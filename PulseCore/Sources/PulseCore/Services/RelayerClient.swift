import Foundation

/// Gasless wallet operations through Polymarket's relayer, via Pulse's own
/// relay server.
///
/// The relayer needs Builder API credentials on every write, and those are a
/// server secret — they must never ship in the app. So the app talks to the
/// Pulse relay (`server/pulse-relay`), which checks the caller's Privy token,
/// adds the builder headers and forwards to `relayer-v2.polymarket.com`. Paths
/// here are the relayer's own, under `/relayer`.
///
/// Only Pulse's own users (Privy wallets) use this. An existing Polymarket
/// account connected through a wallet app is already deployed and approved.
public actor RelayerClient {

    public struct Transaction: Decodable, Sendable {
        public let transactionID: String?
        public let transactionHash: String?
        public let proxyAddress: String?
        public let state: String?

        public var isConfirmed: Bool { state == "STATE_CONFIRMED" }
        public var isFailed: Bool { state == "STATE_FAILED" || state == "STATE_INVALID" }
    }

    public enum RelayerError: Error, Sendable, Equatable {
        case notConfigured
        case failed(state: String)
        case timedOut
    }

    private let http: HTTPClient

    /// - Parameters:
    ///   - baseURL: the Pulse relay server.
    ///   - token: returns the signed-in user's Privy access token.
    public init(baseURL: URL, token: @escaping @Sendable () async throws -> String) {
        // No automatic retries: a retried submit could relay a batch twice.
        // Polling is the retry.
        self.http = HTTPClient(
            baseURL: baseURL,
            authorizer: BearerAuthorizer(token: token),
            maxRetries: 0
        )
    }

    // MARK: Reads

    /// Whether a Deposit Wallet is already deployed at `wallet`.
    public func isDeployed(depositWallet wallet: String) async throws -> Bool {
        struct Response: Decodable { let deployed: Bool }
        let response: Response = try await http.send(HTTPRequest(
            path: "/relayer/deployed",
            query: ["address": wallet, "type": "WALLET"],
            requiresAuth: true
        ))
        return response.deployed
    }

    /// The Deposit Wallet batch nonce for an owner.
    public func walletNonce(owner: String) async throws -> String {
        struct Response: Decodable {
            let nonce: Nonce
            /// The relayer has returned the nonce as both a string and a number.
            enum Nonce: Decodable {
                case text(String)
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if let s = try? c.decode(String.self) { self = .text(s) }
                    else { self = .text(String(try c.decode(UInt64.self))) }
                }
                var value: String { if case .text(let s) = self { s } else { "0" } }
            }
        }
        let response: Response = try await http.send(HTTPRequest(
            path: "/relayer/v1/account/transactions/params",
            query: ["address": owner, "type": "WALLET"],
            requiresAuth: true
        ))
        return response.nonce.value
    }

    public func transaction(id: String) async throws -> Transaction? {
        let list: [Transaction] = try await http.send(HTTPRequest(
            path: "/relayer/transaction",
            query: ["id": id],
            requiresAuth: true
        ))
        return list.first
    }

    // MARK: Writes

    /// Deploys the signer's Deposit Wallet. Returns the relayer transaction id.
    public func deployDepositWallet(signer: String) async throws -> String {
        try await submit([
            "type": "WALLET-CREATE",
            "from": signer,
            "to": PolymarketContracts.depositWalletFactory,
            "metadata": "Deploy Deposit Wallet"
        ])
    }

    /// Relays a batch of calls from a Deposit Wallet, signed by its owner.
    /// Returns the relayer transaction id.
    public func executeBatch(
        account: TradingAccount,
        calls: [ContractCall],
        metadata: String,
        signer: EthereumSigner,
        validFor seconds: TimeInterval = 600
    ) async throws -> String {
        let nonce = try await walletNonce(owner: account.signer)
        let deadline = String(Int(Date().timeIntervalSince1970 + seconds))
        let signature = try await signer.signTypedData(
            TypedData.depositWalletBatch(wallet: account.wallet, nonce: nonce, deadline: deadline, calls: calls)
        )
        return try await submit([
            "type": "WALLET",
            "from": account.signer,
            "to": PolymarketContracts.depositWalletFactory,
            "nonce": nonce,
            "signature": signature,
            "metadata": metadata,
            "depositWalletParams": [
                "depositWallet": account.wallet,
                "deadline": deadline,
                "calls": calls.map { ["target": $0.target, "value": $0.value, "data": $0.data] }
            ]
        ])
    }

    /// Polls until the transaction confirms, fails, or `timeout` passes.
    @discardableResult
    public func waitForConfirmation(
        id: String,
        timeout: TimeInterval = 90,
        interval: TimeInterval = 2
    ) async throws -> Transaction {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let tx = try? await transaction(id: id) {
                if tx.isConfirmed { return tx }
                if tx.isFailed { throw RelayerError.failed(state: tx.state ?? "unknown") }
            }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        throw RelayerError.timedOut
    }

    private func submit(_ body: [String: Any]) async throws -> String {
        struct Response: Decodable { let transactionID: String }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let response: Response = try await http.send(HTTPRequest(
            method: .post,
            path: "/relayer/submit",
            body: data,
            headers: ["Content-Type": "application/json"],
            requiresAuth: true
        ))
        return response.transactionID
    }
}

/// `Authorization: Bearer <token>` for the Pulse relay.
public struct BearerAuthorizer: RequestAuthorizing {
    private let token: @Sendable () async throws -> String

    public init(token: @escaping @Sendable () async throws -> String) {
        self.token = token
    }

    public func authorizationHeaders(method: String, path: String, body: Data?) async throws -> [String: String] {
        ["Authorization": "Bearer \(try await token())"]
    }
}
