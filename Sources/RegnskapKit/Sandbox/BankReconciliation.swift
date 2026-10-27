import Foundation

private extension Array where Element: Hashable {
    /// The elements in order, each once.
    var unique: [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

/// One match the user made: some bank lines that together equal some vouchers' bank movement.
public struct BankMatch: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var bankLineIds: [String]
    public var entryIds: [UUID]

    public init(id: UUID = UUID(), bankLineIds: [String], entryIds: [UUID]) {
        self.id = id; self.bankLineIds = bankLineIds; self.entryIds = entryIds
    }
}

public enum MatchError: Error, Hashable, Sendable {
    case emptySide, unknownId(String), alreadyMatched(String), difference(Decimal)   // bank minus journal

    public var message: String {
        switch self {
        case .emptySide: "Velg minst én banklinje og ett bilag."
        case .unknownId: "Linjen eller bilaget finnes ikke lenger."
        case .alreadyMatched(let id): "«\(id)» er allerede avstemt."
        case .difference(let d): "Differanse \(NorwegianFormat.kroner(d))."
        }
    }
}

/// The user's matches between statement lines and their own vouchers; saved as JSON.
public struct Reconciliation: Codable, Hashable, Sendable {
    public var matches: [BankMatch]
    public init(matches: [BankMatch] = []) { self.matches = matches }

    public func isMatched(bankLine id: String) -> Bool { matches.contains { $0.bankLineIds.contains(id) } }
    public func isMatched(entry id: UUID) -> Bool { matches.contains { $0.entryIds.contains(id) } }

    /// The selected bank lines' sum and the selected vouchers' bank movement, with repeated ids counted once; nil when an id is unknown.
    public static func sums(bankLineIds: [String], entryIds: [UUID], statement: BankStatement, journal: Journal) -> (bank: Decimal, journal: Decimal)? {
        var bank: Decimal = 0, books: Decimal = 0
        for id in bankLineIds.unique {
            guard let line = statement.line(id: id) else { return nil }
            bank += line.belop
        }
        for id in entryIds.unique {
            guard let entry = journal.entries.first(where: { $0.id == id }) else { return nil }
            books += entry.bankMovement(konto: statement.konto)
        }
        return (bank, books)
    }

    /// Bank sum minus journal bank movement for a selection; nil when an id is unknown.
    public static func difference(bankLineIds: [String], entryIds: [UUID], statement: BankStatement, journal: Journal) -> Decimal? {
        sums(bankLineIds: bankLineIds, entryIds: entryIds, statement: statement, journal: journal).map { $0.bank - $0.journal }
    }

    public func check(bankLineIds: [String], entryIds: [UUID], statement: BankStatement, journal: Journal) -> MatchError? {
        validate(bankLineIds: bankLineIds, entryIds: entryIds, statement: statement, journal: journal, ignoringMatches: false)
    }

    @discardableResult
    public mutating func match(bankLineIds: [String], entryIds: [UUID], statement: BankStatement, journal: Journal) -> MatchError? {
        if let error = check(bankLineIds: bankLineIds, entryIds: entryIds, statement: statement, journal: journal) { return error }
        matches.append(BankMatch(bankLineIds: bankLineIds.unique, entryIds: entryIds.unique))
        return nil
    }

    public mutating func remove(id: UUID) { matches.removeAll { $0.id == id } }

    /// Drops every match that no longer holds: a line or entry gone, or the sums no longer equal.
    public mutating func prune(statement: BankStatement, journal: Journal) {
        // Filter into a copy: validate reads self, so it cannot run inside a mutation of `matches`.
        matches = matches.filter {
            validate(bankLineIds: $0.bankLineIds, entryIds: $0.entryIds, statement: statement, journal: journal, ignoringMatches: true) == nil
        }
    }

    // `ignoringMatches` lets prune re-check a match against itself without tripping alreadyMatched.
    private func validate(bankLineIds: [String], entryIds: [UUID], statement: BankStatement, journal: Journal, ignoringMatches: Bool) -> MatchError? {
        // A repeated id must count once, or a selection could be padded to hit a zero difference.
        let bankLineIds = bankLineIds.unique, entryIds = entryIds.unique
        if bankLineIds.isEmpty || entryIds.isEmpty { return .emptySide }
        for id in bankLineIds where statement.line(id: id) == nil { return .unknownId(id) }
        for id in entryIds where !journal.entries.contains(where: { $0.id == id }) { return .unknownId(id.uuidString) }
        if !ignoringMatches {
            for id in bankLineIds where isMatched(bankLine: id) { return .alreadyMatched(id) }
            for id in entryIds where isMatched(entry: id) { return .alreadyMatched(id.uuidString) }
        }
        guard let diff = Self.difference(bankLineIds: bankLineIds, entryIds: entryIds, statement: statement, journal: journal) else {
            return .emptySide
        }
        return diff == 0 ? nil : .difference(diff)
    }
}

/// How far the reconciliation has got: what is matched, what is left, and whether the books end where the bank does.
public struct BankCheck: Hashable, Sendable {
    public let linesTotal: Int, linesMatched: Int, entriesTotal: Int, entriesMatched: Int
    public let unmatchedBank: Decimal, unmatchedJournal: Decimal, bankBalance: Decimal, utgaaende: Decimal

    public var allLinesMatched: Bool { linesMatched == linesTotal }
    public var allEntriesMatched: Bool { entriesMatched == entriesTotal }
    public var balanceMatches: Bool { bankBalance == utgaaende }
    public var done: Bool { allLinesMatched && allEntriesMatched && balanceMatches }

    public init(statement: BankStatement, journal: Journal, reconciliation: Reconciliation) {
        let lines = statement.linjer
        let openLines = lines.filter { !reconciliation.isMatched(bankLine: $0.id) }
        // A voucher with zero net movement on the account is not a bank voucher, so it needs no match.
        let bankEntries = journal.entries.filter { $0.bankMovement(konto: statement.konto) != 0 }
        let openEntries = bankEntries.filter { !reconciliation.isMatched(entry: $0.id) }
        linesTotal = lines.count; linesMatched = lines.count - openLines.count
        entriesTotal = bankEntries.count; entriesMatched = bankEntries.count - openEntries.count
        unmatchedBank = openLines.reduce(0) { $0 + $1.belop }
        unmatchedJournal = openEntries.reduce(0) { $0 + $1.bankMovement(konto: statement.konto) }
        bankBalance = journal.entries.reduce(0) { $0 + $1.bankMovement(konto: statement.konto) }
        utgaaende = statement.utgaaende
    }
}

extension JournalEntry {
    /// What "Før fra banklinjen" starts with: the line's date and text, a bank line equal to it, and an empty counter line.
    public init(bankLine: BankLine, konto: String = JournalValidator.bank) {
        let side: Side = bankLine.belop > 0 ? .debet : .kredit
        self.init(dato: bankLine.dato, tekst: bankLine.tekst, linjer: [
            JournalLine(konto: konto, side: side, belop: abs(bankLine.belop)),
            JournalLine(konto: "", side: side == .debet ? .kredit : .debet, belop: 0),
        ])
    }
}
