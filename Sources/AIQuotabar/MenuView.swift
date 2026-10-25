import ServiceManagement
import SwiftUI

/// The popover: usage overview, with settings swapped in place.
struct MenuView: View {
    let store: UsageStore
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(store: store) { showingSettings = false }
            } else {
                OverviewView(store: store) { showingSettings = true }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

// MARK: - Overview

struct OverviewView: View {
    let store: UsageStore
    let openSettings: () -> Void
    @AppStorage("showRemaining") private var showRemaining = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 14) {
                header(now: context.date)

                if store.enabled.isEmpty {
                    Text("No providers enabled. Turn some on in Settings.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(store.enabled) { p in
                    ProviderSection(provider: p, entry: store.entries[p], showRemaining: showRemaining, now: context.date)
                    Divider()
                }

                if store.isEnabled(.claude) || store.isEnabled(.codex) {
                    AgentsSection(agents: store.agents, now: context.date)
                    Divider()
                }
                footer
            }
        }
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 8) {
            Text("AI Quotabar").font(.system(size: 15, weight: .semibold))
            Spacer()
            if let last = store.lastRefresh {
                Text(relative(last, now: now)).font(.caption).foregroundStyle(.secondary)
            }
            IconButton(systemName: "arrow.clockwise", label: "Refresh") {
                Task { await store.refreshUsage() }
            }
            .disabled(store.isRefreshing)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Picker("Show", selection: $showRemaining) {
                Text("Remaining").tag(true)
                Text("Used").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            Spacer()
            Button("Settings…", action: openSettings)
                .buttonStyle(.borderless)
                .keyboardShortcut(",")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .font(.callout)
        .foregroundStyle(.primary)
    }
}

struct ProviderSection: View {
    let provider: ProviderID
    let entry: UsageStore.Entry?
    let showRemaining: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderIcon(provider: provider, size: 22)
                Text(provider.name).font(.system(size: 14, weight: .semibold))
                if let plan = entry?.usage?.plan {
                    Text(plan)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                Spacer()
                if let usage = entry?.usage, usage.fromLogs {
                    Text("as of \(relative(usage.asOf, now: now))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            ForEach(entry?.usage?.windows ?? []) { w in
                WindowRow(provider: provider, window: normalized(w, now: now), showRemaining: showRemaining, now: now)
            }

            if let error = entry?.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if entry == nil {
                ProgressView().controlSize(.small)
            }
        }
    }
}

struct WindowRow: View {
    let provider: ProviderID
    let window: UsageWindow
    let showRemaining: Bool
    let now: Date

    /// Below this much headroom the row turns red.
    private var isLow: Bool { !window.unlimited && window.remainingPercent < 15 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.label).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isLow ? Color.low : Color.primary)
            }
            if !window.unlimited {
                Bar(fraction: (showRemaining ? window.remainingPercent : window.usedPercent) / 100,
                    tint: isLow ? .low : provider.tint)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var valueText: String {
        if window.unlimited { return "Unlimited" }
        return showRemaining
            ? "\(Int(window.remainingPercent.rounded()))% left"
            : "\(Int(window.usedPercent.rounded()))% used"
    }

    private var caption: String {
        var parts: [String] = []
        if let note = window.note { parts.append(note) }
        if let reset = window.resetsAt {
            parts.append(window.unlimited
                ? "resets \(absolute(reset, now: now))"
                : "resets in \(countdown(to: reset, now: now)) · \(absolute(reset, now: now))")
        } else if parts.isEmpty {
            parts.append("Reset time unknown")
        }
        return parts.joined(separator: " · ")
    }
}

struct Bar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

// MARK: - Agents

struct AgentsSection: View {
    let agents: [Agent]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agents").font(.system(size: 14, weight: .semibold))
                Spacer()
                let working = agents.filter { $0.status == .working }.count
                Text("\(working) working · \(agents.count - working) idle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if agents.isEmpty {
                Text("No open sessions").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(agents) { AgentRow(agent: $0, now: now) }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 200)
                .fixedSize(horizontal: false, vertical: agents.count <= 4)
            }
        }
    }
}

struct AgentRow: View {
    let agent: Agent
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(agent.status == .working ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(agent.provider == .claude ? "CLAUDE" : "CODEX")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(agent.provider.tint)
                    Text(agent.title).font(.system(size: 13)).lineLimit(1)
                }
                HStack(spacing: 4) {
                    if let cwd = agent.cwd {
                        Text((cwd as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.head)
                    }
                    if agent.status == .idle, let last = agent.lastActivity {
                        Text("· \(relative(last, now: now))").fixedSize()
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .help(agent.cwd ?? agent.title)
    }
}

// MARK: - Settings

struct SettingsView: View {
    let store: UsageStore
    let close: () -> Void
    @AppStorage("showRemaining") private var showRemaining = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                IconButton(systemName: "chevron.left", label: "Back", action: close)
                    .keyboardShortcut(.cancelAction)
                Text("Settings").font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Providers")
                ForEach(Array(ProviderID.allCases.enumerated()), id: \.element) { index, p in
                    providerRow(p)
                    if index < ProviderID.allCases.count - 1 { Divider() }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Menu bar")
                HStack {
                    Text("Show")
                    Spacer()
                    Picker("Show", selection: $showRemaining) {
                        Text("Remaining").tag(true)
                        Text("Used").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
                HStack {
                    Text("Refresh every")
                    Spacer()
                    Picker("Refresh every", selection: Binding(get: { store.refreshMinutes }, set: { store.refreshMinutes = $0 })) {
                        ForEach(UsageStore.refreshChoices, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            .font(.system(size: 13))
        }
    }

    private func providerRow(_ p: ProviderID) -> some View {
        let installed = p.isInstalled
        return Toggle(isOn: Binding(get: { store.isEnabled(p) }, set: { store.setEnabled(p, $0) })) {
            HStack(spacing: 10) {
                ProviderIcon(provider: p, size: 26)
                    .opacity(installed ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.system(size: 13, weight: .medium))
                    Text(installed ? p.summary : "Not found on this Mac")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .foregroundStyle(installed ? .primary : .secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!installed)
        .padding(.vertical, 8)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.4)
            .padding(.bottom, 4)
    }
}

// MARK: - Shared pieces

/// The provider's real app icon, or a letter badge when no app is installed.
struct ProviderIcon: View {
    let provider: ProviderID
    let size: CGFloat

    var body: some View {
        if let image = provider.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(provider.tint)
                .frame(width: size, height: size)
                .overlay(
                    Text(provider.short)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                )
        }
    }
}

struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Formatting

func countdown(to date: Date, now: Date) -> String {
    let secs = max(0, Int(date.timeIntervalSince(now)))
    let d = secs / 86400, h = secs % 86400 / 3600, m = secs % 3600 / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(max(m, 1))m"
}

func absolute(_ date: Date, now: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "'today' HH:mm" : "EEE, MMM d HH:mm"
    return f.string(from: date)
}

func relative(_ date: Date, now: Date) -> String {
    let secs = Int(now.timeIntervalSince(date))
    if secs < 60 { return "just now" }
    if secs < 3600 { return "\(secs / 60)m ago" }
    if secs < 86400 { return "\(secs / 3600)h ago" }
    return "\(secs / 86400)d ago"
}
