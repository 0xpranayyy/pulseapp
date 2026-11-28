import SwiftUI
import PulseCore

/// Pip, the Pulse mascot.
///
/// Drawn, not imported: one `Canvas` in a 240×240 space, ported from the
/// design canvas's SVG so the proportions match exactly, and driven by one
/// `TimelineView` so every part — bob, blink, antenna, arms — moves from a
/// single clock rather than a dozen independent repeat-forever animations
/// that drift out of step.
///
/// Pip reacts to what happened and never points at Yes or No. Poses are
/// tied to moments, not to advice:
///
/// | Pose          | When                                   |
/// |---------------|----------------------------------------|
/// | `.hello`      | onboarding, empty welcome states       |
/// | `.paddles`    | "pick Yes or No" — holds both, favours neither |
/// | `.holdingCard`| sign-in: the wallet you get            |
/// | `.peek`       | over the edge of a chart or sheet      |
/// | `.yay`        | an order filled, a market won          |
/// | `.hmm`        | nothing found                          |
/// | `.oops`       | an order failed, a market lost         |
/// | `.zzz`        | a market is closed                     |
///
/// Under Reduce Motion the clock stops at zero, which is a calm rest frame
/// for every pose. Decorative to VoiceOver unless given a `label`.
struct Pip: View {
    enum Pose: Sendable {
        case hello, paddles, holdingCard, peek, yay, hmm, oops, zzz
    }

    var pose: Pose = .hello
    var size: CGFloat = 160
    /// Ground shadow; nil for poses drawn over an edge or on a dark panel.
    var shadow: Color? = Brand.meadowShadow.opacity(0.38)
    var label: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                var ctx = context
                ctx.scaleBy(x: canvasSize.width / 240, y: canvasSize.height / 240)
                PipRenderer(pose: pose, time: time, shadow: shadow).draw(in: ctx)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "")
        .accessibilityHidden(label == nil)
    }
}

// MARK: - Renderer

private struct PipRenderer {
    let pose: Pip.Pose
    let time: Double
    let shadow: Color?

    private typealias C = Brand.Pip

    func draw(in ctx: GraphicsContext) {
        if pose == .peek {
            drawPeek(ctx)
            return
        }

        if let shadow {
            ctx.fill(ellipse(120, 227, 72, 9), with: .color(shadow))
        }

        let figure = bodyMotion(ctx)
        drawFeet(figure)
        drawArmsBehind(figure)
        drawBody(figure)
        drawAntenna(figure)
        drawFace(figure)
        drawArmsInFront(figure)
        drawExtras(ctx)
    }

    // MARK: Motion

    /// 0..<1 position through a repeating cycle.
    private func cycle(_ period: Double, delay: Double = 0) -> Double {
        let value = ((time - delay) / period).truncatingRemainder(dividingBy: 1)
        return value < 0 ? value + 1 : value
    }

    private func wave(_ period: Double, delay: Double = 0) -> Double {
        sin(cycle(period, delay: delay) * 2 * .pi)
    }

    /// Bob with squash and stretch, or a slow breath for the quiet poses.
    private func bodyMotion(_ ctx: GraphicsContext) -> GraphicsContext {
        switch pose {
        case .oops, .zzz:
            let breath = CGFloat(wave(3.6)) * 0.03
            return scaled(ctx, around: CGPoint(x: 120, y: 214), x: 1 + breath, y: 1 - breath)
        default:
            let period = pose == .yay ? 1.2 : 2.4
            let height: CGFloat = pose == .yay ? 16 : 10
            let s = CGFloat(wave(period))
            let lift = s > 0 ? -s * height : 0
            let squash = s < 0 ? -s * 0.04 : -s * 0.02
            var moved = ctx
            moved.translateBy(x: 0, y: lift)
            return scaled(moved, around: CGPoint(x: 120, y: 214), x: 1 + squash, y: 1 - squash)
        }
    }

