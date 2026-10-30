import XCTest
@testable import RegnskapKit

final class TownArchiveTests: XCTestCase {
    static let library = TownFlowTests.library
    static let town = TownFlowTests.town
    let jan = MonthKey(year: 2026, month: 1)
    let mar = MonthKey(year: 2026, month: 3)

    func day(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }

    private func state(today: DayKey? = nil) -> TownState {
        var s = TownState.new(content: Self.town, year: 2026)
        s.calendar = TownCalendar(start: today ?? day(1, 5))
        return s
    }

    private func flow(_ state: TownState) -> TownFlow {
        TownFlow(content: Self.town, state: state, deadlines: Self.library.deadlines, pool: TownFlowTests.pool,
                 regions: TownFlowTests.regions, damage: [:], badges: [], ruleCards: Self.library.rules)
    }

    private func text(_ f: TownFlow) -> String { f.pages.flatMap { $0 }.joined(separator: " ") }

    private func bilag(_ month: MonthKey, correct: Bool = true) -> BookedBilag {
        BookedBilag(puzzleId: "mva-quiz-001", month: month, day: month.first, correct: correct)
    }

    private func person(_ role: PersonRole = .arkiv) -> TownPerson {
        TownPerson(id: "pc", rolle: role, x: 1, y: 1, klient: nil, fagkontor: nil, tekst: [])
    }

    private func klientPerson(_ id: String) -> TownPerson {
        TownPerson(id: "p-\(id)", rolle: .klient, x: 1, y: 1, klient: id, fagkontor: nil, tekst: [])
    }

    func testParkNeedsCleanBooks() {
        var s = state()
        s.clients["butikken"]!.book(bilag(jan), boxBefore: 0, client: "butikken")
        XCTAssertFalse(s.clients["butikken"]!.canPark(start: s.start, today: s.calendar.today), "a booked month that is open")
        XCTAssertFalse(s.park("butikken"))
        XCTAssertEqual(s.clients["butikken"]!.status, .active)
        s.clients["butikken"]!.closedMonths = [jan]
        XCTAssertTrue(s.park("butikken"))
        XCTAssertEqual(s.clients["butikken"]!.status, .parked)
        XCTAssertFalse(s.park("butikken"), "only an active client can be parked")
        var wrong = state()
        wrong.clients["butikken"]!.book(bilag(jan, correct: false), boxBefore: 0, client: "butikken")
        wrong.clients["butikken"]!.closedMonths = [jan]
        wrong.clients["butikken"]!.openErrors = [OpenError(puzzleId: "mva-quiz-001", client: "butikken", month: jan, day: jan.first, boxBefore: 0)]
        XCTAssertFalse(wrong.park("butikken"), "an open error")
    }

    /// An ended month that is still open blocks the archive too, booked or not: otherwise a park
    /// and an unpark the same day would close it for free.
    func testParkNeedsEveryEndedMonthClosed() {
        var s = state(today: day(3, 10))
        s.clients["butikken"]!.book(bilag(jan), boxBefore: 0, client: "butikken")
        s.clients["butikken"]!.closedMonths = [jan]
        XCTAssertFalse(s.park("butikken"), "February has ended and is open")
        XCTAssertEqual(s.clients["butikken"]!.status, .active)
        s.clients["butikken"]!.closedMonths = [jan, MonthKey(year: 2026, month: 2)]
        XCTAssertTrue(s.park("butikken"), "March is not over yet")
    }

    func testParkedClientHasNoPileDeadlinesOrDiscoveries() {
        var s = state(today: day(5, 20))
        s.clients["butikken"]!.status = .parked
        let content = Self.town
        XCTAssertTrue(flow(s).activeClients.isEmpty)
        XCTAssertTrue(s.checkMissed(content: content, deadlines: Self.library.deadlines).isEmpty)
        XCTAssertTrue(s.clients["butikken"]!.missed.isEmpty)
        let events = s.sleepEvents(content: content, deadlines: Self.library.deadlines)
        XCTAssertEqual(events, [MonthKey(day(5, 20)).next.first])
        s.clients["butikken"]!.openErrors = [OpenError(puzzleId: "mva-quiz-001", client: "butikken", month: jan, day: day(1, 2), boxBefore: 0)]
        XCTAssertTrue(s.discover(day: day(5, 20), content: content, pool: TownFlowTests.pool).isEmpty)
        var f = flow(s)
        _ = f.talk(to: klientPerson("butikken"))
        XCTAssertEqual(text(f), "Vi venter i arkivet ditt.")
        XCTAssertEqual(f.phase, .dialog)
        _ = f.key(.a)
        XCTAssertEqual(f.phase, .walking, "no pile, no bilag run")
    }

