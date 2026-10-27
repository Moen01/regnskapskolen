---
name: kvalitetssjekk
description: Gå gjennom oppgaver i Regnskapsskolen og sjekk lovhenvisninger og regnestykker mot satser.json. Bruk når brukeren sier «kvalitetssjekk», «sjekk oppgavene i <tema>», «/kvalitetssjekk [tema|fil]».
---

# /kvalitetssjekk [tema|fil]

Uten argument: alle utkast (`"status": "utkast"` eller mappen `generert`).

## Steg

1. Les `Innhold/satser.json`, `Innhold/kontoplan.json` og regelkortene for temaet.
2. For hver oppgave, sjekk:
   - **Regnestykket.** Regn ut mva, avskrivning, feriepenger, aga, frister på nytt fra satsene. Avvik er en feil.
   - **Loven.** Finnes paragrafen i regelkortene? Sier `tekst` det paragrafen faktisk sier? En paragraf som ikke står i noe regelkort, merkes «ikke verifisert».
   - **Fasiten.** Er den entydig? Kan et annet alternativ forsvares? For `postering`: riktige kontoer etter NS 4102, riktig side.
   - **Språk.** Bokmål, «debet/kredit», beløp som «12 500 kr», ingen produktnavn.
   - **Nivå og tagger.** Stemmer `vanskelighet` med skalaen i `docs/innhold.md`? Har 4–5 `edge-case`?
3. Kjør `swift test --filter ContentValidatorTests`.
4. Rapporter som en tabell: fil, funn, alvorlighet (feil / usikker / stil), foreslått rettelse.
5. Rett bare med brukerens godkjenning. Når en oppgave er sjekket og riktig, foreslå `status: godkjent`.
