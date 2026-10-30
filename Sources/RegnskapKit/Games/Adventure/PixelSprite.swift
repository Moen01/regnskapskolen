import Foundation

/// A small bitmap for the Game Boy screen. `pixels` is rows of palette slots: 0 transparent,
/// 1 outline, 2 body, 3 detail (a creature's eyes, a person's skin). Creatures are generated from the puzzle id, mirrored so they read as
/// a living thing; the player is drawn by hand.
public struct PixelSprite: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [[UInt8]]

    public init(pixels: [[UInt8]]) {
        self.pixels = pixels
        height = pixels.count
        width = pixels.first?.count ?? 0
    }

    /// 14 × 12, or 18 × 14 for a gym leader. Same seed, same creature.
    public static func creature(seed: String, large: Bool = false) -> PixelSprite {
        let width = large ? 18 : 14
        let height = large ? 14 : 12
        let half = width / 2
        var generator = SplitMix64(seed: SpeciesName.fnv1a(seed) ^ 0x5eed_5eed)

        // The left half: denser in the middle, sparse at the rim. The right half is its mirror.
        var filled = Array(repeating: Array(repeating: false, count: half), count: height)
        for y in 0..<height {
            for x in 0..<half {
                let fromAxis = Double(half - 1 - x) / Double(max(1, half - 1))
                let fromMiddle = abs(Double(y) - Double(height - 1) / 2) / (Double(height - 1) / 2)
                let probability = 0.75 - 0.45 * max(fromAxis, fromMiddle)
                filled[y][x] = Double(generator.next() % 1000) / 1000 < probability
            }
        }
        filled = largestComponent(filled)

        var pixels = Array(repeating: Array(repeating: UInt8(0), count: width), count: height)
        for y in 0..<height {
            for x in 0..<half where filled[y][x] {
                pixels[y][x] = 2
                pixels[y][width - 1 - x] = 2
            }
        }
        // Body on the grid edge becomes outline, so every body pixel is closed in on all sides.
        for y in 0..<height {
            for x in 0..<width where pixels[y][x] == 2 && (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
                pixels[y][x] = 1
            }
        }
        for y in 0..<height {
            for x in 0..<width where pixels[y][x] == 0 {
                let touchesBody = neighbours(x, y, width, height).contains { pixels[$0.1][$0.0] == 2 }
                if touchesBody { pixels[y][x] = 1 }
            }
        }
        // Two eyes: the body pixel nearest a point high in the left half, and its mirror.
        let target = (x: half - 2, y: height / 3)
        var best: (x: Int, y: Int, distance: Int)?
        for y in 0..<height {
            for x in 0..<half where pixels[y][x] == 2 {
                let distance = abs(x - target.x) + abs(y - target.y)
                if best == nil || distance < best!.distance { best = (x, y, distance) }
            }
        }
        if let eye = best {
            pixels[eye.y][eye.x] = 3
            pixels[eye.y][width - 1 - eye.x] = 3
        }
        return PixelSprite(pixels: pixels)
    }

    /// The accountant seen from behind: hair and shirt as outline colour, skin as detail colour.
    public static let player = PixelSprite(pixels: [
        "......####......",
        ".....######.....",
        "....########....",
        "....########....",
        "....########....",
        ".....#oooo#.....",
        "......oooo......",
        "....###oo###....",
        "...##########...",
        "..############..",
        "..############..",
        ".o############o.",
        ".o############o.",
        "...##########...",
        "...###....###...",
        "...###....###...",
    ].map { row in row.map { character -> UInt8 in
        switch character {
        case "#": 1
        case "o": 3
        default: 0
        }
    } })

    private static func neighbours(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> [(Int, Int)] {
        [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)].filter { (0..<width).contains($0.0) && (0..<height).contains($0.1) }
    }

    /// Keeps only the largest 4-connected blob of the half grid, so the creature is one shape.
    private static func largestComponent(_ cells: [[Bool]]) -> [[Bool]] {
        let height = cells.count
        let width = cells.first?.count ?? 0
        var label = Array(repeating: Array(repeating: -1, count: width), count: height)
        var sizes: [Int] = []
        for y in 0..<height {
            for x in 0..<width where cells[y][x] && label[y][x] < 0 {
                let id = sizes.count
                var stack = [(x, y)]
                var size = 0
                label[y][x] = id
                while let (cx, cy) = stack.popLast() {
                    size += 1
                    for (nx, ny) in neighbours(cx, cy, width, height) where cells[ny][nx] && label[ny][nx] < 0 {
                        label[ny][nx] = id
                        stack.append((nx, ny))
                    }
                }
                sizes.append(size)
            }
        }
        guard let keep = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) else { return cells }
        return (0..<height).map { y in (0..<width).map { x in label[y][x] == keep } }
    }
}
