# Tekniske notater

Ting som kostet tid, så de ikke koster tid igjen.

## Pakking

- **Symlinkede ressurser kommer ikke med i bundelen.** `scripts/bundle.sh` kopierer `Innhold/` inn i `Contents/Resources/Innhold` med `cp -R`. En symlink der gir en app som finner `temaer.json` på utviklermaskinen og ingen andre steder.
- **Varsler krever en ekte bundel.** `UNUserNotificationCenter` krasjer ved `swift run` (ingen `CFBundleIdentifier`). `Reminder` sjekker at `Bundle.main.bundleURL` slutter på `.app` og gjør ingenting ellers.
- **`LSUIElement`** i `Info.plist` holder appen ute av Dock til hovedvinduet åpnes; da settes aktiveringspolicyen til `.regular` og tilbake til `.accessory` når vinduet lukkes.
- Ad hoc-signering (`codesign --sign -`) er nok lokalt og i CI. Første åpning krever høyreklikk → Åpne. Signering for distribusjon: `SIGN_IDENTITY="Developer ID Application: …" ./scripts/bundle.sh release`.

## Claude Code som underprosess

- **Fjern den overordnede øktens variabler.** En `claude`-prosess som arver `CLAUDECODE`, `CLAUDE_CODE_*`, `CLAUDE_AGENT_SDK*`, `CLAUDE_PID*` eller `CLAUDE_EFFORT*` fra en Claude Code-økt (for eksempel når appen startes fra et agentskall) oppfører seg som en nøstet økt. `ShellEnvironment` filtrerer dem bort.
- **PATH fra innloggingsskallet.** En app fra Finder får launchd sin PATH uten `~/.local/bin`. `ShellEnvironment` spør `$SHELL -lic 'printf "$PATH"'` én gang, med markører rundt verdien så profilens utskrift ikke blander seg inn.
- `--tools ""` og en tom arbeidsmappe under `/tmp`: Claude skal svare, ikke handle.
- `--output-format json` gir `result`, `session_id`, `total_cost_usd` og (med `--json-schema`) `structured_output`.

## Innhold

- **JSON-tall gjennom `Double` mister presisjon** (14,1 blir 14.100000000000001). `Amount` dekoder via tallets korteste tekst til `Decimal`.
- `Progress` som typenavn kolliderer med `Foundation.Progress`; typen heter `LearnerProgress`.
- Innholdsmappen velges i rekkefølgen `REGNSKAP_INNHOLD`, Innstillinger, bundelen, repoet (fra `#filePath`). `onboard.sh` setter Innstillinger til repoets `Innhold/`, så nye filer vises uten ny bygging; `reloadIfChanged` sammenligner fil-lister og endringstider når appen blir aktiv.

## Sidepanelet og museklikk

- **`List(data, selection:)` matcher rader mot ForEach-id-en, ikke mot `.tag()`.** `AppSection.id` er `String`, bindingen er `AppSection`; da ble ingen rad markert og klikk gjorde ingenting, mens tastatur og Accessibility virket. `id: \.self` i `MainView` løste det. Samme felle gjelder alle lister der valgtypen ikke er lik id-typen.
- **Raske klikk som forsvinner i alt SwiftUI-innhold (knapper, rader), mens verktøylinjen virker, kan komme utenfra.** Et verktøy med global event-tap (Rectangle) som hadde kjørt lenge, ødela rekkefølgen på mouseDown/mouseUp; trykk over ~0,4 s gikk gjennom, korte ikke. Omstart av verktøyet fjernet feilen. Sjekk dette før du leter i appen: `sample <pid>` under et klikk viser om noe står i en tracking-loop.

## Datoer

- **`DatePicker` på macOS er for liten til å treffe.** `.field` er tre små segmenter, `.graphical` tegner dagene ca. 18 pt brede. `MonthCalendar` er en egen SwiftUI-måned med 36 × 30-celler, og `DateField` setter et skrivefelt (`dd.mm.åååå`, `NorwegianFormat.parseDay`) foran den. Året må ha fire sifre: «10.06.26» kan ikke skilles fra et år som ikke er ferdig skrevet.
- **Sidepanelet lukker en åpen oppgave.** `MainView` nullstiller `openPuzzle` når `navigation.section` endres; tilbakeknappen er bare en snarvei.

