#if canImport(SwiftUI)
import SwiftUI

// MARK: - Hex helpers

extension Color {
    /// Builds a colour from a 6-digit hex string. Invalid input falls back to
    /// clear rather than trapping, so a typo never crashes a view.
    public init(hex: String) {
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

/// The semantic layer the screens were written against, now pointing at the
/// bright brand (`Brand`).
///
/// Every token keeps its name so the whole app moves onto the cream canvas in
/// one coherent step; screens are then restyled to the design one by one,
/// and tokens that nothing references any more are deleted.
public enum Palette {

    // MARK: Neutrals

    public static let canvas = Brand.canvas
    public static let surface = Brand.card
    public static let surfaceRaised = Brand.cardSunken

    public static let ink = Brand.ink
    public static let inkSecondary = Brand.inkSecondary
    public static let inkTertiary = Brand.inkTertiary
    public static let separator = Brand.hairline

    // MARK: Yes and No

    public static let yes = Brand.yes
    public static let yesSurface = Brand.yesTint
    public static let no = Brand.no
    public static let noSurface = Brand.noTint

    /// Price movement follows Yes and No, so a rising market and a Yes
    /// position read as the same direction.
    public static let up = yes
    public static let down = no

    /// Destructive actions only.
    public static let danger = Color(hex: "C9342B")
    /// Caution: stale data, partial fills, warnings.
    public static let caution = Color(hex: "B07A12")

    // MARK: Tab bar

    public static let tabBarFill = Brand.card
    public static let tabBarInk = Brand.inkTertiary
    public static let tabBarSelectedFill = Brand.ink
    public static let tabBarSelectedInk = Color.white

    // MARK: Themes

    /// A screen's colour identity.
    public struct Theme: Sendable, Hashable, Identifiable {
        public let id: String
        /// The screen or header background.
        public let screen: Color
        /// A card-weight surface on that screen.
        public let field: Color
        /// Text and icons on `screen`.
        public let onField: Color
        /// Control fill.
        public let control: Color
        /// Text on `control`.
        public let onControl: Color

        public init(id: String, screen: Color, field: Color, onField: Color, control: Color, onControl: Color) {
            self.id = id
            self.screen = screen
            self.field = field
            self.onField = onField
            self.control = control
            self.onControl = onControl
        }
    }

    /// The house theme: navy ink on cream. Every screen that belongs to no
    /// single market.
    public static let brand = Theme(
        id: "brand",
        screen: Brand.canvas,
        field: Brand.card,
        onField: Brand.ink,
        control: Brand.ink,
        onControl: .white
    )

    /// A market's theme: its category's panel colour with white on it. Used
    /// for the market header, never for a whole screen — a full-bleed
    /// category colour behind a chart and an order book competes with them.
    public static func theme(for category: MarketCategory) -> Theme {
        let panel = Brand.panel(category)
        return Theme(
            id: category.rawValue,
            screen: panel,
            field: panel,
            onField: .white,
            control: .white,
            onControl: panel
        )
    }

    public static let themes: [Theme] = [brand]

    /// Cards on the canvas.
    public enum Card {
        public static let fill = Brand.card
        public static let fillRaised = Brand.cardSunken
        public static let stroke = Brand.hairline
        public static let shadow = Brand.cardShadow

        public static let ink = Brand.ink
        public static let inkSecondary = Brand.inkSecondary
        public static let inkTertiary = Brand.inkTertiary
        public static let separator = Brand.hairline
    }

    public enum Tabs {
        public static var explore: Theme { brand }
        public static var portfolio: Theme { brand }
        public static var activity: Theme { brand }
        public static var profile: Theme { brand }
        public static var fallback: Theme { brand }
    }

    /// The house theme. Screens that know their event ask for
    /// `theme(for: event.category)` instead.
    public static func theme(named id: String) -> Theme { brand }
    public static func theme(for identifier: String) -> Theme { brand }
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
