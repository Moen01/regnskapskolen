import Foundation

/// Claude as tutor and author. Every call sends the puzzle, the attempt, the topic's rule cards and
/// the rates; nothing else leaves the Mac.
public final class Tutor: @unchecked Sendable {
    public let library: ContentLibrary
    public let runner: ClaudeRunner
    private let lock = NSLock()
    private var storedModel: String
    /// Set from Settings on the main actor, read inside the tutor's own tasks.
    public var model: String {
        get { lock.withLock { storedModel } }
        set { lock.withLock { storedModel = newValue } }
    }

    public init(library: ContentLibrary, runner: ClaudeRunner = ClaudeRunner(), model: String = "sonnet") {
        self.library = library; self.runner = runner; storedModel = model
    }

    public static func prompt(named name: String, root: URL) -> String? {
        try? String(contentsOf: root.appendingPathComponent("prompter/\(name).md"), encoding: .utf8)
    }

    func system(_ name: String, tema: String) -> String { system(name, temas: [tema]) }

    /// The cards of every topic in order, each card once.
    func system(_ name: String, temas: [String]) -> String {
        let base = Self.prompt(named: name, root: library.root) ?? "Du er en norsk regnskapsveileder. Svar på bokmål, kort, og vis til lovparagrafer bare når du er sikker."
        var seen = Set<String>()
        let cards = temas.flatMap { library.rules(tema: $0) }.filter { seen.insert($0.id).inserted }.map(\.promptText).joined(separator: "\n\n")
        return base + "\n\n# Regelkort for temaet\n\n" + (cards.isEmpty ? "(ingen)" : cards) + "\n\n# Satser og frister (bruk disse, ikke egne tall)\n\n" + library.rates.promptSummary()
    }

    func describe(_ puzzle: Puzzle) -> String {
        let json = String(decoding: (try? puzzle.encoded()) ?? Data(), as: UTF8.self)
        let accounts = Set(puzzleAccounts(puzzle)).sorted().compactMap { library.chart.account($0) }.map { "\($0.nr) \($0.navn) (\($0.type.navn), øker på \($0.okerPa.navn.lowercased()))" }
        return "## Oppgaven (JSON)\n```json\n\(json)\n```" + (accounts.isEmpty ? "" : "\n\n## Kontoer som er med\n" + accounts.joined(separator: "\n"))
    }

    func puzzleAccounts(_ puzzle: Puzzle) -> [String] {
        if case .posting(let p) = puzzle.payload { return p.kontoer.map(\.nr) + p.fasit.map(\.konto) }
        return []
    }

    /// Why the attempt was wrong, in Norwegian, with the paragraphs from the cards.
    public func explain(puzzle: Puzzle, attempt: String, verdict: Verdict) async throws -> String {
        let prompt = """
        \(describe(puzzle))

        ## Brukerens svar
        \(attempt)

        ## Appens tilbakemelding
        \(verdict.messages.joined(separator: " "))

        Forklar hvorfor svaret ikke er riktig, hva som er riktig tankegang, og hvilken regel det bygger på. Maks 180 ord. Ikke gjenta oppgaveteksten.
        """
        let reply = try await runner.run(ClaudeRequest(system: system("veileder", tema: puzzle.tema), prompt: prompt, schema: nil, model: model, resume: nil, persist: false))
        return reply.text
    }

    /// A question about the puzzle; pass the returned session id to continue the conversation.
    public func ask(puzzle: Puzzle, question: String, session: String?) async throws -> (answer: String, session: String) {
        let prompt = session == nil ? "\(describe(puzzle))\n\n## Spørsmål\n\(question)" : question
        let reply = try await runner.run(ClaudeRequest(system: system("veileder", tema: puzzle.tema), prompt: prompt, schema: nil, model: model, resume: session, persist: true))
        return (reply.text, reply.sessionId ?? session ?? "")
    }

    /// A new puzzle of the same kind and topic, one level harder, validated; saved as a draft by the caller.
    public func harder(than puzzle: Puzzle) async throws -> Puzzle {
        let level = min(5, puzzle.vanskelighet + 1)
        let prompt = """
        Brukeren har nettopp løst denne oppgaven:

        \(describe(puzzle))

        Lag én ny oppgave av samme type (\(puzzle.kind.rawValue)) i temaet «\(puzzle.tema)» med vanskelighet \(level): et sjeldnere tilfelle, en felle en erfaren regnskapsfører kan gå i, eller en regel med unntak. Bruk id «\(puzzle.tema)-gen-\(Int(Date().timeIntervalSince1970))». Sett status «utkast». Svar bare med JSON etter skjemaet.
        """
        let reply = try await runner.run(ClaudeRequest(system: system("forfatter", tema: puzzle.tema), prompt: prompt, schema: PuzzleSchema.schema(for: puzzle.kind), model: model, resume: nil, persist: false))
        guard let structured = reply.structured else { throw ClaudeError.badOutput }
        var generated: Puzzle
        do { generated = try Puzzle.decode(structured.data) } catch { throw ClaudeError.invalidPuzzle([ContentLibrary.describe(error)]) }
        generated.status = .utkast
        generated.generert = true
        if library.puzzle(id: generated.id) != nil { generated.id += "-\(Int(Date().timeIntervalSince1970))" }
        let problems = ContentValidator.validate(generated, library: library)
        guard problems.isEmpty else { throw ClaudeError.invalidPuzzle(problems) }
        return generated
    }

