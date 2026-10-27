# Claude i Regnskapsskolen

Appen bruker [Claude Code](https://claude.com/claude-code) som en kommandolinje på brukerens egen maskin. Ingen API-nøkkel, ingen egen tjeneste: `claude` kjøres som en prosess med brukerens innlogging.

## Hva knappene gjør

| Knapp | Prompt | Skjema | Resultat |
|---|---|---|---|
| **Forklar** (etter feil svar) | `veileder` + oppgaven, fasiten, svaret og appens tilbakemelding | tekst | Maks 180 ord, vises under oppgaven |
| **Spør** | `veileder` + oppgaven + spørsmålet; oppfølging gjenbruker økten (`--resume`) | tekst | Maks 120 ord |
| **Vanskeligere oppgave** | `forfatter` + oppgaven; ber om samme type og tema, ett nivå opp | JSON-skjema for typen | Valideres som alt annet innhold, lagres som utkast og åpnes |
| **Lag en case med Claude** (sandkassen) | `sandkasse` + temaet | JSON-skjema for en case | Journalen må stemme med saldobalansen, ellers avvises den |

Systempromptene ligger i `Innhold/prompter/` og kan redigeres uten ny bygging. Til prompten legges regelkortene for temaet (`Innhold/regler/`, `tema:` i front matter) og satsene fra `Innhold/satser.json`, så Claude aldri trenger å huske en sats.

## Hva som sendes

Oppgaveteksten, fasiten, brukerens svar, appens tilbakemelding, regelkortene for temaet og satsene. Ikke noe annet: fremdriften (`fremdrift.json`), journalen i sandkassen og innstillingene forlater aldri maskinen. Modellen velges i Innstillinger (`sonnet` standard, `opus`, `haiku`).

## Kommandoen

```sh
claude -p "<prompt>" --output-format json --system-prompt "<prompt-fil + regelkort + satser>" \
  --tools "" --strict-mcp-config --model sonnet \
  [--json-schema '<skjema>'] [--resume <økt>] [--no-session-persistence]
```

- `--tools ""` og `--strict-mcp-config`: Claude får ingen verktøy og ingen MCP-servere. Svaret er tekst eller JSON.
- `--json-schema`: for oppgaver og caser; svaret dekodes som `Puzzle`/`SandboxCase` og kjøres gjennom validatoren.
- `--no-session-persistence` for alt unntatt *Spør*, som beholder økten så oppfølgingsspørsmål får sammenheng.
- Tidsavbrudd 120 sekunder. Arbeidsmappen er en tom mappe under `/tmp`, så Claude ikke ser repoet.

Appen finner `claude` på PATH fra brukerens innloggingsskall (`zsh -lic`), siden en app startet fra Finder bare har launchd sin PATH. Variabler en overordnet Claude Code-økt setter (`CLAUDECODE`, `CLAUDE_CODE_*`, …) fjernes før kjøring, ellers ville `claude` nekte å starte som en nøstet økt.

## Status og feil

Ved oppstart kjøres `claude auth status`. Tre tilstander: ikke installert (knapp som åpner Terminal med `curl -fsSL https://claude.ai/install.sh | bash`), ikke innlogget (`claude auth login`), klar (e-post og abonnement vises). Feil vises på norsk under oppgaven: ikke innlogget, tidsavbrudd, svar som ikke er gyldig JSON, oppgave som ikke besto validatoren (med hva som manglet).

## Hvor generert innhold havner

`Innhold/oppgaver/generert/<id>.json` og `Innhold/sandkasse/generert/<id>.json` i innholdsmappen fra Innstillinger. Er innholdsmappen kopien inne i appen (ingen mappe valgt i Innstillinger) eller kan den ikke skrives til, brukes `~/Library/Application Support/Regnskapsskolen/generert/`; appen skriver aldri inn i sin egen bundel. Alt der er `utkast`; les gjennom, flytt filen til riktig temamappe og sett `status: godkjent` når den holder mål.

## Testing

`ClaudeTests` kjører runneren mot en falsk prosess med et lagret svar. `REGNSKAP_LIVE=1 swift test --filter ClaudeLiveTests` gjør ett ekte kall (haiku) og krever innlogget `claude`.
