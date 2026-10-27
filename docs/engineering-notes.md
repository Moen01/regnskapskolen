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

## Skjermbilder uten å klikke

`REGNSKAP_SCREENSHOTS=<mappe>` tegner hver skjerm i et vindu utenfor skjermen og skriver PNG. Tre ting måtte til på macOS 26:

1. **`NSHostingController` krymper vinduet** til visningens ideelle størrelse. Rotvisningen får `.frame(width:height:)` og kontrolleren `sizingOptions = []`.
2. **Innholdet i glass-containere (sidefeltet) tegnes av vindustjeneren**, ikke av `cacheDisplay`; det kommer ut tomt. `Screenshots.render` tar et eget bilde av hver `…GlassEffectView` sin innholdsvisning og legger det oppå. `NSGraphicsContext(bitmapImageRep:)` jobber i punkter, ikke piksler.
3. **Vindusbakgrunnen er ikke en del av innholdsvisningen.** Rotvisningen får `.background(Color(nsColor: .windowBackgroundColor))`, ellers blir PNG-en gjennomsiktig.

Symboler i sidefeltet og markeringen av valgt rad tegnes fortsatt ikke, og `.borderedProminent`-knapper er grå fordi vinduet aldri er nøkkelvindu; det er nok for å se layout.

## Arbeid fra et agentskall

Å kjøre `open build/Regnskapsskolen.app` fra en Claude Code-økt i en terminal uten full disktilgang fikk macOS (TCC) til å trekke tilbake terminalens tilgang til `~/Documents` midt i økten. Bruk skjermbildemodus for å verifisere, og la et menneske åpne appen.
