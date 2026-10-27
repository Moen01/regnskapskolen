#!/bin/zsh
# Setter opp Regnskapsskolen på denne maskinen: sjekker verktøyene, bygger appen, legger den i
# /Applications, peker den på innholdet i dette repoet og åpner den.
#   ./scripts/onboard.sh            vanlig kjøring
#   ./scripts/onboard.sh --no-open  alt unntatt å åpne appen
set -euo pipefail
cd "$(dirname "$0")/.."
OPEN=1
[[ "${1:-}" == "--no-open" ]] && OPEN=0

say() { print -- "▸ $*" }

if ! xcode-select -p >/dev/null 2>&1; then
  print "Xcode Command Line Tools mangler. Kjør: xcode-select --install"
  exit 1
fi
SWIFT_MAJOR="$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+' | grep -oE '[0-9]+$' || print 0)"
if (( SWIFT_MAJOR < 6 )); then
  print "Swift 6 eller nyere kreves (fant ${SWIFT_MAJOR:-ingen}). Oppdater Xcode eller Command Line Tools."
  exit 1
fi
say "Swift $SWIFT_MAJOR funnet."

if command -v claude >/dev/null 2>&1; then
  if claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
    say "Claude Code er installert og innlogget. Forklar, Spør og Vanskeligere oppgave virker."
  else
    say "Claude Code er installert, men ikke innlogget. Logg inn når du vil: claude auth login"
  fi
else
  say "Claude Code er ikke installert. Appen virker uten, men Forklar og Spør trenger den. Installer med:"
  print "    curl -fsSL https://claude.ai/install.sh | bash"
fi

say "Bygger appen og legger den i /Applications (tar et minutt første gang) …"
make install

defaults write no.catacloud.regnskapsskolen innholdMappe "$PWD/Innhold"
say "Appen leser innholdet fra $PWD/Innhold. Oppgaver du eller Claude skriver dit, vises uten ny bygging."

if (( OPEN )); then
  open /Applications/Regnskapsskolen.app
  say "Appen er åpnet. Se etter bokikonet i menylinjen; første gang får du en kort oppsettsdialog."
else
  say "Ferdig. Åpne /Applications/Regnskapsskolen.app når du vil."
fi
