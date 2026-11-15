#!/usr/bin/env bash
# Preparazione comune ai job iOS (runner macOS):
# test → pacchetto filtri verificato con WebKit → configurazione aggiornamenti → progetto Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "::group::Test strumenti filtri"
python3 -c "import cryptography" 2>/dev/null || \
  python3 -m pip install --quiet --break-system-packages cryptography || \
  python3 -m pip install --quiet cryptography || true
python3 -m unittest discover -s filters/tests
node filters/tests/media-bridge.test.mjs
echo "::endgroup::"

KEYFILE=""
if [ -n "${FILTERS_SIGNING_KEY:-}" ]; then
  KEYFILE="${RUNNER_TEMP:-/tmp}/filters-key.pem"
  printf '%s\n' "$FILTERS_SIGNING_KEY" > "$KEYFILE"
  PUB="$(python3 filters/tools/build_pack.py pubkey --key "$KEYFILE")"
  {
    echo "LIEVE_FILTERS_PUBKEY=$PUB"
    echo "LIEVE_FILTERS_URL=https://github.com/${GITHUB_REPOSITORY}/releases/download/filters/pack.lvp"
  } >> "${GITHUB_ENV:-/dev/null}"
  echo "Aggiornamenti filtri attivi (chiave pubblica $PUB)"
else
  echo "::notice::FILTERS_SIGNING_KEY non impostato: l'app userà solo i filtri inclusi."
fi

echo "::group::Pacchetto filtri incluso nell'app"
bash filters/tools/make_pack.sh Lieve/Resources/FilterPack.lvp $KEYFILE
rm -f Lieve/Resources/FilterPack.lvp.hash
[ -n "$KEYFILE" ] && rm -f "$KEYFILE"
node filters/tests/scripts.test.mjs Lieve/Resources/FilterPack.lvp
echo "::endgroup::"

echo "::group::Generazione progetto"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
echo "::endgroup::"
