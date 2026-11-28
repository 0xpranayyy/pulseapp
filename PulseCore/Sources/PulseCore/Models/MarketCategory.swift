import Foundation

/// What a market is about, read from its Gamma tags.
///
/// The category decides a market's colour everywhere — the feed card, the
/// detail header, the Live Activity — so it has to be stable and cheap. It
/// lives here rather than in the app target so it can be tested on Linux.
///
/// Colour rule: green and red belong to Yes and No and are never a
/// category. Each category carries two shades: a bright `fillHex` for icons,
/// dots and the allocation bar, and a deeper `panelHex` for any surface that
/// carries white text, chosen to clear 4.5:1 against white. The design's
/// sport orange, for instance, is only 2.9:1 — fine as a dot, not as the
/// background of a headline.
public enum MarketCategory: String, CaseIterable, Sendable, Hashable, Identifiable {
    case sport, crypto, politics, economy, tech, culture, world, other

    public var id: String { rawValue }

    /// Picks the category from a market's tags.
    ///
    /// Tags arrive in Gamma's relevance order, so the first tag that names a
    /// category wins: a market tagged `trump`, `crypto` is politics. Matching
    /// is on slugs, case-insensitive; labels are display text and change.
    public init(tagSlugs: [String]) {
        for slug in tagSlugs.map({ $0.lowercased() }) {
            if let match = Self.bySlug[slug] {
                self = match
                return
            }
        }
        self = .other
    }

    public init(tags: [Tag]?) {
        self.init(tagSlugs: (tags ?? []).compactMap(\.slug))
    }

    public var title: String {
        switch self {
        case .sport: "Sport"
        case .crypto: "Crypto"
        case .politics: "Politics"
        case .economy: "Economy"
        case .tech: "Tech & science"
        case .culture: "Culture"
        case .world: "World"
        case .other: "Markets"
        }
    }

    /// An SF Symbol for the category tile.
    public var symbol: String {
        switch self {
        case .sport: "soccerball"
        case .crypto: "bitcoinsign.circle.fill"
        case .politics: "building.columns.fill"
        case .economy: "chart.line.uptrend.xyaxis"
        case .tech: "cpu.fill"
        case .culture: "theatermasks.fill"
        case .world: "globe.europe.africa.fill"
        case .other: "sparkles"
        }
    }

    /// Bright shade: icons, dots, bars. Not for text backgrounds.
    public var fillHex: String {
        switch self {
        case .sport: "F07A2E"
        case .crypto: "7B5CE6"
        case .politics: "4F7BEA"
        case .economy: "1C9AA0"
        case .tech: "D6479F"
        case .culture: "E5A100"
        case .world: "6C80A6"
        case .other: "5A6190"
        }
    }

    /// Deep shade: panels and headers that carry white text (≥ 4.5:1).
    public var panelHex: String {
        switch self {
        case .sport: "C2541F"
        case .crypto: "6B4BD8"
        case .politics: "3F6BDB"
        case .economy: "157A80"
        case .tech: "B0368A"
        case .culture: "8F5E00"
        case .world: "4A5C7A"
        case .other: "1F2557"
        }
    }

    private static let slugs: [MarketCategory: [String]] = [
        .sport: ["sports", "sport", "soccer", "football", "nba", "nfl", "mlb", "nhl",
                 "tennis", "f1", "formula-1", "cricket", "ufc", "boxing", "golf",
                 "champions-league", "premier-league", "epl", "olympics"],
        .crypto: ["crypto", "bitcoin", "ethereum", "solana", "btc", "eth", "crypto-prices",
                  "defi", "airdrops", "memecoins", "stablecoins"],
        .politics: ["politics", "elections", "election", "us-politics", "us-elections",
                    "trump", "congress", "senate", "uk-politics", "primaries"],
        .economy: ["economy", "finance", "business", "fed", "fed-rates", "inflation",
                   "stocks", "earnings", "interest-rates", "macro", "recession", "ipos"],
        .tech: ["tech", "technology", "ai", "science", "space", "spacex", "openai"],
        .culture: ["pop-culture", "culture", "entertainment", "movies", "music", "tv",
                   "celebrities", "awards", "oscars", "gaming"],
        .world: ["world", "geopolitics", "middle-east", "ukraine", "russia", "china",
                 "israel", "global-politics"]
    ]

    private static let bySlug: [String: MarketCategory] = {
        var index: [String: MarketCategory] = [:]
        for (category, list) in slugs {
            for slug in list { index[slug] = category }
        }
        return index
    }()
}

public extension Event {
    /// The event's category, read from its tags. Computed rather than stored:
    /// it is a handful of dictionary lookups, and storing it would mean a
    /// second source of truth to keep in step with `tags`.
    var category: MarketCategory { MarketCategory(tags: tags) }
}
