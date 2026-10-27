import XCTest
@testable import RegnskapKit

final class PuzzleDecodingTests: XCTestCase {
    static let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/puzzles")

    func testDecodesEveryKind() throws {
        for kind in PuzzleKind.allCases {
            let url = Self.fixtures.appendingPathComponent("valid/\(kind.rawValue).json")
            let puzzle = try Puzzle.load(url: url)
            XCTAssertEqual(puzzle.kind, kind)
            XCTAssertEqual(puzzle.status, .godkjent)
            XCTAssertFalse(puzzle.generert)
            XCTAssertEqual(puzzle.sourceURL, url)
            switch (kind, puzzle.payload) {
            case (.postering, .posting(let p)): XCTAssertEqual(p.fasit.count, 3); XCTAssertEqual(p.fasit[0].belop, 2500)
            case (.klassifiser, .classify(let p)): XCTAssertEqual(p.kategorier.count, 5)
            case (.finnfeil, .spot(let p)): XCTAssertEqual(p.elementer.filter(\.feil).count, 1)
            case (.regnut, .number(let p)): XCTAssertEqual(p.svar, 250); XCTAssertEqual(p.toleranse, 0)
            case (.quiz, .quiz(let p)): XCTAssertEqual(p.svar, 2); XCTAssertEqual(p.alternativer.count, 4)
            case (.sak, .case(let p)): XCTAssertEqual(p.svar, "A"); XCTAssertEqual(p.valg.count, 2)
            case (.mva, .vat(let p)): XCTAssertEqual(p.fasit.behandling, "omvendt"); XCTAssertEqual(p.fasit.fradrag, true)
            case (.frist, .deadline(let p)): XCTAssertEqual(p.fasit.string, "2026-08-31"); XCTAssertEqual(p.fasitRegel?["termin"]?.int, 3)
            default: XCTFail("payload does not match kind \(kind)")
            }
        }
    }

    func testUnknownTypeFails() {
        XCTAssertThrowsError(try Puzzle.load(url: Self.fixtures.appendingPathComponent("invalid/unknown-type.json")))
    }

    func testMissingStatusDecodesAsDraft() throws {
        let data = Data(#"{"id":"x","type":"quiz","tema":"mva","vanskelighet":1,"tittel":"t","oppgave":"o","alternativer":["a","b"],"svar":0,"lov":[],"forklaring":"f"}"#.utf8)
        let puzzle = try Puzzle.decode(data)
        XCTAssertEqual(puzzle.status, .utkast)
        XCTAssertEqual(puzzle.tags, [])
    }

    func testRoundTripThroughEncoder() throws {
        let puzzle = try Puzzle.load(url: Self.fixtures.appendingPathComponent("valid/postering.json"))
        let data = try puzzle.encoded()
        let again = try Puzzle.decode(data)
        XCTAssertEqual(again.id, puzzle.id)
        XCTAssertEqual(again.payload, puzzle.payload)
        XCTAssertEqual(again.lov, puzzle.lov)
    }
}
