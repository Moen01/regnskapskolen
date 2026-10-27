# Bankavstemming og valuta i sandkassen

Status: utkast til godkjenning. Skrevet 27.10.2026 etter samtale med Andreas.

## Hvorfor

Sandkassen i dag: en case gir hendelser, brukeren fører bilag, saldobalansen sammenlignes med fasiten. Det som mangler er det en regnskapsfører gjør hver måned etter at bilagene er ført: **avstemme banken**. Kontoutskriften fra banken skal forklares linje for linje mot egen bokføring, og virkeligheten er rotete: én innbetaling dekker tre fakturaer, én faktura betales i to omganger, banken trekker gebyr uten at noe bilag finnes, og en faktura i euro gjøres opp til en annen kurs enn den ble ført til.

Andreas vil ha «et enda mer virkelig sandbox». Målet er at brukeren lærer at avstemmingen er *kontrollen* på bokføringen: feil beløp i et bilag viser seg som en banklinje som ikke lar seg matche.

## Mål

1. En case kan ha en **kontoutskrift** for konto 1920.
2. Brukeren **avstemmer selv**: velger én eller flere banklinjer og ett eller flere av sine egne bilag, og «Avstem» godtas bare når summene er like, på øret.
3. Banklinjer uten bilag (gebyr, renter, netto fra kortinnløser) kan **føres rett fra banklinjen**: appen lager et bilag med dato, tekst og 1920-linjen ferdig utfylt.
4. **Valuta**: hendelser i utenlandsk valuta med kurs ved føring og ved betaling. Differansen føres på 8060 (agio) eller 8160 (disagio). Kursene er casens egne tall.
5. **Claude** kan lage caser med alt dette, og validatoren forkaster caser der banken ikke stemmer med journalen.
6. Fasit-fanen får et nytt kriterium ved siden av saldobalansen: **bank avstemt**.
7. `kafe-001` får en kontoutskrift, og en ny håndskrevet case øver alle mønstrene og er Claudes formateksempel.

## Ikke-mål

- Ingen import av ekte bankfiler (CSV, CAMT).
- Ingen reskontroavstemming per kunde/leverandør. Bare bank, bare 1920.
- Ingen automatisk matching («Foreslå»). Å finne paret er øvelsen.
- Ingen endringer i oppgavetypene under `Innhold/oppgaver`.
- Ingen bankinnskudd i valuta (bare fordringer og gjeld i valuta). Årsslutt-omregning etter rskl. § 5-9 er utenfor denne runden.

## Anti-mål (dette ville gjort det til en fiasko)

- Brukeren kan «bli ferdig» med avstemmingen uten at bokføringen er riktig. Derfor: summene må stemme nøyaktig, og alle banklinjer og alle egne 1920-posteringer må være forklart.
- Casen avslører fasiten. Referansene fra banklinjer til fasitbilag er for validatoren og vises aldri i appen.
- Tall som er gjettet. Mva-satser og frister kommer fra `satser.json` som før. Valutakurser er *fiktive casetall* og står i casefilen. Dette er en bevisst justering av regelen «satser.json er den eneste kilden til tall»: den gjelder lovsatser, ikke casens egne kurser. CLAUDE.md oppdateres med den setningen.

## Begrensninger

- Alt som kan testes ligger i `RegnskapKit`. Ingen SwiftUI i Kit.
- Gamle casefiler uten kontoutskrift skal laste og virke som før. Bank-visningen sier da «Denne casen har ingen kontoutskrift».
- `sandkasse.json` (brukerens journal i Application Support) beholder formatet sitt. Avstemmingen lagres i en egen fil, så en eldre journal aldri blir ulesbar.
- Ingen nye avhengigheter.
- Norsk bokmål i alt brukeren leser.

## Datamodell i casefilen

To nye, valgfrie felt i `Innhold/sandkasse/<id>.json`:

```json
"valutakurser": {
  "EUR": [ { "dato": "2026-03-04", "kurs": 11.50 }, { "dato": "2026-03-24", "kurs": 11.80 } ]
},
"kontoutskrift": {
  "konto": "1920",
  "utgaaende": 94900,
  "linjer": [
    { "id": "b01", "dato": "2026-03-01", "tekst": "Innskudd aksjekapital", "belop": 100000, "bilag": [1] },
    { "id": "b02", "dato": "2026-03-02", "tekst": "Nettgiro Gårdeier AS", "belop": -18750, "bilag": [2] },
    { "id": "b07", "dato": "2026-03-20", "tekst": "Innbet. Kunde AS", "belop": 56250, "bilag": [5, 6, 8] },
    { "id": "b09", "dato": "2026-03-31", "tekst": "Gebyr", "belop": -150, "bilag": [11] }
  ]
}
```

