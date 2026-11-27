import XCTest
@testable import PulseCore

/// Covers order preparation — the step between what the user types and what
/// gets signed. The trade sheet renders exactly the `PreparedOrder` these
/// produce, so an error here is an error shown to the user as fact.
final class PreparationTests: XCTestCase {

    private func service(builderFeeBps: Int? = nil) -> TradingService {
        TradingService(
            clob: ClobService(authenticator: ClobAuthenticator()),
            configuration: PulseConfiguration(
                builderCode: "0x" + String(repeating: "ab", count: 32),
                builderFeeBps: builderFeeBps
            )
        ) {
            throw TradingService.TradingError.notAuthenticated
        }
    }

    private func market(tick: Double = 0.01, minSize: Double = 5, fees: Bool = false) -> Market {
        Market(
            id: "1",
            question: "Test?",
            conditionId: "0xabc",
            outcomes: JSONStringArray(["Yes", "No"]),
            clobTokenIds: JSONStringArray(["111", "222"]),
            active: true, closed: false, archived: false,
            acceptingOrders: true, enableOrderBook: true,
            orderPriceMinTickSize: LenientDouble(tick),
            orderMinSize: LenientDouble(minSize),
            feesEnabled: fees
        )
    }

    private var book: OrderBook {
        OrderBook(
            bids: [
                OrderBookLevel(price: 0.48, size: 100),
                OrderBookLevel(price: 0.40, size: 100)
            ],
            asks: [
                OrderBookLevel(price: 0.50, size: 100),
                OrderBookLevel(price: 0.60, size: 100)
            ]
        )
    }

    // MARK: Market orders

    func testMarketBuyMatchesTheQuote() throws {
        let order = try service().prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, amount: 10, book: book,
            availableBalance: 100, heldShares: nil,
            slippageLimit: nil, isAuthenticated: true
        )

