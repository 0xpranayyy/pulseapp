import SwiftUI
import WidgetKit
import ActivityKit
import PulseCore

/// Live Activity for a tracked market.
///
/// Four presentations, each sized very differently, so each is laid out for
/// its own constraints rather than scaled from one design:
///
/// * **Lock Screen / banner** — the market's category colour, the question,
///   the big number and the tug.
/// * **Expanded island** — the same information on black, shorter.
/// * **Compact** — about four glyphs either side of the camera.
/// * **Minimal** — one glyph, shared with other activities.
///
/// The app's fonts are not bundled in the extension, so type is the system's
/// rounded face, which sits closest to Nunito. Colours come from `Brand`, so
/// green and red still mean only Yes and No and the lime dot still means
/// live.
struct PulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MarketActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Brand.panel(context.attributes.category))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            let category = context.attributes.category
            let yes = context.attributes.yesProbability(context.state)
            let stale = context.state.isStale()

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        LiveDot(isLive: !stale)
                        Text(context.attributes.outcomeLabel.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if let change = ActivityFormat.change(context.state.changeSinceStart) {
                            Text(change)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    context.state.changeSinceStart >= 0 ? Brand.yesTint : Brand.noTint
                                )
                        }
                        Text(Format.probability(context.state.probability))
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 6) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Brand.fill(category))
                        Text(ActivityFormat.shortQuestion(context.attributes.question, limit: 54))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ActivityTug(yesProbability: yes, height: 8, knot: 14)
                        .padding(.top, 4)
                        .padding(.horizontal, 4)

                    if stale {
                        Text("Price may be out of date")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 3)
                    }
                }

            } compactLeading: {
                // Roughly four glyphs. A percent sign costs one of them for
                // no information, so it is dropped here.
                HStack(spacing: 4) {
                    LiveDot(isLive: !stale, size: 6)
                    Text(ActivityFormat.compactProbability(context.state.probability))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

            } compactTrailing: {
                ProbabilityDial(probability: context.state.probability, ink: Brand.fill(category))
                    .frame(width: 18, height: 18)

            } minimal: {
                ProbabilityDial(probability: context.state.probability, ink: Brand.fill(category))
                    .frame(width: 18, height: 18)
            }
            .keylineTint(Brand.fill(category))
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<MarketActivityAttributes>

    private var category: MarketCategory { context.attributes.category }
    private var stale: Bool { context.state.isStale() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 10, weight: .bold))
                        Text("\(category.title.uppercased()) · \(context.attributes.outcomeLabel.uppercased())")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)

                    Text(ActivityFormat.shortQuestion(context.attributes.question, limit: 64))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Format.probability(context.state.probability))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    if let change = ActivityFormat.change(context.state.changeSinceStart) {
                        // On a white chip so green and red keep their
                        // contrast against the category colour.
                        Text("\(context.state.changeSinceStart >= 0 ? "▲" : "▼") \(change.dropFirst()) pts")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(context.state.changeSinceStart >= 0 ? Brand.yes : Brand.no)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.white))
                    }
                }
            }

            ActivityTug(yesProbability: context.attributes.yesProbability(context.state), height: 10, knot: 18)

            HStack(spacing: 10) {
                LiveDot(isLive: !stale)
                if let bid = context.state.bestBid, let ask = context.state.bestAsk {
                    Text("Bid \(Format.cents(bid))")
                    Text("Ask \(Format.cents(ask))")
                }
                Spacer()
                if stale {
                    Label("Delayed", systemImage: "clock")
                } else if let end = context.attributes.endDate {
                    Text(Format.timeRemaining(until: end))
                }
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
        }
        .padding(14)
    }
}

// MARK: - Shared marks

/// The tug, static: green for Yes on the left, red for No, the lime knot at
/// the Yes price. Widgets cannot animate continuously, so no braid drift.
private struct ActivityTug: View {
    let yesProbability: Double
    var height: CGFloat
    var knot: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let p = min(1, max(0, yesProbability))
            let split = geometry.size.width * p
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Brand.yes.frame(width: split)
                    Brand.no
                }
                .frame(height: height)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).padding(-1.5))

                Circle()
                    .fill(Brand.lime)
                    .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 2.5))
                    .frame(width: knot, height: knot)
                    .offset(x: min(max(0, split - knot / 2), geometry.size.width - knot))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: knot)
        .accessibilityElement()
        .accessibilityLabel("Odds")
        .accessibilityValue("Yes \(Int((yesProbability * 100).rounded())) cents")
    }
}

/// Lime when the price is current, grey when it has gone stale — the same
/// rule as the app's LIVE badge.
private struct LiveDot: View {
    let isLive: Bool
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(isLive ? Brand.lime : Color.white.opacity(0.4))
            .frame(width: size, height: size)
            .accessibilityLabel(isLive ? "Live" : "Delayed")
    }
}

/// A ring filled to the probability — legible at 18pt, where a number is not.
private struct ProbabilityDial: View {
    let probability: Double
    let ink: Color

    var body: some View {
        ZStack {
            Circle().stroke(ink.opacity(0.3), lineWidth: 3)
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
