import XCTest
@testable import RegnskapKit

final class PostingCheckerTests: XCTestCase {
    // Sale for 2 000 + 25 % mva, paid to the bank: D 1920 2 500, K 3000 2 000, K 2700 500.
    let posting = Posting(
        kontoer: [AccountOption(nr: "1920", navn: "Bank"), AccountOption(nr: "3000", navn: "Salg"), AccountOption(nr: "2700", navn: "Utg. mva"), AccountOption(nr: "1900", navn: "Kontanter"), AccountOption(nr: "6300", navn: "Leie")],
        fasit: [PostingLine(konto: "1920", side: .debet, belop: 2500, alt: ["1900"]), PostingLine(konto: "3000", side: .kredit, belop: 2000), PostingLine(konto: "2700", side: .kredit, belop: 500)])

    func line(_ konto: String, d: Decimal? = nil, k: Decimal? = nil) -> PostingAttemptLine { PostingAttemptLine(konto: konto, debet: d, kredit: k) }

    func testBothSidesOnOneLine() {
        let v = PostingChecker.check([line("1920", d: 2500, k: 2500)], against: posting)
        XCTAssertFalse(v.correct)
        XCTAssertEqual(v.messages.first, "En linje kan ha debet eller kredit, ikke begge.")
    }

    func testUnbalanced() {
        let v = PostingChecker.check([line("1920", d: 2500), line("3000", k: 2000)], against: posting)
        XCTAssertFalse(v.correct)
        XCTAssertEqual(v.messages.first, "Bilaget balanserer ikke. Differanse: 500,00 kr.")
    }

    func testWrongSide() {
        let v = PostingChecker.check([line("1920", k: 2500), line("3000", d: 2000), line("2700", d: 500)], against: posting)
        XCTAssertFalse(v.correct)
        XCTAssertTrue(v.messages.contains("Konto 1920: riktig konto, feil side."), v.messages.joined(separator: " | "))
    }

    func testWrongAmount() {
        let v = PostingChecker.check([line("1920", d: 2500), line("3000", k: 2100), line("2700", k: 400)], against: posting)
        XCTAssertFalse(v.correct)
        XCTAssertTrue(v.messages.contains("Konto 3000: riktig side, feil beløp."), v.messages.joined(separator: " | "))
        XCTAssertTrue(v.messages.contains("Konto 2700: riktig side, feil beløp."))
    }

    func testExtraAccount() {
        let v = PostingChecker.check([line("1920", d: 2500), line("6300", k: 2000), line("2700", k: 500)], against: posting)
        XCTAssertFalse(v.correct)
        XCTAssertTrue(v.messages.contains("Konto 6300 skal ikke være med her."), v.messages.joined(separator: " | "))
    }

    func testMissingLineDoesNotNameAccount() {
        // 1920 against 2700 only, balanced by amount: a line is missing on the kredit side, and the message must not say 3000.
        let v = PostingChecker.check([line("1920", d: 500), line("2700", k: 500)], against: posting)
        XCTAssertFalse(v.correct)
        XCTAssertTrue(v.messages.contains("Det mangler en linje på kreditsiden."), v.messages.joined(separator: " | "))
        XCTAssertFalse(v.messages.joined().contains("3000"))
    }

    func testCorrect() {
        let v = PostingChecker.check([line("1920", d: 2500), line("3000", k: 2000), line("2700", k: 500)], against: posting)
        XCTAssertTrue(v.correct)
        XCTAssertEqual(v.score, 1)
        XCTAssertEqual(v.messages, ["Riktig! Debet 2\u{202F}500,00 = kredit 2\u{202F}500,00."])
    }

    func testAltAccountAccepted() {
        let v = PostingChecker.check([line("1900", d: 2500), line("3000", k: 2000), line("2700", k: 500)], against: posting)
        XCTAssertTrue(v.correct)
    }

    func testSplitLinesAreSummed() {
        let v = PostingChecker.check([line("1920", d: 2000), line("1920", d: 500), line("3000", k: 2000), line("2700", k: 500)], against: posting)
        XCTAssertTrue(v.correct)
    }

    func testEmptyLinesAreIgnoredAndEmptyAttemptIsNotBalanced() {
        let v = PostingChecker.check([line("1920"), line("")], against: posting)
        XCTAssertFalse(v.correct)
        XCTAssertEqual(v.messages.first, "Legg til minst én debetlinje og én kreditlinje.")
    }
}
