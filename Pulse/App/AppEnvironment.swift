import Foundation
import SwiftUI
import Observation
import os
import PulseCore

/// The app's composition root.
///
/// Every service is constructed here and injected downward, so no view ever
/// reaches for a singleton and every screen can be previewed or tested with
/// substitutes. Secrets live only in `secretStore`; nothing else holds key
/// material.
@MainActor
@Observable
final class AppEnvironment {
    let configuration: PulseConfiguration
    let gamma: GammaService
    let data: DataService
    let clob: ClobService
    let authenticator: ClobAuthenticator
    let marketSocket: MarketSocket
    let secretStore: any SecretStore

    private(set) var auth: PrivyAuth
    /// WalletConnect, for trading an existing Polymarket account from the
    /// wallet app it was created with.
    let walletConnection: WalletConnection
    private(set) var session: SessionStore
    private(set) var watchlist: WatchlistStore
    private(set) var settings: SettingsStore
    let trading: TradingService

    init(
        configuration: PulseConfiguration = .fromEnvironment(),
        secretStore: any SecretStore = AppEnvironment.defaultSecretStore()
    ) {
        self.configuration = configuration
        self.secretStore = secretStore

        let authenticator = ClobAuthenticator()
        self.authenticator = authenticator
        self.gamma = GammaService()
        self.data = DataService()
        self.clob = ClobService(authenticator: authenticator, configuration: configuration)
        self.marketSocket = MarketSocket()

        self.watchlist = WatchlistStore()
        self.settings = SettingsStore()

        let auth = PrivyAuth(configuration: configuration)
        self.auth = auth
        let walletConnection = WalletConnection(
            projectId: Self.infoValue("ReownProjectId", placeholder: "$(REOWN_PROJECT_ID)"),
            keychainGroup: Self.infoValue("PulseKeychainGroup", placeholder: "$(DEVELOPMENT_TEAM).$(PRODUCT_BUNDLE_IDENTIFIER)")
                .flatMap { $0.hasPrefix(".") ? nil : $0 },
            appURL: configuration.relayURL.flatMap { url in url.host.map { "https://\($0)" } }
                ?? "https://localhost"
        )
        self.walletConnection = walletConnection
        // Gasless wallet setup goes through the Pulse relay, authenticated
        // with the user's Privy token. Without a relay URL the app still
        // browses; trading setup explains what is missing.
        let relayer = configuration.relayURL.map { url in
            RelayerClient(baseURL: url) { [auth] in try await auth.accessToken() }
        }
        let session = SessionStore(
            secretStore: secretStore,
            authenticator: authenticator,
            clob: clob,
            data: data,
            gamma: gamma,
            auth: auth,
            relayer: relayer,
            walletConnection: walletConnection
        )
        self.session = session

        // `session` is a @MainActor type and therefore Sendable, so the
        // signer closure can safely cross into the TradingService actor.
        self.trading = TradingService(
            clob: self.clob,
            configuration: configuration
        ) {
            try await session.signingContext()
        }
    }

    /// An Info.plist string, or nil when empty or still its xcconfig placeholder.
    static func infoValue(_ key: String, placeholder: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != placeholder else { return nil }
        return trimmed
    }

    private static func defaultSecretStore() -> any SecretStore {
        #if canImport(Security)
        return KeychainStore()
        #else
        return InMemorySecretStore()
        #endif
    }
}

// MARK: - Configuration

