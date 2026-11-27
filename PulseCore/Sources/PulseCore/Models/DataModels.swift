import Foundation

// MARK: - Data API v2 models
//
// IMPORTANT: Data API **v1 is retired** — it returns HTTP 410 with
// `{"error":"Data API v1 has been retired"}`. v2 differs in three ways:
//   1. every response is wrapped in a `data` envelope,
//   2. fields are snake_case (v1 was camelCase),
//   3. paging uses an opaque `cursor`, not `offset` (offset is now a 400).
// Verified against live data-api.polymarket.com responses on 2026-11-27.

/// The shared v2 envelope. `data` is documented to be `null` or empty on a
/// miss, never an error, so `items` normalises that away.
public struct DataEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let data: T?
    public let pagination: Pagination?

    public struct Pagination: Decodable, Hashable, Sendable {
        public let limit: Int?
        public let hasMore: Bool?
        public let nextCursor: String?

        private enum CodingKeys: String, CodingKey {
            case limit
            case hasMore = "has_more"
            case nextCursor = "next_cursor"
        }
    }
}

public extension DataEnvelope where T: RangeReplaceableCollection {
    var items: T { data ?? T() }
}

/// A page of results plus the cursor needed to fetch the next one.
public struct Page<Element: Sendable>: Sendable {
    public let items: [Element]
    public let nextCursor: String?
    public let hasMore: Bool

    public init(items: [Element], nextCursor: String?, hasMore: Bool) {
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }

    public static var empty: Page<Element> {
        Page(items: [], nextCursor: nil, hasMore: false)
    }
}

// MARK: - Positions

/// Lifecycle filter for `GET /v2/positions`.
public enum PositionStatus: String, CaseIterable, Sendable {
    case open = "OPEN"
    case redeemable = "REDEEMABLE"
    case redeemableLost = "REDEEMABLE_LOST"
    case mergeable = "MERGEABLE"
    case closed = "CLOSED"

    public var displayName: String {
        switch self {
        case .open: "Open"
        case .redeemable: "Redeemable"
        case .redeemableLost: "Lost"
        case .mergeable: "Mergeable"
        case .closed: "Closed"
        }
    }
}

/// A holding in one outcome token.
///
/// All monetary figures come straight from the API — the app does not
/// recompute P&L from entry price, because the API's figures already account
/// for fees and partial exits. `Portfolio` only ever *sums* these.
public struct Position: Decodable, Identifiable, Hashable, Sendable {
    public let proxyWallet: String
    public let tokenId: String
    public let conditionId: String

    public let currentSize: Double
    public let avgPrice: Double
    public let entryCostUsdc: Double
    public let entryFeesUsdc: Double
    public let totalCostUsdc: Double
    public let currentPrice: Double
    public let currentValue: Double
    public let totalSize: Double

    public let realizedPnl: Double
    public let unrealizedPnl: Double
    public let totalPnl: Double
    public let percentPnl: Double
    public let percentRealizedPnl: Double

    public let status: String?
    public let redeemable: Bool
    public let mergeable: Bool
    public let negativeRisk: Bool
    public let archived: Bool

    public let title: String?
    public let slug: String?
    public let icon: String?
    public let eventId: String?
    public let eventSlug: String?
    public let eventTitle: String?
    public let groupItemTitle: String?

    public let outcome: String?
    public let outcomeIndex: Int?
    public let oppositeOutcome: String?
    public let oppositeTokenId: String?

    public let endDate: String?
    public let lastEventAt: Int?
    public let firstEntryAt: Int?

    public var id: String { "\(proxyWallet)-\(tokenId)" }

