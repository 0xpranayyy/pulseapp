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
                .preferredColorScheme(environment.settings.appearance.colorScheme)
                .tint(Palette.ink)
                .task { await environment.session.restore() }
        }
    }
}

// MARK: - Root

/// The app shell.
///
/// The tab bar is custom rather than a stock `TabView` bar: the reference
/// language puts a detached capsule over a full-bleed colour field, and a
/// system bar paints an opaque strip across the bottom that cuts the colour
/// off. Screens therefore draw edge to edge and reserve clearance for the bar
/// themselves via `Layout.Size.tabBarClearance`.
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

        /// The colour of this tab's selection pill. Drawn from the market
        /// palette so the bar belongs to the same system as the content.
        var accent: Palette.Theme {
            switch self {
            case .home: Palette.theme(named: "green")
            case .explore: Palette.theme(named: "sky")
            case .portfolio: Palette.theme(named: "lime")
            case .activity: Palette.theme(named: "coral")
            case .profile: Palette.theme(named: "lilac")
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

/// A detached glass tab bar.
///
/// Icon-only at rest; the selected tab expands into a filled pill carrying
/// its label. Five icon-and-label stacks side by side is the default every
/// app ships, and at this width the labels are cramped and the highlight is
/// a grey smear. Showing the label only where it is needed buys room for
/// larger icons and makes the selection unmistakable.
///
/// Each tab owns an accent from the palette, so the pill is a colour rather
/// than a tint of the bar — it ties the bar to the same eight hues the
/// markets use.
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
        .padding(6)
        .background(Capsule().fill(Palette.tabBarFill.opacity(0.84)))
        .glass(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.32), radius: 20, y: 9)
        .padding(.horizontal, Layout.Space.l)
        .padding(.bottom, Layout.Space.s)
    }

    private func item(_ tab: RootView.Tab) -> some View {
        let isSelected = selection == tab
        let accent = tab.accent

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
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: isSelected ? 19 : 21, weight: .semibold))
                    .foregroundStyle(isSelected ? accent.onField : Palette.tabBarInk)

                if isSelected {
                    Text(tab.title)
                        .font(Allo.font(.semibold, size: 14, relativeTo: .caption))
                        .foregroundStyle(accent.onField)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(
                            .opacity.combined(with: .move(edge: .leading))
                        )
                }
            }
            .padding(.horizontal, isSelected ? 16 : 0)
            .frame(height: 48)
            // The pill sizes to its label; the remaining icons share what is
            // left. The other way round makes the selected tab dominate the
            // bar and squeezes the icons against each other.
            .frame(maxWidth: isSelected ? nil : .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(accent.screen)
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
/// Content scrolls under the status bar and under the floating tab bar,
/// which is what lets the colour field run to the edges — but without this
/// the clock collides with a headline and rows read straight through the
/// glass. The scrim dissolves content into the field instead of clipping it.
///
/// Drawn from the environment's own background colour so it works on every
/// theme, and it never takes touches.
struct ScrollScrim: View {
    enum Edge { case top, bottom }
    let edge: Edge

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: edge == .top
                ? [base.opacity(0.55), base.opacity(0.22), base.opacity(0)]
                : [base.opacity(0), base.opacity(0.18), base.opacity(0.45)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: edge == .top ? 56 : 96)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Black in both appearances: the themes are mid-to-dark, so darkening
    /// toward the edge reads as depth, while lightening would look like a
    /// smear of fog.
    private var base: Color { .black }
}

/// A full-bleed colour field.
///
/// Every screen sits on one of these. The colour reaches the very edges —
/// behind the status bar and under the tab bar — because a field that stops
/// short of an edge reads as a card, not as the screen.
struct ColourField: View {
    var colour: Color

    var body: some View {
        colour
            .ignoresSafeArea()
            .animation(Motion.standard, value: colour)
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
                        .foregroundStyle(ink.opacity(0.65))
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
