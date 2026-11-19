import XCTest
@testable import RegnskapKit

final class CelebrationTests: XCTestCase {
    func testNoTransitionWhenAlreadyDone() {
        XCTAssertNil(Celebrations.forDayTransition(wasDone: true, isDone: true, streak: 7))
    }

    func testNoTransitionWhenStillNotDone() {
        XCTAssertNil(Celebrations.forDayTransition(wasDone: false, isDone: false, streak: 3))
    }

    func testPlainCompletionOnNonMilestoneStreak() {
        XCTAssertEqual(Celebrations.forDayTransition(wasDone: false, isDone: true, streak: 3), .dayCompleted)
        XCTAssertEqual(Celebrations.forDayTransition(wasDone: false, isDone: true, streak: 50), .dayCompleted)
    }

    func testMilestoneCompletion() {
        for streak in [7, 30, 100] {
            XCTAssertEqual(Celebrations.forDayTransition(wasDone: false, isDone: true, streak: streak), .streakMilestone(streak))
        }
    }
}
