import XCTest
@testable import RegnskapKit

final class TownSandboxTests: XCTestCase {
    static let library = TownFlowTests.library
    let jan = MonthKey(year: 2026, month: 1)
    let feb = MonthKey(year: 2026, month: 2)
    let ids = (1...6).map { "x\($0)" }

    func day(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }

    /// The fixture town where the café has six tasks, so February has a pile of its own.
    private func town() throws -> TownContent {
        var town = TownFlowTests.town
        let i = try XCTUnwrap(town.klienter.firstIndex { $0.id == "kafeen" })
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(town.klienter[i])) as! [String: Any]
        json["oppgaver"] = ids
        town.klienter[i] = try JSONDecoder().decode(TownClient.self, from: JSONSerialization.data(withJSONObject: json))
        return town
    }

    private func person(client: String? = "kafeen", gir: String? = nil, case id: String = "kafe-001") -> TownPerson {
        TownPerson(id: "perm-\(id)", rolle: .sandkasse, x: 1, y: 1, klient: client, fagkontor: nil, tekst: ["Her ligger en sak."], gir: gir, sandkasse: id)
    }

    private func with(_ p: TownPerson, in town: TownContent) -> TownContent {
        var t = town
        let m = t.kart[0]
        t.kart[0] = TownMap(id: m.id, navn: m.navn, bredde: m.bredde, hoyde: m.hoyde, ruter: m.ruter, dorer: m.dorer, folk: m.folk + [p], fullmakt: m.fullmakt, bydel: m.bydel, rekkefolge: m.rekkefolge, ankomst: m.ankomst)
        return t
    }

    /// The café is active from 1 January, with the given months closed and `today` set.
    private func state(today: DayKey, closed: Set<MonthKey> = []) throws -> TownState {
        var s = TownState.new(content: try town(), year: 2026)
        s.calendar = TownCalendar(start: today)
        var c = ClientState.fresh(.active)
        c.activeFrom = day(1, 1)
        c.closedMonths = closed
        s.clients["kafeen"] = c
        return s
    }

    private func credit(_ s: inout TownState, _ p: TownPerson) throws -> SandboxCredit {
        s.creditSandbox(p.sandkasse!, content: with(p, in: try town()))
    }

    func testClearedCaseClosesTheEarliestEndedMonth() throws {
        var s = try state(today: day(4, 15), closed: [jan])
        XCTAssertEqual(try credit(&s, person()), .closedMonth(client: "kafeen", month: feb))
        XCTAssertTrue(s.clients["kafeen"]!.closedMonths.contains(feb))
        XCTAssertEqual(s.sandboxCleared, ["kafe-001"])
        let kafe = try XCTUnwrap(try town().client("kafeen"))
        let pile = Ledger.pileMonth(for: kafe, start: s.start, today: s.calendar.today, state: s.clients["kafeen"]!, pool: Set(ids))
        XCTAssertNotEqual(pile, feb)
    }

    func testClearedTwiceCountsOnce() throws {
        var s = try state(today: day(4, 15), closed: [jan])
        _ = try credit(&s, person())
        let closed = s.clients["kafeen"]!.closedMonths
        XCTAssertEqual(try credit(&s, person()), .already)
        XCTAssertEqual(s.clients["kafeen"]!.closedMonths, closed)
    }

    func testNoEndedMonthIsTriedAgainLater() throws {
        var s = try state(today: day(1, 20))
        XCTAssertEqual(try credit(&s, person()), .noMonth(client: "kafeen"))
        XCTAssertTrue(s.sandboxCleared.isEmpty)
        s.calendar = TownCalendar(start: day(2, 2))
        XCTAssertEqual(try credit(&s, person()), .closedMonth(client: "kafeen", month: jan))
        XCTAssertEqual(s.sandboxCleared, ["kafe-001"])
    }

    /// The month is chosen without looking at verdicts (spec Mål 7): a right and a wrong booking
    /// in January give the same result, so the credit tells nothing about January.
    func testMonthWithBookingsIsNotTakenWhateverTheVerdict() throws {
        var results: [SandboxCredit] = []
        for correct in [true, false] {
            var s = try state(today: day(4, 15))
            s.clients["kafeen"]!.book(BookedBilag(puzzleId: "x1", month: jan, day: day(1, 3), correct: correct), boxBefore: 0, client: "kafeen")
            results.append(try credit(&s, person()))
            XCTAssertFalse(s.clients["kafeen"]!.closedMonths.contains(jan), "correct: \(correct)")
        }
        XCTAssertEqual(results, [.closedMonth(client: "kafeen", month: feb), .closedMonth(client: "kafeen", month: feb)])
    }

    func testInactiveClientGetsNoCredit() throws {
        var s = try state(today: day(4, 15))
        s.clients["kafeen"]!.status = .parked
        XCTAssertEqual(try credit(&s, person()), .notActive(client: "kafeen"))
        XCTAssertTrue(s.sandboxCleared.isEmpty)
    }

    func testBankCaseGivesItsCard() throws {
        var s = try state(today: day(1, 5))
        let card = Self.library.rules[0].id
        let p = person(client: nil, gir: card, case: "bank-001")
        XCTAssertEqual(try credit(&s, p), .card(card))
        XCTAssertEqual(s.regelkort, [card])
        XCTAssertEqual(s.sandboxCleared, ["bank-001"])
        XCTAssertEqual(try credit(&s, p), .already)
    }

    func testUnknownCaseIsNotStored() throws {
        var s = try state(today: day(1, 5))
        XCTAssertEqual(s.creditSandbox("finnes-ikke", content: try town()), .unknown)
        XCTAssertTrue(s.sandboxCleared.isEmpty)
    }

    /// January's damage is held back until the player closes January at the counter; the case
    /// closes February, which has no bookings and so no damage.
    func testHeldBackDamageWaitsForTheCounter() throws {
        var s = try state(today: day(4, 15))
        s.clients["kafeen"]!.book(BookedBilag(puzzleId: "x1", month: jan, day: day(1, 3), correct: true, damage: 3), boxBefore: 0, client: "kafeen")
        XCTAssertEqual(try credit(&s, person()), .closedMonth(client: "kafeen", month: feb))
        XCTAssertFalse(s.clients["kafeen"]!.closedMonths.contains(jan))
        XCTAssertEqual(s.clients["kafeen"]!.closeIfClean(jan, tema: { _ in "mva" }), ["mva": 3])
    }

    func testSandboxPersonOffersTheChoiceOnce() throws {
        let p = person()
        let town = with(p, in: try town())
        XCTAssertEqual(town.sandboxPerson("kafe-001")?.id, p.id)
        XCTAssertNil(town.sandboxPerson("bank-001"))
        var s = try state(today: day(4, 15))
        var f = TownFlow(content: town, state: s, deadlines: Self.library.deadlines, pool: Set(ids), regions: TownFlowTests.regions, damage: [:], badges: [], ruleCards: Self.library.rules)
        _ = f.talk(to: p)
        XCTAssertEqual(f.pages.flatMap { $0 }, ["Her ligger en sak."])
        _ = f.key(.a)
        XCTAssertEqual(f.phase, .choice)
        XCTAssertEqual(f.key(.a), .openSandbox(caseId: "kafe-001"))
        XCTAssertFalse(TownAction.openSandbox(caseId: "kafe-001").spendsAction)
        s.sandboxCleared = ["kafe-001"]
        f = TownFlow(content: town, state: s, deadlines: Self.library.deadlines, pool: Set(ids), regions: TownFlowTests.regions, damage: [:], badges: [], ruleCards: Self.library.rules)
        _ = f.talk(to: p)
        XCTAssertEqual(f.pages.flatMap { $0 }, ["Denne saken er ryddet."])
    }

    func testSandboxTexts() {
        let town = TownFlowTests.town
        let card = Self.library.rules[0]
        XCTAssertEqual(TownFlow.sandboxTexts(.closedMonth(client: "kafeen", month: jan), content: town, ruleCards: []), ["Saken er ryddet!", "KAFÉ: januar er lukket."])
        XCTAssertEqual(TownFlow.sandboxTexts(.card(card.id), content: town, ruleCards: Self.library.rules), ["Saken er ryddet!", "Du fikk regelkortet «\(card.tittel)»."])
        XCTAssertEqual(TownFlow.sandboxTexts(.already, content: town, ruleCards: []), [])
        XCTAssertEqual(TownFlow.sandboxTexts(.noMonth(client: "kafeen"), content: town, ruleCards: []), [])
    }

    func testSaveWithoutSandboxClearedStillLoads() throws {
        var s = try state(today: day(1, 5))
        s.sandboxCleared = ["bank-001"]
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(TownState.self, from: data).sandboxCleared, ["bank-001"])
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "sandboxCleared")
        let old = try JSONDecoder().decode(TownState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.sandboxCleared.isEmpty)
    }
}
