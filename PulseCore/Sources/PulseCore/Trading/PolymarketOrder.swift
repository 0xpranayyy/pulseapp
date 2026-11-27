import Foundation

// MARK: - Signature types

/// How the CLOB should verify the order signature.
/// Table from https://docs.polymarket.com/trading/place-orders.
public enum SignatureType: Int, Codable, Sendable, Hashable {
    /// Plain externally-owned account; maker == signer.
    case eoa = 0
    /// Polymarket proxy wallet; maker is the proxy, signer is the account key.
    case polyProxy = 1
    /// Gnosis Safe; maker is the Safe, signer is the account key.
    case polyGnosisSafe = 2
    /// Deposit Wallet (Polymarket Protocol V2); maker == signer == deposit wallet.
    case depositWallet = 3
}

/// Which exchange contract (and therefore signing domain) an order belongs to.
public enum ExchangeDomain: Sendable, Hashable {
    /// Polymarket Protocol V2 order book (`version: "v2"`).
    case protocolV2
    /// Conditional Token Framework exchange, standard markets.
    case ctf
    /// CTF exchange for negative-risk (multi-outcome) markets.
    case ctfNegRisk

    public var verifyingContract: String {
        switch self {
        case .protocolV2: "0xe3333700cA9d93003F00f0F71f8515005F6c00Aa"
        case .ctf: "0xE111180000d2663C0091e4f400237545B87B996B"
        case .ctfNegRisk: "0xe2222d279d744050d28e00520010520000310F59"
        }
    }

    public var domainVersion: String {
        switch self {
        case .protocolV2: "3"
        case .ctf, .ctfNegRisk: "2"
        }
    }

    public var domain: EIP712.Domain {
        EIP712.Domain(
            name: "Polymarket CTF Exchange",
            version: domainVersion,
            chainId: 137,
            verifyingContract: verifyingContract
        )
    }

    /// Chooses the domain from the market's reported book version and
    /// negative-risk flag.
    public static func select(isProtocolV2: Bool, negRisk: Bool) -> ExchangeDomain {
        if isProtocolV2 { return .protocolV2 }
        return negRisk ? .ctfNegRisk : .ctf
    }
}

// MARK: - Amount maths

/// Converts a human price/size into the six-decimal integer amounts the
/// exchange signs over, applying the precision rules the CLOB enforces.
public enum OrderAmounts {

    /// Decimal precision implied by a market's tick size.
    /// Table from https://docs.polymarket.com/trading/place-orders.
    public struct Precision: Sendable, Hashable {
        public let price: Int
        public let size: Int
        public let amount: Int

        public init(price: Int, size: Int, amount: Int) {
            self.price = price
            self.size = size
            self.amount = amount
        }

        public static func forTickSize(_ tick: Double) -> Precision {
            switch tick {
            case 0.1: Precision(price: 1, size: 2, amount: 3)
            case 0.01: Precision(price: 2, size: 2, amount: 4)
            case 0.005: Precision(price: 3, size: 2, amount: 5)
            case 0.0025: Precision(price: 4, size: 2, amount: 6)
            case 0.001: Precision(price: 3, size: 2, amount: 5)
            case 0.0001: Precision(price: 4, size: 2, amount: 6)
            // Unknown tick: fall back to the finest documented precision so we
            // never round a price into an invalid tick.
            default: Precision(price: 4, size: 2, amount: 6)
            }
        }
    }

    /// Six-decimal fixed point, matching USDC and the exchange's share units.
    public static let decimals = 6

    public struct Amounts: Sendable, Hashable {
        /// What the maker gives up, in 1e-6 units.
        public let makerAmount: String
        /// What the maker receives, in 1e-6 units.
        public let takerAmount: String
        /// The rounded price actually signed.
        public let price: Double
        /// The rounded share count actually signed.
        public let size: Double
        /// The USD notional actually signed.
        public let usdcAmount: Double
    }

