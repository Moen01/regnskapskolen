# Spillmodus fase 1: implementasjonsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En seksjon «Spill» med Lynrunde (90 s quiz/mva/sak med combo), Debet eller kredit? (60 s reflekstrening på kontoplanen), og et felles lag av XP, nivåer og merker som også teller dagens oppgaver, der Lynrunden mater Leitner.

**Architecture:** All spillogikk er rene, deterministiske tilstandsmaskiner i `RegnskapKit` med injisert klokke (`now: TimeInterval`) og seed (`SplitMix64`). `LearnerProgress` får `game: GameProgress` (XP, merker, rekorder, tellere), lagret i samme `fremdrift.json`. Appen holder runden i `AppStore`, kjører en klokke-`Task`, og tegner tre skjermer.

**Tech Stack:** Swift 6, SwiftUI (macOS), Swift Package Manager, XCTest. Ingen nye avhengigheter. Ingen lyd.

**Spec:** `docs/superpowers/specs/2026-10-27-spillmodus-design.md`

## Global Constraints

- `RegnskapKit` importerer aldri SwiftUI/AppKit, og bruker aldri `Date()` i spillogikken: klokka er et `now: TimeInterval`-argument.
- Norsk bokmål i alt brukeren leser; kode, commit-meldinger og kommentarer på engelsk.
- Ingen lyd, ingen konfetti. Tilbakemelding med farge, symbol og rolige animasjoner.
- `fremdrift.json` skrevet før denne endringen skal lese inn uten feil.
- Nivånavn: Lærling, Regnskapsmedarbeider, Regnskapsfører, Seniorregnskapsfører, Partner (0, 500, 1 500, 4 000, 10 000 XP).
- Lynrunde: 90 s, typene `quiz`, `mva`, `sak`; poeng `100 × vanskelighet × combo`; combo 1,0 + 0,25 per riktig, maks 3,0, nullstilles ved feil; klokka står stille i tilbakemeldingen, minst 1,5 s.
- Debet eller kredit?: 60 s, `10 × combo` + 5 ved svar innen 1,5 s; disponeringskontoer utenfor.
- Én telling per oppgave per dag for boks og XP.
- Alle tall for poeng, XP og terskler er `static let` ett sted i Kit.
- Kjør `swift test` etter hver oppgave. Commit etter hver oppgave, melding på engelsk med trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. Et utvalg med 0 oppgaver (tema uten quiz/mva/sak, eller utkast skjult): runden må avsluttes rett etter start uten krasj; testes i oppgave 4.
2. Svar som kommer etter at tiden er ute (tastetrykk i det klokka når null): `answer` returnerer nil og ingenting telles; testes i oppgave 4.
3. En `fremdrift.json` uten `game`: leses med tom `GameProgress`, og XP seedes fra historikken én gang, ikke ved hver start; testes i oppgave 1 og 6 (seed bare når `game` manglet).
4. En motkonto uten `merknad` i kontoplanen ville gi en gal læresetning: testen i oppgave 5 krever merknad på alle motkontoer.
5. Samme oppgave to ganger på én dag (Øv, så Lynrunde): boksen rykker bare én gang og XP gis én gang; testes i oppgave 2.

---

### Task 1: `GameProgress`, bakoverkompatibel `LearnerProgress`, og XP-reglene

**Files:**
- Create: `Sources/RegnskapKit/Learning/GameProgress.swift`
- Create: `Sources/RegnskapKit/Games/XP.swift`
- Modify: `Sources/RegnskapKit/Learning/LearnerProgress.swift` (feltet `game`, egen `init(from:)`)
- Test: `Tests/RegnskapKitTests/XPTests.swift`, `Tests/RegnskapKitTests/ProgressStoreTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct GameProgress: Codable, Hashable, Sendable {
      public var xp: Int
      public var badges: [String: DayKey]      // badge id → day awarded
      public var bestScores: [String: Int]     // "lynrunde", "lynrunde:<tema>", "debet-kredit"
      public var counters: [String: Int]       // "mva-paa-rad", "frist-riktig"
      public init(xp: Int = 0, badges: [String: DayKey] = [:], bestScores: [String: Int] = [:], counters: [String: Int] = [:])
  }
  // LearnerProgress: public var game: GameProgress  (init parameter with default GameProgress(); decodeIfPresent)
  public struct Level: Hashable, Sendable { public let navn: String; public let terskel: Int; public let neste: Int? }
  public enum XP {
      public static let levels: [Level]                                   // the five, ascending
      public static func level(for xp: Int) -> Level
      public static func forPuzzle(vanskelighet: Int, correctFirstTry: Bool) -> Int   // 10 × v, else 3
      public static func forRound(score: Int) -> Int                      // score / 10
      public static func seed(from progress: LearnerProgress) -> Int      // totalCorrect × 10 + (totalAttempts − totalCorrect) × 3
  }
  ```

- [ ] **Steg 1: Skriv testene**

`XPTests.swift`:
```swift
import XCTest
@testable import RegnskapKit

final class XPTests: XCTestCase {
    func testLevelsFollowTheThresholds() {
        XCTAssertEqual(XP.level(for: 0).navn, "Lærling")
        XCTAssertEqual(XP.level(for: 499).navn, "Lærling")
        XCTAssertEqual(XP.level(for: 500).navn, "Regnskapsmedarbeider")
        XCTAssertEqual(XP.level(for: 1500).navn, "Regnskapsfører")
        XCTAssertEqual(XP.level(for: 4000).navn, "Seniorregnskapsfører")
        XCTAssertEqual(XP.level(for: 10000).navn, "Partner")
        XCTAssertEqual(XP.level(for: 0).neste, 500)
        XCTAssertEqual(XP.level(for: 4000).neste, 10000)
        XCTAssertNil(XP.level(for: 12000).neste)
        XCTAssertEqual(XP.levels.map(\.terskel), [0, 500, 1500, 4000, 10000])
    }

    func testPointsForPuzzlesAndRounds() {
        XCTAssertEqual(XP.forPuzzle(vanskelighet: 3, correctFirstTry: true), 30)
        XCTAssertEqual(XP.forPuzzle(vanskelighet: 3, correctFirstTry: false), 3)
        XCTAssertEqual(XP.forRound(score: 1234), 123)
    }

    func testSeedFromHistory() {
        var p = LearnerProgress()
        p.puzzles["a"] = PuzzleProgress(box: 2, attempts: 3, correct: 2)
        p.puzzles["b"] = PuzzleProgress(box: 0, attempts: 1, correct: 0)
        XCTAssertEqual(XP.seed(from: p), 2 * 10 + 2 * 3)
        XCTAssertEqual(XP.seed(from: LearnerProgress()), 0)
    }
}
```

