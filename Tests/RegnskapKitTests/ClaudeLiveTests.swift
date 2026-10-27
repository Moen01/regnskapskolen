import XCTest
@testable import RegnskapKit

/// Runs the real `claude` binary. On by `REGNSKAP_LIVE=1 swift test --filter ClaudeLive`; needs a login.
final class ClaudeLiveTests: XCTestCase {
    func testExplainWithHaiku() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REGNSKAP_LIVE"] == "1", "set REGNSKAP_LIVE=1 to run")
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let tutor = Tutor(library: library, model: "haiku")
        let puzzle = library.puzzle(id: "mva-quiz-001")!
        let verdict = Checkers.quiz(0, (puzzle.payload.quiz)!)
        let text = try await tutor.explain(puzzle: puzzle, attempt: "25 %, alminnelig sats", verdict: verdict)
        print("LIVE:", text)
        XCTAssertTrue(text.contains("§"), text)
        XCTAssertTrue(text.lowercased().contains("fritatt"), text)
    }
}

extension PuzzlePayload {
    var quiz: Quiz? { if case .quiz(let q) = self { q } else { nil } }
}