    /// A sandbox case for a topic: company, events, expected trial balance and a model journal that must reconcile.
    public func makeCase(tema: String, vanskelighet: Int = 3) async throws -> SandboxCase {
        // The richest hand-written case shows the format best; generated cases are never the model.
        let existing = SandboxCase.load(folder: library.root.appendingPathComponent("sandkasse"), includeGenerated: false)
            .max { ($0.kontoutskrift?.linjer.count ?? 0) < ($1.kontoutskrift?.linjer.count ?? 0) }
        let example = existing.map { String(decoding: (try? JSONEncoder().encode($0)) ?? Data(), as: UTF8.self) } ?? "(ingen)"
        let accounts = library.chart.all.map { "\($0.nr) \($0.navn)" }.joined(separator: "; ")
        let prompt = """
        Lag en sandkasse-case for temaet «\(tema)» med vanskelighet \(vanskelighet): et lite norsk selskap, 8–14 hendelser i én måned som brukeren skal bokføre, en fasitSaldobalanse (debet pluss, kredit minus, summen null) og en fasitJournal som gir nøyaktig den saldobalansen, og en kontoutskrift for 1920 der hver linje peker på bilagene (1-basert nummer i fasitJournal) den gjør opp. Bruk bare kontoer fra listen. Bruk id «\(tema)-case-\(Int(Date().timeIntervalSince1970))».

        ## Kontoer
        \(accounts)

        ## Eksempel på formatet
        ```json
        \(example)
        ```
        Svar bare med JSON etter skjemaet.
        """
        let reply = try await runner.run(ClaudeRequest(system: system("sandkasse", temas: [tema, "reskontro-bank", "valuta-korrigeringer"]), prompt: prompt, schema: PuzzleSchema.sandboxCase, model: model, resume: nil, persist: false))
        guard let structured = reply.structured else { throw ClaudeError.badOutput }
        let made: SandboxCase
        do { made = try JSONDecoder().decode(SandboxCase.self, from: structured.data) } catch { throw ClaudeError.invalidPuzzle([ContentLibrary.describe(error)]) }
        let problems = SandboxCaseValidator.problems(made, chart: library.chart, rates: library.rates)
        guard problems.isEmpty else { throw ClaudeError.invalidPuzzle(problems) }
        return made
    }
}

/// Where generated content is written.
public enum TutorFiles {
    public static var fallback: URL { ContentLocator.applicationSupport.appendingPathComponent("generert", isDirectory: true) }

    /// A content root inside an app bundle is never written to: it would break the code signature
    /// and the next install would delete the files.
    static func isInsideAppBundle(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0.hasSuffix(".app") }
    }

    /// `<content>/oppgaver/generert/<id>.json` when that folder can be written, else `<fallback>/<id>.json`.
    @discardableResult
    public static func save(_ puzzle: Puzzle, contentRoot: URL, fallback: URL = TutorFiles.fallback) throws -> URL {
        let data = try puzzle.encoded()
        let preferred = contentRoot.appendingPathComponent("oppgaver/generert", isDirectory: true)
        if !isInsideAppBundle(contentRoot), (try? FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true)) != nil {
            let url = preferred.appendingPathComponent("\(puzzle.id).json")
            if (try? data.write(to: url, options: .atomic)) != nil { return url }
        }
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        let url = fallback.appendingPathComponent("\(puzzle.id).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    public static func save(_ sandboxCase: SandboxCase, contentRoot: URL, fallback: URL = TutorFiles.fallback) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(sandboxCase)
        let preferred = contentRoot.appendingPathComponent("sandkasse/generert", isDirectory: true)
        if !isInsideAppBundle(contentRoot), (try? FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true)) != nil {
            let url = preferred.appendingPathComponent("\(sandboxCase.id).json")
            if (try? data.write(to: url, options: .atomic)) != nil { return url }
        }
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        let url = fallback.appendingPathComponent("\(sandboxCase.id).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
