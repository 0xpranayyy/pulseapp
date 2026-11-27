import Foundation

// MARK: - Lenient scalar decoding
//
// Polymarket's Gamma API is inconsistent about whether a numeric field arrives
// as a JSON number or a JSON string. Verified against live responses on
// 2026-11-27: `event.liquidity` is a number while `market.liquidity` is the
// string "19722.914"; `market.volumeNum` is a number while `market.volume` is a
// string. Rather than guess per field, every numeric field we read goes through
// these helpers.

/// A `Double` that decodes from a JSON number, a JSON string, or a JSON bool.
/// Decodes to `nil` rather than throwing when the value is absent or unparseable,
/// so one malformed field never discards an otherwise good market.
public struct LenientDouble: Codable, Hashable, Sendable {
    public let value: Double?

    public init(_ value: Double?) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil; return }
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        value = nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}

/// An `Int` that decodes from a JSON number or string.
public struct LenientInt: Codable, Hashable, Sendable {
    public let value: Int?

    public init(_ value: Int?) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil; return }
        if let i = try? c.decode(Int.self) { value = i; return }
        if let d = try? c.decode(Double.self) { value = Int(d); return }
        if let s = try? c.decode(String.self) { value = Int(s) ?? Double(s).map(Int.init); return }
        value = nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}

/// A `Bool` that decodes from a JSON bool, string, or number.
public struct LenientBool: Codable, Hashable, Sendable {
    public let value: Bool?

    public init(_ value: Bool?) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil; return }
        if let b = try? c.decode(Bool.self) { value = b; return }
        if let s = try? c.decode(String.self) {
            switch s.lowercased() {
            case "true", "1", "yes": value = true
            case "false", "0", "no": value = false
            default: value = nil
            }
            return
        }
        if let i = try? c.decode(Int.self) { value = i != 0; return }
        value = nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}

/// A `[String]` that decodes either from a real JSON array **or** from a string
/// containing JSON, which is how Gamma returns `outcomes`, `outcomePrices` and
/// `clobTokenIds`:
///
/// ```json
/// "outcomes": "[\"Yes\", \"No\"]"
/// ```
public struct JSONStringArray: Codable, Hashable, Sendable {
    public let values: [String]

    public init(_ values: [String]) { self.values = values }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { values = []; return }

        // Real array of strings.
        if let arr = try? c.decode([String].self) { values = arr; return }

        // Real array of numbers (outcomePrices occasionally arrives this way).
        if let arr = try? c.decode([Double].self) {
            values = arr.map { Self.trimmedNumber($0) }
            return
        }

        // JSON encoded inside a string.
        if let raw = try? c.decode(String.self) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { values = []; return }
            if let data = trimmed.data(using: .utf8) {
                if let arr = try? JSONDecoder().decode([String].self, from: data) {
                    values = arr; return
                }
                if let arr = try? JSONDecoder().decode([Double].self, from: data) {
                    values = arr.map { Self.trimmedNumber($0) }; return
                }
            }
            values = []
            return
        }
        values = []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }

    /// Formats a double without a trailing `.0`, so round-tripping a price
    /// string like "0.5" does not become "0.5000000000000001".
    private static func trimmedNumber(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }

    public var doubles: [Double] { values.compactMap(Double.init) }
}

// MARK: - Dates

/// A value guarded by a lock. Used for the shared `DateFormatter`s below:
/// `DateFormatter` is not `Sendable`, and on Linux corelibs-foundation makes no
/// thread-safety promise even for read-only use, so every access is serialised.
/// The lock is held only for the duration of one parse, which is cheap relative
/// to the allocation a per-call formatter would cost.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

public enum PolyDate {
    /// Polymarket mixes ISO-8601 with and without fractional seconds, and
    /// sometimes sends a bare `yyyy-MM-dd` (e.g. `market.endDateIso`) or a
    /// Postgres timestamp (e.g. `tag.publishedAt`). Tries each in turn.
    public static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }

        if let d = isoFractional.withLock({ $0.date(from: string) }) { return d }
        if let d = isoPlain.withLock({ $0.date(from: string) }) { return d }
        if let d = dayOnly.withLock({ $0.date(from: string) }) { return d }
        if let d = postgres.withLock({ $0.date(from: string) }) { return d }
        return nil
    }

    private static let isoFractional = Locked<ISO8601DateFormatter>({
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }())

    private static let isoPlain = Locked<ISO8601DateFormatter>({
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }())

    private static let dayOnly = Locked<DateFormatter>({
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }())

    private static let postgres = Locked<DateFormatter>({
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        return f
    }())
}
