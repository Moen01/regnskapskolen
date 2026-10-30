import XCTest
@testable import RegnskapKit

final class TownPayrollTests: XCTestCase {
    private func deadlines() throws -> Deadlines {
        Deadlines(rates: try Rates(url: ContentLocator.repoContent.appendingPathComponent("satser.json")))
    }

    /// The fixture shop with its staff and pay day replaced.
    private func client(ansatte: Int, lonnsdag: Int?) throws -> TownClient {
        let url = TownContentTests.fixtureTown.appendingPathComponent("klienter/butikken.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["ansatte"] = ansatte
        json["lonnsdag"] = lonnsdag
        return try JSONDecoder().decode(TownClient.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func count(_ list: [TownDeadline], _ test: (DeadlineKind) -> Bool) -> Int { list.filter { test($0.kind) }.count }

    func testCafeWithStaffGetsThirtyPayrollDeadlines() throws {
        let d = try deadlines()
        let list = DeadlinePlanner.deadlines(for: try client(ansatte: 4, lonnsdag: 20), year: 2026, deadlines: d)
        XCTAssertEqual(count(list) { if case .amelding = $0 { true } else { false } }, 12)
        XCTAssertEqual(count(list) { if case .forskuddstrekk = $0 { true } else { false } }, 12)
        XCTAssertEqual(count(list) { if case .aga = $0 { true } else { false } }, 6)
        let first = try XCTUnwrap(list.first { $0.kind == .amelding(month: MonthKey(year: 2026, month: 1)) })
        XCTAssertEqual(first.day, d.ameldingFrist(forMonth: 1, year: 2026))
        XCTAssertEqual(first.kind.id, "amelding-2026-01")
        XCTAssertEqual(first.label, "05.02 A-MELDING JAN")
        XCTAssertEqual(first.shortLabel, "05.02 AMELD1")
        let trekk = try XCTUnwrap(list.first { $0.kind == .forskuddstrekk(month: MonthKey(year: 2026, month: 1)) })
        XCTAssertEqual(trekk.kind.id, "trekk-2026-01")
        XCTAssertEqual(trekk.label, "21.01 TREKK JAN")
        XCTAssertEqual(trekk.kind.shortName, "TREKK1")
        let aga = try XCTUnwrap(list.first { $0.kind == .aga(termin: 1, year: 2026) })
        XCTAssertEqual(aga.kind.id, "aga-2026-1")
        XCTAssertEqual(aga.label, "16.03 AGA 1. TERMIN")
        XCTAssertEqual(aga.kind.shortName, "AGA1")
        XCTAssertEqual(aga.kind.months(rates: d.rates), d.rates.agaTerminer[0].maaneder.map { MonthKey(year: 2026, month: $0) })
        XCTAssertEqual(trekk.kind.months(rates: d.rates), [])
    }

    func testShopWithoutStaffGetsNoPayrollDeadlines() throws {
        let list = DeadlinePlanner.deadlines(for: try client(ansatte: 0, lonnsdag: nil), year: 2026, deadlines: try deadlines())
        XCTAssertEqual(count(list) { $0.isPayroll }, 0)
        XCTAssertEqual(list.count, 8, "six vat terms, skattemelding and årsregnskap")
    }

    func testTrekkAfterFridayPayDayIsMonday() throws {
        let d = try deadlines()
        let list = DeadlinePlanner.deadlines(for: try client(ansatte: 2, lonnsdag: 24), year: 2026, deadlines: d)
        let trekk = try XCTUnwrap(list.first { $0.kind == .forskuddstrekk(month: MonthKey(year: 2026, month: 4)) })
        XCTAssertEqual(trekk.day, d.forskuddstrekkFrist(utbetalt: DayKey(year: 2026, month: 4, day: 24)))
        XCTAssertEqual(trekk.day.weekday, 1)
    }

    func testUpcomingAcrossNewYearShowsDecemberPayroll() throws {
        let d = try deadlines()
        let upcoming = DeadlinePlanner.upcoming(clients: [try client(ansatte: 2, lonnsdag: 20)], from: DayKey(year: 2026, month: 12, day: 28), days: 21, deadlines: d)
        let kinds = upcoming.map(\.kind)
        XCTAssertTrue(kinds.contains(.amelding(month: MonthKey(year: 2026, month: 12))))
        XCTAssertTrue(kinds.contains(.aga(termin: 6, year: 2026)))
    }

    func testOpensIsPayDayForTrekkAndDayAfterMonthForTheRest() throws {
        let d = try deadlines()
        let list = DeadlinePlanner.deadlines(for: try client(ansatte: 2, lonnsdag: 20), year: 2026, deadlines: d)
        func opens(_ kind: DeadlineKind) throws -> DayKey { try XCTUnwrap(list.first { $0.kind == kind }).opens }
        XCTAssertEqual(try opens(.forskuddstrekk(month: MonthKey(year: 2026, month: 3))), DayKey(year: 2026, month: 3, day: 20))
        XCTAssertEqual(try opens(.amelding(month: MonthKey(year: 2026, month: 12))), DayKey(year: 2027, month: 1, day: 1))
        XCTAssertEqual(try opens(.aga(termin: 1, year: 2026)), DayKey(year: 2026, month: 3, day: 1))
        XCTAssertEqual(try opens(.mva(termin: 1, year: 2026)), DayKey(year: 2026, month: 3, day: 1))
        XCTAssertEqual(try opens(.mva(termin: 6, year: 2026)), DayKey(year: 2027, month: 1, day: 1))
    }
}
