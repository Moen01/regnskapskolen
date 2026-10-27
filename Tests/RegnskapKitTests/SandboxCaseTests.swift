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
            let model = try XCTUnwrap(c.fasitJournal, "\(c.id) mangler fasitJournal")
            XCTAssertTrue(JournalValidator.problems(model, chart: Self.library.chart, rates: Self.library.rates).isEmpty, c.id)
            let diffs = c.compare(journal: model, chart: Self.library.chart)
            XCTAssertTrue(diffs.isEmpty, "\(c.id): " + diffs.map { "\($0.konto) forventet \($0.forventet) fikk \($0.faktisk)" }.joined(separator: "; "))
            for nr in c.fasitSaldobalanse.keys { XCTAssertTrue(Self.library.chart.contains(nr), "\(c.id): konto \(nr)") }
        }
    }

    func testCompareReportsMissingAndWrongAccounts() throws {
        let c = SandboxCase.load(folder: ContentLocator.repoContent.appendingPathComponent("sandkasse"))[0]
        let empty = Journal(entries: [])
        let diffs = c.compare(journal: empty, chart: Self.library.chart)
        XCTAssertEqual(diffs.count, c.fasitSaldobalanse.filter { $0.value != 0 }.count)
        XCTAssertTrue(diffs.allSatisfy { $0.faktisk == 0 })
    }
}
