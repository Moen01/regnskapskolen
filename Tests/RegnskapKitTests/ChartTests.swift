import XCTest
@testable import RegnskapKit

final class ChartTests: XCTestCase {
    func testLoadsRepoChart() throws {
        let chart = try ChartOfAccounts(url: ContentLocator.repoContent.appendingPathComponent("kontoplan.json"))
        XCTAssertGreaterThanOrEqual(chart.all.count, 70)
        let bank = try XCTUnwrap(chart.account("1920"))
        XCTAssertEqual(bank.navn, "Bankinnskudd")
        XCTAssertEqual(bank.type, .eiendel)
        XCTAssertEqual(bank.okerPa, .debet)
        XCTAssertEqual(bank.rapport, .balanse)
        XCTAssertEqual(bank.klasse, 1)
        XCTAssertEqual(bank.gruppe, "19")
        let utgaaende = try XCTUnwrap(chart.account("2700"))
        XCTAssertEqual(utgaaende.type, .gjeld)
        XCTAssertEqual(utgaaende.okerPa, .kredit)
        XCTAssertEqual(chart.account("2710")?.okerPa, .debet)
        XCTAssertEqual(chart.account("3000")?.rapport, .resultat)
        XCTAssertEqual(chart.classes[1], "Eiendeler")
        XCTAssertEqual(chart.groups["19"], "Bankinnskudd, kontanter og lignende")
        XCTAssertNil(chart.account("9999"))
    }

    func testEveryAccountSitsInItsClassAndGroup() throws {
        let chart = try ChartOfAccounts(url: ContentLocator.repoContent.appendingPathComponent("kontoplan.json"))
        for a in chart.all {
            XCTAssertEqual(a.nr.count, 4, a.nr)
            XCTAssertEqual(String(a.nr.prefix(1)), String(a.klasse), a.nr)
            XCTAssertEqual(String(a.nr.prefix(2)), a.gruppe, a.nr)
            XCTAssertNotNil(chart.groups[a.gruppe], "gruppe \(a.gruppe) mangler navn (\(a.nr))")
            XCTAssertEqual(a.rapport, a.klasse <= 2 ? .balanse : .resultat, a.nr)
        }
    }
}
