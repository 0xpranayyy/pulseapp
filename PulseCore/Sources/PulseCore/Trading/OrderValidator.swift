import Foundation

/// Pre-flight checks run before an order is signed or sent.
///
/// The CLOB rejects malformed orders, but a rejection after signing is a poor
/// experience and wastes a round trip. Every rule here mirrors a constraint the
/// exchange actually enforces, so the trade sheet can disable its confirm
/// button with a specific reason instead of a generic failure.
public enum OrderValidator {

    public enum Issue: Error, Sendable, Hashable, Equatable {
        case marketNotTradable
        case priceOutOfRange(price: Double)
        case priceNotOnTick(price: Double, tick: Double)
        case sizeBelowMinimum(size: Double, minimum: Double)
        case insufficientBalance(required: Double, available: Double)
        case insufficientShares(required: Double, available: Double)
        case emptyOrderBook
        case noLiquidity
        case amountNotPositive
        case notAuthenticated
        case excessiveSlippage(slippage: Double, limit: Double)

        public var message: String {
            switch self {
            case .marketNotTradable:
                "This market isn't accepting orders."
            case .priceOutOfRange(let p):
                "Price \(formatted(p)) must be between 0 and 1."
            case .priceNotOnTick(let p, let tick):
                "Price \(formatted(p)) must be a multiple of \(formatted(tick))."
            case .sizeBelowMinimum(let size, let minimum):
                "Minimum order is \(formatted(minimum)) shares — this is \(formatted(size))."
            case .insufficientBalance(let required, let available):
                "Needs $\(formatted(required)) but only $\(formatted(available)) available."
            case .insufficientShares(let required, let available):
                "You hold \(formatted(available)) shares, not \(formatted(required))."
            case .emptyOrderBook:
                "No orders on the book right now."
            case .noLiquidity:
                "Not enough liquidity to fill this order."
            case .amountNotPositive:
                "Enter an amount."
            case .notAuthenticated:
                "Connect a wallet to trade."
            case .excessiveSlippage(let s, let limit):
                "Price impact \(percent(s)) exceeds your \(percent(limit)) limit."
            }
        }

        private func formatted(_ v: Double) -> String {
            String(format: v < 0.01 ? "%.4f" : "%.2f", v)
        }

        private func percent(_ v: Double) -> String {
            String(format: "%.1f%%", v * 100)
        }
    }

    public struct Context: Sendable {
        public let market: Market
        public let side: OrderSide
        public let book: OrderBook
        public let isAuthenticated: Bool
        /// USDC available to spend.
        public let availableBalance: Double?
        /// Shares already held in the outcome being sold.
        public let heldShares: Double?
        /// Maximum tolerated price impact, as a fraction. `nil` disables the check.
        public let slippageLimit: Double?

        public init(
            market: Market,
            side: OrderSide,
            book: OrderBook,
            isAuthenticated: Bool,
            availableBalance: Double? = nil,
            heldShares: Double? = nil,
            slippageLimit: Double? = nil
        ) {
            self.market = market
            self.side = side
            self.book = book
            self.isAuthenticated = isAuthenticated
            self.availableBalance = availableBalance
            self.heldShares = heldShares
            self.slippageLimit = slippageLimit
        }
    }

    /// Validates a **market** order sized in dollars (BUY) or shares (SELL).
    /// Returns every problem found, most blocking first, so the UI can show the
    /// single most relevant one.
    public static func validateMarketOrder(
        amount: Double,
        context: Context,
        quote: QuoteEngine.Quote
    ) -> [Issue] {
        var issues: [Issue] = []

        if !context.isAuthenticated { issues.append(.notAuthenticated) }
        if !context.market.isTradable { issues.append(.marketNotTradable) }
        guard amount > 0 else {
            issues.append(.amountNotPositive)
            return issues
        }

        let relevantSide = context.side == .buy ? context.book.asks : context.book.bids
        if relevantSide.isEmpty {
            issues.append(.emptyOrderBook)
            return issues
        }

        if quote.shares <= 0 {
            issues.append(.noLiquidity)
            return issues
        }

        let minimum = context.market.minimumOrderSize
        if quote.shares < minimum {
            issues.append(.sizeBelowMinimum(size: quote.shares, minimum: minimum))
        }

        switch context.side {
        case .buy:
            if let balance = context.availableBalance, quote.notional > balance + 1e-9 {
                issues.append(.insufficientBalance(required: quote.notional, available: balance))
            }
        case .sell:
            if let held = context.heldShares, amount > held + 1e-9 {
                issues.append(.insufficientShares(required: amount, available: held))
            }
        }

        if quote.isPartial { issues.append(.noLiquidity) }

        if let limit = context.slippageLimit, let slippage = quote.slippage, slippage > limit {
            issues.append(.excessiveSlippage(slippage: slippage, limit: limit))
        }

        return issues
    }

    /// Validates a **limit** order at an explicit price and share count.
    public static func validateLimitOrder(
        price: Double,
        shares: Double,
        context: Context
    ) -> [Issue] {
        var issues: [Issue] = []

        if !context.isAuthenticated { issues.append(.notAuthenticated) }
        if !context.market.isTradable { issues.append(.marketNotTradable) }

        guard shares > 0, price > 0 else {
            issues.append(.amountNotPositive)
            return issues
        }

        // A price of exactly 0 or 1 is never accepted: those are resolution
        // values, not tradable prices.
        if price <= 0 || price >= 1 {
            issues.append(.priceOutOfRange(price: price))
        }

        let tick = context.market.tickSize
        if tick > 0, !isOnTick(price: price, tick: tick) {
            issues.append(.priceNotOnTick(price: price, tick: tick))
        }

        let minimum = context.market.minimumOrderSize
        if shares < minimum {
            issues.append(.sizeBelowMinimum(size: shares, minimum: minimum))
        }

        switch context.side {
        case .buy:
            let cost = price * shares
            if let balance = context.availableBalance, cost > balance + 1e-9 {
                issues.append(.insufficientBalance(required: cost, available: balance))
            }
        case .sell:
            if let held = context.heldShares, shares > held + 1e-9 {
                issues.append(.insufficientShares(required: shares, available: held))
            }
        }

        return issues
    }

    /// True when `price` is an exact multiple of `tick`, within the tolerance
    /// that floating point demands.
    public static func isOnTick(price: Double, tick: Double) -> Bool {
        guard tick > 0 else { return true }
        // Work in integer tick units to avoid accumulating binary error:
        // 0.3 / 0.1 is 2.9999999999999996 in IEEE 754.
        let scaled = (Decimal(price) / Decimal(tick)) as NSDecimalNumber
        let value = scaled.doubleValue
        return abs(value - value.rounded()) < 1e-6
    }

    /// Snaps a price to the nearest valid tick, which is what the trade sheet
    /// does as the user types.
    public static func snapToTick(price: Double, tick: Double) -> Double {
        guard tick > 0 else { return price }
        var result = Decimal()
        var input = Decimal(price) / Decimal(tick)
        NSDecimalRound(&result, &input, 0, .plain)
        let snapped = (result as NSDecimalNumber).doubleValue * tick
        // Re-round to the tick's own precision so 0.30000000000000004 → 0.3.
        let decimals = max(0, Int(ceil(-log10(tick))))
        return OrderAmounts.round(snapped, decimals: decimals, rule: .toNearestOrAwayFromZero)
    }
}
