import Foundation

/// General EIP-712 typed data: the struct hash, the signing digest, and the
/// `eth_signTypedData_v4` JSON a wallet app signs.
///
/// One engine serves every payload Pulse signs — `ClobAuth`, the exchange
/// `Order`, a Deposit Wallet's `TypedDataSign` wrapper around that order, and
/// the relayer's `Batch(Call[])` — and the same value produces both the
/// digest (for signers that sign a raw hash, such as the Privy embedded
/// wallet) and the JSON (for wallet apps over WalletConnect, which refuse to
/// sign raw hashes). Because both come from one value, they cannot disagree.
///
/// The hand-written `EIP712.ClobAuth` and `PolymarketOrder.structHash()` stay
/// as independent references: the tests check this engine against them.
public struct TypedData: Sendable, Hashable {

    public struct Field: Sendable, Hashable {
        public let name: String
        public let type: String
        public init(_ name: String, _ type: String) {
            self.name = name
            self.type = type
        }
    }

    /// A message value. Integers and addresses are carried as strings so
    /// 256-bit values never pass through a lossy numeric type.
    public indirect enum Value: Sendable, Hashable {
        case string(String)
        case bool(Bool)
        case object([String: Value])
        case array([Value])

        public static func uint(_ value: UInt64) -> Value { .string(String(value)) }
    }

    public let domain: EIP712.Domain
    /// Struct definitions, excluding `EIP712Domain` (derived from `domain`).
    public let types: [String: [Field]]
    public let primaryType: String
    public let message: [String: Value]
    /// Some domains (the Deposit Wallet's) also carry a `salt`.
    public let domainSalt: String?

    public init(
        domain: EIP712.Domain,
        types: [String: [Field]],
        primaryType: String,
        message: [String: Value],
        domainSalt: String? = nil
    ) {
        self.domain = domain
        self.types = types
        self.primaryType = primaryType
        self.message = message
        self.domainSalt = domainSalt
    }

    // MARK: Hashing

    public func signingDigest() throws -> Data {
        EIP712.digest(domainSeparator: try domainSeparator(), structHash: try structHash())
    }

    public func structHash() throws -> Data {
        try hashStruct(primaryType, message)
    }

    public func domainSeparator() throws -> Data {
        guard domainSalt != nil else { return try domain.separator() }
        var values: [String: Value] = [
            "name": .string(domain.name),
            "version": .string(domain.version),
            "chainId": .uint(domain.chainId),
            "salt": .string(domainSalt ?? "")
        ]
        if let contract = domain.verifyingContract { values["verifyingContract"] = .string(contract) }
        var withDomain = types
        withDomain["EIP712Domain"] = domainFields
        return try TypedData(domain: domain, types: withDomain, primaryType: "EIP712Domain", message: values)
            .hashStruct("EIP712Domain", values)
    }

    var domainFields: [Field] {
        var fields = [Field("name", "string"), Field("version", "string"), Field("chainId", "uint256")]
        if domain.verifyingContract != nil { fields.append(Field("verifyingContract", "address")) }
        if domainSalt != nil { fields.append(Field("salt", "bytes32")) }
        return fields
    }

    /// `Primary(...)` followed by every referenced struct, sorted by name.
    public func encodeType(_ name: String) throws -> String {
        var deps = Set<String>()
        try collectDependencies(of: name, into: &deps)
        deps.remove(name)
        return try ([name] + deps.sorted()).map { type in
            guard let fields = types[type] else { throw TypedDataError.unknownType(type) }
            return "\(type)(" + fields.map { "\($0.type) \($0.name)" }.joined(separator: ",") + ")"
        }.joined()
    }

    private func collectDependencies(of name: String, into found: inout Set<String>) throws {
        guard !found.contains(name), let fields = types[name] else { return }
        found.insert(name)
        for field in fields {
            let base = Self.baseType(field.type)
            if types[base] != nil { try collectDependencies(of: base, into: &found) }
        }
    }

    func hashStruct(_ type: String, _ value: [String: Value]) throws -> Data {
        guard let fields = types[type] else { throw TypedDataError.unknownType(type) }
        var encoded = Keccak256.hash(try encodeType(type))
        for field in fields {
            guard let fieldValue = value[field.name] else {
                throw TypedDataError.missingField(type: type, field: field.name)
            }
            encoded += try encodeValue(field.type, fieldValue)
        }
        return Keccak256.hash(encoded)
    }

