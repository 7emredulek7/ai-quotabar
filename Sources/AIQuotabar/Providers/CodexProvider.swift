import Foundation

/// Codex logs its rate limits into every session file (`token_count` events),
/// so the latest event across recent sessions is the latest known usage.
enum CodexProvider {
    static let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")

    static func fetch() throws -> ProviderUsage {
        // The weekly window is 7 days, so older files can't hold anything useful.
        let files = recentSessionFiles(within: 8 * 24 * 3600)
        var best: (date: Date, limits: [String: Any])?

        // Files are newest first; a few are enough to find the latest event.
        for file in files.prefix(8) {
            guard let (date, limits) = lastRateLimits(in: file.url) else { continue }
            if best == nil || date > best!.date { best = (date, limits) }
        }
        guard let best else { throw ProviderError.noData }

        var usage = ProviderUsage(asOf: best.date, fromLogs: true)
        usage.plan = (best.limits["plan_type"] as? String)?.capitalized
        for key in ["primary", "secondary"] {
            guard let d = best.limits[key] as? [String: Any],
                  let used = d["used_percent"] as? Double else { continue }
            let resets = (d["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let minutes = d["window_minutes"] as? Double ?? 0
            usage.windows.append(UsageWindow(label: label(minutes: minutes), usedPercent: used, resetsAt: resets))
        }
        return usage
    }

    private static func label(minutes: Double) -> String {
        switch minutes {
        case 0: return "Limit"
        case ..<(24 * 60): return "\(Int((minutes / 60).rounded()))-hour"
        case (6 * 24 * 60)...(8 * 24 * 60): return "Weekly"
        default: return "\(Int((minutes / 1440).rounded()))-day"
        }
    }

    struct SessionFile {
        var url: URL
        var modified: Date
    }

    /// Session files under YYYY/MM/DD folders, newest first.
    static func recentSessionFiles(within seconds: TimeInterval) -> [SessionFile] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-seconds)
        var result: [SessionFile] = []
        let cal = Calendar.current
        let days = Int(seconds / 86400) + 1
        for offset in 0...days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = sessionsDir.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".jsonl") {
                let url = dir.appendingPathComponent(name)
                guard let mod = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                      mod >= cutoff else { continue }
                result.append(SessionFile(url: url, modified: mod))
            }
        }
        return result.sorted { $0.modified > $1.modified }
    }

    private static func lastRateLimits(in url: URL) -> (Date, [String: Any])? {
        for line in tailLines(of: url, bytes: 2 << 20).reversed() where line.contains("\"rate_limits\"") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any],
                  limits["primary"] is [String: Any] || limits["secondary"] is [String: Any]
            else { continue }
            let date = (obj["timestamp"] as? String).flatMap(parseISODate) ?? Date.distantPast
            return (date, limits)
        }
        return nil
    }

    /// The complete lines in the last `bytes` of a file.
    static func tailLines(of url: URL, bytes: Int) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if start > 0, !lines.isEmpty { lines.removeFirst() } // likely cut mid-line
        return lines
    }

    static func firstLine(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var buf = Data()
        while let chunk = try? h.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let nl = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                buf.append(chunk[chunk.startIndex..<nl])
                break
            }
            buf.append(chunk)
            if buf.count > 4 << 20 { break }
        }
        return String(data: buf, encoding: .utf8)
    }
}
