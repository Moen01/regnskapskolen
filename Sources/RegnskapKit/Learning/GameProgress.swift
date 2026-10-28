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
    /// Paragrafjakten: damage dealt per region (tema), kept between sessions.
    public var regionDamage: [String: Int]
    /// The weekly challenge's score per ISO week ("2026-44").
    public var weekly: [String: Int]

    enum CodingKeys: String, CodingKey { case xp, badges, bestScores, counters, regionDamage, weekly }

    public init(xp: Int = 0, badges: [String: DayKey] = [:], bestScores: [String: Int] = [:], counters: [String: Int] = [:],
                regionDamage: [String: Int] = [:], weekly: [String: Int] = [:]) {
        self.xp = xp; self.badges = badges; self.bestScores = bestScores; self.counters = counters; self.regionDamage = regionDamage; self.weekly = weekly
    }

    /// Fields added later read as empty from an older file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xp = try c.decode(Int.self, forKey: .xp)
        badges = try c.decode([String: DayKey].self, forKey: .badges)
        bestScores = try c.decode([String: Int].self, forKey: .bestScores)
        counters = try c.decode([String: Int].self, forKey: .counters)
        regionDamage = try c.decodeIfPresent([String: Int].self, forKey: .regionDamage) ?? [:]
        weekly = try c.decodeIfPresent([String: Int].self, forKey: .weekly) ?? [:]
    }
}
