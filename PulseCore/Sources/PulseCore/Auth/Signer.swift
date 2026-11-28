import Foundation
import P256K


/// Signs a 32-byte EIP-712 digest with a secp256k1 key.
///
/// Abstracting this lets the app support different custody models — a locally
/// held key today, an external wallet or passkey-backed signer later — without
/// the trading layer changing. Implementations must never log or export key
/// material.
public protocol EthereumSigner: Sendable {
    /// Checksummed or lowercase `0x`-prefixed address of the signing key.
    var address: String { get async throws }

    /// Returns a 65-byte `r ‖ s ‖ v` signature, hex encoded with `0x`,
    /// where `v` is 27 or 28 as Ethereum expects.
    func signDigest(_ digest: Data) async throws -> String

    /// Signs EIP-712 typed data. Signers that hold a key (or a Privy wallet)
    /// sign the digest; wallet apps over WalletConnect override this and sign
    /// the `eth_signTypedData_v4` JSON, because they refuse raw hashes.
    func signTypedData(_ data: TypedData) async throws -> String
}

public extension EthereumSigner {
    func signTypedData(_ data: TypedData) async throws -> String {
        try await signDigest(try data.signingDigest())
    }
}

public enum SignerError: Error, Sendable, Equatable {
    case invalidPrivateKey
    case invalidDigestLength(Int)
    case signingFailed(String)
    case noKeyAvailable
}

/// Wraps a pre-computed 32-byte hash so it can be handed to a signing API that
/// expects a `Digest`. Keccak-256 is not one of the algorithms swift-crypto
/// models, and the EIP-712 digest must be signed exactly as computed — never
/// re-hashed — so this carries the bytes through unchanged.
struct RawDigest32: Digest {
    static var byteCount: Int { 32 }

    private let bytes: [UInt8]

    init?(_ data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.bytes = Array(data)
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    func makeIterator() -> Array<UInt8>.Iterator { bytes.makeIterator() }

    var description: String { "RawDigest32(\(bytes.count) bytes)" }
}

/// Signs with a secp256k1 private key held in memory only for the duration of
/// a signing call. The key itself lives in the Keychain (`KeychainWalletStore`)
/// and is read on demand.
public struct PrivateKeySigner: EthereumSigner {
    private let privateKeyBytes: Data

    /// - Parameter privateKeyHex: 32 bytes, hex with or without `0x`.
    public init(privateKeyHex: String) throws {
        guard let data = Data(hexString: privateKeyHex), data.count == 32 else {
            throw SignerError.invalidPrivateKey
        }
        self.privateKeyBytes = data
    }

    public init(privateKey: Data) throws {
        guard privateKey.count == 32 else { throw SignerError.invalidPrivateKey }
        self.privateKeyBytes = privateKey
    }

    /// Uses the recovery-capable key type: Ethereum signatures must carry the
    /// recovery id so the signer address can be recovered from the signature.
    private func key() throws -> P256K.Recovery.PrivateKey {
        do {
            return try P256K.Recovery.PrivateKey(
                dataRepresentation: privateKeyBytes,
                format: .uncompressed
            )
        } catch {
            throw SignerError.invalidPrivateKey
        }
    }

    public var address: String {
        get async throws {
            let publicKey = try key().publicKey.dataRepresentation
            // Ethereum addresses come from the *uncompressed* public key with
            // its 0x04 prefix stripped: keccak256(pubkey[1...])[12...].
            guard publicKey.count == 65, publicKey.first == 0x04 else {
                throw SignerError.signingFailed(
                    "expected 65-byte uncompressed public key, got \(publicKey.count)"
                )
            }
            let hash = Keccak256.hash(publicKey.dropFirst())
            return "0x" + hash.suffix(20).hexString(prefixed: false)
        }
    }

    public func signDigest(_ digest: Data) async throws -> String {
        guard digest.count == 32 else {
            throw SignerError.invalidDigestLength(digest.count)
        }
        guard let wrapped = RawDigest32(digest) else {
            throw SignerError.invalidDigestLength(digest.count)
        }

        // 65 bytes, r || s || recoveryId.
        let raw = try key().signature(for: wrapped).dataRepresentation
        guard raw.count == 65 else {
            throw SignerError.signingFailed("expected 65-byte signature, got \(raw.count)")
        }

        // Ethereum expects v = 27 + recoveryId, not the bare recovery id.
        var out = Data(raw.prefix(64))
        let recoveryId = raw[raw.index(raw.startIndex, offsetBy: 64)]
        out.append(27 &+ recoveryId)
        return out.hexString(prefixed: true)
    }
}

// MARK: - Address helpers

public enum EthereumAddress {
    /// EIP-55 mixed-case checksum encoding.
    public static func checksummed(_ address: String) -> String {
        var hex = address.lowercased()
        if hex.hasPrefix("0x") { hex = String(hex.dropFirst(2)) }
        guard hex.count == 40 else { return address }

        let hash = Keccak256.hash(hex).hexString(prefixed: false)
        var out = "0x"
        for (i, ch) in hex.enumerated() {
            let hashNibble = hash[hash.index(hash.startIndex, offsetBy: i)]
            if let v = hashNibble.hexDigitValue, v >= 8 {
                out.append(Character(ch.uppercased()))
            } else {
                out.append(ch)
            }
        }
        return out
    }

    public static func isValid(_ address: String) -> Bool {
        guard let data = Data(hexString: address), data.count == 20 else { return false }
        return true
    }

    /// `0x1234…abcd` for display.
    public static func short(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}

// MARK: - Recovery

/// Public-key and address recovery from an Ethereum signature.
///
/// Used to check that a signature a wallet app returns over WalletConnect
/// really came from the connected account before anything is submitted, and
/// as the WalletConnect SDK's `CryptoProvider`.
public enum EthereumRecovery {

    /// The 64-byte uncompressed public key (without the `0x04` prefix) that
    /// signed `digest`. `v` may be 0/1 or 27/28.
    public static func publicKey(r: Data, s: Data, v: UInt8, digest: Data) throws -> Data {
        guard r.count == 32, s.count == 32, let wrapped = RawDigest32(digest) else {
            throw SignerError.signingFailed("malformed signature or digest")
        }
        let recoveryId = Int32(v >= 27 ? v - 27 : v)
        let signature = try P256K.Recovery.ECDSASignature(
            compactRepresentation: r + s, recoveryId: recoveryId
        )
        let key = try P256K.Recovery.PublicKey(wrapped, signature: signature, format: .uncompressed)
        let raw = key.dataRepresentation
        guard raw.count == 65, raw.first == 0x04 else {
            throw SignerError.signingFailed("unexpected public key length \(raw.count)")
        }
        return Data(raw.dropFirst())
    }

    /// The address that produced a 65-byte `r ‖ s ‖ v` signature over `digest`.
    public static func address(signature: String, digest: Data) throws -> String {
        guard let bytes = Data(hexString: signature), bytes.count == 65 else {
            throw SignerError.signingFailed("expected a 65-byte signature")
        }
        let key = try publicKey(
            r: bytes.prefix(32), s: bytes.dropFirst(32).prefix(32), v: bytes[bytes.startIndex + 64], digest: digest
        )
        return "0x" + Keccak256.hash(key).suffix(20).hexString(prefixed: false)
    }
}
