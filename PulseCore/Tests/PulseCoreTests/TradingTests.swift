import XCTest
@testable import PulseCore

final class QuoteEngineTests: XCTestCase {

    /// Asks ascending: 10 @ 0.50, 10 @ 0.60, 10 @ 0.70.
    private var book: OrderBook {
        OrderBook(
            bids: [
                OrderBookLevel(price: 0.48, size: 10),
                OrderBookLevel(price: 0.40, size: 10),
                OrderBookLevel(price: 0.30, size: 100)
            ],
            asks: [
                OrderBookLevel(price: 0.50, size: 10),
                OrderBookLevel(price: 0.60, size: 10),
                OrderBookLevel(price: 0.70, size: 10)
            ]
        )
    }

    func testBuyWithinFirstLevel() {
        // $3 at 0.50 = 6 shares, no slippage.
        let quote = QuoteEngine.buy(budget: 3, book: book)
        XCTAssertEqual(quote.shares, 6, accuracy: 1e-9)
        XCTAssertEqual(quote.notional, 3, accuracy: 1e-9)
        XCTAssertEqual(quote.averagePrice, 0.50, accuracy: 1e-9)
        XCTAssertEqual(quote.slippage ?? -1, 0, accuracy: 1e-9)
        XCTAssertFalse(quote.isPartial)
    }

    func testBuyWalksMultipleLevels() {
        // $5 fills level 1 ($5 → 10 shares) exactly.
        let exact = QuoteEngine.buy(budget: 5, book: book)
        XCTAssertEqual(exact.shares, 10, accuracy: 1e-9)

        // $11 = 10 shares @0.50 ($5) + 10 @0.60 ($6) = 20 shares for $11.
        let deeper = QuoteEngine.buy(budget: 11, book: book)
        XCTAssertEqual(deeper.shares, 20, accuracy: 1e-9)
        XCTAssertEqual(deeper.notional, 11, accuracy: 1e-9)
        XCTAssertEqual(deeper.averagePrice, 0.55, accuracy: 1e-9)
        XCTAssertEqual(deeper.worstPrice, 0.60, accuracy: 1e-9)
        // Average 0.55 vs best 0.50 → 10% impact.
        XCTAssertEqual(try XCTUnwrap(deeper.slippage), 0.10, accuracy: 1e-9)
    }

    func testBuyBeyondBookIsPartial() {
        // Book holds 10×0.5 + 10×0.6 + 10×0.7 = $18 of liquidity.
        let quote = QuoteEngine.buy(budget: 100, book: book)
        XCTAssertEqual(quote.notional, 18, accuracy: 1e-9)
        XCTAssertEqual(quote.shares, 30, accuracy: 1e-9)
        XCTAssertTrue(quote.isPartial, "must flag that the book cannot absorb this")
        XCTAssertLessThan(quote.filledFraction, 1)
    }

    func testBuyRespectsLimitPrice() {
        // Capped at 0.60, so the 0.70 level is untouched: max $11.
        let quote = QuoteEngine.buy(budget: 100, book: book, maxPrice: 0.60)
        XCTAssertEqual(quote.notional, 11, accuracy: 1e-9)
        XCTAssertEqual(quote.worstPrice, 0.60, accuracy: 1e-9)
        XCTAssertTrue(quote.isPartial)
    }

    func testSellWalksBids() {
        // 15 shares: 10 @0.48 + 5 @0.40 = 4.8 + 2.0 = 6.80.
        let quote = QuoteEngine.sell(shares: 15, book: book)
        XCTAssertEqual(quote.shares, 15, accuracy: 1e-9)
        XCTAssertEqual(quote.notional, 6.80, accuracy: 1e-9)
        XCTAssertEqual(quote.averagePrice, 6.80 / 15, accuracy: 1e-9)
        // Selling below the best bid is adverse, so slippage is positive.
        XCTAssertGreaterThan(try XCTUnwrap(quote.slippage), 0)
    }

    func testSellRespectsFloorPrice() {
        let quote = QuoteEngine.sell(shares: 100, book: book, minPrice: 0.45)
        XCTAssertEqual(quote.shares, 10, accuracy: 1e-9)
        XCTAssertTrue(quote.isPartial)
    }

    func testBuySharesSizing() {
        let quote = QuoteEngine.buyShares(15, book: book)
        XCTAssertEqual(quote.shares, 15, accuracy: 1e-9)
        // 10 @0.50 + 5 @0.60 = 5 + 3 = 8.
        XCTAssertEqual(quote.notional, 8, accuracy: 1e-9)
    }

