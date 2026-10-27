# Bankavstemming og valuta i sandkassen: implementasjonsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En sandkasse-case kan ha en kontoutskrift for 1920 som brukeren avstemmer mot sine egne bilag, med samlebetalinger, delte utbetalinger, gebyrer fra banklinjen og valutadifferanser; Claude kan lage slike caser og validatoren forkaster dem som ikke stemmer.

**Architecture:** All logikk i `RegnskapKit` (modell, validator, avstemming, sjekk), ren og testbar; appen holder bare tilstand og tegner. Casefilen får to valgfrie felt (`kontoutskrift`, `valutakurser`), brukerens avstemming lagres i en egen fil ved siden av journalen. Én validator (`SandboxCaseValidator`) brukes av både testene og Claude-kjøreren.

**Tech Stack:** Swift 6, SwiftUI (macOS), Swift Package Manager, XCTest. Ingen nye avhengigheter.

**Spec:** `docs/superpowers/specs/2026-10-27-bankavstemming-design.md`

## Global Constraints

- `RegnskapKit` importerer aldri SwiftUI/AppKit.
- Norsk bokmål i alt brukeren leser; kode, commit-meldinger og kommentarer på engelsk.
- Ingen nye avhengigheter.
- Gamle casefiler uten `kontoutskrift` skal laste og virke som før.
- `sandkasse.json` beholder formatet sitt; avstemmingen lagres i `avstemming.json`.
- Summer sammenlignes nøyaktig (`Decimal`), aldri med toleranse.
- `bilag` i en banklinje er 1-basert indeks i `fasitJournal.entries`.
- Valutakurser er casens egne tall og står i casefilen, aldri i `satser.json`.
- Kjør `swift test` etter hver oppgave; `swift test --filter Content` etter innhold. Rød validator = ikke ferdig.
- Commit etter hver oppgave, melding på engelsk med trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. Et bilag med 1920 på begge sider (intern overføring, netto 0) skal verken kreves avstemt eller kunne matches; testes i oppgave 4.
2. `avstemming.json` fra en tidligere case når den aktive casen mangler kontoutskrift: alle matcher skal bort; `prune` mot en tom kontoutskrift testes i oppgave 4, og appen nullstiller i oppgave 7.
3. Banklinje med øre (12 500,50) må dekodes til nøyaktig `Decimal` så den matcher et bilag på 12500.5; testes i oppgave 1.
4. Et avstemt bilag som slettes eller endres: matchen forsvinner, ingen hengende id-er; testes i oppgave 4.
5. En case der `fasitSaldobalanse` mangler 1920 men har kontoutskrift: validatoren regner 1920 som 0 og melder avvik mot `utgaaende`; testes i oppgave 2.

---

### Task 1: Modell: kontoutskrift, valutakurser og bankbevegelse

**Files:**
- Create: `Sources/RegnskapKit/Sandbox/BankStatement.swift`
- Modify: `Sources/RegnskapKit/Sandbox/SandboxCase.swift` (felt, CodingKeys, init, decode, encode)
- Modify: `Sources/RegnskapKit/Sandbox/Journal.swift` (`JournalValidator.bank`, `JournalEntry.bankMovement`)
- Test: `Tests/RegnskapKitTests/BankStatementTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct ExchangeRate: Codable, Hashable, Sendable { public let dato: DayKey; @Amount public var kurs: Decimal; public init(dato: DayKey, kurs: Decimal) }
  public struct BankLine: Codable, Hashable, Sendable, Identifiable {
      public let id: String; public let dato: DayKey; public let tekst: String; @Amount public var belop: Decimal; public let bilag: [Int]
      public init(id: String, dato: DayKey, tekst: String, belop: Decimal, bilag: [Int])
  }
  public struct BankStatement: Codable, Hashable, Sendable {
      public let konto: String; @Amount public var utgaaende: Decimal; public let linjer: [BankLine]
      public init(konto: String, utgaaende: Decimal, linjer: [BankLine])
      public var sum: Decimal                       // sum of linjer.belop
      public func line(id: String) -> BankLine?
  }
  // SandboxCase gets: public let kontoutskrift: BankStatement?; public let valutakurser: [String: [ExchangeRate]]?
  // memberwise init gets the two as trailing parameters with default nil.
  extension JournalValidator { public static let bank = "1920" }
  extension JournalEntry { public func bankMovement(konto: String = JournalValidator.bank) -> Decimal }  // debet minus kredit over the entry's lines on that account
  ```

- [ ] **Steg 1: Skriv testen**

```swift
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
```

- [ ] **Steg 2: Kjør testen, den skal feile**

Kjør: `swift test --filter BankStatementTests`
Forventet: kompileringsfeil, `SandboxCase` har ingen `kontoutskrift`.

- [ ] **Steg 3: Implementer typene i `BankStatement.swift`, feltene i `SandboxCase`, `JournalValidator.bank` og `JournalEntry.bankMovement`**

Synthesized `Codable` holder for de tre nye typene; `@Amount` koder tallet. I `SandboxCase`: `decodeIfPresent`/`encodeIfPresent`, nye `CodingKeys`, og de to parameterne sist i den offentlige init-en med standard `nil`.

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter BankStatementTests`
Forventet: 4 tester, 0 feil. Kjør også `swift test --filter SandboxCaseTests` for å se at eksisterende caser fortsatt laster.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Sandbox/BankStatement.swift Sources/RegnskapKit/Sandbox/SandboxCase.swift Sources/RegnskapKit/Sandbox/Journal.swift Tests/RegnskapKitTests/BankStatementTests.swift
git commit -m "feat(sandbox): bank statement and exchange rates on a case"
```

---

### Task 2: `SandboxCaseValidator` i Kit

**Files:**
- Create: `Sources/RegnskapKit/Sandbox/SandboxCaseValidator.swift`
- Modify: `Sources/RegnskapKit/Claude/Tutor.swift` (`makeCase`: bytt de to inline-sjekkene mot validatoren)
- Modify: `Tests/RegnskapKitTests/SandboxCaseTests.swift` (`testCasesLoadAndModelJournalMatchesExpected` bruker validatoren)
- Test: `Tests/RegnskapKitTests/SandboxCaseValidatorTests.swift`

