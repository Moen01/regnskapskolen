#!/bin/zsh
# Notariserer en Developer ID-signert build/Regnskapsskolen.app, stifter billetten og zipper den for utgivelse.
# Trenger en App Store Connect API-nøkkel: NOTARY_KEY (sti til .p8), NOTARY_KEY_ID, NOTARY_ISSUER_ID.
# Bruk: scripts/notarize.sh Regnskapsskolen-0.2.0.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Regnskapsskolen.app"
OUT="${1:?zip-navn, f.eks. Regnskapsskolen-0.2.0.zip}"
SUBMIT="build/notarize-submit.zip"

ditto -c -k --keepParent "$APP" "$SUBMIT"
xcrun notarytool submit "$SUBMIT" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
  --wait --timeout 30m --output-format json | tee build/notarize-result.json
if ! grep -q '"status" *: *"Accepted"' build/notarize-result.json; then
  ID=$(python3 -c 'import json; print(json.load(open("build/notarize-result.json"))["id"])')
  xcrun notarytool log "$ID" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
  exit 1
fi
rm "$SUBMIT"

# Billetten går inn i bundelen, så Gatekeeper godtar den også uten nett. Zip først etter stifting.
xcrun stapler staple "$APP"
spctl --assess --type execute -vv "$APP"
ditto -c -k --keepParent "$APP" "$OUT"
echo "Notarisert $OUT"
