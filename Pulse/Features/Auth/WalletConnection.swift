import Foundation
import Combine
import Observation
import os
import PulseCore
@preconcurrency import ReownAppKit
#if canImport(UIKit)
import UIKit
#endif

/// Connects a wallet app (MetaMask, Rabby, Rainbow…) over WalletConnect, so
/// someone who signed up on Polymarket with that wallet can trade their own
/// account from Pulse.
///
/// Pulse never sees the wallet's key: each signature is requested from the
/// wallet app, which shows it to the user to approve. Requests are typed data
/// (`eth_signTypedData_v4`) only — wallet apps refuse raw hashes, and typed
/// data is what lets the user read what they are signing.
@MainActor
@Observable
final class WalletConnection {
    enum State: Equatable {
        /// No WalletConnect project id in this build.
        case unavailable
        case disconnected
        case connecting
        case connected(address: String)
    }

    private(set) var state: State
    /// Called when a wallet finishes connecting.
    var onConnect: ((String) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    nonisolated private static let log = Logger(subsystem: "com.pulse.polymarket", category: "walletconnect")
    private static let polygon = "eip155:137"

    /// - Parameter appURL: shown by the wallet as the requesting site. Pulse
    ///   is not Polymarket, so this is never polymarket.com: it is the
    ///   app's own relay domain when deployed.
    init(projectId: String?, keychainGroup: String?, appURL: String) {
        guard let projectId, let keychainGroup else {
            state = .unavailable
            return
        }
        state = .disconnected
        Self.configure(projectId: projectId, keychainGroup: keychainGroup, appURL: appURL)
        subscribe()
        if let address = AppKit.instance.getAddress(), !AppKit.instance.getSessions().isEmpty {
            state = .connected(address: address)
        }
    }

    var isAvailable: Bool { state != .unavailable }

    var connectedAddress: String? {
        if case .connected(let address) = state { return address }
        return nil
    }

    // MARK: Setup

    private static func configure(projectId: String, keychainGroup: String, appURL: String) {
        // The SDK keeps its keys in a keychain access group. The app's own
        // default group (team id + bundle id) needs no extra entitlement.
        Networking.configure(
            groupIdentifier: keychainGroup,
            projectId: projectId,
            socketFactory: URLSessionSocketFactory()
        )

        let metadata = AppMetadata(
            name: "Pulse",
            description: "Trade Polymarket from your phone.",
            url: appURL,
            icons: [],
            // Cannot throw: no universal link and no link mode.
            redirect: try! AppMetadata.Redirect(native: "pulse://", universal: nil)
        )

        // Polygon only, and only the two methods Pulse uses.
        let namespaces: [String: ProposalNamespace] = [
            "eip155": ProposalNamespace(
                chains: [Blockchain(Self.polygon)].compactMap { $0 },
                methods: ["eth_signTypedData_v4", "personal_sign"],
                events: ["accountsChanged", "chainChanged"]
            )
        ]

        AppKit.configure(
            projectId: projectId,
            metadata: metadata,
            crypto: PulseCryptoProvider(),
            sessionParams: SessionParams(namespaces: namespaces),
            authRequestParams: nil,
            // The Coinbase SDK path bypasses WalletConnect requests, which
            // this class relies on for typed-data signing.
            coinbaseEnabled: false
        ) { error in
            WalletConnection.log.error("AppKit: \(String(describing: error), privacy: .public)")
        }
    }

    private func subscribe() {
        AppKit.instance.sessionSettlePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.didSettle() }
            }
            .store(in: &cancellables)

