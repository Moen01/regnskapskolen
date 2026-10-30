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
- **Lønnsfrister.** Klienter med ansatte (`ansatte > 0`, og da må `lonnsdag` stå i klientfilen, 1–28) får a-melding (den 5.), forskuddstrekk og arbeidsgiveravgift per termin. Alle datoer kommer fra `Innhold/satser.json` via `Deadlines`; ingenting er hardkodet i spillet. Forskuddstrekket forfaller første virkedag etter lønnsdagen (regelen fra 2026). `TownState.payrollFrom` er dagen en 2a-lagring først åpnes med 2b; lønnsfrister før den dagen finnes ikke, så ingen glipper tilbake i tid. En klient som vinnes sent, begynner regnskapet i måneden den ble vunnet (`ClientState.booksFrom`), ikke ved spillets start. Månedene før regnes som ført av forrige regnskapsfører: de kan ikke lukkes (`Ledger.canClose`), og en frist som gjelder dem, kan leveres når spillerens egne måneder i terminen er lukket (`ClientState.hasClosed`). En klient vunnet 2. mars leverer altså a-melding for februar, AGA 1. termin og mva 1. termin. En 2a-lagring kan ha bilag ført på måneder før klienten ble vunnet (2a skar haugen fra spillets start); da begynner regnskapet i den tidligste førte måneden, så de bilagene og feilene deres kan rettes og lukkes.
- **Oppdagede feil.** En åpen feil som er minst 7 dager gammel, oppdages av klienten med sjanse 1 av 4 per dag. Trekningen er seedet fra feilens id og dagen (`fnv1a` inn i `SplitMix64`), så samme dag gir samme utfall, også etter omstart. Bare oppgaver i den synlige `pool` kan oppdages. Klienten mister 15 fornøydhet, og spilleren retter feilen ved skranken med RETT FEIL.
- **Energi, og hvorfor feil ikke koster ekstra.** Energien er 100 og hvert møte koster 5, likt for rett og galt svar. Hadde et feil svar kostet mer, kunne spilleren lese dommen av energimåleren, og dommen skal vente til månedslukkingen. Tom energi gir besvimelse: spilleren våkner på kontoret neste morgen med full energi. Kaffe fra kontoret gir +30, én gang per dag, og ligger i BAG (`coffee`, `coffeeTakenOn`).
- **Kundesaker.** Personer med rollen `kundesak` har en `sak`- eller `quiz`-oppgave for en klient. Dommen og forklaringen vises med en gang (+5 fornøydhet ved rett svar), og saken tilbys bare én gang.
- **`masked` skjuler dommen på kartet.** `TownState.masked(progress)` gir en `LearnerProgress` der hvert bilag i en måned som ikke er lukket, står i boksen det hadde før føringen (`BookedBilag.boxBefore`), riktig eller feil; en åpen feil holdes også tilbake til den er rettet. Også et riktig svar flytter boksen, så å skjule bare feilene ville røpe dommen. Kartet, samlingen, «GYM n/m», byens prøvesaker og fagkontor og Paragrafjaktens økter (valg av skapning, steg, fanget eller gjentatt) bruker den. `Scheduler.record` skriver fortsatt den ekte fremdriften. En føring lagret før `boxBefore` fantes, skjules ikke. Bilagsskaden mot gymmen (`BookedBilag.damage`) venter til måneden er lukket, av samme grunn, og et bilag gir aldri oppgavemerker (`record(_:countXP:awardBadges:)`), fordi et merke for riktig svar ville røpe dommen.
- **Kjent grense: skjermer utenfor spillet leser den ekte fremdriften.** Mestring, statistikk, oppgavelisten og tilstanden til en enkelt oppgave viser de ekte boksene. Der kan en spiller som leter, se om et bilag var riktig før måneden er lukket.
- **Bydelene står i kartfilene.** En bydelskart har `bydel` (lik egen id), `rekkefolge`, `ankomst` og, fra den andre bydelen, `fullmakt` (samme navn som bydelen). Innendørskart nevner bydelen sin i `bydel`. `TownDistricts.all` leser dette; en ny bydel er en ny kartfil og ingenting mer. Fire bydeler og åtte fagkontor, to per bydel: Sentrum (Bilag, MVA), Havna (Bank, Periode), Industriområdet (Avskrivning, Lønn), Bryggen (Årsoppgjør, Valuta). Hver bydel har en port, og ingen dør fører forbi den (validatorregel 12).
- **Dekningsregelen kjøres bare av `validateAll`.** Regel 13 (hvert tema har et fagkontor, hver bydel har nøyaktig to) ligger i `validateTownCoverage`, ikke i `validateTown`. En by under bygging, eller den lille byen i testene, oppfyller den ikke.
- **Et kontor under bygging kreves ikke for fullmakten.** Bydel n gir fullmakten når alle *ferdige* kontorer i bydel n − 1 har merke. Et kontor er ferdig (`TownTrials.fagkontorReady`) når temaene har minst tre synlige oppgaver (`fagkontorSize`). Så spilleren aldri låses ute av innhold som mangler.
- **`ClientStatus.parked` er ikke `.archived`.** `.parked` er spillerens valg: klienten ligger i arkivet. `.archived` betyr at klienten sa opp (fornøydheten nådde 0). `park` krever `canPark`: ingen åpne feil og alle førte måneder lukket. Ellers ville en klient i arkivet gjemme en dom som ikke var avslørt ennå.
- **`rejoin` lukker månedene borte.** Både en hentet klient (`unpark`) og en klient som vinnes tilbake etter oppsigelse (`winTrial`) kaller `rejoin`: `activeFrom` settes til dagen, og hver måned fra `booksFrom` til nåværende måned uten bilag lukkes, siden spilleren ikke førte bøkene da. En måned med bilag beholdes som den er. Fornøydheten blir minst startverdien.
- **Regelkortet gjelder én kamp.** `takeEquippedCard()` gir kortet og tømmer `equippedCard`, så det aldri går videre til neste kamp.
- **`sandboxCleared` og journalen.** `TownState.sandboxCleared` er de sakene som alt har gitt noe. Bare `closedMonth` og `card` bruker opp saken; en sak som ikke ga noe (klienten ikke aktiv, ingen måned å lukke), lagres ikke, så neste lagring prøver igjen. Byen tømmer aldri en sandkassejournal: journalen er brukerens arbeid i sandkassen, og en case skal kunne øves om igjen, bare uten ny utbetaling.
- **`masked` tømmer `due`.** Et bilag med holdt-tilbake dom står i boksen fra før føringen, og `due` settes til `nil`; ellers ville rekkefølgen (et feil svar forfaller i morgen) røpe dommen. Klienter som har sagt opp (`.archived`) hoppes over: dommen er ikke hemmelig lenger.
- **Validator: mva og uregistrerte klienter.** Regel 6 sjekker også oppgaveteksten og forklaringen for klienter som ikke er mva-registrert: «inngående mva» eller en konto 2700–2749 er en feil, ikke bare nøkkelen. Regel 15: en kundesak for en slik klient kan ikke være en `quiz` eller `sak` med temaet `mva`.
- **Bokettersynet gjelder året som er omme, og kalenderen hoppes ikke.** `TownState.auditYear` er `calendar.today.year - 1`, hvis det året er med i spillet (`start.year`) og ikke står i `revidert`. Kontoret åpner altså 1. januar og gjelder året før. Å hoppe kalenderen til neste januar ville latt spilleren hoppe over fristene i mellomtiden; nå går tiden som vanlig, og et bestått syn setter bare `revidert`.
- **Én HP-måler, og ett forsøk per dag.** `AuditRun.hp == RegionRun.hp`. En feil som ikke rettes riktig, koster `TownRules.auditErrorCost`; et galt svar til en kontrollør koster vanskelighet × `RegionRun.hpLossPerLevel`. Ingen energi og ingen −10 fornøydhet i bokettersynet. `beginAudit` setter `auditTriedOn` ved start (`startAudit`), så å avslutte appen midt i gir ikke nytt forsøk samme dag. `failAudit` sender spilleren til kontoret og rører ikke klientene.
- **Gjennomgangen er det tredje stedet dommen kommer fram.** De to andre er månedslukkingen og rettingen ved skranken. `TownAudit.reviewed` tar åpne feil hos aktive klienter fra det reviderte året eller tidligere (`month.year <= year`), for oppgaver som finnes i puljen. Feil fra det nye året holdes tilbake som før. Gjennomgangen bruker `masked`-fremdriften, så en feil har trinnet fra før den gale føringen.
- **Panelet står i kartfilen.** `avgiftskontoret.json` har personen med `rolle: bokettersyn`, `kontrollorer` og `sensor`. `TownAudit.panel` hopper over oppgavene som fagkontorene bruker (de første `fagkontorSize` per kontor), så de tas sist, bare når temaet ikke har nok andre. Ingen oppgave stilles to ganger. Sensoren tar ett tema per oppgave. Mangler det oppgaver til panelet, er kontoret «under bygging» og kreves ikke.
- **Skjermen starter på nytt for hvert møte via et trinn.** `AuditRun.step` og `BilagRun` telles opp for hvert møte, og `BattleHost.key` gir dem til `BattleScreen`. Samme oppgave kan komme to ganger på rad (en feil og en kontrollør, eller to klienter med samme gale bilag, eller haugene som begynner igjen i januar), og skjermen kunne ellers holdt på den gamle kampen. Uten nøkkelen faller den tilbake på oppgave-id.
- **Nytt regnskapsår (`passAudit`).** Det nullstilles: sandkassebetalingen (`sandboxCleared`), energien (til maks) og kaffen i dag (`coffeeTakenOn`). Det som står: klientene og åpne feil, fullmakter, merker, regelkort, kontrakter og kalenderen.
- **`Ledger.pile` per kalenderår.** Haugen begynner på nytt hver januar: skiven regnes fra `max(booksFrom, 1. januar i måneden)`, og bare føringer fra samme år teller som ført.
- **Årsfristene.** Skattemelding (AS og ENK) og årsregnskap (bare AS) kommer fra `DeadlinePlanner` etter `selskapsform`, og datoene fra `satser.json` (`Deadlines`). `TownState.annualFrom` er som `payrollFrom`: en lagring uten feltet får dagen den åpnes, så en frist som alt er forbi, ikke glipper tilbake i tid.
- **Frister fra før spillet startet teller ikke.** `counts` krever `deadline.kind.year >= start.year` (`DeadlineKind.year`). Skattemeldingen for året før start forfaller i spillets første år, men gjelder et år spilleren aldri førte.
- **Lagring.** `GameProgress.town` er valgfritt. En bilagsøkt lagres ikke: ved omstart står spilleren ved klienten, førte bilag er lagret og uførte ligger i haugen.

