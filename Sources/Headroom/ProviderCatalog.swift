import AppKit
import SwiftUI

enum ProviderID: String, CaseIterable, Identifiable {
    case claude, codex, cursor, copilot, antigravity, grok

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .copilot: return "GitHub Copilot"
        case .antigravity: return "Antigravity"
        case .grok: return "Grok"
        }
    }

    /// Prefix in the menu bar label and fallback badge text.
    var short: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        case .cursor: return "Cu"
        case .copilot: return "Gh"
        case .antigravity: return "Ag"
        case .grok: return "Gk"
        }
    }

    /// What the provider's numbers mean, for the settings list.
    var summary: String {
        switch self {
        case .claude, .codex: return "5 saatlik + haftalık"
        case .cursor: return "Fatura dönemi kullanımı"
        case .copilot: return "Aylık premium istekler"
        case .antigravity: return "Model kotaları"
        case .grok: return "Kullanım verisi henüz okunamıyor"
        }
    }

    var tint: Color {
        switch self {
        case .claude: return Color(light: 0xC2410C, dark: 0xF0A27A)
        case .codex: return Color(light: 0x1D4ED8, dark: 0x8DB0FF)
        case .cursor: return Color(light: 0x3F3F46, dark: 0xD4D4D8)
        case .copilot: return Color(light: 0x7C3AED, dark: 0xC4A7FF)
        case .antigravity: return Color(light: 0x0F766E, dark: 0x5EEAD4)
        case .grok: return Color(light: 0x52525B, dark: 0xA1A1AA)
        }
    }

    var isInstalled: Bool {
        let fm = FileManager.default
        switch self {
        case .claude: return fm.exists("\(homePath)/.claude") || Shell.find("claude") != nil
        case .codex: return fm.exists("\(homePath)/.codex")
        case .cursor: return fm.exists(CursorProvider.dbPath)
        case .copilot:
            return ["/Applications/GitHub Copilot.app", "\(homePath)/.copilot", "\(homePath)/.config/github-copilot"]
                .contains(where: fm.exists)
        case .antigravity: return fm.exists("/Applications/Antigravity.app") || fm.exists("\(homePath)/.antigravity")
        case .grok: return fm.exists("\(homePath)/.grok") || Shell.find("grok") != nil
        }
    }

    func fetch() async throws -> ProviderUsage {
        switch self {
        case .claude: return try await ClaudeProvider.fetch()
        case .codex: return try CodexProvider.fetch()
        case .cursor: return try await CursorProvider.fetch()
        case .copilot: return try await CopilotProvider.fetch()
        case .antigravity: return try await AntigravityProvider.fetch()
        case .grok: throw ProviderError.unsupported
        }
    }

    // MARK: Icons

    /// The real icon, read from the app installed on this Mac. Nothing is
    /// bundled, so providers without an app fall back to a letter badge.
    @MainActor var icon: NSImage? {
        if let cached = Self.iconCache[self] { return cached }
        let image = loadIcon()
        Self.iconCache[self] = image
        return image
    }

    @MainActor private static var iconCache: [ProviderID: NSImage?] = [:]

    private func loadIcon() -> NSImage? {
        let candidates: [String]
        switch self {
        case .claude: candidates = ["Claude.app"]
        case .codex:
            if let png = NSImage(contentsOfFile: "/Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png") {
                return png
            }
            candidates = ["Codex.app", "ChatGPT.app"]
        case .cursor: candidates = ["Cursor.app"]
        case .copilot: candidates = ["GitHub Copilot.app", "Visual Studio Code.app"]
        case .antigravity: candidates = ["Antigravity.app"]
        case .grok: candidates = ["Grok.app"]
        }
        for dir in ["/Applications", "\(homePath)/Applications"] {
            for app in candidates where FileManager.default.exists("\(dir)/\(app)") {
                return NSWorkspace.shared.icon(forFile: "\(dir)/\(app)")
            }
        }
        return nil
    }
}

/// Which providers the user turned on. Until they touch a toggle, Claude Code
/// and Codex are on when installed; if neither is, every installed one is.
enum ProviderSettings {
    static func isEnabled(_ p: ProviderID) -> Bool {
        guard p.isInstalled else { return false }
        if let stored = UserDefaults.standard.object(forKey: key(p)) as? Bool { return stored }
        return defaults.contains(p)
    }

    static func setEnabled(_ p: ProviderID, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: key(p))
    }

    private static func key(_ p: ProviderID) -> String { "enabled.\(p.rawValue)" }

    private static let defaults: Set<ProviderID> = {
        let installed = ProviderID.allCases.filter(\.isInstalled)
        let primary = installed.filter { $0 == .claude || $0 == .codex }
        return Set(primary.isEmpty ? installed : primary)
    }()
}

extension Color {
    /// A color that follows the system light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static let low = Color(light: 0xB91C1C, dark: 0xFF8A8A)
}
