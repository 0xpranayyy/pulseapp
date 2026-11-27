import SwiftUI
import PulseCore

@main
@MainActor
struct PulseApp: App {
    @State private var environment = AppEnvironment()

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
            case .activity: "clock.arrow.circlepath"
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

            FloatingTabBar(selection: $selection)
        }
        .overlay(alignment: .top) { ScrollScrim(edge: .top) }
        .overlay(alignment: .bottom) { ScrollScrim(edge: .bottom) }
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

/// A detached glass capsule tab bar.
///
/// Glass rather than an opaque bar: it floats over a saturated colour field
/// and the field should keep running underneath it. The selected item carries
/// a filled pill, which is the clearest state signal at this size and the
/// motif the references use.
struct FloatingTabBar: View {
    @Binding var selection: RootView.Tab

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RootView.Tab.allCases) { tab in
                item(tab)
            }
        }
        .padding(5)
        .glass(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
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
                withAnimation(Motion.quick) { selection = tab }
            }
            Haptics.selection(enabled: environment.settings.hapticsEnabled)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Palette.tabBarSelectedInk : Palette.tabBarInk)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Palette.tabBarSelectedFill)
                        .matchedGeometryEffect(id: "tab", in: pill)
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
                ? [base.opacity(0.92), base.opacity(0.55), base.opacity(0)]
                : [base.opacity(0), base.opacity(0.55), base.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: edge == .top ? 64 : 120)
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
