import Foundation

/// An industry the player can meet in town: which topics and rule cards it draws on.
public struct Bransje: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let navn: String
    public let temaer: [String]
    public let regelkort: [String]
    public let setning: String
}

public enum MvaTerminType: String, Codable, Sendable {
    case tomaanedlig, aarlig
}

public struct TownPlace: Codable, Hashable, Sendable {
    public let kart: String
    public let x: Int
    public let y: Int
}

/// What a client says in each situation. Every line goes through `TextWrap` at 18 columns.
public struct ClientLines: Codable, Hashable, Sendable {
    public let hilsen: [String]
    public let drift: [String]
    public let haug: [String]
    public let tomHaug: [String]
    public let glippetFrist: [String]
    /// Said when the client finds an old error. It must not give the answer away.
    public let oppdagetFeil: [String]
}

public struct TownClient: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let navn: String
    public let bransje: String
    public let selskapsform: String
    public let mvaRegistrert: Bool
    public let ansatte: Int
    /// The day of the month staff are paid (1...28); set exactly when `ansatte > 0`.
    public let lonnsdag: Int?
    public let mvaTermin: MvaTerminType?
    public let sted: TownPlace
    public let oppgaver: [String]
    public let provesak: [String]
    public let replikker: ClientLines
    public let startklient: Bool
    public let status: PuzzleStatus

    private enum CodingKeys: String, CodingKey {
        case id, navn, bransje, selskapsform, mvaRegistrert, ansatte, lonnsdag, mvaTermin, sted, oppgaver, provesak, replikker, startklient, status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        navn = try c.decode(String.self, forKey: .navn)
        bransje = try c.decode(String.self, forKey: .bransje)
        selskapsform = try c.decode(String.self, forKey: .selskapsform)
        mvaRegistrert = try c.decode(Bool.self, forKey: .mvaRegistrert)
        ansatte = try c.decode(Int.self, forKey: .ansatte)
        lonnsdag = try c.decodeIfPresent(Int.self, forKey: .lonnsdag)
        mvaTermin = try c.decodeIfPresent(MvaTerminType.self, forKey: .mvaTermin)
        sted = try c.decode(TownPlace.self, forKey: .sted)
        oppgaver = try c.decode([String].self, forKey: .oppgaver)
        provesak = try c.decode([String].self, forKey: .provesak)
        replikker = try c.decode(ClientLines.self, forKey: .replikker)
        // Missing in the JSON means "not a starting client".
        startklient = try c.decodeIfPresent(Bool.self, forKey: .startklient) ?? false
        status = try c.decode(PuzzleStatus.self, forKey: .status)
    }
}

/// One map square, written as a single character in `TownMap.ruter`.
public enum Tile: Character, Sendable {
    case wall = "#", floor = ".", water = "~", grass = ",", door = "D", roof = "^", counter = "="

    public var walkable: Bool {
        switch self {
        case .floor, .grass, .door: true
        case .wall, .water, .roof, .counter: false
        }
    }
}

public struct Door: Codable, Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let til: String
    public let tilX: Int
    public let tilY: Int
}

public enum PersonRole: String, Codable, Sendable {
    case klient, fagkontor, skilt, sjef, skranke, seng, folk
}

public struct FagkontorRef: Codable, Hashable, Sendable {
    public let id: String
    public let navn: String
    public let temaer: [String]
}

public struct TownPerson: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let rolle: PersonRole
    public let x: Int
    public let y: Int
    public let klient: String?
    public let fagkontor: FagkontorRef?
    public let tekst: [String]
}

public struct TownMap: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let navn: String
    public let bredde: Int
    public let hoyde: Int
    public let ruter: [String]
    public let dorer: [Door]
    public let folk: [TownPerson]
    public let fullmakt: String?

    /// The square at a position; `nil` outside the map or for a character that is no tile.
    public func tile(x: Int, y: Int) -> Tile? {
        guard y >= 0, y < ruter.count, x >= 0 else { return nil }
        let row = Array(ruter[y])
        guard x < row.count else { return nil }
        return Tile(rawValue: row[x])
    }
}

public struct TownContent: Hashable, Sendable {
    public var bransjer: [Bransje]
    public var klienter: [TownClient]
    public var kart: [TownMap]

    public static let empty = TownContent(bransjer: [], klienter: [], kart: [])

    public func map(_ id: String) -> TownMap? { kart.first { $0.id == id } }
    public func client(_ id: String) -> TownClient? { klienter.first { $0.id == id } }
    public func bransje(_ id: String) -> Bransje? { bransjer.first { $0.id == id } }

    /// Reads `bransjer.json`, `klienter/*.json` and `kart/*.json`, sorted by id. Throws the first
    /// file error; `ContentLibrary` uses `loadReporting` to keep going past a broken file.
    public static func load(folder: URL) throws -> TownContent {
        let result = loadReporting(folder: folder)
        if let first = result.errors.first { throw first }
        return result.town
    }

    /// Like `load`, but a file that cannot be read is returned as an error and the rest still load.
    static func loadReporting(folder: URL) -> (town: TownContent, errors: [TownLoadFailure]) {
        var errors: [TownLoadFailure] = []
        var bransjer: [Bransje] = []
        let bransjeFile = folder.appendingPathComponent("bransjer.json")
        if FileManager.default.fileExists(atPath: bransjeFile.path) {
            do { bransjer = try read([Bransje].self, from: bransjeFile) } catch { errors.append(TownLoadFailure(file: bransjeFile.path, underlying: error)) }
        }
        func records<T: Decodable>(_ type: T.Type, in sub: String) -> [T] {
            ContentLibrary.jsonFiles(under: folder.appendingPathComponent(sub, isDirectory: true)).compactMap { url in
                do { return try read(type, from: url) } catch { errors.append(TownLoadFailure(file: url.path, underlying: error)); return nil }
            }
        }
        let klienter = records(TownClient.self, in: "klienter").sorted { $0.id < $1.id }
        let kart = records(TownMap.self, in: "kart").sorted { $0.id < $1.id }
        return (TownContent(bransjer: bransjer.sorted { $0.id < $1.id }, klienter: klienter, kart: kart), errors)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}

struct TownLoadFailure: Error {
    let file: String
    let underlying: Error
}
