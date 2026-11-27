import SwiftUI

/// Type scale.
///
/// Every style is built from `Font.system(_:design:weight:)` with a text
/// style, so all of it scales with Dynamic Type. Nothing is a fixed point
/// size. Numbers that sit in columns or change in place use monospaced
/// digits, which stops prices and countdowns from jittering as they update.
public enum Typography {

    // MARK: Display — screen headlines

    /// Large screen titles. Rounded, because the pastel fields are soft and a
    /// grotesque title fights them.
    public static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let title = Font.system(.title, design: .rounded, weight: .bold)
    public static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)
    public static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)

    // MARK: Body

    public static let headline = Font.system(.headline, weight: .semibold)
    public static let body = Font.system(.body)
    public static let bodyMedium = Font.system(.body, weight: .medium)
    public static let callout = Font.system(.callout)
    public static let subheadline = Font.system(.subheadline)
    public static let subheadlineMedium = Font.system(.subheadline, weight: .medium)
    public static let footnote = Font.system(.footnote)
    public static let caption = Font.system(.caption)
    public static let captionMedium = Font.system(.caption, weight: .medium)

    /// Small all-caps section labels. Pair with `.tracking(0.6)`.
    public static let overline = Font.system(.caption2, weight: .semibold)

    // MARK: Numerals
    //
    // Monospaced digits everywhere a figure updates live or aligns in a
    // column, so the layout does not shift as digits change width.

    /// The headline probability on a market detail screen.
    public static let probabilityLarge = Font.system(
        .largeTitle, design: .rounded, weight: .bold
    ).monospacedDigit()

    /// Probability in a feed row.
    public static let probability = Font.system(
        .title3, design: .rounded, weight: .bold
    ).monospacedDigit()

    /// Portfolio total.
    public static let currencyLarge = Font.system(
        .largeTitle, design: .rounded, weight: .bold
    ).monospacedDigit()

    public static let currency = Font.system(
        .headline, design: .rounded, weight: .semibold
    ).monospacedDigit()

    /// Order-book rows and other dense tabular figures.
    public static let tabular = Font.system(
        .footnote, design: .monospaced, weight: .regular
    ).monospacedDigit()

    public static let tabularMedium = Font.system(
        .footnote, design: .monospaced, weight: .medium
    ).monospacedDigit()
}

// MARK: - Layout constants

/// Spacing, radii and sizes.
///
/// A small, fixed set — four spacing steps and three radii cover the whole app.
/// Anything that needs a value outside this list is usually a sign the layout
/// is wrong rather than that the scale is incomplete.
public enum Layout {

    public enum Space {
        /// 4 — between tightly related items, like a value and its unit.
        public static let xs: CGFloat = 4
        /// 8 — within a component.
        public static let s: CGFloat = 8
        /// 12 — between components in a group.
        public static let m: CGFloat = 12
        /// 16 — the standard screen gutter and between groups.
        public static let l: CGFloat = 16
        /// 24 — between sections.
        public static let xl: CGFloat = 24
        /// 32 — around a section that needs to breathe.
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        /// 10 — chips, small controls.
        public static let small: CGFloat = 10
        /// 16 — cards, rows.
        public static let medium: CGFloat = 16
        /// 24 — sheets, large cards, hero art.
        public static let large: CGFloat = 24
        /// Fully rounded. Pills are the app's signature control shape.
        public static let pill: CGFloat = 999
    }

    public enum Size {
        /// Apple's minimum comfortable hit target.
        public static let minimumTapTarget: CGFloat = 44
        public static let iconButton: CGFloat = 44
        public static let marketThumbnail: CGFloat = 48
        public static let heroArt: CGFloat = 220
        /// Height reserved for the floating tab bar so content can clear it.
        public static let tabBarClearance: CGFloat = 92
    }

    /// Standard screen gutter.
    public static let gutter: CGFloat = Space.l
}

// MARK: - Motion

/// Animation curves.
///
/// Financial UI should feel responsive, not animated: a price updating is
/// information, and a long spring on it delays reading the number. Durations
/// are short, and anything carrying data respects Reduce Motion.
public enum Motion {
    /// Standard transition for layout and presentation.
    public static let standard = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Quick feedback on a tap.
    public static let quick = Animation.spring(response: 0.22, dampingFraction: 0.9)
    /// Value changes — a number ticking, a bar resizing.
    public static let value = Animation.easeOut(duration: 0.22)
    /// Looping shimmer for loading placeholders.
    public static let shimmer = Animation.linear(duration: 1.1).repeatForever(autoreverses: false)
}
