import Foundation

/// GitHub's Copilot entitlement endpoint (the one the editors use), called
/// with the GitHub CLI's token. Quotas are monthly.
enum CopilotProvider {
    private static let url = URL(string: "https://api.github.com/copilot_internal/user")!

    static func fetch() async throws -> ProviderUsage {
        guard let token = githubToken() else {
            throw ProviderError.noCredentials("Sign in to GitHub with `gh auth login`")
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Headroom/1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 401: throw ProviderError.noCredentials("GitHub session invalid, run `gh auth login`")
        case 403, 404: throw ProviderError.noCredentials("This GitHub account has no Copilot access")
        default: throw ProviderError.http(code)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let reset = parseLooseDate(json["quota_reset_date_utc"] ?? json["quota_reset_date"])
        let snapshots = json["quota_snapshots"] as? [String: Any] ?? [:]

        var windows: [UsageWindow] = []
        for (key, label) in [("premium_interactions", "Premium requests"), ("chat", "Chat"), ("completions", "Completions")] {
            guard let s = snapshots[key] as? [String: Any] else { continue }
            let unlimited = s["unlimited"] as? Bool ?? false
            // Chat and completions are unlimited on every paid plan; only
            // worth a row when they are actually metered.
            if unlimited && key != "premium_interactions" { continue }

            if unlimited {
                let credits = parseLooseDouble(s["credits_used"]) ?? 0
                windows.append(UsageWindow(label: label, usedPercent: 0, resetsAt: reset, unlimited: true,
                                           note: credits > 0 ? "\(Int(credits)) credits used" : nil))
            } else {
                let remaining = parseLooseDouble(s["percent_remaining"]) ?? 100
                let entitlement = parseLooseDouble(s["entitlement"]) ?? 0
                let left = parseLooseDouble(s["remaining"]) ?? 0
                windows.append(UsageWindow(label: label, usedPercent: 100 - remaining, resetsAt: reset,
                                           note: entitlement > 0 ? "\(Int(entitlement - left))/\(Int(entitlement)) used" : nil))
            }
        }
        if windows.isEmpty { throw ProviderError.noData }

        let plan = (json["copilot_plan"] as? String)?.replacingOccurrences(of: "_", with: " ").capitalized
        return ProviderUsage(windows: windows, plan: plan)
    }

    private static func githubToken() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let t = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"], !t.isEmpty { return t }
        guard let gh = Shell.find("gh"), let out = Shell.run(gh, ["auth", "token"]) else { return nil }
        let token = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
