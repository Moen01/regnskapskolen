import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
    public var succeeded: Bool { exitCode == 0 }
}

public enum ProcessError: Error, LocalizedError, Equatable {
    case notFound(String)
    case failed(command: String, exitCode: Int32, stderr: String)
    case timedOut(command: String)
    case badDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let tool): "Fant ikke \(tool) på PATH"
        case .failed(let command, let code, let stderr):
            "\(command) avsluttet med kode \(code)" + (stderr.isEmpty ? "" : ": \(stderr.prefix(300))")
        case .timedOut(let command): "\(command) brukte for lang tid"
        case .badDirectory(let path): "Mappen \(path) finnes ikke"
        }
    }
}

/// Runs a command-line tool with the login shell's environment and returns everything it printed.
public enum ProcessRunner {
    public static func run(
        _ tool: String,
        _ arguments: [String],
        cwd: String? = nil,
        stdin: Data? = nil,
        extraEnv: [String: String] = [:],
        timeout: TimeInterval = 60
    ) async throws -> ProcessResult {
        let shell = ShellEnvironment.shared
        let executable: String
        if tool.hasPrefix("/") {
            executable = tool
        } else if let found = shell.which(tool) {
            executable = found
        } else {
            throw ProcessError.notFound(tool)
        }
        if let cwd {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue else {
                throw ProcessError.badDirectory(cwd)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = shell.environment.merging(extraEnv) { _, new in new }
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true) }
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input

        let command = ([tool] + arguments.prefix(2)).joined(separator: " ")
        let collector = OutputCollector()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                let once = ResumeOnce(continuation)
                collector.onComplete = { result in once.resume(.success(result)) }
                // Read as output arrives: a full pipe buffer would otherwise block the child.
                out.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { handle.readabilityHandler = nil; collector.finished(.out) } else { collector.append(data, .out) }
                }
                err.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { handle.readabilityHandler = nil; collector.finished(.err) } else { collector.append(data, .err) }
                }
                process.terminationHandler = { p in
                    collector.exited(p.terminationStatus)
                    // A grandchild holding the pipes open would otherwise keep us waiting forever.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { collector.giveUp() }
                }
                do {
                    try process.run()
                } catch {
                    once.resume(.failure(error))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        process.terminate()
                        once.resume(.failure(ProcessError.timedOut(command: command)))
                    }
                }
                if let stdin {
                    let writer = input.fileHandleForWriting
                    _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                    DispatchQueue.global().async {
                        try? writer.write(contentsOf: stdin)
                        try? writer.close()
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Runs `tool` and returns stdout, throwing when it exits non-zero.
    public static func output(_ tool: String, _ arguments: [String], cwd: String? = nil, timeout: TimeInterval = 60) async throws -> Data {
        let result = try await run(tool, arguments, cwd: cwd, timeout: timeout)
        guard result.succeeded else {
            throw ProcessError.failed(command: ([tool] + arguments.prefix(2)).joined(separator: " "), exitCode: result.exitCode,
                                      stderr: result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }
}

/// Gathers a process's two output streams and reports once both are closed and the process has exited.
final class OutputCollector: @unchecked Sendable {
    enum Stream { case out, err }
    private let lock = NSLock()
    private var out = Data(), err = Data()
    private var outDone = false, errDone = false, status: Int32?, delivered = false
    var onComplete: (@Sendable (ProcessResult) -> Void)?

    func append(_ data: Data, _ stream: Stream) {
        lock.withLock { if stream == .out { out.append(data) } else { err.append(data) } }
    }
    func finished(_ stream: Stream) { update { if stream == .out { $0.outDone = true } else { $0.errDone = true } } }
    func exited(_ code: Int32) { update { $0.status = code } }
    func giveUp() { update { $0.outDone = true; $0.errDone = true } }

    private func update(_ change: (OutputCollector) -> Void) {
        let result: ProcessResult? = lock.withLock {
            change(self)
            guard !delivered, outDone, errDone, let status else { return nil }
            delivered = true
            return ProcessResult(exitCode: status, stdout: out, stderr: err)
        }
        if let result { onComplete?(result) }
    }
}

final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
    func resume(_ result: Result<T, Error>) {
        let c: CheckedContinuation<T, Error>? = lock.withLock { defer { continuation = nil }; return continuation }
        c?.resume(with: result)
    }
}
