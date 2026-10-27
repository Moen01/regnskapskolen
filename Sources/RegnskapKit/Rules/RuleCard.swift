import Foundation

/// A rule card from `Innhold/regler/<id>.md`: front matter with the law and a short body.
public struct RuleCard: Identifiable, Hashable, Sendable {
    public let id: String
    public let tittel: String
    public let lov: String
    public let paragrafer: [String]
    public let tema: String
    public let kilde: String?
    public let body: String

    public static func load(folder: URL) -> [RuleCard] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).flatMap { parse($0, id: url.deletingPathExtension().lastPathComponent) } }
    }

    static func parse(_ text: String, id: String) -> RuleCard? {
        let (meta, body) = FrontMatter.split(text)
        guard let tittel = meta["tittel"], let lov = meta["lov"], let tema = meta["tema"] else { return nil }
        let paragrafer = (meta["paragrafer"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return RuleCard(id: id, tittel: tittel, lov: lov, paragrafer: paragrafer, tema: tema, kilde: meta["kilde"], body: body)
    }

    /// The card as text for a prompt.
    public var promptText: String { "## \(tittel) (\(lov) \(paragrafer.joined(separator: ", ")))\n\(body)" }
}

/// `---` key: value `---` at the top of a Markdown file.
enum FrontMatter {
    static func split(_ text: String) -> (meta: [String: String], body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return ([:], text) }
        var meta: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
            meta[key] = value
        }
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (meta, body)
    }
}
