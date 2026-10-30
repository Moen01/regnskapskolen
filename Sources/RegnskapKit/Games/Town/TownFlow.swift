import Foundation

public enum TownPhase: Hashable, Sendable {
    case walking, dialog, menu, fristnav, travel, portfolio, bag, cards, counter, choice, archive
}

/// What the app must do after a key. The flow never spends calendar actions itself: the app
/// decides which of these cost time.
public enum TownAction: Hashable, Sendable {
    case none
    /// The player moved one square. Turning on the spot and walking into a wall are `.none`.
    case walked
    case enteredDoor
    case startBilag(client: String)
    case startCorrection(client: String, month: MonthKey)
    /// A correction over only the errors the client found itself.
    case fixDiscovered(client: String)
    case startTrial(client: String)
    case startFagkontor(FagkontorRef)
    /// A customer case from a person in town.
    case startCase(client: String, puzzle: String)
    /// A clean month was closed at the counter; the player has read the dialog that says so.
    case closedMonth(client: String, month: MonthKey)
    case deliver(client: String, kind: DeadlineKind)
    case sleep
    case save
    case openTraining
    case openCollection
    /// The player chose to open a sandbox case from its folder in town. Free.
    case openSandbox(caseId: String)
}

/// The town on the Game Boy, driven by keys: walking, talking (dialog pages and JA/NEI choices),
/// the main menu, Fristnav, the portfolio and the counter. Pure state, like `BattleFlow`; the app
/// draws `phase`, `pages` and `rows` and performs the returned `TownAction`.
public struct TownFlow: Hashable, Sendable {
    public static let mainMenu = ["FRISTNAV", "PORTEFØLJE", "BAG", "SAMLING", "TRENING", "LAGRE"]
    public static let columns = DialogBox.columns
    public static let rows = DialogBox.rows
    /// List rows leave one column for the cursor.
    public static let rowColumns = ListBox.columns
    static let choiceRows = [PanelRow(id: "ja", text: "JA"), PanelRow(id: "nei", text: "NEI")]

    let content: TownContent
    let deadlines: Deadlines
    let pool: Set<String>
    let regions: [Region]
    let damage: [String: Int]
    let badges: Set<String>
    let ruleCards: [RuleCard]
    /// Settable so the app can write back what a bilag run, a trial or the calendar changed.
    public var state: TownState
    public private(set) var phase: TownPhase = .walking
    public private(set) var pages: [[String]] = [[]]
    public private(set) var page = 0
    public internal(set) var rows: [PanelRow] = []
    public private(set) var cursor = 0
    /// What the last dialog page leads to; in `.choice`, what JA does.
    var then: Followup = .walk
    /// The counter's tasks, one per row.
    var counterTasks: [CounterTask] = []

    enum Followup: Hashable, Sendable {
        case walk
        case action(TownAction)
        case choice(prompt: String, yes: ChoiceYes)
    }

    enum ChoiceYes: Hashable, Sendable {
        case sleep
        case trial(client: String)
        case fagkontor(FagkontorRef)
        case kundesak(client: String, puzzle: String)
        case sandbox(caseId: String)
    }

    enum CounterTask: Hashable, Sendable {
        case fixDiscovered(client: String)
        case close(client: String, month: MonthKey)
        case deliver(client: String, kind: DeadlineKind)
    }

    /// `badges` are the earned badge keys (`TownTrials.badgeKey`); `ruleCards` are the library's
    /// cards, for the titles on the needs card.
    public init(content: TownContent, state: TownState, deadlines: Deadlines, pool: Set<String>, regions: [Region],
                damage: [String: Int], badges: Set<String> = [], ruleCards: [RuleCard] = []) {
        self.content = content
        self.state = state
        self.deadlines = deadlines
        self.pool = pool
        self.regions = regions
        self.damage = damage
        self.badges = badges
        self.ruleCards = ruleCards
    }

    public var hasMorePages: Bool { page < pages.count - 1 }

    public mutating func key(_ key: GameKey) -> TownAction {
        if key == .b {
            walk()
            return .none
        }
        switch phase {
        case .walking:
            return handleWalking(key)
        case .dialog:
            // Space reads like A while the dialog tells the story.
            guard key == .a || key == .tab || key == .character(" ") else { return .none }
            if hasMorePages { page += 1; return .none }
            return follow(then)
        case .menu, .fristnav, .travel, .portfolio, .bag, .cards, .counter, .choice, .archive:
            return handleList(key)
        }
    }

    // MARK: Walking

