#if canImport(SwiftUI)
import SwiftUI

// MARK: - Hex helpers

extension Color {
    /// Builds a colour from a 6-digit hex string. Invalid input falls back to
    /// clear rather than trapping, so a typo never crashes a view.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .clear
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A colour that resolves differently in light and dark mode.
    ///
    /// Defined in code rather than an asset catalog so the whole palette is
    /// readable in one file and reviewable in a diff.
    static func adaptive(light: String, dark: String) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        return Color(hex: light)
        #endif
    }
}

// MARK: - Palette

/// Pulse's colour system.
///
/// Built around solid pastel fields rather than gradients: each market carries
/// a flat colour identity, which gives the feed variety without decoration and
/// makes a market recognisable before its title is read. Neutrals are warm
/// (paper, not grey) so the pastels sit on them without clashing.
public enum Palette {

    // MARK: Neutrals

    /// Page background. Warm off-white in light, near-black in dark.
    public static let canvas = Color.adaptive(light: "FAF8F4", dark: "0E0E0D")
    /// Raised surface: cards, sheets, rows.
    public static let surface = Color.adaptive(light: "FFFFFF", dark: "1A1A18")
    /// A surface one step above `surface`, for nested content.
    public static let surfaceRaised = Color.adaptive(light: "F3F1EC", dark: "242421")

    /// Primary text.
    public static let ink = Color.adaptive(light: "11110F", dark: "F7F5F0")
    /// Secondary text: metadata, captions.
    public static let inkSecondary = Color.adaptive(light: "6B6962", dark: "A3A099")
    /// Tertiary text: the quietest legible level.
    public static let inkTertiary = Color.adaptive(light: "9A978E", dark: "6F6C65")

    /// Hairline separators.
    public static let separator = Color.adaptive(light: "E8E4DC", dark: "2E2E2A")

    // MARK: Semantic market colours
    //
    // Yes and No keep the same hues everywhere — list rows, charts, the trade
    // sheet, the order book — so the mapping is learned once.

    /// "Yes" — clean green, matched to the theme palette. The previous
    /// value carried grey, which turned muddy wherever it was drawn at
    /// partial opacity over a coloured field.
    public static let yes = Color.adaptive(light: "0FA45C", dark: "3DD98B")
    public static let yesSurface = Color.adaptive(light: "D6F3E3", dark: "0E3A26")

    /// "No" — a clean rose. Reads as the opposite of yes without being an
    /// alarm colour; pure red stays reserved for destructive actions.
    public static let no = Color.adaptive(light: "E03A60", dark: "FF7D9B")
    public static let noSurface = Color.adaptive(light: "FCDBE3", dark: "401A26")

    /// Price movement. Matches yes/no so a rising probability and a yes
    /// position read as the same direction.
    public static let up = yes
    public static let down = no

    /// Destructive actions only.
    public static let danger = Color.adaptive(light: "C9342B", dark: "FF7A70")
    /// Caution: stale data, partial fills, warnings.
    public static let caution = Color.adaptive(light: "B07A12", dark: "E8B44A")

    // MARK: Floating tab bar
    //
    // Dark in both appearances. The bar floats over saturated colour fields,
    // so it has to read as one object against mint, butter or rose alike — a
    // light bar disappears over the pale fields, and a tinted one fights them.

    /// Retained for the material fallback on pre-iOS-26 SDKs.
    public static let tabBarFill = Color.adaptive(light: "17171A", dark: "1C1C20")
    /// Unselected items sit on glass over a saturated field, so they are a
    /// dimmed white rather than a grey — a grey would read as disabled.
    public static let tabBarInk = Color.white.opacity(0.62)
    public static let tabBarSelectedFill = Color.white.opacity(0.22)
    public static let tabBarSelectedInk = Color.white

    // MARK: Market themes

