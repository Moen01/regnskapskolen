import Foundation

/// The process layer the Claude code talks to, so tests can fake it.
public protocol ClaudeProcesses: Sendable {
    func claudeInstalled() -> Bool
    func run(_ arguments: [String], cwd: String, timeout: TimeInterval) async throws -> ProcessResult
}

public struct RealClaudeProcesses: ClaudeProcesses {
    public init() {}
    public func claudeInstalled() -> Bool { ShellEnvironment.shared.which("claude") != nil }
    public func run(_ arguments: [String], cwd: String, timeout: TimeInterval) async throws -> ProcessResult {
        try await ProcessRunner.run("claude", arguments, cwd: cwd, timeout: timeout)
    }
}

/// What `claude auth status` prints.
public struct ClaudeAccount: Decodable, Sendable, Equatable {
    public let loggedIn: Bool
    public let email: String?
    public let subscriptionType: String?
    public let authMethod: String?

    public init(loggedIn: Bool, email: String? = nil, subscriptionType: String? = nil, authMethod: String? = nil) {
        self.loggedIn = loggedIn; self.email = email; self.subscriptionType = subscriptionType; self.authMethod = authMethod
    }

    public var summary: String {
        var parts: [String] = []
        if let email { parts.append(email) }
        if let subscriptionType { parts.append(subscriptionType.capitalized) }
        return parts.isEmpty ? "Innlogget" : parts.joined(separator: " · ")
    }
}

public enum ClaudeStatus: Sendable, Equatable {
    case unknown
    case missing
    case notSignedIn
    case ready(ClaudeAccount)

    public var isReady: Bool { if case .ready = self { true } else { false } }

    public var text: String {
        switch self {
        case .unknown: "Sjekker…"
        case .missing: "Claude Code er ikke installert"
        case .notSignedIn: "Ikke logget inn"
        case .ready(let account): account.summary
        }
    }
}

public enum ClaudeError: Error, LocalizedError, Equatable {
    case notInstalled
    case notSignedIn
    case failed(String)
    case badOutput
    case timedOut
    case invalidPuzzle([String])

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Claude Code er ikke installert. Kjør: curl -fsSL https://claude.ai/install.sh | bash"
        case .notSignedIn: "Du er ikke logget inn i Claude Code. Kjør: claude auth login"
        case .failed(let message): "Claude svarte ikke: \(message)"
        case .badOutput: "Claude ga et svar appen ikke forsto."
        case .timedOut: "Claude brukte for lang tid (over to minutter)."
        case .invalidPuzzle(let problems): "Oppgaven Claude laget, besto ikke kontrollen: " + problems.joined(separator: "; ")
        }
    }
}

/// Finds the `claude` binary and reads its sign-in state.
public struct ClaudeCLI: Sendable {
    public static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"
    public static let loginCommand = "claude auth login"

    let processes: ClaudeProcesses

    public init(processes: ClaudeProcesses = RealClaudeProcesses()) { self.processes = processes }

    public func status() async -> ClaudeStatus {
        guard processes.claudeInstalled() else { return .missing }
        guard let result = try? await processes.run(["auth", "status"], cwd: NSTemporaryDirectory(), timeout: 20),
              let account = try? JSONDecoder().decode(ClaudeAccount.self, from: result.stdout) else { return .notSignedIn }
        return account.loggedIn ? .ready(account) : .notSignedIn
    }
}
