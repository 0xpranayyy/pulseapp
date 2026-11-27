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
    private var theme: Palette.Theme { Palette.Tabs.activity }
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ActivityViewModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FieldHeader(
                    title: "Activity",
                    subtitle: environment.session.address == nil
                        ? nil : "Trades, orders and transfers",
                    ink: theme.onField
                )

                if environment.session.address == nil {
                    VStack {
                        StateView(
                            icon: "clock.arrow.circlepath",
                            title: "No wallet connected",
                            message: "Connect a wallet in Profile to see your trades and orders.",
                            ink: theme.onField
                        )
                        .padding(.top, Layout.Space.xxl)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let model {
                    content(model)
                } else {
                    ProgressView()
                        .tint(theme.onField)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(ColourField(colour: theme.screen))
            .toolbar(.hidden, for: .navigationBar)
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
                FieldScroll {
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
                        ActivityRow(item: item, theme: theme)
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
                        OpenOrderRow(order: order, theme: theme) {
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
    let theme: Palette.Theme

    private var tint: Color {
        switch item.type {
        case .trade: item.orderSide == .buy ? Palette.yes : Palette.no
        case .redeem, .reward: Palette.yes
        default: Palette.Card.inkSecondary
        }
    }

    private var icon: String {
        switch item.type {
        case .trade: item.orderSide == .buy ? "arrow.down.left" : "arrow.up.right"
        case .split: "arrow.triangle.branch"
        case .merge: "arrow.triangle.merge"
        case .redeem: "checkmark.seal.fill"
        case .reward: "gift.fill"
        case .conversion: "arrow.2.squarepath"
        case .unknown: "circle"
        }
    }

    private var actionText: String {
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "Market")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Palette.Card.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text(actionText)
                        .foregroundStyle(tint)
                    if item.type == .trade, item.price > 0 {
                        Text("· \(Format.shares(item.size)) @ \(Format.cents(item.price))")
                            .foregroundStyle(Palette.Card.inkSecondary)
                    }
                }
                .font(Typography.caption)
                .lineLimit(1)
            }

            Spacer(minLength: Layout.Space.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.currency(item.usdcSize))
                    .font(Typography.currency)
                    .foregroundStyle(Palette.Card.ink)
                Text(Format.relative(item.date))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.Card.inkTertiary)
            }
            .fixedSize()
        }
        .padding(Layout.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                .fill(Palette.Card.fill)
                // Shadow on the opaque shape, not the composed view: shadowing
                // a subtree forces an offscreen pass to resolve its alpha.
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
        .accessibilityElement(children: .combine)
    }
}

struct OpenOrderRow: View {
    let order: OpenOrder
    let theme: Palette.Theme
    let onCancel: () -> Void

    @State private var confirmingCancel = false

    private var sideTint: Color { order.side == .buy ? Palette.yes : Palette.no }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(spacing: Layout.Space.s) {
                Text(order.side == .buy ? "Buy" : "Sell")
                    .font(Typography.captionMedium)
                    .foregroundStyle(sideTint)
                    .padding(.horizontal, Layout.Space.m)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(sideTint.opacity(0.14)))

                if let outcome = order.outcome {
                    Text(outcome)
                        .font(Typography.subheadlineMedium)
                        .foregroundStyle(Palette.Card.ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Destructive, so it is a deliberate target rather than a
                // small word that sits next to the numbers.
                Button { confirmingCancel = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.danger)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Palette.danger.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Cancel order")
            }

            HStack(spacing: Layout.Space.l) {
                detail("Price", Format.cents(order.price))
                detail("Size", Format.shares(order.originalSize))
                detail("Filled", Format.shares(order.sizeMatched ?? 0))
                Spacer(minLength: 0)
                detail("Remaining", Format.shares(order.remainingSize))
            }

            if order.fillFraction > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.Card.separator)
                            Capsule()
                                .fill(Palette.yes)
                                .frame(width: max(3, geometry.size.width * order.fillFraction))
                        }
                    }
                    .frame(height: 6)

                    Text("\(Format.probability(order.fillFraction)) filled")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.Card.inkSecondary)
                }
            }
        }
        .padding(Layout.Space.l)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous)
                .fill(Palette.Card.fill)
                // Shadow on the opaque shape, not the composed view: shadowing
                // a subtree forces an offscreen pass to resolve its alpha.
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .confirmationDialog(
            "Cancel this order?",
            isPresented: $confirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Cancel order", role: .destructive, action: onCancel)
            Button("Keep order", role: .cancel) {}
        } message: {
            Text(order.fillFraction > 0
                 ? "The \(Format.shares(order.remainingSize)) unfilled shares are removed from the book. Shares already filled stay in your portfolio."
                 : "This order is removed from the book. Nothing has filled yet.")
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(Palette.Card.inkTertiary)
            Text(value)
                .font(Typography.tabularMedium)
                .foregroundStyle(Palette.Card.ink)
        }
    }
}
