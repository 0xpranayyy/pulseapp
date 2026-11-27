import XCTest
@testable import PulseCore

final class PortfolioTests: XCTestCase {

    private func position(
        value: Double,
        cost: Double,
        unrealized: Double,
        realized: Double = 0,
        size: Double = 100,
        redeemable: Bool = false,
        event: String = "Event A"
    ) throws -> Position {
        let json = """
        {"proxy_wallet":"0xabc","token_id":"\(UUID().uuidString)","condition_id":"0xc",
         "current_size":\(size),"avg_price":0.5,"entry_cost_usdc":\(cost),
         "entry_fees_usdc":0,"total_cost_usdc":\(cost),"current_price":0.6,
         "current_value":\(value),"total_size":\(size),"realized_pnl":\(realized),
         "unrealized_pnl":\(unrealized),"total_pnl":\(unrealized + realized),
         "percent_pnl":0,"percent_realized_pnl":0,"status":"OPEN",
         "redeemable":\(redeemable),"mergeable":false,"negative_risk":false,
         "archived":false,"event_title":"\(event)","outcome":"Yes","outcome_index":0}
        """
        return try JSONDecoder().decode(Position.self, from: Data(json.utf8))
    }

    func testEmptyPortfolioIsAllZeros() {
        let portfolio = Portfolio.empty
        XCTAssertEqual(portfolio.totalValue, 0)
        XCTAssertEqual(portfolio.totalPnl, 0)
        XCTAssertEqual(portfolio.openCount, 0)
        XCTAssertNil(portfolio.totalReturn, "no cost basis means no meaningful return")
        XCTAssertNil(portfolio.netWorth, "unknown cash must stay unknown, not become 0")
    }

    func testSumsAcrossPositions() throws {
        let portfolio = Portfolio(positions: [
            try position(value: 100, cost: 80, unrealized: 20),
            try position(value: 50, cost: 60, unrealized: -10)
        ])
        XCTAssertEqual(portfolio.positionsValue, 150, accuracy: 1e-9)
        XCTAssertEqual(portfolio.totalCost, 140, accuracy: 1e-9)
        XCTAssertEqual(portfolio.unrealizedPnl, 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(portfolio.totalReturn), 10.0 / 140.0, accuracy: 1e-9)
    }

    /// The API's own value is authoritative; the local sum is only a fallback.
    func testPrefersReportedValueOverLocalSum() throws {
        let portfolio = Portfolio(
            positions: [try position(value: 100, cost: 80, unrealized: 20)],
            reportedValue: 123.45
        )
        XCTAssertEqual(portfolio.totalValue, 123.45)
        XCTAssertEqual(portfolio.positionsValue, 100, accuracy: 1e-9)
    }

    func testNetWorthAddsCashOnlyWhenKnown() throws {
        let positions = [try position(value: 100, cost: 80, unrealized: 20)]
        XCTAssertNil(Portfolio(positions: positions).netWorth)
        XCTAssertEqual(
            try XCTUnwrap(Portfolio(positions: positions, availableBalance: 25).netWorth),
            125, accuracy: 1e-9
        )
    }

    func testRedeemableSubset() throws {
        let portfolio = Portfolio(positions: [
            try position(value: 100, cost: 80, unrealized: 20, redeemable: true),
            try position(value: 50, cost: 60, unrealized: -10)
        ])
        XCTAssertEqual(portfolio.redeemablePositions.count, 1)
        XCTAssertEqual(portfolio.redeemableValue, 100, accuracy: 1e-9)
    }

    func testMaximumPayoutIsShareCount() throws {
        // Every winning share settles at $1.
        let portfolio = Portfolio(positions: [
            try position(value: 60, cost: 50, unrealized: 10, size: 100),
            try position(value: 20, cost: 15, unrealized: 5, size: 50)
        ])
        XCTAssertEqual(portfolio.maximumPayout, 150, accuracy: 1e-9)
    }

    func testAllocationsSumToOne() throws {
        let portfolio = Portfolio(positions: [
            try position(value: 75, cost: 50, unrealized: 25),
            try position(value: 25, cost: 20, unrealized: 5)
        ])
        let allocations = portfolio.allocations()
        XCTAssertEqual(allocations.count, 2)
        XCTAssertEqual(allocations.reduce(0) { $0 + $1.share }, 1.0, accuracy: 1e-9)
        XCTAssertEqual(allocations[0].share, 0.75, accuracy: 1e-9, "largest first")
    }

