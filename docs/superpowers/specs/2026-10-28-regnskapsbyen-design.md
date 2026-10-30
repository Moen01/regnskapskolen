# Debet & Kredit: Rubin-utgaven (Paragrafjakten fase 2, en by man går rundt i)

Status: utkast til godkjenning. Skrevet 28.10.2026 etter Andreas' beskjed: «kom med et spill som ligner på pokemon ruby, hvor du er en regnskapsfører som går rundt og jobber som regnskapsfører i en by. Bilag må bokføres, frister må huskes på osv, kunder fra forskjellige bransjer må forstås og deres behov når det kommer til regnskap.» Andre runde samme dag: Andreas' utkast («Debet & Kredit: Rubin-utgaven», byen Hovedbok, feil som kommer tilbake senere, 8 fagkontor, bokettersyn, MVP med to klienter) er flettet inn. Bygger på `2026-10-28-paragrafjakten-design.md` (spillogikken) og `2026-10-28-gameboy-design.md` (skallet, fase 1). Fase 1 sa: «Verdenskart man går rundt på er fase 2.» Dette er fase 2.

## Hvorfor

Paragrafjakten har kamp, samling og gym-ledere, men verdenen er en liste med tolv rader. Det man lærer, er enkeltregler. Det en regnskapsfører faktisk gjør, er noe annet: holde flere kunder i orden samtidig, i en kalender, der hver kunde har sin bransje og sine fallgruver, der fristene kommer uansett om bilagene er ført, og der en feil i mars blir funnet i juni. Pokémon Ruby har den strukturen: en by man går i, et lag man bygger, typer med styrker og svakheter, en PDA med kalender (PokéNav), og gym-ledere som stenger veien videre. Spillet bytter innholdet, ikke strukturen.

Læringsregelen fra Paragrafjakten gjelder fortsatt: faget *er* mekanikken. Å bokføre bilaget er angrepet; å vite hvilken mva-behandling et legekontor har, er typefordelen; å huske fristen er overlevelse; å finne og rette sin egen feil er sluttspillet.

## Spillet på én side

Du er ny regnskapsfører på et lite kontor i byen Hovedbok. Sjefen gir deg din første klient. Du går rundt i byen, besøker klientene i butikkene og kontorene deres, henter bilag fra papirhaugene, bokfører dem, og leverer mva-melding, a-melding og årsregnskap før fristen. Bokfører du feil, sier spillet ingenting med en gang: feilen dukker opp når måneden lukkes, eller i bokettersynet. Nye klienter vinner du med en prøvesak. Byen har åtte fagkontor (gyms); hvert gir et fagmerke, og to merker åpner neste bydel. Til slutt venter bokettersynet: fire kontrollører og en sensor.

| Pokémon Ruby | Debet & Kredit | Hvor læringen sitter |
|---|---|---|
| Laget (6 Pokémon) | Porteføljen (inntil 6 klienter) med tilfredshet som HP | Hver klient har sin bransje og sine behov |
| Typer (ild, vann …) | Bransjer (restaurant, lege, nettbutikk …) | Bransjen bestemmer hvilke regler som treffer |
| Ville Pokémon i høyt gress | Bilag i papirhauger hos klienten | Dagens oppgaver, valgt fra klientens bransje |
| Fange en Pokémon | Bokføre bilaget riktig | Kampen fra fase 1, uendret |
| Trenerkamper | Kundesaker med dialogvalg | `sak`- og `quiz`-oppgaver |
| 8 gyms og merker | 8 fagkontor og fagmerker | Temaets vanskeligste edge case |
| Elite Four + Champion | Bokettersynet: fire kontrollører + sensor | Dine egne urettede feil, pluss fem temaer |
| PokéNav | Fristnav | Kalender, portefølje, kart |
| TM/HM | Regelkort / fullmakter | Trekk = paragrafer; fullmakt åpner bydel |
| Pokédex | Samlingen (uendret) | Leitner-boksene |
| Pokémon Center | Kontoret: kaffe, hvile, lagre | Energi tilbake, dagen avsluttes |

## Mål