I `ProgressStoreTests.swift`:
```swift
    func testAFileWithoutGameReadsWithEmptyGameProgress() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fremdrift-\(UUID().uuidString).json")
        try Data(#"{"puzzles":{"x":{"box":1,"attempts":1,"correct":1}},"days":{}}"#.utf8).write(to: url)
        let loaded = ProgressStore(url: url).load()
        XCTAssertEqual(loaded.puzzles["x"]?.box, 1)
        XCTAssertEqual(loaded.game, GameProgress())
    }

    func testGameProgressRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fremdrift-\(UUID().uuidString).json")
        var progress = LearnerProgress()
        progress.game.xp = 420
        progress.game.badges["lynrask"] = DayKey(string: "2026-10-27")!
        progress.game.bestScores["lynrunde"] = 1600
        progress.game.counters["mva-paa-rad"] = 3
        let store = ProgressStore(url: url)
        try store.save(progress)
        XCTAssertEqual(store.load().game, progress.game)
    }
```

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter "XPTests|ProgressStoreTests"`
Forventet: kompileringsfeil, `GameProgress`/`XP` finnes ikke.

- [ ] **Steg 3: Implementer `GameProgress`, `game` på `LearnerProgress` med egen `init(from:)` (`decodeIfPresent` for `game`, resten som før), og `XP`**

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter "XPTests|ProgressStoreTests|SchedulerTests"`
Forventet: grønt.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Learning/GameProgress.swift Sources/RegnskapKit/Games/XP.swift Sources/RegnskapKit/Learning/LearnerProgress.swift Tests/RegnskapKitTests/XPTests.swift Tests/RegnskapKitTests/ProgressStoreTests.swift
git commit -m "feat(games): game progress on the learner, XP levels and sources"
```

---

### Task 2: Én telling per oppgave per dag

**Files:**
- Modify: `Sources/RegnskapKit/Learning/Scheduler.swift` (`record`, ny `isFirstAnswer`)
- Test: `Tests/RegnskapKitTests/SchedulerTests.swift`

**Interfaces:**
- Produces: `public static func isFirstAnswer(of puzzleId: String, on day: DayKey, progress: LearnerProgress) -> Bool` (`lastSeen != day`). `record` rykker bare opp en boks når `isFirstAnswer` var sann før registreringen; feil svar nullstiller alltid; `attempts`/`correct`/`lastSeen`/`due` som før.

- [ ] **Steg 1: Skriv testen, og rett den gamle**

```swift
    func testASecondCorrectAnswerTheSameDayKeepsTheBox() {
        var progress = LearnerProgress()
        let id = pool[0].id
        XCTAssertTrue(Scheduler.isFirstAnswer(of: id, on: day, progress: progress))
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertFalse(Scheduler.isFirstAnswer(of: id, on: day, progress: progress))
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: day, progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, 1, "one promotion per day")
        XCTAssertEqual(progress.puzzles[id]?.attempts, 2)
        XCTAssertEqual(progress.puzzles[id]?.correct, 2)
        Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: false), on: day, progress: &progress)
        XCTAssertEqual(progress.puzzles[id]?.box, 0, "a wrong answer always resets")
        XCTAssertTrue(Scheduler.isFirstAnswer(of: id, on: day.adding(days: 1), progress: progress))
    }
```

I `testCorrectMovesUpWrongResetsToZero` erstatt løkka `for _ in 0..<6 { … on: day.adding(days: 30) … }` med `for i in 0..<6 { … on: day.adding(days: 30 + i) … }`: seks riktige på seks dager, fortsatt tak på boks 4.

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter SchedulerTests`
Forventet: `isFirstAnswer` finnes ikke.

- [ ] **Steg 3: Implementer**

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter SchedulerTests`
Forventet: grønt.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Learning/Scheduler.swift Tests/RegnskapKitTests/SchedulerTests.swift
git commit -m "feat(scheduler): a puzzle moves up at most one box per day"
```

---

### Task 3: Merker

**Files:**
- Create: `Sources/RegnskapKit/Games/Badges.swift`
- Test: `Tests/RegnskapKitTests/BadgesTests.swift`

**Interfaces:**
- Consumes: oppgave 1.
- Produces:
  ```swift
  public enum GameKind: String, Codable, Hashable, Sendable, CaseIterable {
      case lynrunde, debetKredit = "debet-kredit"
      public var navn: String   // "Lynrunde", "Debet eller kredit?"
  }
  public struct Badge: Hashable, Sendable, Identifiable { public let id: String; public let navn: String; public let beskrivelse: String; public let symbol: String }
  public enum GameEvent: Hashable, Sendable {
      case puzzleAnswered(kind: PuzzleKind, correctFirstTry: Bool)
      case roundFinished(game: GameKind, score: Int, correct: Int)
      case caseMatched, bankReconciled
      case dayCompleted(streak: Int)
  }
  public enum Badges {
      public static let all: [Badge]                 // the eight from the spec, in the spec's order
      public static let mvaRun = "mva-paa-rad", fristCount = "frist-riktig"
      /// Updates the counters, records new badges on `day`, and returns the badges awarded by this event.
      public static func award(_ event: GameEvent, on day: DayKey, progress: inout LearnerProgress) -> [Badge]
  }
  ```
  Vilkårene: `mva-mester` 20 mva riktig på rad (`counters["mva-paa-rad"]`, nullstilles av et mva-svar som ikke var riktig på første forsøk); `fristfri` 10 frist riktig på første forsøk samlet (`counters["frist-riktig"]`); `null-differanse` ved `.caseMatched`; `bank-avstemt` ved `.bankReconciled`; `lynrask` Lynrunde-score ≥ 1 500; `reflekser` Debet/kredit `correct` ≥ 30; `sju-dager` streak ≥ 7; `tretti-dager` streak ≥ 30 (begge kan komme i samme hendelse). Et merke deles ut én gang.

- [ ] **Steg 1: Skriv testene**

