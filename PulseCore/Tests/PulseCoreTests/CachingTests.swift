import XCTest
@testable import PulseCore

/// Caching is the one optimisation that can be actively harmful: a cached
/// order book is a wrong order book, and an order sized against one loses
/// real money. These pin down which requests may come from cache.
final class CachingTests: XCTestCase {

    func testLivePolicyNeverServesFromCache() {
        XCTAssertEqual(
            NetworkCache.Freshness.live.policy,
            .reloadIgnoringLocalCacheData,
            "prices, books, balances and orders must always hit the network"
        )
    }

    func testListAndReferenceUseProtocolCaching() {
        // Honouring the server's own Cache-Control means Polymarket decides
        // how long a market list is good for, rather than this app guessing.
        XCTAssertEqual(NetworkCache.Freshness.list.policy, .useProtocolCachePolicy)
        XCTAssertEqual(NetworkCache.Freshness.reference.policy, .useProtocolCachePolicy)
    }

    func testRequestsDefaultToLive() {
        // The safe default: an endpoint has to opt in to being cacheable.
        let request = HTTPRequest(path: "/book")
        XCTAssertEqual(request.freshness.policy, .reloadIgnoringLocalCacheData)
    }

    func testCacheIsLargeEnoughToHoldAFeed() {
        // The default shared cache is 512 KB in memory, which a feed of
        // market artwork evicts almost immediately.
        XCTAssertGreaterThanOrEqual(NetworkCache.shared.memoryCapacity, 32 * 1024 * 1024)
        XCTAssertGreaterThanOrEqual(NetworkCache.shared.diskCapacity, 128 * 1024 * 1024)
    }

    func testSessionUsesTheSharedCache() {
        XCTAssertTrue(NetworkCache.session.configuration.urlCache === NetworkCache.shared)
    }
}

/// The portfolio list reads `byValue` from a view body, so it must be a
/// stored, pre-sorted array rather than something that re-sorts per frame.
final class PortfolioOrderingTests: XCTestCase {

    private func position(value: Double) throws -> Position {
        let json = """
        {"proxy_wallet":"0xabc","token_id":"\(UUID().uuidString)","condition_id":"0xc",
         "current_size":10,"avg_price":0.5,"entry_cost_usdc":5,"entry_fees_usdc":0,
         "total_cost_usdc":5,"current_price":0.6,"current_value":\(value),
         "total_size":10,"realized_pnl":0,"unrealized_pnl":1,"total_pnl":1,
         "percent_pnl":0,"percent_realized_pnl":0,"status":"OPEN","redeemable":false,
         "mergeable":false,"negative_risk":false,"archived":false}
        """
        return try JSONDecoder().decode(Position.self, from: Data(json.utf8))
    }

    func testByValueIsSortedLargestFirst() throws {
        let portfolio = Portfolio(positions: [
            try position(value: 10),
            try position(value: 90),
            try position(value: 50)
        ])
        XCTAssertEqual(portfolio.byValue.map(\.currentValue), [90, 50, 10])
    }

    func testByValueIsStableAcrossReads() throws {
        let portfolio = Portfolio(positions: [
            try position(value: 10), try position(value: 90)
        ])
        // Identical across reads, and identical ids: a recomputed sort could
        // reorder equal elements and make the list jump while scrolling.
        XCTAssertEqual(portfolio.byValue.map(\.id), portfolio.byValue.map(\.id))
    }

    func testAllocationsFollowByValueOrder() throws {
        let portfolio = Portfolio(positions: [
            try position(value: 25), try position(value: 75)
        ])
        let allocations = portfolio.allocations()
        XCTAssertEqual(allocations.map(\.position.id), portfolio.byValue.map(\.id))
        XCTAssertEqual(allocations.first?.share ?? 0, 0.75, accuracy: 1e-9)
        XCTAssertEqual(allocations.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
    }

    func testEmptyPortfolioHasNoAllocations() {
        XCTAssertTrue(Portfolio.empty.byValue.isEmpty)
        XCTAssertTrue(Portfolio.empty.allocations().isEmpty)
    }
}
