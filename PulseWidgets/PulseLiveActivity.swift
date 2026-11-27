import SwiftUI
import WidgetKit
import ActivityKit
import PulseCore

/// Live Activity for a tracked market.
///
/// Four presentations, each sized very differently, so each is laid out for
/// its own constraints rather than scaled from one design:
///
/// * **Lock Screen / banner** — room for the question and a book.
/// * **Expanded island** — the same information, shorter.
/// * **Compact** — about four glyphs either side of the camera.
/// * **Minimal** — one glyph, shared with other activities.
struct PulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MarketActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(theme(context).screen)
                .activitySystemActionForegroundColor(theme(context).onField)

        } dynamicIsland: { context in
            let palette = theme(context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.outcomeLabel.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.onField.opacity(0.6))
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        if let change = ActivityFormat.change(context.state.changeSinceStart) {
                            Text(change)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    context.state.changeSinceStart >= 0
                                        ? Color.green : Color.pink
                                )
                        }
                        Text(Format.probability(context.state.probability))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(palette.onField)
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(ActivityFormat.shortQuestion(context.attributes.question, limit: 54))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.onField)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ProbabilityRail(
                        probability: context.state.probability,
                        ink: palette.onField
                    )
                    .frame(height: 6)
                    .padding(.top, 2)

                    if context.state.isStale() {
                        Text("Price may be out of date")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.onField.opacity(0.5))
                            .padding(.top, 3)
                    }
                }

            } compactLeading: {
                // Roughly four glyphs. A percent sign costs one of them for
                // no information, so it is dropped here.
                Text(ActivityFormat.compactProbability(context.state.probability))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.onField)

            } compactTrailing: {
                ProbabilityDial(
                    probability: context.state.probability,
                    ink: palette.onField
                )
                .frame(width: 18, height: 18)

            } minimal: {
                ProbabilityDial(
                    probability: context.state.probability,
                    ink: palette.onField
                )
                .frame(width: 18, height: 18)
            }
            .keylineTint(palette.onField)
        }
    }

    private func theme(
        _ context: ActivityViewContext<MarketActivityAttributes>
    ) -> Palette.Theme {
        Palette.theme(named: context.attributes.themeId)
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<MarketActivityAttributes>

    private var theme: Palette.Theme { Palette.theme(named: context.attributes.themeId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.outcomeLabel.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.onField.opacity(0.55))

                    Text(ActivityFormat.shortQuestion(context.attributes.question, limit: 64))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.onField)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.probability(context.state.probability))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.onField)

                    if let change = ActivityFormat.change(context.state.changeSinceStart) {
                        Text("\(change) pts")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.onField.opacity(0.65))
                    }
                }
            }

            ProbabilityRail(probability: context.state.probability, ink: theme.onField)
                .frame(height: 7)

            HStack(spacing: 10) {
                if let bid = context.state.bestBid, let ask = context.state.bestAsk {
                    Text("Bid \(Format.cents(bid))")
                    Text("Ask \(Format.cents(ask))")
                }
                Spacer()
                if context.state.isStale() {
                    Label("Delayed", systemImage: "clock")
                } else if let end = context.attributes.endDate {
                    Text(Format.timeRemaining(until: end))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.onField.opacity(0.6))
        }
        .padding(14)
    }
}

// MARK: - Shared marks

/// A thin Yes/No split rail.
private struct ProbabilityRail: View {
    let probability: Double
    let ink: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.18))
                Capsule()
                    .fill(ink)
                    .frame(width: max(3, geometry.size.width * min(1, max(0, probability))))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A ring filled to the probability — legible at 18pt, where a number is not.
private struct ProbabilityDial: View {
    let probability: Double
    let ink: Color

    var body: some View {
        ZStack {
            Circle().stroke(ink.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0.02, probability)))
                .stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityLabel("\(Int((probability * 100).rounded())) percent")
    }
}

// MARK: - Bundle

@main
struct PulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PulseLiveActivity()
    }
}
