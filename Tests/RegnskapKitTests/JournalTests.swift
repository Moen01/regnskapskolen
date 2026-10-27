import XCTest
@testable import RegnskapKit

final class JournalTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    let d1 = DayKey(string: "2026-03-01")!, d2 = DayKey(string: "2026-03-15")!

    func entry(_ day: DayKey, _ text: String, _ lines: [(String, Side, Decimal, String?)]) -> JournalEntry {
        JournalEntry(dato: day, tekst: text, linjer: lines.map { JournalLine(konto: $0.0, side: $0.1, belop: $0.2, mvaKode: $0.3) })
    }

    var journal: Journal {
        Journal(entries: [
            entry(d1, "Salg", [("1920", .debet, 12500, nil), ("3000", .kredit, 10000, "25"), ("2700", .kredit, 2500, nil)]),
            entry(d1, "Husleie", [("6300", .debet, 4000, nil), ("1920", .kredit, 4000, nil)]),
            entry(d2, "Rekvisita", [("6800", .debet, 800, "25"), ("2710", .debet, 200, nil), ("2400", .kredit, 1000, nil)]),
        ])
    }

    func testTrialBalanceAndStatementsSplit() {
        let rows = Reports.trialBalance(journal, chart: Self.library.chart)
        XCTAssertEqual(rows.map(\.konto), ["1920", "2400", "2700", "2710", "3000", "6300", "6800"])
        XCTAssertEqual(rows.first { $0.konto == "1920" }?.saldo, 8500)
        XCTAssertEqual(rows.first { $0.konto == "3000" }?.saldo, -10000, "kredit is minus")
        XCTAssertEqual(rows.reduce(Decimal(0)) { $0 + $1.saldo }, 0, "a balanced journal sums to zero")
        let s = Reports.statements(journal, chart: Self.library.chart)
        XCTAssertEqual(s.inntekter, 10000)
        XCTAssertEqual(s.kostnader, 4800)
        XCTAssertEqual(s.resultat, 5200)
        XCTAssertEqual(s.eiendeler, 8500, "2710 sits in class 2 in NS 4102, so it nets against the mva liability, not the assets")
        XCTAssertEqual(s.gjeld, 1000 + 2500 - 200)
        XCTAssertEqual(s.egenkapital, 0)
        XCTAssertEqual(s.differanse, s.resultat, "before closing, the balance differs by exactly the result")
    }

    func testPerDateBalanceProblem() {
        var j = journal
        j.entries.append(entry(d2, "Skjev", [("6300", .debet, 100, nil), ("1920", .kredit, 90, nil)]))
        let problems = JournalValidator.problems(j, chart: Self.library.chart, rates: Self.library.rates)
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems[0].entryId, j.entries[3].id)
        XCTAssertTrue(problems[0].message.contains("balanserer ikke"), problems[0].message)
    }

    func testUnknownAccountProblem() {
        var j = journal
        j.entries.append(entry(d2, "Ukjent", [("9999", .debet, 100, nil), ("1920", .kredit, 100, nil)]))
        let problems = JournalValidator.problems(j, chart: Self.library.chart, rates: Self.library.rates)
        XCTAssertTrue(problems.contains { $0.message.contains("9999") })
    }

    func testVATLineMismatchFlagged() {
        var j = journal
        // 25 % of 800 is 200, not 150.
        j.entries[2] = entry(d2, "Rekvisita", [("6800", .debet, 800, "25"), ("2710", .debet, 150, nil), ("2400", .kredit, 950, nil)])
        let problems = JournalValidator.problems(j, chart: Self.library.chart, rates: Self.library.rates)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].message.contains("200"), problems[0].message)
        XCTAssertTrue(JournalValidator.problems(journal, chart: Self.library.chart, rates: Self.library.rates).isEmpty)
    }

    func testVATSettlementAndTAccount() {
        let vat = Reports.vatSettlement(journal)
        XCTAssertEqual(vat.utgaaende, 2500)
        XCTAssertEqual(vat.inngaaende, 200)
        XCTAssertEqual(vat.aaBetale, 2300)
        let t = Reports.tAccount(konto: "1920", journal: journal)
        XCTAssertEqual(t.debet.map(\.belop), [12500])
        XCTAssertEqual(t.kredit.map(\.belop), [4000])
        XCTAssertEqual(t.saldo, 8500)
    }

    func testJournalRoundTrip() throws {
        let original = journal
        let data = try JSONEncoder().encode(original)
        let again = try JSONDecoder().decode(Journal.self, from: data)
        XCTAssertEqual(again, original)
        let withoutIds = Data(#"{"entries":[{"dato":"2026-03-01","tekst":"x","linjer":[{"konto":"1920","side":"D","belop":"1 250,00"}]}]}"#.utf8)
        let decoded = try JSONDecoder().decode(Journal.self, from: withoutIds)
        XCTAssertEqual(decoded.entries[0].linjer[0].belop, 1250, "ids are optional in files and amounts may be Norwegian strings")
    }
}
