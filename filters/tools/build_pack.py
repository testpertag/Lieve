#!/usr/bin/env python3
"""Costruisce il pacchetto filtri di Lieve (.lvp).

Formato file:  b"LVP1" | firma Ed25519 (64 byte, zeri se non firmato) | payload DEFLATE grezzo
Payload (JSON):
  { "format": 1, "version": int, "contentHash": str,
    "ruleLists": [ { "id", "hash", "critical", "json" } ],
    "scripts":   [ { "id", "world", "source" } ] }

Uso:
  build_pack.py build  --out dist/pack.lvp [--key chiave.pem] [--offline] [--cache dir]
                       [--from-cache] [--exclude bad-rules.json]
  build_pack.py pubkey --key chiave.pem          # chiave pubblica grezza in Base64
  build_pack.py verify --pack dist/pack.lvp [--pubkey BASE64]
Solo libreria standard + openssl a riga di comando (per la firma).
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import abp2webkit  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MAGIC = b"LVP1"
SIG_LEN = 64
CFG_TOKEN = "__LIEVE_CFG__"


# --------------------------------------------------------------------------- utilità

def canonical(obj) -> str:
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=True, sort_keys=False)


def short_hash(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def deflate_raw(data: bytes) -> bytes:
    c = zlib.compressobj(9, zlib.DEFLATED, -15)  # DEFLATE grezzo: è ciò che si aspetta NSData .zlib
    return c.compress(data) + c.flush()


def inflate_raw(data: bytes) -> bytes:
    return zlib.decompress(data, -15)


def host_guard(hosts: list[str]) -> str:
    alts = "|".join(re.escape(h) for h in hosts)
    return f"/(^|\\.)({alts})$/"


def wrap_script(source: str, hosts: list[str]) -> str:
    """Avvolge lo script: controllo del dominio + configurazione iniettata dall'app."""
    guard = host_guard(hosts)
    return (
        "(function (LIEVE) {\n"
        f"if (!{guard}.test(location.hostname)) return;\n"
        f"{source}\n"
        f"}})({CFG_TOKEN});\n"
    )


# --------------------------------------------------------------------------- liste remote

def fetch(url: str, cache: Path | None, from_cache: bool = False) -> str | None:
    cached = cache / (re.sub(r"[^a-z0-9]+", "_", url.lower()) + ".txt") if cache else None
    if from_cache:
        return cached.read_text() if cached and cached.exists() else None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Lieve-filter-builder"})
        with urllib.request.urlopen(req, timeout=60) as r:
            text = r.read().decode("utf-8", "replace")
        if cached:
            cached.parent.mkdir(parents=True, exist_ok=True)
            cached.write_text(text)
        return text
    except Exception as e:  # rete assente: si usa la cache se c'è
        print(f"  ! download fallito {url}: {e}", file=sys.stderr)
        if cached and cached.exists():
            return cached.read_text()
        return None


# --------------------------------------------------------------------------- build

def build_payload(offline: bool, cache: Path | None, exclude: dict | None = None,
                  from_cache: bool = False) -> dict:
    """exclude: { idLista: [indici] } prodotto da check_rules.swift (regole rifiutate da WebKit)."""
    exclude = exclude or {}
    manifest = json.loads((ROOT / "pack.json").read_text())
    if manifest.get("format") != 1:
        raise SystemExit("format non supportato")
    max_rules = int(manifest.get("maxRulesPerList", 40000))

    rule_lists = []
    for entry in manifest["ruleLists"]:
        rules = json.loads((ROOT / entry["file"]).read_text())
        validate_rules(rules, entry["id"])
        text = canonical(rules)
        rule_lists.append({"id": entry["id"], "hash": short_hash(text),
                           "critical": bool(entry.get("critical")), "json": text})
        print(f"  {entry['id']}: {len(rules)} regole")

    if not offline:
        for remote in manifest.get("remoteLists", []):
            text = fetch(remote["url"], cache, from_cache)
            if text is None:
                continue
            res = abp2webkit.convert(text, remote.get("cosmetic", "specific"))
            # Le liste generiche non agiscono sulle pagine YouTube né sulle sue risorse:
            # alcune loro regole (es. /api/stats/qoe in EasyPrivacy) bloccano l'avvio dei video.
            for domain in manifest.get("remoteListsExcludedDomains", []):
                res.exceptions.append({"trigger": {"url-filter": ".*", "if-domain": ["*" + domain]},
                                       "action": {"type": "ignore-previous-rules"}})
                res.exceptions.append({"trigger": {"url-filter": abp2webkit.HOST_PREFIX + domain.replace(".", "\\.") + "[:/]"},
                                       "action": {"type": "ignore-previous-rules"}})
            chunks = abp2webkit.chunk(res, max_rules)
            print(f"  {remote['id']}: {len(res.blocks)} blocchi, {len(res.cosmetics)} cosmetici, "
                  f"{len(res.exceptions)} eccezioni, {res.skipped} scartate → {len(chunks)} liste")
            for i, rules in enumerate(chunks, 1):
                drop = set(exclude.get(f"{remote['id']}-{i}", []))
                if drop:
                    rules = [r for j, r in enumerate(rules) if j not in drop]
                    print(f"    {remote['id']}-{i}: escluse {len(drop)} regole rifiutate da WebKit")
                validate_rules(rules, f"{remote['id']}-{i}")
                text = canonical(rules)
                rule_lists.append({"id": f"{remote['id']}-{i}", "hash": short_hash(text),
                                   "critical": False, "json": text})

    scripts = []
    for s in manifest["scripts"]:
        if s["world"] not in ("page", "lieve"):
            raise SystemExit(f"world non valido per {s['id']}")
        src = (ROOT / s["file"]).read_text()
        scripts.append({"id": s["id"], "world": s["world"], "source": wrap_script(src, s["hosts"])})

    content = canonical({"ruleLists": rule_lists, "scripts": scripts})
    return {
        "format": 1,
        "version": int(time.strftime("%Y%m%d%H%M", time.gmtime())),
        "contentHash": hashlib.sha256(content.encode()).hexdigest(),
        "ruleLists": rule_lists,
        "scripts": scripts,
    }