1. **En by man går i.** Et rutekart (tiles à 16 × 16 px) inne i Game Boy-rammen. Skjermen viser 10 × 9 ruter (160 × 144, samme skall som fase 1). Piltaster flytter regnskapsføreren én rute om gangen (4 bilder per steg, 0,25 s), med kollisjon mot vegger, vann og folk. Dører fører inn til et innendørskart. A snakker med den du står vendt mot eller leser et skilt. B går tilbake fra menyer. Enter på ingenting åpner hovedmenyen (FRISTNAV · PORTEFØLJE · SAMLING · BAG · LAGRE).
   **All tekst holder seg inne i boksen.** Hver tekst på skjermen (replikker, skilt, navn, Fristnav-rader, menyer) går gjennom `TextWrap.lines` med boksens antall tegn (36 i dialogboksen siden fase 2b, 18 før). Ord brytes aldri midt i, bortsett fra ord som er lengre enn en hel linje; de deles med bindestrek. Ingen tekst tegnes utenfor boksens kant, og ingen linje kuttes uten at hele teksten kan leses i dialogboksen. Tester i Kit dekker det (se Oppbygning).
1b. **Gå fra bygg til bygg og finn klientene.** Byen er full av bygg med skilt: restaurant, legekontor, nettbutikk, verksted, butikk, utleiegård. Inne i hvert bygg står eieren. A på eieren gir en samtale der eieren forteller om driften sin med egne ord («Vi har servering i salen og take-away i disken.»). Det er bransjens fallgruve, fortalt slik en klient ville sagt det. Etter samtalen ligger et **behovskort** for klienten i porteføljen: bransje, mva-status, ansatte, hvilke frister klienten får, og hvilke regelkort som gjelder. Å forstå klienten er første steg; prøvesaken (mål 8) er det andre. Noen bygg er låst (lys av, «Stengt for i dag») til bydelen er åpnet. Bygg uten klient (banken, kafeen, kontoret ditt) har andre ting: sandkasse-casene, kaffe, lagring.
2. **Hovedbok har fire bydeler med to fagkontor hver.** De 12 temaene i `temaer.json` fordeles på 8 fagkontor:
   | Bydel | Fagkontor | Temaer |
   |---|---|---|
   | Sentrum | Bilag | `grunnlag`, `kontoplan`, `bilag-bokforingsloven` |
   | Sentrum | MVA | `mva` |
   | Havna | Bank | `reskontro-bank` |
   | Havna | Periodisering | `periodisering`, `perioder-frister` |
   | Industriområdet | Lønn | `lonn` |
   | Industriområdet | Avskrivning | `avskrivning` |
   | Bryggen | Valuta og korrigering | `valuta-korrigeringer` |
   | Bryggen | Årsoppgjør | `arsoppgjor`, `resultat-balanse` |
   Begge fagmerkene i en bydel gir fullmakten til neste. Fordelingen ligger i kartfilene (se Oppbygning), ikke i kode. Utkastets «Bygg» og «Skatt» er byttet ut: det finnes ikke tema eller regelkort for dem (se mål 4).
3. **Klienter er laget.** En klient er en innholdsfil: navn, bransje, selskapsform, mva-status, om de har ansatte, termin (bare termintyper som finnes i `satser.json`), sted på kartet, og en liste med oppgave-id-er som hører til klienten. Inntil 6 klienter er aktive i porteføljen; resten ligger «i arkivet» på kontoret (som PC-boksen i Ruby). Hver klient har en **tilfredshetsmåler** (0–100), som er klientens HP. Den stiger når du leverer riktig og i tide, og faller når du glipper en frist eller når en feil blir funnet. Ved 0 sier klienten opp og går til arkivet («Kunden byttet regnskapsfører»). Ingenting slettes; du kan vinne klienten tilbake med en ny prøvesak.
4. **Bransjer er typer.** Bransjen avgjør hvilke oppgaver og regler som dukker opp hos klienten, og hvilke trekk som er «supereffektive». Første sett, og bare med regler som har regelkort i dag:
   | Bransje | Typisk fallgruve | Regelkort |
   |---|---|---|
   | Restaurant | servering 25 % mot take-away 15 % | `mva-satser` |
   | Lege / tannlege | helsetjenester er unntatt mva, derfor ikke fradrag for inngående mva | `mva-fritatt-unntatt` |
   | Nettbutikk | tjenester kjøpt fra utlandet, valuta | `mva-omvendt-avgiftsplikt`, `valuta-korrigeringer` |
   | Verksted / transport | driftsmidler, saldogrupper, personbil | `avskrivning-saldogrupper`, `mva-fradrag-begrensninger` |
   | Varehandel med ansatte | lønn, forskuddstrekk, AGA, feriepenger | `lonn-forskuddstrekk-aga`, `feriepenger` |
   | Eiendom | frivillig registrering, utleie | `mva-fritatt-unntatt` |
   En bransje er en liste med regelkort-id-er og temaer i `bransjer.json`. Ingen bransje får en regel uten regelkort (CLAUDE.md regel 2). To bransjer fra utkastet er tatt ut:
   - **Bygg med omvendt avgiftsplikt.** Den regelen finnes ikke i Norge for bygg; underentreprenøren fakturerer med mva som vanlig. Det er svensk regel («omvänd byggmoms»). Vårt kort dekker bare tjenester kjøpt fra utlandet (§ 3-30, § 11-3) og klimakvoter og gull (§ 11-1). En byggklient kan komme med andre fallgruver (prosjektperiodisering) når et regelkort finnes.
   - **Frisør med kontantsalg.** Kontantsalg og kassasystem har ikke regelkort i dag. Kommer når kortet er skrevet og kontrollert.
