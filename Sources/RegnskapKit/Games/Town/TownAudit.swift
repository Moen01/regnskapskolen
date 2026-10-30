import Foundation

/// One controller (or the sensor) of the bokettersyn and the puzzles that person asks.
public struct AuditExaminer: Hashable, Sendable {
    public let ref: FagkontorRef
    public let puzzles: [Puzzle]
    public let isSensor: Bool
}

/// The rules of the bokettersyn: when the office opens, the year it audits, the errors it reviews
/// and who asks what. The run itself lives in the app.
public enum TownAudit {
    /// The fagkontor in every map that are ready (`needed`) and how many of them the player has a badge for (`held`).
    public static func badgeCount(content: TownContent, badges: Set<String>, regions: [Region]) -> (held: Int, needed: Int) {
        let ready = content.kart.flatMap(\.folk).compactMap(\.fagkontor).filter { TownTrials.fagkontorReady($0, regions: regions) }
        return (ready.filter { badges.contains(TownTrials.badgeKey($0)) }.count, ready.count)
    }

    /// Like `TownDistricts.earned`: an office still under construction is not required.
    public static func ready(content: TownContent, badges: Set<String>, regions: [Region]) -> Bool {
        let count = badgeCount(content: content, badges: badges, regions: regions)
        return count.held == count.needed
    }

    /// The panel of a desk person; a person without examiners has an empty panel.
    public static func panel(_ person: TownPerson, content: TownContent, pool: [Puzzle]) -> [AuditExaminer] {
        guard let sensor = person.sensor else { return [] }
        return panel(examiners: person.kontrollorer ?? [], sensor: sensor, content: content, pool: pool)
    }

    /// The controllers in order, then the sensor. Taking the examiners as parameters keeps this free
    /// of the person's fields; the person-based overload comes with the audit people.
    public static func panel(examiners: [FagkontorRef], sensor: FagkontorRef, content: TownContent, pool: [Puzzle]) -> [AuditExaminer] {
        let size = TownTrials.fagkontorSize
        // The puzzles of every fagkontor are the player's training ground, so they are asked last.
        let excluded = content.kart.flatMap(\.folk).compactMap(\.fagkontor).flatMap {
            TownTrials.ranked($0.temaer, pool: pool).prefix(size)
        }
        let excludedIds = Set(excluded.map(\.id))
        var used = Set<String>()
        var result: [AuditExaminer] = []

        for ref in examiners {
            let ranked = TownTrials.ranked(ref.temaer, pool: pool).filter { !used.contains($0.id) }
            var picked = Array(ranked.filter { !excludedIds.contains($0.id) }.prefix(size))
            if picked.count < size {
                picked += ranked.filter { excludedIds.contains($0.id) }.prefix(size - picked.count)
            }
            used.formUnion(picked.map(\.id))
            if !picked.isEmpty { result.append(AuditExaminer(ref: ref, puzzles: picked, isSensor: false)) }
        }

        var picked: [Puzzle] = []
        var topics = Set<String>()
        let ranked = TownTrials.ranked(sensor.temaer, pool: pool).filter { !used.contains($0.id) }
        for fromExcluded in [false, true] {
            for puzzle in ranked where picked.count < size && !topics.contains(puzzle.tema) && excludedIds.contains(puzzle.id) == fromExcluded {
                picked.append(puzzle)
                topics.insert(puzzle.tema)
            }
        }
        if !picked.isEmpty { result.append(AuditExaminer(ref: sensor, puzzles: picked, isSensor: true)) }
        return result
    }

    /// The open errors the review shows: those of active clients from the audited year or earlier,
    /// for puzzles in the pool. Errors from the new year stay held back.
    public static func reviewed(_ state: TownState, year: Int, pool: Set<String>) -> [OpenError] {
        state.clients.values.filter { $0.status == .active }.flatMap(\.openErrors)
            .filter { $0.month.year <= year && pool.contains($0.puzzleId) }
            .sorted { ($0.day, $0.client, $0.puzzleId) < ($1.day, $1.client, $1.puzzleId) }
    }
}

extension TownState {
    /// The year the bokettersyn audits: the year that ended, when it is in the game and not yet audited.
    public var auditYear: Int? {
        let year = calendar.today.year - 1
        return year >= start.year && !revidert.contains(year) ? year : nil
    }

    /// A pass starts the new year: sandbox credits, energy and coffee are new. Everything else stays.
    public mutating func passAudit(year: Int) {
        revidert.insert(year)
        auditTriedOn = calendar.today
        sandboxCleared = []
        energy = TownRules.maxEnergy
        coffeeTakenOn = nil
    }

    /// A fail sends the player to the office. The clients are not touched.
    public mutating func failAudit(content: TownContent) {
        auditTriedOn = calendar.today
        (mapId, walker) = Self.officeSpot(content)
    }

    /// Set at the start, so quitting the app in the middle does not give a new attempt.
    public mutating func beginAudit() {
        auditTriedOn = calendar.today
    }
}

extension TownFlow {
    /// The dialog after the bokettersyn. A fail keeps the badges; the errors still open are told.
    public static func auditResultTexts(won: Bool, year: Int, today: DayKey, standing: Int, newBadge: Bool) -> [String] {
        if won {
            var texts = ["Bokettersynet er avsluttet uten merknader.", "Regnskapsåret \(today.year) er i gang."]
            if newBadge { texts.append("Du fikk merket «Revisorens beste venn»!") }
            return texts
        }
        var texts = ["Bokettersynet er avbrutt.", "Du er tilbake på kontoret. Merkene dine er i behold."]
        if standing > 0 { texts.append("\(standing) feil står fortsatt åpne.") }
        return texts
    }
}
