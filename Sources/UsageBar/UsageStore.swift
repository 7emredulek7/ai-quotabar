import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    var claude: ProviderUsage?
    var claudeError: String?
    var codex: ProviderUsage?
    var codexError: String?
    var agents: [Agent] = []
    var isRefreshing = false
    var lastRefresh: Date?

    // The usage endpoint is rate limited; a few minutes is plenty for limits
    // that move over hours. Agents are local files, so they can poll faster.
    private let usageInterval: TimeInterval = 180
    private let agentInterval: TimeInterval = 5
    private var timers: [Timer] = []

    init() {
        Task { await refreshUsage() }
        refreshAgents()
        timers = [
            Timer.scheduledTimer(withTimeInterval: usageInterval, repeats: true) { [weak self] _ in
                Task { await self?.refreshUsage() }
            },
            Timer.scheduledTimer(withTimeInterval: agentInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshAgents() }
            },
        ]
    }

    func refreshUsage() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }

        let claudeTask = Task.detached { () -> Result<ProviderUsage, Error> in
            do { return .success(try await ClaudeProvider.fetch()) } catch { return .failure(error) }
        }
        let codexTask = Task.detached { Result { try CodexProvider.fetch() } }

        switch await claudeTask.value {
        case .success(let u): claude = u; claudeError = nil
        // Keep showing the last good numbers when a refresh fails.
        case .failure(let e): claudeError = e.localizedDescription
        }
        switch await codexTask.value {
        case .success(let u): codex = u; codexError = nil
        case .failure(let e): codexError = e.localizedDescription
        }
        refreshAgents()
    }

    func refreshAgents() {
        Task {
            let found = await Task.detached { AgentScanner.scan() }.value
            if found != agents { agents = found }
        }
    }

    var workingCount: Int { agents.filter { $0.status == .working }.count }
}
