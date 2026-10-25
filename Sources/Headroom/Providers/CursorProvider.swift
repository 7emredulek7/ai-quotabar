import Foundation
import SQLite3

/// Cursor's dashboard usage, fetched with the session token the Cursor app
/// keeps in its local state database.
enum CursorProvider {
    static let dbPath = "\(homePath)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    private static let periodURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    private static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!

    static func fetch() async throws -> ProviderUsage {
        let stored = readState(keys: ["cursorAuth/accessToken", "cursorAuth/stripeMembershipType"])
        guard let token = stored["cursorAuth/accessToken"], !token.isEmpty else {
            throw ProviderError.noCredentials("Cursor'a giriş yapılmamış")
        }
        let claims = jwtClaims(token)
        if let exp = claims["exp"] as? Double, Date(timeIntervalSince1970: exp) < Date() {
            throw ProviderError.tokenExpired(app: "Cursor")
        }
        let plan = stored["cursorAuth/stripeMembershipType"].map { $0.replacingOccurrences(of: "_", with: " ").capitalized }

        // The current-period endpoint is what the dashboard uses today; the
        // older summary endpoint still answers for some plans.
        if let usage = try await currentPeriod(token: token) {
            return ProviderUsage(windows: [usage], plan: plan)
        }
        let userID = (claims["sub"] as? String)?.split(separator: "|").last.map(String.init) ?? ""
        return ProviderUsage(windows: [try await summary(token: token, userID: userID)], plan: plan)
    }

    private static func currentPeriod(token: String) async throws -> UsageWindow? {
        var req = URLRequest(url: periodURL, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.httpBody = Data("{}".utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw ProviderError.tokenExpired(app: "Cursor") }
        guard code == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plan = json["planUsage"] as? [String: Any],
              let used = parseLooseDouble(plan["totalPercentUsed"])
        else { return nil }
        return window(used: used, start: parseLooseDate(json["billingCycleStart"]), end: parseLooseDate(json["billingCycleEnd"]))
    }

    private static func summary(token: String, userID: String) async throws -> UsageWindow {
        var req = URLRequest(url: summaryURL, timeoutInterval: 15)
        req.setValue("WorkosCursorSessionToken=\(userID)%3A%3A\(token)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw ProviderError.tokenExpired(app: "Cursor") }
        guard code == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.http(code)
        }
        if json["error"] != nil { throw ProviderError.tokenExpired(app: "Cursor") }

        let plan = (json["individualUsage"] as? [String: Any])?["plan"] as? [String: Any] ?? [:]
        var used = parseLooseDouble(plan["totalPercentUsed"])
        if used == nil, let u = parseLooseDouble(plan["used"]), let l = parseLooseDouble(plan["limit"]), l > 0 {
            used = u / l * 100
        }
        guard let used else { throw ProviderError.noData }
        return window(used: used, start: parseLooseDate(json["billingCycleStart"]), end: parseLooseDate(json["billingCycleEnd"]))
    }

    private static func window(used: Double, start: Date?, end: Date?) -> UsageWindow {
        var label = "Fatura dönemi"
        if let start, let end {
            label = end.timeIntervalSince(start) <= 8 * 86400 ? "Haftalık" : "Aylık"
        }
        return UsageWindow(label: label, usedPercent: used, resetsAt: end)
    }

    // MARK: Local state

    private static func readState(keys: [String]) -> [String: String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_close(db) }

        var result: [String: String] = [:]
        for key in keys {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) {
                result[key] = String(cString: text)
            }
        }
        return result
    }

    private static func jwtClaims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }
}
