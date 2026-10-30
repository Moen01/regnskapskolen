# Innholdsformatet

Alt innhold ligger under `Innhold/`. Oppgaver er JSON, én fil per oppgave, i `Innhold/oppgaver/<tema>/`. Regelkort er Markdown i `Innhold/regler/`. Appen og testene leser det samme; `swift test --filter ContentValidatorTests` validerer hver fil i repoet.

## Felles felt

| Felt | Type | Krav |
|---|---|---|
| `id` | string | Unik. Mønster `<tema>-<type>-<nr>`, f.eks. `mva-quiz-004`. Claude-genererte: `<tema>-gen-<tidsstempel>`. |
| `type` | string | `postering`, `klassifiser`, `finnfeil`, `regnut`, `quiz`, `sak`, `mva` eller `frist`. |
| `tema` | string | En `id` fra `Innhold/temaer.json`. |
| `vanskelighet` | 1–5 | Se skalaen under. |
| `tags` | [string] | Valgfritt. `edge-case` markerer feller; brukes av planleggeren. |
| `tittel` | string | Kort. |
| `oppgave` | string | Hendelsen. Enkel Markdown (fet, kursiv, kode). |
| `lov` | [{lov, paragraf, tekst}] | Minst én. `paragraf` har formen `§ 3-1` eller `§ 8-3-10`; «første ledd» o.l. går i `tekst`. |
| `forklaring` | string | Vises ved riktig svar og etter *Vis fasit*. 60–150 ord. Markdown. |
| `status` | string | `godkjent` eller `utkast`. Mangler feltet, er oppgaven et utkast. |

Appen viser utkast bare når *Vis utkast* er på. Alt Claude skriver, er utkast. Filer i en mappe som heter `generert` regnes som generert og får merkelappen «utkast» uansett.

## Vanskelighetsskalaen

| Nivå | Betyr |
|---|---|
| 1 | Kjenner begrepet. Ett faktum, ingen felle. |
| 2 | Kan bruke regelen på et vanlig tilfelle. |
| 3 | Må kombinere to regler, eller regne i flere steg. |
| 4 | Et unntak eller en felle. Tagg `edge-case`. |
| 5 | Et grensetilfelle en erfaren regnskapsfører kan ta feil av. Tagg `edge-case`. |

Planleggeren velger ukjente oppgaver nær brukerens nivå (1 + antall temaer over 60 % mestring, maks 5) og sørger for minst én `edge-case` i dagens sett.

## Typene

### `postering`: før bilaget

`kontoer` er velgeren brukeren får (6–8 kontoer, 2–3 av dem skal ikke brukes). `fasit` er linjene; summen av debet må være lik summen av kredit. `alt` på en linje er kontoer som godtas i stedet.

```json
{
  "id": "grunnlag-001", "type": "postering", "tema": "grunnlag", "vanskelighet": 1, "status": "godkjent",
  "tittel": "Kontantsalg av en tjeneste",
  "oppgave": "Du selger en tjeneste for 2 000 kr + 25 % mva. Kunden betaler hele beløpet til bankkontoen med en gang. Før bilaget.",
  "kontoer": [{ "nr": "1920", "navn": "Bankinnskudd" }, { "nr": "2700", "navn": "Utgående merverdiavgift" }, { "nr": "3000", "navn": "Salgsinntekt, avgiftspliktig, høy sats" }, { "nr": "1500", "navn": "Kundefordringer" }],
  "fasit": [{ "konto": "1920", "side": "D", "belop": 2500 }, { "konto": "3000", "side": "K", "belop": 2000 }, { "konto": "2700", "side": "K", "belop": 500 }],
  "lov": [{ "lov": "merverdiavgiftsloven", "paragraf": "§ 3-1", "tekst": "Det skal beregnes merverdiavgift ved omsetning av varer og tjenester." }],
  "forklaring": "Kunden betaler 2 500 kr, så banken øker med 2 500 på debet. Inntekten er 2 000 kr uten mva på kredit 3000. Mvaen på 500 kr skal til staten: kredit 2700."
}
```

Sjekkeren gir tilbakemelding i denne rekkefølgen: en linje med både debet og kredit → balanserer ikke (differanse) → riktig konto, feil side → riktig side, feil beløp → en konto som ikke skal være med → en linje mangler på debet/kredit (kontoen nevnes ikke) → riktig. Beløp godtas som `1 250`, `1250`, `1250,00` og `1.250,00`.

