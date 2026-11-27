import SwiftUI
import Observation
import PulseCore

@MainActor
@Observable
final class ExploreViewModel {
    /// Categories shown as chips. Slugs match Gamma's `tag_slug`.
    struct Category: Identifiable, Hashable {
        let id: String
        let title: String
        let icon: String
        /// `nil` means "everything".
        let slug: String?

        static let all: [Category] = [
            Category(id: "all", title: "All", icon: "square.grid.2x2", slug: nil),
            Category(id: "politics", title: "Politics", icon: "building.columns", slug: "politics"),
            Category(id: "sports", title: "Sports", icon: "sportscourt", slug: "sports"),
            Category(id: "crypto", title: "Crypto", icon: "bitcoinsign.circle", slug: "crypto"),
            Category(id: "economy", title: "Economy", icon: "chart.line.uptrend.xyaxis", slug: "economy"),
            Category(id: "tech", title: "Tech", icon: "cpu", slug: "tech"),
            Category(id: "culture", title: "Culture", icon: "theatermasks", slug: "pop-culture"),
            Category(id: "science", title: "Science", icon: "atom", slug: "science"),
            Category(id: "world", title: "World", icon: "globe", slug: "world")
        ]
    }

    private(set) var events: [Event] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasMore = true

    var query: String = ""
    var category: Category = Category.all[0]
    var sort: GammaService.Sort = .volume24hr

    private let gamma: GammaService
    private var offset = 0
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    private let pageSize = 20

    init(gamma: GammaService) {
        self.gamma = gamma
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Debounced search. Cancels the in-flight request on every keystroke so
    /// a fast typist issues one request, not ten.
    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    func reload() async {
        loadTask?.cancel()
        offset = 0
        hasMore = true
        errorMessage = nil
        isLoading = true

        let task = Task { await fetch(replacing: true) }
        loadTask = task
        await task.value
    }

    func loadMoreIfNeeded(currentItem: Event) async {
        guard !isLoadingMore, hasMore, !isSearching else { return }
        // Start fetching three rows from the end so the next page is usually
        // already there by the time the user reaches it.
        let threshold = max(0, events.count - 3)
        guard let index = events.firstIndex(where: { $0.id == currentItem.id }),
              index >= threshold else { return }

        isLoadingMore = true
        await fetch(replacing: false)
    }

    private func fetch(replacing: Bool) async {
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let page: [Event]
            if isSearching {
                page = try await gamma.search(query, limit: pageSize)
                hasMore = false
            } else {
                page = try await gamma.events(
                    limit: pageSize,
                    offset: offset,
                    sort: sort,
                    tagSlug: category.slug
                )
                hasMore = page.count == pageSize
                offset += page.count
            }

            guard !Task.isCancelled else { return }

            if replacing {
                events = page
            } else {
                // Guard against duplicates when a page boundary shifts under us.
                let existing = Set(events.map(\.id))
                events.append(contentsOf: page.filter { !existing.contains($0.id) })
            }
            errorMessage = events.isEmpty && isSearching ? nil : errorMessage
        } catch let error as APIError {
            guard !Task.isCancelled, error != .cancelled else { return }
            if events.isEmpty { errorMessage = error.userMessage }
        } catch {
            if events.isEmpty { errorMessage = "Couldn't load markets." }
        }
    }
}

// MARK: - View

struct ExploreView: View {
    private var theme: Palette.Theme { Palette.Tabs.explore }
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ExploreViewModel?
    @State private var route: MarketRoute?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FieldHeader(title: "Explore", ink: theme.onField)

                if let model {
                    content(model)
                } else {
                    ProgressView()
                        .tint(theme.onField)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(ColourField())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $route) { route in
                MarketDetailView(
                    event: route.event,
                    initialMarket: route.market,
                    autoOpenOutcome: route.autoOpenOutcome
                )
            }
        }
        .task {
            if model == nil {
                model = ExploreViewModel(gamma: environment.gamma)
                await model?.reload()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ExploreViewModel) -> some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            filters(model)

            if model.isLoading && model.events.isEmpty {
                FieldScroll {
                    ForEach(0..<6, id: \.self) { _ in EventRowSkeleton() }
                }
            } else if let error = model.errorMessage, model.events.isEmpty {
                ScrollView {
                    StateView.error(error) { Task { await model.reload() } }
                        .padding(.top, 60)
                }
            } else if model.events.isEmpty && model.isSearching {
                ScrollView {
                    StateView.noResults(query: model.query).padding(.top, 60)
                }
            } else if model.events.isEmpty {
                ScrollView {
                    StateView(
                        icon: "tray",
                        title: "Nothing here yet",
                        message: "No open markets in this category right now."
                    )
                    .padding(.top, 60)
                }
            } else {
                list(model)
            }
        }
        .searchable(
            text: $model.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search markets"
        )
        .onChange(of: model.query) { _, _ in model.queryChanged() }
    }

    private func filters(_ model: ExploreViewModel) -> some View {
        VStack(spacing: Layout.Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Space.s) {
                    ForEach(ExploreViewModel.Category.all) { category in
                        FilterChip(
                            title: category.title,
                            systemImage: category.icon,
                            isSelected: model.category == category
                        ) {
                            guard model.category != category else { return }
                            model.category = category
                            Haptics.selection(enabled: environment.settings.hapticsEnabled)
                            Task { await model.reload() }
                        }
                    }
                }
                .padding(.horizontal, Layout.gutter)
            }

            if !model.isSearching {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Layout.Space.s) {
                        ForEach(GammaService.Sort.allCases, id: \.self) { sort in
                            FilterChip(
                                title: sort.displayName,
                                isSelected: model.sort == sort,
                                tint: theme.onField.opacity(0.68)
                            ) {
                                guard model.sort != sort else { return }
                                model.sort = sort
                                Task { await model.reload() }
                            }
                        }
                    }
                    .padding(.horizontal, Layout.gutter)
                }
            }
        }
        .padding(.vertical, Layout.Space.s)
    }

    private func list(_ model: ExploreViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: Layout.Space.m) {
                ForEach(model.events) { event in
                    Button {
                        route = MarketRoute(event: event, market: event.primaryMarket)
                    } label: {
                        EventRow(event: event) { market, isYes in
                            route = MarketRoute(event: event, market: market, autoOpenOutcome: isYes)
                        }
                    }
                    .buttonStyle(.plain)
                    .task { await model.loadMoreIfNeeded(currentItem: event) }
                }

                if model.isLoadingMore {
                    ProgressView().padding(.vertical, Layout.Space.l)
                }
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, Layout.Space.xl)
        }
        .refreshable { await model.reload() }
    }
}
