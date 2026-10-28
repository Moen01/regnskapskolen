# Paragrafjakten: Spill som et spill

Status: utkast til godkjenning. Skrevet 28.10.2026 etter Andreas' beskjed: «Spill-seksjonen må endres, oppgavene skal bevares, men dette må gjøres om til et spill. Målet er å lære regler og edge cases; kan det gjøres om til et Pokémon-lignende spill, MMO, PvE eller lignende.»

## Hvorfor

Dagens Spill-fane er to tidsrunder med poeng. Det er trening med klokke, ikke et spill: ingen verden, ingenting å samle, ingen motstander, ingen grunn til å komme tilbake annet enn rekorden. Andreas vil ha noe med framdrift, samling og kamp, der reglene og edge casene er det man lærer.

Forskningen peker i én retning: læringen må sitte i selve mekanikken (Habgood & Ainsworth, Zombie Division: barna lærte mer av versjonen der matten *var* angrepet, og spilte den frivillig sju ganger lenger). En quiz man må gjennom for å «få lov» til å angripe, virker ikke. Derfor er valget av paragraf selve angrepet i dette spillet.

Rammer fra researchen: Game Center (topplister, achievements, kamper mot andre) virker ikke i Developer ID-apper, og App Store-sandkassen ville stoppe `claude`-prosessen appen bruker. MMO krever server, kontoer og moderering: et eget produkt. v1 er derfor **PvE for én spiller**, bygget i SwiftUI (turbasert, ingenting beveger seg av seg selv). SpriteKit tas inn først den dagen et bevegelig kart er ønsket.

## Mål

1. **Verden**: tolv regioner, én per tema i `temaer.json`, i temaenes rekkefølge. En region låses opp når 60 % av skapningene i forrige region er fanget (boks ≥ 1). Første region er alltid åpen. (Mitt valg etter builder-sjekk: mestring i planleggerens forstand er boks ≥ 3, som tar uker per region; det er utviklingen som viser mestring, ikke låsen.)
2. **Møter**: i en region møter du oppgaver som skapninger. Riktig på første forsøk fanger skapningen (boks 1, «Klekket»), og den utvikler seg gjennom Leitner-boksene. Bommer du på en repetisjon, flykter den tilbake til det ville (boks 0, ute av samlingen). Samlingen *er* Leitner, tegnet som Pokédex.
3. **Trekk = paragrafer**: før du svarer, velger du hvilken regel du tar med. Treffer regelen oppgavens `lov`, er trekket «super effektivt» (dobbel XP og dobbel skade). Feil regel gir vanlig utbytte. Valget av regel er læringen.
4. **Kamp**: hver region har en helsemåler i kroner (kundens penger). Feil svar koster `vanskelighet × 500 kr`. Tom måler: «Kunden byttet regnskapsfører», økten er over, det du fanget beholdes. Riktig svar gjør skade på regionens gym-leder-måler.
5. **Gym-leder**: regionens vanskeligste edge case (høyeste `vanskelighet`, `edge-case`-tag). Den møter du når regionens måler er fylt. Fanger du den, får du regionens merke («Mva-merket»).
6. **Dungeon**: regionen «Reskontro og bank» har en dungeon: sandkasse-casen `bank-001`. Den er ryddet når `BankCheck.done` (merket «Bank avstemt» finnes alt).
7. **Samling**: alle oppgaver i spillet, fanget som kort med navn, type (tema), sjeldenhet (vanskelighet, edge case = «sjelden»), utviklingstrinn (boks) og paragrafene på baksiden; ufangede som silhuetter.
8. **Treningsplassene**: dagens Lynrunde og Debet eller kredit? beholdes som «Arena» og «Dojo» på kartet. XP, nivåer og merker beholdes.
9. **Ukens utfordring** (flerspiller uten server): ti oppgaver seedet av ukenummer, like for alle, med en delbar resultatkode («UKE 44 · 1 850 p · 9/10»). Sammenligning skjer utenfor appen.

## Ikke-mål

- MMO, kontoer, server, Game Center, ekte PvP.
- Sprite-grafikk og animert kart. v1 bruker kort, SF Symbols og temafarger.
- Lyd og konfetti (Andreas: lyd dempet).
- Nye oppgavetyper eller endringer i innholdskontrakten. Spillet er en fasade over `Innhold/`.
- Egen historie/tekstspor utover ett navn og én setning per region.

## Anti-mål

