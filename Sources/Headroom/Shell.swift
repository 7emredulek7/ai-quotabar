import Foundation

enum Shell {
    /// Runs a command and returns its stdout when it exits successfully.
    static func run(_ executable: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    /// Apps launched from Finder get a minimal PATH, so look in the usual
    /// install locations instead of relying on it.
    static func find(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "\(home)/.local/bin", "\(home)/bin"]
        return dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

extension FileManager {
    func exists(_ path: String) -> Bool { fileExists(atPath: path) }
}

let homePath = FileManager.default.homeDirectoryForCurrentUser.path
