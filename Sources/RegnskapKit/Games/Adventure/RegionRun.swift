import Foundation

/// One creature in front of the learner: the puzzle, what it was before, and the moves on offer.
public struct Encounter: Hashable, Sendable {
    public let puzzle: Puzzle
    public let stageBefore: Stage
    /// Empty when no paragraph on the region's cards hits the puzzle: the move step is skipped.
    public let moves: [Move]
    public let isGymLeader: Bool
    /// Where the encounter happens: the dialog's intro and result depend on it.
    public var context: EncounterContext = .wild
}

/// Where an encounter happens. The town reuses the battle for bilag, corrections, trials and the fagkontor.
public enum EncounterContext: Hashable, Sendable {
    case wild
    case bilag(client: String)
    case correction(client: String, day: DayKey)
    case trial(client: String)
    case fagkontor(name: String)
    /// A customer case from a person in town; `name` is the client's short name for the intro.
    case kundesak(client: String, name: String)
    /// An open error from the audited year, shown again in the bokettersyn.
    case auditError(client: String, name: String, day: DayKey)
    /// A controller or the sensor of the bokettersyn; `first` is the examiner's first puzzle.
    case examiner(name: String, first: Bool)
}

public enum EncounterOutcome: Hashable, Sendable {
    case caught(stage: Stage, superEffective: Bool)
    case escaped(hpLost: Int)
    /// Right, but the creature was already met today: nothing moves, nothing is farmed.
    case repeated
    /// A bilag booked in town: the verdict is kept quiet until the month is closed.
    case booked
    /// An error from a closed month, answered again: this one tells the verdict.
    case corrected(ok: Bool)
    /// A customer case: the verdict is told, like a correction.
    case answered(ok: Bool)
    /// The bokettersyn: the verdict is told, and `hpLost` comes off the single trust meter.
    case audited(ok: Bool, hpLost: Int)
}

public struct RunSummary: Hashable, Sendable {
    public let tema: String
    public let caught: Int
    public let escaped: Int
    public let xp: Int
    public let gymBadge: Bool
    public let hpLeft: Int
}

/// A session in one region: encounters in Leitner order, HP in kroner, damage towards the gym leader.
/// Pure state: the app hands every `AttemptResult` to `Scheduler.record` and saves `damageToSave`.
public struct RegionRun: Hashable, Sendable {
    public static let hp = 10_000
    public static let hpLossPerLevel = 500
    public static let damagePerLevel = RegionRunRules.damagePerLevel
    public static let gymXP = 200
    public static let hpZeroPenalty = 0.25

    public enum Phase: Hashable, Sendable { case encounter, result(EncounterOutcome), finished }

    public let region: Region
    public private(set) var hp = RegionRun.hp
    public private(set) var damage: Int
    public private(set) var phase: Phase = .encounter
    public private(set) var current: Encounter?
    public private(set) var chosenMove: Move?
    /// The rule step is the attack: with moves on offer, the learner must pick one (or «Ingen regel») before answering.
    public private(set) var hasChosen = false
    public private(set) var caught = 0
    public private(set) var escaped = 0
    public private(set) var xp = 0
    public private(set) var gymBadgeEarned = false
    private let regionCards: [RuleCard]
    private let otherCards: [RuleCard]
    private let context: EncounterContext
    private var generator: SplitMix64
    private var seen: Set<String> = []

    public var gymReady: Bool { damage >= region.damageTarget && region.gymBadge == nil && !gymBadgeEarned }

    public init(region: Region, progress: LearnerProgress, today: DayKey, regionCards: [RuleCard], otherCards: [RuleCard], seed: UInt64,
                context: EncounterContext = .wild) {
        self.region = region
        self.context = context
        damage = progress.game.regionDamage[region.tema] ?? 0
        self.regionCards = regionCards
        self.otherCards = otherCards
        generator = SplitMix64(seed: seed)
    }

    /// Due reviews first, then wild creatures (easiest first), then the rest, then anything already
    /// answered today; the gym leader only when the meter is full. Nothing left ends the run.
    public mutating func nextEncounter(progress: LearnerProgress, today: DayKey) {
        chosenMove = nil
        hasChosen = false
        guard phase != .finished, hp > 0 else { finish(); return }
        if gymReady, let leader = region.gymLeader, !seen.contains(leader.id) {
            current = encounter(leader, progress: progress, isGymLeader: true)
            phase = .encounter
            return
        }
        // The leader is held back only while the gym fight is still ahead; afterwards it is an ordinary creature.
        let gymPending = region.gymBadge == nil && !gymBadgeEarned
        let candidates = region.puzzles.filter { !(gymPending && $0.id == region.gymLeader?.id) && !seen.contains($0.id) }
        func group(_ puzzle: Puzzle) -> (Int, Int) {
            let p = progress.puzzles[puzzle.id]
            if p?.lastSeen == today { return (3, 0) }
            guard let p, p.box >= 1 else { return (1, puzzle.vanskelighet) }
            if (p.due ?? today) <= today { return (0, 0) }
            return (2, 0)
        }
        let ordered = candidates.shuffled(using: &generator).enumerated().sorted {
            let a = group($0.element), b = group($1.element)
            return (a.0, a.1, $0.offset) < (b.0, b.1, $1.offset)
        }
        guard let next = ordered.first?.element else { current = nil; finish(); return }
        current = encounter(next, progress: progress, isGymLeader: false)
        phase = .encounter
    }

