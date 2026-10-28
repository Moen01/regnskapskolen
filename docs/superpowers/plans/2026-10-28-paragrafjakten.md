# Paragrafjakten: implementasjonsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spill-fanen blir et PvE-spill: tolv regioner (temaene), møter der du velger paragraf og svarer på oppgaven, fangst og utvikling som speiler Leitner-boksene, HP i kroner, gym-ledere (edge cases), en dungeon (bank-001), samling, Arena/Dojo beholdt, og Ukens utfordring med delbar kode.

**Architecture:** All spillogikk i `RegnskapKit/Games/Adventure/` som rene verdityper med injisert seed, ingen `Date()`; appen holder økten i `AppStore`, bruker `PuzzleSession` og dagens inndata-visninger inne i møtet, og tegner kart, region, møte, samling og utfordring i SwiftUI. Fremdrift går gjennom `Scheduler.record` som før; nye felt i `GameProgress` er valgfrie.

**Tech Stack:** Swift 6, SwiftUI (macOS), SwiftPM, XCTest. Ingen nye avhengigheter, ingen SpriteKit, ingen lyd.

**Spec:** `docs/superpowers/specs/2026-10-28-paragrafjakten-design.md`

## Global Constraints

- Kit importerer aldri UI og bruker aldri `Date()` i spillogikken; seed og «i dag» kommer inn som argumenter.
- Norsk bokmål i alt brukeren leser; kode, kommentarer, commit-meldinger på engelsk.
- Tall (konstanter i Kit): HP 10 000; feil koster `vanskelighet × 500`; riktig gir skade `vanskelighet × 100`, ×2 ved trekk-treff; regionens mål = halvparten av summen av `vanskelighet × 100` utenom gym-lederen; tom HP → regionens skade −25 %; gym-leder-bonus 200 XP; opplåsing ved ≥ 60 % fanget i forrige region med oppgaver; trinn 0 vill, 1 Klekket, 2 Ung, 3 Voksen, 4 Mester; trekk-knapper høyst 6 inkl. «Ingen regel», to avledere; ukens utfordring 10 godkjente quiz/mva/sak, seed `isoYear × 100 + isoWeek`.
- Alle fangster og flukter går gjennom `Scheduler.record`; én telling per oppgave per dag som ellers.
- `fremdrift.json` fra før leses uten feil.
- Commit etter hver oppgave, melding på engelsk med trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. `swift test` etter hver oppgave.

## Review Focus

1. Tom region (0 oppgaver) og region med 1 oppgave: kjeden låser ikke, gym-lederen er eneste møte, målet er 0 → full fra start. Testes i oppgave 3 og 4.
2. Oppgave uten treffbart trekk: trekk-steget hoppes over og ingen bonus. Testes i oppgave 2 og 4.
3. Feil svar på en alt fanget skapning: ut av samlingen (boks 0) og HP-tap; feil på en vill: HP-tap, fortsatt vill. Testes i oppgave 4.
4. Tom HP: økten avsluttes, skaden faller 25 %, fangster beholdes. Testes i oppgave 4.
5. Ukens utfordring gir samme ti oppgaver uavhengig av «vis utkast» og av oppgavenes filrekkefølge. Testes i oppgave 5.

---

### Task 1: `GameProgress`-felt, ISO-uke og fire nye merker

**Files:**
- Modify: `Sources/RegnskapKit/Learning/GameProgress.swift` (`regionDamage`, `weekly`, egen `init(from:)`)
- Modify: `Sources/RegnskapKit/Util/DayKey.swift` (`isoWeek`)
- Modify: `Sources/RegnskapKit/Games/Badges.swift` (fire merker, nye hendelser)
- Test: `Tests/RegnskapKitTests/ProgressStoreTests.swift`, `Tests/RegnskapKitTests/DayKeyTests.swift`, `Tests/RegnskapKitTests/BadgesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  // GameProgress
  public var regionDamage: [String: Int]   // tema → damage so far
  public var weekly: [String: Int]         // "2026-44" → score
  // DayKey
  public var isoWeek: (year: Int, week: Int)
  public var weekKey: String               // "2026-44"
  // Badges.all gains, in this order after "tretti-dager":
  //   "forste-fangst" Første fangst «Den første skapningen i samlingen» symbol "sparkle"
  //   "samler" Samler «25 skapninger i samlingen» symbol "square.grid.3x3.fill"
  //   "hele-regionen" Hele regionen «Alle skapningene i én region på Voksen eller høyere» symbol "map.fill"
  //   "tolv-merker" Tolv merker «Alle gym-merkene» symbol "crown.fill"
  // GameEvent gains:
  case caught(total: Int)                  // creatures in the collection after this catch
  case regionMastered                      // every puzzle in a region at box ≥ 3
  case gymBadges(count: Int)               // gym badges held after this one
  ```
  Regler: `forste-fangst` ved `.caught(total: 1)` (eller mer, første gang), `samler` ved `total ≥ 25`, `hele-regionen` ved `.regionMastered`, `tolv-merker` ved `count ≥ 12`.

- [ ] **Steg 1: Skriv testene**