    func testUnparkSkipsTheMonthsAway() {
        var s = state(today: day(3, 10))
        let feb = MonthKey(year: 2026, month: 2)
        s.clients["butikken"]!.book(bilag(jan), boxBefore: 0, client: "butikken")
        s.clients["butikken"]!.closedMonths = [jan, feb]
        XCTAssertTrue(s.park("butikken"))
        s.calendar = TownCalendar(start: day(6, 12))
        XCTAssertTrue(s.unpark("butikken", on: day(6, 12)))
        let client = s.clients["butikken"]!
        XCTAssertEqual(client.status, .active)
        XCTAssertEqual(client.activeFrom, day(6, 12))
        XCTAssertEqual(client.closedMonths, Set((1...5).map { MonthKey(year: 2026, month: $0) }),
                       "January and February closed by the player, March to May away; June is open")
        let mva = DeadlinePlanner.deadlines(for: Self.town.client("butikken")!, year: 2026, deadlines: Self.library.deadlines)
            .first { $0.day == day(6, 10) }
        XCTAssertNotNil(mva, "the term due 10.06 exists")
        XCTAssertFalse(s.counts(mva!, client: client))
        let c = Self.town.client("butikken")!
        XCTAssertNil(Ledger.pileMonth(for: c, start: s.start, today: day(6, 12), state: client, pool: TownFlowTests.pool),
                     "the months away are closed, so they give no pile")
    }

    func testUnparkNeedsRoom() {
        var s = state()
        s.clients["butikken"]!.status = .parked
        for id in ["kafeen", "konsulenten"] { s.clients[id]!.status = .active }
        for i in 0..<(TownRules.portfolioSize - 2) {
            s.clients["fyll\(i)"] = .fresh(.active)
        }
        XCTAssertTrue(s.portfolioFull)
        XCTAssertFalse(s.unpark("butikken", on: day(1, 5)))
        XCTAssertEqual(s.clients["butikken"]!.status, .parked)
        s.clients["fyll0"]!.status = .archived
        XCTAssertFalse(s.portfolioFull)
        XCTAssertTrue(s.unpark("butikken", on: day(1, 5)))
        XCTAssertFalse(s.unpark("kafeen", on: day(1, 5)), "only a parked client can be taken back")
    }

    func testQuitClientCanBeWonBackWithATrial() {
        var s = state()
        s.clients["butikken"]!.satisfaction = 0
        s.clients["butikken"]!.status = .archived
        let before = s.contracts
        var f = flow(s)
        _ = f.talk(to: klientPerson("butikken"))
        XCTAssertTrue(text(f).contains("Vi har funnet et annet kontor."), text(f))
        while f.phase == .dialog { _ = f.key(.a) }
        XCTAssertEqual(f.phase, .choice)
        XCTAssertEqual(f.pages.flatMap { $0 }, ["Prøvesak?"])
        XCTAssertEqual(f.key(.a), .startTrial(client: "butikken"))
        s.winTrial(client: "butikken", on: day(4, 2))
        XCTAssertEqual(s.clients["butikken"]!.status, .active)
        XCTAssertEqual(s.clients["butikken"]!.satisfaction, TownRules.startSatisfaction)
        XCTAssertEqual(s.clients["butikken"]!.activeFrom, day(4, 2))
        XCTAssertEqual(s.contracts, before - 1)
    }

    func testRejoinKeepsAnUnclosedBookedMonth() {
        var client = ClientState.fresh(.parked)
        client.book(bilag(jan), boxBefore: 0, client: "butikken")
        client.closedMonths = []
        client.rejoin(on: day(6, 12), start: jan)
        XCTAssertFalse(client.closedMonths.contains(jan), "a booked month stays open")
        XCTAssertEqual(client.booksFrom(start: jan), jan)
        for m in 2...5 { XCTAssertTrue(client.closedMonths.contains(MonthKey(year: 2026, month: m)), "month \(m)") }
    }

