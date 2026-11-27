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

    // MARK: Market themes

    /// A flat colour identity assigned to a market or event.
    public struct Theme: Sendable, Hashable, Identifiable {
        public let id: String
        /// The full-bleed field colour.
        public let field: Color
        /// Text and icons placed on `field`.
        public let onField: Color
        /// Control fill on `field` — a tinted pill, not a grey one.
        public let control: Color
        /// Text on `control`.
        public let onControl: Color

        public init(id: String, field: Color, onField: Color, control: Color, onControl: Color) {
            self.id = id
            self.field = field
            self.onField = onField
            self.control = control
            self.onControl = onControl
        }
    }

    /// The eight market themes.
    ///
    /// Each is a solid pastel in light mode and a deepened version of the same
    /// hue in dark mode, so a market keeps its identity across appearances.
    /// `onField` is always a dark tint of the same hue rather than pure black,
    /// which keeps the fields feeling coloured rather than printed on.
    public static let themes: [Theme] = [
        Theme(
            id: "mint",
            field: .adaptive(light: "C7E9D7", dark: "16342A"),
            onField: .adaptive(light: "0C3A2A", dark: "C7E9D7"),
            control: .adaptive(light: "0C3A2A", dark: "C7E9D7"),
            onControl: .adaptive(light: "EAF7F0", dark: "0C3A2A")
        ),
        Theme(
            id: "butter",
            field: .adaptive(light: "F7E6A6", dark: "3A3212"),
            onField: .adaptive(light: "4A3A08", dark: "F7E6A6"),
            control: .adaptive(light: "4A3A08", dark: "F7E6A6"),
            onControl: .adaptive(light: "FDF6DC", dark: "4A3A08")
        ),
        Theme(
            id: "sky",
            field: .adaptive(light: "C1DFF6", dark: "14303F"),
            onField: .adaptive(light: "0E3450", dark: "C1DFF6"),
            control: .adaptive(light: "0E3450", dark: "C1DFF6"),
            onControl: .adaptive(light: "E8F3FC", dark: "0E3450")
        ),
        Theme(
            id: "lilac",
            field: .adaptive(light: "DAD3F5", dark: "272243"),
            onField: .adaptive(light: "2E2456", dark: "DAD3F5"),
            control: .adaptive(light: "2E2456", dark: "DAD3F5"),
            onControl: .adaptive(light: "F0EDFB", dark: "2E2456")
        ),
        Theme(
            id: "peach",
            field: .adaptive(light: "FBD6C1", dark: "3E2A1F"),
            onField: .adaptive(light: "5A2A14", dark: "FBD6C1"),
            control: .adaptive(light: "5A2A14", dark: "FBD6C1"),
            onControl: .adaptive(light: "FEEFE6", dark: "5A2A14")
        ),
        Theme(
            id: "rose",
            field: .adaptive(light: "F8CAD5", dark: "3C2029"),
            onField: .adaptive(light: "5A1F32", dark: "F8CAD5"),
            control: .adaptive(light: "5A1F32", dark: "F8CAD5"),
            onControl: .adaptive(light: "FDEBEF", dark: "5A1F32")
        ),
        Theme(
            id: "sage",
            field: .adaptive(light: "D8E4C9", dark: "26301E"),
            onField: .adaptive(light: "2F3D1E", dark: "D8E4C9"),
            control: .adaptive(light: "2F3D1E", dark: "D8E4C9"),
            onControl: .adaptive(light: "EFF4E8", dark: "2F3D1E")
        ),
        Theme(
            id: "clay",
            field: .adaptive(light: "ECD5C0", dark: "37291E"),
            onField: .adaptive(light: "4E3522", dark: "ECD5C0"),
            control: .adaptive(light: "4E3522", dark: "ECD5C0"),
            onControl: .adaptive(light: "F8EEE4", dark: "4E3522")
        )
    ]

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
