import XCTest
@testable import RegnskapKit

final class PortfolioTests: XCTestCase {
    func day(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }
    let kind = DeadlineKind.mva(termin: 1, year: 2026)

    func testFreshStartsAtStartSatisfaction() {
        let s = ClientState.fresh(.prospect)
        XCTAssertEqual(s.status, .prospect)
        XCTAssertEqual(s.satisfaction, TownRules.startSatisfaction)
        XCTAssertFalse(s.met)
        XCTAssertTrue(s.booked.isEmpty && s.openErrors.isEmpty && s.delivered.isEmpty && s.missed.isEmpty)
    }

    func testDeliverGivesTen() {
        var s = ClientState.fresh(.active)
        s.deliver(kind)
        XCTAssertEqual(s.satisfaction, 70)
        XCTAssertTrue(s.delivered.contains(kind.id))
        s.satisfaction = 95
        s.deliver(.mva(termin: 2, year: 2026))
        XCTAssertEqual(s.satisfaction, 100)
    }

    func testMissedIsRegisteredTheDayAfter() {
        var s = ClientState.fresh(.active)
        let d = TownDeadline(day: day(4, 10), kind: kind, client: "k1")
        XCTAssertTrue(s.checkMissed([d], today: day(4, 10)).isEmpty)
        let newly = s.checkMissed([d], today: day(4, 11))
        XCTAssertEqual(newly, [d])
        XCTAssertEqual(s.satisfaction, 35)
        XCTAssertTrue(s.missed.contains(kind.id))
        XCTAssertTrue(s.checkMissed([d], today: day(4, 12)).isEmpty)
        XCTAssertEqual(s.satisfaction, 35)
    }

    func testDeliveredDeadlineIsNotMissed() {
        var s = ClientState.fresh(.active)
        s.deliver(kind)
        let d = TownDeadline(day: day(4, 10), kind: kind, client: "k1")
        XCTAssertTrue(s.checkMissed([d], today: day(5, 1)).isEmpty)
    }

    func testZeroSatisfactionArchives() {
        var s = ClientState.fresh(.active)
        s.satisfaction = 20
        let d = TownDeadline(day: day(4, 10), kind: kind, client: "k1")
        _ = s.checkMissed([d], today: day(4, 11))
        XCTAssertEqual(s.satisfaction, 0)
        XCTAssertEqual(s.status, .archived)
    }

    func testADeadlineBeforeTheClientWasWonIsNotMissed() {
        var s = ClientState.fresh(.active)
        s.activeFrom = day(4, 12)
        let before = TownDeadline(day: day(4, 10), kind: kind, client: "k1")
        let after = TownDeadline(day: day(6, 10), kind: .mva(termin: 2, year: 2026), client: "k1")
        XCTAssertFalse(s.covers(before))
        XCTAssertTrue(s.covers(after))
        XCTAssertEqual(s.checkMissed([before, after], today: day(6, 11)), [after])
        XCTAssertTrue(ClientState.fresh(.active).covers(before), "no activeFrom covers every deadline")
    }

    func testOldSaveWithoutActiveFromDecodes() throws {
        var s = ClientState.fresh(.active)
        s.activeFrom = day(4, 12)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        XCTAssertNotNil(json.removeValue(forKey: "activeFrom"))
        let old = try JSONDecoder().decode(ClientState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.activeFrom)
        XCTAssertEqual(try JSONDecoder().decode(ClientState.self, from: JSONEncoder().encode(s)), s)
    }
}
