# Lekent tema (Catacloud) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A toggleable "lekent tema" that reskins every non-game screen in Catacloud's warm premium look, adds an accountant figure and medium-level celebrations, without touching the game UI.

**Architecture:** One `AppTheme` value in the SwiftUI environment carries the playful tokens and an `isPlayful` flag. Semantic view modifiers (`.themedScreenBackground()`, `.themedCard()`, `.themedPrimaryButton()`, `.themedHeading()`) branch on that flag: the standard branch is today's literal styling (so "off" is pixel-identical), the playful branch is the Catacloud warm skin. Celebration *detection* is pure logic in RegnskapKit (tested); celebration *rendering* is a SwiftUI overlay fed by an observable `pendingCelebration` on `AppStore`.

**Tech Stack:** Swift 6, SwiftUI, macOS 15. No new dependencies, no bundled assets — figure and confetti are drawn in code.

**Spec:** `docs/superpowers/specs/2026-11-19-lekent-tema-design.md`

## Global Constraints

- RegnskapKit never imports SwiftUI/AppKit. Only pure, UI-free logic may be added there (CLAUDE.md: "Logikk som kan testes, ligger i RegnskapKit").
- The app target (`Regnskapsskolen`) has **no test target** — SwiftUI code is verified by `swift build` + the `REGNSKAP_SCREENSHOTS` harness, not XCTest.
- User-facing text in Norwegian bokmål; code and comments in English.
- Settings persist via the `AppSettings` + UserDefaults `didSet`/`init` pattern. New key: `tema.lekent`, **default ON** (`defaults.object(forKey:) as? Bool ?? true`).
- Theme off ⇒ every screen looks exactly like today. Game UI (`UI/Game/**`) is never touched.
- All motion and celebration respect `@Environment(\.accessibilityReduceMotion)`: when true, no confetti/bounce/spring, plain fades only.
- Playful palette tokens (verbatim from spec): screen `#f7f5f2`, card `#ffffff` r=20, shadow `0 1 3 / .04` + `0 6 24 / .04`, accent `#4a5e9e`, text `#2c2a26` / `#6b6760`, success `#3CBF9C` (text `#2a8a70`), danger `#F85C5C` (text `#c04848`), warning `#f5b04d`, debet `#4a5e9e`, kredit `#f5b04d`-darkened. Dark playful: screen `#26241f`, card `#32302a`, text `#f7f5f2`, accent `#7a8fc4`.
- Confetti colors: `#F85C5C`, `#f5b04d`, `#3CBF9C`, `#4a5e9e`, `#ED4A7B`.

## Review Focus

- **Toggle off mid-session restores today's look exactly** — every modifier's standard branch must reproduce the literal pre-refactor styling. Owned by Task 3/4; checked by the standard-theme screenshot diff in Task 8.
- **Reduce Motion on ⇒ no confetti/bounce** — celebration overlay and motion modifiers must read `accessibilityReduceMotion`. Owned by Task 6; verified in Task 8.
- **Day completed inside the game ⇒ celebration deferred, never shown over Game Boy, never lost** — `pendingCelebration` is set in `record()` but the overlay only renders when `section != .game`. Owned by Task 2 (set) + Task 6 (render gate).
- **Never fires on launch / already-done day** — pure `forDayTransition` returns nil unless `!wasDone && isDone`. Owned by Task 1 tests.
- **Dark playful contrast** — warm dark tokens must stay legible; `.playful(dark:)` carries them. Owned by Task 3; eyeballed in Task 8 dark screenshots.

---

### Task 1: Celebration detection (RegnskapKit, TDD)

**Files:**
- Create: `Sources/RegnskapKit/Learning/Celebration.swift`
- Test: `Tests/RegnskapKitTests/CelebrationTests.swift`

**Interfaces:**
- Produces: `public enum Celebration: Equatable, Sendable { case dayCompleted; case streakMilestone(Int) }` and `public enum Celebrations { public static let milestones = [7, 30, 100]; public static func forDayTransition(wasDone: Bool, isDone: Bool, streak: Int) -> Celebration? }`.
- Rule: returns `nil` unless `!wasDone && isDone`; then `.streakMilestone(streak)` if `milestones.contains(streak)`, else `.dayCompleted`. Milestone outranks plain done.

- [ ] **Step 1: Write the failing tests** in `CelebrationTests.swift`:

