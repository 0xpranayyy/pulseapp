import Foundation

/// Display formatting.
///
/// Centralised so money, probabilities and times read identically everywhere.
/// Formatters are cached: constructing a `NumberFormatter` per row is a
/// measurable cost in a scrolling list.
public enum Format {

    // MARK: Currency

    /// `$1,234.56`. Exact cents — used wherever the figure is the user's own
    /// money and rounding would be misleading.
    public static func currency(_ value: Double, showSign: Bool = false) -> String {
        let formatted = currencyFormatter.string(from: NSNumber(value: abs(value)))
            ?? String(format: "$%.2f", abs(value))
        if showSign && value != 0 {
            return (value > 0 ? "+" : "−") + formatted
        }
        return value < 0 ? "−" + formatted : formatted
    }

    /// `$1.2M`, `$24.5K`. For volume and liquidity, where magnitude matters
    /// more than precision and the exact figure would be noise.
    public static func compactCurrency(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let magnitude = abs(value)
        let sign = value < 0 ? "−" : ""

        switch magnitude {
        case 1_000_000_000...:
            return "\(sign)$\(trim(magnitude / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)$\(trim(magnitude / 1_000_000))M"
        case 1_000...:
            return "\(sign)$\(trim(magnitude / 1_000))K"
        default:
            return "\(sign)$\(Int(magnitude.rounded()))"
        }
    }

    /// One decimal unless it would be `.0`.
    private static func trim(_ value: Double) -> String {
        value >= 100 || value == value.rounded()
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }

    // MARK: Probability

    /// `67%`. The standard way a market price is shown.
    public static func probability(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let percent = value * 100
        // Never round a live market to a flat 0% or 100%: those are
        // resolution values, and showing them on an open market is wrong.
        if percent > 0, percent < 1 { return "<1%" }
        if percent < 100, percent > 99 { return ">99%" }
        return "\(Int(percent.rounded()))%"
    }

    /// `67.3%` where a single point matters, as on the trade sheet.
    public static func preciseProbability(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f%%", value * 100)
    }

    /// A raw market price in cents: `67¢`.
    public static func cents(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int((value * 100).rounded()))¢"
    }

    /// `+4` / `−2` probability points. Deliberately *points*, not percent:
    /// a move from 50% to 54% is 4 points, not a 4% change.
    public static func probabilityChange(_ value: Double?) -> String {
        guard let value, value.isFinite, abs(value) >= 0.0001 else { return "—" }
        let points = value * 100
        let sign = points > 0 ? "+" : "−"
        return abs(points) < 1
            ? "\(sign)\(String(format: "%.1f", abs(points)))"
            : "\(sign)\(Int(abs(points).rounded()))"
    }

    /// `+12.4%` for returns on money.
    public static func percentChange(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let percent = value * 100
        let sign = percent > 0 ? "+" : (percent < 0 ? "−" : "")
        return "\(sign)\(String(format: "%.1f", abs(percent)))%"
    }

    // MARK: Shares

    /// Share counts: whole numbers when whole, two decimals otherwise.
    public static func shares(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value == value.rounded(), abs(value) < 1e9 {
            return sharesFormatter.string(from: NSNumber(value: value)) ?? String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    // MARK: Time

    /// `3d left`, `4h left`, `12m left`, `Closed`.
    public static func timeRemaining(until date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Closed" }

        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let days = hours / 24

        if days >= 365 { return "\(days / 365)y left" }
        if days >= 30 { return "\(days / 30)mo left" }
        if days >= 1 { return "\(days)d left" }
        if hours >= 1 { return "\(hours)h left" }
        if minutes >= 1 { return "\(minutes)m left" }
        return "Closing"
    }

    /// `2m ago`, `3h ago`, `Nov 14`.
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        return mediumDate.string(from: date)
    }

    /// `14 Nov 2026`.
    public static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return mediumDate.string(from: date)
    }

    /// `14 Nov, 16:30`.
    public static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateTimeFormatter.string(from: date)
    }

    // MARK: Cached formatters

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        // Pinned to en_US so the symbol is always "$". Polymarket settles in
        // USDC, and the device's locale deciding between "$", "US$" and
        // "1.234,56 $" makes the same balance look like different currencies
        // to different users.
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    private static let sharesFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()
}