    private enum CodingKeys: String, CodingKey {
        case proxyWallet = "proxy_wallet"
        case tokenId = "token_id"
        case conditionId = "condition_id"
        case currentSize = "current_size"
        case avgPrice = "avg_price"
        case entryCostUsdc = "entry_cost_usdc"
        case entryFeesUsdc = "entry_fees_usdc"
        case totalCostUsdc = "total_cost_usdc"
        case currentPrice = "current_price"
        case currentValue = "current_value"
        case totalSize = "total_size"
        case realizedPnl = "realized_pnl"
        case unrealizedPnl = "unrealized_pnl"
        case totalPnl = "total_pnl"
        case percentPnl = "percent_pnl"
        case percentRealizedPnl = "percent_realized_pnl"
        case status, redeemable, mergeable, archived
        case negativeRisk = "negative_risk"
        case title, slug, icon, outcome
        case eventId = "event_id"
        case eventSlug = "event_slug"
        case eventTitle = "event_title"
        case groupItemTitle = "group_item_title"
        case outcomeIndex = "outcome_index"
        case oppositeOutcome = "opposite_outcome"
        case oppositeTokenId = "opposite_token_id"
        case endDate = "end_date"
        case lastEventAt = "last_event_at"
        case firstEntryAt = "first_entry_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxyWallet = try c.decodeIfPresent(String.self, forKey: .proxyWallet) ?? ""
        tokenId = try c.decodeIfPresent(String.self, forKey: .tokenId) ?? ""
        conditionId = try c.decodeIfPresent(String.self, forKey: .conditionId) ?? ""
        currentSize = try c.decodeIfPresent(LenientDouble.self, forKey: .currentSize)?.value ?? 0
        avgPrice = try c.decodeIfPresent(LenientDouble.self, forKey: .avgPrice)?.value ?? 0
        entryCostUsdc = try c.decodeIfPresent(LenientDouble.self, forKey: .entryCostUsdc)?.value ?? 0
        entryFeesUsdc = try c.decodeIfPresent(LenientDouble.self, forKey: .entryFeesUsdc)?.value ?? 0
        totalCostUsdc = try c.decodeIfPresent(LenientDouble.self, forKey: .totalCostUsdc)?.value ?? 0
        currentPrice = try c.decodeIfPresent(LenientDouble.self, forKey: .currentPrice)?.value ?? 0
        currentValue = try c.decodeIfPresent(LenientDouble.self, forKey: .currentValue)?.value ?? 0
        totalSize = try c.decodeIfPresent(LenientDouble.self, forKey: .totalSize)?.value ?? 0
        realizedPnl = try c.decodeIfPresent(LenientDouble.self, forKey: .realizedPnl)?.value ?? 0
        unrealizedPnl = try c.decodeIfPresent(LenientDouble.self, forKey: .unrealizedPnl)?.value ?? 0
        totalPnl = try c.decodeIfPresent(LenientDouble.self, forKey: .totalPnl)?.value ?? 0
        percentPnl = try c.decodeIfPresent(LenientDouble.self, forKey: .percentPnl)?.value ?? 0
        percentRealizedPnl = try c.decodeIfPresent(LenientDouble.self, forKey: .percentRealizedPnl)?.value ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status)
        redeemable = try c.decodeIfPresent(LenientBool.self, forKey: .redeemable)?.value ?? false
        mergeable = try c.decodeIfPresent(LenientBool.self, forKey: .mergeable)?.value ?? false
        negativeRisk = try c.decodeIfPresent(LenientBool.self, forKey: .negativeRisk)?.value ?? false
        archived = try c.decodeIfPresent(LenientBool.self, forKey: .archived)?.value ?? false
        title = try c.decodeIfPresent(String.self, forKey: .title)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        eventId = try c.decodeIfPresent(String.self, forKey: .eventId)
        eventSlug = try c.decodeIfPresent(String.self, forKey: .eventSlug)
        eventTitle = try c.decodeIfPresent(String.self, forKey: .eventTitle)
        groupItemTitle = try c.decodeIfPresent(String.self, forKey: .groupItemTitle)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        outcomeIndex = try c.decodeIfPresent(LenientInt.self, forKey: .outcomeIndex)?.value
        oppositeOutcome = try c.decodeIfPresent(String.self, forKey: .oppositeOutcome)
        oppositeTokenId = try c.decodeIfPresent(String.self, forKey: .oppositeTokenId)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        lastEventAt = try c.decodeIfPresent(LenientInt.self, forKey: .lastEventAt)?.value
        firstEntryAt = try c.decodeIfPresent(LenientInt.self, forKey: .firstEntryAt)?.value
    }

    /// What the position would pay out if this outcome resolves true:
    /// every share settles at exactly $1.
    public var payoutIfWon: Double { currentSize }

    public var displayTitle: String {
        if let g = groupItemTitle, !g.isEmpty,
           let e = eventTitle, !e.isEmpty {
            return "\(e) — \(g)"
        }
        return title ?? eventTitle ?? slug ?? "Position"
    }

    public var resolvedEndDate: Date? { PolyDate.parse(endDate) }
}

// MARK: - Activity

/// Kinds of on-chain activity reported by `GET /v2/activity`.
public enum ActivityType: String, Codable, Hashable, Sendable {
    case trade = "TRADE"
    case split = "SPLIT"
    case merge = "MERGE"
    case redeem = "REDEEM"
    case reward = "REWARD"
    case conversion = "CONVERSION"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ActivityType(rawValue: raw.uppercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .trade: "Trade"
        case .split: "Split"
        case .merge: "Merge"
        case .redeem: "Redeem"
        case .reward: "Reward"
        case .conversion: "Conversion"
        case .unknown: "Activity"
        }
    }
}

