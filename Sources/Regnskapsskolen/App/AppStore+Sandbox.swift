import Foundation
import RegnskapKit

extension AppStore {
    static var sandboxURL: URL { ContentLocator.applicationSupport.appendingPathComponent("sandkasse.json") }

    func loadSandbox() {
        if let data = try? Data(contentsOf: Self.sandboxURL), let journal = try? JSONDecoder().decode(Journal.self, from: data) { sandbox = journal }
        if !settings.sandboxCaseId.isEmpty { activeCase = sandboxCases.first { $0.id == settings.sandboxCaseId } }
        validateSandbox()
    }

    func saveSandbox() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(sandbox).write(to: Self.sandboxURL, options: .atomic)
        validateSandbox()
    }

    func validateSandbox() {
        guard let library else { sandboxProblems = []; return }
        sandboxProblems = JournalValidator.problems(sandbox, chart: library.chart, rates: library.rates)
    }

    var sandboxCases: [SandboxCase] {
        guard let contentRoot else { return [] }
        return SandboxCase.load(folder: contentRoot.appendingPathComponent("sandkasse")) + SandboxCase.load(folder: TutorFiles.fallback)
    }

    func startCase(_ sandboxCase: SandboxCase) {
        activeCase = sandboxCase
        settings.sandboxCaseId = sandboxCase.id
        sandbox = Journal()
        saveSandbox()
    }

    func clearSandbox() {
        sandbox = Journal()
        saveSandbox()
    }

    /// For the screenshots: the café case with its model journal half booked.
    func loadSandboxDemo() {
        guard let first = sandboxCases.first, let model = first.fasitJournal else { return }
        activeCase = first
        sandbox = Journal(entries: Array(model.entries.prefix(6)))
        validateSandbox()
    }

    /// Called when the app becomes active: a new day rolls the set, and content edited on disk is picked up.
    func reloadIfNewDayOrChanged() {
        library?.reloadIfChanged()
        if DayKey.today() != todayKey {
            rollDay()
            updateBadge?()
            scheduleReminders()  // the reminder names the new day's topics
        }
    }
}