## Spillene

- **Klokka er et argument, ikke `Date()`.** `LightningRound` og `DebitCreditDrill` får `now` inn i hvert kall og pauser ved å bokføre pausetid; testene kjører en hel runde med faste tall. Appen tikker fra en `Task` hvert 100 ms, men tildeler bare runden på nytt når fasen endrer seg, ellers tegner hele skjermen ti ganger i sekundet. Selve nedtellingen leser `TimelineView` rett fra runden.
- **Én tastatursnarvei per knapp.** `Debet` skal svare på både ← og D; den andre tasten ligger på en usynlig knapp i `.background`.

## Oppdateringer og Swift 6

- **`static let` i en `@MainActor`-klasse er aktør-isolert.** `Reminder.updatePrefix` leses fra en `nonisolated` delegatmetode og må være `nonisolated static let`, ellers nekter kompilatoren.
- **`try await XCTUnwrap(expr)` kompilerer ikke**: `XCTUnwrap` tar en autoclosure som ikke kan vente. Skriv `let x = try await expr; try XCTUnwrap(x)`.
- **Skjermbildemodus må aldri lagre til Application Support.** En avsluttet demo-runde lagret fremdriften over den ekte fila (27.10.2026). `Screenshots.capture` bytter `store.progressStore` til en fil ved siden av PNG-ene før noe tegnes.

## Gatekeeper på macOS 15

- **Høyreklikk → Åpne virker ikke lenger for ad hoc-signerte apper.** Dialogen har bare «Done» og «Move to Bin». Veien er Systeminnstillinger → Personvern og sikkerhet → «Åpne likevel» etter første forsøk, eller `xattr -dr com.apple.quarantine <app>`. Oppdateringer appen gjør selv fjerner karantenen etter `codesign --verify`, så bare førstegangsinstallasjonen rammes. Developer ID + notarisering fjerner dialogen helt.

## Paragrafjakten

- **Bindinger lever lenger enn visningen.** `EncounterView` bandt inndata til `store.encounterSession!`; når `endRun()` nullstilte økten, oppdaterte SwiftUI fortsatt bindingene på vei ut og trappet på nil. Bindinger inn i valgfri tilstand må ha en fallback (`PuzzleAttempt.empty(for:)`).
- **Trekk er (lov, paragraf)-par, ikke regelkort.** Sju temaer har ett kort, og et kort kan dekke flere lover, så parene gir valg der kortene ikke gjør det. Avledere hentes fra andre temaer og treffer aldri oppgaven.

## Byen (Rubin-utgaven)

- **`TownFlow` er ren tilstand, som `BattleFlow`.** Den tar `GameKey` inn, eier fase, sider og rader, og gir en `TownAction` ut. Butikken (`AppStore+Town`) utfører handlingen. Flyten bruker aldri kalendertid selv; det er butikken som bestemmer hva som koster tid.
- **`BattleHost` gjør `BattleScreen` uavhengig av spillet.** Skjermen får hente møte, økt, utfall og HP, og velge, angripe, flykte og gå videre, gjennom closures. Paragrafjakten og byen gir hver sine closures (`BattleHost.adventure(store)` og byens egne), så skjermen vet ikke hvilket spill den tjener.
- **Rekkefølgen: handlingen skjer først, tiden brukes etterpå.** Et bilag, en retting, en prøvesak eller et fagkontor setter `townActionPending`. Tiden brukes (`spendPendingAction`) når spilleren er tilbake i byen (`showTown`), ikke når økten starter. Da får et bilag som føres med dagens siste handling dagens dato. `deliver` leverer før den bruker handlingen, så fristdagens siste handling teller. «Glippet» registreres først dagen etter fristen.
- **Skjulte utkast.** Klientens haug filtreres mot `pool` (det spilleren ser). Feil på skjulte oppgaver kan aldri vises som rettinger, så de blokkerer ikke lukkingen (`closeIfClean(_, pool:)`) og slettes når måneden lukkes. Ellers kunne en måned aldri lukkes. En haug kan også bli tom; da kan måneden lukkes uten møter.
- **Dommen holdes tilbake i byen, ikke i Leitner.** `Scheduler.record` kalles i det spilleren svarer, også for et bilag; boksene og rekken er like ærlige som overalt ellers. Bare byens dialog venter: et bilag sier «ført», og om det var riktig kommer først ved månedslukking. Det er spillets poeng (en bokfører ser ikke egne feil før avstemmingen). En retting sier dommen med en gang. Skadepoeng (`regionDamage`) telles bare på dagens første svar, som i `RegionRun`, så byen ikke kan brukes til å tjene opp fagkontorets port.
- **Lagring.** `GameProgress.town` er valgfritt. En bilagsøkt lagres ikke: ved omstart står spilleren ved klienten, førte bilag er lagret og uførte ligger i haugen.

