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
        let session = SessionStore(
            secretStore: secretStore,
            authenticator: authenticator,
            clob: clob,
            data: data
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

        return PulseConfiguration(
            builderCode: (code?.isEmpty == false && code != "$(POLYMARKET_BUILDER_CODE)") ? code : nil,
            builderFeeBps: bps.flatMap(Int.init)
        )
    }
}

// MARK: - Session

/// Wallet connection and CLOB credentials.
///
/// Three states matter to the UI: no wallet (browse only), a wallet with no
/// CLOB credentials (needs a one-time signature), and fully ready to trade.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case signedOut
        case connecting
        /// Wallet known, but no L2 credentials yet.
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

    /// Spendable USDC. `nil` means "not yet known" and must render as a dash,
    /// never as $0.
    private(set) var availableBalance: Double?
    private(set) var portfolioValue: Double?

    private let secretStore: any SecretStore
    private let authenticator: ClobAuthenticator
    private let clob: ClobService
    private let data: DataService

    init(
        secretStore: any SecretStore,
        authenticator: ClobAuthenticator,
        clob: ClobService,
        data: DataService
    ) {
        self.secretStore = secretStore
        self.authenticator = authenticator
        self.clob = clob
        self.data = data
    }

    var address: String? { state.address }
    var canTrade: Bool { state.canTrade }

    /// Restores a previously connected wallet on launch.
    func restore() async {
        guard let key = try? secretStore.getString(SecretKey.walletPrivateKey),
              let signer = try? PrivateKeySigner(privateKeyHex: key),
              let address = try? await signer.address else {
            state = .signedOut
            return
        }

        if let credentials = try? secretStore.getCodable(
            ClobCredentials.self, for: SecretKey.clobCredentials
        ) {
            await authenticator.update(credentials: credentials, signerAddress: address)
            state = .ready(address: address)
        } else {
            state = .walletOnly(address: address)
        }
        await refreshBalances()
    }

    /// Imports a private key and derives CLOB credentials.
    ///
    /// The key is written straight to the Keychain and never retained in this
    /// object, logged, or sent anywhere: only signatures leave the device.
    func connect(privateKeyHex: String) async {
        state = .connecting
        lastError = nil

        do {
            let signer = try PrivateKeySigner(privateKeyHex: privateKeyHex)
            let address = try await signer.address

            try secretStore.setString(privateKeyHex, for: SecretKey.walletPrivateKey)
            state = .walletOnly(address: address)

            let credentials = try await clob.deriveOrCreateCredentials(signer: signer)
            try secretStore.setCodable(credentials, for: SecretKey.clobCredentials)
            await authenticator.update(credentials: credentials, signerAddress: address)

            state = .ready(address: address)
            await refreshBalances()
        } catch {
            lastError = (error as? APIError)?.userMessage ?? "Couldn't connect that wallet."
            // Keep a wallet-only state if the key itself was valid, so the
            // user can retry credential derivation without re-entering it.
            if state == .connecting { state = .signedOut }
        }
    }

    func disconnect() async {
        try? secretStore.remove(SecretKey.walletPrivateKey)
        try? secretStore.remove(SecretKey.clobCredentials)
        try? secretStore.remove(SecretKey.proxyWalletAddress)
        await authenticator.update(credentials: nil, signerAddress: nil)
        state = .signedOut
        availableBalance = nil
        portfolioValue = nil
    }

    func refreshBalances() async {
        guard let address else { return }
        portfolioValue = try? await data.portfolioValue(user: address)
    }

    /// Supplies the signer to `TradingService` at submission time.
    ///
    /// Reading the key here, rather than holding it, keeps key material out of
    /// memory except during the moment a signature is produced.
    nonisolated func signingContext() async throws
        -> (signer: EthereumSigner, maker: String, signatureType: SignatureType) {
        let (store, currentAddress) = await MainActor.run {
            (self.secretStore, self.state.address)
        }
        guard let currentAddress,
              let key = try? store.getString(SecretKey.walletPrivateKey) else {
            throw TradingService.TradingError.notAuthenticated
        }
        let signer = try PrivateKeySigner(privateKeyHex: key)
        // An imported EOA signs for itself. A Polymarket proxy or Safe wallet
        // would use .polyProxy / .polyGnosisSafe with the proxy as `maker`.
        return (signer, currentAddress, .eoa)
    }
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: "pulse.appearance") ?? Appearance.system.rawValue
        self.appearance = Appearance(rawValue: stored) ?? .system
        let slippage = defaults.double(forKey: "pulse.slippageLimit")
        self.slippageLimit = slippage > 0 ? slippage : 0.05
        self.confirmBeforeTrading = defaults.object(forKey: "pulse.confirmBeforeTrading") as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: "pulse.haptics") as? Bool ?? true
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
