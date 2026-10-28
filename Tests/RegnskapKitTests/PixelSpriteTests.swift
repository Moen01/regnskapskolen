import XCTest
@testable import RegnskapKit

final class PixelSpriteTests: XCTestCase {
    func testSizes() {
        XCTAssertEqual(PixelSprite.creature(seed: "x").width, 14)
        XCTAssertEqual(PixelSprite.creature(seed: "x").height, 12)
        XCTAssertEqual(PixelSprite.creature(seed: "x", large: true).width, 18)
        XCTAssertEqual(PixelSprite.creature(seed: "x", large: true).height, 14)
        XCTAssertEqual(PixelSprite.player.width, 16)
        XCTAssertEqual(PixelSprite.player.pixels.count, 16)
    }

    func testDeterministicAndDifferentPerSeed() {
        XCTAssertEqual(PixelSprite.creature(seed: "mva-quiz-01"), PixelSprite.creature(seed: "mva-quiz-01"))
        XCTAssertNotEqual(PixelSprite.creature(seed: "mva-quiz-01"), PixelSprite.creature(seed: "mva-quiz-02"))
    }

    func testMirrorSymmetric() {
        let s = PixelSprite.creature(seed: "lonn-sak-03")
        for row in s.pixels { XCTAssertEqual(row, Array(row.reversed())) }
    }

    func testHasBodyOutlineAndTwoEyes() {
        let s = PixelSprite.creature(seed: "grunnlag-postering-05")
        let flat = s.pixels.flatMap { $0 }
        XCTAssertGreaterThan(flat.filter { $0 == 2 }.count, 20)
        XCTAssertEqual(flat.filter { $0 == 3 }.count, 2)
        // Every body pixel touches only body, outline or eye pixels: the outline closes the shape.
        for y in 0..<s.height { for x in 0..<s.width where s.pixels[y][x] == 2 {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                let v = (0..<s.width).contains(nx) && (0..<s.height).contains(ny) ? s.pixels[ny][nx] : 0
                XCTAssertNotEqual(v, 0, "body at \(x),\(y) is open towards \(nx),\(ny)")
            }
        } }
    }
}
