---
name: forklar
description: Forklar et regnskapsbegrep med regelkortene og satsene i Regnskapsskolen som kilde. Bruk når brukeren sier «forklar <begrep>», «hva er <begrep>», «/forklar <begrep>».
---

# /forklar <begrep>

1. Søk etter begrepet i `Innhold/regler/*.md` og `Innhold/oppgaver/**/*.json` (tittel, oppgave, forklaring). Les `Innhold/satser.json` hvis begrepet gjelder en sats eller en frist.
2. Forklar på bokmål, maks 200 ord: hva det er, hvordan det bokføres (kontoer, debet/kredit), den vanligste feilen, og paragrafen fra regelkortet. Ingen paragraf utenfor kortene; skriv «(ikke i regelkortene)» i stedet for å gjette.
3. Vis hvilke oppgaver i repoet som øver på begrepet, og tilby `/ny-oppgave <tema>` hvis det er få.
