import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Errors

public enum APIError: Error, Sendable, Equatable {
    case invalidURL
    case transport(String)
    case http(status: Int, body: String?)
    case decoding(String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case cancelled
    case offline
    /// The server answered 200 but the payload signalled failure.
    case server(message: String)

    public var isRetryable: Bool {
        switch self {
        case .transport, .offline: true
        case .rateLimited: true
        case .http(let status, _): status >= 500 || status == 408 || status == 429
        default: false
        }
    }

    public var userMessage: String {
        switch self {
        case .invalidURL:
            "Couldn't build that request."
        case .transport:
            "Network problem. Check your connection and try again."
        case .offline:
            "You're offline."
        case .http(let status, _) where status == 404:
            "Not found."
        case .http(let status, _) where status >= 500:
            "Polymarket is having trouble right now. Try again shortly."
        case .http(let status, _):
            "Request failed (\(status))."
        case .decoding:
            "Received an unexpected response."
        case .unauthorized:
            "You need to sign in to do that."
        case .rateLimited:
            "Too many requests. Give it a moment."
        case .cancelled:
            "Cancelled."
        case .server(let message):
            message
        }
    }
}

// MARK: - Request building

public struct HTTPRequest: Sendable {
    public enum Method: String, Sendable {
        case get = "GET", post = "POST", delete = "DELETE", put = "PUT"
    }

    public var method: Method
    public var path: String
    public var query: [String: String?]
    public var body: Data?
    public var headers: [String: String]
    /// Set when the endpoint requires CLOB L2 authentication.
    public var requiresAuth: Bool
    /// How stale a cached response may be for this endpoint.
    public var freshness: NetworkCache.Freshness

    public init(
        method: Method = .get,
        path: String,
        query: [String: String?] = [:],
        body: Data? = nil,
        headers: [String: String] = [:],
        requiresAuth: Bool = false,
        freshness: NetworkCache.Freshness = .live
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.headers = headers
        self.requiresAuth = requiresAuth
        self.freshness = freshness
    }
}

/// Supplies L2 authentication headers for CLOB requests.
/// Implemented by `ClobAuthenticator`; injected so the HTTP layer never owns
/// secrets and so tests can run without any credentials.
public protocol RequestAuthorizing: Sendable {
    /// - Parameters:
    ///   - method: Uppercase HTTP method.
    ///   - path: Request path *without* query string, e.g. `/data/orders`.
    ///   - body: Exact serialized body bytes that will go on the wire, if any.
    func authorizationHeaders(
        method: String,
        path: String,
        body: Data?
    ) async throws -> [String: String]
}

// MARK: - Client

/// A small, dependency-free HTTP client built on `URLSession` with
/// retry-with-backoff, request coalescing-friendly cancellation, and a shared
/// JSON decoder.
public actor HTTPClient {
    private let baseURL: URL
    private let session: URLSession
    private let authorizer: RequestAuthorizing?
    private let maxRetries: Int

    public init(
        baseURL: URL,
        session: URLSession = NetworkCache.session,
        authorizer: RequestAuthorizing? = nil,
        maxRetries: Int = 2
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authorizer = authorizer
        self.maxRetries = maxRetries
    }

    public static let jsonDecoder: JSONDecoder = JSONDecoder()

    // MARK: Public API

    public func get<T: Decodable & Sendable>(
        _ path: String,
        query: [String: String?] = [:],
        as type: T.Type = T.self,
        requiresAuth: Bool = false,
        freshness: NetworkCache.Freshness = .live
    ) async throws -> T {
        try await send(
            HTTPRequest(
                path: path, query: query,
                requiresAuth: requiresAuth, freshness: freshness
            )
        )
    }

    public func send<T: Decodable & Sendable>(
        _ request: HTTPRequest,
        as type: T.Type = T.self
    ) async throws -> T {
        let data = try await data(for: request)
        do {
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
            throw APIError.decoding("\(type): \(error.localizedDescription). Body: \(preview)")
        }
    }

    /// Performs the request, retrying transient failures with exponential
    /// backoff and honouring `Retry-After` on 429.
    public func data(for request: HTTPRequest) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await performOnce(request)
            } catch let error as APIError {
                attempt += 1
                guard error.isRetryable, attempt <= maxRetries else { throw error }

                var delay = pow(2.0, Double(attempt - 1)) * 0.4
                if case .rateLimited(let retryAfter) = error, let retryAfter {
                    delay = retryAfter
                }
                // Jitter avoids a thundering herd when many cells refresh at once.
                delay += Double.random(in: 0...0.2)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try Task.checkCancellation()
            }
        }
    }

    // MARK: Internals

    private func performOnce(_ request: HTTPRequest) async throws -> Data {
        let urlRequest = try await buildURLRequest(request)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("Non-HTTP response")
            }

            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw APIError.unauthorized
            case 429:
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
                throw APIError.rateLimited(retryAfter: retryAfter)
            default:
                let body = String(data: data.prefix(400), encoding: .utf8)
                throw APIError.http(status: http.statusCode, body: body)
            }
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let urlError as URLError {
            switch urlError.code {
            case .cancelled: throw APIError.cancelled
            case .notConnectedToInternet, .dataNotAllowed: throw APIError.offline
            default: throw APIError.transport(urlError.localizedDescription)
            }
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func buildURLRequest(_ request: HTTPRequest) async throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(request.path.hasPrefix("/")
                ? String(request.path.dropFirst())
                : request.path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }

        let items = request.query
            .compactMap { key, value -> URLQueryItem? in
                guard let value, !value.isEmpty else { return nil }
                return URLQueryItem(name: key, value: value)
            }
            .sorted { $0.name < $1.name }
        if !items.isEmpty { components.queryItems = items }

        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url, cachePolicy: request.freshness.policy)
        req.httpMethod = request.method.rawValue
        req.httpBody = request.body
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in request.headers { req.setValue(v, forHTTPHeaderField: k) }

        if request.requiresAuth {
            guard let authorizer else { throw APIError.unauthorized }
            // The L2 signature covers the path only — never the query string.
            let path = components.path
            let headers = try await authorizer.authorizationHeaders(
                method: request.method.rawValue,
                path: path,
                body: request.body
            )
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        }

        return req
    }
}