```swift
import XCTest
@testable import RegnskapKit

final class BadgesTests: XCTestCase {
    let day = DayKey(string: "2026-10-27")!
    var progress = LearnerProgress()
    func award(_ event: GameEvent) -> [String] { Badges.award(event, on: day, progress: &progress).map(\.id) }

    func testCatalogHasEightBadgesWithUniqueIds() {
        XCTAssertEqual(Badges.all.count, 8)
        XCTAssertEqual(Set(Badges.all.map(\.id)).count, 8)
        XCTAssertEqual(Badges.all.map(\.id), ["mva-mester", "fristfri", "null-differanse", "bank-avstemt", "lynrask", "reflekser", "sju-dager", "tretti-dager"])
    }

    func testMvaMesterNeedsTwentyInARowAndIsAwardedOnce() {
        for _ in 0..<19 { XCTAssertEqual(award(.puzzleAnswered(kind: .mva, correctFirstTry: true)), []) }
        XCTAssertEqual(award(.puzzleAnswered(kind: .mva, correctFirstTry: true)), ["mva-mester"])
        XCTAssertEqual(progress.game.badges["mva-mester"], day)
        for _ in 0..<20 { _ = award(.puzzleAnswered(kind: .mva, correctFirstTry: true)) }
        XCTAssertEqual(progress.game.badges.count, 1)
    }

    func testAWrongMvaAnswerResetsTheRun() {
        for _ in 0..<19 { _ = award(.puzzleAnswered(kind: .mva, correctFirstTry: true)) }
        XCTAssertEqual(award(.puzzleAnswered(kind: .mva, correctFirstTry: false)), [])
        XCTAssertEqual(progress.game.counters[Badges.mvaRun], 0)
        XCTAssertEqual(award(.puzzleAnswered(kind: .quiz, correctFirstTry: true)), [], "other kinds do not touch the mva run")
        XCTAssertEqual(progress.game.counters[Badges.mvaRun], 0)
    }

    func testFristfriIsCumulative() {
        for _ in 0..<5 { _ = award(.puzzleAnswered(kind: .frist, correctFirstTry: true)) }
        _ = award(.puzzleAnswered(kind: .frist, correctFirstTry: false))
        for _ in 0..<4 { XCTAssertEqual(award(.puzzleAnswered(kind: .frist, correctFirstTry: true)), []) }
        XCTAssertEqual(award(.puzzleAnswered(kind: .frist, correctFirstTry: true)), ["fristfri"])
    }

    func testRoundBadges() {
        XCTAssertEqual(award(.roundFinished(game: .lynrunde, score: 1499, correct: 10)), [])
        XCTAssertEqual(award(.roundFinished(game: .lynrunde, score: 1500, correct: 10)), ["lynrask"])
        XCTAssertEqual(award(.roundFinished(game: .debetKredit, score: 1500, correct: 29)), [], "a drill score never gives lynrask")
        XCTAssertEqual(award(.roundFinished(game: .debetKredit, score: 0, correct: 30)), ["reflekser"])
    }

    func testStreakAndSandboxBadges() {
        XCTAssertEqual(award(.dayCompleted(streak: 6)), [])
        XCTAssertEqual(award(.dayCompleted(streak: 7)), ["sju-dager"])
        XCTAssertEqual(award(.dayCompleted(streak: 30)), ["tretti-dager"])
        XCTAssertEqual(award(.caseMatched), ["null-differanse"])
        XCTAssertEqual(award(.bankReconciled), ["bank-avstemt"])
        var fresh = LearnerProgress()
        XCTAssertEqual(Badges.award(.dayCompleted(streak: 30), on: day, progress: &fresh).map(\.id), ["sju-dager", "tretti-dager"], "a long streak gives both")
    }
}
```

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter BadgesTests`
Forventet: kompileringsfeil.

- [ ] **Steg 3: Implementer `Badges.swift`**

Tekstene (navn, beskrivelse, SF-symbol) på bokmål: Mva-mester «20 mva-oppgaver riktig på rad» `percent`; Fristfri «10 frister riktig på første forsøk» `calendar.badge.checkmark`; Null differanse «En sandkasse-case som stemmer med fasiten» `equal.circle`; Bank avstemt «En case avstemt mot banken» `building.columns`; Lynrask «1 500 poeng i Lynrunden» `bolt`; Reflekser «30 riktige i én runde Debet eller kredit?» `arrow.left.arrow.right`; Sju dager «7 dager på rad» `flame`; Tretti dager «30 dager på rad» `flame.fill`.

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter BadgesTests`
Forventet: 6 tester, 0 feil.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Games/Badges.swift Tests/RegnskapKitTests/BadgesTests.swift
git commit -m "feat(games): badge catalog and awarding"
```

---

### Task 4: Combo og Lynrunden

**Files:**
- Create: `Sources/RegnskapKit/Games/Combo.swift`
- Create: `Sources/RegnskapKit/Games/LightningRound.swift`
- Test: `Tests/RegnskapKitTests/LightningRoundTests.swift`

**Interfaces:**
- Consumes: oppgave 1 (`XP.forRound`), oppgave 2 (`Scheduler.isFirstAnswer` for rekkefølgen), oppgave 3 (`GameKind`).
- Produces:
  ```swift
  public struct Combo: Hashable, Sendable {
      public static let step = 0.25, max = 3.0
      public private(set) var multiplier = 1.0
      public private(set) var best = 1.0
      public init()
      public mutating func hit()    // multiplier = min(max, multiplier + step); best = max(best, multiplier)
      public mutating func miss()   // multiplier = 1.0
  }
  public struct RoundSummary: Hashable, Sendable {
      public let game: GameKind; public let tema: String?
      public let score: Int, correct: Int, answered: Int
      public let bestCombo: Double
      public var xp: Int { XP.forRound(score: score) }
  }
  public struct RoundEvent: Hashable, Sendable { public let verdict: Verdict; public let points: Int; public let result: AttemptResult }
  public struct LightningRound: Hashable, Sendable {
      public enum Phase: Hashable, Sendable { case question, feedback(since: TimeInterval), finished }
      public static let duration: TimeInterval = 90, feedbackMinimum: TimeInterval = 1.5
      public static let quickKinds: [PuzzleKind] = [.quiz, .mva, .sak], minimumTopicSize = 8
      public static let pointsPerLevel = 100
      public static func eligible(pool: [Puzzle], tema: String?) -> [Puzzle]
      /// Due or box 0–1 first, then the rest, then puzzles already answered today; seeded shuffle inside each group.
      public static func order(pool: [Puzzle], tema: String?, progress: LearnerProgress, today: DayKey, seed: UInt64) -> [Puzzle]
      /// Topics with at least `minimumTopicSize` eligible puzzles, in the pool's order of first appearance.
      public static func topics(in pool: [Puzzle]) -> [String]
      public init(pool: [Puzzle], tema: String?, progress: LearnerProgress, today: DayKey, seed: UInt64, startedAt: TimeInterval)
      public let tema: String?
      public private(set) var queue: [Puzzle]
      public var current: Puzzle? { queue.first }
      public private(set) var phase: Phase
      public private(set) var score = 0, correct = 0, answered = 0
      public private(set) var combo = Combo()
      public private(set) var lastEvent: RoundEvent?
      public func remaining(at now: TimeInterval) -> TimeInterval
      /// Nil outside `.question` or once the time is up. Right: points added, next question at once. Wrong: no points, `.feedback`, clock paused.
      public mutating func answer(_ attempt: PuzzleAttempt, at now: TimeInterval) -> RoundEvent?
      /// Leaves `.feedback` when at least `feedbackMinimum` has passed; a no-op otherwise.
      public mutating func next(at now: TimeInterval)
      /// Finishes the round when the time is up.
      public mutating func tick(at now: TimeInterval)
      public mutating func finish()
      public var summary: RoundSummary
  }
  ```
  Poeng: `Int(Double(pointsPerLevel * puzzle.vanskelighet) * combo.multiplier)` (avkortet, ikke avrundet), med combo-verdien *før* `hit()`. Usette oppgaver regnes som boks 0 i rekkefølgen. En tom kø ved start gir `phase == .finished` med en gang.

- [ ] **Steg 1: Skriv testene**

```swift
import XCTest
@testable import RegnskapKit

