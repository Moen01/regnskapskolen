import Foundation

/// `LearnerProgress` as one JSON file, written atomically. A missing or corrupt file reads as empty.
public final class ProgressStore: @unchecked Sendable {
    public let url: URL
    public private(set) var lastError: String?
    /// False when the last file read had no `game` key: the learner's history predates the games and XP is seeded once.
    public private(set) var fileHadGame = true

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL { ContentLocator.applicationSupport.appendingPathComponent("fremdrift.json") }

    /// A file that does not decode is moved to `<name>.broken-<time>` before an empty progress is
    /// returned, so the next save cannot overwrite the learner's history.
    public func load() -> LearnerProgress {
        guard let data = try? Data(contentsOf: url) else { fileHadGame = true; return LearnerProgress() }
        do {
            let progress = try JSONDecoder().decode(LearnerProgress.self, from: data)
            fileHadGame = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["game"] != nil
            return progress
        } catch {
            fileHadGame = true
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.appendingPathExtension("broken-\(stamp)")
            try? FileManager.default.moveItem(at: url, to: aside)
            lastError = "Kunne ikke lese \(url.lastPathComponent) (\(error.localizedDescription)). Filen er lagt til side som \(aside.lastPathComponent); fremdriften starter på nytt."
            return LearnerProgress()
        }
    }

    public func save(_ progress: LearnerProgress) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(progress).write(to: url, options: .atomic)
    }
}
