# Spillmodus, fase 1

Status: utkast til godkjenning. Skrevet 27.10.2026 etter samtale med Andreas.

## Hvorfor

Regnskap skal bli gøy og lett å huske. Dagens app er en pliktoppgave: tre oppgaver om dagen, Leitner-bokser, statistikk. Det virker, men det er ikke noe man *har lyst* til å åpne. En egen seksjon «Spill» gir to korte spill som kan tas på to minutter, med poeng, rekorder, nivåer og merker, og som samtidig mater den samme læringsmodellen som resten av appen.

Andreas har sagt ja til denne fasen og til **lyd dempet**: ingen lydeffekter, ingen konfetti. Tilbakemelding gis med farge, symbol og små, rolige animasjoner.

Fase 2 (ikke i dette dokumentet): «Regnskapsåret», en kampanje over sandkasse-caser med bankavstemming som månedsslutt, og «Finn feilen før revisor kommer». Fase 2 forutsetter bankavstemmingen i den andre spesifikasjonen.

## Mål

1. Ny seksjon **Spill** i sidemenyen, etter «Øv».
2. En **hub** som viser nivå og XP, merkene, og ett kort per spill med beste resultat og en «Spill»-knapp.
3. **Lynrunde**: 90 sekunder med oppgaver som besvares med ett klikk, combo-multiplikator, rekord per runde.
4. **Debet eller kredit?**: 60 sekunder med kontoer, venstre/høyre piltast eller D/K, trener refleksen «hvilken side øker kontoen på».
5. **XP, nivåer og merker** som ett felles lag. XP kommer fra spillene *og* fra dagens oppgaver, så nivået speiler all læring.
6. Lynrunden **mater Leitner**: hvert svar registreres som et forsøk på oppgaven, akkurat som i «I dag» og «Øv».

## Ikke-mål

- Regnskapsåret, Finn feilen på tid (fase 2).
- Lyd, konfetti, haptikk.
- Topplister på nett, kontoer, synkronisering. Rekordene er brukerens egne.
- Claude-generert spillinnhold. Spillene bruker oppgavene som finnes (godkjente, pluss utkast når «vis utkast» er på, som ellers i appen).
- Egen innstilling for spill. Ingenting å slå av eller på i fase 1.

## Anti-mål

- Spillet blir en silo. Lynrunden skal flytte oppgaver i boksene; en oppgave man bommer på i spillet kommer igjen i «I dag».
- Gjetting lønner seg. Feil svar nuller comboen, gir null poeng og viser forklaringen før neste oppgave kan besvares.
- Falske titler. Nivånavnene er yrkestrinn uten beskyttede titler: Lærling → Regnskapsmedarbeider → Regnskapsfører → Seniorregnskapsfører → Partner. («Autorisert regnskapsfører» er en lovregulert tittel og brukes ikke.)
- Tidspress som hindrer læring. Klokka står stille mens forklaringen etter et feil svar vises.

## Begrensninger

- All spillogikk i `RegnskapKit`, uten UI og uten `Date()`: klokka og tilfeldigheten injiseres, så rundene kan testes deterministisk (`SplitMix64` finnes allerede).
- `LearnerProgress` utvides bakoverkompatibelt: `fremdrift.json` fra før skal lese inn uten feil.
- Ingen nye avhengigheter.
- Norsk bokmål i alt brukeren leser.

## Lynrunde

