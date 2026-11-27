import Foundation

/// Walks an order book to price a prospective trade.
///
/// Every number the trade sheet shows — shares received, average fill price,
/// worst price touched, slippage, payout — comes from here, computed against
/// the live book rather than the last trade price. That matters on thin
/// Polymarket books, where a $500 market buy can move several cents.
public enum QuoteEngine {

    public struct Quote: Sendable, Hashable {
        /// Shares the order would acquire (BUY) or sell (SELL).
        public let shares: Double
        /// USDC spent (BUY) or received (SELL), before fees.
        public let notional: Double
        /// Size-weighted average fill price.
        public let averagePrice: Double
        /// The deepest price level the order touches.
        public let worstPrice: Double
        /// Difference between the average fill and the best available price,
        /// as a fraction of the best price. `nil` when the book is empty.
        public let slippage: Double?
        /// True when the book could not fully absorb the request.
        public let isPartial: Bool
        /// How much of the request could be filled, 0...1.
        public let filledFraction: Double

        /// What the position pays out if the outcome resolves true.
        /// Every winning share settles at exactly $1.
        public var payoutIfWon: Double { shares }

        /// Profit if the outcome resolves true (BUY side).
        public var profitIfWon: Double { shares - notional }

        /// Return on the stake if the outcome resolves true.
        public var returnIfWon: Double? {
            guard notional > 0 else { return nil }
            return (shares - notional) / notional
        }

        public static let zero = Quote(
            shares: 0, notional: 0, averagePrice: 0, worstPrice: 0,
            slippage: nil, isPartial: false, filledFraction: 0
        )
    }

    /// Prices a BUY of `budget` USDC against the ask side.
    ///
    /// - Parameter maxPrice: optional limit; levels above it are not consumed.
    public static func buy(
        budget: Double,
        book: OrderBook,
        maxPrice: Double? = nil
    ) -> Quote {
        guard budget > 0, !book.asks.isEmpty else { return .zero }

        let best = book.asks[0].price
        var remaining = budget
        var shares = 0.0
        var spent = 0.0
        var worst = best

        for level in book.asks {
            if let maxPrice, level.price > maxPrice { break }
            guard remaining > 0, level.price > 0 else { break }

            let levelCost = level.price * level.size
            if levelCost <= remaining {
                shares += level.size
                spent += levelCost
                remaining -= levelCost
            } else {
                let partialShares = remaining / level.price
                shares += partialShares
                spent += remaining
                remaining = 0
            }
            worst = level.price
            if remaining <= 0 { break }
        }

        guard shares > 0 else { return .zero }
        let average = spent / shares
        return Quote(
            shares: shares,
            notional: spent,
            averagePrice: average,
            worstPrice: worst,
            slippage: best > 0 ? (average - best) / best : nil,
            isPartial: remaining > 1e-9,
            filledFraction: budget > 0 ? min(1, spent / budget) : 0
        )
    }

    /// Prices a SELL of `shares` against the bid side.
    ///
    /// - Parameter minPrice: optional floor; levels below it are not consumed.
    public static func sell(
        shares requested: Double,
        book: OrderBook,
        minPrice: Double? = nil
    ) -> Quote {
        guard requested > 0, !book.bids.isEmpty else { return .zero }

        let best = book.bids[0].price
        var remaining = requested
        var sold = 0.0
        var proceeds = 0.0
        var worst = best

        for level in book.bids {
            if let minPrice, level.price < minPrice { break }
            guard remaining > 0 else { break }

            let take = min(level.size, remaining)
            sold += take
            proceeds += take * level.price
            remaining -= take
            worst = level.price
            if remaining <= 0 { break }
        }

        guard sold > 0 else { return .zero }
        let average = proceeds / sold
        return Quote(
            shares: sold,
            notional: proceeds,
            averagePrice: average,
            worstPrice: worst,
            // Selling into lower bids is adverse, so invert the sign.
            slippage: best > 0 ? (best - average) / best : nil,
            isPartial: remaining > 1e-9,
            filledFraction: min(1, sold / requested)
        )
    }

    /// Prices a BUY expressed in shares rather than dollars.
    public static func buyShares(
        _ requested: Double,
        book: OrderBook,
        maxPrice: Double? = nil
    ) -> Quote {
        guard requested > 0, !book.asks.isEmpty else { return .zero }

        let best = book.asks[0].price
        var remaining = requested
        var bought = 0.0
        var spent = 0.0
        var worst = best

        for level in book.asks {
            if let maxPrice, level.price > maxPrice { break }
            guard remaining > 0 else { break }
            let take = min(level.size, remaining)
            bought += take
            spent += take * level.price
            remaining -= take
            worst = level.price
            if remaining <= 0 { break }
        }

        guard bought > 0 else { return .zero }
        let average = spent / bought
        return Quote(
            shares: bought,
            notional: spent,
            averagePrice: average,
            worstPrice: worst,
            slippage: best > 0 ? (average - best) / best : nil,
            isPartial: remaining > 1e-9,
            filledFraction: min(1, bought / requested)
        )
    }
}

// MARK: - Fees

/// Fee estimation, mirroring https://docs.polymarket.com/programs/builders/fees.
///
/// Two independent, additive components:
///  * the **platform fee**, `C × feeRate × p × (1 - p)` — taker only, and
///    zero on markets where fees are disabled,
///  * the **builder fee**, a flat `notional × bps / 10_000`, charged only when
///    this app attaches a builder code.
///
/// These are estimates for display. The authoritative amount is whatever the
/// matching engine charges at fill time, which the UI states plainly.
public enum FeeEstimator {

    public struct Estimate: Sendable, Hashable {
        public let platformFee: Double
        public let builderFee: Double

        public var total: Double { platformFee + builderFee }

        public static let none = Estimate(platformFee: 0, builderFee: 0)
    }

    public static func estimate(
        notional: Double,
        price: Double,
        platformFeeRate: Double?,
        builderFeeBps: Int?,
        isTaker: Bool
    ) -> Estimate {
        guard notional > 0 else { return .none }

        // Platform fee is currently taker-only and shaped so it peaks at p=0.5
        // and vanishes at the extremes.
        var platform = 0.0
        if isTaker, let rate = platformFeeRate, rate > 0, price > 0, price < 1 {
            platform = notional * rate * price * (1 - price)
        }

        var builder = 0.0
        if let bps = builderFeeBps, bps > 0 {
            builder = notional * Double(bps) / 10_000
        }

        return Estimate(platformFee: platform, builderFee: builder)
    }
}
