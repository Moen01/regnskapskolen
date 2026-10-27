---
name: ukens-tema
description: Finn brukerens to svakeste temaer i Regnskapsskolen og lag en plan med nye oppgaver. Bruk når brukeren sier «ukens tema», «hva bør jeg øve på», «/ukens-tema».
---

# /ukens-tema

1. Les `~/Library/Application Support/Regnskapsskolen/fremdrift.json` (`puzzles`: boks per oppgave-id; `days`: dagens sett). Finnes den ikke, si at appen ikke er brukt ennå og stopp.
2. Les `Innhold/temaer.json` og id-ene i `Innhold/oppgaver/<tema>/`. Mestring per tema = andel oppgaver i boks 3 eller høyere. Oppgaver i boks 0 med flere forsøk er de brukeren sliter mest med.
3. Velg de to svakeste temaene (lavest mestring, flest i boks 0). Skriv en kort plan på bokmål: hva som går igjen i feilene (les forklaringene i oppgavene i boks 0), hvilket regelkort som bør leses, og hva de nye oppgavene skal øve på.
4. Lag fem oppgaver per tema med fremgangsmåten i `/ny-oppgave` (les den skillen): typer som varierer, nivå rundt brukerens, minst én `edge-case`. Alle som `utkast`.
5. Kjør `swift test --filter ContentValidatorTests` og oppsummer planen og filene.
