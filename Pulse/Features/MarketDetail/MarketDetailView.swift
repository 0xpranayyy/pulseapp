import SwiftUI
import Charts
import PulseCore

struct MarketDetailView: View {
    let event: Event
    let initialMarket: Market?
    /// When set, the trade sheet opens straight away on this outcome, so a
    /// Yes/No tap in the feed lands where the user aimed.
    var autoOpenOutcome: Bool?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var model: MarketDetailViewModel?
    @State private var tradeRequest: TradeRequest?
    @State private var showsRules = false

    private var theme: Palette.Theme { Palette.theme(for: event.id) }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ScreenBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $tradeRequest) { request in
            TradeSheet(request: request)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsRules) {
            MarketRulesSheet(event: event, market: model?.selectedMarket)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if model == nil {
                let market = initialMarket ?? event.primaryMarket
                guard let market else { return }
                model = MarketDetailViewModel(
                    event: event,
                    market: market,
                    gamma: environment.gamma,
                    clob: environment.clob,
                    data: environment.data,
                    socket: environment.marketSocket
                )
                await model?.load()

                if let isYes = autoOpenOutcome, let loaded = model {
                    openTrade(loaded, isYes: isYes)
                }
            }
        }
        .onDisappear {
            // Release the socket when leaving: keeping a subscription open per
            // visited market would leak connections across navigation.
            Task { [model] in await model?.stopStreaming() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                environment.watchlist.toggle(event.id)
                Haptics.selection(enabled: environment.settings.hapticsEnabled)
            } label: {
                Image(systemName: environment.watchlist.contains(event.id) ? "star.fill" : "star")
            }
            .accessibilityLabel(
                environment.watchlist.contains(event.id)
                    ? "Remove from watchlist" : "Add to watchlist"
            )
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showsRules = true } label: {
                    Label("Rules & resolution", systemImage: "doc.text")
                }
                if let slug = event.slug,
                   let url = URL(string: "https://polymarket.com/event/\(slug)") {
                    ShareLink(item: url) {
                        Label("Share market", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More options")
        }
    }

    // MARK: Content

    private func content(_ model: MarketDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.Space.xl) {
                header(model)

                if event.isMultiOutcome {
                    outcomePicker(model)
                }

                chartSection(model)
                statsSection(model)
                orderBookSection(model)

                if !model.recentTrades.isEmpty {
                    recentTradesSection(model)
                }

                if !model.holders.isEmpty {
                    holdersSection(model)
                }

                descriptionSection

                if !model.relatedEvents.isEmpty {
                    relatedSection(model)
                }

                RiskNotice()
                    .padding(.horizontal, Layout.gutter)
            }
            .padding(.vertical, Layout.Space.l)
            .padding(.bottom, 120)   // clearance for the trade bar
        }
        .refreshable { await model.refresh() }
        .safeAreaInset(edge: .bottom) { tradeBar(model) }
    }

    /// Full-bleed themed header — the reference images' colour-field motif,
    /// carrying the market's identity.
    private func header(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(alignment: .top, spacing: Layout.Space.m) {
                MarketImage(
                    url: event.imageURL,
                    theme: theme,
                    fallbackText: event.displayTitle,
                    size: 56,
                    cornerRadius: Layout.Radius.small
                )

                VStack(alignment: .leading, spacing: Layout.Space.xs) {
                    Text(event.displayTitle)
                        .font(Typography.title2)
                        .foregroundStyle(theme.onField)
                        .fixedSize(horizontal: false, vertical: true)

                    if event.isMultiOutcome {
                        Text(model.selectedMarket.displayTitle)
                            .font(Typography.subheadlineMedium)
                            .foregroundStyle(theme.onField.opacity(0.75))
                    }
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: Layout.Space.s) {
                Text(Format.probability(model.displayedProbability))
                    .font(Typography.probabilityLarge)
                    .foregroundStyle(theme.onField)
                    .contentTransition(.numericText())

                Text(model.outcomeLabel)
                    .font(Typography.headline)
                    .foregroundStyle(theme.onField.opacity(0.7))

                Spacer()

                LiveIndicator(
                    isLive: !model.isPriceStale,
                    label: model.isPriceStale ? "Delayed" : "Live"
                )
            }

            if let change = model.selectedMarket.dayChange, abs(change) > 0.0001 {
                Text("\(Format.probabilityChange(change)) points today")
                    .font(Typography.footnote)
                    .foregroundStyle(theme.onField.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.Space.l)
        .background(theme.field)
        .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous))
        .padding(.horizontal, Layout.gutter)
    }

    private func outcomePicker(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            SectionHeader(title: "Outcomes")
                .padding(.horizontal, Layout.gutter)

            VStack(spacing: Layout.Space.s) {
                ForEach(
                    (event.markets ?? []).sorted {
                        ($0.yesProbability ?? 0) > ($1.yesProbability ?? 0)
                    },
                    id: \.id
                ) { market in
                    Button {
                        Task { await model.select(market: market) }
                    } label: {
                        HStack(spacing: Layout.Space.m) {
                            Text(market.displayTitle)
                                .font(Typography.subheadlineMedium)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(Format.probability(market.yesProbability))
                                .font(Typography.subheadlineMedium.monospacedDigit())
                                .foregroundStyle(Palette.ink)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.inkTertiary)
                        }
                        .padding(Layout.Space.m)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                                .fill(
                                    market.id == model.selectedMarket.id
                                        ? theme.field
                                        : Palette.surface
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Layout.gutter)
        }
    }

    // MARK: Chart

    private func chartSection(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack {
                SectionHeader(title: "Price history")
                Spacer()
            }
            .padding(.horizontal, Layout.gutter)

            Group {
                if model.isLoadingHistory && model.history.isEmpty {
                    SkeletonBlock(height: 180, cornerRadius: Layout.Radius.medium)
                } else if model.history.count < 2 {
                    Text("Not enough price history yet.")
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .cardSurface()
                } else {
                    PriceChart(points: model.history, tint: theme.onField)
                        .frame(height: 180)
                        .padding(Layout.Space.m)
                        .cardSurface()
                }
            }
            .padding(.horizontal, Layout.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Space.s) {
                    ForEach(PriceHistoryInterval.allCases, id: \.self) { interval in
                        FilterChip(
                            title: interval.displayName,
                            isSelected: model.interval == interval
                        ) {
                            model.interval = interval
                            Haptics.selection(enabled: environment.settings.hapticsEnabled)
                        }
                    }
                }
                .padding(.horizontal, Layout.gutter)
            }
        }
    }

    // MARK: Stats

    private func statsSection(_ model: MarketDetailViewModel) -> some View {
        let market = model.selectedMarket
        return VStack(alignment: .leading, spacing: Layout.Space.m) {
            SectionHeader(title: "Market")
                .padding(.horizontal, Layout.gutter)

            VStack(spacing: Layout.Space.m) {
                HStack(spacing: Layout.Space.l) {
                    StatTile(label: "Volume", value: Format.compactCurrency(market.volumeTotal))
                    StatTile(label: "24h volume", value: Format.compactCurrency(market.volume24hr?.value))
                    StatTile(label: "Liquidity", value: Format.compactCurrency(market.liquidityTotal))
                }
                Divider().background(Palette.separator)
                HStack(spacing: Layout.Space.l) {
                    StatTile(
                        label: "Spread",
                        value: model.book.spread.map { Format.cents($0) } ?? "—"
                    )
                    StatTile(
                        label: "Closes",
                        value: Format.timeRemaining(until: market.resolvedEndDate),
                        caption: Format.date(market.resolvedEndDate)
                    )
                    StatTile(
                        label: "Min order",
                        value: "\(Format.shares(market.minimumOrderSize)) sh"
                    )
                }
            }
            .padding(Layout.Space.l)
            .cardSurface(radius: Layout.Radius.large)
            .padding(.horizontal, Layout.gutter)
        }
    }

    // MARK: Order book

    private func orderBookSection(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            SectionHeader(
                title: "Order book",
                subtitle: "\(model.outcomeLabel) · top of book"
            )
            .padding(.horizontal, Layout.gutter)

            OrderBookView(book: model.book, isLoading: model.isLoadingBook)
                .padding(.horizontal, Layout.gutter)
        }
    }

    private func recentTradesSection(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            SectionHeader(title: "Recent trades", subtitle: "Across all outcomes")
                .padding(.horizontal, Layout.gutter)

            VStack(spacing: Layout.Space.s) {
                ForEach(model.recentTrades.prefix(8)) { trade in
                    HStack(spacing: Layout.Space.s) {
                        Text(trade.side == .buy ? "Buy" : "Sell")
                            .font(Typography.caption)
                            .foregroundStyle(trade.side == .buy ? Palette.up : Palette.down)
                            .frame(width: 32, alignment: .leading)

                        if let outcome = trade.outcome, !outcome.isEmpty {
                            Text(outcome)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                        }

                        Spacer(minLength: Layout.Space.xs)

                        Text("\(Format.shares(trade.size)) @ \(Format.cents(trade.price))")
                            .font(Typography.tabular)
                            .foregroundStyle(Palette.inkSecondary)

                        Text(Format.relative(trade.date))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Layout.Space.l)
            .cardSurface(radius: Layout.Radius.large)
            .padding(.horizontal, Layout.gutter)
        }
    }

    private func relatedSection(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            SectionHeader(title: "Related markets")
                .padding(.horizontal, Layout.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Space.m) {
                    ForEach(model.relatedEvents) { related in
                        NavigationLink {
                            MarketDetailView(
                                event: related,
                                initialMarket: related.primaryMarket
                            )
                        } label: {
                            FeaturedEventCard(event: related)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Layout.gutter)
            }
            .scrollClipDisabled()
        }
    }

    private func holdersSection(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            SectionHeader(title: "Top holders", subtitle: model.outcomeLabel)
                .padding(.horizontal, Layout.gutter)

            VStack(spacing: Layout.Space.s) {
                ForEach(model.holders) { holder in
                    HStack {
                        Text(holder.displayName)
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Format.shares(holder.amount)) sh")
                            .font(Typography.tabular)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
            .padding(Layout.Space.l)
            .cardSurface(radius: Layout.Radius.large)
            .padding(.horizontal, Layout.gutter)
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let description = event.description ?? initialMarket?.description,
           !description.isEmpty {
            VStack(alignment: .leading, spacing: Layout.Space.s) {
                SectionHeader(title: "About")
                Text(description)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Rules & resolution") { showsRules = true }
                    .buttonStyle(.pill(.quiet, tint: Palette.ink))
                    .padding(.top, Layout.Space.xs)
            }
            .padding(.horizontal, Layout.gutter)
        }
    }

    // MARK: Trade bar

    private func tradeBar(_ model: MarketDetailViewModel) -> some View {
        VStack(spacing: Layout.Space.s) {
            if !model.canTrade {
                Text(
                    model.selectedMarket.closed == true
                        ? "This market has closed."
                        : "This market isn't accepting orders."
                )
                .font(Typography.footnote)
                .foregroundStyle(Palette.inkSecondary)
            } else {
                HStack(spacing: Layout.Space.s) {
                    tradeButton(
                        model,
                        label: model.selectedMarket.outcomeLabels.first ?? "Yes",
                        price: model.selectedMarket.yesProbability,
                        tint: Palette.yes,
                        surface: Palette.yesSurface,
                        isYes: true
                    )
                    tradeButton(
                        model,
                        label: model.selectedMarket.outcomeLabels.count > 1
                            ? model.selectedMarket.outcomeLabels[1] : "No",
                        price: model.selectedMarket.yesProbability.map { 1 - $0 },
                        tint: Palette.no,
                        surface: Palette.noSurface,
                        isYes: false
                    )
                }
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.vertical, Layout.Space.m)
        .background(.bar)
    }

    /// Builds the trade request for one outcome, or does nothing when that
    /// outcome has no tradable token.
    private func openTrade(_ model: MarketDetailViewModel, isYes: Bool) {
        let labels = model.selectedMarket.outcomeLabels
        let label = isYes
            ? (labels.first ?? "Yes")
            : (labels.count > 1 ? labels[1] : "No")
        guard let tokenId = isYes
            ? model.selectedMarket.yesTokenId
            : model.selectedMarket.noTokenId,
            model.selectedMarket.isTradable
        else { return }

        tradeRequest = TradeRequest(
            event: event,
            market: model.selectedMarket,
            tokenId: tokenId,
            outcomeLabel: label,
            isYes: isYes,
            side: .buy
        )
    }

    private func tradeButton(
        _ model: MarketDetailViewModel,
        label: String,
        price: Double?,
        tint: Color,
        surface: Color,
        isYes: Bool
    ) -> some View {
        Button {
            openTrade(model, isYes: isYes)
        } label: {
            VStack(spacing: 1) {
                Text("Buy \(label)")
                    .font(Typography.headline)
                Text(Format.cents(price))
                    .font(Typography.subheadline.monospacedDigit())
                    .opacity(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Buy \(label) at \(Format.cents(price))")
    }
}

// MARK: - Price chart

/// Native Swift Charts line chart with a scrubbable selection.
struct PriceChart: View {
    let points: [PricePoint]
    var tint: Color = Palette.ink

    @State private var selected: PricePoint?

    private var range: ClosedRange<Double> {
        let values = points.map(\.p)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        // Pad by a tenth of the range so a flat line is not glued to an edge.
        let padding = max(0.02, (high - low) * 0.1)
        return max(0, low - padding)...min(1, high + padding)
    }

    private var isRising: Bool {
        guard let first = points.first?.p, let last = points.last?.p else { return true }
        return last >= first
    }

    private var lineColor: Color { isRising ? Palette.up : Palette.down }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Probability", point.p)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Floor", range.lowerBound),
                    yEnd: .value("Probability", point.p)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [lineColor.opacity(0.22), lineColor.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Palette.inkTertiary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("Time", selected.date),
                    y: .value("Probability", selected.p)
                )
                .foregroundStyle(lineColor)
                .symbolSize(90)
                .annotation(position: .top, spacing: 6) {
                    VStack(spacing: 1) {
                        Text(Format.probability(selected.p))
                            .font(Typography.captionMedium.monospacedDigit())
                            .foregroundStyle(Palette.ink)
                        Text(Format.dateTime(selected.date))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.horizontal, Layout.Space.s)
                    .padding(.vertical, Layout.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                            .fill(Palette.surface)
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    )
                }
            }
        }
        .chartYScale(domain: range)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel {
                    if let probability = value.as(Double.self) {
                        Text(Format.probability(probability))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator.opacity(0.5))
                AxisValueLabel()
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geometry[plotFrame].origin
                                let x = value.location.x - origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                selected = nearest(to: date)
                            }
                            .onEnded { _ in selected = nil }
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private func nearest(to date: Date) -> PricePoint? {
        points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else {
            return "Price chart, no data"
        }
        let direction = last.p >= first.p ? "rose" : "fell"
        return """
            Price chart. \(direction) from \(Format.probability(first.p)) \
            to \(Format.probability(last.p)) over the selected range.
            """
    }
}

// MARK: - Order book

struct OrderBookView: View {
    let book: OrderBook
    var isLoading: Bool = false
    var maxLevels: Int = 6

    /// Depth bars are scaled to the largest level in view, so the relative
    /// sizes are readable even when one side dwarfs the other.
    private var maxSize: Double {
        let sizes = (book.bids.prefix(maxLevels) + book.asks.prefix(maxLevels)).map(\.size)
        return sizes.max() ?? 1
    }

    var body: some View {
        VStack(spacing: Layout.Space.m) {
            if isLoading && book.bids.isEmpty && book.asks.isEmpty {
                ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 18) }
            } else if book.bids.isEmpty && book.asks.isEmpty {
                Text("No resting orders.")
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Layout.Space.l)
            } else {
                HStack(alignment: .top, spacing: Layout.Space.l) {
                    column(
                        title: "Bids",
                        levels: Array(book.bids.prefix(maxLevels)),
                        tint: Palette.up,
                        alignment: .leading
                    )
                    column(
                        title: "Asks",
                        levels: Array(book.asks.prefix(maxLevels)),
                        tint: Palette.down,
                        alignment: .trailing
                    )
                }
            }
        }
        .padding(Layout.Space.l)
        .cardSurface(radius: Layout.Radius.large)
    }

    private func column(
        title: String,
        levels: [OrderBookLevel],
        tint: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: Layout.Space.xs) {
            Text(title.uppercased())
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(Palette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)

            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                ZStack(alignment: alignment == .leading ? .leading : .trailing) {
                    // Depth bar behind the numbers.
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tint.opacity(0.14))
                            .frame(width: geometry.size.width * (level.size / maxSize))
                            .frame(
                                maxWidth: .infinity,
                                alignment: alignment == .leading ? .leading : .trailing
                            )
                    }

                    HStack {
                        if alignment == .trailing { Spacer(minLength: 0) }
                        Text(Format.cents(level.price))
                            .font(Typography.tabularMedium)
                            .foregroundStyle(tint)
                        Spacer(minLength: Layout.Space.s)
                        Text(Format.shares(level.size))
                            .font(Typography.tabular)
                            .foregroundStyle(Palette.inkSecondary)
                        if alignment == .leading { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, Layout.Space.xs)
                }
                .frame(height: 20)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rules sheet

struct MarketRulesSheet: View {
    let event: Event
    let market: Market?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.Space.l) {
                    if let description = market?.description ?? event.description {
                        labelled("Resolution criteria", description)
                    }
                    if let source = market?.resolutionSource ?? event.resolutionSource,
                       !source.isEmpty {
                        labelled("Resolution source", source)
                    }
                    labelled("Closes", Format.dateTime(market?.resolvedEndDate ?? event.resolvedEndDate))

                    if market?.negRisk == true {
                        labelled(
                            "Negative risk",
                            """
                            This event's outcomes are mutually exclusive. Buying \
                            "No" across outcomes is capital-efficient because only \
                            one outcome can resolve true.
                            """
                        )
                    }

                    RiskNotice()
                }
                .padding(Layout.gutter)
            }
            .background(ScreenBackground())
            .navigationTitle("Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func labelled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.xs) {
            Text(title.uppercased())
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(Palette.inkTertiary)
            Text(body)
                .font(Typography.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
