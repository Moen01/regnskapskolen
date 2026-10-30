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
    /// Before the flow is built: a player in a district without permit wakes at the office, badges
    /// won outside town give their permits, and a cleared sandbox case gives its credit.
    func openTown() {
        guard let library else { return }
        if progress.game.town == nil {
            progress.game.town = TownState.new(content: library.town, year: library.rates.verifisert.year)
            saveProgress()
        }
        // A kept flow writes its own copy of the state back on the next key, so the state is only
        // changed here when the flow is built again right after.
        guard town == nil || town?.phase == .walking else { return }
        let moved = progress.game.town?.relocateIfLocked(content: library.town) == true
        townNotice += grantFullmakter()
        if moved { saveProgress() }
        creditSandboxIfCleared()
        refreshTown()
        if !townNotice.isEmpty {
            town?.tell(townNotice)
            townNotice = []
        }
    }

    /// Gives the permits the badges earn and saves them; returns the lines that tell the new ones.
    private func grantFullmakter() -> [String] {
        guard let library else { return [] }
        // Read before the mutation: reading `progress` inside a call that mutates it is an access conflict.
        let badges = Set(progress.game.badges.keys), regions = regions
        let fresh = progress.game.town?.grantFullmakter(content: library.town, badges: badges, regions: regions) ?? []
        if !fresh.isEmpty { saveProgress() }
        return fresh.map { "Du har fullmakt til \($0.navn)!" }
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
        // A talk, a clean close, a cup from the machine or one drunk from the bag change the state
        // without an action: save it now. Steps are saved at doors and LAGRE, not on every square.
        // The bag and the archive change cards, finds and clients without an action too.
        let old = progress.game.town
        let new = flow.state
        let changed = new.clients != old?.clients || new.coffee != old?.coffee || new.energy != old?.energy
            || new.contracts != old?.contracts || new.regelkort != old?.regelkort || new.equippedCard != old?.equippedCard
            || new.found != old?.found || new.fullmakter != old?.fullmakter || new.sandboxCleared != old?.sandboxCleared
        progress.game.town = flow.state
        if changed { saveProgress() }
        perform(action)
    }

    // MARK: Actions

    /// A start that fails (an empty pile, no case to show, a full portfolio) costs nothing: only a
    /// run that begins, a delivery and a clean close spend an action.
    private func perform(_ action: TownAction) {
        switch action {
        case .none:
            break
        case .walked:
            townSteps += 1
        case .enteredDoor, .save:
            saveProgress()
        case .openTraining:
            saveProgress()
            showTraining = true
        case .openCollection:
            showCollection = true
        case .openSandbox(let caseId):
            openSandbox(caseId)
        case .sleep:
            sleepInTown()
        case .startTrial where activeClientCount >= TownRules.portfolioSize:
            showTown(["Porteføljen er full."])
        case .deliver(let id, let kind):
            deliver(id, kind: kind)
        case .closedMonth(let id, let month):
            // Kit closed the month and told it: the month's held-back booking damage falls due now,
            // and the close costs its action like a correction.
            addDamage(progress.game.town?.clients[id]?.bookingDamage(in: month, tema: tema(of:)) ?? [:])
            townActionPending = true
            showTown()
        case .startBilag(let id):
            startBilag(id)
        case .startCorrection(let id, let month):
            startCorrection(id, month: month)
        case .fixDiscovered(let id):
            startCorrection(id, month: nil)
        case .startTrial(let id):
            startTrial(id)
        case .startFagkontor(let ref):
            startFagkontor(ref)
        case .startCase(let id, let puzzle):
            startCustomerCase(id, puzzle: puzzle)
        }
    }

    /// A sandbox entrance in town. The journal is never cleared from here: a case with entries
    /// of another case waits until the player empties the sandbox.
    private func openSandbox(_ caseId: String) {
        if activeCase?.id == caseId {
            pendingSection = .sandbox
            return
        }
        guard sandbox.entries.isEmpty else {
            showTown(["Sandkassen har en annen sak.", "Tøm den først."])
            return
        }
        guard let found = sandboxCases.first(where: { $0.id == caseId }) else {
            showTown(["Saken finnes ikke ennå."])
            return
        }
        startCase(found)
        pendingSection = .sandbox
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

    /// The last energy went on an encounter: the player wakes at the office the next morning. The
    /// collapse takes the rest of the day, so the run's own action is not spent on top of it.
    private func collapseInTown() -> [String] {
        townCollapsed = false
        townActionPending = false
        guard let library, var state = progress.game.town else { return [] }
        let missed = state.collapse(content: library.town, deadlines: library.deadlines, pool: poolIds)
        progress.game.town = state
        saveProgress()
        return TownFlow.collapseTexts(wokeOn: state.calendar.today) + missedLines(missed) + discoveryLines()
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

    /// The errors the clients found on the new day, told with the task title, never the answer.
    /// Call it after every change of day, or the next one tells them late.
    private func discoveryLines() -> [String] {
        guard let library, let found = progress.game.town?.takeDiscoveries() else { return [] }
        return TownFlow.discoveryTexts(found, content: library.town) { library.puzzle(id: $0)?.tittel }
    }

    /// The client's own line about a missed deadline, after its name and the deadline.
    private func missedLines(_ missed: [TownDeadline]) -> [String] {
        missed.flatMap { d in
            ["\(clientName(d.client)): \(d.label)"] + (library?.town.client(d.client)?.replikker.glippetFrist ?? [])
        }
    }

    private func clientName(_ id: String) -> String { library?.town.client(id)?.navn ?? id }

    /// Back to walking: the flow is rebuilt, and anything to tell (a notice from before a run, then
    /// `texts`, then a collapse) is shown. Every way out of a run ends here, FLYKT too.
    private func showTown(_ texts: [String] = []) {
        let collapse = townCollapsed ? collapseInTown() : []
        spendPendingAction()
        refreshTown()
        let all = townNotice + texts + collapse
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

    /// A customer case: one puzzle a person in town asks about. Its verdict is told, like a correction's.
    private func startCustomerCase(_ id: String, puzzle: String) {
        guard let library, let client = library.town.client(id), poolIds.contains(puzzle), let found = library.puzzle(id: puzzle) else {
            showTown()
            return
        }
        let cards = ruleCards(for: client)
        begin(BilagRun(client: client, puzzles: [found], kind: .kundesak(puzzle: puzzle), errors: [],
                       bransjeCards: cards.own, otherCards: cards.other, seed: townSeed))
    }

    /// The industry's own cards (and its topics' cards) give the moves; the rest are the decoys.
    /// The equipped card counts as one of the industry's own for this battle.
    private func ruleCards(for client: TownClient) -> (own: [RuleCard], other: [RuleCard]) {
        let all = library?.rules ?? []
        let bransje = library?.town.bransje(client.bransje)
        let own = withEquippedCard(all.filter { bransje?.regelkort.contains($0.id) == true || bransje?.temaer.contains($0.tema) == true })
        let ownIds = Set(own.map(\.id))
        return (own, all.filter { !ownIds.contains($0.id) })
    }

    private func withEquippedCard(_ own: [RuleCard]) -> [RuleCard] {
        progress.game.town?.ownCards(own, all: library?.rules ?? []) ?? own
    }

    /// A run with an encounter costs its action when the player is back in town (`showTown`), so a
    /// bilag booked with the day's last action still gets that day's date. An empty run costs nothing,
    /// and keeps the equipped card too.
    private func begin(_ run: BilagRun) {
        if run.current != nil {
            townActionPending = true
            _ = progress.game.town?.takeEquippedCard()
        }
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
        bilagStage = Stage.of(box: maskedProgress.puzzles[id]?.box)
    }

    /// The learner pressed «Sjekk» on a bilag: the scheduler hears it now, the ledger books it. A
    /// booking keeps the verdict to itself, its damage too, until the month closes; a correction
    /// and a case tell the verdict, so their damage counts at once.
    func answerBilag() {
        guard var run = bilagRun, let session = townSession, session.attempt.isAnswered, let encounter = run.current else { return }
        let puzzle = encounter.puzzle
        let boxBefore = progress.puzzles[puzzle.id]?.box ?? 0
        guard let (_, result, damage) = run.answer(session.attempt, progress: progress, today: todayKey) else { return }
        let error = run.currentError
        bilagRun = run
        let isBooking = if case .booking = run.kind { true } else { false }
        record(result, countXP: false, awardBadges: !isBooking)
        switch run.kind {
        case .booking(let month):
            let day = progress.game.town?.calendar.today ?? month.first
            // R7: BilagRun gives damage only for the day's first answer to the puzzle.
            let bilag = BookedBilag(puzzleId: puzzle.id, month: month, day: day, correct: result.correctFirstTry, damage: damage)
            progress.game.town?.clients[run.client]?.book(bilag, boxBefore: boxBefore, client: run.client)
        case .correction:
            if let error { progress.game.town?.clients[run.client]?.correct(error, ok: result.correctFirstTry) }
            addDamage([puzzle.tema: damage])
        case .kundesak(let id):
            progress.game.town?.clients[run.client]?.answerCase(id, ok: result.correctFirstTry)
            addDamage([puzzle.tema: damage])
        }
        spendEncounterEnergy()
        saveProgress()
    }

    func addDamage(_ damage: [String: Int]) {
        for (tema, value) in damage where value > 0 { progress.game.regionDamage[tema, default: 0] += value }
    }

    /// The puzzle's topic, for the booking damage a closed month pays out.
    private func tema(of puzzleId: String) -> String? { library?.puzzle(id: puzzleId)?.tema }

    /// Every answered encounter costs the same energy, right or wrong, so the bar never tells the verdict.
    private func spendEncounterEnergy() {
        if progress.game.town?.spendEncounter() == true { townCollapsed = true }
    }

    func proceedBilag() {
        guard !townCollapsed else { return finishBilag() }
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
            addDamage(progress.game.town?.clients[run.client]?.closeIfClean(month, pool: poolIds, tema: tema(of:)) ?? [:])
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
        let region = TownTrials.trialRegion(for: client, pool: pool, progress: maskedProgress)
        guard region.puzzles.count >= TownRules.trialWinsNeeded else {
            showTown(["Prøvesaken er ikke klar ennå."])
            return
        }
        startTownRun(region, goal: .trial(client: id), context: .trial(client: id), cards: ruleCards(for: client).own)
    }

    private func startFagkontor(_ ref: FagkontorRef) {
        guard let library, let region = TownTrials.fagkontorRegion(ref, pool: pool, progress: maskedProgress) else {
            showTown(["\(ref.navn) har for få saker ennå."])
            return
        }
        startTownRun(region, goal: .fagkontor(ref), context: .fagkontor(name: ref.navn), cards: library.rules.filter { ref.temaer.contains($0.tema) })
    }

    private func startTownRun(_ region: Region, goal: TownRunGoal, context: EncounterContext, cards own: [RuleCard]) {
        let cards = withEquippedCard(own)
        let ownIds = Set(cards.map(\.id))
        // The masked progress picks and shows the creatures, so a stage never tells a booking's verdict.
        let shown = maskedProgress
        var run = RegionRun(region: region, progress: shown, today: todayKey, regionCards: cards,
                            otherCards: (library?.rules ?? []).filter { !ownIds.contains($0.id) }, seed: townSeed, context: context)
        run.nextEncounter(progress: shown, today: todayKey)
        if run.current != nil {
            townActionPending = true
            _ = progress.game.town?.takeEquippedCard()
        }
        townRun = run
        townRunGoal = goal
        trialScore = TrialScore()
        townSession = run.current.map { PuzzleSession(puzzle: $0.puzzle) }
        if run.phase == .finished { finishTownRun() }
    }

    /// Judges a trial or fagkontor answer. The scheduler hears it; the topic's damage does not.
    func answerTownRun() {
        guard var run = townRun, let session = townSession, session.attempt.isAnswered,
              let (outcome, result) = run.answer(session.attempt, progress: maskedProgress, today: todayKey) else { return }
        townRun = run
        record(result, countXP: false)
        trialScore.add(outcome)
        spendEncounterEnergy()
        saveProgress()
    }

    func proceedTownRun() {
        guard !townCollapsed else { return finishTownRun() }
        guard var run = townRun else { return }
        run.proceed()
        run.nextEncounter(progress: maskedProgress, today: todayKey)
        townRun = run
        townSession = run.current.map { PuzzleSession(puzzle: $0.puzzle) }
        if run.phase == .finished { finishTownRun() }
    }

    /// Scores the run: a won trial makes the client active for one contract; a won fagkontor gives
    /// its badge, a new contract, its topics' rule cards and the permits the badge opens.
    /// Never `regionDamage`: this damage is not the topic's.
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
                lines = winFagkontor(ref)
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

    /// The badge, its contract and its cards are given once: a badge already won gives nothing new.
    private func winFagkontor(_ ref: FagkontorRef) -> [String] {
        let key = TownTrials.badgeKey(ref)
        guard progress.game.badges[key] == nil else { return ["Du har allerede merket fra \(ref.navn)."] }
        progress.game.badges[key] = todayKey
        let cards = progress.game.town?.winFagkontor(ref, cards: library?.rules ?? []) ?? []
        return ["Du fikk merket fra \(ref.navn)!", "Du har en ny oppdragsavtale."]
            + cards.map { "Du fikk regelkortet «\($0.tittel)»." }
            + grantFullmakter()
    }
}
