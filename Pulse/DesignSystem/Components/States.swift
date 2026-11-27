import SwiftUI
import PulseCore

// MARK: - Loading

/// A shimmering placeholder block, tinted to the field it sits on.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = Layout.Radius.small
    var ink: Color = Palette.ink

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ink.opacity(0.08))
            .frame(width: width, height: height)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.clear, ink.opacity(0.07), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: phase * geometry.size.width * 1.6)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.shimmer) { phase = 1 }
            }
            .accessibilityHidden(true)
    }
}

/// Placeholder shaped like `EventRow`, so the layout does not jump when real
/// data lands.
struct EventRowSkeleton: View {
    var theme: Palette.Theme = Palette.themes[0]

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(alignment: .top, spacing: Layout.Space.m) {
                SkeletonBlock(
                    width: Layout.Size.rowArt,
                    height: Layout.Size.rowArt,
                    ink: theme.onField
                )
                VStack(alignment: .leading, spacing: Layout.Space.s) {
                    SkeletonBlock(height: 16, ink: theme.onField)
                    SkeletonBlock(width: 160, height: 16, ink: theme.onField)
                    SkeletonBlock(width: 110, height: 11, ink: theme.onField)
                }
                Spacer()
            }
            HStack(spacing: Layout.Space.s) {
                SkeletonBlock(height: 44, cornerRadius: Layout.Radius.pill, ink: theme.onField)
                SkeletonBlock(height: 44, cornerRadius: Layout.Radius.pill, ink: theme.onField)
            }
        }
        .padding(Layout.Space.l)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous)
                .fill(theme.field)
        )
    }
}

// MARK: - Empty and error states

/// A state view for "nothing here", "that failed" and "nothing matched".
///
/// Every state offers an action or a reason. A dead end with no way forward
/// is a bug, not a design.
struct StateView: View {
    let icon: String
    let title: String
    let message: String
    var ink: Color = Palette.ink
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Layout.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ink.opacity(0.45))
                .padding(.bottom, Layout.Space.xs)

            Text(title)
                .font(Typography.title2)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Typography.callout)
                .foregroundStyle(ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.pill(.secondary, tint: ink))
                    .padding(.top, Layout.Space.s)
            }
        }
        .frame(maxWidth: 330)
        .padding(Layout.Space.xl)
        .frame(maxWidth: .infinity)
    }
}

extension StateView {
    static func error(
        _ message: String,
        ink: Color = Palette.ink,
        retry: @escaping () -> Void
    ) -> StateView {
        StateView(
            icon: "exclamationmark.triangle",
            title: "Something went wrong",
            message: message,
            ink: ink,
            actionTitle: "Try again",
            action: retry
        )
    }

    static func noResults(query: String, ink: Color = Palette.ink) -> StateView {
        StateView(
            icon: "magnifyingglass",
            title: "No markets found",
            message: "Nothing matched \"\(query)\". Try a shorter or more general search.",
            ink: ink
        )
    }
}

// MARK: - Stat tiles

/// A labelled figure.
struct StatTile: View {
    let label: String
    let value: String
    var caption: String?
    var ink: Color = Palette.ink
    var tint: Color?
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.8)
                .foregroundStyle(ink.opacity(0.5))
                .lineLimit(1)

            Text(value)
                .font(Typography.currency)
                .foregroundStyle(tint ?? ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let caption {
                Text(caption)
                    .font(Typography.caption)
                    .foregroundStyle(ink.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// A section heading with an optional trailing action.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var ink: Color = Palette.ink
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(ink.opacity(0.6))
                }
            }
            Spacer()
            trailing()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, ink: Color = Palette.ink) {
        self.init(title: title, subtitle: subtitle, ink: ink) { EmptyView() }
    }
}

// MARK: - Risk disclosure

/// A plain statement of what a prediction market is.
///
/// Shown before the first trade and in Settings. Deliberately unglamorous and
/// never paired with projected returns: this is the one place in the app that
/// must not persuade.
struct RiskNotice: View {
    var compact: Bool = false
    var ink: Color = Palette.ink

    var body: some View {
        HStack(alignment: .top, spacing: Layout.Space.s) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ink.opacity(0.55))
            Text(compact ? Self.shortText : Self.fullText)
                .font(Typography.caption)
                .foregroundStyle(ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                .fill(ink.opacity(0.06))
        )
    }

    static let shortText =
        "Prediction markets carry risk. Positions can lose their full value."

    static let fullText = """
        Prediction markets carry risk. A position can lose its entire value, \
        and prices are set by other traders rather than by any forecast. \
        Nothing here is financial advice, and availability depends on your \
        jurisdiction and account eligibility.
        """
}
