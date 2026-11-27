import Foundation

/// Minimal EIP-712 typed-data hashing, supporting exactly the two structures
/// Polymarket requires: `ClobAuth` (L1 authentication) and `Order`.
///
/// Rather than a general typed-data engine, this models the encoding
/// primitives directly. Each struct hash is built by hand from its documented
/// type string, which keeps the implementation auditable against
/// https://docs.polymarket.com/trading/place-orders.
public enum EIP712 {

    // MARK: - Encoding primitives (all produce exactly 32 bytes)

    /// `uintN` / `intN`: big-endian, left-padded to 32 bytes.
    public static func encodeUInt(_ value: UInt64) -> Data {
        var out = Data(repeating: 0, count: 32)
        var v = value
        var i = 31
        while v > 0 && i >= 0 {
            out[i] = UInt8(v & 0xff)
            v >>= 8
            i -= 1
        }
        return out
    }

    /// Encodes an arbitrarily large unsigned integer given in decimal.
    /// Token ids are 77-digit uint256 values that do not fit in `UInt64`.
    /// Returns nil if the string is not a valid non-negative integer or
    /// overflows 256 bits.
    public static func encodeUInt256(decimalString: String) -> Data? {
        let trimmed = decimalString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return nil }

        // Schoolbook base-256 accumulation: bytes = bytes * 10 + digit.
        var bytes = [UInt8]()
        for ch in trimmed {
            guard let digit = ch.wholeNumberValue else { return nil }
            var carry = digit
            for i in stride(from: bytes.count - 1, through: 0, by: -1) {
                let product = Int(bytes[i]) * 10 + carry
                bytes[i] = UInt8(product & 0xff)
                carry = product >> 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
            if bytes.count > 32 { return nil }
        }
        guard bytes.count <= 32 else { return nil }
        return Data(repeating: 0, count: 32 - bytes.count) + Data(bytes)
    }

    /// `address`: 20 bytes, left-padded to 32.
    public static func encodeAddress(_ address: String) -> Data? {
        guard let raw = Data(hexString: address), raw.count == 20 else { return nil }
        return Data(repeating: 0, count: 12) + raw
    }

    /// `bytes32`: used as-is, right-padded if short.
    public static func encodeBytes32(_ hex: String) -> Data? {
        guard var raw = Data(hexString: hex) else { return nil }
        if raw.count > 32 { return nil }
        if raw.count < 32 { raw.append(Data(repeating: 0, count: 32 - raw.count)) }
        return raw
    }

    /// `string` / `bytes`: encoded as their keccak256 hash.
    public static func encodeString(_ value: String) -> Data {
        Keccak256.hash(value)
    }

    /// `bool`
    public static func encodeBool(_ value: Bool) -> Data {
        encodeUInt(value ? 1 : 0)
    }

    // MARK: - Domain

    public struct Domain: Sendable, Hashable {
        public let name: String
        public let version: String
        public let chainId: UInt64
        public let verifyingContract: String?

        public init(name: String, version: String, chainId: UInt64, verifyingContract: String?) {
            self.name = name
            self.version = version
            self.chainId = chainId
            self.verifyingContract = verifyingContract
        }

        /// `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)`
        ///
        /// When `verifyingContract` is absent the field is omitted from both
        /// the type string and the encoding — this is what Polymarket's
        /// `ClobAuthDomain` does.
        public func separator() throws -> Data {
            var typeString = "EIP712Domain(string name,string version,uint256 chainId"
            if verifyingContract != nil { typeString += ",address verifyingContract" }
            typeString += ")"

            var encoded = Keccak256.hash(typeString)
            encoded += EIP712.encodeString(name)
            encoded += EIP712.encodeString(version)
            encoded += EIP712.encodeUInt(chainId)
            if let verifyingContract {
                guard let addr = EIP712.encodeAddress(verifyingContract) else {
                    throw EIP712Error.invalidAddress(verifyingContract)
                }
                encoded += addr
            }
            return Keccak256.hash(encoded)
        }
    }

    /// Final EIP-191 / EIP-712 digest: `keccak256(0x1901 ‖ domainSeparator ‖ structHash)`.
    public static func digest(domainSeparator: Data, structHash: Data) -> Data {
        var payload = Data([0x19, 0x01])
        payload += domainSeparator
        payload += structHash
        return Keccak256.hash(payload)
    }
}

public enum EIP712Error: Error, Sendable, Equatable {
    case invalidAddress(String)
    case invalidTokenId(String)
    case invalidBytes32(String)
    case amountOverflow(String)
}

// MARK: - ClobAuth (L1)

public extension EIP712 {
    /// The L1 payload that proves control of a wallet, exchanged at
    /// `/auth/api-key` or `/auth/derive-api-key` for L2 credentials.
    ///
    /// `ClobAuth(address address,string timestamp,uint256 nonce,string message)`
    struct ClobAuth: Sendable {
        public static let messageText = "This message attests that I control the given wallet"

        public let address: String
        /// Unix seconds, as a *string* — the type really is `string`.
        public let timestamp: String
        public let nonce: UInt64
        public let message: String

        public init(
            address: String,
            timestamp: String,
            nonce: UInt64 = 0,
            message: String = ClobAuth.messageText
        ) {
            self.address = address
            self.timestamp = timestamp
            self.nonce = nonce
            self.message = message
        }

        public static let domain = Domain(
            name: "ClobAuthDomain",
            version: "1",
            chainId: 137,
            verifyingContract: nil
        )

        public func structHash() throws -> Data {
            let typeHash = Keccak256.hash(
                "ClobAuth(address address,string timestamp,uint256 nonce,string message)"
            )
            guard let addr = EIP712.encodeAddress(address) else {
                throw EIP712Error.invalidAddress(address)
            }
            var encoded = typeHash
            encoded += addr
            encoded += EIP712.encodeString(timestamp)
            encoded += EIP712.encodeUInt(nonce)
            encoded += EIP712.encodeString(message)
            return Keccak256.hash(encoded)
        }

        /// The 32-byte digest to sign with the wallet's private key.
        public func signingDigest() throws -> Data {
            EIP712.digest(
                domainSeparator: try Self.domain.separator(),
                structHash: try structHash()
            )
        }
    }
}
