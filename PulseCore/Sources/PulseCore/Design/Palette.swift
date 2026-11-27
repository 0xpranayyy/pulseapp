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

    /// "Yes" — a deep green on a pastel surface. Both halves of the pair
    /// are drawn from the same family as the themes, so a Yes pill on a
    /// sage field belongs to it rather than sitting on top of it.
    public static let yes = Color.adaptive(light: "1F5A2E", dark: "8FD3A3")
    public static let yesSurface = Color.adaptive(light: "C9E3C0", dark: "1E3826")

    /// "No" — a deep rose on a pastel surface. Reads as the opposite of yes
    /// without being an alarm colour; pure red stays for destructive actions.
    public static let no = Color.adaptive(light: "8C2437", dark: "F0A8B4")
    public static let noSurface = Color.adaptive(light: "F2CCCE", dark: "3C1F26")

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
    /// Soft pastels with enough chroma to stay colours rather than tints.
    /// The earlier pastel attempt failed because it was *pale* — very low
    /// chroma, plus white cards on top — not because it was pastel. These
    /// keep real saturation and pair with a deep ink of the field's own hue,
    /// never black, which is what stops a pastel reading as paper.
    ///
    /// Variants are generated from one base colour per theme by shifting
    /// lightness in HLS, so the hue is identical across light and dark and
    /// across the screen and card weights.
    ///
    /// `ink` is the odd one out and deliberately so: list screens need
    /// something calm to hold a stack of cards, and the pastels do their
    /// work on the detail screens and the featured carousel. Assigning a
    /// pastel to a whole feed is what produced the rainbow earlier.
    public static let themes: [Theme] = [
        Theme(
            id: "ink",
            screen: .adaptive(light: "262E38", dark: "12171D"),
            field: .adaptive(light: "333C49", dark: "1C222A"),
            onField: .adaptive(light: "F4F6F8", dark: "F4F6F8"),
            control: .adaptive(light: "F4F6F8", dark: "F4F6F8"),
            onControl: .adaptive(light: "262E38", dark: "12171D")
        ),
        Theme(
            id: "sage",
            screen: .adaptive(light: "B5D0A6", dark: "33432A"),
            field: .adaptive(light: "C3D9B7", dark: "445938"),
            onField: .adaptive(light: "203D10", dark: "E2E9DF"),
            control: .adaptive(light: "203D10", dark: "E2E9DF"),
            onControl: .adaptive(light: "CBDEC1", dark: "33432A")
        ),
        Theme(
            id: "butter",
            screen: .adaptive(light: "EFD98E", dark: "614F13"),
            field: .adaptive(light: "F2E1A4", dark: "7F6819"),
            onField: .adaptive(light: "4C3B00", dark: "F6EFD8"),
            control: .adaptive(light: "4C3B00", dark: "F6EFD8"),
            onControl: .adaptive(light: "F4E5B2", dark: "614F13")
        ),
        Theme(
            id: "sky",
            screen: .adaptive(light: "A8CBE6", dark: "234662"),
            field: .adaptive(light: "BCD7EC", dark: "2C597C"),
            onField: .adaptive(light: "062A46", dark: "E9F1F6"),
            control: .adaptive(light: "062A46", dark: "E9F1F6"),
            onControl: .adaptive(light: "C8DEEF", dark: "234662")
        ),
        Theme(
            id: "lilac",
            screen: .adaptive(light: "C3B5E8", dark: "3B296B"),
            field: .adaptive(light: "D3C8EE", dark: "493385"),
            onField: .adaptive(light: "180745", dark: "F6F4FA"),
            control: .adaptive(light: "180745", dark: "F6F4FA"),
            onControl: .adaptive(light: "DCD4F2", dark: "3B296B")
        ),
        Theme(
            id: "blush",
            screen: .adaptive(light: "F0BEB2", dark: "7A311F"),
            field: .adaptive(light: "F4D0C7", dark: "963C26"),
            onField: .adaptive(light: "4B1002", dark: "FCF5F3"),
            control: .adaptive(light: "4B1002", dark: "FCF5F3"),
            onControl: .adaptive(light: "F7DBD4", dark: "7A311F")
        ),
        Theme(
            id: "clay",
            screen: .adaptive(light: "E0C29C", dark: "533C20"),
            field: .adaptive(light: "E6CEAF", dark: "6D4F2A"),
            onField: .adaptive(light: "452A08", dark: "F1E8DD"),
            control: .adaptive(light: "452A08", dark: "F1E8DD"),
            onControl: .adaptive(light: "EAD5BB", dark: "533C20")
        ),
        Theme(
            id: "mist",
            screen: .adaptive(light: "A6D2CD", dark: "2A4542"),
            field: .adaptive(light: "B7DBD7", dark: "375B57"),
            onField: .adaptive(light: "0F3E38", dark: "DFEAE9"),
            control: .adaptive(light: "0F3E38", dark: "DFEAE9"),
            onControl: .adaptive(light: "C1E0DC", dark: "2A4542")
        ),
        Theme(
            id: "plum",
            screen: .adaptive(light: "D9B5D2", dark: "52324C"),
            field: .adaptive(light: "E2C6DC", dark: "694061"),
            onField: .adaptive(light: "3D0F34", dark: "F3EDF2"),
            control: .adaptive(light: "3D0F34", dark: "F3EDF2"),
            onControl: .adaptive(light: "E7D0E2", dark: "52324C")
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
