import XCTest
@testable import RegnskapKit

final class TownFlowTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    static let town = try! TownContent.load(folder: TownContentTests.fixtureTown)
    static let regions = Regions.build(topics: library.topics, pool: library.pool(includeDrafts: false), progress: LearnerProgress())
    static let pool: Set<String> = ["mva-quiz-001", "grunnlag-quiz-010"]
    let jan = MonthKey(year: 2026, month: 1)
    let feb = MonthKey(year: 2026, month: 2)

    func day(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }

    /// A new game moved to a place and a date.
    func state(map: String = "kontoret", x: Int, y: Int, facing: Facing = .up, today: DayKey? = nil) -> TownState {
        var s = TownState.new(content: Self.town, year: 2026)
        s.mapId = map
        s.walker = TownWalker(x: x, y: y, facing: facing)
        s.calendar = TownCalendar(start: today ?? day(1, 5))
        return s
    }

    func flow(_ state: TownState, pool: Set<String> = TownFlowTests.pool, damage: [String: Int] = [:], badges: Set<String> = []) -> TownFlow {
        TownFlow(content: Self.town, state: state, deadlines: Self.library.deadlines, pool: pool, regions: Self.regions,
                 damage: damage, badges: badges, ruleCards: Self.library.rules)
    }

    func text(_ f: TownFlow) -> String { f.pages.map { $0.joined(separator: " ") }.joined(separator: " ") }

    /// Presses A through the dialog; returns the action of the last press.
    @discardableResult
    func readDialog(_ f: inout TownFlow, file: StaticString = #filePath, line: UInt = #line) -> TownAction {
        var action = TownAction.none
        var guardCount = 0
        while f.phase == .dialog {
            action = f.key(.a)
            guardCount += 1
            if guardCount > 50 { XCTFail("dialog never ends", file: file, line: line); break }
        }
        return action
    }

    func bookAll(_ s: inout TownState, client: String, month: MonthKey, correct: Bool = true) {
        let c = Self.town.client(client)!
        for id in Ledger.pile(for: c, month: month, start: s.start, state: s.clients[client]!, pool: Self.pool) {
            s.clients[client]!.book(BookedBilag(puzzleId: id, month: month, day: month.first, correct: correct), boxBefore: 0, client: client)
        }
    }

    // MARK: Walking

    func testEnterOnNothingOpensTheMenu() {
        // Facing left at (3, 3) in the office: empty floor.
        var f = flow(state(x: 3, y: 3, facing: .left))
        XCTAssertEqual(f.key(.a), .none)
        XCTAssertEqual(f.phase, .menu)
        XCTAssertEqual(f.rows.map(\.text), TownFlow.mainMenu)
        XCTAssertEqual(f.cursor, 0)
        XCTAssertEqual(f.key(.b), .none)
        XCTAssertEqual(f.phase, .walking)

        _ = f.key(.a)
        _ = f.key(.down)
        _ = f.key(.down)
        XCTAssertEqual(f.cursor, 2)
        XCTAssertEqual(f.key(.a), .openCollection)
        XCTAssertEqual(f.phase, .walking)
        _ = f.key(.a)
        _ = f.key(.down); _ = f.key(.down); _ = f.key(.down)
        XCTAssertEqual(f.key(.a), .openTraining)
        _ = f.key(.a)
        for _ in 0..<10 { _ = f.key(.down) }
        XCTAssertEqual(f.cursor, 4)
        XCTAssertEqual(f.key(.a), .save)
    }

    func testDoorChangesMap() {
        var f = flow(state(x: 3, y: 3, facing: .up))
        XCTAssertEqual(f.key(.down), .none)  // turns
        XCTAssertEqual(f.key(.down), .walked)
        XCTAssertEqual(f.state.walker.y, 4)
        XCTAssertEqual(f.key(.right), .none)  // turns
        XCTAssertEqual(f.key(.left), .none)  // turns back
        XCTAssertEqual(f.key(.down), .none)  // turns
        XCTAssertEqual(f.key(.down), .enteredDoor)
        XCTAssertEqual(f.state.mapId, "sentrum")
        XCTAssertEqual(f.state.walker.x, 4)
        XCTAssertEqual(f.state.walker.y, 3)
        XCTAssertEqual(f.state.walker.facing, .down)
        XCTAssertEqual(f.phase, .walking)
    }

    // MARK: Clients

    func testMeetingAProspectCreatesTheNeedsCard() {
        var f = flow(state(map: "sentrum", x: 6, y: 3))
        XCTAssertFalse(f.state.clients["konsulenten"]!.met)
        _ = f.key(.a)
        XCTAssertEqual(f.phase, .dialog)
        XCTAssertTrue(text(f).contains("God dag."))
        XCTAssertTrue(f.state.clients["konsulenten"]!.met)
        readDialog(&f)
        // The drift line was on a later page.
        XCTAssertEqual(f.phase, .choice)
        XCTAssertEqual(f.rows.map(\.text), ["JA", "NEI"])
        XCTAssertTrue(text(f).contains("Prøvesak?"))
        XCTAssertEqual(f.key(.b), .none)
        XCTAssertEqual(f.phase, .walking)

        // The second talk is only the greeting.
        _ = f.key(.a)
        XCTAssertFalse(text(f).contains("rolig"))

        // The needs card in the portfolio.
        var g = flow(f.state)
        g.state.walker = TownWalker(x: 5, y: 3, facing: .down)
        _ = g.key(.a)
        XCTAssertEqual(g.phase, .menu)
        _ = g.key(.down)
        _ = g.key(.a)
        XCTAssertEqual(g.phase, .portfolio)
        XCTAssertEqual(Set(g.rows.map(\.id)), ["butikken", "konsulenten"])
        while g.rows[g.cursor].id != "konsulenten" { _ = g.key(.down) }
        _ = g.key(.a)
        let card = text(g)
        // "Konsulentvirksomhet" is 19 characters, so TextWrap cuts it with a hyphen.
        XCTAssertTrue(card.contains("Konsulentvirksomh-"), card)
        XCTAssertTrue(card.contains("Ikke mva-registrert"), card)
        XCTAssertTrue(card.contains("Mva-terminer og frister"), card)
    }

    func testTrialNeedsAContract() {
        var s = state(map: "sentrum", x: 6, y: 3)
        s.contracts = 0
        var f = flow(s)
        _ = f.key(.a)
        readDialog(&f)
        XCTAssertEqual(f.phase, .choice)
        XCTAssertEqual(f.key(.a), .none)  // JA
        XCTAssertEqual(f.phase, .dialog)
        XCTAssertTrue(text(f).contains("Du har ingen oppdragsavtale."))
        XCTAssertEqual(readDialog(&f), .none)
        XCTAssertEqual(f.phase, .walking)

        s.contracts = 1
        var g = flow(s)
        _ = g.key(.a)
        readDialog(&g)
        XCTAssertEqual(g.key(.a), .startTrial(client: "konsulenten"))
        XCTAssertEqual(g.phase, .walking)

        // NEI just ends the talk.
        _ = g.key(.a)
        readDialog(&g)
        _ = g.key(.down)
        XCTAssertEqual(g.key(.a), .none)
        XCTAssertEqual(g.phase, .walking)
    }

    func testActiveClientWithPileStartsBilag() {
        var f = flow(state(map: "sentrum", x: 2, y: 3))
        XCTAssertFalse(f.state.clients["butikken"]!.met)
        XCTAssertEqual(f.key(.a), .none)
        // The start client is active from the start; its first talk still tells how it runs.
        XCTAssertTrue(f.state.clients["butikken"]!.met)
        XCTAssertTrue(text(f).contains("Hei! Bilagene ligger klare."))
        XCTAssertTrue(text(f).contains("travel uke"))
        XCTAssertTrue(text(f).contains("Her er bilagene dine."))
        XCTAssertEqual(readDialog(&f), .startBilag(client: "butikken"))
        XCTAssertEqual(f.phase, .walking)
        // The second talk is only the pile.
        _ = f.key(.a)
        XCTAssertFalse(text(f).contains("travel uke"))
        XCTAssertTrue(text(f).contains("Her er bilagene dine."))
        XCTAssertEqual(readDialog(&f), .startBilag(client: "butikken"))

        // R1: a January bilag left unbooked is still the pile in March.
        var march = flow(state(map: "sentrum", x: 2, y: 3, today: day(3, 2)))
        _ = march.key(.a)
        XCTAssertEqual(readDialog(&march), .startBilag(client: "butikken"))

        var empty = flow(state(map: "sentrum", x: 2, y: 3), pool: [])
        _ = empty.key(.a)
        XCTAssertTrue(text(empty).contains("Ingen bilag denne måneden."))
        XCTAssertEqual(readDialog(&empty), .none)
        XCTAssertEqual(empty.phase, .walking)
    }

    // MARK: Counter

    func testCounterOffersCloseAfterTheMonthEnds() {
        var s = state(x: 1, y: 3, today: day(1, 31))
        bookAll(&s, client: "butikken", month: jan)
        var f = flow(s)
        _ = f.key(.a)
        // January has not ended: nothing to do.
        XCTAssertEqual(f.phase, .dialog)
        XCTAssertEqual(readDialog(&f), .none)

        s.calendar = TownCalendar(start: day(2, 1))
        var g = flow(s)
        _ = g.key(.a)
        XCTAssertEqual(g.phase, .counter)
        XCTAssertEqual(g.rows.map(\.text), ["BAKEREN LUKK JAN"])
        XCTAssertEqual(g.key(.a), .none)
        XCTAssertEqual(g.state.clients["butikken"]!.closedMonths, [jan])
        XCTAssertEqual(g.phase, .dialog)
        XCTAssertEqual(readDialog(&g), .none)
        XCTAssertEqual(g.phase, .walking)

        // An open error sends the player to correct it instead.
        var w = state(x: 1, y: 3, today: day(2, 1))
        bookAll(&w, client: "butikken", month: jan, correct: false)
        var h = flow(w)
        _ = h.key(.a)
        XCTAssertEqual(h.rows.map(\.text), ["BAKEREN LUKK JAN"])
        XCTAssertEqual(h.key(.a), .startCorrection(client: "butikken", month: jan))
        XCTAssertEqual(h.state.clients["butikken"]!.closedMonths, [])
        XCTAssertEqual(h.phase, .walking)
    }

    func testCounterOffersDeliverWhenTermIsClosed() {
        var s = state(x: 1, y: 3, today: day(3, 2))
        s.clients["butikken"]!.closedMonths = [jan]
        var f = flow(s)
        _ = f.key(.a)
        // February is not closed yet: only the close row.
        XCTAssertEqual(f.rows.map(\.text), ["BAKEREN LUKK FEB"])

        s.clients["butikken"]!.closedMonths = [jan, feb]
        var g = flow(s)
        _ = g.key(.a)
        XCTAssertEqual(g.phase, .counter)
        // "BAKEREN LEVER MVA1" is 18 columns: the name is cut, never the term.
        XCTAssertEqual(g.rows.map(\.text), ["BAKER… LEVER MVA1"])
        XCTAssertEqual(g.rows.map(\.full), ["Lever 10.04 MVA 1. TERMIN for Bakeren AS"])
        XCTAssertEqual(g.key(.a), .deliver(client: "butikken", kind: .mva(termin: 1, year: 2026)))
        XCTAssertEqual(g.phase, .walking)

        s.clients["butikken"]!.delivered = [DeadlineKind.mva(termin: 1, year: 2026).id]
        var h = flow(s)
        _ = h.key(.a)
        XCTAssertEqual(h.phase, .dialog)
    }

    // MARK: Fristnav

    func testFristnavMarksThreeDaysLeft() {
        // 10.04.2026 is a Friday: the first term's deadline does not move.
        for (today, marked) in [(day(4, 6), false), (day(4, 7), true)] {
            var f = flow(state(x: 3, y: 3, facing: .left, today: today))
            _ = f.key(.a)
            XCTAssertEqual(f.key(.a), .none)
            XCTAssertEqual(f.phase, .fristnav)
            XCTAssertEqual(f.rows.count, 1)
            XCTAssertEqual(f.rows[0].text, "10.04 MVA1 BAKER…")
            XCTAssertEqual(f.rows[0].full, "10.04 MVA 1. TERMIN Bakeren AS")
            XCTAssertEqual(f.rows[0].marked, marked, "\(today)")
            XCTAssertTrue(f.rows.allSatisfy { $0.text.count <= 17 })
        }
        var empty = flow(state(x: 3, y: 3, facing: .left, today: day(1, 5)))
        _ = empty.key(.a)
        _ = empty.key(.a)
        XCTAssertEqual(empty.rows, [])
        XCTAssertFalse(text(empty).isEmpty)
        XCTAssertEqual(empty.key(.b), .none)
        XCTAssertEqual(empty.phase, .walking)
    }

    // MARK: Fagkontor

    func testFagkontorShowsProgressWhenClosed() throws {
        let target = try XCTUnwrap(Self.regions.first { $0.tema == "mva" }).damageTarget
        XCTAssertGreaterThan(target, 2)
        var f = flow(state(x: 5, y: 2), damage: ["mva": 2])
        _ = f.key(.a)
        XCTAssertEqual(f.phase, .dialog)
        XCTAssertTrue(text(f).contains("Her prøves mva."))
        XCTAssertTrue(f.pages.joined().contains("GYM 2/\(target)"), "\(f.pages)")
        XCTAssertEqual(readDialog(&f), .none)
        XCTAssertEqual(f.phase, .walking)

        let ref = try XCTUnwrap(Self.town.map("kontoret")?.folk.first { $0.rolle == .fagkontor }?.fagkontor)
        var open = flow(state(x: 5, y: 2), damage: ["mva": target])
        _ = open.key(.a)
        readDialog(&open)
        XCTAssertEqual(open.phase, .choice)
        XCTAssertTrue(text(open).contains("Vil du prøve?"))
        XCTAssertEqual(open.key(.a), .startFagkontor(ref))

        var done = flow(state(x: 5, y: 2), damage: ["mva": target], badges: [TownTrials.badgeKey(ref)])
        _ = done.key(.a)
        XCTAssertTrue(text(done).contains("Du har alt merket."))
        XCTAssertEqual(readDialog(&done), .none)
    }

    // MARK: Width

    func testClientRowCutsTheNameNotTheDeadline() {
        let annual = TownFlow.clientRow(id: "x", name: "LEGEKONTORET", detail: "LEVER MVAÅR", nameFirst: true, full: "full")
        XCTAssertEqual(annual.text, "LEGE… LEVER MVAÅR")
        XCTAssertLessThanOrEqual(annual.text.count, TownFlow.rowColumns)
        XCTAssertEqual(annual.full, "full")
        XCTAssertEqual(TownFlow.clientRow(id: "x", name: "KAFÉ", detail: "10.04 MVA1", nameFirst: false, full: "").text, "10.04 MVA1 KAFÉ")
    }


    func testEveryPageLineFitsEighteen() throws {
        var seen: [[[String]]] = []
        func check(_ f: TownFlow, _ label: String) {
            seen.append(f.pages)
            for page in f.pages {
                XCTAssertLessThanOrEqual(page.count, 3, "\(label): \(page)")
                for line in page { XCTAssertLessThanOrEqual(line.count, 18, "\(label): «\(line)»") }
            }
            for row in f.rows { XCTAssertLessThanOrEqual(row.text.count, 17, "\(label): row «\(row.text)»") }
        }
        /// Talks to the person, reads every page, then tries each choice row.
        func talkThrough(_ start: TownFlow, _ person: TownPerson) {
            var f = start
            _ = f.talk(to: person)
            check(f, person.id)
            while f.phase == .dialog { _ = f.key(.a); check(f, person.id) }
            let listed = f
            for i in listed.rows.indices {
                var g = listed
                while g.cursor < i { _ = g.key(.down) }
                _ = g.key(.a)
                check(g, "\(person.id) row \(i)")
                while g.phase == .dialog { _ = g.key(.a); check(g, "\(person.id) row \(i)") }
            }
        }

        let target = Self.regions.first { $0.tema == "mva" }?.damageTarget ?? 0
        let ref = Self.town.map("kontoret")?.folk.first { $0.rolle == .fagkontor }?.fagkontor
        var states: [TownState] = []
        var fresh = state(x: 3, y: 3, today: day(4, 7))
        states.append(fresh)
        fresh.clients["konsulenten"]!.met = true
        fresh.contracts = 0
        states.append(fresh)
        var counter = state(x: 3, y: 3, today: day(3, 2))
        counter.clients["butikken"]!.closedMonths = [jan, feb]
        counter.clients["konsulenten"]!.status = .active
        states.append(counter)
        var errors = state(x: 3, y: 3, today: day(2, 1))
        bookAll(&errors, client: "butikken", month: jan, correct: false)
        states.append(errors)

        for s in states {
            for (damage, badges) in [([String: Int](), Set<String>()), (["mva": target], Set<String>()), (["mva": target], Set(ref.map { [TownTrials.badgeKey($0)] } ?? []))] {
                for pool in [Self.pool, []] {
                    let base = flow(s, pool: pool, damage: damage, badges: badges)
                    for map in Self.town.kart {
                        for person in map.folk { talkThrough(base, person) }
                    }
                    // The menu and every list it opens, row by row.
                    var menu = base
                    menu.state.walker = TownWalker(x: 3, y: 3, facing: .left)
                    _ = menu.key(.a)
                    check(menu, "menu")
                    for i in 0..<2 {
                        var list = menu
                        while list.cursor < i { _ = list.key(.down) }
                        _ = list.key(.a)
                        check(list, "menu \(i)")
                        for _ in list.rows.indices {
                            _ = list.key(.a); check(list, "menu \(i) A")
                            _ = list.key(.tab); check(list, "menu \(i) tab")
                            _ = list.key(.down); check(list, "menu \(i) down")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(seen.count, 50)
    }
}