5. **Kalenderen går, fristene kommer.** Spillet har en egen dato (starter 1. januar i året fra `satser.json`). Én dag går etter 12 handlinger (en handling = et møte, et klientbesøk, en levering). Å sove på kontoret hopper til neste hendelse (den 1. i neste måned, tre dager før en frist, eller fristen), ellers til i morgen; uten det ville en termin vart over tusen handlinger. Fristene leses fra `satser.json`, aldri fra kode: mva-terminene, a-meldingen (den 5.), forskuddstrekket, arbeidsgiveravgiften, skattemeldingen (31. mai) og årsregnskapet (31. juli). Hver klient får de fristene som passer: ingen mva-frist for en klient som ikke er registrert, ingen a-melding uten ansatte. Fristnav viser de neste sju dagene som en liste (`10.04 MVA 1. TERMIN · KAFÉ LYSTHUSET`). Spilldatoen er en injisert verdi i Kit; ingen `Date()`.
6. **Papirhaugen.** Hver klient har en haug med bilag som må føres i perioden. Bilagene er de eksisterende `postering`-, `klassifiser`- og `finnfeil`-oppgavene som hører til klienten. Du henter haugen hos klienten (A på klienten: «Her er bilagene for mars.»), og fører dem som møter. Kampen er Paragrafjakten-kampen fra fase 1, uendret: trekk (paragraf), så svarpanelet.
7. **Feil kommer tilbake senere.** Dette er hovedidéen. I byen sier spillet ikke «feil» når du fører et bilag; det sier «Bilaget er bokført.» Et feilført bilag blir liggende i klientens bøker som en **åpen feil**. Den kommer tilbake på ett av tre steder:
   - **Når måneden lukkes** (du velger LUKK MÅNED for klienten på kontoret): hver åpen feil fra måneden dukker opp som et møte, «Avstemmingen går ikke opp: BILAGO 14.03». Du må finne feilen og føre et korrigeringsbilag (regelkort `valuta-korrigeringer`: rette feil uten å slette). Riktig korrigering: feilen er lukket, tilfredshet − 0. Feil igjen: tilfredshet − 10, og feilen blir stående.
   - **Når klienten oppdager den** (seedet sjanse, 1 av 4 per spilldag, bare for feil eldre enn sju dager): klienten ringer, tilfredshet − 15, og feilen må rettes som over.
   - **I bokettersynet** (mål 10): alle feil som fortsatt er åpne.
   Forklaringen vises alltid, når feilen kommer fram. Månedslukking er obligatorisk før levering, så ingen feil lever lenger enn én periode uten at du ser den.
   **Leitner er ærlig fra første svar.** `Scheduler.record` får `correctFirstTry: false` i det du svarer feil, som ellers i appen; samlingen og «I dag» vet det med en gang. Bare *byen* venter med å si det. Samlingen viser derfor ikke det feilførte bilaget før måneden er lukket (ellers røper den svaret).
