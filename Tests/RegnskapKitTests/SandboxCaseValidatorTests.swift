import XCTest
@testable import RegnskapKit

final class SandboxCaseValidatorTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    func mars(_ d: Int) -> DayKey { DayKey(year: 2026, month: 3, day: d) }
    func line(_ konto: String, _ side: Side, _ belop: Decimal, _ mva: String? = nil) -> JournalLine { JournalLine(konto: konto, side: side, belop: belop, mvaKode: mva) }
    func problems(_ c: SandboxCase) -> [String] { SandboxCaseValidator.problems(c, chart: Self.library.chart, rates: Self.library.rates) }

    func makeCase(journal: Journal, balances: [String: Decimal], statement: BankStatement?, rates: [String: [ExchangeRate]]? = nil) -> SandboxCase {
        SandboxCase(id: "v-1", tittel: "t", selskap: "t", beskrivelse: "t", vanskelighet: 3,
                    lov: [LawReference(lov: "bokføringsloven", paragraf: "§ 7", tekst: "x")],
                    hendelser: journal.entries.map { CaseEvent(dato: $0.dato, tekst: $0.tekst, hint: nil) },
                    fasitSaldobalanse: balances, fasitJournal: journal, kontoutskrift: statement, valutakurser: rates)
    }

    /// Opening, a purchase on credit (no bank), its payment, a fee: three bank lines, all 1 to 1.
    var simpleJournal: Journal {
        Journal(entries: [
            JournalEntry(dato: mars(1), tekst: "Åpning", linjer: [line("1920", .debet, 100000), line("2000", .kredit, 100000)]),
            JournalEntry(dato: mars(3), tekst: "Varekjøp", linjer: [line("4300", .debet, 8000, "25"), line("2710", .debet, 2000), line("2400", .kredit, 10000)]),
            JournalEntry(dato: mars(15), tekst: "Betalt leverandør", linjer: [line("2400", .debet, 10000), line("1920", .kredit, 10000)]),
            JournalEntry(dato: mars(31), tekst: "Gebyr", linjer: [line("7770", .debet, 150), line("1920", .kredit, 150)]),
        ])
    }
    let simpleBalances: [String: Decimal] = ["1920": 89850, "2000": -100000, "4300": 8000, "2710": 2000, "7770": 150]
    var simpleStatement: BankStatement {
        BankStatement(konto: "1920", utgaaende: 89850, linjer: [
            BankLine(id: "b01", dato: mars(1), tekst: "Inngående saldo", belop: 100000, bilag: [1]),
            BankLine(id: "b02", dato: mars(15), tekst: "Nettgiro", belop: -10000, bilag: [3]),
            BankLine(id: "b03", dato: mars(31), tekst: "Gebyr", belop: -150, bilag: [4]),
        ])
    }
    func simple(_ change: (inout [BankLine], inout Decimal) -> Void = { _, _ in }) -> SandboxCase {
        var lines = simpleStatement.linjer, utgaaende = simpleStatement.utgaaende
        change(&lines, &utgaaende)
        return makeCase(journal: simpleJournal, balances: simpleBalances, statement: BankStatement(konto: "1920", utgaaende: utgaaende, linjer: lines))
    }

    /// Opening, two card-sale days paid out as one line, a salary paid out as two lines.
    var componentJournal: Journal {
        Journal(entries: [
            JournalEntry(dato: mars(1), tekst: "Åpning", linjer: [line("1920", .debet, 100000), line("2000", .kredit, 100000)]),
            JournalEntry(dato: mars(3), tekst: "Kortsalg tirsdag", linjer: [line("1920", .debet, 5000), line("3000", .kredit, 4000, "25"), line("2700", .kredit, 1000)]),
            JournalEntry(dato: mars(4), tekst: "Kortsalg onsdag", linjer: [line("1920", .debet, 7000), line("3000", .kredit, 5600, "25"), line("2700", .kredit, 1400)]),
            JournalEntry(dato: mars(25), tekst: "Lønn", linjer: [line("5000", .debet, 42000), line("1920", .kredit, 21000), line("1920", .kredit, 21000)]),
        ])
    }
    let componentBalances: [String: Decimal] = ["1920": 70000, "2000": -100000, "3000": -9600, "2700": -2400, "5000": 42000]
    func component(lines: [BankLine]) -> SandboxCase {
        makeCase(journal: componentJournal, balances: componentBalances, statement: BankStatement(konto: "1920", utgaaende: 70000, linjer: lines))
    }

    func testValidCaseHasNoProblems() { XCTAssertEqual(problems(simple()), []) }

    func testCaseWithoutStatementIsStillValid() {
        XCTAssertEqual(problems(makeCase(journal: simpleJournal, balances: simpleBalances, statement: nil)), [])
    }

    func testLineAmountMustMatchItsVouchers() {
        let p = problems(simple { lines, _ in lines[1] = BankLine(id: "b02", dato: self.mars(15), tekst: "Nettgiro", belop: -9000, bilag: [3]) })
        XCTAssertTrue(p.contains { $0.contains("b02") && $0.contains("bilag 3") }, p.joined(separator: "; "))
    }

    func testEveryVoucherWithBankMovementNeedsALine() {
        let p = problems(simple { lines, utgaaende in lines.removeLast(); utgaaende = 90000 })
        XCTAssertTrue(p.contains { $0.contains("bilag 4") && $0.contains("ingen banklinje") }, p.joined(separator: "; "))
    }

    func testUtgaaendeMustMatchLinesAndBalance() {
        let p = problems(simple { _, utgaaende in utgaaende = 1 })
        XCTAssertTrue(p.contains { $0.contains("summerer til") }, p.joined(separator: "; "))
        XCTAssertTrue(p.contains { $0.contains("utgaaende") && $0.contains("fasitSaldobalanse") }, p.joined(separator: "; "))
        // A balance without 1920 counts as zero and is reported too.
        var balances = simpleBalances; balances["1920"] = nil; balances["1900"] = 89850
        let q = problems(makeCase(journal: simpleJournal, balances: balances, statement: simpleStatement))
        XCTAssertTrue(q.contains { $0.contains("utgaaende") && $0.contains("0,00") }, q.joined(separator: "; "))
    }

    func testBilagIndexMustExist() {
        let p = problems(simple { lines, _ in lines[2] = BankLine(id: "b03", dato: self.mars(31), tekst: "Gebyr", belop: -150, bilag: [9]) })
        XCTAssertTrue(p.contains { $0.contains("b03") && $0.contains("bilag 9") }, p.joined(separator: "; "))
    }

    func testLineMayNotPointAtAVoucherWithoutBankMovement() {
        let p = problems(simple { lines, _ in lines[1] = BankLine(id: "b02", dato: self.mars(15), tekst: "Nettgiro", belop: -10000, bilag: [3, 2]) })
        XCTAssertTrue(p.contains { $0.contains("b02") && $0.contains("bilag 2") && $0.contains("ikke har bankbevegelse") }, p.joined(separator: "; "))
    }

    func testLineIdsMustBeUniqueAndPointAtSomething() {
        let p = problems(simple { lines, _ in lines[1] = BankLine(id: "b01", dato: self.mars(15), tekst: "Nettgiro", belop: -10000, bilag: []) })
        XCTAssertTrue(p.contains { $0.contains("«b01»") && $0.contains("flere ganger") }, p.joined(separator: "; "))
        XCTAssertTrue(p.contains { $0.contains("peker ikke på noe bilag") }, p.joined(separator: "; "))
    }

    func testStatementKontoMustBeBank() {
        let c = makeCase(journal: simpleJournal, balances: simpleBalances, statement: BankStatement(konto: "1900", utgaaende: 89850, linjer: simpleStatement.linjer))
        XCTAssertTrue(problems(c).contains { $0.contains("må være 1920") })
    }

    func testDatesMustSitInTheCasesMonth() {
        let p = problems(simple { lines, _ in lines[2] = BankLine(id: "b03", dato: DayKey(year: 2026, month: 4, day: 1), tekst: "Gebyr", belop: -150, bilag: [4]) })
        XCTAssertTrue(p.contains { $0.contains("b03") && $0.contains("2026-03") }, p.joined(separator: "; "))
    }

    func testRatesMustBePositive() {
        let c = makeCase(journal: simpleJournal, balances: simpleBalances, statement: simpleStatement, rates: ["EUR": [ExchangeRate(dato: mars(4), kurs: 0)]])
        XCTAssertTrue(problems(c).contains { $0.contains("kurs for EUR") })
    }

    func testOneLineForSeveralVouchersAndSeveralLinesForOneVoucher() {
        let good = component(lines: [
            BankLine(id: "b01", dato: mars(1), tekst: "Inngående saldo", belop: 100000, bilag: [1]),
            BankLine(id: "b02", dato: mars(9), tekst: "Nets oppgjør", belop: 12000, bilag: [2, 3]),
            BankLine(id: "b03", dato: mars(25), tekst: "Lønn Kari", belop: -21000, bilag: [4]),
            BankLine(id: "b04", dato: mars(25), tekst: "Lønn Ola", belop: -21000, bilag: [4]),
        ])
        XCTAssertEqual(problems(good), [])
        let bad = component(lines: [
            BankLine(id: "b01", dato: mars(1), tekst: "Inngående saldo", belop: 100000, bilag: [1]),
            BankLine(id: "b02", dato: mars(9), tekst: "Nets oppgjør", belop: 12000, bilag: [2]),
            BankLine(id: "b03", dato: mars(25), tekst: "Lønn Kari", belop: -21000, bilag: [4]),
            BankLine(id: "b04", dato: mars(25), tekst: "Lønn Ola", belop: -21000, bilag: [4]),
        ])
        let p = problems(bad)
        XCTAssertTrue(p.contains { $0.contains("b02") && $0.contains("bilag 2 gir") }, p.joined(separator: "; "))
        XCTAssertTrue(p.contains { $0.contains("bilag 3") && $0.contains("ingen banklinje") }, p.joined(separator: "; "))
    }
}