        // $10 at 0.50 fills entirely on the first level.
        XCTAssertEqual(order.shares, 20, accuracy: 1e-9)
        XCTAssertEqual(order.notional, 10, accuracy: 1e-9)
        XCTAssertTrue(order.isMarketOrder)
        XCTAssertEqual(order.orderType, .fak, "market orders must not silently rest on the book")
        XCTAssertEqual(order.payoutIfWon, 20, accuracy: 1e-9)
    }

    /// A market order is signed at the worst price it touches, so the order
    /// stays marketable if the book ticks against us between quote and submit.
    func testMarketBuySignsAtTheWorstTouchedPrice() throws {
        let order = try service().prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, amount: 80, book: book,
            availableBalance: 1000, heldShares: nil,
            slippageLimit: nil, isAuthenticated: true
        )
        // $80 consumes all of 0.50 ($50) and part of 0.60.
        XCTAssertEqual(order.price, 0.60, accuracy: 1e-9)
        XCTAssertGreaterThan(order.price, order.quote?.averagePrice ?? 0)
    }

    func testMarketSellUsesBids() throws {
        let order = try service().prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .sell, amount: 50, book: book,
            availableBalance: nil, heldShares: 100,
            slippageLimit: nil, isAuthenticated: true
        )
        XCTAssertEqual(order.shares, 50, accuracy: 1e-9)
        XCTAssertEqual(order.notional, 50 * 0.48, accuracy: 1e-9)
        XCTAssertEqual(order.netProceeds, order.notional - order.fees.total, accuracy: 1e-9)
    }

    func testPreparationRejectsInvalidOrders() {
        let service = self.service()

        // Unauthenticated.
        XCTAssertThrowsError(try service.prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, amount: 10, book: book,
            availableBalance: 100, heldShares: nil,
            slippageLimit: nil, isAuthenticated: false
        ))

        // Over balance.
        XCTAssertThrowsError(try service.prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, amount: 500, book: book,
            availableBalance: 10, heldShares: nil,
            slippageLimit: nil, isAuthenticated: true
        ))

        // Selling more than is held.
        XCTAssertThrowsError(try service.prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .sell, amount: 500, book: book,
            availableBalance: nil, heldShares: 10,
            slippageLimit: nil, isAuthenticated: true
        ))
    }

    func testSlippageLimitBlocksAThinBook() {
        let thin = OrderBook(
            bids: [],
            asks: [OrderBookLevel(price: 0.50, size: 1), OrderBookLevel(price: 0.95, size: 1000)]
        )
        XCTAssertThrowsError(try service().prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, amount: 200, book: thin,
            availableBalance: 1000, heldShares: nil,
            slippageLimit: 0.05, isAuthenticated: true
        )) { error in
            guard case TradingService.TradingError.validation(let issues) = error else {
                return XCTFail("expected a validation failure, got \(error)")
            }
            XCTAssertTrue(issues.contains { if case .excessiveSlippage = $0 { true } else { false } })
        }
    }

    // MARK: Limit orders

    func testLimitOrderRestsAndSnapsToTick() throws {
        let order = try service().prepareLimitOrder(
            market: market(tick: 0.01), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, price: 0.5049, shares: 10, book: book,
            availableBalance: 100, heldShares: nil, isAuthenticated: true
        )
        XCTAssertEqual(order.price, 0.50, accuracy: 1e-9, "price must land on a valid tick")
        XCTAssertEqual(order.orderType, .gtc)
        XCTAssertFalse(order.isMarketOrder)
        XCTAssertNil(order.quote, "a resting order has no book walk")
        XCTAssertEqual(order.notional, 5, accuracy: 1e-9)
    }

    func testLimitOrderRejectsBelowMinimumSize() {
        XCTAssertThrowsError(try service().prepareLimitOrder(
            market: market(minSize: 5), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, price: 0.50, shares: 2, book: book,
            availableBalance: 100, heldShares: nil, isAuthenticated: true
        ))
    }

    // MARK: Fees

    /// A resting limit order is a maker order, so it carries no platform fee
    /// even on a market where fees are enabled.
    func testPlatformFeeIsTakerOnly() throws {
        let taker = try service().prepareMarketOrder(
            market: market(fees: true), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, amount: 10, book: book,
            availableBalance: 100, heldShares: nil,
            slippageLimit: nil, isAuthenticated: true
        )
        XCTAssertGreaterThan(taker.fees.platformFee, 0)

        let maker = try service().prepareLimitOrder(
            market: market(tick: 0.01, fees: true), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, price: 0.50, shares: 10, book: book,
            availableBalance: 100, heldShares: nil, isAuthenticated: true
        )
        XCTAssertEqual(maker.fees.platformFee, 0)
    }

    /// The builder fee must reach both paths. It previously only reached the
    /// async one, so the confirmation screen under-reported the cost.
    func testBuilderFeeAppliesToBothOrderTypes() throws {
        let service = self.service(builderFeeBps: 100)   // 1%

        let market = try service.prepareMarketOrder(
            market: self.market(), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, amount: 10, book: book,
            availableBalance: 100, heldShares: nil,
            slippageLimit: nil, isAuthenticated: true
        )
        XCTAssertEqual(market.fees.builderFee, 0.10, accuracy: 1e-9)
        XCTAssertEqual(market.totalCost, 10.10, accuracy: 1e-9)

        let limit = try service.prepareLimitOrder(
            market: self.market(), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, price: 0.50, shares: 10, book: book,
            availableBalance: 100, heldShares: nil, isAuthenticated: true
        )
        XCTAssertEqual(limit.fees.builderFee, 0.05, accuracy: 1e-9, "1% of $5")
    }

    func testTotalCostAndProceedsDirections() throws {
        let service = self.service(builderFeeBps: 100)

        let buy = try service.prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .buy, amount: 10, book: book,
            availableBalance: 100, heldShares: nil,
            slippageLimit: nil, isAuthenticated: true
        )
        // Fees increase what a buyer pays…
        XCTAssertGreaterThan(buy.totalCost, buy.notional)

        let sell = try service.prepareMarketOrder(
            market: market(), tokenId: "111", outcomeLabel: "Yes",
            side: .sell, amount: 50, book: book,
            availableBalance: nil, heldShares: 100,
            slippageLimit: nil, isAuthenticated: true
        )
        // …and reduce what a seller receives.
        XCTAssertLessThan(sell.netProceeds, sell.notional)
    }
}
