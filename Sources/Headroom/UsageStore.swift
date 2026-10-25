import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    struct Entry: Equatable {
        var usage: ProviderUsage?
        var error: String?
    }

    private(set) var enabled: [ProviderID] = ProviderID.allCases.filter(ProviderSettings.isEnabled)
    private(set) var entries: [ProviderID: Entry] = [:]
    private(set) var agents: [Agent] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?

    /// Minutes between usage fetches; the limits move over hours, and some
    /// endpoints rate limit, so this stays in minutes.
    static let refreshChoices = [1, 3, 5, 10]
    var refreshMinutes: Int {
        get { access(keyPath: \.refreshMinutes); return UserDefaults.standard.object(forKey: "refreshMinutes") as? Int ?? 3 }
        set { withMutation(keyPath: \.refreshMinutes) { UserDefaults.standard.set(newValue, forKey: "refreshMinutes") } }
    }

    private var timers: [Timer] = []

    init() {
        Task { await refreshUsage() }
        refreshAgents()
        timers = [
            // Ticks often but only fetches once the chosen interval has passed.
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let due = self.lastRefresh.map { Date().timeIntervalSince($0) >= Double(self.refreshMinutes * 60) - 1 } ?? true
                    if due { await self.refreshUsage() }
                }
            },
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshAgents() }
            },
        ]
    }

    func isEnabled(_ p: ProviderID) -> Bool { enabled.contains(p) }

    func setEnabled(_ p: ProviderID, _ on: Bool) {
        ProviderSettings.setEnabled(p, on)
        enabled = ProviderID.allCases.filter(ProviderSettings.isEnabled)
        if on {
            Task { await refresh(p) }
        } else {
            entries[p] = nil
        }
        refreshAgents()
    }

    func refreshUsage() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }

        await withTaskGroup(of: Void.self) { group in
            for p in enabled {
                group.addTask { await self.refresh(p) }
            }
        }
        refreshAgents()
    }

    private func refresh(_ p: ProviderID) async {
        let result = await Task.detached { () -> Result<ProviderUsage, Error> in
            do { return .success(try await p.fetch()) } catch { return .failure(error) }
        }.value
        guard enabled.contains(p) else { return }
        var entry = entries[p] ?? Entry()
        switch result {
        case .success(let u): entry = Entry(usage: u, error: nil)
        // Keep showing the last good numbers when a refresh fails.
        case .failure(let e): entry.error = e.localizedDescription
        }
        entries[p] = entry
    }

    func refreshAgents() {
        let on = Set(enabled)
        Task {
            let found = await Task.detached { AgentScanner.scan(enabled: on) }.value
            if found != agents { agents = found }
        }
    }

    var workingCount: Int { agents.filter { $0.status == .working }.count }
}
