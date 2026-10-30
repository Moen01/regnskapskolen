import Foundation

/// The answer panel over the battle field: a cursor list or an entry field per puzzle kind,
/// driven by Game Boy keys. Pure state: the view draws `rows`, `cursor`, `entry`; the app hands
/// keys in and reads the event out. The attempt is kept in step with what the learner did.
public struct AnswerPanel: Hashable, Sendable {
    public static let columns = ListBox.columns
    public static let visibleRows = ListBox.rows(in: ListBox.windowRowSpace)

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

    public let puzzle: Puzzle
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

    /// True while the voucher's lines are listed (the view shows the sums in the headline).
    public var isListingLines: Bool { mode == .postingLines }

    /// An amount as the learner wrote it: no grouping, a decimal comma.
    public static func amountText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(of: ".", with: ",")
    }

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

    /// `1920 Bank  D 2500` in the list's columns: the name gives way so the amount always fits.
    public static func format(line: PostingAttemptLine, accounts: [AccountOption]) -> String {
        guard !line.konto.isEmpty else { return "---- (tom)" }
        let side = line.debet != nil ? "D" : (line.kredit != nil ? "K" : " ")
        let amount = (line.debet ?? line.kredit).map(amountText) ?? ""
        let name = accounts.first { $0.nr == line.konto }?.navn ?? ""
        // Everything but the name and the gap before the side; the name shrinks to at least two
        // letters, and the gap closes to one space when even that is too wide.
        let base = line.konto.count + 1 + side.count + 1 + amount.count
        let room = max(2, columns - base - 2)
        let gap = base + room + 2 <= columns ? "  " : " "
        let shortName = String(name.prefix(room)).padding(toLength: room, withPad: " ", startingAt: 0)
        return "\(line.konto) \(shortName)\(gap)\(side) \(amount)".trimmingCharacters(in: .whitespaces)
    }

    private mutating func handlePosting(_ key: GameKey) -> PanelEvent {
        guard case .posting(let p) = puzzle.payload else { return .none }
        var lines = postingLines
        switch mode {
        case .postingLines:
            if move(key) { return .none }
            let row = rows[cursor]
            switch key {
            case .a where row.id == "strike":
                return attempt.isAnswered ? .attack : .invalid("Før minst én linje først.")
            case .a where row.id == "add":
                lines.append(PostingAttemptLine())
                attempt = .posting(lines)
                return .none
            case .a:
                let index = cursor
                mode = .postingAccount(index)
                cursor = p.kontoer.firstIndex { $0.nr == lines[index].konto } ?? 0
                return .none
            case .delete where row.id.hasPrefix("line-") && lines.count > 1:
                lines.remove(at: cursor)
                attempt = .posting(lines)
                cursor = min(cursor, lines.count - 1)
                return .none
            case .b:
                return .back
            default:
                return .none
            }
        case .postingAccount(let index):
            if move(key) { return .none }
            switch key {
            case .a:
                lines[index].konto = p.kontoer[cursor].nr
                attempt = .posting(lines)
                mode = .postingSide(index)
                cursor = lines[index].kredit != nil && lines[index].debet == nil ? 1 : 0
                return .none
            case .b:
                mode = .postingLines
                cursor = index
                return .none
            default:
                return .none
            }
        case .postingSide(let index):
            switch key {
            case .left, .up: cursor = 0; return .none
            case .right, .down: cursor = 1; return .none
            case .a:
                mode = .postingAmount(index)
                entry = (lines[index].debet ?? lines[index].kredit).map(Self.amountText) ?? ""
                entryLabel = "BELØP:"
                return .none
            case .b:
                mode = .postingLines
                cursor = index
                return .none
            default:
                return .none
            }
        case .postingAmount(let index):
            switch key {
            case .character(let c):
                if Set("0123456789 ,.").contains(c) { entry = (entry ?? "") + String(c) }
                return .none
            case .delete:
                if let text = entry, !text.isEmpty { entry = String(text.dropLast()) }
                return .none
            case .a:
                guard let amount = NorwegianFormat.parseAmount(entry ?? ""), amount > 0 else {
                    return .invalid("Skriv et beløp, for eksempel 1 250 eller 1250,50.")
                }
                let credit = cursor == 1
                lines[index].debet = credit ? nil : amount
                lines[index].kredit = credit ? amount : nil
                attempt = .posting(lines)
                entry = nil
                entryLabel = ""
                mode = .postingLines
                cursor = min(index + 1, lines.count - 1)
                return .none
            case .b:
                entry = nil
                entryLabel = ""
                mode = .postingLines
                cursor = index
                return .none
            default:
                return .none
            }
        default:
            return .none
        }
    }

    // MARK: Classify and spot

    private var classifyAnswers: [Int: String] {
        if case .classify(let answers) = attempt { answers } else { [:] }
    }

    private mutating func handleClassify(_ key: GameKey) -> PanelEvent {
        guard case .classify(let p) = puzzle.payload else { return .none }
        if move(key) { return .none }
        switch mode {
        case .classifyElements:
            switch key {
            case .a where rows[cursor].id == "strike":
                return attempt.isAnswered ? .attack : .invalid("Velg en kategori først.")
            case .a:
                let index = cursor
                mode = .classifyCategory(index)
                cursor = classifyAnswers[index].flatMap { p.kategorier.firstIndex(of: $0) } ?? 0
                return .none
            case .b:
                return .back
            default:
                return .none
            }
        case .classifyCategory(let index):
            switch key {
            case .a:
                var answers = classifyAnswers
                answers[index] = p.kategorier[cursor]
                attempt = .classify(answers)
                mode = .classifyElements
                cursor = index
                return .none
            case .b:
                mode = .classifyElements
                cursor = index
                return .none
            default:
                return .none
            }
        default:
            return .none
        }
    }

    private var spotMarked: Set<Int> {
        if case .spot(let marked) = attempt { marked } else { [] }
    }

    private mutating func handleSpot(_ key: GameKey) -> PanelEvent {
        if move(key) { return .none }
        switch key {
        case .a where rows[cursor].id == "strike":
            return .attack
        case .a, .character(" "):
            var marked = spotMarked
            if marked.contains(cursor) { marked.remove(cursor) } else { marked.insert(cursor) }
            attempt = .spot(marked)
            return .none
        case .b:
            return .back
        default:
            return .none
        }
    }
}