- Spillet som silo: alt som fanges og mistes går gjennom `Scheduler.record`, samme bokser som «I dag».
- Sukker på brokkoli: ingen mekanikk der svaret bare er en port til spillet. Regelvalget og svaret er handlingen.
- Gjetting lønner seg: feil svar koster HP og combo; feil regel gir ingen bonus; forklaringen vises alltid etter feil.
- Beskyttede titler, lyd, mørke mønstre (ingen daglige «tap» man må kjøpe seg ut av).

## Begrensninger

- All spillogikk i `RegnskapKit/Games/`, deterministisk med injisert klokke og seed, ingen `Date()` i Kit, ingen UI-import.
- `fremdrift.json` leses bakoverkompatibelt; nye felt i `GameProgress` er valgfrie.
- Norsk bokmål i alt brukeren leser; kode og commit-meldinger på engelsk.
- Ingen nye avhengigheter.
- Dagens oppgaveskjermer (`PostingView`, `QuizView`, `VATView` …) gjenbrukes inne i møtet; sjekken går gjennom `PuzzleSession`.

## Spillets deler

### Regioner

`Region` bygges fra `Topic` + utvalget (`store.pool`, så «vis utkast» styrer hva som finnes i spillet, som ellers i appen): `tema`, `navn`, `rekkefolge`, antall oppgaver, antall fanget (boks ≥ 1), mestring (`LearnerProgress.mastery`), `unlocked`, gym-leder, gym-merke fanget (`badges["gym-<tema>"]`). **Tomme regioner (mitt valg):** med utkast skjult har flere tidlige temaer null godkjente oppgaver i dag. En region uten oppgaver vises som «Under bygging», kan ikke besøkes, og teller som låst opp for kjeden, så den ikke sperrer neste region. `unlocked` = første region, eller forrige region *med oppgaver* har mestring ≥ 0,6, eller forrige region er tom. **Gym-leder:** edge case med høyest `vanskelighet`; finnes ingen edge case, oppgaven med høyest `vanskelighet`; likt → lavest id. En region med bare én oppgave har gym-lederen som eneste møte, og måleren er full fra start. Hver region har ett SF-symbol og én farge fra en tabell i Kit (tema → symbol/farge), og én setning («Her bor bilagene. Alt begynner med debet og kredit.»); tekstene står i Kit i en tabell, ikke i innholdet.

### Møte

`Encounter` lages fra en oppgave: `navn` = `tittel`, `type` = tema, `sjeldenhet` = vanskelighet 1–5, `sjelden` = `isEdgeCase`, `trinn` = boks: 0 = vill (ikke fanget, silhuett), 1 «Klekket», 2 «Ung», 3 «Voksen», 4 «Mester». «Egg» er bare øyeblikket når du fanger den. Møtet har to steg:

1. **Velg trekk**: trekk er par av (lov, paragraf), ikke hele kort, siden sju temaer har ett kort og et kort kan dekke flere lover. Valgene er alle par fra regionens regelkort, pluss to avledere (par fra andre regioners kort, seedet), høyst seks knapper, og alltid «Ingen regel». Et trekk treffer når paret står i oppgavens `lov`. Treff → «Super effektivt!» og multiplikator 2 på XP og skade. Har ingen av regionens par noe treff i oppgaven (15 av 120 oppgaver i dag), hoppes steget over med «Ingen kjent regel for denne»; ingen bonus mulig. En innholdstest krever at minst 75 % av de godkjente oppgavene kan treffes av et kort i sitt tema (i dag 87 %), så dekningen ikke faller.
2. **Svar**: oppgavens vanlige inndata og «Sjekk». Riktig på første sjekk = fanget (`Scheduler.record` med `correctFirstTry: true`). Feil = skapningen flykter, HP minus `vanskelighet × 500`, forklaringen vises, og oppgaven går til boks 0 (`correctFirstTry: false`); var den fanget fra før, er den nå ute av samlingen. Vis fasit er ikke tilgjengelig i møtet; skapningen kommer igjen.

Rekkefølgen på møtene i en region: forfalte repetisjoner først, så ville (lavest vanskelighet først, så lærer man seg opp), så resten; oppgaver som alt er besvart i dag sist (de gir verken boks eller XP, samme regel som ellers); seedet stokking innen hver gruppe. Gym-lederen holdes utenfor til måleren er full.

### Regionens måler og gym-leder

