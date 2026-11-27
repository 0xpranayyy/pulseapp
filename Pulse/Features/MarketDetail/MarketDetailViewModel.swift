import Foundation
import Observation
import PulseCore

@MainActor
@Observable
final class MarketDetailViewModel {
    private(set) var event: Event
    private(set) var selectedMarket: Market

    /// Live book for the currently selected outcome token.
    private(set) var book: OrderBook = .empty
    private(set) var history: [PricePoint] = []
    private(set) var holders: [Holder] = []

    private(set) var isLoadingHistory = false
    private(set) var isLoadingBook = false
    private(set) var socketState: SocketState = .idle
    private(set) var errorMessage: String?

    /// Last price seen on the stream, which leads the REST snapshot.
    private(set) var livePrice: Double?
    private(set) var lastUpdate: Date?

    var interval: PriceHistoryInterval = .oneDay {
        didSet {
            guard interval != oldValue else { return }
            Task { await loadHistory() }
        }
    }

    /// Which side of the binary market the user is looking at.
    var isViewingYes: Bool = true {
        didSet {
            guard isViewingYes != oldValue else { return }
            Task { await loadBookAndHistory() }
        }
    }

    private let gamma: GammaService
    private let clob: ClobService
    private let data: DataService
    private let socket: MarketSocket

    init(
        event: Event,
        market: Market,
        gamma: GammaService,
        clob: ClobService,
        data: DataService,
        socket: MarketSocket
    ) {
        self.event = event
        self.selectedMarket = market
        self.gamma = gamma
        self.clob = clob
        self.data = data
        self.socket = socket
    }

    // MARK: Derived

    var activeTokenId: String? {
        isViewingYes ? selectedMarket.yesTokenId : selectedMarket.noTokenId
    }

    var outcomeLabel: String {
        let labels = selectedMarket.outcomeLabels
        if isViewingYes { return labels.first ?? "Yes" }
        return labels.count > 1 ? labels[1] : "No"
    }

    /// The probability to display: the live stream when it is current,
    /// otherwise the book midpoint, otherwise Gamma's figure.
    var displayedProbability: Double? {
        if let livePrice { return livePrice }
        if let mid = book.midpoint, mid > 0 { return mid }
        let gammaValue = selectedMarket.yesProbability
        return isViewingYes ? gammaValue : gammaValue.map { 1 - $0 }
    }

    /// True when the socket is not delivering, so the UI can mark prices stale
    /// rather than presenting frozen numbers as current.
    var isPriceStale: Bool { !socketState.isLive }

    var canTrade: Bool { selectedMarket.isTradable && activeTokenId != nil }

    // MARK: Loading

    func load() async {
        async let bookLoad: () = loadBook()
        async let historyLoad: () = loadHistory()
        async let holdersLoad: () = loadHolders()
        _ = await (bookLoad, historyLoad, holdersLoad)
        await startStreaming()
    }

    func refresh() async {
        await loadBookAndHistory()
        await loadHolders()
    }

    private func loadBookAndHistory() async {
        livePrice = nil
        async let bookLoad: () = loadBook()
        async let historyLoad: () = loadHistory()
        _ = await (bookLoad, historyLoad)
        await startStreaming()
    }

    func select(market: Market) async {
        guard market.id != selectedMarket.id else { return }
        selectedMarket = market
        livePrice = nil
        history = []
        book = .empty
        await loadBookAndHistory()
    }

    private func loadBook() async {
        guard let tokenId = activeTokenId else { return }
        isLoadingBook = true
        defer { isLoadingBook = false }
        do {
            book = try await clob.book(tokenId: tokenId)
            lastUpdate = Date()
            errorMessage = nil
        } catch let error as APIError where error == .cancelled {
            return
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "Couldn't load the order book."
        }
    }

    private func loadHistory() async {
        guard let tokenId = activeTokenId else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        history = (try? await clob.priceHistory(tokenId: tokenId, interval: interval)) ?? []
    }

    private func loadHolders() async {
        guard let conditionId = selectedMarket.conditionId else { return }
        let groups = (try? await data.holders(conditionId: conditionId, limit: 10)) ?? []
        // Holders for the outcome currently in view.
        let index = isViewingYes ? 0 : 1
        holders = groups
            .flatMap(\.holders)
            .filter { ($0.outcomeIndex ?? 0) == index }
            .sorted { $0.amount > $1.amount }
            .prefix(8)
            .map { $0 }
    }

    // MARK: Streaming

    private func startStreaming() async {
        guard let tokenId = activeTokenId else { return }

        await socket.onStateChange { [weak self] state in
            Task { @MainActor in self?.socketState = state }
        }
        await socket.onEvents { [weak self] events in
            Task { @MainActor in self?.apply(events) }
        }
        await socket.subscribe(to: [tokenId])
    }

    func stopStreaming() async {
        await socket.stop()
    }

    private func apply(_ events: [MarketEvent]) {
        guard let tokenId = activeTokenId else { return }

        for event in events where event.assetId == tokenId {
            switch event {
            case .book(_, let newBook):
                book = newBook
                if let mid = newBook.midpoint { livePrice = mid }
            case .priceChange(_, _, let bid, let ask):
                if let bid, let ask, bid > 0, ask > 0 {
                    livePrice = (bid + ask) / 2
                }
            case .bestBidAsk(_, let bid, let ask, _):
                if let bid, let ask, bid > 0, ask > 0 {
                    livePrice = (bid + ask) / 2
                }
            case .lastTradePrice(_, let price, _, _):
                livePrice = price
            case .tickSizeChange:
                // The tick size changed under us; the cached market's value is
                // now wrong and every later order would be rejected, so refetch.
                Task { await self.refreshMarketMetadata() }
            }
            lastUpdate = Date()
        }
    }

    private func refreshMarketMetadata() async {
        guard let updated = try? await gamma.market(id: selectedMarket.id) else { return }
        selectedMarket = updated
    }
}
