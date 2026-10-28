# Paragrafjakten på Game Boy: fase 1, kampskjermen

Status: utkast til godkjenning. Skrevet 28.10.2026 etter Andreas' beskjed: «now its all text and boring, how to make this more like a gameboy feeling game?» og «do this then» til forslaget under. Mockup: https://claude.ai/artifact/CbcsxZ5Ad3Y36uMxtihTYy (tre øyeblikk: møtet, regelmenyen, bilaget som angrep).

## Hvorfor

Spill-fanen har riktig spillogikk (regioner, møter, trekk = paragraf, HP i kroner, gym-ledere, Leitner som samling), men alt tegnes med vanlige macOS-kontroller: hvit flate, systemfont, grå chips, et skjema. Det ser ut som Innstillinger. Følelsen av et håndholdt spill kommer fra fire ting: én liten mørk skjerm med fire farger, pikselfont med tekst som skrives bokstav for bokstav, skapninger som beveger seg (dukker opp, rister, forsvinner), og D-pad/A/B i stedet for museklikk på knapper. Fase 1 gir Paragrafjakten alle fire. Logikken i `RegnskapKit` røres ikke; dette er et nytt skall.

## Mål

1. **Én skjerm.** Hele Paragrafjakten (kart, region, møte, resultat, oppsummering, samling) tegnes inne i en Game Boy-ramme: en logisk skjerm på 160 × 144 piksler, skalert med et heltall (3–5, det største som får plass i vinduet; under 3 vises en beskjed om å gjøre vinduet større) og midtstilt i en mørk ramme. Fire farger (DMG-grønn: `#0f380f`, `#306230`, `#8bac0f`, `#9bbc0f`). Pikselfonten «Press Start 2P» (8 × 8 px per tegn, 18 tegn per linje i dialogboksen). Ingenting hvitt, ingen systemkontroller inne i rammen.
2. **Møtet er en kampskjerm.** Oppe til høyre: skapningen på en plattform, med navneboks (artsnavn, nivå = vanskelighet, trinn = Leitner-boks som fire ruter). *Artsnavnet* er et oppdiktet ord på 5–9 bokstaver generert fra oppgavens `id` (stavelser som passer norsk: «MOVAKS», «BILAGO»), alltid det samme for samme id og uten kollisjoner i oppgavesettet (test). Oppgavens tittel er for lang til en navneboks (alle 120 er over 11 tegn), så den står i dialogboksen i stedet: «En vill MOVAKS dukket opp!» og på neste side tittelen. Det endrer ikke innholdskontrakten; et valgfritt `kortnavn` i oppgavene kan komme senere. Nede til venstre: regnskapsføreren sett bakfra, med boks «KUNDEN», HP-stolpe og `10000/10000`. Nederst: dialogboksen (tre linjer à 18 tegn, skrivemaskin-tekst 30 tegn/s, blinkende ▼ når det er mer; Enter, mellomrom eller klikk viser hele siden med en gang, neste trykk blar).
3. **Rekkefølgen i et møte.** Blink på skjermen, skapningen glir inn fra høyre, «En vill MOVAKS dukket opp!», så tittelen. Så menyen i dialogboksen, 2 × 2: **KJEMP · LES · REGLER · FLYKT**. KJEMP åpner trekklisten over feltet (inntil seks rader: regionens paragrafer, to fremmede, «Ingen regel»; samme `Moves.options` som i dag). Et valg gir «Du brukte bfl. § 4!» og så svarpanelet. LES viser oppgaveteksten side for side. REGLER viser regionens regelkort (titler som liste; et valg blar kortets tekst i dialogboksen). FLYKT avslutter økten (dagens «Avbryt»). Esc (B) fra svarpanelet går tilbake til menyen; trekket beholdes, og KJEMP lar deg velge på nytt (`RegionRun.choose` tillater det). Svaret som er skrevet inn, beholdes også.
   **Tre taster, én regel.** Enter (A) velger og angriper. Esc (B) går tilbake. **Tab** blar dialogboksen (på skjermen står `TAB▼` nederst til høyre når det er flere sider; klikk i boksen gjør det samme). Mens et svarpanel er åpent, viser dialogboksen først den markerte radens fulle tekst når raden er avkortet, deretter oppgaveteksten side for side; flytter markøren seg, starter boksen på nytt. Slik kan bilaget leses mens linjene føres, og et langt quiz-alternativ (opptil 128 tegn finnes) leses uten at Enter noen gang blar.