I `ProgressStoreTests`:
```swift
    func testRegionDamageAndWeeklyRoundTripAndDefaultEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fremdrift-\(UUID().uuidString).json")
        try Data(#"{"puzzles":{},"days":{},"game":{"xp":5,"badges":{},"bestScores":{},"counters":{}}}"#.utf8).write(to: url)
        let store = ProgressStore(url: url)
        XCTAssertEqual(store.load().game.regionDamage, [:])
        XCTAssertEqual(store.load().game.weekly, [:])
        var progress = LearnerProgress()
        progress.game.regionDamage["mva"] = 350
        progress.game.weekly["2026-44"] = 1850
        try store.save(progress)
        XCTAssertEqual(store.load().game, progress.game)
    }
```
I `DayKeyTests`:
```swift
    func testISOWeek() {
        XCTAssertEqual(DayKey(year: 2026, month: 10, day: 28).isoWeek.week, 44)
        XCTAssertEqual(DayKey(year: 2026, month: 10, day: 28).weekKey, "2026-44")
        XCTAssertEqual(DayKey(year: 2026, month: 12, day: 31).isoWeek.week, 53, "2026 has 53 ISO weeks")
        XCTAssertEqual(DayKey(year: 2027, month: 1, day: 1).weekKey, "2026-53", "the first days of 2027 belong to 2026's last week")
    }
```
I `BadgesTests`: endre `testCatalogHasEightBadgesWithUniqueIds` til tolv (`count == 12`, id-listen forlenget med de fire), og legg til:
```swift
    func testCollectionBadges() {
        XCTAssertEqual(award(.caught(total: 1)), ["forste-fangst"])
        XCTAssertEqual(award(.caught(total: 24)), [])
        XCTAssertEqual(award(.caught(total: 25)), ["samler"])
        XCTAssertEqual(award(.regionMastered), ["hele-regionen"])
        XCTAssertEqual(award(.gymBadges(count: 11)), [])
        XCTAssertEqual(award(.gymBadges(count: 12)), ["tolv-merker"])
    }
```

- [ ] **Steg 2: Kjør, de skal feile** — `swift test --filter "ProgressStoreTests|DayKeyTests|BadgesTests"`: kompileringsfeil (`regionDamage`, `isoWeek`, `.caught`).

- [ ] **Steg 3: Implementer.** `GameProgress` får egen `init(from:)` med `decodeIfPresent` for de to nye feltene (de gamle fire som før). `isoWeek` via `Calendar.norwegian.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)`.

- [ ] **Steg 4: Kjør, de skal passere** — samme filter, så `swift test`.

- [ ] **Steg 5: Commit** — `git add` de seks filene; `git commit -m "feat(games): region damage, weekly results, ISO weeks and collection badges"` + trailer.

---

### Task 2: Trekk: paragrafpar fra regelkortene

**Files:**
- Create: `Sources/RegnskapKit/Games/Adventure/Moves.swift`
- Test: `Tests/RegnskapKitTests/MovesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Move: Hashable, Sendable, Identifiable {
      public let lov: String        // "merverdiavgiftsloven"
      public let paragraf: String   // "§ 3-30"
      public var id: String { "\(lov) \(paragraf)" }
      public var label: String { id }
  }
  public enum Moves {
      public static let maxOptions = 6, distractors = 2
      /// Every (lov, paragraf) pair a set of cards covers: each paragraf on the card paired with each lov the card names (its `lov` is a comma list), deduplicated, sorted by id.
      public static func pairs(from cards: [RuleCard]) -> [Move]
      public static func hits(_ move: Move, _ puzzle: Puzzle) -> Bool          // puzzle.lov contains the same lov and paragraf
      public static func canHit(_ puzzle: Puzzle, regionCards: [RuleCard]) -> Bool
      /// Region pairs plus `distractors` pairs from other cards (seeded, never a pair that hits the puzzle), at most `maxOptions - 1` moves; the UI adds «Ingen regel». Empty when the region cannot hit.
      public static func options(for puzzle: Puzzle, regionCards: [RuleCard], otherCards: [RuleCard], seed: UInt64) -> [Move]
  }
  ```

- [ ] **Steg 1: Skriv testene**

```swift
import XCTest
@testable import RegnskapKit

final class MovesTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    var mva: [RuleCard] { Self.library.rules(tema: "mva") }
    var others: [RuleCard] { Self.library.rules.filter { $0.tema != "mva" } }

    func testPairsCrossEachLawWithEachParagraphAndDeduplicate() {
        let card = Self.library.rules(tema: "valuta-korrigeringer")[0]   // lov "regnskapsloven, bokføringsloven", paragrafer § 5-9, § 4-3, § 7, § 9
        let pairs = Moves.pairs(from: [card, card])
        XCTAssertEqual(pairs.count, 8)
        XCTAssertTrue(pairs.contains(Move(lov: "bokføringsloven", paragraf: "§ 7")))
        XCTAssertEqual(pairs, pairs.sorted { $0.id < $1.id })
    }

    func testHitsMatchesLawAndParagraph() throws {
        let puzzle = try XCTUnwrap(Self.library.puzzle(id: "mva-quiz-001"))
        let law = puzzle.lov[0]
        XCTAssertTrue(Moves.hits(Move(lov: law.lov, paragraf: law.paragraf), puzzle))
        XCTAssertFalse(Moves.hits(Move(lov: law.lov, paragraf: "§ 99-99"), puzzle))
        XCTAssertFalse(Moves.hits(Move(lov: "tulleloven", paragraf: law.paragraf), puzzle))
    }

    func testOptionsHoldTheRegionsPairsPlusTwoDistractorsAndNeverLeakAHit() throws {
        let puzzle = try XCTUnwrap(Self.library.puzzles(tema: "mva").first { Moves.canHit($0, regionCards: mva) })
        let options = Moves.options(for: puzzle, regionCards: mva, otherCards: others, seed: 3)
        XCTAssertLessThanOrEqual(options.count, Moves.maxOptions - 1)
        XCTAssertTrue(options.contains { Moves.hits($0, puzzle) })
        let regionPairs = Set(Moves.pairs(from: mva))
        let foreign = options.filter { !regionPairs.contains($0) }
        XCTAssertEqual(foreign.count, min(Moves.distractors, max(0, Moves.maxOptions - 1 - min(regionPairs.count, Moves.maxOptions - 1 - Moves.distractors))))
        XCTAssertFalse(foreign.contains { Moves.hits($0, puzzle) }, "a distractor never hits")
        XCTAssertEqual(options, Moves.options(for: puzzle, regionCards: mva, otherCards: others, seed: 3), "seeded")
    }

    func testOptionsAreEmptyWhenTheRegionCannotHit() throws {
        let puzzle = try XCTUnwrap(Self.library.puzzle(id: "mva-quiz-001"))
        XCTAssertFalse(Moves.canHit(puzzle, regionCards: Self.library.rules(tema: "lonn")))
        XCTAssertEqual(Moves.options(for: puzzle, regionCards: Self.library.rules(tema: "lonn"), otherCards: others, seed: 1), [])
    }

    func testMostApprovedPuzzlesCanBeHitByTheirOwnTopic() {
        let approved = Self.library.approved
        let hittable = approved.filter { Moves.canHit($0, regionCards: Self.library.rules(tema: $0.tema)) }
        XCTAssertGreaterThanOrEqual(Double(hittable.count) / Double(approved.count), 0.75, "\(approved.count - hittable.count) approved puzzles cite no paragraph on a card in their topic")
    }
}
```
Sjekk at `mva-quiz-001` sin `lov[0]` ikke tilfeldigvis er på et `lonn`-kort; velg en annen mva-oppgave om så. Avleder-antallet: fyll regionens par først (høyst `maxOptions − 1 − distractors` = 3 av dem når det er flere), så to avledere; har regionen færre par, får avlederne ikke flere plasser enn `distractors`.

