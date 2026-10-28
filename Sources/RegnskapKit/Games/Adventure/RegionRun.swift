import Foundation

/// One creature in front of the learner: the puzzle, what it was before, and the moves on offer.
public struct Encounter: Hashable, Sendable {
    public let puzzle: Puzzle
    public let stageBefore: Stage
    /// Empty when no paragraph on the region's cards hits the puzzle: the move step is skipped.
    public let moves: [Move]
    public let isGymLeader: Bool
}

public enum EncounterOutcome: Hashable, Sendable {
    case caught(stage: Stage, superEffective: Bool)
    case escaped(hpLost: Int)
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
    public private(set) var caught = 0
    public private(set) var escaped = 0
    public private(set) var xp = 0
    public private(set) var gymBadgeEarned = false
    private let regionCards: [RuleCard]
    private let otherCards: [RuleCard]
    private var generator: SplitMix64
    private var seen: Set<String> = []

    public var gymReady: Bool { damage >= region.damageTarget && region.gymBadge == nil && !gymBadgeEarned }

    public init(region: Region, progress: LearnerProgress, today: DayKey, regionCards: [RuleCard], otherCards: [RuleCard], seed: UInt64) {
        self.region = region
        damage = progress.game.regionDamage[region.tema] ?? 0
        self.regionCards = regionCards
        self.otherCards = otherCards
        generator = SplitMix64(seed: seed)
    }

    /// Due reviews first, then wild creatures (easiest first), then the rest, then anything already
    /// answered today; the gym leader only when the meter is full. Nothing left ends the run.
    public mutating func nextEncounter(progress: LearnerProgress, today: DayKey) {
        chosenMove = nil
        guard phase != .finished, hp > 0 else { finish(); return }
        if gymReady, let leader = region.gymLeader, !seen.contains(leader.id) {
            current = encounter(leader, progress: progress, isGymLeader: true)
            phase = .encounter
            return
        }
        let candidates = region.puzzles.filter { $0.id != region.gymLeader?.id && !seen.contains($0.id) }
        func group(_ puzzle: Puzzle) -> (Int, Int) {
            guard let p = progress.puzzles[puzzle.id], p.box >= 1 else { return (1, puzzle.vanskelighet) }
            if p.lastSeen == today { return (3, 0) }
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
        Encounter(puzzle: puzzle, stageBefore: Stage.of(box: progress.puzzles[puzzle.id]?.box),
                  moves: Moves.options(for: puzzle, regionCards: regionCards, otherCards: otherCards, seed: generator.next()), isGymLeader: isGymLeader)
    }

    public mutating func choose(_ move: Move?) { chosenMove = move }

    /// Checks the attempt: right on this one try catches, anything else escapes. Returns what the
    /// scheduler must hear, or nil outside an encounter.
    public mutating func answer(_ attempt: PuzzleAttempt, progress: LearnerProgress, today: DayKey) -> (outcome: EncounterOutcome, result: AttemptResult)? {
        guard phase == .encounter, let encounter = current else { return nil }
        let puzzle = encounter.puzzle
        let verdict = attempt.verdict(for: puzzle)
        let first = Scheduler.isFirstAnswer(of: puzzle.id, on: today, progress: progress)
        let outcome: EncounterOutcome
        if verdict.correct {
            let hit = chosenMove.map { Moves.hits($0, puzzle) } ?? false
            let multiplier = hit ? 2 : 1
            damage += puzzle.vanskelighet * Self.damagePerLevel * multiplier
            if first { xp += XP.forPuzzle(vanskelighet: puzzle.vanskelighet, correctFirstTry: true) * multiplier }
            caught += 1
            let box = progress.puzzles[puzzle.id]?.box ?? 0
            outcome = .caught(stage: Stage.of(box: first ? box + 1 : box), superEffective: hit)
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
        return (outcome, AttemptResult(puzzleId: puzzle.id, correctFirstTry: verdict.correct))
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
