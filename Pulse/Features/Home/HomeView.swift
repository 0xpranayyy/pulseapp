import SwiftUI
import Observation
import PulseCore

@MainActor
@Observable
final class HomeViewModel {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var trending: [Event] = []
    private(set) var featured: [Event] = []
    private(set) var closingSoon: [Event] = []
    private(set) var watchlistEvents: [Event] = []

    private let gamma: GammaService
    private var loadTask: Task<Void, Never>?

    init(gamma: GammaService) {
        self.gamma = gamma
    }

    /// Loads the four feed sections concurrently. A section that fails leaves
    /// the others intact — one slow category should not blank the home screen.
    func load(watchlistIds: Set<String>, force: Bool = false) async {
        if case .loaded = state, !force { return }
        loadTask?.cancel()

        state = trending.isEmpty ? .loading : state

        let task = Task {
            // Three independent fetches in flight at once. Child tasks rather
            // than `async let` so each result is read explicitly and a single
            // slow section cannot hold the others back.
            let trendingTask = Task { try? await gamma.events(limit: 20, sort: .volume24hr) }
            let featuredTask = Task { try? await gamma.events(limit: 8, sort: .liquidity) }
            let closingTask = Task { try? await gamma.events(limit: 10, sort: .endDate) }

            let t = await trendingTask.value
            let f = await featuredTask.value
            let c = await closingTask.value

            guard !Task.isCancelled else { return }

            if let t { trending = t }
            if let f { featured = f }
            if let c {
                // Ending soon is only interesting while it is still open.
                closingSoon = c.filter { event in
                    guard let end = event.resolvedEndDate else { return false }
                    return end > Date()
                }
            }

            if trending.isEmpty && featured.isEmpty {
                state = .failed("Couldn't load markets. Pull to refresh.")
            } else {
                state = .loaded
            }

            await loadWatchlist(ids: watchlistIds)
        }
        loadTask = task
        await task.value
    }

    func loadWatchlist(ids: Set<String>) async {
        guard !ids.isEmpty else {
            watchlistEvents = []
            return
        }
        // Prefer events already in hand to avoid refetching.
        let cached = (trending + featured + closingSoon).filter { ids.contains($0.id) }
        var byId = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let missing = ids.subtracting(byId.keys)
        if !missing.isEmpty {
            await withTaskGroup(of: Event?.self) { group in
                for id in missing.prefix(20) {
                    group.addTask { [gamma] in try? await gamma.event(id: id) }
                }
                for await event in group {
                    if let event { byId[event.id] = event }
                }
            }
        }
        watchlistEvents = ids.compactMap { byId[$0] }
    }
}

// MARK: - View

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: HomeViewModel?
    @State private var route: MarketRoute?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(ScreenBackground())
            .navigationTitle("Markets")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $route) { route in
                MarketDetailView(
                    event: route.event,
                    initialMarket: route.market,
                    autoOpenOutcome: route.autoOpenOutcome
                )
            }
        }
        .task {
            if model == nil { model = HomeViewModel(gamma: environment.gamma) }
            await model?.load(watchlistIds: environment.watchlist.eventIds)
        }
    }

    @ViewBuilder
    private func content(_ model: HomeViewModel) -> some View {
        switch model.state {
        case .loading where model.trending.isEmpty:
            ScreenScroll {
                ForEach(0..<5, id: \.self) { _ in EventRowSkeleton() }
            }

        case .failed(let message) where model.trending.isEmpty:
            ScrollView {
                StateView.error(message) {
                    Task { await model.load(watchlistIds: environment.watchlist.eventIds, force: true) }
                }
                .padding(.top, 80)
            }
            .refreshable {
                await model.load(watchlistIds: environment.watchlist.eventIds, force: true)
            }

        default:
            feed(model)
        }
    }

    private func feed(_ model: HomeViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.Space.xl) {
                if !model.featured.isEmpty {
                    section(title: "Featured", subtitle: "Deepest markets right now") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Layout.Space.m) {
                                ForEach(model.featured) { event in
                                    Button { open(event) } label: {
                                        FeaturedEventCard(event: event)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Layout.gutter)
                        }
                        .scrollClipDisabled()
                    }
                }

                if !model.watchlistEvents.isEmpty {
                    section(title: "Watchlist") {
                        rows(model.watchlistEvents)
                    }
                }

                if !model.trending.isEmpty {
                    section(title: "Trending", subtitle: "Most traded in the last 24 hours") {
                        rows(model.trending)
                    }
                }

                if !model.closingSoon.isEmpty {
                    section(title: "Closing soon") {
                        rows(model.closingSoon)
                    }
                }

                RiskNotice(compact: true)
                    .padding(.horizontal, Layout.gutter)
            }
            .padding(.vertical, Layout.Space.m)
        }
        .refreshable {
            await model.load(watchlistIds: environment.watchlist.eventIds, force: true)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            SectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, Layout.gutter)
            content()
        }
    }

    private func rows(_ events: [Event]) -> some View {
        VStack(spacing: Layout.Space.m) {
            ForEach(events) { event in
                Button { open(event) } label: {
                    EventRow(event: event) { market, isYes in
                        route = MarketRoute(event: event, market: market, autoOpenOutcome: isYes)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        environment.watchlist.toggle(event.id)
                    } label: {
                        Label(
                            environment.watchlist.contains(event.id)
                                ? "Remove from watchlist" : "Add to watchlist",
                            systemImage: environment.watchlist.contains(event.id)
                                ? "star.slash" : "star"
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Layout.gutter)
    }

    private func open(_ event: Event) {
        route = MarketRoute(event: event, market: event.primaryMarket)
    }
}

/// Navigation payload for a market screen.
struct MarketRoute: Hashable, Identifiable {
    let event: Event
    let market: Market?
    /// Set only when the user tapped a specific outcome, which opens the trade
    /// sheet on arrival. `nil` means they opened the market itself.
    var autoOpenOutcome: Bool?

    var id: String { "\(event.id)-\(market?.id ?? "")-\(autoOpenOutcome.map(String.init) ?? "none")" }
}