    private func encodeValue(_ type: String, _ value: Value) throws -> Data {
        if type.hasSuffix("[]") {
            guard case .array(let items) = value else { throw TypedDataError.typeMismatch(type) }
            let element = String(type.dropLast(2))
            var joined = Data()
            for item in items { joined += try encodeValue(element, item) }
            return Keccak256.hash(joined)
        }
        if types[type] != nil {
            guard case .object(let object) = value else { throw TypedDataError.typeMismatch(type) }
            return try hashStruct(type, object)
        }
        switch (type, value) {
        case ("string", .string(let s)):
            return EIP712.encodeString(s)
        case ("bytes", .string(let hex)):
            guard let raw = Data(hexString: hex) else { throw TypedDataError.typeMismatch(type) }
            return Keccak256.hash(raw)
        case ("address", .string(let s)):
            guard let encoded = EIP712.encodeAddress(s) else { throw EIP712Error.invalidAddress(s) }
            return encoded
        case ("bool", .bool(let b)):
            return EIP712.encodeBool(b)
        case (_, .string(let s)) where type.hasPrefix("uint"):
            guard let encoded = Self.encodeUInt(s) else { throw EIP712Error.amountOverflow(s) }
            return encoded
        case (_, .string(let s)) where type.hasPrefix("bytes"):
            guard let encoded = EIP712.encodeBytes32(s) else { throw EIP712Error.invalidBytes32(s) }
            return encoded
        default:
            throw TypedDataError.typeMismatch(type)
        }
    }

    /// Decimal or `0x` hex.
    static func encodeUInt(_ s: String) -> Data? {
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            guard let raw = Data(hexString: s), raw.count <= 32 else { return nil }
            return Data(repeating: 0, count: 32 - raw.count) + raw
        }
        return EIP712.encodeUInt256(decimalString: s)
    }

    static func baseType(_ type: String) -> String {
        var base = type
        while base.hasSuffix("[]") { base = String(base.dropLast(2)) }
        return base
    }

    // MARK: eth_signTypedData_v4

    /// The JSON wallet apps sign, with keys sorted so the output is stable.
    ///
    /// Integers that fit JavaScript's safe range are emitted as numbers,
    /// larger ones (token ids, amounts in wei) as decimal strings — the form
    /// MetaMask and other wallets accept for `uint256`.
    public func v4JSON() throws -> String {
        var typeTable: [String: Any] = ["EIP712Domain": domainFields.map { ["name": $0.name, "type": $0.type] }]
        for (name, fields) in types {
            typeTable[name] = fields.map { ["name": $0.name, "type": $0.type] }
        }
        var domainObject: [String: Any] = [
            "name": domain.name, "version": domain.version, "chainId": domain.chainId
        ]
        if let contract = domain.verifyingContract { domainObject["verifyingContract"] = contract }
        if let domainSalt { domainObject["salt"] = domainSalt }

        let root: [String: Any] = [
            "types": typeTable,
            "domain": domainObject,
            "primaryType": primaryType,
            "message": try jsonObject(primaryType, message)
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw TypedDataError.typeMismatch("json") }
        return text
    }

    private func jsonObject(_ type: String, _ value: [String: Value]) throws -> [String: Any] {
        guard let fields = types[type] else { throw TypedDataError.unknownType(type) }
        var out: [String: Any] = [:]
        for field in fields {
            guard let v = value[field.name] else {
                throw TypedDataError.missingField(type: type, field: field.name)
            }
            out[field.name] = try jsonValue(field.type, v)
        }
        return out
    }

    private func jsonValue(_ type: String, _ value: Value) throws -> Any {
        if type.hasSuffix("[]") {
            guard case .array(let items) = value else { throw TypedDataError.typeMismatch(type) }
            let element = String(type.dropLast(2))
            return try items.map { try jsonValue(element, $0) }
        }
        if types[type] != nil {
            guard case .object(let object) = value else { throw TypedDataError.typeMismatch(type) }
            return try jsonObject(type, object)
        }
        switch value {
        case .bool(let b): return b
        case .string(let s):
            if type.hasPrefix("uint"), !s.hasPrefix("0x"), let n = UInt64(s), n <= 9_007_199_254_740_991 {
                return n
            }
            return s
        default: throw TypedDataError.typeMismatch(type)
        }
    }
}

