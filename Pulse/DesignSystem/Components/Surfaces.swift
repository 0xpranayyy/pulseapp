import SwiftUI

// MARK: - Liquid Glass

/// A translucent floating surface.
///
/// On iOS 26 the system bars this app uses — `TabView`, `.toolbar`, and the
/// `.bar` material behind the trade actions — adopt Liquid Glass automatically
/// when built against that SDK, with no code here. This modifier covers the
/// remaining custom floating surfaces and deliberately does **not** call
/// `glassEffect`: that symbol only exists in the iOS 26 SDK, so referencing it
/// would break the build on Xcode 16 even behind an `if #available` check.
///
/// Glass is reserved for *navigation and controls that float over content* —
/// the tab bar, the toolbar pills, the trade sheet's action bar. Content
/// surfaces stay opaque: a glass card over a glass background is noise, and on
/// the pastel fields it muddies the colour the design depends on.
struct GlassBackground: ViewModifier {
    var shape: AnyShape
    /// Tint applied under the glass, usually the market's theme colour.
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint?.opacity(0.18) ?? .clear))
                    .overlay(
                        shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
    }
}

extension View {
    /// Floating navigation and controls.
    func glassSurface(
        shape: some Shape = Capsule(),
        tint: Color? = nil
    ) -> some View {
        modifier(GlassBackground(shape: AnyShape(shape), tint: tint))
    }

    /// An opaque content card.
    func cardSurface(
        radius: CGFloat = Layout.Radius.medium,
        fill: Color = Palette.surface
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
        )
    }
}

// MARK: - Pill buttons

/// The app's primary control shape.
///
/// Pills in a theme's `control` colour, echoing the reference language where
/// every action is a rounded, tinted capsule rather than a bordered rectangle.
struct PillButtonStyle: ButtonStyle {
    enum Prominence {
        /// Solid fill — the single most important action on screen.
        case primary
        /// Tinted fill — secondary actions.
        case secondary
        /// Outline only — tertiary, destructive confirmations.
        case quiet
    }

    var prominence: Prominence = .primary
    var tint: Color = Palette.ink
    var onTint: Color = Palette.canvas
    var fullWidth: Bool = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.headline)
            .foregroundStyle(foreground)
            .padding(.horizontal, Layout.Space.xl)
            .padding(.vertical, Layout.Space.m)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: Layout.Size.minimumTapTarget)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                if prominence == .quiet {
                    Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            // A small, fast press response. Anything slower makes a trading
            // control feel laggy.
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch prominence {
        case .primary: onTint
        case .secondary, .quiet: tint
        }
    }

    @ViewBuilder private var background: some View {
        switch prominence {
        case .primary: Capsule().fill(tint)
        case .secondary: Capsule().fill(tint.opacity(0.14))
        case .quiet: Color.clear
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }

    static func pill(
        _ prominence: PillButtonStyle.Prominence = .primary,
        tint: Color = Palette.ink,
        onTint: Color = Palette.canvas,
        fullWidth: Bool = false
    ) -> PillButtonStyle {
        PillButtonStyle(prominence: prominence, tint: tint, onTint: onTint, fullWidth: fullWidth)
    }
}

/// A circular icon button, as used in the reference toolbars.
struct IconPillButton: View {
    let systemName: String
    var tint: Color = Palette.ink
    var background: Color = Palette.surfaceRaised
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Layout.Size.iconButton, height: Layout.Size.iconButton)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Chips

/// A selectable filter chip. Selected chips invert — dark fill, light text —
/// which is the clearest state signal without adding a checkmark.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    var tint: Color = Palette.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(Typography.subheadlineMedium)
            }
            .foregroundStyle(isSelected ? Palette.canvas : Palette.ink)
            .padding(.horizontal, Layout.Space.l)
            .padding(.vertical, Layout.Space.s)
            .frame(minHeight: 36)
            .background(
                Capsule().fill(isSelected ? tint : Palette.surfaceRaised)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A non-interactive label, e.g. a category tag.
struct TagChip: View {
    let title: String
    var tint: Color = Palette.inkSecondary

    var body: some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, Layout.Space.s)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - Live indicator

/// A small pulsing dot showing whether prices are streaming.
///
/// Shown whenever the socket is not live, because silently displaying frozen
/// prices in a trading app is the failure mode that actually costs people money.
struct LiveIndicator: View {
    let isLive: Bool
    var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: Layout.Space.xs) {
            Circle()
                .fill(isLive ? Palette.up : Palette.caution)
                .frame(width: 6, height: 6)
                .scaleEffect(pulsing && isLive && !reduceMotion ? 1.5 : 1)
                .opacity(pulsing && isLive && !reduceMotion ? 0.4 : 1)
                .animation(
                    reduceMotion || !isLive
                        ? nil
                        : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                    value: pulsing
                )
            if let label {
                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .onAppear { pulsing = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLive ? "Prices are live" : "Prices may be out of date")
    }
}