final class LightningRoundTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    var pool: [Puzzle] { Self.library.pool(includeDrafts: true) }
    let today = DayKey(string: "2026-10-27")!

    func correctAttempt(for puzzle: Puzzle) -> PuzzleAttempt {
        switch puzzle.payload {
        case .quiz(let q): .quiz(q.svar)
        case .vat(let v): .vat(behandling: v.fasit.behandling, fradrag: v.fasit.fradrag)
        case .case(let c): .case(c.svar)
        default: fatalError("not a quick kind")
        }
    }
    func wrongAttempt(for puzzle: Puzzle) -> PuzzleAttempt {
        switch puzzle.payload {
        case .quiz(let q): .quiz((q.svar + 1) % q.alternativer.count)
        case .vat: .vat(behandling: "ingen-slik-kode", fradrag: nil)
        case .case: .case("ingen-slik-nokkel")
        default: fatalError("not a quick kind")
        }
    }
    func round(tema: String? = nil, progress: LearnerProgress = LearnerProgress(), seed: UInt64 = 1) -> LightningRound {
        LightningRound(pool: pool, tema: tema, progress: progress, today: today, seed: seed, startedAt: 0)
    }

    func testOnlyQuickKindsAndTheTopicFilter() {
        XCTAssertTrue(LightningRound.eligible(pool: pool, tema: nil).allSatisfy { LightningRound.quickKinds.contains($0.kind) })
        XCTAssertTrue(LightningRound.eligible(pool: pool, tema: "mva").allSatisfy { $0.tema == "mva" })
        XCTAssertTrue(LightningRound.topics(in: pool).contains("mva"))
        XCTAssertTrue(LightningRound.topics(in: pool).allSatisfy { LightningRound.eligible(pool: pool, tema: $0).count >= LightningRound.minimumTopicSize })
    }

    func testSeededOrderIsStableAndFree() {
        XCTAssertEqual(round(seed: 7).queue.map(\.id), round(seed: 7).queue.map(\.id))
        XCTAssertNotEqual(round(seed: 7).queue.map(\.id), round(seed: 8).queue.map(\.id))
        XCTAssertEqual(Set(round().queue.map(\.id)).count, round().queue.count, "no repeats")
    }

    func testOrderPutsDueAndLowBoxFirstAndTodaysLast() {
        let eligible = LightningRound.eligible(pool: pool, tema: nil)
        let strong = eligible[0], weak = eligible[1], seenToday = eligible[2]
        var progress = LearnerProgress()
        progress.puzzles[strong.id] = PuzzleProgress(box: 4, attempts: 4, correct: 4, lastSeen: today.adding(days: -2), due: today.adding(days: 19))
        progress.puzzles[weak.id] = PuzzleProgress(box: 0, attempts: 1, correct: 0, lastSeen: today.adding(days: -1), due: today.adding(days: -1))
        progress.puzzles[seenToday.id] = PuzzleProgress(box: 1, attempts: 1, correct: 1, lastSeen: today, due: today.adding(days: 1))
        let ids = round(progress: progress).queue.map(\.id)
        XCTAssertLessThan(ids.firstIndex(of: weak.id)!, ids.firstIndex(of: strong.id)!)
        XCTAssertEqual(ids.last, seenToday.id)
    }

    func testScoringAndCombo() {
        var r = round()
        let p1 = r.current!
        let e1 = r.answer(correctAttempt(for: p1), at: 1)!
        XCTAssertTrue(e1.verdict.correct)
        XCTAssertEqual(e1.points, 100 * p1.vanskelighet)
        XCTAssertEqual(e1.result, AttemptResult(puzzleId: p1.id, correctFirstTry: true))
        XCTAssertEqual(r.phase, .question, "a right answer goes straight on")
        let p2 = r.current!
        XCTAssertEqual(r.answer(correctAttempt(for: p2), at: 2)!.points, Int(Double(100 * p2.vanskelighet) * 1.25))
        XCTAssertEqual(r.combo.multiplier, 1.5)
        let p3 = r.current!
        let e3 = r.answer(wrongAttempt(for: p3), at: 3)!
        XCTAssertFalse(e3.verdict.correct)
        XCTAssertEqual(e3.points, 0)
        XCTAssertEqual(e3.result, AttemptResult(puzzleId: p3.id, correctFirstTry: false))
        XCTAssertEqual(r.combo.multiplier, 1.0)
        XCTAssertEqual(r.combo.best, 1.5)
        XCTAssertEqual(r.score, e1.points + Int(Double(100 * p2.vanskelighet) * 1.25))
        XCTAssertEqual(r.correct, 2); XCTAssertEqual(r.answered, 3)
        XCTAssertEqual(r.phase, .feedback(since: 3))
        XCTAssertNil(r.answer(correctAttempt(for: r.current!), at: 3.2), "no answers during feedback")
    }

    func testClockPausesDuringFeedback() {
        var r = round()
        XCTAssertEqual(r.remaining(at: 10), 80)
        _ = r.answer(wrongAttempt(for: r.current!), at: 10)
        XCTAssertEqual(r.remaining(at: 20), 80, "paused")
        r.next(at: 11)
        XCTAssertEqual(r.phase, .feedback(since: 10), "not before 1.5 s")
        r.next(at: 12)
        XCTAssertEqual(r.phase, .question)
        XCTAssertEqual(r.remaining(at: 12), 80)
        XCTAssertEqual(r.remaining(at: 22), 70)
    }

    func testRoundEndsWhenTimeIsUpOrThePoolIsEmpty() {
        var r = round()
        r.tick(at: 89.9); XCTAssertEqual(r.phase, .question)
        r.tick(at: 90); XCTAssertEqual(r.phase, .finished)
        XCTAssertNil(r.answer(correctAttempt(for: r.current!), at: 90.1), "late answers do not count")
        XCTAssertEqual(r.remaining(at: 200), 0)
        var tiny = LightningRound(pool: Array(LightningRound.eligible(pool: pool, tema: nil).prefix(2)), tema: nil, progress: LearnerProgress(), today: today, seed: 1, startedAt: 0)
        _ = tiny.answer(correctAttempt(for: tiny.current!), at: 1)
        _ = tiny.answer(correctAttempt(for: tiny.current!), at: 2)
        XCTAssertEqual(tiny.phase, .finished)
        XCTAssertNil(tiny.current)
        let empty = LightningRound(pool: [], tema: nil, progress: LearnerProgress(), today: today, seed: 1, startedAt: 0)
        XCTAssertEqual(empty.phase, .finished)
    }

    func testSummary() {
        var r = round()
        let e = r.answer(correctAttempt(for: r.current!), at: 1)!
        r.finish()
        let s = r.summary
        XCTAssertEqual(s.game, .lynrunde); XCTAssertNil(s.tema)
        XCTAssertEqual(s.score, e.points); XCTAssertEqual(s.correct, 1); XCTAssertEqual(s.answered, 1)
        XCTAssertEqual(s.bestCombo, 1.25); XCTAssertEqual(s.xp, e.points / 10)
    }
}
```

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter LightningRoundTests`
Forventet: kompileringsfeil.

