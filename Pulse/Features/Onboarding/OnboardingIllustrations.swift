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

/// Market cards fanned out, breathing at slightly different rates, with the
/// lead card's probability counting as it moves.
///
/// The subject of the app is many simultaneous opinions, so the opening
/// image is a stack of them rather than a single abstract shape.
struct MarketFanMark: View {
    let theme: Palette.Theme

    private struct Card {
        let title: String
        let probability: Double
        let rotation: Double
        let offset: CGSize
        let scale: Double
        let phase: Double
    }

    private let cards: [Card] = [
        Card(title: "Rate cut in March",   probability: 0.18, rotation: -15,
             offset: CGSize(width: -58, height: 30), scale: 0.80, phase: 0.0),
        Card(title: "Who wins the final",  probability: 0.74, rotation: 13,
             offset: CGSize(width: 62, height: 18), scale: 0.82, phase: 0.33),
        Card(title: "BTC above $100k",     probability: 0.61, rotation: -2,
             offset: CGSize(width: 0, height: -16), scale: 1.0, phase: 0.66),
    ]

    var body: some View {
        Animated { time in
            ZStack {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    let lift = wave(time, period: 3.4, phase: card.phase)
                    cardView(card, isLead: index == cards.count - 1, time: time)
                        .scaleEffect(card.scale)
                        .rotationEffect(.degrees(card.rotation))
                        .offset(
                            x: card.offset.width,
                            y: card.offset.height - lift * 10
                        )
                        .zIndex(Double(index))
                }
            }
        }
        .frame(height: 230)
        .accessibilityHidden(true)
    }

    private func cardView(_ card: Card, isLead: Bool, time: Double) -> some View {
        // Only the lead card's number moves, so the eye has one thing to
        // follow rather than three competing.
        let drift = isLead ? (wave(time, period: 5.1) - 0.5) * 0.06 : 0
        let shown = min(0.97, max(0.03, card.probability + drift))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.onField.opacity(0.22))
                    .frame(width: 26, height: 26)
                Text(card.title)
                    .font(Allo.font(.semibold, size: 13))
                    .foregroundStyle(theme.screen.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(Format.probability(shown))
                .font(Allo.tabular(.black, size: 30))
                .foregroundStyle(theme.screen)
                .contentTransition(.numericText())

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.screen.opacity(0.15))
                    Capsule()
                        .fill(theme.screen.opacity(0.85))
                        .frame(width: geometry.size.width * shown)
                }
            }
            .frame(height: 5)
        }
        .padding(14)
        .frame(width: 180, height: 130, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.onField)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        )
    }
}

// MARK: - Page 2 · what a share pays

/// The one interactive page: drag the price, watch the payout follow.
///
/// Prediction markets have exactly one idea a newcomer has to grasp — a
/// share costs the probability and pays $1 — and letting someone move it
/// themselves lands it faster than any amount of copy.
struct PayoutDemoMark: View {
    let theme: Palette.Theme

    @State private var price: Double = 0.35
    @State private var isDragging = false

    private let stake: Double = 10
    private var shares: Double { price > 0 ? stake / price : 0 }

    var body: some View {
        VStack(spacing: Layout.Space.l) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(Format.cents(price))
                    .font(Allo.tabular(.black, size: 60))
                    .foregroundStyle(theme.onField)
                    .contentTransition(.numericText())
                Text("per share")
                    .font(Typography.subheadline)
                    .foregroundStyle(theme.onField.opacity(0.6))
            }

            priceSlider

