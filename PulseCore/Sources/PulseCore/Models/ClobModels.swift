import Foundation

// MARK: - CLOB API models
//
// Verified against live https://clob.polymarket.com responses on 2026-11-27.
// The CLOB returns prices and sizes as decimal *strings* throughout.

/// One level of the order book.
public struct OrderBookLevel: Codable, Hashable, Sendable {
    public let price: Double
    public let size: Double

    public init(price: Double, size: Double) {
        self.price = price
        self.size = size
    }

    private enum CodingKeys: String, CodingKey { case price, size }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        price = try c.decode(LenientDouble.self, forKey: .price).value ?? 0
        size = try c.decode(LenientDouble.self, forKey: .size).value ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(String(price), forKey: .price)
        try c.encode(String(size), forKey: .size)
    }
}

/// A full order book snapshot for one outcome token.
///
/// The API returns `bids` ascending and `asks` descending. We normalise both
/// into "best first" order so the UI never has to care.
public struct OrderBook: Codable, Hashable, Sendable {
    public let market: String?
    public let assetId: String?
    public let timestamp: String?
    public let hash: String?
    /// Highest price first.
    public let bids: [OrderBookLevel]
    /// Lowest price first.
    public let asks: [OrderBookLevel]

    private enum CodingKeys: String, CodingKey {
        case market
        case assetId = "asset_id"
        case timestamp, hash, bids, asks
    }

    public init(
        market: String? = nil,
        assetId: String? = nil,
        timestamp: String? = nil,
        hash: String? = nil,
        bids: [OrderBookLevel],
        asks: [OrderBookLevel]
    ) {
        self.market = market
        self.assetId = assetId
        self.timestamp = timestamp
        self.hash = hash
        self.bids = bids.sorted { $0.price > $1.price }
        self.asks = asks.sorted { $0.price < $1.price }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        market = try c.decodeIfPresent(String.self, forKey: .market)
        assetId = try c.decodeIfPresent(String.self, forKey: .assetId)
        timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        let rawBids = try c.decodeIfPresent([OrderBookLevel].self, forKey: .bids) ?? []
        let rawAsks = try c.decodeIfPresent([OrderBookLevel].self, forKey: .asks) ?? []
        bids = rawBids.filter { $0.size > 0 }.sorted { $0.price > $1.price }
        asks = rawAsks.filter { $0.size > 0 }.sorted { $0.price < $1.price }
    }

    public static let empty = OrderBook(bids: [], asks: [])

    public var bestBid: Double? { bids.first?.price }
    public var bestAsk: Double? { asks.first?.price }

    public var midpoint: Double? {
        guard let b = bestBid, let a = bestAsk else { return bestBid ?? bestAsk }
        return (b + a) / 2
    }

    public var spread: Double? {
        guard let b = bestBid, let a = bestAsk else { return nil }
        return a - b
    }

    /// Total shares resting on each side — used for the depth visualisation.
    public var bidDepth: Double { bids.reduce(0) { $0 + $1.size } }
    public var askDepth: Double { asks.reduce(0) { $0 + $1.size } }

    public var timestampDate: Date? {
        guard let timestamp, let ms = Double(timestamp) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}

// MARK: - Simple scalar responses

public struct PriceResponse: Codable, Sendable {
    public let price: Double
    private enum CodingKeys: String, CodingKey { case price }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        price = try c.decode(LenientDouble.self, forKey: .price).value ?? 0
    }
}

public struct MidpointResponse: Codable, Sendable {
    public let mid: Double
    private enum CodingKeys: String, CodingKey { case mid }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mid = try c.decode(LenientDouble.self, forKey: .mid).value ?? 0
    }
}

public struct SpreadResponse: Codable, Sendable {
    public let spread: Double
    private enum CodingKeys: String, CodingKey { case spread }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spread = try c.decode(LenientDouble.self, forKey: .spread).value ?? 0
    }
}

public struct TickSizeResponse: Codable, Sendable {
    public let minimumTickSize: Double
    private enum CodingKeys: String, CodingKey { case minimumTickSize = "minimum_tick_size" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minimumTickSize = try c.decode(LenientDouble.self, forKey: .minimumTickSize).value ?? 0.001
    }
}

// MARK: - Price history

public struct PricePoint: Codable, Hashable, Sendable, Identifiable {
    /// Unix seconds.
    public let t: Int
    public let p: Double

    public var id: Int { t }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(t)) }

    public init(t: Int, p: Double) {
        self.t = t
        self.p = p
    }

    private enum CodingKeys: String, CodingKey { case t, p }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(LenientInt.self, forKey: .t).value ?? 0
        p = try c.decode(LenientDouble.self, forKey: .p).value ?? 0
    }
}

