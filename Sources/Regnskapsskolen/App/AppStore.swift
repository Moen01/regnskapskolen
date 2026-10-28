import Foundation
import Observation
import RegnskapKit

/// All app state, on the main actor. The work lives in the `AppStore+<Area>` extensions.
@MainActor
@Observable
final class AppStore {
    let settings = AppSettings()
    /// Swapped for a throwaway file in screenshot mode, so a verification run never touches the learner's progress.
    @ObservationIgnored var progressStore = ProgressStore(url: ProgressStore.defaultURL)

    var library: ContentLibrary?
    var contentRoot: URL?
    var loadError: String?
    /// A one-line notice about the content, such as a fallback to the bundled copy.
    var contentNotice: String?
    var progress = LearnerProgress()
    var today: [Puzzle] = []
    var todayKey = DayKey.today()

    var claudeStatus: ClaudeStatus = .unknown
    var tutor: Tutor?
    var tutorBusy = false
    var tutorError: String?

    /// The puzzle open in the detail pane, and whether it came from the day's set.
    var openPuzzle: Puzzle?
    var openFromToday = false

    /// Set by the delegate: refreshes the status item's badge.
    @ObservationIgnored var updateBadge: (() -> Void)?

    var sandbox = Journal()
    var activeCase: SandboxCase?
    var reconciliation = Reconciliation()
    var sandboxPane: SandboxPane = .journal
    var sandboxProblems: [JournalProblem] = []

    /// The round in progress, if any; at most one of the two.
    var lightning: LightningRound?
    var drill: DebitCreditDrill?
    var lastSummary: RoundSummary?
    var lastWasRecord = false
    /// Badges earned since the hub last showed them.
    var newBadges: [Badge] = []
    /// The hub's topic choice for the lightning round; nil is all topics.
    var lynrundeTema: String?
    @ObservationIgnored var clock: Task<Void, Never>?

    /// Paragrafjakten: the region on screen, the run in it, and the encounter's input.
    var selectedRegion: String?
    var run: RegionRun?
    var encounterSession: PuzzleSession?
    var lastRunSummary: RunSummary?
    var showCollection = false
    /// The open lightning round is this week's challenge (no clock, result saved per week).
    var weeklyRound = false
    /// The last summary came from the weekly challenge, so it shows the shareable code.
    var lastWasWeekly = false

    /// A newer release on GitHub, once a check has found one.
    var availableUpdate: AppRelease?
    /// One line about the last check or install, for Settings.
    var updateState: String?
    var isUpdating = false
    var lastUpdateCheck = Date.distantPast
    @ObservationIgnored var updateLoop: Task<Void, Never>?

    var remainingToday: Int { progress.days[todayKey.string]?.remaining ?? today.count }
    var streak: Int { progress.streak(today: todayKey) }
    var pool: [Puzzle] { library?.pool(includeDrafts: settings.showDrafts) ?? [] }

    func start() {
        loadContent()
        progress = progressStore.load()
        if let error = progressStore.lastError { contentNotice = error }
        if !progressStore.fileHadGame {
            // A learner with history should not start as Lærling: score the past once.
            progress.game.xp = XP.seed(from: progress)
            saveProgress()
        }
        rollDay()
        loadSandbox()
        Task { await checkClaude() }
        scheduleReminders()
    }

    func saveProgress() {
        do { try progressStore.save(progress) } catch { loadError = "Kunne ikke lagre fremdrift: \(error.localizedDescription)" }
    }
}
