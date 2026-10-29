import Foundation

/// The score of a trial (prøvesak) or a fagkontor fight. A right answer wins even when the
/// puzzle was met earlier today (`.repeated`), so practising first never blocks a trial.
public struct TrialScore: Hashable, Sendable {
    public private(set) var wins = 0
    public private(set) var losses = 0

    public init() {}

    public mutating func add(_ outcome: EncounterOutcome) {
        switch outcome {
        case .caught, .repeated: wins += 1
        case .escaped: losses += 1
        // Town bilag outcomes never come from a trial run.
        case .booked, .corrected: break
        }
    }

    public func won(needed: Int) -> Bool { wins >= needed }
}

/// The regions behind a client's trial and a fagkontor, run by `RegionRun`. The app never saves
/// `regionDamage` for them: their damage is not the topic's.
public enum TownTrials {
    public static let fagkontorSize = 3
    static let trialPrefix = "provesak-"
    static let fagkontorPrefix = "fagkontor-"
    static let badgePrefix = "fag-"

    /// The client's `provesak` puzzles that are in the pool, in the client's order.
    public static func trialRegion(for client: TownClient, pool: [Puzzle], progress: LearnerProgress) -> Region {
        let byId = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return region(tema: trialPrefix + client.id, navn: client.navn, puzzles: client.provesak.compactMap { byId[$0] }, progress: progress)
    }

    /// The three hardest puzzles in the fagkontor's topics: edge cases first, then vanskelighet,
    /// then id, each highest first. Nil when the topics have fewer than three.
    public static func fagkontorRegion(_ ref: FagkontorRef, pool: [Puzzle], progress: LearnerProgress) -> Region? {
        let ranked = pool.filter { ref.temaer.contains($0.tema) }.sorted { a, b in
            (a.isEdgeCase ? 1 : 0, a.vanskelighet, a.id) > (b.isEdgeCase ? 1 : 0, b.vanskelighet, b.id)
        }
        guard ranked.count >= fagkontorSize else { return nil }
        return region(tema: fagkontorPrefix + ref.id, navn: ref.navn, puzzles: Array(ranked.prefix(fagkontorSize)), progress: progress)
    }

    /// Open when every topic's saved damage has reached its region's target, like a gym. A topic
    /// with no region stays closed.
    public static func fagkontorOpen(_ ref: FagkontorRef, regions: [Region], damage: [String: Int]) -> Bool {
        ref.temaer.allSatisfy { tema in
            guard let region = regions.first(where: { $0.tema == tema }) else { return false }
            return (damage[tema] ?? 0) >= region.damageTarget
        }
    }

    public static func badgeKey(_ ref: FagkontorRef) -> String { badgePrefix + ref.id }

    /// No gym leader, always open, no badge: the whole selection is fought in one run.
    private static func region(tema: String, navn: String, puzzles: [Puzzle], progress: LearnerProgress) -> Region {
        let boxes = puzzles.map { progress.puzzles[$0.id]?.box ?? 0 }
        return Region(tema: tema, navn: navn, rekkefolge: 0, theme: Regions.fallbackTheme, puzzles: puzzles, gymLeader: nil,
                      caught: boxes.filter { $0 >= 1 }.count, mastered: boxes.filter { $0 >= 3 }.count, unlocked: true, gymBadge: nil)
    }
}
