import Foundation

/// The one check for a sandbox case, used by the tests and by the Claude runner. Messages are
/// Norwegian because the author (Claude or a human) reads them. The bank checks only run when the
/// case has a `kontoutskrift`.
public enum SandboxCaseValidator {
    public static func problems(_ sandboxCase: SandboxCase, chart: ChartOfAccounts, rates: Rates) -> [String] {
        var out: [String] = []
        if sandboxCase.fasitJournal == nil { out.append("fasitJournal mangler") }
        if sandboxCase.lov.isEmpty { out.append("lov mangler") }
        if sandboxCase.hendelser.isEmpty { out.append("hendelser mangler") }
        guard let journal = sandboxCase.fasitJournal else { return out }

        out += JournalValidator.problems(journal, chart: chart, rates: rates).map(\.message)
        out += sandboxCase.compare(journal: journal, chart: chart).map { "konto \($0.konto): fasitSaldobalanse \($0.forventet) ≠ journalen \($0.faktisk)" }
        for konto in sandboxCase.fasitSaldobalanse.keys.sorted() where !chart.contains(konto) {
            out.append("konto \(konto) i fasitSaldobalanse finnes ikke i kontoplanen")
        }
        for (currency, list) in (sandboxCase.valutakurser ?? [:]).sorted(by: { $0.key < $1.key }) {
            for rate in list where rate.kurs <= 0 { out.append("kurs for \(currency) \(rate.dato.string) må være større enn null") }
        }
        if let statement = sandboxCase.kontoutskrift {
            out += bankProblems(statement, journal: journal, balances: sandboxCase.fasitSaldobalanse, month: sandboxCase.hendelser.first?.dato)
        }
        return out
    }

    private static func bankProblems(_ statement: BankStatement, journal: Journal, balances: [String: Decimal], month: DayKey?) -> [String] {
        let bank = JournalValidator.bank
        var out: [String] = []
        if statement.konto != bank { out.append("kontoutskrift.konto må være \(bank), er \(statement.konto)") }

        var seen = Set<String>(), reported = Set<String>()
        for id in statement.linjer.map(\.id) where !seen.insert(id).inserted && reported.insert(id).inserted {
            out.append("banklinje-id «\(id)» er brukt flere ganger")
        }

        // Lines with a bad voucher reference are reported here and kept out of the component check.
        var valid: [BankLine] = []
        for line in statement.linjer {
            if line.bilag.isEmpty { out.append("banklinje \(line.id) peker ikke på noe bilag"); continue }
            let bad = line.bilag.filter { $0 < 1 || $0 > journal.entries.count }
            for index in bad { out.append("banklinje \(line.id) peker på bilag \(index), journalen har \(journal.entries.count)") }
            if bad.isEmpty {
                // A voucher with no net bank movement is not a bank voucher, so a line must not point at it.
                for index in line.bilag where journal.entries[index - 1].bankMovement(konto: bank) == 0 {
                    out.append("banklinje \(line.id) peker på bilag \(index) som ikke har bankbevegelse")
                }
                valid.append(line)
            }
        }

        let referenced = Set(valid.flatMap(\.bilag))
        for (offset, entry) in journal.entries.enumerated() where !referenced.contains(offset + 1) && entry.bankMovement(konto: bank) != 0 {
            out.append("bilag \(offset + 1) («\(entry.tekst)») har bankbevegelse \(NorwegianFormat.kroner(entry.bankMovement(konto: bank))) men ingen banklinje")
        }

        for component in components(of: valid) {
            let lineSum = component.lines.reduce(Decimal(0)) { $0 + $1.belop }
            let voucherSum = component.vouchers.reduce(Decimal(0)) { $0 + journal.entries[$1 - 1].bankMovement(konto: bank) }
            if lineSum != voucherSum {
                out.append("banklinjene \(component.lines.map(\.id).joined(separator: ", ")) er \(NorwegianFormat.kroner(lineSum)), bilag \(component.vouchers.map(String.init).joined(separator: ", ")) gir \(NorwegianFormat.kroner(voucherSum))")
            }
        }

        if statement.sum != statement.utgaaende {
            out.append("kontoutskriften summerer til \(NorwegianFormat.kroner(statement.sum)), utgaaende er \(NorwegianFormat.kroner(statement.utgaaende))")
        }
        let expected = balances[bank] ?? 0
        if statement.utgaaende != expected {
            out.append("utgaaende \(NorwegianFormat.kroner(statement.utgaaende)) ≠ \(bank) i fasitSaldobalanse \(NorwegianFormat.kroner(expected))")
        }

        if let month {
            for line in statement.linjer where line.dato.year != month.year || line.dato.month != month.month {
                out.append("banklinje \(line.id) er datert \(line.dato.string), casen er i \(monthText(month))")
            }
        }
        return out
    }

    private static func monthText(_ day: DayKey) -> String { String(day.string.prefix(7)) }

    /// Groups lines and vouchers that explain each other (union-find over line positions and voucher
    /// indexes, edges from `bilag`). Lines are keyed by position so a repeated id cannot merge groups.
    private static func components(of lines: [BankLine]) -> [(lines: [BankLine], vouchers: [Int])] {
        var parent: [String: String] = [:]
        func find(_ x: String) -> String {
            var root = x
            while let up = parent[root], up != root { root = up }
            parent[x] = root
            return root
        }
        func union(_ a: String, _ b: String) {
            for key in [a, b] where parent[key] == nil { parent[key] = key }
            parent[find(a)] = find(b)
        }
        for (position, line) in lines.enumerated() { for index in line.bilag { union("L\(position)", "B\(index)") } }

        var groups: [String: (lines: [BankLine], vouchers: Set<Int>)] = [:]
        for (position, line) in lines.enumerated() {
            let root = find("L\(position)")
            groups[root, default: ([], [])].lines.append(line)
            groups[root]!.vouchers.formUnion(line.bilag)
        }
        return groups.values.map { ($0.lines, $0.vouchers.sorted()) }.sorted { ($0.lines.first?.id ?? "") < ($1.lines.first?.id ?? "") }
    }
}
