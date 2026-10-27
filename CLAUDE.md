# Regnskapsskolen

Treningsapp for norske regnskapsførere: macOS-app i menylinjen (`Sources/Regnskapsskolen`) over et UI-fritt bibliotek (`Sources/RegnskapKit`), med alt innhold som JSON og Markdown under `Innhold/`. Alt brukeren leser er på norsk bokmål.

## Oppbygning

| Hvor | Hva |
|---|---|
| `Innhold/oppgaver/<tema>/*.json` | Én oppgave per fil. Formatet: `docs/innhold.md`. |
| `Innhold/regler/*.md` | Regelkort med front matter (`tittel`, `lov`, `paragrafer`, `tema`, `kilde`). |
| `Innhold/satser.json` | Satser og frister. Den eneste kilden til tall. |
| `Innhold/sandkasse/*.json` | Caser til sandkassen, med `fasitJournal` som må stemme med `fasitSaldobalanse`. |
| `Innhold/prompter/*.md` | Systemprompter (`veileder`, `forfatter`, `sandkasse`). |
| `Sources/RegnskapKit` | Innhold, validator, sjekkere, Leitner-planlegger, sandkasse, Claude-kjører. Importerer aldri SwiftUI/AppKit. |
| `Sources/Regnskapsskolen` | AppDelegate (statusikon, popover, vindu), AppStore, skjermene. |
| `Tests/RegnskapKitTests` | XCTest. `ContentValidatorTests` validerer alt innhold i repoet. |
| `docs/` | `innhold.md`, `claude.md`, `regler.md`, `engineering-notes.md`. |

## Innholdskontrakten, kort

- Hver oppgave har `id` (unik, `<tema>-<type>-<nr>`), `type` (postering, klassifiser, finnfeil, regnut, quiz, sak, mva, frist), `tema` (fra `temaer.json`), `vanskelighet` 1–5, `tittel`, `oppgave`, `lov` (minst én), `forklaring`, `status` (`godkjent` eller `utkast`) og typens egne felt.
- `lov`-oppføringer: `{ "lov": "merverdiavgiftsloven", "paragraf": "§ 3-30", "tekst": "…én setning…" }`. `paragraf` er bare nummeret.
- Posteringer balanserer. Kontoer finnes i `kontoplan.json`. Mva-behandlinger finnes i `satser.json`. Frister regnes ut fra `fasitRegel`.
- Nytt innhold er `utkast` til et menneske har lest det.

## Regler for arbeid i dette repoet

1. **Gjett aldri en sats eller en frist.** Les `Innhold/satser.json`. Står tallet ikke der, skriv ikke oppgaven.
2. **Hver oppgave trenger `lov`.** Bruk paragrafer fra regelkortene i `Innhold/regler/` eller fra en oppgave du bygger videre på. Er du usikker på paragrafen, velg en annen vinkling.
3. **Kjør `swift test --filter Content` etter at du har skrevet innhold.** Rød validator betyr at filen ikke er ferdig.
4. **Kit importerer aldri UI.** Logikk som kan testes, ligger i `RegnskapKit`.
5. **Norsk overalt der brukeren leser.** Kode, commit-meldinger og kommentarer er på engelsk.
6. Satsene og kontoplanen endres i sine filer, aldri i oppgavetekster.

## Kommandoer

```sh
swift test                              # alt
swift test --filter ContentValidatorTests
swift test --filter SandboxCaseTests
REGNSKAP_LIVE=1 swift test --filter ClaudeLiveTests   # ekte kall til claude
make app                                # build/Regnskapsskolen.app
make install                            # til /Applications
REGNSKAP_SCREENSHOTS=/tmp/shots build/Regnskapsskolen.app/Contents/MacOS/Regnskapsskolen   # alle skjermer som PNG
./scripts/onboard.sh                    # førstegangsoppsett
```

Skillene: `/ny-oppgave`, `/kvalitetssjekk`, `/forklar`, `/sandkasse-case`, `/ukens-tema` (se `.claude/skills/`).