    /// Eyes close for ~120ms roughly every four seconds.
    private var blinkScale: CGFloat {
        let phase = cycle(4.4, delay: 1.1)
        let distance = abs(phase - 0.96)
        guard distance < 0.02 else { return 1 }
        return 1 - 0.92 * CGFloat(1 - distance / 0.02)
    }

    // MARK: Parts

    private func drawFeet(_ ctx: GraphicsContext) {
        for x in [96.0, 144.0] {
            let foot = ellipse(x, 213, 20, 11)
            ctx.fill(foot, with: .color(C.foot))
            ctx.stroke(foot, with: .color(C.line), lineWidth: 3)
        }
    }

    private var bodyPath: Path {
        Path { p in
            p.move(to: CGPoint(x: 120, y: 56))
            p.addCurve(to: CGPoint(x: 206, y: 144), control1: CGPoint(x: 170, y: 56), control2: CGPoint(x: 206, y: 94))
            p.addCurve(to: CGPoint(x: 120, y: 214), control1: CGPoint(x: 206, y: 190), control2: CGPoint(x: 170, y: 214))
            p.addCurve(to: CGPoint(x: 34, y: 144), control1: CGPoint(x: 70, y: 214), control2: CGPoint(x: 34, y: 190))
            p.addCurve(to: CGPoint(x: 120, y: 56), control1: CGPoint(x: 34, y: 94), control2: CGPoint(x: 70, y: 56))
            p.closeSubpath()
        }
    }

    private func drawBody(_ ctx: GraphicsContext) {
        let body = bodyPath
        ctx.fill(body, with: .radialGradient(
            Gradient(stops: [
                .init(color: C.bodyLight, location: 0),
                .init(color: C.body, location: 0.55),
                .init(color: C.foot, location: 1)
            ]),
            center: CGPoint(x: 99, y: 103), startRadius: 0, endRadius: 170
        ))
        ctx.stroke(body, with: .color(C.line), lineWidth: 3)

        let shade = Path { p in
            p.move(to: CGPoint(x: 199, y: 150))
            p.addCurve(to: CGPoint(x: 126, y: 211), control1: CGPoint(x: 196, y: 188), control2: CGPoint(x: 166, y: 209))
            p.addCurve(to: CGPoint(x: 199, y: 150), control1: CGPoint(x: 162, y: 201), control2: CGPoint(x: 190, y: 182))
            p.closeSubpath()
        }
        ctx.fill(shade, with: .color(C.shade.opacity(0.55)))

        let highlight = ellipse(84, 92, 24, 10)
            .applying(rotation(-30, around: CGPoint(x: 84, y: 92)))
        ctx.fill(highlight, with: .color(.white.opacity(0.6)))
        ctx.fill(ellipse(110, 72, 4, 4), with: .color(.white.opacity(0.6)))
    }

    private func drawAntenna(_ ctx: GraphicsContext) {
        if pose == .zzz {
            // Drooped and dimmed: the market is asleep.
            let stem = Path { p in
                p.move(to: CGPoint(x: 120, y: 62))
                p.addCurve(to: CGPoint(x: 96, y: 40), control1: CGPoint(x: 116, y: 50), control2: CGPoint(x: 104, y: 44))
            }
            ctx.stroke(stem, with: .color(C.line), style: round(5))
            let orb = ellipse(93, 39, 10, 10)
            ctx.fill(orb, with: .color(Color(hex: "B9C97A")))
            ctx.stroke(orb, with: .color(C.eye), lineWidth: 3)
            return
        }
        let swing = wave(pose == .yay ? 0.6 : 2.2) * (pose == .yay ? 12 : 10)
        let swung = rotated(ctx, around: CGPoint(x: 120, y: 58), degrees: swing)
        let stem = Path { p in
            p.move(to: CGPoint(x: 120, y: 58))
            p.addCurve(to: CGPoint(x: 130, y: 21), control1: CGPoint(x: 113, y: 42), control2: CGPoint(x: 117, y: 29))
        }
        swung.stroke(stem, with: .color(C.line), style: round(5))
        let pulse = 1 + CGFloat(wave(1.6)) * 0.25
        var glow = swung
        glow.opacity = 0.4
        glow.fill(ellipse(132, 19, 18 * pulse, 18 * pulse), with: .color(Brand.lime))
        let orb = ellipse(132, 19, 10.5, 10.5)
        swung.fill(orb, with: .color(Brand.lime))
        swung.stroke(orb, with: .color(C.eye), lineWidth: 3)
        swung.fill(ellipse(128.5, 15.5, 3, 3), with: .color(.white))
    }

