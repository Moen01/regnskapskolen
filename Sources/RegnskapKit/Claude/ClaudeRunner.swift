import Foundation

public struct ClaudeRequest: Sendable, Equatable {
    public var system: String
    public var prompt: String
    public var schema: JSONValue?
    public var model: String
    public var resume: String?
    /// Keep the session on disk so `resume` can continue it; one-shots don't.
    public var persist: Bool

    public init(system: String, prompt: String, schema: JSONValue?, model: String, resume: String?, persist: Bool) {
        self.system = system; self.prompt = prompt; self.schema = schema; self.model = model; self.resume = resume; self.persist = persist
    }
}

public struct ClaudeReply: Sendable, Equatable {
    public let text: String
    public let structured: JSONValue?
    public let sessionId: String?
    public let costUSD: Double?
}

/// One call of `claude -p`: no tools, no MCP servers, a temp working directory, two minutes.
public final class ClaudeRunner: Sendable {
    public static let timeout: TimeInterval = 120
    let processes: ClaudeProcesses

    public init(processes: ClaudeProcesses = RealClaudeProcesses()) { self.processes = processes }

    public static func arguments(for request: ClaudeRequest) -> [String] {
        var args = ["-p", request.prompt, "--output-format", "json", "--system-prompt", request.system,
                    "--tools", "", "--strict-mcp-config", "--model", request.model]
        if let schema = request.schema { args += ["--json-schema", String(decoding: schema.compactData, as: UTF8.self)] }
        if let resume = request.resume { args += ["--resume", resume] }
        if !request.persist { args.append("--no-session-persistence") }
        return args
    }

    public func run(_ request: ClaudeRequest) async throws -> ClaudeReply {
        guard processes.claudeInstalled() else { throw ClaudeError.notInstalled }
        let cwd = FileManager.default.temporaryDirectory.appendingPathComponent("regnskapsskolen-claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let result: ProcessResult
        do {
            result = try await processes.run(Self.arguments(for: request), cwd: cwd.path, timeout: Self.timeout)
        } catch ProcessError.timedOut {
            throw ClaudeError.timedOut
        } catch ProcessError.notFound {
            throw ClaudeError.notInstalled
        }
        guard result.succeeded else {
            let text = (result.stderrString + "\n" + result.stdoutString).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().contains("not logged in") || text.lowercased().contains("auth login") { throw ClaudeError.notSignedIn }
            throw ClaudeError.failed(String(text.prefix(400)))
        }
        return try Self.decode(result.stdout)
    }

    public static func decode(_ data: Data) throws -> ClaudeReply {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), json["type"]?.string == "result" else { throw ClaudeError.badOutput }
        let text = json["result"]?.string ?? ""
        if json["is_error"]?.bool == true { throw ClaudeError.failed(String(text.prefix(400))) }
        return ClaudeReply(text: text, structured: json["structured_output"], sessionId: json["session_id"]?.string, costUSD: json["total_cost_usd"]?.double)
    }
}

extension JSONValue {
    /// Compact, with sorted keys, so the same schema always gives the same command line.
    public var compactData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data()
    }
}
