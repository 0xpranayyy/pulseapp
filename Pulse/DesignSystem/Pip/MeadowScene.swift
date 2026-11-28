import SwiftUI
import PulseCore

/// The meadow: sky, sun, drifting clouds, two swaying trees, rolling hills,
/// flowers and a couple of hopping coins.
///
/// The brand's stage, used on welcome, onboarding and sign-in only — never
/// on a working screen, where it would compete with the data. Drawn in one
/// `Canvas` in a 393 × 362 design space, scaled to the width and anchored to
/// the bottom, so a shorter frame trims sky rather than squashing the hills.
/// The bottom edge is exactly `Brand.meadow`, so a meadow gradient below it
/// continues seamlessly.
///
/// One `TimelineView` drives everything and pauses under Reduce Motion.
/// Purely decorative: hidden from VoiceOver.
struct MeadowScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                MeadowRenderer(time: t).draw(in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MeadowRenderer {
    let time: Double

    static let designWidth: CGFloat = 393
    static let designHeight: CGFloat = 362

    private func wave(_ period: Double, _ phase: Double = 0) -> Double {
        sin((time / period + phase) * 2 * .pi)
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let s = size.width / Self.designWidth
        // Anchor to the bottom: extra height becomes sky above the scene.
        let dy = size.height / s - Self.designHeight

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [Brand.skyTop, Brand.skyBottom]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.85)
            )
        )

        var c = context
        c.scaleBy(x: s, y: s)
        c.translateBy(x: 0, y: dy)

        sun(&c)
        cloud(&c, at: CGPoint(x: wave(12) * 13 + 13, y: 0), large: true)
        cloud(&c, at: CGPoint(x: -wave(16, 0.3) * 13 - 13, y: 0), large: false)

        c.fill(Path { p in
            p.move(to: CGPoint(x: 0, y: 252))
            p.addCurve(to: CGPoint(x: 186, y: 246), control1: CGPoint(x: 60, y: 222), control2: CGPoint(x: 124, y: 230))
            p.addCurve(to: CGPoint(x: 393, y: 236), control1: CGPoint(x: 246, y: 262), control2: CGPoint(x: 302, y: 226))
            p.addLine(to: CGPoint(x: 393, y: 362)); p.addLine(to: CGPoint(x: 0, y: 362)); p.closeSubpath()
        }, with: .color(Brand.hillFar))

        tree(&c, trunk: CGRect(x: 32, y: 212, width: 17, height: 84), shadeWidth: 7,
             leaves: [(22, 214, 27, Brand.leafDark), (64, 210, 28, Brand.leaf), (42, 194, 34, Brand.leaf),
                      (44, 172, 24, Brand.leafLight), (34, 166, 7, Brand.leafGlint), (58, 186, 5, Brand.leafGlint)],
             sway: wave(4) * 1.6)
        tree(&c, trunk: CGRect(x: 336, y: 178, width: 21, height: 124), shadeWidth: 9,
             leaves: [(318, 186, 34, Brand.leafDark), (378, 180, 38, Brand.leafDark), (346, 158, 46, Brand.leaf),
                      (350, 122, 32, Brand.leafLight), (338, 114, 9, Brand.leafGlint), (372, 146, 6, Brand.leafGlint)],
             sway: wave(5, 0.14) * 1.6)

        c.fill(Path { p in
            p.move(to: CGPoint(x: 0, y: 302))
            p.addCurve(to: CGPoint(x: 204, y: 266), control1: CGPoint(x: 80, y: 272), control2: CGPoint(x: 150, y: 264))
            p.addCurve(to: CGPoint(x: 393, y: 292), control1: CGPoint(x: 262, y: 268), control2: CGPoint(x: 322, y: 286))
            p.addLine(to: CGPoint(x: 393, y: 362)); p.addLine(to: CGPoint(x: 0, y: 362)); p.closeSubpath()
        }, with: .color(Brand.hillNear))

        for (x, y, r, colour) in [(104.0, 292.0, 16.0, Brand.leaf), (122, 296, 12, Brand.leafLight), (282, 290, 13, Brand.leafLight)] {
            c.fill(circle(x, y, r), with: .color(colour))
        }
        for (x, y) in [(160.0, 302.0), (252, 296), (302, 310), (84, 318)] {
            c.fill(circle(x, y, 3.4), with: .color(.white))
            c.fill(circle(x, y, 1.4), with: .color(Brand.sun))
        }

        c.fill(Path { p in
            p.move(to: CGPoint(x: 0, y: 340))
            p.addQuadCurve(to: CGPoint(x: 140, y: 336), control: CGPoint(x: 70, y: 326))
            p.addQuadCurve(to: CGPoint(x: 280, y: 334), control: CGPoint(x: 210, y: 346))
            p.addQuadCurve(to: CGPoint(x: 393, y: 330), control: CGPoint(x: 350, y: 322))
            p.addLine(to: CGPoint(x: 393, y: 362)); p.addLine(to: CGPoint(x: 0, y: 362)); p.closeSubpath()
        }, with: .color(Brand.meadow))

        butterfly(&c)
        coin(&c, x: 306, y: 300, r: 15, hop: max(0, wave(2.6)))
        coin(&c, x: 74, y: 270, r: 11, hop: max(0, wave(3.1, 0.35)))
        twinkle(&c, x: 282, y: 238, r: 8, phase: 0)
        twinkle(&c, x: 110, y: 242, r: 6, phase: 0.45)
    }

    // MARK: Pieces

    private func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private func sun(_ context: inout GraphicsContext) {
        var c = context
        c.translateBy(x: 78, y: 84)
        c.fill(circle(0, 0, 62), with: .radialGradient(
            Gradient(colors: [Brand.sunGlow.opacity(0.9), Brand.sunGlow.opacity(0)]),
            center: .zero, startRadius: 0, endRadius: 62
        ))
        var rays = c
        rays.rotate(by: .degrees(time.truncatingRemainder(dividingBy: 24) / 24 * 360))
        for index in 0..<8 {
            var ray = rays
            ray.rotate(by: .degrees(Double(index) * 45))
            ray.fill(Path(roundedRect: CGRect(x: -4, y: -50, width: 8, height: 15), cornerRadius: 4),
                     with: .color(Brand.sun))
        }
        c.fill(circle(0, 0, 28), with: .color(Brand.sun))
        c.fill(circle(0, 0, 21), with: .color(Brand.sunCore))
        c.fill(circle(-8, -8, 6), with: .color(.white.opacity(0.6)))
    }

    private func cloud(_ context: inout GraphicsContext, at offset: CGPoint, large: Bool) {
        var c = context
        c.translateBy(x: offset.x, y: offset.y)
        if large {
            c.fill(Path(ellipseIn: CGRect(x: 192, y: 82, width: 88, height: 20)), with: .color(Brand.cloudShade))
            for (x, y, r) in [(212.0, 80.0, 18.0), (236, 70, 25), (262, 80, 17)] {
                c.fill(circle(x, y, r), with: .color(.white))
            }
            c.fill(Path(roundedRect: CGRect(x: 196, y: 80, width: 82, height: 12), cornerRadius: 6), with: .color(.white))
        } else {
            c.fill(Path(ellipseIn: CGRect(x: 134, y: 142, width: 52, height: 12)), with: .color(Brand.cloudShade))
            for (x, y, r) in [(148.0, 140.0, 11.0), (164, 134, 15)] {
                c.fill(circle(x, y, r), with: .color(.white))
            }
            c.fill(Path(roundedRect: CGRect(x: 138, y: 140, width: 46, height: 9), cornerRadius: 4.5), with: .color(.white))
        }
    }

    private func tree(
        _ context: inout GraphicsContext,
        trunk: CGRect,
        shadeWidth: CGFloat,
        leaves: [(Double, Double, Double, Color)],
        sway: Double
    ) {
        var c = context
        // Sway about the foot of the trunk.
        c.translateBy(x: trunk.midX, y: trunk.maxY)
        c.rotate(by: .degrees(sway))
        c.translateBy(x: -trunk.midX, y: -trunk.maxY)
        c.fill(Path(roundedRect: trunk, cornerRadius: 5), with: .color(Brand.bark))
        c.fill(Path(CGRect(x: trunk.maxX - shadeWidth, y: trunk.minY, width: shadeWidth, height: trunk.height)),
               with: .color(Brand.barkShade))
        for (x, y, r, colour) in leaves {
            c.fill(circle(x, y, r), with: .color(colour))
        }
    }

    private func butterfly(_ context: inout GraphicsContext) {
        var c = context
        // A slow loop around its perch, wings fluttering.
        let a = time / 7 * 2 * .pi
        c.translateBy(x: 300 - 15 + cos(a) * 15, y: 236 + sin(a * 2) * 13)
        let flap = 0.2 + 0.8 * abs(cos(time / 0.32 * .pi))
        var wings = c
        wings.scaleBy(x: flap, y: 1)
        for (x, y, rx, ry, colour) in [(-7.0, -4.0, 8.0, 10.0, Brand.lime), (7, -4, 8, 10, Brand.lime),
                                       (-5, 7, 5, 6, Brand.limeDeep), (5, 7, 5, 6, Brand.limeDeep)] {
            let wing = Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
            wings.fill(wing, with: .color(colour))
            wings.stroke(wing, with: .color(Brand.ink), lineWidth: 2)
        }
        c.fill(Path(roundedRect: CGRect(x: -1.6, y: -10, width: 3.2, height: 20), cornerRadius: 1.6),
               with: .color(Brand.ink))
    }

    private func coin(_ context: inout GraphicsContext, x: Double, y: Double, r: Double, hop: Double) {
        var c = context
        c.translateBy(x: x, y: y - hop * 14)
        c.rotate(by: .degrees(hop * 10))
        let face = circle(0, 0, r)
        c.fill(face, with: .color(Brand.coin))
        c.stroke(face, with: .color(Brand.coinEdge), lineWidth: r > 12 ? 2.5 : 2.2)
        c.stroke(circle(0, 0, r * 0.6), with: .color(Brand.coinShine), lineWidth: 2)
    }

    private func twinkle(_ context: inout GraphicsContext, x: Double, y: Double, r: Double, phase: Double) {
        let pulse = (wave(2.2, phase) + 1) / 2
        var c = context
        c.opacity = 0.15 + 0.85 * pulse
        c.translateBy(x: x, y: y)
        c.scaleBy(x: 0.5 + 0.5 * pulse, y: 0.5 + 0.5 * pulse)
        c.fill(Path { p in
            p.move(to: CGPoint(x: 0, y: -r))
            p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
            p.addQuadCurve(to: CGPoint(x: 0, y: r), control: .zero)
            p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: .zero)
            p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: .zero)
            p.closeSubpath()
        }, with: .color(.white))
    }
}

/// The meadow below the scene: bright where it meets the hills, deepening
/// fast enough that headlines sit on `meadowMid` or darker (3.6:1 for large
/// text) and body copy further down approaches `meadowDeep` (5.6:1).
struct MeadowGround: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Brand.meadow, location: 0),
                .init(color: Brand.meadowMid, location: 0.12),
                .init(color: Brand.meadowDeep, location: 0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
