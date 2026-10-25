import AppKit
import SwiftUI

@main
struct UsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        if CommandLine.arguments.contains("--dump") { Self.dump() }
    }

    /// `UsageBar --dump` prints what the providers see, for debugging.
    private static func dump() -> Never {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do { print("Claude:", try await ClaudeProvider.fetch()) } catch { print("Claude error:", error) }
            do { print("Codex:", try CodexProvider.fetch()) } catch { print("Codex error:", error) }
            AgentScanner.scan().forEach { print("Agent:", $0.tool, $0.status, $0.title, $0.cwd ?? "") }
            done.signal()
        }
        done.wait()
        exit(0)
    }

    // Everything lives in the status item; the app has no windows.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Owns the menu bar item. A plain NSStatusItem is used instead of SwiftUI's
/// MenuBarExtra because MenuBarExtra can silently render an empty label.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var ticker: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }

        let host = NSHostingController(rootView: MenuView(store: store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient

        observeStore()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLabel() }
        }
        // Passed resets drop to 0% without a fetch, so re-render once a minute.
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLabel() }
        }

        if ProcessInfo.processInfo.environment["USAGEBAR_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                let line = "visible: \(self.statusItem.isVisible) title: \(button.title) "
                    + "frame: \(button.window?.frame ?? .zero) screen: \(button.window?.screen?.frame ?? .zero)\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
        }
    }

    /// Re-renders the label whenever any store property it reads changes.
    private func observeStore() {
        withObservationTracking {
            updateLabel()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    private func updateLabel() {
        guard let button = statusItem?.button else { return }
        let working = store.workingCount
        button.image = NSImage(
            systemSymbolName: working > 0 ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.33percent",
            accessibilityDescription: "Kullanım"
        )
        button.image?.isTemplate = true
        button.title = " " + labelText(working: working)
    }

    /// Compact 5-hour figures for both tools, e.g. "C 82% · X 12%".
    private func labelText(working: Int) -> String {
        let showRemaining = UserDefaults.standard.object(forKey: "showRemaining") as? Bool ?? true
        func format(_ w: UsageWindow) -> String {
            "\(Int((showRemaining ? w.remainingPercent : w.usedPercent).rounded()))%"
        }
        var parts: [String] = []
        if let w = normalized(store.claude?.fiveHour) { parts.append("C \(format(w))") }
        if let w = normalized(store.codex?.fiveHour) { parts.append("X \(format(w))") }
        if working > 0 { parts.append("⚡︎\(working)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
