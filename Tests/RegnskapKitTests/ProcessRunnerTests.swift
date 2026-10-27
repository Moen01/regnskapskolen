import XCTest
@testable import RegnskapKit

final class ProcessRunnerTests: XCTestCase {
    func testRunsEchoAndCapturesExit() async throws {
        let result = try await ProcessRunner.run("/bin/sh", ["-c", "echo hi; echo oops 1>&2; exit 3"])
        XCTAssertEqual(result.stdoutString, "hi\n")
        XCTAssertEqual(result.stderrString, "oops\n")
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertFalse(result.succeeded)
    }

    func testTimeout() async {
        do {
            _ = try await ProcessRunner.run("/bin/sh", ["-c", "sleep 5"], timeout: 0.5)
            XCTFail("expected a timeout")
        } catch ProcessError.timedOut {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testMissingToolIsNotFound() async {
        do {
            _ = try await ProcessRunner.run("no-such-tool-xyz", [])
            XCTFail("expected notFound")
        } catch ProcessError.notFound(let name) {
            XCTAssertEqual(name, "no-such-tool-xyz")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testStrippedPrefixesCoverParentClaudeSession() {
        let env = ["CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "x", "CLAUDE_PID": "1", "CLAUDE_EFFORT": "high", "CLAUDE_AGENT_SDK": "1", "HOME": "/tmp"]
        let cleaned = ShellEnvironment.stripped(env)
        XCTAssertEqual(cleaned, ["HOME": "/tmp"])
    }

    func testWhichFindsSh() {
        XCTAssertEqual(ShellEnvironment.shared.which("sh"), "/bin/sh")
    }
}
