import XCTest
@testable import PulseCore

/// Formatting is where a finance app quietly lies to people: a rounded 100%
/// on an open market, a "+" on a loss, a missing value shown as zero. These
/// pin down the cases that matter.
final class FormatTests: XCTestCase {

    func testCurrency() {
        XCTAssertEqual(Format.currency(1234.56), "$1,234.56")
        XCTAssertEqual(Format.currency(0), "$0.00")
        // A true minus sign, not a hyphen.
        XCTAssertEqual(Format.currency(-42.10), "−$42.10")
        XCTAssertEqual(Format.currency(42.10, showSign: true), "+$42.10")
        XCTAssertEqual(Format.currency(0, showSign: true), "$0.00", "zero gets no sign")
    }

    func testCompactCurrency() {
        XCTAssertEqual(Format.compactCurrency(2_162_402), "$2.2M")
        XCTAssertEqual(Format.compactCurrency(24_500), "$24.5K")
        XCTAssertEqual(Format.compactCurrency(1_500_000_000), "$1.5B")
        XCTAssertEqual(Format.compactCurrency(999), "$999")
        XCTAssertEqual(Format.compactCurrency(nil), "—", "unknown must not read as zero")
    }

    /// An open market must never display as a certainty.
    func testProbabilityNeverShowsFalseCertainty() {
        XCTAssertEqual(Format.probability(0.001), "<1%")
        XCTAssertEqual(Format.probability(0.9985), ">99%")
        XCTAssertEqual(Format.probability(0.67), "67%")
        XCTAssertEqual(Format.probability(0.5), "50%")
        XCTAssertEqual(Format.probability(nil), "—")
        // Genuine resolution values are still allowed through.
        XCTAssertEqual(Format.probability(0), "0%")
        XCTAssertEqual(Format.probability(1), "100%")
    }

    func testCentsAndPrecision() {
        XCTAssertEqual(Format.cents(0.67), "67¢")
        XCTAssertEqual(Format.cents(nil), "—")
        XCTAssertEqual(Format.preciseProbability(0.6734), "67.3%")
    }

    /// A market moving 50% → 54% moved four *points*, not four percent.
    func testProbabilityChangeIsInPoints() {
        XCTAssertEqual(Format.probabilityChange(0.04), "+4")
        XCTAssertEqual(Format.probabilityChange(-0.02), "−2")
        XCTAssertEqual(Format.probabilityChange(0.005), "+0.5")
        XCTAssertEqual(Format.probabilityChange(0), "—", "no movement is not '+0'")
        XCTAssertEqual(Format.probabilityChange(nil), "—")
    }

    func testPercentChange() {
        XCTAssertEqual(Format.percentChange(0.124), "+12.4%")
        XCTAssertEqual(Format.percentChange(-0.05), "−5.0%")
        XCTAssertEqual(Format.percentChange(nil), "—")
    }

    func testShares() {
        XCTAssertEqual(Format.shares(100), "100")
        XCTAssertEqual(Format.shares(10.5), "10.50")
        XCTAssertEqual(Format.shares(nil), "—")
    }

    func testTimeRemaining() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(Format.timeRemaining(until: now.addingTimeInterval(3 * 86_400), now: now), "3d left")
        XCTAssertEqual(Format.timeRemaining(until: now.addingTimeInterval(4 * 3600), now: now), "4h left")
        XCTAssertEqual(Format.timeRemaining(until: now.addingTimeInterval(12 * 60), now: now), "12m left")
        XCTAssertEqual(Format.timeRemaining(until: now.addingTimeInterval(-60), now: now), "Closed")
        XCTAssertEqual(Format.timeRemaining(until: now.addingTimeInterval(45 * 86_400), now: now), "1mo left")
        XCTAssertEqual(Format.timeRemaining(until: nil, now: now), "—")
    }

    func testRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-30), now: now), "Just now")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-120), now: now), "2m ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-2 * 86_400), now: now), "2d ago")
    }

    func testNilAndNonFiniteNeverRenderAsZero() {
        // A dash communicates "unknown"; "$0.00" communicates "nothing", and
        // confusing the two in a portfolio is a real harm.
        XCTAssertEqual(Format.compactCurrency(.nan), "—")
        XCTAssertEqual(Format.probability(.infinity), "—")
        XCTAssertEqual(Format.shares(.nan), "—")
        XCTAssertEqual(Format.percentChange(.nan), "—")
    }
}
