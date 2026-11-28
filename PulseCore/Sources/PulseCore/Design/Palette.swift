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

/// Pulse's colour system.
///
/// One *language*, many colours.
///
/// Every screen is the same vertical gradient: near-black at the top,
/// falling to a saturated colour at the bottom. That shape is what makes
/// the app recognisable. Which colour it falls to is the market's own, so
/// a feed of twelve markets is twelve colours and a market keeps the same
/// one on every visit.
///
/// Collapsing this to a single violet — one gradient for everything — was
/// a mistake: it made the product consistent and completely monotonous,
/// and threw away the only thing that tells two markets apart at a glance.
/// The fix is not to go back to nine unrelated pastels, which made the feed
/// a rainbow. It is to keep one structure and vary one variable.
///
/// Gradients are fixed rather than adaptive. They are the brand the way a
/// logo is; text on them is white in both appearances.
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

    /// "Yes" — the acid accent. On a violet field, lime is the only thing
    /// that reads instantly at any size, which is what a Yes needs to do.
    public static let yes = Color(hex: "D9F930")
    public static let yesSurface = Color(hex: "D9F930").opacity(0.18)

    /// "No" — a warm pink. Opposite the lime without being an alarm colour;
    /// pure red stays for destructive actions.
    public static let no = Color(hex: "FF7A9C")
    public static let noSurface = Color(hex: "FF7A9C").opacity(0.18)

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

    /// The dark end. Shared by every gradient, which is what keeps twelve
    /// colours reading as one app rather than twelve.
    public static let fieldTop = Color(hex: "0C0A14")

    /// The saturated ends, one per market.
    ///
    /// All at a similar lightness and chroma so no market looks louder than
    /// another — the rainbow problem was colours of wildly different weight
    /// sitting next to each other, not the count of them.
    public static let accents: [Color] = [
        Color(hex: "B45CD6"),   // violet
        Color(hex: "3FA7E8"),   // azure
        Color(hex: "2FB08A"),   // jade
        Color(hex: "E86A8E"),   // rose
        Color(hex: "E8893F"),   // amber
        Color(hex: "7C6CE8"),   // indigo
        Color(hex: "3FBFC4"),   // teal
        Color(hex: "C95CA8"),   // magenta
        Color(hex: "7EA82F"),   // olive
        Color(hex: "E05C5C")    // coral
    ]

    /// The house colour, for screens that belong to no single market:
    /// the feed, portfolio, activity, profile, onboarding, sign-in.
    public static let fieldBottom = accents[0]

    /// A gradient ending in `colour`. The mid stop is placed low so the
    /// dark end holds the headline and the colour arrives around the
    /// action row, rather than washing the whole screen.
    public static func gradient(to colour: Color) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: fieldTop, location: 0),
                .init(color: colour.opacity(0.45), location: 0.58),
                .init(color: colour, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The house gradient.
    public static var fieldGradient: LinearGradient { gradient(to: fieldBottom) }

    /// A market's own gradient, stable across launches and devices.
    public static func fieldGradient(for identifier: String) -> LinearGradient {
        gradient(to: accent(for: identifier))
    }

    /// A market's colour. FNV-1a rather than `hashValue`, which Swift seeds
    /// randomly per process — that would recolour the feed on every launch.
    public static func accent(for identifier: String) -> Color {
        guard !identifier.isEmpty else { return fieldBottom }
        if let cached = accentCache.withLock({ $0[identifier] }) { return cached }
        let resolved = accents[Int(hash(identifier) % UInt64(accents.count))]
        accentCache.withLock { cache in
            if cache.count > 512 { cache.removeAll(keepingCapacity: true) }
            cache[identifier] = resolved
        }
        return resolved
    }

    private static func hash(_ identifier: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private static let accentCache = Locked<[String: Color]>([:])

    /// The house identity, for screens that belong to no market.
    public static let brand = Theme(
        id: "brand",
        screen: fieldTop,
        field: fieldTop,
        onField: Color(hex: "FFFFFF"),
        control: Color(hex: "D9F930"),
        onControl: Color(hex: "16121F")
    )

    public static let themes: [Theme] = [brand]

    /// Card surfaces.
    ///
    /// Translucent white rather than an opaque panel, so the gradient shows
    /// through and a card belongs to the screen it sits on. An opaque card
    /// on a gradient reads as a sticker, and stacking several of them hides
    /// the gradient entirely — which is the whole identity.
    public enum Card {
        public static let fill = Color.white.opacity(0.09)
        public static let fillRaised = Color.white.opacity(0.14)
        public static let stroke = Color.white.opacity(0.12)

        public static let ink = Color(hex: "FFFFFF")
        public static let inkSecondary = Color.white.opacity(0.66)
        public static let inkTertiary = Color.white.opacity(0.44)
        public static let separator = Color.white.opacity(0.12)
    }

    public enum Tabs {
        public static var explore: Theme { brand }
        public static var portfolio: Theme { brand }
        public static var activity: Theme { brand }
        public static var profile: Theme { brand }
        public static var fallback: Theme { brand }
    }

    /// Kept so existing call sites compile. There is one identity now, so
    /// both lookups answer the same thing — no hashing, no cache, and no way
    /// for an unknown id to silently select a different-looking screen,
    /// which is a bug this file has shipped twice.
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