    private func drawFace(_ ctx: GraphicsContext) {
        drawBrows(ctx)
        drawEyes(ctx)
        for x in [66.0, 174.0] {
            ctx.fill(ellipse(x, 158, 14, 9), with: .color(C.blush))
        }
        for (x, y) in [(60.0, 156.0), (66.0, 160.0), (72.0, 156.0), (168.0, 156.0), (174.0, 160.0), (180.0, 156.0)] {
            ctx.fill(ellipse(x, y, 1.6, 1.6), with: .color(.white.opacity(0.75)))
        }
        drawMouth(ctx)
    }

    private func drawBrows(_ ctx: GraphicsContext) {
        let brows: [(CGPoint, CGPoint, CGPoint)]
        switch pose {
        case .yay, .zzz:
            return
        case .hmm:
            brows = [(CGPoint(x: 76, y: 96), CGPoint(x: 90, y: 86), CGPoint(x: 104, y: 92)),
                     (CGPoint(x: 136, y: 100), CGPoint(x: 150, y: 98), CGPoint(x: 164, y: 102))]
        case .oops:
            brows = [(CGPoint(x: 78, y: 96), CGPoint(x: 92, y: 102), CGPoint(x: 104, y: 92)),
                     (CGPoint(x: 136, y: 92), CGPoint(x: 148, y: 102), CGPoint(x: 162, y: 96))]
        default:
            brows = [(CGPoint(x: 76, y: 102), CGPoint(x: 90, y: 92), CGPoint(x: 104, y: 100)),
                     (CGPoint(x: 136, y: 100), CGPoint(x: 150, y: 92), CGPoint(x: 164, y: 102))]
        }
        for (start, control, end) in brows {
            let brow = Path { p in p.move(to: start); p.addQuadCurve(to: end, control: control) }
            ctx.stroke(brow, with: .color(C.eye), style: round(4.5))
        }
    }

    private func drawEyes(_ ctx: GraphicsContext) {
        switch pose {
        case .yay:
            // Squeezed shut with joy.
            for (a, c, b) in [(78.0, 92.0, 106.0), (134.0, 148.0, 162.0)] {
                let arc = Path { p in
                    p.move(to: CGPoint(x: a, y: 130))
                    p.addQuadCurve(to: CGPoint(x: b, y: 130), control: CGPoint(x: c, y: 114))
                }
                ctx.stroke(arc, with: .color(C.eye), style: round(6))
            }
            return
        case .zzz:
            for (a, c, b) in [(78.0, 92.0, 106.0), (134.0, 148.0, 162.0)] {
                let lid = Path { p in
                    p.move(to: CGPoint(x: a, y: 132))
                    p.addQuadCurve(to: CGPoint(x: b, y: 132), control: CGPoint(x: c, y: 142))
                }
                ctx.stroke(lid, with: .color(C.eye), style: round(5))
            }
            return
        default:
            break
        }

        let eyes = scaled(ctx, around: CGPoint(x: 120, y: 130), x: 1, y: blinkScale)
        for x in [92.0, 148.0] {
            let sclera = ellipse(x, 128, 20, 23)
            eyes.fill(sclera, with: .color(.white))
            eyes.stroke(sclera, with: .color(C.line), lineWidth: 2)
        }

        let look: CGPoint
        var pupil = CGSize(width: 13, height: 15.5)
        switch pose {
        case .hmm: look = CGPoint(x: 6, y: -8)
        case .oops: look = CGPoint(x: 0, y: 4); pupil = CGSize(width: 8, height: 10)
        case .hello: look = CGPoint(x: 4, y: 4)
        default: look = CGPoint(x: 2, y: 3)
        }
        for x in [92.0, 148.0] {
            let cx = x + look.x, cy = 128 + look.y
            eyes.fill(ellipse(cx, cy, pupil.width, pupil.height), with: .color(C.eye))
            let glint = pose == .oops ? 3.0 : 5.0
            eyes.fill(ellipse(cx + pupil.width * 0.38, cy - pupil.height * 0.45, glint, glint), with: .color(.white))
            if pose != .oops {
                eyes.fill(ellipse(cx - 5, cy + 7, 2.2, 2.2), with: .color(.white))
            }
        }
    }

