import Foundation

// MARK: - Gamma API models
//
// Field names and nullability verified against live responses from
// https://gamma-api.polymarket.com on 2026-11-27. Almost everything is
// optional: Gamma omits fields freely depending on market type and lifecycle,
// and a missing field must never fail the whole page of results.

/// A tradable binary outcome market. In Polymarket's model an `Event` groups
/// one or more `Market`s; a single-market event is the familiar Yes/No market,
/// while a multi-market event is a mutually exclusive set (e.g. "who wins?").
public struct Market: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let question: String?
    public let conditionId: String?
    public let slug: String?
    public let description: String?
    public let resolutionSource: String?

    public let image: String?
    public let icon: String?

    /// Display title when this market is one leg of a multi-outcome event,
    /// e.g. "<50,000" or "54,000".
    public let groupItemTitle: String?

    // Outcomes. Gamma encodes these as JSON *strings*.
    public let outcomes: JSONStringArray?
    public let outcomePrices: JSONStringArray?
    public let clobTokenIds: JSONStringArray?

    // Lifecycle
    public let active: Bool?
    public let closed: Bool?
    public let archived: Bool?
    public let acceptingOrders: Bool?
    public let enableOrderBook: Bool?
    public let restricted: Bool?

    // Dates
    public let startDate: String?
    public let endDate: String?
    public let endDateIso: String?

    // Economics — note the string/number split.
    public let liquidity: LenientDouble?
    public let liquidityNum: LenientDouble?
    public let volume: LenientDouble?
    public let volumeNum: LenientDouble?
    public let volume24hr: LenientDouble?
    public let volume1wk: LenientDouble?
    public let volume1mo: LenientDouble?

    // Order book state
    public let bestBid: LenientDouble?
    public let bestAsk: LenientDouble?
    public let lastTradePrice: LenientDouble?
    public let spread: LenientDouble?
    public let oneDayPriceChange: LenientDouble?
    public let oneHourPriceChange: LenientDouble?

    // Trading constraints
    public let orderPriceMinTickSize: LenientDouble?
    public let orderMinSize: LenientDouble?

    // Negative risk (multi-outcome capital efficiency)
    public let negRisk: Bool?
    public let negRiskMarketID: String?

    // Fees
    public let feesEnabled: Bool?
    public let feeType: String?

    public let competitive: LenientDouble?
    public let umaResolutionStatuses: JSONStringArray?

    public init(
        id: String,
        question: String? = nil,
        conditionId: String? = nil,
        slug: String? = nil,
        description: String? = nil,
        resolutionSource: String? = nil,
        image: String? = nil,
        icon: String? = nil,
        groupItemTitle: String? = nil,
        outcomes: JSONStringArray? = nil,
        outcomePrices: JSONStringArray? = nil,
        clobTokenIds: JSONStringArray? = nil,
        active: Bool? = nil,
        closed: Bool? = nil,
        archived: Bool? = nil,
        acceptingOrders: Bool? = nil,
        enableOrderBook: Bool? = nil,
        restricted: Bool? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        endDateIso: String? = nil,
        liquidity: LenientDouble? = nil,
        liquidityNum: LenientDouble? = nil,
        volume: LenientDouble? = nil,
        volumeNum: LenientDouble? = nil,
        volume24hr: LenientDouble? = nil,
        volume1wk: LenientDouble? = nil,
        volume1mo: LenientDouble? = nil,
        bestBid: LenientDouble? = nil,
        bestAsk: LenientDouble? = nil,
        lastTradePrice: LenientDouble? = nil,
        spread: LenientDouble? = nil,
        oneDayPriceChange: LenientDouble? = nil,
        oneHourPriceChange: LenientDouble? = nil,
        orderPriceMinTickSize: LenientDouble? = nil,
        orderMinSize: LenientDouble? = nil,
        negRisk: Bool? = nil,
        negRiskMarketID: String? = nil,
        feesEnabled: Bool? = nil,
        feeType: String? = nil,
        competitive: LenientDouble? = nil,
        umaResolutionStatuses: JSONStringArray? = nil
    ) {
        self.id = id
        self.question = question
        self.conditionId = conditionId
        self.slug = slug
        self.description = description
        self.resolutionSource = resolutionSource
        self.image = image
        self.icon = icon
        self.groupItemTitle = groupItemTitle
        self.outcomes = outcomes
        self.outcomePrices = outcomePrices
        self.clobTokenIds = clobTokenIds
        self.active = active
        self.closed = closed
        self.archived = archived
        self.acceptingOrders = acceptingOrders
        self.enableOrderBook = enableOrderBook
        self.restricted = restricted
        self.startDate = startDate
        self.endDate = endDate
        self.endDateIso = endDateIso
        self.liquidity = liquidity
        self.liquidityNum = liquidityNum
        self.volume = volume
        self.volumeNum = volumeNum
        self.volume24hr = volume24hr
        self.volume1wk = volume1wk
        self.volume1mo = volume1mo
        self.bestBid = bestBid
        self.bestAsk = bestAsk
        self.lastTradePrice = lastTradePrice
        self.spread = spread
        self.oneDayPriceChange = oneDayPriceChange
        self.oneHourPriceChange = oneHourPriceChange
        self.orderPriceMinTickSize = orderPriceMinTickSize
        self.orderMinSize = orderMinSize
        self.negRisk = negRisk
        self.negRiskMarketID = negRiskMarketID
        self.feesEnabled = feesEnabled
        self.feeType = feeType
        self.competitive = competitive
        self.umaResolutionStatuses = umaResolutionStatuses
    }

    /// Gamma returns `id` as a string, but be tolerant of a number.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "Market.id missing or not a string/int"
            )
        }
        question = try c.decodeIfPresent(String.self, forKey: .question)
        conditionId = try c.decodeIfPresent(String.self, forKey: .conditionId)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        resolutionSource = try c.decodeIfPresent(String.self, forKey: .resolutionSource)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        groupItemTitle = try c.decodeIfPresent(String.self, forKey: .groupItemTitle)
        outcomes = try c.decodeIfPresent(JSONStringArray.self, forKey: .outcomes)
        outcomePrices = try c.decodeIfPresent(JSONStringArray.self, forKey: .outcomePrices)
        clobTokenIds = try c.decodeIfPresent(JSONStringArray.self, forKey: .clobTokenIds)
        active = try c.decodeIfPresent(LenientBool.self, forKey: .active)?.value
        closed = try c.decodeIfPresent(LenientBool.self, forKey: .closed)?.value
        archived = try c.decodeIfPresent(LenientBool.self, forKey: .archived)?.value
        acceptingOrders = try c.decodeIfPresent(LenientBool.self, forKey: .acceptingOrders)?.value
        enableOrderBook = try c.decodeIfPresent(LenientBool.self, forKey: .enableOrderBook)?.value
        restricted = try c.decodeIfPresent(LenientBool.self, forKey: .restricted)?.value
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        endDateIso = try c.decodeIfPresent(String.self, forKey: .endDateIso)
        liquidity = try c.decodeIfPresent(LenientDouble.self, forKey: .liquidity)
        liquidityNum = try c.decodeIfPresent(LenientDouble.self, forKey: .liquidityNum)
        volume = try c.decodeIfPresent(LenientDouble.self, forKey: .volume)
        volumeNum = try c.decodeIfPresent(LenientDouble.self, forKey: .volumeNum)
        volume24hr = try c.decodeIfPresent(LenientDouble.self, forKey: .volume24hr)
        volume1wk = try c.decodeIfPresent(LenientDouble.self, forKey: .volume1wk)
        volume1mo = try c.decodeIfPresent(LenientDouble.self, forKey: .volume1mo)
        bestBid = try c.decodeIfPresent(LenientDouble.self, forKey: .bestBid)
        bestAsk = try c.decodeIfPresent(LenientDouble.self, forKey: .bestAsk)
        lastTradePrice = try c.decodeIfPresent(LenientDouble.self, forKey: .lastTradePrice)
        spread = try c.decodeIfPresent(LenientDouble.self, forKey: .spread)
        oneDayPriceChange = try c.decodeIfPresent(LenientDouble.self, forKey: .oneDayPriceChange)
        oneHourPriceChange = try c.decodeIfPresent(LenientDouble.self, forKey: .oneHourPriceChange)
        orderPriceMinTickSize = try c.decodeIfPresent(LenientDouble.self, forKey: .orderPriceMinTickSize)
        orderMinSize = try c.decodeIfPresent(LenientDouble.self, forKey: .orderMinSize)
        negRisk = try c.decodeIfPresent(LenientBool.self, forKey: .negRisk)?.value
        negRiskMarketID = try c.decodeIfPresent(String.self, forKey: .negRiskMarketID)
        feesEnabled = try c.decodeIfPresent(LenientBool.self, forKey: .feesEnabled)?.value
        feeType = try c.decodeIfPresent(String.self, forKey: .feeType)
        competitive = try c.decodeIfPresent(LenientDouble.self, forKey: .competitive)
        umaResolutionStatuses = try c.decodeIfPresent(JSONStringArray.self, forKey: .umaResolutionStatuses)
    }
}

