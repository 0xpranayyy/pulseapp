import SwiftUI
import PulseCore

/// First-run onboarding.
///
/// Four pages on the meadow: the sky, sun and hills stay put while each
/// page's illustration slides in over them. Three things do the work:
///
/// * **Illustrations that are about the product.** Drawn and animated rather
///   than shipped as images, so they stay crisp at any size and show what a
///   prediction market actually is — the same cards, tug and depth bars the
///   app uses, not a metaphor for them.
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
            id: "markets",
            eyebrow: "Pulse",
            headline: "Trade what\nyou think\nwill happen.",
            body: "Elections, sport, crypto, the news. Real money, and the price is set by everyone else trading it.",
            kind: .markets
        ),
        Page(
            id: "payout",
            eyebrow: "How it works",
            headline: "Price is\nprobability.",
            body: "35¢ means the market puts it at 35%. Right, and the share pays $1. Wrong, and it pays nothing. Drag the knot to try it.",
            kind: .payout
        ),
        Page(
            id: "book",
            eyebrow: "Live",
            headline: "Prices move\nwhile you\nwatch them.",
            body: "Every order as it lands, and a chart running back to the day the market opened.",
            kind: .book
        ),
        Page(
            id: "settlement",
            eyebrow: "Before you start",
            headline: "You can\nlose it all.",
            body: "A position can go to zero. These prices are other traders' opinions, not a forecast, and none of this is advice.",
            kind: .settlement
        )
    ]

    struct Page: Identifiable {
        enum Kind { case markets, payout, book, settlement }
        /// The page's own identity. It used to be the theme id, which made
        /// `ForEach` depend on a colour — and when those ids went stale the
        /// four pages collapsed onto one another.
        let id: String
        let eyebrow: String
        let headline: String
        let body: String
        let kind: Kind
    }

    private var isLast: Bool { page == Self.pages.count - 1 }

    var body: some View {
        GeometryReader { geometry in
            // The scene takes about two-fifths of the screen, less on small
            // phones, so the copy and the button always fit below it.
            let sceneHeight = min(340, geometry.size.height * 0.42)

            ZStack(alignment: .top) {
                MeadowGround().ignoresSafeArea()

                MeadowScene()
                    .frame(height: sceneHeight + geometry.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 0) {
                    topBar

                    TabView(selection: $page) {
                        ForEach(Array(Self.pages.enumerated()), id: \.element.id) { index, item in
                            PageContent(
                                page: item,
                                isCurrent: index == page,
                                // Down to the hill line, so cards stand on the grass.
                                illustrationHeight: sceneHeight - 44
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    controls
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.expressive, value: page)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            // A white pill, not white text: this sits on the sky, where
            // white type would vanish.
            Button("Skip") { finish() }
                .font(Typography.captionMedium)
                .foregroundStyle(Brand.ink)
                .padding(.horizontal, Layout.Space.m)
                .frame(height: 32)
                .background(Capsule().fill(.white))
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.s)
        .frame(height: 44)
    }

    /// A segmented rail rather than dots: it says how much is left, and the
    /// filled segment stretches across rather than a dot lighting up.
    private var rail: some View {
        HStack(spacing: 6) {
            ForEach(Self.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index == page ? 1 : 0.42))
                    .frame(width: index == page ? 26 : 8, height: 8)
            }
        }
        .animation(reduceMotion ? nil : Motion.quick, value: page)
        .accessibilityElement()
        .accessibilityLabel("Page \(page + 1) of \(Self.pages.count)")
    }

    private var controls: some View {
        VStack(spacing: Layout.Space.m) {
            rail

            Button {
                if isLast {
                    finish()
                } else {
                    withAnimation(reduceMotion ? nil : Motion.expressive) { page += 1 }
                    Haptics.selection(enabled: environment.settings.hapticsEnabled)
                }
            } label: {
                HStack(spacing: Layout.Space.s) {
                    Text(buttonTitle)
                    Image(systemName: isLast ? "arrow.up.right" : "arrow.right")
                        .font(.system(size: 15, weight: .black))
                }
            }
            .buttonStyle(.chunkyOnMeadow)

            Text(isLast
                 ? "You can browse every market without an account."
                 : " ")
                .font(Typography.captionMedium)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                // Reserved whether or not it is filled, so the button does
                // not shift upward on the last page.
                .frame(height: 16)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, Layout.Space.l)
        .padding(.top, Layout.Space.s)
    }

    private var buttonTitle: String {
        switch page {
        case 0: "Let’s go"
        case Self.pages.count - 1: "Start browsing"
        default: "Continue"
        }
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
    let illustrationHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(spacing: Layout.Space.m) {
            illustration
                .frame(maxWidth: .infinity)
                // Flexible: on a small phone the illustration gives up height
                // before the copy does.
                .frame(minHeight: 170, maxHeight: max(170, illustrationHeight))
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed ? 1 : 0.94, anchor: .bottom)
                .offset(y: revealed ? 0 : 14)

            VStack(spacing: Layout.Space.s) {
                Text(page.eyebrow.uppercased())
                    .font(Typography.overline)
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Brand.meadowShadow))
                    .reveal(revealed, delay: 0.04)

                // Centred and reflowed: the hand-placed line breaks were set
                // for a left-aligned column.
                Text(page.headline.replacingOccurrences(of: "\n", with: " "))
                    .font(Typography.hero)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-4)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .reveal(revealed, delay: 0.10)

                Text(page.body)
                    .font(BrandFont.ui(.extrabold, size: 18, relativeTo: .body))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(revealed, delay: 0.16)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Layout.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
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
        case .markets: MarketFanMark()
        case .payout: PayoutDemoMark()
        case .book: LiveBookMark()
        case .settlement: SettlementMark()
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