public struct ActivityItem: Decodable, Identifiable, Hashable, Sendable {
    public let proxyWallet: String
    public let timestamp: Int
    public let conditionId: String?
    public let type: ActivityType
    public let size: Double
    public let usdcSize: Double
    public let transactionHash: String?
    public let price: Double
    public let tokenId: String?
    public let side: String?
    public let outcomeIndex: Int?
    public let title: String?
    public let slug: String?
    public let icon: String?
    public let eventSlug: String?
    public let outcome: String?
    public let name: String?
    public let pseudonym: String?

    public var id: String {
        "\(transactionHash ?? "")-\(tokenId ?? "")-\(timestamp)-\(type.rawValue)-\(size)"
    }

    private enum CodingKeys: String, CodingKey {
        case proxyWallet = "proxy_wallet"
        case timestamp, type, size, price, side, title, slug, icon, outcome, name, pseudonym
        case conditionId = "condition_id"
        case usdcSize = "usdc_size"
        case transactionHash = "transaction_hash"
        case tokenId = "token_id"
        case outcomeIndex = "outcome_index"
        case eventSlug = "event_slug"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxyWallet = try c.decodeIfPresent(String.self, forKey: .proxyWallet) ?? ""
        timestamp = try c.decodeIfPresent(LenientInt.self, forKey: .timestamp)?.value ?? 0
        conditionId = try c.decodeIfPresent(String.self, forKey: .conditionId)
        type = (try? c.decode(ActivityType.self, forKey: .type)) ?? .unknown
        size = try c.decodeIfPresent(LenientDouble.self, forKey: .size)?.value ?? 0
        usdcSize = try c.decodeIfPresent(LenientDouble.self, forKey: .usdcSize)?.value ?? 0
        transactionHash = try c.decodeIfPresent(String.self, forKey: .transactionHash)
        price = try c.decodeIfPresent(LenientDouble.self, forKey: .price)?.value ?? 0
        tokenId = try c.decodeIfPresent(String.self, forKey: .tokenId)
        side = try c.decodeIfPresent(String.self, forKey: .side)
        outcomeIndex = try c.decodeIfPresent(LenientInt.self, forKey: .outcomeIndex)?.value
        title = try c.decodeIfPresent(String.self, forKey: .title)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        eventSlug = try c.decodeIfPresent(String.self, forKey: .eventSlug)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        pseudonym = try c.decodeIfPresent(String.self, forKey: .pseudonym)
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

    /// `outcome_index` is 999 on non-trade rows (merge/redeem), which must not
    /// be rendered as an outcome.
    public var hasOutcome: Bool {
        guard let i = outcomeIndex else { return false }
        return i >= 0 && i < 100 && !(outcome ?? "").isEmpty
    }

    public var orderSide: OrderSide? {
        guard let side, !side.isEmpty else { return nil }
        return OrderSide(rawValue: side.uppercased())
    }
}

// MARK: - Portfolio value & user stats

public struct PortfolioValue: Decodable, Sendable {
    public let proxyWallet: String?
    public let value: Double

    private enum CodingKeys: String, CodingKey {
        case proxyWallet = "proxy_wallet"
        case value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxyWallet = try c.decodeIfPresent(String.self, forKey: .proxyWallet)
        value = try c.decodeIfPresent(LenientDouble.self, forKey: .value)?.value ?? 0
    }

    public init(proxyWallet: String?, value: Double) {
        self.proxyWallet = proxyWallet
        self.value = value
    }
}

public struct UserStats: Decodable, Sendable {
    public let proxyWallet: String?
    public let trades: Int?
    public let biggestWin: Double?
    public let joinDate: Int?
    public let allTimePnl: AllTimePnl?

    public struct AllTimePnl: Decodable, Sendable {
        public let realizedPnl: Double?
        public let unrealizedPnl: Double?
        public let volume: Double?
        public let tradeCount: Int?
        public let feesPaid: Double?

