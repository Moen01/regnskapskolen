import XCTest
@testable import RegnskapKit

/// A fake process layer: records the arguments and returns canned output.
final class FakeProcesses: ClaudeProcesses, @unchecked Sendable {
    var calls: [[String]] = []
    var status: ProcessResult = ProcessResult(exitCode: 0, stdout: Data(#"{"loggedIn":true,"email":"a@b.no","subscriptionType":"pro","authMethod":"claude.ai"}"#.utf8), stderr: Data())
    var reply: ProcessResult
    var installed = true
    init(reply: ProcessResult) { self.reply = reply }
    func claudeInstalled() -> Bool { installed }
    func run(_ arguments: [String], cwd: String, timeout: TimeInterval) async throws -> ProcessResult {
        calls.append(arguments)
        return arguments.first == "auth" ? status : reply
    }
}

final class ClaudeTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    static let fixture = try! Data(contentsOf: Bundle.module.resourceURL!.appendingPathComponent("Fixtures/claude-result.json"))

    func testArgumentsOneShot() {
        let request = ClaudeRequest(system: "SYS", prompt: "Hei", schema: .object(["type": .string("object")]), model: "sonnet", resume: nil, persist: false)
        XCTAssertEqual(ClaudeRunner.arguments(for: request), [
            "-p", "Hei", "--output-format", "json", "--system-prompt", "SYS", "--tools", "", "--strict-mcp-config",
            "--model", "sonnet", "--json-schema", #"{"type":"object"}"#, "--no-session-persistence",
        ])
    }

    func testArgumentsResume() {
        let request = ClaudeRequest(system: "SYS", prompt: "Mer", schema: nil, model: "haiku", resume: "abc", persist: true)
        let args = ClaudeRunner.arguments(for: request)
        XCTAssertTrue(args.contains("--resume")); XCTAssertEqual(args[args.firstIndex(of: "--resume")! + 1], "abc")
        XCTAssertFalse(args.contains("--no-session-persistence")); XCTAssertFalse(args.contains("--json-schema"))
    }

    func testDecodesFixture() throws {
        let reply = try ClaudeRunner.decode(Self.fixture)
        XCTAssertEqual(reply.structured?["sats"]?.int, 12)
        XCTAssertEqual(reply.sessionId, "b7c385e5-b5bf-4f9e-bf16-f9c2176cfc34")
        XCTAssertTrue(reply.text.contains("persontransport"))
        XCTAssertEqual(reply.costUSD, 0.0014487)
    }

    func testRunnerUsesFakeAndStripsNothingElse() async throws {
        let fake = FakeProcesses(reply: ProcessResult(exitCode: 0, stdout: Self.fixture, stderr: Data()))
        let runner = ClaudeRunner(processes: fake)
        let reply = try await runner.run(ClaudeRequest(system: "s", prompt: "p", schema: nil, model: "haiku", resume: nil, persist: false))
        XCTAssertEqual(reply.structured?["sats"]?.int, 12)
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertEqual(fake.calls[0].prefix(2), ["-p", "p"])
    }

    func testRunnerReportsNotSignedIn() async {
        let fake = FakeProcesses(reply: ProcessResult(exitCode: 0, stdout: Self.fixture, stderr: Data()))
        fake.status = ProcessResult(exitCode: 0, stdout: Data(#"{"loggedIn":false}"#.utf8), stderr: Data())
        let cli = ClaudeCLI(processes: fake)
        let status = await cli.status()
        guard case .notSignedIn = status else { return XCTFail("expected notSignedIn, got \(status)") }
        XCTAssertTrue(ClaudeError.notSignedIn.errorDescription!.contains("claude auth login"))
        fake.installed = false
        guard case .missing = await cli.status() else { return XCTFail("expected missing") }
        XCTAssertTrue(ClaudeError.notInstalled.errorDescription!.contains("claude.ai/install.sh"))
    }

    func testRunnerReportsFailureAndBadOutput() async {
        let failing = ClaudeRunner(processes: FakeProcesses(reply: ProcessResult(exitCode: 1, stdout: Data(), stderr: Data("boom".utf8))))
        do { _ = try await failing.run(ClaudeRequest(system: "s", prompt: "p", schema: nil, model: "haiku", resume: nil, persist: false)); XCTFail() }
        catch ClaudeError.failed(let message) { XCTAssertTrue(message.contains("boom")) }
        catch { XCTFail("\(error)") }
        let garbage = ClaudeRunner(processes: FakeProcesses(reply: ProcessResult(exitCode: 0, stdout: Data("not json".utf8), stderr: Data())))
        do { _ = try await garbage.run(ClaudeRequest(system: "s", prompt: "p", schema: nil, model: "haiku", resume: nil, persist: false)); XCTFail() }
        catch ClaudeError.badOutput { }
        catch { XCTFail("\(error)") }
    }

    func testGeneratorRejectsInvalidPuzzle() async {
        // A posting that does not balance, wrapped as claude's json result with structured_output.
        let bad: [String: Any] = ["id": "gen-1", "type": "postering", "tema": "mva", "vanskelighet": 4, "tittel": "x", "oppgave": "x", "forklaring": "x",
                                  "lov": [["lov": "merverdiavgiftsloven", "paragraf": "§ 3-1", "tekst": "x"]],
                                  "kontoer": [["nr": "1920", "navn": "Bank"], ["nr": "3000", "navn": "Salg"]],
                                  "fasit": [["konto": "1920", "side": "D", "belop": 100], ["konto": "3000", "side": "K", "belop": 90]]]
        let envelope: [String: Any] = ["type": "result", "is_error": false, "result": "{}", "session_id": "s", "structured_output": bad]
        let data = try! JSONSerialization.data(withJSONObject: envelope)
        let tutor = Tutor(library: Self.library, runner: ClaudeRunner(processes: FakeProcesses(reply: ProcessResult(exitCode: 0, stdout: data, stderr: Data()))), model: "haiku")
        do {
            _ = try await tutor.harder(than: Self.library.puzzle(id: "mva-quiz-001")!)
            XCTFail("expected invalidPuzzle")
        } catch ClaudeError.invalidPuzzle(let problems) {
            XCTAssertTrue(problems.contains { $0.contains("balanserer ikke") }, problems.joined(separator: "; "))
        } catch { XCTFail("\(error)") }
    }

    func testGeneratorAcceptsValidPuzzleAsDraft() async throws {
        var good = try JSONDecoder().decode(JSONValue.self, from: try Self.library.puzzle(id: "mva-quiz-001")!.encoded())
        var o = good.object!; o["id"] = .string("mva-quiz-001-gen"); o["vanskelighet"] = .number(3); good = .object(o)
        let envelope = JSONValue.object(["type": .string("result"), "is_error": .bool(false), "result": .string("{}"), "session_id": .string("s"), "structured_output": good])
        let tutor = Tutor(library: Self.library, runner: ClaudeRunner(processes: FakeProcesses(reply: ProcessResult(exitCode: 0, stdout: envelope.data, stderr: Data()))), model: "haiku")
        let puzzle = try await tutor.harder(than: Self.library.puzzle(id: "mva-quiz-001")!)
        XCTAssertEqual(puzzle.status, .utkast)
        XCTAssertTrue(puzzle.generert)
        XCTAssertEqual(puzzle.id, "mva-quiz-001-gen")
    }

    func testPromptsExistAndSchemaCoversEveryKind() {
        for name in ["veileder", "forfatter", "sandkasse"] {
            XCTAssertNotNil(Tutor.prompt(named: name, root: ContentLocator.repoContent), name)
        }
        for kind in PuzzleKind.allCases {
            let schema = PuzzleSchema.schema(for: kind)
            XCTAssertEqual(schema["type"]?.string, "object", kind.rawValue)
            XCTAssertTrue(schema["required"]?.array?.contains(.string("forklaring")) ?? false, kind.rawValue)
        }
    }

    func testSaveGeneratedPuzzleGoesToGenerertFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("innhold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("oppgaver"), withIntermediateDirectories: true)
        var puzzle = Self.library.puzzle(id: "mva-quiz-001")!
        puzzle.id = "gen-x"; puzzle.status = .utkast
        let url = try TutorFiles.save(puzzle, contentRoot: root, fallback: root.appendingPathComponent("fallback"))
        XCTAssertEqual(url.path, root.appendingPathComponent("oppgaver/generert/gen-x.json").path)
        XCTAssertEqual(try Puzzle.load(url: url).generert, true)
        let readOnly = URL(fileURLWithPath: "/System/Library")
        let fallback = root.appendingPathComponent("fallback")
        let url2 = try TutorFiles.save(puzzle, contentRoot: readOnly, fallback: fallback)
        XCTAssertEqual(url2.path, fallback.appendingPathComponent("gen-x.json").path)
    }

    func testGeneratedFilesNeverLandInsideAnAppBundle() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)", isDirectory: true)
        let inBundle = tmp.appendingPathComponent("Regnskapsskolen.app/Contents/Resources/Innhold", isDirectory: true)
        let fallback = tmp.appendingPathComponent("fallback", isDirectory: true)
        try FileManager.default.createDirectory(at: inBundle, withIntermediateDirectories: true)
        var puzzle = try Puzzle.load(url: ContentLocator.repoContent.appendingPathComponent("oppgaver/mva/mva-quiz-001.json"))
        puzzle.id = "gen-bundle-test"
        let url = try TutorFiles.save(puzzle, contentRoot: inBundle, fallback: fallback)
        XCTAssertTrue(url.path.hasPrefix(fallback.path), url.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inBundle.appendingPathComponent("oppgaver/generert").path), "nothing is created inside the bundle")
    }
}
