import Foundation

/// Pixel art for the town, drawn as 16 × 16 string literals (one character per pixel, `0`-`3`).
/// Each thing has its own four-colour palette in the app, as on the Game Boy Color. Tiles fill
/// the whole square, so slot 0 there is a colour of the tile. Person and player sprites use
/// slot 0 as transparent, so the floor shows through. Slots: 1 outline (and hair and eyes),
/// 2 body (clothes), 3 detail (skin).
public enum TileSprite {
    public static func sprite(for tile: Tile) -> PixelSprite {
        switch tile {
        case .floor: floor
        case .wall: wall
        case .water: water
        case .grass: grass
        case .door: door
        case .roof: roof
        case .counter: counter
        }
    }

    public static func person(_ role: PersonRole, facing: Facing) -> PixelSprite {
        if role == .kaffe { return coffeeMachine }
        if role == .funn { return paperPile }
        let base = switch facing {
        case .down: personDown
        case .up: personUp
        case .left: personLeft
        case .right: mirrored(personLeft)
        }
        // Only the front and side views show a tie or glasses; from behind every role looks alike.
        guard facing != .up else { return base }
        var pixels = base.pixels
        switch role {
        case .sjef:
            let column = facing == .down ? [7, 8] : [facing == .left ? 5 : 10]
            for x in column { for y in 8...10 { pixels[y][x] = 1 } }
        case .fagkontor:
            let columns = switch facing {
            case .left: [4, 5, 6]
            case .right: [9, 10, 11]
            default: [5, 6, 8, 9]
            }
            for x in columns { pixels[4][x] = 1 }
            if facing == .down { pixels[4][7] = 1 }
        default:
            break
        }
        return PixelSprite(pixels: pixels)
    }

    /// Two walking frames per facing; `frame` is taken modulo 2.
    public static func player(facing: Facing, frame: Int) -> PixelSprite {
        let step = ((frame % 2) + 2) % 2
        switch facing {
        case .down: return parse(playerDownTop + (step == 0 ? playerLegsA : playerLegsB))
        case .up: return parse(playerUpTop + (step == 0 ? playerLegsA : playerLegsB))
        case .left: return parse(playerLeftTop + (step == 0 ? playerSideLegsA : playerSideLegsB))
        case .right: return mirrored(parse(playerLeftTop + (step == 0 ? playerSideLegsA : playerSideLegsB)))
        }
    }

    // MARK: Helpers

    private static func parse(_ rows: [String]) -> PixelSprite {
        precondition(rows.count == 16, "a sprite needs 16 rows, got \(rows.count)")
        let pixels = rows.map { row -> [UInt8] in
            precondition(row.count == 16, "a sprite row needs 16 characters: \(row)")
            return row.map { character -> UInt8 in
                if character == "." { return 0 }  // dots keep person art readable; same as 0
                guard let slot = character.wholeNumberValue, (0...3).contains(slot) else {
                    preconditionFailure("bad sprite character \(character)")
                }
                return UInt8(slot)
            }
        }
        return PixelSprite(pixels: pixels)
    }

    private static func mirrored(_ sprite: PixelSprite) -> PixelSprite {
        PixelSprite(pixels: sprite.pixels.map { Array($0.reversed()) })
    }

    // MARK: Tiles

    private static let floor = parse([
        "0000000000000000",
        "0000000000000000",
        "0000200000000000",
        "0000000000002000",
        "0000000000000000",
        "0000000000000000",
        "0200000000000000",
        "0000000020000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000200",
        "0002000000000000",
        "0000000000000000",
        "0000000020000000",
        "0000000000000000",
        "0000000000000000",
    ])

    private static let wall = parse([
        "1111211111112111",
        "1111211111112111",
        "1111211111112111",
        "2222222222222222",
        "1111111121111111",
        "1111111121111111",
        "1111111121111111",
        "2222222222222222",
        "1111211111112111",
        "1111211111112111",
        "1111211111112111",
        "2222222222222222",
        "1111111121111111",
        "1111111121111111",
        "1111111121111111",
        "2222222222222222",
    ])

    private static let water = parse([
        "2222222222222222",
        "2200222222002222",
        "2022022220220222",
        "2222222222222222",
        "2222222222222222",
        "2222002222222002",
        "2222022022222022",
        "2222222222222222",
        "2222222222222222",
        "0022222200222222",
        "2202222022022222",
        "2222222222222222",
        "2222222222222222",
        "2222200222222200",
        "2222220222222022",
        "2222222222222222",
    ])

    private static let grass = parse([
        "0000000000000000",
        "0000200000002000",
        "0002120000021200",
        "0000100000001000",
        "0000000000000000",
        "0000000200000000",
        "0000002120000000",
        "0000001000000000",
        "0020000000000200",
        "0212000000002120",
        "0010000000000100",
        "0000000000000000",
        "0000020000200000",
        "0000212002120000",
        "0000010000100000",
        "0000000000000000",
    ])

    private static let door = parse([
        "1111111111111111",
        "1222222222222221",
        "1211111111111121",
        "1211111111111121",
        "1211111111111121",
        "1211111111111121",
        "1211111111111121",
        "1211111111111121",
        "1211111111003121",
        "1211111111003121",
        "1211111111111121",
        "1211111111111121",
        "1211111111111121",
        "1211111111111121",
        "1211111111111121",
        "1111111111111111",
    ])