```swift
func testNoTransitionWhenAlreadyDone() {
    XCTAssertNil(Celebrations.forDayTransition(wasDone: true, isDone: true, streak: 7))
}
func testNoTransitionWhenStillNotDone() {
    XCTAssertNil(Celebrations.forDayTransition(wasDone: false, isDone: false, streak: 3))
}
func testPlainCompletionOnNonMilestoneStreak() {
    XCTAssertEqual(Celebrations.forDayTransition(wasDone: false, isDone: true, streak: 3), .dayCompleted)
    XCTAssertEqual(Celebrations.forDayTransition(wasDone: false, isDone: true, streak: 50), .dayCompleted)
}
func testMilestoneCompletion() {
    for s in [7, 30, 100] {
        XCTAssertEqual(Celebrations.forDayTransition(wasDone: false, isDone: true, streak: s), .streakMilestone(s))
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter CelebrationTests` → FAIL (type not defined).
- [ ] **Step 3: Implement** `Celebration` + `Celebrations.forDayTransition` per the rule above.
- [ ] **Step 4: Run to verify pass** — `swift test --filter CelebrationTests` → PASS.
- [ ] **Step 5: Run `swift test --filter Content`** — validator still green.
- [ ] **Step 6: Commit** — `feat(kit): celebration trigger for day completion and streak milestones`.

---

### Task 2: Settings toggle + store wiring

**Files:**
- Modify: `Sources/Regnskapsskolen/App/AppSettings.swift` (add `playfulTheme`)
- Modify: `Sources/Regnskapsskolen/App/AppStore.swift` (add `var pendingCelebration: Celebration?`)
- Modify: `Sources/Regnskapsskolen/App/AppStore+Today.swift` (`record()` sets it)

**Interfaces:**
- Consumes: `Celebrations.forDayTransition` (Task 1).
- Produces: `settings.playfulTheme: Bool` (default ON, key `tema.lekent`); `store.pendingCelebration: Celebration?` (observable, nil at launch).

- [ ] **Step 1:** Add `playfulTheme` to `AppSettings` following the exact `didSet`/`init` pattern of `showGame`, default `defaults.object(forKey: "tema.lekent") as? Bool ?? true`.
- [ ] **Step 2:** Add `var pendingCelebration: Celebration?` to `AppStore` (plain observable property, not `@ObservationIgnored`).
- [ ] **Step 3:** In `record()`, replace the done-transition block so that after `Badges.award(.dayCompleted…)` it also sets `pendingCelebration = Celebrations.forDayTransition(wasDone: wasDone, isDone: progress.days[todayKey.string]?.done == true, streak: streak)` — but only overwrite when the result is non-nil, so a later same-day answer never clears a still-unshown celebration.
- [ ] **Step 4:** `swift build` → succeeds.
- [ ] **Step 5: Commit** — `feat(app): playful-theme setting and pending-celebration state`.

---

### Task 3: AppTheme, environment, core modifiers

**Files:**
- Create: `Sources/Regnskapsskolen/UI/Components/AppTheme.swift`
- Modify: `Sources/Regnskapsskolen/App/RegnskapsskolenApp.swift`, `Sources/Regnskapsskolen/App/AppDelegate.swift` (inject theme at the three roots: main window, popover, Settings scene)

**Interfaces:**
- Produces:
  - `struct AppTheme: Equatable { var isPlayful: Bool; var screenBackground, cardBackground, accent, primaryText, secondaryText, success, successText, danger, dangerText, warning, debet, kredit: Color; var cardCornerRadius: CGFloat; var headingDesign: Font.Design; var celebrationsEnabled: Bool }` with `static let standard` and `static func playful(dark: Bool) -> AppTheme`.
  - `extension EnvironmentValues { var appTheme: AppTheme }` (default `.standard`).
  - `extension View` modifiers: `.themedScreenBackground()`, `.themedCard(cornerRadius:CGFloat? = nil)`, `.themedPrimaryButton()`, `.themedHeading()`, and `.rootTheme()` — a modifier reading `@Environment(AppStore.self)` + `@Environment(\.colorScheme)` that computes `settings.playfulTheme ? .playful(dark: scheme == .dark) : .standard` and sets `\.appTheme` (and the playful screen background on the whole subtree).
- Standard-branch contract: `.themedCard()` with `isPlayful == false` applies exactly `.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius ?? 10))` and no shadow; `.themedScreenBackground()` is a no-op; `.themedPrimaryButton()` is `.buttonStyle(.borderedProminent).tint(.skole)`; `.themedHeading()` leaves the font unchanged. Playful branch applies the token values.