- `belop` er signert sett fra kontoen: inn på konto pluss, ut minus.
- `bilag` er **1-basert indeks i `fasitJournal.entries`**. Siden det er ett bilag per hendelse, er det samme tall som hendelsesnummeret brukeren ser. Ingen nytt `nr`-felt; Claude kan ikke nummerere feil.
- Én banklinje kan peke på flere bilag (samlebetaling). Flere banklinjer kan peke på samme bilag (delbetaling).
- `utgaaende` er det kontoutskriften viser som sluttsaldo. Den kan regnes ut fra linjene, men står der fordi det er slik en utskrift ser ut, og fordi validatoren da fanger regnefeil hos Claude.
- `valutakurser` er bare til visning i casepanelet («Kurser i casen») og til prompten. Hendelsesteksten skal uansett oppgi kursen («2 000 EUR, kurs 11,50»), så brukeren slipper å slå opp.

Mønstre en kontoutskrift skal kunne inneholde. «Bilag» betyr her **brukerens journalbilag med en 1920-linje**, ikke fakturaer i reskontroen: det er journalen som avstemmes mot banken. Et bilag uten 1920-linje (faktura på kreditt) pekes aldri på.

| Nr | Mønster | Eksempel |
|---|---|---|
| 1 | én linje ↔ ett bilag | husleie betalt; én faktura betalt; et bilag som gjør opp tre fakturaer i én betaling er fortsatt ett bilag og én linje |
| 2 | én linje ↔ flere bilag | kortinnløser eller Vipps betaler ut ukens salg samlet, mens salget er bokført per dag (tre hendelser «Kortsalg mandag/tirsdag/onsdag», én banklinje); eller innbetaling fra kunde registrert som ett bilag per faktura |
| 3 | flere linjer ↔ ett bilag | lønn: ett lønnsbilag, én nettoutbetaling per ansatt på kontoutskriften |
| 4 | linje uten eget bilag i hendelsene fra før | gebyr, renter, kortinnløser som setter inn netto. Hendelsen finnes («Banken belaster…»), men brukeren fører den fra banklinjen |
| 5 | bilag uten banklinje ved månedsslutt | ubetalt faktura, åpen post. Treffer ikke 1920 og skal derfor ikke i kontoutskriften |
| 6 | valuta med differanse | faktura 2 000 EUR til 11,50 (23 000), betalt til 11,80 (23 600): 600 på 8160 |

Mønster 4 er egentlig mønster 1 med et bilag brukeren ikke tenkte på. Det er poenget med det. Delbetaling av én faktura er to betalingshendelser og dermed to ganger mønster 1; det er lov, men er ikke et eget mønster.

**Åpningsbalansen (mitt valg):** kontoutskriften starter på null, og første linje er «Inngående saldo» (eller «Innskudd aksjekapital» for et nytt selskap) som peker på åpningsbilaget. Da trengs ikke et `inngaaende`-felt, og `BankCheck` slipper et unntak for åpningsbilaget. Prompten sier dette rett ut.

## Brukerens avstemming

### Modell (Kit)

```swift
public struct BankLine: Codable, Hashable, Identifiable { id: String; dato: DayKey; tekst: String; belop: Decimal; bilag: [Int] }
public struct BankStatement: Codable, Hashable { konto: String; utgaaende: Decimal; linjer: [BankLine] }

public struct BankMatch: Codable, Hashable, Identifiable { id: UUID; bankLineIds: [String]; entryIds: [UUID] }
public struct Reconciliation: Codable, Hashable { matches: [BankMatch] }
```