    func testEmptyBookYieldsZeroQuote() {
        XCTAssertEqual(QuoteEngine.buy(budget: 10, book: .empty).shares, 0)
        XCTAssertEqual(QuoteEngine.sell(shares: 10, book: .empty).shares, 0)
        XCTAssertEqual(QuoteEngine.buy(budget: 0, book: book).shares, 0)
        XCTAssertEqual(QuoteEngine.buy(budget: -5, book: book).shares, 0)
    }

    /// Winning shares settle at exactly $1, which is the basis of every
    /// payout figure the trade sheet shows.
    func testPayoutMath() {
        let quote = QuoteEngine.buy(budget: 11, book: book)   // 20 shares for $11
        XCTAssertEqual(quote.payoutIfWon, 20, accuracy: 1e-9)
        XCTAssertEqual(quote.profitIfWon, 9, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(quote.returnIfWon), 9.0 / 11.0, accuracy: 1e-9)
    }
}

final class OrderAmountsTests: XCTestCase {

    /// The worked example straight from the docs: BUY 10 shares at 0.52
    /// encodes to makerAmount 5200000 and takerAmount 10000000.
    func testDocumentedBuyExample() throws {
        let amounts = try OrderAmounts.make(side: .buy, price: 0.52, size: 10, tickSize: 0.01)
        XCTAssertEqual(amounts.makerAmount, "5200000")
        XCTAssertEqual(amounts.takerAmount, "10000000")
        XCTAssertEqual(amounts.usdcAmount, 5.20, accuracy: 1e-9)
    }

    /// SELL swaps the two: the maker gives shares and receives USD.
    func testSellInvertsAmounts() throws {
        let amounts = try OrderAmounts.make(side: .sell, price: 0.52, size: 10, tickSize: 0.01)
        XCTAssertEqual(amounts.makerAmount, "10000000", "maker gives shares")
        XCTAssertEqual(amounts.takerAmount, "5200000", "maker receives USD")
    }

    func testSixDecimalFixedPoint() throws {
        XCTAssertEqual(try OrderAmounts.fixedPoint(1), "1000000")
        XCTAssertEqual(try OrderAmounts.fixedPoint(0.000001), "1")
        XCTAssertEqual(try OrderAmounts.fixedPoint(0), "0")
        XCTAssertEqual(try OrderAmounts.fixedPoint(1234.56), "1234560000")
    }

    /// Binary floating point cannot represent 0.1 + 0.2 exactly; the fixed
    /// point conversion must not inherit that error.
    func testNoFloatingPointDrift() throws {
        let amounts = try OrderAmounts.make(side: .buy, price: 0.3, size: 100, tickSize: 0.01)
        XCTAssertEqual(amounts.makerAmount, "30000000", "0.3 × 100 must be exactly 30")
    }

    func testSizeRoundsDownNeverUp() throws {
        // 10.999 shares must round down to 10.99, never up past what the user has.
        let amounts = try OrderAmounts.make(side: .sell, price: 0.5, size: 10.999, tickSize: 0.01)
        XCTAssertEqual(amounts.size, 10.99, accuracy: 1e-9)
    }

    func testPrecisionTableMatchesDocs() {
        XCTAssertEqual(OrderAmounts.Precision.forTickSize(0.1).price, 1)
        XCTAssertEqual(OrderAmounts.Precision.forTickSize(0.01).price, 2)
        XCTAssertEqual(OrderAmounts.Precision.forTickSize(0.001).price, 3)
        XCTAssertEqual(OrderAmounts.Precision.forTickSize(0.0001).price, 4)
        XCTAssertEqual(OrderAmounts.Precision.forTickSize(0.0025).price, 4)
        XCTAssertEqual(OrderAmounts.Precision.forTickSize(0.005).price, 3)
        // Unknown ticks fall back to the finest precision.
        XCTAssertEqual(OrderAmounts.Precision.forTickSize(0.123).price, 4)
    }

    func testRejectsNonsenseInput() {
        XCTAssertThrowsError(try OrderAmounts.make(side: .buy, price: 0, size: 10, tickSize: 0.01))
        XCTAssertThrowsError(try OrderAmounts.make(side: .buy, price: 0.5, size: 0, tickSize: 0.01))
        XCTAssertThrowsError(try OrderAmounts.make(side: .buy, price: .nan, size: 10, tickSize: 0.01))
        XCTAssertThrowsError(
            try OrderAmounts.make(side: .buy, price: 0.5, size: 0.001, tickSize: 0.01),
            "a size that rounds to zero must not silently become a zero-size order"
        )
    }
}

final class OrderValidatorTests: XCTestCase {

