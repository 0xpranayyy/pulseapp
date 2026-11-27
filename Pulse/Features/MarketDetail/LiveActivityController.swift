import Foundation
import Observation
import PulseCore
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, updates and ends the market Live Activity.
///
/// Updates are pushed locally from the market screen's WebSocket stream, so
/// the Dynamic Island tracks the same prices the app is showing without a
/// server or push certificate. Two consequences shape the design:
///
/// * The activity only updates while the app is running or briefly after it
///   is backgrounded, so every state carries `updatedAt` and the widget
///   marks itself delayed rather than presenting a frozen price as live.
/// * Updates are throttled. A busy book ticks many times a second, and
///   pushing each one burns battery for pixels nobody can read.
@MainActor
@Observable
final class LiveActivityController {

    private(set) var isTracking = false
    private(set) var lastError: String?

    #if canImport(ActivityKit)
    private var activity: Activity<MarketActivityAttributes>?
    #endif

    private var startProbability: Double?
    private var lastPush: Date = .distantPast
    /// Minimum gap between pushes.
    private let throttle: TimeInterval = 2

    /// Whether the system currently permits Live Activities.
    var isAvailable: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    func start(
        market: Market,
        tokenId: String,
        outcomeLabel: String,
        probability: Double,
        book: OrderBook?
    ) {
        #if canImport(ActivityKit)
        guard isAvailable, activity == nil else { return }
        guard let conditionId = market.conditionId else { return }

        let attributes = MarketActivityAttributes(
            marketId: market.id,
            conditionId: conditionId,
            tokenId: tokenId,
            question: market.question ?? market.displayTitle,
            outcomeLabel: outcomeLabel,
            themeId: Palette.theme(for: market.id).id,
            endDate: market.resolvedEndDate
        )

        startProbability = probability
        let state = MarketActivityAttributes.ContentState(
            probability: probability,
            changeSinceStart: 0,
            bestBid: book?.bestBid,
            bestAsk: book?.bestAsk
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate()),
                pushType: nil
            )
            isTracking = true
            lastError = nil
        } catch {
            // Most often the user has Live Activities switched off, or too
            // many are already running. Neither is worth interrupting them for.
            lastError = error.localizedDescription
            isTracking = false
        }
        #endif
    }

    func update(probability: Double, book: OrderBook?) {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPush) >= throttle else { return }
        lastPush = now

        let state = MarketActivityAttributes.ContentState(
            probability: probability,
            changeSinceStart: probability - (startProbability ?? probability),
            bestBid: book?.bestBid,
            bestAsk: book?.bestAsk,
            updatedAt: now
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: staleDate(from: now)))
        }
        #endif
    }

    func stop() {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let current = activity.content.state
        self.activity = nil
        isTracking = false
        startProbability = nil

        Task {
            // Dismiss immediately: a market the user has navigated away from
            // should not linger on their Lock Screen.
            await activity.end(
                ActivityContent(state: current, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        #endif
    }

    /// After this the system dims the activity, which is the honest signal
    /// that the app is no longer feeding it prices.
    private func staleDate(from now: Date = Date()) -> Date {
        now.addingTimeInterval(5 * 60)
    }
}
