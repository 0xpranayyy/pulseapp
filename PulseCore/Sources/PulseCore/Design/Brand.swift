#if canImport(SwiftUI)
import SwiftUI

/// Pulse's colour system: bright, trading-first.
///
/// A warm cream canvas, white chunky cards with hard unblurred shadows, navy
/// ink, and two colours that mean exactly one thing each — green is Yes, red
/// is No. Category colours (`MarketCategory`) say what a market is about and
/// are never green or red. Lime is the live accent: the knot on the tug, the
/// dot that ends a sparkline, Pip's antenna.
///
/// The meadow (greens, sky, sun) belongs to the brand moments — welcome,
/// sign-in — not to working screens, where it would compete with the data.
///
/// Light only for now: these colours are designed against cream, and a dark
/// variant is a separate piece of design work, not an inversion.
public enum Brand {

    // MARK: Canvas and cards

    public static let canvas = Color(hex: "F7F5EC")
    public static let card = Color(hex: "FFFFFF")
    /// Inset areas inside a card: the buy summary, segmented tracks.
    public static let cardSunken = Color(hex: "F2F0E8")
    /// The hard shadow under cards on the canvas.
    public static let cardShadow = Color(hex: "E3E0D2")
    public static let hairline = Color(hex: "E3E0D2")

    // MARK: Ink

    public static let ink = Color(hex: "1F2557")
    /// ≥ 7:1 on cream.
    public static let inkSecondary = Color(hex: "474E6E")
    /// ≥ 4.5:1 on cream and on white — the quietest text allowed.
    public static let inkTertiary = Color(hex: "5F6488")

    // MARK: Yes and No — the only meanings green and red ever carry

    public static let yes = Color(hex: "2E8A1D")
    public static let yesDeep = Color(hex: "1E6B12")
    public static let yesTint = Color(hex: "DFF5D6")
    public static let no = Color(hex: "CC3355")
    public static let noDeep = Color(hex: "8E1F38")
    public static let noTint = Color(hex: "FBDDE4")

    /// The live accent.
    public static let lime = Color(hex: "D9F930")
    public static let limeDeep = Color(hex: "9CB81A")

    // MARK: Meadow — welcome and sign-in only

    public static let meadow = Color(hex: "4DAE2C")
    public static let meadowMid = Color(hex: "3A9A22")
    public static let meadowDeep = Color(hex: "26781A")
    /// The hard shadow under white things on the meadow.
    public static let meadowShadow = Color(hex: "1E6B12")

    public static let skyTop = Color(hex: "46B7F0")
    public static let skyBottom = Color(hex: "C6EDFF")
    public static let cloudShade = Color(hex: "DDF2FF")
    public static let sun = Color(hex: "FFD23F")
    public static let sunCore = Color(hex: "FFE369")
    public static let sunGlow = Color(hex: "FFF4B8")
    public static let hillFar = Color(hex: "9BDB6C")
    public static let hillNear = Color(hex: "6CC24A")
    public static let leafDark = Color(hex: "2F8F2A")
    public static let leaf = Color(hex: "3FA637")
    public static let leafLight = Color(hex: "57B947")
    public static let leafGlint = Color(hex: "80D25A")
    public static let bark = Color(hex: "8A5A2E")
    public static let barkShade = Color(hex: "6E4422")
    public static let coin = Color(hex: "FFD23F")
    public static let coinEdge = Color(hex: "D9A100")
    public static let coinShine = Color(hex: "FFF0A6")

    /// White text on the meadow sits on `meadowMid` or deeper; this gradient
    /// gets there by the time body text starts.
    public static var meadowGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: meadow, location: 0),
                .init(color: meadowMid, location: 0.48),
                .init(color: meadowDeep, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static var skyGradient: LinearGradient {
        LinearGradient(colors: [skyTop, skyBottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Pip

    public enum Pip {
        public static let body = Color(hex: "FFB3C7")
        public static let bodyLight = Color(hex: "FFD3DE")
        public static let line = Color(hex: "E2789A")
        public static let shade = Color(hex: "F08AA8")
        public static let foot = Color(hex: "F598B2")
        public static let blush = Color(hex: "FF8FAE")
        public static let tongue = Color(hex: "FF6F91")
        public static let eye = Color(hex: "1F2557")
    }

    // MARK: Categories

    /// Bright shade: icons, dots, bars.
    public static func fill(_ category: MarketCategory) -> Color {
        Color(hex: category.fillHex)
    }

    /// Deep shade: any surface carrying white text.
    public static func panel(_ category: MarketCategory) -> Color {
        Color(hex: category.panelHex)
    }
}

#endif
