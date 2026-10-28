import XCTest
@testable import RegnskapKit

final class TextWrapTests: XCTestCase {
    func testWrapsOnWordsWithinColumns() {
        XCTAssertEqual(TextWrap.lines("En vill KONTANTSALG dukket opp!", columns: 18), ["En vill", "KONTANTSALG dukket", "opp!"])
    }

    func testSplitsAWordLongerThanTheLineWithAHyphen() {
        XCTAssertEqual(TextWrap.lines("skatteforvaltningsforskriften § 15-3", columns: 18), ["skatteforvaltning-", "sforskriften §", "15-3"])
    }

    func testKeepsExplicitNewlinesAndDropsBlankRuns() {
        XCTAssertEqual(TextWrap.lines("A\n\n\nB", columns: 18), ["A", "", "B"])
    }

    func testPagesCutEveryNRows() {
        XCTAssertEqual(TextWrap.pages(["1", "2", "3", "4"], rows: 3), [["1", "2", "3"], ["4"]])
        XCTAssertEqual(TextWrap.pages([], rows: 3), [[]])
    }

    func testPlainStripsInlineMarksListsAndHeadings() {
        XCTAssertEqual(TextWrap.plain(markdown: "## Tittel\n\nDette er **viktig** og _kursiv_ med `kode`.\n\n- ett\n- to\n\n[lenke](https://x.no)"),
                       "Tittel\nDette er viktig og kursiv med kode.\n- ett\n- to\nlenke")
    }

    func testTruncateAddsEllipsisOnlyWhenNeeded() {
        XCTAssertEqual(TextWrap.truncate("bokføringsloven § 4", to: 17), "bokføringsloven…")
        XCTAssertEqual(TextWrap.truncate("bfl. § 4", to: 17), "bfl. § 4")
    }

    func testCharactersOutsideTheFontAreKept() {
        XCTAssertEqual(TextWrap.lines("−3 😀", columns: 18), ["−3 😀"])
    }
}
