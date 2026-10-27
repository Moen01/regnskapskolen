# Regnskapsskolen

En liten macOS-app i menylinjen som gir deg tre oppgaver om dagen i norsk regnskap: føre bilag, mva, lønn, frister, periodisering, avskrivning, årsoppgjør. Hver oppgave peker på paragrafen den bygger på. Det du får til, kommer sjeldnere tilbake; det du bommer på, kommer snart igjen (Leitner-bokser, 0–21 dager).

Med [Claude Code](https://claude.com/claude-code) installert kan appen forklare hvorfor et svar var feil, svare på spørsmål om oppgaven og lage en vanskeligere variant. Uten Claude virker alt annet som før.

![I dag](docs/skjermbilder/i-dag.png)

| Oppgave med tilbakemelding | Sandkasse |
|---|---|
| ![Oppgave](docs/skjermbilder/oppgave.png) | ![Sandkasse](docs/skjermbilder/sandkasse.png) |

## Installer fra zip

1. Last ned `Regnskapsskolen-<versjon>.zip` under *Releases* og pakk ut.
2. Dra `Regnskapsskolen.app` til *Programmer*.
3. Appen er ad hoc-signert: høyreklikk → *Åpne* første gang (macOS spør én gang).
4. Finn bokikonet i menylinjen. Tallet er oppgavene som gjenstår i dag.
5. Gå gjennom oppsettet: når du vil minnes på, og om Claude skal brukes.

Krever macOS 15 eller nyere.

## Bygg selv

```sh
git clone https://github.com/Moen01/regnskapskolen.git
cd regnskapskolen
./scripts/onboard.sh
```

Skriptet sjekker Xcode og Swift 6, ser etter Claude Code, bygger appen, legger den i `/Applications`, peker den på `Innhold/` i repoet (så oppgaver du eller Claude skriver, vises uten ny bygging) og åpner den. Andre kommandoer: `make test`, `make app`, `make run`, `make install`, `make icon`.

## Claude

Knappene *Forklar*, *Spør* og *Vanskeligere oppgave* bruker Claude Code på din egen maskin, med din egen innlogging. Appen trenger ingen API-nøkkel.

```sh
curl -fsSL https://claude.ai/install.sh | bash   # installer Claude Code
claude auth login                                # logg inn
```

Det som sendes er oppgaven, fasiten, svaret ditt, regelkortene for temaet og satsene fra `Innhold/satser.json`. Fremdriften din (`~/Library/Application Support/Regnskapsskolen/fremdrift.json`) sendes aldri. Detaljer i [docs/claude.md](docs/claude.md).

## Daglig bruk

- **I dag**: dagens sett. Riktig på første forsøk flytter oppgaven opp en boks; feil sender den til boks 0.
- **Øv**: alle temaer med mestringsgrad. Oppgaver her teller for boksene, ikke for dagens sett.
- **Sandkasse**: før en hel måned for en kafé, se saldobalanse, resultat og balanse, T-konto og mva-oppgjør, og sjekk mot fasiten.
- **Regler**: korte kort om lovene oppgavene bygger på, med lenker til Lovdata.
- **Statistikk**: rekke, bokser og mestring per tema.
- **Innstillinger**: påminnelse, antall oppgaver, Claude-modell, innholdsmappe, utkast.

## Legg til oppgaver med Claude Code

Åpne en `claude`-økt i repoet. Skillene i `.claude/skills/` kjenner formatet:

```
/ny-oppgave mva quiz 2 4        # to quizer om mva på nivå 4, validert
/kvalitetssjekk lonn            # sjekk lov og regnestykker i et tema
/forklar omvendt avgiftsplikt   # forklaring fra regelkortene
/sandkasse-case lonn 3          # en ny case til sandkassen
/ukens-tema                     # fem oppgaver i hvert av de to svakeste temaene dine
```

Nye oppgaver får `status: utkast` til et menneske har lest dem. Appen viser utkast når *Vis utkast* er på i Innstillinger. Formatet står i [docs/innhold.md](docs/innhold.md).

## Mappestruktur

| Sti | Innhold |
|---|---|
| `Innhold/oppgaver/<tema>/*.json` | Oppgavene, én fil per oppgave |
| `Innhold/regler/*.md` | Regelkortene |
| `Innhold/sandkasse/*.json` | Casene til sandkassen |
| `Innhold/satser.json` | Satser og frister med kilde og dato |
| `Innhold/kontoplan.json` | Kontoplanen (NS 4102-utvalg) |
| `Innhold/temaer.json` | Temaene og rekkefølgen |
| `Innhold/prompter/*.md` | Systempromptene til Claude |
| `Sources/RegnskapKit/` | Innhold, sjekkere, planlegger, sandkasse, Claude-kjører. Ingen UI. |
| `Sources/Regnskapsskolen/` | Appen (AppKit + SwiftUI) |
| `Tests/RegnskapKitTests/` | Tester, inkludert validering av alt innhold |
| `docs/` | Innholdsformat, Claude, lovkilder, tekniske notater |
| `.claude/skills/` | Skillene over |

## Lovkilder og satser

Alle lover, forskrifter og satser oppgavene bruker, står i [docs/regler.md](docs/regler.md) med lenker. Satsene i `Innhold/satser.json` ble sjekket 26.10.2026.

**Oppdatere satser**: endre tallet i `Innhold/satser.json`, oppdater `gjelderFra` og `kilde`, og kjør `swift test`. Fristoppgavene (`frist`) regnes ut fra reglene der, så filene kan ikke drifte fra satsene. Oppgavetekster som nevner et tall, finner du med `grep`.
