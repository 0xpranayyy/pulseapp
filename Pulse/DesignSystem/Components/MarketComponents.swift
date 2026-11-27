import SwiftUI
import PulseCore

// MARK: - Probability

/// The probability figure plus its movement.
struct ProbabilityView: View {
    let probability: Double?
    var change: Double?
    var ink: Color = Palette.ink
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
        VStack(alignment: .trailing, spacing: 0) {
            Text(Format.probability(probability))
                .font(font)
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let change, abs(change) >= 0.0001 {
                HStack(spacing: 1) {
                    Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .black))
                    Text(String(Format.probabilityChange(change).dropFirst()))
                }
                .font(Typography.captionMedium)
                .foregroundStyle(ink.opacity(0.7))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var text = "\(Format.probability(probability)) chance"
        if let change, abs(change) >= 0.0001 {
            let direction = change > 0 ? "up" : "down"
            text += ", \(direction) \(String(Format.probabilityChange(change).dropFirst())) points today"
        }
        return text
    }
}

/// A single Yes/No split bar, drawn on a theme field.
struct ProbabilityBar: View {
    let yesProbability: Double
    var ink: Color = Palette.ink
    var height: CGFloat = 6

    private var clamped: Double { min(1, max(0, yesProbability)) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.15))
                Capsule()
                    .fill(ink.opacity(0.85))
                    .frame(width: max(2, geometry.size.width * clamped))
            }
        }
        .frame(height: height)
        .animation(Motion.value, value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yes \(Format.probability(clamped)), No \(Format.probability(1 - clamped))")
    }
}

// MARK: - Outcome pills

/// Yes / No buying pills.
///
/// Semantic green and rose rather than the theme's ink: on a neutral card
/// these are the only coloured elements besides the artwork, and the
/// Yes/No mapping is worth learning once and reusing everywhere.
struct OutcomePills: View {
    let yesLabel: String
    let noLabel: String
    let yesProbability: Double?
    var compact: Bool = false
    let onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: Layout.Space.s) {
            pill(label: yesLabel, price: yesProbability,
                 tint: Palette.yes, surface: Palette.yesSurface, isYes: true)
            pill(label: noLabel, price: yesProbability.map { 1 - $0 },
                 tint: Palette.no, surface: Palette.noSurface, isYes: false)
        }
    }

    private func pill(
        label: String, price: Double?, tint: Color, surface: Color, isYes: Bool
    ) -> some View {
        Button { onSelect(isYes) } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(compact ? Typography.captionMedium : Typography.subheadlineMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(0)
                Spacer(minLength: 0)
                // The price never wraps or truncates; the label yields first.
                Text(Format.cents(price))
                    .font(compact ? Typography.currencySmall : Typography.currency)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Layout.Space.m)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 34 : Layout.Size.minimumTapTarget)
            .background(Capsule().fill(surface))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Buy \(label) at \(Format.cents(price))")
    }
}

/// A press response for custom buttons. Small and fast: a trading control
/// that bounces feels slow.
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

/// Market artwork, large by default.
///
/// The placeholder is the market's own theme with its initial, so a missing
/// image still carries identity rather than leaving a grey hole.
struct MarketArt: View {
    let url: URL?
    let theme: Palette.Theme
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
                .strokeBorder(theme.onField.opacity(0.08), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            theme.control.opacity(0.14)
            if let initial = fallbackText?.first.map(String.init) {
                Text(initial.uppercased())
                    .font(Allo.font(.black, size: size * 0.42))
                    .foregroundStyle(theme.onField.opacity(0.55))
            }
        }
    }
}

// MARK: - Feed row

/// One event in the feed.
///
/// A light card on the dark list field, artwork leading. The card itself is
/// neutral and the colour comes from the artwork and the Yes/No pills —
/// tinting every card as well as the background turns a feed into noise with
/// nothing to rest the eye on.
struct EventRow: View {
    let event: Event
    var showsActions: Bool = true
    let onTapOutcome: ((Market, Bool) -> Void)?

    private var theme: Palette.Theme { Palette.theme(for: event.id) }

    /// The legs shown inline, resolved once per row rather than on every
    /// body evaluation — a feed would otherwise re-sort every multi-outcome
    /// market on each frame of a scroll.
    private let topLegs: [Market]
    private let totalLegs: Int

