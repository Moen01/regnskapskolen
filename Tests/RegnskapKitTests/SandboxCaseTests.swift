import XCTest
@testable import RegnskapKit

final class SandboxCaseTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)

    func testCasesLoadAndModelJournalMatchesExpected() throws {
        let cases = SandboxCase.load(folder: ContentLocator.repoContent.appendingPathComponent("sandkasse"))
        XCTAssertGreaterThanOrEqual(cases.count, 1)
        for c in cases {
            XCTAssertFalse(c.hendelser.isEmpty, c.id)
            XCTAssertFalse(c.lov.isEmpty, c.id)
            XCTAssertEqual(SandboxCaseValidator.problems(c, chart: Self.library.chart, rates: Self.library.rates), [], c.id)
        }
    }

    func testCompareReportsMissingAndWrongAccounts() throws {
        let c = SandboxCase.load(folder: ContentLocator.repoContent.appendingPathComponent("sandkasse"))[0]
        let empty = Journal(entries: [])
        let diffs = c.compare(journal: empty, chart: Self.library.chart)
        XCTAssertEqual(diffs.count, c.fasitSaldobalanse.filter { $0.value != 0 }.count)
        XCTAssertTrue(diffs.allSatisfy { $0.faktisk == 0 })
    }

    func testKafeHasAStatementThatReconciles() throws {
        let kafe = try XCTUnwrap(SandboxCase.load(folder: ContentLocator.repoContent.appendingPathComponent("sandkasse")).first { $0.id == "kafe-001" })
        let statement = try XCTUnwrap(kafe.kontoutskrift)
        XCTAssertEqual(statement.linjer.count, 8)
        XCTAssertEqual(statement.utgaaende, 94900)
        XCTAssertEqual(statement.linjer.map(\.bilag), [[1], [2], [4], [5], [7], [8], [9], [11]])
        XCTAssertEqual(SandboxCaseValidator.problems(kafe, chart: Self.library.chart, rates: Self.library.rates), [])
    }
}
