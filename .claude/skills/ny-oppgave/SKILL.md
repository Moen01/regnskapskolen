---
name: ny-oppgave
description: Skriv nye oppgaver til Regnskapsskolen i riktig JSON-format og valider dem. Bruk når brukeren sier «ny oppgave», «lag oppgaver om <tema>», «/ny-oppgave <tema> [type] [antall] [vanskelighet]».
---

# /ny-oppgave <tema> [type] [antall] [vanskelighet]

Standard: type velges etter temaet, antall 1, vanskelighet 3. Gyldige typer: postering, klassifiser, finnfeil, regnut, quiz, sak, mva, frist.

## Steg

1. Les `docs/innhold.md` (formatet og validatorreglene) og `Innhold/satser.json` (de eneste tallene du får bruke).
2. Slå opp temaet i `Innhold/temaer.json`. Finnes det ikke, stopp og si hvilke som finnes.
3. Les regelkortene for temaet: filene i `Innhold/regler/` med `tema: <tema>` i front matter. Paragrafene du bruker i `lov`, skal stå der eller i en oppgave du bygger på.
4. Les tre eksisterende oppgaver i `Innhold/oppgaver/<tema>/` for stil, og alle id-ene der så den nye blir unik: `<tema>-<type>-<nnn>` med neste ledige nummer.
5. Skriv hver oppgave som én fil i `Innhold/oppgaver/<tema>/<id>.json` med `"status": "utkast"`. Konkrete beløp i kroner, datoer i 2026, et lite norsk selskap. Én ting å lære per oppgave; `forklaring` på 60–150 ord sier hva. Vanskelighet 4–5 får taggen `edge-case`. For `frist`: `fasit` må være datoen `fasitRegel` gir.
6. Kjør `swift test --filter ContentValidatorTests`. Rett filene til testen er grønn. Ikke endre validatoren.
7. Oppsummer: filnavn, tittel, nivå, paragrafen hver oppgave bygger på, og at de er utkast til et menneske har lest dem (sett `status: godkjent` da).

## Ikke

- Ikke gjett satser, frister eller paragrafer. Mangler grunnlaget, si det og foreslå en annen vinkling.
- Ikke rediger `satser.json`, `kontoplan.json` eller eksisterende oppgaver.
