# Oppdateringer fra GitHub Releases

Status: utkast til godkjenning. Skrevet 27.10.2026 etter Andreas' beskjed: «bruk oppdateringssystemet som catacloud-dev bruker, med hvordan den søker etter update og hvordan den installerer (viser en knapp at en oppdatering er ledig), samt release i GitHub-siden».

## Hvorfor

I dag installeres Regnskapsskolen fra en zip under *Releases* på GitHub. Ingen får vite at en ny versjon finnes, og nye oppgaver, regler og satser når ikke fram. Catacloud Dev løser det samme for utviklerne: appen sjekker GitHub Releases selv, viser en knapp når en nyere versjon finnes, laster ned, kontrollerer signaturen, bytter ut seg selv og starter på nytt. Regnskapsskolen får det samme systemet, med de avvikene som følger av at repoet er offentlig og brukerne er regnskapsførere, ikke utviklere.

Referansen er `Sources/CatacloudDevKit/Shell/AppUpdater.swift`, `Sources/CatacloudDev/App/AppStore+Updates.swift`, `.github/workflows/release.yml` og `scripts/notarize.sh` i `/Users/moen/Documents/catacloud-dev`. Den som bygger skal lese dem.

## Mål

1. **Søk.** Appen sjekker nyeste release i `Moen01/regnskapskolen` 30 sekunder etter start, deretter hver 6. time mens den kjører, og når brukeren trykker **Sjekk nå**. Sjekken kan slås av i Innstillinger («Se etter oppdateringer», på som standard).
2. **Knapp.** Når en nyere versjon finnes: **Oppdater til X.Y.Z** nederst i popoveren (menylinjen) og **Oppdater og start på nytt** i Innstillinger → Oppdateringer, med utgivelsesnotatene under. Tallet i statusikonet rører vi ikke; en nyere versjon vises som en linje i popoveren.
3. **Installering.** Som Catacloud Dev: last ned `Regnskapsskolen-<versjon>.zip` fra utgivelsen, pakk ut med `ditto`, kontroller med `codesign --verify --deep --strict` (og krev samme Apple-team når den kjørende appen er signert med Developer ID), fjern karantene, bytt bundelen med `.previous` som sikkerhetskopi, start på nytt. Feil underveis setter den gamle tilbake.
4. **Release på GitHub.** Workflowen som finnes (`.github/workflows/release.yml`: tag `v*` → test → `bundle.sh` → zip → `gh release create`) beholdes og utvides: når hemmelighetene for Developer ID og notarisering finnes i repoet, signeres og notariseres appen som i Catacloud Dev; ellers ad hoc som i dag. Nytt `scripts/notarize.sh` (kopi av Catacloud Dev sitt, med Regnskapsskolens navn). **Utgivelsesnotatene er på bokmål (mitt valg, etter repoets regel 5):** taggen er annotert (`git tag -a vX.Y.Z -m "Regnskapsskolen X.Y.Z: <hva som er nytt>"`), og workflowen bruker `--notes-from-tag` i stedet for `--generate-notes`, så det som vises i Innstillinger er skrevet for regnskapsførere, ikke en liste over engelske commit-meldinger.
5. **Utviklingsbygg oppdaterer aldri seg selv.** `bundle.sh` uten `APP_VERSION` setter `RegnskapsskolenDevBuild` i Info.plist og versjon `<siste tag>-dev`; appen viser «Utviklingsbygg» i stedet for knappen.

## Ikke-mål

- Automatisk installering uten klikk. Catacloud Dev har det som valg; Regnskapsskolen får det ikke i denne runden. Brukeren trykker.
- Sparkle eller andre rammeverk. Ingen nye avhengigheter.
- Delta-oppdateringer, flere kanaler (beta), nedgradering.
- Oppdatering av innholdsmappen alene. Innholdet følger appen.

## Anti-mål

- En oppdatering som installerer noe som ikke lar seg kontrollere. `codesign --verify` må gå gjennom, og en Developer ID-signert app godtar bare samme team. En ad hoc-signert app (uten hemmelighetene i CI) kontrollerer bare at bundelen er hel; det står i README som en kjent begrensning, og er grunnen til at Developer ID anbefales.
- En sjekk som krever noe brukeren ikke har. Ingen `gh`, ingen innlogging, ingen token.
- Å ødelegge den kjørende appen. Bytt aldri før den nye er pakket ut og kontrollert; behold `.previous` til byttet er gjort.
- Å oppdatere mens skjermbilder tas (`REGNSKAP_SCREENSHOTS`) eller fra et utviklingsbygg.

## Avvik fra Catacloud Dev, og hvorfor

| Catacloud Dev | Regnskapsskolen | Hvorfor |
|---|---|---|
| `gh release view` / `gh release download` | `URLSession` mot `https://api.github.com/repos/Moen01/regnskapskolen/releases/latest` og vedleggets `browser_download_url` | Repoet er offentlig, og regnskapsførere har ikke `gh`. 60 kall i timen uten innlogging er mer enn nok for ett per 6 timer. |
| Venter på at jobber er ferdige | Ingen venting | Appen har ingen bakgrunnsjobber. |
| Automatisk installering som valg | Bare knapp | Mindre å forklare; kan legges til senere. |
| Varsel i appens feed | Én macOS-varsling per ny versjon via `Reminder`, når varsler er tillatt (mitt valg) | Appen er i menylinjen; uten varsel ser ingen knappen før de åpner popoveren. |
| Provisioning profile, keychain-entitlements | Ikke med | Regnskapsskolen har ingen nøkkelring-tokens. |