- Et bilags **bankbevegelse** er summen av dets 1920-linjer, debet pluss og kredit minus. Et bilag uten 1920-linje kan ikke avstemmes.
- En match er gyldig når summen av banklinjene er lik summen av bilagenes bankbevegelse, nøyaktig. Ingen toleranse: en valutadifferanse føres i samme bilag, så 1920-linjen blir lik banklinjen.
- En banklinje og et bilag er med i høyst én match.
- **Beskjæring (mitt valg):** etter hver endring i journalen fjernes matcher som ikke lenger er gyldige (bilag slettet, beløp endret). Brukeren ser at linjen «spretter tilbake» til uavstemt. Enkelt og uten ødelagte mellomtilstander.
- **Ferdig** når: alle banklinjer er i en match, alle bilag med bankbevegelse ≠ 0 er i en match, og journalens 1920-saldo er lik `utgaaende`. `BankCheck` i Kit returnerer disse tre som hver sin bool pluss tall til visning (antall avstemt av totalt, uavstemt sum på hver side, differanse mot utgående).
- Lagres som `avstemming.json` i Application Support ved siden av `sandkasse.json`. Tømmes når journalen tømmes eller en ny case starter.

### «Før fra banklinjen»

Knapp på hver uavstemt banklinje. Lager et nytt bilag i journalen med linjens dato, tekst og én 1920-linje (debet når `belop` > 0, ellers kredit, beløp uten fortegn) pluss én tom motlinje. Bilaget og banklinjen matches med en gang (mitt valg: 1920-linjen er lik banklinjen per konstruksjon, så matchen holder; brukeren slipper tre klikk). Bilaget balanserer ikke før motlinjen er fylt ut, og det vises som i dag under bilaget.

### Skjerm

Midtpanelet (det bredeste) får en segmentert velger øverst: **Journal | Bank**. Rapportpanelet til høyre beholder fanene sine. Bank-visningen trenger to kolonner, og rapportpanelet (36 % av vinduet, minst 320 pt) er for smalt til det. Dette er mitt valg.

Bank-visningen:

- Topp: «Kontoutskrift 1920 · utgående 94 900,00», framdrift «5 av 9 linjer avstemt».
- To kolonner. Venstre: banklinjer (dato, tekst, beløp). Høyre: egne bilag med bankbevegelse (dato, bilagstekst, beløp). Rader velges ved klikk (flervalg). Avstemte rader samles under en `DisclosureGroup` «Avstemt (5)», grå, med «Opphev» per match.
- Bunn: «Valgt: bank 23 600,00 · bilag 23 600,00 · differanse 0,00» og knappen **Avstem**, aktiv bare når differansen er null og begge sider har noe valgt.
- Hver uavstemt banklinje har **Før fra banklinjen**.
- Når casen mangler kontoutskrift: `ContentUnavailableView` med «Denne casen har ingen kontoutskrift».

Fasit-fanen (rapportpanelet) viser to linjer: «Saldobalansen stemmer» og «Banken er avstemt», hver med hake eller avvik. Teksten «Godt jobbet!» kommer når begge er grønne.

Casepanelet viser `valutakurser` som en liten tabell under hendelsene når feltet finnes.

## Claude

- `PuzzleSchema.sandboxCase` får `kontoutskrift` (påkrevd) og `valutakurser` (valgfritt). `bilag` er en array av heltall ≥ 1.
- `Innhold/prompter/sandkasse.md` får et avsnitt om kontoutskriften: mønstrene 1–6 med krav om minst ett av hvert av 2, 3, 4 og 5 ved vanskelighet ≥ 3; mønster 6 er påkrevd for tema `valuta-korrigeringer`, velkommen ved vanskelighet ≥ 4 ellers, og aldri påtvunget et tema der valuta er unaturlig (mitt valg); første linje er åpningsbalansen; hver linje peker på bilagene den gjør opp, og bare bilag med 1920-linje; gebyr og renter er hendelser («Banken belaster…»); minst én faktura står ubetalt ved månedsslutt; summen av linjene er lik `utgaaende` og lik 1920 i `fasitSaldobalanse`; kurser står i `valutakurser` *og* i hendelsesteksten; regelkortet for valuta (bfl. § 7, rskl. § 5-9) er kilden for 8060/8160.
- **Regelkort i prompten (mitt valg):** `Tutor.system` legger i dag bare ved kortene for casens tema. Siden hver case nå har bank, legger `makeCase` alltid ved kortene for `reskontro-bank` og `valuta-korrigeringer` i tillegg, så Claude har paragrafene for avstemming og kursdifferanse uansett tema. Validatoren sjekker bare paragrafens form, så uten kortene ville Claude dikte.
- **Formateksempelet** Claude får er casen med flest banklinjer blant de håndskrevne, ikke lenger «første fil». Det blir den nye `bank-001`.
- **Validering flyttes til Kit:** `SandboxCaseValidator.problems(case, chart:, rates:)` brukes av både `Tutor.makeCase` og `SandboxCaseTests` (i dag ligger samme logikk to steder). Den sjekker det som finnes i dag (journalen er gyldig, saldobalansen stemmer) pluss, når kontoutskriften finnes:
  - linje-id-er er unike, `konto` er 1920, hver `bilag`-indeks peker på et bilag som finnes
  - bygg sammenhengende komponenter av banklinjer og bilag via `bilag`; i hver komponent er sum(linjer) lik sum(bilagenes bankbevegelse)
  - hvert bilag med bankbevegelse ≠ 0 er pekt på av minst én linje; hver linje peker på minst ett bilag
  - sum(alle linjer) = `utgaaende` = `fasitSaldobalanse["1920"]`
  - hver linjes dato ligger i casens måned
