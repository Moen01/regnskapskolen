import Foundation
import RegnskapKit

/// What a town `RegionRun` is fought for: a client's trial or a fagkontor's badge.
enum TownRunGoal: Hashable {
    case trial(client: String)
    case fagkontor(FagkontorRef)
}

// Rubin: the town flow, its calendar, and the runs it starts at a client, the counter and a fagkontor.
// `progress.game.town` is the saved truth; the flow is rebuilt from it whenever a run ends.
extension AppStore {
    private var poolIds: Set<String> { Set(pool.map(\.id)) }
    private var townSeed: UInt64 { UInt64(Date().timeIntervalSince1970) }

    /// Shows the town; the first visit starts a game on 1 January of the year `satser.json` was checked.
    /// A flow showing a dialog is kept, so a message told after a run is not lost on appear.
    func openTown() {
        guard let library else { return }
        if progress.game.town == nil {
            progress.game.town = TownState.new(content: library.town, year: library.rates.verifisert.year)
            saveProgress()
        }
        if town == nil || town?.phase == .walking { refreshTown() }
    }

    /// Builds the flow again from the saved state: a run may have changed the state, badges, damage or pool.
    func refreshTown() {
        guard let library, let state = progress.game.town else {
            town = nil
            return
        }
        town = TownFlow(content: library.town, state: state, deadlines: library.deadlines, pool: poolIds, regions: regions,
                        damage: progress.game.regionDamage, badges: Set(progress.game.badges.keys), ruleCards: library.rules)
    }

    func townKey(_ key: GameKey) {
        guard var flow = town else { return }
        let action = flow.key(key)
        town = flow
        // Copying out is always safe; only writing *into* the flow must wait until it walks again.
        // A talk or a clean close changes the clients without an action: save it now. Steps are
        // saved at doors and LAGRE, not on every square.
        let clientsChanged = flow.state.clients != progress.game.town?.clients
        progress.game.town = flow.state
        if clientsChanged { saveProgress() }
        perform(action)
    }

    // MARK: Actions

    private func perform(_ action: TownAction) {
        switch action {
        case .none:
            return
        case .walked:
            townSteps += 1
            return
        case .enteredDoor, .save:
            saveProgress()
            return
        case .openTraining:
            saveProgress()
            showTraining = true
            return
        case .openCollection:
            showCollection = true
            return
        case .sleep:
            sleepInTown()
            return
        case .startTrial where activeClientCount >= TownRules.portfolioSize:
            showTown(["Porteføljen er full."])
            return
        case .deliver(let id, let kind):
            deliver(id, kind: kind)
            return
        case .startBilag, .startCorrection, .fixDiscovered, .startTrial, .startFagkontor:
            break
        }
        // The action happens first and costs its time when the player is back in town (`showTown`),
        // so a bilag booked with the day's last action still gets that day's date.
        townActionPending = true
        switch action {
        case .startBilag(let id): startBilag(id)
        case .startCorrection(let id, let month): startCorrection(id, month: month)
        case .fixDiscovered(let id): startCorrection(id, month: nil)
        case .startTrial(let id): startTrial(id)
        case .startFagkontor(let ref): startFagkontor(ref)
        default: break
        }
    }

    private var activeClientCount: Int {
        progress.game.town?.clients.values.filter { $0.status == .active }.count ?? 0
    }

    /// Spends the pending action's time; a deadline missed on the new day is told with the rest.
    private func spendPendingAction() {
        guard townActionPending, let library else { return }
        townActionPending = false
        let missed = progress.game.town?.spendAction(content: library.town, deadlines: library.deadlines, pool: poolIds) ?? []
        townNotice += missedLines(missed) + discoveryLines()
        saveProgress()
    }

    private func sleepInTown() {
        guard let library, var state = progress.game.town else { return }
        let missed = state.sleep(content: library.town, deadlines: library.deadlines, pool: poolIds)
        progress.game.town = state
        saveProgress()
        let day = state.calendar.today
        showTown([String(format: "Du sov til %02d.%02d.", day.day, day.month)] + missedLines(missed) + discoveryLines())
    }

    private func deliver(_ id: String, kind: DeadlineKind) {
        guard let library else { return }
        // Kit delivers before it spends the action, so the deadline day's last action still counts.
        let missed = progress.game.town?.deliver(client: id, kind: kind, content: library.town, deadlines: library.deadlines, pool: poolIds) ?? []
        townNotice += missedLines(missed) + discoveryLines()
        saveProgress()
        let what: String
        switch kind {
        case let .mva(termin, _): what = "Mva-meldingen for \(termin). termin"
        case .mvaAarlig: what = "Den årlige mva-meldingen"
        case .amelding: what = "A-meldingen"
        case .forskuddstrekk: what = "Forskuddstrekket"
        case .aga: what = "Arbeidsgiveravgiften"
        }
        showTown(["\(what) er levert for \(clientName(id))."])
    }

