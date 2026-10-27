import Foundation
import RegnskapKit

extension AppStore {
    func checkClaude() async {
        claudeStatus = await ClaudeCLI().status()
    }

    /// Explains a wrong answer; the result goes to the caller's pane.
    func explain(puzzle: Puzzle, attempt: String, verdict: Verdict) async -> String? {
        await tutorCall { try await $0.explain(puzzle: puzzle, attempt: attempt, verdict: verdict) }
    }

    func ask(puzzle: Puzzle, question: String, session: String?) async -> (String, String)? {
        await tutorCall { let r = try await $0.ask(puzzle: puzzle, question: question, session: session); return (r.answer, r.session) }
    }

    /// A harder puzzle, saved as a draft and opened at once.
    func harder(than puzzle: Puzzle) async -> Puzzle? {
        guard let made = await tutorCall({ try await $0.harder(than: puzzle) }) else { return nil }
        var saved = made
        if let contentRoot, let url = try? TutorFiles.save(made, contentRoot: contentRoot) { saved.sourceURL = url }
        library?.addGenerated(saved)
        open(saved, fromToday: false)
        return saved
    }

    func makeCase(tema: String) async -> SandboxCase? {
        guard let made = await tutorCall({ try await $0.makeCase(tema: tema) }) else { return nil }
        if let contentRoot { _ = try? TutorFiles.save(made, contentRoot: contentRoot) }
        return made
    }

    private func tutorCall<T: Sendable>(_ work: @Sendable (Tutor) async throws -> T) async -> T? {
        guard let tutor else { tutorError = "Innholdet er ikke lastet."; return nil }
        guard !tutorBusy else { tutorError = "Claude jobber allerede med noe. Vent litt."; return nil }
        tutor.model = settings.claudeModel
        tutorBusy = true
        tutorError = nil
        defer { tutorBusy = false }
        do {
            return try await work(tutor)
        } catch {
            tutorError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case ClaudeError.notSignedIn = error { claudeStatus = .notSignedIn }
            if case ClaudeError.notInstalled = error { claudeStatus = .missing }
            return nil
        }
    }
}

extension ContentLibrary {
    /// A puzzle Claude just wrote, kept in memory until the next reload picks the file up.
    func addGenerated(_ puzzle: Puzzle) {
        if self.puzzle(id: puzzle.id) == nil { generatedInMemory.append(puzzle) }
    }
}
