---
name: sandkasse-case
description: Skriv en ny case til sandkassen i Regnskapsskolen, med hendelser, fasit-saldobalanse og en modelljournal som stemmer. Bruk når brukeren sier «ny case», «sandkasse-case», «/sandkasse-case <tema> [vanskelighet]».
---

# /sandkasse-case <tema> [vanskelighet]

1. Les `docs/innhold.md` (avsnittet om sandkassecaser), `Innhold/sandkasse/kafe-001.json` og `Innhold/sandkasse/bank-001.json` som mal, `Innhold/satser.json` og `Innhold/kontoplan.json`.
2. Finn på et lite norsk selskap og 8–12 hendelser i én måned i 2026 som øver på temaet. Hver hendelse har `dato`, `tekst` og gjerne `hint`.
3. Før `fasitJournal` selv: ett bilag per hendelse, kontoer fra kontoplanen, `mvaKode` på grunnlagslinjene og mva-linjer på 2700/2710 som stemmer med koden. Summer saldoene per konto (debet pluss, kredit minus) til `fasitSaldobalanse`.
4. Skriv `kontoutskrift` for 1920: første linje er åpningsbalansen, hver linje peker på bilagsnumrene den gjør opp, summen er lik `utgaaende` og 1920 i saldobalansen. Ta med minst ett av mønstrene 2–5 (se `docs/innhold.md`), og `valutakurser` når casen har valuta.
5. Skriv `Innhold/sandkasse/<tema>-<nnn>.json` med `lov` (minst én henvisning fra regelkortene).
6. Kjør `swift test --filter SandboxCaseTests`. Testen regner journalen om til saldobalanse og sjekker mva; rett til den er grønn.
7. Oppsummer hendelsene og hva casen øver på.