- [ ] **Steg 2: Kjør, de skal feile** — `swift test --filter MovesTests`: kompileringsfeil.
- [ ] **Steg 3: Implementer `Moves.swift`.** `RuleCard.lov` splittes på komma og trimmes. Avledere velges med `SplitMix64(seed:)` fra `pairs(from: otherCards)` minus par som treffer oppgaven; rekkefølgen på knappene stokkes seedet.
- [ ] **Steg 4: Kjør, de skal passere** — `swift test --filter MovesTests`, så `swift test`.
- [ ] **Steg 5: Commit** — `git commit -m "feat(games): moves are paragraph pairs from the rule cards"` + trailer.

---

### Task 3: Regioner

**Files:**
- Create: `Sources/RegnskapKit/Games/Adventure/Region.swift`
- Test: `Tests/RegnskapKitTests/RegionTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum Stage: Int, Hashable, Sendable, CaseIterable { case vill = 0, klekket, ung, voksen, mester
      public var navn: String   // "Vill", "Klekket", "Ung", "Voksen", "Mester"
      public static func of(box: Int?) -> Stage   // nil or 0 → .vill, clamped to 4
  }
  public struct RegionTheme: Hashable, Sendable { public let symbol: String; public let farge: String; public let setning: String }
  public struct Region: Hashable, Sendable, Identifiable {
      public let tema: String, navn: String, rekkefolge: Int
      public let theme: RegionTheme
      public let puzzles: [Puzzle]            // the region's puzzles in the pool, gym leader included
      public let gymLeader: Puzzle?           // nil when the region is empty
      public let caught: Int                  // box ≥ 1
      public let mastered: Int                // box ≥ 3
      public let unlocked: Bool
      public let gymBadge: DayKey?
      public var id: String { tema }
      public var isEmpty: Bool { puzzles.isEmpty }
      public var caughtRatio: Double          // 0 when empty
      public var damageTarget: Int            // half the sum of vanskelighet × 100 over puzzles except the gym leader
  }
  public enum Regions {
      public static let unlockRatio = 0.6
      public static let themes: [String: RegionTheme]   // one entry per tema id in temaer.json; a missing tema gets ("questionmark.circle", "secondary", "")
      public static func build(topics: [Topic], pool: [Puzzle], progress: LearnerProgress) -> [Region]   // sorted by rekkefolge
      /// Edge case with the highest vanskelighet, else the highest vanskelighet; ties by lowest id.
      public static func gymLeader(of puzzles: [Puzzle]) -> Puzzle?
  }
  ```
  Opplåsing: første region alltid; ellers forrige region *med oppgaver* har `caughtRatio ≥ 0.6`, eller forrige region er tom (regn videre bakover: en tom region arver statusen til regionen før den).

- [ ] **Steg 1: Skriv testene**

