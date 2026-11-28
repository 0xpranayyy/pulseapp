import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Hosts and shared configuration.
/// Base URLs from https://docs.polymarket.com/getting-started/api.
public enum PolymarketHost {
    public static let gamma = URL(string: "https://gamma-api.polymarket.com")!
    public static let clob = URL(string: "https://clob.polymarket.com")!
    public static let data = URL(string: "https://data-api.polymarket.com")!
    public static let marketSocket = URL(string: "wss://ws-subscriptions-clob.polymarket.com/ws/market")!
    public static let userSocket = URL(string: "wss://ws-subscriptions-clob.polymarket.com/ws/user")!
}

/// App-level configuration, including the optional builder code.
public struct PulseConfiguration: Sendable {
    /// A registered builder code (`bytes32`) that attributes orders to this
    /// app. Obtained from polymarket.com → Settings → Builders.
    /// When nil, orders carry the zero value and earn no attribution.
    public let builderCode: String?
    /// Builder fee in basis points, if the builder profile charges one.
    public let builderFeeBps: Int?

    /// Privy app and client identifiers. Both are public values that ship in
    /// the bundle. The Privy *app secret* is a server credential and must
    /// never reach the app — it is not represented here on purpose.
    public let privyAppId: String?
    public let privyClientId: String?
    /// The Pulse relay server (`server/pulse-relay`), which holds the Builder
    /// API credentials for gasless Deposit Wallet setup. Nil when not deployed.
    public let relayURL: URL?

    public init(
        builderCode: String? = nil,
        builderFeeBps: Int? = nil,
        privyAppId: String? = nil,
        privyClientId: String? = nil,
        relayURL: URL? = nil
    ) {
        self.builderCode = builderCode
        self.builderFeeBps = builderFeeBps
        self.privyAppId = privyAppId
        self.privyClientId = privyClientId
        self.relayURL = relayURL
    }

    public static let `default` = PulseConfiguration()

    /// The value to place in an order's `builder` field.
    public var builderField: String {
        guard let builderCode,
              let data = Data(hexString: builderCode),
              data.count == 32 else {
            return PolymarketOrder.zeroBytes32
        }
        return builderCode
    }
}

// MARK: - Gamma

