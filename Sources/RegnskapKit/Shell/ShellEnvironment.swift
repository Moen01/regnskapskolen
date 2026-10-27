import Foundation

/// The environment child processes get. An app started from Finder has launchd's bare PATH, where
/// `claude` is not found, so the login shell is asked once for the real one. Variables a parent
/// Claude Code session sets are removed: a child inheriting them runs as a nested session.
public final class ShellEnvironment: @unchecked Sendable {
    public static let shared = ShellEnvironment()

    static let strippedPrefixes = ["CLAUDECODE", "CLAUDE_CODE_", "CLAUDE_AGENT_SDK", "CLAUDE_PID", "CLAUDE_EFFORT"]

    private let lock = NSLock()
    private var resolved: [String: String]?
    private var found: [String: String] = [:]

    public var environment: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let resolved { return resolved }
        var env = Self.stripped(ProcessInfo.processInfo.environment)
        env["PATH"] = Self.loginShellPath() ?? Self.fallbackPath(home: env["HOME"] ?? NSHomeDirectory())
        resolved = env
        return env
    }

    public var path: String { environment["PATH"] ?? "" }

    static func stripped(_ env: [String: String]) -> [String: String] {
        env.filter { key, _ in !strippedPrefixes.contains { key.hasPrefix($0) } }
    }

    /// The full path of `name` on the resolved PATH, looked up once; a missing tool is looked up again.
    public func which(_ name: String) -> String? {
        if let hit = lock.withLock({ found[name] }) { return hit }
        let dirs = path.split(separator: ":")
        guard let hit = dirs.lazy.map({ "\($0)/\(name)" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        lock.withLock { found[name] = hit }
        return hit
    }

    static func loginShellPath() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Markers keep anything a profile prints out of the value.
        process.arguments = ["-lic", "printf '<<PATH>>%s<<END>>' \"$PATH\""]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return nil }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let start = text.range(of: "<<PATH>>"), let end = text.range(of: "<<END>>", range: start.upperBound..<text.endIndex) else { return nil }
        let value = String(text[start.upperBound..<end.lowerBound])
        return value.isEmpty ? nil : value
    }

    static func fallbackPath(home: String) -> String {
        ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
    }
}
