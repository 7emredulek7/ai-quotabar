import Foundation

/// One rate-limit window (5-hour or weekly).
struct UsageWindow: Equatable {
    var usedPercent: Double
    var resetsAt: Date?

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

struct ProviderUsage: Equatable {
    var fiveHour: UsageWindow?
    var weekly: UsageWindow?
    var plan: String?
    /// When the numbers were produced. For Codex this is the time of the last
    /// logged event, which can be older than the fetch time.
    var asOf: Date
}

enum Tool: String {
    case claude = "Claude"
    case codex = "Codex"
}

struct Agent: Identifiable, Equatable {
    enum Status { case working, idle }

    var id: String
    var tool: Tool
    var title: String
    var cwd: String?
    var status: Status
    var lastActivity: Date?
}

enum ProviderError: LocalizedError {
    case noCredentials
    case tokenExpired
    case rateLimited
    case http(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "Giriş bilgisi bulunamadı"
        case .tokenExpired: return "Oturum süresi dolmuş, Claude Code'u bir kez açın"
        case .rateLimited: return "Çok sık istek, birazdan tekrar denenecek"
        case .http(let code): return "Sunucu hatası (\(code))"
        case .noData: return "Henüz veri yok"
        }
    }
}

/// Reset windows that already passed mean the counter is back to zero.
func normalized(_ window: UsageWindow?, now: Date = Date()) -> UsageWindow? {
    guard var w = window else { return nil }
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
