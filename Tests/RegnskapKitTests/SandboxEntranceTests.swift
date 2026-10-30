import XCTest
@testable import RegnskapKit

final class SandboxEntranceTests: XCTestCase {
    func testTheActiveCaseIsShownAsItIs() {
        XCTAssertEqual(SandboxEntrance.decide(caseId: "bank-001", activeCaseId: "bank-001", journalEmpty: false, exists: true), .show)
    }

    /// A half-done case is never wiped: the player empties the sandbox first.
    func testAnotherCaseWithEntriesIsKept() {
        XCTAssertEqual(SandboxEntrance.decide(caseId: "bank-001", activeCaseId: "kafe-001", journalEmpty: false, exists: true), .busy)
        XCTAssertEqual(SandboxEntrance.decide(caseId: "bank-001", activeCaseId: nil, journalEmpty: false, exists: true), .busy)
    }

    func testAnEmptyJournalStartsTheCase() {
        XCTAssertEqual(SandboxEntrance.decide(caseId: "bank-001", activeCaseId: "kafe-001", journalEmpty: true, exists: true), .start)
        XCTAssertEqual(SandboxEntrance.decide(caseId: "bank-001", activeCaseId: nil, journalEmpty: true, exists: false), .missing)
    }

    func testTexts() {
        XCTAssertEqual(SandboxEntrance.busy.texts, ["Sandkassen har en annen sak.", "Tøm den først."])
        XCTAssertEqual(SandboxEntrance.missing.texts, ["Saken finnes ikke ennå."])
        XCTAssertEqual(SandboxEntrance.show.texts, [])
    }
}
