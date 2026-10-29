import Foundation

/// A day-and-month deadline, in the same year as the period or the next.
public struct DeadlineRule: Codable, Hashable, Sendable {
    public let dag: Int
    public let maaned: Int
    public let aar: String  // "samme" | "neste"

    public func day(forYear year: Int) -> DayKey {
        DayKey(year: aar == "neste" ? year + 1 : year, month: maaned, day: dag)
    }
}

public struct Termin: Codable, Hashable, Sendable {
    public let nr: Int
    public let maaneder: [Int]
    public let frist: DeadlineRule
}

public struct MVARate: Codable, Hashable, Sendable {
    public let kode: String
    public let navn: String
    public let prosent: Decimal?
    public let fradrag: Bool
    public let eksempler: [String]

    enum CodingKeys: String, CodingKey { case kode, navn, prosent, fradrag, eksempler }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kode = try c.decode(String.self, forKey: .kode)
        navn = try c.decode(String.self, forKey: .navn)
        prosent = try c.decodeIfPresent(Double.self, forKey: .prosent).map { Decimal(lossless: $0) }
        fradrag = try c.decode(Bool.self, forKey: .fradrag)
        eksempler = try c.decodeIfPresent([String].self, forKey: .eksempler) ?? []
    }

    /// 1.25 for 25 %; 1 when the code has no rate.
    public var factor: Decimal { 1 + (prosent ?? 0) / 100 }
}

public struct AGAZone: Codable, Hashable, Sendable {
    public let sone: String
    @Amount public var prosent: Decimal
    public let merknad: String?
}

public struct Saldogruppe: Codable, Hashable, Sendable {
    public let gruppe: String
    public let navn: String
    @Amount public var prosent: Decimal
    public let merknad: String?
}

public struct Feriepenger: Codable, Hashable, Sendable {
    @Amount public var lovfestet: Decimal
    @Amount public var tariff: Decimal
    @Amount public var tilleggOver60: Decimal
    public let over60Tak: String
    public let lov: String
}

public struct Forskuddstrekk: Codable, Hashable, Sendable {
    public let regel: String
    public let beskrivelse: String
    public let gjelderFra: DayKey
    public let lov: String
    public let tidligereRegel: String
}

public struct Driftsmiddel: Codable, Hashable, Sendable {
    @Amount public var grense: Decimal
    public let levetidAar: Int
    public let lov: String
    public let merknad: String
}

public struct Oppbevaring: Codable, Hashable, Sendable {
    public let primaerAar: Int
    @Amount public var sekundaerAar: Decimal
    public let lov: String
}

public struct Representasjon: Codable, Hashable, Sendable {
    @Amount public var bevertningPerPerson: Decimal
    public let lov: String
}

public struct Aarsregnskap: Codable, Hashable, Sendable {
    public let fastsettesInnenMaaneder: Int
    public let sendesInnen: DeadlineRule
    public let lov: String
    public let merknad: String
}

public struct RenteSats: Codable, Hashable, Sendable {
    public let fra: DayKey
    @Amount public var prosent: Decimal
}

/// `Innhold/satser.json`: every rate, threshold and deadline rule the puzzles, the validator and
/// the sandbox use. Nothing here is hard-coded in Swift.
public struct Rates: Hashable, Sendable {
    public let verifisert: DayKey
    public let kilder: [String: String]
    public let mvaSatser: [MVARate]
    public let mvaRegistreringsgrense: Decimal
    public let mvaTerminer: [Termin]
    public let mvaAarligFrist: DeadlineRule
    public let mvaAarligGrense: Decimal
    public let ameldingFristDag: Int
    public let forskuddstrekk: Forskuddstrekk
    public let agaSoner: [AGAZone]
    public let agaTerminer: [Termin]
    public let feriepenger: Feriepenger
    public let selskapsskatt: Decimal
    public let skattemeldingFrist: DeadlineRule
    public let saldogrupper: [Saldogruppe]
    public let driftsmiddel: Driftsmiddel
    public let representasjon: Representasjon
    public let aarsregnskap: Aarsregnskap
    public let oppbevaring: Oppbevaring
    public let forsinkelsesrenter: [RenteSats]
    public let standardkompensasjon: Decimal
    public let purregebyr: Decimal
    public let inkassosats: Decimal

    private struct File: Decodable {
        struct MVA: Decodable {
            struct Terminer: Decodable { let liste: [Termin]; let aarligFrist: DeadlineRule; let aarligGrense: Double }
            let satser: [MVARate]; let registreringsgrense: Double; let terminer: Terminer
        }
        struct Lonn: Decodable {
            struct AGA: Decodable { let soner: [AGAZone]; let terminer: [Termin] }
            let ameldingFristDag: Int; let forskuddstrekk: Forskuddstrekk; let arbeidsgiveravgift: AGA; let feriepenger: Feriepenger
        }
        struct Skatt: Decodable {
            struct Saldo: Decodable { let liste: [Saldogruppe] }
            let selskapsskatt: Double; let skattemeldingFrist: DeadlineRule; let saldogrupper: Saldo
            let driftsmiddel: Driftsmiddel; let representasjon: Representasjon
        }
        struct Regnskap: Decodable { let aarsregnskap: Aarsregnskap; let oppbevaring: Oppbevaring }
        struct Inndrivelse: Decodable { let forsinkelsesrente: [RenteSats]; let standardkompensasjon: Double; let inkassosats: Double; let purregebyr: Double }
        let verifisert: DayKey; let kilder: [String: String]; let mva: MVA; let lonn: Lonn; let skatt: Skatt; let regnskap: Regnskap; let inndrivelse: Inndrivelse
    }

