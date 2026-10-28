# Utgivelser

Grenene: arbeid skjer på feature-grener med pull requests mot **`staging`**. Når `staging` er klar, lages en pull request `staging` → `main`; merge den, og workflowen **Release** (`.github/workflows/release.yml`) gjør resten på en macOS-runner: finner siste tag, bumper versjonen (patch som standard; skriv `#minor` eller `#major` i merge-meldingen for et større hopp), lager en annotert tag med utgivelsesnotatet, tester, bygger med `APP_VERSION` fra taggen, signerer med Developer ID og notariserer når hemmelighetene finnes (ellers ad hoc), og legger `Regnskapsskolen-X.Y.Z.zip` på GitHub-releasen. Pushes til `main` som bare rører docs gir ingen utgivelse.

**Utgivelsesnotatet** er beskrivelsen i pull requesten `staging` → `main` (tittel + tekst), så skriv den på bokmål for regnskapsførere. Finnes ingen PR (direkte push), brukes commit-titlene siden forrige tag.

Installerte apper finner utgivelsen innen seks timer, når popoveren åpnes etter en time, eller med en gang fra Innstillinger → **Sjekk nå**. Da vises en blå knapp **Oppdater til X.Y.Z**; ett klikk laster ned, kontrollerer, bytter ut appen og starter den på nytt.

En annotert tag `vX.Y.Z` pushet for hånd utgis fortsatt som før, med taggens melding som notat.

## Sjekkliste

1. `swift test` er grønn. Rør du prosesser eller timing, kjør den tre ganger.
2. Sjekk skjermene du endret i skjermbildemodus (`REGNSKAP_SCREENSHOTS=<mappe> …`).
3. PR mot `staging`; CI kjører testene.
4. PR `staging` → `main` med notatet i beskrivelsen; merge.
5. Følg kjøringen: `gh run watch "$(gh run list --workflow Release --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status`, og se at vedlegget er der: `gh release view "$(git describe --tags --abbrev=0 origin/main)" --json assets -q '.assets[].name'` etter `git fetch --tags`.
6. Sjekk en nedlasting for hånd når den er signert: `spctl -a -vv Regnskapsskolen.app` og `xcrun stapler validate Regnskapsskolen.app`.

## Når CI feiler

- En feilet kjøring publiserer ingenting, og ingen app får tilbud om noe. Rett feilen og **tag neste patch-versjon**. Flytt aldri en tag som er pushet; den døde taggen er ufarlig.
- Les feilen med `gh run view <id> --log-failed | grep -E "recorded an issue|error:"`.
- Feil i signering eller notarisering kommer fra hemmelighetene (se README). Ikke gå rundt dem i workflowen.

## Versjoner

| Versjon | Hva den brakte |
|---|---|
| 0.1.0 | Første zip: oppgaver, Leitner, sandkasse, Claude |
| 0.2.0 | Bankavstemming i sandkassen, Spill (Lynrunde, Debet eller kredit?, XP og merker), oppdateringer fra GitHub Releases |
| 0.3.0 | Paragrafjakten: regioner, trekk, HP, gym-ledere, samling, ukens utfordring |
| 0.3.1 | Staging-grenen og automatisk versjon ved merge til main; blå oppdateringsknapp; sjekk når popoveren åpnes |
| 0.4.0 | Paragrafjakten på Game Boy: pikselskjerm, kampskjerm med trekk og svarpanel, tastatur; Spill av som standard |
