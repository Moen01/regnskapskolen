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
        for _ in 0..<TownRules.actionsPerDay { missed += loaded.spendAction(content: content, deadlines: library.deadlines, pool: []) }
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

    func testMaskedProgressHidesTheWrongBooking() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let pool = library.pool(includeDrafts: true)
        let target = try XCTUnwrap(pool.first)
        let other = try XCTUnwrap(pool.first { $0.tema == target.tema && $0.id != target.id })
        func caught(_ progress: LearnerProgress) -> Int {
            Regions.build(topics: library.topics, pool: pool, progress: progress).first { $0.tema == target.tema }!.caught
        }
        let jan = MonthKey(year: 2026, month: 1)
        var state = TownState.new(content: Self.town, year: 2026)
        let id = try XCTUnwrap(state.clients.keys.sorted().first)

        // Never seen before the wrong booking: it must still look uncaught afterwards.
        let before = LearnerProgress()
        state.clients[id]?.book(BookedBilag(puzzleId: target.id, month: jan, day: day(1, 5), correct: false), boxBefore: 0, client: id)
        var after = before
        after.puzzles[target.id] = PuzzleProgress(box: 1, attempts: 1, correct: 0)
        XCTAssertEqual(caught(after), caught(before) + 1, "the raw progress gives the error away")
        XCTAssertEqual(caught(state.masked(after)), caught(before))

        // Seen before in box 3: the mask puts it back in box 3.
        var state2 = TownState.new(content: Self.town, year: 2026)
        state2.clients[id]?.book(BookedBilag(puzzleId: target.id, month: jan, day: day(1, 5), correct: false), boxBefore: 3, client: id)
        var progress = LearnerProgress()
        progress.puzzles[target.id] = PuzzleProgress(box: 1, attempts: 2, correct: 1)
        progress.puzzles[other.id] = PuzzleProgress(box: 2, attempts: 1, correct: 1)
        let masked = state2.masked(progress)
        XCTAssertEqual(masked.puzzles[target.id]?.box, 3)
        XCTAssertEqual(masked.puzzles[other.id], progress.puzzles[other.id])
    }

    /// Spec Mål 7: a right booking moves the box too, so every booking in an open month is masked,
    /// right or wrong; only the close shows the real box.
    func testMaskedProgressHidesEveryBookingUntilTheMonthCloses() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let pool = library.pool(includeDrafts: true)
        let target = try XCTUnwrap(pool.first)
        let jan = MonthKey(year: 2026, month: 1)
        let id = try XCTUnwrap(TownState.new(content: Self.town, year: 2026).clients.keys.sorted().first)
        func region(_ progress: LearnerProgress) -> Region {
            Regions.build(topics: library.topics, pool: pool, progress: progress).first { $0.tema == target.tema }!
        }
        // Box 2 before: right goes to 3 (mastered), wrong goes down.
        func booked(correct: Bool) -> (state: TownState, progress: LearnerProgress) {
            var state = TownState.new(content: Self.town, year: 2026)
            var progress = LearnerProgress()
            progress.puzzles[target.id] = PuzzleProgress(box: 2, attempts: 2, correct: 2)
            Scheduler.record(AttemptResult(puzzleId: target.id, correctFirstTry: correct), on: day(1, 5), progress: &progress)
            state.clients[id]?.book(BookedBilag(puzzleId: target.id, month: jan, day: day(1, 5), correct: correct), boxBefore: 2, client: id)
            return (state, progress)
        }
        let right = booked(correct: true)
        let wrong = booked(correct: false)
        XCTAssertNotEqual(right.progress.puzzles[target.id]?.box, wrong.progress.puzzles[target.id]?.box, "the raw boxes differ")

        let shownRight = right.state.masked(right.progress)
        let shownWrong = wrong.state.masked(wrong.progress)
        XCTAssertEqual(region(shownRight).caught, region(shownWrong).caught)
        XCTAssertEqual(region(shownRight).mastered, region(shownWrong).mastered)
        XCTAssertEqual(Stage.of(box: shownRight.puzzles[target.id]?.box), Stage.of(box: shownWrong.puzzles[target.id]?.box))
        XCTAssertEqual(shownRight.puzzles[target.id]?.box, 2)

        // The month closes: the right booking shows its real box.
        var closed = right.state
        closed.clients[id]?.closeIfClean(jan)
        XCTAssertEqual(closed.masked(right.progress).puzzles[target.id]?.box, right.progress.puzzles[target.id]?.box)

        // A booking saved before `boxBefore` existed is not masked.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(right.state.clients[id]!.booked[0])) as? [String: Any])
        object["boxBefore"] = nil
        let old = try JSONDecoder().decode(BookedBilag.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.boxBefore)
        var oldState = right.state
        oldState.clients[id]?.booked = [old]
        XCTAssertEqual(oldState.masked(right.progress), right.progress)
    }

    /// Paragrafjakten picks and judges creatures from the progress it gets; from the masked one, a
    /// bilag in an open month looks the same whether it was booked right or wrong.
    func testARegionRunOnTheMaskedProgressKeepsTheVerdict() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let target = try XCTUnwrap(library.pool(includeDrafts: true).first)
        let region = Region(tema: target.tema, navn: target.tema, rekkefolge: 1, theme: RegionTheme(symbol: "x", farge: "skole", setning: ""),
                            puzzles: [target], gymLeader: nil, caught: 0, mastered: 0, unlocked: true, gymBadge: nil)
        let id = try XCTUnwrap(TownState.new(content: Self.town, year: 2026).clients.keys.sorted().first)
        func firstStage(correct: Bool, masked: Bool) -> Stage? {
            var state = TownState.new(content: Self.town, year: 2026)
            var progress = LearnerProgress()
            progress.puzzles[target.id] = PuzzleProgress(box: 2, attempts: 2, correct: 2)
            Scheduler.record(AttemptResult(puzzleId: target.id, correctFirstTry: correct), on: day(1, 5), progress: &progress)
            state.clients[id]?.book(BookedBilag(puzzleId: target.id, month: MonthKey(year: 2026, month: 1), day: day(1, 5), correct: correct),
                                    boxBefore: 2, client: id)
            let shown = masked ? state.masked(progress) : progress
            var run = RegionRun(region: region, progress: shown, today: day(2, 1), regionCards: [], otherCards: [], seed: 1)
            run.nextEncounter(progress: shown, today: day(2, 1))
            return run.current?.stageBefore
        }
        XCTAssertNotEqual(firstStage(correct: true, masked: false), firstStage(correct: false, masked: false), "the real boxes tell the verdict")
        XCTAssertEqual(firstStage(correct: true, masked: true), firstStage(correct: false, masked: true))
        XCTAssertEqual(firstStage(correct: true, masked: true), Stage.of(box: 2))
    }

    func testMaskedProgressIsUnchangedWithoutOpenErrors() throws {
        let state = TownState.new(content: Self.town, year: 2026)
        var progress = LearnerProgress()
        progress.puzzles["a"] = PuzzleProgress(box: 2, attempts: 3, correct: 2)
        XCTAssertEqual(state.masked(progress), progress)
    }
}