```swift
import XCTest
@testable import RegnskapKit

final class RegionTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    var topics: [Topic] { Self.library.topics }
    var pool: [Puzzle] { Self.library.pool(includeDrafts: true) }

    func testStages() {
        XCTAssertEqual(Stage.of(box: nil), .vill); XCTAssertEqual(Stage.of(box: 0), .vill)
        XCTAssertEqual(Stage.of(box: 1), .klekket); XCTAssertEqual(Stage.of(box: 4), .mester); XCTAssertEqual(Stage.of(box: 9), .mester)
        XCTAssertEqual(Stage.allCases.map(\.navn), ["Vill", "Klekket", "Ung", "Voksen", "Mester"])
    }

    func testEveryTopicHasAThemeAndARegionInOrder() {
        let regions = Regions.build(topics: topics, pool: pool, progress: LearnerProgress())
        XCTAssertEqual(regions.map(\.tema), topics.sorted { $0.rekkefolge < $1.rekkefolge }.map(\.id))
        for region in regions { XCTAssertFalse(region.theme.setning.isEmpty, region.tema); XCTAssertFalse(region.theme.symbol.isEmpty, region.tema) }
        XCTAssertTrue(regions[0].unlocked)
        XCTAssertFalse(regions[1].unlocked, "nothing caught yet")
    }

    func testGymLeaderPrefersEdgeCasesThenDifficultyThenId() {
        let mva = pool.filter { $0.tema == "mva" }
        let leader = Regions.gymLeader(of: mva)!
        XCTAssertTrue(leader.isEdgeCase)
        XCTAssertEqual(leader.vanskelighet, mva.filter(\.isEdgeCase).map(\.vanskelighet).max())
        XCTAssertEqual(leader.id, mva.filter { $0.isEdgeCase && $0.vanskelighet == leader.vanskelighet }.map(\.id).min())
        let plain = pool.filter { $0.tema == "kontoplan" }   // no edge cases among the drafts
        XCTAssertEqual(Regions.gymLeader(of: plain)?.vanskelighet, plain.map(\.vanskelighet).max())
        XCTAssertNil(Regions.gymLeader(of: []))
    }

    func testUnlockFollowsCaughtRatioAndSkipsEmptyRegions() {
        let approved = Self.library.pool(includeDrafts: false)   // kontoplan and resultat-balanse are empty here
        var progress = LearnerProgress()
        for p in approved.filter({ $0.tema == "grunnlag" }) { progress.puzzles[p.id] = PuzzleProgress(box: 1, attempts: 1, correct: 1) }
        let regions = Regions.build(topics: topics, pool: approved, progress: progress)
        let byTema = Dictionary(uniqueKeysWithValues: regions.map { ($0.tema, $0) })
        XCTAssertTrue(byTema["kontoplan"]!.isEmpty)
        XCTAssertTrue(byTema["kontoplan"]!.unlocked, "an empty region inherits the status of the one before")
        XCTAssertTrue(byTema["bilag-bokforingsloven"]!.unlocked, "grunnlag fully caught, the two empty regions do not block")
        XCTAssertFalse(byTema["perioder-frister"]!.unlocked, "bilag has one puzzle, not caught")
        XCTAssertEqual(byTema["grunnlag"]!.caughtRatio, 1)
    }

    func testCountsAndDamageTarget() {
        var progress = LearnerProgress()
        let lonn = pool.filter { $0.tema == "lonn" }
        progress.puzzles[lonn[0].id] = PuzzleProgress(box: 3, attempts: 1, correct: 1)
        progress.puzzles[lonn[1].id] = PuzzleProgress(box: 1, attempts: 1, correct: 1)
        let region = Regions.build(topics: topics, pool: pool, progress: progress).first { $0.tema == "lonn" }!
        XCTAssertEqual(region.caught, 2); XCTAssertEqual(region.mastered, 1)
        let leader = region.gymLeader!
        XCTAssertEqual(region.damageTarget, lonn.filter { $0.id != leader.id }.map { $0.vanskelighet * 100 }.reduce(0, +) / 2)
        let single = Region(tema: "x", navn: "x", rekkefolge: 99, theme: Regions.themes["mva"]!, puzzles: [lonn[0]], gymLeader: lonn[0], caught: 0, mastered: 0, unlocked: true, gymBadge: nil)
        XCTAssertEqual(single.damageTarget, 0, "a one-puzzle region's leader is ready at once")
    }
}
```

- [ ] **Steg 2: Kjør, de skal feile** — `swift test --filter RegionTests`.
- [ ] **Steg 3: Implementer `Region.swift`** med temaene fra `Innhold/temaer.json` i `Regions.themes` (symboler: grunnlag `scalemass`, kontoplan `list.number`, resultat-balanse `chart.bar.doc.horizontal`, bilag-bokforingsloven `doc.text`, perioder-frister `calendar`, mva `percent`, lonn `person.2`, periodisering `arrow.left.arrow.right`, avskrivning `wrench.and.screwdriver`, arsoppgjor `book.closed`, reskontro-bank `building.columns`, valuta-korrigeringer `eurosign.circle`; fargenavn `skole`/`debet`/`kredit`/`ok`/`warn`/`orange` fordelt; én setning per region på bokmål, f.eks. grunnlag «Her bor bilagene. Alt begynner med debet og kredit.»).
- [ ] **Steg 4: Kjør, de skal passere** — `swift test --filter RegionTests`, så `swift test`.
- [ ] **Steg 5: Commit** — `git commit -m "feat(games): regions from the topics, gym leaders and unlocking"` + trailer.

---

### Task 4: `RegionRun`: møter, HP, fangst, gym-leder

**Files:**
- Create: `Sources/RegnskapKit/Games/Adventure/RegionRun.swift`
- Test: `Tests/RegnskapKitTests/RegionRunTests.swift`

**Interfaces:**
- Consumes: oppgave 2 (`Moves`), 3 (`Region`, `Stage`), `PuzzleAttempt.verdict(for:)` (internal), `Scheduler.isFirstAnswer`.
- Produces:
  ```swift
  public struct Encounter: Hashable, Sendable {
      public let puzzle: Puzzle
      public let stageBefore: Stage
      public let moves: [Move]                 // empty = move step skipped
      public var isGymLeader: Bool
  }
  public enum EncounterOutcome: Hashable, Sendable { case caught(stage: Stage, superEffective: Bool), escaped(hpLost: Int) }
  public struct RunSummary: Hashable, Sendable { public let tema: String; public let caught: Int; public let escaped: Int; public let xp: Int; public let gymBadge: Bool; public let hpLeft: Int }
  public struct RegionRun: Hashable, Sendable {
      public static let hp = 10_000, hpLossPerLevel = 500, damagePerLevel = 100, gymXP = 200, hpZeroPenalty = 0.25
      public enum Phase: Hashable, Sendable { case encounter, result(EncounterOutcome), finished }
      public let region: Region
      public private(set) var hp: Int
      public private(set) var damage: Int        // starts from progress.game.regionDamage[tema]
      public private(set) var phase: Phase
      public private(set) var current: Encounter?
      public private(set) var chosenMove: Move?
      public private(set) var caught = 0, escaped = 0, xp = 0
      public private(set) var gymBadgeEarned = false
      public var gymReady: Bool { damage >= region.damageTarget && region.gymBadge == nil && !gymBadgeEarned }
      public init(region: Region, progress: LearnerProgress, today: DayKey, regionCards: [RuleCard], otherCards: [RuleCard], seed: UInt64)
      /// Due first, then wild (lowest vanskelighet first), then the rest, answered-today last; the gym leader only when `gymReady`. Nil when nothing is left.
      public mutating func nextEncounter(progress: LearnerProgress, today: DayKey)
      public mutating func choose(_ move: Move?)
      /// Checks the attempt; right on this single try catches, wrong escapes. Returns the AttemptResult the app must hand to Scheduler.record.
      public mutating func answer(_ attempt: PuzzleAttempt, progress: LearnerProgress, today: DayKey) -> (outcome: EncounterOutcome, result: AttemptResult)?
      public mutating func proceed()             // from .result back to .encounter (or .finished when hp == 0)
      public mutating func finish()
      public var summary: RunSummary
      /// The damage to persist: the run's damage, cut by 25 % when it ended on empty HP.
      public var damageToSave: Int
  }
  ```
  `answer`: riktig → `damage += vanskelighet × 100 × (treff ? 2 : 1)`, `xp += XP.forPuzzle(vanskelighet, true) × (treff ? 2 : 1)` (bare når `Scheduler.isFirstAnswer` var sann), `caught += 1`, outcome `.caught(stage: Stage.of(box: (progress box ?? 0) + 1 når første svar i dag, ellers uendret), superEffective: treff)`; gym-leder → `gymBadgeEarned = true`, `xp += gymXP`. Feil → `hp -= vanskelighet × 500` (minst 0), `escaped += 1`, outcome `.escaped(hpLost:)`. `proceed`: `hp == 0` → `.finished`.

