import Foundation

public struct LawReference: Codable, Hashable, Sendable {
    public let lov: String
    public let paragraf: String
    public let tekst: String

    public init(lov: String, paragraf: String, tekst: String) { self.lov = lov; self.paragraf = paragraf; self.tekst = tekst }
    public var label: String { "\(lov) \(paragraf)" }
}

public enum PuzzleKind: String, Codable, Sendable, CaseIterable {
    case postering, klassifiser, finnfeil, regnut, quiz, sak, mva, frist

    public var navn: String {
        switch self {
        case .postering: "Før bilaget"
        case .klassifiser: "Sorter"
        case .finnfeil: "Finn feilene"
        case .regnut: "Regn ut"
        case .quiz: "Quiz"
        case .sak: "Sak"
        case .mva: "Mva-behandling"
        case .frist: "Frist"
        }
    }
}

public enum PuzzleStatus: String, Codable, Sendable {
    case godkjent, utkast
}

public struct AccountOption: Codable, Hashable, Sendable, Identifiable {
    public let nr: String
    public let navn: String
    public var id: String { nr }
    public init(nr: String, navn: String) { self.nr = nr; self.navn = navn }
}

public struct PostingLine: Codable, Hashable, Sendable {
    public let konto: String
    public let side: Side
    @Amount public var belop: Decimal
    public var alt: [String]

    enum CodingKeys: String, CodingKey { case konto, side, belop, alt }

    public init(konto: String, side: Side, belop: Decimal, alt: [String] = []) {
        self.konto = konto; self.side = side; self._belop = Amount(wrappedValue: belop); self.alt = alt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        konto = try c.decode(String.self, forKey: .konto)
        side = try c.decode(Side.self, forKey: .side)
        _belop = try c.decode(Amount.self, forKey: .belop)
        alt = try c.decodeIfPresent([String].self, forKey: .alt) ?? []
    }
}

public struct Posting: Codable, Hashable, Sendable {
    public var kontoer: [AccountOption]
    public var fasit: [PostingLine]
    public init(kontoer: [AccountOption], fasit: [PostingLine]) { self.kontoer = kontoer; self.fasit = fasit }
}

public struct ClassifyItem: Codable, Hashable, Sendable {
    public let tekst: String
    public let svar: String
    public let hvorfor: String?
}

public struct Classify: Codable, Hashable, Sendable {
    public let kategorier: [String]
    public let elementer: [ClassifyItem]
}

public struct SpotItem: Codable, Hashable, Sendable {
    public let tekst: String
    public let feil: Bool
    public let hvorfor: String?
}

public struct Spot: Codable, Hashable, Sendable {
    public let overskrift: String?
    public let elementer: [SpotItem]
}

public struct NumberAnswer: Codable, Hashable, Sendable {
    @Amount public var svar: Decimal
    @Amount public var toleranse: Decimal
    public let enhet: String?
    public let hint: String?

    enum CodingKeys: String, CodingKey { case svar, toleranse, enhet, hint }

    public init(svar: Decimal, toleranse: Decimal = 0, enhet: String? = nil, hint: String? = nil) {
        _svar = Amount(wrappedValue: svar); _toleranse = Amount(wrappedValue: toleranse); self.enhet = enhet; self.hint = hint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _svar = try c.decode(Amount.self, forKey: .svar)
        _toleranse = try c.decodeIfPresent(Amount.self, forKey: .toleranse) ?? Amount(wrappedValue: 0)
        enhet = try c.decodeIfPresent(String.self, forKey: .enhet)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
    }
}

public struct Quiz: Codable, Hashable, Sendable {
    public let alternativer: [String]
    public let svar: Int
}

public struct CaseChoice: Codable, Hashable, Sendable, Identifiable {
    public let nokkel: String
    public let tekst: String
    public var id: String { nokkel }
}

public struct Case: Codable, Hashable, Sendable {
    public let fra: String?
    public let melding: String
    public let valg: [CaseChoice]
    public let svar: String
    public let sporsmal: [String]
    public let forslag: String?

    enum CodingKeys: String, CodingKey { case fra, melding, valg, svar, sporsmal, forslag }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fra = try c.decodeIfPresent(String.self, forKey: .fra)
        melding = try c.decode(String.self, forKey: .melding)
        valg = try c.decode([CaseChoice].self, forKey: .valg)
        svar = try c.decode(String.self, forKey: .svar)
        sporsmal = try c.decodeIfPresent([String].self, forKey: .sporsmal) ?? []
        forslag = try c.decodeIfPresent(String.self, forKey: .forslag)
    }
}

public struct VATAnswer: Codable, Hashable, Sendable {
    public let behandling: String
    public let fradrag: Bool?
    public init(behandling: String, fradrag: Bool?) { self.behandling = behandling; self.fradrag = fradrag }
}

