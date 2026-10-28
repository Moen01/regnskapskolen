import XCTest
@testable import RegnskapKit

final class BattleFlowTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    private func flow(kind: PuzzleKind = .quiz) -> (BattleFlow, PuzzleAttempt) {
        // A puzzle whose region has rule cards that can hit it, so the move list and REGLER are populated.
        let puzzle = Self.library.puzzles.first { $0.kind == kind && Moves.canHit($0, regionCards: Self.library.rules(tema: $0.tema)) }!
        let cards = Self.library.rules(tema: puzzle.tema)
        let moves = Moves.options(for: puzzle, regionCards: cards, otherCards: Self.library.rules.filter { $0.tema != puzzle.tema }, seed: 1)
        let encounter = Encounter(puzzle: puzzle, stageBefore: .vill, moves: moves, isGymLeader: false)
        let attempt = PuzzleAttempt.empty(for: kind)
        return (BattleFlow(encounter: encounter, laws: Self.library.laws, cards: cards, rates: Self.library.rates.mvaSatser, attempt: attempt), attempt)
    }

    func testIntroPagesThenMenu() {
        var (f, a) = flow()
        XCTAssertEqual(f.phase, .intro)
        XCTAssertTrue(f.hasMorePages)
        XCTAssertEqual(f.handle(.a, attempt: &a), .none)      // next page (the title)
        XCTAssertEqual(f.handle(.a, attempt: &a), .none)      // past the last page → menu
        XCTAssertEqual(f.phase, .menu)
        XCTAssertEqual(f.pages, [["Hva gjør du?"]])
    }

    func testMenuIsTwoByTwo() {
        var (f, a) = flow()
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)
        _ = f.handle(.right, attempt: &a); XCTAssertEqual(f.menuCursor, 1)
        _ = f.handle(.down, attempt: &a); XCTAssertEqual(f.menuCursor, 3)
        _ = f.handle(.left, attempt: &a); XCTAssertEqual(f.menuCursor, 2)
        _ = f.handle(.up, attempt: &a); XCTAssertEqual(f.menuCursor, 0)
    }

    func testFightChoosesAMoveThenOpensThePanel() {
        var (f, a) = flow()
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)
        XCTAssertEqual(f.handle(.a, attempt: &a), .none)      // KJEMP
        XCTAssertEqual(f.phase, .moves)
        XCTAssertEqual(f.moveRows.last?.text, "Ingen regel")
        XCTAssertTrue(f.moveRows.allSatisfy { $0.text.count <= 17 })
        let action = f.handle(.a, attempt: &a)
        guard case .chooseMove = action else { return XCTFail("\(action)") }
        XCTAssertTrue(f.hasChosen)
        XCTAssertEqual(f.phase, .answer)
        XCTAssertEqual(f.pages.first?.first?.hasPrefix("Du brukte"), true)
        XCTAssertTrue(f.pages.count > 1)                     // then the task text
    }

    func testTabTurnsTheDialogAndEnterNeverDoes() {
        var (f, a) = flow()
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)
        XCTAssertEqual(f.phase, .answer)
        let before = f.page
        _ = f.handle(.tab, attempt: &a)
        XCTAssertEqual(f.page, before + 1)
        XCTAssertEqual(f.handle(.a, attempt: &a), .attack)   // Enter on the first quiz row attacks
    }

    func testBackFromThePanelKeepsTheMove() {
        var (f, a) = flow()
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)
        XCTAssertEqual(f.handle(.b, attempt: &a), .none)
        XCTAssertEqual(f.phase, .menu)
        XCTAssertTrue(f.hasChosen)
    }

    func testReadAndRules() {
        var (f, a) = flow()
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)
        _ = f.handle(.right, attempt: &a)
        _ = f.handle(.a, attempt: &a)                         // LES
        XCTAssertEqual(f.phase, .reading)
        XCTAssertFalse(f.pages.isEmpty)
        _ = f.handle(.b, attempt: &a)
        XCTAssertEqual(f.phase, .menu)
        _ = f.handle(.down, attempt: &a); _ = f.handle(.left, attempt: &a)
        _ = f.handle(.a, attempt: &a)                         // REGLER
        XCTAssertEqual(f.phase, .rules)
        XCTAssertFalse(f.cardRows.isEmpty)
        _ = f.handle(.a, attempt: &a)
        XCTAssertEqual(f.phase, .card(0))
        _ = f.handle(.b, attempt: &a)
        XCTAssertEqual(f.phase, .rules)
    }

    func testFleeAndOutcome() {
        var (f, a) = flow()
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)
        _ = f.handle(.down, attempt: &a); _ = f.handle(.right, attempt: &a)
        XCTAssertEqual(f.handle(.a, attempt: &a), .flee)
        f.showOutcome(.escaped(hpLost: 500))
        XCTAssertEqual(f.phase, .outcome)
        XCTAssertEqual(f.pages.first, ["Bom!"])
        while f.hasMorePages { _ = f.handle(.a, attempt: &a) }
        XCTAssertEqual(f.handle(.a, attempt: &a), .none)
        XCTAssertEqual(f.phase, .explanation)
        while f.hasMorePages { _ = f.handle(.a, attempt: &a) }
        XCTAssertEqual(f.handle(.a, attempt: &a), .next)
    }

    func testBookedSkipsTheExplanationButCorrectedShowsIt() {
        var (f, a) = flow()
        f.showOutcome(.booked)
        XCTAssertEqual(f.pages, [["Bilaget er", "bokført."]])
        XCTAssertEqual(f.handle(.a, attempt: &a), .next, "the explanation would give the verdict away")
        var (g, b) = flow()
        g.showOutcome(.corrected(ok: false))
        while g.hasMorePages { _ = g.handle(.a, attempt: &b) }
        XCTAssertEqual(g.handle(.a, attempt: &b), .none)
        XCTAssertEqual(g.phase, .explanation)
    }

    func testClickOnTheDialogAdvancesLikeAInThePagePhases() {
        var (f, a) = flow()
        XCTAssertTrue(f.awaitsContinue)
        XCTAssertEqual(f.clickDialog(attempt: &a), .none)    // next intro page
        XCTAssertEqual(f.clickDialog(attempt: &a), .none)    // → menu
        XCTAssertEqual(f.phase, .menu)
        XCTAssertFalse(f.awaitsContinue)
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)   // KJEMP, first move → answer
        XCTAssertEqual(f.phase, .answer)
        let before = f.page
        XCTAssertEqual(f.clickDialog(attempt: &a), .none)    // in the answer phase a click only turns the page
        XCTAssertEqual(f.page, before + 1)
        XCTAssertEqual(f.phase, .answer)
        f.showOutcome(.escaped(hpLost: 500))
        while f.hasMorePages { _ = f.clickDialog(attempt: &a) }
        _ = f.clickDialog(attempt: &a)
        XCTAssertEqual(f.phase, .explanation)
        XCTAssertTrue(f.awaitsContinue)                      // the last explanation page still shows the marker
        while f.hasMorePages { _ = f.clickDialog(attempt: &a) }
        XCTAssertEqual(f.clickDialog(attempt: &a), .next)
    }

    func testSpaceActsAsAWhileReading() {
        var (f, a) = flow()
        XCTAssertEqual(f.handle(.character(" "), attempt: &a), .none)
        XCTAssertEqual(f.page, 1)
        _ = f.handle(.character(" "), attempt: &a)
        XCTAssertEqual(f.phase, .menu)
    }

    func testAnswerPagesShowTheRowThenTheTask() {
        let puzzle = Self.library.puzzles.first { p in
            p.kind == .quiz && Moves.canHit(p, regionCards: Self.library.rules(tema: p.tema)) && p.payloadQuiz!.alternativer[0].count > 17
        }!
        let cards = Self.library.rules(tema: puzzle.tema)
        let moves = Moves.options(for: puzzle, regionCards: cards, otherCards: Self.library.rules.filter { $0.tema != puzzle.tema }, seed: 1)
        var f = BattleFlow(encounter: Encounter(puzzle: puzzle, stageBefore: .vill, moves: moves, isGymLeader: false),
                           laws: Self.library.laws, cards: cards, rates: [], attempt: .empty(for: .quiz))
        var a = PuzzleAttempt.empty(for: .quiz)
        for _ in 0..<4 { _ = f.handle(.a, attempt: &a) }
        XCTAssertEqual(f.phase, .answer)
        let taskPages = TextWrap.pages(TextWrap.lines(TextWrap.plain(markdown: puzzle.oppgave), columns: 18), rows: 3)
        let rowPages = TextWrap.pages(TextWrap.lines(puzzle.payloadQuiz!.alternativer[0], columns: 18), rows: 3)
        XCTAssertEqual(Array(f.pages.suffix(taskPages.count)), taskPages)
        XCTAssertEqual(Array(f.pages.dropFirst().prefix(rowPages.count)), rowPages)
    }

    func testPanelInvalidBecomesADialogPage() {
        var (f, a) = flow(kind: .regnut)
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)
        XCTAssertEqual(f.phase, .answer)
        let action = f.handle(.a, attempt: &a)
        guard case .invalid(let message) = action else { return XCTFail("\(action)") }
        XCTAssertEqual(f.pages.first, TextWrap.pages(TextWrap.lines(message, columns: 18), rows: 3).first)
    }
}
