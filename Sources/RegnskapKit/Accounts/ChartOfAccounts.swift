import Foundation

public enum Side: String, Codable, Sendable, CaseIterable {
    case debet = "D"
    case kredit = "K"

    public var navn: String { self == .debet ? "Debet" : "Kredit" }
    public var other: Side { self == .debet ? .kredit : .debet }
}

public enum AccountType: String, Codable, Sendable, CaseIterable {
    case eiendel, gjeld, egenkapital, inntekt, kostnad, disponering

    public var navn: String {
        switch self {
        case .eiendel: "Eiendel"
        case .gjeld: "Gjeld"
        case .egenkapital: "Egenkapital"
        case .inntekt: "Inntekt"
        case .kostnad: "Kostnad"
        case .disponering: "Disponering"
        }
    }
}

public enum Report: String, Codable, Sendable {
    case balanse, resultat
}

public struct Account: Codable, Hashable, Sendable, Identifiable {
    public let nr: String
    public let navn: String
    public let klasse: Int
    public let gruppe: String
    public let type: AccountType
    public let okerPa: Side
    public let rapport: Report
    public let merknad: String?

    public var id: String { nr }
    public var label: String { "\(nr) \(navn)" }

    public init(nr: String, navn: String, klasse: Int, gruppe: String, type: AccountType, okerPa: Side, rapport: Report, merknad: String? = nil) {
        self.nr = nr; self.navn = navn; self.klasse = klasse; self.gruppe = gruppe; self.type = type; self.okerPa = okerPa; self.rapport = rapport; self.merknad = merknad
    }
}

/// The NS 4102 subset the puzzles and the sandbox use, from `Innhold/kontoplan.json`.
public struct ChartOfAccounts: Sendable {
    public let standard: String
    public let classes: [Int: String]
    public let groups: [String: String]
    public let all: [Account]
    private let byNumber: [String: Account]

    private struct File: Decodable {
        let standard: String
        let klasser: [String: String]
        let grupper: [String: String]
        let kontoer: [Account]
    }

    public init(url: URL) throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        standard = file.standard
        classes = Dictionary(uniqueKeysWithValues: file.klasser.compactMap { k, v in Int(k).map { ($0, v) } })
        groups = file.grupper
        all = file.kontoer.sorted { $0.nr < $1.nr }
        byNumber = Dictionary(file.kontoer.map { ($0.nr, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func account(_ nr: String) -> Account? { byNumber[nr] }
    public func contains(_ nr: String) -> Bool { byNumber[nr] != nil }
    public func name(_ nr: String) -> String { byNumber[nr]?.navn ?? "ukjent konto" }
    public func accounts(inClass klasse: Int) -> [Account] { all.filter { $0.klasse == klasse } }
}