### `klassifiser`: sorter

```json
{
  "id": "kontoplan-klassifiser-001", "type": "klassifiser", "tema": "kontoplan", "vanskelighet": 1, "status": "godkjent",
  "tittel": "Kontotyper", "oppgave": "Velg kontotypen.",
  "kategorier": ["Eiendel", "Gjeld", "Egenkapital", "Inntekt", "Kostnad"],
  "elementer": [
    { "tekst": "1920 Bankinnskudd", "svar": "Eiendel", "hvorfor": "Pengene eies av bedriften." },
    { "tekst": "2400 Leverandørgjeld", "svar": "Gjeld", "hvorfor": "Bedriften skylder leverandørene." }
  ],
  "lov": [{ "lov": "regnskapsloven", "paragraf": "§ 6-2", "tekst": "Balansens oppstilling: eiendeler, egenkapital og gjeld." }],
  "forklaring": "Klasse 1 er eiendeler, klasse 2 er egenkapital og gjeld."
}
```

Hvert `svar` må være en av `kategorier`. `hvorfor` vises på feil svar.

### `finnfeil`: finn feilene

```json
{
  "id": "bilag-finnfeil-001", "type": "finnfeil", "tema": "bilag-bokforingsloven", "vanskelighet": 2, "status": "godkjent",
  "tittel": "Faktura 1043", "oppgave": "Marker radene som bryter med bff § 5-1-1.", "overskrift": "Faktura 1043",
  "elementer": [
    { "tekst": "**Selger:** Eksempelfirma AS, Org.nr. 123 456 789", "feil": true, "hvorfor": "Et AS i Merverdiavgiftsregisteret skal ha «MVA» etter organisasjonsnummeret." },
    { "tekst": "**Beskrivelse:** Montering av hyller, 6 timer", "feil": false }
  ],
  "lov": [{ "lov": "bokføringsforskriften", "paragraf": "§ 5-1-1", "tekst": "Hva et salgsdokument minst skal inneholde." }],
  "forklaring": "…"
}
```

Minst ett element må ha `feil: true`. Ingen kryss er et gyldig svar («alt er riktig»). Tilbakemeldingen er «Du fant X av Y»; treff er grønne, feilmarkeringer røde, oversette gule.

### `regnut`: regn ut

```json
{
  "id": "mva-regnut-001", "type": "regnut", "tema": "mva", "vanskelighet": 1, "status": "godkjent",
  "tittel": "Mva av brutto", "oppgave": "En kvittering lyder på 1 250 kr inkl. 25 % mva. Hvor mye er mva?",
  "svar": 250, "toleranse": 0, "enhet": "kr", "hint": "Del på 1,25 for å finne nettobeløpet.",
  "lov": [{ "lov": "merverdiavgiftsloven", "paragraf": "§ 5-1", "tekst": "Alminnelig sats er 25 %." }],
  "forklaring": "1 250 / 1,25 = 1 000 netto. Mva = 250."
}
```

`hint` vises etter første feil. *Vis fasit* låses opp etter to feil. `toleranse` er absolutt (kroner), ikke negativ.

### `quiz`

```json
{
  "id": "mva-quiz-001", "type": "quiz", "tema": "mva", "vanskelighet": 2, "tags": ["fritatt"], "status": "godkjent",
  "tittel": "Mva på bøker", "oppgave": "En bokhandel selger en roman til en privatkunde. Hvilken mva-behandling er riktig?",
  "alternativer": ["25 %, alminnelig sats", "15 %, redusert sats", "0 %, fritatt med fradragsrett", "Unntatt fra merverdiavgiftsloven"],
  "svar": 2,
  "lov": [{ "lov": "merverdiavgiftsloven", "paragraf": "§ 6-4", "tekst": "Omsetning av bøker er fritatt i siste omsetningsledd." }],
  "forklaring": "Bøker er **fritatt** (nullsats) i siste ledd. Fritatt er ikke unntatt: full fradragsrett beholdes."
}
```

Ett spørsmål per fil, så repetisjonen blir atomisk. `svar` er 0-basert. Fire alternativer, fristende distraktorer.

### `sak`: en melding å behandle

