import SwiftUI
import PulseCore

// MARK: - Probability display

/// The headline probability figure plus its movement.
struct ProbabilityView: View {
    let probability: Double?
    var change: Double?
    var size: Size = .regular

    enum Size { case regular, large }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(Format.probability(probability))
                .font(size == .large ? Typography.probabilityLarge : Typography.probability)
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())

            if let change, abs(change) >= 0.0001 {
                HStack(spacing: 1) {
                    Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(Format.probabilityChange(change).dropFirst()))
                }
                .font(Typography.captionMedium)
                .foregroundStyle(change > 0 ? Palette.up : Palette.down)
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

/// A horizontal Yes/No split bar.
///
/// Reads as one bar rather than two, so the eye compares the split directly
/// instead of two separate numbers.
struct ProbabilityBar: View {
    let yesProbability: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                Capsule()
                    .fill(Palette.yes)
                    .frame(width: max(0, geometry.size.width * clamped - 1))
                Capsule()
                    .fill(Palette.no.opacity(0.35))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yes \(Format.probability(clamped)), No \(Format.probability(1 - clamped))")
    }

    private var clamped: Double { min(1, max(0, yesProbability)) }
}

/// The Yes / No buying buttons.
struct OutcomeButtons: View {
    let yesProbability: Double?
    var compact: Bool = false
    let onSelect: (OrderSide, Bool) -> Void   // side, isYes

    var body: some View {
        HStack(spacing: Layout.Space.s) {
            outcomeButton(
                label: "Yes",
                price: yesProbability,
                tint: Palette.yes,
                surface: Palette.yesSurface,
                isYes: true
            )
            outcomeButton(
                label: "No",
                price: yesProbability.map { 1 - $0 },
                tint: Palette.no,
                surface: Palette.noSurface,
                isYes: false
            )
        }
    }

    private func outcomeButton(
        label: String,
        price: Double?,
        tint: Color,
        surface: Color,
        isYes: Bool
    ) -> some View {
        Button {
            onSelect(.buy, isYes)
        } label: {
            HStack(spacing: Layout.Space.xs) {
                Text(label)
                    .font(Typography.subheadlineMedium)
                Spacer(minLength: 2)
                Text(Format.cents(price))
                    .font(Typography.subheadlineMedium.monospacedDigit())
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Layout.Space.m)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 36 : Layout.Size.minimumTapTarget)
            .background(Capsule().fill(surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Buy \(label) at \(Format.cents(price))")
    }
}

// MARK: - Remote images

/// Market artwork with a themed placeholder.
///
/// Falls back to the market's theme colour and initial rather than a grey box,
/// so a missing image still carries the market's identity.
struct MarketImage: View {
    let url: URL?
    let theme: Palette.Theme
    var fallbackText: String?
    var size: CGFloat
    var cornerRadius: CGFloat = Layout.Radius.small

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            theme.field
            if let initial = fallbackText?.first.map(String.init) {
                Text(initial.uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.onField.opacity(0.65))
            }
        }
    }
}

// MARK: - Feed rows

/// One event in the feed.
///
/// Dense but not cramped: title, probability and the two most useful
/// numbers (volume and time left). Multi-outcome events show their top legs
/// inline rather than forcing a tap to see what the event is about.
struct EventRow: View {
    let event: Event
    var showsOutcomes: Bool = true
    let onTapOutcome: ((Market, Bool) -> Void)?

    private var theme: Palette.Theme { Palette.theme(for: event.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(alignment: .top, spacing: Layout.Space.m) {
                MarketImage(
                    url: event.imageURL,
                    theme: theme,
                    fallbackText: event.displayTitle,
                    size: Layout.Size.marketThumbnail
                )

                VStack(alignment: .leading, spacing: Layout.Space.xs) {
                    Text(event.displayTitle)
                        .font(Typography.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    metadata
                }

                Spacer(minLength: Layout.Space.s)

                if !event.isMultiOutcome, let market = event.primaryMarket {
                    ProbabilityView(
                        probability: market.yesProbability,
                        change: market.dayChange
                    )
                }
            }

            if showsOutcomes {
                outcomes
            }
        }
        .padding(Layout.Space.l)
        .cardSurface(radius: Layout.Radius.large)
    }

    private var metadata: some View {
        HStack(spacing: Layout.Space.s) {
            if let volume = event.volume24h ?? event.volumeTotal {
                Label(Format.compactCurrency(volume), systemImage: "chart.bar.fill")
                    .labelStyle(.titleAndIcon)
            }
            if let end = event.resolvedEndDate {
                Text("·")
                Text(Format.timeRemaining(until: end))
            }
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.inkSecondary)
        .lineLimit(1)
    }

    @ViewBuilder private var outcomes: some View {
        if event.isMultiOutcome {
            // Top legs by probability — the ones a reader actually cares about.
            let legs = (event.markets ?? [])
                .sorted { ($0.yesProbability ?? 0) > ($1.yesProbability ?? 0) }
                .prefix(3)

            VStack(spacing: Layout.Space.s) {
                ForEach(Array(legs), id: \.id) { market in
                    HStack(spacing: Layout.Space.m) {
                        Text(market.displayTitle)
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)

                        Spacer(minLength: Layout.Space.s)

                        Text(Format.probability(market.yesProbability))
                            .font(Typography.subheadlineMedium.monospacedDigit())
                            .foregroundStyle(Palette.ink)

                        if let onTapOutcome {
                            OutcomeButtons(
                                yesProbability: market.yesProbability,
                                compact: true
                            ) { _, isYes in
                                onTapOutcome(market, isYes)
                            }
                            .frame(width: 136)
                        }
                    }
                }

                if (event.markets ?? []).count > 3 {
                    HStack {
                        Text("+\((event.markets ?? []).count - 3) more")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer()
                    }
                }
            }
        } else if let market = event.primaryMarket, market.isTradable {
            VStack(spacing: Layout.Space.s) {
                ProbabilityBar(yesProbability: market.yesProbability ?? 0.5)
                if let onTapOutcome {
                    OutcomeButtons(yesProbability: market.yesProbability) { _, isYes in
                        onTapOutcome(market, isYes)
                    }
                }
            }
        }
    }
}

/// A compact card for horizontal carousels, using the market's theme as a
/// full-bleed field — the reference images' strongest motif.
struct FeaturedEventCard: View {
    let event: Event

    private var theme: Palette.Theme { Palette.theme(for: event.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(alignment: .top) {
                MarketImage(
                    url: event.imageURL,
                    theme: theme,
                    fallbackText: event.displayTitle,
                    size: 40,
                    cornerRadius: Layout.Radius.small
                )
                Spacer()
                if let market = event.primaryMarket, !event.isMultiOutcome {
                    Text(Format.probability(market.yesProbability))
                        .font(Typography.probability)
                        .foregroundStyle(theme.onField)
                }
            }

            Text(event.displayTitle)
                .font(Typography.title3)
                .foregroundStyle(theme.onField)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: Layout.Space.s) {
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
        .frame(width: 260, height: 190, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous)
                .fill(theme.field)
        )
    }
}