- [ ] **Steg 1: Skriv testene**

```swift
import XCTest
@testable import RegnskapKit

final class RegionRunTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    let today = DayKey(string: "2026-10-28")!
    var pool: [Puzzle] { Self.library.pool(includeDrafts: true) }
    func region(_ tema: String, progress: LearnerProgress = LearnerProgress()) -> Region {
        Regions.build(topics: Self.library.topics, pool: pool, progress: progress).first { $0.tema == tema }!
    }
    func run(_ tema: String, progress: LearnerProgress = LearnerProgress(), seed: UInt64 = 1) -> RegionRun {
        RegionRun(region: region(tema, progress: progress), progress: progress, today: today, regionCards: Self.library.rules(tema: tema), otherCards: Self.library.rules.filter { $0.tema != tema }, seed: seed)
    }
    func correct(_ p: Puzzle) -> PuzzleAttempt {   // the fasit for every kind the game meets
        switch p.payload {
        case .quiz(let q): .quiz(q.svar)
        case .vat(let v): .vat(behandling: v.fasit.behandling, fradrag: v.fasit.fradrag)
        case .case(let c): .case(c.svar)
        case .number(let n): .number(NorwegianFormat.kroner(n.svar))
        case .deadline(let d): .deadline(d.fasit)
        case .classify(let c): .classify(Dictionary(uniqueKeysWithValues: c.elementer.enumerated().map { ($0.offset, $0.element.svar) }))
        case .spot(let s): .spot(Set(s.elementer.enumerated().filter { $0.element.feil }.map(\.offset)))
        case .posting(let p): .posting(p.fasit.map { PostingAttemptLine(konto: $0.konto, debet: $0.side == .debet ? $0.belop : nil, kredit: $0.side == .kredit ? $0.belop : nil) })
        }
    }

    func testFirstEncounterIsWildAndEasyAndMovesAreOfferedWhenHittable() {
        var r = run("mva")
        r.nextEncounter(progress: LearnerProgress(), today: today)
        let e = r.current!
        XCTAssertEqual(e.stageBefore, .vill)
        XCTAssertFalse(e.isGymLeader)
        XCTAssertEqual(e.puzzle.vanskelighet, r.region.puzzles.filter { $0.id != r.region.gymLeader?.id }.map(\.vanskelighet).min())
        if Moves.canHit(e.puzzle, regionCards: Self.library.rules(tema: "mva")) { XCTAssertFalse(e.moves.isEmpty) } else { XCTAssertTrue(e.moves.isEmpty) }
    }

    func testCatchWithAHitDoublesDamageAndXP() throws {
        var progress = LearnerProgress()
        var r = run("mva")
        r.nextEncounter(progress: progress, today: today)
        let e = try XCTUnwrap(r.current)
        let hit = try XCTUnwrap(e.moves.first { Moves.hits($0, e.puzzle) })
        r.choose(hit)
        let (outcome, result) = try XCTUnwrap(r.answer(correct(e.puzzle), progress: progress, today: today))
        XCTAssertEqual(outcome, .caught(stage: .klekket, superEffective: true))
        XCTAssertEqual(result, AttemptResult(puzzleId: e.puzzle.id, correctFirstTry: true))
        XCTAssertEqual(r.damage, e.puzzle.vanskelighet * 200)
        XCTAssertEqual(r.xp, XP.forPuzzle(vanskelighet: e.puzzle.vanskelighet, correctFirstTry: true) * 2)
        XCTAssertEqual(r.caught, 1); XCTAssertEqual(r.phase, .result(outcome))
        Scheduler.record(result, on: today, progress: &progress)
        XCTAssertEqual(progress.puzzles[e.puzzle.id]?.box, 1)
    }

    func testEscapeCostsHPAndAWrongRuleGivesNoBonus() throws {
        var r = run("lonn")
        r.nextEncounter(progress: LearnerProgress(), today: today)
        let e = try XCTUnwrap(r.current)
        r.choose(nil)
        let (outcome, result) = try XCTUnwrap(r.answer(.quiz(-1), progress: LearnerProgress(), today: today))
        XCTAssertEqual(outcome, .escaped(hpLost: e.puzzle.vanskelighet * 500))
        XCTAssertEqual(r.hp, RegionRun.hp - e.puzzle.vanskelighet * 500)
        XCTAssertEqual(result.correctFirstTry, false)
        XCTAssertEqual(r.damage, 0); XCTAssertEqual(r.xp, 0); XCTAssertEqual(r.escaped, 1)
        r.proceed(); XCTAssertEqual(r.phase, .encounter)
    }

    func testEmptyHPEndsTheRunAndCutsSavedDamageByAQuarter() throws {
        var progress = LearnerProgress()
        progress.game.regionDamage["lonn"] = 800
        var r = run("lonn", progress: progress)
        XCTAssertEqual(r.damage, 800, "continues from the saved damage")
        while r.hp > 0 {
            r.nextEncounter(progress: progress, today: today)
            _ = r.answer(.quiz(-1), progress: progress, today: today)
            r.proceed()
        }
        XCTAssertEqual(r.phase, .finished)
        XCTAssertEqual(r.damageToSave, 600)
        XCTAssertEqual(r.summary.hpLeft, 0)
    }

    func testGymLeaderComesOnlyWhenTheMeterIsFullAndEarnsTheBadge() throws {
        var progress = LearnerProgress()
        progress.game.regionDamage["periodisering"] = 10_000   // well past the target
        var r = run("periodisering", progress: progress)
        XCTAssertTrue(r.gymReady)
        r.nextEncounter(progress: progress, today: today)
        let e = try XCTUnwrap(r.current)
        XCTAssertTrue(e.isGymLeader)
        XCTAssertEqual(e.puzzle.id, r.region.gymLeader?.id)
        r.choose(nil)
        _ = r.answer(correct(e.puzzle), progress: progress, today: today)
        XCTAssertTrue(r.gymBadgeEarned)
        XCTAssertEqual(r.xp, XP.forPuzzle(vanskelighet: e.puzzle.vanskelighet, correctFirstTry: true) + RegionRun.gymXP)
        XCTAssertTrue(r.summary.gymBadge)
        r.proceed(); r.nextEncounter(progress: progress, today: today)
        XCTAssertFalse(r.current?.isGymLeader ?? false, "the leader is not met twice in a run")
    }

    func testAnsweredTodayComesLastAndGivesNoXP() throws {
        var progress = LearnerProgress()
        let lonn = pool.filter { $0.tema == "lonn" }
        for p in lonn { progress.puzzles[p.id] = PuzzleProgress(box: 1, attempts: 1, correct: 1, lastSeen: today, due: today.adding(days: 1)) }
        progress.puzzles[lonn[0].id] = PuzzleProgress(box: 1, attempts: 1, correct: 1, lastSeen: today.adding(days: -3), due: today.adding(days: -2))
        var r = run("lonn", progress: progress)
        r.nextEncounter(progress: progress, today: today)
        XCTAssertEqual(r.current?.puzzle.id, lonn[0].id, "the one due review comes first")
        r.choose(nil); _ = r.answer(correct(lonn[0]), progress: progress, today: today); r.proceed()
        r.nextEncounter(progress: progress, today: today)
        let e = try XCTUnwrap(r.current)
        let xpBefore = r.xp
        _ = r.answer(correct(e.puzzle), progress: progress, today: today)
        XCTAssertEqual(r.xp, xpBefore, "already answered today: no XP")
    }

    func testEmptyRegionFinishesAtOnce() {
        let empty = Region(tema: "tom", navn: "Tom", rekkefolge: 99, theme: Regions.themes["mva"]!, puzzles: [], gymLeader: nil, caught: 0, mastered: 0, unlocked: true, gymBadge: nil)
        var r = RegionRun(region: empty, progress: LearnerProgress(), today: today, regionCards: [], otherCards: [], seed: 1)
        r.nextEncounter(progress: LearnerProgress(), today: today)
        XCTAssertNil(r.current); XCTAssertEqual(r.phase, .finished)
    }
}
```
`PostingAttemptLine(konto:debet:kredit:)` og `NorwegianFormat.kroner` brukes for fasit-svar; sjekk signaturene i `PostingChecker.swift`. Avhengig av seed kan første møte i «lonn» være en type `.quiz(-1)` ikke passer; `answer` må gi feil for et svar som ikke passer typen (`verdict(for:)` gir «Svaret passer ikke oppgavetypen» = feil), så testen holder uansett.

