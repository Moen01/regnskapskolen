import XCTest
@testable import RegnskapKit

/// Builds a client with 12 made-up puzzle ids (p0 ... p11) without touching repo content.
func makeLedgerClient(count: Int = 12) -> TownClient {
    let ids = (0..<count).map { "\"p\($0)\"" }.joined(separator: ",")
    let lines = "{\"hilsen\":[],\"drift\":[],\"haug\":[],\"tomHaug\":[],\"glippetFrist\":[],\"oppdagetFeil\":[]}"
    let json = """
    {"id":"k1","navn":"Test AS","bransje":"b","selskapsform":"as","mvaRegistrert":true,"ansatte":1,
     "sted":{"kart":"m","x":0,"y":0},"oppgaver":[\(ids)],"provesak":[],"replikker":\(lines),"status":"godkjent"}
    """
    return try! JSONDecoder().decode(TownClient.self, from: Data(json.utf8))
}

final class LedgerTests: XCTestCase {
    let jan = MonthKey(year: 2026, month: 1)
    let feb = MonthKey(year: 2026, month: 2)
    let mar = MonthKey(year: 2026, month: 3)
    let allIds = Set((0..<12).map { "p\($0)" })

    func day(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }

    func testPileIsFiveFromTheMonthsSlice() {
        let c = makeLedgerClient()
        let state = ClientState.fresh(.active)
        XCTAssertEqual(Ledger.pile(for: c, month: jan, start: jan, state: state, pool: allIds), ["p0", "p1", "p2", "p3", "p4"])
        XCTAssertEqual(Ledger.pile(for: c, month: feb, start: jan, state: state, pool: allIds), ["p5", "p6", "p7", "p8", "p9"])
        XCTAssertEqual(Ledger.pile(for: c, month: mar, start: jan, state: state, pool: allIds), ["p10", "p11"])
        XCTAssertEqual(Ledger.pile(for: c, month: MonthKey(year: 2026, month: 4), start: jan, state: state, pool: allIds), [])
        XCTAssertEqual(Ledger.pile(for: c, month: MonthKey(year: 2025, month: 12), start: jan, state: state, pool: allIds), [])
    }

