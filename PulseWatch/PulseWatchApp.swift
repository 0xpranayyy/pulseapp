import SwiftUI
import PulseCore

/// The watch app.
///
/// Standalone rather than a mirror of the phone: Gamma and the CLOB are
/// public, so the watch fetches its own data and stays useful when the phone
/// is not nearby. Trading is deliberately absent — signing an order needs the
/// Keychain key that lives on the phone, and a 44mm screen is the wrong place
/// to confirm spending money.
@main
struct PulseWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class WatchStore {
    private(set) var events: [Event] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    private let gamma = GammaService()

    /// A short list: the watch is for a glance, and more rows means more
    /// scrolling on a crown rather than more information.
    private let limit = 12

    func load(force: Bool = false) async {
        guard force || events.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            events = try await gamma.events(limit: limit, sort: .volume24hr)
            lastUpdated = Date()
        } catch let error as APIError {
            if events.isEmpty { errorMessage = error.userMessage }
        } catch {
            if events.isEmpty { errorMessage = "Couldn't load markets." }
        }
    }
}

// MARK: - Root

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.events.isEmpty {
                    ProgressView()
                } else if let error = store.errorMessage, store.events.isEmpty {
                    WatchMessage(
                        icon: "exclamationmark.triangle",
                        title: "Can't load",
                        message: error
                    ) {
                        Task { await store.load(force: true) }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Pulse")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await store.load() }
    }

    private var list: some View {
        List {
            ForEach(store.events) { event in
                NavigationLink {
                    WatchMarketDetail(event: event)
                } label: {
                    WatchMarketRow(event: event)
                }
                // Each row in its category's panel colour, as on the
                // phone's featured cards. White text clears 4.5:1 on every
                // panel shade.
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.theme(for: event.category).field)
                )
            }
        }
        .listStyle(.carousel)
        .refreshable { await store.load(force: true) }
    }
}

// MARK: - Row

struct WatchMarketRow: View {
    let event: Event

    private var theme: Palette.Theme { Palette.theme(for: event.category) }
    private var market: Market? { event.primaryMarket }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(event.category.title.uppercased(), systemImage: event.category.symbol)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.onField)
                .lineLimit(1)

            Text(event.displayTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(theme.onField)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Format.probability(market?.yesProbability))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.onField)

                if let change = market?.dayChange, abs(change) > 0.0001 {
                    Text(Format.probabilityChange(change))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.onField)
                }

                Spacer(minLength: 0)
            }

            WatchTug(probability: market?.yesProbability ?? 0.5, height: 5, knot: 11)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(event.displayTitle), \(Format.probability(market?.yesProbability))"
        )
    }
}

// MARK: - Detail

struct WatchMarketDetail: View {
    let event: Event

    @State private var book: OrderBook?
    @State private var isLoading = true

    private var theme: Palette.Theme { Palette.theme(for: event.category) }
    private var market: Market? { event.primaryMarket }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(Format.probability(market?.yesProbability))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.onField)

                Text(event.displayTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.onField)
                    .fixedSize(horizontal: false, vertical: true)

                WatchTug(probability: market?.yesProbability ?? 0.5, height: 7, knot: 14)

                if event.isMultiOutcome {
                    outcomes
                } else if let book {
                    bookSummary(book)
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }

                stats
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(theme.screen.gradient, for: .navigation)
        .navigationTitle("Market")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBook() }
    }

    private var outcomes: some View {
        VStack(spacing: 5) {
            ForEach(
                (event.markets ?? [])
                    .sorted { ($0.yesProbability ?? 0) > ($1.yesProbability ?? 0) }
                    .prefix(5),
                id: \.id
            ) { leg in
                HStack {
                    Text(leg.displayTitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Format.probability(leg.yesProbability))
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(theme.onField)
            }
        }
    }

    private func bookSummary(_ book: OrderBook) -> some View {
        HStack {
            if let bid = book.bestBid {
                statLabel("Bid", Format.cents(bid))
            }
            Spacer()
            if let ask = book.bestAsk {
                statLabel("Ask", Format.cents(ask))
            }
        }
    }

    private var stats: some View {
        HStack {
            statLabel("Volume", Format.compactCurrency(market?.volumeTotal))
            Spacer()
            if let end = market?.resolvedEndDate {
                statLabel("Closes", Format.timeRemaining(until: end))
            }
        }
    }

    private func statLabel(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.onField.opacity(0.85))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.onField)
        }
    }

    private func loadBook() async {
        defer { isLoading = false }
        guard let tokenId = market?.yesTokenId else { return }
        let clob = ClobService(authenticator: ClobAuthenticator())
        book = try? await clob.book(tokenId: tokenId)
    }
}

// MARK: - Shared

/// The tug, as on the phone: green Yes on the left, red No, the lime knot
/// at the Yes price.
struct WatchTug: View {
    let probability: Double
    var height: CGFloat
    var knot: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let split = geometry.size.width * min(1, max(0, probability))
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Brand.yes.frame(width: split)
                    Brand.no
                }
                .frame(height: height)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1).padding(-1))

                Circle()
                    .fill(Brand.lime)
                    .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 2))
                    .frame(width: knot, height: knot)
                    .offset(x: min(max(0, split - knot / 2), geometry.size.width - knot))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: knot)
        .accessibilityHidden(true)
    }
}

struct WatchMessage: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
            }
        }
        .padding()
    }
}
