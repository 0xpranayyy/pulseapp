import SwiftUI
import PulseCore

// MARK: - Probability

/// The probability figure plus its movement.
struct ProbabilityView: View {
    let probability: Double?
    var change: Double?
    var ink: Color = Brand.ink
    var size: Size = .regular

    enum Size { case small, regular, large, hero }

    private var font: Font {
        switch size {
        case .small: Typography.probabilitySmall
        case .regular: Typography.probability
        case .large: Typography.probabilityLarge
        case .hero: Typography.probabilityHero
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if size == .regular || size == .small, let probability {
                PriceTick(probability: probability, font: font, ink: ink)
            } else {
                Text(Format.probability(probability))
                    .font(font)
                    .foregroundStyle(ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            if let change, abs(change) >= 0.005 {
                ChangeChip(change: change)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var text = "\(Format.probability(probability)) chance"
        if let change, abs(change) >= 0.005 {
            let direction = change > 0 ? "up" : "down"
            text += ", \(direction) \(String(Format.probabilityChange(change).dropFirst())) points today"
        }
        return text
    }
}

// MARK: - Outcome pills

/// Yes / No buying pills: chunky, green and red, white text.
///
/// The only place on a card where green and red appear as fills, and they
/// mean exactly Yes and No — the mapping is learned once and reused
/// everywhere, including the tug.
struct OutcomePills: View {
    let yesLabel: String
    let noLabel: String
    let yesProbability: Double?
    var compact: Bool = false
    let onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: Layout.Space.s) {
            pill(label: yesLabel, price: yesProbability, isYes: true)
            pill(label: noLabel, price: yesProbability.map { 1 - $0 }, isYes: false)
        }
    }

    private func pill(label: String, price: Double?, isYes: Bool) -> some View {
        Button { onSelect(isYes) } label: {
            HStack(spacing: 5) {
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                // The price never wraps or truncates; the label yields first.
                Text(Format.cents(price))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.chunky(
            isYes ? Brand.yes : Brand.no,
            ink: .white,
            shadow: isYes ? Brand.yesDeep : Brand.noDeep,
            height: compact ? 34 : 44,
            font: compact ? Typography.captionMedium : Typography.buttonSmall
        ))
        .accessibilityLabel("Buy \(label) at \(Format.cents(price))")
    }
}

/// A press response for custom buttons that are not chunky. Small and fast:
/// a trading control that bounces feels slow.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Artwork

/// Market artwork. While loading, or when a market has no image, its
/// category tile stands in, so a row is never a grey hole.
struct MarketArt: View {
    let url: URL?
    var theme: Palette.Theme = Palette.brand
    var category: MarketCategory = .other
    var fallbackText: String?
    var size: CGFloat
    var cornerRadius: CGFloat = Layout.Radius.small

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Brand.ink.opacity(0.08), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Brand.panel(category)
            Image(systemName: category.symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Feed row

/// One event in a list: a white chunky card, artwork leading, the live
/// probability trailing, and the tug underneath so the odds read at a glance
/// before the number does.
struct EventRow: View {
    let event: Event
    var showsActions: Bool = true
    let onTapOutcome: ((Market, Bool) -> Void)?

    /// The legs shown inline, resolved once per row rather than on every
    /// body evaluation — a feed would otherwise re-sort every multi-outcome
    /// market on each frame of a scroll.
    private let topLegs: [Market]
    private let totalLegs: Int
    private let category: MarketCategory

    init(
        event: Event,
        showsActions: Bool = true,
        onTapOutcome: ((Market, Bool) -> Void)? = nil
    ) {
        self.event = event
        self.showsActions = showsActions
        self.onTapOutcome = onTapOutcome
        self.category = event.category

        let markets = event.markets ?? []
        self.totalLegs = markets.count
        self.topLegs = markets.count > 1
            ? Array(markets.sorted { ($0.yesProbability ?? 0) > ($1.yesProbability ?? 0) }.prefix(3))
            : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(alignment: .center, spacing: Layout.Space.m) {
                MarketArt(
                    url: event.imageURL,
                    category: category,
                    fallbackText: event.displayTitle,
                    size: 48,
                    cornerRadius: 15
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.displayTitle)
                        .font(Typography.title3)
                        .foregroundStyle(Brand.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !event.isMultiOutcome, let market = event.primaryMarket {
                    ProbabilityView(probability: market.yesProbability, change: market.dayChange)
                        .fixedSize()
                }
            }

            if !event.isMultiOutcome, let market = event.primaryMarket, let p = market.yesProbability {
                TugBar(probability: p, size: showsActions ? .card : .row)
            }

            if showsActions { actions }
        }
        .padding(Layout.Space.l)
        .chunkyCard()
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            Circle().fill(Brand.fill(category)).frame(width: 8, height: 8)
            Text(category.title.uppercased())
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(Brand.inkSecondary)
            if let volume = event.volume24h ?? event.volumeTotal {
                Text("·")
                Text(Format.compactCurrency(volume))
            }
            if let end = event.resolvedEndDate {
                Text("·")
                Text(Format.timeRemaining(until: end))
            }
        }
        .font(Typography.caption)
        .foregroundStyle(Brand.inkTertiary)
        .lineLimit(1)
    }

    @ViewBuilder private var actions: some View {
        if event.isMultiOutcome {
            VStack(spacing: Layout.Space.m) {
                ForEach(topLegs, id: \.id) { market in
                    VStack(spacing: 6) {
                        HStack(spacing: Layout.Space.s) {
                            Text(market.displayTitle)
                                .font(Typography.subheadlineMedium)
                                .foregroundStyle(Brand.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: Layout.Space.xs)
                            if let p = market.yesProbability {
                                PriceTick(probability: p, font: Typography.probabilitySmall)
                                    .fixedSize()
                            }
                        }
                        HStack(spacing: Layout.Space.s) {
                            TugBar(probability: market.yesProbability ?? 0.5, size: .row)
                            if let onTapOutcome {
                                OutcomePills(
                                    yesLabel: "Yes",
                                    noLabel: "No",
                                    yesProbability: market.yesProbability,
                                    compact: true
                                ) { isYes in onTapOutcome(market, isYes) }
                                .frame(width: 170)
                            }
                        }
                    }
                }

                if totalLegs > 3 {
                    HStack {
                        Text("+\(totalLegs - 3) more outcomes")
                            .font(Typography.captionMedium)
                            .foregroundStyle(Brand.inkSecondary)
                        Spacer()
                    }
                }
            }
        } else if let market = event.primaryMarket, market.isTradable, let onTapOutcome {
            OutcomePills(
                yesLabel: market.outcomeLabels.first ?? "Yes",
                noLabel: market.outcomeLabels.count > 1 ? market.outcomeLabels[1] : "No",
                yesProbability: market.yesProbability
            ) { isYes in onTapOutcome(market, isYes) }
        }
    }
}

// MARK: - Featured card

/// A large card in its category's colour: the one place on a list screen
/// where a market's colour fills a surface. It works because only a handful
/// are on screen and they scroll sideways; the same on every row would be
/// noise.
struct FeaturedEventCard: View {
    let event: Event
    var width: CGFloat = 300
    var onTapOutcome: ((Market, Bool) -> Void)? = nil

    private var category: MarketCategory { event.category }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            footer
        }
        .frame(width: width, alignment: .topLeading)
        .chunkyCard(clips: true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Layout.Space.s) {
            HStack(spacing: Layout.Space.s) {
                Image(systemName: category.symbol)
                    .font(.system(size: 14, weight: .bold))
                Text(category.title.uppercased())
                    .font(Typography.overline)
                    .tracking(0.8)
                Spacer(minLength: 0)
                if let volume = event.volume24h ?? event.volumeTotal {
                    Text(Format.compactCurrency(volume))
                        .font(Typography.captionMedium)
                }
            }

            Text(event.displayTitle)
                .font(Typography.title2)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let market = event.primaryMarket, !event.isMultiOutcome {
                HStack(alignment: .center, spacing: Layout.Space.s) {
                    Text(Format.probability(market.yesProbability))
                        .font(Typography.probabilityLarge)
                        .contentTransition(.numericText())
                    if let change = market.dayChange, abs(change) >= 0.005 {
                        ChangeChip(change: change, suffix: "today", filled: true)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(Layout.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.panel(category))
    }

    @ViewBuilder private var footer: some View {
        if let market = event.primaryMarket, !event.isMultiOutcome {
            VStack(spacing: Layout.Space.m) {
                TugBar(probability: market.yesProbability ?? 0.5)
                if market.isTradable, let onTapOutcome {
                    OutcomePills(
                        yesLabel: market.outcomeLabels.first ?? "Yes",
                        noLabel: market.outcomeLabels.count > 1 ? market.outcomeLabels[1] : "No",
                        yesProbability: market.yesProbability
                    ) { isYes in onTapOutcome(market, isYes) }
                }
            }
            .padding(Layout.Space.l)
        } else {
            HStack {
                Text("\(event.markets?.count ?? 0) outcomes")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Brand.inkSecondary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Brand.ink)
            }
            .padding(Layout.Space.l)
        }
    }
}
