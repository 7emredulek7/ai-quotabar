import ServiceManagement
import SwiftUI

struct MenuView: View {
    let store: UsageStore
    @AppStorage("showRemaining") private var showRemaining = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 14) {
                header(now: context.date)
                ProviderSection(tool: .claude, usage: store.claude, error: store.claudeError,
                                isLive: true, showRemaining: showRemaining, now: context.date)
                Divider()
                ProviderSection(tool: .codex, usage: store.codex, error: store.codexError,
                                isLive: false, showRemaining: showRemaining, now: context.date)
                Divider()
                AgentsSection(agents: store.agents, now: context.date)
                Divider()
                footer
            }
            .padding(14)
            .frame(width: 340)
        }
    }

    private func header(now: Date) -> some View {
        HStack {
            Text("Kullanım").font(.headline)
            Spacer()
            if let last = store.lastRefresh {
                Text(relative(last, now: now)).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await store.refreshUsage() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 180 : 0))
                    .animation(.easeInOut, value: store.isRefreshing)
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("Yenile")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Göster", selection: $showRemaining) {
                Text("Kalan").tag(true)
                Text("Kullanılan").tag(false)
            }
            .pickerStyle(.segmented)
            HStack {
                Toggle("Girişte başlat", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Spacer()
                Button("Çıkış") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .font(.callout)
        }
    }
}

// MARK: - Usage

struct ProviderSection: View {
    let tool: Tool
    let usage: ProviderUsage?
    let error: String?
    /// Claude numbers come straight from the API; Codex numbers come from its
    /// logs, so their age is worth showing.
    let isLive: Bool
    let showRemaining: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(tool.rawValue).font(.subheadline.weight(.semibold))
                if let plan = usage?.plan {
                    Text(plan)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if !isLive, let asOf = usage?.asOf {
                    Text("son veri \(relative(asOf, now: now))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let usage {
                WindowRow(title: "5 saatlik", window: normalized(usage.fiveHour, now: now),
                          showRemaining: showRemaining, now: now)
                WindowRow(title: "Haftalık", window: normalized(usage.weekly, now: now),
                          showRemaining: showRemaining, now: now)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if usage == nil {
                ProgressView().controlSize(.small)
            }
        }
    }
}

struct WindowRow: View {
    let title: String
    let window: UsageWindow?
    let showRemaining: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                if let w = window {
                    Text(showRemaining ? "%\(Int(w.remainingPercent.rounded())) kaldı" : "%\(Int(w.usedPercent.rounded())) kullanıldı")
                        .font(.callout.monospacedDigit().weight(.medium))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(window?.usedPercent ?? 0, 100), total: 100)
                .tint(color(for: window?.usedPercent ?? 0))
            Text(resetText)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var resetText: String {
        guard let reset = window?.resetsAt else { return "Yenilenme zamanı bilinmiyor" }
        return "\(countdown(to: reset, now: now)) sonra yenilenir · \(absolute(reset, now: now))"
    }

    private func color(for used: Double) -> Color {
        used >= 85 ? .red : used >= 60 ? .orange : .green
    }
}

// MARK: - Agents

struct AgentsSection: View {
    let agents: [Agent]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Agent'lar").font(.subheadline.weight(.semibold))
                Spacer()
                let working = agents.filter { $0.status == .working }.count
                Text("\(working) çalışıyor · \(agents.count - working) boşta")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if agents.isEmpty {
                Text("Açık oturum yok").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(agents) { AgentRow(agent: $0, now: now) }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }
}

struct AgentRow: View {
    let agent: Agent
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(agent.status == .working ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(agent.tool.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(agent.tool == .claude ? Color.orange : Color.blue)
                    Text(agent.title).font(.callout).lineLimit(1)
                }
                HStack(spacing: 4) {
                    if let cwd = agent.cwd {
                        Text((cwd as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.head)
                    }
                    if agent.status == .idle, let last = agent.lastActivity {
                        Text("· \(relative(last, now: now))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .help(agent.cwd ?? agent.title)
    }
}

// MARK: - Formatting

func countdown(to date: Date, now: Date) -> String {
    let secs = max(0, Int(date.timeIntervalSince(now)))
    let d = secs / 86400, h = secs % 86400 / 3600, m = secs % 3600 / 60
    if d > 0 { return "\(d) g \(h) sa" }
    if h > 0 { return "\(h) sa \(m) dk" }
    return "\(max(m, 1)) dk"
}

func absolute(_ date: Date, now: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "'bugün' HH:mm" : "d MMM EEE HH:mm"
    return f.string(from: date)
}

func relative(_ date: Date, now: Date) -> String {
    let secs = Int(now.timeIntervalSince(date))
    if secs < 60 { return "az önce" }
    if secs < 3600 { return "\(secs / 60) dk önce" }
    if secs < 86400 { return "\(secs / 3600) sa önce" }
    return "\(secs / 86400) g önce"
}