```json
{
  "id": "grunnlag-sak-001", "type": "sak", "tema": "grunnlag", "vanskelighet": 2, "status": "godkjent",
  "tittel": "Bilaget balanserer ikke per dato", "oppgave": "Hva er riktig behandling?",
  "fra": "Kollega", "melding": "Systemet sier bilaget ikke balanserer på 22.09, men summene er like.",
  "valg": [{ "nokkel": "A", "tekst": "Sjekk datoene på linjene" }, { "nokkel": "B", "tekst": "Slett bilaget" }],
  "svar": "A", "sporsmal": ["Har alle linjene samme dato?"], "forslag": "Hver dato må gå i null for seg.",
  "lov": [{ "lov": "bokføringsloven", "paragraf": "§ 7", "tekst": "Bokføringen skal være à jour per periode." }],
  "forklaring": "Hver dato hører til en periode og må balansere for seg."
}
```

`sporsmal` (oppklarende spørsmål) og `forslag` (svarutkast) vises når oppgaven er ferdig.

### `mva`: behandling og fradrag

```json
{
  "id": "mva-mva-003", "type": "mva", "tema": "mva", "vanskelighet": 3, "status": "godkjent",
  "tittel": "Konsulent fra Sverige", "oppgave": "Velg behandling og om det er fradragsrett.",
  "transaksjon": "Et norsk AS kjøper rådgivning fra et svensk firma for 10 000 kr. Tjenesten leveres over e-post.",
  "fasit": { "behandling": "omvendt", "fradrag": true },
  "lov": [{ "lov": "merverdiavgiftsloven", "paragraf": "§ 3-30", "tekst": "Fjernleverbare tjenester kjøpt fra utlandet: mottakeren beregner mva." }],
  "forklaring": "Omvendt avgiftsplikt: 2 500 kr utgående og 2 500 kr inngående, netto null for en avgiftspliktig kjøper."
}
```

`behandling` må være en `kode` i `satser.json` (`25`, `15`, `12`, `0`, `unntatt`, `omvendt`). `fradrag: null` betyr at fradragsretten ikke spørres om.

### `frist`: velg datoen

```json
{
  "id": "frist-mva-003-2026", "type": "frist", "tema": "perioder-frister", "vanskelighet": 2, "tags": ["mva", "edge-case"], "status": "godkjent",
  "tittel": "Fristen for 3. mva-termin",
  "hendelse": "Bedriften leverer mva-melding annenhver måned. Når er fristen for 3. termin 2026 (mai og juni)?",
  "oppgave": "Velg datoen.",
  "fasit": "2026-08-31",
  "fasitRegel": { "type": "mva", "termin": 3, "aar": 2026 },
  "hint": "Hovedregelen er 1 måned og 10 dager etter terminens slutt, men én termin har en egen sommerfrist.",
  "lov": [{ "lov": "skatteforvaltningsforskriften", "paragraf": "§ 8-3-10", "tekst": "Mva-meldingen leveres innen én måned og ti dager etter utløpet av terminen. 3. termin: 31. august." }],
  "forklaring": "Hovedregelen ville gitt 10. august. For 3. termin er fristen **31. august**."
}
```

`fasit` må være lik datoen `fasitRegel` gir fra `satser.json`; validatoren regner den ut, så filen kan ikke drifte fra reglene. Helg og helligdag skyves til første virkedag.

| `fasitRegel.type` | Felt | Gir |
|---|---|---|
| `mva` | `termin` 1–6, `aar` | Fristen for terminen (3. termin: 31. august) |
| `mva-aarlig` | `aar` | Årlig mva-melding |
| `amelding` | `maaned`, `aar` | A-melding: den 5. i måneden etter |
| `aga` | `termin` 1–6, `aar` | Arbeidsgiveravgift, den 15. annenhver måned |
| `forskuddstrekk` | `utbetalt` (YYYY-MM-DD) | Første virkedag etter utbetaling (fra 1.1.2026) |
| `aarsregnskap` | `aar` | Innsending til Regnskapsregisteret, 31. juli året etter |
| `aarsregnskap-fastsettes` | `aar` | Generalforsamlingens frist, 30. juni året etter |
| `skattemelding` | `aar` | 31. mai året etter |

## Hva validatoren sjekker

- `id` er unik på tvers av alle filer; `type` er kjent; `tema` finnes i `temaer.json`; `vanskelighet` er 1–5.
- `oppgave` og `forklaring` er ikke tomme; minst én `lov` med `lov`, `paragraf` (riktig form) og `tekst`.
- `postering`: minst to linjer, balanserer, beløp > 0, alle kontoer (fasit, `alt` og velgeren) finnes i `kontoplan.json`, fasit-kontoer finnes i velgeren.
- `klassifiser`: minst to kategorier, elementer finnes, hvert svar er en kategori.
- `finnfeil`: minst ett element med `feil: true`.
- `regnut`: `toleranse` ≥ 0.
- `quiz`: minst to alternativer, `svar` innenfor.
- `sak`: minst to valg, `svar` er en nøkkel.
- `mva`: `behandling` finnes i `satser.json`.
- `frist`: `fasit` er lik datoen fra `fasitRegel`.

