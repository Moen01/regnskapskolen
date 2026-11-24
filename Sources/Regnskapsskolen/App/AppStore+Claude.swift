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
        let saved = saveGenerated(made)
        open(saved, fromToday: false)
        return saved
    }

    /// One new puzzle per kind the topic already uses, each saved as a draft.
    /// A kind that fails is reported and the rest still run; a missing CLI stops the batch.
    func generateNew(tema: String) async -> [Puzzle] {
        guard let tutor, let library else { tutorError = "Innholdet er ikke lastet."; return [] }
        guard !tutorBusy else { tutorError = "Claude jobber allerede med noe. Vent litt."; return [] }
        let kinds = library.kinds(tema: tema)
        let wanted = kinds.isEmpty ? PuzzleKind.allCases : kinds
        tutor.model = settings.claudeModel
        tutorBusy = true
        tutorError = nil
        defer { tutorBusy = false; tutorProgress = nil }
        var made: [Puzzle] = []
        var failed: [String] = []
        for (index, kind) in wanted.enumerated() {
            tutorProgress = "\(kind.navn) (\(index + 1) av \(wanted.count))"
            do {
                made.append(saveGenerated(try await tutor.newPuzzle(tema: tema, kind: kind)))
            } catch {
                failed.append("\(kind.navn): \(describe(error))")
                if case ClaudeError.notInstalled = error { break }
                if case ClaudeError.notSignedIn = error { break }
            }
        }
        if !failed.isEmpty { tutorError = failed.joined(separator: " · ") }
        return made
    }

    /// A fresh puzzle for the weakest topic, added to today's set so it counts toward the day.
    func generateForToday() async -> Puzzle? {
        guard let library, let topic = library.topics.min(by: { mastery($0.id) < mastery($1.id) }) else {
            tutorError = "Innholdet er ikke lastet."
            return nil
        }
        // The kind the topic has fewest puzzles of, so generation fills the thin spots first.
        let counts = Dictionary(grouping: library.puzzles(tema: topic.id).filter { !$0.generert }, by: \.kind)
        let kind = library.kinds(tema: topic.id).min { (counts[$0]?.count ?? 0) < (counts[$1]?.count ?? 0) } ?? .quiz
        guard let made = await tutorCall({ try await $0.newPuzzle(tema: topic.id, kind: kind) }) else { return nil }
        let saved = saveGenerated(made)
        Scheduler.extendDay(todayKey, with: saved, progress: &progress)
        today.append(saved)
        saveProgress()
        updateBadge?()
        return saved
    }

    func makeCase(tema: String) async -> SandboxCase? {
        guard let made = await tutorCall({ try await $0.makeCase(tema: tema) }) else { return nil }
        if let contentRoot { _ = try? TutorFiles.save(made, contentRoot: contentRoot) }
        return made
    }

    /// Writes the puzzle to the generert folder and keeps it in memory until the next reload.
    private func saveGenerated(_ puzzle: Puzzle) -> Puzzle {
        var saved = puzzle
        if let contentRoot, let url = try? TutorFiles.save(puzzle, contentRoot: contentRoot) { saved.sourceURL = url }
        library?.addGenerated(saved)
        return saved
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
            tutorError = describe(error)
            return nil
        }
    }

    /// One line for the error pane; a missing or signed-out CLI also updates the status banner.
    private func describe(_ error: Error) -> String {
        if case ClaudeError.notSignedIn = error { claudeStatus = .notSignedIn }
        if case ClaudeError.notInstalled = error { claudeStatus = .missing }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

extension ContentLibrary {
    /// A puzzle Claude just wrote, kept in memory until the next reload picks the file up.
    func addGenerated(_ puzzle: Puzzle) {
        if self.puzzle(id: puzzle.id) == nil { generatedInMemory.append(puzzle) }
    }
}