    func testClientWonInAprilStartsInApril() {
        let c = makeLedgerClient()
        let apr = MonthKey(year: 2026, month: 4)
        var state = ClientState.fresh(.active)
        state.activeFrom = day(4, 12)
        XCTAssertEqual(state.booksFrom(start: jan), apr)
        XCTAssertEqual(Ledger.pile(for: c, month: apr, start: jan, state: state, pool: allIds), ["p0", "p1", "p2", "p3", "p4"])
        XCTAssertEqual(Ledger.pile(for: c, month: mar, start: jan, state: state, pool: allIds), [])
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: day(4, 20), state: state, pool: allIds), apr)
        XCTAssertFalse(Ledger.canClose(apr, client: c, start: jan, state: state, today: day(5, 1), pool: allIds), "the bilag are not booked")
        // March has no pile and has ended, but it is the previous accountant's month.
        XCTAssertFalse(Ledger.canClose(mar, client: c, start: jan, state: state, today: day(5, 1), pool: allIds))
    }

    /// Phase 2a cut every pile from the game's start, so a client won in April may hold January's
    /// slice, booked on month January and with an open error there. The books start at the earliest
    /// booked month, so that slice is not lost and its error can still be corrected and closed.
    func testA2aSaveWithALateWonClientKeepsItsBookedMonths() throws {
        let c = makeLedgerClient()
        let json = """
        {"status":"active","satisfaction":50,"met":true,"activeFrom":"2026-04-12",
         "booked":[{"puzzleId":"p0","month":"2026-01","day":"2026-04-13","correct":false},
                   {"puzzleId":"p1","month":"2026-01","day":"2026-04-13","correct":true}],
         "openErrors":[{"puzzleId":"p0","client":"k1","month":"2026-01","day":"2026-04-13","boxBefore":0}],
         "closedMonths":[],"delivered":[],"missed":[]}
        """
        let state = try JSONDecoder().decode(ClientState.self, from: Data(json.utf8))
        XCTAssertEqual(state.booksFrom(start: jan), jan)
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: day(4, 20), state: state, pool: allIds), jan)
        XCTAssertEqual(Ledger.pile(for: c, month: jan, start: jan, state: state, pool: allIds), ["p2", "p3", "p4"])
        XCTAssertEqual(Ledger.pile(for: c, month: feb, start: jan, state: state, pool: allIds), ["p5", "p6", "p7", "p8", "p9"])
        XCTAssertFalse(state.hasClosed([jan, feb], start: jan), "January is the player's month now")
        var done = state
        for i in 2..<5 {
            done.book(BookedBilag(puzzleId: "p\(i)", month: jan, day: day(4, 20), correct: true), boxBefore: 0, client: "k1")
        }
        XCTAssertTrue(Ledger.canClose(jan, client: c, start: jan, state: done, today: day(4, 20), pool: allIds))
        XCTAssertEqual(done.errors(in: jan).map(\.puzzleId), ["p0"])

        // Without bookings the books still start in the month the client was won.
        var fresh = state
        fresh.booked = []
        fresh.openErrors = []
        XCTAssertEqual(fresh.booksFrom(start: jan), MonthKey(year: 2026, month: 4))
    }

    func testStartClientStillStartsInJanuary() {
        let c = makeLedgerClient()
        let state = ClientState.fresh(.active)
        XCTAssertEqual(state.booksFrom(start: jan), jan)
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: day(2, 10), state: state, pool: allIds), jan)
        // A client won before the game's start month never starts earlier than the game.
        var early = ClientState.fresh(.active)
        early.activeFrom = DayKey(year: 2025, month: 11, day: 3)
        XCTAssertEqual(early.booksFrom(start: jan), jan)
    }

    func testPileIgnoresPuzzlesOutsideThePoolButKeepsTheSlice() {
        let c = makeLedgerClient()
        let pool = allIds.subtracting(["p1", "p3"])
        let state = ClientState.fresh(.active)
        XCTAssertEqual(Ledger.pile(for: c, month: jan, start: jan, state: state, pool: pool), ["p0", "p2", "p4"])
        XCTAssertEqual(Ledger.pile(for: c, month: feb, start: jan, state: state, pool: pool), ["p5", "p6", "p7", "p8", "p9"])
    }

    func testEmptyPileWhenPoolIsEmpty() {
        let c = makeLedgerClient()
        XCTAssertEqual(Ledger.pile(for: c, month: jan, start: jan, state: .fresh(.active), pool: []), [])
    }

    func testPileSkipsBookedBilag() {
        let c = makeLedgerClient()
        var state = ClientState.fresh(.active)
        state.book(BookedBilag(puzzleId: "p0", month: jan, day: day(1, 5), correct: true), boxBefore: 1, client: "k1")
        XCTAssertEqual(Ledger.pile(for: c, month: jan, start: jan, state: state, pool: allIds), ["p1", "p2", "p3", "p4"])
    }

    func testWrongBookingOpensAnErrorRightDoesNot() {
        var state = ClientState.fresh(.active)
        state.book(BookedBilag(puzzleId: "p0", month: jan, day: day(1, 5), correct: true), boxBefore: 2, client: "k1")
        XCTAssertTrue(state.openErrors.isEmpty)
        state.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 6), correct: false), boxBefore: 3, client: "k1")
        XCTAssertEqual(state.booked.count, 2)
        XCTAssertEqual(state.openErrors.count, 1)
        XCTAssertEqual(state.openErrors[0].boxBefore, 3)
        XCTAssertEqual(state.openErrors[0].id, "k1:p1:2026-01-06")
        XCTAssertEqual(state.errors(in: jan).count, 1)
        XCTAssertTrue(state.errors(in: feb).isEmpty)
    }

    func testCannotCloseBeforeTheMonthIsOver() {
        let c = makeLedgerClient()
        let state = ClientState.fresh(.active)
        // Pile empty requires everything booked; use a client with no items in this month instead.
        let empty = makeLedgerClient(count: 0)
        XCTAssertFalse(Ledger.canClose(jan, client: empty, start: jan, state: state, today: day(1, 31), pool: allIds))
        XCTAssertTrue(Ledger.canClose(jan, client: empty, start: jan, state: state, today: day(2, 1), pool: allIds))
        // Unbooked bilag keep the month open even after it ends.
        XCTAssertFalse(Ledger.canClose(jan, client: c, start: jan, state: state, today: day(2, 1), pool: allIds))
    }

    func testPileMonthIsTheOldestUnbookedMonth() {
        let c = makeLedgerClient()
        var state = ClientState.fresh(.active)
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: day(2, 10), state: state, pool: allIds), jan)
        for i in 0..<5 {
            state.book(BookedBilag(puzzleId: "p\(i)", month: jan, day: day(2, 10), correct: true), boxBefore: 1, client: "k1")
        }
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: day(2, 10), state: state, pool: allIds), feb)
        for i in 5..<10 {
            state.book(BookedBilag(puzzleId: "p\(i)", month: feb, day: day(2, 11), correct: true), boxBefore: 1, client: "k1")
        }
        XCTAssertNil(Ledger.pileMonth(for: c, start: jan, today: day(2, 11), state: state, pool: allIds))
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: day(3, 1), state: state, pool: allIds), mar)
        XCTAssertNil(Ledger.pileMonth(for: c, start: jan, today: day(3, 1), state: state, pool: allIds.subtracting(["p10", "p11"])))
    }

    func testCorrectionClosesTheMonth() {
        var state = ClientState.fresh(.active)
        state.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 6), correct: false), boxBefore: 3, client: "k1")
        state.closeIfClean(jan)
        XCTAssertTrue(state.closedMonths.isEmpty)
        state.correct(state.openErrors[0], ok: true)
        XCTAssertTrue(state.openErrors.isEmpty)
        state.closeIfClean(jan)
        XCTAssertEqual(state.closedMonths, [jan])
    }

    func testRightBookingDamageFallsDueOnlyWhenTheMonthCloses() {
        var state = ClientState.fresh(.active)
        let tema: (String) -> String? = { ["p0": "mva", "p1": "mva", "p2": "lonn"][$0] }
        state.book(BookedBilag(puzzleId: "p0", month: jan, day: day(1, 5), correct: true, damage: 30), boxBefore: 0, client: "k1")
        state.book(BookedBilag(puzzleId: "p2", month: jan, day: day(1, 5), correct: true, damage: 20), boxBefore: 0, client: "k1")
        state.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 6), correct: false, damage: 0), boxBefore: 3, client: "k1")
        // Before the close nothing is paid: the open error keeps the month open.
        XCTAssertEqual(state.closeIfClean(jan, tema: tema), [:])
        state.correct(state.openErrors[0], ok: true)
        // The close pays the right bookings per topic; the wrong one earned nothing.
        XCTAssertEqual(state.closeIfClean(jan, tema: tema), ["mva": 30, "lonn": 20])
        XCTAssertEqual(state.bookingDamage(in: jan, tema: tema), ["mva": 30, "lonn": 20])
        // A month closed once never pays again.
        XCTAssertEqual(state.closeIfClean(jan, tema: tema), [:])
    }

    func testWrongBookingPaysNoDamageBeforeOrAfterTheClose() {
        var state = ClientState.fresh(.active)
        state.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 6), correct: false), boxBefore: 3, client: "k1")
        XCTAssertEqual(state.bookingDamage(in: jan, tema: { _ in "mva" }), [:])
        state.correct(state.openErrors[0], ok: true)
        XCTAssertEqual(state.closeIfClean(jan, tema: { _ in "mva" }), [:])
    }

    func testBookingDamageFromABilagRunIsHeldOnTheBooking() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let town = try TownContent.load(folder: TownContentTests.fixtureTown)
        let puzzle = try XCTUnwrap(library.pool(includeDrafts: false).first { $0.kind == .quiz })
        guard case .quiz(let q) = puzzle.payload else { return XCTFail("not a quiz") }
        var run = BilagRun(client: town.klienter[0], puzzles: [puzzle], kind: .booking(jan), errors: [], bransjeCards: [], otherCards: [], seed: 1)
        let (outcome, result, damage) = try XCTUnwrap(run.answer(.quiz(q.svar), progress: LearnerProgress(), today: day(2, 2)))
        XCTAssertEqual(outcome, .booked)
        XCTAssertTrue(result.correctFirstTry)
        XCTAssertGreaterThan(damage, 0)
        var state = ClientState.fresh(.active)
        state.book(BookedBilag(puzzleId: puzzle.id, month: jan, day: day(2, 2), correct: true, damage: damage), boxBefore: 0, client: "k1")
        XCTAssertEqual(state.closeIfClean(jan, tema: { _ in puzzle.tema }), [puzzle.tema: damage])
    }

    func testOldSaveBookingHasNoDamage() throws {
        // A booking as phase 2a/2b wrote it: encode a current one and drop the new key.
        let new = BookedBilag(puzzleId: "p0", month: jan, day: day(1, 5), correct: true, damage: 25)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(new)) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "damage"))
        let old = try JSONDecoder().decode(BookedBilag.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.damage, 0)
        XCTAssertEqual(old.puzzleId, "p0")
        XCTAssertEqual(try JSONDecoder().decode(BookedBilag.self, from: JSONEncoder().encode(new)), new)
    }

    func testFailedCorrectionCostsTenAndStays() {
        var state = ClientState.fresh(.active)
        state.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 6), correct: false), boxBefore: 3, client: "k1")
        state.correct(state.openErrors[0], ok: false)
        XCTAssertEqual(state.satisfaction, TownRules.startSatisfaction - 10)
        XCTAssertEqual(state.openErrors.count, 1)
    }

    func testFailedCorrectionClampsAtZeroAndArchives() {
        var state = ClientState.fresh(.active)
        state.satisfaction = 5
        state.book(BookedBilag(puzzleId: "p1", month: jan, day: day(1, 6), correct: false), boxBefore: 3, client: "k1")
        state.correct(state.openErrors[0], ok: false)
        XCTAssertEqual(state.satisfaction, 0)
        XCTAssertEqual(state.status, .archived)
    }
}

