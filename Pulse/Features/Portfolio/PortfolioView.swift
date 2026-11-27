import SwiftUI
import Observation
import PulseCore

@MainActor
@Observable
final class PortfolioViewModel {
    private(set) var portfolio: Portfolio = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoadedOnce = false

    var statusFilter: PositionStatus = .open {
        didSet {
            guard statusFilter != oldValue else { return }
            Task { await load(force: true) }
        }
    }

    private let data: DataService
    private let session: SessionStore

    init(data: DataService, session: SessionStore) {
        self.data = data
        self.session = session
    }

    func load(force: Bool = false) async {
        guard let address = session.address else {
            portfolio = .empty
            hasLoadedOnce = true
            return
        }
        guard !isLoading, force || !hasLoadedOnce else { return }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            // Walk the cursor to a sane cap: a portfolio view does not need
            // thousands of rows, and unbounded paging on a wallet with a long
            // history would stall the screen.
            var collected: [Position] = []
            var cursor: String?
            for _ in 0..<5 {
                let page = try await data.positions(
                    user: address, status: statusFilter, limit: 100, cursor: cursor
                )
                collected.append(contentsOf: page.items)
                guard page.hasMore, let next = page.nextCursor else { break }
                cursor = next
            }

            let value = try? await data.portfolioValue(user: address)
            portfolio = Portfolio(
                positions: collected,
                reportedValue: value,
                availableBalance: session.availableBalance
            )
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "Couldn't load your portfolio."
        }
    }
}

struct PortfolioView: View {
    private var theme: Palette.Theme { Palette.Tabs.portfolio }
    @Environment(AppEnvironment.self) private var environment
    @State private var model: PortfolioViewModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FieldHeader(
                    title: "Portfolio",
                    subtitle: environment.session.address == nil
                        ? nil : "Your positions and P&L",
                    ink: theme.onField
                )

                if environment.session.address == nil {
                    signedOut
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
                model = PortfolioViewModel(data: environment.data, session: environment.session)
            }
            await model?.load()
        }
    }

    private var signedOut: some View {
        VStack {
            StateView(
                icon: "chart.pie",
                title: "No wallet connected",
                message: "Browse markets without one. Connect a wallet to track positions and P&L.",
                ink: theme.onField
            )
            .padding(.top, Layout.Space.xxl)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(_ model: PortfolioViewModel) -> some View {
        if model.isLoading && !model.hasLoadedOnce {
            FieldScroll {
                SkeletonBlock(height: 140, cornerRadius: Layout.Radius.large)
                ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 72, cornerRadius: Layout.Radius.medium) }
            }
        } else if let error = model.errorMessage, model.portfolio.positions.isEmpty {
            ScrollView {
                StateView.error(error) { Task { await model.load(force: true) } }
                    .padding(.top, 60)
            }
            .refreshable { await model.load(force: true) }
        } else {
            ScrollView {
                VStack(spacing: Layout.Space.l) {
                    summaryCard(model.portfolio)
                    filters(model)

                    if model.portfolio.positions.isEmpty {
                        StateView(
                            icon: "tray",
                            title: emptyTitle(for: model.statusFilter),
                            message: "Positions you take will appear here."
                        )
                        .padding(.top, Layout.Space.xl)
                    } else {
                        positionsList(model.portfolio)
                    }
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.vertical, Layout.Space.m)
                .padding(.bottom, Layout.Space.xl)
            }
            .refreshable { await model.load(force: true) }
        }
    }

    private func emptyTitle(for status: PositionStatus) -> String {
        switch status {
        case .open: "No open positions"
        case .redeemable: "Nothing to redeem"
        case .redeemableLost: "No losing positions"
        case .mergeable: "Nothing to merge"
        case .closed: "No closed positions"
        }
    }

    /// Portfolio header.
    ///
    /// Shows value, P&L and maximum payout. Maximum payout is labelled "if all
    /// correct" rather than presented as an expectation: it is a ceiling, and
    /// showing it unqualified would be the single most misleading number here.
    private func summaryCard(_ portfolio: Portfolio) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("POSITIONS VALUE")
                    .font(Typography.overline)
                    .tracking(0.6)
                    .foregroundStyle(theme.onField.opacity(0.55))
                Text(Format.currency(portfolio.totalValue))
                    .font(Typography.currencyLarge)
                    .foregroundStyle(theme.onField)
                    .contentTransition(.numericText())

                if let totalReturn = portfolio.totalReturn {
                    HStack(spacing: Layout.Space.xs) {
                        Image(systemName: portfolio.totalPnl >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(Format.currency(portfolio.totalPnl, showSign: true))
                        Text("(\(Format.percentChange(totalReturn)))")
                    }
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(portfolio.totalPnl >= 0 ? Palette.up : Palette.down)
                }
            }

            Divider().background(theme.onField.opacity(0.12))

            HStack(spacing: Layout.Space.l) {
                StatTile(
                    label: "Unrealised",
                    value: Format.currency(portfolio.unrealizedPnl, showSign: true),
                    tint: portfolio.unrealizedPnl >= 0 ? Palette.up : Palette.down
                )
                StatTile(
                    label: "Realised",
                    value: Format.currency(portfolio.realizedPnl, showSign: true),
                    tint: portfolio.realizedPnl >= 0 ? Palette.up : Palette.down
                )
                StatTile(
                    label: "If all correct",
                    value: Format.currency(portfolio.maximumPayout),
                    caption: "maximum"
                )
            }

            if portfolio.redeemableValue > 0 {
                HStack(spacing: Layout.Space.s) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.up)
                    Text("\(Format.currency(portfolio.redeemableValue)) ready to redeem")
                        .font(Typography.footnote)
                        .foregroundStyle(theme.onField)
                    Spacer()
                }
                .padding(Layout.Space.s)
                .background(
                    RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                        .fill(Palette.yesSurface)
                )
            }
        }
        .padding(Layout.Space.l)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous)
                .fill(Palette.themes[0].field)
        )
    }

    private func filters(_ model: PortfolioViewModel) -> some View {
        @Bindable var model = model
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.Space.s) {
                ForEach(PositionStatus.allCases, id: \.self) { status in
                    FilterChip(
                        title: status.displayName,
                        isSelected: model.statusFilter == status
                    ) {
                        model.statusFilter = status
                    }
                }
            }
        }
    }

    private func positionsList(_ portfolio: Portfolio) -> some View {
        VStack(spacing: Layout.Space.s) {
            ForEach(portfolio.byValue) { position in
                PositionRow(position: position)
            }
        }
    }
}

