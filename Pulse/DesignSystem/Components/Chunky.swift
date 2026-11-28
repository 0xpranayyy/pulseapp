import SwiftUI
import PulseCore

// MARK: - Chunky button

/// A solid pill with a hard, unblurred shadow directly beneath it.
///
/// The press *is* the shadow: the button drops by `Layout.chunkyDepth` onto
/// where its shadow was, and the shadow vanishes. No scale, no opacity flash —
/// the same physical press on every button in the app, which is what makes
/// the style read as one material rather than a stack of effects.
struct ChunkyButtonStyle: ButtonStyle {
    var fill: Color
    var ink: Color
    var shadow: Color
    var height: CGFloat = 60
    var fullWidth: Bool = true
    var font: Font = Typography.button

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(font)
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, fullWidth ? Layout.Space.l : 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(Capsule().fill(fill))
            .background(
                Capsule()
                    .fill(shadow)
                    .offset(y: pressed ? 0 : Layout.chunkyDepth)
            )
            .offset(y: pressed ? Layout.chunkyDepth : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: pressed)
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static func chunky(
        _ fill: Color,
        ink: Color,
        shadow: Color,
        height: CGFloat = 60,
        fullWidth: Bool = true,
        font: Font = Typography.button
    ) -> ChunkyButtonStyle {
        ChunkyButtonStyle(fill: fill, ink: ink, shadow: shadow, height: height, fullWidth: fullWidth, font: font)
    }

    /// Buy Yes.
    static var chunkyYes: ChunkyButtonStyle { .chunky(Brand.yes, ink: .white, shadow: Brand.yesDeep) }
    /// Buy No.
    static var chunkyNo: ChunkyButtonStyle { .chunky(Brand.no, ink: .white, shadow: Brand.noDeep) }
    /// The primary action on the cream canvas.
    static var chunkyInk: ChunkyButtonStyle { .chunky(Brand.ink, ink: .white, shadow: Color(hex: "0F1335")) }
    /// The primary action on the meadow.
    static var chunkyOnMeadow: ChunkyButtonStyle { .chunky(.white, ink: Brand.yes, shadow: Brand.meadowShadow) }
}

// MARK: - Chunky card

private struct ChunkyCard: ViewModifier {
    var fill: Color
    var shadow: Color
    var radius: CGFloat
    var clips: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .clipShape(clips ? AnyShape(shape) : AnyShape(Rectangle().inset(by: -1000)))
            .background(shape.fill(fill))
            .background(shape.fill(shadow).offset(y: Layout.chunkyDepth))
    }
}

extension View {
    /// White card with the hard shadow. `clips` keeps a coloured header band
    /// inside the rounded corners.
    func chunkyCard(
        fill: Color = Brand.card,
        shadow: Color = Brand.cardShadow,
        radius: CGFloat = Layout.Radius.card,
        clips: Bool = false
    ) -> some View {
        modifier(ChunkyCard(fill: fill, shadow: shadow, radius: radius, clips: clips))
    }
}

// MARK: - The tug

/// Yes and No pulling against each other, with the knot at the price.
///
/// The app's signature: the odds read as a position before they read as a
/// number. Green is the Yes share of the rope, red the No share, and the lime
/// knot sits exactly at the Yes probability. Three sizes, chosen by context:
/// a 6pt line in dense rows (no knot — it would crowd), 14pt on cards, 16pt
/// in a market header.
///
/// The stripes drift slowly so the rope reads as taut and live; under Reduce
/// Motion they stop and the knot holds still. VoiceOver hears one element:
/// "Odds, Yes 64¢, No 36¢".
struct TugBar: View {
    enum Size {
        case row, card, header

        var height: CGFloat {
            switch self { case .row: 6; case .card: 14; case .header: 16 }
        }
        var knot: CGFloat? {
            switch self { case .row: nil; case .card: 22; case .header: 26 }
        }
        var striped: Bool { self != .row }
    }

