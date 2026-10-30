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
3. Appen er ad hoc-signert (inntil utgivelsene signeres med Developer ID), så macOS stopper den første gang med «Apple could not verify …». Trykk *Done*, åpne *Systeminnstillinger → Personvern og sikkerhet*, rull ned til meldingen om Regnskapsskolen og trykk *Åpne likevel*. Alternativ i Terminal: `xattr -dr com.apple.quarantine /Applications/Regnskapsskolen.app`. Oppdateringer appen installerer selv får ikke denne dialogen.
4. Finn bokikonet i menylinjen. Tallet er oppgavene som gjenstår i dag.
5. Gå gjennom oppsettet: når du vil minnes på, og om Claude skal brukes.
6. Appen sier fra i menylinjen når en ny versjon finnes; du trykker, den bytter seg selv ut og starter på nytt.

Krever macOS 15 eller nyere.

## Bygg selv

```sh
git clone https://github.com/Moen01/regnskapskolen.git
cd regnskapskolen
./scripts/onboard.sh
```

Skriptet sjekker Xcode og Swift 6, ser etter Claude Code, bygger appen, legger den i `/Applications`, peker den på `Innhold/` i repoet (så oppgaver du eller Claude skriver, vises uten ny bygging) og åpner den. Andre kommandoer: `make test`, `make app`, `make run`, `make install`, `make icon`.

## Oppdateringer

Appen sjekker nyeste utgivelse på GitHub 30 sekunder etter start og hver sjette time (kan slås av i Innstillinger). Finnes en nyere versjon, får du knappen **Oppdater til X.Y.Z** i menylinjen og **Oppdater og start på nytt** i Innstillinger → Oppdateringer, med utgivelsesnotatene under, og én varsling. Appen laster ned `Regnskapsskolen-<versjon>.zip` fra utgivelsen, pakker ut, kontrollerer signaturen (`codesign --verify`), bytter seg selv ut og starter på nytt. En app signert med Developer ID godtar bare en oppdatering fra samme Apple-team. En ad hoc-signert utgivelse (uten hemmelighetene under) kontrolleres bare for at bundelen er hel; Developer ID anbefales. Et lokalt bygg (`make app`, `make install`) er et utviklingsbygg og oppdaterer aldri seg selv.

Arbeid går i pull requests mot `staging`. En pull request `staging` → `main` som merges, blir en ny versjon av seg selv: workflowen **Release** bumper versjonen (patch; `#minor`/`#major` i merge-meldingen for mer), tagger, tester, bygger, signerer og notariserer når disse hemmelighetene finnes i repoet, og legger zip-en på utgivelsen. PR-beskrivelsen blir utgivelsesnotatet appen viser. Mer i `docs/releasing.md`.

| Hemmelighet | Hva det er |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Sertifikatet **Developer ID Application** med privat nøkkel, eksportert fra Nøkkelringtilgang som .p12 og base64-kodet (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_CERT_PASSWORD` | Passordet du satte ved eksporten |
| `NOTARY_KEY_P8` | En App Store Connect API-nøkkel (Users and Access → Integrations → Team Keys, rollen Developer); innholdet i .p8-fila |
| `NOTARY_KEY_ID` | Nøkkelens ID |
| `NOTARY_ISSUER_ID` | Issuer ID over nøkkellisten |

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
- **Spill**: *Debet & Kredit, Rubin-utgaven*. Spill åpner byen Hovedbok (bydelen Sentrum). Du går rundt med piltastene, møter klienter og fører bilagene deres. Hvert bilag er en oppgave, men dommen får du først når måneden lukkes; feil kommer tilbake som rettinger. Du lukker måneder, følger fristene i Fristnav, leverer mva-meldingen før fristen, tar en prøvesak for å få en ny klient, og møter fagkontoret for mva. Klienter med ansatte har også lønnsfrister: a-meldingen (den 5.), forskuddstrekket (første virkedag etter lønnsdagen) og arbeidsgiveravgiften per termin. Hver handling koster tid på kalenderen, og du kan sove til neste dag. Du har 100 energi, og hvert møte koster 5, enten du svarer rett eller galt. Er energien tom, besvimer du og våkner på kontoret neste morgen med full energi. Kaffemaskinen på kontoret gir én kopp om dagen (+30 energi), og koppen ligger i BAG til du drikker den. Noen kunder i Sentrum har en kundesak: du får svar og forklaring med en gang, og +5 fornøydhet hvis du svarer rett. Den tilbys bare én gang. En klient kan også oppdage en gammel feil selv (−15 fornøydhet); du retter den ved skranken med RETT FEIL. *Trening* i bymenyen er det gamle kartet, Paragrafjakten, beskrevet under. Alt du svarer teller i de samme Leitner-boksene som «I dag».
- **Paragrafjakten** (Trening): Tolv regioner, én per tema, låses opp etter hvert som du fanger skapningene i den forrige. En skapning er en oppgave: du velger først hvilken paragraf som gjelder (riktig regel gir dobbel uttelling), så svarer du. Riktig på første forsøk fanger den; den utvikler seg gjennom Leitner-boksene (Klekket, Ung, Voksen, Mester) og flykter hvis du bommer på en repetisjon. Feil svar koster kundens penger; er de brukt opp, er økten over. Hver region voktes av en gym-leder (temaets vanskeligste edge case), og «Reskontro og bank» har en dungeon: bankavstemmingen i sandkassen. Samlingen viser alt du har fanget med paragrafene på baksiden. Treningsplassene *Arena* (Lynrunde, 90 s) og *Dojo* (Debet eller kredit?, 60 s) gir poeng og rekorder, og *Ukens utfordring* er ti oppgaver som er like for alle, med en kode du kan dele. Alt teller i de samme boksene som «I dag», og gir XP, nivåer (Lærling til Partner) og merker. Ingen lyd. Paragrafjakten spilles på en Game Boy-skjerm: 160 × 144 piksler med Game Boy Color-farger per ting (gress, vann, tak, personer, skapninger per region), pikselfont, skrivemaskin-tekst i en dialogboks med seks linjer à 36 tegn og en kampskjerm der regelen er trekket og svaret er angrepet. Piltaster = D-pad, Enter = A, Esc = B, Tab blar dialogboksen; musen virker også. Spill er av som standard og skrus på i Innstillinger → Spill.
- **Sandkasse**: før en hel måned for en kafé eller en nettbutikk, se saldobalanse, resultat og balanse, T-konto og mva-oppgjør, avstem banken i Bank-fanen, og sjekk mot fasiten.
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
