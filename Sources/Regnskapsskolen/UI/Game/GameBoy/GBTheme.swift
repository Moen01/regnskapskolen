import RegnskapKit
import SwiftUI

/// A sprite's four colours, one per slot, as on the Game Boy Color: 0 transparent (a tile's own
/// ground colour), 1 outline, 2 body, 3 detail.
struct SpritePalette: Hashable {
    let slots: [Color?]

    init(_ slot0: Color?, _ slot1: Color, _ slot2: Color, _ slot3: Color) {
        slots = [slot0, slot1, slot2, slot3]
    }

    /// A palette for a sprite drawn over something: slot 0 lets the ground show through.
    init(outline: Color, body: Color, detail: Color) {
        self.init(nil, outline, body, detail)
    }

    func color(_ slot: UInt8) -> Color? {
        slots.indices.contains(Int(slot)) ? slots[Int(slot)] : nil
    }
}

/// Every colour of the game in one place, like CSS variables: change a value here and every
/// screen follows. Game Boy Color style: saturated but not neon, outlines dark enough to read
/// against the floor and the grass, and text at least 4.5 : 1 against its box.
/// No other file under `UI/Game/GameBoy` writes a colour literal.
enum GBTheme {
    // MARK: Screen and boxes

    /// Behind the battle field and the menus.
    static let screen = hex(0xE8F0D8)
    /// The handheld around the screen.
    static let bezel = hex(0x3B3B3B)
    /// Outside a map smaller than the screen.
    static let mapVoid = hex(0x181830)
    /// The flash when a creature appears (drawn with `.difference`, so white inverts).
    static let flash = hex(0xFFFFFF)

    static let boxFill = hex(0xF8F8F0)
    static let boxBorder = hex(0x283878)
    static let text = hex(0x181830)
    /// Second lines, locked or done rows, hints.
    static let textDim = hex(0x4A5878)
    /// The ▶ in front of the chosen row.
    static let cursor = hex(0xC02838)
    /// A row drawn inverted: the voucher line that just hit.
    static let highlight = boxBorder
    static let highlightText = boxFill

    static let dialogFill = hex(0xFFFFFF)
    static let dialogText = text

    // MARK: Bars and the battle field

    static let hpHigh = hex(0x2E9A40)
    static let hpMid = hex(0xB87800)
    static let hpLow = hex(0xD03028)
    /// The meter towards the gym leader.
    static let gymBar = hex(0x8848B8)
    /// The four boxes of a creature's stage: reached and not yet.
    static let stageOn = boxBorder
    static let stageOff = hex(0xC8D0E0)
    /// The platform under the creature.
    static let platform = hex(0xA8C890)

    /// The bar's colour for a share of the client's money.
    static func hp(_ value: Double) -> Color {
        value > 0.5 ? hpHigh : value > 0.2 ? hpMid : hpLow
    }

    // MARK: Tiles

    static let floor = SpritePalette(hex(0xE8DCB8), hex(0x7A6440), hex(0xB8A07C), hex(0xF8F0D8))
    static let wall = SpritePalette(hex(0xCDB89A), hex(0x9A4E3C), hex(0xCDB89A), hex(0x5A2A20))
    static let water = SpritePalette(hex(0xC8E8F8), hex(0x183C78), hex(0x3878C8), hex(0x88B8E8))
    static let grass = SpritePalette(hex(0x88C860), hex(0x2E6B30), hex(0x5AA040), hex(0xC8E890))
    static let door = SpritePalette(hex(0xF8D860), hex(0x5A3018), hex(0xB07038), hex(0xA07818))
    static let roof = SpritePalette(hex(0xE88870), hex(0x7A2438), hex(0xC0443C), hex(0xE88870))
    static let counter = SpritePalette(hex(0xE8C890), hex(0x5A3418), hex(0xA86A34), hex(0xF0DCB0))
    /// The client's bilag on the counter.
    static let paper = SpritePalette(outline: hex(0x404058), body: hex(0xF8F8F0), detail: hex(0x88A0D0))

    static func palette(for tile: Tile) -> SpritePalette {
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

    // MARK: People and things in town

    private static let skin = hex(0xF8C898)
    private static let skinDark = hex(0xC88C60)

    /// A dark crimson suit with red sleeves: the one figure on the map in red.
    static let player = SpritePalette(outline: hex(0x6E1A28), body: hex(0xD83C3C), detail: skin)

    static func palette(for role: PersonRole) -> SpritePalette {
        switch role {
        case .klient: SpritePalette(outline: hex(0x1C4428), body: hex(0x3C9A50), detail: skin)
        case .fagkontor: SpritePalette(outline: hex(0x2E1E4A), body: hex(0x7A50B0), detail: skinDark)
        case .sjef: SpritePalette(outline: hex(0x141E40), body: hex(0x34509C), detail: skin)
        case .skranke: SpritePalette(outline: hex(0x10403E), body: hex(0x2A9A9A), detail: skin)
        case .folk: SpritePalette(outline: hex(0x5A2C10), body: hex(0xD8782C), detail: skinDark)
        case .kundesak: SpritePalette(outline: hex(0x4E1630), body: hex(0xC8487C), detail: skin)
        case .skilt: SpritePalette(outline: hex(0x5A3418), body: hex(0xC89058), detail: hex(0xF0E0B0))
        case .seng: SpritePalette(outline: hex(0x202850), body: hex(0x4058A8), detail: hex(0x88A0E0))
        case .kaffe: SpritePalette(outline: hex(0x282830), body: hex(0x8890A0), detail: hex(0xC84030))
        }
    }

    // MARK: Creatures

    /// A creature's palette from its region's colour name (`RegionTheme.farge`), so a mva
    /// creature and a payroll creature differ at a glance.
    static func palette(forCreature tema: String) -> SpritePalette {
        switch tema {
        case "skole": SpritePalette(outline: hex(0x123C34), body: hex(0x3AA08A), detail: hex(0xF8F0C8))
        case "debet": SpritePalette(outline: hex(0x142C5C), body: hex(0x3C78D8), detail: hex(0xF8E870))
        case "kredit": SpritePalette(outline: hex(0x4E2410), body: hex(0xD87830), detail: hex(0xF8F0C8))
        case "ok": SpritePalette(outline: hex(0x1C4418), body: hex(0x58B048), detail: hex(0xF8E870))
        case "warn": SpritePalette(outline: hex(0x5A3C08), body: hex(0xE0B030), detail: hex(0xC83020))
        case "orange": SpritePalette(outline: hex(0x5A1810), body: hex(0xE85838), detail: hex(0xF8E870))
        default: SpritePalette(outline: hex(0x303040), body: hex(0x9090A0), detail: hex(0xF8F8F8))
        }
    }

    /// The creature palette for a puzzle's topic.
    static func creature(topic: String) -> SpritePalette {
        palette(forCreature: Regions.themes[topic]?.farge ?? "secondary")
    }

    // MARK: Helpers

    /// `0xRRGGBB` as an sRGB colour.
    private static func hex(_ value: UInt32) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}
