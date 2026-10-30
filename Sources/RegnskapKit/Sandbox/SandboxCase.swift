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
    public let kontoutskrift: BankStatement?
    /// Dated rates per currency code, for cases with foreign-currency events.
    public let valutakurser: [String: [ExchangeRate]]?

    enum CodingKeys: String, CodingKey { case id, tittel, selskap, beskrivelse, vanskelighet, lov, hendelser, fasitSaldobalanse, fasitJournal, kontoutskrift, valutakurser }

    public init(id: String, tittel: String, selskap: String, beskrivelse: String, vanskelighet: Int, lov: [LawReference], hendelser: [CaseEvent], fasitSaldobalanse: [String: Decimal], fasitJournal: Journal?, kontoutskrift: BankStatement? = nil, valutakurser: [String: [ExchangeRate]]? = nil) {
        self.id = id; self.tittel = tittel; self.selskap = selskap; self.beskrivelse = beskrivelse; self.vanskelighet = vanskelighet
        self.lov = lov; self.hendelser = hendelser; self.fasitSaldobalanse = fasitSaldobalanse; self.fasitJournal = fasitJournal
        self.kontoutskrift = kontoutskrift; self.valutakurser = valutakurser
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
        kontoutskrift = try c.decodeIfPresent(BankStatement.self, forKey: .kontoutskrift)
        valutakurser = try c.decodeIfPresent([String: [ExchangeRate]].self, forKey: .valutakurser)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(tittel, forKey: .tittel); try c.encode(selskap, forKey: .selskap)
        try c.encode(beskrivelse, forKey: .beskrivelse); try c.encode(vanskelighet, forKey: .vanskelighet); try c.encode(lov, forKey: .lov)
        try c.encode(hendelser, forKey: .hendelser)
        try c.encode(fasitSaldobalanse.mapValues { NSDecimalNumber(decimal: $0).doubleValue }, forKey: .fasitSaldobalanse)
        try c.encodeIfPresent(fasitJournal, forKey: .fasitJournal)
        try c.encodeIfPresent(kontoutskrift, forKey: .kontoutskrift); try c.encodeIfPresent(valutakurser, forKey: .valutakurser)
    }

    /// `includeGenerated: false` skips files under a `generert` folder, so only hand-written cases remain.
    public static func load(folder: URL, includeGenerated: Bool = true) -> [SandboxCase] {
        ContentLibrary.jsonFiles(under: folder).filter { includeGenerated || !$0.pathComponents.contains("generert") }.compactMap { url in
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

/// What an entrance to a sandbox case does: the town's sandbox people and the bank region's
/// dungeon share it, so neither ever wipes a half-done case.
public enum SandboxEntrance: Equatable, Sendable {
    /// The case is the active one: show the sandbox as it is.
    case show
    /// Start the case on the empty journal.
    case start
    /// The journal holds entries of another case; the player empties it first.
    case busy
    /// No case has the id.
    case missing

    public static func decide(caseId: String, activeCaseId: String?, journalEmpty: Bool, exists: Bool) -> SandboxEntrance {
        if activeCaseId == caseId { return .show }
        guard journalEmpty else { return .busy }
        return exists ? .start : .missing
    }

    /// The lines that tell why the sandbox did not open; empty when it opens.
    public var texts: [String] {
        switch self {
        case .show, .start: []
        case .busy: ["Sandkassen har en annen sak.", "Tøm den først."]
        case .missing: ["Saken finnes ikke ennå."]
        }
    }
}