Kjør `swift test --filter ContentValidatorTests`. Testen `ContentCoverageTests` sier fra hvis et tema har for få oppgaver.

## Regelkort

`Innhold/regler/<navn>.md` med front matter:

```markdown
---
tittel: Omvendt avgiftsplikt: når kjøperen beregner mva
lov: merverdiavgiftsloven
paragrafer: § 3-30, § 11-1, § 11-3
tema: mva
kilde: https://lovdata.no/lov/2009-06-19-58/%C2%A73-30
---
Brødtekst i Markdown: avsnitt, punktlister og tabeller.
```

Kortene vises under *Regler* og legges ved systemprompten når Claude forklarer eller skriver oppgaver i temaet. Bruk bare paragrafer du har sjekket på Lovdata.

## Lover

`Innhold/lover.json` har én oppføring per lov eller forskrift som oppgavene og regelkortene viser til: `navn` (slik det står i `lov`-feltene), `kort` (forkortelsen regnskapsførere skriver, `bfl.`, `mval.`, `rskl.`; `null` når ingen er kjent) og `tittel`. Spillet viser `kort` i trekklisten; mangler den, vises fullt navn. Testen `LawNamesTests` krever at hver lov i repoet har en oppføring og at forkortelsene er unike og høyst 8 tegn. Filen er innhold: rett den når Lovdata sier noe annet, og fjern `(?)` fra `tittel` når forkortelsen er kontrollert.

## Sandkassecaser

`Innhold/sandkasse/<id>.json`: `id`, `tittel`, `selskap`, `beskrivelse`, `vanskelighet`, `lov`, `hendelser` (`dato`, `tekst`, `hint`), `fasitSaldobalanse` (konto → saldo, debet pluss og kredit minus) og `fasitJournal` (bilagene som gir fasiten). `SandboxCaseTests` sjekker at journalen stemmer med saldobalansen og at mva-linjene følger kodene.

To valgfrie felt gjør casen avstembar: `kontoutskrift` (`konto` 1920, `utgaaende`, `linjer` med `id`, `dato`, `tekst`, `belop` signert sett fra kontoen og `bilag`: 1-baserte numre på bilagene i `fasitJournal` som linjen gjør opp) og `valutakurser` (valuta → liste av `dato` og `kurs`; casens egne tall, aldri fra `satser.json`). Bare bilag med en 1920-linje pekes på. `SandboxCaseValidator` krever at hver gruppe av linjer og bilag summerer likt, at hvert bilag med bankbevegelse har en linje, og at summen av linjene er lik `utgaaende` og 1920 i `fasitSaldobalanse`.

Mønstre: (1) én linje ↔ ett bilag; (2) én linje ↔ flere bilag (kortinnløser betaler ut flere dagers salg samlet); (3) flere linjer ↔ ett bilag (ett lønnsbilag, én utbetaling per ansatt); (4) gebyr og renter som føres fra banklinjen; (5) åpen post uten banklinje; (6) valuta med kursdifferanse på 8060/8160. `bank-001` har alle seks.

## Byen (`by/`)

`Innhold/by/` er byen Hovedbok i Rubin-utgaven: bransjer, klienter og kart. All tekst i byen vises i en dialogboks på 36 tegn og 6 linjer; et ord over 18 tegn er likevel en valideringsfeil, så velg et kortere ord.

**`bransjer.json`**: én liste. `id`, `navn` (vises på behovskortet), `temaer` (fra `temaer.json`), `regelkort` (filnavn i `Innhold/regler/` uten `.md`) og `setning`. Ingen bransje får en regel uten regelkort.

**`klienter/<id>.json`**: én klient per fil.