        AppKit.instance.sessionDeletePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.state = .disconnected }
            }
            .store(in: &cancellables)

        AppKit.instance.sessionResponsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                let key = response.id.map { "\($0)" } ?? ""
                let outcome: Result<String, Error>
                switch response.result {
                case .response(let value):
                    if let signature = try? value.get(String.self) {
                        outcome = .success(signature)
                    } else {
                        outcome = .failure(SignerError.signingFailed("The wallet returned an unexpected response."))
                    }
                case .error(let error):
                    outcome = .failure(SignerError.signingFailed(error.message))
                }
                MainActor.assumeIsolated { self?.resolve(key, with: outcome) }
            }
            .store(in: &cancellables)
    }

    private func didSettle() {
        guard let address = AppKit.instance.getAddress() else { return }
        state = .connected(address: address)
        onConnect?(address)
    }

    // MARK: Actions

    /// Shows the wallet picker.
    func connect() {
        guard isAvailable else { return }
        state = .connecting
        AppKit.present()
    }

    func disconnect() async {
        for session in AppKit.instance.getSessions() {
            try? await AppKit.instance.disconnect(topic: session.topic)
        }
        if isAvailable { state = .disconnected }
    }

    /// Hands a `pulse://` callback back to WalletConnect.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard isAvailable else { return false }
        return AppKit.instance.handleDeeplink(url)
    }

    /// Asks the wallet app to sign typed data and waits for its answer.
    func signTypedData(json: String, address: String) async throws -> String {
        guard let session = AppKit.instance.getSessions().first,
              let chain = Blockchain(Self.polygon) else {
            throw SignerError.noKeyAvailable
        }
        let request = try Request(
            topic: session.topic,
            method: "eth_signTypedData_v4",
            params: AnyCodable(any: [address, json]),
            chainId: chain
        )
        let key = "\(request.id)"

        return try await withCheckedThrowingContinuation { continuation in
            pending[key] = continuation
            Task {
                do {
                    try await AppKit.instance.request(params: request)
                    // Bring the wallet forward so the user can approve.
                    AppKit.instance.launchCurrentWallet()
                } catch {
                    self.resolve(key, with: .failure(error))
                }
            }
            // A request nobody answers must not hang the trade sheet.
            Task {
                try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
                self.resolve(key, with: .failure(SignerError.signingFailed("The wallet didn't respond. Try again.")))
            }
        }
    }

    private func resolve(_ key: String, with result: Result<String, Error>) {
        guard let continuation = pending.removeValue(forKey: key) else { return }
        continuation.resume(with: result)
    }
}

// MARK: - Signer

/// Signs through the connected wallet app, and checks every signature
/// recovers to the connected account before it is used.
struct WalletAppSigner: EthereumSigner {
    let address: String
    let connection: WalletConnection

    func signDigest(_ digest: Data) async throws -> String {
        throw SignerError.signingFailed("Wallet apps sign typed data, not raw hashes.")
    }

    func signTypedData(_ data: TypedData) async throws -> String {
        let json = try data.v4JSON()
        let raw = try await connection.signTypedData(json: json, address: address)
        guard var bytes = Data(hexString: raw), bytes.count == 65 else {
            throw SignerError.signingFailed("The wallet returned a signature Pulse can't use.")
        }
        // Some wallets return v as 0/1; the exchange expects 27/28.
        let vIndex = bytes.index(bytes.startIndex, offsetBy: 64)
        if bytes[vIndex] < 27 { bytes[vIndex] &+= 27 }
        let signature = bytes.hexString(prefixed: true)

        let signer = try EthereumRecovery.address(signature: signature, digest: try data.signingDigest())
        guard signer.lowercased() == address.lowercased() else {
            throw SignerError.signingFailed("The wallet signed with a different account than the one connected.")
        }
        return signature
    }
}

// MARK: - WalletConnect plumbing

/// `CryptoProvider` for the WalletConnect SDK, backed by PulseCore's
/// Keccak and secp256k1 rather than two more crypto dependencies.
struct PulseCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        try EthereumRecovery.publicKey(
            r: Data(signature.r), s: Data(signature.s), v: signature.v,
            digest: Keccak256.hash(message)
        )
    }

    func keccak256(_ data: Data) -> Data {
        Keccak256.hash(data)
    }
}

/// WalletConnect's relay socket on `URLSessionWebSocketTask`, instead of the
/// Starscream dependency its examples use.
final class URLSessionSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        URLSessionSocket(url: url)
    }
}

final class URLSessionSocket: NSObject, WebSocketConnecting, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _isConnected = false
    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isConnected
    }
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    func connect() {
        task?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receive(on: task)
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        setConnected(false)
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in completion?() }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, task === self.task else { return }
            switch result {
            case .success(.string(let text)):
                self.onText?(text)
                self.receive(on: task)
            case .success(.data(let data)):
                if let text = String(data: data, encoding: .utf8) { self.onText?(text) }
                self.receive(on: task)
            case .success:
                self.receive(on: task)
            case .failure(let error):
                self.closed(error)
            }
        }
    }

    private func setConnected(_ value: Bool) {
        lock.lock(); _isConnected = value; lock.unlock()
    }

    private func closed(_ error: Error?) {
        guard isConnected else { return }
        setConnected(false)
        onDisconnect?(error)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        setConnected(true)
        onConnect?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        closed(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        closed(error)
    }
}