    private static let roof = parse([
        "1221122112211221",
        "2211221122112211",
        "2112211221122112",
        "1122112211221122",
        "1221122112211221",
        "2211221122112211",
        "2112211221122112",
        "1122112211221122",
        "1221122112211221",
        "2211221122112211",
        "2112211221122112",
        "1122112211221122",
        "1221122112211221",
        "2211221122112211",
        "2112211221122112",
        "1111111111111111",
    ])

    private static let counter = parse([
        "1111111111111111",
        "1000000000000001",
        "1000000000000001",
        "1000000000000001",
        "1000000000000001",
        "1111111111111111",
        "1222222222222221",
        "1222222222222221",
        "1222222222222221",
        "1222222222222221",
        "1222222222222221",
        "1222222222222221",
        "1222222222222221",
        "1222222222222221",
        "1222222222222221",
        "1111111111111111",
    ])

    /// A stack of documents on the floor; the client's "bilag".
    public static let paperPile = parse([
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000011111110000",
        "0000123333321000",
        "0001222222221100",
        "0011111111111210",
        "0123333333332210",
        "0122222222222210",
        "0111111111111110",
        "0013333333333210",
        "0012222222222210",
        "0011111111111110",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
    ])

    /// What stands in a sign's or the sofa's square instead of a person; nil for everyone else.
    public static func object(_ role: PersonRole) -> PixelSprite? {
        switch role {
        case .skilt: sign
        case .seng: sofa
        case .kaffe: coffeeMachine
        default: nil
        }
    }

    private static let sign = parse([
        "0000000000000000",
        "0111111111111110",
        "0122222222222210",
        "0123333333333210",
        "0122222222222210",
        "0123333333332210",
        "0122222222222210",
        "0111111111111110",
        "0000000110000000",
        "0000000110000000",
        "0000000110000000",
        "0000000110000000",
        "0000000110000000",
        "0000001111000000",
        "0000000000000000",
        "0000000000000000",
    ])

    private static let coffeeMachine = parse([
        "0000000000000000",
        "0001111111111000",
        "0012222222222100",
        "0012333333332100",
        "0012322222232100",
        "0012333333332100",
        "0012222222222100",
        "0012211221122100",
        "0012211221122100",
        "0012233333322100",
        "0012233333322100",
        "0012233113322100",
        "0012233333322100",
        "0011111111111100",
        "0000000000000000",
        "0000000000000000",
    ])

    private static let sofa = parse([
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0001111111111000",
        "0012222222222100",
        "0012222222222100",
        "0012222222222100",
        "0111111111111110",
        "1223333333333221",
        "1223333333333221",
        "1221111111111221",
        "1222222222222221",
        "1111111111111111",
        "0100000000000010",
        "0000000000000000",
        "0000000000000000",
    ])

    // MARK: People

    private static let personDown = parse([
        "................",
        ".....111111.....",
        "....11111111....",
        "....13333331....",
        "....13133131....",
        "....13333331....",
        ".....111111.....",
        "....11222211....",
        "...1122222211...",
        "...1222222221...",
        "...1222222221...",
        "...1122222211...",
        ".....122221.....",
        ".....12..21.....",
        ".....11..11.....",
        "....111..111....",
    ])

    private static let personUp = parse([
        "................",
        ".....111111.....",
        "....11111111....",
        "....11111111....",
        "....11111111....",
        "....11111111....",
        ".....111111.....",
        "....11222211....",
        "...1122222211...",
        "...1222222221...",
        "...1222222221...",
        "...1122222211...",
        ".....122221.....",
        ".....12..21.....",
        ".....11..11.....",
        "....111..111....",
    ])

    private static let personLeft = parse([
        "................",
        ".....111111.....",
        "....11111111....",
        "....11333311....",
        "....13133311....",
        "....13333311....",
        ".....133311.....",
        ".....112211.....",
        "....1122221.....",
        "....1222221.....",
        "....1222221.....",
        "....1122211.....",
        ".....12221......",
        ".....12221......",
        ".....11111......",
        "....111111......",
    ])

    // MARK: Player

    private static let playerDownTop = [
        ".....111111.....",
        "....11111111....",
        "...1111111111...",
        "....13333331....",
        "....13133131....",
        "....13333331....",
        ".....133331.....",
        "....11111111....",
        "...1121111211...",
        "...1211111121...",
        "...1211111121...",
        "...1121111211...",
    ]

    private static let playerUpTop = [
        ".....111111.....",
        "....11111111....",
        "...1111111111...",
        "....11111111....",
        "....11111111....",
        "....11111111....",
        ".....111111.....",
        "....11111111....",
        "...1121111211...",
        "...1211111121...",
        "...1211111121...",
        "...1121111211...",
    ]

    private static let playerLeftTop = [
        ".....111111.....",
        "....11111111....",
        "...1111111111...",
        "....11333311....",
        "....13133311....",
        "....13333311....",
        ".....133311.....",
        ".....111111.....",
        "....1121111.....",
        "....1211121.....",
        "....1211121.....",
        "....1121111.....",
    ]

    private static let playerLegsA = [
        ".....111111.....",
        ".....11..11.....",
        ".....11..11.....",
        "....111..111....",
    ]

    private static let playerLegsB = [
        ".....111111.....",
        "....11....11....",
        "....11....11....",
        "...111....111...",
    ]

    private static let playerSideLegsA = [
        ".....11111......",
        ".....11.11......",
        ".....11.11......",
        "....111.111.....",
    ]

    private static let playerSideLegsB = [
        ".....11111......",
        "......111.......",
        "......111.......",
        ".....1111.......",
    ]
}
