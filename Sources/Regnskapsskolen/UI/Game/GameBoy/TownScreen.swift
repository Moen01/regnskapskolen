import RegnskapKit
import SwiftUI

/// Rubin's overworld on the handheld: the map around the player, the people, and over it the
/// dialog, the menu, Fristnav, the portfolio, the bag, the counter or a JA/NEI choice. `TownFlow` owns the
/// phases; this view draws them and sends every key to the store.
struct TownScreen: View {
    @Environment(AppStore.self) private var store
    /// Whether the dialog has typed out its page; Enter and space first reveal, then advance.
    @State private var dialogComplete = true
    @State private var reveal = 0

    var body: some View {
        GBScreen(onKey: handle) {
            if let flow = store.town, let map = store.library?.town.map(flow.state.mapId) {
                TownMapView(map: map, walker: flow.state.walker, step: store.townSteps, piles: piles(on: map, flow: flow))
                overlay(flow)
            } else {
                GBDialog(pages: [["Byen mangler", "innhold."]], page: 0, typing: false, onTurn: {})
            }
        }
        .onAppear { store.openTown() }
    }

    @ViewBuilder
    private func overlay(_ flow: TownFlow) -> some View {
        switch flow.phase {
        case .walking:
            EmptyView()
        case .dialog:
            dialog(flow, marker: true)
        case .menu:
            TownDateBox(day: flow.state.calendar.today, energy: flow.state.energy)
            TownListBox(title: nil, rows: flow.rows, cursor: flow.cursor, x: 64, width: 96, onClick: { click($0, flow) })
            dialog(flow, marker: false)
        case .fristnav, .travel, .portfolio, .bag, .cards, .counter, .archive:
            TownListBox(title: title(flow.phase), rows: flow.rows, cursor: flow.cursor, x: 4, width: 152, onClick: { click($0, flow) })
            dialog(flow, marker: false)
        case .choice:
            TownChoiceBox(rows: flow.rows, cursor: flow.cursor, onClick: { click($0, flow) })
            dialog(flow, marker: false)
        }
    }

    private func dialog(_ flow: TownFlow, marker: Bool) -> some View {
        GBDialog(pages: flow.pages, page: flow.page, typing: !AppStore.isScreenshotRun && flow.phase == .dialog,
                 tabTurns: !marker && flow.pages.count > 1, showsMarker: marker,
                 reveal: reveal, onComplete: { dialogComplete = $0 },
                 onTurn: { store.townKey(marker ? .a : .tab) })
    }

    private func title(_ phase: TownPhase) -> String {
        switch phase {
        case .fristnav: "FRISTNAV"
        case .travel: "KART"
        case .portfolio: "PORTEFØLJE"
        case .bag: "BAG"
        case .cards: "REGELKORT"
        case .archive: "ARKIV"
        default: "SKRANKE"
        }
    }

    /// Paper piles on the counter in front of every active client with bilag left to book.
    private func piles(on map: TownMap, flow: TownFlow) -> [PileSpot] {
        let state = flow.state
        let visible = Set(store.pool.map(\.id))
        return map.folk.compactMap { person in
            guard person.rolle == .klient, let id = person.klient, let client = store.library?.town.client(id),
                  let clientState = state.clients[id], clientState.status == .active,
                  map.tile(x: person.x, y: person.y + 1) == .counter,
                  Ledger.pileMonth(for: client, start: state.start, today: state.calendar.today, state: clientState, pool: visible) != nil else { return nil }
            return PileSpot(x: person.x, y: person.y + 1)
        }
    }

    private func handle(_ key: GameKey) {
        // While a dialog page is still being typed, Enter and space show the rest of it first.
        if !dialogComplete, !AppStore.isScreenshotRun, store.town?.phase == .dialog, key == .a || key == .character(" ") {
            reveal += 1
            return
        }
        store.townKey(key)
    }

    /// A click on a list row: walk the cursor there, then press A.
    private func click(_ index: Int, _ flow: TownFlow) {
        let delta = index - flow.cursor
        for _ in 0..<abs(delta) { store.townKey(delta > 0 ? .down : .up) }
        store.townKey(.a)
    }
}

/// A square on the current map.
private struct PileSpot: Hashable {
    let x: Int
    let y: Int
}

/// The map in nearest-neighbour pixels: the camera keeps the player in the middle and stops at
/// the map's edge; a room smaller than the screen sits in the middle of it.
private struct TownMapView: View {
    @Environment(\.gbScale) private var scale
    let map: TownMap
    let walker: TownWalker
    let step: Int
    let piles: [PileSpot]

    private static let tile = 16
    private static let screen = (width: 160, height: 144)
    /// The player's square on screen: column 4 of 10, row 4 of 9.
    private static let playerSquare = 4