extension PulseConfiguration {
    /// Reads the builder code from the app's Info.plist, which is populated
    /// from an xcconfig that is **not** committed.
    ///
    /// A builder code is a public attribution identifier, not a secret, so
    /// shipping it in the bundle is appropriate — unlike a private key, which
    /// never goes near the bundle. See `docs/CONFIGURATION.md`.
    static func fromEnvironment() -> PulseConfiguration {
        let bundle = Bundle.main
        let code = (bundle.object(forInfoDictionaryKey: "PolymarketBuilderCode") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bps = bundle.object(forInfoDictionaryKey: "PolymarketBuilderFeeBps") as? String

        func value(_ key: String, placeholder: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An unset xcconfig variable reaches Info.plist as its own
            // placeholder, which must not be mistaken for a real value.
            guard !trimmed.isEmpty, trimmed != placeholder else { return nil }
            return trimmed
        }

        return PulseConfiguration(
            builderCode: (code?.isEmpty == false && code != "$(POLYMARKET_BUILDER_CODE)") ? code : nil,
            builderFeeBps: bps.flatMap(Int.init),
            privyAppId: value("PrivyAppId", placeholder: "$(PRIVY_APP_ID)"),
            privyClientId: value("PrivyClientId", placeholder: "$(PRIVY_CLIENT_ID)"),
            relayURL: value("PulseRelayURL", placeholder: "$(PULSE_RELAY_URL)")
                .flatMap(URL.init(string:))
                .flatMap { $0.scheme == "https" ? $0 : nil }
        )
    }
}

// MARK: - Session

/// The trading session.
///
/// Identity comes from Privy; the session owns what Privy does not.
///
/// **The trading account.** Polymarket trades from a smart *Deposit Wallet*
/// owned by the user's key, not from the key itself (plain-wallet trading is
/// allowlist-only). A new Pulse user's Deposit Wallet is deployed and
/// approved for trading gas-free through Polymarket's relayer, via the Pulse
/// relay server that holds the Builder API credentials. The Privy wallet
/// signs; the Deposit Wallet holds funds and positions, so `address` — what
/// every screen queries for positions and history — is the Deposit Wallet.
///
/// **The CLOB credentials**, derived once from a signature by the Privy
/// wallet and cached in the Keychain.
///
/// Setup runs once per wallet and is resumable: a step that fails leaves the
/// session browse-only with the reason, and `retrySetup()` picks up from
/// where it stopped.
///
/// **Or an existing Polymarket account**, connected from the wallet app it
/// was created with (WalletConnect). That account is already deployed and
/// approved by polymarket.com, so it only needs CLOB credentials; every
/// signature is approved in the wallet app.
@MainActor
@Observable
final class SessionStore {
    enum SetupStep: Equatable {
        case creatingWallet, approving, connectingExchange

        var label: String {
            switch self {
            case .creatingWallet: "Creating your trading wallet…"
            case .approving: "Enabling trading…"
            case .connectingExchange: "Connecting to Polymarket…"
            }
        }
    }

    enum State: Equatable {
        case signedOut
        case connecting
        case settingUp(SetupStep)
        /// Account known, but not (yet) able to trade.
        case walletOnly(address: String)
        case ready(address: String)

        var address: String? {
            switch self {
            case .walletOnly(let a), .ready(let a): a
            case .signedOut, .connecting, .settingUp: nil
            }
        }

        var canTrade: Bool { if case .ready = self { true } else { false } }
    }

    private(set) var state: State = .signedOut
    private(set) var lastError: String?
    /// The account orders are placed for. Set as soon as it is known, before
    /// setup finishes, so its funding address can be shown.
    private(set) var account: TradingAccount?

    /// Spendable pUSD. `nil` means "not yet known" and renders as a dash,
    /// never as $0.
    private(set) var availableBalance: Double?
    private(set) var portfolioValue: Double?

    private let secretStore: any SecretStore
    private let authenticator: ClobAuthenticator
    private let clob: ClobService
    private let data: DataService
    private let gamma: GammaService
    private let auth: PrivyAuth
    private let relayer: RelayerClient?
    private let walletConnection: WalletConnection

    /// Where the signing key lives.
    enum Source: Equatable {
        case none
        /// A Pulse wallet: Privy holds the key, Pulse set up its Deposit Wallet.
        case privy
        /// An existing Polymarket account, signed for in a wallet app.
        case walletApp(address: String)
    }
    private(set) var source: Source = .none
    var isWalletApp: Bool { if case .walletApp = source { true } else { false } }