// MARK: - Market conveniences

public extension Market {
    /// Human label for the market, preferring the per-leg title inside a
    /// multi-outcome event.
    var displayTitle: String {
        if let g = groupItemTitle, !g.isEmpty { return g }
        return question ?? slug ?? id
    }

    var outcomeLabels: [String] { outcomes?.values ?? ["Yes", "No"] }
    var tokenIds: [String] { clobTokenIds?.values ?? [] }

    /// The CLOB token id for the "Yes" (index 0) outcome, if present.
    var yesTokenId: String? { tokenIds.first }
    /// The CLOB token id for the "No" (index 1) outcome, if present.
    var noTokenId: String? { tokenIds.count > 1 ? tokenIds[1] : nil }

    /// Probability of the first ("Yes") outcome as reported by Gamma, 0...1.
    ///
    /// Prefers the mid of best bid/ask because `outcomePrices` can lag; falls
    /// back to `outcomePrices`, then to `lastTradePrice`.
    var yesProbability: Double? {
        if let bid = bestBid?.value, let ask = bestAsk?.value, bid > 0 || ask > 0 {
            // Guard against a one-sided book reporting 0 on the empty side.
            if bid > 0 && ask > 0 { return (bid + ask) / 2 }
        }
        if let p = outcomePrices?.doubles.first { return p }
        if let l = lastTradePrice?.value { return l }
        if let bid = bestBid?.value, bid > 0 { return bid }
        if let ask = bestAsk?.value, ask > 0 { return ask }
        return nil
    }