`RegionRun` er en økt i en region: `hp` starter på 10 000 kr hver økt, `skade` samlet (riktig svar: `vanskelighet × 100`, ×2 ved treff), `mål` = summen av `vanskelighet × 100` for regionens oppgaver utenom gym-lederen, delt på to. Skaden lagres per region i `GameProgress.regionDamage[tema]`, så en økt kan avbrytes og fortsettes. Når skaden når målet, står gym-lederen klar som neste møte. Fanges den: `badges["gym-<tema>"] = dag`, XP-bonus 200. Tom HP avslutter økten («Kunden byttet regnskapsfører»); det du fanget beholdes, men regionens skade faller med 25 % (mitt valg: ellers koster tapet ingenting). For en region med to oppgaver er målet nådd etter ett riktig svar; gym-lederen er innen rekkevidde i én økt overalt.

### Samling

Alle oppgaver i utvalget, gruppert per region. Fanget = boks ≥ 1 (`progress.puzzles[id]`). Kortet viser forside (symbol, navn, type, sjeldenhet, trinn) og bakside (oppgaveteksten kort, `lov` som `LawBadge`, forklaringens første avsnitt). Ufangede: silhuett med sjeldenhet, uten navn.

### Treningsplassene og utfordringen

Arena (Lynrunde) og Dojo (Debet eller kredit?) er to kort nederst på kartet, uendret oppførsel. Ukens utfordring: `WeeklyChallenge(pool:, week:)` velger ti oppgaver av typene quiz/mva/sak fra de **godkjente** oppgavene, sortert på id før seedet stokking (seed = ISO-år × 100 + ISO-uke), så alle med samme innholdsversjon får samme ti uansett «vis utkast». Kjøres som en Lynrunde uten klokke (ti svar) og gir en resultatkode `UKE <nr> · <poeng> p · <riktige>/10` med en knapp «Kopier». Én gang per uke per bruker, håndhevet lokalt i `GameProgress.weekly[<år-uke>]`.

### XP og merker

Fanget skapning: `XP.forPuzzle` som før (×2 ved treff). Gym-leder: +200. Dungeon: eksisterende merke. Nye merker i katalogen: «Første fangst», «Samler» (25 fanget), «Hele regionen» (alle i én region på boks ≥ 3), «Tolv merker» (alle gym-merker). Gym-merkene lagres som `gym-<tema>` i `badges` og vises på kartet, ikke i merkelisten.

## Gammel fremdrift

En bruker med `fremdrift.json` fra før har alt oppgaver i bokser: de vises som fanget med sitt trinn fra første start, og regioner kan være låst opp med en gang. Det er riktig: samlingen viser hva du kan. XP er alt seedet én gang (`fileHadGame`); ingenting telles dobbelt.

## Innhold som mangler

Med utkast skjult er «Kontoplanen» og «Resultat og balanse» tomme regioner og «Bilag» har én oppgave. Spillet tåler det (under bygging), men verdenen blir bedre når disse temaene får godkjente oppgaver. Det er en egen innholdsjobb (`/ny-oppgave`), ikke en del av denne planen.

## Skjermer

- **Kart** (erstatter dagens hub): nivåkortet øverst som nå; tolv regionkort i et rutenett, hver med symbol, navn, «7 av 12 fanget», mestringslinje, lås eller gym-merke; nederst Arena, Dojo, Ukens utfordring. Klikk på en åpen region → regionskjermen.
- **Region**: HP-måler (kroner) og skademåler mot gym-lederen, knappen «Neste møte», liste over regionens skapninger (små kort), «Tilbake til kartet». «Reskontro og bank» har «Gå inn i dungeon» som åpner Sandkasse med `bank-001`.
- **Møte**: skapningskortet, trekk-valg, oppgaven, «Sjekk»; etter svar: «Fanget!» med trinn, eller «Flyktet» med forklaring og HP-tap; «Neste».
- **Samling**: regionfaner, kortrutenett, klikk snur kortet.
- **Oppsummering** ved tom HP eller når du går ut: fanget, mistet, XP, nye merker.

## Overlatt til den som bygger

- Navnene på utviklingstrinnene og regionsetningene (tabell i Kit, lett å endre).
- Fargene per tema og hvilke SF-symboler.
- Animasjon ved fangst (rolig; ingen lyd).
- Om Samling er egen sidemeny-seksjon eller en knapp på kartet (anbefalt: knapp).
