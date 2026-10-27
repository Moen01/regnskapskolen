import Foundation
import RegnskapKit

enum SandboxPane: String, CaseIterable { case journal = "Journal", bank = "Bank" }

extension AppStore {
    static var sandboxURL: URL { ContentLocator.applicationSupport.appendingPathComponent("sandkasse.json") }
    static var reconciliationURL: URL { ContentLocator.applicationSupport.appendingPathComponent("avstemming.json") }

    var bankStatement: BankStatement? { activeCase?.kontoutskrift }

    var bankCheck: BankCheck? {
        guard let bankStatement else { return nil }
        return BankCheck(statement: bankStatement, journal: sandbox, reconciliation: reconciliation)
    }

    /// Drops matches that no longer hold after a journal edit; without a statement there is nothing to match.
    func pruneReconciliation() {
        guard let bankStatement else {
            if !reconciliation.matches.isEmpty { reconciliation = Reconciliation() }
            return
        }
        var pruned = reconciliation
        pruned.prune(statement: bankStatement, journal: sandbox)
        if pruned != reconciliation { reconciliation = pruned }
    }

    @discardableResult
    func matchBank(lineIds: [String], entryIds: [UUID]) -> MatchError? {
        guard let bankStatement else { return .emptySide }
        let error = reconciliation.match(bankLineIds: lineIds, entryIds: entryIds, statement: bankStatement, journal: sandbox)
        saveSandbox()
        return error
    }

    func unmatchBank(_ id: UUID) {
        reconciliation.remove(id: id)
        saveSandbox()
    }

    /// Starts a voucher from a statement line and matches it at once; the user fills in the counter line afterwards.
    func bookFromBankLine(_ line: BankLine) {
        guard let bankStatement else { return }
        let entry = JournalEntry(bankLine: line, konto: bankStatement.konto)
        sandbox.entries.append(entry)
        // The counter line is still empty, so the sums can differ only if the bank movement does not equal the line.
        matchBank(lineIds: [line.id], entryIds: [entry.id])
    }

    func loadSandbox() {
        if let data = try? Data(contentsOf: Self.sandboxURL), let journal = try? JSONDecoder().decode(Journal.self, from: data) { sandbox = journal }
        if let data = try? Data(contentsOf: Self.reconciliationURL), let saved = try? JSONDecoder().decode(Reconciliation.self, from: data) { reconciliation = saved }
        if !settings.sandboxCaseId.isEmpty { activeCase = sandboxCases.first { $0.id == settings.sandboxCaseId } }
        pruneReconciliation()
        validateSandbox()
    }

    func saveSandbox() {
        pruneReconciliation()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(sandbox).write(to: Self.sandboxURL, options: .atomic)
        try? encoder.encode(reconciliation).write(to: Self.reconciliationURL, options: .atomic)
        validateSandbox()
        awardSandboxBadges()
    }

    /// A case whose balance matches, or whose bank is reconciled, earns its badge once.
    func awardSandboxBadges() {
        guard let library, let activeCase, !sandbox.entries.isEmpty else { return }
        var earned: [Badge] = []
        if activeCase.compare(journal: sandbox, chart: library.chart).isEmpty {
            earned += Badges.award(.caseMatched, on: todayKey, progress: &progress)
        }
        if bankCheck?.done == true {
            earned += Badges.award(.bankReconciled, on: todayKey, progress: &progress)
        }
        if !earned.isEmpty { newBadges += earned; saveProgress() }
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
        reconciliation = Reconciliation()
        sandboxPane = .journal
        saveSandbox()
    }

    func clearSandbox() {
        sandbox = Journal()
        reconciliation = Reconciliation()
        sandboxPane = .journal
        saveSandbox()
    }

    /// For the screenshots: the bank case with the first eight vouchers booked and all but the last statement group matched.
    func loadSandboxDemo() {
        guard let demo = sandboxCases.first(where: { $0.id == "bank-001" }), let model = demo.fasitJournal else { return }
        activeCase = demo
        sandbox = Journal(entries: Array(model.entries.prefix(8)))
        reconciliation = Reconciliation()
        if let statement = demo.kontoutskrift {
            let groups = Dictionary(grouping: statement.linjer, by: \.bilag).values
                .filter { $0[0].bilag.allSatisfy { $0 <= 8 } }
                .sorted { $0[0].id < $1[0].id }
            for group in groups.dropLast() {
                let entryIds = group[0].bilag.map { sandbox.entries[$0 - 1].id }
                reconciliation.match(bankLineIds: group.map(\.id), entryIds: entryIds, statement: statement, journal: sandbox)
            }
        }
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