8. **Kundesaker er trenerkamper.** Noen klienter står ute i byen og vil snakke: «Jeg kjøpte en bil til firmaet. Kan vi trekke fra mva?» Det er `sak`- og `quiz`-oppgaver med dialogvalg. Her er svaret synlig med en gang (en samtale er ikke et bilag). Riktig: tilfredshet + 5. Nye klienter vinnes med en **prøvesak**: tre møter på rad fra klientens bransje, uten pause, med klientens egen HP-måler (10 000 kr som i `RegionRun`). Vinner du, signerer klienten oppdragsavtalen og går inn i porteføljen.
9. **Fagkontorene er gyms.** Kampen er tre gym-ledere på rad (de vanskeligste edge casene i kontorets temaer, som i Paragrafjakten). Seier gir fagmerket. Kontoret åpnes når gym-målet er nådd for temaene (`Region.damageTarget` per tema, uendret regel).
10. **Bokettersynet er sluttspillet.** Etter åtte merker åpner Avgiftskontoret (oppdiktet etat). Først gås dine åpne feil gjennom, én og én. Så fire kontrollører og en sensor, ett tema hver (`arsoppgjor`, `mva`, `lonn`, `periodisering`, sensor: blandet). Én HP-måler gjennom alt, ingen hvile. Hver åpen feil du ikke retter, koster HP før kontrollørene i det hele tatt starter, så nøyaktighet gjennom året lønner seg. Tap: tilbake til kontoret, merkene beholdes. Seier: «Bokettersynet er avsluttet uten merknader», og spillet fortsetter med nytt regnskapsår (kalenderen ruller videre, klientene blir).
11. **Bagen.** Ting man finner eller får: *Kaffe* (fyller energi), *Regelkort* (som TM: legger et ekstra trekk i trekklisten for en kamp), *Fullmakt* (åpner bydel), *Oppdragsavtale* (kreves for å ta inn en ny klient; én ved oppstart og én per fagmerke). Ingen ting kan kjøpes, og ingen ting gir svaret.
12. **Energi er regnskapsførerens HP.** 100 energi. Hvert møte koster 5. Tom energi: du sovner på stedet og våkner på kontoret dagen etter (en dag går, frister kan glippe). Kaffe gir 30, å sove på kontoret fyller alt. Feil koster ikke ekstra energi (det ville røpet feilen, se mål 7).
13. **Lagre og fortsette.** Spillets tilstand (posisjon, dato, portefølje, tilfredshet, hauger, åpne feil, bag, merker) lagres i `fremdrift.json` som nye valgfrie felt under `GameProgress.town`. En gammel `fremdrift.json` uten `town` starter et nytt spill på kontoret med samlingen og merkene man har.

## Ikke-mål

- **Phaser, TypeScript, Vite eller Tiled.** Utkastet anbefalte en nettleserversjon. Appen er en macOS-app i Swift med et Game Boy-skall som alt er bygget (fase 1), og spillogikken ligger i `RegnskapKit`, der den alt testes med XCTest. Det er den samme idéen som utkastet ville ha (regnskapsreglene skilt fra spillmotoren), og vi har den alt. Et nytt språk og fire nye avhengigheter ville gitt to kodebaser for de samme reglene. Kartfilene er vår egen enkle JSON i stedet for Tiled.
- **Kontering som konto + mva-kode + periode i ett svar.** God idé, men svarpanelet for `postering` sjekker i dag konto, side og beløp. Mva-kode og periode per linje er en endring i innholdskontrakten og `PostingChecker`, og får en egen spec.
- Ekte pikselkunst for byen i første versjon. Tiles tegnes i kode (gulv, vegg, dør, vann, papirhaug, tak, skranke) i fire farger, som spritene i fase 1. PNG-tiles kan komme senere uten å endre kartfilene.
- Game Boy Advance-oppløsning (240 × 160) og farger per bydel. Vi beholder 160 × 144; fargene er per ting (Game Boy Color) siden fase 2b, se Beslutninger punkt 1.
- Lyd, musikk, flerspiller, server, mobil, nettleser.
- Nye oppgavetyper. Alt som spilles, er eksisterende oppgaver og sandkasse-caser.
- Ekte etater, banker, systemer eller personer i byen. Navnene er oppdiktet (Avgiftskontoret, Registerhuset, Hovedbok Sparebank). Bokettersyn er et begrep, ikke en figur fra Skatteetaten.
- Ekte gebyrer og tvangsmulkt. De står ikke i `satser.json`; spillets straff er tilfredshet.
- Hvitvasking og kundekontroll (oppdragsavtalen er bare en ting i bagen). Det finnes ikke regelkort for det.

## Anti-mål

