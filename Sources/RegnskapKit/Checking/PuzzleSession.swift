import Foundation

/// What the learner has entered for one puzzle, one case per kind.
public enum PuzzleAttempt: Hashable, Sendable {
    case posting(PostingAttempt)
    case classify([Int: String])
    case spot(Set<Int>)
    case number(String)
    case quiz(Int?)
    case `case`(String?)
    case vat(behandling: String?, fradrag: Bool?)
    case deadline(DayKey?)

    public static func empty(for kind: PuzzleKind) -> PuzzleAttempt {
        switch kind {
        case .postering: .posting([])
        case .klassifiser: .classify([:])
        case .finnfeil: .spot([])
        case .regnut: .number("")
        case .quiz: .quiz(nil)
        case .sak: .case(nil)
        case .mva: .vat(behandling: nil, fradrag: nil)
        case .frist: .deadline(nil)
        }
    }

    /// Enough input to be checked. Marking nothing in "finn feilene" is an answer in itself.
    public var isAnswered: Bool {
        switch self {
        case .posting(let lines): lines.contains { !$0.konto.isEmpty && (($0.debet ?? 0) != 0 || ($0.kredit ?? 0) != 0) }
        case .classify(let answers): !answers.isEmpty
        case .spot: true
        case .number(let text): NorwegianFormat.parseAmount(text) != nil
        case .quiz(let index): index != nil
        case .case(let key): key != nil
        case .vat(let behandling, _): behandling != nil
        case .deadline(let day): day != nil
        }
    }

    func verdict(for puzzle: Puzzle) -> Verdict {
        switch (self, puzzle.payload) {
        case (.posting(let lines), .posting(let p)): PostingChecker.check(lines, against: p)
        case (.classify(let answers), .classify(let p)): Checkers.classify(answers, p)
        case (.spot(let marked), .spot(let p)): Checkers.spot(marked, p)
        case (.number(let text), .number(let p)): Checkers.number(NorwegianFormat.parseAmount(text) ?? 0, p)
        case (.quiz(let index?), .quiz(let p)): Checkers.quiz(index, p)
        case (.case(let key?), .case(let p)): Checkers.case(key, p)
        case (.vat(let behandling?, let fradrag), .vat(let p)): Checkers.vat(behandling, fradrag, p)
        case (.deadline(let day?), .deadline(let p)): Checkers.deadline(day, p)
        default: .wrong(["Svaret passer ikke oppgavetypen."])
        }
    }

    /// The attempt in words, for the tutor prompt.
    public func summary(for puzzle: Puzzle) -> String {
        let unanswered = "Ikke besvart"
        switch (self, puzzle.payload) {
        case (.posting(let lines), .posting(let p)):
            let used = lines.filter { !$0.konto.isEmpty && ($0.debet != nil || $0.kredit != nil) }
            guard !used.isEmpty else { return unanswered }
            return used.map { line in
                let name = p.kontoer.first { $0.nr == line.konto }.map { " \($0.navn)" } ?? ""
                var sides: [String] = []
                if let d = line.debet { sides.append("debet \(NorwegianFormat.kroner(d))") }
                if let k = line.kredit { sides.append("kredit \(NorwegianFormat.kroner(k))") }
                return "\(line.konto)\(name): \(sides.joined(separator: " / "))"
            }.joined(separator: "\n")
        case (.classify(let answers), .classify(let p)):
            guard !answers.isEmpty else { return unanswered }
            return answers.keys.sorted().compactMap { i in p.elementer.indices.contains(i) ? "\(p.elementer[i].tekst) → \(answers[i]!)" : nil }.joined(separator: "\n")
        case (.spot(let marked), .spot(let p)):
            let texts = marked.sorted().compactMap { p.elementer.indices.contains($0) ? p.elementer[$0].tekst : nil }
            return texts.isEmpty ? "Markerte ingen feil" : "Markerte som feil: " + texts.joined(separator: "; ")
        case (.number(let text), _):
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? unanswered : "Svarte: \(text)"
        case (.quiz(let index?), .quiz(let p)):
            return p.alternativer.indices.contains(index) ? "Valgte: \(p.alternativer[index])" : unanswered
        case (.case(let key?), .case(let p)):
            return "Valgte: \(key)" + (p.valg.first { $0.nokkel == key }.map { " – \($0.tekst)" } ?? "")
        case (.vat(let behandling?, let fradrag), _):
            let deduction = fradrag.map { $0 ? "ja" : "nei" } ?? "ikke angitt"
            return "Behandling: \(behandling), fradrag: \(deduction)"
        case (.deadline(let day?), _):
            return "Svarte: \(NorwegianFormat.date(day.date))"
        default:
            return unanswered
        }
    }
}

/// One sitting with one puzzle: the attempt, how many checks it took, and what the scheduler
/// should hear about it.
public struct PuzzleSession: Hashable, Sendable {
    public let puzzle: Puzzle
    public var attempt: PuzzleAttempt
    public private(set) var checks = 0
    public private(set) var wrongChecks = 0
    public private(set) var verdict: Verdict?
    public private(set) var revealed = false

    public init(puzzle: Puzzle) {
        self.puzzle = puzzle
        attempt = .empty(for: puzzle.kind)
    }

    public var isFinished: Bool { verdict?.correct == true || revealed }

    /// "Regn ut" gives two tries before the answer may be shown; every other kind may show it at once.
    public var canReveal: Bool { puzzle.kind != .regnut || wrongChecks >= 2 }

    /// Checks the attempt. An attempt without an answer gets a prompt back and is not counted.
    @discardableResult
    public mutating func check() -> Verdict {
        guard attempt.isAnswered else {
            let prompt = puzzle.kind == .regnut ? "Skriv et beløp, for eksempel 1 250 eller 1250,50." : "Svar først."
            verdict = .wrong([prompt])
            return verdict!
        }
        let result = attempt.verdict(for: puzzle)
        checks += 1
        if !result.correct { wrongChecks += 1 }
        verdict = result
        return result
    }

    public mutating func reveal() { revealed = true }

    /// Right on the first check, with the answer not shown, is what moves a puzzle up a box.
    public var result: AttemptResult {
        AttemptResult(puzzleId: puzzle.id, correctFirstTry: checks == 1 && verdict?.correct == true && !revealed)
    }
}
