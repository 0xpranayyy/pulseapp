import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Shared caching for market data and artwork.
///
/// `URLSession.shared` carries a 512 KB memory / 10 MB disk cache by default,
/// which a feed of market artwork evicts almost immediately — scrolling back
/// up re-downloads every image. Market data has the same problem in reverse:
/// switching tabs refetches lists that changed by nothing.
///
/// Both are fixed by one properly sized cache plus honest per-request
/// policies. Nothing here caches anything a trader acts on: prices, books and
/// positions always go to the network.
public enum NetworkCache {

    /// 64 MB memory, 256 MB disk. Artwork dominates, and these sizes hold a
    /// few hundred images — enough that ordinary scrolling never refetches,
    /// while staying far below what iOS will evict under pressure.
    public static let shared: URLCache = {
        URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "pulse.network"
        )
    }()

    /// The session every service and `AsyncImage` should use.
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = shared
        configuration.requestCachePolicy = .useProtocolCachePolicy
        // A market list is worth waiting a few seconds for; a stuck request
        // is not. The resource timeout bounds retries as well as the request.
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        #if !canImport(FoundationNetworking)
        // Fail fast rather than hang when offline; the UI has an offline
        // state and a retry. Not settable on corelibs-foundation.
        configuration.waitsForConnectivity = false
        #endif
        // More than a handful of parallel requests to one host buys nothing
        // and makes rate limiting likelier.
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    /// Installs the cache on `URLSession.shared` too.
    ///
    /// SwiftUI's `AsyncImage` always uses the shared session and offers no
    /// way to pass another, so artwork only benefits if the shared cache
    /// itself is replaced. Call once at launch.
    public static func installSharedCache() {
        URLCache.shared = shared
    }

    /// How fresh a given kind of response has to be.
    public enum Freshness: Sendable {
        /// Prices, books, positions, orders. Never served from cache.
        case live
        /// Market lists and metadata. A few seconds of reuse makes tab
        /// switching instant without showing anything meaningfully stale.
        case list
        /// Descriptions, rules, tags — effectively static for a session.
        case reference

        var policy: URLRequest.CachePolicy {
            switch self {
            case .live: .reloadIgnoringLocalCacheData
            case .list, .reference: .useProtocolCachePolicy
            }
        }
    }
}
