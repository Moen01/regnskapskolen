# Utgivelser

En utgivelse er en pushet, annotert tag `vX.Y.Z`. Workflowen **Release** (`.github/workflows/release.yml`) kjører på en macOS-runner: tester, bygger med `APP_VERSION` fra taggen, signerer med Developer ID og notariserer når hemmelighetene finnes (ellers ad hoc), og legger `Regnskapsskolen-X.Y.Z.zip` på GitHub-releasen. Installerte apper finner den innen seks timer, eller med en gang fra Innstillinger → **Sjekk nå**. Taggens melding blir utgivelsesnotatet appen viser, så skriv den på bokmål for regnskapsførere.

## Sjekkliste

1. `swift test` er grønn. Rør du prosesser eller timing, kjør den tre ganger.
2. Sjekk skjermene du endret i skjermbildemodus (`REGNSKAP_SCREENSHOTS=<mappe> …`).
3. Commit og push `main`.
4. Tag og push: `git tag -a vX.Y.Z -m "Regnskapsskolen X.Y.Z: <hva som er nytt>" && git push origin vX.Y.Z`.
5. Følg kjøringen: `gh run watch "$(gh run list --workflow Release --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status`, og se at vedlegget er der: `gh release view vX.Y.Z --json assets -q '.assets[].name'`.
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