**Interfaces:**
- Consumes: oppgave 1.
- Produces: `public enum SandboxCaseValidator { public static func problems(_ sandboxCase: SandboxCase, chart: ChartOfAccounts, rates: Rates) -> [String] }`

Meldingene (nøyaktig, testene matcher på deler av dem):

| Vilkår | Melding |
|---|---|
| `fasitJournal` nil | `fasitJournal mangler` |
| `lov` tom | `lov mangler` |
| `hendelser` tom | `hendelser mangler` |
| journalfeil | `JournalValidator.problems(...)` sine meldinger |
| saldoavvik | `konto 1920: fasitSaldobalanse 94900 ≠ journalen 94000` |
| ukjent konto i saldobalansen | `konto 9999 i fasitSaldobalanse finnes ikke i kontoplanen` |
| kurs ≤ 0 | `kurs for EUR 2026-03-04 må være større enn null` |
| `konto` ≠ 1920 | `kontoutskrift.konto må være 1920, er 1900` |
| id brukt to ganger | `banklinje-id «b01» er brukt flere ganger` |
| `bilag` tom | `banklinje b02 peker ikke på noe bilag` |
| indeks utenfor | `banklinje b03 peker på bilag 9, journalen har 4` |
| bilag med bankbevegelse uten linje | `bilag 4 («Gebyr») har bankbevegelse −150,00 men ingen banklinje` |
| komponent stemmer ikke | `banklinjene b02 er 12 000,00, bilag 2 gir 5 000,00` |
| sum ≠ utgående | `kontoutskriften summerer til 89 850,00, utgaaende er 1,00` |
| utgående ≠ saldobalanse | `utgaaende 1,00 ≠ 1920 i fasitSaldobalanse 89 850,00` |
| dato i feil måned | `banklinje b03 er datert 2026-04-01, casen er i 2026-03` |

Beløp formateres med `NorwegianFormat.kroner`. Casens måned er `hendelser.first` sin år og måned. Komponentene finnes med union-find over banklinje-id-er og bilagsindekser (kanter fra `bilag`); linjer med ugyldige indekser er alt meldt og holdes utenfor.

- [ ] **Steg 1: Skriv testene**

```swift
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
```

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter SandboxCaseValidatorTests`
Forventet: kompileringsfeil, `SandboxCaseValidator` finnes ikke.

- [ ] **Steg 3: Implementer `SandboxCaseValidator.problems` i `SandboxCaseValidator.swift`**

Rekkefølgen i tabellen over. Sjekkene for journal og saldobalanse er de som i dag ligger i `Tutor.makeCase` og `SandboxCaseTests`; flytt dem hit.

- [ ] **Steg 4: Bytt `Tutor.makeCase` sin inline-validering mot `SandboxCaseValidator.problems`, og la `SandboxCaseTests.testCasesLoadAndModelJournalMatchesExpected` bruke `XCTAssertEqual(SandboxCaseValidator.problems(c, chart:, rates:), [], c.id)` i stedet for de fire assertene om journal, diffs og kontoer**

Behold assertene om `hendelser`, `lov` og antall caser ≥ 1.

- [ ] **Steg 5: Kjør testene, de skal passere**

Kjør: `swift test --filter "SandboxCaseValidatorTests|SandboxCaseTests|ClaudeTests"`
Forventet: alle grønne.

- [ ] **Steg 6: Commit**

```bash
git add Sources/RegnskapKit/Sandbox/SandboxCaseValidator.swift Sources/RegnskapKit/Claude/Tutor.swift Tests/RegnskapKitTests/SandboxCaseValidatorTests.swift Tests/RegnskapKitTests/SandboxCaseTests.swift
git commit -m "feat(sandbox): one case validator for tests and Claude, with bank statement checks"
```

---

### Task 3: Kontoutskrift på `kafe-001`

**Files:**
- Modify: `Innhold/sandkasse/kafe-001.json` (nytt felt `kontoutskrift` etter `fasitSaldobalanse`)
- Test: `Tests/RegnskapKitTests/SandboxCaseTests.swift`

**Interfaces:** Consumes oppgave 1 og 2. Produces: `kafe-001` med 8 banklinjer, alle mønster 1.

- [ ] **Steg 1: Skriv testen i `SandboxCaseTests`**

```swift
    func testKafeHasAStatementThatReconciles() throws {
        let kafe = try XCTUnwrap(SandboxCase.load(folder: ContentLocator.repoContent.appendingPathComponent("sandkasse")).first { $0.id == "kafe-001" })
        let statement = try XCTUnwrap(kafe.kontoutskrift)
        XCTAssertEqual(statement.linjer.count, 8)
        XCTAssertEqual(statement.utgaaende, 94900)
        XCTAssertEqual(statement.linjer.map(\.bilag), [[1], [2], [4], [5], [7], [8], [9], [11]])
        XCTAssertEqual(SandboxCaseValidator.problems(kafe, chart: Self.library.chart, rates: Self.library.rates), [])
    }
```

- [ ] **Steg 2: Kjør testen, den skal feile**

Kjør: `swift test --filter SandboxCaseTests/testKafeHasAStatementThatReconciles`
Forventet: FAIL, `kontoutskrift` er nil.

- [ ] **Steg 3: Legg kontoutskriften inn i `kafe-001.json`**

```json
  "kontoutskrift": {
    "konto": "1920",
    "utgaaende": 94900,
    "linjer": [
      { "id": "b01", "dato": "2026-03-01", "tekst": "Innskudd aksjekapital og egenkapital", "belop": 100000, "bilag": [1] },
      { "id": "b02", "dato": "2026-03-01", "tekst": "Nettgiro Gårdeier AS, husleie mars", "belop": -18750, "bilag": [2] },
      { "id": "b03", "dato": "2026-03-05", "tekst": "Kontantinnskudd uke 10", "belop": 23000, "bilag": [4] },
      { "id": "b04", "dato": "2026-03-10", "tekst": "Kortoppgjør Nets", "belop": 50000, "bilag": [5] },
      { "id": "b05", "dato": "2026-03-15", "tekst": "Nettgiro Grossisten AS", "belop": -9200, "bilag": [7] },
      { "id": "b06", "dato": "2026-03-25", "tekst": "Lønn mars", "belop": -35000, "bilag": [8] },
      { "id": "b07", "dato": "2026-03-26", "tekst": "Skatteetaten, forskuddstrekk", "belop": -15000, "bilag": [9] },
      { "id": "b08", "dato": "2026-03-31", "tekst": "Gebyr", "belop": -150, "bilag": [11] }
    ]
  },
