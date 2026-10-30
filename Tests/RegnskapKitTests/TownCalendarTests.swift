import XCTest
@testable import RegnskapKit

final class TownCalendarTests: XCTestCase {
    private func deadlines() throws -> Deadlines {
        Deadlines(rates: try Rates(url: ContentLocator.repoContent.appendingPathComponent("satser.json")))
    }

    private func town() throws -> TownContent { try TownContent.load(folder: TownContentTests.fixtureTown) }

    func testRestaurantGetsSixVatDeadlines2026() throws {
        let d = try deadlines()
        let client = try XCTUnwrap(try town().client("butikken"))
        // The annual deadlines (skattemelding, årsregnskap) come after the six terms.
        let list = DeadlinePlanner.deadlines(for: client, year: 2026, deadlines: d).filter { !$0.kind.isAnnual }
        XCTAssertEqual(list.count, 6)
        XCTAssertEqual(list.first?.day, d.mvaFrist(termin: 1, year: 2026))
        XCTAssertEqual(list.map(\.day), d.mvaFrister(year: 2026))
        XCTAssertEqual(list.first?.kind.id, "mva-2026-1")
        XCTAssertEqual(list.first?.label, "10.04 MVA 1. TERMIN")
        XCTAssertEqual(list.first?.kind.months(rates: d.rates), [MonthKey(DayKey(year: 2026, month: 1, day: 1)), MonthKey(DayKey(year: 2026, month: 2, day: 1))])
        let annual = DeadlineKind.mvaAarlig(year: 2026)
        XCTAssertEqual(annual.id, "mva-2026-aar")
        XCTAssertEqual(annual.months(rates: d.rates).count, 12)
        let json = try JSONEncoder().encode(MonthKey(DayKey(year: 2026, month: 1, day: 20)))
        XCTAssertEqual(String(decoding: json, as: UTF8.self), "\"2026-01\"")
        XCTAssertEqual(MonthKey(DayKey(year: 2026, month: 12, day: 1)).next, MonthKey(DayKey(year: 2027, month: 1, day: 1)))
    }

    func testDoctorGetsNoVatDeadline() throws {
        let client = try XCTUnwrap(try town().client("konsulenten"))
        // An ENK without vat still files a tax return.
        XCTAssertEqual(DeadlinePlanner.deadlines(for: client, year: 2026, deadlines: try deadlines()).map(\.kind), [.skattemelding(year: 2026)])
    }

    func testDeadlineOnSaturdayMovesToMonday() throws {
        let d = try deadlines()
        let raw = d.rates.mvaTerminer[0].frist.day(forYear: 2027)
        XCTAssertEqual(raw.weekday, 6)
        let moved = d.mvaFrist(termin: 1, year: 2027)
        XCTAssertEqual(moved.weekday, 1)
        XCTAssertEqual(DayKey.daysBetween(raw, moved), 2)
        let client = try XCTUnwrap(try town().client("butikken"))
        let first = DeadlinePlanner.deadlines(for: client, year: 2027, deadlines: d).first
        XCTAssertEqual(first?.day, moved)
        XCTAssertEqual(first?.label, String(format: "%02d.%02d MVA 1. TERMIN", moved.day, moved.month))
    }

    func testTwelveActionsMakeADay() {
        let start = DayKey(year: 2026, month: 1, day: 5)
        var cal = TownCalendar(start: start)
        for _ in 0..<(TownRules.actionsPerDay - 1) { XCTAssertFalse(cal.act()) }
        XCTAssertEqual(cal.today, start)
        XCTAssertTrue(cal.act())
        XCTAssertEqual(cal.today, start.adding(days: 1))
        XCTAssertEqual(cal.actionsToday, 0)
    }

    func testSleepStopsAtEventsInOrder() {
        var cal = TownCalendar(start: DayKey(year: 2026, month: 1, day: 20))
        _ = cal.act()
        let events = [DayKey(year: 2026, month: 4, day: 10), DayKey(year: 2026, month: 2, day: 1), DayKey(year: 2026, month: 4, day: 7)]
        cal.sleep(events: events)
        XCTAssertEqual(cal.today, DayKey(year: 2026, month: 2, day: 1))
        XCTAssertEqual(cal.actionsToday, 0)
        cal.sleep(events: events)
        XCTAssertEqual(cal.today, DayKey(year: 2026, month: 4, day: 7))
        cal.sleep(events: events)
        XCTAssertEqual(cal.today, DayKey(year: 2026, month: 4, day: 10))
        cal.sleep(events: events)
        XCTAssertEqual(cal.today, DayKey(year: 2026, month: 4, day: 11))
    }

    func testUpcomingListsSevenDays() throws {
        let d = try deadlines()
        let clients = try town().klienter
        let first = d.mvaFrist(termin: 1, year: 2026)
        let list = DeadlinePlanner.upcoming(clients: clients, from: first.adding(days: -3), days: 7, deadlines: d)
        XCTAssertFalse(list.isEmpty)
        XCTAssertTrue(list.allSatisfy { $0.day >= first.adding(days: -3) && $0.day < first.adding(days: 4) })
        XCTAssertEqual(list.map(\.day), list.map(\.day).sorted())
        XCTAssertEqual(DeadlinePlanner.upcoming(clients: clients, from: first.adding(days: 1), days: 7, deadlines: d), [])
        // The previous year's last term falls in February.
        let feb = d.mvaFrist(termin: 6, year: 2026)
        let carried = DeadlinePlanner.upcoming(clients: clients, from: feb, days: 1, deadlines: d)
        XCTAssertEqual(carried.first?.kind, .mva(termin: 6, year: 2026))
        XCTAssertEqual(carried.first?.day, DayKey(year: feb.year, month: feb.month, day: feb.day))
    }
}