    private func market(
        tick: Double = 0.01,
        minSize: Double = 5,
        tradable: Bool = true
    ) -> Market {
        Market(
            id: "1",
            question: "Test?",
            conditionId: "0xabc",
            outcomes: JSONStringArray(["Yes", "No"]),
            clobTokenIds: JSONStringArray(["111", "222"]),
            active: tradable,
            closed: !tradable,
            archived: false,
            acceptingOrders: tradable,
            enableOrderBook: tradable,
            orderPriceMinTickSize: LenientDouble(tick),
            orderMinSize: LenientDouble(minSize)
        )
    }

    private var book: OrderBook {
        OrderBook(
            bids: [OrderBookLevel(price: 0.48, size: 100)],
            asks: [OrderBookLevel(price: 0.50, size: 100)]
        )
    }

    // MARK: Tick conformance

    func testTickConformance() {
        XCTAssertTrue(OrderValidator.isOnTick(price: 0.50, tick: 0.01))
        XCTAssertTrue(OrderValidator.isOnTick(price: 0.3, tick: 0.1), "0.3/0.1 drifts in IEEE 754")
        XCTAssertTrue(OrderValidator.isOnTick(price: 0.123, tick: 0.001))
        XCTAssertFalse(OrderValidator.isOnTick(price: 0.505, tick: 0.01))
        XCTAssertFalse(OrderValidator.isOnTick(price: 0.1234, tick: 0.001))
    }

    func testSnapToTick() {
        XCTAssertEqual(OrderValidator.snapToTick(price: 0.5049, tick: 0.01), 0.50, accuracy: 1e-9)
        XCTAssertEqual(OrderValidator.snapToTick(price: 0.5051, tick: 0.01), 0.51, accuracy: 1e-9)
        XCTAssertEqual(OrderValidator.snapToTick(price: 0.1234, tick: 0.001), 0.123, accuracy: 1e-9)
    }

    // MARK: Limit orders

    func testValidLimitOrderHasNoIssues() {
        let context = OrderValidator.Context(
            market: market(), side: .buy, book: book,
            isAuthenticated: true, availableBalance: 100
        )
        XCTAssertTrue(OrderValidator.validateLimitOrder(price: 0.50, shares: 10, context: context).isEmpty)
    }

    func testRejectsOffTickPrice() {
        let context = OrderValidator.Context(
            market: market(), side: .buy, book: book,
            isAuthenticated: true, availableBalance: 100
        )
        let issues = OrderValidator.validateLimitOrder(price: 0.505, shares: 10, context: context)
        XCTAssertTrue(issues.contains { if case .priceNotOnTick = $0 { true } else { false } })
    }

    func testRejectsPriceOutsideZeroToOne() {
        let context = OrderValidator.Context(
            market: market(), side: .buy, book: book,
            isAuthenticated: true, availableBalance: 100
        )
        for price in [1.0, 1.5] {
            let issues = OrderValidator.validateLimitOrder(price: price, shares: 10, context: context)
            XCTAssertTrue(
                issues.contains { if case .priceOutOfRange = $0 { true } else { false } },
                "price \(price) must be rejected"
            )
        }
    }

    func testRejectsBelowMinimumSize() {
        let context = OrderValidator.Context(
            market: market(minSize: 5), side: .buy, book: book,
            isAuthenticated: true, availableBalance: 100
        )
        let issues = OrderValidator.validateLimitOrder(price: 0.50, shares: 2, context: context)
        XCTAssertTrue(issues.contains { if case .sizeBelowMinimum = $0 { true } else { false } })
    }

    func testRejectsInsufficientBalance() {
        let context = OrderValidator.Context(
            market: market(), side: .buy, book: book,
            isAuthenticated: true, availableBalance: 1
        )
        // 10 shares @ 0.50 = $5 against a $1 balance.
        let issues = OrderValidator.validateLimitOrder(price: 0.50, shares: 10, context: context)
        XCTAssertTrue(issues.contains { if case .insufficientBalance = $0 { true } else { false } })
    }

    func testRejectsSellingSharesNotHeld() {
        let context = OrderValidator.Context(
            market: market(), side: .sell, book: book,
            isAuthenticated: true, heldShares: 3
        )
        let issues = OrderValidator.validateLimitOrder(price: 0.50, shares: 10, context: context)
        XCTAssertTrue(issues.contains { if case .insufficientShares = $0 { true } else { false } })
    }

    func testRejectsClosedMarket() {
        let context = OrderValidator.Context(
            market: market(tradable: false), side: .buy, book: book,
            isAuthenticated: true, availableBalance: 100
        )
        XCTAssertTrue(
            OrderValidator.validateLimitOrder(price: 0.50, shares: 10, context: context)
                .contains(.marketNotTradable)
        )
    }

