import Foundation
import Crypto

/// Produces the CLOB's L2 request headers and performs the L1 credential
/// exchange.
///
/// Two layers, per https://docs.polymarket.com/getting-started/api:
///  * **L1** — the wallet signs an EIP-712 `ClobAuth` message once, which is
///    exchanged at `/auth/api-key` (create) or `/auth/derive-api-key` (recover)
///    for a long-lived `apiKey`/`secret`/`passphrase` triple.
///  * **L2** — every private request carries an HMAC-SHA256 over
///    `timestamp + METHOD + path + body`, keyed by the base64-decoded secret.
public actor ClobAuthenticator: RequestAuthorizing {
    public private(set) var credentials: ClobCredentials?
    public private(set) var signerAddress: String?

    public init(credentials: ClobCredentials? = nil, signerAddress: String? = nil) {
        self.credentials = credentials
        self.signerAddress = signerAddress
    }

    public func update(credentials: ClobCredentials?, signerAddress: String?) {
        self.credentials = credentials
        self.signerAddress = signerAddress
    }

    public var isAuthenticated: Bool { credentials != nil && signerAddress != nil }

    // MARK: - L2

    /// Builds the five headers every authenticated CLOB request carries.
    public func authorizationHeaders(
        method: String,
        path: String,
        body: Data?
    ) async throws -> [String: String] {
        guard let credentials, let signerAddress else { throw APIError.unauthorized }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = try Self.l2Signature(
            secret: credentials.secret,
            timestamp: timestamp,
            method: method,
            path: path,
            body: body
        )

        return [
            "POLY_ADDRESS": signerAddress,
            "POLY_SIGNATURE": signature,
            "POLY_TIMESTAMP": timestamp,
            "POLY_API_KEY": credentials.apiKey,
            "POLY_PASSPHRASE": credentials.passphrase
        ]
    }

    /// `urlsafeBase64WithPadding(HMAC-SHA256(base64Decode(secret), message))`
    /// where `message = timestamp + METHOD + path + body`.
    ///
    /// The secret is base64 in the **URL-safe** alphabet, so `-` and `_` are
    /// translated back before decoding.
    public static func l2Signature(
        secret: String,
        timestamp: String,
        method: String,
        path: String,
        body: Data?
    ) throws -> String {
        guard let keyData = base64URLDecode(secret) else {
            throw APIError.server(message: "CLOB API secret is not valid base64")
        }

        var message = timestamp + method.uppercased() + path
        if let body, let bodyString = String(data: body, encoding: .utf8) {
            message += bodyString
        }

        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: keyData)
        )
        return base64URLEncode(Data(mac))
    }

    /// Standard base64 → URL-safe base64, padding preserved.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore padding if the server omitted it.
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: s)
    }

    // MARK: - L1

    /// Headers for the one-time credential exchange. The signature is over the
    /// EIP-712 `ClobAuth` struct, not an HMAC.
    public static func l1Headers(
        signer: EthereumSigner,
        nonce: UInt64 = 0,
        timestamp: Date = Date()
    ) async throws -> [String: String] {
        let address = try await signer.address
        let ts = String(Int(timestamp.timeIntervalSince1970))
        let auth = EIP712.ClobAuth(address: address, timestamp: ts, nonce: nonce)
        // Typed data rather than a bare digest, so wallet apps can sign it too.
        let signature = try await signer.signTypedData(TypedData.clobAuth(auth))

        return [
            "POLY_ADDRESS": address,
            "POLY_SIGNATURE": signature,
            "POLY_TIMESTAMP": ts,
            "POLY_NONCE": String(nonce)
        ]
    }
}
