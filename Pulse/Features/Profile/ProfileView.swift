import SwiftUI
import PulseCore

struct ProfileView: View {
    private var theme: Palette.Theme { Palette.Tabs.profile }
    @Environment(AppEnvironment.self) private var environment
    @State private var showsConnect = false
    @State private var confirmingDisconnect = false
    @State private var stats: UserStats?

    var body: some View {
        NavigationStack {
            Form {
                walletSection
                if environment.session.address != nil { statsSection }
                tradingSection
                appearanceSection
                aboutSection
                legalSection
            }
            .scrollContentBackground(.hidden)
            .background(ColourField(colour: theme.screen))
            .navigationTitle("Profile")
            .sheet(isPresented: $showsConnect) { ConnectWalletSheet() }
            .task { await loadStats() }
        }
    }

    // MARK: Wallet

    @ViewBuilder
    private var walletSection: some View {
        Section {
            switch environment.session.state {
            case .signedOut:
                VStack(alignment: .leading, spacing: Layout.Space.s) {
                    Text("No wallet connected")
                        .font(Typography.headline)
                    Text("Browse markets freely. Connect a wallet to place orders.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    Button("Connect wallet") { showsConnect = true }
                        .buttonStyle(.pill(.primary))
                        .padding(.top, Layout.Space.xs)
                }
                .padding(.vertical, Layout.Space.xs)

            case .connecting:
                HStack {
                    ProgressView()
                    Text("Connecting…").foregroundStyle(Palette.inkSecondary)
                }

            case .walletOnly(let address), .ready(let address):
                VStack(alignment: .leading, spacing: Layout.Space.s) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wallet").font(Typography.caption)
                                .foregroundStyle(Palette.inkTertiary)
                            Text(EthereumAddress.short(EthereumAddress.checksummed(address)))
                                .font(Typography.headline.monospacedDigit())
                        }
                        Spacer()
                        if environment.session.canTrade {
                            Label("Ready", systemImage: "checkmark.seal.fill")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.up)
                        } else {
                            Label("Needs signing", systemImage: "exclamationmark.triangle")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.caution)
                        }
                    }

                    if let value = environment.session.portfolioValue {
                        Text("Positions worth \(Format.currency(value))")
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }

                    Button("Copy address") {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = EthereumAddress.checksummed(address)
                        #endif
                        Haptics.selection(enabled: environment.settings.hapticsEnabled)
                    }
                    .font(Typography.footnote)
                }
                .padding(.vertical, Layout.Space.xs)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Polygon network · USDC settlement")
        }

        if environment.session.address != nil {
            Section {
                Button("Disconnect wallet", role: .destructive) {
                    confirmingDisconnect = true
                }
                .confirmationDialog(
                    "Disconnect this wallet?",
                    isPresented: $confirmingDisconnect,
                    titleVisibility: .visible
                ) {
                    Button("Disconnect", role: .destructive) {
                        Task { await environment.session.disconnect() }
                    }
                    Button("Keep connected", role: .cancel) {}
                } message: {
                    Text("""
                        The key is removed from this device's Keychain. Your \
                        positions stay on-chain and you can reconnect any time.
                        """)
                }
            }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        if let stats, let pnl = stats.allTimePnl {
            Section("Lifetime") {
                LabeledContent("Trades", value: "\(stats.trades ?? 0)")
                LabeledContent("Volume", value: Format.compactCurrency(pnl.volume))
                LabeledContent("Realised P&L") {
                    Text(Format.currency(pnl.realizedPnl ?? 0, showSign: true))
                        .foregroundStyle((pnl.realizedPnl ?? 0) >= 0 ? Palette.up : Palette.down)
                }
                if let biggest = stats.biggestWin, biggest > 0 {
                    LabeledContent("Biggest win", value: Format.currency(biggest))
                }
            }
        }
    }

    // MARK: Settings

    private var tradingSection: some View {
        @Bindable var settings = environment.settings
        return Section {
            Toggle("Confirm before trading", isOn: $settings.confirmBeforeTrading)
            Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)

            VStack(alignment: .leading, spacing: Layout.Space.xs) {
                HStack {
                    Text("Max price impact")
                    Spacer()
                    Text(Format.percentChange(settings.slippageLimit))
                        .foregroundStyle(Palette.inkSecondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.slippageLimit, in: 0.01...0.25, step: 0.01)
            }
        } header: {
            Text("Trading")
        } footer: {
            Text("""
                Market orders are blocked when walking the book would move the \
                price more than this. Lower is safer on thin markets.
                """)
        }
    }

    private var appearanceSection: some View {
        @Bindable var settings = environment.settings
        return Section("Appearance") {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(SettingsStore.Appearance.allCases) { appearance in
                    Text(appearance.displayName).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.appVersion)
            LabeledContent("Builder code") {
                Text(environment.configuration.builderCode == nil ? "Not set" : "Configured")
                    .foregroundStyle(Palette.inkSecondary)
            }
            Link(
                "Polymarket documentation",
                destination: URL(string: "https://docs.polymarket.com")!
            )
        }
    }

    private var legalSection: some View {
        Section {
            RiskNotice()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            Text("""
                Pulse is an independent client for Polymarket's public API. It \
                is not affiliated with, endorsed by, or operated by Polymarket. \
                Market availability and trading eligibility depend on your \
                jurisdiction and account status, which Polymarket determines — \
                this app does not work around those controls.
                """)
            .font(Typography.caption)
            .foregroundStyle(Palette.inkSecondary)
        } header: {
            Text("Legal")
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

// MARK: - Connect

/// Wallet import.
///
/// A deliberately plain screen with an explicit warning. Pasting a private key
/// is the mechanism Polymarket's own API integrations use, but it is also the
/// riskiest thing a person can do in this app, so the screen says exactly
/// where the key goes and what the app will and will not do with it.
struct ConnectWalletSheet: View {
    private var theme: Palette.Theme { Palette.Tabs.profile }
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var privateKey = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.Space.l) {
                    VStack(alignment: .leading, spacing: Layout.Space.s) {
                        Text("Connect a wallet")
                            .font(Typography.title2)
                        Text("""
                            Pulse signs orders locally with your key. Enter the \
                            private key of a Polygon wallet funded with USDC on \
                            Polymarket.
                            """)
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                    }

                    SecureField("Private key (0x…)", text: $privateKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Typography.body.monospaced())
                        .padding(Layout.Space.m)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                                .fill(Palette.surfaceRaised)
                        )

                    VStack(alignment: .leading, spacing: Layout.Space.s) {
                        bullet("Stored in the iOS Keychain, locked to this device and excluded from backups.")
                        bullet("Never sent to Pulse, Polymarket, or any server — only signatures leave the device.")
                        bullet("Use a wallet funded only for trading. Never your main wallet.")
                    }
                    .padding(Layout.Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                            .fill(Palette.caution.opacity(0.1))
                    )

                    if let error = environment.session.lastError {
                        Text(error)
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.danger)
                    }

                    Button {
                        Task {
                            isWorking = true
                            await environment.session.connect(privateKeyHex: privateKey)
                            isWorking = false
                            if environment.session.canTrade {
                                privateKey = ""
                                dismiss()
                            }
                        }
                    } label: {
                        if isWorking {
                            ProgressView().tint(Palette.canvas)
                        } else {
                            Text("Connect")
                        }
                    }
                    .buttonStyle(.pill(.primary, fullWidth: true))
                    .disabled(privateKey.isEmpty || isWorking)
                }
                .padding(Layout.gutter)
            }
            .background(ColourField(colour: theme.screen))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Layout.Space.s) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.caution)
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
