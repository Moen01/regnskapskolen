import XCTest
@testable import RegnskapKit

final class BilagRunTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    let today = DayKey(string: "2026-02-03")!
    let jan = MonthKey(year: 2026, month: 1)
    let client = makeLedgerClient()
    var pool: [Puzzle] { Self.library.pool(includeDrafts: false) }
    var mvaCards: [RuleCard] { Self.library.rules(tema: "mva") }
    var otherCards: [RuleCard] { Self.library.rules.filter { $0.tema != "mva" } }
    func quizzes(_ count: Int) -> [Puzzle] { Array(pool.filter { $0.tema == "mva" && $0.kind == .quiz }.prefix(count)) }
    func wrong(_ p: Puzzle) -> PuzzleAttempt { .quiz(-1) }
    func right(_ p: Puzzle) -> PuzzleAttempt {
        guard case .quiz(let q) = p.payload else { fatalError("quiz only") }
        return .quiz(q.svar)
    }
    func booking(_ puzzles: [Puzzle], seed: UInt64 = 1) -> BilagRun {
        BilagRun(client: client, puzzles: puzzles, kind: .booking(jan), errors: [], bransjeCards: mvaCards, otherCards: otherCards, seed: seed)
    }

    func testBookingNeverTellsTheVerdict() throws {
        let puzzles = quizzes(2)
        XCTAssertEqual(puzzles.count, 2)
        var run = booking(puzzles)
        XCTAssertEqual(run.current?.puzzle.id, puzzles[0].id)
        XCTAssertEqual(run.current?.context, .bilag(client: client.id))
        run.choose(nil)
        let first = try XCTUnwrap(run.answer(right(puzzles[0]), progress: LearnerProgress(), today: today))
        XCTAssertEqual(first.outcome, .booked)
        XCTAssertEqual(first.result, AttemptResult(puzzleId: puzzles[0].id, correctFirstTry: true))
        XCTAssertEqual(run.phase, .result(.booked))
        run.proceed()
        XCTAssertEqual(run.current?.puzzle.id, puzzles[1].id, "puzzles come in the given order")
        run.choose(nil)
        let second = try XCTUnwrap(run.answer(wrong(puzzles[1]), progress: LearnerProgress(), today: today))
        XCTAssertEqual(second.outcome, .booked)
        XCTAssertEqual(second.result.correctFirstTry, false)
        XCTAssertEqual(second.damage, 0)
        run.proceed()
        XCTAssertEqual(run.phase, .finished)
        XCTAssertNil(run.current)
    }

    func testBookingDamageDoublesOnHit() throws {
        let puzzle = try XCTUnwrap(pool.first { $0.tema == "mva" && $0.kind == .quiz && Moves.canHit($0, regionCards: mvaCards) })
        var run = booking([puzzle])
        let e = try XCTUnwrap(run.current)
        XCTAssertNil(run.answer(right(puzzle), progress: LearnerProgress(), today: today), "a move must be picked first")
        let hit = try XCTUnwrap(e.moves.first { Moves.hits($0, puzzle) })
        run.choose(hit)
        let struck = try XCTUnwrap(run.answer(right(puzzle), progress: LearnerProgress(), today: today))
        XCTAssertEqual(struck.outcome, .booked)
        XCTAssertEqual(struck.damage, puzzle.vanskelighet * RegionRunRules.damagePerLevel * 2)

        var plain = booking([puzzle])
        plain.choose(nil)
        XCTAssertEqual(plain.answer(right(puzzle), progress: LearnerProgress(), today: today)?.damage,
                       puzzle.vanskelighet * RegionRunRules.damagePerLevel)

        // Answered earlier today (Trening): still booked, but no damage is farmed.
        var seen = LearnerProgress()
        Scheduler.record(AttemptResult(puzzleId: puzzle.id, correctFirstTry: true), on: today, progress: &seen)
        var again = booking([puzzle])
        again.choose(nil)
        XCTAssertEqual(again.answer(right(puzzle), progress: seen, today: today)?.damage, 0)
    }

    func testCorrectionTellsTheVerdict() throws {
        let puzzles = quizzes(2)
        let day = DayKey(year: 2026, month: 1, day: 14)
        let errors = puzzles.map { OpenError(puzzleId: $0.id, client: client.id, month: jan, day: day, boxBefore: 2) }
        var run = BilagRun(client: client, puzzles: puzzles, kind: .correction, errors: errors, bransjeCards: mvaCards, otherCards: otherCards, seed: 1)
        let e = try XCTUnwrap(run.current)
        XCTAssertEqual(e.context, .correction(client: client.id, day: day))
        XCTAssertEqual(e.stageBefore, .ung, "the box before the wrong booking, so the error is not given away")
        XCTAssertEqual(run.currentError, errors[0])
        run.choose(nil)
        let ok = try XCTUnwrap(run.answer(right(puzzles[0]), progress: LearnerProgress(), today: today))
        XCTAssertEqual(ok.outcome, .corrected(ok: true))
        XCTAssertTrue(ok.result.correctFirstTry)
        run.proceed()
        XCTAssertEqual(run.currentError, errors[1])
        run.choose(nil)
        let notOk = try XCTUnwrap(run.answer(wrong(puzzles[1]), progress: LearnerProgress(), today: today))
        XCTAssertEqual(notOk.outcome, .corrected(ok: false))
        XCTAssertFalse(notOk.result.correctFirstTry)
        run.proceed()
        XCTAssertEqual(run.phase, .finished)
    }

    func testStepChangesOnEveryEncounterEvenWithTheSamePuzzle() throws {
        let puzzle = try XCTUnwrap(quizzes(1).first)
        // The same bilag booked wrong in two years: both errors come back in one run.
        let errors = [jan, MonthKey(year: 2027, month: 1)].map {
            OpenError(puzzleId: puzzle.id, client: client.id, month: $0, day: $0.first, boxBefore: 2)
        }
        var run = BilagRun(client: client, puzzles: [puzzle], kind: .correction, errors: errors, bransjeCards: mvaCards, otherCards: otherCards, seed: 1)
        XCTAssertEqual(run.step, 1)
        run.choose(nil)
        _ = try XCTUnwrap(run.answer(right(puzzle), progress: LearnerProgress(), today: today))
        run.proceed()
        XCTAssertEqual(run.current?.puzzle.id, puzzle.id)
        XCTAssertEqual(run.currentError, errors[1])
        XCTAssertEqual(run.step, 2)
        run.choose(nil)
        _ = try XCTUnwrap(run.answer(right(puzzle), progress: LearnerProgress(), today: today))
        run.proceed()
        XCTAssertEqual(run.phase, .finished)
        XCTAssertEqual(run.step, 2)
    }

    func testEmptyPileIsFinishedAtOnce() {
        let run = booking([])
        XCTAssertNil(run.current)
        XCTAssertEqual(run.phase, .finished)
    }
}
