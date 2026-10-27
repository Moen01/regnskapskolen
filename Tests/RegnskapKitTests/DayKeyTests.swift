import XCTest
@testable import RegnskapKit

final class DayKeyTests: XCTestCase {
    func testWeekdayAndWeekend() throws {
        let saturday = try XCTUnwrap(DayKey(string: "2026-10-10"))
        XCTAssertEqual(saturday.weekday, 6)
        XCTAssertTrue(saturday.isWeekend)
        let monday = try XCTUnwrap(DayKey(string: "2026-10-12"))
        XCTAssertEqual(monday.weekday, 1)
        XCTAssertFalse(monday.isWeekend)
        XCTAssertEqual(saturday.adding(days: 2), monday)
        XCTAssertLessThan(saturday, monday)
        XCTAssertEqual(saturday.string, "2026-10-10")
        XCTAssertEqual(saturday.year, 2026)
        XCTAssertEqual(saturday.month, 10)
        XCTAssertEqual(saturday.day, 10)
    }

    func testEaster2026() {
        for s in ["2026-04-02", "2026-04-03", "2026-04-05", "2026-04-06", "2026-05-14", "2026-05-24", "2026-05-25",
                  "2026-01-01", "2026-05-01", "2026-05-17", "2026-12-25", "2026-12-26"] {
            XCTAssertTrue(DayKey(string: s)!.isNorwegianPublicHoliday, s)
        }
        XCTAssertFalse(DayKey(string: "2026-04-07")!.isNorwegianPublicHoliday)
        XCTAssertFalse(DayKey(string: "2026-12-24")!.isNorwegianPublicHoliday)
    }

    func testNextWorkingDay() {
        XCTAssertEqual(DayKey(string: "2026-10-10")!.nextWorkingDay.string, "2026-10-12")
        XCTAssertEqual(DayKey(string: "2026-05-01")!.nextWorkingDay.string, "2026-05-04")
        XCTAssertEqual(DayKey(string: "2026-10-12")!.nextWorkingDay.string, "2026-10-12")
    }

    func testCodableAsString() throws {
        let key = DayKey(string: "2026-02-28")!
        let data = try JSONEncoder().encode([key])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["2026-02-28"]"#)
        XCTAssertEqual(try JSONDecoder().decode([DayKey].self, from: data), [key])
    }

    func testFromDateInOslo() {
        // 23:30 UTC on 31 Dec is already 1 Jan in Oslo.
        let utc = ISO8601DateFormatter().date(from: "2025-12-31T23:30:00Z")!
        XCTAssertEqual(DayKey(utc).string, "2026-01-01")
    }
}
