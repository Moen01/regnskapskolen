import XCTest
@testable import RegnskapKit

final class BankReconciliationTests: XCTestCase {
    func mars(_ d: Int) -> DayKey { DayKey(year: 2026, month: 3, day: d) }
    func line(_ konto: String, _ side: Side, _ belop: Decimal) -> JournalLine { JournalLine(konto: konto, side: side, belop: belop) }

    let opening = JournalEntry(dato: DayKey(year: 2026, month: 3, day: 1), tekst: "Åpning", linjer: [JournalLine(konto: "1920", side: .debet, belop: 100000), JournalLine(konto: "2000", side: .kredit, belop: 100000)])
    let sale1 = JournalEntry(dato: DayKey(year: 2026, month: 3, day: 3), tekst: "Kortsalg tirsdag", linjer: [JournalLine(konto: "1920", side: .debet, belop: 5000), JournalLine(konto: "3000", side: .kredit, belop: 5000)])
    let sale2 = JournalEntry(dato: DayKey(year: 2026, month: 3, day: 4), tekst: "Kortsalg onsdag", linjer: [JournalLine(konto: "1920", side: .debet, belop: 7000), JournalLine(konto: "3000", side: .kredit, belop: 7000)])
    let salary = JournalEntry(dato: DayKey(year: 2026, month: 3, day: 25), tekst: "Lønn", linjer: [JournalLine(konto: "5000", side: .debet, belop: 42000), JournalLine(konto: "1920", side: .kredit, belop: 21000), JournalLine(konto: "1920", side: .kredit, belop: 21000)])
    var journal: Journal { Journal(entries: [opening, sale1, sale2, salary]) }
    var statement: BankStatement {
        BankStatement(konto: "1920", utgaaende: 70000, linjer: [
            BankLine(id: "b01", dato: mars(1), tekst: "Inngående saldo", belop: 100000, bilag: [1]),
            BankLine(id: "b02", dato: mars(9), tekst: "Nets oppgjør", belop: 12000, bilag: [2, 3]),
            BankLine(id: "b03", dato: mars(25), tekst: "Lønn Kari", belop: -21000, bilag: [4]),
            BankLine(id: "b04", dato: mars(25), tekst: "Lønn Ola", belop: -21000, bilag: [4]),
        ])
    }

    func testOneToOneMatch() {
        var r = Reconciliation()
        XCTAssertNil(r.match(bankLineIds: ["b01"], entryIds: [opening.id], statement: statement, journal: journal))
        XCTAssertEqual(r.matches.count, 1)
        XCTAssertTrue(r.isMatched(bankLine: "b01"))
        XCTAssertTrue(r.isMatched(entry: opening.id))
        XCTAssertFalse(r.isMatched(bankLine: "b02"))
    }

    func testOneLineSettlesSeveralVouchersAndSeveralLinesSettleOne() {
        var r = Reconciliation()
        XCTAssertNil(r.match(bankLineIds: ["b02"], entryIds: [sale1.id, sale2.id], statement: statement, journal: journal))
        XCTAssertNil(r.match(bankLineIds: ["b03", "b04"], entryIds: [salary.id], statement: statement, journal: journal))
        XCTAssertEqual(r.matches.count, 2)
    }

    func testDifferenceAndSelectionErrors() {
        var r = Reconciliation()
        XCTAssertEqual(Reconciliation.difference(bankLineIds: ["b02"], entryIds: [sale1.id], statement: statement, journal: journal), 7000)
        XCTAssertEqual(r.check(bankLineIds: ["b02"], entryIds: [sale1.id], statement: statement, journal: journal), .difference(7000))
        XCTAssertEqual(r.check(bankLineIds: [], entryIds: [sale1.id], statement: statement, journal: journal), .emptySide)
        XCTAssertEqual(r.check(bankLineIds: ["zzz"], entryIds: [sale1.id], statement: statement, journal: journal), .unknownId("zzz"))
        XCTAssertNil(Reconciliation.difference(bankLineIds: ["zzz"], entryIds: [], statement: statement, journal: journal))
        r.match(bankLineIds: ["b01"], entryIds: [opening.id], statement: statement, journal: journal)
        XCTAssertEqual(r.check(bankLineIds: ["b01"], entryIds: [opening.id], statement: statement, journal: journal), .alreadyMatched("b01"))
        XCTAssertEqual(r.matches.count, 1, "a failed match adds nothing")
        XCTAssertEqual(MatchError.difference(7000).message, "Differanse 7\u{202F}000,00.")
    }

