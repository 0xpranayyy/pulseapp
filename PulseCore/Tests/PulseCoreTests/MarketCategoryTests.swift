import XCTest
@testable import PulseCore

final class MarketCategoryTests: XCTestCase {

    func testMatchesKnownSlugs() {
        XCTAssertEqual(MarketCategory(tagSlugs: ["sports"]), .sport)
        XCTAssertEqual(MarketCategory(tagSlugs: ["bitcoin"]), .crypto)
        XCTAssertEqual(MarketCategory(tagSlugs: ["fed-rates"]), .economy)
        XCTAssertEqual(MarketCategory(tagSlugs: ["pop-culture"]), .culture)
        XCTAssertEqual(MarketCategory(tagSlugs: ["geopolitics"]), .world)
    }

    /// Gamma returns tags in relevance order; the first one that names a
    /// category must win, not whichever happens to be checked first.
    func testFirstMatchingTagWins() {
        XCTAssertEqual(MarketCategory(tagSlugs: ["trump", "crypto"]), .politics)
        XCTAssertEqual(MarketCategory(tagSlugs: ["crypto", "trump"]), .crypto)
        XCTAssertEqual(MarketCategory(tagSlugs: ["some-new-tag", "nba"]), .sport)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(MarketCategory(tagSlugs: ["Crypto"]), .crypto)
    }

    func testUnknownOrMissingIsOther() {
        XCTAssertEqual(MarketCategory(tagSlugs: []), .other)
        XCTAssertEqual(MarketCategory(tagSlugs: ["weather"]), .other)
        XCTAssertEqual(MarketCategory(tags: nil), .other)
    }

    func testDecodedTagsUseTheirSlugs() throws {
        let json = #"[{"id":"1","label":"Bitcoin","slug":"bitcoin"},{"id":2,"label":"Hidden"}]"#
        let tags = try JSONDecoder().decode([Tag].self, from: Data(json.utf8))
        XCTAssertEqual(MarketCategory(tags: tags), .crypto)
    }

    /// Green and red are reserved for Yes and No, so no category may use a
    /// colour that reads as either. Checked by hue, which is what a reader
    /// actually confuses.
    func testNoCategoryLooksLikeYesOrNo() {
        for category in MarketCategory.allCases {
            for hex in [category.fillHex, category.panelHex] {
                let hue = Self.hue(hex)
                XCTAssertFalse((90...150).contains(hue), "\(category) \(hex) reads as Yes green")
                XCTAssertFalse(hue < 12 || hue > 340, "\(category) \(hex) reads as No red")
            }
        }
    }

    /// Panels carry white text, so each must clear WCAG AA (4.5:1) against white.
    func testPanelsAreReadableUnderWhiteText() {
        for category in MarketCategory.allCases {
            let ratio = 1.05 / (Self.luminance(category.panelHex) + 0.05)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(category) panel \(category.panelHex) is \(ratio):1")
        }
    }

    // MARK: Colour maths

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        let v = UInt32(hex, radix: 16)!
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    private static func luminance(_ hex: String) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = rgb(hex)
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private static func hue(_ hex: String) -> Double {
        let (r, g, b) = rgb(hex)
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0 else { return 0 }
        var h: Double
        if mx == r { h = (g - b) / d } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }
}