    /// Builds the signed amounts for an order.
    ///
    /// Per the docs, precision is applied in a specific order:
    ///  1. round the price to `price` decimals,
    ///  2. round the share quantity **down** to `size` decimals,
    ///  3. compute the USD amount; if it needs more than `amount` decimals,
    ///     round **up** to `amount + 4` first, then **down** to `amount`.
    ///
    /// For a BUY the maker pays USD and receives shares; for a SELL the maker
    /// gives shares and receives USD.
    public static func make(
        side: OrderSide,
        price: Double,
        size: Double,
        tickSize: Double
    ) throws -> Amounts {
        guard price.isFinite, size.isFinite, price > 0, size > 0 else {
            throw EIP712Error.amountOverflow("price and size must be positive and finite")
        }

        let p = Precision.forTickSize(tickSize)

        let roundedPrice = round(price, decimals: p.price, rule: .toNearestOrAwayFromZero)
        let roundedSize = round(size, decimals: p.size, rule: .down)

        guard roundedSize > 0 else {
            throw EIP712Error.amountOverflow("size rounds to zero at \(p.size) decimals")
        }

        var usdc = roundedPrice * roundedSize
        if !isExact(usdc, decimals: p.amount) {
            usdc = round(usdc, decimals: p.amount + 4, rule: .up)
            usdc = round(usdc, decimals: p.amount, rule: .down)
        }

        let sharesUnits = try fixedPoint(roundedSize)
        let usdcUnits = try fixedPoint(usdc)

        switch side {
        case .buy:
            return Amounts(
                makerAmount: usdcUnits,
                takerAmount: sharesUnits,
                price: roundedPrice,
                size: roundedSize,
                usdcAmount: usdc
            )
        case .sell:
            return Amounts(
                makerAmount: sharesUnits,
                takerAmount: usdcUnits,
                price: roundedPrice,
                size: roundedSize,
                usdcAmount: usdc
            )
        }
    }

    /// Converts to a 1e-6 integer string without going through `Double`'s
    /// decimal formatting, which would introduce representation error.
    static func fixedPoint(_ value: Double) throws -> String {
        let scaled = (Decimal(value) * pow(Decimal(10), decimals))
        var rounded = Decimal()
        var input = scaled
        NSDecimalRound(&rounded, &input, 0, .plain)
        guard rounded >= 0 else { throw EIP712Error.amountOverflow("negative amount") }
        let string = NSDecimalNumber(decimal: rounded).stringValue
        guard !string.contains("."), string.allSatisfy(\.isNumber) else {
            throw EIP712Error.amountOverflow("amount \(value) not representable")
        }
        return string
    }

    static func round(_ value: Double, decimals: Int, rule: FloatingPointRoundingRule) -> Double {
        var result = Decimal()
        var input = Decimal(value)
        let mode: NSDecimalNumber.RoundingMode = switch rule {
        case .down: .down
        case .up: .up
        default: .plain
        }
        NSDecimalRound(&result, &input, decimals, mode)
        return NSDecimalNumber(decimal: result).doubleValue
    }

    static func isExact(_ value: Double, decimals: Int) -> Bool {
        var rounded = Decimal()
        var input = Decimal(value)
        NSDecimalRound(&rounded, &input, decimals, .plain)
        return NSDecimalNumber(decimal: rounded).doubleValue == value
    }
}

// MARK: - The signed order

/// A Polymarket exchange order, exactly as signed and submitted.
///
/// Field order matters: it must match the EIP-712 type string
/// `Order(uint256 salt,address maker,address signer,uint256 tokenId,uint256 makerAmount,uint256 takerAmount,uint8 side,uint8 signatureType,uint256 timestamp,bytes32 metadata,bytes32 builder)`.
public struct PolymarketOrder: Sendable, Hashable {
    public static let zeroBytes32 = "0x" + String(repeating: "0", count: 64)

    public let salt: UInt64
    public let maker: String
    public let signer: String
    public let tokenId: String
    public let makerAmount: String
    public let takerAmount: String
    public let side: OrderSide
    public let signatureType: SignatureType
    /// Unix **milliseconds**, per the docs.
    public let timestamp: String
    public let metadata: String
    /// The builder code (bytes32) that attributes this order. Zero when the
    /// app has no builder code configured.
    public let builder: String
    /// Unix seconds for GTD orders; "0" otherwise. Not part of the signature.
    public let expiration: String

    public init(
        salt: UInt64,
        maker: String,
        signer: String,
        tokenId: String,
        makerAmount: String,
        takerAmount: String,
        side: OrderSide,
        signatureType: SignatureType,
        timestamp: String,
        metadata: String = PolymarketOrder.zeroBytes32,
        builder: String = PolymarketOrder.zeroBytes32,
        expiration: String = "0"
    ) {
        self.salt = salt
        self.maker = maker
        self.signer = signer
        self.tokenId = tokenId
        self.makerAmount = makerAmount
        self.takerAmount = takerAmount
        self.side = side
        self.signatureType = signatureType
        self.timestamp = timestamp
        self.metadata = metadata
        self.builder = builder
        self.expiration = expiration
    }

