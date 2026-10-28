import RegnskapKit
import SwiftUI

/// The encounter on the handheld: the creature and the learner face to face, the dialog box,
/// and over the field the menu, the move list, the rule cards or the answer panel. `BattleFlow`
/// owns the phases; this view draws them and maps its actions onto the store.
struct BattleScreen: View {
    @Environment(AppStore.self) private var store
    /// The flow for one creature; a creature with another id gets a fresh one.
    @State private var battle: Battle?

    private struct Battle: Hashable {
        let id: String
        var flow: BattleFlow
    }

    /// The flow for the creature in front of the learner, built on the spot when none is kept
    /// yet (so a first render, including a screenshot, shows the intro).
    private var flow: BattleFlow? {
        guard let encounter = store.run?.current else { return nil }
        if let battle, battle.id == encounter.puzzle.id { return battle.flow }
        return BattleFlow(encounter: encounter,
                          laws: store.library?.laws ?? .empty,
                          cards: store.library?.rules(tema: encounter.puzzle.tema) ?? [],
                          rates: store.library?.rates.mvaSatser ?? [],
                          attempt: store.encounterSession?.attempt ?? .empty(for: encounter.puzzle.kind))
    }

    var body: some View {
        GBScreen(onKey: handle) {
            if let run = store.run, let encounter = run.current, let flow {
                BattleField(encounter: encounter, hp: run.hp, species: SpeciesName.name(for: encounter.puzzle.id))
                switch flow.phase {
                case .moves:
                    ListPanel(title: "HVILKEN REGEL?", rows: flow.moveRows, cursor: flow.moveCursor, onClick: { index in click(row: index) })
                case .rules:
                    ListPanel(title: "REGELKORT", rows: flow.cardRows, cursor: flow.cardCursor, onClick: { index in click(row: index) })
                case .answer:
                    AnswerPanelView(panel: flow.panel, onClick: { index in click(row: index) })
                default:
                    EmptyView()
                }
                if flow.phase == .menu {
                    BattleMenu(cursor: flow.menuCursor, onClick: { index in click(menu: index) })
                } else {
                    GBDialog(pages: flow.pages, page: flow.page, typing: !AppStore.isScreenshotRun,
                             tabTurns: flow.phase == .answer && flow.pages.count > 1, onTurn: turnPage)
                }
            }
        }
    }

    private func handle(_ key: GameKey) {
        drive { flow, attempt in flow.handle(key, attempt: &attempt) }
    }

    private func click(row index: Int) {
        drive { flow, attempt in flow.click(row: index, attempt: &attempt) }
    }

    private func click(menu index: Int) {
        drive { flow, attempt in flow.click(menu: index, attempt: &attempt) }
    }

    private func turnPage() {
        drive { flow, _ in flow.turnPage(); return .none }
    }

    /// Runs one step of the flow against the session's attempt, keeps both, and acts on the result.
    private func drive(_ step: (inout BattleFlow, inout PuzzleAttempt) -> BattleAction) {
        guard let encounter = store.run?.current, var current = flow else { return }
        var attempt = store.encounterSession?.attempt ?? .empty(for: encounter.puzzle.kind)
        let action = step(&current, &attempt)
        store.encounterSession?.attempt = attempt
        battle = Battle(id: encounter.puzzle.id, flow: current)
        act(action)
    }

    private func act(_ action: BattleAction) {
        switch action {
        case .none, .invalid:
            break
        case .chooseMove(let move):
            store.chooseMove(move)
        case .attack:
            store.answerEncounter()
            if case .result(let outcome) = store.run?.phase { battle?.flow.showOutcome(outcome) }
        case .flee:
            store.endRun()
        case .next:
            store.proceedEncounter()
        }
    }
}

/// The creature top right on its platform with its nameplate, the learner bottom left with the
/// client's money.
private struct BattleField: View {
    @Environment(\.gbScale) private var scale
    let encounter: Encounter
    let hp: Int
    let species: String

    private var stage: Stage { encounter.stageBefore }

    var body: some View {
        GBBox(x: 4, y: 6, width: 96, height: 30, padding: 3) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText(TextWrap.truncate(species, to: 11))
                GBText(":L\(encounter.puzzle.vanskelighet) \(stage.navn.uppercased())", color: GBPalette.dark)
                HStack(spacing: 2 * scale) {
                    ForEach(1...4, id: \.self) { box in
                        Rectangle().fill(box <= stage.rawValue ? GBPalette.darkest : GBPalette.light).frame(width: 8 * scale, height: 3 * scale)
                    }
                }
            }
        }
        GBAt(x: 100, y: 46) { Ellipse().fill(GBPalette.light).frame(width: 56 * scale, height: 6 * scale) }
        if encounter.isGymLeader {
            GBAt(x: 102, y: 6) { GBSprite(PixelSprite.creature(seed: encounter.puzzle.id, large: true), pixel: 3) }
        } else {
            GBAt(x: 108, y: 10) { GBSprite(PixelSprite.creature(seed: encounter.puzzle.id), pixel: 3) }
        }
        GBAt(x: 12, y: 46) { GBSprite(PixelSprite.player, pixel: 3) }
        GBBox(x: 62, y: 60, width: 94, height: 32, padding: 3) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText("KUNDEN")
                HStack(spacing: 2 * scale) {
                    GBText("HP:")
                    GBBar(value: Double(hp) / Double(RegionRun.hp), width: 58)
                }
                HStack { Spacer(minLength: 0); GBText("\(hp)/\(RegionRun.hp)") }
            }
        }
    }
}

/// The move list or the rule cards over the field.
private struct ListPanel: View {
    @Environment(\.gbScale) private var scale
    let title: String
    let rows: [PanelRow]
    let cursor: Int
    let onClick: (Int) -> Void

    private var visible: Range<Int> {
        let start = min(max(0, cursor - AnswerPanel.visibleRows + 1), max(0, rows.count - AnswerPanel.visibleRows))
        return start..<min(rows.count, start + AnswerPanel.visibleRows)
    }

    var body: some View {
        GBBox(x: 4, y: 4, width: 152, height: 90, padding: 4) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText(title)
                if rows.isEmpty {
                    GBText("Ingen her.", color: GBPalette.dark)
                } else {
                    GBList(rows: rows, cursor: cursor, visible: visible, onClick: onClick)
                }
            }
        }
    }
}

/// KJEMP · LES · REGLER · FLYKT in the dialog box, two by two.
private struct BattleMenu: View {
    @Environment(\.gbScale) private var scale
    let cursor: Int
    let onClick: (Int) -> Void

    var body: some View {
        GBBox(x: 0, y: 96, width: 160, height: 48, padding: 0) {
            VStack(alignment: .leading, spacing: 4 * scale) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            Button { onClick(index) } label: {
                                HStack(spacing: 0) {
                                    GBText(index == cursor ? "▶" : " ").frame(width: 8 * scale)
                                    GBText(BattleFlow.menu[index])
                                }
                                .frame(width: 72 * scale, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 10 * scale)
            .padding(.leading, 8 * scale)
        }
    }
}