public enum TypedDataError: Error, Sendable, Equatable {
    case unknownType(String)
    case missingField(type: String, field: String)
    case typeMismatch(String)
}

// MARK: - Polymarket payloads

public extension TypedData {

    static let orderFields: [Field] = [
        Field("salt", "uint256"), Field("maker", "address"), Field("signer", "address"),
        Field("tokenId", "uint256"), Field("makerAmount", "uint256"), Field("takerAmount", "uint256"),
        Field("side", "uint8"), Field("signatureType", "uint8"), Field("timestamp", "uint256"),
        Field("metadata", "bytes32"), Field("builder", "bytes32")
    ]

    static func orderMessage(_ order: PolymarketOrder) -> [String: Value] {
        [
            "salt": .uint(order.salt),
            "maker": .string(order.maker),
            "signer": .string(order.signer),
            "tokenId": .string(order.tokenId),
            "makerAmount": .string(order.makerAmount),
            "takerAmount": .string(order.takerAmount),
            "side": .uint(order.sideValue),
            "signatureType": .uint(UInt64(order.signatureType.rawValue)),
            "timestamp": .string(order.timestamp),
            "metadata": .string(order.metadata),
            "builder": .string(order.builder)
        ]
    }

    /// The exchange `Order`, as signed by EOA, Proxy and Safe wallets.
    static func order(_ order: PolymarketOrder, exchange: ExchangeDomain) -> TypedData {
        TypedData(
            domain: exchange.domain,
            types: ["Order": orderFields],
            primaryType: "Order",
            message: orderMessage(order)
        )
    }

    static let zeroSalt = PolymarketOrder.zeroBytes32

    /// A Deposit Wallet's order: the `Order` nested as `contents` of an
    /// ERC-7739 `TypedDataSign`, under the exchange's domain, naming the
    /// Deposit Wallet as the account that validates it.
    static func depositWalletOrder(_ order: PolymarketOrder, exchange: ExchangeDomain) -> TypedData {
        TypedData(
            domain: exchange.domain,
            types: [
                "Order": orderFields,
                "TypedDataSign": [
                    Field("contents", "Order"), Field("name", "string"), Field("version", "string"),
                    Field("chainId", "uint256"), Field("verifyingContract", "address"), Field("salt", "bytes32")
                ]
            ],
            primaryType: "TypedDataSign",
            message: [
                "contents": .object(orderMessage(order)),
                "name": .string("DepositWallet"),
                "version": .string("1"),
                "chainId": .uint(137),
                "verifyingContract": .string(order.maker),
                "salt": .string(zeroSalt)
            ]
        )
    }

    /// The L1 credential message.
    static func clobAuth(_ auth: EIP712.ClobAuth) -> TypedData {
        TypedData(
            domain: EIP712.ClobAuth.domain,
            types: ["ClobAuth": [
                Field("address", "address"), Field("timestamp", "string"),
                Field("nonce", "uint256"), Field("message", "string")
            ]],
            primaryType: "ClobAuth",
            message: [
                "address": .string(auth.address),
                "timestamp": .string(auth.timestamp),
                "nonce": .uint(auth.nonce),
                "message": .string(auth.message)
            ]
        )
    }
}

// MARK: - Deposit Wallet signature

/// Wraps an owner's signature over a Deposit Wallet `TypedDataSign` so the
/// wallet's ERC-7739 validation accepts it.
///
/// Port of `wrapDepositWalletSignature` from
/// https://docs.polymarket.com/trading/place-orders (Deposit Wallet tab):
/// `innerSignature ‖ appDomainSeparator ‖ contentsHash ‖ ORDER_TYPE ‖ uint16(len(ORDER_TYPE))`.
public enum DepositWalletSignature {
    public static func wrap(
        innerSignature: String,
        order: PolymarketOrder,
        exchange: ExchangeDomain
    ) throws -> String {
        guard let inner = Data(hexString: innerSignature), inner.count == 65 else {
            throw SignerError.signingFailed("expected a 65-byte inner signature")
        }
        let typeString = Data(PolymarketOrder.typeString.utf8)
        var out = inner
        out += try exchange.domain.separator()
        out += try order.structHash()
        out += typeString
        out += Data([UInt8((typeString.count >> 8) & 0xff), UInt8(typeString.count & 0xff)])
        return out.hexString(prefixed: true)
    }
}
