import SwiftUI
import PulseCore

/// Profile and settings.
///
/// Built from chunky cards rather than a `Form`, whose grouped-list chrome
/// (grey headers, inset rows) reads as a different app bolted on.
///
/// No appearance picker for now: the palette is designed against cream and
/// the app runs light. The stored setting is kept for when a dark theme is
/// designed, rather than offering a switch that does nothing.
struct ProfileView: View {
    private var theme: Palette.Theme { Palette.Tabs.profile }
    @Environment(AppEnvironment.self) private var environment
    @State private var showsConnect = false
    @State private var confirmingDisconnect = false
    @State private var stats: UserStats?

    private var ink: Color { theme.onField }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FieldHeader(title: "Profile", subtitle: nil, ink: ink)

                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.Space.xl) {
                        walletSection
                        if environment.session.address != nil { statsSection }
                        tradingSection
                        aboutSection
                        legalSection
                    }
                    .padding(.horizontal, Layout.gutter)
                    .padding(.bottom, Layout.Size.tabBarClearance)
                }
            }
            .background(ColourField())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsConnect) { SignInView() }
            .task { await loadStats() }
        }
    }

    // MARK: Building blocks

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.overline)
            .tracking(0.9)
            .foregroundStyle(Brand.inkTertiary)
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .fieldPanel(theme, radius: Layout.Radius.medium)
    }

    private func row<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(title)
                .font(Typography.bodyMedium)
                .foregroundStyle(ink)
            Spacer(minLength: Layout.Space.m)
            trailing()
        }
        .padding(.horizontal, Layout.Space.l)
        .frame(minHeight: 52)
    }

    private var divider: some View {
        Rectangle()
            .fill(Brand.hairline)
            .frame(height: 2)
            .padding(.leading, Layout.Space.l)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Brand.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Wallet

    @ViewBuilder
    private var walletSection: some View {
        VStack(alignment: .leading, spacing: Layout.Space.s) {
            sectionLabel("Account")

            panel {
                switch environment.session.state {
                case .signedOut:
                    HStack(alignment: .top, spacing: Layout.Space.s) {
                    VStack(alignment: .leading, spacing: Layout.Space.s) {
                        Text("No wallet connected")
                            .font(Typography.title3)
                            .foregroundStyle(ink)
                        Text("Browse markets freely. Sign in to place orders — a wallet is created for you.")
                            .font(Typography.footnote)
                            .foregroundStyle(Brand.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Sign in") { showsConnect = true }
                            .buttonStyle(.chunky(
                                Brand.ink, ink: .white, shadow: Color(hex: "0F1335"),
                                height: 48, fullWidth: false, font: Typography.buttonSmall
                            ))
                            .padding(.top, Layout.Space.xs)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Pip(pose: .hello, size: 84, shadow: nil)
                    }
                    .padding(Layout.Space.l)

                case .connecting:
                    progressRow("Connecting…")

                case .settingUp(let step):
                    // One-time setup, done for the user by Polymarket's
                    // relayer: no gas, no prompts.
                    VStack(alignment: .leading, spacing: Layout.Space.xs) {
                        progressRow(step.label).padding(.bottom, -Layout.Space.s)
                        Text("One-time setup. It's free and takes under a minute.")
                            .font(Typography.caption)
                            .foregroundStyle(Brand.inkSecondary)
                            .padding([.horizontal, .bottom], Layout.Space.l)
                    }

                case .walletOnly(let address), .ready(let address):
                    VStack(alignment: .leading, spacing: Layout.Space.m) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("TRADING WALLET")
                                    .font(Typography.overline)
                                    .tracking(0.8)
                                    .foregroundStyle(Brand.inkTertiary)
                                Text(EthereumAddress.short(EthereumAddress.checksummed(address)))
                                    .font(Typography.currency)
                                    .foregroundStyle(ink)
                            }
                            Spacer()
                            statusChip
                        }

                        if let balance = environment.session.availableBalance {
                            Text("\(Format.currency(balance)) available to trade")
                                .font(Typography.subheadlineMedium)
                                .foregroundStyle(ink)
                        }
                        if let value = environment.session.portfolioValue {
                            Text("Positions worth \(Format.currency(value))")
                                .font(Typography.footnote)
                                .foregroundStyle(Brand.inkSecondary)
                        }

                        if let error = environment.session.lastError {
                            HStack(alignment: .top, spacing: Layout.Space.s) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Palette.caution)
                                Text(error)
                                    .font(Typography.footnote)
                                    .foregroundStyle(ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button("Try again") {
                                Task { await environment.session.retrySetup() }
                            }
                            .buttonStyle(.chunky(
                                Brand.ink, ink: .white, shadow: Color(hex: "0F1335"),
                                height: 44, fullWidth: false, font: Typography.buttonSmall
                            ))
                        }

                        // Funds go to the trading wallet itself.
                        Text("To add funds, send pUSD on Polygon to this address.")
                            .font(Typography.caption)
                            .foregroundStyle(Brand.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: Layout.Space.s) {
                            Button("Copy address") {
                                #if canImport(UIKit)
                                UIPasteboard.general.string =
                                    EthereumAddress.checksummed(address)
                                #endif
                                Haptics.selection(enabled: environment.settings.hapticsEnabled)
                            }
                            .buttonStyle(.pill(.secondary, tint: ink))

                            Button("Sign out") { confirmingDisconnect = true }
                                .buttonStyle(.pill(.quiet, tint: ink))
                        }
                        .font(Typography.footnote)
                    }
                    .padding(Layout.Space.l)
                }
            }

            footnote("Polygon network · pUSD settlement")
        }
        .confirmationDialog(
            "Sign out?",
            isPresented: $confirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await environment.session.signOut() }
            }
            Button("Stay signed in", role: .cancel) {}
        } message: {
            Text("""
                Your wallet and positions stay exactly as they are — signing \
                back in with the same account restores them.
                """)
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: Layout.Space.s) {
            ProgressView().tint(ink)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Brand.inkSecondary)
            Spacer()
        }
        .padding(Layout.Space.l)
    }

    private var statusChip: some View {
        let ready = environment.session.canTrade
        return Label(
            ready ? "Ready" : "Not ready",
            systemImage: ready ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        )
        .font(Typography.caption)
        .foregroundStyle(ready ? Brand.yesDeep : Palette.caution)
        .padding(.horizontal, Layout.Space.m)
        .padding(.vertical, 6)
        .background(Capsule().fill(ready ? Brand.yesTint : Brand.cardSunken))
    }

    // MARK: Stats

    @ViewBuilder
    private var statsSection: some View {
        if let stats, let pnl = stats.allTimePnl {
            VStack(alignment: .leading, spacing: Layout.Space.s) {
                sectionLabel("Lifetime")
                panel {
                    HStack(spacing: Layout.Space.l) {
                        StatTile(label: "Trades", value: "\(stats.trades ?? 0)", ink: ink)
                        StatTile(
                            label: "Volume",
                            value: Format.compactCurrency(pnl.volume),
                            ink: ink
                        )
                        StatTile(
                            label: "Realised",
                            value: Format.currency(pnl.realizedPnl ?? 0, showSign: true),
                            ink: ink,
                            tint: (pnl.realizedPnl ?? 0) >= 0 ? Palette.yes : Palette.no
                        )
                    }
                    .padding(Layout.Space.l)
                }
            }
        }
    }

    // MARK: Settings

    private var tradingSection: some View {
        @Bindable var settings = environment.settings
        return VStack(alignment: .leading, spacing: Layout.Space.s) {
            sectionLabel("Trading")
            panel {
                row("Confirm before trading") {
                    Toggle("", isOn: $settings.confirmBeforeTrading)
                        .labelsHidden()
                        .tint(Brand.ink)
                }
                divider
                row("Haptic feedback") {
                    Toggle("", isOn: $settings.hapticsEnabled)
                        .labelsHidden()
                        .tint(Brand.ink)
                }
                divider
                VStack(alignment: .leading, spacing: Layout.Space.xs) {
                    HStack {
                        Text("Max price impact")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(ink)
                        Spacer()
                        Text(Format.percentChange(settings.slippageLimit))
                            .font(Typography.currency)
                            .foregroundStyle(ink)
                    }
                    Slider(value: $settings.slippageLimit, in: 0.01...0.25, step: 0.01)
                        .tint(theme.control)
                }
                .padding(.horizontal, Layout.Space.l)
                .padding(.vertical, Layout.Space.m)
            }
            footnote("""
                Market orders are blocked when walking the book would move the \
                price by more than this. Lower is safer on thin markets.
                """)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Layout.Space.s) {
            sectionLabel("About")
            panel {
                row("Version") {
                    Text(Self.appVersion)
                        .font(Typography.callout)
                        .foregroundStyle(Brand.inkSecondary)
                }
                divider
                row("Builder code") {
                    Text(environment.configuration.builderCode == nil ? "Not set" : "Configured")
                        .font(Typography.callout)
                        .foregroundStyle(Brand.inkSecondary)
                }
                divider
                Link(destination: URL(string: "https://docs.polymarket.com")!) {
                    row("Polymarket documentation") {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Brand.inkSecondary)
                    }
                }
            }
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: Layout.Space.s) {
            sectionLabel("Legal")
            RiskNotice(ink: ink)
            footnote("""
                Pulse is an independent client for Polymarket's public API. It \
                is not affiliated with, endorsed by, or operated by Polymarket. \
                Market availability and trading eligibility depend on your \
                jurisdiction and account status, which Polymarket determines — \
                this app does not work around those controls.
                """)
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(version ?? "1.0") (\(build ?? "1"))"
    }

    private func loadStats() async {
        guard let address = environment.session.address else { return }
        stats = try? await environment.data.userStats(user: address)
    }
}
