import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Inbound events

/// Messages from the CLOB market channel.
/// Shapes from https://docs.polymarket.com/market-data/realtime-data.
public enum MarketEvent: Sendable, Hashable {
    case book(assetId: String, book: OrderBook)
    case priceChange(assetId: String, price: Double, bestBid: Double?, bestAsk: Double?)
    case lastTradePrice(assetId: String, price: Double, size: Double, side: OrderSide?)
    case tickSizeChange(assetId: String, newTickSize: Double)
    case bestBidAsk(assetId: String, bestBid: Double?, bestAsk: Double?, spread: Double?)

    public var assetId: String {
        switch self {
        case .book(let id, _), .priceChange(let id, _, _, _),
             .lastTradePrice(let id, _, _, _), .tickSizeChange(let id, _),
             .bestBidAsk(let id, _, _, _):
            id
        }
    }
}

/// Connection state, surfaced so the UI can show a live/stale indicator
/// rather than silently displaying old prices.
public enum SocketState: Sendable, Hashable {
    case idle
    case connecting
    case live
    case reconnecting(attempt: Int)
    case failed(String)

    public var isLive: Bool { self == .live }
}

// MARK: - Decoding

private struct RawMarketMessage: Decodable {
    let eventType: String
    let market: String?
    let assetId: String?
    let timestamp: String?
    let bids: [OrderBookLevel]?
    let asks: [OrderBookLevel]?
    let price: LenientDouble?
    let size: LenientDouble?
    let side: String?
    let bestBid: LenientDouble?
    let bestAsk: LenientDouble?
    let spread: LenientDouble?
    let newTickSize: LenientDouble?
    let priceChanges: [PriceChange]?

    struct PriceChange: Decodable {
        let assetId: String?
        let price: LenientDouble?
        let size: LenientDouble?
        let side: String?
        let bestBid: LenientDouble?
        let bestAsk: LenientDouble?

        private enum CodingKeys: String, CodingKey {
            case assetId = "asset_id"
            case price, size, side
            case bestBid = "best_bid"
            case bestAsk = "best_ask"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case market, timestamp, bids, asks, price, size, side, spread
        case assetId = "asset_id"
        case bestBid = "best_bid"
        case bestAsk = "best_ask"
        case newTickSize = "new_tick_size"
        case priceChanges = "price_changes"
    }
}

enum MarketMessageParser {
    /// Parses one inbound frame into zero or more events. The server may send
    /// a bare object or an array of them, and `price_change` batches several
    /// assets into one frame.
    static func parse(_ data: Data) -> [MarketEvent] {
        let decoder = JSONDecoder()
        if let batch = try? decoder.decode([RawMarketMessage].self, from: data) {
            return batch.flatMap(events(from:))
        }
        if let single = try? decoder.decode(RawMarketMessage.self, from: data) {
            return events(from: single)
        }
        return []
    }

