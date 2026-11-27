import SwiftUI
import PulseCore

@main
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

/// The tab shell.
///
/// Five tabs matching the main things someone does here: find a market, search
/// for one, check what they hold, review what happened, and manage the account.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: Tab = .home

    enum Tab: Hashable {
        case home, explore, portfolio, activity, profile

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
            case .home: "house"
            case .explore: "magnifyingglass"
            case .portfolio: "chart.pie"
            case .activity: "clock.arrow.circlepath"
            case .profile: "person"
            }
        }

        var selectedIcon: String {
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
        TabView(selection: $selection) {
            HomeView()
                .tag(Tab.home)
                .tabItem { Label(Tab.home.title, systemImage: Tab.home.icon) }

            ExploreView()
                .tag(Tab.explore)
                .tabItem { Label(Tab.explore.title, systemImage: Tab.explore.icon) }

            PortfolioView()
                .tag(Tab.portfolio)
                .tabItem { Label(Tab.portfolio.title, systemImage: Tab.portfolio.icon) }

            ActivityView()
                .tag(Tab.activity)
                .tabItem { Label(Tab.activity.title, systemImage: Tab.activity.icon) }

            ProfileView()
                .tag(Tab.profile)
                .tabItem { Label(Tab.profile.title, systemImage: Tab.profile.icon) }
        }
        .tint(Palette.ink)
    }
}

// MARK: - Shared screen scaffolding

/// Standard screen background.
struct ScreenBackground: View {
    var body: some View {
        Palette.canvas.ignoresSafeArea()
    }
}

/// Wraps content in the app's standard list geometry: canvas background,
/// consistent gutter, and clearance for the floating tab bar.
struct ScreenScroll<Content: View>: View {
    var spacing: CGFloat = Layout.Space.m
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: spacing) {
                content()
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, Layout.Space.s)
            .padding(.bottom, Layout.Space.xl)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(ScreenBackground())
    }
}
