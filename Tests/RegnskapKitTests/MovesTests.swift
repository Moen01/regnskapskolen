import XCTest
@testable import RegnskapKit

final class MovesTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    var mva: [RuleCard] { Self.library.rules(tema: "mva") }
    var others: [RuleCard] { Self.library.rules.filter { $0.tema != "mva" } }

    func testPairsCrossEachLawWithEachParagraphAndDeduplicate() {
        let card = Self.library.rules(tema: "valuta-korrigeringer")[0]   // lov "regnskapsloven, bokføringsloven", paragrafer § 5-9, § 4-3, § 7, § 9
        let pairs = Moves.pairs(from: [card, card])
        XCTAssertEqual(pairs.count, 8)
        XCTAssertTrue(pairs.contains(Move(lov: "bokføringsloven", paragraf: "§ 7")))
        XCTAssertEqual(pairs, pairs.sorted { $0.id < $1.id })
    }

    func testHitsMatchesLawAndParagraph() throws {
        let puzzle = try XCTUnwrap(Self.library.puzzle(id: "mva-quiz-001"))
        let law = puzzle.lov[0]
        XCTAssertTrue(Moves.hits(Move(lov: law.lov, paragraf: law.paragraf), puzzle))
        XCTAssertFalse(Moves.hits(Move(lov: law.lov, paragraf: "§ 99-99"), puzzle))
        XCTAssertFalse(Moves.hits(Move(lov: "tulleloven", paragraf: law.paragraf), puzzle))
    }

    func testOptionsHoldTheRegionsPairsPlusTwoDistractorsAndNeverLeakAHit() throws {
        let puzzle = try XCTUnwrap(Self.library.puzzles(tema: "mva").first { Moves.canHit($0, regionCards: mva) })
        let options = Moves.options(for: puzzle, regionCards: mva, otherCards: others, seed: 3)
        XCTAssertLessThanOrEqual(options.count, Moves.maxOptions - 1)
        XCTAssertTrue(options.contains { Moves.hits($0, puzzle) })
        let regionPairs = Set(Moves.pairs(from: mva))
        let foreign = options.filter { !regionPairs.contains($0) }
        XCTAssertEqual(foreign.count, Moves.distractors)
        XCTAssertFalse(foreign.contains { Moves.hits($0, puzzle) }, "a distractor never hits")
        XCTAssertEqual(options, Moves.options(for: puzzle, regionCards: mva, otherCards: others, seed: 3), "seeded")
    }

    func testOptionsAreEmptyWhenTheRegionCannotHit() throws {
        let puzzle = try XCTUnwrap(Self.library.puzzle(id: "mva-quiz-001"))
        XCTAssertFalse(Moves.canHit(puzzle, regionCards: Self.library.rules(tema: "lonn")))
        XCTAssertEqual(Moves.options(for: puzzle, regionCards: Self.library.rules(tema: "lonn"), otherCards: others, seed: 1), [])
    }

    func testMostApprovedPuzzlesCanBeHitByTheirOwnTopic() {
        let approved = Self.library.approved
        let hittable = approved.filter { Moves.canHit($0, regionCards: Self.library.rules(tema: $0.tema)) }
        XCTAssertGreaterThanOrEqual(Double(hittable.count) / Double(approved.count), 0.75, "\(approved.count - hittable.count) approved puzzles cite no paragraph on a card in their topic")
    }
}
