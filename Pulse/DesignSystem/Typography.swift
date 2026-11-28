import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The app's two typefaces.
///
/// * **Fredoka** — display: titles, the big probability, the wordmark.
///   Round and friendly, which is most of the brand's voice.
/// * **Nunito** — UI: buttons, body, labels and every number that moves.
///
/// Both are OFL Google Fonts, bundled as static instances cut from the
/// upstream variable fonts by `Supporting/fonts/build_fonts.sh`.
///
/// Neither face has a `tnum` feature, so there is no descriptor trick here.
/// Nunito's digits are already fixed-width (all 600 units, checked in the
/// font build); Fredoka's are proportional. That decides the split: anything
/// that ticks in place or sits in a column — feed prices, the order book,
/// money — is Nunito, so it never jitters. Fredoka only gets numbers that
/// are hero-sized and change rarely, and those animate with
/// `.contentTransition(.numericText())` rather than jumping.
///
/// Every style goes through `relativeTo:` so Dynamic Type still scales.
public enum BrandFont {
    public enum Display: String {
        case medium = "Fredoka-Medium"
        case semibold = "Fredoka-SemiBold"
        case bold = "Fredoka-Bold"
    }

    public enum UI: String {
        case bold = "Nunito-Bold"
        case extrabold = "Nunito-ExtraBold"
        case black = "Nunito-Black"
    }

    public static func display(
        _ weight: Display,
        size: CGFloat,
        relativeTo style: Font.TextStyle = .title
    ) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    public static func ui(
        _ weight: UI,
        size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// True when both families registered. A missing font falls back to San
    /// Francisco silently, so this backs a debug assertion at launch.
    public static var isAvailable: Bool {
        #if canImport(UIKit)
        return UIFont(name: Display.semibold.rawValue, size: 12) != nil
            && UIFont(name: UI.extrabold.rawValue, size: 12) != nil
        #else
        return false
        #endif
    }
}

/// The type scale.
///
/// Token names are unchanged from the Allo era so call sites carry over;
/// only what each token points at moved.
public enum Typography {

    // MARK: Display — Fredoka

    public static let hero = BrandFont.display(.semibold, size: 40, relativeTo: .largeTitle)
    public static let display = BrandFont.display(.semibold, size: 34, relativeTo: .largeTitle)
    public static let title = BrandFont.display(.semibold, size: 28, relativeTo: .title)
    public static let title2 = BrandFont.display(.semibold, size: 22, relativeTo: .title2)

    // MARK: UI — Nunito

    /// Card and row titles. Nunito rather than Fredoka: at 17pt in a dense
    /// list the display face gets cartoonish.
    public static let title3 = BrandFont.ui(.extrabold, size: 17, relativeTo: .title3)
    public static let headline = BrandFont.ui(.extrabold, size: 16, relativeTo: .headline)
    public static let body = BrandFont.ui(.bold, size: 16, relativeTo: .body)
    public static let bodyMedium = BrandFont.ui(.extrabold, size: 16, relativeTo: .body)
    public static let callout = BrandFont.ui(.bold, size: 15, relativeTo: .callout)
    public static let subheadline = BrandFont.ui(.bold, size: 14, relativeTo: .subheadline)
    public static let subheadlineMedium = BrandFont.ui(.extrabold, size: 14, relativeTo: .subheadline)
    public static let footnote = BrandFont.ui(.bold, size: 13, relativeTo: .footnote)
    public static let caption = BrandFont.ui(.bold, size: 12, relativeTo: .caption)
    public static let captionMedium = BrandFont.ui(.extrabold, size: 12, relativeTo: .caption)

    /// Small all-caps labels. Pair with `.tracking(0.8)`.
    public static let overline = BrandFont.ui(.black, size: 11, relativeTo: .caption2)

    /// Chunky buttons.
    public static let button = BrandFont.ui(.black, size: 18, relativeTo: .headline)
    public static let buttonSmall = BrandFont.ui(.black, size: 15, relativeTo: .subheadline)

    // MARK: Numerals

    /// The probability on a market screen. Fredoka, animated on change.
    public static let probabilityHero = BrandFont.display(.bold, size: 60, relativeTo: .largeTitle)
    public static let probabilityLarge = BrandFont.display(.bold, size: 40, relativeTo: .largeTitle)
    /// Probability in a feed row — ticks live, so Nunito (fixed-width digits).
    public static let probability = BrandFont.ui(.black, size: 22, relativeTo: .title2)
    public static let probabilitySmall = BrandFont.ui(.black, size: 15, relativeTo: .subheadline)

    public static let currencyLarge = BrandFont.display(.bold, size: 48, relativeTo: .largeTitle)
    public static let currency = BrandFont.ui(.black, size: 17, relativeTo: .headline)
    public static let currencySmall = BrandFont.ui(.extrabold, size: 13, relativeTo: .footnote)

    /// Order-book rows and other dense columns.
    public static let tabular = BrandFont.ui(.bold, size: 13, relativeTo: .footnote)
    public static let tabularMedium = BrandFont.ui(.extrabold, size: 13, relativeTo: .footnote)
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
        /// Chunky cards.
        public static let card: CGFloat = 24
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
        public static let tabBarClearance: CGFloat = 128
    }

    public static let gutter: CGFloat = 20

    /// The hard, unblurred drop under chunky cards and buttons. Pressing a
    /// button moves it down by this much and the shadow disappears, which is
    /// the whole press feedback.
    public static let chunkyDepth: CGFloat = 5
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
