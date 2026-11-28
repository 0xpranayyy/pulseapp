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
                        ? nil : nil,
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
            .background(ColourField())
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
                SkeletonBlock(height: 190, cornerRadius: Layout.Radius.large, ink: ink)
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(height: 96, cornerRadius: Layout.Radius.large, ink: ink)
                }
            }
        } else if let error = model.errorMessage, model.portfolio.positions.isEmpty {
            ScrollView {
                StateView.error(error, ink: ink) { Task { await model.load(force: true) } }
                    .padding(.top, Layout.Space.xl)
            }
            .refreshable { await model.load(force: true) }
        } else {
            ScrollView {
                LazyVStack(spacing: Layout.Space.l) {
                    summaryCard(model.portfolio)

                    if !model.portfolio.positions.isEmpty {
                        allocationStrip(model.portfolio)
                    }

                    filters(model)

                    if model.portfolio.positions.isEmpty {
                        StateView(
                            icon: "tray",
                            title: emptyTitle(for: model.statusFilter),
                            message: "Positions you take will appear here.",
                            ink: ink,
                            pip: .zzz
                        )
                        .padding(.top, Layout.Space.l)
                    } else {
                        ForEach(model.portfolio.byValue) { position in
                            PositionRow(position: position, total: model.portfolio.positionsValue)
                        }
                    }
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.top, Layout.Space.xs)
                .padding(.bottom, Layout.Size.tabBarClearance)
            }
            .refreshable { await model.load(force: true) }
        }
    }

    private var ink: Color { theme.onField }

    private func emptyTitle(for status: PositionStatus) -> String {
        switch status {
        case .open: "No open positions"
        case .redeemable: "Nothing to redeem"
        case .redeemableLost: "No losing positions"
        case .mergeable: "Nothing to merge"
        case .closed: "No closed positions"
        }
    }

    /// The headline figure.
    ///
    /// "If all correct" is labelled as a ceiling rather than shown bare:
    /// it is the payout only if every open position wins, and presenting
    /// that as a portfolio figure would be the most misleading number here.
    private func summaryCard(_ portfolio: Portfolio) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.l) {
            HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("POSITIONS VALUE")
                    .font(Typography.overline)
                    .tracking(0.9)
                    .foregroundStyle(Brand.inkTertiary)

                Text(Format.currency(portfolio.totalValue))
                    .font(Typography.currencyLarge)
                    .foregroundStyle(ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let totalReturn = portfolio.totalReturn {
                    HStack(spacing: 5) {
                        Image(systemName: portfolio.totalPnl >= 0
                              ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .black))
                        Text(Format.currency(portfolio.totalPnl, showSign: true))
                        Text("·")
                        Text(Format.percentChange(totalReturn))
                    }
                    .font(Typography.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(portfolio.totalPnl >= 0 ? Brand.yes : Brand.no))
                    .padding(.top, 2)
                }
            }
                Spacer(minLength: Layout.Space.s)
                // Pip reacts to the portfolio, not to any one market: pleased
                // when it is up, thoughtful when it is down. Never a cheer for
                // a side.
                Pip(
                    pose: portfolio.totalPnl >= 0 ? .yay : .hmm,
                    size: 96,
                    shadow: nil
                )
                .padding(.top, -Layout.Space.s)
            }

            Rectangle().fill(Brand.hairline).frame(height: 2)

            HStack(spacing: Layout.Space.m) {
                StatTile(
                    label: "Unrealised",
                    value: Format.currency(portfolio.unrealizedPnl, showSign: true),
                    ink: ink,
                    tint: portfolio.unrealizedPnl >= 0 ? Palette.yes : Palette.no
                )
                StatTile(
                    label: "Realised",
                    value: Format.currency(portfolio.realizedPnl, showSign: true),
                    ink: ink,
                    tint: portfolio.realizedPnl >= 0 ? Palette.yes : Palette.no
                )
                StatTile(
                    label: "If all correct",
                    value: Format.currency(portfolio.maximumPayout),
                    caption: "ceiling",
                    ink: ink
                )
            }

            if portfolio.redeemableValue > 0 {
                HStack(spacing: Layout.Space.s) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Palette.yes)
                    Text("\(Format.currency(portfolio.redeemableValue)) ready to redeem")
                        .font(Typography.footnote)
                        .foregroundStyle(ink)
                    Spacer()
                }
                .padding(Layout.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                        .fill(Brand.yesTint)
                )
            }
        }
        .padding(Layout.Space.l)
        .fieldPanel(theme, radius: Layout.Radius.large)
    }

    /// How the money is spread, as one bar.
    ///
    /// Concentration is the thing worth seeing at a glance, and a single bar
    /// shows it faster than a column of percentages. Positions carry no tags,
    /// so the segments take distinct colours in size order rather than
    /// pretending to be categories; a legend names the largest three. Never
    /// green or red, which would read as winning and losing.
    private func allocationStrip(_ portfolio: Portfolio) -> some View {
        let allocations = portfolio.allocations().prefix(8)

        return VStack(alignment: .leading, spacing: Layout.Space.s) {
            HStack {
                Text("ALLOCATION")
                    .font(Typography.overline)
                    .tracking(0.9)
                    .foregroundStyle(Brand.inkTertiary)
                Spacer()
                Text("\(portfolio.openCount) position\(portfolio.openCount == 1 ? "" : "s")")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.inkTertiary)
            }

            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(Array(allocations.enumerated()), id: \.element.position.id) { index, entry in
                        Self.allocationColour(index)
                            .frame(width: max(4, geometry.size.width * entry.share - 3))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)

            VStack(spacing: 6) {
                ForEach(Array(allocations.prefix(3).enumerated()), id: \.element.position.id) { index, entry in
                    HStack(spacing: Layout.Space.s) {
                        Circle().fill(Self.allocationColour(index)).frame(width: 9, height: 9)
                        Text(entry.position.displayTitle)
                            .font(Typography.caption)
                            .foregroundStyle(Brand.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: Layout.Space.s)
                        Text(Format.probability(entry.share))
                            .font(Typography.tabularMedium)
                            .foregroundStyle(ink)
                    }
                }
            }
        }
        .padding(Layout.Space.l)
        .fieldPanel(theme, radius: Layout.Radius.large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Allocation across \(portfolio.openCount) positions")
    }

    /// Category fills, in a fixed order, for allocation segments.
    private static let allocationPalette: [Color] = [
        MarketCategory.politics, .crypto, .sport, .economy, .tech, .culture, .world, .other
    ].map(Brand.fill)

    private static func allocationColour(_ index: Int) -> Color {
        allocationPalette[index % allocationPalette.count]
    }

    private func filters(_ model: PortfolioViewModel) -> some View {
        @Bindable var model = model
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.Space.s) {
                ForEach(PositionStatus.allCases, id: \.self) { status in
                    FilterChip(
                        title: status.displayName,
                        isSelected: model.statusFilter == status,
                        tint: ink,
                        onTint: theme.onControl
                    ) {
                        model.statusFilter = status
                        Haptics.selection(enabled: environment.settings.hapticsEnabled)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

/// One holding.
///
/// A white chunky card, matching the feed. Three numbers earn
/// their place: what it is worth now, what it has made or lost, and what it
/// pays if it wins. Entry price and share count sit underneath for anyone
/// checking the maths.
struct PositionRow: View {
    let position: Position
    /// Total positions value, used for the share-of-portfolio read.
    var total: Double = 0


    private var isYes: Bool { (position.outcomeIndex ?? 0) == 0 }
    private var outcomeTint: Color { isYes ? Palette.yes : Palette.no }
    private var outcomeSurface: Color { isYes ? Palette.yesSurface : Palette.noSurface }
    private var share: Double { total > 0 ? position.currentValue / total : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(alignment: .top, spacing: Layout.Space.m) {
                MarketArt(
                    url: position.icon.flatMap(URL.init(string:)),
                    fallbackText: position.displayTitle,
                    size: 48,
                    cornerRadius: 15
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(position.eventTitle ?? position.title ?? "Position")
                        .font(Typography.headline)
                        .foregroundStyle(Palette.Card.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        if let outcome = position.outcome, !outcome.isEmpty {
                            Text(outcome)
                                .font(Typography.captionMedium)
                                .foregroundStyle(outcomeTint)
                                .padding(.horizontal, Layout.Space.s)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(outcomeSurface))
                        }
                        if let leg = position.groupItemTitle, !leg.isEmpty {
                            Text(leg)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.Card.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: Layout.Space.s)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.currency(position.currentValue))
                        .font(Typography.currency)
                        .foregroundStyle(Palette.Card.ink)
                        .contentTransition(.numericText())
                    Text(Format.currency(position.unrealizedPnl, showSign: true))
                        .font(Typography.captionMedium)
                        .foregroundStyle(position.unrealizedPnl >= 0 ? Palette.yes : Palette.no)
                }
                .fixedSize()
            }

            // Entry versus now, drawn as one bar: the fill is the current
            // price and the notch marks what was paid, so a position's
            // direction reads without comparing two numbers.
            priceTrack

            HStack(spacing: Layout.Space.l) {
                detail("Shares", Format.shares(position.currentSize))
                detail("Avg", Format.cents(position.avgPrice))
                detail("Now", Format.cents(position.currentPrice))
                Spacer(minLength: 0)
                detail("If won", Format.currency(position.payoutIfWon), tint: Palette.yes)
            }

            if position.redeemable || share > 0.25 {
                HStack(spacing: Layout.Space.s) {
                    if position.redeemable {
                        Label("Redeemable", systemImage: "checkmark.seal.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.yes)
                    }
                    if share > 0.25 {
                        Label(
                            "\(Format.probability(share)) of portfolio",
                            systemImage: "chart.pie.fill"
                        )
                        .font(Typography.caption)
                        .foregroundStyle(Palette.caution)
                    }
                    Spacer()
                }
            }
        }
        .padding(Layout.Space.l)
        .chunkyCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var priceTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let now = min(1, max(0, position.currentPrice))
            let entry = min(1, max(0, position.avgPrice))

            ZStack(alignment: .leading) {
                Capsule().fill(Brand.cardSunken)
                Capsule()
                    .fill(outcomeTint)
                    .frame(width: max(4, width * now))
                // The entry marker: what was paid, as a navy pin on the track.
                Capsule()
                    .fill(Brand.ink)
                    .frame(width: 4, height: 18)
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 1))
                    .offset(x: max(0, min(width - 4, width * entry - 2)))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    private func detail(
        _ label: String,
        _ value: String,
        tint: Color = Palette.Card.inkSecondary
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(Palette.Card.inkTertiary)
            Text(value)
                .font(Typography.tabularMedium)
                .foregroundStyle(tint)
        }
    }

    private var accessibilityDescription: String {
        let title = position.eventTitle ?? position.title ?? "Position"
        let pnl = position.unrealizedPnl >= 0 ? "up" : "down"
        return """
            \(title), \(position.outcome ?? ""), worth \
            \(Format.currency(position.currentValue)), \(pnl) \
            \(Format.currency(abs(position.unrealizedPnl)))
            """
    }
}