- Gåing som fyll. Ingen rute på kartet er lenger enn 20 steg fra kontoret til en klient i samme bydel. Hurtigreise mellom bydeler fra Fristnav når bydelen er åpnet.
- Tall i kode. Satser og frister kommer fra `satser.json`; spillets egne tall (tilfredshet, energi, dager, sjansen for at klienten oppdager en feil) ligger i én `TownRules`-tabell i Kit.
- Frister man ikke kan se. Fristnav varsler tre dager før, og dialogboksen sier det når du går ut av kontoret.
- Tekst som stikker ut av boksen eller deler et ord der det ikke trengs.
- Feil som aldri blir forklart. Den utsatte feilen kommer alltid fram senest ved månedslukking, med forklaring.
- Straff som tvinger deg til å spille. Kalenderen står stille når appen er lukket.
- Logikk i views. Kart, kollisjon, kalender, frister, tilfredshet, hauger og åpne feil ligger i Kit og testes der.

## Oppbygning

**Innhold (nytt, validert av `ContentValidatorTests`):**
- `Innhold/by/bransjer.json`: `id`, `navn`, `temaer`, `regelkort` (id-er som finnes i `Innhold/regler/`), `setning`.
- `Innhold/by/klienter/*.json`: én klient per fil. `id`, `navn`, `bransje`, `selskapsform`, `mvaRegistrert`, `ansatte`, `mvaTermin` (en termintype fra `satser.json`), `sted` (`kart`, `x`, `y`), `oppgaver` (id-er), `provesak` (tre oppgave-id-er), `replikker` (hilsen, haug, glippet frist, oppdaget feil). `status` som oppgavene (`utkast`/`godkjent`).
- `Innhold/by/kart/*.json`: ett kart per bydel og per innendørsrom. `bredde`, `hoyde`, `ruter` (rader med tegn: `#` vegg, `.` gulv, `~` vann, `,` gress, `D` dør), `dorer` (til kart og rute), `folk` (klient-id, fagkontor med temaer, skilt med tekst), `fullmakt` (hvilket merke som kreves).
- Validatoren sjekker: hver dør peker på et kart og en gangbar rute; hver klient står på en gangbar rute; hver oppgave-id finnes; hver bransje har regelkort som finnes; alle kart kan nås fra kontoret (flood fill); hvert tema i `temaer.json` har nøyaktig ett fagkontor; mva-termin finnes i `satser.json`; hver replikk og hvert skilt brytes med `TextWrap.lines` til 18 tegn uten at noe ord deles (et ord over 18 tegn er en valideringsfeil i byens tekster, så forfatteren velger et kortere ord).
- `docs/innhold.md` får et avsnitt om `by/`.

**Kit (nytt, under `Games/Town/`, testet):**
- `TownMap`: rutenett, kollisjon, dører, `walkable(x, y)`, lastet fra kartfilene.
- `TownWalker`: posisjon, retning, `step(_ key: GameKey) -> WalkEvent` (`moved`, `blocked`, `door(to:)`, `talk(to:)`).
- `TownCalendar`: spilldato, `advance(actions:)`, `sleep()`. Injisert startdato.
- `DeadlinePlanner`: fra klient + `satser.json` til en sortert liste av `Deadline(dato, type, klient)`. Bruker samme fristregler som `frist`-oppgavene (ingen ny tolkning av satsene).
- `Ledger` / `OpenError`: bilag ført per klient og måned, åpne feil (oppgave-id, dato, klient), `closeMonth(client, month) -> [OpenError]`, `discover(on:seed:)`, `correct(_:)`.
- `Portfolio` / `ClientState`: tilfredshet, haug, levert per periode, aktiv eller arkiv. `deliver(client, on:)`, `miss(_:)`.
- `TownRules`: spillets egne tall.
- `TownState`: alt over samlet, `Codable`, lagret som `GameProgress.town` (valgfritt felt, bakoverkompatibelt).
- Gjenbruk uten endring: `BattleFlow`, `AnswerPanel`, `RegionRun` (prøvesak og fagkontor er `RegionRun` med et annet utvalg), `Scheduler.record`, `PixelSprite`. `BattleScript` får én ny replikk for bilag i byen («Bilaget er bokført.») i stedet for fanget/flyktet.