- [ ] **Step 1:** Write `AppTheme.swift` with the struct, `.standard` (today's semantic colors: debet/kredit/skole/ok/bad/warn from `Theme.swift`), `.playful(dark:)` (token table above), the environment key, the four semantic modifiers, and `.rootTheme()`.
- [ ] **Step 2:** Apply `.rootTheme()` at `MainView()` and `PopoverView()` creation in `AppDelegate` and at `SettingsView()` in `RegnskapsskolenApp`.
- [ ] **Step 3:** `swift build` → succeeds (no call sites use the modifiers yet; standard look unchanged).
- [ ] **Step 4: Commit** — `feat(ui): AppTheme tokens, environment and semantic modifiers`.

---

### Task 4: Apply theme to content screens

**Files (modify):** `UI/Today/TodayView.swift`, `UI/Topics/TopicsView.swift`, `UI/Stats/StatsView.swift`, `UI/Rules/RulesView.swift`, `UI/Sandbox/SandboxView.swift`, `UI/Puzzle/PuzzleView.swift` + `VerdictView.swift`, `UI/MenuBar/PopoverView.swift`, `UI/Components/Theme.swift` (`Pill`, `SectionHeader` read the theme).

**Interfaces:** Consumes the Task 3 modifiers + `@Environment(\.appTheme)`.

- [ ] **Step 1:** Replace every `.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: N))` (PuzzleCard, StatTile, TopicsView row, MarkdownBlocksView table) with `.themedCard(cornerRadius: N)`.
- [ ] **Step 2:** Replace `.buttonStyle(.borderedProminent).tint(.skole)` on the primary action of each screen (Today/Popover "Åpne…", Puzzle "Sjekk"/"Neste") with `.themedPrimaryButton()`. Leave `.tint(.blue)` update buttons alone.
- [ ] **Step 3:** Add `.themedScreenBackground()` to the top `ScrollView`/`HStack` of each content screen and the popover root; make `SectionHeader` use `.themedHeading()` and `Pill`/`MasteryBar` read `theme.accent`/`theme.success` for their playful fill.
- [ ] **Step 4:** `swift build` → succeeds.
- [ ] **Step 5: Verify** — run `REGNSKAP_SCREENSHOTS=/tmp/shots-playful` build; eyeball `today/practice/stats/rules/sandbox/popover.png` warm-skinned, and a standard-theme run unchanged. (Task 8 automates both-theme shots.)
- [ ] **Step 6: Commit** — `feat(ui): warm Catacloud skin on content screens`.

---

### Task 5: Accountant figure

**Files:** Create `Sources/Regnskapsskolen/UI/Components/AccountantFigure.swift`.

**Interfaces:** Produces `struct AccountantFigure: View { enum Pose { case standing, celebrating }; var pose: Pose = .standing; var size: CGFloat = 96 }` — the A1 figure (blue suit, yellow tie, briefcase, round head, simple smile) drawn with `Path`/`Shape`, `celebrating` raising the free arm. Reads `@Environment(\.appTheme)` so the suit uses `theme.accent`.

- [ ] **Step 1:** Implement the figure from `figur-regnskapsforer.html` variant A1 proportions (`.superpowers/brainstorm/31107-1795080723/content/`).
- [ ] **Step 2:** Show `.standing` in the empty states of Today ("Dagens oppgaver er gjort"), Rules ("Velg en regel") and the popover greeting — only when `theme.isPlayful`.
- [ ] **Step 3:** `swift build` → succeeds; screenshot run shows the figure where expected and nothing in standard theme.
- [ ] **Step 4: Commit** — `feat(ui): accountant figure drawn in SwiftUI`.

---

### Task 6: Confetti + celebration overlay

**Files:** Create `Sources/Regnskapsskolen/UI/Components/ConfettiView.swift`, `Sources/Regnskapsskolen/UI/Components/CelebrationOverlay.swift`; modify `UI/MainView.swift`, `UI/MenuBar/PopoverView.swift`.

**Interfaces:**
- `struct ConfettiView: View` — one `TimelineView(.animation)` + `Canvas` burst in the five confetti colors, ~2 s, self-contained (seeded offsets, no `Math.random` dependency).
- `struct CelebrationOverlay: View { let celebration: Celebration; let onDone: () -> Void }` — dim scrim + `AccountantFigure(pose: .celebrating)` + message (`.dayCompleted` → "Dagens økt er ferdig!", `.streakMilestone(n)` → "\(n) dager på rad!") + `ConfettiView`. Reads `accessibilityReduceMotion`: when true, drops the confetti and auto-dismisses with a plain fade.

- [ ] **Step 1:** Implement `ConfettiView` and `CelebrationOverlay`.
- [ ] **Step 2:** In `MainView`, add `.overlay { if theme.celebrationsEnabled, navigation.section != .game, let c = store.pendingCelebration { CelebrationOverlay(celebration: c) { store.pendingCelebration = nil } } }`. Same gate in `PopoverView`. The `section != .game` gate is what defers a celebration earned inside the game until the learner leaves it.
- [ ] **Step 3:** `swift build` → succeeds.
- [ ] **Step 4: Verify** — in the screenshot harness set `store.pendingCelebration = .streakMilestone(7)` on the Today screen and shoot it; confirm overlay renders, and that with `section == .game` it does not.
- [ ] **Step 5: Commit** — `feat(ui): celebration overlay with confetti and figure`.

---

### Task 7: Settings + sidebar full rebuild (playful branch)

**Files:** Modify `UI/Settings/SettingsView.swift`, `UI/MainView.swift`.

- [ ] **Step 1:** Add an "Utseende" `Section` to `SettingsView` with `Toggle("Lekent tema (Catacloud)", isOn: $settings.playfulTheme)` + caption; place it first.
- [ ] **Step 2:** When `theme.isPlayful`, render the Form's sections as custom white 20 pt cards on the warm background (`scrollContentBackground(.hidden)` + a `VStack` of `.themedCard()` section blocks); when not, keep today's `Form`/`.formStyle(.grouped)` untouched. Factor the section contents so both branches share them.
- [ ] **Step 3:** When `theme.isPlayful`, give the `MainView` sidebar custom rows (accent-filled rounded selection) over the warm background; when not, keep today's `List`. Both branches keep the same `selection: $navigation.section` binding and the Spill filter.
- [ ] **Step 4:** Theme `OnboardingView` and the content-notice overlay (warm card, accent progress dots, `.themedPrimaryButton()`), playful branch only.
- [ ] **Step 5:** `swift build` → succeeds; screenshots of `settings.png`/`onboarding.png` warm in playful, identical to today in standard.
- [ ] **Step 6: Commit** — `feat(ui): playful settings, sidebar and onboarding`.

---

### Task 8: Motion + both-theme screenshots

**Files:** Modify the content screens (hover-lift, mastery-bar spring, screen slide-in) + `Sources/Regnskapsskolen/App/Screenshots.swift`.

- [ ] **Step 1:** Add `.themedCard` hover lift (shadow + small translate) and spring-fill `MasteryBar`/`BoxHistogram` + content slide-in on appear, all gated `theme.isPlayful && !reduceMotion`.
- [ ] **Step 2:** Extend `Screenshots.capture` to also render `today`, `stats`, `settings`, `popover` with `settings.playfulTheme = true` (file suffix `-lekent.png`) and a celebration shot, leaving the existing standard shots in place.
- [ ] **Step 3: Verify** — `REGNSKAP_SCREENSHOTS=/tmp/shots` run: standard shots match today's look, `-lekent` shots show the warm skin, figure and a celebration; reduce-motion path produces no confetti.
- [ ] **Step 4:** `swift test` full suite green.
- [ ] **Step 5: Commit** — `feat(ui): playful motion and both-theme screenshots`.

---

## Self-Review

- **Spec coverage:** toggle (T2/T7), warm skin all non-game screens (T4/T7), figure A1 (T5), confetti+figure on done & milestones, medium level (T6/T1), full settings/sidebar rebuild (T7), dark playful (T3), reduce-motion (T6/T8), game untouched + deferred celebration (T6 gate), default ON (T2). Covered.
- **Type consistency:** `Celebration`/`Celebrations.forDayTransition` identical in T1→T2→T6; `AppTheme`/modifiers identical T3→T4–T8; `AccountantFigure.Pose` T5→T6.
- **Proportion:** plan carries decisions (tokens, modifier contracts, call-site swaps, gates) and defers all SwiftUI bodies to execution; only the pure celebration rule and its tests are spelled out as code.
- **Review Focus:** five listed, each pinned to an owning task.