- Forventning: Claude bommer oftere på konsistens når tre ting skal henge sammen. Validatoren gir konkrete meldinger («b07: linjen er 56 250, bilagene 5, 6, 8 gir 46 250»), og feilmeldingen vises som i dag. Ingen automatisk nytt forsøk i denne runden.

## Innhold som skrives for hånd

1. `kafe-001` får `kontoutskrift` med de åtte 1920-bevegelsene journalen allerede har, alle mønster 1, og `utgaaende` 94 900. Ingen hendelser endres.
2. Ny case `Innhold/sandkasse/bank-001.json`, tema `reskontro-bank`, vanskelighet 4: et lite norsk selskap, 11–14 hendelser i én måned i 2026, med mønster 2, 3, 4, 5 og 6 minst én gang hver. Valuta: én leverandørfaktura i EUR ført til én kurs og betalt til en annen; begge kursene i `valutakurser` og i teksten. `lov` fra regelkortene `reskontro-tap-purring` og `valuta-korrigeringer`. Skrives med `/sandkasse-case` og må bestå `SandboxCaseTests`. Selskapet, bransjen og tallene er opp til den som skriver.

## Tester

- `SandboxCaseTests`: alle caser i repoet består `SandboxCaseValidator`; `kafe-001` og `bank-001` har kontoutskrift.
- Ny `BankReconciliationTests`: match godtas bare når summene er like; samlebetaling (1↔3) og delbetaling (2↔1) går; beskjæring fjerner en match når bilaget endres; `BankCheck` er ferdig bare når alle tre vilkår holder; «Før fra banklinjen» gir et bilag med riktig side og beløp og en match.
- Ny test for validatoren med en fikstur der en banklinje ikke stemmer med bilagene, og en der `utgaaende` ikke stemmer med summen.
- `ClaudeTests`: skjemaet inneholder `kontoutskrift`; `makeCase` avviser en fikstur med gal kontoutskrift og sier hvilken linje.
- Skjermbilder: `sandbox.png` beholdes; ny `sandbox-bank.png` med `bank-001` halvveis avstemt (demo i `loadSandboxDemo`).

## Dokumentasjon som oppdateres

- `docs/innhold.md`, avsnittet om sandkassecaser: de nye feltene og mønstertabellen.
- `docs/claude.md`: raden for «Lag en case» nevner kontoutskriften og at eksempelet er casen med flest banklinjer.
- `.claude/skills/sandkasse-case/SKILL.md`: steg for kontoutskrift og valutakurser.
- `CLAUDE.md`: tabellraden for `Innhold/sandkasse` og setningen om kurser under regel 1.

## Utgangspunkt

Planen bygger på arbeidstreet slik det er 27.10.2026, med de ukomitterte endringene fra samme dag (`DateField`, `MonthCalendar`, `MainView`, `JournalEditor`). Andreas committer dem før planen kjøres, så grenen starter rent.

## Overlatt til den som bygger

- Layout, farger og avstander i Bank-visningen, så lenge den følger `Theme.swift` (debet/kredit-farger, `.skole`).
- Sortering av radene (dato stigende er et greit utgangspunkt).
- Om avstemte matcher skal vise hvilke bilag de inneholder når gruppen er åpnet (ja, hvis det er billig).
- Hvordan «Før fra banklinjen» plasserer fokus etterpå.
- Om `bilag`-referansene kan vises som en fasit *etter* at casen er ferdig. Ikke i denne runden med mindre det er gratis.
