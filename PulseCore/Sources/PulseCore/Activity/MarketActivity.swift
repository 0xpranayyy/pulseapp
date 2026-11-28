import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// The payload behind a market Live Activity.
///
/// Declared in the shared core because the app starts and updates the
/// activity while the widget extension renders it, and both must agree on the
/// exact shape. Guarded by `canImport` so the core still builds on platforms
/// without ActivityKit, which is how its tests run.
#if canImport(ActivityKit)
public struct MarketActivityAttributes: ActivityAttributes, Sendable {

    /// The part that changes while the activity is live.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Probability of the tracked outcome, 0...1.
        public let probability: Double
        /// Change since the activity started, in probability points.
        public let changeSinceStart: Double
        /// Best bid and ask, when a book is available.
        public let bestBid: Double?
        public let bestAsk: Double?
        /// When this value was produced, so the UI can mark it stale.
        public let updatedAt: Date

        public init(
            probability: Double,
            changeSinceStart: Double,
            bestBid: Double? = nil,
            bestAsk: Double? = nil,
            updatedAt: Date = Date()
        ) {
            self.probability = probability
            self.changeSinceStart = changeSinceStart
            self.bestBid = bestBid
            self.bestAsk = bestAsk
            self.updatedAt = updatedAt
        }

        /// Live Activities keep displaying their last state after updates
        /// stop, so anything older than a few minutes is called out rather
        /// than shown as current.
        public func isStale(now: Date = Date(), tolerance: TimeInterval = 300) -> Bool {
            now.timeIntervalSince(updatedAt) > tolerance
        }
    }

    /// Fixed for the life of the activity.
    public let marketId: String
    public let conditionId: String
    public let tokenId: String
    public let question: String
    public let outcomeLabel: String
    public let endDate: Date?
    /// The market's category, by raw value. Optional so activities started
    /// by an earlier build, which did not carry it, still decode.
    public let categoryRaw: String?
    /// Whether the tracked outcome is the market's first ("Yes") outcome.
    /// Optional for the same reason; nil reads as Yes.
    public let tracksYes: Bool?

    public init(
        marketId: String,
        conditionId: String,
        tokenId: String,
        question: String,
        outcomeLabel: String,
        endDate: Date?,
        category: MarketCategory = .other,
        tracksYes: Bool = true
    ) {
        self.marketId = marketId
        self.conditionId = conditionId
        self.tokenId = tokenId
        self.question = question
        self.outcomeLabel = outcomeLabel
        self.endDate = endDate
        self.categoryRaw = category.rawValue
        self.tracksYes = tracksYes
    }

    public var category: MarketCategory {
        categoryRaw.flatMap(MarketCategory.init(rawValue:)) ?? .other
    }

    /// The Yes probability for a state, whichever side is tracked — the tug
    /// always puts Yes on the left.
    public func yesProbability(_ state: ContentState) -> Double {
        tracksYes == false ? 1 - state.probability : state.probability
    }
}
#endif

/// Formatting shared by the app, the widget and the watch.
///
/// Kept out of the ActivityKit guard so every target can use it, and so the
/// strings the Dynamic Island shows are covered by the core's tests.
public enum ActivityFormat {

    /// The compact leading/trailing slots are tiny — roughly four glyphs —
    /// so the probability is rendered without a decimal and without a
    /// percent sign when it would not fit.
    public static func compactProbability(_ probability: Double) -> String {
        let percent = (probability * 100).rounded()
        if percent >= 100 { return "99+" }
        if percent <= 0 { return "<1" }
        return String(Int(percent))
    }

    /// Change in probability points, with an explicit sign.
    public static func change(_ points: Double) -> String? {
        let scaled = points * 100
        guard abs(scaled) >= 0.5 else { return nil }
        return (scaled > 0 ? "+" : "−") + String(Int(abs(scaled).rounded()))
    }

    /// A short title that survives truncation in a Lock Screen banner.
    public static func shortQuestion(_ question: String, limit: Int = 48) -> String {
        guard question.count > limit else { return question }
        let cut = question.prefix(limit)
        // Break on a word boundary rather than mid-word.
        if let space = cut.lastIndex(of: " ") {
            return String(cut[cut.startIndex..<space]) + "…"
        }
        return String(cut) + "…"
    }
}
