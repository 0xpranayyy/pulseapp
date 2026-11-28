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
    @State private var liveActivity = LiveActivityController()
    @State private var tradeRequest: TradeRequest?
    @State private var showsRules = false

    /// Navy on cream for the body of the screen; the category colour lives
    /// only in the header panel.
    private var theme: Palette.Theme { Palette.brand }
    private var category: MarketCategory { event.category }

    /// Sorted once per screen rather than on every body pass.
    private var sortedOutcomes: [Market] {
        (event.markets ?? []).sorted { ($0.yesProbability ?? 0) > ($1.yesProbability ?? 0) }
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ColourField(market: event.id))
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { floatingBar }
        .sheet(item: $tradeRequest) { request in
            TradeSheet(request: request)
                .presentationDetents([.large])
                // The sheet draws its own grabber and cancel control; the
                // system indicator would be a second one.
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
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
        .onChange(of: model?.displayedProbability) { _, new in
            guard let new, liveActivity.isTracking else { return }
            liveActivity.update(probability: new, book: model?.book)
        }
        .onDisappear {
            // Release the socket when leaving: keeping a subscription open per
            // visited market would leak connections across navigation.
            Task { [model] in await model?.stopStreaming() }
            liveActivity.stop()
        }
    }

    /// Back on the left, the market's controls on the right, floating over
    /// the header panel.
    private var floatingBar: some View {
        GlassTopBar(title: nil, subtitle: nil, tint: Brand.panel(category), onBack: { dismiss() }) {
            if let model { controlRow(model) }
        }
        .padding(.top, Layout.Space.s)
    }

    // MARK: Content

    private func content(_ model: MarketDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.Space.l) {
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
            .padding(.bottom, 120)   // clearance for the trade bar
        }
        .ignoresSafeArea(edges: .top)
        .refreshable { await model.refresh() }
        .safeAreaInset(edge: .bottom) { tradeBar(model) }
    }

    /// The market's own panel: its category colour, the question, the odds
    /// as a number and as a tug. The one place on this screen where the
    /// category colour fills a surface; everything below sits on calm cream
    /// so the chart and the book do not compete with it.
    private func header(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(spacing: Layout.Space.s) {
                MarketArt(url: event.imageURL, category: category, fallbackText: event.displayTitle,
                          size: 36, cornerRadius: 11)
                Text(category.title.uppercased())
                    .font(Typography.overline)
                    .tracking(0.7)
                if let volume = model.selectedMarket.volumeTotal {
                    Text("· \(Format.compactCurrency(volume))")
                        .font(Typography.captionMedium)
                }
                Spacer(minLength: 0)
                if model.isPriceStale {
                    Text("Delayed")
                        .font(Typography.captionMedium)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(.white.opacity(0.2)))
                        .accessibilityLabel("Prices may be out of date")
                } else {
                    LiveBadge(onDark: false)
                }
            }

            Text(event.displayTitle)
                .font(Typography.title)
                .fixedSize(horizontal: false, vertical: true)

            if event.isMultiOutcome {
                Text(model.selectedMarket.displayTitle)
                    .font(Typography.subheadlineMedium)
                    .opacity(0.85)
            }

            HStack(alignment: .center, spacing: Layout.Space.m) {
                Text(Format.probability(model.displayedProbability))
                    .font(Typography.probabilityHero)
                    .contentTransition(.numericText())
                    .animation(Motion.value, value: model.displayedProbability)
                VStack(alignment: .leading, spacing: 4) {
                    Text("chance of \(model.outcomeLabel)")
                        .font(Typography.headline)
                    if let change = model.selectedMarket.dayChange, abs(change) >= 0.005 {
                        ChangeChip(change: change, suffix: "today", filled: true)
                    }
                }
            }

            if let p = model.displayedProbability {
                VStack(spacing: 6) {
                    HStack {
                        Text("\(model.selectedMarket.outcomeLabels.first ?? "Yes") \(Format.cents(p))")
                        Spacer()
                        Text("\(model.selectedMarket.outcomeLabels.count > 1 ? model.selectedMarket.outcomeLabels[1] : "No") \(Format.cents(1 - p))")
                    }
                    .font(Typography.subheadlineMedium)
                    TugBar(probability: p, size: .header, ringed: true)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 112)
        .padding(.bottom, Layout.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous)
                .fill(Brand.panel(category))
        )
    }

    /// Watchlist, Dynamic Island, rules and share — white chunky circles on
    /// the panel.
    private func controlRow(_ model: MarketDetailViewModel) -> some View {
        HStack(spacing: Layout.Space.s) {
            GlassIconButton(
                systemName: environment.watchlist.contains(event.id) ? "star.fill" : "star",
                tint: Brand.panel(category),
                accessibilityLabel: environment.watchlist.contains(event.id)
                    ? "Remove from watchlist" : "Add to watchlist"
            ) {
                environment.watchlist.toggle(event.id)
                Haptics.selection(enabled: environment.settings.hapticsEnabled)
            }

            GlassIconButton(
                systemName: liveActivity.isTracking
                    ? "bolt.horizontal.fill" : "bolt.horizontal",
                tint: Brand.panel(category),
                isOn: liveActivity.isTracking,
                accessibilityLabel: liveActivity.isTracking
                    ? "Stop tracking in Dynamic Island" : "Track in Dynamic Island"
            ) {
                toggleLiveActivity()
            }
            .opacity(liveActivity.isAvailable ? 1 : 0.45)
            .disabled(!liveActivity.isAvailable)

            GlassIconButton(
                systemName: "doc.text",
                tint: Brand.panel(category),
                accessibilityLabel: "Rules and resolution"
            ) {
                showsRules = true
            }

            if let slug = event.slug,
               let url = URL(string: "https://polymarket.com/event/\(slug)") {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Brand.panel(category))
                        .frame(width: Layout.Size.iconButton, height: Layout.Size.iconButton)
                        .contentShape(Circle())
                }
                .background(Circle().fill(Brand.card))
                .background(Circle().fill(Brand.cardShadow).offset(y: 4))
                .accessibilityLabel("Share market")
            }
        }
    }

    private func outcomePicker(_ model: MarketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            SectionHeader(title: "Outcomes")
                .padding(.horizontal, Layout.gutter)

            VStack(spacing: Layout.Space.s) {
                ForEach(sortedOutcomes, id: \.id) { market in
                    Button {
                        Task { await model.select(market: market) }
                    } label: {
                        HStack(spacing: Layout.Space.m) {
                            Text(market.displayTitle)
                                .font(Typography.subheadlineMedium)
                                .foregroundStyle(theme.onField)
                                .lineLimit(1)
                            Spacer()
                            Text(Format.probability(market.yesProbability))
                                .font(Typography.subheadlineMedium.monospacedDigit())
                                .foregroundStyle(theme.onField)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.onField.opacity(0.5))
                        }
                        .padding(Layout.Space.m)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                                .fill(market.id == model.selectedMarket.id ? Brand.yesTint : Brand.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                                .strokeBorder(market.id == model.selectedMarket.id ? Brand.yes : Brand.hairline,
                                              lineWidth: 2)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Space.s) {
                    ForEach(PriceHistoryInterval.allCases, id: \.self) { interval in
                        FilterChip(
                            title: interval.displayName,
                            isSelected: model.interval == interval,
                            tint: Brand.panel(category)
                        ) {
                            model.interval = interval
                            Haptics.selection(enabled: environment.settings.hapticsEnabled)
                        }
                    }
                }
            }

            Group {
                if model.isLoadingHistory && model.history.isEmpty {
                    SkeletonBlock(height: 180, cornerRadius: Layout.Radius.medium)
                } else if model.history.count < 2 {
                    Text("Not enough price history yet.")
                        .font(Typography.subheadline)
                        .foregroundStyle(Brand.inkTertiary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    PriceChart(points: model.history, theme: theme, accent: Brand.panel(category))
                        .frame(height: 180)
                }
            }
        }
        .padding(Layout.Space.l)
        .chunkyCard()
        // Pip watches the price from the top edge of the card. Watching, not
        // pointing: it never leans toward a side.
        .overlay(alignment: .topTrailing) {
            Pip(pose: .peek, size: 92, shadow: nil)
                .offset(x: -18, y: -64)
                .allowsHitTesting(false)
        }
        .padding(.top, 34)
        .padding(.horizontal, Layout.gutter)
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
                Divider().background(theme.onField.opacity(0.18))
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
            .fieldPanel(theme, radius: Layout.Radius.large)
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

            OrderBookView(book: model.book, theme: theme, isLoading: model.isLoadingBook,
                          outcomeLabel: model.outcomeLabel)
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
                                .foregroundStyle(theme.onField)
                                .lineLimit(1)
                        }

                        Spacer(minLength: Layout.Space.xs)

                        Text("\(Format.shares(trade.size)) @ \(Format.cents(trade.price))")
                            .font(Typography.tabular)
                            .foregroundStyle(theme.onField.opacity(0.68))

                        Text(Format.relative(trade.date))
                            .font(Typography.caption)
                            .foregroundStyle(theme.onField.opacity(0.5))
                            .frame(width: 58, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Layout.Space.l)
            .fieldPanel(theme, radius: Layout.Radius.large)
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
                            .foregroundStyle(theme.onField)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Format.shares(holder.amount)) sh")
                            .font(Typography.tabular)
                            .foregroundStyle(theme.onField.opacity(0.68))
                    }
                }
            }
            .padding(Layout.Space.l)
            .fieldPanel(theme, radius: Layout.Radius.large)
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
                    .foregroundStyle(theme.onField.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Rules & resolution") { showsRules = true }
                    .buttonStyle(.pill(.quiet, tint: theme.onField))
                    .padding(.top, Layout.Space.xs)
            }
            .padding(.horizontal, Layout.gutter)
        }
    }

    // MARK: Trade bar

    private func tradeBar(_ model: MarketDetailViewModel) -> some View {
        VStack(spacing: Layout.Space.s) {
            if !model.canTrade {
                HStack(spacing: Layout.Space.s) {
                    Pip(pose: .zzz, size: 52, shadow: nil)
                    Text(
                        model.selectedMarket.closed == true
                            ? "This market has closed."
                            : "This market isn't accepting orders."
                    )
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Brand.inkSecondary)
                }
            } else {
                HStack(spacing: Layout.Space.s) {
                    tradeButton(
                        model,
                        label: model.selectedMarket.outcomeLabels.first ?? "Yes",
                        price: model.selectedMarket.yesProbability,
                        isYes: true
                    )
                    tradeButton(
                        model,
                        label: model.selectedMarket.outcomeLabels.count > 1
                            ? model.selectedMarket.outcomeLabels[1] : "No",
                        price: model.selectedMarket.yesProbability.map { 1 - $0 },
                        isYes: false
                    )
                }
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.l)
        .padding(.bottom, Layout.Space.s)
        .background(
            LinearGradient(colors: [Brand.canvas.opacity(0), Brand.canvas, Brand.canvas],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func toggleLiveActivity() {
        guard let model else { return }
        if liveActivity.isTracking {
            liveActivity.stop()
        } else {
            guard let tokenId = model.activeTokenId,
                  let probability = model.displayedProbability else { return }
            liveActivity.start(
                market: model.selectedMarket,
                tokenId: tokenId,
                outcomeLabel: model.outcomeLabel,
                probability: probability,
                book: model.book
            )
        }
        Haptics.selection(enabled: environment.settings.hapticsEnabled)
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
        isYes: Bool
    ) -> some View {
        Button {
            openTrade(model, isYes: isYes)
        } label: {
            Text("Buy \(label) · \(Format.cents(price))")
        }
        .buttonStyle(isYes ? ChunkyButtonStyle.chunkyYes : ChunkyButtonStyle.chunkyNo)
        .accessibilityLabel("Buy \(label) at \(Format.cents(price))")
    }
}

// MARK: - Price chart

/// Native Swift Charts line chart with a scrubbable selection.
struct PriceChart: View {
    let points: [PricePoint]
    let theme: Palette.Theme
    /// The market's category colour. The line is deliberately not green or
    /// red: those mean Yes and No, and a falling Yes price is not "No".
    var accent: Color = Brand.ink

    @State private var selected: PricePoint?

    private var range: ClosedRange<Double> {
        let values = points.map(\.p)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        // Pad by a tenth of the range so a flat line is not glued to an edge.
        let padding = max(0.02, (high - low) * 0.1)
        return max(0, low - padding)...min(1, high + padding)
    }

    private var lineColor: Color { accent }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Probability", point.p)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

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

            // The live end of the line.
            if selected == nil, let last = points.last {
                PointMark(x: .value("Time", last.date), y: .value("Probability", last.p))
                    .symbol {
                        Circle()
                            .fill(Brand.lime)
                            .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 2.5))
                            .frame(width: 13, height: 13)
                    }
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(theme.onField.opacity(0.5).opacity(0.4))
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
                            .foregroundStyle(theme.onField)
                        Text(Format.dateTime(selected.date))
                            .font(Typography.caption)
                            .foregroundStyle(theme.onField.opacity(0.68))
                    }
                    .padding(.horizontal, Layout.Space.s)
                    .padding(.vertical, Layout.Space.xs)
                    .background(RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                        .fill(Brand.card))
                    .background(RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                        .fill(Brand.cardShadow).offset(y: 3))
                }
            }
        }
        .chartYScale(domain: range)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(theme.onField.opacity(0.18))
                AxisValueLabel {
                    if let probability = value.as(Double.self) {
                        Text(Format.probability(probability))
                            .font(Typography.caption)
                            .foregroundStyle(theme.onField.opacity(0.5))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(theme.onField.opacity(0.18).opacity(0.5))
                AxisValueLabel()
                    .font(Typography.caption)
                    .foregroundStyle(theme.onField.opacity(0.5))
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
    let theme: Palette.Theme
    var isLoading: Bool = false
    /// The outcome this book trades, for column titles in plain words.
    var outcomeLabel: String = "Yes"
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
                    .foregroundStyle(theme.onField.opacity(0.68))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Layout.Space.l)
            } else {
                HStack(alignment: .top, spacing: Layout.Space.l) {
                    column(
                        title: "Buying \(outcomeLabel)",
                        levels: Array(book.bids.prefix(maxLevels)),
                        tint: Palette.up,
                        alignment: .leading
                    )
                    column(
                        title: "Selling \(outcomeLabel)",
                        levels: Array(book.asks.prefix(maxLevels)),
                        tint: Palette.down,
                        alignment: .trailing
                    )
                }
            }
        }
        .padding(Layout.Space.l)
        .fieldPanel(theme, radius: Layout.Radius.large)
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
                .foregroundStyle(theme.onField.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)

            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                ZStack(alignment: alignment == .leading ? .leading : .trailing) {
                    // Depth bar behind the numbers.
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint == Palette.up ? Brand.yesTint : Brand.noTint)
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
                            .foregroundStyle(theme.onField.opacity(0.68))
                        if alignment == .leading { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, Layout.Space.xs)
                }
                .frame(height: 24)
                .animation(Motion.value, value: level.size)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rules sheet

struct MarketRulesSheet: View {
    private var theme: Palette.Theme { Palette.brand }
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
            .background(ColourField(market: event.id))
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
                .foregroundStyle(theme.onField.opacity(0.5))
            Text(body)
                .font(Typography.callout)
                .foregroundStyle(theme.onField)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
