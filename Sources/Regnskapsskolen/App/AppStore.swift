import Foundation
import Observation
import RegnskapKit

/// All app state, on the main actor. The work lives in the `AppStore+<Area>` extensions.
@MainActor
@Observable
final class AppStore {
    let settings = AppSettings()
    let progressStore = ProgressStore(url: ProgressStore.defaultURL)

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

    var remainingToday: Int { progress.days[todayKey.string]?.remaining ?? today.count }
    var streak: Int { progress.streak(today: todayKey) }
    var pool: [Puzzle] { library?.pool(includeDrafts: settings.showDrafts) ?? [] }

    func start() {
        loadContent()
        progress = progressStore.load()
        if let error = progressStore.lastError { contentNotice = error }
        rollDay()
        loadSandbox()
        Task { await checkClaude() }
        scheduleReminders()
    }

    func saveProgress() {
        do { try progressStore.save(progress) } catch { loadError = "Kunne ikke lagre fremdrift: \(error.localizedDescription)" }
    }
}
