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

    func testPanelInvalidBecomesADialogPage() {
        var (f, a) = flow(kind: .regnut)
        _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a); _ = f.handle(.a, attempt: &a)
        XCTAssertEqual(f.phase, .answer)
        let action = f.handle(.a, attempt: &a)
        guard case .invalid(let message) = action else { return XCTFail("\(action)") }
        XCTAssertEqual(f.pages.first, TextWrap.pages(TextWrap.lines(message, columns: 18), rows: 3).first)
    }
}