**App (nytt under `UI/Game/GameBoy/`):**
- `TownScreen`: tegner kartet med `Canvas` (nærmeste nabo), regnskapsføreren og folk, kamera som følger spilleren, dialog når du snakker.
- `TileSprite` i Kit (som `PixelSprite`): gulv, vegg, dør, vann, papirhaug, tak, skranke, skilt.
- `FristnavScreen`, `PortfolioScreen`, `BagScreen`: lister i fase 1-stil (`GBList`, `GBDialog`).
- `BattleScreen` gjenbrukes for bilag, kundesaker, korrigeringer, prøvesaker, fagkontor og bokettersyn.
- `MapScreen` (listen over regioner) blir værende som «Trening» fra hovedmenyen, så den raske veien til en region finnes fortsatt.
- `AppStore+Town`: kobler `TownState` til `AppStore` og lagring.

**Sandkassen:** banken i Havna er inngangen til `bank-001` (dungeon fra Paragrafjakten). Kaféen i Sentrum er inngangen til `kafe-001`. En ryddet sandkasse-case teller som lukket måned for klienten.

## Faser

1. **2a: MVP.** Sentrum med seks bygg man kan gå inn i: kontoret, banken, restaurant, legekontor, nettbutikk og verksted. Fire klienter i fire bransjer. Restauranten får du av sjefen ved start; de tre andre finner du ved å gå rundt, snakke med eieren (behovskortet) og vinne prøvesaken. Restauranten og legekontoret har full papirhaug (20 bilag til sammen); nettbutikken og verkstedet har prøvesak og noen få bilag. Én frist: mva-meldingen. Månedslukking og åpne feil. Ett fagkontor (MVA). Lagring. Ferdig når man kan spille én termin fra 1. januar til fristen 10. april, finne alle fire klientene og se en egen feil komme tilbake. Det er også testen på om det er gøy: blir det ikke det, stopper vi her.
2. **2b: Resten av fristene.** A-melding, forskuddstrekk, AGA, energi, sove, klienten som oppdager feil.
3. **2c: Bydeler og fagkontor.** De tre andre bydelene, alle åtte fagkontor, fullmakter, prøvesaker for nye klienter, arkivet.
4. **2d: Bokettersynet.** Avgiftskontoret, gjennomgang av åpne feil, de fem kampene, nytt regnskapsår.

Hver fase er en egen plan og en egen PR mot `staging`.

## Innhold som mangler

- Klientfilene finnes ikke. MVP trenger 2 klienter og 20 bilag; hele spillet minst 12 klienter med 6–10 oppgaver hver. Mange oppgaver kan deles mellom klienter i samme bransje. En `/ny-klient`-skill (som `/ny-oppgave`) er naturlig, men er ikke en del av denne spec-en.
- Legekontoret i MVP trenger nok `mva`-oppgaver om unntak og fradrag; antallet må telles før planen skrives.
- Tomme temaer (`kontoplan`, `resultat-balanse` med utkast skjult) gjør fagkontorene Bilag og Årsoppgjør tynne.
- Regelkort for kontantsalg/kassasystem og for bygg (prosjekt, periodisering) før frisør og byggfirma kan bli klienter.

## Beslutninger (Andreas, 28.10.2026)

1. **Oppløsning:** 160 × 144, Game Boy Color-farger per ting, dialog 36 × 6 (fra fase 2b, Task 11; erstatter DMG-grønt og 3 × 18 fra fase 1). Alle farger står i `GBTheme`. Krav: alle ord holder seg inne i boksen (mål 1). GBA-oppløsning kan bli en egen fase 3 sammen med ekte tiles.
2. **Kalenderens tempo:** 12 handlinger per dag.
3. **Navnet i appen:** Dojo-spillet beholder «Debet eller kredit?»; fanen heter «Rubin-utgaven», med «Debet & Kredit» som tittelskjerm.
4. **Utforsking:** man går fra bygg til bygg og finner klienter fra forskjellige bransjer (mål 1b). Er med alt i MVP.

Utkastets egne spørsmål er besvart av repoet: spillet er en del av Regnskapsskolen (offentlig repo, ingen Catacloud-kode), språket er norsk bokmål (CLAUDE.md), og plattformen er macOS.

## Overlatt til byggeren

- Nøyaktige kart, så lenge validatoren og anti-målet om 20 steg holder.
- Tile-mønstrene og spillerens gå-animasjon (to bilder per retning).
- Hvordan kameraet oppfører seg ved kartkanten (stopper, ikke svart kant).
- Klientenes replikker, så lenge de er på bokmål og ikke gir svaret.