    private mutating func handleWalking(_ key: GameKey) -> TownAction {
        guard let map = content.map(state.mapId) else {
            if key == .a { openMenu() }
            return .none
        }
        let before = state.walker
        switch state.walker.step(key, on: map) {
        case .moved:
            return .walked
        case .turned, .blocked:
            return .none
        case .door(let door):
            guard TownDistricts.isOpen(door.til, content: content, fullmakter: state.fullmakter) else {
                // The step already moved the walker onto the gate square; the gate does not open.
                state.walker = before
                let name = TownDistricts.district(of: door.til, in: content)?.navn ?? door.til
                return say(["Veien er stengt.", "Du trenger fullmakt til \(name)."])
            }
            state.mapId = door.til
            state.walker = TownWalker(x: door.tilX, y: door.tilY, facing: state.walker.facing)
            return .enteredDoor
        case .talk(let person):
            return talk(to: person)
        case .nothing:
            if key == .a { openMenu() }
            return .none
        }
    }

    /// Internal so tests can talk to every person without walking up to them.
    mutating func talk(to person: TownPerson) -> TownAction {
        switch person.rolle {
        case .skilt, .folk, .sjef:
            return say(person.tekst)
        case .seng:
            return say(person.tekst, then: .choice(prompt: "Sove?", yes: .sleep))
        case .fagkontor:
            return talkToFagkontor(person)
        case .klient:
            return talkToClient(person)
        case .skranke:
            return openCounter()
        case .kaffe:
            return takeCoffee()
        case .kundesak:
            return talkAboutCase(person)
        case .funn:
            return findCard(person)
        case .arkiv:
            return openArchive()
        case .sandkasse:
            return talkToSandbox(person)
        }
    }

    private mutating func talkToClient(_ person: TownPerson) -> TownAction {
        guard let id = person.klient, let client = content.client(id) else { return say(person.tekst) }
        var clientState = state.clients[id] ?? .fresh(.prospect)
        let lines = client.replikker
        switch clientState.status {
        case .prospect:
            // The first talk tells how the business runs; that is what opens its needs card.
            let first = !clientState.met
            clientState.met = true
            state.clients[id] = clientState
            return say(first ? lines.hilsen + lines.drift : lines.hilsen, then: .choice(prompt: "Prøvesak?", yes: .trial(client: id)))
        case .active:
            // The start client is active without a first talk; it still tells how it runs once.
            let intro = clientState.met ? [] : lines.hilsen + lines.drift
            clientState.met = true
            state.clients[id] = clientState
            // R1: the oldest month with bilag left, not only this month.
            let month = Ledger.pileMonth(for: client, start: state.start, today: state.calendar.today, state: clientState, pool: pool)
            return month == nil ? say(intro + lines.tomHaug) : say(intro + lines.haug, then: .action(.startBilag(client: id)))
        case .parked:
            return say(["Vi venter i arkivet ditt."])
        case .archived:
            return say(lines.hilsen + ["Vi har funnet et annet kontor."], then: .choice(prompt: "Prøvesak?", yes: .trial(client: id)))
        }
    }

    /// A person with a question for an active client. Answered once; then only the talk is left.
    private mutating func talkAboutCase(_ person: TownPerson) -> TownAction {
        guard let id = person.klient, let puzzle = person.oppgave else { return say(person.tekst) }
        guard let clientState = state.clients[id], clientState.status == .active else { return say(["Jeg er ikke kunde hos deg."]) }
        guard !clientState.casesDone.contains(puzzle), pool.contains(puzzle) else { return say(person.tekst) }
        return say(person.tekst, then: .choice(prompt: "Hjelpe nå?", yes: .kundesak(client: id, puzzle: puzzle)))
    }

    /// A folder with a sandbox case. Once the case is cleared, only a word is left.
    private mutating func talkToSandbox(_ person: TownPerson) -> TownAction {
        guard let caseId = person.sandkasse else { return say(person.tekst) }
        if state.sandboxCleared.contains(caseId) { return say(["Denne saken er ryddet."]) }
        return say(person.tekst, then: .choice(prompt: "Åpne sandkassen?", yes: .sandbox(caseId: caseId)))
    }

    private mutating func talkToFagkontor(_ person: TownPerson) -> TownAction {
        guard let ref = person.fagkontor else { return say(person.tekst) }
        if badges.contains(TownTrials.badgeKey(ref)) { return say(["Du har alt merket."]) }
        if !TownTrials.fagkontorReady(ref, regions: regions) { return say(person.tekst + ["Kontoret er under bygging."]) }
        if TownTrials.fagkontorOpen(ref, regions: regions, damage: damage) {
            return say(person.tekst, then: .choice(prompt: "Vil du prøve?", yes: .fagkontor(ref)))
        }
        // A topic with no visible puzzles has no gym to show.
        let progress = ref.temaer.compactMap { tema -> String? in
            guard let region = regions.first(where: { $0.tema == tema }), !region.isEmpty else { return nil }
            return "GYM \(damage[tema] ?? 0)/\(region.damageTarget)"
        }
        return say(person.tekst + [progress.joined(separator: "\n")])
    }

