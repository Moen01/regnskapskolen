import Foundation

/// Where one puzzle stands in the Leitner boxes.
public struct PuzzleProgress: Codable, Hashable, Sendable {
    public var box: Int
    public var attempts: Int
    public var correct: Int
    public var lastSeen: DayKey?
    public var due: DayKey?

    public init(box: Int = 0, attempts: Int = 0, correct: Int = 0, lastSeen: DayKey? = nil, due: DayKey? = nil) {
        self.box = box; self.attempts = attempts; self.correct = correct; self.lastSeen = lastSeen; self.due = due
    }
}

/// One day's set and what was completed of it.
public struct DayRecord: Codable, Hashable, Sendable {
    public var day: DayKey
    public var set: [String]
    public var completed: [String]

    public init(day: DayKey, set: [String], completed: [String] = []) { self.day = day; self.set = set; self.completed = completed }

    public var done: Bool { !self.set.isEmpty && self.set.allSatisfy { completed.contains($0) } }
    public var remaining: Int { self.set.filter { !completed.contains($0) }.count }
}

public struct AttemptResult: Hashable, Sendable {
    public let puzzleId: String
    public let correctFirstTry: Bool
    public init(puzzleId: String, correctFirstTry: Bool) { self.puzzleId = puzzleId; self.correctFirstTry = correctFirstTry }
}

/// Everything the app remembers about the learner, saved as one JSON file.
public struct LearnerProgress: Codable, Hashable, Sendable {
    public var puzzles: [String: PuzzleProgress]
    /// Keyed by the day's "YYYY-MM-DD".
    public var days: [String: DayRecord]
    public var game: GameProgress

    enum CodingKeys: String, CodingKey { case puzzles, days, game }

    public init(puzzles: [String: PuzzleProgress] = [:], days: [String: DayRecord] = [:], game: GameProgress = GameProgress()) {
        self.puzzles = puzzles; self.days = days; self.game = game
    }

    /// A file written before the games has no `game`; it reads as empty rather than failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        puzzles = try c.decode([String: PuzzleProgress].self, forKey: .puzzles)
        days = try c.decode([String: DayRecord].self, forKey: .days)
        game = try c.decodeIfPresent(GameProgress.self, forKey: .game) ?? GameProgress()
    }

    /// Consecutive completed days ending today, or ending yesterday when today is not done yet.
    public func streak(today: DayKey) -> Int {
        var day = days[today.string]?.done == true ? today : today.adding(days: -1)
        var count = 0
        while days[day.string]?.done == true {
            count += 1
            day = day.adding(days: -1)
        }
        return count
    }

    /// The share of a topic's puzzles that sit in box 3 or higher.
    public func mastery(tema: String, pool: [Puzzle]) -> Double {
        let topic = pool.filter { $0.tema == tema }
        guard !topic.isEmpty else { return 0 }
        let strong = topic.filter { (puzzles[$0.id]?.box ?? 0) >= 3 }.count
        return Double(strong) / Double(topic.count)
    }

    /// 1 plus the number of topics mastered (≥ 60 %), capped at 5: the difficulty the scheduler aims for.
    public func level(pool: [Puzzle]) -> Int {
        let topics = Set(pool.map(\.tema))
        let mastered = topics.filter { mastery(tema: $0, pool: pool) >= 0.6 }.count
        return min(5, 1 + mastered)
    }

    public var daysCompleted: Int { days.values.filter(\.done).count }
    public var totalAttempts: Int { puzzles.values.reduce(0) { $0 + $1.attempts } }
    public var totalCorrect: Int { puzzles.values.reduce(0) { $0 + $1.correct } }
}