- [ ] **Steg 2: Kjør, de skal feile** — `swift test --filter RegionRunTests`.
- [ ] **Steg 3: Implementer `RegionRun.swift`.** Rekkefølgen beregnes på nytt i hvert `nextEncounter` fra `progress` (så fangster påvirker neste valg), med seedet stokking per gruppe og uten gjentak i samme økt (hold en `seen: Set<String>`; tom liste → `.finished`).
- [ ] **Steg 4: Kjør, de skal passere** — `swift test --filter RegionRunTests`, så `swift test`.
- [ ] **Steg 5: Commit** — `git commit -m "feat(games): region runs: encounters, HP, catches and the gym leader"` + trailer.

---

### Task 5: Ukens utfordring og Lynrunde uten klokke

**Files:**
- Create: `Sources/RegnskapKit/Games/Adventure/WeeklyChallenge.swift`
- Modify: `Sources/RegnskapKit/Games/LightningRound.swift` (`duration` som init-parameter, `.infinity` = ingen klokke)
- Test: `Tests/RegnskapKitTests/WeeklyChallengeTests.swift`, `Tests/RegnskapKitTests/LightningRoundTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum WeeklyChallenge {
      public static let count = 10
      public static func seed(for week: (year: Int, week: Int)) -> UInt64      // year × 100 + week
      /// Ten approved quiz/mva/sak puzzles, chosen from the pool sorted by id with the week's seed; fewer when the pool is smaller.
      public static func puzzles(approved: [Puzzle], week: (year: Int, week: Int)) -> [Puzzle]
      public static func resultCode(week: Int, score: Int, correct: Int) -> String   // "UKE 44 · 1 850 p · 9/10" (kroner-style thousands space, no decimals)
  }
  // LightningRound.init gains `duration: TimeInterval = LightningRound.duration`; remaining(at:) returns .infinity and tick never finishes when duration is .infinity.
  ```

