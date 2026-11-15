#!/usr/bin/env bash
# Costruisce il pacchetto filtri verificato con il compilatore WebKit reale (richiede macOS).
# Uso: filters/tools/make_pack.sh <output.lvp> [chiave-ed25519.pem]
set -euo pipefail
OUT="$1"
KEY="${2:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== 1/3 Costruzione preliminare"
python3 "$DIR/build_pack.py" build --out "$WORK/draft.lvp" --cache "$WORK/cache"

echo "== 2/3 Verifica con WebKit"
swift "$DIR/check_rules.swift" "$WORK/draft.lvp" "$WORK/bad.json"

echo "== 3/3 Pacchetto finale"
ARGS=(build --out "$OUT" --cache "$WORK/cache" --from-cache --exclude "$WORK/bad.json")
[ -n "$KEY" ] && ARGS+=(--key "$KEY")
python3 "$DIR/build_pack.py" "${ARGS[@]}"
