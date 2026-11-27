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

    public static let tabBarFill = Color.adaptive(light: "17171A", dark: "232326")
    public static let tabBarInk = Color.adaptive(light: "9B9BA2", dark: "8E8E96")
    public static let tabBarSelectedFill = Color.adaptive(light: "2E2E33", dark: "3A3A40")
    public static let tabBarSelectedInk = Color.adaptive(light: "FFFFFF", dark: "FFFFFF")

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

    /// The eight market themes.
    ///
    /// Two weights per hue. `screen` carries real chroma because a pale tint
    /// stretched edge to edge reads as off-white, not as colour; `field` is
    /// the lighter mix used for cards on top of it. `onField` is a deep tint
    /// of the same hue rather than black, which keeps the surfaces feeling
    /// coloured rather than printed on.
    public static let themes: [Theme] = [
        Theme(
            id: "mint",
            screen: .adaptive(light: "A6DCC1", dark: "10281F"),
            field: .adaptive(light: "D6EFE1", dark: "1B3B2E"),
            onField: .adaptive(light: "0A3326", dark: "D6EFE1"),
            control: .adaptive(light: "0A3326", dark: "D6EFE1"),
            onControl: .adaptive(light: "EAF7F0", dark: "0A3326")
        ),
        Theme(
            id: "butter",
            screen: .adaptive(light: "F3D978", dark: "2E2710"),
            field: .adaptive(light: "FAEDBC", dark: "3E3516"),
            onField: .adaptive(light: "443505", dark: "FAEDBC"),
            control: .adaptive(light: "443505", dark: "FAEDBC"),
            onControl: .adaptive(light: "FDF6DC", dark: "443505")
        ),
        Theme(
            id: "sky",
            screen: .adaptive(light: "9CCCF2", dark: "102634"),
            field: .adaptive(light: "CFE7F9", dark: "173546"),
            onField: .adaptive(light: "0B2D46", dark: "CFE7F9"),
            control: .adaptive(light: "0B2D46", dark: "CFE7F9"),
            onControl: .adaptive(light: "E8F3FC", dark: "0B2D46")
        ),
        Theme(
            id: "lilac",
            screen: .adaptive(light: "C2B8EE", dark: "211C38"),
            field: .adaptive(light: "E2DCF8", dark: "2C2648"),
            onField: .adaptive(light: "281E4D", dark: "E2DCF8"),
            control: .adaptive(light: "281E4D", dark: "E2DCF8"),
            onControl: .adaptive(light: "F0EDFB", dark: "281E4D")
        ),
        Theme(
            id: "peach",
            screen: .adaptive(light: "F8BE9D", dark: "33221A"),
            field: .adaptive(light: "FDE0D0", dark: "432D21"),
            onField: .adaptive(light: "52240F", dark: "FDE0D0"),
            control: .adaptive(light: "52240F", dark: "FDE0D0"),
            onControl: .adaptive(light: "FEEFE6", dark: "52240F")
        ),
        Theme(
            id: "rose",
            screen: .adaptive(light: "F4ADBF", dark: "311A22"),
            field: .adaptive(light: "FBD8E0", dark: "40232C"),
            onField: .adaptive(light: "51182A", dark: "FBD8E0"),
            control: .adaptive(light: "51182A", dark: "FBD8E0"),
            onControl: .adaptive(light: "FDEBEF", dark: "51182A")
        ),
        Theme(
            id: "sage",
            screen: .adaptive(light: "C0D3A9", dark: "1F2819"),
            field: .adaptive(light: "E1EAD5", dark: "2A3422"),
            onField: .adaptive(light: "293618", dark: "E1EAD5"),
            control: .adaptive(light: "293618", dark: "E1EAD5"),
            onControl: .adaptive(light: "EFF4E8", dark: "293618")
        ),
        Theme(
            id: "clay",
            screen: .adaptive(light: "E2BD9C", dark: "2E221A"),
            field: .adaptive(light: "F1DECB", dark: "3C2C21"),
            onField: .adaptive(light: "472E1C", dark: "F1DECB"),
            control: .adaptive(light: "472E1C", dark: "F1DECB"),
            onControl: .adaptive(light: "F8EEE4", dark: "472E1C")
        )
    ]

    /// Signature themes per tab.
    ///
    /// Each destination owns a hue, so switching tabs is a visible change of
    /// place rather than a change of list contents. Home is the exception: it
    /// takes the colour of whatever is featured, so the feed drives it.
    public enum Tabs {
        public static var explore: Theme { theme(named: "sky") }
        public static var portfolio: Theme { theme(named: "mint") }
        public static var activity: Theme { theme(named: "clay") }
        public static var profile: Theme { theme(named: "lilac") }
        public static var fallback: Theme { theme(named: "butter") }
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
