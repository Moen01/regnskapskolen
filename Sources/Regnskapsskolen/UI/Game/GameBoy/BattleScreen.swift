import RegnskapKit
import SwiftUI

/// The encounter on the handheld: the creature and the learner face to face, the dialog box,
/// and over the field the menu, the move list, the rule cards or the answer panel. `BattleFlow`
/// owns the phases; this view draws them and maps its actions onto the host.
struct BattleScreen: View {
    let host: BattleHost
    /// The flow for one creature; a creature with another id gets a fresh one.
    @State private var battle: Battle?
    /// Counts the misses, so each one shakes the screen once.
    @State private var misses = 0
    /// The voucher line that is hitting right now, while the hits play.
    @State private var hitLine: Int?
    /// Whether the dialog has typed out its page; Enter and space first reveal, then advance.
    @State private var dialogComplete = true
    @State private var reveal = 0

    private struct Battle: Hashable {
        let id: String
        var flow: BattleFlow
    }

    /// The flow for the creature in front of the learner, built on the spot when none is kept
    /// yet (so a first render, including a screenshot, shows the intro).
    private var flow: BattleFlow? {
        guard let encounter = host.encounter() else { return nil }
        let library = host.library()
        if let battle, battle.id == encounter.puzzle.id { return battle.flow }
        return BattleFlow(encounter: encounter,
                          laws: library?.laws ?? .empty,
                          cards: library?.rules(tema: encounter.puzzle.tema) ?? [],
                          rates: library?.rates.mvaSatser ?? [],
                          attempt: host.session()?.attempt ?? .empty(for: encounter.puzzle.kind))
    }

    var body: some View {
        GBScreen(onKey: handle) {
            if let encounter = host.encounter(), let flow {
                BattleField(encounter: encounter, stage: host.stage() ?? encounter.stageBefore, hp: host.hp(),
                            species: SpeciesName.name(for: encounter.puzzle.id), caught: isCaught)
                switch flow.phase {
                case .moves:
                    ListPanel(title: "HVILKEN REGEL?", rows: flow.moveRows, cursor: flow.moveCursor, onClick: { index in click(row: index) })
                case .rules:
                    ListPanel(title: "REGELKORT", rows: flow.cardRows, cursor: flow.cardCursor, onClick: { index in click(row: index) })
                case .answer:
                    AnswerPanelView(panel: flow.panel, hitLine: hitLine, onClick: { index in click(row: index) })
                default:
                    EmptyView()
                }
                if flow.phase == .menu {
                    BattleMenu(cursor: flow.menuCursor, onClick: { index in click(menu: index) })
                } else {
                    GBDialog(pages: flow.pages, page: flow.page, typing: !AppStore.isScreenshotRun,
                             tabTurns: flow.phase == .answer && flow.pages.count > 1, showsMarker: flow.awaitsContinue,
                             reveal: reveal, onComplete: { dialogComplete = $0 }, onTurn: clickDialog)
                }
            }
        }
        .gbFlash(trigger: host.encounter()?.puzzle.id)
        .gbShake(trigger: misses)
    }

    /// Caught, and the dialog has moved on to say so: the creature shrinks away.
    private var isCaught: Bool {
        guard case .caught = host.outcome(), let phase = flow?.phase else { return false }
        return phase == .outcome || phase == .explanation
    }

    private func handle(_ key: GameKey) {
        // While the page is still being typed, Enter and space show the rest of it; the next press moves on.
        if !dialogComplete, !AppStore.isScreenshotRun, key == .a || key == .character(" "), flow?.awaitsContinue == true {
            reveal += 1
            return
        }
        drive { flow, attempt in flow.handle(key, attempt: &attempt) }
    }

    private func click(row index: Int) {
        drive { flow, attempt in flow.click(row: index, attempt: &attempt) }
    }

    private func click(menu index: Int) {
        drive { flow, attempt in flow.click(menu: index, attempt: &attempt) }
    }

    private func clickDialog() {
        if !dialogComplete, !AppStore.isScreenshotRun { reveal += 1; return }
        drive { flow, attempt in flow.clickDialog(attempt: &attempt) }
    }

    /// Runs one step of the flow against the session's attempt, keeps both, and acts on the result.
    private func drive(_ step: (inout BattleFlow, inout PuzzleAttempt) -> BattleAction) {
        guard let encounter = host.encounter(), var current = flow else { return }
        var attempt = host.session()?.attempt ?? .empty(for: encounter.puzzle.kind)
        let action = step(&current, &attempt)
        host.setAttempt(attempt)
        battle = Battle(id: encounter.puzzle.id, flow: current)
        act(action)
    }

    private func act(_ action: BattleAction) {
        switch action {
        case .none, .invalid:
            break
        case .chooseMove(let move):
            host.choose(move)
        case .attack:
            host.attack()
            guard let outcome = host.outcome() else { return }
            if case .escaped = outcome { misses += 1 }
            // A correct voucher lands one hit per line before the dialog tells the result.
            if case .caught = outcome, case .posting(let lines) = host.session()?.attempt ?? .quiz(nil), !AppStore.isScreenshotRun {
                Task { @MainActor in
                    for index in lines.indices {
                        hitLine = index
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                    hitLine = nil
                    battle?.flow.showOutcome(outcome)
                }
            } else {
                battle?.flow.showOutcome(outcome)
            }
        case .flee:
            host.flee()
        case .next:
            host.next()
        }
    }
}

/// The creature top right on its platform with its nameplate, the learner bottom left with the
/// client's money.
private struct BattleField: View {
    @Environment(\.gbScale) private var scale
    let encounter: Encounter
    let stage: Stage
    let hp: Int?
    let species: String
    let caught: Bool

    private var creature: SpritePalette { GBTheme.creature(topic: encounter.puzzle.tema) }

    var body: some View {
        GBBox(x: 4, y: 6, width: 96, height: 30, padding: 3) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText(TextWrap.truncate(species, to: 11))
                GBText(":L\(encounter.puzzle.vanskelighet) \(stage.navn.uppercased())", color: GBTheme.textDim)
                HStack(spacing: 2 * scale) {
                    ForEach(1...4, id: \.self) { box in
                        Rectangle().fill(box <= stage.rawValue ? GBTheme.stageOn : GBTheme.stageOff).frame(width: 8 * scale, height: 3 * scale)
                    }
                }
            }
        }
        GBAt(x: 100, y: 46) { Ellipse().fill(GBTheme.platform).frame(width: 56 * scale, height: 6 * scale) }
        if encounter.isGymLeader {
            GBAt(x: 102, y: 6) { GBSprite(PixelSprite.creature(seed: encounter.puzzle.id, large: true), palette: creature, pixel: 3) }
                .gbSlideIn(trigger: encounter.puzzle.id).gbShrink(when: caught)
        } else {
            GBAt(x: 108, y: 10) { GBSprite(PixelSprite.creature(seed: encounter.puzzle.id), palette: creature, pixel: 3) }
                .gbSlideIn(trigger: encounter.puzzle.id).gbShrink(when: caught)
        }
        GBAt(x: 12, y: 46) { GBSprite(PixelSprite.player, palette: GBTheme.player, pixel: 3) }
        if let hp {
            // Three 8 px rows, two 2 px gaps and 3 px padding top and bottom: 34 px, so the text stays inside the border.
            GBBox(x: 62, y: 60, width: 94, height: 34, padding: 3) {
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
                    GBText("Ingen her.", color: GBTheme.textDim)
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