- **Oppgaver**: typene `quiz`, `mva` og `sak`. De besvares uten skriving. `klassifiser`, `postering`, `regnut`, `finnfeil` og `frist` tar for lang tid og holdes utenfor. Hub-kortet lar brukeren velge «Alle temaer» eller ett tema; temaer med færre enn 8 slike oppgaver vises ikke i velgeren. (I dag: 29 godkjente og 59 med utkast, de fleste quiz og mva.)
- **Mva i to steg (mitt valg)**: først behandlingen (én knapp per kode i `satser.json`), så «Fradrag: Ja / Nei» når fasiten spør om det (`fasit.fradrag != nil`; `Checkers.vat` bryr seg ikke om fradrag ellers, så steget hoppes over). Sjekken går gjennom `PuzzleAttempt.vat` og `Checkers.vat` som i dag, ikke en egen snarvei.
- **Rekkefølge**: seedet stokking av utvalget, uten gjentak i samme runde. Forfalte oppgaver og oppgaver i boks 0–1 først, oppgaver som allerede er besvart i dag sist. Er utvalget tomt når tiden går, avsluttes runden tidlig.
- **Tid**: 90 sekunder. Klokka går mens en oppgave vises og står stille mens forklaringen vises.
- **Poeng**: riktig svar gir `100 × vanskelighet × combo`. Combo starter på 1,0 og øker med 0,25 per riktig på rad, maks 3,0. Feil svar: 0 poeng, combo tilbake til 1,0. Ingen minuspoeng (mitt valg: straffen er tapt combo og tapt tid til å lese forklaringen).
- **Etter feil svar**: riktig alternativ markeres, forklaringen (`forklaring`, første avsnitt) vises, klokka stopper. Neste oppgave kommer ved klikk eller Enter, tidligst etter 1,5 sekunder.
- **Etter riktig svar**: grønt blink, neste oppgave med en gang.
- **Leitner**: hvert besvarte spørsmål sendes til `Scheduler.record` med `correctFirstTry` = riktig på det ene forsøket. En oppgave fra dagens sett som besvares riktig i spillet telles som gjort i dag. Det er greit: den ble løst riktig på første forsøk.
- **Én telling per oppgave per dag (mitt valg)**: `Scheduler.record` flytter ikke en oppgave opp en boks når `lastSeen` allerede er i dag; forsøket telles, men boksen står. Feil svar sender fortsatt til boks 0. Uten dette ville fire runder på én kveld skyve hele utvalget til boks 4. Regelen gjelder også «Øv», der man i dag kan åpne samme oppgave flere ganger og rykke opp hver gang. Det er en endring i eksisterende oppførsel, og `SchedulerTests` får en test på den.
- **Rekord og merker**: rekorden `lynrunde` og merket `lynrask` gjelder bare runder med «Alle temaer». Temarunder lagres som `lynrunde:<tema>` og vises på hub-kortet når et tema er valgt.
- **Slutt**: poeng, riktige av totalt, beste combo, XP tjent, nye merker, rekord-markering hvis ny rekord, knappene «Spill igjen» og «Til spill».

## Debet eller kredit?

- **Kort** lages fra `kontoplan.json`: for hver konto to kort, «4300 Innkjøp av varer *øker*» (svar `okerPa`) og «4300 Innkjøp av varer *minker*» (motsatt side). Kontoer av typen `disponering` (8800–8990) holdes utenfor: de har ingen fast side å lære. Antall kort i testen regnes fra kontoplanen (2 × antall kontoer utenom disponering), ikke som et fast tall. Seedet stokking, kontoer fra alle klasser blandes.
- **Forklaringssetningen** bygges slik: når kontoens `okerPa` er typens vanlige side («4300 er en kostnad. Kostnader øker på debet.»); ellers er kontoen en motkonto og setningen er `merknad` fra kontoplanen pluss «Den øker på kredit.» Motkontoene i dag er 1580, 2080 og 2710; 2080 mangler merknad og får en («Negativ egenkapital: tap som ikke er dekket av annen egenkapital.»). En test sjekker at hver motkonto i kontoplanen har merknad, så en ny motkonto ikke får en gal setning.
- **Svar**: ← eller **D** for debet, → eller **K** for kredit, eller klikk på to store knapper i debet- og kredit-fargene fra `Theme.swift`.
- **Tid**: 60 sekunder. Klokka stopper i 1,5 sekunder etter et feil svar mens kortet viser forklaringssetningen.
- **Poeng**: riktig gir `10 × combo` (samme combo-regel som Lynrunden), pluss 5 i fartsbonus når svaret kom innen 1,5 sekunder. Feil: 0, combo nullstilles.
- **Ingen Leitner**: kontoer er ikke oppgaver. Resultatet er XP og rekord.
- **Slutt**: som Lynrunden.
- Fase 2-idé, ikke nå: kort fra posteringsoppgavenes fasit («Kjøp av varer på kreditt: 2400 Leverandørgjeld?»), som trener siden i en sammenheng.

## XP, nivåer og merker

- **XP-kilder** (konstanter i Kit, lette å justere):
  - Lynrunde og Debet/kredit: poeng ÷ 10.
  - Dagens oppgaver, «Øv» og Lynrunden: 10 × vanskelighet ved riktig på første forsøk, 3 ellers, bare for den første besvarelsen av oppgaven den dagen (samme regel som boksene). Legges på i `AppStore.record`.
  - **Første gang** `fremdrift.json` leses uten `game` (mitt valg): XP settes til `totalCorrect × 10 + (totalAttempts − totalCorrect) × 3`, så en bruker med historikk ikke starter som Lærling. Gjøres én gang i `AppStore.start`, med test.
- **Nivåer** (terskler i XP): Lærling 0, Regnskapsmedarbeider 500, Regnskapsfører 1 500, Seniorregnskapsfører 4 000, Partner 10 000. Huben viser tittel, XP og en linje til neste nivå.
- **Merker**: katalog i Kit med `id`, `navn`, `beskrivelse`, SF-symbol og regelen som deler det ut. Tildelt dato lagres per merke.