- [ ] **Steg 3: Implementer `Combo.swift` og `LightningRound.swift`**

Klokka: `startedAt`, `pausedFor: TimeInterval = 0`, `pauseStart: TimeInterval?`; `remaining = max(0, duration − (now − startedAt − pausedFor − (pauseStart.map { now − $0 } ?? 0)))`. `order`: stokk hele utvalget med `SplitMix64(seed:)`, så stabil sortering på gruppe (0: forfalt eller boks ≤ 1 og ikke sett i dag; 1: resten; 2: `lastSeen == today`). Sjekken av svaret går gjennom `PuzzleSession` eller `attempt.verdict(for:)` (internal i Kit), ikke en egen sjekk.

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter LightningRoundTests`
Forventet: 7 tester, 0 feil.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Games/Combo.swift Sources/RegnskapKit/Games/LightningRound.swift Tests/RegnskapKitTests/LightningRoundTests.swift
git commit -m "feat(games): the lightning round state machine"
```

---

### Task 5: Debet eller kredit?

**Files:**
- Create: `Sources/RegnskapKit/Games/DebitCreditDrill.swift`
- Modify: `Innhold/kontoplan.json` (merknad på 2080)
- Test: `Tests/RegnskapKitTests/DebitCreditDrillTests.swift`

**Interfaces:**
- Consumes: oppgave 4 (`Combo`, `RoundSummary`), `ChartOfAccounts`.
- Produces:
  ```swift
  extension AccountType {
      /// The side this kind of account normally grows on; nil for disponering.
      public var normalSide: Side?
      /// "en eiendel", "gjeld", "egenkapital", "en inntekt", "en kostnad" (nil for disponering)
      var drillPhrase: String?
      /// "Eiendeler", "Gjeld", "Egenkapital", "Inntekter", "Kostnader"
      var pluralNavn: String?
  }
  public struct DrillCard: Hashable, Sendable, Identifiable {
      public let account: Account
      public let increases: Bool
      public var id: String { "\(account.nr)-\(increases ? "opp" : "ned")" }
      public var answer: Side { increases ? account.okerPa : account.okerPa.other }
      public var isContra: Bool { account.type.normalSide != account.okerPa }
      /// "4300 er en kostnad. Kostnader øker på debet." or, for a contra account, "<merknad> Den øker på kredit."
      public var explanation: String
  }
  public struct DebitCreditDrill: Hashable, Sendable {
      public enum Phase: Hashable, Sendable { case question(shownAt: TimeInterval), feedback(since: TimeInterval), finished }
      public static let duration: TimeInterval = 60, feedbackMinimum: TimeInterval = 1.5, quickAnswer: TimeInterval = 1.5
      public static let basePoints = 10, speedBonus = 5
      public static func cards(chart: ChartOfAccounts) -> [DrillCard]     // every non-disponering account × {true, false}, chart order
      public init(chart: ChartOfAccounts, seed: UInt64, startedAt: TimeInterval)
      public private(set) var queue: [DrillCard]
      public var current: DrillCard? { queue.first }
      public private(set) var phase: Phase
      public private(set) var score = 0, correct = 0, answered = 0
      public private(set) var combo = Combo()
      public private(set) var lastCorrect: Bool?
      public func remaining(at now: TimeInterval) -> TimeInterval
      /// Nil outside `.question` or when the time is up. Returns the points given.
      public mutating func answer(_ side: Side, at now: TimeInterval) -> Int?
      public mutating func next(at now: TimeInterval)
      public mutating func tick(at now: TimeInterval)
      public mutating func finish()
      public var summary: RoundSummary       // game .debetKredit, tema nil
  }
  ```
  Poeng for riktig: `Int(Double(basePoints) * combo.multiplier) + (now − shownAt <= quickAnswer ? speedBonus : 0)` (avkortet: 10 × 1,25 gir 12), combo før `hit()`. Køen går rundt: når den er tom, fylles den på nytt med samme stokking, så en rask spiller aldri går tom på 60 s.

- [ ] **Steg 1: Skriv testene**