    /// A flat colour identity assigned to a market or event.
    public struct Theme: Sendable, Hashable, Identifiable {
        public let id: String
        /// Screen-weight: saturated enough to own a whole background.
        public let screen: Color
        /// Card-weight: a lighter mix of the same hue, so a card reads as an
        /// object sitting on the screen rather than merging into it.
        public let field: Color
        /// Text and icons on either weight.
        public let onField: Color
        /// Control fill — a tinted pill, never a grey one.
        public let control: Color
        /// Text on `control`.
        public let onControl: Color

        public init(
            id: String,
            screen: Color,
            field: Color,
            onField: Color,
            control: Color,
            onControl: Color
        ) {
            self.id = id
            self.screen = screen
            self.field = field
            self.onField = onField
            self.control = control
            self.onControl = onControl
        }
    }

    /// The market themes.
    ///
    /// Clean saturated hues. Three earlier passes missed in three different
    /// directions: pale tints washed out at full-screen size, fully
    /// saturated ones read as electric, and desaturating those to fix it
    /// just made them dirty — adding grey to a hue does not refine it.
    ///
    /// These keep the hue pure and vary only lightness. Every variant below
    /// is generated from one base colour per theme by shifting lightness in
    /// HLS, so the hue is identical across light and dark and across the
    /// screen and card weights. `ink` is set by hand, because the same
    /// formula applied to an already-dark colour collapses it to near black
    /// with no separation between the field and the cards on it.
    ///
    /// `onField` is white on the deep hues and a dark tint of the hue itself
    /// on lime and butter, picked by luma rather than by eye.
    public static let themes: [Theme] = [
        Theme(
            id: "ink",
            screen: .adaptive(light: "152238", dark: "0C1420"),
            field: .adaptive(light: "1E3252", dark: "16233A"),
            onField: .adaptive(light: "FFFFFF", dark: "F2F5FA"),
            control: .adaptive(light: "FFFFFF", dark: "F2F5FA"),
            onControl: .adaptive(light: "152238", dark: "0C1420")
        ),
        Theme(
            id: "green",
            screen: .adaptive(light: "15A95C", dark: "0D5530"),
            field: .adaptive(light: "18C46B", dark: "11703E"),
            onField: .adaptive(light: "FFFFFF", dark: "A6E4C4"),
            control: .adaptive(light: "FFFFFF", dark: "A6E4C4"),
            onControl: .adaptive(light: "0E733E", dark: "0D5530")
        ),
        Theme(
            id: "lime",
            screen: .adaptive(light: "C9DB1E", dark: "7C8716"),
            field: .adaptive(light: "D3E334", dark: "95A11A"),
            onField: .adaptive(light: "1E2002", dark: "EEF1D4"),
            control: .adaptive(light: "1E2002", dark: "EEF1D4"),
            onControl: .adaptive(light: "EFF2D3", dark: "1E2002")
        ),
        Theme(
            id: "sky",
            screen: .adaptive(light: "2E7BE8", dark: "1651A4"),
            field: .adaptive(light: "4A8CEB", dark: "1A5EBF"),
            onField: .adaptive(light: "FFFFFF", dark: "E9F0F9"),
            control: .adaptive(light: "FFFFFF", dark: "E9F0F9"),
            onControl: .adaptive(light: "155DC3", dark: "1651A4")
        ),
        Theme(
            id: "lilac",
            screen: .adaptive(light: "7C5CE0", dark: "4B28B8"),
            field: .adaptive(light: "9176E5", dark: "552ED1"),
            onField: .adaptive(light: "FFFFFF", dark: "F6F4FB"),
            control: .adaptive(light: "FFFFFF", dark: "F6F4FB"),
            onControl: .adaptive(light: "5329D6", dark: "4B28B8")
        ),
        Theme(
            id: "coral",
            screen: .adaptive(light: "F2623F", dark: "C33512"),
            field: .adaptive(light: "F4795C", dark: "DF3C14"),
            onField: .adaptive(light: "FFFFFF", dark: "FCF4F3"),
            control: .adaptive(light: "FFFFFF", dark: "FCF4F3"),
            onControl: .adaptive(light: "E4390F", dark: "C33512")
        ),
        Theme(
            id: "butter",
            screen: .adaptive(light: "F0B429", dark: "AD7E10"),
            field: .adaptive(light: "F2BE46", dark: "C99213"),
            onField: .adaptive(light: "422E01", dark: "FAF6EB"),
            control: .adaptive(light: "422E01", dark: "FAF6EB"),
            onControl: .adaptive(light: "FBF6EA", dark: "422E01")
        ),
        Theme(
            id: "teal",
            screen: .adaptive(light: "10A3A8", dark: "0A5052"),
            field: .adaptive(light: "13BEC4", dark: "0D6A6E"),
            onField: .adaptive(light: "FFFFFF", dark: "9FE3E5"),
            control: .adaptive(light: "FFFFFF", dark: "9FE3E5"),
            onControl: .adaptive(light: "0B6D70", dark: "0A5052")
        )
    ]

