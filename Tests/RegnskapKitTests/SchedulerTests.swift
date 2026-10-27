import XCTest
@testable import RegnskapKit

final class SchedulerTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    var pool: [Puzzle] { Self.library.pool(includeDrafts: false) }
    let day = DayKey(string: "2026-10-26")!

    func testCorrectMovesUpWrongResetsToZero() {
        var progress = LearnerProgress()
        let id = pool[0].id
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, 1)
        XCTAssertEqual(progress.puzzles[id]?.attempts, 1)
        XCTAssertEqual(progress.puzzles[id]?.correct, 1)
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day.adding(days: 1), progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, 2)
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: false), on: day.adding(days: 4), progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, 0)
        XCTAssertEqual(progress.puzzles[id]?.attempts, 3)
        XCTAssertEqual(progress.puzzles[id]?.correct, 2)
        for i in 0..<6 { Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day.adding(days: 30 + i), progress: &progress) }
        XCTAssertEqual(progress.puzzles[id]?.box, 4, "box is capped at 4")
    }

    func testASecondCorrectAnswerTheSameDayKeepsTheBox() {
        var progress = LearnerProgress()
        let id = pool[0].id
        XCTAssertTrue(Scheduler.isFirstAnswer(of: id, on: day, progress: progress))
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertFalse(Scheduler.isFirstAnswer(of: id, on: day, progress: progress))
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, 1, "one promotion per day")
        XCTAssertEqual(progress.puzzles[id]?.attempts, 2)
        XCTAssertEqual(progress.puzzles[id]?.correct, 2)
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: false), on: day, progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, 0, "a wrong answer always resets")
        XCTAssertTrue(Scheduler.isFirstAnswer(of: id, on: day.adding(days: 1), progress: progress))
    }

    func testDueFollowsIntervals() {
        var progress = LearnerProgress()
        let id = pool[0].id
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.due, day.adding(days: 1))  // box 1 → 1 day
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day.adding(days: 1), progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.due, day.adding(days: 1 + 3))  // box 2 → 3 days
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: false), on: day.adding(days: 4), progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.due, day.adding(days: 4))  // box 0 → due at once
        XCTAssertEqual(progress.puzzles[id]?.lastSeen, day.adding(days: 4))
    }

    func testDailySetPrefersDueThenWeakTopic() {
        var progress = LearnerProgress()
        let dueOne = pool.first { $0.tema == "lonn" }!
        Scheduler.record(AttemptResult(puzzleId: dueOne.id, correctFirstTry: false), on: day.adding(days: -2), progress: &progress)
        // Make mva strong: every mva puzzle in box 3.
        for p in pool where p.tema == "mva" { progress.puzzles[p.id] = PuzzleProgress(box: 3, attempts: 1, correct: 1, lastSeen: day.adding(days: -1), due: day.adding(days: 6)) }
        let set = Scheduler.startDay(day, count: 3, pool: pool, progress: &progress)
        XCTAssertEqual(set.count, 3)
        XCTAssertEqual(set[0].id, dueOne.id, "the due review comes first")
        XCTAssertFalse(set.dropFirst().contains { $0.tema == "mva" }, "a strong topic is not picked for new puzzles")
        XCTAssertEqual(Set(set.map(\.id)).count, 3)
        XCTAssertEqual(progress.days[day.string]?.set, set.map(\.id))
    }

    func testDailySetIncludesEdgeCase() {
        var progress = LearnerProgress()
        let set = Scheduler.startDay(day, count: 3, pool: pool, progress: &progress)
        XCTAssertTrue(set.contains(where: \.isEdgeCase), set.map(\.id).joined(separator: ","))
    }

    func testDailySetIsStablePerDay() {
        var a = LearnerProgress(), b = LearnerProgress()
        let first = Scheduler.startDay(day, count: 3, pool: pool, progress: &a)
        let again = Scheduler.startDay(day, count: 3, pool: pool, progress: &a)
        XCTAssertEqual(first.map(\.id), again.map(\.id), "the stored set is returned on a second call")
        let fresh = Scheduler.startDay(day, count: 3, pool: pool, progress: &b)
        XCTAssertEqual(first.map(\.id), fresh.map(\.id), "the same day and progress give the same set")
        var c = LearnerProgress()
        let otherDay = Scheduler.startDay(day.adding(days: 1), count: 3, pool: pool, progress: &c)
        XCTAssertNotEqual(first.map(\.id), otherDay.map(\.id), "another day shuffles differently")
    }

    func testDailySetWithTinyPool() {
        var progress = LearnerProgress()
        let tiny = Array(pool.prefix(2))
        let set = Scheduler.startDay(day, count: 3, pool: tiny, progress: &progress)
        XCTAssertEqual(set.count, 2)
        XCTAssertEqual(Set(set.map(\.id)).count, 2)
        for p in tiny { Scheduler.record(AttemptResult(puzzleId: p.id, correctFirstTry: true), on: day, progress: &progress) }
        var next = LearnerProgress(puzzles: progress.puzzles, days: [:])
        let tomorrow = Scheduler.startDay(day.adding(days: 1), count: 3, pool: tiny, progress: &next)
        XCTAssertEqual(tomorrow.count, 2, "all seen and due: still a full set from the pool")
        var empty = LearnerProgress()
        XCTAssertEqual(Scheduler.startDay(day, count: 3, pool: [], progress: &empty).count, 0)
    }

    func testStreakCountsConsecutiveCompletedDays() {
        var progress = LearnerProgress()
        for offset in [-3, -2, -1] {
            let d = day.adding(days: offset)
            let set = Scheduler.startDay(d, count: 2, pool: pool, progress: &progress)
            for p in set { Scheduler.record(AttemptResult(puzzleId: p.id, correctFirstTry: offset != -2), on: d, progress: &progress) }
        }
        XCTAssertEqual(progress.streak(today: day), 3, "yesterday completed counts even before today is done; wrong answers still complete the day")
        let today = Scheduler.startDay(day, count: 2, pool: pool, progress: &progress)
        XCTAssertEqual(progress.streak(today: day), 3)
        Scheduler.record(AttemptResult(puzzleId: today[0].id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertEqual(progress.streak(today: day), 3, "today is not done yet")
        Scheduler.record(AttemptResult(puzzleId: today[1].id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertEqual(progress.streak(today: day), 4)
        XCTAssertEqual(progress.streak(today: day.adding(days: 2)), 0, "a gap breaks the streak")
        XCTAssertTrue(progress.days[day.string]!.done)
    }

    func testMasteryAndLevel() {
        var progress = LearnerProgress()
        XCTAssertEqual(progress.mastery(tema: "mva", pool: pool), 0)
        for p in pool where p.tema == "mva" { progress.puzzles[p.id] = PuzzleProgress(box: 3, attempts: 1, correct: 1, lastSeen: day, due: day) }
        XCTAssertEqual(progress.mastery(tema: "mva", pool: pool), 1)
        XCTAssertEqual(progress.level(pool: pool), 2)
        XCTAssertEqual(progress.mastery(tema: "nope", pool: pool), 0)
    }

    func testStartDayPrunesPuzzlesThatLeftThePool() {
        var progress = LearnerProgress()
        let kept = pool[0].id
        progress.days[day.string] = DayRecord(day: day, set: [kept, "slettet-oppgave"], completed: [kept])
        let set = Scheduler.startDay(day, count: 3, pool: pool, progress: &progress)
        XCTAssertEqual(set.map(\.id), [kept])
        XCTAssertEqual(progress.days[day.string]?.set, [kept], "the stored set follows the pool, so the day can still be completed")
        XCTAssertEqual(progress.days[day.string]?.done, true)
        XCTAssertEqual(progress.days[day.string]?.remaining, 0)
    }

    func testStartDayToleratesEntriesWithoutDue() {
        var progress = LearnerProgress()
        progress.puzzles[pool[0].id] = PuzzleProgress(box: 1, attempts: 1, correct: 1, lastSeen: day.adding(days: -5), due: nil)
        progress.puzzles[pool[1].id] = PuzzleProgress(box: 2, attempts: 2, correct: 2, lastSeen: day.adding(days: -9), due: nil)
        let set = Scheduler.startDay(day, count: 2, pool: pool, progress: &progress)
        XCTAssertEqual(Set(set.map(\.id)), [pool[0].id, pool[1].id], "no due date counts as due now")
    }

    func testRecordClampsAnOutOfRangeBox() {
        var progress = LearnerProgress()
        let id = pool[0].id
        progress.puzzles[id] = PuzzleProgress(box: 9)
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, Scheduler.topBox)
        progress.puzzles[id] = PuzzleProgress(box: -3)
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, 1)
    }
}
