import Foundation

/// The multiplier a run of right answers builds: 1,0 at the start, +0,25 per hit, capped, back to 1,0 on a miss.
public struct Combo: Hashable, Sendable {
    public static let step = 0.25
    public static let max = 3.0
    public private(set) var multiplier = 1.0
    public private(set) var best = 1.0

    public init() {}

    public mutating func hit() {
        multiplier = Swift.min(Self.max, multiplier + Self.step)
        best = Swift.max(best, multiplier)
    }

    public mutating func miss() { multiplier = 1.0 }
}

/// What a finished round reports: the numbers for the summary screen, the record and the XP.
public struct RoundSummary: Hashable, Sendable {
    public let game: GameKind
    public let tema: String?
    public let score: Int
    public let correct: Int
    public let answered: Int
    public let bestCombo: Double
    public var xp: Int { XP.forRound(score: score) }

    public init(game: GameKind, tema: String?, score: Int, correct: Int, answered: Int, bestCombo: Double) {
        self.game = game; self.tema = tema; self.score = score; self.correct = correct; self.answered = answered; self.bestCombo = bestCombo
    }
}
