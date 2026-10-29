import Foundation

public struct ContentLoadError: Sendable, CustomStringConvertible {
    public let file: String
    public let message: String
    public var description: String { "\(file): \(message)" }
}

/// Everything under a content folder: the chart, the rates, the topics, the rule cards and every
/// puzzle under `oppgaver/` (plus extra roots, such as the app's own `generert/` folder). A file
/// that fails to decode is reported in `loadErrors` and the rest still load.
public final class ContentLibrary: @unchecked Sendable {
    public let root: URL
    public let extraPuzzleRoots: [URL]

    /// Everything loaded, swapped as one value under the lock: the app reloads on the main actor
    /// while the tutor reads from its own tasks.
    private struct State {
        var chart: ChartOfAccounts
        var rates: Rates
        var topics: [Topic]
        var puzzles: [Puzzle] = []
        var rules: [RuleCard] = []
        var laws: LawNames = .empty
        var town: TownContent = .empty
        var loadErrors: [ContentLoadError] = []
        var generatedInMemory: [Puzzle] = []
        var byId: [String: Puzzle] = [:]
        var lastSignature = ""
    }

    private let lock = NSLock()
    private var state: State

    public var chart: ChartOfAccounts { lock.withLock { state.chart } }
    public var rates: Rates { lock.withLock { state.rates } }
    public var topics: [Topic] { lock.withLock { state.topics } }
    public var puzzles: [Puzzle] { lock.withLock { state.puzzles } }
    public var rules: [RuleCard] { lock.withLock { state.rules } }
    /// Short law names from `lover.json`; empty when the folder has none.
    public var laws: LawNames { lock.withLock { state.laws } }
    /// The town from `by/`; `.empty` when the folder is missing.
    public var town: TownContent { lock.withLock { state.town } }
    public var loadErrors: [ContentLoadError] { lock.withLock { state.loadErrors } }
    /// Puzzles Claude wrote this session, visible until the next reload reads their files.
    public var generatedInMemory: [Puzzle] {
        get { lock.withLock { state.generatedInMemory } }
        set { lock.withLock { state.generatedInMemory = newValue } }
    }

    public init(root: URL, extraPuzzleRoots: [URL] = []) throws {
        self.root = root
        self.extraPuzzleRoots = extraPuzzleRoots
        state = try Self.load(root: root, extraRoots: extraPuzzleRoots, generated: [])
    }

    /// Reads everything again and swaps it in at once; a file that fails leaves the old state in place.
    public func reload() throws {
        let fresh = try Self.load(root: root, extraRoots: extraPuzzleRoots, generated: generatedInMemory)
        lock.withLock { state = fresh }
    }

    private static func load(root: URL, extraRoots: [URL], generated: [Puzzle]) throws -> State {
        var state = State(chart: try ChartOfAccounts(url: root.appendingPathComponent("kontoplan.json")),
                          rates: try Rates(url: root.appendingPathComponent("satser.json")),
                          topics: try Topics(url: root.appendingPathComponent("temaer.json")).all)
        var loaded: [Puzzle] = []
        var errors: [ContentLoadError] = []
        var seen: [String: URL] = [:]
        let main = root.appendingPathComponent("oppgaver", isDirectory: true)
        for folder in [main] + extraRoots {
            for url in jsonFiles(under: folder) {
                do {
                    let puzzle = try Puzzle.load(url: url, generert: folder != main)
                    if let first = seen[puzzle.id] {
                        errors.append(ContentLoadError(file: url.path, message: "id «\(puzzle.id)» finnes allerede i \(first.lastPathComponent)"))
                        continue
                    }
                    seen[puzzle.id] = url
                    loaded.append(puzzle)
                } catch {
                    errors.append(ContentLoadError(file: url.path, message: describe(error)))
                }
            }
        }
        state.puzzles = loaded
        state.byId = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        state.rules = RuleCard.load(folder: root.appendingPathComponent("regler", isDirectory: true))
        let lawsURL = root.appendingPathComponent("lover.json")
        do {
            state.laws = try LawNames.read(url: lawsURL)
        } catch {
            errors.append(ContentLoadError(file: lawsURL.path, message: describe(error)))
        }
        let townLoad = TownContent.loadReporting(folder: root.appendingPathComponent("by", isDirectory: true))
        state.town = townLoad.town
        errors += townLoad.errors.map { ContentLoadError(file: $0.file, message: describe($0.underlying)) }
        state.loadErrors = errors
        state.generatedInMemory = generated.filter { state.byId[$0.id] == nil }
        state.lastSignature = signature(root: root, extraRoots: extraRoots)
        return state
    }

    /// The puzzle folders' file list and modification dates, to notice edits made on disk.
    func signature() -> String { Self.signature(root: root, extraRoots: extraPuzzleRoots) }

    private static func signature(root: URL, extraRoots: [URL]) -> String {
        let roots = [root.appendingPathComponent("oppgaver", isDirectory: true), root.appendingPathComponent("regler", isDirectory: true), root.appendingPathComponent("by", isDirectory: true)] + extraRoots
        return roots.flatMap { folder -> [String] in
            (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])?
                .compactMap { $0 as? URL } ?? []).map { "\($0.lastPathComponent):\((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0)" }
        }.sorted().joined(separator: "|")
    }

    /// Reloads when a content file was added, removed or edited since the last load.
    public func reloadIfChanged() {
        let current = signature()
        guard lock.withLock({ current != state.lastSignature }) else { return }
        try? reload()
    }

    static func jsonFiles(under folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let ctx): return ctx.debugDescription
            case .keyNotFound(let key, _): return "feltet «\(key.stringValue)» mangler"
            case .typeMismatch(_, let ctx): return "feil type i «\(ctx.codingPath.map(\.stringValue).joined(separator: "."))»: \(ctx.debugDescription)"
            case .valueNotFound(_, let ctx): return "mangler verdi i «\(ctx.codingPath.map(\.stringValue).joined(separator: "."))»"
            @unknown default: return "\(decoding)"
            }
        }
        return error.localizedDescription
    }

    public var approved: [Puzzle] { puzzles.filter { $0.status == .godkjent } }

    /// What the scheduler may pick from, read as one consistent snapshot.
    public func pool(includeDrafts: Bool) -> [Puzzle] {
        lock.withLock { (includeDrafts ? state.puzzles : state.puzzles.filter { $0.status == .godkjent }) + (includeDrafts ? state.generatedInMemory : []) }
    }

    public func puzzle(id: String) -> Puzzle? { lock.withLock { state.byId[id] ?? state.generatedInMemory.first { $0.id == id } } }

    public func puzzles(tema: String, includeDrafts: Bool = true) -> [Puzzle] {
        pool(includeDrafts: includeDrafts).filter { $0.tema == tema }.sorted { ($0.vanskelighet, $0.id) < ($1.vanskelighet, $1.id) }
    }

    public func topic(_ id: String) -> Topic? { topics.first { $0.id == id } }

    public func rules(tema: String) -> [RuleCard] { rules.filter { $0.tema == tema } }

    public var deadlines: Deadlines { Deadlines(rates: rates) }
}
