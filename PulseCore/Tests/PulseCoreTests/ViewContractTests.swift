import XCTest
@testable import PulseCore

/// Pins the shapes the SwiftUI layer relies on.
///
/// The views live in the app target and cannot be compiled on Linux, so these
/// cover the contracts between core and UI that a refactor could silently
/// break: optional depth, the exact strings rendered, and the derived values
/// the trade sheet prints.
final class ViewContractTests: XCTestCase {

    /// The views write `market.volume24hr?.value` and pass it straight to a
    /// `Double?` formatter. If optional chaining ever produced `Double??`
    /// those call sites would stop compiling.
    func testOptionalChainingDepthOnLenientFields() {
        let market = Market(id: "1", volume24hr: LenientDouble(5))
        let value: Double? = market.volume24hr?.value
        XCTAssertEqual(value, 5)
        XCTAssertEqual(Format.compactCurrency(value), "$5")

        let missing = Market(id: "2")
        let none: Double? = missing.volume24hr?.value
        XCTAssertNil(none)
        XCTAssertEqual(Format.compactCurrency(none), "—")
    }

    /// `ProbabilityView` renders the change without its sign character and
    /// supplies the arrow itself, so the sign must be exactly one character.
    func testProbabilityChangeSignIsSingleCharacter() {
        for value in [0.04, -0.04, 0.005, -0.12] {
            let text = Format.probabilityChange(value)
            let first = try? XCTUnwrap(text.first)
            XCTAssertTrue(first == "+" || first == "−", "unexpected sign in \(text)")
            XCTAssertFalse(String(text.dropFirst()).isEmpty)
        }
    }

    /// The feed shows a market's two outcomes as complementary prices.
    func testYesNoProbabilitiesAreComplementary() {
        let market = Market(
            id: "1",
            outcomes: JSONStringArray(["Yes", "No"]),
            outcomePrices: JSONStringArray(["0.67", "0.33"]),
            bestBid: LenientDouble(0.66),
            bestAsk: LenientDouble(0.68)
        )
        let yes = try? XCTUnwrap(market.yesProbability)
        XCTAssertEqual(yes ?? 0, 0.67, accuracy: 1e-9, "midpoint of the book")
        XCTAssertEqual((market.yesProbability ?? 0) + (market.noProbability ?? 0), 1, accuracy: 1e-9)
    }

    /// A one-sided book must not report a midpoint of half the live side.
    func testOneSidedBookDoesNotFabricateMidpoint() {
        let market = Market(
            id: "1",
            outcomePrices: JSONStringArray(["0.9985"]),
            bestBid: LenientDouble(0.001),
            bestAsk: LenientDouble(0)
        )
        // Falls back to outcomePrices rather than averaging against a zero ask.
        XCTAssertEqual(market.yesProbability ?? 0, 0.9985, accuracy: 1e-9)
    }

    /// `isTradable` gates the whole trade surface; every flag must count.
    func testTradabilityRequiresEveryFlag() {
        func market(
            active: Bool = true, closed: Bool = false, archived: Bool = false,
            accepting: Bool = true, book: Bool = true, tokens: [String] = ["1", "2"]
        ) -> Market {
            Market(
                id: "1",
                clobTokenIds: JSONStringArray(tokens),
                active: active, closed: closed, archived: archived,
                acceptingOrders: accepting, enableOrderBook: book
            )
        }

        XCTAssertTrue(market().isTradable)
        XCTAssertFalse(market(active: false).isTradable)
        XCTAssertFalse(market(closed: true).isTradable)
        XCTAssertFalse(market(archived: true).isTradable)
        XCTAssertFalse(market(accepting: false).isTradable)
        XCTAssertFalse(market(book: false).isTradable)
        XCTAssertFalse(market(tokens: []).isTradable)
    }

    /// The order summary prints total cost and profit from these properties.
    func testTradeSummaryArithmetic() {
        let book = OrderBook(
            bids: [OrderBookLevel(price: 0.48, size: 1000)],
            asks: [OrderBookLevel(price: 0.50, size: 1000)]
        )
        let quote = QuoteEngine.buy(budget: 10, book: book)
        XCTAssertEqual(quote.shares, 20, accuracy: 1e-9)
        XCTAssertEqual(quote.payoutIfWon, 20, accuracy: 1e-9)
        XCTAssertEqual(quote.profitIfWon, 10, accuracy: 1e-9)

        // Rendered strings, exactly as the confirmation screen shows them.
        XCTAssertEqual(Format.currency(quote.notional), "$10.00")
        XCTAssertEqual(Format.currency(quote.payoutIfWon), "$20.00")
        XCTAssertEqual(Format.currency(quote.profitIfWon, showSign: true), "+$10.00")
    }


}
