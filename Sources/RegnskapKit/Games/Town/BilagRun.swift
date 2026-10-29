import Foundation

public enum BilagRunKind: Hashable, Sendable {
    case booking(MonthKey)
    case correction
}

/// A session at a client's desk: the bilag of the pile in order, or the errors that came back when
/// the month was closed. The battle is the same as in `RegionRun` (moves, verdict, damage), but a
/// booking never says whether it was right; a correction does. No HP: a bilag cannot flee.
/// Pure state: the app hands every `AttemptResult` to `Scheduler.record` and adds `damage` to the topic.
public struct BilagRun: Hashable, Sendable {
    public let client: String
    public let kind: BilagRunKind
    public private(set) var phase: RegionRun.Phase
    public private(set) var current: Encounter?
    /// The error the current correction encounter is about; nil while booking.
    public private(set) var currentError: OpenError?
    public private(set) var chosenMove: Move?
    public private(set) var hasChosen = false
    private var queue: [Pending]

    private struct Pending: Hashable, Sendable {
        let encounter: Encounter
        let error: OpenError?
    }

    /// In `booking` the encounters are `puzzles` in order; in `correction` they are the errors'
    /// puzzles, looked up in `puzzles`, in the order of `errors`. An error whose puzzle is not
    /// given (a draft hidden again) is left out.
    public init(client: TownClient, puzzles: [Puzzle], kind: BilagRunKind, errors: [OpenError],
                bransjeCards: [RuleCard], otherCards: [RuleCard], seed: UInt64) {
        self.client = client.id
        self.kind = kind
        var generator = SplitMix64(seed: seed)
        func make(_ puzzle: Puzzle, stage: Stage, context: EncounterContext) -> Encounter {
            RegionRun.encounter(puzzle, stageBefore: stage, isGymLeader: false, context: context,
                                regionCards: bransjeCards, otherCards: otherCards, generator: &generator)
        }
        switch kind {
        case .booking:
            // The pile is booked before any progress is known, so every bilag shows as a fresh creature.
            queue = puzzles.map { Pending(encounter: make($0, stage: .vill, context: .bilag(client: client.id)), error: nil) }
        case .correction:
            let byId = Dictionary(puzzles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            queue = errors.compactMap { error in
                guard let puzzle = byId[error.puzzleId] else { return nil }
                // The box before the wrong booking: the collection masks the error the same way.
                let encounter = make(puzzle, stage: Stage.of(box: error.boxBefore), context: .correction(client: client.id, day: error.day))
                return Pending(encounter: encounter, error: error)
            }
        }
        phase = .encounter
        advance()
    }

    public mutating func choose(_ move: Move?) {
        chosenMove = move
        hasChosen = true
    }

    /// Judges the attempt like `RegionRun`: with moves on offer, one must be chosen first. A
    /// booking always says `.booked`; the verdict is only in `result`. Damage counts once a day,
    /// like a catch. Nil outside an encounter.
    public mutating func answer(_ attempt: PuzzleAttempt, progress: LearnerProgress, today: DayKey)
        -> (outcome: EncounterOutcome, result: AttemptResult, damage: Int)? {
        guard phase == .encounter, let encounter = current, encounter.moves.isEmpty || hasChosen else { return nil }
        let puzzle = encounter.puzzle
        let strike = RegionRun.strike(attempt, on: puzzle, with: chosenMove)
        let first = Scheduler.isFirstAnswer(of: puzzle.id, on: today, progress: progress)
        let outcome: EncounterOutcome
        switch kind {
        case .booking: outcome = .booked
        case .correction: outcome = .corrected(ok: strike.correct)
        }
        phase = .result(outcome)
        return (outcome, AttemptResult(puzzleId: puzzle.id, correctFirstTry: strike.correct), first ? strike.damage : 0)
    }

    /// Leaves the result: the next bilag, or finished when the pile is empty.
    public mutating func proceed() {
        guard case .result = phase else { return }
        advance()
    }

    private mutating func advance() {
        chosenMove = nil
        hasChosen = false
        guard !queue.isEmpty else {
            current = nil
            currentError = nil
            phase = .finished
            return
        }
        let next = queue.removeFirst()
        current = next.encounter
        currentError = next.error
        phase = .encounter
    }
}