    /// The signer the session last adopted, so the launch-time restore and
    /// the auth-change observer cannot both run setup for it.
    private var adoptedSigner: String?

    private static let log = Logger(subsystem: "com.pulse.polymarket", category: "trading")

    init(
        secretStore: any SecretStore,
        authenticator: ClobAuthenticator,
        clob: ClobService,
        data: DataService,
        gamma: GammaService,
        auth: PrivyAuth,
        relayer: RelayerClient?,
        walletConnection: WalletConnection
    ) {
        self.secretStore = secretStore
        self.authenticator = authenticator
        self.clob = clob
        self.data = data
        self.gamma = gamma
        self.auth = auth
        self.relayer = relayer
        self.walletConnection = walletConnection
        walletConnection.onConnect = { [weak self] address in
            guard let self else { return }
            Task { await self.useWalletApp(address: address) }
        }
    }

    var address: String? { state.address }
    var canTrade: Bool { state.canTrade }
    var isSettingUp: Bool { if case .settingUp = state { true } else { false } }

    /// Restores the Privy session, then the trading account behind it.
    func restore() async {
        // A wallet app still connected from last time takes precedence.
        if let address = walletConnection.connectedAddress {
            await useWalletApp(address: address)
            return
        }
        await auth.restore()
        await adoptWallet()
    }

    /// Brings the session in line with Privy's current wallet.
    ///
    /// Called after sign-in and after sign-out, so the two never drift: a
    /// signed-out Privy must not leave stale CLOB credentials behind that
    /// would let the UI believe it can still trade.
    func adoptWallet() async {
        // Privy is irrelevant while a wallet app is connected.
        if isWalletApp { return }
        let current = auth.state.address
        // Already adopted (or being adopted): nothing to do. Set before the
        // first await so a concurrent call sees it.
        if let current, current == adoptedSigner { return }
        adoptedSigner = current

        guard let signer = current else {
            await reset()
            return
        }
        source = .privy
        await setUpDepositWallet(signer: signer)
    }

    /// Runs setup again after a failure.
    func retrySetup() async {
        if case .walletApp(let address) = source {
            await useWalletApp(address: address)
            return
        }
        adoptedSigner = nil
        await adoptWallet()
    }

    private func reset() async {
        await authenticator.update(credentials: nil, signerAddress: nil)
        source = .none
        state = .signedOut
        account = nil
        lastError = nil
        availableBalance = nil
        portfolioValue = nil
    }

    // MARK: Existing account (wallet app)

    /// Connects the Polymarket account that `address` controls.
    ///
    /// The account's wallet comes from its public profile; its type is read
    /// off the address. Only accounts the wallet owns directly qualify: a
    /// Safe (wallet-app sign-ups before May 2026) or a Deposit Wallet.
    func useWalletApp(address: String) async {
        source = .walletApp(address: address)
        lastError = nil
        state = .connecting

        let wallet: String?
        do {
            wallet = try await gamma.accountWallet(forSigner: address)
        } catch {
            fail("Couldn't look up your Polymarket account. Check your connection and try again.", address: nil)
            return
        }
        guard let wallet else {
            fail("No Polymarket account uses this wallet. Sign in to Polymarket with it first, or use a Pulse wallet.", address: nil)
            return
        }
        guard let type = WalletDerivation.classify(signer: address, wallet: wallet),
              type == .depositWallet || type == .polyGnosisSafe || type == .eoa else {
            fail("This Polymarket account isn't controlled directly by this wallet, so Pulse can't trade it.", address: nil)
            return
        }

        let account = TradingAccount(signer: address, wallet: wallet, type: type)
        self.account = account
        state = .settingUp(.connectingExchange)
        await connectExchange(account, refreshAllowances: false)
    }

    // MARK: Setup