            HStack(spacing: Layout.Space.s) {
                tile("Stake", Format.currency(stake))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.onField.opacity(0.4))
                tile("Shares", Format.shares(shares.rounded()))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.onField.opacity(0.4))
                tile("If right", Format.currency(shares), highlight: true)
            }
        }
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: price)
    }

    /// A custom track rather than `Slider`: the stock control renders in
    /// system colours that fight a saturated field, and the payout reads
    /// better when the fill itself is the measure.
    private var priceSlider: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = width * price

            ZStack(alignment: .leading) {
                Capsule().fill(theme.onField.opacity(0.16))
                Capsule()
                    .fill(theme.onField)
                    .frame(width: max(10, x))

                Circle()
                    .fill(theme.screen)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(theme.onField, lineWidth: 4))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .scaleEffect(isDragging ? 1.18 : 1)
                    .offset(x: max(0, min(width - 30, x - 15)))
                    .animation(Motion.quick, value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        price = min(0.95, max(0.05, value.location.x / width))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel("Share price")
        .accessibilityValue(Format.cents(price))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: price = min(0.95, price + 0.05)
            case .decrement: price = max(0.05, price - 0.05)
            default: break
            }
        }
    }

    private func tile(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.8)
                .foregroundStyle(theme.onField.opacity(0.5))
            Text(value)
                .font(Allo.tabular(.bold, size: 17))
                .foregroundStyle(theme.onField)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                .fill(theme.onField.opacity(highlight ? 0.2 : 0.08))
        )
    }
}

// MARK: - Page 3 · a book that moves

/// An order book mid-flow: bids and asks shuffling, the spread holding in
/// the middle. Each level moves on its own period so it reads as activity
/// rather than a looping animation.
struct LiveBookMark: View {
    let theme: Palette.Theme

    private let bids: [(price: Double, base: Double, phase: Double)] = [
        (0.62, 0.42, 0.0), (0.61, 0.66, 0.21), (0.60, 0.88, 0.44), (0.59, 0.55, 0.67),
    ]
    private let asks: [(price: Double, base: Double, phase: Double)] = [
        (0.63, 0.50, 0.13), (0.64, 0.74, 0.36), (0.65, 0.38, 0.58), (0.66, 0.62, 0.81),
    ]

    var body: some View {
        Animated { time in
            VStack(spacing: 5) {
                ForEach(asks.reversed(), id: \.price) { level in
                    row(level, time: time, tint: Palette.no, alignment: .trailing)
                }

                HStack {
                    Text("SPREAD")
                        .font(Typography.overline)
                        .tracking(1)
                        .foregroundStyle(theme.onField.opacity(0.45))
                    Spacer()
                    Text("1¢")
                        .font(Allo.tabular(.bold, size: 13))
                        .foregroundStyle(theme.onField.opacity(0.7))
                }
                .padding(.vertical, 3)

                ForEach(bids, id: \.price) { level in
                    row(level, time: time, tint: Palette.yes, alignment: .leading)
                }
            }
        }
        .frame(height: 230)
        .accessibilityHidden(true)
    }

    private func row(
        _ level: (price: Double, base: Double, phase: Double),
        time: Double,
        tint: Color,
        alignment: Alignment
    ) -> some View {
        let depth = level.base * (0.72 + 0.28 * wave(time, period: 2.6, phase: level.phase))

        return ZStack(alignment: alignment) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.55))
                    .frame(width: max(8, geometry.size.width * depth))
                    .frame(maxWidth: .infinity, alignment: alignment)
            }

            HStack {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(Format.cents(level.price))
                    .font(Allo.tabular(.semibold, size: 13))
                    .foregroundStyle(theme.onField)
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 22)
    }
}

// MARK: - Page 4 · the two outcomes

/// A single bar settling between $1 and $0.
///
/// The honest picture of a binary market, and the reason this page exists:
/// one of these two things happens, and the losing side is worth nothing.
struct SettlementMark: View {
    let theme: Palette.Theme

    var body: some View {
        Animated { time in
            let split = 0.3 + 0.4 * wave(time, period: 4.2)

            VStack(spacing: Layout.Space.m) {
                GeometryReader { geometry in
                    let width = geometry.size.width - 8

                    HStack(spacing: 8) {
                        outcome("$1", filled: true, width: max(40, width * split))
                        outcome("$0", filled: false, width: nil)
                    }
                }
                .frame(height: 178)

                Text("One of these happens. The other is worth nothing.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.onField.opacity(0.6))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func outcome(_ label: String, filled: Bool, width: CGFloat?) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(filled ? theme.onField : theme.onField.opacity(0.16))
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .overlay(
                Text(label)
                    .font(Allo.font(.black, size: 40))
                    .foregroundStyle(filled ? theme.screen : theme.onField.opacity(0.55))
            )
    }
}
