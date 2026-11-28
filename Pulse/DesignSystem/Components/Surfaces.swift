import SwiftUI
import PulseCore

// MARK: - Panels

extension View {
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
}

// MARK: - Pills

/// The app's primary control shape.
struct PillButtonStyle: ButtonStyle {
    enum Prominence {
        /// Solid fill — the single most important action on screen.
        case primary
        /// Tinted fill — secondary actions.
        case secondary
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
        case .secondary, .quiet: tint
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

/// A white circular icon button sitting on its hard shadow; navy when on.
struct CircleIconButton: View {
    let systemName: String
    var tint: Color = Palette.ink
    var size: CGFloat = Layout.Size.iconButton
    var isOn: Bool = false
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

// MARK: - Floating top bar

/// A bar that floats over content at the top of a screen, carrying a white
/// chunky back button and a title. Replaces the opaque navigation bar, which
/// would cut a band across a market's coloured header.
struct FloatingTopBar<Trailing: View>: View {
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

extension FloatingTopBar where Trailing == EmptyView {
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
