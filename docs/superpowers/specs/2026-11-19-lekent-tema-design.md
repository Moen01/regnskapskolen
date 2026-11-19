# Lekent tema (Catacloud) — design

Dato: 2026-11-19. Status: utkast til godkjenning.

## Hensikt og hvorfor

Appen utenfor spillet oppleves statisk og nøktern (standard macOS-utseende). Andreas vil at
den skal være morsommere og mindre statisk, med Catacloud-identitet — uten å røre spilldelene,
som har sitt eget Game Boy-uttrykk. Utseendet skal kunne slås av og på i innstillingene.

## Mål

- Et «lekent tema» som gir ikke-spill-skjermene Catacloud sin varme premium-drakt
  (varm off-white bakgrunn, store runde kort, myke skygger, varm aksentblå).
- En egen figur, **Regnskapsføreren**: geometrisk flat fyr i blå dress med gult slips og
  koffert (valgt variant A1 i mockupene), tegnet i SwiftUI-kode, med flere positurer.
- Feiring på nivå «middels»: konfetti og jublende figur når dagens økt fullføres og på
  streak-milepæler; myke inn-animasjoner, hover-løft og fjæranimerte mestringsbarer ellers.
- Bryter i generelle innstillinger. Virker umiddelbart, uten omstart.

## Ikke-mål

- Spill-UI (`Sources/Regnskapsskolen/UI/Game/`) røres ikke. Game Boy-drakten består.
- Ingen endring i RegnskapKit — dette er ren UI (kit importerer aldri SwiftUI).
- Ingen nye avhengigheter, ingen bildefiler/fonter bundles. Alt tegnes i kode, systemfont brukes.
- Ingen lyd.

## Anti-mål

- Masete: konfetti ved hvert riktige svar, popups overalt (nivå «full fest» ble valgt bort).
- En halvveis drakt: hvis temaet er på, skal alle ikke-spill-skjermer følge det — ikke bare noen.
- Å ødelegge standardutseendet: med bryteren av skal appen se nøyaktig ut som i dag.

## Begrensninger

- macOS-app, SwiftUI. Kit/UI-skillet i repoet er absolutt.
- Brukertekst på norsk bokmål; kode og kommentarer på engelsk.
- Innstillinger persisteres i UserDefaults via `AppSettings`-mønsteret som finnes
  (`Sources/Regnskapsskolen/App/AppSettings.swift`).
- Animasjoner skal respektere systeminnstillingen «Reduser bevegelse»
  (`accessibilityReduceMotion`): da spilles ikke konfetti/sprett, bare enkle fades.

## Vurderte tilnærminger

1. **Inline-betingelser per view** — `if settings.playfulTheme` spredt i ~10 filer.
   Raskt i gang, uvedlikeholdbart. Forkastet.
2. **Temaobjekt i environment + semantiske modifiers** — én `AppTheme`-struct med tokens,
   to instanser (`standard`, `playful`), injisert via `@Environment`; views bruker
   semantiske modifiers (`.themedCard()` osv.). Én ærlig refaktorering, deretter bor hele
   utseendet i én fil. **Valgt av Andreas.**
3. **Global fargeswap** — `Color.skole` m.fl. blir computed properties som leser flagget.
   Minimal diff, men dekker bare farger; former, skygger, figur og bevegelse er mesteparten
   av jobben. Forkastet.

## Beslutningene (slik de ble tatt)

Valgt i visuell mockup-runde med Andreas:

- **Figur:** variant A1 — geometrisk flat regnskapsfører, blå dress, gult slips, koffert,
  rund frisyre, enkelt smil. Ikke katt, ikke maskotdyr.
- **Drakt:** «Catacloud premium (varm)» — retningen fra catacloud-web sine start-tokens,
  ikke dagens Bootstrap-aktige webutseende.
- **Feiringsnivå:** middels (nivå 2 av 3).

## Draktens tokens (lekent tema)

Hentet fra catacloud-web (`_start-tokens.scss`, `_variables.scss`):

| Token | Verdi (lys) |
|---|---|
| Skjermbakgrunn | `#f7f5f2` |
| Kortbakgrunn | `#ffffff`, hjørneradius 20 pt |
| Kortskygge | `0 1px 3px rgba(0,0,0,0.04)` + `0 6px 24px rgba(0,0,0,0.04)` |
| Aksent (knapper, lenker, tint) | `#4a5e9e` |
| Tekst | `#2c2a26`, sekundær `#6b6760` |
| Suksess | `#3CBF9C` (tekstvariant `#2a8a70`) |
| Feil | `#F85C5C` (tekstvariant `#c04848`) |
| Advarsel | `#f5b04d` |
| Piller | kapselform, 10 % tint av egen farge, som i dag men varmere palett |
| Debet / kredit | beholder dagens semantikk, justert mot paletten: debet `#4a5e9e`, kredit `#f5b04d`-mørknet for kontrast (builder finjusterer mot WCAG-kontrast) |
| Overskrifter | systemfont med `.fontDesign(.rounded)` og tyngre vekt (mitt valg) |
| Knapper | aksentfarge, radius 10 pt, hvit tekst |

**Mørk modus (mitt valg):** det lekne temaet får varme mørke varianter i stedet for å falle
tilbake til standard: bakgrunn `#26241f`, kort `#32302a`, tekst `#f7f5f2`, aksent lysnet
`#7a8fc4`, status-fargene beholdes. Builder finjusterer kontrast. Standardtemaet bruker
systemmaterialer som i dag og påvirkes ikke.

## Arkitektur (hvordan, slik det ble besluttet)

