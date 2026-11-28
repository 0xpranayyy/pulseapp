import SwiftUI
import PulseCore

// MARK: - Shared motion

/// Drives continuous illustration animation from one clock.
///
/// `TimelineView` rather than a pile of `repeatForever` animations: those
/// keep running when the page is off screen and drift out of phase with each
/// other. One schedule means every element on a page moves together and
/// stops together, and it collapses to a single static frame under Reduce
/// Motion.
struct Animated<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var content: (_ time: Double) -> Content

    var body: some View {
        if reduceMotion {
            // A fixed, deliberately mid-cycle frame — the illustrations are
            // composed to read well here, not just to animate well.
            content(0.35)
        } else {
            TimelineView(.animation) { timeline in
                content(timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }
}

/// Eased 0...1 oscillation.
private func wave(_ time: Double, period: Double, phase: Double = 0) -> Double {
    let raw = sin((time / period + phase) * 2 * .pi)
    return (raw + 1) / 2
}

// MARK: - Page 1 · a fan of live markets

/// Market cards fanned out behind Pip, who holds up both paddles.
///
/// The subject of the app is many simultaneous opinions, so the opening
/// image is a stack of them — each in its category's colour, each with its
/// tug — and Pip offering the choice without making it.
struct MarketFanMark: View {
    private struct Card {
        let title: String
        let category: MarketCategory
        let probability: Double
        let rotation: Double
        let offset: CGSize
        let phase: Double
    }

    private let cards: [Card] = [
        Card(title: "Rate cut in March", category: .economy, probability: 0.18, rotation: -14,
             offset: CGSize(width: -84, height: 10), phase: 0.0),
        Card(title: "Who wins the final", category: .sport, probability: 0.74, rotation: 12,
             offset: CGSize(width: 84, height: 4), phase: 0.33),
        Card(title: "BTC above $100k", category: .crypto, probability: 0.61, rotation: -2,
             offset: CGSize(width: 0, height: -22), phase: 0.66),
    ]

    var body: some View {
        Animated { time in
            ZStack(alignment: .bottom) {
                ZStack {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        let lift = wave(time, period: 3.4, phase: card.phase)
                        cardView(card, isLead: index == cards.count - 1, time: time)
                            .scaleEffect(index == cards.count - 1 ? 1 : 0.86)
                            .rotationEffect(.degrees(card.rotation))
                            .offset(x: card.offset.width, y: card.offset.height - lift * 8)
                            .zIndex(Double(index))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 18)

                Pip(pose: .paddles, size: 136)
                    .offset(y: 18)
                    .zIndex(10)
            }
        }
        .accessibilityHidden(true)
    }

    private func cardView(_ card: Card, isLead: Bool, time: Double) -> some View {
        // Only the lead card's number moves, so the eye has one thing to
        // follow rather than three competing.
        let drift = isLead ? (wave(time, period: 5.1) - 0.5) * 0.06 : 0
        let shown = min(0.97, max(0.03, card.probability + drift))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                CategoryTile(category: card.category, size: 24)
                Text(card.title)
                    .font(BrandFont.ui(.extrabold, size: 12))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(Format.probability(shown))
                .font(BrandFont.ui(.black, size: 28))
                .foregroundStyle(Brand.ink)
                .contentTransition(.numericText(value: shown))
            TugBar(probability: shown, size: .row)
        }
        .padding(12)
        .frame(width: 168, alignment: .topLeading)
        .chunkyCard(shadow: Brand.meadowShadow, radius: 20)
    }
}

// MARK: - Page 2 · price is probability

/// The one interactive page: drag the knot along the tug, watch the payout
/// follow.
///
/// Prediction markets have exactly one idea a newcomer has to grasp — a
/// share costs the probability and pays $1 — and letting someone move it
/// themselves lands it faster than any amount of copy.
struct PayoutDemoMark: View {
    @State private var price: Double = 0.35
    @State private var isDragging = false

    private let stake: Double = 10
    private var shares: Double { price > 0 ? stake / price : 0 }

    var body: some View {
        VStack(spacing: Layout.Space.m) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(Format.cents(price))
                    .font(BrandFont.ui(.black, size: 48))
                    .foregroundStyle(Brand.ink)
                    .contentTransition(.numericText(value: price))
                Text("per Yes share")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Brand.inkSecondary)
                Spacer(minLength: 0)
            }

            tug

            HStack(spacing: 6) {
                tile("Stake", Format.currency(stake))
                arrow
                tile("Shares", Format.shares(shares.rounded()))
                arrow
                tile("If Yes", Format.currency(shares), highlight: true)
            }
        }
        .padding(Layout.Space.l)
        .frame(maxWidth: 340)
        .chunkyCard(shadow: Brand.meadowShadow)
        // Pip watches over the card's edge — a reminder that this is a
        // sandbox, not a trade.
        .overlay(alignment: .topTrailing) {
            Pip(pose: .peek, size: 74, shadow: nil)
                .offset(x: -18, y: -52)
                .allowsHitTesting(false)
        }
        .padding(.top, 40)
        .frame(maxHeight: .infinity)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: price)
    }

    /// The tug itself is the control: the knot sits at the price, and
    /// dragging anywhere along it moves the knot there.
    private var tug: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                TugBar(probability: price, size: .header)
                    .scaleEffect(isDragging ? 1.04 : 1)
                    .animation(Motion.quick, value: isDragging)
                    .contentShape(Rectangle().inset(by: -14))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                price = min(0.95, max(0.05, value.location.x / geometry.size.width))
                            }
                            .onEnded { _ in isDragging = false }
                    )
            }
            .frame(height: 26)

            HStack {
                Text("Yes \(Format.cents(price))").foregroundStyle(Brand.yes)
                Spacer()
                Text("No \(Format.cents(1 - price))").foregroundStyle(Brand.no)
            }
            .font(Typography.captionMedium)
            .contentTransition(.numericText(value: price))
        }
        .accessibilityElement()
        .accessibilityLabel("Share price")
        .accessibilityValue("Yes \(Format.cents(price)), No \(Format.cents(1 - price))")
        .accessibilityHint("Swipe up or down to change it.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: price = min(0.95, price + 0.05)
            case .decrement: price = max(0.05, price - 0.05)
            default: break
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(Brand.inkTertiary)
            .accessibilityHidden(true)
    }

    private func tile(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(highlight ? Brand.yesDeep : Brand.inkTertiary)
            Text(value)
                .font(BrandFont.ui(.black, size: 16))
                .foregroundStyle(highlight ? Brand.yesDeep : Brand.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.Space.s)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlight ? Brand.yesTint : Brand.cardSunken)
        )
    }
}

