import XCTest
@testable import PulseCore

/// End-to-end checks against the real Polymarket APIs.
///
/// Skipped unless `PULSE_LIVE_TESTS=1`, so the normal suite stays hermetic and
/// offline. Run with:
///
/// ```
/// PULSE_LIVE_TESTS=1 swift test --filter LiveSmokeTests
/// ```
///
/// These only read public data — no credentials, no orders.
final class LiveSmokeTests: XCTestCase {

    private var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PULSE_LIVE_TESTS"] == "1"
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(isEnabled, "set PULSE_LIVE_TESTS=1 to run live tests")
    }

    func testGammaReturnsTradableEvents() async throws {
        let gamma = GammaService()
        let events = try await gamma.events(limit: 5, sort: .volume24hr)

        XCTAssertFalse(events.isEmpty, "Gamma returned no events")

        let markets = events.flatMap { $0.markets ?? [] }
        XCTAssertFalse(markets.isEmpty)

        let tradable = markets.filter(\.isTradable)
        XCTAssertFalse(tradable.isEmpty, "no tradable market in the top 5 events")

        let market = try XCTUnwrap(tradable.first)
        XCTAssertNotNil(market.yesTokenId)
        XCTAssertNotNil(market.conditionId)
        let probability = try XCTUnwrap(market.yesProbability)
        XCTAssertTrue((0...1).contains(probability), "probability out of range: \(probability)")
    }

    func testClobBookAndDerivedPrices() async throws {
        let gamma = GammaService()
        let clob = ClobService(authenticator: ClobAuthenticator())

        let events = try await gamma.events(limit: 5, sort: .volume24hr)
        let market = try XCTUnwrap(
            events.flatMap { $0.markets ?? [] }.first(where: \.isTradable)
        )
        let tokenId = try XCTUnwrap(market.yesTokenId)

        let book = try await clob.book(tokenId: tokenId)
        XCTAssertFalse(book.bids.isEmpty && book.asks.isEmpty, "book was empty on both sides")

        // Whatever the wire order, the book must come back best-first.
        XCTAssertEqual(book.asks.map(\.price), book.asks.map(\.price).sorted())
        XCTAssertEqual(book.bids.map(\.price), book.bids.map(\.price).sorted(by: >))

        if let bid = book.bestBid, let ask = book.bestAsk {
            XCTAssertLessThanOrEqual(bid, ask, "crossed book")
        }

        // The scalar endpoints should agree with the book.
        let midpoint = try await clob.midpoint(tokenId: tokenId)
        XCTAssertTrue((0...1).contains(midpoint))
        if let localMid = book.midpoint {
            XCTAssertEqual(midpoint, localMid, accuracy: 0.02,
                           "server midpoint disagrees with the book we parsed")
        }

        let tick = try await clob.tickSize(tokenId: tokenId)
        XCTAssertTrue([0.1, 0.01, 0.005, 0.0025, 0.001, 0.0001].contains(tick),
                      "unexpected tick size \(tick)")
    }

    func testPriceHistoryIsOrderedAndInRange() async throws {
        let gamma = GammaService()
        let clob = ClobService(authenticator: ClobAuthenticator())

        let events = try await gamma.events(limit: 5, sort: .volume24hr)
        let market = try XCTUnwrap(
            events.flatMap { $0.markets ?? [] }.first(where: \.isTradable)
        )
        let tokenId = try XCTUnwrap(market.yesTokenId)

        let history = try await clob.priceHistory(tokenId: tokenId, interval: .oneDay)
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.map(\.t), history.map(\.t).sorted(), "history must be chronological")
        for point in history {
            XCTAssertTrue((0...1).contains(point.p), "price out of range: \(point.p)")
        }
    }

    /// Guards against a regression to the retired v1 routes.
    func testDataAPIv2EnvelopeAndPagination() async throws {
        let gamma = GammaService()
        let data = DataService()

        let events = try await gamma.events(limit: 3, sort: .volume24hr)
        let market = try XCTUnwrap(events.flatMap { $0.markets ?? [] }.first)
        let conditionId = try XCTUnwrap(market.conditionId)

        let holderGroups = try await data.holders(conditionId: conditionId, limit: 3)
        guard let wallet = holderGroups.flatMap(\.holders).first?.proxyWallet else {
            throw XCTSkip("no holders on this market right now")
        }

        let positions = try await data.positions(user: wallet, status: .open, limit: 2)
        // A wallet may have closed everything since; the shape is what matters.
        XCTAssertLessThanOrEqual(positions.items.count, 2)
        if positions.hasMore {
            XCTAssertNotNil(positions.nextCursor, "hasMore without a cursor would stall paging")
        }

        let value = try await data.portfolioValue(user: wallet)
        XCTAssertGreaterThanOrEqual(value, 0)

        let activity = try await data.activity(user: wallet, limit: 2)
        XCTAssertLessThanOrEqual(activity.items.count, 2)
    }

    func testSearchReturnsRelevantEvents() async throws {
        let gamma = GammaService()
        let results = try await gamma.search("bitcoin", limit: 5)
        XCTAssertFalse(results.isEmpty, "search returned nothing for 'bitcoin'")
        let titles = results.compactMap { $0.title?.lowercased() }
        XCTAssertTrue(
            titles.contains { $0.contains("bitcoin") || $0.contains("btc") },
            "no result mentioned the query: \(titles)"
        )
    }
}
