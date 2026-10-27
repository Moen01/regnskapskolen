import XCTest
@testable import RegnskapKit

final class DeadlinesTests: XCTestCase {
    private func deadlines() throws -> Deadlines {
        Deadlines(rates: try Rates(url: ContentLocator.repoContent.appendingPathComponent("satser.json")))
    }

    func testMVADeadlines2026() throws {
        let d = try deadlines()
        XCTAssertEqual(d.mvaFrister(year: 2026).map(\.string),
                       ["2026-04-10", "2026-06-10", "2026-08-31", "2026-10-12", "2026-12-10", "2027-02-10"])
        XCTAssertEqual(d.mvaTermin(for: DayKey(string: "2026-05-14")!).nr, 3)
        XCTAssertEqual(d.mvaTermin(for: DayKey(string: "2026-12-31")!).maaneder, [11, 12])
        XCTAssertEqual(d.mvaAarligFrist(year: 2026).string, "2027-03-10")
    }

    func testDeadlineRollsOverWeekendAndHoliday() throws {
        let d = try deadlines()
        XCTAssertEqual(d.agaFrist(termin: 1, year: 2026).string, "2026-03-16")  // 15.03.2026 is a Sunday
        XCTAssertEqual(d.agaFrist(termin: 5, year: 2026).string, "2026-11-16")
        XCTAssertEqual(d.agaFrist(termin: 6, year: 2026).string, "2027-01-15")
        XCTAssertEqual(d.ameldingFrist(forMonth: 4, year: 2026).string, "2026-05-05")
        XCTAssertEqual(d.ameldingFrist(forMonth: 12, year: 2026).string, "2027-01-05")
        // 5 April 2026 is 1. påskedag (Sunday) and 6 April is 2. påskedag: the a-melding for March waits until the 7th.
        XCTAssertEqual(d.ameldingFrist(forMonth: 3, year: 2026).string, "2026-04-07")
    }

    func testForskuddstrekkFrist() throws {
        let d = try deadlines()
        XCTAssertEqual(d.forskuddstrekkFrist(utbetalt: DayKey(string: "2026-10-09")!).string, "2026-10-12")
        XCTAssertEqual(d.forskuddstrekkFrist(utbetalt: DayKey(string: "2026-10-13")!).string, "2026-10-14")
    }

    func testAarsregnskapAndSkattemelding() throws {
        let d = try deadlines()
        XCTAssertEqual(d.aarsregnskapFrist(year: 2025).string, "2026-07-31")
        XCTAssertEqual(d.aarsregnskapFrist(year: 2026).string, "2027-08-02")  // 31.07.2027 is a Saturday
        XCTAssertEqual(d.aarsregnskapFastsettesFrist(year: 2025).string, "2026-06-30")
        XCTAssertEqual(d.skattemeldingFrist(year: 2025).string, "2026-06-01")  // 31.05.2026 is a Sunday
    }
}