```

- [ ] **Steg 4: Kjør innholdstestene, de skal passere**

Kjør: `swift test --filter "SandboxCaseTests|ContentValidatorTests"`
Forventet: grønt.

- [ ] **Steg 5: Commit**

```bash
git add Innhold/sandkasse/kafe-001.json Tests/RegnskapKitTests/SandboxCaseTests.swift
git commit -m "content(sandbox): bank statement for kafe-001"
```

---

### Task 4: Avstemming og sjekk i Kit

**Files:**
- Create: `Sources/RegnskapKit/Sandbox/BankReconciliation.swift`
- Test: `Tests/RegnskapKitTests/BankReconciliationTests.swift`

**Interfaces:**
- Consumes: oppgave 1 (`BankStatement`, `BankLine`, `JournalEntry.bankMovement`).
- Produces:
  ```swift
  public struct BankMatch: Codable, Hashable, Sendable, Identifiable {
      public var id: UUID; public var bankLineIds: [String]; public var entryIds: [UUID]
      public init(id: UUID = UUID(), bankLineIds: [String], entryIds: [UUID])
  }
  public enum MatchError: Error, Hashable, Sendable {
      case emptySide, unknownId(String), alreadyMatched(String), difference(Decimal)   // bank minus journal
      public var message: String
      // "Velg minst én banklinje og ett bilag." / "Linjen eller bilaget finnes ikke lenger." /
      // "«b01» er allerede avstemt." / "Differanse 7 000,00."  (via NorwegianFormat.kroner)
  }
  public struct Reconciliation: Codable, Hashable, Sendable {
      public var matches: [BankMatch]
      public init(matches: [BankMatch] = [])
      public func isMatched(bankLine id: String) -> Bool
      public func isMatched(entry id: UUID) -> Bool
      /// Bank sum minus journal bank movement for a selection; nil when an id is unknown.
      public static func difference(bankLineIds: [String], entryIds: [UUID], statement: BankStatement, journal: Journal) -> Decimal?
      public func check(bankLineIds: [String], entryIds: [UUID], statement: BankStatement, journal: Journal) -> MatchError?
      @discardableResult public mutating func match(bankLineIds: [String], entryIds: [UUID], statement: BankStatement, journal: Journal) -> MatchError?  // nil = added
      public mutating func remove(id: UUID)
      /// Drops every match that no longer holds: a line or entry gone, or the sums no longer equal.
      public mutating func prune(statement: BankStatement, journal: Journal)
  }
  public struct BankCheck: Hashable, Sendable {
      public let linesTotal: Int, linesMatched: Int, entriesTotal: Int, entriesMatched: Int
      public let unmatchedBank: Decimal, unmatchedJournal: Decimal, bankBalance: Decimal, utgaaende: Decimal
      public var allLinesMatched: Bool; public var allEntriesMatched: Bool; public var balanceMatches: Bool; public var done: Bool
      public init(statement: BankStatement, journal: Journal, reconciliation: Reconciliation)
  }
  extension JournalEntry {
      /// What "Før fra banklinjen" starts with: the line's date and text, a bank line equal to it, and an empty counter line.
      public init(bankLine: BankLine, konto: String = JournalValidator.bank)
  }
  ```
  `entriesTotal` teller bare bilag med `bankMovement() != 0`. `check` prøver i rekkefølgen emptySide, unknownId, alreadyMatched, difference.

- [ ] **Steg 1: Skriv testene**

```swift
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

    func testEntryFromBankLineMatchesTheLine() {
        let fee = BankLine(id: "b09", dato: mars(31), tekst: "Gebyr", belop: -150, bilag: [])
        let entry = JournalEntry(bankLine: fee)
        XCTAssertEqual(entry.dato, mars(31)); XCTAssertEqual(entry.tekst, "Gebyr")
        XCTAssertEqual(entry.linjer.count, 2)
        XCTAssertEqual(entry.linjer[0].konto, "1920"); XCTAssertEqual(entry.linjer[0].side, .kredit); XCTAssertEqual(entry.linjer[0].belop, 150)
        XCTAssertEqual(entry.linjer[1].konto, ""); XCTAssertEqual(entry.linjer[1].belop, 0)
        XCTAssertEqual(JournalEntry(bankLine: BankLine(id: "x", dato: mars(1), tekst: "Renter", belop: 40, bilag: [])).linjer[0].side, .debet)
        let s = BankStatement(konto: "1920", utgaaende: statement.utgaaende - 150, linjer: statement.linjer + [fee])
        var j = journal; j.entries.append(entry)
        XCTAssertNil(Reconciliation().check(bankLineIds: ["b09"], entryIds: [entry.id], statement: s, journal: j))
    }
}
```

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter BankReconciliationTests`
Forventet: kompileringsfeil, `Reconciliation` finnes ikke.

- [ ] **Steg 3: Implementer typene i `BankReconciliation.swift`**

`prune` beholder en match bare når `check`-logikken for dens id-er (uten alreadyMatched-sjekken) gir nil. `difference` summerer `statement.line(id:)` sine beløp minus `journal.entries` sine `bankMovement()`.

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter BankReconciliationTests`
Forventet: 6 tester, 0 feil.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Sandbox/BankReconciliation.swift Tests/RegnskapKitTests/BankReconciliationTests.swift
git commit -m "feat(sandbox): bank reconciliation model, pruning and completion check"
```

