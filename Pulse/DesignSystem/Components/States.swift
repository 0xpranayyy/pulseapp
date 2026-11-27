import SwiftUI

// MARK: - Loading

/// A shimmering placeholder block.
///
/// Skeletons mirror the shape of the content they replace, so the layout does
/// not jump when real data lands. The shimmer stops entirely under Reduce
/// Motion.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = Layout.Radius.small

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Palette.surfaceRaised)
            .frame(width: width, height: height)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.clear, Palette.ink.opacity(0.06), .clear],
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

/// Placeholder matching `EventRow`'s shape.
struct EventRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(spacing: Layout.Space.m) {
                SkeletonBlock(
                    width: Layout.Size.marketThumbnail,
                    height: Layout.Size.marketThumbnail
                )
                VStack(alignment: .leading, spacing: Layout.Space.s) {
                    SkeletonBlock(height: 14)
                    SkeletonBlock(width: 140, height: 11)
                }
                Spacer()
                SkeletonBlock(width: 48, height: 24)
            }
            HStack(spacing: Layout.Space.s) {
                SkeletonBlock(height: 40, cornerRadius: Layout.Radius.pill)
                SkeletonBlock(height: 40, cornerRadius: Layout.Radius.pill)
            }
        }
        .padding(Layout.Space.l)
        .cardSurface(radius: Layout.Radius.large)
    }
}

// MARK: - Empty and error states

/// A state view for "nothing here", "that failed" and "nothing matched".
///
/// Every state offers either an action or a clear reason. A dead end with no
/// way forward is a bug, not a design.
struct StateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Layout.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.inkTertiary)
                .padding(.bottom, Layout.Space.xs)

            Text(title)
                .font(Typography.title3)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Typography.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.pill(.secondary))
                    .padding(.top, Layout.Space.s)
            }
        }
        .frame(maxWidth: 320)
        .padding(Layout.Space.xl)
        .frame(maxWidth: .infinity)
    }
}

extension StateView {
    static func error(_ message: String, retry: @escaping () -> Void) -> StateView {
        StateView(
            icon: "exclamationmark.triangle",
            title: "Something went wrong",
            message: message,
            actionTitle: "Try again",
            action: retry
        )
    }

    static func offline(retry: @escaping () -> Void) -> StateView {
        StateView(
            icon: "wifi.slash",
            title: "You're offline",
            message: "Prices need a connection. Reconnect and pull to refresh.",
            actionTitle: "Try again",
            action: retry
        )
    }

    static func noResults(query: String) -> StateView {
        StateView(
            icon: "magnifyingglass",
            title: "No markets found",
            message: "Nothing matched \"\(query)\". Try a shorter or more general search."
        )
    }
}

// MARK: - Stat tiles

/// A labelled figure. Used in the portfolio header and market statistics.
struct StatTile: View {
    let label: String
    let value: String
    var caption: String?
    var tint: Color = Palette.ink
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.6)
                .foregroundStyle(Palette.inkTertiary)

            Text(value)
                .font(Typography.currency)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let caption {
                Text(caption)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
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
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
            trailing()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
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

    var body: some View {
        HStack(alignment: .top, spacing: Layout.Space.s) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            Text(compact ? Self.shortText : Self.fullText)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                .fill(Palette.surfaceRaised)
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