## Game Boy-skallet

- **Én logisk skjerm, heltallsskala.** Alt under `UI/Game/GameBoy/` regner i piksler på en 160 × 144-skjerm og ganger med `gbScale` (3–5, det største som får plass). Plassering skjer med `offset` i en `ZStack(alignment: .topLeading)`; rammen må ha `alignment: .topLeading` på `frame`, ellers sentreres innholdet (første skjermbilde viste det).
- **Logikken ligger i Kit.** `AnswerPanel` (markør, skrivefelt, bilagslinjer) og `BattleFlow` (fasene i et møte) tar `GameKey` inn og gir hendelser ut; visningene tegner `rows`, `cursor`, `pages`. Alt som kan gå galt med taster, testes uten SwiftUI.
- **Ingen `onAppear` for tilstand skjermbildene trenger.** Skjermbildemodus tegner uten at `onAppear` kjører, så `BattleScreen` utleder flyten fra møtet og lagrer den per oppgave-id. Skrivemaskinen er av i skjermbildemodus (`typing: false`).
- **Farger bare i `GBTheme`.** Alle farger i spillet er navngitte tokens i `UI/Game/GameBoy/GBTheme.swift`, som CSS-variabler: `screen`, `text`, `textDim`, `boxFill`, `boxBorder`, `cursor`, `hpHigh/Mid/Low`, `dialogFill`, `dialogText` og en firefargepalett (`SpritePalette`) per ting: hver `Tile`, papirhaugen, hver `PersonRole`, spilleren og skapningene per `RegionTheme.farge`. Ingen annen fil under `UI/Game/GameBoy/` skriver en `Color(`-literal (sjekk med `grep`). Spritene har fire plasser som på Game Boy Color: 0 gjennomsiktig (eller flisens egen bunnfarge), 1 omriss (og hår og øyne), 2 kropp (klær), 3 detalj (hud, skapningens øyne). Kartet tegnes med én `Path` per palett og plass, i den rekkefølgen palettene dukker opp, så spilleren ligger øverst. Tekst holder minst 4,5 : 1 mot sin boks.
- **Dialogboksen er 36 × 4.** `DialogBox` i Kit (36 tegn, 4 linjer, 4 px per tegn) styrer sidedelingen i `BattleFlow` og `TownFlow`; `GBText(_, size: .small)` tegner den halve skriftstørrelsen. Boksen er 160 × 32 på y 112, med linjer på y 5, 10, 15 og 20 (fjerde linje slutter på 24) og ▼ eller TAB▼ i cellen y 25–28, under fjerde linje og over den indre rammen, som GBBox tegner 1 px tykk på y 29 (høyde − 3). Alle tallene er hele piksler, så linjene treffer skjermpiksler ved hver heltallsskala. ▼ står 3 px fra høyre, til høyre for tekstkolonnene. I kampen står kampbildet der det står; båndet y 96–111 viser kampbildets bakgrunn, og KJEMP/LES/REGLER/FLYKT (8 px) står i samme boks på 32 px. Byvalidatorens grense på 18 tegn per ord står fast.
- **Listevinduene er `ListBox`: 34 tegn, 7 px per rad.** Radene i menyen, Fristnav, KART, porteføljen, bagen, regelkortene, arkivet, skranken, JA/NEI, trekklisten og svarpanelene i kampen og listene i Paragrafjakten tegnes i 4 px (`GBList` bruker `.small` og `ListBox.rowHeight`), så lange navn får plass: `TownFlow.rowColumns` og `AnswerPanel.columns` er `ListBox.columns`. Tittelen (ARKIV, KART, BILAG D… K…) beholder 8 px og kortes til `ListBox.titleColumns` (17). Antall synlige rader regnes fra plassen under tittelen: `ListBox.rows(in:)`, og i vinduet på 90 px er det `ListBox.windowRowSpace` = 72 px, altså 10 rader (`AnswerPanel.visibleRows`). Hele raden er klikkflate.
- **Store bokstaver med aksent.** «Press Start 2P» presser en stor bokstav med aksent inn i versalhøyden: aksenten tar de øverste radene, og bokstaven krymper til høyden av en liten bokstav. I 4 px leses É som é, Ö som ö, og Å mister ringen. `GBText` tegner derfor Å, Á, Ä, É, È, Ê, Ö og Ü som grunnbokstaven (A, E, O, U) i full høyde og aksenten i piksler over den (`CapitalAccent`, i fontpiksler, det vil si en åttendedel av et tegn, så den følger begge størrelsene). I 8 px står aksenten med én rad luft over bokstaven; i 4 px står den rett på bokstaven, fordi linjene i dialogen bare har 1 px mellom seg. Ø og Æ har ingen aksent og beholder fontens tegn. Små bokstaver med aksent er riktige i fonten og røres ikke.
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
