import Foundation

/// One law or regulation as the content names it, with the short form accountants write.
public struct LawName: Codable, Hashable, Sendable {
    public let navn: String
    public let kort: String?
    public let tittel: String?

    public init(navn: String, kort: String?, tittel: String?) {
        self.navn = navn; self.kort = kort; self.tittel = tittel
    }
}

/// `Innhold/lover.json`: the short names the game shows in the move list. A missing file or a law
/// without an entry falls back to the full name, so older content folders and Claude-made puzzles
/// keep working.
public struct LawNames: Hashable, Sendable {
    public let all: [LawName]
    private let byName: [String: LawName]

    public init(all: [LawName]) {
        self.all = all
        byName = Dictionary(all.map { ($0.navn, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public static let empty = LawNames(all: [])

    private struct File: Decodable {
        let lover: [LawName]
    }

    /// Empty when the file is missing. A file that exists but does not decode throws, so the
    /// library can report it.
    public static func read(url: URL) throws -> LawNames {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let data = try Data(contentsOf: url)
        return LawNames(all: try JSONDecoder().decode(File.self, from: data).lover)
    }

    /// Empty when the file is missing or broken.
    public static func load(url: URL) -> LawNames {
        (try? read(url: url)) ?? .empty
    }

    public subscript(_ lov: String) -> LawName? { byName[lov] }

    /// The short form, or the full name when none is known.
    public func short(_ lov: String) -> String { byName[lov]?.kort ?? lov }
}
