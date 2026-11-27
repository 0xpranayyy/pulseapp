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
    /// Saturated, not pastel. The references hold a whole screen in deep navy,
    /// a confident green or a chartreuse — colours with enough weight that
    /// white type and white cards sit on them cleanly. A pale tint at full
    /// screen size reads as off-white, which is what made the first pass look
    /// like a settings app.
    ///
    /// `onField` is near-white on the dark fields and near-black on the bright
    /// ones, chosen per theme rather than derived, so contrast is deliberate
    /// at every step.
    public static let themes: [Theme] = [
        Theme(
            id: "ink",
            screen: .adaptive(light: "0E2238", dark: "081726"),
            field: .adaptive(light: "17324D", dark: "11253A"),
            onField: .adaptive(light: "F2F6FA", dark: "F2F6FA"),
            control: .adaptive(light: "F2F6FA", dark: "F2F6FA"),
            onControl: .adaptive(light: "0E2238", dark: "081726")
        ),
        Theme(
            id: "green",
            screen: .adaptive(light: "11914B", dark: "0B5C31"),
            field: .adaptive(light: "17A757", dark: "0E6E3B"),
            onField: .adaptive(light: "FFFFFF", dark: "EAF7EF"),
            control: .adaptive(light: "FFFFFF", dark: "EAF7EF"),
            onControl: .adaptive(light: "0C6435", dark: "0B5C31")
        ),
        Theme(
            id: "chartreuse",
            screen: .adaptive(light: "C3D600", dark: "6E7A00"),
            field: .adaptive(light: "D3E22E", dark: "879600"),
            onField: .adaptive(light: "1B2000", dark: "F2F7CE"),
            control: .adaptive(light: "1B2000", dark: "F2F7CE"),
            onControl: .adaptive(light: "E8F09A", dark: "1B2000")
        ),
        Theme(
            id: "cobalt",
            screen: .adaptive(light: "1B4FD8", dark: "11317F"),
            field: .adaptive(light: "2C61EC", dark: "173E9C"),
            onField: .adaptive(light: "FFFFFF", dark: "E6EDFD"),
            control: .adaptive(light: "FFFFFF", dark: "E6EDFD"),
            onControl: .adaptive(light: "16409F", dark: "11317F")
        ),
        Theme(
            id: "violet",
            screen: .adaptive(light: "6A3BD6", dark: "40217F"),
            field: .adaptive(light: "7D52E4", dark: "4F2B9B"),
            onField: .adaptive(light: "FFFFFF", dark: "EDE6FC"),
            control: .adaptive(light: "FFFFFF", dark: "EDE6FC"),
            onControl: .adaptive(light: "4E2AA3", dark: "40217F")
        ),
        Theme(
            id: "ember",
            screen: .adaptive(light: "D4452A", dark: "81291A"),
            field: .adaptive(light: "E65A3C", dark: "9C3422"),
            onField: .adaptive(light: "FFFFFF", dark: "FDE7E1"),
            control: .adaptive(light: "FFFFFF", dark: "FDE7E1"),
            onControl: .adaptive(light: "A5331F", dark: "81291A")
        ),
        Theme(
            id: "sand",
            screen: .adaptive(light: "E8C76B", dark: "6E5720"),
            field: .adaptive(light: "F0D88F", dark: "85692A"),
            onField: .adaptive(light: "2A1F00", dark: "FBF0D2"),
            control: .adaptive(light: "2A1F00", dark: "FBF0D2"),
            onControl: .adaptive(light: "F7EBC4", dark: "2A1F00")
        ),
        Theme(
            id: "teal",
            screen: .adaptive(light: "0B7D86", dark: "064B52"),
            field: .adaptive(light: "0F969F", dark: "085D66"),
            onField: .adaptive(light: "FFFFFF", dark: "DFF4F6"),
            control: .adaptive(light: "FFFFFF", dark: "DFF4F6"),
            onControl: .adaptive(light: "08626A", dark: "064B52")
        )
    ]

    /// Signature themes per tab.
    ///
    /// Each destination owns a hue, so switching tabs is a visible change of
    /// place rather than a change of list contents. Home is the exception: it
    /// takes the colour of whatever is featured, so the feed drives it.
    public enum Tabs {
        public static var explore: Theme { theme(named: "cobalt") }
        public static var portfolio: Theme { theme(named: "green") }
        public static var activity: Theme { theme(named: "ink") }
        public static var profile: Theme { theme(named: "violet") }
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
    public static func theme(for identifier: String) -> Theme {
        guard !identifier.isEmpty else { return themes[0] }
        // FNV-1a: tiny, stable, and well spread for short strings.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return themes[Int(hash % UInt64(themes.count))]
    }
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
