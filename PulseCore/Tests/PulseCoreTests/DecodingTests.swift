import XCTest
@testable import PulseCore

/// Decodes real, unmodified API responses captured from production. If
/// Polymarket changes a field's type or name, these fail rather than the app
/// silently rendering zeros.
final class DecodingTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")
                ?? Bundle.module.url(forResource: name, withExtension: "json"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    // MARK: Gamma

    func testDecodesLiveEventsResponse() throws {
        let events = try JSONDecoder().decode([Event].self, from: fixture("events"))
        XCTAssertFalse(events.isEmpty)

        let event = try XCTUnwrap(events.first)
        XCTAssertFalse(event.id.isEmpty)
        XCTAssertNotNil(event.title)
        XCTAssertNotNil(event.markets)
        XCTAssertFalse(event.displayTitle.isEmpty)
    }

    /// The single most error-prone part of the Gamma contract: `outcomes`,
    /// `outcomePrices` and `clobTokenIds` arrive as JSON-encoded *strings*.
    func testDecodesStringEncodedArrays() throws {
        let events = try JSONDecoder().decode([Event].self, from: fixture("events"))
        let markets = events.flatMap { $0.markets ?? [] }
        XCTAssertFalse(markets.isEmpty)

        let withTokens = markets.first { !$0.tokenIds.isEmpty }
        let market = try XCTUnwrap(withTokens, "no market exposed clobTokenIds")

        XCTAssertGreaterThanOrEqual(market.tokenIds.count, 2)
        // Token ids are huge decimal integers, not hex.
        let tokenId = try XCTUnwrap(market.yesTokenId)
        XCTAssertGreaterThan(tokenId.count, 40)
        XCTAssertTrue(tokenId.allSatisfy(\.isNumber), "token id should be decimal: \(tokenId)")

        XCTAssertEqual(market.outcomeLabels.count, 2)
    }

    func testParsesStringEncodedJSONArrayDirectly() throws {
        struct Wrapper: Decodable { let outcomes: JSONStringArray }

        let json = #"{"outcomes": "[\"Yes\", \"No\"]"}"#
        let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.outcomes.values, ["Yes", "No"])

        // A genuine array must work identically.
        let realArray = #"{"outcomes": ["Yes", "No"]}"#
        XCTAssertEqual(
            try JSONDecoder().decode(Wrapper.self, from: Data(realArray.utf8)).outcomes.values,
            ["Yes", "No"]
        )

        // Empty and malformed values degrade to [] rather than throwing.
        for bad in [#"{"outcomes": ""}"#, #"{"outcomes": "not json"}"#, #"{"outcomes": null}"#] {
            XCTAssertEqual(
                try JSONDecoder().decode(Wrapper.self, from: Data(bad.utf8)).outcomes.values,
                []
            )
        }
    }

    func testLenientNumbersAcceptStringsAndNumbers() throws {
        struct Wrapper: Decodable { let v: LenientDouble }

        XCTAssertEqual(try JSONDecoder().decode(Wrapper.self, from: Data(#"{"v": 1.5}"#.utf8)).v.value, 1.5)
        XCTAssertEqual(try JSONDecoder().decode(Wrapper.self, from: Data(#"{"v": "1.5"}"#.utf8)).v.value, 1.5)
        XCTAssertEqual(try JSONDecoder().decode(Wrapper.self, from: Data(#"{"v": 2}"#.utf8)).v.value, 2)
        XCTAssertNil(try JSONDecoder().decode(Wrapper.self, from: Data(#"{"v": null}"#.utf8)).v.value)
        XCTAssertNil(try JSONDecoder().decode(Wrapper.self, from: Data(#"{"v": "abc"}"#.utf8)).v.value)
    }

    /// A market missing most optional fields must still decode: Gamma omits
    /// fields freely and one sparse market must not discard the whole page.
    func testMinimalMarketStillDecodes() throws {
        let json = #"{"id": "123"}"#
        let market = try JSONDecoder().decode(Market.self, from: Data(json.utf8))
        XCTAssertEqual(market.id, "123")
        XCTAssertFalse(market.isTradable, "a market with no token ids is not tradable")
        XCTAssertEqual(market.displayTitle, "123")
        // Sensible defaults rather than crashes.
        XCTAssertEqual(market.tickSize, 0.001)
        XCTAssertEqual(market.minimumOrderSize, 5)
    }

    func testIdDecodesFromStringOrNumber() throws {
        XCTAssertEqual(try JSONDecoder().decode(Market.self, from: Data(#"{"id": 7}"#.utf8)).id, "7")
        XCTAssertEqual(try JSONDecoder().decode(Market.self, from: Data(#"{"id": "7"}"#.utf8)).id, "7")
        XCTAssertThrowsError(try JSONDecoder().decode(Market.self, from: Data("{}".utf8)))
    }

    // MARK: CLOB

    func testDecodesLiveOrderBook() throws {
        let book = try JSONDecoder().decode(OrderBook.self, from: fixture("book"))
        XCTAssertNotNil(book.assetId)
        XCTAssertFalse(book.asks.isEmpty)

        // Normalised to best-first regardless of the wire order.
        let askPrices = book.asks.map(\.price)
        XCTAssertEqual(askPrices, askPrices.sorted(), "asks must ascend")

        let bidPrices = book.bids.map(\.price)
        XCTAssertEqual(bidPrices, bidPrices.sorted(by: >), "bids must descend")

        if let bid = book.bestBid, let ask = book.bestAsk {
            XCTAssertLessThan(bid, ask, "bid must be below ask")
            XCTAssertEqual(book.spread ?? 0, ask - bid, accuracy: 1e-9)
        }
    }

    func testOrderBookDropsZeroSizeLevels() throws {
        let json = """
        {"bids":[{"price":"0.4","size":"0"},{"price":"0.3","size":"10"}],
         "asks":[{"price":"0.6","size":"5"}]}
        """
        let book = try JSONDecoder().decode(OrderBook.self, from: Data(json.utf8))
        XCTAssertEqual(book.bids.count, 1)
        XCTAssertEqual(book.bestBid, 0.3)
    }

    func testDecodesPriceHistory() throws {
        let history = try JSONDecoder()
            .decode(PriceHistoryResponse.self, from: fixture("price_history"))
        XCTAssertFalse(history.history.isEmpty)

        let point = try XCTUnwrap(history.history.first)
        XCTAssertGreaterThan(point.t, 1_600_000_000)
        XCTAssertTrue((0...1).contains(point.p), "probabilities are 0...1, got \(point.p)")
    }

    func testOrderPlacementResponseDetectsRejection() throws {
        let rejected = #"{"success": false, "errorMsg": "not enough balance"}"#
        let decoded = try JSONDecoder()
            .decode(OrderPlacementResponse.self, from: Data(rejected.utf8))
        XCTAssertFalse(decoded.isAccepted)
        XCTAssertEqual(decoded.errorMsg, "not enough balance")

        let accepted = #"{"success": true, "orderID": "0xabc"}"#
        XCTAssertTrue(
            try JSONDecoder()
                .decode(OrderPlacementResponse.self, from: Data(accepted.utf8)).isAccepted
        )
    }

    // MARK: Data API v2

    func testDecodesPositionsEnvelope() throws {
        let envelope = try JSONDecoder()
            .decode(DataEnvelope<[Position]>.self, from: fixture("positions_v2"))
        let positions = try XCTUnwrap(envelope.data)
        XCTAssertFalse(positions.isEmpty)

        let position = try XCTUnwrap(positions.first)
        XCTAssertFalse(position.proxyWallet.isEmpty)
        XCTAssertFalse(position.tokenId.isEmpty)
        XCTAssertGreaterThan(position.currentSize, 0)
        XCTAssertNotNil(position.title)
        XCTAssertEqual(position.payoutIfWon, position.currentSize)

        // Cursor pagination, not offset.
        XCTAssertNotNil(envelope.pagination)
    }

    func testDecodesActivityEnvelope() throws {
        let envelope = try JSONDecoder()
            .decode(DataEnvelope<[ActivityItem]>.self, from: fixture("activity_v2"))
        let items = try XCTUnwrap(envelope.data)
        XCTAssertFalse(items.isEmpty)

        let item = try XCTUnwrap(items.first)
        XCTAssertGreaterThan(item.timestamp, 0)
        XCTAssertNotEqual(item.type, .unknown)
    }

    /// Non-trade rows carry `outcome_index: 999`, which must not render.
    func testActivitySentinelOutcomeIndexIsHidden() throws {
        let json = """
        {"proxy_wallet":"0xabc","timestamp":1,"type":"MERGE","outcome_index":999,"outcome":""}
        """
        let item = try JSONDecoder().decode(ActivityItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.type, .merge)
        XCTAssertFalse(item.hasOutcome)

        let trade = """
        {"proxy_wallet":"0xabc","timestamp":1,"type":"TRADE","outcome_index":0,"outcome":"Yes","side":"BUY"}
        """
        let tradeItem = try JSONDecoder().decode(ActivityItem.self, from: Data(trade.utf8))
        XCTAssertTrue(tradeItem.hasOutcome)
        XCTAssertEqual(tradeItem.orderSide, .buy)
    }

    func testEmptyEnvelopeIsNotAnError() throws {
        let json = #"{"data": [], "pagination": {"limit": 2, "has_more": false, "next_cursor": null}}"#
        let envelope = try JSONDecoder()
            .decode(DataEnvelope<[Position]>.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.data?.count, 0)
        XCTAssertEqual(envelope.pagination?.hasMore, false)

        // `data: null` is documented as a miss, not a failure.
        let nullJSON = #"{"data": null}"#
        let nullEnvelope = try JSONDecoder()
            .decode(DataEnvelope<[Position]>.self, from: Data(nullJSON.utf8))
        XCTAssertNil(nullEnvelope.data)
        XCTAssertEqual(nullEnvelope.items.count, 0)
    }

    // MARK: Dates

    func testParsesEveryDateFormatPolymarketSends() {
        XCTAssertNotNil(PolyDate.parse("2026-11-27T17:00:00Z"))
        XCTAssertNotNil(PolyDate.parse("2026-11-20T17:01:48.071599Z"))
        XCTAssertNotNil(PolyDate.parse("2026-11-27"))
        XCTAssertNotNil(PolyDate.parse("2023-11-02 21:40:32.968+00"))
        XCTAssertNil(PolyDate.parse(nil))
        XCTAssertNil(PolyDate.parse(""))
        XCTAssertNil(PolyDate.parse("not a date"))
    }
}
