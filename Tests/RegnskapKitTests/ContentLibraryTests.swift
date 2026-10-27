import XCTest
@testable import RegnskapKit

final class ContentLibraryTests: XCTestCase {
    /// A temp content root with the repo's data files and an empty puzzle folder.
    static func scratchRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("innhold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("oppgaver/x"), withIntermediateDirectories: true)
        for name in ["kontoplan.json", "satser.json", "temaer.json"] {
            try FileManager.default.copyItem(at: ContentLocator.repoContent.appendingPathComponent(name), to: root.appendingPathComponent(name))
        }
        return root
    }

    func testLoadsRepoContent() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        XCTAssertGreaterThanOrEqual(library.puzzles.count, 3)
        XCTAssertEqual(library.topics.count, 12)
        XCTAssertTrue(library.loadErrors.isEmpty, library.loadErrors.map(\.description).joined(separator: "\n"))
        XCTAssertNotNil(library.puzzle(id: "grunnlag-001"))
        XCTAssertEqual(library.puzzles(tema: "mva").map(\.tema), Array(repeating: "mva", count: library.puzzles(tema: "mva").count))
        XCTAssertEqual(library.chart.account("1920")?.navn, "Bankinnskudd")
        XCTAssertEqual(library.rates.mva(kode: "25")?.prosent, 25)
    }

    func testBrokenFileIsReportedAndOthersLoad() throws {
        let root = try Self.scratchRoot()
        let good = ContentLocator.repoContent.appendingPathComponent("oppgaver/mva/mva-quiz-001.json")
        try FileManager.default.copyItem(at: good, to: root.appendingPathComponent("oppgaver/x/good.json"))
        try Data("{ not json".utf8).write(to: root.appendingPathComponent("oppgaver/x/bad.json"))
        let library = try ContentLibrary(root: root)
        XCTAssertEqual(library.puzzles.count, 1)
        XCTAssertEqual(library.loadErrors.count, 1)
        XCTAssertTrue(library.loadErrors[0].file.hasSuffix("bad.json"))
    }

    func testEmptyFolder() throws {
        let library = try ContentLibrary(root: try Self.scratchRoot())
        XCTAssertEqual(library.puzzles.count, 0)
        XCTAssertTrue(library.loadErrors.isEmpty)
    }

    func testExtraRootAndDraftPool() throws {
        let root = try Self.scratchRoot()
        let extra = FileManager.default.temporaryDirectory.appendingPathComponent("generert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        var draft = try Puzzle.load(url: ContentLocator.repoContent.appendingPathComponent("oppgaver/mva/mva-quiz-001.json"))
        draft.id = "utkast-1"
        draft.status = .utkast
        try draft.encoded().write(to: extra.appendingPathComponent("utkast-1.json"))
        try FileManager.default.copyItem(at: ContentLocator.repoContent.appendingPathComponent("oppgaver/grunnlag/grunnlag-001.json"), to: root.appendingPathComponent("oppgaver/x/g.json"))
        let library = try ContentLibrary(root: root, extraPuzzleRoots: [extra])
        XCTAssertEqual(library.puzzles.count, 2)
        XCTAssertEqual(library.pool(includeDrafts: false).map(\.id), ["grunnlag-001"])
        XCTAssertEqual(Set(library.pool(includeDrafts: true).map(\.id)), ["grunnlag-001", "utkast-1"])
        XCTAssertEqual(library.puzzle(id: "utkast-1")?.generert, true)
    }

    func testDuplicateIdIsALoadError() throws {
        let root = try Self.scratchRoot()
        let good = ContentLocator.repoContent.appendingPathComponent("oppgaver/mva/mva-quiz-001.json")
        try FileManager.default.copyItem(at: good, to: root.appendingPathComponent("oppgaver/x/a.json"))
        try FileManager.default.copyItem(at: good, to: root.appendingPathComponent("oppgaver/x/b.json"))
        let library = try ContentLibrary(root: root)
        XCTAssertEqual(library.puzzles.count, 1)
        XCTAssertEqual(library.loadErrors.count, 1)
        XCTAssertTrue(library.loadErrors[0].message.contains("mva-quiz-001"))
    }

    func testReloadIfChangedPicksUpFilesAddedOnDisk() throws {
        let root = try Self.scratchRoot()
        let library = try ContentLibrary(root: root)
        XCTAssertEqual(library.puzzles.count, 0)
        library.reloadIfChanged()
        XCTAssertEqual(library.puzzles.count, 0)

        try FileManager.default.copyItem(at: ContentLocator.repoContent.appendingPathComponent("oppgaver/grunnlag/grunnlag-001.json"), to: root.appendingPathComponent("oppgaver/x/g.json"))
        library.reloadIfChanged()
        XCTAssertEqual(library.puzzles.map(\.id), ["grunnlag-001"])

        var edited = try Puzzle.load(url: root.appendingPathComponent("oppgaver/x/g.json"))
        edited.id = "grunnlag-redigert"
        try edited.encoded().write(to: root.appendingPathComponent("oppgaver/x/g.json"))
        library.reloadIfChanged()
        XCTAssertEqual(library.puzzles.map(\.id), ["grunnlag-redigert"])
    }

    func testGeneratedInMemoryIsADraftUntilItsFileLands() throws {
        let root = try Self.scratchRoot()
        let library = try ContentLibrary(root: root)
        var generated = try Puzzle.load(url: ContentLocator.repoContent.appendingPathComponent("oppgaver/mva/mva-quiz-001.json"))
        generated.id = "generert-1"
        generated.status = .utkast
        library.generatedInMemory = [generated]

        XCTAssertEqual(library.pool(includeDrafts: false).map(\.id), [])
        XCTAssertEqual(library.pool(includeDrafts: true).map(\.id), ["generert-1"])
        XCTAssertEqual(library.puzzle(id: "generert-1")?.status, .utkast)

        try generated.encoded().write(to: root.appendingPathComponent("oppgaver/x/generert-1.json"))
        try library.reload()
        XCTAssertTrue(library.generatedInMemory.isEmpty)
        XCTAssertEqual(library.pool(includeDrafts: true).map(\.id), ["generert-1"])
        XCTAssertNotNil(library.puzzle(id: "generert-1"))
    }
}
