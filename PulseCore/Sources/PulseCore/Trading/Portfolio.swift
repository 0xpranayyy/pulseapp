import Foundation

/// Aggregate view of a wallet's holdings.
///
/// Deliberately a pure summation of API-reported figures. The Data API already
/// accounts for fees, partial exits and realised legs; recomputing P&L from
/// `avgPrice × size` locally would disagree with Polymarket's own numbers and
/// mislead the user about money. Anything this type *derives* is clearly a
/// derived quantity (counts, exposure, allocation shares).
public struct Portfolio: Sendable, Hashable {
    public let positions: [Position]
    /// Cash value of all positions, as reported by `/v2/value`. When that call
    /// fails this falls back to the sum of position values, which is the same
    /// figure computed a different way.
    public let reportedValue: Double?
    /// Spendable USDC balance. `nil` when unknown — the UI must then say
    /// "unavailable" rather than show zero.
    public let availableBalance: Double?

    /// Positions ordered by current value, largest first — the order the
    /// portfolio list renders. Sorted once here rather than on every read:
    /// the list reads it from a view body, so a computed property would
    /// re-sort on every frame of a scroll.
    public let byValue: [Position]

    public init(
        positions: [Position],
        reportedValue: Double? = nil,
        availableBalance: Double? = nil
    ) {
        self.positions = positions
        self.reportedValue = reportedValue
        self.availableBalance = availableBalance
        self.byValue = positions.sorted { $0.currentValue > $1.currentValue }
    }

    public static let empty = Portfolio(positions: [])

    // MARK: Totals

    /// Current market value of open positions.
    public var positionsValue: Double {
        positions.reduce(0) { $0 + $1.currentValue }
    }

    /// Prefers the API's own figure; falls back to the local sum.
    public var totalValue: Double { reportedValue ?? positionsValue }

    /// Positions value plus spendable cash, when cash is known.
    public var netWorth: Double? {
        guard let availableBalance else { return nil }
        return totalValue + availableBalance
    }

    public var totalCost: Double {
        positions.reduce(0) { $0 + $1.totalCostUsdc }
    }

    public var unrealizedPnl: Double {
        positions.reduce(0) { $0 + $1.unrealizedPnl }
    }

    public var realizedPnl: Double {
        positions.reduce(0) { $0 + $1.realizedPnl }
    }

    public var totalPnl: Double {
        positions.reduce(0) { $0 + $1.totalPnl }
    }

    /// Return on cost. `nil` when nothing has been invested, so the UI shows
    /// a dash instead of a meaningless 0%.
    public var totalReturn: Double? {
        let cost = totalCost
        guard cost > 0 else { return nil }
        return totalPnl / cost
    }

    /// Return on currently open positions only.
    public var unrealizedReturn: Double? {
        let cost = positions.reduce(0) { $0 + $1.totalCostUsdc }
        guard cost > 0 else { return nil }
        return unrealizedPnl / cost
    }

    // MARK: Composition

    public var openCount: Int { positions.filter { $0.currentSize > 0 }.count }

    public var redeemablePositions: [Position] { positions.filter(\.redeemable) }

    /// Total that would be received by redeeming every settled winning position.
    public var redeemableValue: Double {
        redeemablePositions.reduce(0) { $0 + $1.currentValue }
    }

    /// Maximum payout if every open position resolves in the user's favour.
    /// Shown as a ceiling, never as an expectation.
    public var maximumPayout: Double {
        positions.reduce(0) { $0 + $1.payoutIfWon }
    }

    public var biggestWinner: Position? {
        positions.max { $0.unrealizedPnl < $1.unrealizedPnl }
    }

    public var biggestLoser: Position? {
        positions.min { $0.unrealizedPnl < $1.unrealizedPnl }
    }

    /// Each position's share of total value, 0...1, largest first.
    ///
    /// Reads `byValue`, which is already sorted, so this is a single pass.
    public func allocations() -> [(position: Position, share: Double)] {
        let total = positionsValue
        guard total > 0 else { return [] }
        return byValue.map { ($0, $0.currentValue / total) }
    }

    /// Groups positions by their parent event, so a multi-leg event reads as
    /// one row rather than several.
    public func groupedByEvent() -> [(eventTitle: String, positions: [Position], value: Double)] {
        let groups = Dictionary(grouping: positions) { position in
            position.eventTitle ?? position.title ?? position.conditionId
        }
        return groups
            .map { key, value in
                (eventTitle: key,
                 positions: value.sorted { $0.currentValue > $1.currentValue },
                 value: value.reduce(0) { $0 + $1.currentValue })
            }
            .sorted { $0.value > $1.value }
    }
}
