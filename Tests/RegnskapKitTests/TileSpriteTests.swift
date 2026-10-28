import XCTest
@testable import RegnskapKit

final class TileSpriteTests: XCTestCase {
    private let allTiles: [Tile] = [.wall, .floor, .water, .grass, .door, .roof, .counter]
    private let allRoles: [PersonRole] = [.klient, .fagkontor, .skilt, .sjef, .skranke, .seng, .folk]
    private let allFacings: [Facing] = [.up, .down, .left, .right]

    private func assertSixteen(_ sprite: PixelSprite, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sprite.width, 16, label, file: file, line: line)
        XCTAssertEqual(sprite.height, 16, label, file: file, line: line)
        XCTAssertTrue(sprite.pixels.allSatisfy { $0.count == 16 && $0.allSatisfy { $0 <= 3 } }, label, file: file, line: line)
    }

    func testEveryTileIsSixteenBySixteen() {
        for tile in allTiles { assertSixteen(TileSprite.sprite(for: tile), "\(tile)") }
        assertSixteen(TileSprite.paperPile, "paperPile")
        for role in allRoles {
            for facing in allFacings { assertSixteen(TileSprite.person(role, facing: facing), "\(role) \(facing)") }
        }
        for facing in allFacings {
            for frame in 0..<2 { assertSixteen(TileSprite.player(facing: facing, frame: frame), "player \(facing) \(frame)") }
        }
    }

    func testPlayerHasTwoFramesPerFacing() {
        for facing in allFacings {
            XCTAssertNotEqual(TileSprite.player(facing: facing, frame: 0), TileSprite.player(facing: facing, frame: 1), "\(facing)")
            XCTAssertEqual(TileSprite.player(facing: facing, frame: 2), TileSprite.player(facing: facing, frame: 0), "frame wraps modulo 2")
        }
    }

    func testWallAndFloorDiffer() {
        XCTAssertNotEqual(TileSprite.sprite(for: .wall), TileSprite.sprite(for: .floor))
        XCTAssertEqual(Set(allTiles.map { TileSprite.sprite(for: $0) }).count, allTiles.count)
        XCTAssertNotEqual(TileSprite.person(.sjef, facing: .down), TileSprite.person(.klient, facing: .down))
        XCTAssertNotEqual(TileSprite.person(.fagkontor, facing: .down), TileSprite.person(.klient, facing: .down))
    }
}
