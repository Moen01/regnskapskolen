import XCTest
@testable import RegnskapKit

final class CheckersTests: XCTestCase {
    static let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/puzzles/valid")
    func fixture(_ name: String) throws -> Puzzle { try Puzzle.load(url: Self.fixtures.appendingPathComponent("\(name).json")) }

    func testClassify() throws {
        guard case .classify(let p) = try fixture("klassifiser").payload else { return XCTFail() }
        let right = Checkers.classify([0: "Eiendel", 1: "Gjeld"], p)
        XCTAssertTrue(right.correct); XCTAssertEqual(right.score, 1); XCTAssertEqual(right.messages, ["2 av 2 riktig."])
        let half = Checkers.classify([0: "Eiendel", 1: "Kostnad"], p)
        XCTAssertFalse(half.correct); XCTAssertEqual(half.score, 0.5)
        XCTAssertEqual(half.perItem?[1].state, .wrong); XCTAssertEqual(half.perItem?[1].note, "Bedriften skylder leverandørene.")
        XCTAssertEqual(half.messages, ["1 av 2 riktig."])
        let missing = Checkers.classify([0: "Eiendel"], p)
        XCTAssertEqual(missing.perItem?[1].state, .missed)
    }

    func testSpot() throws {
        guard case .spot(let p) = try fixture("finnfeil").payload else { return XCTFail() }
        let right = Checkers.spot([0], p)
        XCTAssertTrue(right.correct); XCTAssertEqual(right.messages, ["Du fant 1 av 1."])
        let wrong = Checkers.spot([1], p)
        XCTAssertFalse(wrong.correct)
        XCTAssertEqual(wrong.perItem?[0].state, .missed); XCTAssertEqual(wrong.perItem?[1].state, .wrong)
        XCTAssertEqual(wrong.messages, ["Du fant 0 av 1."])
        XCTAssertEqual(wrong.score, 0)
    }

    func testNumberTolerance() throws {
        guard case .number(let p) = try fixture("regnut").payload else { return XCTFail() }
        XCTAssertTrue(Checkers.number(250, p).correct)
        XCTAssertFalse(Checkers.number(251, p).correct)
        XCTAssertEqual(Checkers.number(251, p).messages, ["Ikke riktig. Hint: Del på 1,25 for å finne nettobeløpet."])
        let loose = NumberAnswer(svar: 100, toleranse: 2, enhet: nil, hint: nil)
        XCTAssertTrue(Checkers.number(102, loose).correct)
        XCTAssertTrue(Checkers.number(98, loose).correct)
        XCTAssertFalse(Checkers.number(Decimal(string: "102.01")!, loose).correct)
    }

    func testQuiz() throws {
        guard case .quiz(let p) = try fixture("quiz").payload else { return XCTFail() }
        XCTAssertTrue(Checkers.quiz(2, p).correct)
        let wrong = Checkers.quiz(0, p)
        XCTAssertFalse(wrong.correct); XCTAssertEqual(wrong.messages, ["Ikke riktig."])
    }

    func testCase() throws {
        guard case .case(let p) = try fixture("sak").payload else { return XCTFail() }
        XCTAssertTrue(Checkers.case("A", p).correct)
        XCTAssertFalse(Checkers.case("B", p).correct)
    }

    func testVATNeedsBothParts() throws {
        guard case .vat(let p) = try fixture("mva").payload else { return XCTFail() }
        XCTAssertTrue(Checkers.vat("omvendt", true, p).correct)
        let half = Checkers.vat("omvendt", false, p)
        XCTAssertFalse(half.correct); XCTAssertEqual(half.messages, ["Behandlingen er riktig, men fradragsretten er feil."])
        let other = Checkers.vat("25", true, p)
        XCTAssertFalse(other.correct); XCTAssertEqual(other.messages, ["Feil behandling."])
        let noDeduction = VAT(transaksjon: "x", fasit: VATAnswer(behandling: "25", fradrag: nil))
        XCTAssertTrue(Checkers.vat("25", nil, noDeduction).correct)
        XCTAssertTrue(Checkers.vat("25", false, noDeduction).correct)
    }

    func testDeadline() throws {
        guard case .deadline(let p) = try fixture("frist").payload else { return XCTFail() }
        XCTAssertTrue(Checkers.deadline(DayKey(string: "2026-08-31")!, p).correct)
        let wrong = Checkers.deadline(DayKey(string: "2026-08-10")!, p)
        XCTAssertFalse(wrong.correct)
        XCTAssertEqual(wrong.messages, ["Ikke riktig. Hint: Hovedregelen er 1 måned og 10 dager etter terminens slutt, men én termin har en egen sommerfrist."])
    }
}