    private func drawMouth(_ ctx: GraphicsContext) {
        switch pose {
        case .yay:
            let mouth = Path { p in
                p.move(to: CGPoint(x: 96, y: 152))
                p.addQuadCurve(to: CGPoint(x: 144, y: 152), control: CGPoint(x: 120, y: 196))
                p.closeSubpath()
            }
            ctx.fill(mouth, with: .color(C.eye))
            ctx.fill(tongue(y: 170, depth: 14, width: 28), with: .color(C.tongue))
        case .hmm:
            ctx.fill(ellipse(114, 166, 7, 8), with: .color(C.eye))
        case .oops:
            let mouth = Path { p in
                p.move(to: CGPoint(x: 100, y: 168))
                p.addQuadCurve(to: CGPoint(x: 112, y: 168), control: CGPoint(x: 106, y: 160))
                p.addQuadCurve(to: CGPoint(x: 124, y: 168), control: CGPoint(x: 118, y: 176))
                p.addQuadCurve(to: CGPoint(x: 136, y: 168), control: CGPoint(x: 130, y: 160))
            }
            ctx.stroke(mouth, with: .color(C.eye), style: round(4.5))
        case .zzz, .holdingCard:
            let mouth = Path { p in
                p.move(to: CGPoint(x: 106, y: 162))
                p.addQuadCurve(to: CGPoint(x: 134, y: 162), control: CGPoint(x: 120, y: 176))
            }
            ctx.stroke(mouth, with: .color(C.eye), style: round(5))
        default:
            let mouth = Path { p in
                p.move(to: CGPoint(x: 102, y: 160))
                p.addQuadCurve(to: CGPoint(x: 138, y: 160), control: CGPoint(x: 120, y: 184))
                p.closeSubpath()
            }
            ctx.fill(mouth, with: .color(C.eye))
            ctx.fill(tongue(y: 171, depth: 9, width: 20), with: .color(C.tongue))
        }
    }