    // MARK: Lists

    private mutating func handleList(_ key: GameKey) -> TownAction {
        switch key {
        case .up: moveCursor(by: -1)
        case .down: moveCursor(by: 1)
        case .tab: turnPage()
        case .a: return select()
        default: break
        }
        return .none
    }

    private mutating func moveCursor(by delta: Int) {
        guard !rows.isEmpty else { return }
        cursor = min(rows.count - 1, max(0, cursor + delta))
        showRowPage()
    }

    private mutating func select() -> TownAction {
        switch phase {
        case .menu: return selectMenu()
        case .counter: return selectCounter()
        case .choice: return choose()
        // The dialog already shows the row in full; A reads on through it.
        case .bag: return selectBag()
        case .cards: return selectCard()
        case .fristnav: return rows.indices.contains(cursor) && rows[cursor].id == Self.travelRowId ? openTravel() : turnPageOnly()
        case .travel: return selectTravel()
        case .portfolio: return turnPageOnly()
        case .archive: return selectArchive()
        case .walking, .dialog: return .none
        }
    }

    private mutating func turnPageOnly() -> TownAction {
        turnPage()
        return .none
    }

    private mutating func openMenu() {
        phase = .menu
        rows = Self.mainMenu.map { PanelRow(id: $0, text: $0) }
        cursor = 0
        show(["Hva vil du gjøre?"])
    }

    private mutating func selectMenu() -> TownAction {
        switch cursor {
        case 0: return openFristnav()
        case 1: return openPortfolio()
        case 2: openBag(); return .none
        case 3: walk(); return .openCollection
        case 4: walk(); return .openTraining
        default: walk(); return .save
        }
    }

    private mutating func choose() -> TownAction {
        guard case .choice(_, let yes) = then, cursor == 0 else {
            walk()
            return .none
        }
        switch yes {
        case .sleep:
            walk()
            return .sleep
        case .trial(let client):
            guard !state.portfolioFull else { return say(["Porteføljen er full."]) }
            guard state.contracts > 0 else { return say(["Du har ingen oppdragsavtale."]) }
            walk()
            return .startTrial(client: client)
        case .fagkontor(let ref):
            walk()
            return .startFagkontor(ref)
        case .kundesak(let client, let puzzle):
            walk()
            return .startCase(client: client, puzzle: puzzle)
        case .sandbox(let caseId):
            walk()
            return .openSandbox(caseId: caseId)
        }
    }

    // MARK: Phases and pages

    /// Opens a list phase with its rows and the dialog for the first row.
    mutating func openList(_ phase: TownPhase, rows: [PanelRow]) {
        self.phase = phase
        self.rows = rows
        cursor = 0
        showRowPage()
    }

    /// The dialog under a list: the needs card in the portfolio, else the highlighted row in full.
    private mutating func showRowPage() {
        guard rows.indices.contains(cursor) else { return }
        let row = rows[cursor]
        if phase == .portfolio, let client = content.client(row.id) {
            show(needsCard(client))
        } else if phase != .menu, phase != .choice {
            show([row.full ?? row.text])
        }
    }

    /// Shows the texts as a dialog; with nothing to say, goes straight on to `next`.
    @discardableResult
    mutating func say(_ texts: [String], then next: Followup = .walk) -> TownAction {
        guard texts.contains(where: { !$0.isEmpty }) else { return follow(next) }
        phase = .dialog
        rows = []
        cursor = 0
        then = next
        show(texts)
        return .none
    }

    private mutating func follow(_ next: Followup) -> TownAction {
        switch next {
        case .walk:
            walk()
            return .none
        case .action(let action):
            walk()
            return action
        case .choice(let prompt, _):
            phase = .choice
            rows = Self.choiceRows
            cursor = 0
            then = next
            show([prompt])
            return .none
        }
    }

    mutating func walk() {
        phase = .walking
        rows = []
        cursor = 0
        counterTasks = []
        then = .walk
        pages = [[]]
        page = 0
    }

    /// Tab in a list: the next page, round to the first.
    mutating func turnPage() {
        page = hasMorePages ? page + 1 : 0
    }

    mutating func show(_ texts: [String]) {
        pages = Self.paged(texts)
        page = 0
    }

    static func paged(_ texts: [String]) -> [[String]] {
        let pages = texts.flatMap { TextWrap.pages(TextWrap.lines($0, columns: columns), rows: rows) }
        return pages.isEmpty ? [[]] : pages
    }
}
