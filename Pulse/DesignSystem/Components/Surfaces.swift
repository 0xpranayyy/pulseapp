import SwiftUI
import PulseCore

// MARK: - Liquid Glass

/// A translucent floating surface.
///
/// Uses Liquid Glass where the SDK provides it and a material elsewhere. The
/// gate is on the **compiler**, not only on `#available`: `glassEffect` ships
/// in the iOS 26 SDK, and an availability check alone would still fail to
/// compile on Xcode 16 because the symbol would not exist. Xcode 26 ships
/// Swift 6.2, so `compiler(>=6.2)` is the practical proxy for "this SDK has
/// Liquid Glass".
struct GlassSurface: ViewModifier {
    var shape: AnyShape
    /// Tint pulled under the glass, usually the field's own ink.
    var tint: Color?
    /// Interactive glass reacts to touch. Reserved for things you press.
    var isInteractive: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, watchOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(fallback)
        }
        #else
        content.background(fallback)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, watchOS 26.0, *)
    private var glass: Glass {
        var base = Glass.regular
        if let tint { base = base.tint(tint) }
        if isInteractive { base = base.interactive() }
        return base
    }
    #endif

    private var fallback: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(tint?.opacity(0.16) ?? .clear))
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
    }
}

extension View {
    /// Floating navigation, toolbars and controls.
    func glass(
        _ shape: some Shape = Capsule(),
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            GlassSurface(shape: AnyShape(shape), tint: tint, isInteractive: interactive)
        )
    }

    /// A grouping panel on a colour field.
    ///
    /// Tinted with the field's own ink rather than filled white: on a
    /// saturated field a white card reads as a hole punched through it.
    func fieldPanel(
        _ theme: Palette.Theme,
        radius: CGFloat = Layout.Radius.large,
        strength: Double = 0.12
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.onField.opacity(strength))
        )
    }

    /// An opaque card. Used where the references use one: a light card
    /// standing clear of a dark field, never white-on-white.
    func cardSurface(
        radius: CGFloat = Layout.Radius.medium,
        fill: Color = Palette.surface
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
        )
    }
}

// MARK: - Pills

/// The app's primary control shape.
struct PillButtonStyle: ButtonStyle {
    enum Prominence {
        /// Solid fill — the single most important action on screen.
        case primary
        /// Tinted fill — secondary actions.
        case secondary
        /// Glass — floating over content.
        case glass
        /// Outline only.
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
            .modifier(PillBackground(prominence: prominence, tint: tint))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch prominence {
        case .primary: onTint
        case .secondary, .quiet, .glass: tint
        }
    }
}

private struct PillBackground: ViewModifier {
    let prominence: PillButtonStyle.Prominence
    let tint: Color

    func body(content: Content) -> some View {
        switch prominence {
        case .primary:
            content.background(Capsule().fill(tint)).clipShape(Capsule())
        case .secondary:
            content.background(Capsule().fill(tint.opacity(0.16))).clipShape(Capsule())
        case .glass:
            content.glass(Capsule(), interactive: true)
        case .quiet:
            content.overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1.5))
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

/// A circular glass icon button — the row of controls the references put
/// under a piece of artwork.
struct GlassIconButton: View {
    let systemName: String
    var tint: Color = Palette.ink
    var size: CGFloat = Layout.Size.iconButton
    var isOn: Bool = false
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(isOn ? Palette.ink : tint)
                .frame(width: size, height: size)
                .background {
                    if isOn {
                        Circle().fill(tint)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .glass(Circle(), interactive: true)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : [.isButton])
    }
}

/// A row of glass icon buttons, as seen under the artwork in the references.
struct GlassControlRow<Content: View>: View {
    var tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: Layout.Space.s) {
            content()
        }
    }
}

// MARK: - Floating top bar

/// A glass pill that floats over content at the top of a screen, carrying a
/// back affordance and a title. Replaces the opaque navigation bar, which
/// would cut a band across the colour field.
struct GlassTopBar<Trailing: View>: View {
    let title: String?
    var subtitle: String?
    var tint: Color
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Layout.Space.s) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .glass(Circle(), interactive: true)
                .accessibilityLabel("Back")
            }

            if let title {
                VStack(spacing: 0) {
                    Text(title)
                        .font(Typography.captionMedium)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(tint.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Layout.Space.l)
                .frame(height: 38)
                .glass(Capsule())
            }

            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, Layout.gutter)
    }
}

extension GlassTopBar where Trailing == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        tint: Color,
        onBack: (() -> Void)? = nil
    ) {
        self.init(title: title, subtitle: subtitle, tint: tint, onBack: onBack) { EmptyView() }
    }
}

// MARK: - Chips

/// A selectable filter chip. Selected chips invert — the clearest state
/// signal without adding a checkmark.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    var tint: Color = Palette.ink
    var onTint: Color = Palette.canvas
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
                }
                Text(title).font(Typography.subheadlineMedium)
            }
            .foregroundStyle(isSelected ? onTint : tint)
            .padding(.horizontal, Layout.Space.l)
            .padding(.vertical, Layout.Space.s)
            .frame(minHeight: 38)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .background {
            if isSelected {
                Capsule().fill(tint)
            }
        }
        .glass(Capsule(), interactive: !isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A non-interactive label.
struct TagChip: View {
    let title: String
    var tint: Color = Palette.inkSecondary

    var body: some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, Layout.Space.m)
            .padding(.vertical, 5)
            .glass(Capsule())
    }
}

// MARK: - Live indicator

/// A small pulsing dot showing whether prices are streaming.
///
/// Shown whenever the socket is not live, because silently displaying frozen
/// prices in a trading app is the failure mode that costs people money.
struct LiveIndicator: View {
    let isLive: Bool
    var label: String?
    var ink: Color = Palette.ink

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: Layout.Space.xs) {
            Circle()
                .fill(ink)
                .frame(width: 6, height: 6)
                .opacity(isLive ? (pulsing && !reduceMotion ? 0.35 : 1) : 0.4)
                .animation(
                    reduceMotion || !isLive
                        ? nil
                        : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                    value: pulsing
                )
            if let label {
                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(ink.opacity(0.7))
            }
        }
        .onAppear { pulsing = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLive ? "Prices are live" : "Prices may be out of date")
    }
}
