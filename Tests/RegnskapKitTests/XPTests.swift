import XCTest
@testable import RegnskapKit

final class XPTests: XCTestCase {
    func testLevelsFollowTheThresholds() {
        XCTAssertEqual(XP.level(for: 0).navn, "Lærling")
        XCTAssertEqual(XP.level(for: 499).navn, "Lærling")
        XCTAssertEqual(XP.level(for: 500).navn, "Regnskapsmedarbeider")
        XCTAssertEqual(XP.level(for: 1500).navn, "Regnskapsfører")
        XCTAssertEqual(XP.level(for: 4000).navn, "Seniorregnskapsfører")
        XCTAssertEqual(XP.level(for: 10000).navn, "Partner")
        XCTAssertEqual(XP.level(for: 0).neste, 500)
        XCTAssertEqual(XP.level(for: 4000).neste, 10000)
        XCTAssertNil(XP.level(for: 12000).neste)
        XCTAssertEqual(XP.levels.map(\.terskel), [0, 500, 1500, 4000, 10000])
    }

    func testPointsForPuzzlesAndRounds() {
        XCTAssertEqual(XP.forPuzzle(vanskelighet: 3, correctFirstTry: true), 30)
        XCTAssertEqual(XP.forPuzzle(vanskelighet: 3, correctFirstTry: false), 3)
        XCTAssertEqual(XP.forRound(score: 1234), 123)
    }

    func testSeedFromHistory() {
        var p = LearnerProgress()
        p.puzzles["a"] = PuzzleProgress(box: 2, attempts: 3, correct: 2)
        p.puzzles["b"] = PuzzleProgress(box: 0, attempts: 1, correct: 0)
        XCTAssertEqual(XP.seed(from: p), 2 * 10 + 2 * 3)
        XCTAssertEqual(XP.seed(from: LearnerProgress()), 0)
    }
}