    private mutating func encounter(_ puzzle: Puzzle, progress: LearnerProgress, isGymLeader: Bool) -> Encounter {
        Self.encounter(puzzle, stageBefore: Stage.of(box: progress.puzzles[puzzle.id]?.box), isGymLeader: isGymLeader, context: context,
                       regionCards: regionCards, otherCards: otherCards, generator: &generator)
    }

    /// One encounter with its move options drawn from the generator. Shared with the town's `BilagRun`.
    static func encounter(_ puzzle: Puzzle, stageBefore: Stage, isGymLeader: Bool, context: EncounterContext,
                          regionCards: [RuleCard], otherCards: [RuleCard], generator: inout SplitMix64) -> Encounter {
        Encounter(puzzle: puzzle, stageBefore: stageBefore,
                  moves: Moves.options(for: puzzle, regionCards: regionCards, otherCards: otherCards, seed: generator.next()),
                  isGymLeader: isGymLeader, context: context)
    }

    /// The verdict on one attempt and the damage it deals: right deals `vanskelighet × damagePerLevel`,
    /// twice that when the chosen move hits; wrong deals none. Shared with the town's `BilagRun`.
    struct Strike: Hashable {
        let correct: Bool
        let hit: Bool
        let damage: Int
        var multiplier: Int { hit ? 2 : 1 }
    }

    static func strike(_ attempt: PuzzleAttempt, on puzzle: Puzzle, with move: Move?) -> Strike {
        let correct = attempt.verdict(for: puzzle).correct
        let hit = correct && (move.map { Moves.hits($0, puzzle) } ?? false)
        let damage = correct ? puzzle.vanskelighet * damagePerLevel * (hit ? 2 : 1) : 0
        return Strike(correct: correct, hit: hit, damage: damage)
    }

    public mutating func choose(_ move: Move?) {
        chosenMove = move
        hasChosen = true
    }

    /// Checks the attempt: right on this one try catches, anything else escapes. Returns what the
    /// scheduler must hear, or nil outside an encounter.
    public mutating func answer(_ attempt: PuzzleAttempt, progress: LearnerProgress, today: DayKey) -> (outcome: EncounterOutcome, result: AttemptResult)? {
        guard phase == .encounter, let encounter = current, encounter.moves.isEmpty || hasChosen else { return nil }
        let puzzle = encounter.puzzle
        let strike = Self.strike(attempt, on: puzzle, with: chosenMove)
        let first = Scheduler.isFirstAnswer(of: puzzle.id, on: today, progress: progress)
        let outcome: EncounterOutcome
        if strike.correct, !first {
            outcome = .repeated
        } else if strike.correct {
            damage += strike.damage
            xp += XP.forPuzzle(vanskelighet: puzzle.vanskelighet, correctFirstTry: true) * strike.multiplier
            caught += 1
            outcome = .caught(stage: Stage.of(box: (progress.puzzles[puzzle.id]?.box ?? 0) + 1), superEffective: strike.hit)
            if encounter.isGymLeader {
                gymBadgeEarned = true
                xp += Self.gymXP
            }
        } else {
            let loss = min(hp, puzzle.vanskelighet * Self.hpLossPerLevel)
            hp -= loss
            escaped += 1
            outcome = .escaped(hpLost: puzzle.vanskelighet * Self.hpLossPerLevel)
        }
        seen.insert(puzzle.id)
        phase = .result(outcome)
        return (outcome, AttemptResult(puzzleId: puzzle.id, correctFirstTry: strike.correct))
    }

    /// Leaves the result: back to the next encounter, or finished when the HP is gone.
    public mutating func proceed() {
        guard case .result = phase else { return }
        current = nil
        chosenMove = nil
        phase = hp == 0 ? .finished : .encounter
    }

    public mutating func finish() { phase = .finished }

    public var summary: RunSummary {
        RunSummary(tema: region.tema, caught: caught, escaped: escaped, xp: xp, gymBadge: gymBadgeEarned, hpLeft: hp)
    }

    /// Damage to keep for next time; a run that ended on empty HP loses a quarter of it.
    public var damageToSave: Int {
        hp == 0 ? Int(Double(damage) * (1 - Self.hpZeroPenalty)) : damage
    }
}
