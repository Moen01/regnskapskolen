import XCTest
@testable import RegnskapKit

final class PuzzleSessionTests: XCTestCase {
    static let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/puzzles/valid")
    func fixture(_ name: String) throws -> Puzzle { try Puzzle.load(url: Self.fixtures.appendingPathComponent("\(name).json")) }

    func testRightOnFirstCheckIsAFirstTry() throws {
        var session = PuzzleSession(puzzle: try fixture("quiz"))
        XCTAssertFalse(session.isFinished)
        session.attempt = .quiz(2)
        let verdict = session.check()
        XCTAssertTrue(verdict.correct)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.checks, 1)
        XCTAssertEqual(session.result, AttemptResult(puzzleId: "mva-quiz-001", correctFirstTry: true))
    }

    func testWrongThenRightIsNotAFirstTry() throws {
        var session = PuzzleSession(puzzle: try fixture("quiz"))
        session.attempt = .quiz(0)
        XCTAssertFalse(session.check().correct)
        XCTAssertFalse(session.isFinished)
        session.attempt = .quiz(2)
        XCTAssertTrue(session.check().correct)
        XCTAssertEqual(session.checks, 2)
        XCTAssertFalse(session.result.correctFirstTry)
    }

    func testRegnutShowsTheAnswerOnlyAfterTwoWrongChecks() throws {
        var session = PuzzleSession(puzzle: try fixture("regnut"))
        XCTAssertFalse(session.canReveal)
        session.attempt = .number("100")
        session.check()
        XCTAssertFalse(session.canReveal)
        session.attempt = .number("200")
        session.check()
        XCTAssertTrue(session.canReveal)
        session.reveal()
        XCTAssertTrue(session.isFinished)
        XCTAssertTrue(session.revealed)
        XCTAssertFalse(session.result.correctFirstTry)
    }

    func testOtherKindsCanShowTheAnswerAtOnce() throws {
        for name in ["quiz", "postering", "klassifiser", "finnfeil", "sak", "mva", "frist"] {
            XCTAssertTrue(PuzzleSession(puzzle: try fixture(name)).canReveal, name)
        }
    }

    func testAnUnansweredCheckDoesNotCount() throws {
        var session = PuzzleSession(puzzle: try fixture("regnut"))
        session.attempt = .number("abc")
        let verdict = session.check()
        XCTAssertFalse(verdict.correct)
        XCTAssertEqual(verdict.messages, ["Skriv et beløp, for eksempel 1 250 eller 1250,50."])
        XCTAssertEqual(session.checks, 0)
        session.attempt = .number("250")
        XCTAssertTrue(session.check().correct)
        XCTAssertTrue(session.result.correctFirstTry)
    }

    func testEmptyAttemptMatchesTheKind() throws {
        XCTAssertEqual(PuzzleAttempt.empty(for: .postering), .posting([]))
        XCTAssertEqual(PuzzleAttempt.empty(for: .quiz), .quiz(nil))
        XCTAssertEqual(PuzzleAttempt.empty(for: .mva), .vat(behandling: nil, fradrag: nil))
        XCTAssertFalse(PuzzleAttempt.empty(for: .frist).isAnswered)
        XCTAssertTrue(PuzzleAttempt.deadline(DayKey(year: 2026, month: 6, day: 10)).isAnswered)
    }

    func testSummaryDescribesTheAttemptForTheTutor() throws {
        let posting = try fixture("postering")
        let attempt = PuzzleAttempt.posting([PostingAttemptLine(konto: "1920", debet: 2500), PostingAttemptLine(konto: "3000", kredit: 2500)])
        XCTAssertEqual(attempt.summary(for: posting), "1920 Bankinnskudd: debet \(NorwegianFormat.kroner(2500))\n3000 Salgsinntekt, avgiftspliktig, høy sats: kredit \(NorwegianFormat.kroner(2500))")
        XCTAssertEqual(PuzzleAttempt.quiz(1).summary(for: try fixture("quiz")), "Valgte: 15 %, redusert sats")
        XCTAssertEqual(PuzzleAttempt.number("100").summary(for: try fixture("regnut")), "Svarte: 100")
        XCTAssertEqual(PuzzleAttempt.quiz(nil).summary(for: try fixture("quiz")), "Ikke besvart")
    }
}