```swift
import XCTest
@testable import RegnskapKit

final class DebitCreditDrillTests: XCTestCase {
    static let chart = try! ContentLibrary(root: ContentLocator.repoContent).chart
    func drill(seed: UInt64 = 1) -> DebitCreditDrill { DebitCreditDrill(chart: Self.chart, seed: seed, startedAt: 0) }

    func testCardsCoverEveryAccountTwiceExceptDisponering() {
        let cards = DebitCreditDrill.cards(chart: Self.chart)
        let counted = Self.chart.all.filter { $0.type != .disponering }
        XCTAssertEqual(cards.count, counted.count * 2)
        for account in counted { XCTAssertEqual(cards.filter { $0.account.nr == account.nr }.count, 2, account.nr) }
        XCTAssertFalse(cards.contains { $0.account.type == .disponering })
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
    }

    func testAnswersFollowOkerPa() {
        for card in DebitCreditDrill.cards(chart: Self.chart) {
            XCTAssertEqual(card.answer, card.increases ? card.account.okerPa : card.account.okerPa.other, card.id)
        }
    }

    func testExplanationsForNormalAndContraAccounts() throws {
        func card(_ nr: String) -> DrillCard { DrillCard(account: Self.chart.account(nr)!, increases: true) }
        XCTAssertEqual(card("4300").explanation, "4300 er en kostnad. Kostnader øker på debet.")
        XCTAssertEqual(card("2400").explanation, "2400 er gjeld. Gjeld øker på kredit.")
        XCTAssertEqual(card("1920").explanation, "1920 er en eiendel. Eiendeler øker på debet.")
        XCTAssertEqual(card("3000").explanation, "3000 er en inntekt. Inntekter øker på kredit.")
        XCTAssertEqual(card("2050").explanation, "2050 er egenkapital. Egenkapital øker på kredit.")
        let contra = card("1580")
        XCTAssertTrue(contra.isContra)
        XCTAssertEqual(contra.explanation, try XCTUnwrap(contra.account.merknad) + " Den øker på kredit.")
        XCTAssertFalse(card("4300").isContra)
    }

    func testEveryContraAccountHasANote() {
        for card in DebitCreditDrill.cards(chart: Self.chart) where card.isContra {
            XCTAssertFalse((card.account.merknad ?? "").isEmpty, "\(card.account.nr) needs a merknad for its explanation")
        }
        XCTAssertTrue(DebitCreditDrill.cards(chart: Self.chart).contains { $0.account.nr == "2080" && $0.isContra })
    }

    func testScoringSpeedBonusAndFeedbackPause() {
        var d = drill()
        let first = d.current!
        XCTAssertEqual(d.answer(first.answer, at: 1.0), 15, "10 × 1.0 plus the speed bonus")
        XCTAssertEqual(d.phase, .question(shownAt: 1.0))
        let second = d.current!
        XCTAssertEqual(d.answer(second.answer, at: 3.0), 12, "10 × 1.25, no bonus after 2 s")
        XCTAssertEqual(d.score, 27); XCTAssertEqual(d.correct, 2); XCTAssertEqual(d.answered, 2)
        let third = d.current!
        XCTAssertEqual(d.answer(third.answer.other, at: 4.0), 0)
        XCTAssertEqual(d.phase, .feedback(since: 4.0))
        XCTAssertEqual(d.lastCorrect, false)
        XCTAssertEqual(d.combo.multiplier, 1.0)
        XCTAssertEqual(d.remaining(at: 10), 56, "paused since 4.0")
        d.next(at: 5.0); XCTAssertEqual(d.phase, .feedback(since: 4.0))
        d.next(at: 5.5); XCTAssertEqual(d.phase, .question(shownAt: 5.5))
        XCTAssertEqual(d.remaining(at: 5.5), 56)
    }

    func testRoundEndsAtSixtySecondsAndTheQueueWrapsAround() {
        var d = drill()
        let total = DebitCreditDrill.cards(chart: Self.chart).count
        for i in 0..<total { _ = d.answer(d.current!.answer, at: Double(i) * 0.1) }
        XCTAssertNotNil(d.current, "the queue refills")
        XCTAssertEqual(d.answered, total)
        d.tick(at: 60); XCTAssertEqual(d.phase, .finished)
        XCTAssertNil(d.answer(.debet, at: 61))
        XCTAssertEqual(d.summary.game, .debetKredit)
        XCTAssertEqual(d.summary.correct, total)
    }

    func testSeededOrder() {
        XCTAssertEqual(drill(seed: 3).queue.map(\.id), drill(seed: 3).queue.map(\.id))
        XCTAssertNotEqual(drill(seed: 3).queue.map(\.id), drill(seed: 4).queue.map(\.id))
    }
}
```

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter DebitCreditDrillTests`
Forventet: kompileringsfeil.

- [ ] **Steg 3: Implementer `DebitCreditDrill.swift`, og gi 2080 i `Innhold/kontoplan.json` merknaden «Negativ egenkapital: tap som ikke er dekket av annen egenkapital.»**

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter "DebitCreditDrillTests|ChartTests|ContentValidatorTests"`
Forventet: grønt.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Games/DebitCreditDrill.swift Innhold/kontoplan.json Tests/RegnskapKitTests/DebitCreditDrillTests.swift
git commit -m "feat(games): debit-or-credit drill over the chart of accounts"
```

---

### Task 6: Spill i `AppStore`: runder, klokke, XP og merker

**Files:**
- Modify: `Sources/Regnskapsskolen/App/AppDelegate.swift` (`AppSection.game`: «Spill», symbol `gamecontroller`, mellom `.practice` og `.sandbox`)
- Modify: `Sources/Regnskapsskolen/App/AppStore.swift` (lagrede egenskaper)
- Create: `Sources/Regnskapsskolen/App/AppStore+Games.swift`
- Modify: `Sources/Regnskapsskolen/App/AppStore+Today.swift` (`record` gir XP og merker; `start` seeder XP)
- Modify: `Sources/Regnskapsskolen/App/AppStore+Sandbox.swift` (`.caseMatched`, og `.bankReconciled` når `bankCheck` finnes)
- Modify: `Sources/Regnskapsskolen/UI/MainView.swift` (`case .game: GameHubView()`; en midlertidig `Text("Spill")` til oppgave 7 hvis visningen ikke finnes ennå)

**Interfaces:**
- Consumes: oppgave 1–5.
- Produces (på `AppStore`):
  ```swift
  var lightning: LightningRound?
  var drill: DebitCreditDrill?
  var lastSummary: RoundSummary?
  var newBadges: [Badge] = []           // awarded by the last round or answer, shown once
  var lastWasRecord = false
  var lynrundeTema: String?             // the hub's topic choice, nil = all
  @ObservationIgnored var clock: Task<Void, Never>?
  func startLightning()                 // seed from Date, startedAt = now(); starts the clock task
  func startDrill()
  func answerLightning(_ attempt: PuzzleAttempt)   // Scheduler.record + XP + Badges per answer
  func answerDrill(_ side: Side)
  func nextInRound()                    // next(at: now()) on whichever round is open
  func endRound()                       // finish(), summary, best score, XP, badges, save, clear clock
  func bestScore(for game: GameKind, tema: String?) -> Int?
  var now: TimeInterval { Date().timeIntervalSinceReferenceDate }
  ```
  Klokka: en `Task` som hvert 100 ms kaller `tick(at: now)` på den åpne runden og kaller `endRound()` når fasen er `.finished`. `record(_:)` i `AppStore+Today`: finn oppgaven i `library`; `let first = Scheduler.isFirstAnswer(...)` før `Scheduler.record`; XP bare når `first`; `Badges.award(.puzzleAnswered(kind:correctFirstTry:))`; når dagens sett ble ferdig av dette svaret, `Badges.award(.dayCompleted(streak:))`. Rekord: `bestScores["lynrunde"]` eller `"lynrunde:<tema>"`, `"debet-kredit"`. `start()`: når `progressStore` leste en fil uten `game` (legg til `public private(set) var fileHadGame: Bool` på `ProgressStore` satt i `load`), sett `progress.game.xp = XP.seed(from: progress)` og lagre.

- [ ] **Steg 1: Legg til `public private(set) var fileHadGame = true` på `ProgressStore`, satt i `load()` (sann når fila har nøkkelen `game` eller ikke finnes), med denne testen i `ProgressStoreTests`:**

```swift
    func testLoadReportsWhetherTheFileHadGameProgress() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fremdrift-\(UUID().uuidString).json")
        let store = ProgressStore(url: url)
        _ = store.load()
        XCTAssertTrue(store.fileHadGame, "a missing file needs no seeding")
        try Data(#"{"puzzles":{},"days":{}}"#.utf8).write(to: url)
        _ = store.load()
        XCTAssertFalse(store.fileHadGame)
        try store.save(LearnerProgress())
        _ = store.load()
        XCTAssertTrue(store.fileHadGame)
    }