---

### Task 5: Skjema, prompt og Claude-kjøreren

**Files:**
- Modify: `Sources/RegnskapKit/Claude/PuzzleSchema.swift` (`sandboxCase`)
- Modify: `Sources/RegnskapKit/Claude/Tutor.swift` (`system(_:temas:)`, `makeCase`)
- Modify: `Sources/RegnskapKit/Sandbox/SandboxCase.swift` (`load(folder:includeGenerated:)`)
- Modify: `Innhold/prompter/sandkasse.md`
- Test: `Tests/RegnskapKitTests/ClaudeTests.swift`

**Interfaces:**
- Consumes: oppgave 2 (validatoren er alt i `makeCase`), oppgave 3 (`kafe-001` har kontoutskrift, brukes som fikstur).
- Produces:
  - `PuzzleSchema.sandboxCase` med `kontoutskrift` (påkrevd) og `valutakurser` (valgfri).
  - `public static func load(folder: URL, includeGenerated: Bool = true) -> [SandboxCase]` på `SandboxCase`; `false` hopper over filer med en mappe `generert` i stien.
  - `func system(_ name: String, temas: [String]) -> String` i `Tutor`: kortene for hvert tema i rekkefølge, uten dubletter (på `id`); `system(_:tema:)` kaller den.
  - `makeCase` bruker `system("sandkasse", temas: [tema, "reskontro-bank", "valuta-korrigeringer"])`, og eksempelet er casen med flest banklinjer blant `load(folder:, includeGenerated: false)`.

Skjema-tillegget:

```swift
let rate = obj(["dato": str, "kurs": num], required: ["dato", "kurs"])
let bankLine = obj(["id": str, "dato": str, "tekst": str, "belop": num, "bilag": arr(.object(["type": .string("integer"), "minimum": .number(1)]))], required: ["id", "dato", "tekst", "belop", "bilag"])
props["kontoutskrift"] = obj(["konto": strEnum(["1920"]), "utgaaende": num, "linjer": arr(bankLine, min: 2)], required: ["konto", "utgaaende", "linjer"])
props["valutakurser"] = .object(["type": .string("object"), "additionalProperties": arr(rate)])
required += ["kontoutskrift"]
```

Nytt avsnitt sist i `Innhold/prompter/sandkasse.md` (ordrett):

```markdown
- **kontoutskrift** for konto 1920: det banken viser. Første linje er åpningsbalansen («Inngående saldo», eller «Innskudd aksjekapital» for et nytt selskap) og peker på åpningsbilaget. Hver linje har `id` («b01», «b02» …), `dato`, `tekst` slik banken skriver den (kort, uten fasit), `belop` signert sett fra kontoen (inn pluss, ut minus) og `bilag`: nummeret på bilagene i `fasitJournal` (1 = første bilag) som linjen gjør opp. Bare bilag med en 1920-linje pekes på; en faktura på kreditt har ingen banklinje. Alle linjer er datert i casens måned. Summen av linjene er lik `utgaaende`, som er lik 1920 i `fasitSaldobalanse`.
- **Mønstre** kontoutskriften skal øve: (1) én linje ↔ ett bilag; (2) én linje ↔ flere bilag, f.eks. kortinnløseren betaler ut tre dagers kortsalg samlet mens salget er bokført per dag; (3) flere linjer ↔ ett bilag, f.eks. ett lønnsbilag med én nettoutbetaling per ansatt; (4) linje med et bilag brukeren lett glemmer: gebyr, renter («Banken belaster …» er en egen hendelse); (5) bilag uten banklinje: minst én faktura står ubetalt ved månedsslutt; (6) valuta med kursdifferanse. Ved vanskelighet 3 og høyere: minst ett av hvert av 2, 3, 4 og 5. Mønster 6 er påkrevd i temaet valuta-korrigeringer og velkomment ved vanskelighet 4 og 5 ellers, aldri der valuta er unaturlig.
- **valutakurser** når casen har valuta: `{ "EUR": [ { "dato": "2026-03-04", "kurs": 11.5 } ] }`, én kurs per dato som brukes. Kursen står også i hendelsesteksten («2 000 EUR, kurs 11,50»). Fakturaen føres til kursen på fakturadagen; betaling til en annen kurs gir kursdifferanse på 8060 (agio) eller 8160 (disagio) i betalingsbilaget, så 1920-linjen blir lik banklinjen. Kursene er casens egne tall.
```

Og i `makeCase` sin prompt: etter «… en fasitJournal som gir nøyaktig den saldobalansen» legg til «, og en kontoutskrift for 1920 der hver linje peker på bilagene (1-basert nummer i fasitJournal) den gjør opp».

- [ ] **Steg 1: Skriv testene i `ClaudeTests`**

