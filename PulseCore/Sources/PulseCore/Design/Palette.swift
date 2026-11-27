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

    /// "Yes" — a grounded green, not a neon one.
    public static let yes = Color.adaptive(light: "1B8A5A", dark: "4BC68E")
    public static let yesSurface = Color.adaptive(light: "D4EFE0", dark: "16352A")

    /// "No" — a warm rose that reads as the opposite of yes without being an
    /// alarm colour. Pure red is reserved for destructive actions.
    public static let no = Color.adaptive(light: "C2365B", dark: "F2869F")
    public static let noSurface = Color.adaptive(light: "FAD8E1", dark: "3B2028")

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
    /// Solid and muted, not pastel and not neon. Two earlier passes missed in
    /// both directions: pale tints washed out at full-screen size, then fully
    /// saturated hues read as electric and fought each other in a feed.
    ///
    /// These sit at roughly one perceptual weight — mid lightness, mid chroma
    /// — which is what lets eight of them feel like one family rather than a
    /// swatch book. Each is flat: no gradients anywhere in the palette.
    ///
    /// `onField` is white on the deeper hues and near-black on lime and
    /// butter, chosen per theme so contrast is deliberate rather than derived.
    public static let themes: [Theme] = [
        Theme(
            id: "ink",
            screen: .adaptive(light: "1B2C44", dark: "111C2B"),
            field: .adaptive(light: "27405F", dark: "1B2C44"),
            onField: .adaptive(light: "F3F6FA", dark: "F3F6FA"),
            control: .adaptive(light: "F3F6FA", dark: "F3F6FA"),
            onControl: .adaptive(light: "1B2C44", dark: "111C2B")
        ),
        Theme(
            id: "green",
            screen: .adaptive(light: "2A9159", dark: "1B6039"),
            field: .adaptive(light: "34A567", dark: "217546"),
            onField: .adaptive(light: "FFFFFF", dark: "E9F6EE"),
            control: .adaptive(light: "FFFFFF", dark: "E9F6EE"),
            onControl: .adaptive(light: "216F44", dark: "1B6039")
        ),
        Theme(
            id: "lime",
            screen: .adaptive(light: "C3CF3C", dark: "70791F"),
            field: .adaptive(light: "D0DB5C", dark: "869029"),
            onField: .adaptive(light: "232703", dark: "F3F7D4"),
            control: .adaptive(light: "232703", dark: "F3F7D4"),
            onControl: .adaptive(light: "EEF2BE", dark: "232703")
        ),
        Theme(
            id: "sky",
            screen: .adaptive(light: "4C8FCB", dark: "2A5A86"),
            field: .adaptive(light: "61A0D8", dark: "356E9F"),
            onField: .adaptive(light: "FFFFFF", dark: "E8F1F9"),
            control: .adaptive(light: "FFFFFF", dark: "E8F1F9"),
            onControl: .adaptive(light: "2F6A9F", dark: "2A5A86")
        ),
        Theme(
            id: "lilac",
            screen: .adaptive(light: "8073CE", dark: "4F4590"),
            field: .adaptive(light: "9186D8", dark: "5F54A6"),
            onField: .adaptive(light: "FFFFFF", dark: "EFEDFA"),
            control: .adaptive(light: "FFFFFF", dark: "EFEDFA"),
            onControl: .adaptive(light: "584CA3", dark: "4F4590")
        ),
        Theme(
            id: "coral",
            screen: .adaptive(light: "D9704F", dark: "8E4330"),
            field: .adaptive(light: "E28468", dark: "A5523C"),
            onField: .adaptive(light: "FFFFFF", dark: "FBEAE4"),
            control: .adaptive(light: "FFFFFF", dark: "FBEAE4"),
            onControl: .adaptive(light: "A8523A", dark: "8E4330")
        ),
        Theme(
            id: "butter",
            screen: .adaptive(light: "E6C463", dark: "7D682A"),
            field: .adaptive(light: "EDD183", dark: "937C36"),
            onField: .adaptive(light: "2B2208", dark: "FBF3D9"),
            control: .adaptive(light: "2B2208", dark: "FBF3D9"),
            onControl: .adaptive(light: "F6EDCB", dark: "2B2208")
        ),
        Theme(
            id: "teal",
            screen: .adaptive(light: "35959C", dark: "1D5F64"),
            field: .adaptive(light: "43A8AF", dark: "27747A"),
            onField: .adaptive(light: "FFFFFF", dark: "E3F3F4"),
            control: .adaptive(light: "FFFFFF", dark: "E3F3F4"),
            onControl: .adaptive(light: "277177", dark: "1D5F64")
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
