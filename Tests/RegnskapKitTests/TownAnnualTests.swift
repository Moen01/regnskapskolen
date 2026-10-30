import XCTest
@testable import RegnskapKit

final class TownAnnualTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    static let town = try! TownContent.load(folder: TownContentTests.fixtureTown)
    private var deadlines: Deadlines { Self.library.deadlines }

    private func list(_ id: String, year: Int = 2026, mvaRegistrert: Bool? = nil) throws -> [TownDeadline] {
        var client = try XCTUnwrap(Self.town.client(id))
        if let mvaRegistrert {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(client)) as! [String: Any]
            json["mvaRegistrert"] = mvaRegistrert
            json["mvaTermin"] = mvaRegistrert ? "tomaanedlig" : nil
            client = try JSONDecoder().decode(TownClient.self, from: JSONSerialization.data(withJSONObject: json))
        }
        return DeadlinePlanner.deadlines(for: client, year: year, deadlines: deadlines)
    }

    private func find(_ list: [TownDeadline], _ kind: DeadlineKind) -> TownDeadline? { list.first { $0.kind == kind } }

    func testAsGetsSkattemeldingAndAarsregnskap() throws {
        let all = try list("butikken")
        let skatt = try XCTUnwrap(find(all, .skattemelding(year: 2026)))
        XCTAssertEqual(skatt.day, deadlines.skattemeldingFrist(year: 2026))
        // 31.05.2027 is a Monday.
        XCTAssertEqual(skatt.day, DayKey(year: 2027, month: 5, day: 31))
        let regn = try XCTUnwrap(find(all, .aarsregnskap(year: 2026)))
        XCTAssertEqual(regn.day, deadlines.aarsregnskapFrist(year: 2026))
        // 31.07.2027 is a Saturday, so the deadline rolls to Monday 02.08.2027.
        XCTAssertEqual(regn.day, DayKey(year: 2027, month: 8, day: 2))
    }

    func testEnkGetsOnlySkattemelding() throws {
        let all = try list("konsulenten")
        XCTAssertNotNil(find(all, .skattemelding(year: 2026)))
        XCTAssertNil(find(all, .aarsregnskap(year: 2026)))
    }

    func testUnregisteredAsStillGetsBoth() throws {
        let all = try list("butikken", mvaRegistrert: false)
        XCTAssertNotNil(find(all, .skattemelding(year: 2026)))
        XCTAssertNotNil(find(all, .aarsregnskap(year: 2026)))
    }

    func testAnnualOpensOnTheFirstOfJanuaryAndCoversTheYear() throws {
        let all = try list("butikken")
        for kind in [DeadlineKind.skattemelding(year: 2026), .aarsregnskap(year: 2026)] {
            let d = try XCTUnwrap(find(all, kind))
            XCTAssertEqual(d.opens, DayKey(year: 2027, month: 1, day: 1))
            XCTAssertEqual(kind.months(rates: deadlines.rates).count, 12)
            XCTAssertEqual(kind.year, 2026)
            XCTAssertTrue(kind.isAnnual)
            XCTAssertFalse(kind.isPayroll)
        }
    }

    func testAnnualLabelsAndShortNames() throws {
        let all = try list("butikken")
        let skatt = try XCTUnwrap(find(all, .skattemelding(year: 2026)))
        let regn = try XCTUnwrap(find(all, .aarsregnskap(year: 2026)))
        XCTAssertEqual(skatt.label, "31.05 SKATTEMELDING 2026")
        XCTAssertEqual(regn.label, "02.08 ÅRSREGNSKAP 2026")
        XCTAssertEqual(skatt.kind.shortName, "SKATT")
        XCTAssertEqual(regn.kind.shortName, "ÅRSREGN")
        XCTAssertEqual(skatt.kind.id, "skatt-2026")
        XCTAssertEqual(regn.kind.id, "arsregnskap-2026")
        for d in [skatt, regn] { XCTAssertLessThanOrEqual(d.label.count, ListBox.columns) }
    }

    func testFristnavHidesDeadlinesOfTheYearBeforeTheStart() {
        var s = TownState.new(content: Self.town, year: 2026)
        s.calendar = TownCalendar(start: DayKey(year: 2026, month: 2, day: 5))
        s.clients["butikken"]!.status = .active
        s.mapId = "kontoret"
        s.walker = TownWalker(x: 3, y: 3, facing: .left)
        var f = TownFlow(content: Self.town, state: s, deadlines: deadlines, pool: [], regions: [], damage: [:], badges: [], ruleCards: Self.library.rules)
        _ = f.key(.a)
        _ = f.key(.a)
        XCTAssertEqual(f.phase, .fristnav)
        XCTAssertFalse(f.rows.contains { $0.id.contains("mva-2025-6") }, f.rows.map(\.id).joined(separator: ", "))
        // The 6th term of 2026 is due in February 2027, so it shows up later, not now.
        XCTAssertNotNil(DeadlinePlanner.deadlines(for: Self.town.client("butikken")!, year: 2026, deadlines: deadlines).first { $0.kind == .mva(termin: 6, year: 2026) })
    }

    func testOldSaveOpenedAfterMayMissesNoAnnualDeadline() throws {
        var s = TownState.new(content: Self.town, year: 2026)
        s.clients["butikken"]!.status = .active
        s.calendar = TownCalendar(start: DayKey(year: 2027, month: 6, day: 2))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        json.removeValue(forKey: "annualFrom")
        var old = try JSONDecoder().decode(TownState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.annualFrom, DayKey(year: 2027, month: 6, day: 2))
        let missed = old.checkMissed(content: Self.town, deadlines: deadlines)
        XCTAssertFalse(missed.contains { $0.kind.isAnnual })
    }

    func testNewGameCountsAnnualFromTheStart() {
        let s = TownState.new(content: Self.town, year: 2026)
        XCTAssertNil(s.annualFrom)
        let back = try? JSONDecoder().decode(TownState.self, from: JSONEncoder().encode(s))
        XCTAssertNil(back?.annualFrom)
    }
}
