import Foundation

public enum BattlePhase: Hashable, Sendable {
    case intro, menu, moves, reading, rules
    case card(Int)
    case answer, outcome, explanation
}

/// What the app must do after a key: nothing, or one of the store calls.
public enum BattleAction: Hashable, Sendable {
    case none
    case chooseMove(Move?)
    case attack
    case flee
    case next
    case invalid(String)
}

/// The phases of one encounter on the Game Boy, driven by keys: intro pages, the 2 × 2 menu,
/// the move list, reading the task, the rule cards, the answer panel, the outcome and the
/// explanation. Pure state; the app maps `BattleAction` to `AppStore` calls.
public struct BattleFlow: Hashable, Sendable {
    public static let menu = ["KJEMP", "LES", "REGLER", "FLYKT"]
    public static let columns = 18
    public static let rows = 3

    let encounter: Encounter
    let laws: LawNames
    let cards: [RuleCard]
    public private(set) var phase: BattlePhase = .intro
    public private(set) var menuCursor = 0
    public let moveRows: [PanelRow]
    public private(set) var moveCursor = 0
    public let cardRows: [PanelRow]
    public private(set) var cardCursor = 0
    public private(set) var panel: AnswerPanel
    public private(set) var pages: [[String]] = [[]]
    public private(set) var page = 0
    public private(set) var chosenMove: Move?
    public private(set) var hasChosen = false
    private var outcome: EncounterOutcome?

    public init(encounter: Encounter, laws: LawNames, cards: [RuleCard], rates: [MVARate], attempt: PuzzleAttempt) {
        self.encounter = encounter
        self.laws = laws
        self.cards = cards
        moveRows = encounter.moves.isEmpty ? [] :
            encounter.moves.map { PanelRow.fitting(id: $0.id, $0.shortLabel(laws: laws), columns: AnswerPanel.columns) }
            + [PanelRow(id: "none", text: "Ingen regel")]
        cardRows = cards.map { PanelRow.fitting(id: $0.id, $0.tittel, columns: AnswerPanel.columns) }
        panel = AnswerPanel(puzzle: encounter.puzzle, rates: rates, attempt: attempt)
        pages = Self.paged(BattleScript.intro(encounter))
    }

    public var hasMorePages: Bool { page < pages.count - 1 }

    /// Phases where A (or a click on the dialog) moves the story on, so the dialog shows a
    /// continue marker even on its last page.
    public var awaitsContinue: Bool {
        switch phase {
        case .intro, .reading, .card, .outcome, .explanation: true
        default: false
        }
    }

    /// A click on the dialog box: the next step where the dialog is the story, else the next page.
    public mutating func clickDialog(attempt: inout PuzzleAttempt) -> BattleAction {
        if awaitsContinue { return handle(.a, attempt: &attempt) }
        turnPage()
        return .none
    }

    /// Tab, or a click in the dialog: the next page, round to the first.
    public mutating func turnPage() {
        page = hasMorePages ? page + 1 : 0
    }

    /// The store judged the attack; the dialog tells the result.
    public mutating func showOutcome(_ outcome: EncounterOutcome) {
        self.outcome = outcome
        phase = .outcome
        show(BattleScript.result(outcome, encounter: encounter))
    }

    public mutating func click(menu index: Int, attempt: inout PuzzleAttempt) -> BattleAction {
        guard phase == .menu, Self.menu.indices.contains(index) else { return .none }
        menuCursor = index
        return handle(.a, attempt: &attempt)
    }

    public mutating func click(row index: Int, attempt: inout PuzzleAttempt) -> BattleAction {
        switch phase {
        case .moves where moveRows.indices.contains(index):
            moveCursor = index
            return handle(.a, attempt: &attempt)
        case .rules where cardRows.indices.contains(index):
            cardCursor = index
            return handle(.a, attempt: &attempt)
        case .answer:
            return act(on: panel.click(row: index, attempt: &attempt))
        default:
            return .none
        }
    }

    public mutating func handle(_ key: GameKey, attempt: inout PuzzleAttempt) -> BattleAction {
        if key == .tab { turnPage(); return .none }
        // Space reads like A while the dialog tells the story; in a panel it is a typed character.
        let key = key == .character(" ") && awaitsContinue ? GameKey.a : key
        switch phase {
        case .intro:
            if key == .a || key == .b { advance(orElse: { $0.enterMenu() }) }
            return .none
        case .menu:
            return handleMenu(key)
        case .moves:
            return handleMoves(key)
        case .reading:
            if key == .b { enterMenu() } else if key == .a { advance(orElse: { $0.enterMenu() }) }
            return .none
        case .rules:
            return handleRules(key)
        case .card:
            if key == .b { enterRules() } else if key == .a { advance(orElse: { $0.enterRules() }) }
            return .none
        case .answer:
            return act(on: panel.handle(key, attempt: &attempt))
        case .outcome:
            guard key == .a else { return .none }
            if hasMorePages { page += 1; return .none }
            // A booked bilag keeps its verdict quiet: the explanation would give it away.
            // `.answered` shows the verdict like `.corrected`, so it leads to the explanation too.
            if outcome == .booked { return .next }
            enterExplanation()
            return .none
        case .explanation:
            if key == .a {
                if hasMorePages { page += 1 } else { return .next }
            }
            return .none
        }
    }

