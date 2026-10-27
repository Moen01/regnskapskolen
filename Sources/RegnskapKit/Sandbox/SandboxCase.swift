import Foundation

public struct CaseEvent: Codable, Hashable, Sendable, Identifiable {
    public let dato: DayKey
    public let tekst: String
    public let hint: String?
    public var id: String { "\(dato.string)-\(tekst.prefix(40))" }
}

public struct CaseDiff: Hashable, Sendable, Identifiable {
    public let konto: String
    public let forventet: Decimal
    public let faktisk: Decimal
    public var id: String { konto }
}

/// A sandbox case from `Innhold/sandkasse/<id>.json`: a company, events to book, the expected trial
/// balance (signed, debet plus) and, for the tests, the model journal.
public struct SandboxCase: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let tittel: String
    public let selskap: String
    public let beskrivelse: String
    public let vanskelighet: Int
    public let lov: [LawReference]
    public let hendelser: [CaseEvent]
    public let fasitSaldobalanse: [String: Decimal]
    public let fasitJournal: Journal?

    enum CodingKeys: String, CodingKey { case id, tittel, selskap, beskrivelse, vanskelighet, lov, hendelser, fasitSaldobalanse, fasitJournal }

    public init(id: String, tittel: String, selskap: String, beskrivelse: String, vanskelighet: Int, lov: [LawReference], hendelser: [CaseEvent], fasitSaldobalanse: [String: Decimal], fasitJournal: Journal?) {
        self.id = id; self.tittel = tittel; self.selskap = selskap; self.beskrivelse = beskrivelse; self.vanskelighet = vanskelighet
        self.lov = lov; self.hendelser = hendelser; self.fasitSaldobalanse = fasitSaldobalanse; self.fasitJournal = fasitJournal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tittel = try c.decode(String.self, forKey: .tittel)
        selskap = try c.decode(String.self, forKey: .selskap)
        beskrivelse = try c.decode(String.self, forKey: .beskrivelse)
        vanskelighet = try c.decodeIfPresent(Int.self, forKey: .vanskelighet) ?? 3
        lov = try c.decodeIfPresent([LawReference].self, forKey: .lov) ?? []
        hendelser = try c.decode([CaseEvent].self, forKey: .hendelser)
        fasitSaldobalanse = try c.decode([String: Double].self, forKey: .fasitSaldobalanse).mapValues { Decimal(lossless: $0) }
        fasitJournal = try c.decodeIfPresent(Journal.self, forKey: .fasitJournal)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(tittel, forKey: .tittel); try c.encode(selskap, forKey: .selskap)
        try c.encode(beskrivelse, forKey: .beskrivelse); try c.encode(vanskelighet, forKey: .vanskelighet); try c.encode(lov, forKey: .lov)
        try c.encode(hendelser, forKey: .hendelser)
        try c.encode(fasitSaldobalanse.mapValues { NSDecimalNumber(decimal: $0).doubleValue }, forKey: .fasitSaldobalanse)
        try c.encodeIfPresent(fasitJournal, forKey: .fasitJournal)
    }

    public static func load(folder: URL) -> [SandboxCase] {
        ContentLibrary.jsonFiles(under: folder).compactMap { url in
            try? JSONDecoder().decode(SandboxCase.self, from: Data(contentsOf: url))
        }
    }

    /// Accounts whose balance differs from the expected one. Accounts absent on either side count as zero.
    public func compare(journal: Journal, chart: ChartOfAccounts) -> [CaseDiff] {
        let actual = journal.balances()
        return Set(fasitSaldobalanse.keys).union(actual.keys).sorted().compactMap { konto in
            let expected = fasitSaldobalanse[konto] ?? 0, got = actual[konto] ?? 0
            return expected == got ? nil : CaseDiff(konto: konto, forventet: expected, faktisk: got)
        }
    }
}
