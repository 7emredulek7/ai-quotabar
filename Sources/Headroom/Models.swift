import Foundation

/// One rate-limit window (5-hour, weekly, monthly, a model group...).
struct UsageWindow: Equatable, Identifiable {
    var label: String
    var usedPercent: Double
    var resetsAt: Date?
    var unlimited = false
    /// Extra detail shown under the bar, e.g. "120/300".
    var note: String?

    var id: String { label }
    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

struct ProviderUsage: Equatable {
    var windows: [UsageWindow] = []
    var plan: String?
    /// When the numbers were produced. For log-based providers this is the
    /// time of the last logged event, which can be older than the fetch time.
    var asOf = Date()
    var fromLogs = false
}

struct Agent: Identifiable, Equatable {
    enum Status { case working, idle }

    var id: String
    var provider: ProviderID
    var title: String
    var cwd: String?
    var status: Status
    var lastActivity: Date?
}

enum ProviderError: LocalizedError {
    case noCredentials(String)
    case tokenExpired(app: String)
    case notRunning(app: String)
    case rateLimited
    case http(Int)
    case noData
    case unsupported

    var errorDescription: String? {
        switch self {
        case .noCredentials(let hint): return hint
        case .tokenExpired(let app): return "Session expired, open \(app) once to refresh it"
        case .notRunning(let app): return "\(app) isn't running; open it to see quotas"
        case .rateLimited: return "Rate limited, will retry shortly"
        case .http(let code): return "Server error (\(code))"
        case .noData: return "No data yet"
        case .unsupported: return "Usage data not available yet"
        }
    }
}

/// Reset windows that already passed mean the counter is back to zero.
func normalized(_ window: UsageWindow, now: Date = Date()) -> UsageWindow {
    var w = window
    if let r = w.resetsAt, r < now {
        w.usedPercent = 0
        w.resetsAt = nil
    }
    return w
}

/// Parses ISO-8601 timestamps with any number of fractional digits.
func parseISODate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return f.date(from: trimmed)
}

/// Dates in JSON come as ISO strings, epoch seconds or epoch milliseconds
/// (sometimes as strings, since protobuf JSON encodes int64 that way).
func parseLooseDate(_ any: Any?) -> Date? {
    if let s = any as? String {
        if let n = Double(s) { return parseLooseDate(n) }
        return parseISODate(s)
    }
    if let n = any as? Double, n > 0 {
        return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
    }
    return nil
}

func parseLooseDouble(_ any: Any?) -> Double? {
    if let n = any as? Double { return n }
    if let s = any as? String { return Double(s) }
    return nil
}