    private func tongue(y: CGFloat, depth: CGFloat, width: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 120 - width / 2, y: y))
            p.addQuadCurve(to: CGPoint(x: 120 + width / 2, y: y), control: CGPoint(x: 120, y: y + depth))
            p.addQuadCurve(to: CGPoint(x: 120 - width / 2, y: y), control: CGPoint(x: 120, y: y - 4))
            p.closeSubpath()
        }
    }

    // MARK: Arms

    private func arm(
        _ ctx: GraphicsContext,
        from start: CGPoint, _ c1: CGPoint, _ c2: CGPoint, to end: CGPoint,
        hand: CGPoint?
    ) {
        let path = Path { p in p.move(to: start); p.addCurve(to: end, control1: c1, control2: c2) }
        ctx.stroke(path, with: .color(C.line), style: round(20))
        ctx.stroke(path, with: .color(C.body), style: round(14))
        if let hand {
            let circle = ellipse(hand.x, hand.y, 11, 11)
            ctx.fill(circle, with: .color(C.body))
            ctx.stroke(circle, with: .color(C.line), lineWidth: 3)
        }
    }

    private func restingLeftArm(_ ctx: GraphicsContext) {
        arm(ctx, from: CGPoint(x: 52, y: 150), CGPoint(x: 38, y: 158), CGPoint(x: 34, y: 174),
            to: CGPoint(x: 42, y: 186), hand: nil)
    }

    private func wavingRightArm(_ ctx: GraphicsContext) {
        let angle = 1 + wave(0.9) * 13
        let waving = rotated(ctx, around: CGPoint(x: 188, y: 142), degrees: angle)
        arm(waving, from: CGPoint(x: 188, y: 142), CGPoint(x: 208, y: 128), CGPoint(x: 216, y: 106),
            to: CGPoint(x: 210, y: 88), hand: CGPoint(x: 210, y: 84))
    }

    private func drawArmsBehind(_ ctx: GraphicsContext) {
        switch pose {
        case .hello:
            restingLeftArm(ctx)
            wavingRightArm(ctx)
        case .holdingCard:
            arm(ctx, from: CGPoint(x: 52, y: 150), CGPoint(x: 40, y: 160), CGPoint(x: 40, y: 176),
                to: CGPoint(x: 54, y: 184), hand: nil)
            wavingRightArm(ctx)
        case .yay:
            let swing = wave(0.6) * 7
            arm(rotated(ctx, around: CGPoint(x: 52, y: 132), degrees: -7 - swing),
                from: CGPoint(x: 52, y: 132), CGPoint(x: 34, y: 116), CGPoint(x: 30, y: 94),
                to: CGPoint(x: 40, y: 76), hand: CGPoint(x: 41, y: 73))
            arm(rotated(ctx, around: CGPoint(x: 188, y: 132), degrees: 7 + swing),
                from: CGPoint(x: 188, y: 132), CGPoint(x: 206, y: 116), CGPoint(x: 210, y: 94),
                to: CGPoint(x: 200, y: 76), hand: CGPoint(x: 199, y: 73))
        case .paddles:
            let swing = wave(1.6) * 8
            paddle(rotated(ctx, around: CGPoint(x: 52, y: 140), degrees: -8 - swing), isYes: true)
            paddle(rotated(ctx, around: CGPoint(x: 188, y: 140), degrees: -6 + swing), isYes: false)
        case .hmm:
            restingLeftArm(ctx)
        default:
            break
        }
    }

    /// Both paddles up at once, swinging in turn — Pip offers the choice and
    /// favours neither.
    private func paddle(_ ctx: GraphicsContext, isYes: Bool) {
        let x: CGFloat = isYes ? 32 : 208
        let shoulder: CGFloat = isYes ? 52 : 188
        let reach: CGFloat = isYes ? -1 : 1
        arm(ctx, from: CGPoint(x: shoulder, y: 140),
            CGPoint(x: shoulder + 16 * reach, y: 126), CGPoint(x: x - 2 * reach, y: 108),
            to: CGPoint(x: x, y: 90), hand: nil)
        let pole = Path { p in p.move(to: CGPoint(x: x, y: 92)); p.addLine(to: CGPoint(x: x, y: 40)) }
        ctx.stroke(pole, with: .color(Brand.bark), style: round(5))
        let sign = ellipse(x, 30, 24, 24)
        ctx.fill(sign, with: .color(isYes ? Brand.yes : Brand.no))
        ctx.stroke(sign, with: .color(.white), lineWidth: 4)
        let glyph = Path { p in
            if isYes {
                p.move(to: CGPoint(x: x - 11, y: 30))
                p.addLine(to: CGPoint(x: x - 3, y: 38))
                p.addLine(to: CGPoint(x: x + 12, y: 22))
            } else {
                p.move(to: CGPoint(x: x - 9, y: 21)); p.addLine(to: CGPoint(x: x + 9, y: 39))
                p.move(to: CGPoint(x: x + 9, y: 21)); p.addLine(to: CGPoint(x: x - 9, y: 39))
            }
        }
        ctx.stroke(glyph, with: .color(.white), style: round(5.5))
        let hand = ellipse(x, 92, 11, 11)
        ctx.fill(hand, with: .color(C.body))
        ctx.stroke(hand, with: .color(C.line), lineWidth: 3)
    }

    private func drawArmsInFront(_ ctx: GraphicsContext) {
        switch pose {
        case .hmm:
            arm(ctx, from: CGPoint(x: 190, y: 150), CGPoint(x: 182, y: 172), CGPoint(x: 162, y: 182),
                to: CGPoint(x: 148, y: 178), hand: CGPoint(x: 144, y: 176))
        case .oops:
            arm(ctx, from: CGPoint(x: 50, y: 146), CGPoint(x: 40, y: 158), CGPoint(x: 46, y: 170),
                to: CGPoint(x: 60, y: 168), hand: CGPoint(x: 64, y: 164))
            arm(ctx, from: CGPoint(x: 190, y: 146), CGPoint(x: 200, y: 158), CGPoint(x: 194, y: 170),
                to: CGPoint(x: 180, y: 168), hand: CGPoint(x: 176, y: 164))
        case .holdingCard:
            let card = rotated(ctx, around: CGPoint(x: 59, y: 170), degrees: -12)
            card.fill(rounded(25, 150, 74, 48, 9), with: .color(Color(hex: "155C2C")))
            let face = rounded(22, 146, 74, 48, 9)
            card.fill(face, with: .linearGradient(
                Gradient(colors: [Color(hex: "5FD08A"), Color(hex: "1F7A3C")]),
                startPoint: CGPoint(x: 22, y: 146), endPoint: CGPoint(x: 96, y: 194)
            ))
            card.stroke(face, with: .color(.white.opacity(0.6)), lineWidth: 2)
            card.fill(rounded(31, 156, 17, 13, 3), with: .color(Brand.lime))
            card.fill(rounded(31, 178, 32, 5, 2.5), with: .color(.white.opacity(0.7)))
            let dot = ellipse(84, 181, 5, 5)
            card.fill(dot, with: .color(Brand.lime))
            card.stroke(dot, with: .color(C.eye), lineWidth: 2)
            let hand = ellipse(56, 186, 11, 11)
            ctx.fill(hand, with: .color(C.body))
            ctx.stroke(hand, with: .color(C.line), lineWidth: 3)
        default:
            break
        }
    }

    // MARK: Extras (outside the bob)

    private func drawExtras(_ ctx: GraphicsContext) {
        switch pose {
        case .hmm:
            var bubble = ctx
            bubble.translateBy(x: 0, y: CGFloat(wave(2)) * 3)
            let big = ellipse(204, 48, 24, 24)
            bubble.fill(big, with: .color(.white))
            bubble.stroke(big, with: .color(C.eye), lineWidth: 3)
            let small = ellipse(184, 74, 6, 6)
            bubble.fill(small, with: .color(.white))
            bubble.stroke(small, with: .color(C.eye), lineWidth: 2.5)
            let mark = Path { p in
                p.move(to: CGPoint(x: 196, y: 41))
                p.addQuadCurve(to: CGPoint(x: 205, y: 32), control: CGPoint(x: 196, y: 32))
                p.addQuadCurve(to: CGPoint(x: 213, y: 40), control: CGPoint(x: 213, y: 32))
                p.addQuadCurve(to: CGPoint(x: 206, y: 49), control: CGPoint(x: 213, y: 46))
                p.addLine(to: CGPoint(x: 205, y: 54))
            }
            bubble.stroke(mark, with: .color(C.eye), style: round(4))
            bubble.fill(ellipse(205, 62, 2.8, 2.8), with: .color(C.eye))
        case .oops:
            let phase = cycle(1.8)
            var drop = ctx
            drop.opacity = phase < 0.2 ? phase / 0.2 : 1 - (phase - 0.2) / 0.8
            drop.translateBy(x: 0, y: CGFloat(phase) * 26)
            let tear = Path { p in
                p.move(to: CGPoint(x: 186, y: 82))
                p.addQuadCurve(to: CGPoint(x: 186, y: 102), control: CGPoint(x: 178, y: 96))
                p.addQuadCurve(to: CGPoint(x: 186, y: 82), control: CGPoint(x: 194, y: 96))
                p.closeSubpath()
            }
            drop.fill(tear, with: .color(Color(hex: "7FD0F7")))
            drop.stroke(tear, with: .color(Color(hex: "2B6FA0")), lineWidth: 2)
        case .zzz:
            for (index, origin) in [CGPoint(x: 168, y: 78), CGPoint(x: 184, y: 62), CGPoint(x: 160, y: 60)].enumerated() {
                let phase = cycle(3, delay: Double(index))
                var z = ctx
                z.opacity = phase < 0.25 ? phase / 0.25 : 1 - (phase - 0.25) / 0.75
                z.translateBy(x: origin.x + CGFloat(phase) * 16, y: origin.y - CGFloat(phase) * 40)
                let scale = 0.6 + CGFloat(phase) * 0.5
                z.scaleBy(x: scale, y: scale)
                let letter = Path { p in
                    p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 14, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: 14)); p.addLine(to: CGPoint(x: 14, y: 14))
                }
                z.stroke(letter, with: .color(C.eye), style: round(3.5))
            }
        default:
            break
        }
    }

    // MARK: Peek

    /// Head and paws over an edge at y = 168. The host draws the edge — a
    /// card or a sheet — directly below that line.
    private func drawPeek(_ ctx: GraphicsContext) {
        let rise = CGFloat(wave(3.2)) * 7 - 3
        var head = ctx
        head.clip(to: Path(CGRect(x: 0, y: 0, width: 240, height: 168)))
        head.translateBy(x: 0, y: -rise)

        let swing = wave(2) * 10
        let antenna = rotated(head, around: CGPoint(x: 120, y: 92), degrees: swing)
        let stem = Path { p in
            p.move(to: CGPoint(x: 120, y: 92))
            p.addCurve(to: CGPoint(x: 130, y: 55), control1: CGPoint(x: 113, y: 76), control2: CGPoint(x: 117, y: 63))
        }
        antenna.stroke(stem, with: .color(C.line), style: round(5))
        let orb = ellipse(132, 53, 10.5, 10.5)
        antenna.fill(orb, with: .color(Brand.lime))
        antenna.stroke(orb, with: .color(C.eye), lineWidth: 3)

        let skull = ellipse(120, 178, 86, 86)
        head.fill(skull, with: .color(C.body))
        head.stroke(skull, with: .color(C.line), lineWidth: 3)
        head.fill(ellipse(84, 122, 22, 9).applying(rotation(-28, around: CGPoint(x: 84, y: 122))),
                  with: .color(.white.opacity(0.6)))

        let eyes = scaled(head, around: CGPoint(x: 120, y: 146), x: 1, y: blinkScale)
        let look = CGFloat(max(0, wave(3.2))) * 4
        for x in [92.0, 148.0] {
            let sclera = ellipse(x, 146, 19, 21)
            eyes.fill(sclera, with: .color(.white))
            eyes.stroke(sclera, with: .color(C.line), lineWidth: 2)
            eyes.fill(ellipse(x + look, 150 + look * 0.75, 12, 14), with: .color(C.eye))
            eyes.fill(ellipse(x + look + 4, 144 + look * 0.75, 4.5, 4.5), with: .color(.white))
        }

        for x in [66.0, 174.0] {
            let paw = ellipse(x, 168, 15, 9)
            ctx.fill(paw, with: .color(C.body))
            ctx.stroke(paw, with: .color(C.line), lineWidth: 3)
        }
    }

    // MARK: Geometry helpers

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    private func round(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    private func rotation(_ degrees: Double, around point: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: point.x, y: point.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -point.x, y: -point.y)
    }

    private func rotated(_ ctx: GraphicsContext, around point: CGPoint, degrees: Double) -> GraphicsContext {
        var copy = ctx
        copy.translateBy(x: point.x, y: point.y)
        copy.rotate(by: .degrees(degrees))
        copy.translateBy(x: -point.x, y: -point.y)
        return copy
    }

    private func scaled(_ ctx: GraphicsContext, around point: CGPoint, x: CGFloat, y: CGFloat) -> GraphicsContext {
        var copy = ctx
        copy.translateBy(x: point.x, y: point.y)
        copy.scaleBy(x: x, y: y)
        copy.translateBy(x: -point.x, y: -point.y)
        return copy
    }
}
