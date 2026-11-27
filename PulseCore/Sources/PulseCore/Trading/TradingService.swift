import Foundation

/// Builds, signs and submits orders.
///
/// This is the only place an order is constructed, so every order the app
/// sends necessarily goes through validation, the documented rounding rules,
/// EIP-712 signing and builder attribution. There is no path that fabricates
/// a fill: `submit` either returns the exchange's acceptance or throws.
public actor TradingService {
    private let clob: ClobService
    private let configuration: PulseConfiguration
    private let signerProvider: @Sendable () async throws -> (signer: EthereumSigner, maker: String, signatureType: SignatureType)

    public init(
        clob: ClobService,
        configuration: PulseConfiguration = .default,
        signerProvider: @escaping @Sendable () async throws -> (signer: EthereumSigner, maker: String, signatureType: SignatureType)
    ) {
        self.clob = clob
        self.configuration = configuration
        self.signerProvider = signerProvider
    }

    public enum TradingError: Error, Sendable {
        case validation([OrderValidator.Issue])
        case notAuthenticated
        case missingTokenId

        public var userMessage: String {
            switch self {
            case .validation(let issues):
                issues.first?.message ?? "This order isn't valid."
            case .notAuthenticated:
                "Connect a wallet to trade."
            case .missingTokenId:
                "This market has no tradable outcome."
            }
        }
    }

    /// A fully described, validated order awaiting the user's confirmation.
    /// The trade sheet shows exactly these numbers and then submits this
    /// object unchanged, so what is confirmed is what is signed.
    public struct PreparedOrder: Sendable {
        public let market: Market
        public let tokenId: String
        public let outcomeLabel: String
        public let side: OrderSide
        public let orderType: OrderType
        public let price: Double
        public let shares: Double
        public let notional: Double
        public let fees: FeeEstimator.Estimate
        public let quote: QuoteEngine.Quote?
        public let isMarketOrder: Bool

        /// Total cash leaving the account on a buy, including estimated fees.
        public var totalCost: Double {
            side == .buy ? notional + fees.total : notional
        }

        /// Cash received on a sell, net of estimated fees.
        public var netProceeds: Double {
            side == .sell ? notional - fees.total : 0
        }

        public var payoutIfWon: Double { shares }
    }

    // MARK: Preparation

    /// Prepares a **market** order against live book depth.
    /// - Parameter amount: USDC to spend for a buy, or shares to sell.
    public func prepareMarketOrder(
        market: Market,
        tokenId: String,
        outcomeLabel: String,
        side: OrderSide,
        amount: Double,
        book: OrderBook,
        availableBalance: Double?,
        heldShares: Double?,
        slippageLimit: Double?,
        isAuthenticated: Bool
    ) throws -> PreparedOrder {
        let quote = side == .buy
            ? QuoteEngine.buy(budget: amount, book: book)
            : QuoteEngine.sell(shares: amount, book: book)

        let context = OrderValidator.Context(
            market: market,
            side: side,
            book: book,
            isAuthenticated: isAuthenticated,
            availableBalance: availableBalance,
            heldShares: heldShares,
            slippageLimit: slippageLimit
        )

        let issues = OrderValidator.validateMarketOrder(
            amount: amount, context: context, quote: quote
        )
        guard issues.isEmpty else { throw TradingError.validation(issues) }

        let fees = FeeEstimator.estimate(
            notional: quote.notional,
            price: quote.averagePrice,
            platformFeeRate: market.feesEnabled == true ? 0.01 : nil,
            builderFeeBps: configuration.builderFeeBps,
            isTaker: true
        )

        return PreparedOrder(
            market: market,
            tokenId: tokenId,
            outcomeLabel: outcomeLabel,
            side: side,
            // Fill-and-kill: take what the book offers now, cancel the rest,
            // rather than silently resting an unfilled remainder.
            orderType: .fak,
            // Sign at the worst price touched so the order remains marketable
            // if the book ticks against us between quote and submission.
            price: OrderValidator.snapToTick(
                price: quote.worstPrice, tick: market.tickSize
            ),
            shares: quote.shares,
            notional: quote.notional,
            fees: fees,
            quote: quote,
            isMarketOrder: true
        )
    }

    /// Prepares a **limit** order that rests on the book.
    public func prepareLimitOrder(
        market: Market,
        tokenId: String,
        outcomeLabel: String,
        side: OrderSide,
        price: Double,
        shares: Double,
        book: OrderBook,
        availableBalance: Double?,
        heldShares: Double?,
        isAuthenticated: Bool
    ) throws -> PreparedOrder {
        let snapped = OrderValidator.snapToTick(price: price, tick: market.tickSize)

        let context = OrderValidator.Context(
            market: market,
            side: side,
            book: book,
            isAuthenticated: isAuthenticated,
            availableBalance: availableBalance,
            heldShares: heldShares
        )

        let issues = OrderValidator.validateLimitOrder(
            price: snapped, shares: shares, context: context
        )
        guard issues.isEmpty else { throw TradingError.validation(issues) }

        let notional = snapped * shares
        // A resting limit order is a maker order, so no platform fee applies.
        let fees = FeeEstimator.estimate(
            notional: notional,
            price: snapped,
            platformFeeRate: nil,
            builderFeeBps: configuration.builderFeeBps,
            isTaker: false
        )

        return PreparedOrder(
            market: market,
            tokenId: tokenId,
            outcomeLabel: outcomeLabel,
            side: side,
            orderType: .gtc,
            price: snapped,
            shares: shares,
            notional: notional,
            fees: fees,
            quote: nil,
            isMarketOrder: false
        )
    }

    // MARK: Submission

    /// Signs and submits a prepared order. Throws on any rejection — there is
    /// no success path that is not an exchange acknowledgement.
    @discardableResult
    public func submit(_ prepared: PreparedOrder) async throws -> OrderPlacementResponse {
        let (signer, maker, signatureType) = try await signerProvider()

        let amounts = try OrderAmounts.make(
            side: prepared.side,
            price: prepared.price,
            size: prepared.shares,
            tickSize: prepared.market.tickSize
        )

        let order = PolymarketOrder(
            // A fresh salt per order; kept inside JavaScript's safe integer
            // range because the body serialises it as a JSON number.
            salt: UInt64.random(in: 1...9_007_199_254_740_990),
            maker: maker,
            signer: try await signer.address,
            tokenId: prepared.tokenId,
            makerAmount: amounts.makerAmount,
            takerAmount: amounts.takerAmount,
            side: prepared.side,
            signatureType: signatureType,
            timestamp: String(Int(Date().timeIntervalSince1970 * 1000)),
            builder: configuration.builderField
        )

        let domain = ExchangeDomain.select(
            isProtocolV2: false,
            negRisk: prepared.market.negRisk ?? false
        )
        let digest = try order.signingDigest(domain: domain)
        let signature = try await signer.signDigest(digest)

        return try await clob.submit(
            order: order,
            signature: signature,
            orderType: prepared.orderType
        )
    }
}
