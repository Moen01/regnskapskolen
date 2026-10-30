import XCTest
@testable import RegnskapKit

/// The manual play-through from the Rubin plan, scripted against the repo's own town: walk to the
/// café, book January with one error, sleep to 1 February, close January at the counter, correct
/// the error, check that Fristnav has no VAT for the doctor, and deliver the first term on time.
/// The steps call Kit the way `AppStore+Town` does.
final class TownStoryTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    /// The repo town without staff: this is the phase 2a play-through, which has no payroll. Payroll
    /// deadlines are covered by `TownPayrollTests` until the later phase 2b steps join them to the story.
    static let town: TownContent = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("by-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.copyItem(at: ContentLocator.repoContent.appendingPathComponent("by"), to: folder)
        let clients = folder.appendingPathComponent("klienter")
        for file in try! FileManager.default.contentsOfDirectory(at: clients, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json["ansatte"] = 0
            json["lonnsdag"] = nil
            try! JSONSerialization.data(withJSONObject: json).write(to: file)
        }
        return try! TownContent.load(folder: folder)
    }()
    var town: TownContent { Self.town }
    var deadlines: Deadlines { Self.library.deadlines }
    var puzzles: [Puzzle] { Self.library.pool(includeDrafts: false) }
    var pool: Set<String> { Set(puzzles.map(\.id)) }
    /// The learner's real day; the town has its own calendar.
    let realDay = DayKey(year: 2026, month: 10, day: 28)
    let jan = MonthKey(year: 2026, month: 1)
    let feb = MonthKey(year: 2026, month: 2)
    let cafe = "kafe-lysthuset"
    let doctor = "legekontoret-bryggen"
    let pixel = "nettbutikken-pixel"
    let motor = "verkstedet-motor"

    func flow(_ state: TownState) -> TownFlow {
        TownFlow(content: town, state: state, deadlines: deadlines, pool: pool, regions: [], damage: [:], ruleCards: Self.library.rules)
    }

    /// Presses the keys; returns every action that was not `.none`.
    @discardableResult
    func press(_ keys: [GameKey], _ f: inout TownFlow) -> [TownAction] {
        keys.map { f.key($0) }.filter { $0 != .none }
    }

    func repeated(_ key: GameKey, _ count: Int) -> [GameKey] { Array(repeating: key, count: count) }

    func readDialog(_ f: inout TownFlow) -> TownAction {
        var last = TownAction.none
        for _ in 0..<50 where f.phase == .dialog { last = f.key(.a) }
        return last
    }

    func attempt(for puzzle: Puzzle, right: Bool) -> PuzzleAttempt {
        switch puzzle.payload {
        case .vat(let v): return right ? .vat(behandling: v.fasit.behandling, fradrag: v.fasit.fradrag) : .vat(behandling: "ingen-slik-kode", fradrag: nil)
        case .quiz(let q): return .quiz(right ? q.svar : (q.svar + 1) % q.alternativer.count)
        case .number(let n): return .number(right ? "\(n.svar)" : "\(n.svar + 1_000_000)")
        case .posting(let p):
            let lines = p.fasit.map { PostingAttemptLine(konto: $0.konto, debet: $0.side == .debet ? $0.belop : nil, kredit: $0.side == .kredit ? $0.belop : nil) }
            return .posting(right ? lines : [PostingAttemptLine(konto: "1920", debet: 1)])
        default:
            XCTFail("no scripted attempt for \(puzzle.kind)")
            return .empty(for: puzzle.kind)
        }
    }

    /// Runs a bilag session to the end, answering right except for `wrongAt`, and books every
    /// answer into the state like the store does.
    func play(_ run: inout BilagRun, state: inout TownState, progress: inout LearnerProgress, wrongAt: Int? = nil) -> [EncounterOutcome] {
        var outcomes: [EncounterOutcome] = []
        var index = 0
        while let encounter = run.current {
            run.choose(encounter.moves.first)
            let puzzle = encounter.puzzle
            let boxBefore = progress.puzzles[puzzle.id]?.box ?? 0
            guard let (outcome, result, _) = run.answer(attempt(for: puzzle, right: index != wrongAt), progress: progress, today: realDay) else {
                XCTFail("answer refused for \(puzzle.id)")
                return outcomes
            }
            Scheduler.record(result, on: realDay, progress: &progress)
            switch run.kind {
            case .booking(let month):
                state.clients[run.client]?.book(BookedBilag(puzzleId: puzzle.id, month: month, day: state.calendar.today, correct: result.correctFirstTry),
                                                boxBefore: boxBefore, client: run.client)
            case .correction:
                if let error = run.currentError { state.clients[run.client]?.correct(error, ok: result.correctFirstTry) }
            }
            outcomes.append(outcome)
            run.proceed()
            index += 1
        }
        return outcomes
    }

    func booking(_ state: TownState) throws -> BilagRun {
        let client = try XCTUnwrap(town.client(cafe))
        let month = try XCTUnwrap(Ledger.pileMonth(for: client, start: state.start, today: state.calendar.today, state: state.clients[cafe]!, pool: pool))
        let ids = Ledger.pile(for: client, month: month, start: state.start, state: state.clients[cafe]!, pool: pool)
        let byId = Dictionary(uniqueKeysWithValues: puzzles.map { ($0.id, $0) })
        return BilagRun(client: client, puzzles: ids.compactMap { byId[$0] }, kind: .booking(month), errors: [],
                        bransjeCards: Self.library.rules(tema: "mva"), otherCards: [], seed: 1)
    }

    func testOneTermFromTheOfficeToTheFirstDelivery() throws {
        var state = TownState.new(content: town, year: 2026)
        var progress = LearnerProgress()
        var f = flow(state)

        // Out of the office: turn down, five steps, the last onto the door.
        XCTAssertEqual(press([.down] + repeated(.down, 5), &f).last, .enteredDoor)
        XCTAssertEqual(f.state.mapId, "sentrum")
        // Along the street below the signs, up to the café door and in, then up to the counter.
        let toCafe: [GameKey] = [.down, .down, .left] + repeated(.left, 10) + [.up, .up, .up]
        XCTAssertEqual(press(toCafe, &f).last, .enteredDoor)
        XCTAssertEqual(f.state.mapId, "restauranten")
        press([.up, .up], &f)
        XCTAssertEqual(f.state.walker, TownWalker(x: 4, y: 4, facing: .up))

        // The owner hands over the pile across the counter, and the first time says how the café runs.
        XCTAssertEqual(f.key(.a), .none)
        XCTAssertEqual(f.phase, .dialog)
        let firstTalk = f.pages.flatMap { $0 }.joined(separator: " ")
        XCTAssertTrue(firstTalk.contains("take-away i disken."), firstTalk)
        XCTAssertTrue(f.state.clients[cafe]!.met)
        XCTAssertEqual(readDialog(&f), .startBilag(client: cafe))
        state = f.state
        XCTAssertTrue(TownAction.startBilag(client: cafe).spendsAction)
        _ = state.spendAction(content: town, deadlines: deadlines)

        // Five bilag, the second one wrong; none of them tells the verdict.
        var run = try booking(state)
        XCTAssertEqual(run.kind, .booking(jan))
        let outcomes = play(&run, state: &state, progress: &progress, wrongAt: 1)
        XCTAssertEqual(outcomes, Array(repeating: .booked, count: TownRules.bilagPerMonth))
        XCTAssertEqual(state.clients[cafe]?.openErrors.count, 1)
        let error = try XCTUnwrap(state.clients[cafe]?.openErrors.first)
        XCTAssertNotNil(state.maskedBox(error.puzzleId), "the collection masks the wrong booking")

        // Sleep: the first stop is 1 February.
        XCTAssertEqual(state.sleep(content: town, deadlines: deadlines), [])
        XCTAssertEqual(state.calendar.today, DayKey(year: 2026, month: 2, day: 1))

        // The counter offers to close January; the error sends the player to correct it.
        f = flow(state)
        let counter = try XCTUnwrap(town.map("kontoret")?.folk.first { $0.rolle == .skranke })
        _ = f.talk(to: counter)
        XCTAssertEqual(f.phase, .counter)
        XCTAssertEqual(f.rows.map(\.text), ["KAFÉ LUKK JAN"])
        XCTAssertEqual(f.key(.a), .startCorrection(client: cafe, month: jan))
        state = f.state

        // The error comes back as a correction, told with its date, and then explained.
        let errors = try XCTUnwrap(state.clients[cafe]?.errors(in: jan))
        let byId = Dictionary(uniqueKeysWithValues: puzzles.map { ($0.id, $0) })
        var correction = BilagRun(client: town.client(cafe)!, puzzles: errors.compactMap { byId[$0.puzzleId] }, kind: .correction, errors: errors,
                                  bransjeCards: [], otherCards: [], seed: 1)
        let encounter = try XCTUnwrap(correction.current)
        XCTAssertTrue(BattleScript.intro(encounter).joined().hasPrefix("Avstemmingen går ikke opp"))
        var battle = BattleFlow(encounter: encounter, laws: Self.library.laws, cards: [], rates: [], attempt: .empty(for: encounter.puzzle.kind))
        var typed = PuzzleAttempt.empty(for: encounter.puzzle.kind)
        battle.showOutcome(.corrected(ok: true))
        for _ in 0..<10 where battle.phase == .outcome { _ = battle.handle(.a, attempt: &typed) }
        XCTAssertEqual(battle.phase, .explanation, "a correction explains the answer")
        XCTAssertEqual(play(&correction, state: &state, progress: &progress), [.corrected(ok: true)])
        state.clients[cafe]?.closeIfClean(jan)
        XCTAssertEqual(state.clients[cafe]?.closedMonths, [jan])

        // The doctor is not VAT registered: Fristnav lists the café's term and nothing for the doctor.
        state.clients[doctor] = ClientState(status: .active, satisfaction: TownRules.startSatisfaction, met: true)
        var april = state
        april.calendar = TownCalendar(start: DayKey(year: 2026, month: 4, day: 7))
        f = flow(april)
        _ = f.openFristnav()
        XCTAssertFalse(f.rows.isEmpty)
        XCTAssertTrue(f.rows.allSatisfy { $0.id.hasPrefix(cafe) }, "\(f.rows.map(\.id))")

        // February: book the pile (all right) in March, close the month, and the term can be delivered.
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 3, day: 2))
        run = try booking(state)
        XCTAssertEqual(run.kind, .booking(feb))
        _ = play(&run, state: &state, progress: &progress)
        f = flow(state)
        _ = f.talk(to: counter)
        XCTAssertEqual(f.rows.map(\.text), ["KAFÉ LUKK FEB"])
        XCTAssertEqual(f.key(.a), .none, "a clean month closes on the spot")
        state = f.state
        XCTAssertEqual(state.clients[cafe]?.closedMonths, [jan, feb])

        // Sleep to the deadline, stopping at each event on the way, and deliver on the day.
        var stops: [DayKey] = []
        while state.calendar.today < deadlines.mvaFrist(termin: 1, year: 2026) {
            XCTAssertEqual(state.sleep(content: town, deadlines: deadlines), [])
            stops.append(state.calendar.today)
        }
        XCTAssertEqual(stops.last, deadlines.mvaFrist(termin: 1, year: 2026))
        XCTAssertTrue(stops.contains(deadlines.mvaFrist(termin: 1, year: 2026).adding(days: -TownRules.warnDaysBefore)))
        f = flow(state)
        _ = f.talk(to: counter)
        let deliverRow = try XCTUnwrap(f.rows.firstIndex { $0.text == "KAFÉ LEVER MVA1" })
        for _ in 0..<deliverRow { _ = f.key(.down) }
        let kind = DeadlineKind.mva(termin: 1, year: 2026)
        XCTAssertEqual(f.key(.a), .deliver(client: cafe, kind: kind))
        state = f.state
        state.clients[cafe]?.deliver(kind)

        // The day after the deadline: nothing missed for the café.
        XCTAssertEqual(state.sleep(content: town, deadlines: deadlines).filter { $0.client == cafe }, [])
        XCTAssertEqual(state.clients[cafe]?.delivered, [kind.id])
    }

    func testMissedDeadlineIsFoundOnTheNewDayAndOnlyForActiveClients() {
        var state = TownState.new(content: town, year: 2026)
        let due = deadlines.mvaFrist(termin: 1, year: 2026)
        state.calendar = TownCalendar(start: due)
        // Spending the last action of the deadline day starts the next day: the term is missed.
        var missed: [TownDeadline] = []
        for _ in 0..<TownRules.actionsPerDay { missed += state.spendAction(content: town, deadlines: deadlines) }
        XCTAssertEqual(state.calendar.today, due.adding(days: 1))
        XCTAssertEqual(missed.map(\.client), [cafe], "only the active café; prospects have no deadlines")
        XCTAssertEqual(missed.map(\.kind), [.mva(termin: 1, year: 2026)])
        XCTAssertEqual(state.checkMissed(content: town, deadlines: deadlines), [], "a miss is counted once")
    }

    func testANewGameDoesNotMissLastYearsTerm() {
        // The sixth term of the year before falls due in February; the game did not run then.
        var state = TownState.new(content: town, year: 2026)
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 3, day: 15))
        XCTAssertEqual(state.checkMissed(content: town, deadlines: deadlines), [])
    }

    func testFreeActionsDoNotSpendTime() {
        let free: [TownAction] = [.none, .walked, .enteredDoor, .save, .openTraining, .openCollection, .sleep]
        XCTAssertTrue(free.allSatisfy { !$0.spendsAction })
        XCTAssertTrue(TownAction.deliver(client: cafe, kind: .mva(termin: 1, year: 2026)).spendsAction)
        XCTAssertTrue(TownAction.startTrial(client: cafe).spendsAction)
    }

    func testDeliveringWithTheLastActionOnTheDeadlineDayCounts() {
        var state = TownState.new(content: town, year: 2026)
        let due = deadlines.mvaFrist(termin: 1, year: 2026)
        let kind = DeadlineKind.mva(termin: 1, year: 2026)
        state.calendar = TownCalendar(start: due)
        for _ in 0..<(TownRules.actionsPerDay - 1) { _ = state.spendAction(content: town, deadlines: deadlines) }
        XCTAssertEqual(state.calendar.today, due, "eleven actions keep the day")
        let before = state.clients[cafe]!.satisfaction

        let missed = state.deliver(client: cafe, kind: kind, content: town, deadlines: deadlines)

        XCTAssertEqual(state.calendar.today, due.adding(days: 1), "the twelfth action ends the day")
        XCTAssertEqual(missed, [], "delivered before the day ended")
        XCTAssertEqual(state.clients[cafe]?.missed, [])
        XCTAssertEqual(state.clients[cafe]?.delivered, [kind.id])
        XCTAssertEqual(state.clients[cafe]?.satisfaction, min(TownRules.maxSatisfaction, before + TownRules.deliverBonus))
    }

    func testAnErrorOnAHiddenDraftDoesNotBlockTheClose() throws {
        var state = TownState.new(content: town, year: 2026)
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 2, day: 2))
        let client = try XCTUnwrap(town.client(cafe))
        let ids = Ledger.pile(for: client, month: jan, start: state.start, state: state.clients[cafe]!, pool: pool)
        for (i, id) in ids.enumerated() {
            state.clients[cafe]?.book(BookedBilag(puzzleId: id, month: jan, day: jan.first, correct: i != 0), boxBefore: 2, client: cafe)
        }
        let wrong = ids[0]
        // "Show drafts" switched off after the booking: the wrong bilag's puzzle is no longer visible.
        let hidden = pool.subtracting([wrong])
        XCTAssertEqual(state.clients[cafe]?.errors(in: jan).count, 1)
        XCTAssertEqual(state.clients[cafe]?.errors(in: jan, pool: hidden), [])

        var f = TownFlow(content: town, state: state, deadlines: deadlines, pool: hidden, regions: [], damage: [:], ruleCards: [])
        let counter = try XCTUnwrap(town.map("kontoret")?.folk.first { $0.rolle == .skranke })
        _ = f.talk(to: counter)
        XCTAssertEqual(f.rows.map(\.text), ["KAFÉ LUKK JAN"])
        XCTAssertEqual(f.key(.a), .none, "no correction offered for a puzzle that cannot be shown")
        XCTAssertEqual(f.state.clients[cafe]?.closedMonths, [jan])
        XCTAssertEqual(f.state.clients[cafe]?.openErrors, [], "the hidden error goes with the closed month")
        XCTAssertNil(f.state.maskedBox(wrong))

        // With the puzzle visible, the same error still blocks the close.
        var visible = state.clients[cafe]!
        visible.closeIfClean(jan, pool: pool)
        XCTAssertEqual(visible.closedMonths, [])
    }

    /// Talks to the client where it stands, says yes to the trial, and wins it the way the store does.
    func winTrial(_ id: String, state: inout TownState) throws {
        let client = try XCTUnwrap(town.client(id))
        let person = try XCTUnwrap(town.map(client.sted.kart)?.folk.first { $0.rolle == .klient && $0.klient == id })
        var f = flow(state)
        _ = f.talk(to: person)
        _ = readDialog(&f)
        XCTAssertEqual(f.phase, .choice, id)
        XCTAssertEqual(f.key(.a), .startTrial(client: id))
        state = f.state
        state.winTrial(client: id, on: state.calendar.today)
        _ = state.spendAction(content: town, deadlines: deadlines)
    }

    func testAllThreeTrialsCanBeWonInPhase2a() throws {
        var state = TownState.new(content: town, year: 2026)
        XCTAssertEqual(state.contracts, 3)
        for id in [pixel, motor, doctor] { try winTrial(id, state: &state) }
        XCTAssertEqual(state.clients.values.filter { $0.status == .active }.count, 4)
        XCTAssertEqual(state.contracts, 0)
        XCTAssertEqual(state.clients[pixel]?.activeFrom, DayKey(year: 2026, month: 1, day: 1))
        XCTAssertNil(state.clients[cafe]?.activeFrom, "the start client covers every deadline")
    }

    func testAClientWonAfterADeadlineHasNotMissedIt() throws {
        var state = TownState.new(content: town, year: 2026)
        let wonOn = DayKey(year: 2026, month: 4, day: 12)
        state.calendar = TownCalendar(start: wonOn)
        state.clients[cafe]?.delivered = [DeadlineKind.mva(termin: 1, year: 2026).id]
        try winTrial(pixel, state: &state)
        XCTAssertEqual(state.clients[pixel]?.activeFrom, wonOn)

        var missed: [TownDeadline] = []
        while state.calendar.today < DayKey(year: 2026, month: 5, day: 2) { missed += state.sleep(content: town, deadlines: deadlines) }
        XCTAssertEqual(missed, [], "term 1 fell due on 10 April, before Pixel was won")
        XCTAssertEqual(state.clients[pixel]?.missed, [])
        XCTAssertEqual(state.clients[pixel]?.satisfaction, TownRules.startSatisfaction)

        // January and February closed: the counter offers no delivery for term 1.
        state.clients[pixel]?.closedMonths = [jan, feb]
        var f = flow(state)
        let counter = try XCTUnwrap(town.map("kontoret")?.folk.first { $0.rolle == .skranke })
        _ = f.talk(to: counter)
        XCTAssertFalse(f.rows.contains { $0.text.hasPrefix("PIXEL LEVER") }, "\(f.rows.map(\.text))")

        // Term 2 (due in June) is Pixel's: Fristnav lists it, and it is missed when not delivered.
        state.calendar = TownCalendar(start: deadlines.mvaFrist(termin: 2, year: 2026).adding(days: -2))
        f = flow(state)
        _ = f.openFristnav()
        XCTAssertTrue(f.rows.contains { $0.id == "\(pixel):mva-2026-2" }, "\(f.rows.map(\.id))")
        while state.calendar.today <= deadlines.mvaFrist(termin: 2, year: 2026) { missed += state.sleep(content: town, deadlines: deadlines) }
        XCTAssertTrue(missed.contains { $0.client == pixel && $0.kind == .mva(termin: 2, year: 2026) })
    }

    func testFristnavRowsKeepTheClientName() throws {
        var state = TownState.new(content: town, year: 2026)
        for id in [pixel, motor] { state.clients[id]?.status = .active }
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 4, day: 7))
        var f = flow(state)
        _ = f.openFristnav()
        XCTAssertEqual(f.rows.map(\.text), ["10.04 MVA1 KAFÉ", "10.04 MVA1 PIXEL", "10.04 MVA1 MOTOR"])
        XCTAssertEqual(f.rows.first?.full, "10.04 MVA 1. TERMIN Kafé Lysthuset AS")
        XCTAssertTrue(f.rows.allSatisfy { $0.text.count <= TownFlow.rowColumns && !$0.text.contains("…") })
    }

    func testATrialDoesNotSpoilTheClientsPile() {
        // The trial shows the answer and explanation, so its puzzles must not come back as bilag.
        for client in town.klienter where !client.startklient {
            XCTAssertEqual(Set(client.provesak).intersection(client.oppgaver), [], client.id)
        }
    }
}