    private func setUpDepositWallet(signer: String) async {
        lastError = nil
        var record = (try? secretStore.getCodable(WalletSetup.self, for: WalletSetup.key(signer)))
            ?? WalletSetup(wallet: nil, approved: false)

        guard let derived = record.wallet ?? WalletDerivation.depositWallet(signer: signer) else {
            fail("Couldn't work out this account's trading wallet.", address: nil)
            return
        }
        var account = TradingAccount(signer: signer, wallet: derived, type: .depositWallet)
        self.account = account
        state = .walletOnly(address: account.wallet)

        if !record.approved {
            guard let relayer else {
                fail("Trading isn't set up in this build yet: the Pulse relay server isn't configured.",
                     address: account.wallet)
                return
            }
            do {
                let signingKey = try auth.signer()

                state = .settingUp(.creatingWallet)
                let deployed = try await relayer.isDeployed(depositWallet: account.wallet)
                if !deployed {
                    let id = try await relayer.deployDepositWallet(signer: signer)
                    let tx = try await relayer.waitForConfirmation(id: id)
                    // Trust the relayer's address over the derivation if they
                    // ever disagree, and say so in the log.
                    if let deployed = tx.proxyAddress, deployed.lowercased() != account.wallet.lowercased() {
                        let derivedWallet = account.wallet
                        Self.log.error("Deposit Wallet derived \(derivedWallet, privacy: .public) but deployed \(deployed, privacy: .public)")
                        account = TradingAccount(signer: signer, wallet: deployed, type: .depositWallet)
                        self.account = account
                    }
                }
                record = WalletSetup(wallet: account.wallet, approved: false)
                try? secretStore.setCodable(record, for: WalletSetup.key(signer))

                state = .settingUp(.approving)
                let id = try await relayer.executeBatch(
                    account: account,
                    calls: TradingApprovals.calls,
                    metadata: "Enable trading on Pulse",
                    signer: signingKey
                )
                try await relayer.waitForConfirmation(id: id)
                record = WalletSetup(wallet: account.wallet, approved: true)
                try? secretStore.setCodable(record, for: WalletSetup.key(signer))
            } catch {
                Self.log.error("Wallet setup failed: \(String(describing: error), privacy: .public)")
                fail(Self.setupMessage(for: error), address: account.wallet)
                return
            }
        }

        state = .settingUp(.connectingExchange)
        await connectExchange(account, refreshAllowances: true)
    }

    /// Derives (or restores) the CLOB credentials for the account's signer
    /// and refreshes the exchange's view of its balance and approvals.
    private func connectExchange(_ account: TradingAccount, refreshAllowances: Bool) async {
        do {
            if let stored = try? secretStore.getCodable(StoredCredentials.self, for: SecretKey.clobCredentials),
               stored.address.lowercased() == account.signer.lowercased() {
                await authenticator.update(credentials: stored.credentials, signerAddress: account.signer)
            } else {
                let credentials = try await clob.deriveOrCreateCredentials(signer: try currentSigner())
                try? secretStore.setCodable(
                    StoredCredentials(address: account.signer, credentials: credentials),
                    for: SecretKey.clobCredentials
                )
                await authenticator.update(credentials: credentials, signerAddress: account.signer)
            }
            if refreshAllowances {
                try? await clob.updateBalanceAllowance(signatureType: account.type)
            }
            state = .ready(address: account.wallet)
            lastError = nil
        } catch {
            Self.log.error("CLOB connection failed: \(String(describing: error), privacy: .public)")
            fail((error as? APIError)?.userMessage ?? "Couldn't connect this wallet to Polymarket.",
                 address: account.wallet)
            return
        }
        await refreshBalances()
    }

    private func fail(_ message: String, address: String?) {
        lastError = message
        state = address.map { .walletOnly(address: $0) } ?? .signedOut
    }

    private static func setupMessage(for error: Error) -> String {
        switch error {
        case RelayerClient.RelayerError.timedOut:
            "Polymarket is taking a while to set up your wallet. Try again in a minute."
        case RelayerClient.RelayerError.failed:
            "Polymarket couldn't set up your wallet. Try again."
        case let api as APIError:
            api.userMessage
        default:
            "Couldn't set up your trading wallet. Try again."
        }
    }