    // MARK: Phases

    private mutating func show(_ texts: [String]) {
        pages = Self.paged(texts)
        page = 0
    }

    /// Next page, or the fallback once the last page is shown.
    private mutating func advance(orElse fallback: (inout BattleFlow) -> Void) {
        if hasMorePages { page += 1 } else { fallback(&self) }
    }

    private mutating func enterMenu() {
        phase = .menu
        show(["Hva gjør du?"])
    }

    private mutating func enterRules() {
        phase = .rules
        showRulesPage()
    }

    private mutating func enterExplanation() {
        phase = .explanation
        show(BattleScript.explanation(encounter, laws: laws))
    }

    private mutating func enterAnswer() {
        phase = .answer
        showAnswerPages()
    }

    private mutating func handleMenu(_ key: GameKey) -> BattleAction {
        switch key {
        case .left where menuCursor % 2 == 1: menuCursor -= 1
        case .right where menuCursor % 2 == 0: menuCursor += 1
        case .up where menuCursor >= 2: menuCursor -= 2
        case .down where menuCursor < 2: menuCursor += 2
        case .a:
            switch menuCursor {
            case 0:
                if moveRows.isEmpty { enterAnswer() } else { phase = .moves; showMovesPage() }
            case 1:
                phase = .reading
                show([TextWrap.plain(markdown: encounter.puzzle.oppgave)])
            case 2:
                enterRules()
            default:
                return .flee
            }
        default:
            break
        }
        return .none
    }

    private mutating func handleMoves(_ key: GameKey) -> BattleAction {
        switch key {
        case .up: moveCursor = max(0, moveCursor - 1); showMovesPage()
        case .down: moveCursor = min(moveRows.count - 1, moveCursor + 1); showMovesPage()
        case .b: enterMenu()
        case .a:
            let move = moveCursor < encounter.moves.count ? encounter.moves[moveCursor] : nil
            chosenMove = move
            hasChosen = true
            enterAnswer()
            return .chooseMove(move)
        default: break
        }
        return .none
    }

    private mutating func handleRules(_ key: GameKey) -> BattleAction {
        switch key {
        case .up: cardCursor = max(0, cardCursor - 1); showRulesPage()
        case .down: cardCursor = min(max(0, cardRows.count - 1), cardCursor + 1); showRulesPage()
        case .b: enterMenu()
        case .a where cards.indices.contains(cardCursor):
            phase = .card(cardCursor)
            let card = cards[cardCursor]
            show([card.tittel, TextWrap.plain(markdown: card.body)])
        default: break
        }
        return .none
    }

    private mutating func act(on event: PanelEvent) -> BattleAction {
        switch event {
        case .none:
            let before = pages
            showAnswerPages(keepingPageWhenUnchanged: before)
            return .none
        case .attack:
            return .attack
        case .back:
            enterMenu()
            return .none
        case .invalid(let message):
            show([message])
            return .invalid(message)
        }
    }

    // MARK: Pages

    private mutating func showMovesPage() {
        show([moveRows.indices.contains(moveCursor) ? (moveRows[moveCursor].full ?? "Hvilken regel gjelder?") : "Hvilken regel gjelder?"])
    }

    private mutating func showRulesPage() {
        show([cardRows.isEmpty ? "Ingen regelkort her." : (cardRows[cardCursor].full ?? cardRows[cardCursor].text)])
    }

    /// The move used, the panel's preface (a sak's message), the highlighted row in full when it
    /// was cut, then the task text. The page stays when the pages did not change, so the learner
    /// is not thrown back to the start by every keystroke inside an entry field.
    private mutating func showAnswerPages(keepingPageWhenUnchanged before: [[String]]? = nil) {
        var texts: [String] = []
        if hasChosen { texts.append(BattleScript.moveUsed(chosenMove, laws: laws)) }
        texts += panel.preface
        if let row = panel.dialog { texts.append(row) }
        texts.append(TextWrap.plain(markdown: encounter.puzzle.oppgave))
        let fresh = Self.paged(texts)
        if fresh != before { pages = fresh; page = 0 }
    }

    static func paged(_ texts: [String]) -> [[String]] {
        let pages = texts.flatMap { TextWrap.pages(TextWrap.lines($0, columns: columns), rows: rows) }
        return pages.isEmpty ? [[]] : pages
    }
}
