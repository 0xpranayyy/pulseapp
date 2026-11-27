import Foundation
import SwiftUI
import Observation
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
        let session = SessionStore(
            secretStore: secretStore,
            authenticator: authenticator,
            clob: clob,
            data: data,
            auth: auth
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
            privyClientId: value("PrivyClientId", placeholder: "$(PRIVY_CLIENT_ID)")
        )
    }
}

// MARK: - Session

/// The trading session.
///
/// Identity and the wallet now come from Privy; this type owns what Privy
/// does not — the CLOB's own API credentials, which are derived once from a
/// wallet signature and then cached in the Keychain.
///
/// Three states matter to the UI: signed out (browse only), signed in but
/// without CLOB credentials (one signature away), and ready to trade.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case signedOut
        case connecting
        /// Wallet known, but no CLOB credentials yet.
        case walletOnly(address: String)
        case ready(address: String)

        var address: String? {
            switch self {
            case .walletOnly(let a), .ready(let a): a
            case .signedOut, .connecting: nil
            }
        }

        var canTrade: Bool { if case .ready = self { true } else { false } }
    }

    private(set) var state: State = .signedOut
    private(set) var lastError: String?

    /// Spendable USDC. `nil` means "not yet known" and renders as a dash,
    /// never as $0.
    private(set) var availableBalance: Double?
    private(set) var portfolioValue: Double?

    private let secretStore: any SecretStore
    private let authenticator: ClobAuthenticator
    private let clob: ClobService
    private let data: DataService
    private let auth: PrivyAuth

    init(
        secretStore: any SecretStore,
        authenticator: ClobAuthenticator,
        clob: ClobService,
        data: DataService,
        auth: PrivyAuth
    ) {
        self.secretStore = secretStore
        self.authenticator = authenticator
        self.clob = clob
        self.data = data
        self.auth = auth
    }

    var address: String? { state.address }
    var canTrade: Bool { state.canTrade }

    /// Restores the Privy session, then the CLOB credentials derived from it.
    func restore() async {
        await auth.restore()
        await adoptWallet()
    }

    /// Brings the session in line with Privy's current wallet.
    ///
    /// Called after sign-in and after sign-out, so the two never drift: a
    /// signed-out Privy must not leave stale CLOB credentials behind that
    /// would let the UI believe it can still trade.
    func adoptWallet() async {
        guard let address = auth.state.address else {
            await authenticator.update(credentials: nil, signerAddress: nil)
            state = .signedOut
            availableBalance = nil
            portfolioValue = nil
            return
        }

        state = .walletOnly(address: address)

        // Credentials are per-wallet, so a different wallet must not reuse
        // the previous one's.
        if let stored = try? secretStore.getCodable(
            StoredCredentials.self, for: SecretKey.clobCredentials
        ), stored.address.lowercased() == address.lowercased() {
            await authenticator.update(
                credentials: stored.credentials, signerAddress: address
            )
            state = .ready(address: address)
        } else {
            await deriveCredentials()
        }

        await refreshBalances()
    }

    /// Exchanges one wallet signature for CLOB API credentials.
    ///
    /// Signing happens inside Privy, so no key material passes through the
    /// app at any point.
    func deriveCredentials() async {
        guard let address = auth.state.address else { return }
        state = .connecting
        lastError = nil

        do {
            let signer = try auth.signer()
            let credentials = try await clob.deriveOrCreateCredentials(signer: signer)
            try? secretStore.setCodable(
                StoredCredentials(address: address, credentials: credentials),
                for: SecretKey.clobCredentials
            )
            await authenticator.update(credentials: credentials, signerAddress: address)
            state = .ready(address: address)
        } catch {
            lastError = (error as? APIError)?.userMessage
                ?? "Couldn't set up trading for this wallet."
            // Still signed in — browsing works, trading does not.
            state = .walletOnly(address: address)
        }
    }

    func signOut() async {
        try? secretStore.remove(SecretKey.clobCredentials)
        await auth.signOut()
        await adoptWallet()
    }

    func refreshBalances() async {
        guard let address else { return }
        portfolioValue = try? await data.portfolioValue(user: address)
    }

    /// Supplies the signer to `TradingService` at submission time.
    nonisolated func signingContext() async throws
        -> (signer: EthereumSigner, maker: String, signatureType: SignatureType) {
        try await MainActor.run {
            guard let address = self.state.address else {
                throw TradingService.TradingError.notAuthenticated
            }
            // A Privy embedded wallet is an EOA that signs for itself.
            return (try self.auth.signer(), address, SignatureType.eoa)
        }
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