- [ ] **Steg 1: Skriv testene**

```swift
import XCTest
@testable import RegnskapKit

final class WeeklyChallengeTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)

    func testTenApprovedQuickPuzzlesSameForEveryoneRegardlessOfOrderAndDrafts() {
        let approved = Self.library.approved
        let a = WeeklyChallenge.puzzles(approved: approved, week: (2026, 44))
        let b = WeeklyChallenge.puzzles(approved: approved.shuffled(), week: (2026, 44))
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.count, WeeklyChallenge.count)
        XCTAssertTrue(a.allSatisfy { LightningRound.quickKinds.contains($0.kind) && $0.status == .godkjent })
        XCTAssertEqual(Set(a.map(\.id)).count, a.count)
        XCTAssertNotEqual(a.map(\.id), WeeklyChallenge.puzzles(approved: approved, week: (2026, 45)).map(\.id))
        XCTAssertEqual(WeeklyChallenge.seed(for: (2026, 44)), 202644)
    }

    func testResultCode() {
        XCTAssertEqual(WeeklyChallenge.resultCode(week: 44, score: 1850, correct: 9), "UKE 44 · 1\u{202F}850 p · 9/10")
    }

    func testARoundWithoutAClockNeverRunsOut() {
        var r = LightningRound(pool: WeeklyChallenge.puzzles(approved: Self.library.approved, week: (2026, 44)), tema: nil, progress: LearnerProgress(), today: DayKey(string: "2026-10-28")!, seed: 202644, startedAt: 0, duration: .infinity)
        r.tick(at: 100_000)
        XCTAssertEqual(r.phase, .question)
        XCTAssertEqual(r.remaining(at: 100_000), .infinity)
        XCTAssertEqual(r.queue.count, 10)
    }
}
```
I `LightningRoundTests` legg til én linje i `testRoundEndsWhenTimeIsUpOrThePoolIsEmpty`: en runde laget med `duration: 10` er `.finished` etter `tick(at: 10)`.

- [ ] **Steg 2: Kjør, de skal feile.** — [ ] **Steg 3: Implementer.** — [ ] **Steg 4: Kjør, de skal passere** (`swift test`). — [ ] **Steg 5: Commit** — `git commit -m "feat(games): the weekly challenge and a lightning round without a clock"` + trailer.

---

### Task 6: `AppStore+Adventure`: økten i appen

**Files:**
- Modify: `Sources/Regnskapsskolen/App/AppStore.swift` (egenskaper)
- Create: `Sources/Regnskapsskolen/App/AppStore+Adventure.swift`
- Modify: `Sources/Regnskapsskolen/App/AppStore+Games.swift` (`startWeekly`, `endRound` lagrer ukens resultat når runden er ukens)

**Interfaces:**
- Consumes: oppgave 1–5.
- Produces (på `AppStore`):
  ```swift
  var run: RegionRun?
  var encounterSession: PuzzleSession?      // the current encounter's attempt, for the input views
  var lastRunSummary: RunSummary?
  var selectedRegion: String?               // the region screen
  var showCollection = false
  var weeklyRound = false                   // the open lightning round is this week's challenge
  var regions: [Region]                     // Regions.build(topics:, pool:, progress:)
  func openRegion(_ tema: String)           // selectedRegion = tema
  func startRun()                           // RegionRun for selectedRegion, then nextEncounter + encounterSession
  func chooseMove(_ move: Move?)
  func answerEncounter()                    // session.check(); run.answer(session.attempt); Scheduler.record; XP; badges (.caught(total:), .gymBadges(count:), .regionMastered); save
  func proceedEncounter()                   // run.proceed(); next encounter or finish
  func endRun()                             // run.finish(); progress.game.regionDamage[tema] = run.damageToSave; gym badge "gym-<tema>"; lastRunSummary; save
  var collectionTotal: Int                  // puzzles with box ≥ 1 in the pool
  func startWeekly()                        // LightningRound(duration: .infinity) over WeeklyChallenge.puzzles, weeklyRound = true; refused when game.weekly[weekKey] exists
  var weeklyDone: Int?                      // this week's saved score
  ```
  `endRound` i `AppStore+Games`: når `weeklyRound`, lagre `progress.game.weekly[todayKey.weekKey] = summary.score` og `weeklyRound = false`. `.regionMastered` sjekkes etter hver fangst: regionens `mastered == puzzles.count` og `!isEmpty`, delt ut én gang (merket er globalt; første region som fullføres).

- [ ] **Steg 1: Implementer.** — [ ] **Steg 2: `swift build && swift test`** grønt. — [ ] **Steg 3: Commit** — `git commit -m "feat(app): region runs, encounters and the weekly challenge in the store"` + trailer.

---

### Task 7: Kartet og regionskjermen

**Files:**
- Modify: `Sources/Regnskapsskolen/UI/Game/GameHubView.swift` (huben blir kartet; velger kart / region / møte / samling / utfordring / oppsummering etter `store`-tilstand)
- Create: `Sources/Regnskapsskolen/UI/Game/MapView.swift`, `Sources/Regnskapsskolen/UI/Game/RegionView.swift`
- Modify: `Sources/Regnskapsskolen/App/Screenshots.swift` (`spill-region.png`)

**Interfaces:** Consumes oppgave 6.

