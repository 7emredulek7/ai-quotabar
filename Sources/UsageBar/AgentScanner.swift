import Darwin
import Foundation

enum AgentScanner {
    static func scan() -> [Agent] {
        (claudeAgents() + codexAgents()).sorted {
            if $0.status != $1.status { return $0.status == .working }
            return ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
        }
    }

    // MARK: Claude

    /// Every running Claude Code process keeps `~/.claude/sessions/<pid>.json`
    /// up to date with its name, folder and busy/idle status.
    static func claudeAgents() -> [Agent] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }

        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = d["pid"] as? Int32, isAlive(pid)
            else { return nil }

            let cwd = d["cwd"] as? String
            let updated = ((d["statusUpdatedAt"] ?? d["updatedAt"]) as? Double)
                .map { Date(timeIntervalSince1970: $0 / 1000) }
            return Agent(
                id: "claude-\(pid)",
                tool: .claude,
                title: (d["name"] as? String) ?? cwd.map { ($0 as NSString).lastPathComponent } ?? "Claude Code",
                cwd: cwd,
                status: (d["status"] as? String) == "busy" ? .working : .idle,
                lastActivity: updated
            )
        }
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: Codex

    /// Codex has no live session registry, so recently written session logs
    /// stand in for it: a session whose last turn hasn't completed is working.
    static func codexAgents() -> [Agent] {
        let recent = CodexProvider.recentSessionFiles(within: 30 * 60)
        guard !recent.isEmpty else { return [] }
        let names = codexThreadNames()

        return recent.compactMap { file in
            guard let first = CodexProvider.firstLine(of: file.url),
                  let meta = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any],
                  let payload = meta["payload"] as? [String: Any]
            else { return nil }

            // Spawned sub-agents get their own files and are worth listing;
            // internal helpers (e.g. the "guardian" reviewer) are not.
            var subagentName: String?
            if let sub = (payload["source"] as? [String: Any])?["subagent"] as? [String: Any] {
                guard let spawn = sub["thread_spawn"] as? [String: Any] else { return nil }
                subagentName = (spawn["agent_nickname"] as? String)
                    ?? (spawn["agent_path"] as? String).map { ($0 as NSString).lastPathComponent }
            }

            let id = payload["id"] as? String ?? file.url.lastPathComponent
            let cwd = payload["cwd"] as? String
            let finished = lastTurnFinished(file.url)
            let stale = Date().timeIntervalSince(file.modified) > 5 * 60
            return Agent(
                id: "codex-\(id)",
                tool: .codex,
                title: names[id] ?? subagentName.map { "↳ \($0)" }
                    ?? cwd.map { ($0 as NSString).lastPathComponent } ?? "Codex",
                cwd: cwd,
                status: finished || stale ? .idle : .working,
                lastActivity: file.modified
            )
        }
    }

    private static func lastTurnFinished(_ url: URL) -> Bool {
        for line in CodexProvider.tailLines(of: url, bytes: 256 << 10).reversed() {
            guard line.contains("\"event_msg\""),
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = (obj["payload"] as? [String: Any])?["type"] as? String
            else { continue }
            switch type {
            case "task_complete", "turn_aborted", "shutdown_complete": return true
            case "task_started", "user_message", "agent_message", "agent_reasoning", "exec_command_begin": return false
            default: continue
            }
        }
        return false
    }

    /// Latest thread title per session id from `session_index.jsonl`.
    private static func codexThreadNames() -> [String: String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/session_index.jsonl")
        var names: [String: String] = [:]
        for line in CodexProvider.tailLines(of: url, bytes: 512 << 10) {
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = d["id"] as? String, let name = d["thread_name"] as? String else { continue }
            names[id] = name
        }
        return names
    }
}
