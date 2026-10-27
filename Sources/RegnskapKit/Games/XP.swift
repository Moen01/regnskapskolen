import Foundation

/// A level title with its XP threshold and the next threshold, nil at the top.
public struct Level: Hashable, Sendable {
    public let navn: String
    public let terskel: Int
    public let neste: Int?
}

/// XP sources and levels. The numbers live here and nowhere else.
public enum XP {
    public static let perLevelCorrect = 10
    public static let perPuzzleOtherwise = 3
    public static let roundDivisor = 10

    public static let levels: [Level] = {
        let steps: [(String, Int)] = [("Lærling", 0), ("Regnskapsmedarbeider", 500), ("Regnskapsfører", 1500), ("Seniorregnskapsfører", 4000), ("Partner", 10000)]
        return steps.indices.map { i in Level(navn: steps[i].0, terskel: steps[i].1, neste: i + 1 < steps.count ? steps[i + 1].1 : nil) }
    }()

    public static func level(for xp: Int) -> Level {
        levels.last { $0.terskel <= xp } ?? levels[0]
    }

    /// 10 × vanskelighet when right on the first try, else 3.
    public static func forPuzzle(vanskelighet: Int, correctFirstTry: Bool) -> Int {
        correctFirstTry ? perLevelCorrect * vanskelighet : perPuzzleOtherwise
    }

    public static func forRound(score: Int) -> Int { score / roundDivisor }

    /// One-time XP for a learner whose history predates the games: as if every attempt had been scored.
    public static func seed(from progress: LearnerProgress) -> Int {
        let correct = progress.totalCorrect
        return correct * perLevelCorrect + (progress.totalAttempts - correct) * perPuzzleOtherwise
    }
}