4. **Svaret er angrepet.** Svarpanelet ligger over feltet (152 × 90 px, tittel + seks rader à 12 px, ruller når det er flere). Hver oppgavetype har sitt panel, bygget av to pikselkontroller: en liste med markør og et skrivefelt.
   - *quiz* og *sak*: alternativene som rader (avkortet til 17 tegn); den markerte radens fulle tekst står i dialogboksen. Enter på en rad er angrepet. For *sak* vises meldingen først, side for side.
   - *mva*: listen over behandlinger fra `satser.json`; spør oppgaven om fradrag, kommer en liste til (Ja / Nei) før angrepet.
   - *regnut* og *frist*: ett skrivefelt (`SVAR: 2 500_`, `DATO: 10.06.2026_`); tastaturet skriver, Enter angriper. Tolkes med `NorwegianFormat.parseAmount` og `parseDay` som i dag.
   - *postering*: én rad per linje: `1920 Bank  D 2500`. Enter på en rad går gjennom konto (liste), side (D/K med venstre/høyre) og beløp (skrivefelt). Radene «+ linje» og «SLÅ». Debet- og kreditsum øverst i panelet. SLÅ er angrepet. Er bilaget riktig, spilles ett treff per linje etter hverandre (bare animasjon, 0,15 s per linje); er det feil, bommer hele bilaget. `PostingChecker` og dommen endres ikke, og treffene påvirker verken HP, skade eller XP.
   - *klassifiser*: en rad per element, Enter åpner kategorilisten; «SLÅ» når alle er satt. *finnfeil*: rader med `[x]`/`[ ]`, mellomrom eller Enter veksler, «SLÅ».
   - Alt kan også klikkes med musen: rader er knapper, panelet har samme oppførsel med klikk som med Enter.
5. **Resultatet.** Riktig: skapningen krymper bort (0,4 s), «Det er supereffektivt!» når regelen traff, så «KONTANTSALG ble fanget! Trinn: KLEKKET». Feil: HP-stolpen tømmes tilsvarende over 0,6 s, skjermen rister (± 4 px, 0,3 s), «KONTANTSALG flyktet! Kunden mistet 1 000 kr». Deretter forklaringen side for side (markdown gjort om til ren tekst) og paragrafene som egne linjer (`bfl. § 4`). ▼ til slutt går til neste møte; tom HP går til oppsummeringen. Utfallene og XP er som i dag (`RegionRun.answer`).
6. **Kartet, regionen, oppsummeringen, samlingen** er lister i samme stil. Kart: «PARAGRAFJAKTEN», nivå og XP, regionene som rader (`Grunnlag      3/12`, låst region med `LÅST`, gym-merke med `*`), nederst radene «TRENING» og «SAMLING»; dialogboksen viser den markerte regionens setning. Region: navn, `KUNDEN 10000`, `GYM 0/50`, radene «NESTE MØTE», «DUNGEON» (bare reskontro-bank), «TILBAKE». Oppsummering: tallene som rader, «TILBAKE» og «KARTET». Samling: skapningene som rader per region (ufangede som `???`), dialogboksen viser tittel, trinn og paragrafer.
7. **Skapninger uten tegner.** En skapning er en 14 × 12-sprite generert fra oppgavens `id`: venstre halvdel trekkes med et seedet tilfeldig mønster, speiles, får omriss og to øyne. Gym-lederen er 18 × 14. Spilleren er én fast 16 × 16-sprite tegnet i kode. Samme id gir alltid samme skapning. Ekte pikselkunst kan senere legges inn som PNG per oppgave uten å endre resten.
8. **Korte lovnavn.** Trekklisten bruker forkortelsene regnskapsførere skriver (`bfl.`, `mval.`, `rskl.`, `sktfvl.`). De ligger i den nye innholdsfilen `Innhold/lover.json` (`navn`, `kort`, `tittel`), én oppføring per lov som finnes i oppgavene eller regelkortene. Kravet om at hver lov i innholdet har en oppføring er en **test** (`ContentValidatorTests`, som validerer repoet), ikke en regel i `ContentValidator.validate`: oppgaver Claude lager («Vanskeligere oppgave») og eldre innholdsmapper uten `lover.json` skal fortsatt virke. Mangler fila eller oppføringen, vises fullt navn, avkortet i listen, fullt i dialogboksen. Forfatter-prompten endres ikke. Første versjon av filen er mitt beste forslag og er merket for kontroll mot Lovdata (feltet `merknad`); det er innhold, ikke kode, så et menneske retter den.
9. **Tastatur.** Piltaster = D-pad, Enter = A, Esc = B (tilbake/avbryt). Skjermen tar fokus når den vises. Mus virker alltid.
10. **Fonten følger med appen.** `Resources/Fonts/PressStart2P-Regular.ttf` med `OFL.txt` (SIL Open Font License; fonten har Æ Ø Å og §). `Info.plist` får `ATSApplicationFontsPath = Fonts`, og `bundle.sh` kopierer mappen inn i appen. Et `swift run`-bygg uten bundle registrerer fonten fra repoet; mangler fila, brukes systemets monospace i fet, og skjermen virker likevel.
11. **Skjermbildemodus** (`REGNSKAP_SCREENSHOTS`) tar de samme spill-bildene som i dag, nå av Game Boy-skjermen, uten skrivemaskin-forsinkelse.

## Ikke-mål

