import XCTest
@testable import RegnskapKit

final class ProgressStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fremdrift-\(UUID().uuidString).json")
        let store = ProgressStore(url: url)
        XCTAssertEqual(store.load().puzzles.count, 0, "a missing file is an empty progress")
        var progress = LearnerProgress()
        let day = DayKey(string: "2026-10-26")!
        Scheduler.record(AttemptResult(puzzleId: "x", correctFirstTry: true), on: day, progress: &progress)
        progress.days[day.string] = DayRecord(day: day, set: ["x"], completed: ["x"])
        try store.save(progress)
        let loaded = store.load()
        XCTAssertEqual(loaded.puzzles["x"]?.box, 1)
        XCTAssertEqual(loaded.days[day.string]?.done, true)
        try Data("garbage".utf8).write(to: url)
        XCTAssertEqual(store.load().puzzles.count, 0, "a corrupt file is reported as empty, not a crash")
        XCTAssertNotNil(store.lastError)
    }

    func testCorruptFileIsMovedAsideSoTheNextSaveCannotDestroyIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fremdrift-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fremdrift.json")
        try Data("{ not progress".utf8).write(to: url)
        let store = ProgressStore(url: url)
        XCTAssertEqual(store.load().puzzles.count, 0)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the broken file is moved, not left for save() to overwrite")
        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("fremdrift.json.broken-") }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(kept[0]), encoding: .utf8), "{ not progress")
        try store.save(LearnerProgress())
        XCTAssertEqual(store.load().puzzles.count, 0)
    }

    func testAFileWithoutGameReadsWithEmptyGameProgress() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fremdrift-\(UUID().uuidString).json")
        try Data(#"{"puzzles":{"x":{"box":1,"attempts":1,"correct":1}},"days":{}}"#.utf8).write(to: url)
        let loaded = ProgressStore(url: url).load()
        XCTAssertEqual(loaded.puzzles["x"]?.box, 1)
        XCTAssertEqual(loaded.game, GameProgress())
    }

    func testGameProgressRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fremdrift-\(UUID().uuidString).json")
        var progress = LearnerProgress()
        progress.game.xp = 420
        progress.game.badges["lynrask"] = DayKey(string: "2026-10-27")!
        progress.game.bestScores["lynrunde"] = 1600
        progress.game.counters["mva-paa-rad"] = 3
        let store = ProgressStore(url: url)
        try store.save(progress)
        XCTAssertEqual(store.load().game, progress.game)
    }
}
