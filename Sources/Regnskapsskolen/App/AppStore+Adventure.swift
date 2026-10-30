import Foundation
import RegnskapKit

// Paragrafjakten: the map's regions, a run in one of them, and the encounter in front of the learner.
extension AppStore {
    /// The progress as the screens may show it: every bilag in a month the town has not closed
    /// (right or wrong) sits in the box it had before, and its `due` is cleared, so no count, stage,
    /// unlock or creature order tells whether it was right. Never show attempts, correct counts or
    /// `lastSeen` from this copy.
    var maskedProgress: LearnerProgress { progress.game.town?.masked(progress) ?? progress }
    /// Built from the masked progress: the map, the collection and the town's fagkontor all count from it.
    var regions: [Region] { Regions.build(topics: library?.topics ?? [], pool: pool, progress: maskedProgress) }
    var currentRegion: Region? { selectedRegion.flatMap { tema in regions.first { $0.tema == tema } } }
    /// Puzzles in the pool the learner has caught (box 1 or higher), counted from the masked boxes.
    var collectionTotal: Int {
        let shown = maskedProgress
        return pool.filter { (shown.puzzles[$0.id]?.box ?? 0) >= 1 }.count
    }

    func openRegion(_ tema: String) {
        selectedRegion = tema
    }

    func closeRegion() {
        if run != nil { endRun() }
        selectedRegion = nil
        lastRunSummary = nil
    }

    /// A fresh run in the selected region, with the first creature already waiting.
    func startRun() {
        guard let library, let region = currentRegion, !region.isEmpty else { return }
        lastRunSummary = nil
        newBadges = []
        // The masked boxes pick and show the creatures, like the town's runs: the real box of a
        // bilag in an open month would tell its verdict. `record` still writes the real progress.
        let shown = maskedProgress
        var fresh = RegionRun(region: region, progress: shown, today: todayKey,
                              regionCards: library.rules(tema: region.tema), otherCards: library.rules.filter { $0.tema != region.tema },
                              seed: UInt64(Date().timeIntervalSince1970))
        fresh.nextEncounter(progress: shown, today: todayKey)
        run = fresh
        encounterSession = fresh.current.map { PuzzleSession(puzzle: $0.puzzle) }
        if fresh.phase == .finished { endRun() }
    }

    func chooseMove(_ move: Move?) {
        run?.choose(move)
    }

    /// The learner pressed «Sjekk»: the run judges the attempt, the scheduler hears the result, XP and badges follow.
    func answerEncounter() {
        guard var current = run, let session = encounterSession, session.attempt.isAnswered,
              let (outcome, result) = current.answer(session.attempt, progress: maskedProgress, today: todayKey) else { return }
        run = current
        record(result, countXP: false)
        if case .caught = outcome {
            newBadges += Badges.award(.caught(total: collectionTotal), on: todayKey, progress: &progress)
            if let region = currentRegion, !region.isEmpty, region.mastered == region.puzzles.count {
                newBadges += Badges.award(.regionMastered, on: todayKey, progress: &progress)
            }
        }
        progress.game.regionDamage[current.region.tema] = current.damage
        saveProgress()
    }

    /// Leaves the result: the next creature, or the summary when the HP is gone or the region is done.
    func proceedEncounter() {
        guard var current = run else { return }
        current.proceed()
        current.nextEncounter(progress: maskedProgress, today: todayKey)
        run = current
        encounterSession = current.current.map { PuzzleSession(puzzle: $0.puzzle) }
        if current.phase == .finished { endRun() }
    }

    /// Closes the run: damage saved (cut when the HP ran out), gym badge, XP, summary.
    func endRun() {
        guard var current = run else { return }
        current.finish()
        let summary = current.summary
        progress.game.regionDamage[current.region.tema] = current.damageToSave
        progress.game.xp += summary.xp
        if summary.gymBadge {
            progress.game.badges[Regions.gymBadgePrefix + current.region.tema] = todayKey
            let held = progress.game.badges.keys.filter { $0.hasPrefix(Regions.gymBadgePrefix) }.count
            newBadges += Badges.award(.gymBadges(count: held), on: todayKey, progress: &progress)
        }
        run = nil
        encounterSession = nil
        lastRunSummary = summary
        saveProgress()
    }
}