`MapView`: nivåkortet som i dag; `SectionHeader(title: "Paragrafjakten", subtitle: "Fang reglene. Edge casene vokter regionene.")`; `LazyVGrid` tre kolonner med ett `RegionCard` per region: symbol i regionens farge, navn, «\(caught) av \(puzzles.count) fanget», `MasteryBar(value: Double(mastered)/max(1, count))`, lås-symbol når låst, «Under bygging» når tom, gym-merke (`crown` i `.skole`) når tatt; klikk → `store.openRegion`. Under: tre kort «Arena» (Lynrunde, som i dag med temavelger), «Dojo» (Debet eller kredit?), «Ukens utfordring» («UKE 44 · 10 oppgaver, samme for alle» og «Spill», eller resultatkoden med «Kopier» når ukens er spilt). Nederst «Samling» (knapp → `showCollection`). Merkelisten flyttes inn i Samling-skjermen (oppgave 9).

`RegionView`: tittel og setning, HP-måler («10 000 kr» i `.kredit`-farge når under 3 000), skademåler mot målet («\(damage) av \(damageTarget)», `MasteryBar`), «Gym-lederen venter» når `gymReady`; knappen **Neste møte** (`startRun` første gang, så `proceedEncounter`), skapningene i regionen som små kort (symbol, navn eller «?», trinn), «Gå inn i dungeon» bare for `reskontro-bank` (`store.startCase(bank-001)` + `navigation.section = .sandbox`); «Tilbake til kartet» (`endRun` når en økt pågår).

`Screenshots`: etter spillbildene: `store.openRegion("mva")`, snap `spill-region.png`, `store.selectedRegion = nil`.

- [ ] **Steg 1: Implementer.** — [ ] **Steg 2: `make app` + skjermbilder**; `game.png` viser kartet med tolv regionkort, `spill-region.png` regionskjermen for Merverdiavgift. — [ ] **Steg 3: `swift test`.** — [ ] **Steg 4: Commit** — `git commit -m "feat(app): the world map and the region screen"` + trailer.

---

### Task 8: Møtet og oppsummeringen

**Files:**
- Create: `Sources/Regnskapsskolen/UI/Game/EncounterView.swift`, `Sources/Regnskapsskolen/UI/Game/RunSummaryView.swift`
- Modify: `Sources/Regnskapsskolen/UI/Game/GameHubView.swift` (viser møtet når `store.run?.current` finnes, oppsummeringen når `lastRunSummary`)
- Modify: `Sources/Regnskapsskolen/App/Screenshots.swift` (`spill-mote.png`)

`EncounterView`: skapningskort øverst (regionens symbol stort, `navn`, `Pill(type)`, sjeldenhet som stjerner `vanskelighet`, «Sjelden» når edge case, trinn), HP og skade som to smale linjer. Steg 1 «Hvilken regel gjelder?»: en knapp per `Move` (`label`) + «Ingen regel»; valgt knapp i `.skole`; skjules når `moves` er tom med teksten «Ingen kjent regel for denne.» Steg 2: oppgavens `oppgave` som `MarkdownText` og inndata-visningen for typen (samme `switch` som `PuzzleView.input`, bundet til `store.encounterSession`), «Sjekk» (`answerEncounter`). Resultat: «Fanget! \(stage.navn)» i `.ok` (+ «Super effektivt!» ved treff) eller «Flyktet. −\(hpLost) kr» i `.bad` med `forklaring` og `LawBadge`-ene; «Neste» (`proceedEncounter`, Enter). «Avbryt» → `endRun`.

`RunSummaryView`: «Økten er over» / «Kunden byttet regnskapsfører» (hp 0), `StatTile`-rad fanget/flyktet/XP, «Gym-merket er ditt!» når `gymBadge`, nye merker, knappene «Tilbake til regionen» og «Til kartet».

`Screenshots`: `store.openRegion("mva"); store.startRun()`, snap `spill-mote.png`, `store.endRun(); store.lastRunSummary = nil; store.selectedRegion = nil`.

- [ ] **Steg 1: Implementer.** — [ ] **Steg 2: `make app` + skjermbilder** (`spill-mote.png` viser kortet, trekk-knappene og en oppgave). — [ ] **Steg 3: `swift test`.** — [ ] **Steg 4: Commit** — `git commit -m "feat(app): encounters with a rule to choose and the run summary"` + trailer.

---

### Task 9: Samling og Ukens utfordring på skjermen

**Files:**
- Create: `Sources/Regnskapsskolen/UI/Game/CollectionView.swift`
- Modify: `Sources/Regnskapsskolen/UI/Game/LightningRoundView.swift` (uten klokke når `store.weeklyRound`: viser «Spørsmål \(answered + 1) av 10» i stedet for sekunder), `RoundSummaryView.swift` (resultatkoden + «Kopier» når ukens: `NSPasteboard.general` via en liten `Clipboard`-hjelper i appen)
- Modify: `Sources/Regnskapsskolen/App/Screenshots.swift` (`spill-samling.png`)

`CollectionView`: segmentert regionvelger (navn), rutenett av kort; fanget: forside med symbol, navn, type, stjerner, trinn; klikk snur til bakside: `oppgave` (to linjer), `LawBadge`-er, forklaringens første avsnitt; vill: silhuett (`questionmark` i grått), stjerner, «?». Merkelisten fra dagens hub flyttes hit, øverst. «Tilbake».

- [ ] **Steg 1: Implementer.** — [ ] **Steg 2: `make app` + skjermbilder** (`spill-samling.png`). — [ ] **Steg 3: `swift test`.** — [ ] **Steg 4: Commit** — `git commit -m "feat(app): the collection and the weekly challenge screens"` + trailer.

---

### Task 10: Dokumentasjon

**Files:** `README.md` («Daglig bruk», Spill-linjen beskriver Paragrafjakten), `CLAUDE.md` (tabellen: `Games/Adventure/`), `docs/engineering-notes.md` ved behov.

- [ ] **Steg 1: Skriv.** — [ ] **Steg 2: `swift test`.** — [ ] **Steg 3: Commit** — `git commit -m "docs: Paragrafjakten"` + trailer.