        private enum CodingKeys: String, CodingKey {
            case realizedPnl = "realized_pnl"
            case unrealizedPnl = "unrealized_pnl"
            case volume
            case tradeCount = "trade_count"
            case feesPaid = "fees_paid"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            realizedPnl = try c.decodeIfPresent(LenientDouble.self, forKey: .realizedPnl)?.value
            unrealizedPnl = try c.decodeIfPresent(LenientDouble.self, forKey: .unrealizedPnl)?.value
            volume = try c.decodeIfPresent(LenientDouble.self, forKey: .volume)?.value
            tradeCount = try c.decodeIfPresent(LenientInt.self, forKey: .tradeCount)?.value
            feesPaid = try c.decodeIfPresent(LenientDouble.self, forKey: .feesPaid)?.value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case proxyWallet = "proxy_wallet"
        case trades
        case biggestWin = "biggest_win"
        case joinDate = "join_date"
        case allTimePnl = "all_time_pnl"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxyWallet = try c.decodeIfPresent(String.self, forKey: .proxyWallet)
        trades = try c.decodeIfPresent(LenientInt.self, forKey: .trades)?.value
        biggestWin = try c.decodeIfPresent(LenientDouble.self, forKey: .biggestWin)?.value
        joinDate = try c.decodeIfPresent(LenientInt.self, forKey: .joinDate)?.value
        allTimePnl = try c.decodeIfPresent(AllTimePnl.self, forKey: .allTimePnl)
    }
}

// MARK: - Holders

public struct Holder: Decodable, Identifiable, Hashable, Sendable {
    public let proxyWallet: String
    public let tokenId: String?
    public let amount: Double
    public let name: String?
    public let pseudonym: String?
    public let profileImage: String?
    public let outcomeIndex: Int?
    public let verified: Bool?

    public var id: String { "\(proxyWallet)-\(tokenId ?? "")" }

    private enum CodingKeys: String, CodingKey {
        case proxyWallet = "proxy_wallet"
        case tokenId = "token_id"
        case amount, name, pseudonym, verified
        case profileImage = "profile_image"
        case outcomeIndex = "outcome_index"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxyWallet = try c.decodeIfPresent(String.self, forKey: .proxyWallet) ?? ""
        tokenId = try c.decodeIfPresent(String.self, forKey: .tokenId)
        amount = try c.decodeIfPresent(LenientDouble.self, forKey: .amount)?.value ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name)
        pseudonym = try c.decodeIfPresent(String.self, forKey: .pseudonym)
        profileImage = try c.decodeIfPresent(String.self, forKey: .profileImage)
        outcomeIndex = try c.decodeIfPresent(LenientInt.self, forKey: .outcomeIndex)?.value
        verified = try c.decodeIfPresent(LenientBool.self, forKey: .verified)?.value
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let pseudonym, !pseudonym.isEmpty { return pseudonym }
        return String(proxyWallet.prefix(8))
    }
}

/// `GET /v2/holders` groups holders under each token.
public struct TokenHolders: Decodable, Sendable {
    public let tokenId: String?
    public let holders: [Holder]

    private enum CodingKeys: String, CodingKey {
        case tokenId = "token_id"
        case holders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tokenId = try c.decodeIfPresent(String.self, forKey: .tokenId)
        holders = try c.decodeIfPresent([Holder].self, forKey: .holders) ?? []
    }
}

// MARK: - Trades

/// A public trade on a market, from `GET /v2/trades`.
public struct MarketTrade: Decodable, Identifiable, Hashable, Sendable {
    public let proxyWallet: String
    public let side: OrderSide?
    public let tokenId: String?
    public let conditionId: String?
    public let size: Double
    public let price: Double
    public let timestamp: Int
    public let outcome: String?
    public let outcomeIndex: Int?
    public let name: String?
    public let pseudonym: String?
    public let transactionHash: String?

    public var id: String { "\(transactionHash ?? "")-\(proxyWallet)-\(timestamp)-\(size)-\(price)" }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

    /// Notional value of the trade in USDC.
    public var notional: Double { size * price }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let pseudonym, !pseudonym.isEmpty { return pseudonym }
        return String(proxyWallet.prefix(8))
    }

    private enum CodingKeys: String, CodingKey {
        case side, size, price, timestamp, outcome, name, pseudonym
        case proxyWallet = "proxy_wallet"
        case tokenId = "token_id"
        case conditionId = "condition_id"
        case outcomeIndex = "outcome_index"
        case transactionHash = "transaction_hash"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxyWallet = try c.decodeIfPresent(String.self, forKey: .proxyWallet) ?? ""
        side = (try c.decodeIfPresent(String.self, forKey: .side))
            .flatMap { OrderSide(rawValue: $0.uppercased()) }
        tokenId = try c.decodeIfPresent(String.self, forKey: .tokenId)
        conditionId = try c.decodeIfPresent(String.self, forKey: .conditionId)
        size = try c.decodeIfPresent(LenientDouble.self, forKey: .size)?.value ?? 0
        price = try c.decodeIfPresent(LenientDouble.self, forKey: .price)?.value ?? 0
        timestamp = try c.decodeIfPresent(LenientInt.self, forKey: .timestamp)?.value ?? 0
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        outcomeIndex = try c.decodeIfPresent(LenientInt.self, forKey: .outcomeIndex)?.value
        name = try c.decodeIfPresent(String.self, forKey: .name)
        pseudonym = try c.decodeIfPresent(String.self, forKey: .pseudonym)
        transactionHash = try c.decodeIfPresent(String.self, forKey: .transactionHash)
    }
}
