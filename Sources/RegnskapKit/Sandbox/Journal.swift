import Foundation

public struct JournalLine: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var konto: String
    public var side: Side
    @Amount public var belop: Decimal
    /// The mva code of a base line (e.g. "25"): the validator then expects a matching mva line.
    public var mvaKode: String?

    enum CodingKeys: String, CodingKey { case id, konto, side, belop, mvaKode }

    public init(id: UUID = UUID(), konto: String, side: Side, belop: Decimal, mvaKode: String? = nil) {
        self.id = id; self.konto = konto; self.side = side; self._belop = Amount(wrappedValue: belop); self.mvaKode = mvaKode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        konto = try c.decode(String.self, forKey: .konto)
        side = try c.decode(Side.self, forKey: .side)
        _belop = try c.decode(Amount.self, forKey: .belop)
        mvaKode = try c.decodeIfPresent(String.self, forKey: .mvaKode)
    }

    public var debet: Decimal { side == .debet ? belop : 0 }
    public var kredit: Decimal { side == .kredit ? belop : 0 }
}

public struct JournalEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var dato: DayKey
    public var tekst: String
    public var linjer: [JournalLine]

    enum CodingKeys: String, CodingKey { case id, dato, tekst, linjer }

    public init(id: UUID = UUID(), dato: DayKey, tekst: String, linjer: [JournalLine]) {
        self.id = id; self.dato = dato; self.tekst = tekst; self.linjer = linjer
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        dato = try c.decode(DayKey.self, forKey: .dato)
        tekst = try c.decode(String.self, forKey: .tekst)
        linjer = try c.decode([JournalLine].self, forKey: .linjer)
    }

    public var sumDebet: Decimal { linjer.reduce(0) { $0 + $1.debet } }
    public var sumKredit: Decimal { linjer.reduce(0) { $0 + $1.kredit } }
    public var balanced: Bool { sumDebet == sumKredit }
}

/// The sandbox's scratch ledger: a list of entries, saved as JSON.
public struct Journal: Codable, Hashable, Sendable {
    public var entries: [JournalEntry]
    public init(entries: [JournalEntry] = []) { self.entries = entries }

    /// Signed balance per account: debet plus, kredit minus.
    public func balances() -> [String: Decimal] {
        var out: [String: Decimal] = [:]
        for entry in entries { for line in entry.linjer { out[line.konto, default: 0] += line.debet - line.kredit } }
        return out
    }
}

public struct JournalProblem: Hashable, Sendable {
    public let entryId: UUID
    public let message: String
}

/// Checks each entry: it balances, every account exists, and mva lines match the base lines'
/// codes (± 1 kr). A base line is a line with `mvaKode`; a debet base expects inngående mva on
/// 2710, a kredit base expects utgående mva on 2700, and "omvendt" expects both.
public enum JournalValidator {
    static let utgaaende = "2700", inngaaende = "2710"

    public static func problems(_ journal: Journal, chart: ChartOfAccounts, rates: Rates) -> [JournalProblem] {
        var out: [JournalProblem] = []
        for entry in journal.entries {
            if entry.linjer.isEmpty { out.append(JournalProblem(entryId: entry.id, message: "Bilaget har ingen linjer.")); continue }
            for line in entry.linjer where !chart.contains(line.konto) {
                out.append(JournalProblem(entryId: entry.id, message: "Konto \(line.konto) finnes ikke i kontoplanen."))
            }
            if !entry.balanced {
                out.append(JournalProblem(entryId: entry.id, message: "Bilaget balanserer ikke: debet \(NorwegianFormat.kroner(entry.sumDebet)), kredit \(NorwegianFormat.kroner(entry.sumKredit))."))
            }
            out += vatProblems(entry, rates: rates)
        }
        return out
    }

    static func vatProblems(_ entry: JournalEntry, rates: Rates) -> [JournalProblem] {
        let bases = entry.linjer.filter { $0.mvaKode != nil }
        guard !bases.isEmpty else { return [] }
        var expectedIn: Decimal = 0, expectedOut: Decimal = 0
        for base in bases {
            guard let rate = rates.mva(kode: base.mvaKode!), let prosent = rate.prosent else { continue }
            let mva = base.belop * prosent / 100
            if base.mvaKode == "omvendt" { expectedIn += mva; expectedOut += mva }
            else if base.side == .debet { expectedIn += mva }
            else { expectedOut += mva }
        }
        let actualIn = entry.linjer.filter { $0.konto == inngaaende }.reduce(Decimal(0)) { $0 + $1.debet - $1.kredit }
        let actualOut = entry.linjer.filter { $0.konto == utgaaende }.reduce(Decimal(0)) { $0 + $1.kredit - $1.debet }
        var out: [JournalProblem] = []
        if abs(actualIn - expectedIn) > 1 {
            out.append(JournalProblem(entryId: entry.id, message: "Inngående mva på bilaget skulle vært \(NorwegianFormat.kroner(expectedIn)) (fra mva-koden), fant \(NorwegianFormat.kroner(actualIn))."))
        }
        if abs(actualOut - expectedOut) > 1 {
            out.append(JournalProblem(entryId: entry.id, message: "Utgående mva på bilaget skulle vært \(NorwegianFormat.kroner(expectedOut)) (fra mva-koden), fant \(NorwegianFormat.kroner(actualOut))."))
        }
        return out
    }
}
