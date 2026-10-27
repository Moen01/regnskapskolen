import Foundation

/// Leitner boxes 0–4 and the composition of a day's set. Pure functions over `LearnerProgress`.
public enum Scheduler {
    public static let intervals = [0, 1, 3, 7, 21]
    public static let topBox = intervals.count - 1

    /// Records one attempt: right on the first check moves the puzzle up a box, anything else sends
    /// it back to box 0. The day's record is marked when the puzzle belongs to that day's set.
    public static func record(_ result: AttemptResult, on day: DayKey, progress: inout LearnerProgress) {
        var p = progress.puzzles[result.puzzleId] ?? PuzzleProgress()
        p.box = min(max(p.box, 0), topBox)  // a hand-edited file must not index outside the intervals
        p.attempts += 1
        if result.correctFirstTry {
            p.correct += 1
            p.box = min(topBox, p.box + 1)
        } else {
            p.box = 0
        }
        p.lastSeen = day
        p.due = day.adding(days: intervals[p.box])
        progress.puzzles[result.puzzleId] = p
        if var record = progress.days[day.string], record.set.contains(result.puzzleId), !record.completed.contains(result.puzzleId) {
            record.completed.append(result.puzzleId)
            progress.days[day.string] = record
        }
    }

    /// The day's set: the stored one when the day already has one, else a new one that is stored.
    public static func startDay(_ day: DayKey, count: Int, pool: [Puzzle], progress: inout LearnerProgress) -> [Puzzle] {
        let byId = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if var record = progress.days[day.string] {
            let kept = record.set.compactMap { byId[$0] }
            if !kept.isEmpty || pool.isEmpty {
                // A puzzle that left the pool (a draft hidden, a file deleted) leaves the set too, so the day can still be completed.
                if kept.count != record.set.count {
                    record.set = kept.map(\.id)
                    progress.days[day.string] = record
                }
                return kept
            }
        }
        let set = compose(day: day, count: count, pool: pool, progress: progress)
        progress.days[day.string] = DayRecord(day: day, set: set.map(\.id))
        return set
    }

    /// Due reviews first (oldest due first), then unseen puzzles from the weakest topic near the
    /// learner's level with at least one edge case, then seen-but-not-due puzzles from the lowest box.
    static func compose(day: DayKey, count: Int, pool: [Puzzle], progress: LearnerProgress) -> [Puzzle] {
        guard count > 0, !pool.isEmpty else { return [] }
        var generator = SplitMix64(seed: UInt64(truncatingIfNeeded: day.string.stableHash))
        var chosen: [Puzzle] = []
        var ids = Set<String>()
        func take(_ puzzle: Puzzle) { if ids.insert(puzzle.id).inserted { chosen.append(puzzle) } }

        let due = pool.filter { p in progress.puzzles[p.id].map { ($0.due ?? day) <= day } ?? false }
            .sorted { (progress.puzzles[$0.id]!.due ?? day, $0.id) < (progress.puzzles[$1.id]!.due ?? day, $1.id) }
        for p in due.prefix(count) { take(p) }

        if chosen.count < count {
            let level = progress.level(pool: pool)
            let topicOrder = Set(pool.map(\.tema)).sorted { a, b in
                let (ma, mb) = (progress.mastery(tema: a, pool: pool), progress.mastery(tema: b, pool: pool))
                return ma != mb ? ma < mb : a < b
            }
            var unseen = pool.filter { progress.puzzles[$0.id] == nil }.shuffled(using: &generator)
            unseen.sort { a, b in
                let (ta, tb) = (topicOrder.firstIndex(of: a.tema)!, topicOrder.firstIndex(of: b.tema)!)
                if ta != tb { return ta < tb }
                return abs(a.vanskelighet - level) < abs(b.vanskelighet - level)
            }
            // One unseen puzzle per topic first, so a weak topic does not fill the whole set.
            var seenTopics = Set<String>()
            for p in unseen where chosen.count < count && !seenTopics.contains(p.tema) { take(p); seenTopics.insert(p.tema) }
            for p in unseen where chosen.count < count { take(p) }
            if !chosen.contains(where: \.isEdgeCase), let edge = unseen.first(where: { $0.isEdgeCase && !ids.contains($0.id) }), chosen.count > 1 {
                // Swap the last new pick for an edge case.
                if let last = chosen.last, !due.contains(where: { $0.id == last.id }) { chosen.removeLast(); ids.remove(last.id) }
                take(edge)
            }
        }

        if chosen.count < count {
            let seen = pool.filter { progress.puzzles[$0.id] != nil && !ids.contains($0.id) }
                .sorted { a, b in
                    let (pa, pb) = (progress.puzzles[a.id]!, progress.puzzles[b.id]!)
                    return (pa.box, pa.lastSeen ?? day, a.id) < (pb.box, pb.lastSeen ?? day, b.id)
                }
            for p in seen where chosen.count < count { take(p) }
        }
        return Array(chosen.prefix(count))
    }
}

/// A small seeded generator, so the day's shuffle is the same on every launch.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// FNV-1a, stable across launches (Swift's `hashValue` is not).
    var stableHash: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in utf8 { hash ^= UInt64(byte); hash &*= 0x100_0000_01b3 }
        return hash
    }
}