## Oppførsel i detalj

- **Versjon** er `CFBundleShortVersionString`. `isNewer("0.10.0", than: "0.9.3")` sammenligner tall for tall, som i Catacloud Dev; `-dev`-suffiks teller som 0.
- **Søk** (`AppUpdater.latest()`): `GET …/releases/latest` med `Accept: application/vnd.github+json` og `User-Agent: Regnskapsskolen/<versjon>`. 404 = ingen utgivelser (nil). Svaret gir `tag_name`, `name`, `body`, `published_at`, `html_url` og `assets[]` med `name` og `browser_download_url`; vedlegget er det første som begynner på `Regnskapsskolen` og slutter på `.zip`. En utgivelse uten vedlegg vises med knappen slått av og teksten «Utgivelsen har ingen app vedlagt ennå. Byggingen kan fortsatt pågå.»
- **Nedlasting** (`AppUpdater.install`): `URLSession.download` til en midlertidig mappe, deretter `installArchive(zip, over: Bundle.main.bundlePath)` som i Catacloud Dev. Mappen appen ligger i må være skrivbar. Er den ikke det (en Mac styrt av IT der Programmer er skrivebeskyttet), sier appen «Kan ikke bytte ut appen i <mappe>: mappen er skrivebeskyttet. Last ned den nye versjonen fra GitHub og dra den inn selv, eller be IT.» og knappen «Utgivelser på GitHub» står ved siden av. Ingen fallback til `~/Programmer` i denne runden (mitt valg).
- **Omstart**: `AppUpdater.relaunch` kjører `sleep 1; open <sti>` i et skall etter at appen har avsluttet; popoveren lukkes, og `NSApp.terminate`.
- **Tilstand i appen** (`AppStore`): `availableUpdate: AppRelease?`, `updateState: String?` (én linje til brukeren), `isUpdating: Bool`, `lastUpdateCheck: Date`. Sjekken kjøres i en `Task` som startes fra `AppStore.start` (ikke i skjermbildemodus, ikke i utviklingsbygg).
- **Tekster** (bokmål): «Oppdater til 0.2.0», «Oppdaterer…», «Oppdater og start på nytt», «Sjekk nå», «Du har nyeste versjon (0.1.0).», «Ingen utgivelser ennå.», «Dette er et utviklingsbygg og oppdaterer ikke seg selv.», «Laster ned 0.2.0…», «Installert. Starter på nytt…», «Utgivelser på GitHub» (åpner `https://github.com/Moen01/regnskapskolen/releases`), «Den nedlastede appen lot seg ikke pakke ut eller kontrollere.», «Versjon 0.2.0 er klar» (varselet).
- **Innstillinger**: ny seksjon «Oppdateringer» over «Om»: versjon, knappen når noe finnes, notatene (Markdown, maks 160 pt høye), statuslinjen, «Sjekk nå», «Utgivelser på GitHub», bryteren «Se etter oppdateringer». «Om»-seksjonen mister versjonslinjen.
- **Popover**: under dagens oppgaver, over knappene: `Oppdater til X.Y.Z`-knapp (`.borderedProminent`, `.tint(.skole)`) når en oppdatering finnes; ellers ingenting (versjonen står i Innstillinger).

## Testbarhet (Kit)

`AppUpdater` tar en `fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)` og en `download: @Sendable (URL) async throws -> URL` ved init, med `URLSession.shared` som standard, så testene kan gi JSON og en zip uten nett. `installArchive` testes mot en ekte, ad hoc-signert dummy-app laget i testen (`codesign --sign -`), og mot en zip uten `.app` og en zip med en usignert app. `relaunchCommand` testes som streng. `ProcessRunner` brukes som i resten av Kit.

## Release i CI

`release.yml` får Catacloud Dev sine steg «Import the signing certificate», «Notarise» og «Remove the signing keychain», alle med `if: ${{ secrets.DEVELOPER_ID_CERT_P12 != '' }}` (via en forberedende `env`-sjekk, siden `secrets` ikke kan stå direkte i `if`), slik at workflowen virker både med og uten hemmelighetene. Hemmelighetene heter som i Catacloud Dev: `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`. README får en tabell over dem. Hvilket Apple-team som signerer (Catacloud AS eller Andreas selv) er Andreas' valg; koden bryr seg ikke, bare at det er det samme teamet hver gang.

Andreas' regel: CI og hemmeligheter rører jeg ikke uten et ja. Workflow-endringen og hemmelighetene er derfor en egen oppgave i planen som venter på hans bekreftelse.

## Dokumentasjon

- README: «Installer fra zip» får et nytt punkt om at appen varsler om nye versjoner, og en ny seksjon «Oppdateringer» (hva som sjekkes, hvor ofte, hva som lastes ned, signering, hemmelighetene).
- Ny `docs/releasing.md`: tag, workflow, hva som skjer når CI feiler (aldri flytt en tag; neste patch), og en versjonstabell.
- `docs/engineering-notes.md` hvis noe kostet tid.
- `CLAUDE.md`: kommandoen for release (`git tag vX.Y.Z && git push origin vX.Y.Z`) i kommandotabellen.

## Overlatt til den som bygger

- Nøyaktig plassering og utseende i popover og Innstillinger, innenfor `Theme.swift`.
- Om `updateState` vises i popoveren eller bare i Innstillinger.
- Hvor lenge `.previous` beholdes ved feil (Catacloud Dev sletter den når byttet lyktes, ellers setter den tilbake).