public struct VAT: Codable, Hashable, Sendable {
    public let transaksjon: String
    public let fasit: VATAnswer
    public init(transaksjon: String, fasit: VATAnswer) { self.transaksjon = transaksjon; self.fasit = fasit }
}

public struct Deadline: Codable, Hashable, Sendable {
    public let hendelse: String
    public let fasit: DayKey
    public let fasitRegel: JSONValue?
    public let hint: String?
}

public enum PuzzlePayload: Hashable, Sendable {
    case posting(Posting)
    case classify(Classify)
    case spot(Spot)
    case number(NumberAnswer)
    case quiz(Quiz)
    case `case`(Case)
    case vat(VAT)
    case deadline(Deadline)
}

/// One puzzle, as one JSON file in `Innhold/oppgaver/<tema>/`. The common fields are in the
/// object itself and the kind-specific ones beside them (see docs/innhold.md).
public struct Puzzle: Identifiable, Sendable, Hashable {
    public var id: String
    public var kind: PuzzleKind
    public var tema: String
    public var vanskelighet: Int
    public var tags: [String]
    public var tittel: String
    public var oppgave: String
    public var lov: [LawReference]
    public var forklaring: String
    public var status: PuzzleStatus
    public var payload: PuzzlePayload
    /// Loaded from a `generert/` folder: written by Claude, not reviewed.
    public var generert: Bool = false
    public var sourceURL: URL?

    public var isEdgeCase: Bool { tags.contains("edge-case") }

    enum Keys: String, CodingKey {
        case id, type, tema, vanskelighet, tags, tittel, oppgave, lov, forklaring, status
        case kontoer, fasit, kategorier, elementer, overskrift, svar, toleranse, enhet, hint, alternativer
        case fra, melding, valg, sporsmal, forslag, transaksjon, hendelse, fasitRegel
    }

    /// `generert` marks a puzzle from a folder Claude writes to; a folder named `generert` counts on its own.
    public static func load(url: URL, generert: Bool = false) throws -> Puzzle {
        var puzzle = try decode(Data(contentsOf: url))
        puzzle.sourceURL = url
        puzzle.generert = generert || url.pathComponents.contains("generert")
        return puzzle
    }

    public static func decode(_ data: Data) throws -> Puzzle {
        try JSONDecoder().decode(Puzzle.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension Puzzle: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        let typeName = try c.decode(String.self, forKey: .type)
        guard let kind = PuzzleKind(rawValue: typeName) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Ukjent type «\(typeName)». Gyldige: \(PuzzleKind.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        self.kind = kind
        tema = try c.decode(String.self, forKey: .tema)
        vanskelighet = try c.decode(Int.self, forKey: .vanskelighet)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        tittel = try c.decode(String.self, forKey: .tittel)
        oppgave = try c.decode(String.self, forKey: .oppgave)
        lov = try c.decodeIfPresent([LawReference].self, forKey: .lov) ?? []
        forklaring = try c.decode(String.self, forKey: .forklaring)
        status = try c.decodeIfPresent(PuzzleStatus.self, forKey: .status) ?? .utkast
        // The kind-specific fields sit beside the common ones, so the same container decodes them.
        let flat = try decoder.singleValueContainer()
        switch kind {
        case .postering: payload = .posting(try flat.decode(Posting.self))
        case .klassifiser: payload = .classify(try flat.decode(Classify.self))
        case .finnfeil: payload = .spot(try flat.decode(Spot.self))
        case .regnut: payload = .number(try flat.decode(NumberAnswer.self))
        case .quiz: payload = .quiz(try flat.decode(Quiz.self))
        case .sak: payload = .case(try flat.decode(Case.self))
        case .mva: payload = .vat(try flat.decode(VAT.self))
        case .frist: payload = .deadline(try flat.decode(Deadline.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .type)
        try c.encode(tema, forKey: .tema)
        try c.encode(vanskelighet, forKey: .vanskelighet)
        try c.encode(tags, forKey: .tags)
        try c.encode(tittel, forKey: .tittel)
        try c.encode(oppgave, forKey: .oppgave)
        try c.encode(lov, forKey: .lov)
        try c.encode(forklaring, forKey: .forklaring)
        try c.encode(status, forKey: .status)
        switch payload {
        case .posting(let p): try p.encode(to: encoder)
        case .classify(let p): try p.encode(to: encoder)
        case .spot(let p): try p.encode(to: encoder)
        case .number(let p): try p.encode(to: encoder)
        case .quiz(let p): try p.encode(to: encoder)
        case .case(let p): try p.encode(to: encoder)
        case .vat(let p): try p.encode(to: encoder)
        case .deadline(let p): try p.encode(to: encoder)
        }
    }
}
