import SwiftUI
import PulseCore

/// First-run onboarding.
///
/// Four pages, each owning a full colour field that cross-fades as you move.
/// Three things do the work:
///
/// * **Illustrations that are about the product.** Drawn and animated rather
///   than shipped as images, so they re-colour with the page, stay crisp at
///   any size, and show what a prediction market actually is.
/// * **Staggered entrance.** Eyebrow, headline, body and illustration arrive
///   in sequence. Everything appearing at once reads as a screenshot; a
///   short cascade reads as a page being composed.
/// * **One interactive page.** Explaining that a share costs the probability
///   and pays $1 takes a paragraph; letting someone drag the price takes a
///   second.
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
            body: "Real-money markets on elections, sport, crypto and the news — priced by everyone trading them.",
            kind: .markets
        ),
        Page(
            themeId: "lime",
            eyebrow: "How it works",
            headline: "Price is\nprobability.",
            body: "A share costs what the market thinks the odds are. If you're right, it settles at $1. Drag it.",
            kind: .payout
        ),
        Page(
            themeId: "teal",
            eyebrow: "Live",
            headline: "Books that\nmove every\nsecond.",
            body: "Streaming prices, the full order book, and a chart going back to the day each market opened.",
            kind: .book
        ),
        Page(
            themeId: "coral",
            eyebrow: "Before you start",
            headline: "Know the\nrisk.",
            body: "A position can lose its whole value. Prices come from other traders, not from a forecast — and nothing here is advice.",
            kind: .settlement
        )
    ]

    struct Page: Identifiable {
        enum Kind { case markets, payout, book, settlement }
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
            ColourField(colour: theme.screen)

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    ForEach(Array(Self.pages.enumerated()), id: \.element.id) { index, item in
                        PageContent(page: item, isCurrent: index == page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                controls
            }
        }
        .animation(reduceMotion ? nil : Motion.expressive, value: page)
    }

    // MARK: Chrome

    /// A segmented rail rather than dots: it says how much is left, and the
    /// filled segment animates across rather than a dot lighting up.
    private var topBar: some View {
        HStack(spacing: Layout.Space.m) {
            HStack(spacing: 5) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(theme.onField.opacity(index <= page ? 0.95 : 0.22))
                        .frame(width: index == page ? 26 : 8, height: 8)
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
                    .background(Capsule().fill(theme.onField.opacity(0.14)))
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
                    Image(systemName: isLast ? "arrow.up.right" : "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .buttonStyle(
                .pill(.primary, tint: theme.control, onTint: theme.onControl, fullWidth: true)
            )

            Text(isLast
                 ? "You can browse every market without an account."
                 : " ")
                .font(Typography.caption)
                .foregroundStyle(theme.onField.opacity(0.6))
                .multilineTextAlignment(.center)
                // Reserved whether or not it is filled, so the button does
                // not shift upward on the last page.
                .frame(height: 16)
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
    let isCurrent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var theme: Palette.Theme { page.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.l) {
            Spacer(minLength: Layout.Space.m)

            illustration
                .frame(maxWidth: .infinity)
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed ? 1 : 0.94)
                .offset(y: revealed ? 0 : 14)

            Spacer(minLength: Layout.Space.m)

            VStack(alignment: .leading, spacing: Layout.Space.s) {
                Text(page.eyebrow)
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(theme.onField.opacity(0.55))
                    .reveal(revealed, delay: 0.04)

                Text(page.headline)
                    .font(Typography.hero)
                    .foregroundStyle(theme.onField)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(revealed, delay: 0.10)

                Text(page.body)
                    .font(Typography.callout)
                    .foregroundStyle(theme.onField.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.Space.xs)
                    .reveal(revealed, delay: 0.16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, Layout.Space.l)
        .onAppear { setRevealed(isCurrent) }
        .onChange(of: isCurrent) { _, now in setRevealed(now) }
    }

    private func setRevealed(_ now: Bool) {
        guard !reduceMotion else {
            revealed = true
            return
        }
        if now {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { revealed = true }
        } else {
            // Reset so returning to a page plays the entrance again rather
            // than showing an already-composed screen.
            revealed = false
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch page.kind {
        case .markets: MarketFanMark(theme: theme)
        case .payout: PayoutDemoMark(theme: theme)
        case .book: LiveBookMark(theme: theme)
        case .settlement: SettlementMark(theme: theme)
        }
    }
}

// MARK: - Entrance

private extension View {
    /// Fades and lifts an element into place after a short delay.
    ///
    /// The delays are small — under a fifth of a second apart — because the
    /// point is a sense of order, not a performance to sit through.
    func reveal(_ revealed: Bool, delay: Double) -> some View {
        modifier(RevealModifier(revealed: revealed, delay: delay))
    }
}

private struct RevealModifier: ViewModifier {
    let revealed: Bool
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 12)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.5, dampingFraction: 0.84).delay(delay),
                value: revealed
            )
    }
}
