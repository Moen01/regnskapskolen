#!/bin/zsh
# Bygger en release-binær og pakker den som build/Regnskapsskolen.app (ad hoc-signert).
# APP_VERSION=1.2.0 setter versjonen (en utgivelse); uten den er bygget et utviklingsbygg: versjon
# «<siste tag>-dev» og flagget RegnskapsskolenDevBuild i Info.plist, så appen aldri bytter seg selv ut
# med en utgivelse. SIGN_IDENTITY signerer for distribusjon.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Regnskapsskolen.app"

swift build -c "$CONFIG" --product Regnskapsskolen
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Regnskapsskolen"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Regnskapsskolen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
VERSION="${APP_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.1.0)}"
if [[ -z "${APP_VERSION:-}" ]]; then
  VERSION="${VERSION}-dev"
  /usr/libexec/PlistBuddy -c "Add :RegnskapsskolenDevBuild bool true" "$APP/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Innholdet følger med i appen, som reserve når innholdsmappen i Innstillinger ikke finnes.
cp -R Innhold "$APP/Contents/Resources/Innhold"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements Resources/Regnskapsskolen.entitlements --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - --timestamp=none --entitlements Resources/Regnskapsskolen.entitlements "$APP"
fi
echo "Bygde $APP ($VERSION)"