    var body: some View {
        Canvas { context, _ in
            let camera = (x: Self.axis(walker.x, tiles: map.bredde, view: Self.screen.width),
                          y: Self.axis(walker.y, tiles: map.hoyde, view: Self.screen.height))
            context.fill(Path(CGRect(x: 0, y: 0, width: CGFloat(Self.screen.width) * scale, height: CGFloat(Self.screen.height) * scale)),
                         with: .color(GBTheme.mapVoid))
            var ground = Layers()
            for ty in 0..<map.hoyde {
                for tx in 0..<map.bredde {
                    let px = tx * Self.tile - camera.x, py = ty * Self.tile - camera.y
                    guard px > -Self.tile, px < Self.screen.width, py > -Self.tile, py < Self.screen.height, let tile = map.tile(x: tx, y: ty) else { continue }
                    plot(TileSprite.sprite(for: tile), palette: GBTheme.palette(for: tile), x: px, y: py, into: &ground, opaque: true)
                }
            }
            ground.draw(in: context)

            var figures = Layers()
            for spot in piles {
                plot(TileSprite.paperPile, palette: GBTheme.paper, x: spot.x * Self.tile - camera.x, y: spot.y * Self.tile - camera.y,
                     into: &figures, opaque: false)
            }
            for person in map.folk {
                let sprite = TileSprite.object(person.rolle) ?? TileSprite.person(person.rolle, facing: .down)
                plot(sprite, palette: GBTheme.palette(for: person.rolle), x: person.x * Self.tile - camera.x, y: person.y * Self.tile - camera.y,
                     into: &figures, opaque: false)
            }
            plot(TileSprite.player(facing: walker.facing, frame: step), palette: GBTheme.player,
                 x: walker.x * Self.tile - camera.x, y: walker.y * Self.tile - camera.y, into: &figures, opaque: false)
            figures.draw(in: context)
        }
        .frame(width: CGFloat(Self.screen.width) * scale, height: CGFloat(Self.screen.height) * scale)
    }

    /// The camera's offset in logical px along one axis.
    private static func axis(_ position: Int, tiles: Int, view: Int) -> Int {
        let size = tiles * tile
        guard size > view else { return (size - view) / 2 }
        return min(max(position * tile - playerSquare * tile, 0), size - view)
    }

    /// Adds the sprite's pixels at (x, y) to the path of their palette and slot, one rectangle per run
    /// of equal pixels in a row, cut to the screen. `opaque` draws slot 0 too (tiles cover their square).
    private func plot(_ sprite: PixelSprite, palette: SpritePalette, x: Int, y: Int, into layers: inout Layers, opaque: Bool) {
        for (row, pixels) in sprite.pixels.enumerated() {
            let sy = y + row
            guard sy >= 0, sy < Self.screen.height else { continue }
            var start = 0
            while start < pixels.count {
                let slot = pixels[start]
                var end = start + 1
                while end < pixels.count, pixels[end] == slot { end += 1 }
                let from = max(0, x + start), to = min(Self.screen.width, x + end)
                if (opaque || slot != 0), from < to {
                    layers.add(CGRect(x: CGFloat(from) * scale, y: CGFloat(sy) * scale, width: CGFloat(to - from) * scale, height: scale),
                               palette: palette, slot: slot)
                }
                start = end
            }
        }
    }
}

/// One path per palette and slot, so a screen of tiles is a few dozen fills. Palettes draw in the
/// order they first appear, so the player, added last, stays on top.
private struct Layers {
    private var order: [SpritePalette] = []
    private var paths: [SpritePalette: [Path]] = [:]

    mutating func add(_ rect: CGRect, palette: SpritePalette, slot: UInt8) {
        if paths[palette] == nil {
            order.append(palette)
            paths[palette] = Array(repeating: Path(), count: 4)
        }
        paths[palette]?[Int(slot)].addRect(rect)
    }

    func draw(in context: GraphicsContext) {
        for palette in order {
            for (slot, path) in (paths[palette] ?? []).enumerated() {
                guard let color = palette.color(UInt8(slot)) else { continue }
                context.fill(path, with: .color(color))
            }
        }
    }
}

/// The game's date and the player's energy top left while the menu is open. Two lines: «10.04 E 85»
/// on one would not fit beside the menu.
private struct TownDateBox: View {
    @Environment(\.gbScale) private var scale
    let day: DayKey
    let energy: Int

    var body: some View {
        GBBox(x: 4, y: 4, width: 56, height: 32, padding: 7) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText(String(format: "%02d.%02d", day.day, day.month))
                GBText("E \(energy)")
            }
        }
    }
}

/// A list over the map: the menu (no title), Fristnav, the portfolio, the bag or the counter.
private struct TownListBox: View {
    @Environment(\.gbScale) private var scale
    let title: String?
    let rows: [PanelRow]
    let cursor: Int
    let x: CGFloat
    let width: CGFloat
    let onClick: (Int) -> Void

    private var visibleCount: Int { title == nil ? TownFlow.mainMenu.count : AnswerPanel.visibleRows }

    private var visible: Range<Int> {
        let start = min(max(0, cursor - visibleCount + 1), max(0, rows.count - visibleCount))
        return start..<min(rows.count, start + visibleCount)
    }

    var body: some View {
        let height: CGFloat = title == nil ? CGFloat(visibleCount * 12 + 10) : 90
        GBBox(x: x, y: 4, width: width, height: height, padding: 5) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                if let title { GBText(title) }
                if rows.isEmpty {
                    GBText("Ingen her.", color: GBTheme.textDim)
                } else {
                    GBList(rows: rows, cursor: cursor, visible: visible, onClick: onClick)
                }
            }
        }
    }
}

/// JA / NEI above the dialog's right corner.
private struct TownChoiceBox: View {
    let rows: [PanelRow]
    let cursor: Int
    let onClick: (Int) -> Void

    var body: some View {
        GBBox(x: 104, y: 60, width: 56, height: 36, padding: 5) {
            GBList(rows: rows, cursor: cursor, visible: rows.indices, onClick: onClick)
        }
    }
}