    /// Surfaces on the dark list field.
    ///
    /// Cards are near-neutral, not tinted: on a navy field a light card reads
    /// cleanly and lets the artwork supply the colour. This is the single
    /// biggest difference between a feed that reads and one that shouts.
    public enum Card {
        /// A card on the dark list field.
        public static let fill = Color.adaptive(light: "FFFFFF", dark: "1B1D22")
        /// Text on that card.
        public static let ink = Color.adaptive(light: "11131A", dark: "F4F5F7")
        public static let inkSecondary = Color.adaptive(light: "61646E", dark: "9A9EA8")
        public static let inkTertiary = Color.adaptive(light: "8E919B", dark: "6B6F79")
        /// Hairline inside a card.
        public static let separator = Color.adaptive(light: "E6E7EB", dark: "2B2E35")
    }

    public enum Tabs {
        public static var explore: Theme { theme(named: "ink") }
        public static var portfolio: Theme { theme(named: "ink") }
        public static var activity: Theme { theme(named: "ink") }
        public static var profile: Theme { theme(named: "ink") }
        public static var fallback: Theme { theme(named: "ink") }
    }

    /// Looks a theme up by id, falling back to the first rather than trapping.
    public static func theme(named id: String) -> Theme {
        themes.first { $0.id == id } ?? themes[0]
    }

    /// Picks a stable theme for any identifier.
    ///
    /// Deterministic so a market looks the same on every launch and on every
    /// device — a hash of the string rather than `hashValue`, which Swift
    /// seeds randomly per process.
    ///
    /// Memoised because this is called from view bodies that re-evaluate on
    /// every frame of a scroll. The mapping is pure, so a cache can never be
    /// wrong; it is bounded so a long browsing session cannot grow it without
    /// limit.
    public static func theme(for identifier: String) -> Theme {
        guard !identifier.isEmpty else { return themes[0] }
        if let cached = themeCache.withLock({ $0[identifier] }) { return cached }

        let resolved = themes[Int(hash(identifier) % UInt64(themes.count))]
        themeCache.withLock { cache in
            // Far more than a feed ever holds; clearing wholesale avoids the
            // bookkeeping an LRU would need for no practical gain.
            if cache.count > 512 { cache.removeAll(keepingCapacity: true) }
            cache[identifier] = resolved
        }
        return resolved
    }

    /// FNV-1a: tiny, stable, and well spread for short strings.
    private static func hash(_ identifier: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private static let themeCache = Locked<[String: Theme]>([:])
}

// MARK: - Probability colouring

public extension Palette {
    /// Blends toward yes or no as a probability approaches certainty, so a
    /// 95% market reads differently from a coin flip at a glance.
    static func probabilityTint(_ probability: Double) -> Color {
        if probability >= 0.5 { return yes }
        return no
    }

    /// Opacity for a probability chip: confident markets read stronger.
    static func probabilityEmphasis(_ probability: Double) -> Double {
        let distance = abs(probability - 0.5) * 2   // 0 at a coin flip, 1 at certainty
        return 0.45 + 0.55 * distance
    }
}

#endif