    func testTrialRefusedWhenPortfolioFull() {
        var s = state()
        for i in 0..<TownRules.portfolioSize { s.clients["fyll\(i)"] = .fresh(.active) }
        var f = flow(s)
        _ = f.talk(to: klientPerson("kafeen"))
        while f.phase == .dialog { _ = f.key(.a) }
        XCTAssertEqual(f.phase, .choice)
        f.state.contracts = 0
        XCTAssertEqual(f.key(.a), .none)
        XCTAssertEqual(text(f), "Porteføljen er full.", "full is checked before the contracts")
    }

    func testParkingAndQuittingKeepFullmakterAndCards() {
        var s = state()
        s.fullmakter = ["havna"]
        s.regelkort = ["kort-1"]
        s.found = ["funn-1"]
        XCTAssertTrue(s.park("butikken"))
        XCTAssertTrue(s.unpark("butikken", on: day(2, 1)))
        s.clients["kafeen"]!.status = .archived
        s.winTrial(client: "kafeen", on: day(3, 1))
        XCTAssertEqual(s.fullmakter, ["havna"])
        XCTAssertEqual(s.regelkort, ["kort-1"])
        XCTAssertEqual(s.found, ["funn-1"])
    }

    func testArchiveRowsAndActions() {
        var s = state()
        s.clients["kafeen"]!.status = .parked
        s.clients["konsulenten"]!.status = .archived
        var f = flow(s)
        _ = f.talk(to: person())
        XCTAssertEqual(f.phase, .archive)
        XCTAssertEqual(f.rows.count, 3)
        XCTAssertTrue(f.rows[0].text.hasSuffix(" LEGG BORT"), f.rows[0].text)
        XCTAssertEqual(f.rows[1].text, "KAFÉ HENT")
        XCTAssertTrue(f.rows[2].text.hasSuffix(" SA OPP"), f.rows[2].text)
        _ = f.key(.a)
        XCTAssertEqual(text(f), "Bakeren AS ligger nå i arkivet.")
        XCTAssertEqual(f.state.clients["butikken"]!.status, .parked)
        _ = f.key(.down)
        _ = f.key(.a)
        XCTAssertEqual(text(f), "Kafé Fjord AS er tilbake.")
        XCTAssertEqual(f.state.clients["kafeen"]!.status, .active)
        _ = f.key(.down)
        _ = f.key(.a)
        XCTAssertEqual(text(f), "\(Self.town.client("konsulenten")!.navn) sa opp. Vinn dem tilbake med en prøvesak.")
        XCTAssertEqual(f.phase, .archive)
    }

    func testArchiveRefusesWhenBooksAreOpenOrPortfolioFull() {
        var s = state()
        s.clients["butikken"]!.book(bilag(jan), boxBefore: 0, client: "butikken")
        var f = flow(s)
        _ = f.talk(to: person())
        _ = f.key(.a)
        XCTAssertEqual(text(f), "Lukk månedene for Bakeren AS først.")
        XCTAssertEqual(f.state.clients["butikken"]!.status, .active)
        var full = state()
        full.clients["kafeen"]!.status = .parked
        for i in 0..<TownRules.portfolioSize { full.clients["fyll\(i)"] = .fresh(.active) }
        var g = flow(full)
        _ = g.talk(to: person())
        _ = g.key(.down)
        _ = g.key(.a)
        XCTAssertEqual(text(g), "Porteføljen er full.")
    }

    func testEmptyArchive() {
        var s = state()
        for id in s.clients.keys { s.clients[id]!.status = .prospect }
        var f = flow(s)
        _ = f.talk(to: person())
        XCTAssertEqual(text(f), "Arkivet er tomt.")
    }

    func testArchiveRowsFitTheRow() {
        for town in [Self.town, Self.library.town] {
            var s = TownState.new(content: town, year: 2026)
            let statuses: [ClientStatus] = [.active, .parked, .archived]
            for (i, client) in town.klienter.enumerated() { s.clients[client.id]!.status = statuses[i % 3] }
            var f = TownFlow(content: town, state: s, deadlines: Self.library.deadlines, pool: TownFlowTests.pool,
                             regions: TownFlowTests.regions, damage: [:], badges: [], ruleCards: Self.library.rules)
            _ = f.talk(to: person())
            XCTAssertEqual(f.phase, .archive)
            for row in f.rows { XCTAssertLessThanOrEqual(row.text.count, TownFlow.rowColumns, row.text) }
            XCTAssertEqual(f.rows.count, town.klienter.count)
        }
    }
}