ALLOWED_ACTIONS = {"block", "css-display-none", "ignore-previous-rules"}


def validate_rules(rules: list, name: str) -> None:
    """Controlli sui vincoli noti del compilatore WebKit."""
    if not isinstance(rules, list) or not rules:
        raise SystemExit(f"{name}: lista vuota o non valida")
    if len(rules) > 150000:
        raise SystemExit(f"{name}: oltre il limite WebKit di 150000 regole")
    for r in rules:
        t, a = r.get("trigger", {}), r.get("action", {})
        uf = t.get("url-filter")
        if not isinstance(uf, str) or not uf:
            raise SystemExit(f"{name}: url-filter mancante: {r}")
        if "|" in uf or "{" in uf or not uf.isascii():
            raise SystemExit(f"{name}: url-filter non supportato da WebKit: {uf}")
        re.compile(uf)
        if "if-domain" in t and "unless-domain" in t:
            raise SystemExit(f"{name}: if-domain e unless-domain insieme: {r}")
        if a.get("type") not in ALLOWED_ACTIONS:
            raise SystemExit(f"{name}: azione non ammessa: {r}")
        if a["type"] == "css-display-none" and not a.get("selector"):
            raise SystemExit(f"{name}: selettore mancante: {r}")


# --------------------------------------------------------------------------- firma

def sign(payload: bytes, key: Path) -> bytes:
    with tempfile.TemporaryDirectory() as d:
        src, out = Path(d, "p"), Path(d, "s")
        src.write_bytes(payload)
        subprocess.run(["openssl", "pkeyutl", "-sign", "-inkey", str(key), "-rawin",
                        "-in", str(src), "-out", str(out)], check=True)
        sig = out.read_bytes()
    if len(sig) != SIG_LEN:
        raise SystemExit("firma Ed25519 di lunghezza inattesa: la chiave è ed25519?")
    return sig


def public_key_b64(key: Path) -> str:
    der = subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-outform", "DER"],
                         check=True, capture_output=True).stdout
    return base64.b64encode(der[-32:]).decode()


def write_pack(payload: dict, out: Path, key: Path | None) -> None:
    raw = canonical(payload).encode()
    body = deflate_raw(raw)
    sig = sign(body, key) if key else bytes(SIG_LEN)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(MAGIC + sig + body)
    out.with_suffix(out.suffix + ".hash").write_text(payload["contentHash"] + "\n")
    print(f"→ {out} ({len(raw) // 1024} KB JSON, {len(body) // 1024} KB compresso, "
          f"versione {payload['version']}, {'firmato' if key else 'NON firmato'})")


def read_pack(path: Path, pubkey_b64: str | None = None) -> dict:
    data = path.read_bytes()
    if data[:4] != MAGIC:
        raise SystemExit("file non riconosciuto")
    sig, body = data[4:4 + SIG_LEN], data[4 + SIG_LEN:]
    if pubkey_b64:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        Ed25519PublicKey.from_public_bytes(base64.b64decode(pubkey_b64)).verify(sig, body)
    return json.loads(inflate_raw(body))


# --------------------------------------------------------------------------- CLI

def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--out", type=Path, required=True)
    b.add_argument("--key", type=Path)
    b.add_argument("--offline", action="store_true")
    b.add_argument("--cache", type=Path)
    b.add_argument("--from-cache", action="store_true", help="usa solo le liste già scaricate")
    b.add_argument("--exclude", type=Path, help="JSON di check_rules.swift")
    p = sub.add_parser("pubkey")
    p.add_argument("--key", type=Path, required=True)
    v = sub.add_parser("verify")
    v.add_argument("--pack", type=Path, required=True)
    v.add_argument("--pubkey")
    args = ap.parse_args()

    if args.cmd == "build":
        exclude = json.loads(args.exclude.read_text()) if args.exclude else None
        write_pack(build_payload(args.offline, args.cache, exclude, args.from_cache), args.out, args.key)
    elif args.cmd == "pubkey":
        print(public_key_b64(args.key))
    elif args.cmd == "verify":
        pack = read_pack(args.pack, args.pubkey)
        print(f"OK versione {pack['version']}, {len(pack['ruleLists'])} liste, {len(pack['scripts'])} script")


if __name__ == "__main__":
    main()