```swift
    func testSandboxSchemaRequiresTheStatement() {
        let schema = PuzzleSchema.sandboxCase
        XCTAssertTrue(schema["required"]?.array?.contains(.string("kontoutskrift")) ?? false)
        XCTAssertNotNil(schema["properties"]?["valutakurser"])
        XCTAssertFalse(schema["required"]?.array?.contains(.string("valutakurser")) ?? true)
    }

    func testPromptMentionsTheStatement() throws {
        let prompt = try XCTUnwrap(Tutor.prompt(named: "sandkasse", root: ContentLocator.repoContent))
        XCTAssertTrue(prompt.contains("kontoutskrift"))
        XCTAssertTrue(prompt.contains("valutakurser"))
    }

    func kafeEnvelope(edit: (inout [String: JSONValue]) -> Void = { _ in }) throws -> Data {
        let kafe = try XCTUnwrap(SandboxCase.load(folder: ContentLocator.repoContent.appendingPathComponent("sandkasse")).first { $0.id == "kafe-001" })
        var object = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(kafe)).object!
        edit(&object)
        return JSONValue.object(["type": .string("result"), "is_error": .bool(false), "result": .string("{}"), "session_id": .string("s"), "structured_output": .object(object)]).data
    }

    func testMakeCaseRejectsAStatementThatDoesNotReconcile() async throws {
        let data = try kafeEnvelope { object in
            var statement = object["kontoutskrift"]!.object!
            var lines = statement["linjer"]!.array!
            var second = lines[1].object!; second["belop"] = .number(-18000); lines[1] = .object(second)
            statement["linjer"] = .array(lines); object["kontoutskrift"] = .object(statement)
        }
        let tutor = Tutor(library: Self.library, runner: ClaudeRunner(processes: FakeProcesses(reply: ProcessResult(exitCode: 0, stdout: data, stderr: Data()))), model: "haiku")
        do { _ = try await tutor.makeCase(tema: "mva"); XCTFail("expected invalidPuzzle") }
        catch ClaudeError.invalidPuzzle(let problems) { XCTAssertTrue(problems.contains { $0.contains("b02") }, problems.joined(separator: "; ")) }
        catch { XCTFail("\(error)") }
    }

    func testMakeCaseAttachesBankAndCurrencyCardsAndAcceptsAGoodCase() async throws {
        let fake = FakeProcesses(reply: ProcessResult(exitCode: 0, stdout: try kafeEnvelope(), stderr: Data()))
        let tutor = Tutor(library: Self.library, runner: ClaudeRunner(processes: fake), model: "haiku")
        let made = try await tutor.makeCase(tema: "lonn")
        XCTAssertEqual(made.kontoutskrift?.linjer.count, 8)
        let args = fake.calls.last!
        let system = args[args.firstIndex(of: "--system-prompt")! + 1]
        XCTAssertTrue(system.contains("## Valuta og retting av feil"))
        XCTAssertTrue(system.contains("## Reskontro, tap på fordringer"))
        XCTAssertTrue(system.contains("## " + Self.library.rules(tema: "lonn").first!.tittel), "the topic's own cards are still there")
        let prompt = args[args.firstIndex(of: "-p")! + 1]
        XCTAssertTrue(prompt.contains("kontoutskrift"))
        let richest = SandboxCase.load(folder: ContentLocator.repoContent.appendingPathComponent("sandkasse"), includeGenerated: false)
            .max { ($0.kontoutskrift?.linjer.count ?? 0) < ($1.kontoutskrift?.linjer.count ?? 0) }!.id
        XCTAssertTrue(prompt.contains("\"id\":\"\(richest)\""), "the example is the hand-written case with the most bank lines")
    }

    func testLoadCanSkipGeneratedCases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sandkasse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("generert"), withIntermediateDirectories: true)
        let kafe = try Data(contentsOf: ContentLocator.repoContent.appendingPathComponent("sandkasse/kafe-001.json"))
        try kafe.write(to: root.appendingPathComponent("kafe-001.json"))
        try kafe.write(to: root.appendingPathComponent("generert/x.json"))
        XCTAssertEqual(SandboxCase.load(folder: root).count, 2)
        XCTAssertEqual(SandboxCase.load(folder: root, includeGenerated: false).count, 1)
    }
```

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter ClaudeTests`
Forventet: `testSandboxSchemaRequiresTheStatement`, `testPromptMentionsTheStatement`, `testMakeCaseAttachesBankAndCurrencyCards…` og `testLoadCanSkipGeneratedCases` feiler (skjema uten feltet, prompt uten ordet, kort mangler, `includeGenerated` finnes ikke).

- [ ] **Steg 3: Implementer skjemaet, `load(folder:includeGenerated:)`, `system(_:temas:)`, `makeCase`-endringene og promptavsnittet**

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter "ClaudeTests|SandboxCaseTests"`
Forventet: grønt.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Claude/PuzzleSchema.swift Sources/RegnskapKit/Claude/Tutor.swift Sources/RegnskapKit/Sandbox/SandboxCase.swift Innhold/prompter/sandkasse.md Tests/RegnskapKitTests/ClaudeTests.swift
git commit -m "feat(claude): cases come with a bank statement; bank and currency cards always in the prompt"
```

---

### Task 6: Håndskrevet case `bank-001` med alle mønstrene

**Files:**
- Create: `Innhold/sandkasse/bank-001.json`
- Test: `Tests/RegnskapKitTests/SandboxCaseTests.swift`

**Interfaces:** Consumes oppgave 1–3. Produces: casen Claude bruker som eksempel (flest banklinjer) og som skjermbildene bruker.

Casen, fast bestemt så fasiten er entydig. Fjellsport AS, Lillehammer (sone 1), nettbutikk og butikk for friluftsutstyr, avgiftspliktig 25 %, to ansatte. April 2026. `vanskelighet` 4. `lov`: bokføringsloven § 7 og regnskapsloven § 5-9 fra kortet `valuta-korrigeringer`, og bokføringsforskriften § 3-1 fra kortet `reskontro-tap-purring` (tekstene fra kortene). `beskrivelse` som i `kafe-001`, pluss én setning om at Bank-fanen skal avstemmes til slutt.

| Nr | Dato | Hendelse (tekst til brukeren) | Bilag i fasit | Mønster |
|---|---|---|---|---|
| 1 | 01.04 | Åpningsbalanse: bank 150 000, kundefordringer 40 000 (faktura til Fjellgruppa AS 25 000 og Turlaget 15 000), varelager 60 000; aksjekapital 100 000, annen egenkapital 150 000 | D1920 150000, D1500 40000, D1400 60000, K2000 100000, K2050 150000 | åpning |
| 2 | 02.04 | Varekjøp fra Bergans-grossisten AS 40 000 + 25 % mva på kreditt | D4300 40000 (mva 25), D2710 10000, K2400 50000 | 5 |
| 3 | 07.04 | Kortsalg tirsdag 12 500 inkl. 25 % mva (kortinnløser) | D1920 12500, K3000 10000 (mva 25), K2700 2500 | 2 |
| 4 | 08.04 | Kortsalg onsdag 10 000 inkl. 25 % mva | D1920 10000, K3000 8000 (mva 25), K2700 2000 | 2 |
| 5 | 09.04 | Kortsalg torsdag 15 000 inkl. 25 % mva | D1920 15000, K3000 12000 (mva 25), K2700 3000 | 2 |
| 6 | 10.04 | Fjellgruppa AS betaler fakturaen på 25 000 | D1920 25000, K1500 25000 | 1 |
| 7 | 13.04 | Lisens for nettbutikk-plattform fra Alpenwerk GmbH (Tyskland): 2 000 EUR, kurs 11,50, omvendt avgiftsplikt, 30 dagers kreditt. Hint: «Hva gjør du med mva når selger er utenlandsk, og hvilken kurs føres fakturaen til?» | D6790 23000 (mva omvendt), D2710 5750, K2700 5750, K2400 23000 | 5, 6 |
| 8 | 15.04 | Bergans-grossisten betales | D2400 50000, K1920 50000 | 1 |
| 9 | 20.04 | Turlaget betaler 15 000 | D1920 15000, K1500 15000 | 1 |
| 10 | 24.04 | Alpenwerk betales: 2 000 EUR, kurs 11,80. Hint: «Fakturaen ble ført til 23 000. Hva skjer med de 600?» | D2400 23000, D8160 600, K1920 23600 | 6 |
| 11 | 24.04 | Lønn april, to ansatte: brutto 30 000 hver, forskuddstrekk 9 000 hver, netto utbetalt fra bank til hver; arbeidsgiveravgift 14,1 % | D5000 60000, K2600 18000, K1920 21000, K1920 21000, D5400 8460, K2770 8460 | 3 |
| 12 | 27.04 | Forskuddstrekket betales til Skatteetaten (første virkedag etter) | D2600 18000, K1920 18000 | 1 |
| 13 | 28.04 | Salg på faktura til Turlaget: 20 000 + 25 % mva, forfall i mai | D1500 25000, K3000 20000 (mva 25), K2700 5000 | 5 |
| 14 | 30.04 | Kortinnløseren trekker gebyr for april, 450 kr, ingen mva. Hint: «Står dette på kontoutskriften før du har ført det?» | D7770 450, K1920 450 | 4 |

Kontoutskrift, `utgaaende` 93 450:

| id | dato | tekst | belop | bilag |
|---|---|---|---|---|
| b01 | 2026-04-01 | Inngående saldo | 150000 | [1] |
| b02 | 2026-04-13 | Nets oppgjør uke 15 | 37500 | [3, 4, 5] |
| b03 | 2026-04-10 | Innbet. Fjellgruppa AS | 25000 | [6] |
| b04 | 2026-04-15 | Nettgiro Bergans-grossisten AS | -50000 | [8] |
| b05 | 2026-04-20 | Innbet. Turlaget | 15000 | [9] |
| b06 | 2026-04-24 | Utland Alpenwerk GmbH EUR 2 000,00 | -23600 | [10] |
| b07 | 2026-04-24 | Lønn Kari Nordmann | -21000 | [11] |
| b08 | 2026-04-24 | Lønn Ola Hansen | -21000 | [11] |
| b09 | 2026-04-27 | Skatteetaten forskuddstrekk | -18000 | [12] |
| b10 | 2026-04-30 | Nets gebyr april | -450 | [14] |

`valutakurser`: `{ "EUR": [ { "dato": "2026-04-13", "kurs": 11.5 }, { "dato": "2026-04-24", "kurs": 11.8 } ] }`.

`fasitSaldobalanse` regnes ut fra bilagene (debet pluss, kredit minus, sum null); 1920 skal bli 93 450. Kontonavnene står i `Innhold/kontoplan.json`; `6790` er «Annen fremmed tjeneste».

- [ ] **Steg 1: Skriv testen i `SandboxCaseTests`**

```swift
    func testBank001CoversEveryPattern() throws {
        let c = try XCTUnwrap(SandboxCase.load(folder: ContentLocator.repoContent.appendingPathComponent("sandkasse")).first { $0.id == "bank-001" })
        let statement = try XCTUnwrap(c.kontoutskrift), journal = try XCTUnwrap(c.fasitJournal)
        XCTAssertEqual(SandboxCaseValidator.problems(c, chart: Self.library.chart, rates: Self.library.rates), [])
        XCTAssertTrue(statement.linjer.contains { $0.bilag.count >= 2 }, "pattern 2: one line, several vouchers")
        let referenced = statement.linjer.flatMap(\.bilag)
        XCTAssertTrue(Set(referenced).contains { n in referenced.filter { $0 == n }.count >= 2 }, "pattern 3: several lines, one voucher")
        XCTAssertTrue(journal.entries.contains { $0.linjer.contains { $0.konto == "7770" } && $0.bankMovement() != 0 }, "pattern 4: a fee booked from the statement")
        XCTAssertTrue(journal.entries.contains { $0.bankMovement() == 0 && $0.linjer.contains { ["1500", "2400"].contains($0.konto) } }, "pattern 5: an open post without a bank line")
        XCTAssertTrue(journal.entries.contains { $0.linjer.contains { $0.konto == "8160" || $0.konto == "8060" } }, "pattern 6: a currency difference")
        XCTAssertEqual(c.valutakurser?["EUR"]?.count, 2)
        XCTAssertEqual(statement.utgaaende, 93450)
    }
