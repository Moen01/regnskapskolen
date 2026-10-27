import Foundation

/// One answer in the lightning round: the verdict, the points it gave, and what the scheduler should hear.
public struct RoundEvent: Hashable, Sendable {
    public let verdict: Verdict
    public let points: Int
    public let result: AttemptResult
}

/// Ninety seconds of one-click puzzles. A pure state machine: the clock is the `now` handed in, the
/// order comes from a seed, so a round can be replayed in a test. A right answer moves straight on;
/// a wrong one pauses the clock while the explanation is read.
public struct LightningRound: Hashable, Sendable {
    public enum Phase: Hashable, Sendable { case question, feedback(since: TimeInterval), finished }

    public static let duration: TimeInterval = 90
    public static let feedbackMinimum: TimeInterval = 1.5
    public static let quickKinds: [PuzzleKind] = [.quiz, .mva, .sak]
    public static let minimumTopicSize = 8
    public static let pointsPerLevel = 100

    public let tema: String?
    public private(set) var queue: [Puzzle]
    public private(set) var phase: Phase
    public private(set) var score = 0
    public private(set) var correct = 0
    public private(set) var answered = 0
    public private(set) var combo = Combo()
    public private(set) var lastEvent: RoundEvent?
    private let startedAt: TimeInterval
    private var pausedFor: TimeInterval = 0
    private var pauseStart: TimeInterval?

    public var current: Puzzle? { queue.first }

    public static func eligible(pool: [Puzzle], tema: String?) -> [Puzzle] {
        pool.filter { quickKinds.contains($0.kind) && (tema == nil || $0.tema == tema) }
    }

    /// Topics with enough quick puzzles for a round, in the pool's order of first appearance.
    public static func topics(in pool: [Puzzle]) -> [String] {
        var seen: [String] = []
        for puzzle in eligible(pool: pool, tema: nil) where !seen.contains(puzzle.tema) { seen.append(puzzle.tema) }
        return seen.filter { eligible(pool: pool, tema: $0).count >= minimumTopicSize }
    }

    /// Due or weak puzzles first (unseen counts as box 0), then the rest, then the ones already
    /// answered today; a seeded shuffle inside each group.
    public static func order(pool: [Puzzle], tema: String?, progress: LearnerProgress, today: DayKey, seed: UInt64) -> [Puzzle] {
        var generator = SplitMix64(seed: seed)
        let shuffled = eligible(pool: pool, tema: tema).shuffled(using: &generator)
        func group(_ puzzle: Puzzle) -> Int {
            guard let p = progress.puzzles[puzzle.id] else { return 0 }
            if p.lastSeen == today { return 2 }
            if (p.due ?? today) <= today || p.box <= 1 { return 0 }
            return 1
        }
        return shuffled.enumerated().sorted { (group($0.element), $0.offset) < (group($1.element), $1.offset) }.map(\.element)
    }

    public init(pool: [Puzzle], tema: String?, progress: LearnerProgress, today: DayKey, seed: UInt64, startedAt: TimeInterval) {
        self.tema = tema
        self.startedAt = startedAt
        queue = Self.order(pool: pool, tema: tema, progress: progress, today: today, seed: seed)
        phase = queue.isEmpty ? .finished : .question
    }

    public func remaining(at now: TimeInterval) -> TimeInterval {
        let paused = pausedFor + (pauseStart.map { now - $0 } ?? 0)
        return max(0, Self.duration - (now - startedAt - paused))
    }

    /// Nil outside `.question` or once the time is up.
    public mutating func answer(_ attempt: PuzzleAttempt, at now: TimeInterval) -> RoundEvent? {
        tick(at: now)
        guard phase == .question, let puzzle = current else { return nil }
        let verdict = attempt.verdict(for: puzzle)
        let points = verdict.correct ? Int(Double(Self.pointsPerLevel * puzzle.vanskelighet) * combo.multiplier) : 0
        answered += 1
        if verdict.correct {
            correct += 1
            score += points
            combo.hit()
            advance()
        } else {
            combo.miss()
            phase = .feedback(since: now)
            pauseStart = now
        }
        let event = RoundEvent(verdict: verdict, points: points, result: AttemptResult(puzzleId: puzzle.id, correctFirstTry: verdict.correct))
        lastEvent = event
        return event
    }

    /// Leaves the feedback once it has been on screen long enough to be read.
    public mutating func next(at now: TimeInterval) {
        guard case .feedback(let since) = phase, now - since >= Self.feedbackMinimum else { return }
        pausedFor += now - (pauseStart ?? now)
        pauseStart = nil
        advance()
    }

    public mutating func tick(at now: TimeInterval) {
        if phase != .finished, remaining(at: now) <= 0 { finish() }
    }

    public mutating func finish() { phase = .finished }

    private mutating func advance() {
        queue.removeFirst()
        phase = queue.isEmpty ? .finished : .question
    }

    public var summary: RoundSummary {
        RoundSummary(game: .lynrunde, tema: tema, score: score, correct: correct, answered: answered, bestCombo: combo.best)
    }
}
