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
    /// Applies glass only where it can actually do something.
    ///
    /// Glass works by refracting what is behind it, so it is worth its cost
    /// only when something interesting is back there — content scrolling
    /// under a floating bar, artwork behind a toolbar. Over a flat colour
    /// field it is visually identical to a translucent fill of the same
    /// value, and side-by-side renders confirm it: the blur has nothing to
    /// blur, so it reads as a slightly lighter flat colour while still
    /// paying for an offscreen pass every frame.
    ///
    /// - Parameter isLayered: true when content passes behind this surface.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(
        _ shape: S,
        isLayered: Bool,
        tint: Color,
        interactive: Bool = false
    ) -> some View {
        if isLayered {
            glass(shape, interactive: interactive)
        } else {
            background(shape.fill(tint.opacity(0.14)))
        }
    }

    /// Floating navigation, toolbars and controls.
    ///
    /// Generic over the shape rather than taking `some Shape`: an opaque
    /// parameter type with a default value makes type inference substantially
    /// more expensive at every call site, and this is called from nearly
    /// every view in the app.
    func glass<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            GlassSurface(shape: AnyShape(shape), tint: tint, isInteractive: interactive)
        )
    }

    /// The common case: a capsule.
    func glass(tint: Color? = nil, interactive: Bool = false) -> some View {
        glass(Capsule(), tint: tint, interactive: interactive)
    }

    /// A grouping panel on the canvas: a white chunky card, or — at low
    /// `strength`, which callers use for panels nested inside a panel — a
    /// flat sunken inset, so nesting never stacks two shadows.
    @ViewBuilder
    func fieldPanel(
        _ theme: Palette.Theme,
        radius: CGFloat = Layout.Radius.card,
        strength: Double = 0.12
    ) -> some View {
        if strength < 0.1 {
            background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Brand.cardSunken))
        } else {
            chunkyCard(radius: radius)
        }
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
            .font(Typography.buttonSmall)
            .foregroundStyle(foreground)
            .padding(.horizontal, Layout.Space.xl)
            .padding(.vertical, Layout.Space.m)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: Layout.Size.minimumTapTarget)
            .modifier(PillBackground(prominence: prominence, tint: tint, pressed: configuration.isPressed))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion && prominence == .secondary ? 0.97 : 1)
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: configuration.isPressed)
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
    let pressed: Bool

    func body(content: Content) -> some View {
        switch prominence {
        case .primary:
            // Chunky: the shadow is the press.
            content
                .background(Capsule().fill(tint))
                .background(Capsule().fill(Color.black.opacity(0.28)).offset(y: pressed ? 0 : Layout.chunkyDepth))
                .offset(y: pressed ? Layout.chunkyDepth : 0)
        case .secondary:
            content.background(Capsule().fill(tint.opacity(0.12)))
        case .glass:
            // On the cream canvas there is nothing behind to refract, so the
            // "floating" style is a white chunky pill.
            content
                .background(Capsule().fill(Brand.card))
                .background(Capsule().fill(Brand.cardShadow).offset(y: pressed ? 0 : 4))
                .offset(y: pressed ? 4 : 0)
        case .quiet:
            content.overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 2))
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
    /// True when content passes behind this button. Defaults to false,
    /// because most of these sit on a flat field where glass buys nothing.
    var isLayered: Bool = false
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(PressableStyle())
            .background(Circle().fill(isOn ? tint : Brand.card))
            .background(Circle().fill(Brand.cardShadow).offset(y: 4))
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : [.isButton])
    }

    private var label: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(isOn ? .white : tint)
            .frame(width: size, height: size)
            .contentShape(Circle())
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
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .background(Circle().fill(Brand.card))
                .background(Circle().fill(Brand.cardShadow).offset(y: 4))
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
                .frame(height: 40)
                .background(Capsule().fill(Brand.card))
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
    var tint: Color = Brand.ink
    var onTint: Color = .white
    /// True when content scrolls behind the chip row.
    var isLayered: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(PressableStyle())
            .background(selectedFill)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var label: some View {
        HStack(spacing: Layout.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title)
                .font(isSelected ? Typography.buttonSmall : Typography.subheadlineMedium)
        }
        .foregroundStyle(isSelected ? onTint : tint)
        .padding(.horizontal, Layout.Space.l)
        .padding(.vertical, Layout.Space.s)
        .frame(minHeight: 38)
        .contentShape(Capsule())
    }

    /// One shape with a computed fill rather than a conditional view, so the
    /// type checker has one background type to unify across every chip.
    private var selectedFill: some View {
        Capsule().fill(isSelected ? tint : Brand.card)
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
            .background(Capsule().fill(Brand.card))
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
                    .foregroundStyle(Brand.inkSecondary)
            }
        }
        .onAppear { pulsing = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLive ? "Prices are live" : "Prices may be out of date")
    }
}