    /// What a client says when it finds an old error: its own line and the task title, never the answer.
    private func discoveryLines() -> [String] {
        guard let library, let found = progress.game.town?.takeDiscoveries() else { return [] }
        return found.flatMap { error in
            ["\(clientName(error.client)): \(library.puzzle(id: error.puzzleId)?.tittel ?? error.puzzleId)"]
                + (library.town.client(error.client)?.replikker.oppdagetFeil ?? [])
        }
    }

    /// The client's own line about a missed deadline, after its name and the deadline.
    private func missedLines(_ missed: [TownDeadline]) -> [String] {
        missed.flatMap { d in
            ["\(clientName(d.client)): \(d.label)"] + (library?.town.client(d.client)?.replikker.glippetFrist ?? [])
        }
    }

    private func clientName(_ id: String) -> String { library?.town.client(id)?.navn ?? id }

    /// Back to walking: the flow is rebuilt, and anything to tell (a notice from before a run, then `texts`) is shown.
    private func showTown(_ texts: [String] = []) {
        spendPendingAction()
        refreshTown()
        let all = townNotice + texts
        townNotice = []
        if !all.isEmpty { town?.tell(all) }
    }

    // MARK: Bilag and corrections

    private func startBilag(_ id: String) {
        guard let library, let state = progress.game.town, let client = library.town.client(id), let clientState = state.clients[id],
              let month = Ledger.pileMonth(for: client, start: state.start, today: state.calendar.today, state: clientState, pool: poolIds) else {
            showTown(library?.town.client(id)?.replikker.tomHaug ?? [])
            return
        }
        let ids = Ledger.pile(for: client, month: month, start: state.start, state: clientState, pool: poolIds)
        let cards = ruleCards(for: client)
        begin(BilagRun(client: client, puzzles: ids.compactMap { library.puzzle(id: $0) }, kind: .booking(month), errors: [],
                       bransjeCards: cards.own, otherCards: cards.other, seed: townSeed))
    }

    /// A correction over a month's errors, or, with no month, over the errors the client found itself.
    private func startCorrection(_ id: String, month: MonthKey?) {
        let visible = poolIds
        guard let library, let client = library.town.client(id), let clientState = progress.game.town?.clients[id] else {
            showTown()
            return
        }
        let errors = month.map { clientState.errors(in: $0, pool: visible) } ?? clientState.discoveredErrors(pool: visible)
        let cards = ruleCards(for: client)
        correctionMonth = month
        // Only visible errors: a hidden draft cannot be shown, and it does not block the close either.
        begin(BilagRun(client: client, puzzles: errors.compactMap { visible.contains($0.puzzleId) ? library.puzzle(id: $0.puzzleId) : nil },
                       kind: .correction, errors: errors, bransjeCards: cards.own, otherCards: cards.other, seed: townSeed))
    }

    /// The industry's own cards (and its topics' cards) give the moves; the rest are the decoys.
    private func ruleCards(for client: TownClient) -> (own: [RuleCard], other: [RuleCard]) {
        let all = library?.rules ?? []
        let bransje = library?.town.bransje(client.bransje)
        let own = all.filter { bransje?.regelkort.contains($0.id) == true || bransje?.temaer.contains($0.tema) == true }
        let ownIds = Set(own.map(\.id))
        return (own, all.filter { !ownIds.contains($0.id) })
    }

    private func begin(_ run: BilagRun) {
        bilagRun = run
        showBilagEncounter()
        if run.phase == .finished { finishBilag() }
    }

    private func showBilagEncounter() {
        let encounter = bilagRun?.current
        townSession = encounter.map { PuzzleSession(puzzle: $0.puzzle) }
        // Kit books every bilag as a fresh creature; the box before booking is the honest stage.
        // A correction's encounter already carries the box from before the wrong booking.
        guard let encounter, case .booking = bilagRun?.kind else {
            bilagStage = nil
            return
        }
        let id = encounter.puzzle.id
        bilagStage = Stage.of(box: progress.game.town?.maskedBox(id) ?? progress.puzzles[id]?.box)
    }

    /// The learner pressed «Sjekk» on a bilag: the scheduler hears it now, the ledger books it, the
    /// topic gets the damage. A booking keeps the verdict to itself; a correction tells it.
    func answerBilag() {
        guard var run = bilagRun, let session = townSession, session.attempt.isAnswered, let encounter = run.current else { return }
        let puzzle = encounter.puzzle
        let boxBefore = progress.puzzles[puzzle.id]?.box ?? 0
        guard let (_, result, damage) = run.answer(session.attempt, progress: progress, today: todayKey) else { return }
        let error = run.currentError
        bilagRun = run
        record(result, countXP: false)
        switch run.kind {
        case .booking(let month):
            let day = progress.game.town?.calendar.today ?? month.first
            progress.game.town?.clients[run.client]?.book(BookedBilag(puzzleId: puzzle.id, month: month, day: day, correct: result.correctFirstTry),
                                                         boxBefore: boxBefore, client: run.client)
        case .correction:
            if let error { progress.game.town?.clients[run.client]?.correct(error, ok: result.correctFirstTry) }
        }
        // R7: BilagRun gives damage only for the day's first answer to the puzzle.
        if damage > 0 { progress.game.regionDamage[puzzle.tema, default: 0] += damage }
        saveProgress()
    }