```json
{
  "id": "kafe-lysthuset",
  "navn": "Kafé Lysthuset AS",
  "bransje": "servering",
  "selskapsform": "AS",
  "mvaRegistrert": true,
  "ansatte": 4,
  "lonnsdag": 20,
  "mvaTermin": "tomaanedlig",
  "sted": { "kart": "restauranten", "x": 4, "y": 2 },
  "oppgaver": ["mva-behandling-003", "grunnlag-001"],
  "provesak": ["mva-behandling-004", "mva-regnut-001", "mva-quiz-001"],
  "replikker": {
    "hilsen": ["Hei! Så fint at du kom."],
    "drift": ["Vi har servering i salen og take-away i disken."],
    "haug": ["Her er bilagene."],
    "tomHaug": ["Ingen bilag denne måneden."],
    "glippetFrist": ["Fristen gikk ut."],
    "oppdagetFeil": ["Gjesten vår så noe rart i regnskapet!"]
  },
  "startklient": true,
  "status": "utkast"
}
```

- `mvaTermin` (`tomaanedlig` eller `aarlig`) står der hvis og bare hvis `mvaRegistrert` er `true`.
- `oppgaver` er papirhaugen; bare oppgaver som er i utvalget (godkjent, eller utkast når de vises) havner i haugen. `provesak` er nøyaktig tre oppgave-id-er.
- En klient som ikke er mva-registrert, får ingen oppgave av typen `mva` og ingen `postering` med konto 2700–2799. Fasiten antar ellers et mva-registrert selskap. Det gjelder også kontoer som ikke er mva (2770 og 2780 for arbeidsgiveravgift).
- `lonnsdag` (1–28) er dagen lønnen utbetales. Den står der hvis og bare hvis `ansatte` er over 0, og er casens eget tall (ikke fra `satser.json`). Klienter uten ansatte får ingen lønnsfrister.
- `oppdagetFeil` er replikken når klienten selv har oppdaget en gammel feil (en korrigering). Feltet er valgfritt.
- `drift` er eieren som forteller om driften med egne ord. Den peker på bransjens fallgruve, men gir ikke svaret.
- `sted` må ha en person med `rolle: "klient"` og samme `klient` på samme rute.
- Nøyaktig én klient har `startklient: true`; sjefen gir den ved start.

**`kart/<id>.json`**: ett kart per bydel og per rom. `ruter` er rader med ett tegn per rute:

| Tegn | Rute | Gangbar |
|---|---|---|
| `.` | gulv, gate | ja |
| `,` | gress | ja |
| `D` | dør | ja |
| `#` | vegg | nei |
| `^` | tak | nei |
| `~` | vann | nei |
| `=` | disk | nei; A over disken snakker med den som står bak |

`dorer`: `x`, `y` (en `D`-rute), `til` (kart-id), `tilX`, `tilY` (en gangbar rute uten person). Legg dører i begge retninger: ut av rommet lander på ruten foran døren i bydelen. `folk`: `id`, `rolle`, `x`, `y`, `tekst`, og for noen roller et ekstra felt:

| `rolle` | Gjør | Ekstra |
|---|---|---|
| `sjef` | Sier `tekst`. Spilleren starter på ruten under den første sjefen i `kontoret`, vendt opp. | |
| `skranke` | Lukker måneder og leverer. Står bak en `=`. | |
| `seng` | Sier `tekst`, spør «Sove?». | |
| `fagkontor` | Gym for temaene. Et tema hører til ett fagkontor. | `fagkontor`: `id`, `navn`, `temaer` |
| `klient` | Eieren. Bruker klientens `replikker`, ikke `tekst`. | `klient`: klient-id |
| `kaffe` | Kaffemaskinen på kontoret. Spilleren kjøper en kopp for å få energi. Sier `tekst`. Står på en ledig rute som ikke sperrer døren, disken, sengen eller sjefen. | |
| `kundesak` | En klient som står utenfor bygget sitt og spør om en sak. Spilleren svarer, og dommen vises. | `klient`: klient-id; `oppgave`: id til en godkjent `sak`- eller `quiz`-oppgave |
| `skilt`, `folk` | Sier `tekst`. | |

En `kundesak`-oppgave er av typen `sak` eller `quiz` og må ikke stå i klientens `oppgaver` eller `provesak`. Validatoren sjekker begge deler. En oppgave av typen `mva` kan derfor aldri bli en kundesak. `tekst` er klienten som spør, uten svaret. Ingen kundesak står på selve døra eller sperrer den eneste veien.

Alle kart må kunne nås fra `kontoret` gjennom dører. Hold klientene nær: ingen klientdør mer enn 20 steg fra kontorets dør i samme bydel.

Validatoren sjekker byen sammen med oppgavene: kjør `swift test --filter ContentValidatorTests`.
