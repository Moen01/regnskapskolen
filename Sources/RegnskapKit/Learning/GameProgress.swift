import Foundation

/// What the games add to the learner's record: XP, the badges earned (by day), best scores per game
/// and the running counters the "in a row" badges need. Saved inside `fremdrift.json`.
public struct GameProgress: Codable, Hashable, Sendable {
    public var xp: Int
    /// Badge id → the day it was earned.
    public var badges: [String: DayKey]
    /// "lynrunde", "lynrunde:<tema>", "debet-kredit".
    public var bestScores: [String: Int]
    /// "mva-paa-rad", "frist-riktig".
    public var counters: [String: Int]

    public init(xp: Int = 0, badges: [String: DayKey] = [:], bestScores: [String: Int] = [:], counters: [String: Int] = [:]) {
        self.xp = xp; self.badges = badges; self.bestScores = bestScores; self.counters = counters
    }
}