/// Market and event discovery.
///
/// Gamma is public — no credentials — and is the only source for event
/// grouping, descriptions, images and tags.
public actor GammaService {
    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient(baseURL: PolymarketHost.gamma)) {
        self.client = client
    }

    /// Sort orders accepted by `GET /events`.
    public enum Sort: String, Sendable, CaseIterable {
        case volume24hr
        case volume
        case liquidity
        case startDate
        case endDate
        case competitive

        public var displayName: String {
            switch self {
            case .volume24hr: "Trending"
            case .volume: "Total volume"
            case .liquidity: "Most liquid"
            case .startDate: "Newest"
            case .endDate: "Ending soon"
            case .competitive: "Closest call"
            }
        }

        /// Ending-soon reads ascending; everything else descending.
        public var ascending: Bool { self == .endDate }
    }

    /// Lists events, which is what the feed renders.
    public func events(
        limit: Int = 24,
        offset: Int = 0,
        sort: Sort = .volume24hr,
        tagSlug: String? = nil,
        closed: Bool? = false,
        active: Bool? = true,
        minVolume: Double? = nil
    ) async throws -> [Event] {
        var query: [String: String?] = [
            "limit": String(limit),
            "offset": String(offset),
            "order": sort.rawValue,
            "ascending": sort.ascending ? "true" : "false",
            "archived": "false"
        ]
        if let closed { query["closed"] = closed ? "true" : "false" }
        if let active { query["active"] = active ? "true" : "false" }
        if let tagSlug, !tagSlug.isEmpty { query["tag_slug"] = tagSlug }
        if let minVolume { query["volume_num_min"] = String(minVolume) }
        // Ending-soon must exclude already-expired events.
        if sort == .endDate {
            query["end_date_min"] = ISO8601DateFormatter().string(from: Date())
        }

        return try await client.get(
            "/events", query: query, as: [Event].self, freshness: .list
        )
    }

    public func event(id: String) async throws -> Event? {
        let events = try await client.get(
            "/events", query: ["id": id], as: [Event].self, freshness: .list
        )
        return events.first
    }

    public func event(slug: String) async throws -> Event? {
        let events = try await client.get(
            "/events", query: ["slug": slug], as: [Event].self, freshness: .list
        )
        return events.first
    }

    public func market(id: String) async throws -> Market? {
        let markets = try await client.get(
            "/markets", query: ["id": id], as: [Market].self, freshness: .list
        )
        return markets.first
    }

    /// The Polymarket account that a signing address controls, if any.
    ///
    /// Returns the account wallet (`proxyWallet`), whose type is then read
    /// off its address with `WalletDerivation.classify`. Nil when the address
    /// has no Polymarket profile.
    public func accountWallet(forSigner address: String) async throws -> String? {
        struct Profile: Decodable { let proxyWallet: String? }
        do {
            let profile: Profile = try await client.send(HTTPRequest(
                path: "/public-profile", query: ["address": address]
            ))
            return profile.proxyWallet
        } catch APIError.http(status: 404, _) {
            return nil
        }
    }

    public func markets(conditionIds: [String]) async throws -> [Market] {
        guard !conditionIds.isEmpty else { return [] }
        // Gamma accepts repeated condition_ids parameters; the HTTP client
        // builds one value, so fetch in a small concurrent batch instead.
        return try await withThrowingTaskGroup(of: [Market].self) { group in
            for id in conditionIds.prefix(20) {
                group.addTask { [client] in
                    (try? await client.get("/markets", query: ["condition_ids": id], as: [Market].self)) ?? []
                }
            }
            var all: [Market] = []
            for try await batch in group { all.append(contentsOf: batch) }
            return all
        }
    }

    /// Full-text search across events.
    public func search(_ term: String, limit: Int = 20) async throws -> [Event] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await client.get(
            "/events",
            query: [
                "limit": String(limit),
                "active": "true",
                "closed": "false",
                "archived": "false",
                "order": "volume24hr",
                "ascending": "false",
                "title_contains": trimmed
            ],
            as: [Event].self,
            freshness: .list
        )
    }

    public func tags(limit: Int = 60) async throws -> [Tag] {
        try await client.get(
            "/tags",
            query: ["limit": String(limit), "is_carousel": "true"],
            as: [Tag].self,
            freshness: .reference
        )
    }
}

// MARK: - CLOB

