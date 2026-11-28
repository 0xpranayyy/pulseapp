import SwiftUI
import PulseCore

@main
@MainActor
struct PulseApp: App {
    @State private var environment = AppEnvironment()

    init() {
        // AsyncImage uses URLSession.shared and offers no way to pass
        // another, so market artwork only gets a usable cache if the shared
        // one is replaced. Must happen before the first image is requested.
        NetworkCache.installSharedCache()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                // Light only for now: the palette is designed against cream,
                // and a dark variant is its own design job, not an inversion.
                .preferredColorScheme(.light)
                .tint(Brand.ink)
                .task { await environment.session.restore() }
                // The session follows Privy wherever sign-in or sign-out
                // happens. Without this, a successful sign-in left every
                // screen showing "signed out" until the next launch.
                .onChange(of: environment.auth.state.address) { _, _ in
                    Task { await environment.session.adoptWallet() }
                }
        }
    }
}

// MARK: - Root

/// The app shell.
///
/// The tab bar is custom: a chunky white pill floating over the cream
/// canvas, in the same material as every card. Screens draw edge to edge and
/// reserve clearance for it via `Layout.Size.tabBarClearance`.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: Tab = .home

    enum Tab: Int, CaseIterable, Hashable, Identifiable {
        case home, explore, portfolio, activity, profile

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .explore: "Explore"
            case .portfolio: "Portfolio"
            case .activity: "Activity"
            case .profile: "Profile"
            }
        }

        var icon: String {
            switch self {
            case .home: "house.fill"
            case .explore: "magnifyingglass"
            case .portfolio: "chart.pie.fill"
            case .activity: "arrow.left.arrow.right"
            case .profile: "person.fill"
            }
        }

    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keep every screen alive so scroll position and loaded data
            // survive tab switches, the way a stock TabView does.
            ZStack {
                screen(.home) { HomeView() }
                screen(.explore) { ExploreView() }
                screen(.portfolio) { PortfolioView() }
                screen(.activity) { ActivityView() }
                screen(.profile) { ProfileView() }
            }
            .ignoresSafeArea(.keyboard)
            // Scrims belong to the content layer. Applied to the outer stack
            // they paint over the tab bar instead of behind it.
            .overlay(alignment: .top) { ScrollScrim(edge: .top) }
            .overlay(alignment: .bottom) { ScrollScrim(edge: .bottom) }

            FloatingTabBar(selection: $selection)
        }
        .overlay {
            if !environment.settings.hasOnboarded {
                OnboardingView {
                    withAnimation(Motion.expressive) {
                        environment.settings.hasOnboarded = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
                .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private func screen<Content: View>(
        _ tab: Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selection == tab ? 1 : 0)
            // Hidden tabs must not take hits, or taps land on the wrong screen.
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
    }
}

/// The tab bar: a white pill with the hard card shadow.
///
/// Icon-only at rest; the selected tab expands into a navy capsule carrying
/// its label and a lime dot — the same live accent as the tug's knot.
/// Showing the label only where it is needed buys room for larger icons and
/// makes the selection unmistakable.
struct FloatingTabBar: View {
    @Binding var selection: RootView.Tab

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RootView.Tab.allCases) { tab in
                item(tab)
            }
        }
        .padding(8)
        .background(Capsule().fill(Brand.card))
        .background(Capsule().fill(Brand.cardShadow).offset(y: Layout.chunkyDepth + 1))
        .padding(.horizontal, Layout.Space.l)
        .padding(.bottom, Layout.Space.s)
    }

    private func item(_ tab: RootView.Tab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard !isSelected else { return }
            if reduceMotion {
                selection = tab
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                    selection = tab
                }
            }
            Haptics.selection(enabled: environment.settings.hapticsEnabled)
        } label: {
            HStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: isSelected ? 18 : 21, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Palette.tabBarInk)
                    if isSelected {
                        Circle()
                            .fill(Brand.lime)
                            .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 1.5))
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -2)
                    }
                }

                if isSelected {
                    Text(tab.title)
                        .font(Typography.buttonSmall)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, isSelected ? 18 : 0)
            .frame(height: 50)
            // The pill sizes to its label; the remaining icons share what is
            // left. The other way round makes the selected tab dominate.
            .frame(maxWidth: isSelected ? nil : .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Brand.ink)
                        .matchedGeometryEffect(id: "selection", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

// MARK: - Screen scaffolding

/// A fade at the top and bottom of a screen.
///
/// Content scrolls under the status bar and under the floating tab bar;
/// without this the clock collides with a headline and rows show through
/// around the bar. Fades to the canvas itself, so it reads as distance, not
/// as a band. Never takes touches.
struct ScrollScrim: View {
    enum Edge { case top, bottom }
    let edge: Edge

    var body: some View {
        LinearGradient(
            colors: edge == .top
                ? [Brand.canvas, Brand.canvas.opacity(0.85), Brand.canvas.opacity(0)]
                : [Brand.canvas.opacity(0), Brand.canvas.opacity(0.8), Brand.canvas],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: edge == .top ? 54 : 110)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The screen background: the cream canvas, edge to edge.
///
/// `market` is accepted for the call sites that pass one, but a market no
/// longer tints its whole screen: its colour lives in the header panel, so
/// the chart and the order book sit on calm cream instead of competing with
/// a saturated field.
struct ColourField: View {
    var market: String?

    var body: some View {
        Brand.canvas.ignoresSafeArea()
    }
}

/// Standard scrolling content over a colour field, with clearance for the
/// floating tab bar so the last row is never trapped underneath it.
struct FieldScroll<Content: View>: View {
    var spacing: CGFloat = Layout.Space.m
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, Layout.Space.s)
            .padding(.bottom, Layout.Size.tabBarClearance)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

/// A screen title rendered on the colour field, with optional trailing pills.
struct FieldHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var ink: Color = Palette.ink
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.display)
                    .foregroundStyle(ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.subheadline)
                        .foregroundStyle(Brand.inkSecondary)
                }
            }
            Spacer(minLength: Layout.Space.s)
            trailing()
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.s)
        .padding(.bottom, Layout.Space.m)
        .accessibilityAddTraits(.isHeader)
    }
}

extension FieldHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, ink: Color = Palette.ink) {
        self.init(title: title, subtitle: subtitle, ink: ink) { EmptyView() }
    }
}