    private static func events(from raw: RawMarketMessage) -> [MarketEvent] {
        switch raw.eventType {
        case "book":
            guard let assetId = raw.assetId else { return [] }
            let book = OrderBook(
                market: raw.market,
                assetId: assetId,
                timestamp: raw.timestamp,
                bids: raw.bids ?? [],
                asks: raw.asks ?? []
            )
            return [.book(assetId: assetId, book: book)]

        case "price_change":
            // One frame can carry changes for several assets.
            return (raw.priceChanges ?? []).compactMap { change in
                guard let assetId = change.assetId, let price = change.price?.value else {
                    return nil
                }
                return .priceChange(
                    assetId: assetId,
                    price: price,
                    bestBid: change.bestBid?.value,
                    bestAsk: change.bestAsk?.value
                )
            }

        case "last_trade_price":
            guard let assetId = raw.assetId, let price = raw.price?.value else { return [] }
            return [.lastTradePrice(
                assetId: assetId,
                price: price,
                size: raw.size?.value ?? 0,
                side: raw.side.flatMap { OrderSide(rawValue: $0.uppercased()) }
            )]

        case "tick_size_change":
            guard let assetId = raw.assetId, let tick = raw.newTickSize?.value else { return [] }
            return [.tickSizeChange(assetId: assetId, newTickSize: tick)]

        case "best_bid_ask":
            guard let assetId = raw.assetId else { return [] }
            return [.bestBidAsk(
                assetId: assetId,
                bestBid: raw.bestBid?.value,
                bestAsk: raw.bestAsk?.value,
                spread: raw.spread?.value
            )]

        default:
            return []
        }
    }
}

// MARK: - Socket

/// A resilient connection to the CLOB market channel.
///
/// Responsibilities beyond ferrying bytes:
///  * an application-level `PING` every 10s, which the server requires,
///  * exponential backoff with jitter on drop, capped so a long outage does
///    not spin,
///  * re-subscribing to the current asset set after every reconnect,
///  * publishing `SocketState` so the UI can mark prices stale instead of
///    quietly showing frozen numbers.
public actor MarketSocket {
    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var assetIds: Set<String> = []
    private var receiveLoop: Task<Void, Never>?
    private var pingLoop: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var isStopping = false

    public private(set) var state: SocketState = .idle {
        didSet { stateHandler?(state) }
    }

    private var eventHandler: (@Sendable ([MarketEvent]) -> Void)?
    private var stateHandler: (@Sendable (SocketState) -> Void)?

    /// Backoff ceiling. Reconnects stop getting slower past this.
    private let maxBackoff: TimeInterval = 30

    public init(url: URL = PolymarketHost.marketSocket, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func onEvents(_ handler: @escaping @Sendable ([MarketEvent]) -> Void) {
        eventHandler = handler
    }

    public func onStateChange(_ handler: @escaping @Sendable (SocketState) -> Void) {
        stateHandler = handler
    }

    /// Subscribes to a set of outcome tokens, replacing any previous set.
    public func subscribe(to assetIds: [String]) {
        let new = Set(assetIds.filter { !$0.isEmpty })
        guard new != self.assetIds else { return }
        self.assetIds = new

        guard !new.isEmpty else {
            stop()
            return
        }

        if task == nil {
            connect()
        } else {
            sendSubscription()
        }
    }

    public func stop() {
        isStopping = true
        receiveLoop?.cancel()
        pingLoop?.cancel()
        receiveLoop = nil
        pingLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .idle
    }

    // MARK: Connection lifecycle

    private func connect() {
        guard !assetIds.isEmpty else { return }
        isStopping = false
        state = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        sendSubscription()
        startReceiving()
        startPinging()
    }

    private func sendSubscription() {
        guard let task else { return }
        let payload: [String: Any] = [
            "assets_ids": Array(assetIds),
            "type": "market",
            // Opt in to top-of-book and lifecycle events.
            "custom_feature_enabled": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text)) { _ in }
    }

    private func startReceiving() {
        receiveLoop?.cancel()
        receiveLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let task = await self.currentTask() else { return }
                do {
                    let message = try await task.receive()
                    await self.handle(message)
                } catch {
                    await self.handleDisconnect(error)
                    return
                }
            }
        }
    }

    private func currentTask() -> URLSessionWebSocketTask? { task }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        // First successful frame means the connection is healthy.
        if state != .live {
            state = .live
            reconnectAttempt = 0
        }

        let data: Data?
        switch message {
        case .string(let text):
            // The server answers our PING with a bare "PONG".
            if text == "PONG" || text == "pong" { return }
            data = text.data(using: .utf8)
        case .data(let raw):
            data = raw
        @unknown default:
            data = nil
        }

        guard let data else { return }
        let events = MarketMessageParser.parse(data)
        if !events.isEmpty { eventHandler?(events) }
    }

    /// The market socket needs a text `PING` every 10 seconds or the server
    /// drops the connection.
    private func startPinging() {
        pingLoop?.cancel()
        pingLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.sendPing()
            }
        }
    }

    private func sendPing() {
        task?.send(.string("PING")) { _ in }
    }

    private func handleDisconnect(_ error: Error) {
        guard !isStopping else { return }

        receiveLoop?.cancel()
        pingLoop?.cancel()
        task = nil

        guard !assetIds.isEmpty else {
            state = .idle
            return
        }

        reconnectAttempt += 1
        state = .reconnecting(attempt: reconnectAttempt)

        // Exponential backoff with jitter, capped.
        let base = min(maxBackoff, pow(2.0, Double(min(reconnectAttempt, 6))) * 0.5)
        let delay = base + Double.random(in: 0...0.5)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            let stopped = await self.isStopped()
            guard !stopped else { return }
            await self.connect()
        }
    }

    private func isStopped() -> Bool { isStopping }
}
