import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Allo — the app's typeface.
///
/// Bundled as six upright weights (OFL-1.1). Two details matter beyond
/// picking a face:
///
/// * **Dynamic Type.** Every style goes through `relativeTo:`, so a custom
///   font still scales with the reader's chosen size. A bare
///   `Font.custom(_:size:)` would freeze the app at one size.
/// * **Tabular figures.** Allo ships proportional figures by default, which
///   makes a live price jitter as digits change width. Anything numeric that
///   updates in place or sits in a column asks for the `tnum` feature.
public enum Allo {
    public enum Weight: String {
        case regular = "Allo-Regular"
        case medium = "Allo-Medium"
        case semibold = "Allo-SemiBold"
        case bold = "Allo-Bold"
        case extrabold = "Allo-ExtraBold"
        case black = "Allo-Black"
    }

    /// A text-scaled Allo font.
    public static func font(
        _ weight: Weight,
        size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// Allo with tabular (fixed-width) figures.
    ///
    /// Built through `UIFontDescriptor` because SwiftUI's `Font` API exposes
    /// no way to turn on an OpenType feature. Falls back to the plain face if
    /// the font is missing, so a bundling mistake degrades instead of
    /// crashing.
    public static func tabular(
        _ weight: Weight,
        size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        #if canImport(UIKit)
        guard let base = UIFont(name: weight.rawValue, size: size) else {
            return .system(size: size, weight: .semibold).monospacedDigit()
        }
        // kNumberSpacingType / kMonospacedNumbersSelector
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        let tabularFont = UIFont(descriptor: descriptor, size: size)
        // Scale for Dynamic Type the same way `relativeTo:` would.
        let scaled = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: tabularFont)
        return Font(scaled)
        #else
        return font(weight, size: size, relativeTo: style).monospacedDigit()
        #endif
    }

    /// True when the bundled fonts actually registered. Used by a debug
    /// assertion so a missing font is noticed in development rather than
    /// quietly falling back to San Francisco.
    public static var isAvailable: Bool {
        #if canImport(UIKit)
        return UIFont(name: Weight.bold.rawValue, size: 12) != nil
        #else
        return false
        #endif
    }
}

#if canImport(UIKit)
private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
#endif

/// The type scale.
///
/// Deliberately few sizes, and a hard jump between them. The references get
/// their confidence from one very large headline against small quiet
/// metadata — a smooth ramp of six similar sizes reads as a settings screen.
public enum Typography {

    // MARK: Display

    /// Onboarding and hero headlines. Black weight, tight tracking.
    public static let hero = Allo.font(.black, size: 44, relativeTo: .largeTitle)
    /// Screen titles.
    public static let display = Allo.font(.extrabold, size: 32, relativeTo: .largeTitle)
    public static let title = Allo.font(.bold, size: 26, relativeTo: .title)
    public static let title2 = Allo.font(.bold, size: 21, relativeTo: .title2)
    public static let title3 = Allo.font(.semibold, size: 18, relativeTo: .title3)

    // MARK: Body

    public static let headline = Allo.font(.semibold, size: 16, relativeTo: .headline)
    public static let body = Allo.font(.regular, size: 16, relativeTo: .body)
    public static let bodyMedium = Allo.font(.medium, size: 16, relativeTo: .body)
    public static let callout = Allo.font(.regular, size: 15, relativeTo: .callout)
    public static let subheadline = Allo.font(.regular, size: 14, relativeTo: .subheadline)
    public static let subheadlineMedium = Allo.font(.medium, size: 14, relativeTo: .subheadline)
    public static let footnote = Allo.font(.regular, size: 13, relativeTo: .footnote)
    public static let caption = Allo.font(.regular, size: 12, relativeTo: .caption)
    public static let captionMedium = Allo.font(.medium, size: 12, relativeTo: .caption)

    /// Small all-caps labels. Pair with `.tracking(0.8)`.
    public static let overline = Allo.font(.semibold, size: 11, relativeTo: .caption2)

    // MARK: Numerals — all tabular

    /// The probability on a market screen. Very large on purpose.
    public static let probabilityHero = Allo.tabular(.black, size: 56, relativeTo: .largeTitle)
    public static let probabilityLarge = Allo.tabular(.extrabold, size: 38, relativeTo: .largeTitle)
    /// Probability in a feed row.
    public static let probability = Allo.tabular(.bold, size: 22, relativeTo: .title2)
    public static let probabilitySmall = Allo.tabular(.semibold, size: 15, relativeTo: .subheadline)

    public static let currencyLarge = Allo.tabular(.extrabold, size: 38, relativeTo: .largeTitle)
    public static let currency = Allo.tabular(.semibold, size: 17, relativeTo: .headline)
    public static let currencySmall = Allo.tabular(.medium, size: 13, relativeTo: .footnote)

    /// Order-book rows and other dense columns.
    public static let tabular = Allo.tabular(.regular, size: 13, relativeTo: .footnote)
    public static let tabularMedium = Allo.tabular(.medium, size: 13, relativeTo: .footnote)
}

// MARK: - Layout

public enum Layout {

    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let small: CGFloat = 12
        /// Cards. Generous, matching the references' soft geometry.
        public static let medium: CGFloat = 20
        public static let large: CGFloat = 28
        /// Hero artwork and sheets.
        public static let xlarge: CGFloat = 34
        public static let pill: CGFloat = 999
    }

    public enum Size {
        public static let minimumTapTarget: CGFloat = 44
        public static let iconButton: CGFloat = 44
        /// Artwork in a feed row. Large by design — the references lead with
        /// the image, not with a favicon beside a headline.
        public static let rowArt: CGFloat = 76
        public static let heroArt: CGFloat = 132
        /// Clearance so content scrolls clear of the floating tab bar.
        public static let tabBarClearance: CGFloat = 124
    }

    public static let gutter: CGFloat = Space.l
}

// MARK: - Motion

public enum Motion {
    public static let standard = Animation.spring(response: 0.34, dampingFraction: 0.86)
    public static let quick = Animation.spring(response: 0.22, dampingFraction: 0.9)
    /// A touch looser, for onboarding transitions where the motion is the point.
    public static let expressive = Animation.spring(response: 0.5, dampingFraction: 0.78)
    public static let value = Animation.easeOut(duration: 0.22)
    public static let shimmer = Animation.linear(duration: 1.1).repeatForever(autoreverses: false)
}
