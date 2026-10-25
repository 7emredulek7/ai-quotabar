import Foundation

/// Reads Claude Code's OAuth token and asks the usage endpoint for the
/// 5-hour and weekly utilization. The token is never refreshed here, so this
/// cannot interfere with Claude Code's own login.
enum ClaudeProvider {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private struct Credentials {
        var accessToken: String
        var expiresAt: Date?
        var plan: String?
    }

    static func fetch() async throws -> ProviderUsage {
        let creds = try readCredentials()
        if let exp = creds.expiresAt, exp < Date() { throw ProviderError.tokenExpired(app: "Claude Code") }

        var req = URLRequest(url: usageURL, timeoutInterval: 15)
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("Headroom/1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 401, 403: throw ProviderError.tokenExpired(app: "Claude Code")
        case 429: throw ProviderError.rateLimited
        default: throw ProviderError.http(code)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let windows = [
            window("5-hour", json["five_hour"]),
            window("Weekly", json["seven_day"]),
            window("Weekly · Opus", json["seven_day_opus"]),
            window("Weekly · Sonnet", json["seven_day_sonnet"]),
        ].compactMap { $0 }
        return ProviderUsage(windows: windows, plan: creds.plan?.capitalized)
    }

    private static func window(_ label: String, _ any: Any?) -> UsageWindow? {
        guard let d = any as? [String: Any], let used = d["utilization"] as? Double else { return nil }
        return UsageWindow(label: label, usedPercent: used, resetsAt: (d["resets_at"] as? String).flatMap(parseISODate))
    }

    private static func readCredentials() throws -> Credentials {
        // Shelling out to `security` keeps keychain access stable across
        // rebuilds; a direct SecItem call would re-prompt for every new binary.
        let data = Shell.run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
            ?? (try? Data(contentsOf: URL(fileURLWithPath: "\(homePath)/.claude/.credentials.json")))
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw ProviderError.noCredentials("Not signed in to Claude Code") }

        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(accessToken: token, expiresAt: expiresAt, plan: oauth["subscriptionType"] as? String)
    }
}
