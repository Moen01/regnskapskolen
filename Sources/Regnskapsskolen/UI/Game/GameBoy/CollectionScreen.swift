import RegnskapKit
import SwiftUI

/// The collection on the handheld: badges, then the regions, then each region's creatures with
/// the highlighted one drawn beside the list. The dialog names what the cursor points at.
struct CollectionScreen: View {
    @Environment(AppStore.self) private var store
    @State private var level = Level.regions
    @State private var cursor = GBCursor(visible: ListBox.rows(in: ListBox.windowRowSpace))
    @State private var page = 0

    private enum Level: Hashable {
        case regions
        case badges
        case creatures(String)
    }

    private static let badgesId = "merker"
    /// List columns left of the creature's sprite at x 102, after the cursor.
    private static let creatureColumns = 102 / ListBox.glyph - 1
    private var regions: [Region] { store.regions.filter { !$0.isEmpty } }

    private var rows: [PanelRow] {
        switch level {
        case .regions:
            let held = store.progress.game.badges.keys.filter { Badges.badge($0) != nil }.count
            return [PanelRow(id: Self.badgesId, text: "MERKER \(held)/\(Badges.all.count)")]
                + regions.map { PanelRow.fitting(id: $0.tema, "\($0.navn) \($0.caught)/\($0.puzzles.count)", columns: ListBox.columns) }
        case .badges:
            return Badges.all.map { badge in
                let held = store.progress.game.badges[badge.id] != nil
                return PanelRow.fitting(id: badge.id, (held ? "[x] " : "[ ] ") + badge.navn, columns: ListBox.columns)
            }
        case .creatures(let tema):
            guard let region = regions.first(where: { $0.tema == tema }) else { return [] }
            return region.puzzles.map { puzzle in
                let stage = shownStage(puzzle.id)
                let leader = puzzle.id == region.gymLeader?.id ? "*" : ""
                let name = stage == .vill ? "???" : SpeciesName.name(for: puzzle.id)
                // The creature is drawn from x 102 in the box, so its row stops short of it.
                return PanelRow(id: puzzle.id, text: TextWrap.truncate("\(leader)\(name) \(stage.navn.uppercased())", to: Self.creatureColumns),
                                marked: stage != .vill)
            }
        }
    }

    private var highlighted: (puzzle: Puzzle, stage: Stage)? {
        guard case .creatures(let tema) = level, let region = regions.first(where: { $0.tema == tema }), region.puzzles.indices.contains(cursor.index) else { return nil }
        let puzzle = region.puzzles[cursor.index]
        return (puzzle, shownStage(puzzle.id))
    }

    /// A bilag booked wrong in town shows its stage from before, so the collection does not give the error away.
    private func shownStage(_ id: String) -> Stage {
        Stage.of(box: store.maskedProgress.puzzles[id]?.box)
    }

    private var pages: [[String]] {
        guard rows.indices.contains(cursor.index) else { return [[]] }
        switch level {
        case .regions:
            if cursor.index == 0 { return gbPages("Merkene du har tjent. \(store.collectionTotal) av \(store.pool.count) skapninger fanget.") }
            let region = regions[cursor.index - 1]
            return gbPages("\(region.navn): \(region.caught) av \(region.puzzles.count) fanget, \(region.mastered) mestret.")
        case .badges:
            let badge = Badges.all[cursor.index]
            let earned = store.progress.game.badges[badge.id].map { " Tjent \(NorwegianFormat.date($0.date))." } ?? ""
            return gbPages(badge.beskrivelse + earned)
        case .creatures:
            guard let (puzzle, stage) = highlighted else { return [[]] }
            if stage == .vill { return gbPages("En vill skapning. Fang den i regionen.") }
            let laws = puzzle.lov.map { "\(store.library?.laws.short($0.lov) ?? $0.lov) \($0.paragraf)" }.joined(separator: ", ")
            return gbPages(["\(puzzle.tittel) (\(stage.navn.uppercased()))", laws.isEmpty ? "Ingen regel knyttet." : laws])
        }
    }

    var body: some View {
        GBScreen(onKey: handle) {
            CollectionPanel(title: title, rows: rows, cursor: cursor.index, visible: cursor.range(count: rows.count),
                            sprite: highlighted.flatMap { $0.stage == .vill ? nil : PixelSprite.creature(seed: $0.puzzle.id) },
                            palette: GBTheme.creature(topic: highlighted?.puzzle.tema ?? ""),
                            onClick: { index in cursor.set(index, count: rows.count); select() })
            GBDialog(pages: pages, page: page, typing: !AppStore.isScreenshotRun, onTurn: { page = page < pages.count - 1 ? page + 1 : 0 })
        }
        .onChange(of: cursor.index) { page = 0 }
        .onChange(of: level) { page = 0 }
    }

    private var title: String {
        switch level {
        case .regions: "SAMLING"
        case .badges: "MERKER"
        case .creatures(let tema): TextWrap.truncate((regions.first { $0.tema == tema }?.navn ?? tema).uppercased(), to: ListBox.titleColumns)
        }
    }

    private func handle(_ key: GameKey) {
        switch key {
        case .up: cursor.move(by: -1, count: rows.count)
        case .down: cursor.move(by: 1, count: rows.count)
        case .a: select()
        case .b: back()
        case .tab: page = page < pages.count - 1 ? page + 1 : 0
        default: break
        }
    }

    private func select() {
        guard rows.indices.contains(cursor.index) else { return }
        switch level {
        case .regions:
            level = cursor.index == 0 ? .badges : .creatures(rows[cursor.index].id)
            cursor.reset()
        case .badges, .creatures:
            break
        }
    }

    private func back() {
        switch level {
        case .regions:
            store.showCollection = false
        case .badges:
            level = .regions
            cursor.reset()
        case .creatures(let tema):
            level = .regions
            cursor.set((regions.firstIndex { $0.tema == tema } ?? 0) + 1, count: rows.count)
        }
    }
}

private struct CollectionPanel: View {
    @Environment(\.gbScale) private var scale
    let title: String
    let rows: [PanelRow]
    let cursor: Int
    let visible: Range<Int>
    let sprite: PixelSprite?
    let palette: SpritePalette
    let onClick: (Int) -> Void

    var body: some View {
        GBBox(x: 4, y: 4, width: 152, height: 90, padding: 4) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    GBText(title)
                    GBList(rows: rows, cursor: cursor, visible: visible, onClick: onClick)
                }
                if let sprite {
                    GBSprite(sprite, palette: palette, pixel: 3).offset(x: 102 * scale, y: 22 * scale)
                }
            }
        }
    }
}
