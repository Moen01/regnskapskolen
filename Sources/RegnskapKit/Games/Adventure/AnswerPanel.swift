import Foundation

/// The answer panel over the battle field: a cursor list or an entry field per puzzle kind,
/// driven by Game Boy keys. Pure state: the view draws `rows`, `cursor`, `entry`; the app hands
/// keys in and reads the event out. The attempt is kept in step with what the learner did.
public struct AnswerPanel: Hashable, Sendable {
    public static let columns = 17
    public static let visibleRows = 6

    enum Mode: Hashable, Sendable {
        case list                       // quiz, sak, mva treatment
        case vatDeduction
        case entry                      // regnut, frist
        case postingLines
        case postingAccount(Int)
        case postingSide(Int)
        case postingAmount(Int)
        case classifyElements
        case classifyCategory(Int)
        case spotElements
    }

    let puzzle: Puzzle
    let rates: [MVARate]
    private(set) var mode: Mode
    private(set) var attempt: PuzzleAttempt
    public var cursor: Int { didSet { follow() } }
    private var windowStart = 0
    public private(set) var entry: String?
    public private(set) var entryLabel = ""

    public init(puzzle: Puzzle, rates: [MVARate], attempt: PuzzleAttempt) {
        self.puzzle = puzzle
        self.rates = rates
        self.attempt = attempt
        cursor = 0
        switch (puzzle.payload, attempt) {
        case (.quiz, .quiz(let index)):
            mode = .list
            cursor = index ?? 0
        case (.case(let p), .case(let key)):
            mode = .list
            cursor = key.flatMap { k in p.valg.firstIndex { $0.nokkel == k } } ?? 0
        case (.vat, .vat(let behandling, _)):
            mode = .list
            cursor = behandling.flatMap { code in rates.firstIndex { $0.kode == code } } ?? 0
        case (.number, .number(let text)):
            mode = .entry
            entry = text
            entryLabel = "SVAR:"
        case (.deadline, .deadline(let day)):
            mode = .entry
            entry = day.map { NorwegianFormat.date($0.date) } ?? ""
            entryLabel = "DATO:"
        case (.posting, .posting(let lines)):
            mode = .postingLines
            if lines.isEmpty { self.attempt = .posting([PostingAttemptLine(), PostingAttemptLine()]) }
        case (.classify, _):
            mode = .classifyElements
        case (.spot, _):
            mode = .spotElements
        default:
            mode = .list
        }
    }

    // MARK: What the view draws

    public var title: String {
        switch mode {
        case .list:
            switch puzzle.payload {
            case .vat: "MVA-BEHANDLING"
            case .case: "HVA GJØR DU?"
            default: "VELG SVAR"
            }
        case .vatDeduction: "FRADRAG?"
        case .entry: puzzle.kind == .frist ? "VELG DATOEN" : "REGN UT"
        case .postingLines: "FØR BILAGET"
        case .postingAccount: "KONTO"
        case .postingSide: "SIDE"
        case .postingAmount: "BELØP"
        case .classifyElements: "SORTER"
        case .classifyCategory: "KATEGORI"
        case .spotElements: "FINN FEILENE"
        }
    }