    func proceedBilag() {
        guard var run = bilagRun else { return }
        run.proceed()
        bilagRun = run
        showBilagEncounter()
        if run.phase == .finished { finishBilag() }
    }

    /// Ends the bilag run (also on FLYKT: what is booked stays booked, the rest stays in the pile).
    /// A correction run closes its month when no error is left.
    func finishBilag() {
        guard let run = bilagRun else { return }
        var lines: [String] = []
        if case .correction = run.kind, let month = correctionMonth {
            progress.game.town?.clients[run.client]?.closeIfClean(month, pool: poolIds)
            let name = TownFlow.monthNames[month.month - 1]
            let closed = progress.game.town?.clients[run.client]?.closedMonths.contains(month) == true
            lines = [closed ? "\(clientName(run.client)): \(name) er lukket." : "Det er fortsatt feil i \(name)."]
        }
        bilagRun = nil
        townSession = nil
        bilagStage = nil
        correctionMonth = nil
        saveProgress()
        showTown(lines)
    }

    // MARK: Trials and the fagkontor

    private func startTrial(_ id: String) {
        guard let library, let client = library.town.client(id) else {
            showTown()
            return
        }
        let region = TownTrials.trialRegion(for: client, pool: pool, progress: progress)
        guard region.puzzles.count >= TownRules.trialWinsNeeded else {
            showTown(["Prøvesaken er ikke klar ennå."])
            return
        }
        startTownRun(region, goal: .trial(client: id), context: .trial(client: id), cards: ruleCards(for: client).own)
    }

    private func startFagkontor(_ ref: FagkontorRef) {
        guard let library, let region = TownTrials.fagkontorRegion(ref, pool: pool, progress: progress) else {
            showTown(["\(ref.navn) har for få saker ennå."])
            return
        }
        startTownRun(region, goal: .fagkontor(ref), context: .fagkontor(name: ref.navn), cards: library.rules.filter { ref.temaer.contains($0.tema) })
    }

    private func startTownRun(_ region: Region, goal: TownRunGoal, context: EncounterContext, cards: [RuleCard]) {
        let ownIds = Set(cards.map(\.id))
        var run = RegionRun(region: region, progress: progress, today: todayKey, regionCards: cards,
                            otherCards: (library?.rules ?? []).filter { !ownIds.contains($0.id) }, seed: townSeed, context: context)
        run.nextEncounter(progress: progress, today: todayKey)
        townRun = run
        townRunGoal = goal
        trialScore = TrialScore()
        townSession = run.current.map { PuzzleSession(puzzle: $0.puzzle) }
        if run.phase == .finished { finishTownRun() }
    }

    /// Judges a trial or fagkontor answer. The scheduler hears it; the topic's damage does not.
    func answerTownRun() {
        guard var run = townRun, let session = townSession, session.attempt.isAnswered,
              let (outcome, result) = run.answer(session.attempt, progress: progress, today: todayKey) else { return }
        townRun = run
        record(result, countXP: false)
        trialScore.add(outcome)
        saveProgress()
    }

    func proceedTownRun() {
        guard var run = townRun else { return }
        run.proceed()
        run.nextEncounter(progress: progress, today: todayKey)
        townRun = run
        townSession = run.current.map { PuzzleSession(puzzle: $0.puzzle) }
        if run.phase == .finished { finishTownRun() }
    }

    /// Scores the run: a won trial makes the client active for one contract; a won fagkontor gives
    /// its badge and a new contract. Never `regionDamage`: this damage is not the topic's.
    func finishTownRun() {
        guard var run = townRun, let goal = townRunGoal else { return }
        run.finish()
        progress.game.xp += run.summary.xp
        let lines: [String]
        switch goal {
        case .trial(let id):
            if trialScore.won(needed: TownRules.trialWinsNeeded) {
                // The town's own day, not the learner's: deadlines before it are not the player's.
                if let day = progress.game.town?.calendar.today { progress.game.town?.winTrial(client: id, on: day) }
                lines = ["Prøvesaken er vunnet!", "\(clientName(id)) er nå din klient."]
            } else {
                lines = ["Prøvesaken gikk ikke denne gangen."]
            }
        case .fagkontor(let ref):
            if trialScore.won(needed: TownRules.fagkontorWinsNeeded) {
                progress.game.badges[TownTrials.badgeKey(ref)] = todayKey
                progress.game.town?.contracts += TownRules.contractsPerBadge
                lines = ["Du fikk merket fra \(ref.navn)!", "Du har en ny oppdragsavtale."]
            } else {
                lines = ["\(ref.navn): ikke bestått denne gangen."]
            }
        }
        townRun = nil
        townRunGoal = nil
        townSession = nil
        trialScore = TrialScore()
        saveProgress()
        showTown(lines)
    }
}
