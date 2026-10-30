import XCTest
@testable import RegnskapKit

final class TownStateTests: XCTestCase {
    static let town = try! TownContent.load(folder: Bundle.module.resourceURL!.appendingPathComponent("Fixtures/by", isDirectory: true))

    func day(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }

    func testNewGameStartsAtTheOfficeOnFirstJanuary() throws {
        let content = Self.town
        let state = TownState.new(content: content, year: 2026)
        let office = try XCTUnwrap(content.map("kontoret"))
        let boss = try XCTUnwrap(office.folk.first { $0.rolle == .sjef })
        XCTAssertEqual(state.mapId, "kontoret")
        XCTAssertEqual(state.walker, TownWalker(x: boss.x, y: boss.y + 1, facing: .up))
        XCTAssertEqual(state.calendar, TownCalendar(start: day(1, 1)))
        XCTAssertEqual(state.start, MonthKey(year: 2026, month: 1))
        XCTAssertEqual(state.contracts, TownRules.startContracts)
        XCTAssertEqual(Set(state.clients.keys), Set(content.klienter.map(\.id)))
        for client in content.klienter {
            XCTAssertEqual(state.clients[client.id], .fresh(client.startklient ? .active : .prospect), client.id)
        }
        XCTAssertTrue(content.klienter.contains { $0.startklient })
    }

    func testRoundTripThroughJSON() throws {
        var state = TownState.new(content: Self.town, year: 2026)
        let id = try XCTUnwrap(state.clients.keys.sorted().first)
        let jan = MonthKey(year: 2026, month: 1)
        var client = try XCTUnwrap(state.clients[id])
        client.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 3), correct: false), boxBefore: 2, client: id)
        client.book(BookedBilag(puzzleId: "p2", month: jan, day: day(1, 4), correct: true), boxBefore: 1, client: id)
        client.closedMonths.insert(MonthKey(year: 2025, month: 12))
        state.clients[id] = client
        state.walker = TownWalker(x: 3, y: 4, facing: .left)
        state.calendar.sleep(events: [day(1, 15)])
        state.mapId = "sentrum"
        state.contracts = 3

        let back = try JSONDecoder().decode(TownState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back, state)
        XCTAssertFalse(back.clients[id]!.closedMonths.isEmpty)
        XCTAssertEqual(back.calendar.today, day(1, 15))
    }

    func testOldProgressWithoutTownDecodes() throws {
        let json = #"{"xp":5,"badges":{},"bestScores":{},"counters":{}}"#
        let game = try JSONDecoder().decode(GameProgress.self, from: Data(json.utf8))
        XCTAssertNil(game.town)
        XCTAssertEqual(game.xp, 5)
    }

    func testMaskedBoxHidesAnOpenError() throws {
        var state = TownState.new(content: Self.town, year: 2026)
        XCTAssertNil(state.maskedBox("p1"))
        let ids = state.clients.keys.sorted()
        let jan = MonthKey(year: 2026, month: 1)
        state.clients[ids[0]]?.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 9), correct: false), boxBefore: 4, client: ids[0])
        state.clients[ids[1]]?.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 5), correct: false), boxBefore: 2, client: ids[1])
        XCTAssertEqual(state.maskedBox("p1"), 2, "the oldest open error wins")
        XCTAssertNil(state.maskedBox("p2"))
    }

    func testOldSaveOpenedInAprilMissesNoPayroll() throws {
        let content = Self.town
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        var state = TownState.new(content: content, year: 2026)
        XCTAssertNil(state.payrollFrom, "payroll counts from the start in a new game")
        state.calendar = TownCalendar(start: day(4, 12))
        state.clients["kafeen"]?.status = .active
        state.clients["butikken"]?.delivered = ["mva-2026-1"]

        // A save from phase 2a: the same JSON without the new field.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["payrollFrom"] = nil
        let old = try JSONDecoder().decode(TownState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.payrollFrom, day(4, 12))

        var loaded = old
        var missed: [TownDeadline] = []
        for _ in 0..<TownRules.actionsPerDay { missed += loaded.spendAction(content: content, deadlines: library.deadlines) }
        XCTAssertEqual(loaded.calendar.today, day(4, 13))
        XCTAssertEqual(missed, [])
        XCTAssertEqual(loaded.clients["kafeen"]?.missed, [])

        // The same date in a new game does count the months before.
        var fresh = state
        XCTAssertFalse(fresh.checkMissed(content: content, deadlines: library.deadlines).isEmpty)
    }

    func testPayrollCountsOnlyFromPayrollFrom() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        var state = TownState.new(content: Self.town, year: 2026)
        let client = try XCTUnwrap(state.clients["kafeen"])
        let list = DeadlinePlanner.deadlines(for: try XCTUnwrap(Self.town.client("kafeen")), year: 2026, deadlines: library.deadlines)
        let trekk = try XCTUnwrap(list.first { $0.kind.id == "trekk-2026-01" })
        XCTAssertTrue(state.counts(trekk, client: client))
        state.payrollFrom = day(1, 22)
        XCTAssertFalse(state.counts(trekk, client: client))
        state.payrollFrom = day(1, 21)
        XCTAssertTrue(state.counts(trekk, client: client))
    }
}