    let probability: Double
    var size: Size = .card
    /// A faint white ring, for bars sitting on a coloured panel.
    var ringed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var p: Double { min(1, max(0, probability)) }
    private var cents: Int { Int((p * 100).rounded()) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !size.striped)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                let width = geometry.size.width
                let split = width * p
                ZStack(alignment: .leading) {
                    rope(width: width, split: split, phase: t)
                        .frame(height: size.height)
                        .frame(maxHeight: .infinity)
                    if let knot = size.knot {
                        Circle()
                            .fill(Brand.lime)
                            .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 3))
                            .frame(width: knot, height: knot)
                            .offset(x: split - knot / 2 + CGFloat(sin(t * 3.2)) * 1.6)
                    }
                }
            }
        }
        .frame(height: size.knot ?? size.height)
        .animation(Motion.value, value: p)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Odds")
        .accessibilityValue("Yes \(cents)¢, No \(100 - cents)¢")
    }

    private func rope(width: CGFloat, split: CGFloat, phase: Double) -> some View {
        Canvas { context, canvas in
            let h = canvas.height
            context.fill(Path(CGRect(x: 0, y: 0, width: split, height: h)), with: .color(Brand.yes))
            context.fill(Path(CGRect(x: split, y: 0, width: canvas.width - split, height: h)), with: .color(Brand.no))
            guard size.striped else { return }
            // Diagonal braid. Drifts 6pt a second — slow enough to read as
            // tension, not as a loading bar.
            let spacing: CGFloat = 8
            let offset = CGFloat(phase * 6).truncatingRemainder(dividingBy: spacing)
            var stripes = Path()
            var x = -h + offset - spacing
            while x < canvas.width + h {
                stripes.move(to: CGPoint(x: x, y: h))
                stripes.addLine(to: CGPoint(x: x + h, y: 0))
                x += spacing
            }
            context.stroke(stripes, with: .color(.white.opacity(0.22)), lineWidth: spacing / 2)
        }
        .clipShape(Capsule())
        .overlay(ringed ? Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 3).padding(-3) : nil)
    }
}

// MARK: - Live badge

/// "LIVE", with a lime dot that pings. Only shown when the socket is
/// actually streaming — a badge that is always on stops meaning anything.
struct LiveBadge: View {
    var onDark: Bool = true
    @State private var ping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(Brand.lime).frame(width: 8, height: 8)
                    .scaleEffect(ping ? 2.4 : 0.8)
                    .opacity(ping ? 0 : 0.9)
                Circle().fill(Brand.lime).frame(width: 8, height: 8)
            }
            Text("LIVE")
                .font(Typography.overline)
                .tracking(0.6)
        }
        .foregroundStyle(onDark ? .white : Brand.ink)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(onDark ? Brand.ink : .white))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { ping = true }
        }
        .accessibilityLabel("Live prices")
    }
}

// MARK: - Price tick

/// A probability that flashes green or red for a moment when it moves.
///
/// Nunito, whose figures are fixed-width, so the digits never jitter as the
/// number changes.
struct PriceTick: View {
    let probability: Double
    var font: Font = Typography.probability
    var ink: Color = Brand.ink

    @State private var flash: Color?

    var body: some View {
        Text(Format.probability(probability))
            .font(font)
            .foregroundStyle(ink)
            .contentTransition(.numericText(value: probability))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(flash ?? .clear))
            .animation(Motion.value, value: probability)
            .onChange(of: probability) { old, new in
                guard old != new else { return }
                flash = new > old ? Brand.yesTint : Brand.noTint
                withAnimation(.easeOut(duration: 0.9).delay(0.45)) { flash = nil }
            }
    }
}

/// "▲ 6" / "▼ 3": a change in percentage points.
struct ChangeChip: View {
    /// Change as a fraction (0.06 = 6 points).
    let change: Double
    var suffix: String? = nil
    var filled: Bool = false

    private var points: Int { Int((change * 100).rounded()) }
    private var rising: Bool { points >= 0 }

    var body: some View {
        let text = "\(rising ? "▲" : "▼") \(abs(points))" + (suffix.map { " \($0)" } ?? "")
        Text(text)
            .font(Typography.captionMedium)
            .foregroundStyle(rising ? Brand.yes : Brand.no)
            .padding(.horizontal, filled ? 9 : 0)
            .frame(height: filled ? 24 : nil)
            .background(filled ? Capsule().fill(.white) : nil)
            .accessibilityLabel("\(rising ? "Up" : "Down") \(abs(points)) points" + (suffix.map { " \($0)" } ?? ""))
    }
}

// MARK: - Category tile

/// The category's symbol on its panel colour.
struct CategoryTile: View {
    let category: MarketCategory
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(Brand.panel(category))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Sparkline

/// A small line that ends on a lime live dot.
struct Sparkline: View {
    let values: [Double]
    var ink: Color = Brand.ink
    var lineWidth: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let points = normalised(in: geometry.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(ink, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(Brand.lime)
                        .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 2))
                        .frame(width: 9, height: 9)
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func normalised(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let span = max(hi - lo, 0.0001)
        let inset: CGFloat = 5
        return values.enumerated().map { index, value in
            CGPoint(
                x: inset + (size.width - inset * 2) * CGFloat(index) / CGFloat(values.count - 1),
                y: inset + (size.height - inset * 2) * CGFloat(1 - (value - lo) / span)
            )
        }
    }
}