// MARK: - Page 3 · a book that moves

/// An order book mid-flow: depth bars breathing on both sides, the spread
/// holding in the middle. Each level moves on its own period so it reads as
/// activity rather than a looping animation.
struct LiveBookMark: View {
    private let bids: [(price: Double, base: Double, phase: Double)] = [
        (0.62, 0.46, 0.0), (0.61, 0.70, 0.21), (0.60, 0.90, 0.44),
    ]
    private let asks: [(price: Double, base: Double, phase: Double)] = [
        (0.63, 0.52, 0.13), (0.64, 0.78, 0.36), (0.65, 0.40, 0.58),
    ]

    var body: some View {
        Animated { time in
            VStack(spacing: 5) {
                HStack {
                    Text("SELLING YES")
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Brand.lime)
                            .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 1.5))
                            .frame(width: 9, height: 9)
                            .scaleEffect(0.85 + 0.3 * wave(time, period: 1.4))
                        Text("MOVING")
                    }
                }
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(Brand.inkTertiary)
                .padding(.bottom, 3)

                ForEach(asks.reversed(), id: \.price) { level in
                    row(level, time: time, isBid: false)
                }

                HStack {
                    Text("SPREAD")
                        .font(Typography.overline)
                        .tracking(0.8)
                    Spacer()
                    Text("1¢")
                        .font(BrandFont.ui(.black, size: 13))
                }
                .foregroundStyle(Brand.inkSecondary)
                .padding(.vertical, 4)

                ForEach(bids, id: \.price) { level in
                    row(level, time: time, isBid: true)
                }

                HStack {
                    Text("BUYING YES")
                    Spacer()
                }
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(Brand.inkTertiary)
                .padding(.top, 3)
            }
            .padding(Layout.Space.l)
            .frame(maxWidth: 340)
            .chunkyCard(shadow: Brand.meadowShadow)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func row(
        _ level: (price: Double, base: Double, phase: Double),
        time: Double,
        isBid: Bool
    ) -> some View {
        let depth = level.base * (0.72 + 0.28 * wave(time, period: 2.6, phase: level.phase))
        let alignment: Alignment = isBid ? .leading : .trailing

        return ZStack(alignment: alignment) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isBid ? Brand.yesTint : Brand.noTint)
                    .frame(width: max(10, geometry.size.width * depth))
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
            Text(Format.cents(level.price))
                .font(BrandFont.ui(.black, size: 13))
                .foregroundStyle(isBid ? Brand.yesDeep : Brand.noDeep)
                .padding(.horizontal, 10)
        }
        .frame(height: 22)
    }
}

// MARK: - Page 4 · the two outcomes

/// Pip, startled, over the two ways a share ends: $1 or nothing.
///
/// The honest picture of a binary market, and the reason this page exists.
/// The mascot's one job here is to make the risk land without making it
/// cute.
struct SettlementMark: View {
    var body: some View {
        VStack(spacing: 0) {
            Pip(pose: .oops, size: 128)
                .offset(y: 14)
                .zIndex(1)
            HStack(spacing: Layout.Space.m) {
                outcome("If right", "$1", tint: Brand.yes)
                outcome("If wrong", "$0", tint: Brand.no)
            }
            .frame(maxWidth: 340)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func outcome(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.8)
                .foregroundStyle(Brand.inkTertiary)
            Text(value)
                .font(BrandFont.display(.bold, size: 40))
                .foregroundStyle(tint)
            Text("per share")
                .font(Typography.caption)
                .foregroundStyle(Brand.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.Space.m)
        .chunkyCard(shadow: Brand.meadowShadow, radius: 20)
    }
}