final class LedgerNewYearTests: XCTestCase {
    let jan26 = MonthKey(year: 2026, month: 1)
    let jan27 = MonthKey(year: 2027, month: 1)
    let ids = Set((0..<10).map { "p\($0)" })

    func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

    /// A client with 10 bilag, like the cafe: two piles of five.
    private func bookedJanuary(_ state: inout ClientState) {
        for i in 0..<5 {
            state.book(BookedBilag(puzzleId: "p\(i)", month: jan26, day: day(2026, 1, 10), correct: true), boxBefore: 1, client: "k1")
        }
    }

    func testJanuaryOfTheNextYearStartsThePileAgain() {
        let c = makeLedgerClient(count: 10)
        var state = ClientState.fresh(.active)
        bookedJanuary(&state)
        XCTAssertEqual(Ledger.pile(for: c, month: jan27, start: jan26, state: state, pool: ids), ["p0", "p1", "p2", "p3", "p4"])
        XCTAssertEqual(Ledger.pile(for: c, month: jan26, start: jan26, state: state, pool: ids), [])
    }

    func testClientWonInAprilStartsAgainInJanuary() {
        let c = makeLedgerClient(count: 10)
        var state = ClientState.fresh(.active)
        state.activeFrom = day(2026, 4, 12)
        let first = ["p0", "p1", "p2", "p3", "p4"]
        XCTAssertEqual(Ledger.pile(for: c, month: MonthKey(year: 2026, month: 4), start: jan26, state: state, pool: ids), first)
        XCTAssertEqual(Ledger.pile(for: c, month: jan27, start: jan26, state: state, pool: ids), first)
    }

