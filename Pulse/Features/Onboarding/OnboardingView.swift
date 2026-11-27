import SwiftUI
import PulseCore

/// First-run onboarding.
///
/// Four pages, each owning a full colour field that cross-fades as you move.
/// The middle page is interactive rather than illustrated: prediction markets
/// have exactly one idea a newcomer must grasp — a share costs the
/// probability and pays $1 if it comes true — and letting someone drag the
/// price until that clicks beats any amount of explanatory copy.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private static let pages: [Page] = [
        Page(
            themeId: "ink",
            eyebrow: "Pulse",
            headline: "Trade what\nyou think\nwill happen.",
            body: "Real money markets on elections, sport, crypto and the news — priced by everyone trading them.",
            kind: .hero
        ),
        Page(
            themeId: "lime",
            eyebrow: "How it works",
            headline: "Price is\nprobability.",
            body: "A share costs what the market thinks the odds are. If you're right, it settles at $1. Drag to see it.",
            kind: .payoutDemo
        ),
        Page(
            themeId: "green",
            eyebrow: "Live",
            headline: "Books that\nmove every\nsecond.",
            body: "Streaming prices, full order books and a chart that goes back to the day each market opened.",
            kind: .liveTicker
        ),
        Page(
            themeId: "coral",
            eyebrow: "Before you start",
            headline: "Know the\nrisk.",
            body: "Positions can lose their whole value. Prices come from other traders, not from a forecast — and nothing here is advice.",
            kind: .risk
        )
    ]

    struct Page: Identifiable {
        enum Kind { case hero, payoutDemo, liveTicker, risk }
        let themeId: String
        let eyebrow: String
        let headline: String
        let body: String
        let kind: Kind
        var id: String { themeId }
        var theme: Palette.Theme { Palette.theme(named: themeId) }
    }

    private var theme: Palette.Theme { Self.pages[min(page, Self.pages.count - 1)].theme }
    private var isLast: Bool { page == Self.pages.count - 1 }

    var body: some View {
        ZStack {
            // One field owns the screen and cross-fades between pages.
            ColourField(colour: theme.screen)

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    ForEach(Array(Self.pages.enumerated()), id: \.element.id) { index, item in
                        PageContent(page: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                controls
            }
        }
        .animation(reduceMotion ? nil : Motion.expressive, value: page)
    }

    private var topBar: some View {
        HStack {
            // A progress rail rather than dots: it says how much is left.
            HStack(spacing: 4) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(theme.onField.opacity(index <= page ? 0.9 : 0.22))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
            .animation(reduceMotion ? nil : Motion.quick, value: page)

            Spacer()

            if !isLast {
                Button("Skip") { finish() }
                    .font(Typography.captionMedium)
                    .foregroundStyle(theme.onField)
                    .padding(.horizontal, Layout.Space.m)
                    .frame(height: 32)
                    .glass(Capsule(), interactive: true)
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \(page + 1) of \(Self.pages.count)")
    }

    private var controls: some View {
        VStack(spacing: Layout.Space.m) {
            Button {
                if isLast {
                    finish()
                } else {
                    withAnimation(reduceMotion ? nil : Motion.expressive) { page += 1 }
                    Haptics.selection(enabled: environment.settings.hapticsEnabled)
                }
            } label: {
                HStack(spacing: Layout.Space.s) {
                    Text(isLast ? "Start browsing" : "Continue")
                    if !isLast {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
            }
            .buttonStyle(
                .pill(.primary, tint: theme.control, onTint: theme.onControl, fullWidth: true)
            )

            if isLast {
                Text("You can browse every market without connecting a wallet.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.onField.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, Layout.Space.xl)
        .padding(.top, Layout.Space.m)
    }

    private func finish() {
        Haptics.success(enabled: environment.settings.hapticsEnabled)
        onFinish()
    }
}

// MARK: - Page content

private struct PageContent: View {
    let page: OnboardingView.Page

    private var theme: Palette.Theme { page.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.l) {
            Spacer(minLength: Layout.Space.l)

            illustration
                .frame(maxWidth: .infinity)

            Spacer(minLength: Layout.Space.l)

            VStack(alignment: .leading, spacing: Layout.Space.s) {
                Text(page.eyebrow)
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(theme.onField.opacity(0.55))

                Text(page.headline)
                    .font(Typography.hero)
                    .foregroundStyle(theme.onField)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.body)
                    .font(Typography.callout)
                    .foregroundStyle(theme.onField.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.Space.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, Layout.Space.l)
    }

    @ViewBuilder
    private var illustration: some View {
        switch page.kind {
        case .hero: HeroMark(theme: theme)
        case .payoutDemo: PayoutDemo(theme: theme)
        case .liveTicker: LiveTickerMark(theme: theme)
        case .risk: RiskMark(theme: theme)
        }
    }
}

// MARK: - Illustrations
//
// Drawn rather than shipped as images: they animate, they re-colour with the
// page theme, and they stay crisp at any size.

/// A rising probability line that draws itself in.
private struct HeroMark: View {
    let theme: Palette.Theme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    private let points: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.74), CGPoint(x: 0.18, y: 0.62),
        CGPoint(x: 0.34, y: 0.70), CGPoint(x: 0.52, y: 0.34),
        CGPoint(x: 0.72, y: 0.46), CGPoint(x: 1.00, y: 0.10)
    ]

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let scaled = points.map { CGPoint(x: $0.x * w, y: $0.y * h) }

            ZStack {
                Path { path in
                    path.move(to: scaled[0])
                    for point in scaled.dropFirst() { path.addLine(to: point) }
                }
                .trim(from: 0, to: progress)
                .stroke(
                    theme.onField,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                )

                if let last = scaled.last, progress > 0.98 {
                    Circle()
                        .fill(theme.onField)
                        .frame(width: 20, height: 20)
                        .position(last)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(height: 190)
        .onAppear {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeOut(duration: 1.1).delay(0.15)) { progress = 1 }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The one interactive page: drag the price and watch the payout change.
private struct PayoutDemo: View {
    let theme: Palette.Theme

    @State private var price: Double = 0.35
    private let stake: Double = 10

    private var shares: Double { price > 0 ? stake / price : 0 }
    private var profit: Double { shares - stake }

    var body: some View {
        VStack(spacing: Layout.Space.l) {
            HStack(alignment: .lastTextBaseline, spacing: Layout.Space.xs) {
                Text(Format.cents(price))
                    .font(Typography.probabilityHero)
                    .foregroundStyle(theme.onField)
                    .contentTransition(.numericText())
                Text("per share")
                    .font(Typography.subheadline)
                    .foregroundStyle(theme.onField.opacity(0.6))
            }

            Slider(value: $price, in: 0.05...0.95, step: 0.01)
                .tint(theme.control)
                .accessibilityLabel("Share price")
                .accessibilityValue(Format.cents(price))

            HStack(spacing: Layout.Space.m) {
                demoTile("Stake", Format.currency(stake))
                demoTile("Shares", Format.shares(shares.rounded()))
                demoTile("If right", Format.currency(shares), highlight: true)
            }

            Text("$\(Int(stake)) at \(Format.cents(price)) buys \(Format.shares(shares.rounded())) shares — worth \(Format.currency(shares)) if it happens, and nothing if it doesn't.")
                .font(Typography.caption)
                .foregroundStyle(theme.onField.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(Motion.value, value: price)
    }

    private func demoTile(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.8)
                .foregroundStyle(theme.onField.opacity(0.5))
            Text(value)
                .font(Typography.currency)
                .foregroundStyle(theme.onField)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                .fill(theme.onField.opacity(highlight ? 0.16 : 0.07))
        )
    }
}

/// Bars that breathe, standing in for a live book.
private struct LiveTickerMark: View {
    let theme: Palette.Theme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private let heights: [CGFloat] = [0.35, 0.62, 0.28, 0.80, 0.48, 0.92, 0.40, 0.66]

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(theme.onField.opacity(index % 2 == 0 ? 0.9 : 0.4))
                    .frame(height: 190 * (animating ? heights[index] : heights[index] * 0.45))
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.1 + Double(index) * 0.07)
                                .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .frame(height: 190, alignment: .bottom)
        .onAppear { animating = true }
        .accessibilityHidden(true)
    }
}

/// A split bar: the honest picture of a binary outcome.
private struct RiskMark: View {
    let theme: Palette.Theme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var split: CGFloat = 0.5

    var body: some View {
        VStack(spacing: Layout.Space.m) {
            GeometryReader { geometry in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.onField)
                        .frame(width: max(8, (geometry.size.width - 6) * split))
                        .overlay(alignment: .center) {
                            Text("$1")
                                .font(Typography.title2)
                                .foregroundStyle(theme.screen)
                        }
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.onField.opacity(0.18))
                        .overlay(alignment: .center) {
                            Text("$0")
                                .font(Typography.title2)
                                .foregroundStyle(theme.onField.opacity(0.6))
                        }
                }
            }
            .frame(height: 120)

            Text("Every market settles at one or the other.")
                .font(Typography.caption)
                .foregroundStyle(theme.onField.opacity(0.6))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                split = 0.72
            }
        }
    }
}