## Game Boy-skallet

- **Én logisk skjerm, heltallsskala.** Alt under `UI/Game/GameBoy/` regner i piksler på en 160 × 144-skjerm og ganger med `gbScale` (3–5, det største som får plass). Plassering skjer med `offset` i en `ZStack(alignment: .topLeading)`; rammen må ha `alignment: .topLeading` på `frame`, ellers sentreres innholdet (første skjermbilde viste det).
- **Logikken ligger i Kit.** `AnswerPanel` (markør, skrivefelt, bilagslinjer) og `BattleFlow` (fasene i et møte) tar `GameKey` inn og gir hendelser ut; visningene tegner `rows`, `cursor`, `pages`. Alt som kan gå galt med taster, testes uten SwiftUI.
- **Ingen `onAppear` for tilstand skjermbildene trenger.** Skjermbildemodus tegner uten at `onAppear` kjører, så `BattleScreen` utleder flyten fra møtet og lagrer den per oppgave-id. Skrivemaskinen er av i skjermbildemodus (`typing: false`).
- **Fonten.** «Press Start 2P» ligger i `Resources/Fonts/` (OFL) og registreres av `ATSApplicationFontsPath` i bundelen; `GBFont.register()` tar den fra repoet når appen kjøres uten bundle. Mangler den, brukes systemets monospace i fet. Fonten mangler U+2212, så spilltekst bruker ASCII-minus.
- **Korte lovnavn** er innhold (`Innhold/lover.json`), ikke kode; testen krever en oppføring per lov i repoet, mens kjøretiden faller tilbake til fullt navn.

## Skjermbilder uten å klikke

`REGNSKAP_SCREENSHOTS=<mappe>` tegner hver skjerm i et vindu utenfor skjermen og skriver PNG. Tre ting måtte til på macOS 26:

1. **`NSHostingController` krymper vinduet** til visningens ideelle størrelse. Rotvisningen får `.frame(width:height:)` og kontrolleren `sizingOptions = []`.
2. **Innholdet i glass-containere (sidefeltet) tegnes av vindustjeneren**, ikke av `cacheDisplay`; det kommer ut tomt. `Screenshots.render` tar et eget bilde av hver `…GlassEffectView` sin innholdsvisning og legger det oppå. `NSGraphicsContext(bitmapImageRep:)` jobber i punkter, ikke piksler.
3. **Vindusbakgrunnen er ikke en del av innholdsvisningen.** Rotvisningen får `.background(Color(nsColor: .windowBackgroundColor))`, ellers blir PNG-en gjennomsiktig.

Symboler i sidefeltet og markeringen av valgt rad tegnes fortsatt ikke, og `.borderedProminent`-knapper er grå fordi vinduet aldri er nøkkelvindu; det er nok for å se layout.

## Arbeid fra et agentskall

Å kjøre `open build/Regnskapsskolen.app` fra en Claude Code-økt i en terminal uten full disktilgang fikk macOS (TCC) til å trekke tilbake terminalens tilgang til `~/Documents` midt i økten. Bruk skjermbildemodus for å verifisere, og la et menneske åpne appen.
