import XCTest
@testable import RegnskapKit

final class TownContentTests: XCTestCase {
    static let fixtureTown = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/by", isDirectory: true)

    func testLoadsFixtureTown() throws {
        let town = try TownContent.load(folder: Self.fixtureTown)
        XCTAssertEqual(town.bransjer.count, 2)
        XCTAssertEqual(town.klienter.count, 3)
        XCTAssertEqual(town.kart.count, 2)
        XCTAssertEqual(town.map("sentrum")?.tile(x: 0, y: 0), .wall)
        XCTAssertNil(town.map("sentrum")?.tile(x: -1, y: 0))
        XCTAssertNil(town.map("sentrum")?.tile(x: 0, y: 99))
        XCTAssertEqual(town.map("sentrum")?.tile(x: 4, y: 4), .door)
        XCTAssertTrue(Tile.door.walkable)
        XCTAssertFalse(Tile.wall.walkable)
        XCTAssertEqual(town.client("butikken")?.mvaTermin, .tomaanedlig)
        XCTAssertNil(town.client("konsulenten")?.mvaTermin)
        XCTAssertEqual(town.client("butikken")?.startklient, true)
        XCTAssertEqual(town.client("konsulenten")?.startklient, false)
        XCTAssertEqual(town.bransje("butikk")?.navn, "Butikkdrift")
        XCTAssertEqual(town.map("kontoret")?.folk.first?.rolle, .sjef)
    }

    func testMissingFolderIsEmpty() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("by-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertEqual(try TownContent.load(folder: empty), .empty)
    }

    func testBrokenClientFileIsALoadErrorNotACrash() throws {
        let root = try ContentLibraryTests.scratchRoot()
        let by = root.appendingPathComponent("by", isDirectory: true)
        try FileManager.default.createDirectory(at: by.appendingPathComponent("klienter"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixtureTown.appendingPathComponent("klienter/butikken.json"), to: by.appendingPathComponent("klienter/butikken.json"))
        try Data("{ not json".utf8).write(to: by.appendingPathComponent("klienter/ødelagt.json"))
        let library = try ContentLibrary(root: root)
        XCTAssertEqual(library.loadErrors.count, 1)
        XCTAssertEqual(library.town.klienter.count, 1)
    }

    func testLibraryWithoutTownFolderHasEmptyTown() throws {
        let library = try ContentLibrary(root: try ContentLibraryTests.scratchRoot())
        XCTAssertEqual(library.town, .empty)
        XCTAssertTrue(library.loadErrors.isEmpty)
    }
}
