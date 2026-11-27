import SwiftUI
import Observation
import PulseCore

@MainActor
@Observable
final class ActivityViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case history = "History"
        case openOrders = "Open orders"
        var id: String { rawValue }
    }

    private(set) var items: [ActivityItem] = []
    private(set) var openOrders: [OpenOrder] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasMore = true

    var scope: Scope = .history {
        didSet {
            guard scope != oldValue else { return }
            Task { await load(force: true) }
        }
    }

    private let data: DataService
    private let clob: ClobService
    private let session: SessionStore
    private var cursor: String?

    init(data: DataService, clob: ClobService, session: SessionStore) {
        self.data = data
        self.clob = clob
        self.session = session
    }

    func load(force: Bool = false) async {
        guard let address = session.address else { return }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = true
        defer { isLoading = false }

        do {
            switch scope {
            case .history:
                let page = try await data.activity(user: address, limit: 50)
                items = page.items
                cursor = page.nextCursor
                hasMore = page.hasMore
            case .openOrders:
                openOrders = try await clob.openOrders()
            }
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "Couldn't load your activity."
        }
    }

    func loadMoreIfNeeded(currentItem: ActivityItem) async {
        guard scope == .history, hasMore, !isLoadingMore,
              let address = session.address,
              let cursor,
              items.suffix(4).contains(where: { $0.id == currentItem.id })
        else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        if let page = try? await data.activity(user: address, limit: 50, cursor: cursor) {
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            self.cursor = page.nextCursor
            hasMore = page.hasMore
        } else {
            hasMore = false
        }
    }

    func cancel(order: OpenOrder) async {
        do {
            try await clob.cancel(orderId: order.id)
            openOrders.removeAll { $0.id == order.id }
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "Couldn't cancel that order."
        }
    }
}

struct ActivityView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ActivityViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if environment.session.address == nil {
                    StateView(
                        icon: "clock.arrow.circlepath",
                        title: "No wallet connected",
                        message: "Connect a wallet in Profile to see your trades and orders."
                    )
                    .frame(maxHeight: .infinity)
                } else if let model {
                    content(model)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(ScreenBackground())
            .navigationTitle("Activity")
        }
        .task {
            if model == nil {
                model = ActivityViewModel(
                    data: environment.data,
                    clob: environment.clob,
                    session: environment.session
                )
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: ActivityViewModel) -> some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Picker("Scope", selection: $model.scope) {
                ForEach(ActivityViewModel.Scope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, Layout.Space.s)

            if model.isLoading {
                ScreenScroll {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonBlock(height: 64, cornerRadius: Layout.Radius.medium)
                    }
                }
            } else if let error = model.errorMessage {
                ScrollView {
                    StateView.error(error) { Task { await model.load(force: true) } }
                        .padding(.top, 60)
                }
                .refreshable { await model.load(force: true) }
            } else {
                switch model.scope {
                case .history: history(model)
                case .openOrders: orders(model)
                }
            }
        }
    }

    @ViewBuilder
    private func history(_ model: ActivityViewModel) -> some View {
        if model.items.isEmpty {
            ScrollView {
                StateView(
                    icon: "tray",
                    title: "No activity yet",
                    message: "Trades, merges and redemptions will appear here."
                )
                .padding(.top, 60)
            }
            .refreshable { await model.load(force: true) }
        } else {
            ScrollView {
                LazyVStack(spacing: Layout.Space.s) {
                    ForEach(model.items) { item in
                        ActivityRow(item: item)
                            .task { await model.loadMoreIfNeeded(currentItem: item) }
                    }
                    if model.isLoadingMore {
                        ProgressView().padding(.vertical, Layout.Space.l)
                    }
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, Layout.Space.xl)
            }
            .refreshable { await model.load(force: true) }
        }
    }

    @ViewBuilder
    private func orders(_ model: ActivityViewModel) -> some View {
        if model.openOrders.isEmpty {
            ScrollView {
                StateView(
                    icon: "list.bullet.rectangle",
                    title: "No open orders",
                    message: "Limit orders resting on the book will appear here."
                )
                .padding(.top, 60)
            }
            .refreshable { await model.load(force: true) }
        } else {
            ScrollView {
                LazyVStack(spacing: Layout.Space.s) {
                    ForEach(model.openOrders) { order in
                        OpenOrderRow(order: order) {
                            Task { await model.cancel(order: order) }
                        }
                    }
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, Layout.Space.xl)
            }
            .refreshable { await model.load(force: true) }
        }
    }
}

struct ActivityRow: View {
    let item: ActivityItem

    private var tint: Color {
        switch item.type {
        case .trade: item.orderSide == .buy ? Palette.up : Palette.down
        case .redeem, .reward: Palette.up
        default: Palette.inkSecondary
        }
    }

    private var icon: String {
        switch item.type {
        case .trade: item.orderSide == .buy ? "arrow.down.left" : "arrow.up.right"
        case .split: "arrow.triangle.branch"
        case .merge: "arrow.triangle.merge"
        case .redeem: "checkmark.seal"
        case .reward: "gift"
        case .conversion: "arrow.2.squarepath"
        case .unknown: "circle"
        }
    }

    private var title: String {
        switch item.type {
        case .trade:
            let verb = item.orderSide == .buy ? "Bought" : "Sold"
            return item.hasOutcome ? "\(verb) \(item.outcome ?? "")" : verb
        default:
            return item.type.displayName
        }
    }

    var body: some View {
        HStack(spacing: Layout.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Market")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                HStack(spacing: Layout.Space.xs) {
                    Text(title)
                    if item.type == .trade, item.price > 0 {
                        Text("· \(Format.shares(item.size)) @ \(Format.cents(item.price))")
                    }
                    Text("· \(Format.relative(item.date))")
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: Layout.Space.s)

            Text(Format.currency(item.usdcSize))
                .font(Typography.subheadlineMedium.monospacedDigit())
                .foregroundStyle(Palette.ink)
        }
        .padding(Layout.Space.m)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

struct OpenOrderRow: View {
    let order: OpenOrder
    let onCancel: () -> Void

    @State private var confirmingCancel = false

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.s) {
            HStack {
                Text(order.side == .buy ? "Buy" : "Sell")
                    .font(Typography.captionMedium)
                    .foregroundStyle(order.side == .buy ? Palette.up : Palette.down)
                    .padding(.horizontal, Layout.Space.s)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            (order.side == .buy ? Palette.up : Palette.down).opacity(0.12)
                        )
                    )

                if let outcome = order.outcome {
                    Text(outcome)
                        .font(Typography.subheadlineMedium)
                        .foregroundStyle(Palette.ink)
                }

                Spacer()

                Button("Cancel") { confirmingCancel = true }
                    .font(Typography.caption)
                    .foregroundStyle(Palette.danger)
            }

            HStack(spacing: Layout.Space.l) {
                detail("Price", Format.cents(order.price))
                detail("Size", Format.shares(order.originalSize))
                detail("Filled", Format.shares(order.sizeMatched ?? 0))
            }

            if order.fillFraction > 0 {
                ProgressView(value: order.fillFraction)
                    .tint(Palette.up)
            }
        }
        .padding(Layout.Space.m)
        .cardSurface()
        .confirmationDialog(
            "Cancel this order?",
            isPresented: $confirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Cancel order", role: .destructive, action: onCancel)
            Button("Keep order", role: .cancel) {}
        } message: {
            Text("The unfilled part will be removed from the book.")
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
            Text(value)
                .font(Typography.caption.monospacedDigit())
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}