- Verdenskart man går rundt på (SpriteKit, høyt gress). Det er fase 2.
- Håndtegnede sprites per oppgave. Fase 3.
- Lyd (Andreas: dempet).
- Arena, Dojo og Ukens utfordring inne i rammen. De åpnes fra «TRENING» på kartet og vises som i dag, utenfor rammen, til en senere fase.
- Game Boy Color-paletter per region. Én palett i fase 1.
- Endringer i Leitner, XP, HP-regler, trekk, regioner eller innholdskontrakten for oppgaver.

## Anti-mål

- Tekst som ikke kan leses. Minste skala er 3 (24 pt per tegn); avkortet tekst i en liste skal alltid finnes i full lengde i dialogboksen.
- Logikk i views. Tekstbryting, sider, sprite-generering og kampreplikkene ligger i Kit og testes der.
- En app som bare virker med tastatur, eller bare med mus.
- Et skall som er penere enn det er nyttig: læreren skal fortsatt kunne føre et bilag med fire linjer på under et minutt.

## Oppbygning

**Kit (nytt, testet):**
- `Games/Adventure/PixelSprite.swift`: `PixelSprite` (bredde, høyde, `[[UInt8]]` med 0 = gjennomsiktig, 1 = omriss, 2 = kropp, 3 = øye), `PixelSprite.creature(seed: String, large: Bool)`, `PixelSprite.player`. Deterministisk, speilsymmetrisk, aldri tom.
- `Games/Adventure/BattleScript.swift`: replikkene som rene strenger: `intro(encounter)`, `moveUsed(move, laws)`, `result(outcome, encounter, laws)`, `explanation(encounter, laws)`. Bokmål, uten markdown. Minus skrives med ASCII `-` (fonten mangler U+2212, som `NorwegianFormat.kroner` bruker).
- `Games/Adventure/SpeciesName.swift`: `SpeciesName.name(for id: String) -> String`, 5–9 store bokstaver fra en stavelsestabell, deterministisk; test: ingen to oppgaver i repoet får samme navn.
- `Util/TextWrap.swift`: `TextWrap.lines(_ text: String, columns: Int) -> [String]` (bryter på ord, deler ord lengre enn linjen med bindestrek) og `TextWrap.pages(_ lines: [String], rows: Int) -> [[String]]`; `TextWrap.plain(markdown:)` fjerner `**`, `_`, `#`, lister og lenker.
- `Content/LawNames.swift` + `Innhold/lover.json`: `LawName` (`navn`, `kort`, `tittel`), lastet i `ContentLibrary.laws`; `Move.shortLabel(laws:)`. `ContentValidator`: hver `lov` i oppgaver og regelkort finnes i `lover.json`; `kort` er unik når den finnes.
- `Checking/PostingChecker`: ingen endring. Panelet trenger bare utfallet fra `RegionRun.answer`.

**App (nytt under `UI/Game/GameBoy/`):**
- `GBScreen` (ramme, skalering, palett, fokus og tastatur som `GBKey`-hendelser til skjermen som vises), `GBPalette`/`GBFont` (fonten, fallback), `GBBox`, `GBBar`, `GBList` (rader, markør, rullevindu, klikk), `GBEntry` (skrivefelt med markør), `GBDialog` (sider, skrivemaskin, ▼), `GBSprite` (Canvas, nærmeste nabo), `GBTransition` (blink, risting, inn fra høyre, krymp).
- Skjermer: `MapScreen`, `RegionScreen`, `BattleScreen` (fasene intro → meny → trekk → svar → resultat → forklaring som `@State`, nullstilt per møte), `AnswerPanels` (ett panel per oppgavetype), `SummaryScreen`, `CollectionScreen`.
- `GameHubView` ruter til `GBScreen` for Paragrafjakten og til dagens views for Lynrunde, Debet/kredit og rundeoppsummering. `MapView`, `RegionView`, `EncounterView`, `RunSummaryView`, `CollectionView` slettes (ingen død kode).
- `AppStore+Adventure` er uendret; panelene binder til `encounterSession.attempt` som i dag.

**Ressurser:** `Resources/Fonts/` (ny, med lisens), `Resources/Info.plist` (`ATSApplicationFontsPath`), `scripts/bundle.sh` (kopierer Fonts). Ny eiendel flagget: fonten er den eneste nye filen utenfra; ingen pakkeavhengighet.

**Docs:** `README.md` (Spill-avsnittet), `docs/innhold.md` (`lover.json`), `docs/engineering-notes.md` (Game Boy-skallet: skala, font, tastatur).

## Overlatt til byggeren

- Nøyaktig plassering innenfor 160 × 144 utover mockupen; rullevinduets størrelse per panel.
- Hvordan `onKeyPress` og `@FocusState` kobles så fokus ikke stjeles av skjulte tekstfelt.
- Sprite-algoritmens tetthet og øyeplassering, så lenge testene (deterministisk, symmetrisk, ikke tom, omriss rundt kropp) holder.
- Rekkefølgen tastatur/mus i panelene håndteres på.
