import XCTest
@testable import RegnskapKit

final class NorwegianFormatTests: XCTestCase {
    func testParseAmountVariants() {
        XCTAssertEqual(NorwegianFormat.parseAmount("1 250,00"), 1250)
        XCTAssertEqual(NorwegianFormat.parseAmount("1.250,00"), 1250)
        XCTAssertEqual(NorwegianFormat.parseAmount("1250"), 1250)
        XCTAssertEqual(NorwegianFormat.parseAmount("-300"), -300)
        XCTAssertEqual(NorwegianFormat.parseAmount("1 250,5"), Decimal(string: "1250.5"))
        XCTAssertEqual(NorwegianFormat.parseAmount("kr 1 250"), 1250)
        XCTAssertEqual(NorwegianFormat.parseAmount("1\u{00A0}250,00 kr"), 1250)
        XCTAssertEqual(NorwegianFormat.parseAmount("1,250.00"), 1250)
        XCTAssertEqual(NorwegianFormat.parseAmount("12,5"), Decimal(string: "12.5"))
        XCTAssertNil(NorwegianFormat.parseAmount("abc"))
        XCTAssertNil(NorwegianFormat.parseAmount(""))
        XCTAssertNil(NorwegianFormat.parseAmount("   "))
    }

    func testKronerFormatting() {
        XCTAssertEqual(NorwegianFormat.kroner(1250), "1\u{202F}250,00")
        XCTAssertEqual(NorwegianFormat.kroner(Decimal(string: "0.5")!), "0,50")
        XCTAssertEqual(NorwegianFormat.kroner(-3), "\u{2212}3,00")
        XCTAssertEqual(NorwegianFormat.kroner(1234567, decimals: 0), "1\u{202F}234\u{202F}567")
    }

    func testDateRoundTrip() throws {
        let date = try XCTUnwrap(NorwegianFormat.parseDate("2026-06-10"))
        XCTAssertEqual(NorwegianFormat.date(date), "10.06.2026")
        XCTAssertNil(NorwegianFormat.parseDate("10.06.2026"))
    }

    func testParseAmountRejectsAStrayMinus() {
        for text in ["1-000", "5-", "--5", "1-", "-"] {
            XCTAssertNil(NorwegianFormat.parseAmount(text), text)
        }
        XCTAssertEqual(NorwegianFormat.parseAmount("-1 250,50"), Decimal(string: "-1250.5"))
    }
}