/// One holding.
struct PositionRow: View {
    let position: Position

    private var theme: Palette.Theme {
        Palette.theme(for: position.eventId ?? position.conditionId)
    }

    private var outcomeTint: Color {
        (position.outcomeIndex ?? 0) == 0 ? Palette.yes : Palette.no
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.s) {
            HStack(alignment: .top, spacing: Layout.Space.m) {
                MarketArt(
                    url: position.icon.flatMap(URL.init(string:)),
                    theme: theme,
                    fallbackText: position.displayTitle,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(position.eventTitle ?? position.title ?? "Position")
                        .font(Typography.subheadlineMedium)
                        .foregroundStyle(theme.onField)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: Layout.Space.xs) {
                        if let outcome = position.outcome, !outcome.isEmpty {
                            Text(outcome)
                                .font(Typography.caption)
                                .foregroundStyle(outcomeTint)
                        }
                        if let leg = position.groupItemTitle, !leg.isEmpty {
                            Text("· \(leg)")
                                .font(Typography.caption)
                                .foregroundStyle(theme.onField.opacity(0.68))
                        }
                    }
                }

                Spacer(minLength: Layout.Space.s)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.currency(position.currentValue))
                        .font(Typography.currency)
                        .foregroundStyle(theme.onField)
                    Text(Format.currency(position.unrealizedPnl, showSign: true))
                        .font(Typography.caption)
                        .foregroundStyle(position.unrealizedPnl >= 0 ? Palette.up : Palette.down)
                }
            }

            HStack(spacing: Layout.Space.l) {
                detail("Shares", Format.shares(position.currentSize))
                detail("Avg", Format.cents(position.avgPrice))
                detail("Now", Format.cents(position.currentPrice))
                Spacer()
                if position.redeemable {
                    Text("Redeemable")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.up)
                }
            }
        }
        .padding(Layout.Space.m)
        .fieldPanel(theme, radius: Layout.Radius.medium)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(theme.onField.opacity(0.5))
            Text(value)
                .font(Typography.caption.monospacedDigit())
                .foregroundStyle(theme.onField.opacity(0.68))
        }
    }
}