public struct PriceHistoryResponse: Codable, Sendable {
    public let history: [PricePoint]
    public init(history: [PricePoint]) { self.history = history }
}

/// Time ranges accepted by `GET /prices-history`.
public enum PriceHistoryInterval: String, CaseIterable, Sendable {
    case oneHour = "1h"
    case sixHours = "6h"
    case oneDay = "1d"
    case oneWeek = "1w"
    case oneMonth = "1m"
    case max

    public var displayName: String {
        switch self {
        case .oneHour: "1H"
        case .sixHours: "6H"
        case .oneDay: "1D"
        case .oneWeek: "1W"
        case .oneMonth: "1M"
        case .max: "ALL"
        }
    }

    /// Resolution in minutes to request, balancing detail against payload size.
    public var fidelity: Int {
        switch self {
        case .oneHour: 1
        case .sixHours: 5
        case .oneDay: 10
        case .oneWeek: 60
        case .oneMonth: 180
        case .max: 720
        }
    }
}

// MARK: - Orders

public enum OrderSide: String, Codable, Hashable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
}

/// Time-in-force for a CLOB order.
public enum OrderType: String, Codable, Hashable, Sendable {
    /// Good 'til cancelled — a resting limit order.
    case gtc = "GTC"
    /// Good 'til date — resting with an expiry.
    case gtd = "GTD"
    /// Fill or kill — all of it immediately, or nothing. Used for market buys.
    case fok = "FOK"
    /// Fill and kill — fill what you can immediately, cancel the rest.
    case fak = "FAK"
}

/// An open order as returned by `GET /data/orders`.
public struct OpenOrder: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let status: String?
    public let market: String?
    public let assetId: String?
    public let side: OrderSide?
    public let originalSize: Double?
    public let sizeMatched: Double?
    public let price: Double?
    public let outcome: String?
    public let createdAt: Int?
    public let expiration: String?
    public let orderType: String?

    private enum CodingKeys: String, CodingKey {
        case id, status, market, side, outcome, price, expiration
        case assetId = "asset_id"
        case originalSize = "original_size"
        case sizeMatched = "size_matched"
        case createdAt = "created_at"
        case orderType = "order_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        status = try c.decodeIfPresent(String.self, forKey: .status)
        market = try c.decodeIfPresent(String.self, forKey: .market)
        assetId = try c.decodeIfPresent(String.self, forKey: .assetId)
        side = try c.decodeIfPresent(OrderSide.self, forKey: .side)
        originalSize = try c.decodeIfPresent(LenientDouble.self, forKey: .originalSize)?.value
        sizeMatched = try c.decodeIfPresent(LenientDouble.self, forKey: .sizeMatched)?.value
        price = try c.decodeIfPresent(LenientDouble.self, forKey: .price)?.value
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        createdAt = try c.decodeIfPresent(LenientInt.self, forKey: .createdAt)?.value
        expiration = try c.decodeIfPresent(String.self, forKey: .expiration)
        orderType = try c.decodeIfPresent(String.self, forKey: .orderType)
    }

    /// Shares still resting on the book.
    public var remainingSize: Double {
        max(0, (originalSize ?? 0) - (sizeMatched ?? 0))
    }

    public var fillFraction: Double {
        guard let o = originalSize, o > 0 else { return 0 }
        return min(1, (sizeMatched ?? 0) / o)
    }
}

/// Response from `POST /order`.
public struct OrderPlacementResponse: Codable, Sendable {
    public let success: Bool?
    public let errorMsg: String?
    public let orderId: String?
    public let orderHashes: [String]?
    public let status: String?

    private enum CodingKeys: String, CodingKey {
        case success, status
        case errorMsg = "errorMsg"
        case orderId = "orderID"
        case orderHashes = "orderHashes"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(LenientBool.self, forKey: .success)?.value
        errorMsg = try c.decodeIfPresent(String.self, forKey: .errorMsg)
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId)
        orderHashes = try c.decodeIfPresent([String].self, forKey: .orderHashes)
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    /// The CLOB signals failure with `success: false` plus `errorMsg` while
    /// still returning HTTP 200, so callers must check this rather than status.
    public var isAccepted: Bool {
        if let success { return success }
        return orderId != nil
    }
}

/// CLOB API credentials derived from an L1 wallet signature.
/// These are secrets — they live in the Keychain, never in UserDefaults.
public struct ClobCredentials: Codable, Hashable, Sendable {
    public let apiKey: String
    public let secret: String
    public let passphrase: String

    public init(apiKey: String, secret: String, passphrase: String) {
        self.apiKey = apiKey
        self.secret = secret
        self.passphrase = passphrase
    }

    // Synthesised Codable conformance matches the wire shape exactly:
    // {"apiKey": "...", "secret": "...", "passphrase": "..."}
}
