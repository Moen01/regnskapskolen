import RegnskapKit
import SwiftUI

/// One region on the handheld: the client's money, the meter towards the gym leader, and the
/// rows that start a run, enter the dungeon or go back to the map.
struct RegionScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigation.self) private var navigation
    let region: Region
    @State private var cursor = GBCursor(visible: 3)
    @State private var page = 0

    private var hp: Int { store.run?.hp ?? RegionRun.hp }
    private var damage: Int { store.run?.damage ?? store.progress.game.regionDamage[region.tema] ?? 0 }
    private var gymReady: Bool { store.run?.gymReady ?? (damage >= region.damageTarget && region.gymBadge == nil) }

    private var rows: [PanelRow] {
        var rows = [PanelRow(id: "run", text: "NESTE MØTE")]
        if region.tema == "reskontro-bank" { rows.append(PanelRow(id: "dungeon", text: "DUNGEON")) }
        rows.append(PanelRow(id: "back", text: "TILBAKE"))
        return rows
    }

    private var pages: [[String]] {
        if region.gymBadge != nil { return gbPages("Gym-merket er ditt. " + region.theme.setning) }
        if gymReady, let leader = region.gymLeader { return gbPages("Gym-lederen venter: \(leader.tittel)") }
        if rows[cursor.index].id == "dungeon" { return gbPages("Dungeonen: avstem banken i sandkassen (bank-001).") }
        return gbPages(region.theme.setning.isEmpty ? region.navn : region.theme.setning)
    }

    var body: some View {
        GBScreen(onKey: handle) {
            RegionPanel(name: TextWrap.truncate(region.navn.uppercased(), to: AnswerPanel.columns),
                        hpText: "KUNDEN \(hp) kr", hp: Double(hp) / Double(RegionRun.hp),
                        gymText: "GYM \(damage)/\(region.damageTarget)", gym: region.damageTarget == 0 ? 1 : Double(damage) / Double(region.damageTarget),
                        rows: rows, cursor: cursor.index, visible: cursor.range(count: rows.count),
                        onClick: { index in cursor.set(index, count: rows.count); select() })
            GBDialog(pages: pages, page: page, typing: !AppStore.isScreenshotRun, onTurn: { page = page < pages.count - 1 ? page + 1 : 0 })
        }
        .onChange(of: cursor.index) { page = 0 }
    }

    private func handle(_ key: GameKey) {
        switch key {
        case .up: cursor.move(by: -1, count: rows.count)
        case .down: cursor.move(by: 1, count: rows.count)
        case .a: select()
        case .b: store.closeRegion()
        case .tab: page = page < pages.count - 1 ? page + 1 : 0
        default: break
        }
    }

    private func select() {
        switch rows[cursor.index].id {
        case "run":
            if store.run == nil, !region.isEmpty { store.startRun() }
        case "dungeon":
            if let bank = store.sandboxCases.first(where: { $0.id == "bank-001" }) { store.startCase(bank) }
            navigation.section = .sandbox
        default:
            store.closeRegion()
        }
    }
}

private struct RegionPanel: View {
    @Environment(\.gbScale) private var scale
    let name: String
    let hpText: String
    let hp: Double
    let gymText: String
    let gym: Double
    let rows: [PanelRow]
    let cursor: Int
    let visible: Range<Int>
    let onClick: (Int) -> Void

    var body: some View {
        GBBox(x: 4, y: 4, width: 152, height: 90, padding: 4) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText(name)
                GBText(hpText, color: GBTheme.textDim)
                GBBar(value: hp, width: 136)
                GBText(gymText, color: GBTheme.textDim)
                GBBar(value: gym, width: 136, tint: GBTheme.gymBar)
                GBList(rows: rows, cursor: cursor, visible: visible, onClick: onClick)
            }
        }
    }
}
