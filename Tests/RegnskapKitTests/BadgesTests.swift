import XCTest
@testable import RegnskapKit

final class BadgesTests: XCTestCase {
    let day = DayKey(string: "2026-10-27")!
    var progress = LearnerProgress()
    func award(_ event: GameEvent) -> [String] { Badges.award(event, on: day, progress: &progress).map(\.id) }

    func testCatalogHasEightBadgesWithUniqueIds() {
        XCTAssertEqual(Badges.all.count, 8)
        XCTAssertEqual(Set(Badges.all.map(\.id)).count, 8)
        XCTAssertEqual(Badges.all.map(\.id), ["mva-mester", "fristfri", "null-differanse", "bank-avstemt", "lynrask", "reflekser", "sju-dager", "tretti-dager"])
    }

    func testMvaMesterNeedsTwentyInARowAndIsAwardedOnce() {
        for _ in 0..<19 { XCTAssertEqual(award(.puzzleAnswered(kind: .mva, correctFirstTry: true)), []) }
        XCTAssertEqual(award(.puzzleAnswered(kind: .mva, correctFirstTry: true)), ["mva-mester"])
        XCTAssertEqual(progress.game.badges["mva-mester"], day)
        for _ in 0..<20 { _ = award(.puzzleAnswered(kind: .mva, correctFirstTry: true)) }
        XCTAssertEqual(progress.game.badges.count, 1)
    }

    func testAWrongMvaAnswerResetsTheRun() {
        for _ in 0..<19 { _ = award(.puzzleAnswered(kind: .mva, correctFirstTry: true)) }
        XCTAssertEqual(award(.puzzleAnswered(kind: .mva, correctFirstTry: false)), [])
        XCTAssertEqual(progress.game.counters[Badges.mvaRun], 0)
        XCTAssertEqual(award(.puzzleAnswered(kind: .quiz, correctFirstTry: true)), [], "other kinds do not touch the mva run")
        XCTAssertEqual(progress.game.counters[Badges.mvaRun], 0)
    }

    func testFristfriIsCumulative() {
        for _ in 0..<5 { _ = award(.puzzleAnswered(kind: .frist, correctFirstTry: true)) }
        _ = award(.puzzleAnswered(kind: .frist, correctFirstTry: false))
        for _ in 0..<4 { XCTAssertEqual(award(.puzzleAnswered(kind: .frist, correctFirstTry: true)), []) }
        XCTAssertEqual(award(.puzzleAnswered(kind: .frist, correctFirstTry: true)), ["fristfri"])
    }

    func testRoundBadges() {
        XCTAssertEqual(award(.roundFinished(game: .lynrunde, tema: nil, score: 1499, correct: 10)), [])
        XCTAssertEqual(award(.roundFinished(game: .lynrunde, tema: "mva", score: 1500, correct: 10)), [], "a topic round never gives lynrask")
        XCTAssertEqual(award(.roundFinished(game: .lynrunde, tema: nil, score: 1500, correct: 10)), ["lynrask"])
        XCTAssertEqual(award(.roundFinished(game: .debetKredit, tema: nil, score: 1500, correct: 29)), [], "a drill score never gives lynrask")
        XCTAssertEqual(award(.roundFinished(game: .debetKredit, tema: nil, score: 0, correct: 30)), ["reflekser"])
    }

    func testStreakAndSandboxBadges() {
        XCTAssertEqual(award(.dayCompleted(streak: 6)), [])
        XCTAssertEqual(award(.dayCompleted(streak: 7)), ["sju-dager"])
        XCTAssertEqual(award(.dayCompleted(streak: 30)), ["tretti-dager"])
        XCTAssertEqual(award(.caseMatched), ["null-differanse"])
        XCTAssertEqual(award(.bankReconciled), ["bank-avstemt"])
        var fresh = LearnerProgress()
        XCTAssertEqual(Badges.award(.dayCompleted(streak: 30), on: day, progress: &fresh).map(\.id), ["sju-dager", "tretti-dager"], "a long streak gives both")
    }
}