```

Kjør `swift test --filter ProgressStoreTests` først (rød), så etter implementeringen (grønn).

- [ ] **Steg 2: Implementer seksjonen, egenskapene og `AppStore+Games.swift`, og hektene i `record`, `start` og sandkassen**

- [ ] **Steg 3: Bygg og test**

Kjør: `swift build && swift test`
Forventet: grønt. Skjermbildemodusen (`REGNSKAP_SCREENSHOTS`) skal fortsatt kjøre gjennom uten å starte klokka.

- [ ] **Steg 4: Commit**

```bash
git add Sources/Regnskapsskolen/App Sources/Regnskapsskolen/UI/MainView.swift Sources/RegnskapKit/Learning/ProgressStore.swift Tests/RegnskapKitTests/ProgressStoreTests.swift
git commit -m "feat(app): game rounds, XP and badges wired into the store"
```

---

### Task 7: Huben

**Files:**
- Create: `Sources/Regnskapsskolen/UI/Game/GameHubView.swift`
- Modify: `Sources/Regnskapsskolen/UI/MainView.swift` (bruk `GameHubView`)

**Interfaces:** Consumes oppgave 6. Produces `struct GameHubView: View`.

Innhold, ovenfra: `SectionHeader(title: "Spill", subtitle: "Korte runder som teller i boksene og gir XP")`. **Nivåkort**: `Image(systemName: "star.circle.fill")`, nivånavn i `.title3.weight(.semibold)`, «1 240 XP», en `MasteryBar`-lignende linje mot neste terskel med «260 til Regnskapsfører» (ingen linje på Partner). **Merker**: `LazyVGrid` med fire kolonner, hvert merke som symbol + navn; tjente i `Color.skole`, utjente i `.secondary.opacity(0.4)`, `.help(beskrivelse)` og dato for tjente. **To spillkort** side om side (`HStack`), hvert med tittel, én setning, «Rekord: 1 600» (eller «Ingen runde ennå»), for Lynrunden en `Picker("Tema", selection: $store.lynrundeTema)` med «Alle temaer» (`nil`) og `LightningRound.topics(in: store.pool)` (navn fra `store.topic`), og knappen **Spill** (`.borderedProminent`, `.tint(.skole)`; i Lynrunden slått av når `LightningRound.eligible(...)` er tom, med teksten «Ingen oppgaver i dette temaet»). Når `store.newBadges` ikke er tom: en rolig `Label("Nytt merke: …", systemImage:)` nederst, som forsvinner ved neste besøk. Lynrunde-kortets tekst: «90 sekunder med quiz, mva og saker. Riktig svar bygger combo; feil viser forklaringen.» Debet/kredit-kortets: «60 sekunder: øker kontoen på debet eller kredit? Piltaster eller D og K.»

- [ ] **Steg 1: Skriv `GameHubView` og koble den inn**

- [ ] **Steg 2: Bygg og tegn skjermbildene**

Kjør: `make app && REGNSKAP_SCREENSHOTS=/tmp/shots build/Regnskapsskolen.app/Contents/MacOS/Regnskapsskolen`
Forventet: `/tmp/shots/game.png` viser nivåkortet, merkene (ingen tjente i demoen) og to spillkort med Spill-knapper. Sidepanelet viser «Spill» etter «Øv».

- [ ] **Steg 3: Commit**

```bash
git add Sources/Regnskapsskolen/UI/Game/GameHubView.swift Sources/Regnskapsskolen/UI/MainView.swift
git commit -m "feat(app): the Spill hub with level, badges and the two games"
```

---

### Task 8: Lynrunden på skjermen og oppsummeringen

**Files:**
- Create: `Sources/Regnskapsskolen/UI/Game/LightningRoundView.swift`
- Create: `Sources/Regnskapsskolen/UI/Game/RoundSummaryView.swift`
- Modify: `Sources/Regnskapsskolen/UI/Game/GameHubView.swift` (viser runden eller oppsummeringen i stedet for huben mens `store.lightning`/`store.drill`/`store.lastSummary` finnes)
- Modify: `Sources/Regnskapsskolen/App/Screenshots.swift` (`spill-lynrunde.png`, `spill-oppsummering.png`)

**Interfaces:** Consumes oppgave 6 (`answerLightning`, `nextInRound`, `endRound`). Produces `struct LightningRoundView: View`, `struct RoundSummaryView: View` (`summary: RoundSummary`, `newBadges: [Badge]`, `isRecord: Bool`, `onAgain: () -> Void`, `onHub: () -> Void`).

`LightningRoundView`: topplinje med `Label("\(Int(remaining.rounded(.up))) s", systemImage: "timer")` (rød under 10 s), «\(score) poeng», `Pill(text: "×\(combo)", color: .skole)`, «\(answered) besvart», og **Avbryt** (`store.endRound()`). Tiden leses av `TimelineView(.periodic(from: .now, by: 0.1))` mot `store.lightning?.remaining(at: store.now)`. Spørsmålet: `Text(puzzle.tittel)` og `MarkdownText(puzzle.oppgave)`; svaret etter type: `quiz` → `QuizView(quiz:selected:)` der `.onChange(of: selected)` sender `.quiz(valg)` med en gang; `sak` → `CaseView(sak:selected:)` på samme måte; `mva` → ny `LightningVATView(vat:, rates:, onAnswer:)` i samme fil: knapper for hver kode i `rates` (`kode` og `navn`), og når `vat.fasit.fradrag != nil` et andre steg «Fradrag for inngående mva?» med **Ja**/**Nei**, så `onAnswer(.vat(behandling:fradrag:))`. Tastatur: `1`–`4` velger quiz-alternativ (`.keyboardShortcut`). **Tilbakemelding** (`phase == .feedback`): et panel i `Color.bad.opacity(0.08)` med `Label("Ikke riktig", systemImage: "xmark.circle.fill")`, riktig alternativ (quiz: `alternativer[svar]`; sak: valgets tekst; mva: behandling og fradrag), første avsnitt av `forklaring` som `MarkdownText`, og **Neste** (`.keyboardShortcut(.return)`) som er slått av til 1,5 s har gått. Et riktig svar gir et kort grønt blink på topplinjen (`withAnimation(.easeOut(duration: 0.3))`).

`RoundSummaryView`: «Runden er over», spillets navn, `StatTile`-rad: poeng, riktige av besvarte, beste combo, XP tjent; `Pill(text: "Ny rekord!", color: .ok)` når `isRecord`; nye merker som `Label`; knappene **Spill igjen** (`.borderedProminent`) og **Til spill**.

`Screenshots`: etter seksjonsløkka: `store.lynrundeTema = nil; store.startLightning()` (klokka må ikke startes i skjermbildemodus: `startLightning` sjekker `REGNSKAP_SCREENSHOTS` før den starter `clock`), `navigation.section = .game`, snap `spill-lynrunde.png`; `store.endRound()`, snap `spill-oppsummering.png`; nullstill `lastSummary`.

- [ ] **Steg 1: Skriv visningene, hekt dem inn i huben, legg til skjermbildene**

- [ ] **Steg 2: Bygg og tegn**

Kjør: `make app && REGNSKAP_SCREENSHOTS=/tmp/shots build/Regnskapsskolen.app/Contents/MacOS/Regnskapsskolen`
Forventet: `spill-lynrunde.png` viser topplinjen med tid, poeng, combo og en oppgave med svaralternativer; `spill-oppsummering.png` viser tallene og de to knappene.

- [ ] **Steg 3: Kjør alle testene**

Kjør: `swift test`. Forventet: grønt.

- [ ] **Steg 4: Commit**

```bash
git add Sources/Regnskapsskolen/UI/Game Sources/Regnskapsskolen/App/Screenshots.swift
git commit -m "feat(app): lightning round and round summary screens"
```

---

### Task 9: Debet eller kredit? på skjermen

**Files:**
- Create: `Sources/Regnskapsskolen/UI/Game/DebitCreditView.swift`
- Modify: `Sources/Regnskapsskolen/UI/Game/GameHubView.swift` (viser `DebitCreditView` når `store.drill` finnes)
- Modify: `Sources/Regnskapsskolen/App/Screenshots.swift` (`spill-debet-kredit.png`)

**Interfaces:** Consumes oppgave 6 (`answerDrill`, `nextInRound`, `endRound`).

Topplinje som Lynrunden (60 s). Kortet midt på: `Text(account.nr).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()`, `Text(account.navn).font(.title2)`, og `Text(increases ? "øker" : "minker").font(.title3).foregroundStyle(.secondary)`. To store knapper under: **Debet** i `Color.debet` og **Kredit** i `Color.kredit`, `frame(minWidth: 160, minHeight: 56)`, med `.keyboardShortcut(.leftArrow, modifiers: [])`/`"d"` og `.keyboardShortcut(.rightArrow, modifiers: [])`/`"k"` (to usynlige knapper for bokstavene er greit). Tilbakemelding ved feil: kortet får rød ramme, `Text(card.explanation)` under, og **Neste** (Enter) etter 1,5 s. Riktig: grønt blink, neste kort med en gang.

`Screenshots`: `store.startDrill()` (uten klokke i skjermbildemodus), snap `spill-debet-kredit.png`, `store.endRound()`, nullstill `lastSummary`.

- [ ] **Steg 1: Skriv visningen, hekt den inn, legg til skjermbildet**

- [ ] **Steg 2: Bygg og tegn**

Kjør: `make app && REGNSKAP_SCREENSHOTS=/tmp/shots build/Regnskapsskolen.app/Contents/MacOS/Regnskapsskolen`
Forventet: `spill-debet-kredit.png` viser et kontokort med de to store knappene i debet- og kredit-fargene.

- [ ] **Steg 3: Kjør alle testene**

Kjør: `swift test`. Forventet: grønt.

- [ ] **Steg 4: Commit**

```bash
git add Sources/Regnskapsskolen/UI/Game/DebitCreditView.swift Sources/Regnskapsskolen/UI/Game/GameHubView.swift Sources/Regnskapsskolen/App/Screenshots.swift
git commit -m "feat(app): debit-or-credit drill screen"
```

---

### Task 10: Dokumentasjon

**Files:**
- Modify: `CLAUDE.md` (tabellen: `Sources/RegnskapKit` nevner Games (XP, merker, Lynrunde, Debet/kredit); `Sources/Regnskapsskolen` nevner Spill)
- Modify: `README.md` («Daglig bruk»: ett avsnitt om Spill: to runder, XP og merker, at Lynrunden teller i boksene, ingen lyd)
- Modify: `docs/engineering-notes.md` hvis klokka eller tastaturet kostet tid

- [ ] **Steg 1: Skriv tekstene**

- [ ] **Steg 2: Kjør alt**

Kjør: `swift test`. Forventet: grønt.

- [ ] **Steg 3: Commit**

```bash
git add CLAUDE.md README.md docs/engineering-notes.md
git commit -m "docs: the Spill section, XP and badges"
```