/// Prices, books and order management.
///
/// Every request here is `.live`: a cached order book is a wrong order book,
/// and a trade sized against one loses money. Only `prices-history`, which
/// is immutable apart from its newest point, is allowed to come from cache.
public actor ClobService {
    private let client: HTTPClient
    private let authenticator: ClobAuthenticator
    private let configuration: PulseConfiguration

    public init(
        authenticator: ClobAuthenticator,
        configuration: PulseConfiguration = .default,
        session: URLSession = NetworkCache.session
    ) {
        self.authenticator = authenticator
        self.configuration = configuration
        self.client = HTTPClient(
            baseURL: PolymarketHost.clob,
            session: session,
            authorizer: authenticator
        )
    }

    // MARK: Public market data

    public func book(tokenId: String) async throws -> OrderBook {
        try await client.get("/book", query: ["token_id": tokenId], as: OrderBook.self)
    }

    /// Fetches both sides of a binary market concurrently.
    ///
    /// The "no" side is best-effort: a market can legitimately expose only one
    /// token, and failing the whole call because the complement is missing
    /// would blank a screen that has everything it needs.
    public func books(yes: String, no: String?) async throws -> (yes: OrderBook, no: OrderBook?) {
        let yesTask = Task { try await self.book(tokenId: yes) }
        let noTask = no.map { id in Task { try? await self.book(tokenId: id) } }
        let yesBook = try await yesTask.value
        let noBook = await noTask?.value ?? nil
        return (yesBook, noBook)
    }

    public func price(tokenId: String, side: OrderSide) async throws -> Double {
        try await client.get(
            "/price",
            query: ["token_id": tokenId, "side": side.rawValue],
            as: PriceResponse.self
        ).price
    }

    public func midpoint(tokenId: String) async throws -> Double {
        try await client.get("/midpoint", query: ["token_id": tokenId], as: MidpointResponse.self).mid
    }

    public func spread(tokenId: String) async throws -> Double {
        try await client.get("/spread", query: ["token_id": tokenId], as: SpreadResponse.self).spread
    }

    public func tickSize(tokenId: String) async throws -> Double {
        try await client.get(
            "/tick-size",
            query: ["token_id": tokenId],
            as: TickSizeResponse.self
        ).minimumTickSize
    }

    /// Historical prices for the chart.
    public func priceHistory(
        tokenId: String,
        interval: PriceHistoryInterval
    ) async throws -> [PricePoint] {
        let response = try await client.get(
            "/prices-history",
            query: [
                "market": tokenId,
                "interval": interval.rawValue,
                "fidelity": String(interval.fidelity)
            ],
            as: PriceHistoryResponse.self,
            freshness: .list
        )
        return response.history.sorted { $0.t < $1.t }
    }

    // MARK: Authenticated

    public func openOrders() async throws -> [OpenOrder] {
        try await client.send(
            HTTPRequest(path: "/data/orders", requiresAuth: true),
            as: [OpenOrder].self
        )
    }

    /// Submits a signed order.
    ///
    /// The body is serialized once and reused for both the L2 signature and
    /// the request, because the HMAC covers the exact bytes on the wire.
    public func submit(
        order: PolymarketOrder,
        signature: String,
        orderType: OrderType
    ) async throws -> OrderPlacementResponse {
        guard let credentials = await authenticator.credentials else {
            throw APIError.unauthorized
        }

        let submission = OrderSubmission(
            order: order,
            signature: signature,
            orderType: orderType,
            owner: credentials.apiKey
        )
        let body = try submission.serialized()

        let response: OrderPlacementResponse = try await client.send(
            HTTPRequest(method: .post, path: "/order", body: body, requiresAuth: true),
            as: OrderPlacementResponse.self
        )

        // The CLOB reports business failures inside a 200 response.
        guard response.isAccepted else {
            throw APIError.server(message: response.errorMsg ?? "Order was rejected.")
        }
        return response
    }

    public func cancel(orderId: String) async throws {
        struct CancelBody: Encodable { let orderID: String }
        let body = try JSONEncoder().encode(CancelBody(orderID: orderId))
        _ = try await client.data(
            for: HTTPRequest(method: .delete, path: "/order", body: body, requiresAuth: true)
        )
    }

    /// Refreshes the CLOB's cached balance and allowances for the account,
    /// required after approvals change.
    public func updateBalanceAllowance(signatureType: SignatureType) async throws {
        _ = try await client.data(for: HTTPRequest(
            path: "/balance-allowance/update",
            query: ["asset_type": "COLLATERAL", "signature_type": String(signatureType.rawValue)],
            requiresAuth: true
        ))
    }

    /// Spendable pUSD in the account wallet, in dollars.
    public func collateralBalance(signatureType: SignatureType) async throws -> Double {
        struct Response: Decodable { let balance: String }
        let response: Response = try await client.send(HTTPRequest(
            path: "/balance-allowance",
            query: ["asset_type": "COLLATERAL", "signature_type": String(signatureType.rawValue)],
            requiresAuth: true
        ))
        // pUSD has six decimals.
        return (Double(response.balance) ?? 0) / 1_000_000
    }

    public func cancelAll() async throws {
        _ = try await client.data(
            for: HTTPRequest(method: .delete, path: "/cancel-all", requiresAuth: true)
        )
    }

    /// Exchanges an L1 wallet signature for L2 API credentials, deriving
    /// existing ones when the wallet already has a key for this nonce.
    public func deriveOrCreateCredentials(
        signer: EthereumSigner,
        nonce: UInt64 = 0
    ) async throws -> ClobCredentials {
        let headers = try await ClobAuthenticator.l1Headers(signer: signer, nonce: nonce)

        // Prefer deriving: creating twice for the same nonce is an error.
        if let existing = try? await client.send(
            HTTPRequest(path: "/auth/derive-api-key", headers: headers),
            as: ClobCredentials.self
        ) {
            return existing
        }

        return try await client.send(
            HTTPRequest(method: .post, path: "/auth/api-key", headers: headers),
            as: ClobCredentials.self
        )
    }
}

