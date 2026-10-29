import XCTest
@testable import RegnskapKit

/// Builds a client with 12 made-up puzzle ids (p0 ... p11) without touching repo content.
func makeLedgerClient(count: Int = 12) -> TownClient {
    let ids = (0..<count).map { "\"p\($0)\"" }.joined(separator: ",")
    let lines = "{\"hilsen\":[],\"drift\":[],\"haug\":[],\"tomHaug\":[],\"glippetFrist\":[]}"
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