    func testRequiresAuthentication() {
        let context = OrderValidator.Context(
            market: market(), side: .buy, book: book, isAuthenticated: false
        )
        XCTAssertTrue(
            OrderValidator.validateLimitOrder(price: 0.50, shares: 10, context: context)
                .contains(.notAuthenticated)
        )
    }

    // MARK: Market orders

    func testMarketOrderValidation() {
        let context = OrderValidator.Context(
            market: market(), side: .buy, book: book,
            isAuthenticated: true, availableBalance: 100
        )
        let quote = QuoteEngine.buy(budget: 10, book: book)
        XCTAssertTrue(OrderValidator.validateMarketOrder(amount: 10, context: context, quote: quote).isEmpty)
    }

    func testMarketOrderFlagsEmptyBook() {
        let context = OrderValidator.Context(
            market: market(), side: .buy, book: .empty,
            isAuthenticated: true, availableBalance: 100
        )
        let quote = QuoteEngine.buy(budget: 10, book: .empty)
        XCTAssertTrue(
            OrderValidator.validateMarketOrder(amount: 10, context: context, quote: quote)
                .contains(.emptyOrderBook)
        )
    }

    func testMarketOrderEnforcesSlippageLimit() {
        let thin = OrderBook(
            bids: [],
            asks: [
                OrderBookLevel(price: 0.50, size: 1),
                OrderBookLevel(price: 0.90, size: 1000)
            ]
        )
        let context = OrderValidator.Context(
            market: market(), side: .buy, book: thin,
            isAuthenticated: true, availableBalance: 1000, slippageLimit: 0.05
        )
        let quote = QuoteEngine.buy(budget: 100, book: thin)
        XCTAssertTrue(
            OrderValidator.validateMarketOrder(amount: 100, context: context, quote: quote)
                .contains { if case .excessiveSlippage = $0 { true } else { false } },
            "a 0.50 → 0.90 walk must trip a 5% slippage limit"
        )
    }

    func testIssuesCarryActionableMessages() {
        XCTAssertFalse(OrderValidator.Issue.marketNotTradable.message.isEmpty)
        XCTAssertTrue(
            OrderValidator.Issue.insufficientBalance(required: 10, available: 5)
                .message.contains("10")
        )
    }
}

final class FeeEstimatorTests: XCTestCase {

    /// Builder fee is a flat percentage of notional:
    /// 1000 × 100bps = $10, from the docs' worked example.
    func testBuilderFeeMatchesDocumentedExample() {
        let estimate = FeeEstimator.estimate(
            notional: 1000, price: 0.5, platformFeeRate: nil, builderFeeBps: 100, isTaker: true
        )
        XCTAssertEqual(estimate.builderFee, 10, accuracy: 1e-9)
        XCTAssertEqual(estimate.platformFee, 0)
    }

    /// Platform fee is C × rate × p × (1-p), peaking at p = 0.5.
    func testPlatformFeeShape() {
        let atMid = FeeEstimator.estimate(
            notional: 100, price: 0.5, platformFeeRate: 0.01, builderFeeBps: nil, isTaker: true
        )
        XCTAssertEqual(atMid.platformFee, 100 * 0.01 * 0.25, accuracy: 1e-9)

        // Vanishes at the extremes.
        let atEdge = FeeEstimator.estimate(
            notional: 100, price: 0.99, platformFeeRate: 0.01, builderFeeBps: nil, isTaker: true
        )
        XCTAssertLessThan(atEdge.platformFee, atMid.platformFee)
    }

    func testPlatformFeeIsTakerOnly() {
        let maker = FeeEstimator.estimate(
            notional: 100, price: 0.5, platformFeeRate: 0.01, builderFeeBps: nil, isTaker: false
        )
        XCTAssertEqual(maker.platformFee, 0)
    }

    func testFeesAreAdditive() {
        let both = FeeEstimator.estimate(
            notional: 100, price: 0.5, platformFeeRate: 0.01, builderFeeBps: 50, isTaker: true
        )
        XCTAssertEqual(both.total, both.platformFee + both.builderFee, accuracy: 1e-12)
        XCTAssertGreaterThan(both.platformFee, 0)
        XCTAssertGreaterThan(both.builderFee, 0)
    }

    func testNoFeesWhenNothingConfigured() {
        XCTAssertEqual(
            FeeEstimator.estimate(
                notional: 100, price: 0.5, platformFeeRate: nil, builderFeeBps: nil, isTaker: true
            ).total,
            0
        )
    }
}
