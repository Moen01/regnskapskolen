import RegnskapKit
import SwiftUI

/// After a run: the numbers as rows, the new badges in the dialog, and the way on.
struct SummaryScreen: View {
    let summary: RunSummary
    let newBadges: [Badge]
    let onRegion: () -> Void
    let onMap: () -> Void
    @State private var cursor = GBCursor(visible: 6)
    @State private var page = 0

    private var rows: [PanelRow] {
        [
            PanelRow(id: "caught", text: "FANGET   \(summary.caught)"),
            PanelRow(id: "escaped", text: "FLYKTET  \(summary.escaped)"),
            PanelRow(id: "xp", text: "XP       +\(summary.xp)"),
            PanelRow(id: "hp", text: "KR IGJEN \(summary.hpLeft)"),
            PanelRow(id: "region", text: "TILBAKE"),
            PanelRow(id: "map", text: "KARTET"),
        ]
    }

    private var pages: [[String]] {
        var texts = [summary.hpLeft == 0 ? "Kunden byttet regnskapsfører! Regionen mistet en fjerdedel av framgangen." : "Økten er over. Framgangen er lagret."]
        if summary.gymBadge { texts.append("Gym-merket er ditt!") }
        texts += newBadges.map { "Nytt merke: \($0.navn)" }
        return gbPages(texts)
    }

    var body: some View {
        GBScreen(onKey: handle) {
            SummaryPanel(title: summary.hpLeft == 0 ? "KUNDEN GIKK" : "ØKTEN ER OVER", rows: rows, cursor: cursor.index,
                         visible: cursor.range(count: rows.count), onClick: { index in cursor.set(index, count: rows.count); select() })
            GBDialog(pages: pages, page: page, typing: !AppStore.isScreenshotRun, onTurn: { page = page < pages.count - 1 ? page + 1 : 0 })
        }
    }

    private func handle(_ key: GameKey) {
        switch key {
        case .up: cursor.move(by: -1, count: rows.count)
        case .down: cursor.move(by: 1, count: rows.count)
        case .a: select()
        case .b: onRegion()
        case .tab: page = page < pages.count - 1 ? page + 1 : 0
        default: break
        }
    }

    private func select() {
        switch rows[cursor.index].id {
        case "map": onMap()
        case "region": onRegion()
        default: break
        }
    }
}

private struct SummaryPanel: View {
    @Environment(\.gbScale) private var scale
    let title: String
    let rows: [PanelRow]
    let cursor: Int
    let visible: Range<Int>
    let onClick: (Int) -> Void

    var body: some View {
        GBBox(x: 4, y: 4, width: 152, height: 90, padding: 4) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText(title)
                GBList(rows: rows, cursor: cursor, visible: visible, onClick: onClick)
            }
        }
    }
}