- **`AppTheme`** (ny, i `Sources/Regnskapsskolen/UI/Components/Theme.swift` eller nabo-fil):
  struct med tokens over + `celebrationsEnabled: Bool`. To statiske instanser:
  `.standard` (reproduserer dagens utseende eksakt — systemmaterialer, dagens farger fra
  `Theme.swift`, radius 10, ingen figur/konfetti) og `.playful`.
- **Environment:** egen nøkkel `\.appTheme`. Settes på rotviews (`MainView`, `PopoverView`,
  `SettingsView`-scenen) fra `store.settings.playfulTheme`.
- **Semantiske modifiers/komponenter:** `.themedScreenBackground()`, `.themedCard()`,
  `.themedPrimaryButton()`; eksisterende `Pill` og `SectionHeader` leser temaet.
  Refaktoreringspasset bytter rå styling (`.background(.quaternary…)`, `.tint(.skole)` osv.)
  mot disse i ikke-spill-views.
- **Innstilling:** `playfulTheme: Bool` i `AppSettings` (UserDefaults-nøkkel `"tema.lekent"`),
  toggle i `SettingsView` i ny seksjon «Utseende»: «Lekent tema (Catacloud)» med
  caption-forklaring. **Standardverdi: PÅ** (mitt valg — hele poenget med featuren er å se
  den; bryteren finnes for å slå av).
- **Regnskapsføreren:** `AccountantFigure`-view tegnet med SwiftUI `Path`/shapes,
  parametrisert på positur: `.standing`, `.celebrating` (armene opp), `.thinking`
  (builder kan slå sammen/utvide). Vises kun når lekent tema er på.
- **Konfetti:** `ConfettiView` med `TimelineView` + `Canvas`, partikler i palettens farger
  (`#F85C5C`, `#f5b04d`, `#3CBF9C`, `#4a5e9e`, `#ED4A7B`). Engangs-burst, ~2 s, deretter
  fjernes viewet. Ingen avhengighet.

## Hvor det lekne vises (omfang)

Alle ikke-spill-skjermer: `PopoverView` (menylinja), `TodayView`, `TopicsView`, `PuzzleView`,
`SandboxView`, `RulesView`, `StatsView`, `SettingsView`, `MainView` (sidepanelet),
`OnboardingView` (arket) og innholdsvarsel-overlegget i `MainView`.
`GameHubView` og alt under `UI/Game/` røres ikke.

**Systemstylede containere — full ombygging (valgt av Andreas):** når temaet er på, bygges
`SettingsView` sine Form-seksjoner som egne hvite 20 pt-kort på varm bakgrunn, og sidepanelet
får egne radrekker (avrundet aksent-markering) i stedet for systemutseendet. Når temaet er av,
brukes dagens `Form`/`List` urørt — begge stier må finnes, og standardstien skal være
piksellik dagens app.

Figuren dukker opp:
- Tomme tilstander: dagens økt ferdig («alt gjort»-tilstand i Today/popover), tomt søk i regler.
- Feiringsoverlegg: jublende positur + konfetti når dagens økt fullføres og på
  streak-milepæler 7, 30 og 100 dager.
- Hilsen i popoveren (stillestående figur ved siden av dagens status).

Feiring nivå «middels», presist:
- Konfetti + jublende figur: kun fullført dagsøkt og streak-milepæler.
- **Fullført inne i spillet (mitt valg):** `AppStore.record()` kalles også fra spillflytene
  (Lynrunden, Debet/kredit, byen), så dagen kan bli ferdig mens brukeren står i Game Boy-UI-et.
  Da vises ingen feiring der; et ventende-feiring-flagg settes, og overlegget spilles når
  brukeren neste gang lander på en ikke-spill-skjerm (hovedvinduets innhold eller popoveren,
  aldri innstillingsvinduet). Om flagget overlever appomstart, avgjør builderen.
- **Milepæl-logikk (mitt valg):** milepælene 7/30/100 beregnes i appen fra `store.streak`
  i overgangen til «dagen er ferdig» — ikke fra `Badges` (kit røres ikke, og merkene for
  7/30 deles ut én gang per liv). Feiringen er øyeblikkets: en gjenoppbygd streak som når 7
  igjen, feires igjen. Ingen feiring ved appstart (kun overgangsdeteksjon).
- Riktig svar: liten sprett/skala-animasjon på svar-kortet og tegnet hake — ikke konfetti.
- Mestringsbarer (Øv/Stats): fylles med fjæranimasjon når de kommer til syne.
- Kort: løfter seg svakt ved hover (skygge + 1–2 pt translate).
- Skjermbytte: innhold glir inn med fade/slide 0,3 s ease-out.
- Alt over: av når `accessibilityReduceMotion` er på (enkel fade beholdes), og av i sin
  helhet når temaet er av.

## Overlatt til builderen

- Eksakt filinndeling (én `Theme.swift` eller `Theme.swift` + `AppTheme.swift` + figur/konfetti-filer).
- Finjustering av mørk-modus-verdier og debet/kredit-kontrast (WCAG AA mot kortbakgrunn).
- Figurens eksakte geometri utover mockupen (HTML-mockupene med innebygde SVG-er i
  `.superpowers/brainstorm/31107-1795080723/content/` — særlig `figur-regnskapsforer.html`,
  variant A1 — er referanse for proporsjoner og farger).
- Hvordan `REGNSKAP_SCREENSHOTS`-kjøringen dekker begge temaer (gjerne begge varianter av
  et par nøkkelskjermer).
- Rekkefølgen på refaktoreringen av views.

## Verifikasjon

- `swift test` grønt (ingen kit-endringer forventet; validatortester upåvirket).
- Manuelt: bryter av → appen ser ut som i dag; bryter på → drakten over alt i ikke-spill;
  av/på virker uten omstart; Reduser bevegelse respekteres; spillet uendret i begge stillinger.
