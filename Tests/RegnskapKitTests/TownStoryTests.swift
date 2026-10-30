import XCTest
@testable import RegnskapKit

/// The manual play-through from the Rubin plan, scripted against the repo's own town: walk to the
/// café, book January with one error, sleep to 1 February, close January at the counter, correct
/// the error, check that Fristnav has no VAT for the doctor, and deliver the first term on time.
/// The steps call Kit the way `AppStore+Town` does.
final class TownStoryTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    static var town: TownContent { library.town }
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
            case .kundesak(let id):
                state.clients[run.client]?.answerCase(id, ok: result.correctFirstTry)
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
        _ = state.spendAction(content: town, deadlines: deadlines, pool: [])

        // Five bilag, the second one wrong; none of them tells the verdict.
        var run = try booking(state)
        XCTAssertEqual(run.kind, .booking(jan))
        let outcomes = play(&run, state: &state, progress: &progress, wrongAt: 1)
        XCTAssertEqual(outcomes, Array(repeating: .booked, count: TownRules.bilagPerMonth))
        XCTAssertEqual(state.clients[cafe]?.openErrors.count, 1)
        let error = try XCTUnwrap(state.clients[cafe]?.openErrors.first)
        XCTAssertNotNil(state.maskedBox(error.puzzleId), "the collection masks the wrong booking")

        // Sleep: the café's January withholding is due 21 January, so the sleep stops three days
        // before and on the day. The player delivers it, then the next stop is 1 February.
        let trekk = DeadlineKind.forskuddstrekk(month: jan)
        for stop in [18, 21] {
            XCTAssertEqual(state.sleep(content: town, deadlines: deadlines, pool: []), [])
            XCTAssertEqual(state.calendar.today, DayKey(year: 2026, month: 1, day: stop))
        }
        state.clients[cafe]?.deliver(trekk)
        XCTAssertEqual(state.sleep(content: town, deadlines: deadlines, pool: []), [])
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

        // The doctor is not VAT registered: Fristnav lists the café's term and no VAT for the doctor.
        state.clients[doctor] = ClientState(status: .active, satisfaction: TownRules.startSatisfaction, met: true)
        var april = state
        april.calendar = TownCalendar(start: DayKey(year: 2026, month: 4, day: 7))
        f = flow(april)
        _ = f.openFristnav()
        XCTAssertFalse(f.rows.isEmpty)
        XCTAssertTrue(f.rows.contains { $0.id == "\(cafe):mva-2026-1" }, "\(f.rows.map(\.id))")
        XCTAssertFalse(f.rows.contains { $0.id.hasPrefix(doctor) && $0.id.contains(":mva") }, "\(f.rows.map(\.id))")

        // February: book the pile (all right) in March, close the month, and the term can be delivered.
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 3, day: 2))
        run = try booking(state)
        XCTAssertEqual(run.kind, .booking(feb))
        _ = play(&run, state: &state, progress: &progress)
        f = flow(state)
        _ = f.talk(to: counter)
        XCTAssertEqual(f.rows.map(\.text).filter { $0.hasPrefix("KAFÉ") }, ["KAFÉ LUKK FEB", "KAFÉ LEVER AMELD1", "KAFÉ LEVER TREKK2"])
        XCTAssertEqual(f.key(.a), .none, "a clean month closes on the spot")
        state = f.state
        XCTAssertEqual(state.clients[cafe]?.closedMonths, [jan, feb])

        // With both months closed the payroll that is due can be delivered: the a-meldinger and the
        // first AGA term, and February's withholding.
        var delivered: [DeadlineKind] = []
        while let kind = try deliverNextCafeRow(&state, counter: counter) { delivered.append(kind) }
        XCTAssertEqual(Set(delivered), [.amelding(month: jan), .amelding(month: feb), .forskuddstrekk(month: feb), .aga(termin: 1, year: 2026)])

        // Sleep to the deadline, stopping at each event on the way, and deliver on the day.
        var stops: [DayKey] = []
        var missed: [TownDeadline] = []
        while state.calendar.today < deadlines.mvaFrist(termin: 1, year: 2026) {
            missed += state.sleep(content: town, deadlines: deadlines, pool: [])
            stops.append(state.calendar.today)
        }
        // March is never booked in this story, so March payroll goes by; the VAT term does not.
        XCTAssertEqual(Set(missed.filter { $0.client == cafe }.map(\.kind.id)), ["trekk-2026-03", "amelding-2026-03"])
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
        XCTAssertEqual(state.sleep(content: town, deadlines: deadlines, pool: []).filter { $0.client == cafe }, [])
        XCTAssertTrue(state.clients[cafe]?.delivered.contains(kind.id) == true)
        XCTAssertEqual(state.clients[cafe]?.missed, ["trekk-2026-03", "amelding-2026-03"])
    }

    /// Delivers the first payroll "LEVER" row the counter offers the café, the way the store does. Returns
    /// nil when there is none.
    func deliverNextCafeRow(_ state: inout TownState, counter: TownPerson) throws -> DeadlineKind? {
        var f = flow(state)
        _ = f.talk(to: counter)
        guard f.phase == .counter, let row = f.rows.firstIndex(where: { $0.text.hasPrefix("KAFÉ LEVER") && !$0.text.contains("MVA") }) else { return nil }
        for _ in 0..<row { _ = f.key(.down) }
        guard case let .deliver(client, kind) = f.key(.a) else {
            XCTFail("the counter row did not deliver")
            return nil
        }
        state = f.state
        state.clients[client]?.deliver(kind)
        return kind
    }

    func testAPayrollMonthFromPayDayToAmelding() throws {
        var state = TownState.new(content: town, year: 2026)
        let counter = try XCTUnwrap(town.map("kontoret")?.folk.first { $0.rolle == .skranke })
        let trekk = DeadlineKind.forskuddstrekk(month: jan)
        let amelding = DeadlineKind.amelding(month: jan)

        // The café pays on the 20th: nothing the day before, withholding on the day.
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 1, day: 19))
        var f = flow(state)
        _ = f.talk(to: counter)
        XCTAssertEqual(f.phase, .dialog, "nothing to deliver yet")
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 1, day: 20))
        f = flow(state)
        _ = f.talk(to: counter)
        XCTAssertEqual(f.rows.map(\.text), ["KAFÉ LEVER TREKK1"])
        XCTAssertEqual(f.key(.a), .deliver(client: cafe, kind: trekk))
        state = f.state
        XCTAssertEqual(state.deliver(client: cafe, kind: trekk, content: town, deadlines: deadlines, pool: []), [])

        // The month is booked and sleeping reaches 1 February without anything missed.
        let client = try XCTUnwrap(town.client(cafe))
        for id in Ledger.pile(for: client, month: jan, start: state.start, state: state.clients[cafe]!, pool: pool) {
            state.clients[cafe]?.book(BookedBilag(puzzleId: id, month: jan, day: jan.first, correct: true), boxBefore: 0, client: cafe)
        }
        while state.calendar.today < DayKey(year: 2026, month: 2, day: 1) {
            XCTAssertEqual(state.sleep(content: town, deadlines: deadlines, pool: []), [])
        }
        XCTAssertEqual(state.calendar.today, DayKey(year: 2026, month: 2, day: 1))

        // January closes, which opens the a-melding; it is delivered on the deadline day.
        f = flow(state)
        _ = f.talk(to: counter)
        XCTAssertEqual(f.rows.map(\.text), ["KAFÉ LUKK JAN"])
        XCTAssertEqual(f.key(.a), .none)
        state = f.state
        f = flow(state)
        _ = f.talk(to: counter)
        XCTAssertEqual(f.rows.map(\.text), ["KAFÉ LEVER AMELD1"])
        let due = deadlines.ameldingFrist(forMonth: 1, year: 2026)
        while state.calendar.today < due { XCTAssertEqual(state.sleep(content: town, deadlines: deadlines, pool: []), []) }
        XCTAssertEqual(state.calendar.today, due)
        f = flow(state)
        _ = f.talk(to: counter)
        XCTAssertEqual(f.key(.a), .deliver(client: cafe, kind: amelding))
        state = f.state
        XCTAssertEqual(state.deliver(client: cafe, kind: amelding, content: town, deadlines: deadlines, pool: []), [])
        XCTAssertEqual(state.clients[cafe]?.delivered, [trekk.id, amelding.id])
        XCTAssertEqual(state.clients[cafe]?.missed, [])
    }

    func testMissedDeadlineIsFoundOnTheNewDayAndOnlyForActiveClients() {
        var state = TownState.new(content: town, year: 2026)
        let due = deadlines.mvaFrist(termin: 1, year: 2026)
        state.calendar = TownCalendar(start: due)
        // Spending the last action of the deadline day starts the next day: the term is missed.
        var missed: [TownDeadline] = []
        for _ in 0..<TownRules.actionsPerDay { missed += state.spendAction(content: town, deadlines: deadlines, pool: []) }
        XCTAssertEqual(state.calendar.today, due.adding(days: 1))
        XCTAssertEqual(Set(missed.map(\.client)), [cafe], "only the active café; prospects have no deadlines")
        // The term, and the payroll of January to March that went by without delivery.
        let payroll = (1...3).flatMap { [DeadlineKind.amelding(month: MonthKey(year: 2026, month: $0)), .forskuddstrekk(month: MonthKey(year: 2026, month: $0))] }
        XCTAssertEqual(Set(missed.map(\.kind)), Set(payroll + [.mva(termin: 1, year: 2026), .aga(termin: 1, year: 2026)]))
        XCTAssertEqual(state.checkMissed(content: town, deadlines: deadlines), [], "a miss is counted once")
    }

    func testANewGameDoesNotMissLastYearsTerm() {
        // The sixth term of the year before falls due in February; the game did not run then.
        var state = TownState.new(content: town, year: 2026)
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 3, day: 15))
        // Only this year's payroll of January and February is behind; nothing from the year before.
        let missed = state.checkMissed(content: town, deadlines: deadlines)
        XCTAssertEqual(Set(missed.map(\.kind.id)), ["amelding-2026-01", "amelding-2026-02", "trekk-2026-01", "trekk-2026-02"])
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
        state.payrollFrom = due // the café's payroll before the term is not under test here
        for _ in 0..<(TownRules.actionsPerDay - 1) { _ = state.spendAction(content: town, deadlines: deadlines, pool: []) }
        XCTAssertEqual(state.calendar.today, due, "eleven actions keep the day")
        let before = state.clients[cafe]!.satisfaction

        let missed = state.deliver(client: cafe, kind: kind, content: town, deadlines: deadlines, pool: [])

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
        XCTAssertEqual(f.rows.map(\.text), ["KAFÉ LUKK JAN", "KAFÉ LEVER TREKK1"])
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
        _ = state.spendAction(content: town, deadlines: deadlines, pool: [])
    }

    func testAllThreeTrialsCanBeWonInPhase2a() throws {
        var state = TownState.new(content: town, year: 2026)
        state.contracts = 3
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
        while state.calendar.today < DayKey(year: 2026, month: 5, day: 2) { missed += state.sleep(content: town, deadlines: deadlines, pool: []) }
        XCTAssertEqual(missed.filter { $0.client == pixel }, [], "term 1 fell due on 10 April, before Pixel was won")
        XCTAssertEqual(state.clients[pixel]?.missed, [])
        XCTAssertEqual(state.clients[pixel]?.satisfaction, TownRules.startSatisfaction)

        // January and February closed: the counter offers no delivery for term 1.
        state.clients[pixel]?.closedMonths = [jan, feb]
        var f = flow(state)
        let counter = try XCTUnwrap(town.map("kontoret")?.folk.first { $0.rolle == .skranke })
        _ = f.talk(to: counter)
        XCTAssertFalse(f.rows.contains { $0.text.hasPrefix("PIXEL LEVER") }, "\(f.rows.map(\.text))")

        // Term 2 (March and April, due in June) is Pixel's: Fristnav lists it. March belongs to the
        // previous accountant, so with April closed the counter offers the delivery.
        state.calendar = TownCalendar(start: deadlines.mvaFrist(termin: 2, year: 2026).adding(days: -2))
        f = flow(state)
        _ = f.openFristnav()
        XCTAssertTrue(f.rows.contains { $0.id == "\(pixel):mva-2026-2" }, "\(f.rows.map(\.id))")
        state.clients[pixel]?.closedMonths = [MonthKey(year: 2026, month: 4)]
        f = flow(state)
        _ = f.talk(to: counter)
        XCTAssertTrue(f.rows.contains { $0.text == "PIXEL LEVER MVA2" }, "\(f.rows.map(\.text))")

        // Not delivered, it is missed like any other deadline.
        while state.calendar.today <= deadlines.mvaFrist(termin: 2, year: 2026) { missed += state.sleep(content: town, deadlines: deadlines, pool: []) }
        XCTAssertTrue(missed.contains { $0.client == pixel && $0.kind == .mva(termin: 2, year: 2026) })
    }

    /// Books every bilag of the client right, then closes and delivers everything the counter offers.
    func playPerfectly(_ id: String, state: inout TownState) throws {
        let client = try XCTUnwrap(town.client(id))
        while let month = Ledger.pileMonth(for: client, start: state.start, today: state.calendar.today, state: state.clients[id]!, pool: pool) {
            for puzzle in Ledger.pile(for: client, month: month, start: state.start, state: state.clients[id]!, pool: pool) {
                state.clients[id]?.book(BookedBilag(puzzleId: puzzle, month: month, day: state.calendar.today, correct: true), boxBefore: 0, client: id)
            }
        }
        let counter = try XCTUnwrap(town.map("kontoret")?.folk.first { $0.rolle == .skranke })
        for _ in 0..<50 {
            var f = flow(state)
            _ = f.talk(to: counter)
            guard f.phase != .dialog, let row = f.rows.firstIndex(where: { $0.id.hasSuffix(":\(id)") }) else { return }
            for _ in 0..<row { _ = f.key(.down) }
            let action = f.key(.a)
            if f.phase == .dialog { _ = readDialog(&f) }
            state = f.state
            guard case let .deliver(who, kind) = action else { continue }
            state.clients[who]?.deliver(kind)
        }
        XCTFail("the counter never ran out of tasks for \(id)")
    }

    /// Won partway through the first term: the months before belong to the previous accountant, so
    /// A-MELDING FEB, AGA 1 and MVA 1 can be delivered from what the player booked.
    func testAClientWonMidTermAndPlayedPerfectlyMissesNothing() throws {
        var state = TownState.new(content: town, year: 2026)
        state.clients[cafe]?.status = .archived
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 3, day: 2))
        try winTrial(motor, state: &state)
        XCTAssertEqual(state.clients[motor]?.booksFrom(start: state.start), MonthKey(year: 2026, month: 3))

        var missed: [TownDeadline] = []
        while state.calendar.today < DayKey(year: 2026, month: 12, day: 31) {
            try playPerfectly(motor, state: &state)
            missed += state.sleep(content: town, deadlines: deadlines, pool: pool)
        }
        XCTAssertEqual(missed.filter { $0.client == motor }.map(\.kind.id), [])
        XCTAssertEqual(state.clients[motor]?.missed, [])
        XCTAssertEqual(state.clients[motor]?.status, .active)
        let delivered = try XCTUnwrap(state.clients[motor]?.delivered)
        for kind in [DeadlineKind.mva(termin: 1, year: 2026), .aga(termin: 1, year: 2026), .amelding(month: feb)] {
            XCTAssertTrue(delivered.contains(kind.id), kind.id)
        }
    }

    func testAClientWonInAprilBooksAprilAndClosesItOnTheFirstOfMay() throws {
        var state = TownState.new(content: town, year: 2026)
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 4, day: 12))
        try winTrial(pixel, state: &state)
        let client = try XCTUnwrap(town.client(pixel))
        let apr = MonthKey(year: 2026, month: 4)
        var clientState = try XCTUnwrap(state.clients[pixel])
        XCTAssertEqual(Ledger.pileMonth(for: client, start: state.start, today: state.calendar.today, state: clientState, pool: pool), apr)
        let pile = Ledger.pile(for: client, month: apr, start: state.start, state: clientState, pool: pool)
        XCTAssertEqual(pile, Array(client.oppgaver.prefix(TownRules.bilagPerMonth)).filter(pool.contains))
        XCTAssertFalse(pile.isEmpty)

        for (i, id) in pile.enumerated() {
            clientState.book(BookedBilag(puzzleId: id, month: apr, day: state.calendar.today, correct: true), boxBefore: 1, client: pixel)
            XCTAssertEqual(clientState.booked.count, i + 1)
        }
        state.clients[pixel] = clientState
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 5, day: 1))

        // January to March are not offered: the first close at the counter is April.
        var f = flow(state)
        let counter = try XCTUnwrap(town.map("kontoret")?.folk.first { $0.rolle == .skranke })
        _ = f.talk(to: counter)
        XCTAssertTrue(f.rows.contains { $0.text.hasPrefix("PIXEL LUKK APR") }, "\(f.rows.map(\.text))")
        XCTAssertFalse(f.rows.contains { $0.text.hasPrefix("PIXEL LUKK JAN") }, "\(f.rows.map(\.text))")

        let row = try XCTUnwrap(f.rows.firstIndex { $0.text.hasPrefix("PIXEL LUKK APR") })
        for _ in 0..<row { _ = f.key(.down) }
        XCTAssertEqual(f.key(.a), .none)
        XCTAssertEqual(f.state.clients[pixel]?.closedMonths, [apr])

        _ = readDialog(&f)
        f = flow(f.state)
        _ = f.talk(to: counter)
        let months = ["JAN", "FEB", "MAR", "APR"]
        XCTAssertFalse(f.rows.contains { r in months.contains { r.text.hasPrefix("PIXEL LUKK \($0)") } }, "\(f.rows.map(\.text))")
    }

    func testFristnavRowsKeepTheClientName() throws {
        var state = TownState.new(content: town, year: 2026)
        for id in [pixel, motor] { state.clients[id]?.status = .active }
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 4, day: 7))
        var f = flow(state)
        _ = f.openFristnav()
        // The a-melding for March is due 7 April; the 34-column row keeps every name whole.
        XCTAssertEqual(f.rows.map(\.text), ["07.04 AMELD3 KAFÉ", "07.04 AMELD3 MOTOR", "10.04 MVA1 KAFÉ", "10.04 MVA1 PIXEL", "10.04 MVA1 MOTOR", "KART"])
        XCTAssertEqual(f.rows.first?.full, "07.04 A-MELDING MAR Kafé Lysthuset AS")
        XCTAssertTrue(f.rows.allSatisfy { $0.text.count <= TownFlow.rowColumns })
    }

    func testATrialDoesNotSpoilTheClientsPile() {
        // The trial shows the answer and explanation, so its puzzles must not come back as bilag.
        for client in town.klienter where !client.startklient {
            XCTAssertEqual(Set(client.provesak).intersection(client.oppgaver), [], client.id)
        }
    }

    func testAYearOfDeliveriesEndsWithSkattemelding() {
        var state = TownState.new(content: town, year: 2026)
        state.calendar = TownCalendar(start: DayKey(year: 2027, month: 1, day: 4))
        state.annualFrom = DayKey(year: 2026, month: 1, day: 1)
        state.clients[cafe]?.closedMonths = Set((1...12).map { MonthKey(year: 2026, month: $0) })
        // Everything else of 2026 is delivered, so only the annual deadlines are under test.
        let client = town.client(cafe)!
        for year in 2026...2027 {
            for d in DeadlinePlanner.deadlines(for: client, year: year, deadlines: deadlines) where !d.kind.isAnnual {
                state.clients[cafe]?.delivered.insert(d.kind.id)
            }
        }
        var f = flow(state)
        _ = f.openCounter()
        XCTAssertTrue(f.rows.contains { $0.text.hasSuffix("LEVER SKATT") }, f.rows.map(\.text).joined(separator: ", "))
        XCTAssertEqual(state.deliver(client: cafe, kind: .skattemelding(year: 2026), content: town, deadlines: deadlines, pool: []), [])
        state.calendar = TownCalendar(start: DayKey(year: 2027, month: 1, day: 5))
        XCTAssertEqual(state.deliver(client: cafe, kind: .aarsregnskap(year: 2026), content: town, deadlines: deadlines, pool: []), [])
        state.calendar = TownCalendar(start: DayKey(year: 2027, month: 8, day: 3))
        XCTAssertEqual(state.checkMissed(content: town, deadlines: deadlines).filter { $0.kind.isAnnual }, [])
        XCTAssertFalse(state.clients[cafe]!.missed.contains { $0.hasPrefix("skatt") || $0.hasPrefix("arsregnskap") })
    }

    // MARK: The year ends with the audit

    var offices: [FagkontorRef] { town.kart.flatMap(\.folk).compactMap(\.fagkontor) }
    var allBadges: Set<String> { Set(offices.map(TownTrials.badgeKey)) }
    var regions: [Region] { Regions.build(topics: Self.library.topics, pool: puzzles, progress: LearnerProgress()) }
    let nov = MonthKey(year: 2026, month: 11)
    let dec = MonthKey(year: 2026, month: 12)

    /// The desk at Avgiftskontoret, built here because the repo town has no such person yet.
    var desk: TownPerson {
        func ref(_ id: String, _ name: String, _ topics: [String]) -> FagkontorRef { FagkontorRef(id: id, navn: name, temaer: topics) }
        return TownPerson(id: "avgiftskontoret", rolle: .bokettersyn, x: 1, y: 1, klient: nil, fagkontor: nil, tekst: ["Velkommen til Avgiftskontoret."],
                          kontrollorer: [ref("arsoppgjor", "Kontrollør Aas", ["arsoppgjor", "resultat-balanse"]),
                                         ref("mva", "Kontrollør Berg", ["mva"]),
                                         ref("lonn", "Kontrollør Dahl", ["lonn"]),
                                         ref("periodisering", "Kontrollør Eik", ["periodisering", "perioder-frister"])],
                          sensor: ref("sensor", "Sensor Fjeld", Self.library.topics.map(\.id)))
    }

    func correctAttempt(for puzzle: Puzzle) -> PuzzleAttempt {
        switch puzzle.payload {
        case .classify(let c): .classify(Dictionary(uniqueKeysWithValues: c.elementer.enumerated().map { ($0.offset, $0.element.svar) }))
        case .spot(let s): .spot(Set(s.elementer.indices.filter { s.elementer[$0].feil }))
        case .case(let c): .case(c.svar)
        case .deadline(let d): .deadline(d.fasit)
        default: attempt(for: puzzle, right: true)
        }
    }

    func wrongAttempt(for puzzle: Puzzle) -> PuzzleAttempt {
        switch puzzle.payload {
        case .classify, .spot, .case, .deadline: .empty(for: puzzle.kind)
        default: attempt(for: puzzle, right: false)
        }
    }

    /// 28 December 2026: the café has every month of 2026 closed but November, which holds one
    /// wrong bilag. All badges are held and the sandbox case is cleared.
    func yearEndState() throws -> (state: TownState, error: OpenError) {
        var state = TownState.new(content: town, year: 2026)
        state.calendar = TownCalendar(start: DayKey(year: 2026, month: 12, day: 28))
        state.sandboxCleared = ["kafe-001"]
        // Won in October: the café has ten bilag, so only two months of piles exist per year.
        state.clients[cafe]?.status = .active
        state.clients[cafe]?.activeFrom = DayKey(year: 2026, month: 10, day: 1)
        state.clients[cafe]?.closedMonths = Set((1...10).map { MonthKey(year: 2026, month: $0) })
        let client = try XCTUnwrap(town.client(cafe))
        let wrong = try XCTUnwrap(Ledger.pile(for: client, month: nov, start: state.start, state: state.clients[cafe]!, pool: pool).first)
        state.clients[cafe]?.book(BookedBilag(puzzleId: wrong, month: nov, day: DayKey(year: 2026, month: 11, day: 10), correct: false), boxBefore: 1, client: cafe)
        let error = try XCTUnwrap(state.clients[cafe]?.openErrors.first)
        return (state, error)
    }

    func auditFlow(_ state: TownState) -> TownFlow {
        TownFlow(content: town, state: state, deadlines: deadlines, pool: pool, regions: regions, damage: [:], badges: allBadges, ruleCards: Self.library.rules)
    }

    func auditRun(_ state: TownState, year: Int, errors: [OpenError], progress: LearnerProgress) throws -> AuditRun {
        let panel = TownAudit.panel(desk, content: town, pool: puzzles)
        return AuditRun(year: year, errors: errors, panel: panel, puzzles: puzzles, content: town, progress: state.masked(progress),
                        cards: Self.library.rules, equipped: state.equippedCard, seed: 1)
    }

    /// Plays the run to its end; `rightFor` says whether the current encounter gets the answer key.
    /// Answers go to the scheduler at once, like the app does. Returns how many encounters were answered.
    @discardableResult
    func playAudit(_ run: inout AuditRun, progress: inout LearnerProgress, today: DayKey, rightFor: (OpenError?) -> Bool) -> Int {
        var answered = 0
        while run.phase == .encounter, let encounter = run.current {
            run.choose(encounter.moves.first)
            let attempt = rightFor(run.currentError) ? correctAttempt(for: encounter.puzzle) : wrongAttempt(for: encounter.puzzle)
            guard let (_, result) = run.answer(attempt, progress: progress, today: today) else {
                XCTFail("answer refused for \(encounter.puzzle.id)")
                break
            }
            Scheduler.record(result, on: today, progress: &progress)
            answered += 1
            run.proceed()
        }
        return answered
    }

    func testAYearEndsWithTheAudit() throws {
        // 1. The year-end state.
        var (state, error) = try yearEndState()
        let client = try XCTUnwrap(town.client(cafe))
        XCTAssertEqual(state.clients[cafe]?.closedMonths.count, 10)
        XCTAssertEqual(allBadges.count, 8)

        // 2. The sleep goes to 1 January. November's pile is still the oldest one; January's is new.
        // Everything but the annual deadlines is delivered, so no missed deadline archives the café on the way.
        for year in 2026...2027 {
            for d in DeadlinePlanner.deadlines(for: client, year: year, deadlines: deadlines) where !d.kind.isAnnual {
                state.clients[cafe]?.delivered.insert(d.kind.id)
            }
        }
        XCTAssertEqual(state.sleep(content: town, deadlines: deadlines, pool: pool), [])
        XCTAssertEqual(state.calendar.today, DayKey(year: 2027, month: 1, day: 1))
        // The client may have found the error on the way; it is the same error.
        let found = try XCTUnwrap(state.clients[cafe]?.openErrors.first)
        XCTAssertEqual(found.id, error.id)
        error = found
        let clientState = try XCTUnwrap(state.clients[cafe])
        XCTAssertEqual(Ledger.pileMonth(for: client, start: state.start, today: state.calendar.today, state: clientState, pool: pool), nov)
        XCTAssertEqual(Ledger.pile(for: client, month: MonthKey(year: 2027, month: 1), start: state.start, state: clientState, pool: pool),
                       Array(client.oppgaver.prefix(TownRules.bilagPerMonth)).filter(pool.contains))
        state.calendar = TownCalendar(start: DayKey(year: 2027, month: 1, day: 4))

        // 3. The desk offers the audit of 2026 with the one open error.
        var f = auditFlow(state)
        XCTAssertEqual(f.talk(to: desk), .none)
        _ = readDialog(&f)
        XCTAssertEqual(f.phase, .choice)
        XCTAssertEqual(f.key(.a), .startAudit(year: 2026))
        XCTAssertEqual(TownAudit.reviewed(state, year: 2026, pool: pool).count, 1)
        state.beginAudit()
        XCTAssertEqual(state.auditTriedOn, state.calendar.today)

        // 4. The error is corrected wrongly, all fifteen examiner puzzles are right: trust is 9000 and the audit is won.
        var progress = LearnerProgress()
        let reviewed = TownAudit.reviewed(state, year: 2026, pool: pool)
        var run = try auditRun(state, year: 2026, errors: reviewed, progress: progress)
        XCTAssertEqual(TownAudit.panel(desk, content: town, pool: puzzles).flatMap(\.puzzles).count, 15)
        let answered = playAudit(&run, progress: &progress, today: state.calendar.today) { $0 == nil }
        XCTAssertEqual(answered, 16)
        state.clients[cafe]?.correct(error, ok: false)
        XCTAssertEqual(run.hp, AuditRun.hp - TownRules.auditErrorCost)
        XCTAssertEqual(run.hp, 9_000)
        XCTAssertEqual(run.standing, [error])
        XCTAssertEqual(run.remarks, 0)
        XCTAssertTrue(run.won)

        // 5. The pass starts the new year; the wrongly corrected error still stands.
        state.passAudit(year: 2026)
        XCTAssertEqual(state.sandboxCleared, [])
        XCTAssertEqual(state.revidert, [2026])
        XCTAssertNil(state.auditYear)
        XCTAssertEqual(state.clients[cafe]?.openErrors.map(\.puzzleId), [error.puzzleId])
        XCTAssertEqual(state.clients[cafe]?.errors(in: nov, pool: pool).count, 1, "November cannot close with the error standing")
        XCTAssertEqual(state.maskedBox(error.puzzleId), error.boxBefore, "the error stays masked until its month closes")

        // 6. Correct the error at the counter, close November and December, deliver for 2026 in time.
        f = auditFlow(state)
        _ = f.openCounter()
        func select(_ prefix: String) throws -> TownAction {
            let row = try XCTUnwrap(f.rows.firstIndex { $0.text.hasPrefix(prefix) }, "\(prefix) in \(f.rows.map(\.text))")
            for _ in 0..<row { _ = f.key(.down) }
            return f.key(.a)
        }
        // November has bilag left to book first: the close is not offered before the pile is empty.
        XCTAssertFalse(f.rows.contains { $0.text.hasPrefix("KAFÉ LUKK NOV") })
        let pile = Ledger.pile(for: client, month: nov, start: state.start, state: state.clients[cafe]!, pool: pool)
        XCTAssertFalse(pile.isEmpty)
        for id in pile {
            state.clients[cafe]?.book(BookedBilag(puzzleId: id, month: nov, day: state.calendar.today, correct: true), boxBefore: 1, client: cafe)
        }
        f = auditFlow(state)
        _ = f.openCounter()
        XCTAssertEqual(try select("KAFÉ LUKK NOV"), .startCorrection(client: cafe, month: nov))
        state.clients[cafe]?.correct(error, ok: true)
        XCTAssertEqual(state.clients[cafe]?.openErrors, [])
        for month in [nov, dec] {
            f = auditFlow(state)
            _ = f.openCounter()
            XCTAssertEqual(try select("KAFÉ LUKK \(TownFlow.monthAbbreviations[month.month - 1])"), .none)
            _ = readDialog(&f)
            state = f.state
            XCTAssertTrue(state.clients[cafe]!.closedMonths.contains(month))
        }
        XCTAssertEqual(state.clients[cafe]?.closedMonths.count, 12)

        f = auditFlow(state)
        _ = f.openCounter()
        XCTAssertTrue(f.rows.contains { $0.text.hasSuffix("LEVER SKATT") }, f.rows.map(\.text).joined(separator: ", "))
        XCTAssertLessThan(state.calendar.today, deadlines.skattemeldingFrist(year: 2026))
        XCTAssertEqual(state.deliver(client: cafe, kind: .skattemelding(year: 2026), content: town, deadlines: deadlines, pool: pool), [])
        XCTAssertLessThan(state.calendar.today, deadlines.aarsregnskapFrist(year: 2026))
        XCTAssertEqual(state.deliver(client: cafe, kind: .aarsregnskap(year: 2026), content: town, deadlines: deadlines, pool: pool), [])
        state.calendar = TownCalendar(start: DayKey(year: 2027, month: 8, day: 3))
        XCTAssertEqual(state.checkMissed(content: town, deadlines: deadlines).filter { $0.kind.isAnnual && $0.kind.year == 2026 }, [])
    }

    func testALostAuditKeepsTheBadges() throws {
        // Same start, but ten open errors, so ten wrong corrections empty the meter.
        var (state, _) = try yearEndState()
        state.calendar = TownCalendar(start: DayKey(year: 2027, month: 1, day: 4))
        let wrongOnes = puzzles.filter { wrongAttempt(for: $0).verdict(for: $0).correct == false }.prefix(10)
        XCTAssertEqual(wrongOnes.count, 10)
        state.clients[cafe]?.openErrors = wrongOnes.map {
            OpenError(puzzleId: $0.id, client: cafe, month: nov, day: DayKey(year: 2026, month: 11, day: 10), boxBefore: 1)
        }
        let badges = allBadges
        var f = auditFlow(state)
        _ = f.talk(to: desk)
        _ = readDialog(&f)
        XCTAssertEqual(f.key(.a), .startAudit(year: 2026))
        state.beginAudit()

        var progress = LearnerProgress()
        let reviewed = TownAudit.reviewed(state, year: 2026, pool: pool)
        XCTAssertEqual(reviewed.count, 10)
        var run = try auditRun(state, year: 2026, errors: reviewed, progress: progress)
        let answered = playAudit(&run, progress: &progress, today: state.calendar.today) { _ in false }
        XCTAssertEqual(answered, 10)
        XCTAssertEqual(run.hp, 0)
        XCTAssertEqual(run.phase, .finished)
        XCTAssertFalse(run.won)
        XCTAssertEqual(run.fixed, [])

        state.failAudit(content: town)
        XCTAssertEqual(state.mapId, "kontoret")
        XCTAssertEqual(state.revidert, [])
        XCTAssertEqual(state.auditYear, 2026)
        XCTAssertEqual(state.sandboxCleared, ["kafe-001"])
        XCTAssertEqual(state.clients[cafe]?.openErrors.count, 10)
        XCTAssertEqual(allBadges, badges)
        XCTAssertTrue(TownAudit.ready(content: town, badges: badges, regions: regions))

        // The same day the desk says to wait; the day after it offers the audit again.
        f = auditFlow(state)
        _ = f.talk(to: desk)
        XCTAssertEqual(f.pages, [["Vi fortsetter i morgen."]])
        state.calendar = TownCalendar(start: DayKey(year: 2027, month: 1, day: 5))
        f = auditFlow(state)
        _ = f.talk(to: desk)
        _ = readDialog(&f)
        XCTAssertEqual(f.phase, .choice)
        XCTAssertEqual(f.key(.a), .startAudit(year: 2026))
    }
}