    static let typeString =
        "Order(uint256 salt,address maker,address signer,uint256 tokenId,"
        + "uint256 makerAmount,uint256 takerAmount,uint8 side,uint8 signatureType,"
        + "uint256 timestamp,bytes32 metadata,bytes32 builder)"

    /// `side` is encoded as 0 for BUY and 1 for SELL.
    var sideValue: UInt64 { side == .buy ? 0 : 1 }

    public func structHash() throws -> Data {
        guard let makerAddr = EIP712.encodeAddress(maker) else {
            throw EIP712Error.invalidAddress(maker)
        }
        guard let signerAddr = EIP712.encodeAddress(signer) else {
            throw EIP712Error.invalidAddress(signer)
        }
        guard let tokenEncoded = EIP712.encodeUInt256(decimalString: tokenId) else {
            throw EIP712Error.invalidTokenId(tokenId)
        }
        guard let makerAmountEncoded = EIP712.encodeUInt256(decimalString: makerAmount) else {
            throw EIP712Error.amountOverflow(makerAmount)
        }
        guard let takerAmountEncoded = EIP712.encodeUInt256(decimalString: takerAmount) else {
            throw EIP712Error.amountOverflow(takerAmount)
        }
        guard let timestampEncoded = EIP712.encodeUInt256(decimalString: timestamp) else {
            throw EIP712Error.amountOverflow(timestamp)
        }
        guard let metadataEncoded = EIP712.encodeBytes32(metadata) else {
            throw EIP712Error.invalidBytes32(metadata)
        }
        guard let builderEncoded = EIP712.encodeBytes32(builder) else {
            throw EIP712Error.invalidBytes32(builder)
        }

        var encoded = Keccak256.hash(Self.typeString)
        encoded += EIP712.encodeUInt(salt)
        encoded += makerAddr
        encoded += signerAddr
        encoded += tokenEncoded
        encoded += makerAmountEncoded
        encoded += takerAmountEncoded
        encoded += EIP712.encodeUInt(sideValue)
        encoded += EIP712.encodeUInt(UInt64(signatureType.rawValue))
        encoded += timestampEncoded
        encoded += metadataEncoded
        encoded += builderEncoded
        return Keccak256.hash(encoded)
    }

    /// The 32-byte digest to sign for a given exchange.
    public func signingDigest(domain: ExchangeDomain) throws -> Data {
        EIP712.digest(
            domainSeparator: try domain.domain.separator(),
            structHash: try structHash()
        )
    }
}

// MARK: - Request body

/// The exact JSON body `POST /order` expects.
///
/// `salt` is a JSON **number** while every amount is a **string** — the body
/// is also the input to the L2 HMAC, so the serialization must be byte-stable.
public struct OrderSubmission: Encodable, Sendable {
    public struct Body: Encodable, Sendable {
        public let builder: String
        public let expiration: String
        public let maker: String
        public let makerAmount: String
        public let metadata: String
        public let salt: UInt64
        public let side: String
        public let signature: String
        public let signatureType: Int
        public let signer: String
        public let takerAmount: String
        public let timestamp: String
        public let tokenId: String
    }

    public let deferExec: Bool
    public let order: Body
    public let orderType: String
    public let owner: String

    public init(order: PolymarketOrder, signature: String, orderType: OrderType, owner: String) {
        self.deferExec = false
        self.orderType = orderType.rawValue
        self.owner = owner
        self.order = Body(
            builder: order.builder,
            expiration: order.expiration,
            maker: order.maker,
            makerAmount: order.makerAmount,
            metadata: order.metadata,
            salt: order.salt,
            side: order.side.rawValue,
            signature: signature,
            signatureType: order.signatureType.rawValue,
            signer: order.signer,
            takerAmount: order.takerAmount,
            timestamp: order.timestamp,
            tokenId: order.tokenId
        )
    }

    /// Serializes with sorted keys so the bytes signed by the L2 HMAC are
    /// exactly the bytes sent on the wire.
    public func serialized() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
