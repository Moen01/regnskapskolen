import RegnskapKit
import SwiftUI

/// The world on the handheld: the level, the regions as rows, and the way to the training
/// grounds and the collection. The dialog reads the highlighted region's line.
struct MapScreen: View {
    @Environment(AppStore.self) private var store
    @State private var cursor = 0
    @State private var windowStart = 0
    @State private var page = 0
    @State private var showTraining = false

    /// Rows under the two 8 px title lines of the 90 px box with 5 px padding.
    private static let visibleRows = ListBox.rows(in: 90 - 2 * 5 - 2 * (8 + 2))
    private static let trainingId = "trening"
    private static let collectionId = "samling"
    private static let backId = "tilbake"

    private var regions: [Region] { store.regions }

    private var rows: [PanelRow] {
        regions.map { region in
            // The name has the row; the dialog carries the name in full. Locked rows are dimmed.
            let count = region.isEmpty ? "" : " \(region.caught)/\(region.puzzles.count)"
            let prefix = region.gymBadge != nil ? "*" : ""
            let name = TextWrap.truncate(prefix + region.navn, to: ListBox.columns - count.count)
            return PanelRow(id: region.tema, text: name + count, full: region.navn, marked: !region.unlocked)
        } + [PanelRow(id: Self.trainingId, text: "TRENING"), PanelRow(id: Self.collectionId, text: "SAMLING"), PanelRow(id: Self.backId, text: "TILBAKE")]
    }

    private var visible: Range<Int> {
        let count = rows.count
        let start = min(windowStart, max(0, count - Self.visibleRows))
        return start..<min(count, start + Self.visibleRows)
    }

    private var pages: [[String]] {
        guard rows.indices.contains(cursor) else { return [[]] }
        let level = XP.level(for: store.progress.game.xp)
        let text: String
        if cursor < regions.count {
            let region = regions[cursor]
            if !region.unlocked { text = "\(region.navn) er låst. Fang 60 % av forrige region først." }
            else if region.isEmpty { text = "\(region.navn) er under bygging: ingen skapninger her ennå." }
            else { text = region.theme.setning.isEmpty ? region.navn : "\(region.navn): \(region.theme.setning)" }
        } else if rows[cursor].id == Self.trainingId {
            text = "Arena, Dojo og Ukens utfordring. \(level.navn), \(store.progress.game.xp) XP."
        } else if rows[cursor].id == Self.collectionId {
            text = "Samlingen: \(store.collectionTotal) av \(store.pool.count) fanget."
        } else {
            text = "Tilbake til byen."
        }
        return TextWrap.pages(TextWrap.lines(text, columns: BattleFlow.columns), rows: BattleFlow.rows)
    }

    var body: some View {
        if showTraining {
            TrainingGrounds(onBack: { showTraining = false })
        } else {
            GBScreen(onKey: handle) {
                MapPanel(levelLine: levelLine, rows: rows, cursor: cursor, visible: visible, onClick: { index in
                    cursor = index
                    follow()
                    select()
                })
                GBDialog(pages: pages, page: page, typing: !AppStore.isScreenshotRun, onTurn: { page = page < pages.count - 1 ? page + 1 : 0 })
            }
            .onChange(of: cursor) { page = 0 }
        }
    }

    private var levelLine: String {
        let level = XP.level(for: store.progress.game.xp)
        return TextWrap.truncate("\(level.navn) \(store.progress.game.xp) XP", to: ListBox.titleColumns)
    }

    private func handle(_ key: GameKey) {
        switch key {
        case .up: cursor = max(0, cursor - 1); follow()
        case .down: cursor = min(rows.count - 1, cursor + 1); follow()
        case .a: select()
        case .b: store.showTraining = false
        case .tab: page = page < pages.count - 1 ? page + 1 : 0
        default: break
        }
    }

    private func follow() {
        if cursor < windowStart { windowStart = cursor }
        if cursor >= windowStart + Self.visibleRows { windowStart = cursor - Self.visibleRows + 1 }
    }

    private func select() {
        guard rows.indices.contains(cursor) else { return }
        let id = rows[cursor].id
        if id == Self.trainingId { showTraining = true }
        else if id == Self.collectionId { store.showCollection = true }
        else if id == Self.backId { store.showTraining = false }
        else if let region = regions.first(where: { $0.tema == id }), region.unlocked, !region.isEmpty { store.openRegion(region.tema) }
    }
}

/// The map's box: title, level line, and the region list.
private struct MapPanel: View {
    @Environment(\.gbScale) private var scale
    let levelLine: String
    let rows: [PanelRow]
    let cursor: Int
    let visible: Range<Int>
    let onClick: (Int) -> Void

    var body: some View {
        GBBox(x: 4, y: 4, width: 152, height: 90, padding: 5) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText("PARAGRAFJAKTEN")
                GBText(levelLine, color: GBTheme.textDim)
                GBList(rows: rows, cursor: cursor, visible: visible, onClick: onClick)
            }
        }
    }
}

/// Arena, Dojo and the weekly challenge keep their own screens for now; this is the door to them.
private struct TrainingGrounds: View {
    @Environment(AppStore.self) private var store
    let onBack: () -> Void

    private var topics: [String] { LightningRound.topics(in: store.pool) }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionHeader(title: "Treningsplassene", subtitle: "Arena, Dojo og Ukens utfordring.")
                    Spacer()
                    Button("Tilbake til kartet", action: onBack)
                }
                HStack(alignment: .top, spacing: 12) {
                    GameCard(title: "Arena", text: "Lynrunde: 90 sekunder med quiz, mva og saker. Combo for riktige på rad.",
                             best: store.bestScore(for: .lynrunde, tema: store.lynrundeTema),
                             disabledReason: LightningRound.eligible(pool: store.pool, tema: store.lynrundeTema).isEmpty ? "Ingen oppgaver i dette temaet" : nil,
                             action: store.startLightning) {
                        Picker("Tema", selection: $store.lynrundeTema) {
                            Text("Alle temaer").tag(nil as String?)
                            ForEach(topics, id: \.self) { Text(store.topic($0)?.navn ?? $0).tag(Optional($0)) }
                        }
                    }
                    GameCard(title: "Dojo", text: "Debet eller kredit? 60 sekunder med kontoplanen. Piltaster eller D og K.",
                             best: store.bestScore(for: .debetKredit, tema: nil), disabledReason: nil, action: store.startDrill) { EmptyView() }
                    weeklyCard
                }
                if !store.newBadges.isEmpty {
                    Label("Nytt merke: " + store.newBadges.map(\.navn).joined(separator: ", "), systemImage: store.newBadges[0].symbol).foregroundStyle(Color.skole)
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .onDisappear { store.newBadges = [] }
    }

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ukens utfordring").font(.headline)
            Text("Uke \(store.todayKey.isoWeek.week): ti oppgaver, de samme for alle. Del koden med kollegaene.").font(.callout).foregroundStyle(.secondary)
            if let code = store.weeklyCode {
                Text(code).font(.body.monospacedDigit().weight(.semibold))
                Button("Kopier") { Clipboard.copy(code) }
            } else {
                Button("Spill", action: store.startWeekly).buttonStyle(.borderedProminent).tint(.skole)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
