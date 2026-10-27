import XCTest
@testable import RegnskapKit

final class BankStatementTests: XCTestCase {
    static let json = """
    {
      "id": "t-1", "tittel": "t", "selskap": "t", "beskrivelse": "t", "vanskelighet": 3,
      "lov": [{"lov": "bokføringsloven", "paragraf": "§ 7", "tekst": "x"}],
      "hendelser": [{"dato": "2026-03-01", "tekst": "Åpning"}],
      "fasitSaldobalanse": {"1920": 100000, "2000": -100000},
      "fasitJournal": {"entries": [{"dato": "2026-03-01", "tekst": "Åpning", "linjer": [
        {"konto": "1920", "side": "D", "belop": 100000}, {"konto": "2000", "side": "K", "belop": 100000}]}]},
      "valutakurser": {"EUR": [{"dato": "2026-03-04", "kurs": 11.5}]},
      "kontoutskrift": {"konto": "1920", "utgaaende": 100000, "linjer": [
        {"id": "b01", "dato": "2026-03-01", "tekst": "Inngående saldo", "belop": 100000, "bilag": [1]},
        {"id": "b02", "dato": "2026-03-02", "tekst": "Nets", "belop": 12500.5, "bilag": [1]}]}
    }
    """

    func decode(_ json: String) throws -> SandboxCase { try JSONDecoder().decode(SandboxCase.self, from: Data(json.utf8)) }

    func testDecodesStatementAndRates() throws {
        let c = try decode(Self.json)
        let statement = try XCTUnwrap(c.kontoutskrift)
        XCTAssertEqual(statement.konto, "1920")
        XCTAssertEqual(statement.utgaaende, 100000)
        XCTAssertEqual(statement.linjer.map(\.id), ["b01", "b02"])
        XCTAssertEqual(statement.linjer[1].belop, Decimal(string: "12500.5"), "øre survive decoding")
        XCTAssertEqual(statement.linjer[0].bilag, [1])
        XCTAssertEqual(statement.sum, Decimal(string: "112500.5"))
        XCTAssertEqual(statement.line(id: "b02")?.tekst, "Nets")
        XCTAssertNil(statement.line(id: "b99"))
        XCTAssertEqual(c.valutakurser?["EUR"]?.first?.kurs, Decimal(string: "11.5"))
        XCTAssertEqual(c.valutakurser?["EUR"]?.first?.dato, DayKey(year: 2026, month: 3, day: 4))
    }

    func testCaseWithoutTheNewFieldsDecodesToNil() throws {
        var object = try JSONSerialization.jsonObject(with: Data(Self.json.utf8)) as! [String: Any]
        object["kontoutskrift"] = nil
        object["valutakurser"] = nil
        let c = try JSONDecoder().decode(SandboxCase.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(c.kontoutskrift)
        XCTAssertNil(c.valutakurser)
    }

    func testRoundTripKeepsStatementAndRates() throws {
        let c = try decode(Self.json)
        let again = try JSONDecoder().decode(SandboxCase.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(again.kontoutskrift, c.kontoutskrift)
        XCTAssertEqual(again.valutakurser, c.valutakurser)
    }

    func testBankMovementNetsTheEntrysBankLines() {
        let day = DayKey(year: 2026, month: 3, day: 1)
        let salary = JournalEntry(dato: day, tekst: "Lønn", linjer: [
            JournalLine(konto: "5000", side: .debet, belop: 42000),
            JournalLine(konto: "1920", side: .kredit, belop: 21000),
            JournalLine(konto: "1920", side: .kredit, belop: 21000),
        ])
        XCTAssertEqual(salary.bankMovement(), -42000)
        XCTAssertEqual(salary.bankMovement(konto: "1900"), 0)
        let transfer = JournalEntry(dato: day, tekst: "Intern", linjer: [
            JournalLine(konto: "1920", side: .debet, belop: 500), JournalLine(konto: "1920", side: .kredit, belop: 500),
        ])
        XCTAssertEqual(transfer.bankMovement(), 0)
    }
}
