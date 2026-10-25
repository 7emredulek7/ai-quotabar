import Foundation

/// Antigravity exposes model quotas through its local language server, which
/// only runs while the app is open. The server listens on random loopback
/// ports with a self-signed certificate and wants the CSRF token from its
/// command line.
enum AntigravityProvider {
    private static let method = "/exa.language_server_pb.LanguageServerService/GetUserStatus"
    private static let session = URLSession(configuration: .ephemeral, delegate: LoopbackTrust(), delegateQueue: nil)

    static func fetch() async throws -> ProviderUsage {
        guard let server = findServer() else { throw ProviderError.notRunning(app: "Antigravity") }

        for port in server.ports {
            for scheme in ["https", "http"] {
                guard let json = await request("\(scheme)://127.0.0.1:\(port)\(method)", csrf: server.csrf) else { continue }
                return try parse(json)
            }
        }
        throw ProviderError.notRunning(app: "Antigravity")
    }

    private static func parse(_ json: [String: Any]) throws -> ProviderUsage {
        guard let status = json["userStatus"] as? [String: Any] else { throw ProviderError.noData }
        let plan = ((status["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any])?["planName"] as? String
        let configs = ((status["cascadeModelConfigData"] as? [String: Any])?["clientModelConfigs"] as? [[String: Any]]) ?? []

        // Many models share one quota; collapse them into the two groups the
        // app itself shows, keeping the tightest remaining value per group.
        var groups: [String: UsageWindow] = [:]
        for config in configs {
            // Models the plan doesn't include come back disabled with an empty quota.
            guard config["disabled"] as? Bool != true,
                  let quota = config["quotaInfo"] as? [String: Any], !quota.isEmpty else { continue }
            let label = config["label"] as? String ?? ""
            let group = label.localizedCaseInsensitiveContains("gemini") ? "Gemini" : "Claude + GPT"
            // Protobuf JSON omits zero values, so a missing fraction means none left.
            let remaining = (parseLooseDouble(quota["remainingFraction"]) ?? 0) * 100
            let reset = parseLooseDate(quota["resetTime"])
            let w = UsageWindow(label: group, usedPercent: 100 - remaining, resetsAt: reset)
            if let existing = groups[group], existing.usedPercent >= w.usedPercent { continue }
            groups[group] = w
        }
        let windows = ["Gemini", "Claude + GPT"].compactMap { groups[$0] }
        if windows.isEmpty { throw ProviderError.noData }
        return ProviderUsage(windows: windows, plan: plan)
    }

    private static func request(_ url: String, csrf: String) async -> [String: Any]? {
        guard let url = URL(string: url) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 4)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        req.httpBody = Data(#"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en","ideVersion":"unknown"}}"#.utf8)

        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: Process discovery

    private struct Server {
        var csrf: String
        var ports: [Int]
    }

    private static func findServer() -> Server? {
        guard let out = Shell.run("/bin/ps", ["-axo", "pid=,command="]) else { return nil }
        for line in String(decoding: out, as: UTF8.self).split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.contains("language_server"), text.contains("--app_data_dir antigravity"),
                  let pid = Int32(text.prefix { $0.isNumber }),
                  let csrf = argument("--csrf_token", in: text)
            else { continue }

            var ports = listeningPorts(pid: pid)
            if let ext = argument("--extension_server_port", in: text).flatMap(Int.init), !ports.contains(ext) {
                ports.append(ext)
            }
            return Server(csrf: csrf, ports: ports)
        }
        return nil
    }

    private static func argument(_ flag: String, in command: String) -> String? {
        guard let range = command.range(of: flag + " ") ?? command.range(of: flag + "=") else { return nil }
        let value = command[range.upperBound...].prefix { $0 != " " }
        return value.isEmpty ? nil : String(value)
    }

    private static func listeningPorts(pid: Int32) -> [Int] {
        guard let out = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "\(pid)", "-Fn"]) else { return [] }
        var ports: [Int] = []
        for line in String(decoding: out, as: UTF8.self).split(separator: "\n") where line.hasPrefix("n") {
            if let port = line.split(separator: ":").last.flatMap({ Int($0) }), !ports.contains(port) {
                ports.append(port)
            }
        }
        return ports
    }
}

/// Accepts the language server's self-signed certificate, for loopback only.
private final class LoopbackTrust: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           space.host == "127.0.0.1", let trust = space.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}