    // MARK: Sign out and balances

    func signOut() async {
        try? secretStore.remove(SecretKey.clobCredentials)
        if isWalletApp {
            await walletConnection.disconnect()
            await reset()
            return
        }
        await auth.signOut()
        await adoptWallet()
    }

    /// The key that signs for the current source.
    private func currentSigner() throws -> EthereumSigner {
        if case .walletApp(let address) = source {
            return WalletAppSigner(address: address, connection: walletConnection)
        }
        return try auth.signer()
    }

    func refreshBalances() async {
        guard let account else { return }
        portfolioValue = try? await data.portfolioValue(user: account.wallet)
        if canTrade {
            availableBalance = try? await clob.collateralBalance(signatureType: account.type)
        }
    }

    /// Supplies the signer and account to `TradingService` at submission time.
    nonisolated func signingContext() async throws
        -> (signer: EthereumSigner, account: TradingAccount) {
        try await MainActor.run {
            guard self.canTrade, let account = self.account else {
                throw TradingService.TradingError.notAuthenticated
            }
            return (try self.currentSigner(), account)
        }
    }
}

/// How far a signer's Deposit Wallet setup got, so it is never repeated.
private struct WalletSetup: Codable {
    let wallet: String?
    let approved: Bool

    static func key(_ signer: String) -> String {
        "pulse.wallet.setup.\(signer.lowercased())"
    }
}

/// CLOB credentials bound to the wallet that derived them.
private struct StoredCredentials: Codable {
    let address: String
    let credentials: ClobCredentials
}

// MARK: - Watchlist

/// Locally stored favourites.
///
/// Deliberately device-local: syncing a watchlist would mean an account
/// system the app does not have, and silently uploading what someone watches
/// is not a trade worth making for convenience.
@MainActor
@Observable
final class WatchlistStore {
    private(set) var eventIds: Set<String> = []
    private let defaultsKey = "pulse.watchlist.eventIds"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: defaultsKey) as? [String] {
            eventIds = Set(stored)
        }
    }

    func contains(_ id: String) -> Bool { eventIds.contains(id) }

    func toggle(_ id: String) {
        if eventIds.contains(id) { eventIds.remove(id) } else { eventIds.insert(id) }
        defaults.set(Array(eventIds), forKey: defaultsKey)
    }
}

// MARK: - Settings

@MainActor
@Observable
final class SettingsStore {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "pulse.appearance") }
    }

    /// Maximum tolerated price impact on a market order, as a fraction.
    var slippageLimit: Double {
        didSet { defaults.set(slippageLimit, forKey: "pulse.slippageLimit") }
    }

    /// Require a confirmation step before submitting any order.
    var confirmBeforeTrading: Bool {
        didSet { defaults.set(confirmBeforeTrading, forKey: "pulse.confirmBeforeTrading") }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "pulse.haptics") }
    }

    /// False until onboarding has been completed or skipped.
    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: "pulse.hasOnboarded") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: "pulse.appearance") ?? Appearance.system.rawValue
        self.appearance = Appearance(rawValue: stored) ?? .system
        let slippage = defaults.double(forKey: "pulse.slippageLimit")
        self.slippageLimit = slippage > 0 ? slippage : 0.05
        self.confirmBeforeTrading = defaults.object(forKey: "pulse.confirmBeforeTrading") as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: "pulse.haptics") as? Bool ?? true
        self.hasOnboarded = defaults.bool(forKey: "pulse.hasOnboarded")
    }
}

// MARK: - Haptics

/// Haptics for events with real consequences — an order submitted, an order
/// rejected — and for nothing else. Haptics on scroll or selection become
/// noise and get the whole app silenced.
@MainActor
enum Haptics {
    static func success(enabled: Bool) {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning(enabled: Bool) {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    static func error(enabled: Bool) {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    static func selection(enabled: Bool) {
        #if canImport(UIKit)
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
