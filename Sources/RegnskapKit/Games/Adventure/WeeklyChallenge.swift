import Foundation

/// Ten approved quick puzzles that are the same for everyone in a given ISO week, so results can be
/// compared outside the app without a server.
public enum WeeklyChallenge {
    public static let count = 10

    public static func seed(for week: (year: Int, week: Int)) -> UInt64 { UInt64(week.year * 100 + week.week) }

    /// The pool is sorted by id before the seeded shuffle, so file order and hidden drafts change nothing.
    public static func puzzles(approved: [Puzzle], week: (year: Int, week: Int)) -> [Puzzle] {
        var generator = SplitMix64(seed: seed(for: week))
        let eligible = approved.filter { $0.status == .godkjent && LightningRound.quickKinds.contains($0.kind) }.sorted { $0.id < $1.id }
        return Array(eligible.shuffled(using: &generator).prefix(count))
    }

    /// "UKE 44 · 1 850 p · 9/10"
    public static func resultCode(week: Int, score: Int, correct: Int) -> String {
        "UKE \(week) · \(NorwegianFormat.kroner(Decimal(score), decimals: 0)) p · \(correct)/\(count)"
    }
}
