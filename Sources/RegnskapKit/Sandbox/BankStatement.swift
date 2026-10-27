import Foundation

/// One dated exchange rate (NOK per unit of a foreign currency) for a case.
public struct ExchangeRate: Codable, Hashable, Sendable {
    public let dato: DayKey
    @Amount public var kurs: Decimal

    public init(dato: DayKey, kurs: Decimal) { self.dato = dato; self._kurs = Amount(wrappedValue: kurs) }
}

/// One line on the bank statement. `bilag` lists the model-journal entries (1-based) that explain it.
public struct BankLine: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let dato: DayKey
    public let tekst: String
    @Amount public var belop: Decimal
    public let bilag: [Int]

    public init(id: String, dato: DayKey, tekst: String, belop: Decimal, bilag: [Int]) {
        self.id = id; self.dato = dato; self.tekst = tekst; self._belop = Amount(wrappedValue: belop); self.bilag = bilag
    }
}

/// The bank's statement for one account: signed movements (inn plus) and the closing balance.
public struct BankStatement: Codable, Hashable, Sendable {
    public let konto: String
    @Amount public var utgaaende: Decimal
    public let linjer: [BankLine]

    public init(konto: String, utgaaende: Decimal, linjer: [BankLine]) {
        self.konto = konto; self._utgaaende = Amount(wrappedValue: utgaaende); self.linjer = linjer
    }

    public var sum: Decimal { linjer.reduce(0) { $0 + $1.belop } }
    public func line(id: String) -> BankLine? { linjer.first { $0.id == id } }
}
