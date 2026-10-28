import XCTest
@testable import RegnskapKit

extension Puzzle {
    var payloadQuiz: Quiz? { if case .quiz(let p) = payload { p } else { nil } }
    var payloadCase: Case? { if case .case(let p) = payload { p } else { nil } }
    var payloadClassify: Classify? { if case .classify(let p) = payload { p } else { nil } }
    var payloadVAT: VAT? { if case .vat(let p) = payload { p } else { nil } }
    var payloadPosting: Posting? { if case .posting(let p) = payload { p } else { nil } }
}

final class AnswerPanelTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    private func puzzle(_ kind: PuzzleKind, where test: (Puzzle) -> Bool = { _ in true }) -> Puzzle {
        Self.library.puzzles.first { $0.kind == kind && test($0) }!
    }

    func testQuizRowsAreTruncatedAndEnterAttacks() {
        let p = puzzle(.quiz) { $0.payloadQuiz!.alternativer.contains { $0.count > 17 } }
        var attempt = PuzzleAttempt.empty(for: .quiz)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        XCTAssertEqual(panel.title, "VELG SVAR")
        XCTAssertTrue(panel.rows.allSatisfy { $0.text.count <= 17 })
        XCTAssertNotNil(panel.rows.first { $0.full != nil })
        XCTAssertEqual(panel.handle(.down, attempt: &attempt), .none)
        XCTAssertEqual(panel.cursor, 1)
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .attack)
        XCTAssertEqual(attempt, .quiz(1))
    }

    func testCursorStopsAtTheEndsAndTheWindowFollows() {
        let p = puzzle(.klassifiser) { $0.payloadClassify!.elementer.count >= 8 }
        var attempt = PuzzleAttempt.empty(for: .klassifiser)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        _ = panel.handle(.up, attempt: &attempt)
        XCTAssertEqual(panel.cursor, 0)
        for _ in 0..<20 { _ = panel.handle(.down, attempt: &attempt) }
        XCTAssertEqual(panel.cursor, panel.rows.count - 1)
        XCTAssertTrue(panel.visibleRange.contains(panel.cursor))
        XCTAssertEqual(panel.visibleRange.count, AnswerPanel.visibleRows)
    }

    func testSakShowsTheMessageFirstAndChoicesAsRows() {
        let p = puzzle(.sak)
        var attempt = PuzzleAttempt.empty(for: .sak)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        XCTAssertFalse(panel.preface.isEmpty)
        XCTAssertEqual(panel.rows.count, p.payloadCase!.valg.count)
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .attack)
        XCTAssertEqual(attempt, .case(p.payloadCase!.valg[0].nokkel))
    }

    func testVatAsksForTheTreatmentThenTheDeduction() {
        let p = puzzle(.mva) { $0.payloadVAT!.fasit.fradrag != nil }
        let rates = Self.library.rates.mvaSatser
        var attempt = PuzzleAttempt.empty(for: .mva)
        var panel = AnswerPanel(puzzle: p, rates: rates, attempt: attempt)
        XCTAssertEqual(panel.rows.count, rates.count)
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)
        XCTAssertEqual(attempt, .vat(behandling: rates[0].kode, fradrag: nil))
        XCTAssertEqual(panel.title, "FRADRAG?")
        XCTAssertEqual(panel.rows.map(\.text), ["Ja, fradrag", "Nei, ikke fradrag"])
        _ = panel.handle(.down, attempt: &attempt)
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .attack)
        XCTAssertEqual(attempt, .vat(behandling: rates[0].kode, fradrag: false))
        XCTAssertEqual(panel.handle(.b, attempt: &attempt), .none)   // back to the treatment list
        XCTAssertEqual(panel.title, "MVA-BEHANDLING")
    }

    func testNumberEntryTypesAndParses() {
        let p = puzzle(.regnut)
        var attempt = PuzzleAttempt.empty(for: .regnut)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        XCTAssertEqual(panel.entry, "")
        XCTAssertEqual(panel.entryLabel, "SVAR:")
        for c in "1 250,5x" { _ = panel.handle(.character(c), attempt: &attempt) }
        XCTAssertEqual(panel.entry, "1 250,5")           // x is not a number character
        _ = panel.handle(.delete, attempt: &attempt)
        XCTAssertEqual(panel.entry, "1 250,")
        for _ in 0..<6 { _ = panel.handle(.delete, attempt: &attempt) }
        XCTAssertEqual(panel.entry, "")
        _ = panel.handle(.character("-"), attempt: &attempt)           // a stray minus is not an amount
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .invalid("Skriv et beløp, for eksempel 1 250 eller 1250,50."))
        _ = panel.handle(.delete, attempt: &attempt)
        for c in "1 250,5" { _ = panel.handle(.character(c), attempt: &attempt) }
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .attack)
        XCTAssertEqual(attempt, .number("1 250,5"))
    }

    func testDeadlineEntry() {
        let p = puzzle(.frist)
        var attempt = PuzzleAttempt.empty(for: .frist)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        XCTAssertEqual(panel.entryLabel, "DATO:")
        for c in "10.06.2026" { _ = panel.handle(.character(c), attempt: &attempt) }
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .attack)
        XCTAssertEqual(attempt, .deadline(DayKey(year: 2026, month: 6, day: 10)))
    }

    func testBackLeavesTheAnswerInPlace() {
        let p = puzzle(.quiz)
        var attempt = PuzzleAttempt.quiz(1)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        XCTAssertEqual(panel.cursor, 1)
        XCTAssertEqual(panel.handle(.b, attempt: &attempt), .back)
        XCTAssertEqual(attempt, .quiz(1))
    }

    func testPostingLineFormatFitsSeventeenColumns() {
        let accounts = [AccountOption(nr: "1920", navn: "Bankinnskudd"), AccountOption(nr: "3000", navn: "Salgsinntekt, avgiftspliktig")]
        XCTAssertEqual(AnswerPanel.format(line: PostingAttemptLine(konto: "1920", debet: 2500), accounts: accounts), "1920 Bank  D 2500")
        XCTAssertEqual(AnswerPanel.format(line: PostingAttemptLine(konto: "3000", kredit: 1250000), accounts: accounts), "3000 Sa K 1250000")
        XCTAssertEqual(AnswerPanel.format(line: PostingAttemptLine(), accounts: accounts), "---- (tom)")
        XCTAssertEqual(AnswerPanel.format(line: PostingAttemptLine(konto: "1920", debet: Decimal(string: "2500.5")!), accounts: accounts), "1920 Ba  D 2500,5")
        XCTAssertEqual(AnswerPanel.amountText(Decimal(string: "1250.25")!), "1250,25")
    }

    func testPostingEnterWalksAccountSideAmountThenStrikes() {
        let p = puzzle(.postering)
        let accounts = p.payloadPosting!.kontoer
        var attempt = PuzzleAttempt.empty(for: .postering)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        XCTAssertEqual(panel.title, "FØR BILAGET")
        XCTAssertEqual(panel.rows.map(\.id), ["line-0", "line-1", "add", "strike"])
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)            // line 0 → account list
        XCTAssertEqual(panel.title, "KONTO")
        XCTAssertEqual(panel.rows.count, accounts.count)
        _ = panel.handle(.down, attempt: &attempt)
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)            // account chosen → side
        XCTAssertEqual(panel.title, "SIDE")
        XCTAssertEqual(panel.rows.map(\.text), ["Debet", "Kredit"])
        _ = panel.handle(.right, attempt: &attempt)
        XCTAssertEqual(panel.cursor, 1)
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)            // side chosen → amount entry
        XCTAssertEqual(panel.entryLabel, "BELØP:")
        for c in "2500" { _ = panel.handle(.character(c), attempt: &attempt) }
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)            // amount set → back to lines, next line
        XCTAssertEqual(panel.title, "FØR BILAGET")
        XCTAssertEqual(panel.cursor, 1)
        guard case .posting(let lines) = attempt else { return XCTFail() }
        XCTAssertEqual(lines[0].konto, accounts[1].nr)
        XCTAssertEqual(lines[0].kredit, 2500)
        XCTAssertNil(lines[0].debet)
        XCTAssertEqual(panel.sums?.kredit, 2500)
        _ = panel.handle(.down, attempt: &attempt)                              // "add"
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)
        XCTAssertEqual(panel.rows.map(\.id), ["line-0", "line-1", "line-2", "add", "strike"])
        while panel.rows[panel.cursor].id != "strike" { _ = panel.handle(.down, attempt: &attempt) }
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .attack)
    }

    func testPostingStrikeNeedsAnAnswerAndDeleteRemovesALine() {
        let p = puzzle(.postering)
        var attempt = PuzzleAttempt.empty(for: .postering)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        while panel.rows[panel.cursor].id != "strike" { _ = panel.handle(.down, attempt: &attempt) }
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .invalid("Før minst én linje først."))
        panel.cursor = 0
        _ = panel.handle(.delete, attempt: &attempt)
        XCTAssertEqual(panel.rows.map(\.id), ["line-0", "add", "strike"])
        _ = panel.handle(.delete, attempt: &attempt)                            // the last line stays
        XCTAssertEqual(panel.rows.map(\.id), ["line-0", "add", "strike"])
    }

    func testClassifyPicksACategoryPerElement() {
        let p = puzzle(.klassifiser)
        let c = p.payloadClassify!
        var attempt = PuzzleAttempt.empty(for: .klassifiser)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        XCTAssertEqual(panel.rows.count, c.elementer.count + 1)                 // + "strike"
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)
        XCTAssertEqual(panel.rows.map(\.text), c.kategorier.map { TextWrap.truncate($0, to: 17) })
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)
        XCTAssertEqual(attempt, .classify([0: c.kategorier[0]]))
        XCTAssertTrue(panel.rows[0].marked)
        while panel.rows[panel.cursor].id != "strike" { _ = panel.handle(.down, attempt: &attempt) }
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .attack)
    }

    func testSpotTogglesAndStrikesEvenWithNothingMarked() {
        let p = puzzle(.finnfeil)
        var attempt = PuzzleAttempt.empty(for: .finnfeil)
        var panel = AnswerPanel(puzzle: p, rates: [], attempt: attempt)
        XCTAssertTrue(panel.rows[0].text.hasPrefix("[ ] "))
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .none)
        XCTAssertTrue(panel.rows[0].text.hasPrefix("[x] "))
        XCTAssertEqual(attempt, .spot([0]))
        while panel.rows[panel.cursor].id != "strike" { _ = panel.handle(.down, attempt: &attempt) }
        XCTAssertEqual(panel.handle(.a, attempt: &attempt), .attack)
    }
}