    func testGroupsByEvent() throws {
        let portfolio = Portfolio(positions: [
            try position(value: 60, cost: 50, unrealized: 10, event: "Election"),
            try position(value: 40, cost: 30, unrealized: 10, event: "Election"),
            try position(value: 10, cost: 8, unrealized: 2, event: "Weather")
        ])
        let groups = portfolio.groupedByEvent()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].eventTitle, "Election", "largest group first")
        XCTAssertEqual(groups[0].positions.count, 2)
        XCTAssertEqual(groups[0].value, 100, accuracy: 1e-9)
    }

    func testIdentifiesBestAndWorst() throws {
        let portfolio = Portfolio(positions: [
            try position(value: 100, cost: 80, unrealized: 20),
            try position(value: 50, cost: 60, unrealized: -10)
        ])
        XCTAssertEqual(portfolio.biggestWinner?.unrealizedPnl, 20)
        XCTAssertEqual(portfolio.biggestLoser?.unrealizedPnl, -10)
    }
}

final class MarketSocketParsingTests: XCTestCase {

    func testParsesBookEvent() throws {
        let json = """
        {"event_type":"book","market":"0xabc","asset_id":"123","timestamp":"1782753357257",
         "bids":[{"price":"0.08","size":"33343.4"}],"asks":[{"price":"0.99","size":"218442.27"}]}
        """
        let events = MarketMessageParser.parse(Data(json.utf8))
        XCTAssertEqual(events.count, 1)
        guard case .book(let assetId, let book) = events[0] else {
            return XCTFail("expected a book event, got \(events[0])")
        }
        XCTAssertEqual(assetId, "123")
        XCTAssertEqual(book.bestBid, 0.08)
        XCTAssertEqual(book.bestAsk, 0.99)
    }