    var noProbability: Double? { yesProbability.map { 1 - $0 } }

    /// 24h change in the Yes probability, in absolute probability points.
    var dayChange: Double? { oneDayPriceChange?.value }

    var volumeTotal: Double? { volumeNum?.value ?? volume?.value }
    var liquidityTotal: Double? { liquidityNum?.value ?? liquidity?.value }

    var resolvedEndDate: Date? { PolyDate.parse(endDate) ?? PolyDate.parse(endDateIso) }

    var tickSize: Double { orderPriceMinTickSize?.value ?? 0.001 }
    var minimumOrderSize: Double { orderMinSize?.value ?? 5 }

    /// Whether the app should allow placing an order. Gamma exposes several
    /// independent flags and all of them must agree.
    var isTradable: Bool {
        (active ?? false)
            && !(closed ?? false)
            && !(archived ?? false)
            && (acceptingOrders ?? false)
            && (enableOrderBook ?? false)
            && !tokenIds.isEmpty
    }
}

// MARK: - Event

/// A group of related markets. Single-market events are rendered as a plain
/// binary market; multi-market events get the outcome list treatment.
public struct Event: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let ticker: String?
    public let slug: String?
    public let title: String?
    public let description: String?
    public let resolutionSource: String?

    public let startDate: String?
    public let endDate: String?
    public let creationDate: String?

    public let image: String?
    public let icon: String?

    public let active: Bool?
    public let closed: Bool?
    public let archived: Bool?
    public let new: Bool?
    public let featured: Bool?
    public let restricted: Bool?

    public let liquidity: LenientDouble?
    public let volume: LenientDouble?
    public let volume24hr: LenientDouble?
    public let volume1wk: LenientDouble?
    public let openInterest: LenientDouble?
    public let competitive: LenientDouble?
    public let commentCount: LenientInt?

    public let negRisk: Bool?
    public let enableNegRisk: Bool?
    public let showAllOutcomes: Bool?
    public let showMarketImages: Bool?

    public let markets: [Market]?
    public let tags: [Tag]?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "Event.id missing or not a string/int"
            )
        }
        ticker = try c.decodeIfPresent(String.self, forKey: .ticker)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        resolutionSource = try c.decodeIfPresent(String.self, forKey: .resolutionSource)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        creationDate = try c.decodeIfPresent(String.self, forKey: .creationDate)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        active = try c.decodeIfPresent(LenientBool.self, forKey: .active)?.value
        closed = try c.decodeIfPresent(LenientBool.self, forKey: .closed)?.value
        archived = try c.decodeIfPresent(LenientBool.self, forKey: .archived)?.value
        new = try c.decodeIfPresent(LenientBool.self, forKey: .new)?.value
        featured = try c.decodeIfPresent(LenientBool.self, forKey: .featured)?.value
        restricted = try c.decodeIfPresent(LenientBool.self, forKey: .restricted)?.value
        liquidity = try c.decodeIfPresent(LenientDouble.self, forKey: .liquidity)
        volume = try c.decodeIfPresent(LenientDouble.self, forKey: .volume)
        volume24hr = try c.decodeIfPresent(LenientDouble.self, forKey: .volume24hr)
        volume1wk = try c.decodeIfPresent(LenientDouble.self, forKey: .volume1wk)
        openInterest = try c.decodeIfPresent(LenientDouble.self, forKey: .openInterest)
        competitive = try c.decodeIfPresent(LenientDouble.self, forKey: .competitive)
        commentCount = try c.decodeIfPresent(LenientInt.self, forKey: .commentCount)
        negRisk = try c.decodeIfPresent(LenientBool.self, forKey: .negRisk)?.value
        enableNegRisk = try c.decodeIfPresent(LenientBool.self, forKey: .enableNegRisk)?.value
        showAllOutcomes = try c.decodeIfPresent(LenientBool.self, forKey: .showAllOutcomes)?.value
        showMarketImages = try c.decodeIfPresent(LenientBool.self, forKey: .showMarketImages)?.value
        markets = try c.decodeIfPresent([Market].self, forKey: .markets)
        tags = try c.decodeIfPresent([Tag].self, forKey: .tags)
    }
}

