import Foundation

public struct TrialBalanceRow: Hashable, Sendable, Identifiable {
    public let konto: String
    public let navn: String
    public let debet: Decimal
    public let kredit: Decimal
    /// Debet plus, kredit minus.
    public let saldo: Decimal
    public var id: String { konto }
}

public struct Statements: Hashable, Sendable {
    public let inntekter: Decimal
    public let kostnader: Decimal
    public let resultat: Decimal
    public let eiendeler: Decimal
    public let gjeld: Decimal
    public let egenkapital: Decimal
    /// Eiendeler minus (gjeld + egenkapital): equals the result until it is transferred.
    public let differanse: Decimal
}

public struct VATSettlement: Hashable, Sendable {
    public let utgaaende: Decimal
    public let inngaaende: Decimal
    public var aaBetale: Decimal { utgaaende - inngaaende }
}

public struct TAccountPosting: Hashable, Sendable, Identifiable {
    public let entryId: UUID
    public let dato: DayKey
    public let tekst: String
    public let belop: Decimal
    public var id: UUID { entryId }
}

public struct TAccount: Hashable, Sendable {
    public let konto: String
    public let debet: [TAccountPosting]
    public let kredit: [TAccountPosting]
    public var sumDebet: Decimal { debet.reduce(0) { $0 + $1.belop } }
    public var sumKredit: Decimal { kredit.reduce(0) { $0 + $1.belop } }
    public var saldo: Decimal { sumDebet - sumKredit }
}

/// Reports over a `Journal`.
public enum Reports {
    public static func trialBalance(_ journal: Journal, chart: ChartOfAccounts) -> [TrialBalanceRow] {
        var debet: [String: Decimal] = [:], kredit: [String: Decimal] = [:]
        for entry in journal.entries {
            for line in entry.linjer {
                debet[line.konto, default: 0] += line.debet
                kredit[line.konto, default: 0] += line.kredit
            }
        }
        return Set(debet.keys).union(kredit.keys).sorted().map { konto in
            TrialBalanceRow(konto: konto, navn: chart.name(konto), debet: debet[konto] ?? 0, kredit: kredit[konto] ?? 0, saldo: (debet[konto] ?? 0) - (kredit[konto] ?? 0))
        }
    }

    public static func statements(_ journal: Journal, chart: ChartOfAccounts) -> Statements {
        var inntekter: Decimal = 0, kostnader: Decimal = 0, eiendeler: Decimal = 0, gjeld: Decimal = 0, egenkapital: Decimal = 0
        for (konto, saldo) in journal.balances() {
            switch chart.account(konto)?.type {
            case .inntekt: inntekter -= saldo
            case .kostnad: kostnader += saldo
            case .eiendel: eiendeler += saldo
            case .gjeld: gjeld -= saldo
            case .egenkapital, .disponering: egenkapital -= saldo
            case nil: break
            }
        }
        let resultat = inntekter - kostnader
        return Statements(inntekter: inntekter, kostnader: kostnader, resultat: resultat, eiendeler: eiendeler, gjeld: gjeld, egenkapital: egenkapital,
                          differanse: eiendeler - (gjeld + egenkapital))
    }

    public static func vatSettlement(_ journal: Journal) -> VATSettlement {
        let b = journal.balances()
        return VATSettlement(utgaaende: -(b[JournalValidator.utgaaende] ?? 0), inngaaende: b[JournalValidator.inngaaende] ?? 0)
    }

    public static func tAccount(konto: String, journal: Journal) -> TAccount {
        var debet: [TAccountPosting] = [], kredit: [TAccountPosting] = []
        for entry in journal.entries.sorted(by: { $0.dato < $1.dato }) {
            for line in entry.linjer where line.konto == konto {
                let posting = TAccountPosting(entryId: entry.id, dato: entry.dato, tekst: entry.tekst, belop: line.belop)
                if line.side == .debet { debet.append(posting) } else { kredit.append(posting) }
            }
        }
        return TAccount(konto: konto, debet: debet, kredit: kredit)
    }
}