    public var rows: [PanelRow] {
        let columns = Self.columns
        switch (mode, puzzle.payload) {
        case (.list, .quiz(let p)):
            return p.alternativer.enumerated().map { PanelRow.fitting(id: "alt-\($0.offset)", $0.element, columns: columns) }
        case (.list, .case(let p)):
            return p.valg.map { PanelRow.fitting(id: "valg-\($0.nokkel)", "\($0.nokkel). \($0.tekst)", columns: columns) }
        case (.list, .vat):
            return rates.map { rate in
                let text = rate.prosent.map { "\(rate.navn) \($0) %" } ?? rate.navn
                return PanelRow.fitting(id: "sats-\(rate.kode)", text, columns: columns)
            }
        case (.vatDeduction, _):
            return [PanelRow(id: "ja", text: "Ja, fradrag"), PanelRow(id: "nei", text: "Nei, ikke fradrag")]
        case (.entry, _):
            return []
        case (.postingLines, .posting(let p)):
            let lines = postingLines
            return lines.enumerated().map { PanelRow(id: "line-\($0.offset)", text: Self.format(line: $0.element, accounts: p.kontoer)) }
                + [PanelRow(id: "add", text: "+ linje"), PanelRow(id: "strike", text: "SLÅ")]
        case (.postingAccount, .posting(let p)):
            return p.kontoer.map { PanelRow.fitting(id: "konto-\($0.nr)", "\($0.nr) \($0.navn)", columns: columns) }
        case (.postingSide, _):
            return [PanelRow(id: "debet", text: "Debet"), PanelRow(id: "kredit", text: "Kredit")]
        case (.postingAmount, _):
            return []
        case (.classifyElements, .classify(let p)):
            let answers = classifyAnswers
            return p.elementer.enumerated().map { index, item in
                if let chosen = answers[index] {
                    let mark = " → " + chosen
                    let room = max(3, columns - mark.count)
                    return PanelRow(id: "el-\(index)", text: TextWrap.truncate(item.tekst, to: room) + mark, full: item.tekst, marked: true)
                }
                return PanelRow.fitting(id: "el-\(index)", item.tekst, columns: columns)
            } + [PanelRow(id: "strike", text: "SLÅ")]
        case (.classifyCategory, .classify(let p)):
            return p.kategorier.enumerated().map { PanelRow.fitting(id: "kat-\($0.offset)", $0.element, columns: columns) }
        case (.spotElements, .spot(let p)):
            let marked = spotMarked
            return p.elementer.enumerated().map { index, item in
                let box = marked.contains(index) ? "[x] " : "[ ] "
                let cut = TextWrap.truncate(item.tekst, to: columns - box.count)
                return PanelRow(id: "el-\(index)", text: box + cut, full: cut == item.tekst ? nil : item.tekst, marked: marked.contains(index))
            } + [PanelRow(id: "strike", text: "SLÅ")]
        default:
            return []
        }
    }

    /// The rows to draw: a window of `visibleRows` that always holds the cursor.
    public var visibleRange: Range<Int> {
        let count = rows.count
        let start = min(windowStart, max(0, count - Self.visibleRows))
        return start..<min(count, start + Self.visibleRows)
    }

    /// Pages the dialog shows before the task text: the message in a sak.
    public var preface: [String] {
        if case .case(let p) = puzzle.payload {
            return [[p.fra, p.melding].compactMap { $0 }.joined(separator: ": ")]
        }
        return []
    }

    /// The highlighted row in full, when the row had to be cut.
    public var dialog: String? {
        rows.indices.contains(cursor) ? rows[cursor].full : nil
    }

    /// Debet and kredit totals while a voucher is being entered.
    public var sums: (debet: Decimal, kredit: Decimal)? {
        guard case .posting = puzzle.payload else { return nil }
        let lines = postingLines
        return (lines.reduce(0) { $0 + ($1.debet ?? 0) }, lines.reduce(0) { $0 + ($1.kredit ?? 0) })
    }

    // MARK: Keys

    /// Handles one key and keeps `attempt` in step. The panel owns the attempt while it is open.
    public mutating func handle(_ key: GameKey, attempt: inout PuzzleAttempt) -> PanelEvent {
        defer { attempt = self.attempt }
        switch mode {
        case .list: return handleList(key)
        case .vatDeduction: return handleDeduction(key)
        case .entry: return handleEntry(key)
        case .postingLines, .postingAccount, .postingSide, .postingAmount: return handlePosting(key)
        case .classifyElements, .classifyCategory: return handleClassify(key)
        case .spotElements: return handleSpot(key)
        }
    }

    /// A mouse click on a row: the cursor moves there, then A.
    public mutating func click(row index: Int, attempt: inout PuzzleAttempt) -> PanelEvent {
        guard rows.indices.contains(index) else { return .none }
        cursor = index
        return handle(.a, attempt: &attempt)
    }

    private mutating func move(_ key: GameKey) -> Bool {
        switch key {
        case .up: cursor = max(0, cursor - 1); return true
        case .down: cursor = min(max(0, rows.count - 1), cursor + 1); return true
        default: return false
        }
    }