    init(
        event: Event,
        showsActions: Bool = true,
        onTapOutcome: ((Market, Bool) -> Void)? = nil
    ) {
        self.event = event
        self.showsActions = showsActions
        self.onTapOutcome = onTapOutcome

        let markets = event.markets ?? []
        self.totalLegs = markets.count
        self.topLegs = markets.count > 1
            ? Array(markets.sorted { ($0.yesProbability ?? 0) > ($1.yesProbability ?? 0) }.prefix(3))
            : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(alignment: .top, spacing: Layout.Space.m) {
                MarketArt(
                    url: event.imageURL,
                    theme: theme,
                    fallbackText: event.displayTitle,
                    size: Layout.Size.rowArt,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 5) {
                    if let category = categoryLabel {
                        Text(category.uppercased())
                            .font(Typography.overline)
                            .tracking(0.7)
                            .foregroundStyle(Palette.Card.inkTertiary)
                            .lineLimit(1)
                    }

                    Text(event.displayTitle)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.Card.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !event.isMultiOutcome, let market = event.primaryMarket {
                    ProbabilityView(
                        probability: market.yesProbability,
                        change: market.dayChange,
                        ink: Palette.Card.ink
                    )
                    .fixedSize()
                }
            }

            if showsActions { actions }
        }
        .padding(Layout.Space.l)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous)
                .fill(Palette.Card.fill)
                // Shadow on the opaque shape, not the composed view: shadowing
                // a subtree forces an offscreen pass to resolve its alpha.
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        )
    }

    private var categoryLabel: String? {
        event.tags?.first(where: { ($0.label?.isEmpty == false) })?.label
    }

    private var metadata: some View {
        HStack(spacing: Layout.Space.xs) {
            if let volume = event.volume24h ?? event.volumeTotal {
                Text(Format.compactCurrency(volume))
            }
            if let end = event.resolvedEndDate {
                Text("·")
                Text(Format.timeRemaining(until: end))
            }
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.Card.inkSecondary)
        .lineLimit(1)
    }

    @ViewBuilder private var actions: some View {
        if event.isMultiOutcome {
            VStack(spacing: Layout.Space.s) {
                ForEach(topLegs, id: \.id) { market in
                    HStack(spacing: Layout.Space.s) {
                        Text(market.displayTitle)
                            .font(Typography.subheadlineMedium)
                            .foregroundStyle(Palette.Card.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(0)

                        Spacer(minLength: Layout.Space.xs)

                        Text(Format.probability(market.yesProbability))
                            .font(Typography.probabilitySmall)
                            .foregroundStyle(Palette.Card.ink)
                            .fixedSize()

                        if let onTapOutcome {
                            OutcomePills(
                                yesLabel: "Yes",
                                noLabel: "No",
                                yesProbability: market.yesProbability,
                                compact: true
                            ) { isYes in onTapOutcome(market, isYes) }
                            .frame(width: 176)
                        }
                    }
                }

                if totalLegs > 3 {
                    HStack {
                        Text("+\(totalLegs - 3) more outcomes")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.Card.inkSecondary)
                        Spacer()
                    }
                }
            }
        } else if let market = event.primaryMarket, market.isTradable, let onTapOutcome {
            VStack(spacing: Layout.Space.s) {
                ProbabilityBar(
                    yesProbability: market.yesProbability ?? 0.5,
                    ink: Palette.Card.ink
                )
                OutcomePills(
                    yesLabel: market.outcomeLabels.first ?? "Yes",
                    noLabel: market.outcomeLabels.count > 1 ? market.outcomeLabels[1] : "No",
                    yesProbability: market.yesProbability
                ) { isYes in onTapOutcome(market, isYes) }
            }
        }
    }
}

// MARK: - Featured card

/// A large carousel card.
///
/// The one place on a list screen that carries a market's own colour. It
/// works here because there are only a handful on screen and they scroll
/// horizontally — the same treatment applied to every row is what made the
/// vertical feed unreadable.
struct FeaturedEventCard: View {
    let event: Event
    var width: CGFloat = 290

    private var theme: Palette.Theme { Palette.theme(for: event.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(alignment: .top) {
                MarketArt(
                    url: event.imageURL,
                    theme: theme,
                    fallbackText: event.displayTitle,
                    size: Layout.Size.heroArt,
                    cornerRadius: 18
                )
                Spacer(minLength: Layout.Space.s)
                if let market = event.primaryMarket, !event.isMultiOutcome {
                    ProbabilityView(
                        probability: market.yesProbability,
                        change: market.dayChange,
                        ink: theme.onField,
                        size: .regular
                    )
                    .fixedSize()
                }
            }

            Text(event.displayTitle)
                .font(Typography.title2)
                .foregroundStyle(theme.onField)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: Layout.Space.xs) {
                Text(Format.compactCurrency(event.volume24h ?? event.volumeTotal))
                if let end = event.resolvedEndDate {
                    Text("·")
                    Text(Format.timeRemaining(until: end))
                }
            }
            .font(Typography.caption)
            .foregroundStyle(theme.onField.opacity(0.7))
        }
        .padding(Layout.Space.l)
        .frame(width: width, height: 300, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.xlarge, style: .continuous)
                .fill(theme.screen)
                // Shadow on the opaque shape, not the composed view: shadowing
                // a subtree forces an offscreen pass to resolve its alpha.
                .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
        )
    }
}