    public init(url: URL) throws {
        let f = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        verifisert = f.verifisert
        kilder = f.kilder
        mvaSatser = f.mva.satser
        mvaRegistreringsgrense = Decimal(lossless: f.mva.registreringsgrense)
        mvaTerminer = f.mva.terminer.liste.sorted { $0.nr < $1.nr }
        mvaAarligFrist = f.mva.terminer.aarligFrist
        mvaAarligGrense = Decimal(lossless: f.mva.terminer.aarligGrense)
        ameldingFristDag = f.lonn.ameldingFristDag
        forskuddstrekk = f.lonn.forskuddstrekk
        agaSoner = f.lonn.arbeidsgiveravgift.soner
        agaTerminer = f.lonn.arbeidsgiveravgift.terminer.sorted { $0.nr < $1.nr }
        feriepenger = f.lonn.feriepenger
        selskapsskatt = Decimal(lossless: f.skatt.selskapsskatt)
        skattemeldingFrist = f.skatt.skattemeldingFrist
        saldogrupper = f.skatt.saldogrupper.liste
        driftsmiddel = f.skatt.driftsmiddel
        representasjon = f.skatt.representasjon
        aarsregnskap = f.regnskap.aarsregnskap
        oppbevaring = f.regnskap.oppbevaring
        forsinkelsesrenter = f.inndrivelse.forsinkelsesrente.sorted { $0.fra < $1.fra }
        standardkompensasjon = Decimal(lossless: f.inndrivelse.standardkompensasjon)
        inkassosats = Decimal(lossless: f.inndrivelse.inkassosats)
        purregebyr = Decimal(lossless: f.inndrivelse.purregebyr)
    }

    public func mva(kode: String) -> MVARate? { mvaSatser.first { $0.kode == kode } }
    public func saldogruppe(_ gruppe: String) -> Saldogruppe? { saldogrupper.first { $0.gruppe == gruppe } }
    public func aga(sone: String) -> AGAZone? { agaSoner.first { $0.sone == sone } }

    /// The late-payment interest in force on `day`; nil before the first listed rate.
    public func forsinkelsesrente(on day: DayKey) -> Decimal? {
        forsinkelsesrenter.last { $0.fra <= day }?.prosent
    }

    /// The rates as compact JSON for a prompt.
    public func promptSummary() -> String {
        let mva = mvaSatser.map { "\($0.kode): \($0.navn)\($0.prosent.map { " \($0) %" } ?? ""), fradrag \($0.fradrag ? "ja" : "nei")" }.joined(separator: "; ")
        let saldo = saldogrupper.map { "\($0.gruppe) \($0.prosent) %" }.joined(separator: ", ")
        let frister = mvaTerminer.map { "termin \($0.nr) \($0.frist.dag).\($0.frist.maaned)." }.joined(separator: ", ")
        return """
        Mva-satser: \(mva). Registreringsgrense \(mvaRegistreringsgrense) kr. Mva-frister: \(frister) (årlig \(mvaAarligFrist.dag).\(mvaAarligFrist.maaned).).
        A-melding: den \(ameldingFristDag). i måneden etter. Forskuddstrekk: \(forskuddstrekk.beskrivelse) (fra \(forskuddstrekk.gjelderFra)).
        Arbeidsgiveravgift sone 1: \(aga(sone: "1")?.prosent ?? 0) %. Feriepenger: \(feriepenger.lovfestet) % (lovfestet), \(feriepenger.tariff) % (tariff), +\(feriepenger.tilleggOver60) pp over 60 år.
        Saldogrupper: \(saldo). Driftsmiddel aktiveres fra \(driftsmiddel.grense) kr og \(driftsmiddel.levetidAar) års levetid.
        Representasjon, enkel bevertning: \(representasjon.bevertningPerPerson) kr per person. Selskapsskatt \(selskapsskatt) %.
        Årsregnskap: fastsettes innen \(aarsregnskap.fastsettesInnenMaaneder) måneder, sendes innen \(aarsregnskap.sendesInnen.dag).\(aarsregnskap.sendesInnen.maaned). året etter. Oppbevaring: \(oppbevaring.primaerAar) år primær, \(oppbevaring.sekundaerAar) år sekundær.
        Forsinkelsesrente: \(forsinkelsesrenter.map { "\($0.prosent) % fra \($0.fra)" }.joined(separator: ", ")). Purregebyr \(purregebyr) kr, standardkompensasjon \(standardkompensasjon) kr.
        Satsene er sjekket \(verifisert).
        """
    }
}

public struct Topic: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let navn: String
    public let maal: String
    public let rekkefolge: Int
}

public struct Topics: Sendable {
    public let all: [Topic]
    public init(url: URL) throws {
        all = try JSONDecoder().decode([Topic].self, from: Data(contentsOf: url)).sorted { $0.rekkefolge < $1.rekkefolge }
    }
    public func topic(_ id: String) -> Topic? { all.first { $0.id == id } }
    public func contains(_ id: String) -> Bool { topic(id) != nil }
}