    private mutating func follow() {
        if cursor < windowStart { windowStart = cursor }
        if cursor >= windowStart + Self.visibleRows { windowStart = cursor - Self.visibleRows + 1 }
    }

    private mutating func handleList(_ key: GameKey) -> PanelEvent {
        if move(key) { return .none }
        switch (key, puzzle.payload) {
        case (.b, _):
            return .back
        case (.a, .quiz):
            attempt = .quiz(cursor)
            return .attack
        case (.a, .case(let p)):
            attempt = .case(p.valg[cursor].nokkel)
            return .attack
        case (.a, .vat(let p)):
            guard rates.indices.contains(cursor) else { return .none }
            let fradrag: Bool? = { if case .vat(_, let f) = attempt { f } else { nil } }()
            attempt = .vat(behandling: rates[cursor].kode, fradrag: nil)
            guard p.fasit.fradrag != nil else { return .attack }
            mode = .vatDeduction
            cursor = fradrag == false ? 1 : 0
            return .none
        default:
            return .none
        }
    }

    private mutating func handleDeduction(_ key: GameKey) -> PanelEvent {
        if move(key) { return .none }
        guard case .vat(let behandling, _) = attempt else { return .none }
        switch key {
        case .a:
            attempt = .vat(behandling: behandling, fradrag: cursor == 0)
            return .attack
        case .b:
            mode = .list
            cursor = behandling.flatMap { code in rates.firstIndex { $0.kode == code } } ?? 0
            return .none
        default:
            return .none
        }
    }

    private mutating func handleEntry(_ key: GameKey) -> PanelEvent {
        let isDate = puzzle.kind == .frist
        switch key {
        case .character(let c):
            let allowed: Set<Character> = isDate ? Set("0123456789.") : Set("0123456789 ,.-")
            if allowed.contains(c) { entry = (entry ?? "") + String(c) }
            return .none
        case .delete:
            if let text = entry, !text.isEmpty { entry = String(text.dropLast()) }
            return .none
        case .a:
            let text = entry ?? ""
            if isDate {
                guard let day = NorwegianFormat.parseDay(text) else { return .invalid("Skriv datoen som dd.mm.åååå.") }
                attempt = .deadline(day)
            } else {
                guard NorwegianFormat.parseAmount(text) != nil else { return .invalid("Skriv et beløp, for eksempel 1 250 eller 1250,50.") }
                attempt = .number(text)
            }
            return .attack
        case .b:
            return .back
        default:
            return .none
        }
    }

    // MARK: Posting

    private var postingLines: PostingAttempt {
        if case .posting(let lines) = attempt { lines } else { [] }
    }

    /// `1920 Bank  D 2500` in 17 columns: the name gives way so the amount always fits.
    public static func format(line: PostingAttemptLine, accounts: [AccountOption]) -> String {
        guard !line.konto.isEmpty else { return "---- (tom)" }
        let side = line.debet != nil ? "D" : (line.kredit != nil ? "K" : " ")
        let amount = (line.debet ?? line.kredit).map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        let name = accounts.first { $0.nr == line.konto }?.navn ?? ""
        let fixed = line.konto.count + 1 + 2 + side.count + 1 + amount.count
        let room = max(2, columns - fixed)
        let shortName = String(name.prefix(room))
        return "\(line.konto) \(shortName.padding(toLength: room, withPad: " ", startingAt: 0))\(side) \(amount)".trimmingCharacters(in: .whitespaces)
    }

    private mutating func handlePosting(_ key: GameKey) -> PanelEvent {
        .none
    }

    // MARK: Classify and spot

    private var classifyAnswers: [Int: String] {
        if case .classify(let answers) = attempt { answers } else { [:] }
    }

    private mutating func handleClassify(_ key: GameKey) -> PanelEvent {
        if move(key) { return .none }
        return key == .b ? .back : .none
    }

    private var spotMarked: Set<Int> {
        if case .spot(let marked) = attempt { marked } else { [] }
    }

    private mutating func handleSpot(_ key: GameKey) -> PanelEvent {
        if move(key) { return .none }
        return key == .b ? .back : .none
    }
}
