import Foundation

public struct ContentProblem: Sendable {
    public let id: String
    public let file: String?
    public let messages: [String]
}

/// Checks a puzzle against the chart, the rates and the content contract. Structure only: it
/// cannot tell whether a paragraph is the right one, which is what `/kvalitetssjekk` is for.
public enum ContentValidator {
    nonisolated(unsafe) static let paragraphPattern = /^§ ?\d+(-\d+){0,2}[a-z]?$/

    public static func validateAll(_ library: ContentLibrary) -> [ContentProblem] {
        let puzzleProblems = library.puzzles.compactMap { puzzle -> ContentProblem? in
            let messages = validate(puzzle, library: library)
            return messages.isEmpty ? nil : ContentProblem(id: puzzle.id, file: puzzle.sourceURL?.lastPathComponent, messages: messages)
        }
        return puzzleProblems + validateTown(library.town, library: library)
    }

    public static func validate(_ puzzle: Puzzle, library: ContentLibrary) -> [String] {
        var out: [String] = []
        if puzzle.id.trimmingCharacters(in: .whitespaces).isEmpty { out.append("id mangler") }
        if library.topic(puzzle.tema) == nil { out.append("ukjent tema «\(puzzle.tema)»") }
        if !(1...5).contains(puzzle.vanskelighet) { out.append("vanskelighet må være 1–5, er \(puzzle.vanskelighet)") }
        if puzzle.tittel.isEmpty { out.append("tittel mangler") }
        if puzzle.oppgave.isEmpty { out.append("oppgave mangler") }
        if puzzle.forklaring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("forklaring mangler") }
        if puzzle.lov.isEmpty { out.append("minst én lov-henvisning kreves") }
        for ref in puzzle.lov {
            if ref.paragraf.wholeMatch(of: paragraphPattern) == nil { out.append("paragraf «\(ref.paragraf)» må ha formen «§ 3-1» eller «§ 8-3-10» (detaljer i tekst)") }
            if ref.lov.isEmpty || ref.tekst.isEmpty { out.append("lov-henvisning mangler lov eller tekst") }
        }
        out += validatePayload(puzzle, library: library)
        return out
    }

    private static func validatePayload(_ puzzle: Puzzle, library: ContentLibrary) -> [String] {
        var out: [String] = []
        switch puzzle.payload {
        case .posting(let p):
            if p.fasit.count < 2 { out.append("fasit må ha minst to linjer") }
            let debet = p.fasit.filter { $0.side == .debet }.reduce(Decimal(0)) { $0 + $1.belop }
            let kredit = p.fasit.filter { $0.side == .kredit }.reduce(Decimal(0)) { $0 + $1.belop }
            if debet != kredit { out.append("fasit balanserer ikke: debet \(NorwegianFormat.kroner(debet)) ≠ kredit \(NorwegianFormat.kroner(kredit))") }
            for line in p.fasit {
                if line.belop <= 0 { out.append("konto \(line.konto): beløp må være større enn null") }
                for nr in [line.konto] + line.alt where !library.chart.contains(nr) { out.append("konto \(nr) finnes ikke i kontoplan.json") }
                if !p.kontoer.contains(where: { $0.nr == line.konto }) { out.append("konto \(line.konto) i fasit mangler i kontoer (velgeren)") }
            }
            for option in p.kontoer where !library.chart.contains(option.nr) { out.append("konto \(option.nr) i kontoer finnes ikke i kontoplan.json") }
        case .classify(let p):
            if p.kategorier.count < 2 { out.append("kategorier må ha minst to kategorier") }
            if p.elementer.isEmpty { out.append("elementer mangler") }
            for item in p.elementer where !p.kategorier.contains(item.svar) { out.append("svar «\(item.svar)» er ikke en av kategoriene") }
        case .spot(let p):
            if !p.elementer.contains(where: \.feil) { out.append("finnfeil må ha minst ett element med feil: true") }
            for item in p.elementer where item.feil && (item.hvorfor ?? "").isEmpty { out.append("element «\(item.tekst.prefix(30))» med feil mangler hvorfor") }
        case .number(let p):
            if p.toleranse < 0 { out.append("toleranse kan ikke være negativ") }
        case .quiz(let p):
            if p.alternativer.count < 2 { out.append("quiz må ha minst to alternativer") }
            if !p.alternativer.indices.contains(p.svar) { out.append("svar \(p.svar) peker utenfor alternativer (0–\(max(p.alternativer.count - 1, 0)))") }
        case .case(let p):
            if !p.valg.contains(where: { $0.nokkel == p.svar }) { out.append("svar «\(p.svar)» er ikke en nøkkel i valg") }
            if p.valg.count < 2 { out.append("sak må ha minst to valg") }
        case .vat(let p):
            if library.rates.mva(kode: p.fasit.behandling) == nil {
                out.append("behandling «\(p.fasit.behandling)» finnes ikke i satser.json (\(library.rates.mvaSatser.map(\.kode).joined(separator: ", ")))")
            }
        case .deadline(let p):
            if let rule = p.fasitRegel {
                if let expected = Self.deadline(from: rule, deadlines: library.deadlines) {
                    if expected != p.fasit { out.append("fasit \(p.fasit) stemmer ikke med regelen, som gir \(expected)") }
                } else {
                    out.append("fasitRegel er ukjent eller mangler felt: \(String(decoding: rule.data, as: UTF8.self))")
                }
            }
        }
        return out
    }

    /// The date a `fasitRegel` describes, computed from the rates. Types: mva (termin, aar),
    /// mva-aarlig (aar), amelding (maaned, aar), aga (termin, aar), forskuddstrekk (utbetalt),
    /// aarsregnskap (aar), aarsregnskap-fastsettes (aar), skattemelding (aar).
    public static func deadline(from rule: JSONValue, deadlines: Deadlines) -> DayKey? {
        let year = rule["aar"]?.int
        switch rule["type"]?.string {
        case "mva": if let t = rule["termin"]?.int, let year { return deadlines.mvaFrist(termin: t, year: year) }
        case "mva-aarlig": if let year { return deadlines.mvaAarligFrist(year: year) }
        case "amelding": if let m = rule["maaned"]?.int, let year { return deadlines.ameldingFrist(forMonth: m, year: year) }
        case "aga": if let t = rule["termin"]?.int, let year { return deadlines.agaFrist(termin: t, year: year) }
        case "forskuddstrekk": if let s = rule["utbetalt"]?.string, let day = DayKey(string: s) { return deadlines.forskuddstrekkFrist(utbetalt: day) }
        case "aarsregnskap": if let year { return deadlines.aarsregnskapFrist(year: year) }
        case "aarsregnskap-fastsettes": if let year { return deadlines.aarsregnskapFastsettesFrist(year: year) }
        case "skattemelding": if let year { return deadlines.skattemeldingFrist(year: year) }
        default: break
        }
        return nil
    }
}
