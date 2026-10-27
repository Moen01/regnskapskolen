import Foundation
import RegnskapKit

extension AppStore {
    /// Finds and loads the content folder, keeping the bundled copy as the fallback.
    func loadContent() {
        let bundled = Bundle.main.resourceURL
        let wanted = settings.contentFolder.isEmpty ? nil : settings.contentFolder
        guard let root = ContentLocator.find(settingsPath: wanted, bundleResources: bundled) else {
            loadError = "Fant ingen innholdsmappe (Innhold/ med temaer.json). Velg en i Innstillinger."
            library = nil
            return
        }
        if let wanted, root.path != URL(fileURLWithPath: wanted, isDirectory: true).standardizedFileURL.path {
            contentNotice = "Mappen \(wanted) finnes ikke lenger; bruker \(root.path)."
        } else {
            contentNotice = nil
        }
        do {
            let extra = [TutorFiles.fallback]
            library = try ContentLibrary(root: root, extraPuzzleRoots: extra)
            contentRoot = root
            loadError = library!.loadErrors.isEmpty ? nil : "\(library!.loadErrors.count) fil(er) kunne ikke leses: " + library!.loadErrors.prefix(3).map(\.description).joined(separator: "; ")
            tutor = Tutor(library: library!, model: settings.claudeModel)
        } catch {
            loadError = "Kunne ikke lese innholdet i \(root.path): \(error.localizedDescription)"
            library = nil
        }
    }

    func reloadContent() {
        loadContent()
        rollDay()
    }

    /// Today's set, computed once per day and stored in the progress.
    func rollDay() {
        todayKey = DayKey.today()
        today = Scheduler.startDay(todayKey, count: settings.dailyCount, pool: pool, progress: &progress)
        saveProgress()
    }

    /// Leitner first, then XP and badges: XP only for the day's first answer to the puzzle, like the box.
    func record(_ result: AttemptResult) {
        let first = Scheduler.isFirstAnswer(of: result.puzzleId, on: todayKey, progress: progress)
        let wasDone = progress.days[todayKey.string]?.done ?? false
        Scheduler.record(result, on: todayKey, progress: &progress)
        if let puzzle = library?.puzzle(id: result.puzzleId) {
            if first { progress.game.xp += XP.forPuzzle(vanskelighet: puzzle.vanskelighet, correctFirstTry: result.correctFirstTry) }
            newBadges += Badges.award(.puzzleAnswered(kind: puzzle.kind, correctFirstTry: result.correctFirstTry), on: todayKey, progress: &progress)
        }
        if !wasDone, progress.days[todayKey.string]?.done == true {
            newBadges += Badges.award(.dayCompleted(streak: streak), on: todayKey, progress: &progress)
        }
        saveProgress()
        updateBadge?()
    }

    func open(_ puzzle: Puzzle, fromToday: Bool) {
        openPuzzle = puzzle
        openFromToday = fromToday
    }

    /// The next unfinished puzzle in today's set after `current`, or nil when the day is done.
    func nextToday(after current: Puzzle?) -> Puzzle? {
        let done = Set(progress.days[todayKey.string]?.completed ?? [])
        let remaining = today.filter { !done.contains($0.id) }
        if let current, let index = remaining.firstIndex(where: { $0.id == current.id }) {
            return remaining.dropFirst(index + 1).first ?? remaining.first { $0.id != current.id }
        }
        return remaining.first
    }

    func state(of puzzle: Puzzle) -> PuzzleProgress? { progress.puzzles[puzzle.id] }
    func isCompletedToday(_ puzzle: Puzzle) -> Bool { progress.days[todayKey.string]?.completed.contains(puzzle.id) ?? false }
    func topic(_ id: String) -> Topic? { library?.topic(id) }
    func mastery(_ tema: String) -> Double { progress.mastery(tema: tema, pool: pool) }
}
