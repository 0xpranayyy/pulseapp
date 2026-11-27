import SwiftUI
import Observation
import PulseCore

/// What the user tapped to open the trade sheet.
struct TradeRequest: Identifiable, Hashable {
    let event: Event
    let market: Market
    let tokenId: String
    let outcomeLabel: String
    let isYes: Bool
    var side: OrderSide = .buy

    var id: String { "\(market.id)-\(tokenId)-\(side.rawValue)" }
}

@MainActor
@Observable
final class TradeViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case market = "Market"
        case limit = "Limit"
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case editing
        case confirming
        case submitting
        case succeeded(orderId: String?)
        case failed(String)
    }

    private(set) var phase: Phase = .editing
    private(set) var book: OrderBook = .empty
    private(set) var isLoadingBook = false
    private(set) var heldShares: Double?
    private(set) var validationIssues: [OrderValidator.Issue] = []
    private(set) var prepared: TradingService.PreparedOrder?

    var mode: Mode = .market
    var side: OrderSide
    /// USDC to spend (buy) or shares to sell (sell), as typed.
    var amountText: String = ""
    /// Limit price in cents, as typed.
    var limitPriceText: String = ""
    var limitSharesText: String = ""

    let request: TradeRequest
    private let clob: ClobService
    private let data: DataService
    private let trading: TradingService
    private let session: SessionStore
    private let settings: SettingsStore

    init(
        request: TradeRequest,
        clob: ClobService,
        data: DataService,
        trading: TradingService,
        session: SessionStore,
        settings: SettingsStore
    ) {
        self.request = request
        self.side = request.side
        self.clob = clob
        self.data = data
        self.trading = trading
        self.session = session
        self.settings = settings
    }

    // MARK: Derived

    var amount: Double { Double(amountText) ?? 0 }
    var limitPrice: Double { (Double(limitPriceText) ?? 0) / 100 }
    var limitShares: Double { Double(limitSharesText) ?? 0 }

    var availableBalance: Double? { session.availableBalance }
    var canTrade: Bool { session.canTrade }

    /// Live quote against current book depth.
    var quote: QuoteEngine.Quote? {
        guard mode == .market, amount > 0 else { return nil }
        return side == .buy
            ? QuoteEngine.buy(budget: amount, book: book)
            : QuoteEngine.sell(shares: amount, book: book)
    }

    var isReady: Bool {
        prepared != nil && validationIssues.isEmpty && canTrade
    }

    var blockingIssue: OrderValidator.Issue? { validationIssues.first }

    /// Suggested amounts, clamped so a preset never exceeds what's available.
    var presets: [Double] {
        side == .buy ? [5, 25, 100, 500] : [25, 50, 75, 100]
    }

    // MARK: Loading

    func load() async {
        isLoadingBook = true
        defer { isLoadingBook = false }

        async let bookResult = try? clob.book(tokenId: request.tokenId)
        async let positionResult = loadHeldShares()

        book = await bookResult ?? .empty
        await positionResult

        // Seed the limit price at the current market, so the field opens on a
        // plausible value rather than empty.
        if limitPriceText.isEmpty, let mid = book.midpoint, mid > 0 {
            let snapped = OrderValidator.snapToTick(price: mid, tick: request.market.tickSize)
            limitPriceText = String(Int((snapped * 100).rounded()))
        }
        recalculate()
    }

    private func loadHeldShares() async {
        guard let address = session.address else { return }
        let page = try? await data.positions(user: address, status: .open, limit: 100)
        heldShares = page?.items
            .first { $0.tokenId == request.tokenId }?
            .currentSize
    }

    // MARK: Validation

    /// Re-prepares the order whenever an input changes. Keeping preparation
    /// and display in one place means the confirmation screen can only ever
    /// show numbers that came from a validated order.
    func recalculate() {
        prepared = nil
        validationIssues = []

        guard canTrade else {
            validationIssues = [.notAuthenticated]
            return
        }

        do {
            let order: TradingService.PreparedOrder
            switch mode {
            case .market:
                guard amount > 0 else { return }
                order = try trading.prepareMarketOrderSync(
                    market: request.market,
                    tokenId: request.tokenId,
                    outcomeLabel: request.outcomeLabel,
                    side: side,
                    amount: amount,
                    book: book,
                    availableBalance: availableBalance,
                    heldShares: heldShares,
                    slippageLimit: settings.slippageLimit,
                    isAuthenticated: canTrade
                )
            case .limit:
                guard limitPrice > 0, limitShares > 0 else { return }
                order = try trading.prepareLimitOrderSync(
                    market: request.market,
                    tokenId: request.tokenId,
                    outcomeLabel: request.outcomeLabel,
                    side: side,
                    price: limitPrice,
                    shares: limitShares,
                    book: book,
                    availableBalance: availableBalance,
                    heldShares: heldShares,
                    isAuthenticated: canTrade
                )
            }
            prepared = order
        } catch let error as TradingService.TradingError {
            if case .validation(let issues) = error { validationIssues = issues }
        } catch {
            validationIssues = []
        }
    }

    // MARK: Submission

    func requestConfirmation() {
        guard isReady else { return }
        phase = settings.confirmBeforeTrading ? .confirming : .editing
        if !settings.confirmBeforeTrading {
            Task { await submit() }
        }
    }

    func cancelConfirmation() {
        phase = .editing
    }

    /// Signs and submits. Any failure surfaces verbatim — the sheet never
    /// reports a success the exchange did not confirm.
    func submit() async {
        guard let prepared else { return }
        phase = .submitting

        do {
            let response = try await trading.submit(prepared)
            phase = .succeeded(orderId: response.orderId)
            await session.refreshBalances()
        } catch let error as TradingService.TradingError {
            phase = .failed(error.userMessage)
        } catch let error as APIError {
            phase = .failed(error.userMessage)
        } catch {
            phase = .failed("The order couldn't be submitted.")
        }
    }

    func reset() {
        phase = .editing
        amountText = ""
        prepared = nil
    }
}

// MARK: - Synchronous preparation helpers
//
// `TradingService` is an actor because submission touches the signer, but
// preparation is pure computation. These wrappers let the view model
// recompute a quote synchronously as the user types, instead of hopping
// actors on every keystroke and showing numbers that lag the input.
extension TradingService {
    nonisolated func prepareMarketOrderSync(
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
            market: market, side: side, book: book,
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
            builderFeeBps: nil,
            isTaker: true
        )

        return PreparedOrder(
            market: market, tokenId: tokenId, outcomeLabel: outcomeLabel,
            side: side, orderType: .fak,
            price: OrderValidator.snapToTick(price: quote.worstPrice, tick: market.tickSize),
            shares: quote.shares, notional: quote.notional,
            fees: fees, quote: quote, isMarketOrder: true
        )
    }

    nonisolated func prepareLimitOrderSync(
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
            market: market, side: side, book: book,
            isAuthenticated: isAuthenticated,
            availableBalance: availableBalance,
            heldShares: heldShares
        )
        let issues = OrderValidator.validateLimitOrder(
            price: snapped, shares: shares, context: context
        )
        guard issues.isEmpty else { throw TradingError.validation(issues) }

        let notional = snapped * shares
        let fees = FeeEstimator.estimate(
            notional: notional, price: snapped,
            platformFeeRate: nil, builderFeeBps: nil, isTaker: false
        )

        return PreparedOrder(
            market: market, tokenId: tokenId, outcomeLabel: outcomeLabel,
            side: side, orderType: .gtc, price: snapped,
            shares: shares, notional: notional,
            fees: fees, quote: nil, isMarketOrder: false
        )
    }
}