public extension Event {
    var displayTitle: String { title ?? slug ?? id }
    var tradableMarkets: [Market] { (markets ?? []).filter(\.isTradable) }

    /// True when the event should be shown as a list of competing outcomes
    /// rather than a single Yes/No market.
    var isMultiOutcome: Bool { (markets ?? []).count > 1 }

    /// For a single-market event, the one market.
    var primaryMarket: Market? {
        guard let markets, !markets.isEmpty else { return nil }
        if markets.count == 1 { return markets[0] }
        // Highest-probability leg reads best as the headline.
        return markets.max { ($0.yesProbability ?? 0) < ($1.yesProbability ?? 0) }
    }

    var volumeTotal: Double? { volume?.value }
    var volume24h: Double? { volume24hr?.value }
    var liquidityTotal: Double? { liquidity?.value }
    var resolvedEndDate: Date? { PolyDate.parse(endDate) }

    var imageURL: URL? {
        if let image, let u = URL(string: image) { return u }
        if let icon, let u = URL(string: icon) { return u }
        return nil
    }
}

// MARK: - Tag

public struct Tag: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String?
    public let slug: String?
    public let forceShow: Bool?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "Tag.id missing"
            )
        }
        label = try c.decodeIfPresent(String.self, forKey: .label)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        forceShow = try c.decodeIfPresent(LenientBool.self, forKey: .forceShow)?.value
    }

    public init(id: String, label: String?, slug: String?, forceShow: Bool? = nil) {
        self.id = id
        self.label = label
        self.slug = slug
        self.forceShow = forceShow
    }

    public var displayName: String { label ?? slug ?? id }
}