    func testPruneDropsMatchesThatNoLongerHold() {
        var r = Reconciliation()
        r.match(bankLineIds: ["b01"], entryIds: [opening.id], statement: statement, journal: journal)
        r.match(bankLineIds: ["b03", "b04"], entryIds: [salary.id], statement: statement, journal: journal)
        var edited = journal
        edited.entries[0].linjer[0] = line("1920", .debet, 90000)
        r.prune(statement: statement, journal: edited)
        XCTAssertEqual(r.matches.map(\.bankLineIds), [["b03", "b04"]], "the edited opening is unmatched, the salary stays")
        var deleted = journal
        deleted.entries.removeAll { $0.id == salary.id }
        r.prune(statement: statement, journal: deleted)
        XCTAssertTrue(r.matches.isEmpty)
        r.match(bankLineIds: ["b01"], entryIds: [opening.id], statement: statement, journal: journal)
        r.prune(statement: BankStatement(konto: "1920", utgaaende: 0, linjer: []), journal: journal)
        XCTAssertTrue(r.matches.isEmpty, "a case without lines keeps no matches")
    }

    func testBankCheckIsDoneOnlyWhenEverythingIsExplained() {
        var r = Reconciliation()
        let before = BankCheck(statement: statement, journal: journal, reconciliation: r)
        XCTAssertEqual(before.linesTotal, 4); XCTAssertEqual(before.linesMatched, 0)
        XCTAssertEqual(before.entriesTotal, 4); XCTAssertEqual(before.entriesMatched, 0)
        XCTAssertEqual(before.unmatchedBank, 70000); XCTAssertEqual(before.unmatchedJournal, 70000)
        XCTAssertTrue(before.balanceMatches); XCTAssertFalse(before.done)
        r.match(bankLineIds: ["b01"], entryIds: [opening.id], statement: statement, journal: journal)
        r.match(bankLineIds: ["b02"], entryIds: [sale1.id, sale2.id], statement: statement, journal: journal)
        r.match(bankLineIds: ["b03", "b04"], entryIds: [salary.id], statement: statement, journal: journal)
        XCTAssertTrue(BankCheck(statement: statement, journal: journal, reconciliation: r).done)
        var more = journal
        more.entries.append(JournalEntry(dato: mars(31), tekst: "Gebyr", linjer: [line("7770", .debet, 150), line("1920", .kredit, 150)]))
        let after = BankCheck(statement: statement, journal: more, reconciliation: r)
        XCTAssertEqual(after.entriesTotal, 5); XCTAssertFalse(after.balanceMatches); XCTAssertFalse(after.done)
        more.entries.append(JournalEntry(dato: mars(31), tekst: "Intern", linjer: [line("1920", .debet, 500), line("1920", .kredit, 500)]))
        XCTAssertEqual(BankCheck(statement: statement, journal: more, reconciliation: r).entriesTotal, 5, "a zero net movement is not a bank voucher")
    }

    func testRepeatedIdsCountOnce() {
        var r = Reconciliation()
        XCTAssertEqual(Reconciliation.difference(bankLineIds: ["b03", "b03"], entryIds: [], statement: statement, journal: journal), -21000)
        // bank -21 000 minus journal -42 000 is +21 000
        XCTAssertEqual(r.match(bankLineIds: ["b03", "b03"], entryIds: [salary.id], statement: statement, journal: journal), .difference(21000))
        XCTAssertTrue(r.matches.isEmpty)
        XCTAssertNil(r.match(bankLineIds: ["b01", "b01"], entryIds: [opening.id, opening.id], statement: statement, journal: journal))
        XCTAssertEqual(r.matches.first?.bankLineIds, ["b01"]); XCTAssertEqual(r.matches.first?.entryIds, [opening.id])
    }

    func testEntryFromBankLineMatchesTheLine() {
        let fee = BankLine(id: "b09", dato: mars(31), tekst: "Gebyr", belop: -150, bilag: [])
        let entry = JournalEntry(bankLine: fee)
        XCTAssertEqual(entry.dato, mars(31)); XCTAssertEqual(entry.tekst, "Gebyr")
        XCTAssertEqual(entry.linjer.count, 2)
        XCTAssertEqual(entry.linjer[0].konto, "1920"); XCTAssertEqual(entry.linjer[0].side, .kredit); XCTAssertEqual(entry.linjer[0].belop, 150)
        XCTAssertEqual(entry.linjer[1].konto, ""); XCTAssertEqual(entry.linjer[1].belop, 0)
        XCTAssertEqual(JournalEntry(bankLine: BankLine(id: "x", dato: mars(1), tekst: "Renter", belop: 40, bilag: [])).linjer[0].side, .debet)
        let zero = JournalEntry(bankLine: BankLine(id: "z", dato: mars(1), tekst: "Null", belop: 0, bilag: []))
        XCTAssertEqual(zero.linjer[0].side, .kredit); XCTAssertEqual(zero.linjer[0].belop, 0)
        let s = BankStatement(konto: "1920", utgaaende: statement.utgaaende - 150, linjer: statement.linjer + [fee])
        var j = journal; j.entries.append(entry)
        XCTAssertNil(Reconciliation().check(bankLineIds: ["b09"], entryIds: [entry.id], statement: s, journal: j))
    }
}