// MARK: - Data API v2

/// Positions, activity and portfolio value.
///
/// Also `.live` throughout. A stale balance makes the trade sheet allow an
/// order the wallet cannot fund.
///
/// Note this targets **v2** exclusively: v1 returns HTTP 410.
public actor DataService {
    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient(baseURL: PolymarketHost.data)) {
        self.client = client
    }

    public func positions(
        user: String,
        status: PositionStatus = .open,
        limit: Int = 50,
        cursor: String? = nil
    ) async throws -> Page<Position> {
        var query: [String: String?] = [
            "user": user,
            "status": status.rawValue,
            "limit": String(limit)
        ]
        if let cursor { query["cursor"] = cursor }

        let envelope = try await client.get(
            "/v2/positions",
            query: query,
            as: DataEnvelope<[Position]>.self
        )
        return Page(
            items: envelope.data ?? [],
            nextCursor: envelope.pagination?.nextCursor,
            hasMore: envelope.pagination?.hasMore ?? false
        )
    }

    public func activity(
        user: String,
        limit: Int = 50,
        cursor: String? = nil
    ) async throws -> Page<ActivityItem> {
        var query: [String: String?] = ["user": user, "limit": String(limit)]
        if let cursor { query["cursor"] = cursor }

        let envelope = try await client.get(
            "/v2/activity",
            query: query,
            as: DataEnvelope<[ActivityItem]>.self
        )
        return Page(
            items: envelope.data ?? [],
            nextCursor: envelope.pagination?.nextCursor,
            hasMore: envelope.pagination?.hasMore ?? false
        )
    }

    /// Total current value of a wallet's positions.
    public func portfolioValue(user: String) async throws -> Double {
        let envelope = try await client.get(
            "/v2/value",
            query: ["user": user],
            as: DataEnvelope<PortfolioValue>.self
        )
        return envelope.data?.value ?? 0
    }

    public func userStats(user: String) async throws -> UserStats? {
        let envelope = try await client.get(
            "/v2/user-stats",
            query: ["user": user],
            as: DataEnvelope<UserStats>.self
        )
        return envelope.data
    }

    /// Recent public trades on a market.
    public func trades(
        conditionId: String,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> Page<MarketTrade> {
        var query: [String: String?] = ["condition": conditionId, "limit": String(limit)]
        if let cursor { query["cursor"] = cursor }

        let envelope = try await client.get(
            "/v2/trades",
            query: query,
            as: DataEnvelope<[MarketTrade]>.self
        )
        return Page(
            items: envelope.data ?? [],
            nextCursor: envelope.pagination?.nextCursor,
            hasMore: envelope.pagination?.hasMore ?? false
        )
    }

    public func holders(conditionId: String, limit: Int = 20) async throws -> [TokenHolders] {
        let envelope = try await client.get(
            "/v2/holders",
            query: ["condition": conditionId, "limit": String(limit)],
            as: DataEnvelope<[TokenHolders]>.self
        )
        return envelope.data ?? []
    }
}
