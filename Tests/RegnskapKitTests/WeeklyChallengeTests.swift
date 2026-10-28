import XCTest
@testable import RegnskapKit

final class WeeklyChallengeTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)

    func testTenApprovedQuickPuzzlesSameForEveryoneRegardlessOfOrderAndDrafts() {
        let approved = Self.library.approved
        let a = WeeklyChallenge.puzzles(approved: approved, week: (2026, 44))
        let b = WeeklyChallenge.puzzles(approved: approved.shuffled(), week: (2026, 44))
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.count, WeeklyChallenge.count)
        XCTAssertTrue(a.allSatisfy { LightningRound.quickKinds.contains($0.kind) && $0.status == .godkjent })
        XCTAssertEqual(Set(a.map(\.id)).count, a.count)
        XCTAssertNotEqual(a.map(\.id), WeeklyChallenge.puzzles(approved: approved, week: (2026, 45)).map(\.id))
        XCTAssertEqual(WeeklyChallenge.seed(for: (2026, 44)), 202644)
    }

    func testResultCode() {
        XCTAssertEqual(WeeklyChallenge.resultCode(week: 44, score: 1850, correct: 9), "UKE 44 · 1\u{202F}850 p · 9/10")
    }

    func testARoundWithoutAClockNeverRunsOut() {
        var r = LightningRound(pool: WeeklyChallenge.puzzles(approved: Self.library.approved, week: (2026, 44)), tema: nil, progress: LearnerProgress(), today: DayKey(string: "2026-10-28")!, seed: 202644, startedAt: 0, duration: .infinity)
        r.tick(at: 100_000)
        XCTAssertEqual(r.phase, .question)
        XCTAssertEqual(r.remaining(at: 100_000), .infinity)
        XCTAssertEqual(r.queue.count, 10)
    }
}
