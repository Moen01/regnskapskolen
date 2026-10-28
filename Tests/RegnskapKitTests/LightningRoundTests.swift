import XCTest
@testable import RegnskapKit

final class LightningRoundTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    var pool: [Puzzle] { Self.library.pool(includeDrafts: true) }
    let today = DayKey(string: "2026-10-27")!

    func correctAttempt(for puzzle: Puzzle) -> PuzzleAttempt {
        switch puzzle.payload {
        case .quiz(let q): .quiz(q.svar)
        case .vat(let v): .vat(behandling: v.fasit.behandling, fradrag: v.fasit.fradrag)
        case .case(let c): .case(c.svar)
        default: fatalError("not a quick kind")
        }
    }
    func wrongAttempt(for puzzle: Puzzle) -> PuzzleAttempt {
        switch puzzle.payload {
        case .quiz(let q): .quiz((q.svar + 1) % q.alternativer.count)
        case .vat: .vat(behandling: "ingen-slik-kode", fradrag: nil)
        case .case: .case("ingen-slik-nokkel")
        default: fatalError("not a quick kind")
        }
    }
    func round(tema: String? = nil, progress: LearnerProgress = LearnerProgress(), seed: UInt64 = 1) -> LightningRound {
        LightningRound(pool: pool, tema: tema, progress: progress, today: today, seed: seed, startedAt: 0)
    }

    func testOnlyQuickKindsAndTheTopicFilter() {
        XCTAssertTrue(LightningRound.eligible(pool: pool, tema: nil).allSatisfy { LightningRound.quickKinds.contains($0.kind) })
        XCTAssertTrue(LightningRound.eligible(pool: pool, tema: "mva").allSatisfy { $0.tema == "mva" })
        XCTAssertTrue(LightningRound.topics(in: pool).contains("mva"))
        XCTAssertTrue(LightningRound.topics(in: pool).allSatisfy { LightningRound.eligible(pool: pool, tema: $0).count >= LightningRound.minimumTopicSize })
    }

    func testSeededOrderIsStableAndFree() {
        XCTAssertEqual(round(seed: 7).queue.map(\.id), round(seed: 7).queue.map(\.id))
        XCTAssertNotEqual(round(seed: 7).queue.map(\.id), round(seed: 8).queue.map(\.id))
        XCTAssertEqual(Set(round().queue.map(\.id)).count, round().queue.count, "no repeats")
    }

    func testOrderPutsDueAndLowBoxFirstAndTodaysLast() {
        let eligible = LightningRound.eligible(pool: pool, tema: nil)
        let strong = eligible[0], weak = eligible[1], seenToday = eligible[2]
        var progress = LearnerProgress()
        progress.puzzles[strong.id] = PuzzleProgress(box: 4, attempts: 4, correct: 4, lastSeen: today.adding(days: -2), due: today.adding(days: 19))
        progress.puzzles[weak.id] = PuzzleProgress(box: 0, attempts: 1, correct: 0, lastSeen: today.adding(days: -1), due: today.adding(days: -1))
        progress.puzzles[seenToday.id] = PuzzleProgress(box: 1, attempts: 1, correct: 1, lastSeen: today, due: today.adding(days: 1))
        let ids = round(progress: progress).queue.map(\.id)
        XCTAssertLessThan(ids.firstIndex(of: weak.id)!, ids.firstIndex(of: strong.id)!)
        XCTAssertEqual(ids.last, seenToday.id)
    }

    func testScoringAndCombo() {
        var r = round()
        let p1 = r.current!
        let e1 = r.answer(correctAttempt(for: p1), at: 1)!
        XCTAssertTrue(e1.verdict.correct)
        XCTAssertEqual(e1.points, 100 * p1.vanskelighet)
        XCTAssertEqual(e1.result, AttemptResult(puzzleId: p1.id, correctFirstTry: true))
        XCTAssertEqual(r.phase, .question, "a right answer goes straight on")
        let p2 = r.current!
        XCTAssertEqual(r.answer(correctAttempt(for: p2), at: 2)!.points, Int(Double(100 * p2.vanskelighet) * 1.25))
        XCTAssertEqual(r.combo.multiplier, 1.5)
        let p3 = r.current!
        let e3 = r.answer(wrongAttempt(for: p3), at: 3)!
        XCTAssertFalse(e3.verdict.correct)
        XCTAssertEqual(e3.points, 0)
        XCTAssertEqual(e3.result, AttemptResult(puzzleId: p3.id, correctFirstTry: false))
        XCTAssertEqual(r.combo.multiplier, 1.0)
        XCTAssertEqual(r.combo.best, 1.5)
        XCTAssertEqual(r.score, e1.points + Int(Double(100 * p2.vanskelighet) * 1.25))
        XCTAssertEqual(r.correct, 2); XCTAssertEqual(r.answered, 3)
        XCTAssertEqual(r.phase, .feedback(since: 3))
        XCTAssertNil(r.answer(correctAttempt(for: r.current!), at: 3.2), "no answers during feedback")
    }

    func testClockPausesDuringFeedback() {
        var r = round()
        XCTAssertEqual(r.remaining(at: 10), 80)
        _ = r.answer(wrongAttempt(for: r.current!), at: 10)
        XCTAssertEqual(r.remaining(at: 20), 80, "paused")
        r.next(at: 11)
        XCTAssertEqual(r.phase, .feedback(since: 10), "not before 1.5 s")
        r.next(at: 12)
        XCTAssertEqual(r.phase, .question)
        XCTAssertEqual(r.remaining(at: 12), 80)
        XCTAssertEqual(r.remaining(at: 22), 70)
    }

    func testRoundEndsWhenTimeIsUpOrThePoolIsEmpty() {
        var r = round()
        r.tick(at: 89.9); XCTAssertEqual(r.phase, .question)
        r.tick(at: 90); XCTAssertEqual(r.phase, .finished)
        XCTAssertNil(r.answer(correctAttempt(for: r.current!), at: 90.1), "late answers do not count")
        XCTAssertEqual(r.remaining(at: 200), 0)
        var tiny = LightningRound(pool: Array(LightningRound.eligible(pool: pool, tema: nil).prefix(2)), tema: nil, progress: LearnerProgress(), today: today, seed: 1, startedAt: 0)
        _ = tiny.answer(correctAttempt(for: tiny.current!), at: 1)
        _ = tiny.answer(correctAttempt(for: tiny.current!), at: 2)
        XCTAssertEqual(tiny.phase, .finished)
        XCTAssertNil(tiny.current)
        let empty = LightningRound(pool: [], tema: nil, progress: LearnerProgress(), today: today, seed: 1, startedAt: 0)
        XCTAssertEqual(empty.phase, .finished)
        var short = LightningRound(pool: pool, tema: nil, progress: LearnerProgress(), today: today, seed: 1, startedAt: 0, duration: 10)
        short.tick(at: 10); XCTAssertEqual(short.phase, .finished, "a custom duration ends the round")
    }

    func testSummary() {
        var r = round()
        let e = r.answer(correctAttempt(for: r.current!), at: 1)!
        r.finish()
        let s = r.summary
        XCTAssertEqual(s.game, .lynrunde); XCTAssertNil(s.tema)
        XCTAssertEqual(s.score, e.points); XCTAssertEqual(s.correct, 1); XCTAssertEqual(s.answered, 1)
        XCTAssertEqual(s.bestCombo, 1.25); XCTAssertEqual(s.xp, e.points / 10)
    }
}
