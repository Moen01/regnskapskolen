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
}
