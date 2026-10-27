import Foundation

/// `LearnerProgress` as one JSON file, written atomically. A missing or corrupt file reads as empty.
public final class ProgressStore: @unchecked Sendable {
    public let url: URL
    public private(set) var lastError: String?

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL { ContentLocator.applicationSupport.appendingPathComponent("fremdrift.json") }

    /// A file that does not decode is moved to `<name>.broken-<time>` before an empty progress is
    /// returned, so the next save cannot overwrite the learner's history.
    public func load() -> LearnerProgress {
        guard let data = try? Data(contentsOf: url) else { return LearnerProgress() }
        do {
            return try JSONDecoder().decode(LearnerProgress.self, from: data)
        } catch {
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