| id | Navn | Vilkår |
|---|---|---|
| `mva-mester` | Mva-mester | 20 mva-oppgaver riktig på rad, telt på tvers av dager og skjermer |
| `fristfri` | Fristfri | 10 frist-oppgaver riktig på første forsøk, samlet over tid (ikke på rad) |
| `null-differanse` | Null differanse | en sandkasse-case der saldobalansen stemmer med fasiten |
| `bank-avstemt` | Bank avstemt | en case ferdig avstemt mot banken (deles ut først når bankavstemmingen finnes) |
| `lynrask` | Lynrask | Lynrunde med minst 1 500 poeng |
| `reflekser` | Reflekser | 30 riktige i én runde Debet eller kredit |
| `sju-dager` | Sju dager | 7 dager på rad |
| `tretti-dager` | Tretti dager | 30 dager på rad |

- Merker deles ut ett sted: `Badges.award(progress:, event:)` tar en hendelse og returnerer nye merker. Hendelsene: `.puzzleAnswered(kind:, correctFirstTry:)`, `.roundFinished(game:, score:, correct:)`, `.caseMatched`, `.bankReconciled`, `.dayCompleted(streak:)`. Kalles fra `AppStore`. Nye merker vises på sluttskjermen eller som en rolig banner nederst i huben.
- **«På rad» (mitt valg)** telles over `AttemptResult`-ene som når `AppStore.record`: riktig på første forsøk øker telleren, alt annet nullstiller den. `PuzzleView` melder bare fra ved riktig svar eller fasit, så en oppgave man bommer på og forlater uten å rette teller ingen vei. Det er godt nok; `PuzzleView` endres ikke.

## Lagring

`LearnerProgress` får `game: GameProgress` med `xp: Int`, `badges: [String: DayKey]`, `bestScores: [String: Int]` (nøkkel `lynrunde`, `debet-kredit`), `counters: [String: Int]` (for «på rad»-merkene). Dekodes med `decodeIfPresent`, standard tom. Lagres i `fremdrift.json` som i dag.

## Kode som skal finnes

Kit:
- `Learning/GameProgress.swift`: modellen over.
- `Games/XP.swift`: kilder, nivåer, terskler.
- `Games/Badges.swift`: katalog og `award`.
- `Games/LightningRound.swift`: tilstandsmaskin. `start(pool:, tema:, progress:, seed:, duration:)`, `current`, `answer(_ attempt:) -> RoundEvent`, `tick(now:)`, `isOver`, `summary`. Klokka er et injisert `now: TimeInterval`.
- `Games/DebitCreditDrill.swift`: kortgenerator fra `ChartOfAccounts`, samme tilstandsmaskin-form.
- `Games/Combo.swift` om det er naturlig å dele combo-regelen.

App:
- `AppSection.game` («Spill», symbol `gamecontroller`).
- `UI/Game/GameHubView.swift`, `LightningRoundView.swift`, `DebitCreditView.swift`, `RoundSummaryView.swift`.
- `App/AppStore+Games.swift`: starter runder, kjører klokka (`Task` som kaller `tick` ti ganger i sekundet), sender svar til Kit, skriver XP og merker.
- `Screenshots.swift`: `game.png` kommer av seg selv via `AppSection.allCases`; legg til `spill-lynrunde.png` og `spill-debet-kredit.png` midt i en runde, og `spill-oppsummering.png`.

## Tester

- `LightningRoundTests`: seedet runde gir samme rekkefølge; lav boks først; poeng og combo etter en kjent rekke svar; klokka står stille under forklaring; runden slutter ved 90 s eller tomt utvalg; hvert svar gir riktig `AttemptResult`.
- `DebitCreditDrillTests`: 220 kort fra kontoplanen i repoet; svar og poeng; fartsbonus; forklaringssetningen for en kostnad og en gjeld.
- `XPTests`: nivå fra XP, XP fra en runde og fra en oppgave.
- `BadgesTests`: hvert merke deles ut én gang og på riktig hendelse; «på rad»-teller nullstilles ved feil.
- `ProgressStoreTests`: en `fremdrift.json` uten `game` leser inn med tom `GameProgress`.

## Dokumentasjon som oppdateres

- `CLAUDE.md`: tabellen over `Sources/RegnskapKit` (Games) og `Sources/Regnskapsskolen` (Spill).
- `docs/engineering-notes.md` hvis klokka eller tastaturet i SwiftUI koster tid.
- README/onboarding nevner Spill med én setning der appens skjermer listes.

## Overlatt til den som bygger

- Utseendet på kortene, animasjonene og sluttskjermen, innenfor `Theme.swift`.
- De nøyaktige tallene for poeng, XP og terskler. De står her som utgangspunkt og skal være konstanter på ett sted.
- Om huben viser de siste rundene som en liten liste.
- Tastatursnarveier for svaralternativene i Lynrunden (1–4 er naturlig).