    /// One price_change frame can carry several assets.
    func testParsesBatchedPriceChanges() throws {
        let json = """
        {"event_type":"price_change","market":"0xabc","timestamp":"1782753357257",
         "price_changes":[
           {"asset_id":"111","price":"0.08","size":"33343.4","side":"BUY","best_bid":"0.08","best_ask":"0.09"},
           {"asset_id":"222","price":"0.92","size":"100","side":"SELL","best_bid":"0.91","best_ask":"0.92"}]}
        """
        let events = MarketMessageParser.parse(Data(json.utf8))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.assetId), ["111", "222"])

        guard case .priceChange(_, let price, let bid, let ask) = events[0] else {
            return XCTFail("expected a price change")
        }
        XCTAssertEqual(price, 0.08)
        XCTAssertEqual(bid, 0.08)
        XCTAssertEqual(ask, 0.09)
    }

    func testParsesLastTradePrice() throws {
        let json = """
        {"event_type":"last_trade_price","market":"0xabc","asset_id":"123",
         "price":"0.08","size":"219.217767","side":"SELL","timestamp":"1782753357257"}
        """
        let events = MarketMessageParser.parse(Data(json.utf8))
        guard case .lastTradePrice(let id, let price, let size, let side) = events.first else {
            return XCTFail("expected a last trade price")
        }
        XCTAssertEqual(id, "123")
        XCTAssertEqual(price, 0.08)
        XCTAssertEqual(size, 219.217767)
        XCTAssertEqual(side, .sell)
    }

    func testParsesTickSizeChange() throws {
        let json = """
        {"event_type":"tick_size_change","market":"0xabc","asset_id":"123",
         "old_tick_size":"0.01","new_tick_size":"0.001","timestamp":"1782753357257"}
        """
        guard case .tickSizeChange(_, let tick) = MarketMessageParser.parse(Data(json.utf8)).first else {
            return XCTFail("expected a tick size change")
        }
        XCTAssertEqual(tick, 0.001, "a stale tick size makes every later order invalid")
    }

    func testParsesBestBidAsk() throws {
        let json = """
        {"event_type":"best_bid_ask","market":"0xabc","asset_id":"123",
         "best_bid":"0.08","best_ask":"0.09","spread":"0.01","timestamp":"1"}
        """
        guard case .bestBidAsk(_, let bid, let ask, let spread) =
                MarketMessageParser.parse(Data(json.utf8)).first else {
            return XCTFail("expected best bid/ask")
        }
        XCTAssertEqual(bid, 0.08)
        XCTAssertEqual(ask, 0.09)
        XCTAssertEqual(spread, 0.01)
    }

    func testParsesArrayOfFrames() throws {
        let json = """
        [{"event_type":"last_trade_price","asset_id":"1","price":"0.5","size":"1","timestamp":"1"},
         {"event_type":"last_trade_price","asset_id":"2","price":"0.6","size":"1","timestamp":"1"}]
        """
        XCTAssertEqual(MarketMessageParser.parse(Data(json.utf8)).count, 2)
    }

    /// Unknown or malformed frames must be ignored, never crash the stream.
    func testIgnoresUnparseableFrames() {
        XCTAssertTrue(MarketMessageParser.parse(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(MarketMessageParser.parse(Data(#"{"event_type":"future_event"}"#.utf8)).isEmpty)
        XCTAssertTrue(MarketMessageParser.parse(Data(#"{"event_type":"book"}"#.utf8)).isEmpty)
        XCTAssertTrue(MarketMessageParser.parse(Data()).isEmpty)
    }
}

final class ClobAuthTests: XCTestCase {

    /// HMAC-SHA256 over timestamp + METHOD + path, keyed by the base64-decoded
    /// secret, URL-safe base64 out.
    func testL2SignatureIsStableAndKeyed() throws {
        let secret = Data("a-32-byte-test-secret-for-hmac!!".utf8).base64EncodedString()

        let a = try ClobAuthenticator.l2Signature(
            secret: secret, timestamp: "1700000000", method: "GET", path: "/data/orders", body: nil
        )
        let b = try ClobAuthenticator.l2Signature(
            secret: secret, timestamp: "1700000000", method: "GET", path: "/data/orders", body: nil
        )
        XCTAssertEqual(a, b, "same inputs must produce the same signature")
        XCTAssertFalse(a.contains("+"), "must use the URL-safe alphabet")
        XCTAssertFalse(a.contains("/"), "must use the URL-safe alphabet")
    }

    func testL2SignatureCoversEveryInput() throws {
        let secret = Data("a-32-byte-test-secret-for-hmac!!".utf8).base64EncodedString()
        let base = try ClobAuthenticator.l2Signature(
            secret: secret, timestamp: "1700000000", method: "GET", path: "/data/orders", body: nil
        )

        // Timestamp, method, path and body each change the signature.
        XCTAssertNotEqual(base, try ClobAuthenticator.l2Signature(
            secret: secret, timestamp: "1700000001", method: "GET", path: "/data/orders", body: nil))
        XCTAssertNotEqual(base, try ClobAuthenticator.l2Signature(
            secret: secret, timestamp: "1700000000", method: "POST", path: "/data/orders", body: nil))
        XCTAssertNotEqual(base, try ClobAuthenticator.l2Signature(
            secret: secret, timestamp: "1700000000", method: "GET", path: "/order", body: nil))
        XCTAssertNotEqual(base, try ClobAuthenticator.l2Signature(
            secret: secret, timestamp: "1700000000", method: "GET", path: "/data/orders",
            body: Data("{}".utf8)))
    }

    func testMethodIsUppercased() throws {
        let secret = Data("a-32-byte-test-secret-for-hmac!!".utf8).base64EncodedString()
        XCTAssertEqual(
            try ClobAuthenticator.l2Signature(
                secret: secret, timestamp: "1", method: "get", path: "/p", body: nil),
            try ClobAuthenticator.l2Signature(
                secret: secret, timestamp: "1", method: "GET", path: "/p", body: nil)
        )
    }

    /// Polymarket returns the secret in URL-safe base64, sometimes unpadded.
    func testAcceptsUrlSafeAndUnpaddedSecrets() throws {
        let raw = Data((0..<32).map { UInt8($0) })
        let urlSafe = raw.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        XCTAssertNoThrow(try ClobAuthenticator.l2Signature(
            secret: urlSafe, timestamp: "1", method: "GET", path: "/p", body: nil))

        let unpadded = String(raw.base64EncodedString().replacingOccurrences(of: "=", with: ""))
        XCTAssertNoThrow(try ClobAuthenticator.l2Signature(
            secret: unpadded, timestamp: "1", method: "GET", path: "/p", body: nil))
    }

    func testRejectsNonBase64Secret() {
        XCTAssertThrowsError(try ClobAuthenticator.l2Signature(
            secret: "!!!not base64!!!", timestamp: "1", method: "GET", path: "/p", body: nil))
    }

    func testUnauthenticatedAuthorizerRefuses() async {
        let authenticator = ClobAuthenticator()
        let isAuthed = await authenticator.isAuthenticated
        XCTAssertFalse(isAuthed)
        do {
            _ = try await authenticator.authorizationHeaders(method: "GET", path: "/p", body: nil)
            XCTFail("must not produce headers without credentials")
        } catch {
            // expected
        }
    }

    func testProducesAllFiveHeadersWhenAuthenticated() async throws {
        let secret = Data("a-32-byte-test-secret-for-hmac!!".utf8).base64EncodedString()
        let authenticator = ClobAuthenticator(
            credentials: ClobCredentials(apiKey: "key", secret: secret, passphrase: "pass"),
            signerAddress: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
        )
        let headers = try await authenticator.authorizationHeaders(
            method: "GET", path: "/data/orders", body: nil
        )
        XCTAssertEqual(
            Set(headers.keys),
            ["POLY_ADDRESS", "POLY_SIGNATURE", "POLY_TIMESTAMP", "POLY_API_KEY", "POLY_PASSPHRASE"]
        )
        XCTAssertEqual(headers["POLY_API_KEY"], "key")
        XCTAssertEqual(headers["POLY_PASSPHRASE"], "pass")
    }

    func testL1HeadersAreSignedByTheWallet() async throws {
        let signer = try PrivateKeySigner(
            privateKeyHex: "0x0000000000000000000000000000000000000000000000000000000000000001"
        )
        let headers = try await ClobAuthenticator.l1Headers(signer: signer, nonce: 0)
        XCTAssertEqual(
            headers["POLY_ADDRESS"]?.lowercased(),
            "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
        )
        XCTAssertEqual(headers["POLY_NONCE"], "0")
        let signature = try XCTUnwrap(headers["POLY_SIGNATURE"])
        XCTAssertEqual(Data(hexString: signature)?.count, 65)
    }
}

final class SecretStoreTests: XCTestCase {

    func testRoundTripsSecrets() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(try store.get(SecretKey.walletPrivateKey))

        try store.setString("0xdeadbeef", for: SecretKey.walletPrivateKey)
        XCTAssertEqual(try store.getString(SecretKey.walletPrivateKey), "0xdeadbeef")

        try store.remove(SecretKey.walletPrivateKey)
        XCTAssertNil(try store.get(SecretKey.walletPrivateKey))
    }

    func testStoresCodableCredentials() throws {
        let store = InMemorySecretStore()
        let credentials = ClobCredentials(apiKey: "k", secret: "s", passphrase: "p")
        try store.setCodable(credentials, for: SecretKey.clobCredentials)

        let loaded = try store.getCodable(ClobCredentials.self, for: SecretKey.clobCredentials)
        XCTAssertEqual(loaded, credentials)
    }
}

final class APIErrorTests: XCTestCase {

    func testRetryClassification() {
        XCTAssertTrue(APIError.transport("boom").isRetryable)
        XCTAssertTrue(APIError.offline.isRetryable)
        XCTAssertTrue(APIError.rateLimited(retryAfter: 1).isRetryable)
        XCTAssertTrue(APIError.http(status: 503, body: nil).isRetryable)
        XCTAssertTrue(APIError.http(status: 429, body: nil).isRetryable)

        XCTAssertFalse(APIError.unauthorized.isRetryable, "retrying a 401 just burns requests")
        XCTAssertFalse(APIError.http(status: 404, body: nil).isRetryable)
        XCTAssertFalse(APIError.decoding("bad").isRetryable)
        XCTAssertFalse(APIError.cancelled.isRetryable)
    }

    func testEveryErrorHasAHumanMessage() {
        let errors: [APIError] = [
            .invalidURL, .transport("x"), .http(status: 500, body: nil),
            .http(status: 404, body: nil), .decoding("x"), .unauthorized,
            .rateLimited(retryAfter: nil), .cancelled, .offline, .server(message: "Rejected")
        ]
        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty, "\(error) has no message")
            XCTAssertFalse(error.userMessage.contains("Error Domain"), "leaked a raw NSError")
        }
        XCTAssertEqual(APIError.server(message: "Rejected").userMessage, "Rejected")
    }
}
