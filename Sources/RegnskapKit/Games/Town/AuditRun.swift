import Foundation

/// The bokettersyn as one battle: the open errors of the audited year, then every examiner's puzzles,
/// with a single trust meter (the battle's HP bar) that a wrong answer drains. A wrong correction costs
/// `TownRules.auditErrorCost`; a wrong answer to an examiner costs by difficulty, like a wild creature.
/// Pure state: the app hands every `AttemptResult` to `Scheduler.record` at once.
public struct AuditRun: Hashable, Sendable {
    public static let hp = RegionRun.hp

    public let year: Int
    public private(set) var hp = AuditRun.hp
    public private(set) var phase: RegionRun.Phase = .encounter
    public private(set) var current: Encounter?
    /// The error the current encounter is about; nil with an examiner.
    public private(set) var currentError: OpenError?
    public private(set) var currentExaminer: AuditExaminer?
    public private(set) var chosenMove: Move?
    public private(set) var hasChosen = false
    public private(set) var fixed: [OpenError] = []
    public private(set) var standing: [OpenError] = []
    /// Wrong answers to examiners.
    public private(set) var remarks = 0
    /// The whole queue was answered with trust left. A flight or an empty meter never sets it.
    public private(set) var completed = false
    private var queue: [Pending]

    private struct Pending: Hashable, Sendable {
        let encounter: Encounter
        let error: OpenError?
        let examiner: AuditExaminer?
    }

    /// The errors first, in the given order (an error whose puzzle is not in `puzzles`, a draft hidden
    /// again, is left out), then each examiner with the puzzles asked. `progress` is the masked one:
    /// the stage of an error is the box before the wrong booking. The learner's own cards in an
    /// encounter are those on the examiner's topics, or the error's topic, plus the equipped card.
    public init(year: Int, errors: [OpenError], panel: [AuditExaminer], puzzles: [Puzzle], content: TownContent,
                progress: LearnerProgress, cards: [RuleCard], equipped: String?, seed: UInt64) {
        self.year = year
        var generator = SplitMix64(seed: seed)
        func make(_ puzzle: Puzzle, stage: Stage, themes: [String], context: EncounterContext) -> Encounter {
            var own = cards.filter { themes.contains($0.tema) }
            if let id = equipped, !own.contains(where: { $0.id == id }), let card = cards.first(where: { $0.id == id }) { own.append(card) }
            let ownIds = Set(own.map(\.id))
            return RegionRun.encounter(puzzle, stageBefore: stage, isGymLeader: false, context: context, regionCards: own,
                                       otherCards: cards.filter { !ownIds.contains($0.id) }, generator: &generator)
        }
        let byId = Dictionary(puzzles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var queue: [Pending] = []
        for error in errors {
            guard let puzzle = byId[error.puzzleId] else { continue }
            let name = content.client(error.client).map(TownFlow.shortName) ?? error.client.uppercased()
            let encounter = make(puzzle, stage: Stage.of(box: error.boxBefore), themes: [puzzle.tema],
                                 context: .auditError(client: error.client, name: name, day: error.day))
            queue.append(Pending(encounter: encounter, error: error, examiner: nil))
        }
        for examiner in panel {
            for puzzle in examiner.puzzles {
                let encounter = make(puzzle, stage: Stage.of(box: progress.puzzles[puzzle.id]?.box), themes: examiner.ref.temaer,
                                     context: .examiner(name: examiner.ref.navn, first: puzzle.id == examiner.puzzles.first?.id))
                queue.append(Pending(encounter: encounter, error: nil, examiner: examiner))
            }
        }
        self.queue = queue
        advance()
    }

    public var won: Bool { completed && hp > 0 }

    public mutating func choose(_ move: Move?) {
        chosenMove = move
        hasChosen = true
    }

    /// Judges the attempt: with moves on offer, one must be chosen first. The answer goes to the
    /// scheduler even when the puzzle was seen today. Nil outside an encounter.
    public mutating func answer(_ attempt: PuzzleAttempt, progress: LearnerProgress, today: DayKey)
        -> (outcome: EncounterOutcome, result: AttemptResult)? {
        guard phase == .encounter, let encounter = current, encounter.moves.isEmpty || hasChosen else { return nil }
        let puzzle = encounter.puzzle
        let correct = RegionRun.strike(attempt, on: puzzle, with: chosenMove).correct
        let outcome: EncounterOutcome
        if let error = currentError {
            if correct {
                fixed.append(error)
                outcome = .audited(ok: true, hpLost: 0)
            } else {
                hp -= min(hp, TownRules.auditErrorCost)
                standing.append(error)
                outcome = .audited(ok: false, hpLost: TownRules.auditErrorCost)
            }
        } else if correct {
            outcome = .audited(ok: true, hpLost: 0)
        } else {
            let loss = puzzle.vanskelighet * RegionRun.hpLossPerLevel
            hp -= min(hp, loss)
            remarks += 1
            outcome = .audited(ok: false, hpLost: loss)
        }
        phase = .result(outcome)
        return (outcome, AttemptResult(puzzleId: puzzle.id, correctFirstTry: correct))
    }

    /// Leaves the result: finished (a loss) when the trust is gone, else the next meeting.
    public mutating func proceed() {
        guard case .result = phase else { return }
        guard hp > 0 else { clear(); phase = .finished; return }
        advance()
    }

    /// Flight: the audit ends without a pass.
    public mutating func finish() { phase = .finished }

    private mutating func advance() {
        chosenMove = nil
        hasChosen = false
        guard !queue.isEmpty else {
            clear()
            completed = true
            phase = .finished
            return
        }
        let next = queue.removeFirst()
        current = next.encounter
        currentError = next.error
        currentExaminer = next.examiner
        phase = .encounter
    }

    private mutating func clear() {
        current = nil
        currentError = nil
        currentExaminer = nil
        chosenMove = nil
    }
}