```

- [ ] **Steg 2: Kjør testen, den skal feile**

Kjør: `swift test --filter SandboxCaseTests/testBank001CoversEveryPattern`
Forventet: FAIL, casen finnes ikke.

- [ ] **Steg 3: Skriv `Innhold/sandkasse/bank-001.json` etter tabellene, med `/sandkasse-case` sin fremgangsmåte for journal og saldobalanse**

- [ ] **Steg 4: Kjør innholdstestene, de skal passere**

Kjør: `swift test --filter "SandboxCaseTests|SandboxCaseValidatorTests|ClaudeTests"`
Forventet: grønt. `ClaudeTests` sin eksempel-assert regner selv ut at `bank-001` (10 linjer) nå er eksempelet.

- [ ] **Steg 5: Commit**

```bash
git add Innhold/sandkasse/bank-001.json Tests/RegnskapKitTests/SandboxCaseTests.swift
git commit -m "content(sandbox): bank-001, a month with every reconciliation pattern and a currency difference"
```

---

### Task 7: Tilstand og lagring i appen

**Files:**
- Modify: `Sources/Regnskapsskolen/App/AppStore.swift` (to nye egenskaper)
- Modify: `Sources/Regnskapsskolen/App/AppStore+Sandbox.swift`

**Interfaces:**
- Consumes: oppgave 4.
- Produces (på `AppStore`):
  ```swift
  enum SandboxPane: String, CaseIterable { case journal = "Journal", bank = "Bank" }   // in AppStore+Sandbox.swift
  var reconciliation = Reconciliation()
  var sandboxPane: SandboxPane = .journal
  static var reconciliationURL: URL        // applicationSupport/avstemming.json
  var bankStatement: BankStatement?        // activeCase?.kontoutskrift
  var bankCheck: BankCheck?                // nil without a statement
  func pruneReconciliation()               // prune against the statement; no statement = Reconciliation()
  @discardableResult func matchBank(lineIds: [String], entryIds: [UUID]) -> MatchError?   // then saveSandbox()
  func unmatchBank(_ id: UUID)             // then saveSandbox()
  func bookFromBankLine(_ line: BankLine)  // append JournalEntry(bankLine:), match it with the line, saveSandbox()
  ```
  `loadSandbox` leser `avstemming.json` (manglende/ødelagt fil = tom) og kaller `pruneReconciliation`. `saveSandbox` kaller `pruneReconciliation` før den skriver begge filene. `startCase` og `clearSandbox` setter `reconciliation = Reconciliation()` og `sandboxPane = .journal`. `loadSandboxDemo` velger casen med id `bank-001`, laster de åtte første bilagene fra modelljournalen, og matcher hver gruppe banklinjer (gruppert på `bilag`) der alle bilagene er blant de åtte, unntatt den siste gruppen, så skjermbildet viser begge tilstander.

- [ ] **Steg 1: Implementer egenskapene og funksjonene**

- [ ] **Steg 2: Bygg**

Kjør: `swift build`
Forventet: ingen feil. (Logikken er testet i oppgave 4; appen er tynn.)

- [ ] **Steg 3: Commit**

```bash
git add Sources/Regnskapsskolen/App/AppStore.swift Sources/Regnskapsskolen/App/AppStore+Sandbox.swift
git commit -m "feat(app): reconciliation state next to the sandbox journal"
```

---

### Task 8: Bank-visningen, Journal | Bank-velgeren og kurser i casepanelet

**Files:**
- Create: `Sources/Regnskapsskolen/UI/Sandbox/BankView.swift`
- Modify: `Sources/Regnskapsskolen/UI/Sandbox/SandboxView.swift` (velger i midtpanelet; kurstabell i casepanelet)
- Modify: `Sources/Regnskapsskolen/App/Screenshots.swift` (`sandbox-bank.png`)

**Interfaces:** Consumes oppgave 7. Produces `struct BankView: View`.

`BankView`:
- `@State private var selectedLines: Set<String>`, `@State private var selectedEntries: Set<UUID>`, `@State private var error: MatchError?`.
- Uten `store.bankStatement`: `ContentUnavailableView("Denne casen har ingen kontoutskrift", systemImage: "building.columns")`.
- Topp: `SectionHeader(title: "Kontoutskrift 1920", subtitle: "Utgående \(kroner) · \(linesMatched) av \(linesTotal) linjer avstemt")`.
- To kolonner i en `HStack`: venstre uavstemte banklinjer, høyre uavstemte bilag med bankbevegelse (`store.sandbox.entries.filter { $0.bankMovement() != 0 && !matched }`). Rad = `Button` med `.buttonStyle(.plain)`, valgt rad får `Color.skole.opacity(0.15)` som bakgrunn. Radtekst: dato (`NorwegianFormat.date`), tekst (`lineLimit(1)`), beløp i `.debet`-farge når positivt og `.kredit` når negativt, `monospacedDigit`. Hver banklinje har en liten knapp «Før fra banklinjen» (`store.bookFromBankLine`).
- Under kolonnene: `DisclosureGroup("Avstemt (\(matches.count))")` med én rad per match (banklinjenes tekster · bilagenes tekster · beløp) og «Opphev» (`store.unmatchBank`).
- Bunn: «Valgt: bank X · bilag Y · differanse Z» (`Reconciliation.difference`), knappen **Avstem** (`.borderedProminent`, `.tint(.skole)`), aktiv bare når differansen er 0 og begge sett er ikke-tomme; ved klikk `store.matchBank`, tøm utvalgene, vis `error?.message` i `Color.bad` hvis noe gikk galt.
- Nederst, når `store.bankCheck?.done == true`: `Label("Banken er avstemt. Godt jobbet!", systemImage: "checkmark.seal.fill")` i `Color.ok`.

`SandboxView`: midtpanelet blir `VStack(spacing: 0) { Picker("Visning", selection: $store.sandboxPane) { ForEach(SandboxPane.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().controlSize(.small).padding(.horizontal, 16).padding(.top, 10); switch … { case .journal: JournalEditor(); case .bank: BankView() } }`. I casepanelet, etter hendelsene og før lovhenvisningene: når `sandboxCase.valutakurser` finnes, `Text("Kurser i casen").font(.subheadline.weight(.semibold))` og én linje per valuta og dato («EUR 12.04.2026: 11,50»), `kroner(kurs)`.

`Screenshots.capture`: etter `sandbox.png`-løkka (den tegner `AppSection.allCases`), sett `store.sandboxPane = .bank`, `navigation.section = .sandbox`, `snap(MainView()…, to: "sandbox-bank.png")`, og sett `sandboxPane` tilbake til `.journal`.

- [ ] **Steg 1: Skriv `BankView`, endre `SandboxView`, legg til skjermbildet**

- [ ] **Steg 2: Bygg og tegn skjermbildene**

Kjør:
```sh
make app && REGNSKAP_SCREENSHOTS=/tmp/shots build/Regnskapsskolen.app/Contents/MacOS/Regnskapsskolen
```
Forventet: `Skrev skjermbilder til /tmp/shots`. Åpne `/tmp/shots/sandbox-bank.png` (Read-verktøyet viser PNG) og se: velgeren «Journal | Bank» med Bank valgt, overskrift «Kontoutskrift 1920», to kolonner, gruppen «Avstemt (…)», knappen «Avstem» nederst. `/tmp/shots/sandbox.png` skal se ut som før med velgeren over journalen.

- [ ] **Steg 3: Kjør alle testene**

Kjør: `swift test`
Forventet: grønt.

- [ ] **Steg 4: Commit**

```bash
git add Sources/Regnskapsskolen/UI/Sandbox/BankView.swift Sources/Regnskapsskolen/UI/Sandbox/SandboxView.swift Sources/Regnskapsskolen/App/Screenshots.swift
git commit -m "feat(app): Bank pane for matching the statement against the journal"
```

---

### Task 9: Fasit-fanen viser begge vilkårene

**Files:**
- Modify: `Sources/Regnskapsskolen/UI/Sandbox/ReportsView.swift` (`check(_:)`)

**Interfaces:** Consumes oppgave 7 (`store.bankCheck`, `store.bankStatement`).

`check(_:)` med aktiv case viser to blokker under hverandre:

1. **Saldobalanse**: som i dag (grønn `Label("Saldobalansen stemmer med fasiten", systemImage: "checkmark.seal.fill")` eller avvikstabellen).
2. **Bank**: uten kontoutskrift `Text("Casen har ingen kontoutskrift.").foregroundStyle(.secondary)`; ellers grønn `Label("Banken er avstemt", systemImage: "checkmark.seal.fill")` når `done`, eller `Label("\(linesMatched) av \(linesTotal) banklinjer avstemt, \(entriesMatched) av \(entriesTotal) bilag. Saldo 1920 \(kroner(bankBalance)) mot utgående \(kroner(utgaaende)).", systemImage: "exclamationmark.triangle.fill")` i `Color.warn`.

«Godt jobbet!»-setningen vises bare når saldobalansen stemmer og banken er avstemt (eller casen mangler kontoutskrift). Tom journal: dagens tekst «Før bilagene, så sammenlignes …».

- [ ] **Steg 1: Endre `check(_:)`**

- [ ] **Steg 2: Bygg og se**

Kjør: `make app`. Forventet: bygger. Be Andreas åpne appen, velge `bank-001`, føre to bilag og se Fasit-fanen; skjermbildemodusen viser ikke Fasit-fanen (fanen er lokal tilstand).

- [ ] **Steg 3: Commit**

```bash
git add Sources/Regnskapsskolen/UI/Sandbox/ReportsView.swift
git commit -m "feat(app): Fasit tab reports the bank reconciliation too"
```

---

### Task 10: Dokumentasjon og skill

**Files:**
- Modify: `docs/innhold.md` (avsnittet «Sandkassecaser»)
- Modify: `docs/claude.md` (raden «Lag en case med Claude»)
- Modify: `CLAUDE.md` (tabellraden `Innhold/sandkasse` og regel 1)
- Modify: `.claude/skills/sandkasse-case/SKILL.md`

- [ ] **Steg 1: `docs/innhold.md`**: etter dagens avsnitt legg til:

```markdown
To valgfrie felt gjør casen avstembar: `kontoutskrift` (`konto` 1920, `utgaaende`, `linjer` med `id`, `dato`, `tekst`, `belop` signert sett fra kontoen og `bilag`: 1-baserte numre på bilagene i `fasitJournal` som linjen gjør opp) og `valutakurser` (valuta → liste av `dato` og `kurs`; casens egne tall, aldri fra `satser.json`). Bare bilag med en 1920-linje pekes på. `SandboxCaseValidator` krever at hver gruppe av linjer og bilag summerer likt, at hvert bilag med bankbevegelse har en linje, og at summen av linjene er lik `utgaaende` og 1920 i `fasitSaldobalanse`.

Mønstre: (1) én linje ↔ ett bilag; (2) én linje ↔ flere bilag (kortinnløser betaler ut flere dagers salg samlet); (3) flere linjer ↔ ett bilag (ett lønnsbilag, én utbetaling per ansatt); (4) gebyr og renter som føres fra banklinjen; (5) åpen post uten banklinje; (6) valuta med kursdifferanse på 8060/8160. `bank-001` har alle seks.
```

- [ ] **Steg 2: `docs/claude.md`**: i tabellraden for «Lag en case med Claude» endre «Journalen må stemme med saldobalansen, ellers avvises den» til «Journalen må stemme med saldobalansen og kontoutskriften med journalen, ellers avvises den. Eksempelet Claude får er den håndskrevne casen med flest banklinjer; kortene for bank og valuta legges alltid ved.»

- [ ] **Steg 3: `CLAUDE.md`**: tabellraden `Innhold/sandkasse/*.json` får «…, og `kontoutskrift` som må stemme med journalen.» Under regel 1 legg til setningen: «Valutakurser i en case er casens egne tall og står i casefilen (`valutakurser`), ikke i `satser.json`.»

- [ ] **Steg 4: `.claude/skills/sandkasse-case/SKILL.md`**: nytt steg etter steg 3: «Skriv `kontoutskrift` for 1920: første linje er åpningsbalansen, hver linje peker på bilagsnumrene den gjør opp, summen er lik `utgaaende` og 1920 i saldobalansen. Ta med minst ett av mønstrene 2–5 (se `docs/innhold.md`), og `valutakurser` når casen har valuta.» Steg 1 nevner `bank-001.json` som mal ved siden av `kafe-001.json`.

- [ ] **Steg 5: Kjør alt**

Kjør: `swift test`
Forventet: grønt.

- [ ] **Steg 6: Commit**

```bash
git add docs/innhold.md docs/claude.md CLAUDE.md .claude/skills/sandkasse-case/SKILL.md
git commit -m "docs: bank statement and exchange rates in sandbox cases"
```