    func testDecemberBeforeTheStartIsStillEmpty() {
        let c = makeLedgerClient(count: 10)
        let state = ClientState.fresh(.active)
        XCTAssertEqual(Ledger.pile(for: c, month: MonthKey(year: 2025, month: 12), start: jan26, state: state, pool: ids), [])
    }

    func testPileMonthCrossesTheYear() {
        let c = makeLedgerClient(count: 10)
        var state = ClientState.fresh(.active)
        for m in 1...12 { state.closedMonths.insert(MonthKey(year: 2026, month: m)) }
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan26, today: day(2027, 1, 15), state: state, pool: ids), jan27)
    }

    func testCanCloseDecemberOnTheFirstOfJanuary() {
        let empty = makeLedgerClient(count: 0)
        let state = ClientState.fresh(.active)
        let dec = MonthKey(year: 2026, month: 12)
        XCTAssertFalse(Ledger.canClose(dec, client: empty, start: jan26, state: state, today: day(2026, 12, 31), pool: ids))
        XCTAssertTrue(Ledger.canClose(dec, client: empty, start: jan26, state: state, today: day(2027, 1, 1), pool: ids))
    }

    func testFirstOpenMonthCrossesTheYear() {
        var state = ClientState.fresh(.active)
        for m in 1...10 { state.closedMonths.insert(MonthKey(year: 2026, month: m)) }
        XCTAssertEqual(state.firstOpenMonth(start: jan26, today: day(2027, 1, 10)), MonthKey(year: 2026, month: 11))
    }

    /// The same puzzle booked again a year later must not touch the old booking's verdict or damage.
    func testRebookingInTheNewYearKeepsTheMaskAndDamagePerMonth() {
        var state = ClientState.fresh(.active)
        state.book(BookedBilag(puzzleId: "p0", month: jan26, day: day(2026, 1, 10), correct: true, damage: 3), boxBefore: 1, client: "k1")
        state.closedMonths.insert(jan26)
        state.book(BookedBilag(puzzleId: "p0", month: jan27, day: day(2027, 1, 12), correct: true, damage: 5), boxBefore: 4, client: "k1")
        XCTAssertEqual(state.bookingDamage(in: jan26, tema: { _ in "t" }), ["t": 3])
        XCTAssertEqual(state.bookingDamage(in: jan27, tema: { _ in "t" }), ["t": 5])
        var town = TownState(mapId: "m", walker: TownWalker(x: 0, y: 0, facing: .up), calendar: TownCalendar(start: day(2027, 1, 12)),
                             start: jan26, clients: ["k1": state], contracts: 0)
        // Only the open January 2027 booking is held back, so its box shows, not the closed year's.
        XCTAssertEqual(town.maskedBox("p0"), 4)
        town.clients["k1"]!.closedMonths.insert(jan27)
        XCTAssertNil(town.maskedBox("p0"))
    }
}

final class LedgerArchiveTests: XCTestCase {
    func testPileMonthSkipsClosedMonths() {
        let jan = MonthKey(year: 2026, month: 1)
        let feb = MonthKey(year: 2026, month: 2)
        let c = makeLedgerClient()
        let ids = Set((0..<12).map { "p\($0)" })
        var state = ClientState.fresh(.active)
        let today = DayKey(year: 2026, month: 3, day: 10)
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: today, state: state, pool: ids), jan)
        state.closedMonths = [jan]
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: today, state: state, pool: ids), feb)
        state.closedMonths = [jan, feb]
        XCTAssertEqual(Ledger.pileMonth(for: c, start: jan, today: today, state: state, pool: ids), MonthKey(year: 2026, month: 3))
    }
}
