"""Convertitore minimale da sintassi Adblock Plus / EasyList a regole WebKit (WKContentRuleList).

Converte solo il sottoinsieme che WebKit esegue in modo nativo ed efficiente:
- regole di rete ("||dominio^", "|https://", sottostringhe) con opzioni comuni;
- eccezioni "@@" (ignore-previous-rules);
- filtri cosmetici legati a un dominio ("dominio##selettore").
Scarta tutto il resto (regex, scriptlet, opzioni non supportate), in modo che la
compilazione WebKit non fallisca per una singola regola esotica.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

ALL_TYPES = ["document", "image", "style-sheet", "script", "font", "raw", "media", "ping"]

TYPE_MAP = {
    "script": "script",
    "image": "image",
    "stylesheet": "style-sheet",
    "css": "style-sheet",
    "font": "font",
    "media": "media",
    "xmlhttprequest": "raw",
    "xhr": "raw",
    "websocket": "raw",
    "other": "raw",
    "ping": "ping",
    "beacon": "ping",
    "subdocument": "document",
    "frame": "document",
}
# Tipi ignorati senza scartare la regola (WebKit non li distingue).
IGNORED_TYPES = {"object", "object-subrequest", "webrtc"}
# Opzioni neutre.
NEUTRAL_OPTIONS = {"important", "all"}
# Opzioni che rendono la regola non convertibile.
CSS_UNSUPPORTED = (
    ":-abp-", ":has-text", ":contains", ":xpath", ":upward", ":remove", ":style",
    ":matches-css", ":min-text-length", ":watch-attr", ":others", ":matches-path",
    ":matches-attr", ":matches-prop", ":if(", ":if-not", ":nth-ancestor", ":has(",
    "{", "}", "\\", "!important", ":is(", ":where(",
)

REGEX_SPECIAL = set(".+?()[]{}\\$|")
SEPARATOR = "[^a-zA-Z0-9_.%-]"
HOST_PREFIX = "^[^:]+://+([^/]+\\.)?"
MAX_SELECTORS_PER_RULE = 40

COSMETIC_RE = re.compile(r"^(?P<domains>[^/|@#\s]*?)(?P<sep>#@?[?$%]?#)(?P<body>.+)$")
OPTIONS_RE = re.compile(r"^[a-z0-9~_,=|.\-*:]+$", re.I)
DOMAIN_RE = re.compile(r"^[a-z0-9.-]+$")


@dataclass
class Result:
    blocks: list = field(default_factory=list)
    cosmetics: list = field(default_factory=list)
    exceptions: list = field(default_factory=list)
    skipped: int = 0


def _ascii(s: str) -> bool:
    return all(ord(c) < 128 for c in s)


def _parse_domains(raw: str, sep: str):
    pos, neg = [], []
    for d in raw.split(sep):
        d = d.strip().lower()
        if not d:
            continue
        target = neg if d.startswith("~") else pos
        d = d.lstrip("~")
        if d.endswith(".*") or not DOMAIN_RE.match(d):
            return None
        target.append("*" + d)
    return pos, neg


def pattern_to_regex(pattern: str) -> str | None:
    """Trasforma un pattern ABP in un url-filter compatibile con WebKit (niente |, niente {})."""
    host_anchor = pattern.startswith("||")
    start_anchor = not host_anchor and pattern.startswith("|")
    if host_anchor:
        pattern = pattern[2:]
    elif start_anchor:
        pattern = pattern[1:]
    end_anchor = pattern.endswith("|")
    if end_anchor:
        pattern = pattern[:-1]

    pattern = pattern.strip("*") if not host_anchor else pattern.rstrip("*")
    if not pattern or not _ascii(pattern):
        return None
    if len(pattern.replace("^", "").replace("*", "")) < 3:
        return None

    out = []
    for i, ch in enumerate(pattern):
        last = i == len(pattern) - 1
        if ch == "*":
            out.append(".*")
        elif ch == "^":
            if last:
                # Fine del dominio: dopo l'host c'è sempre ":" (porta) o "/".
                if host_anchor and "/" not in pattern:
                    out.append("[:/]")
                # Altrimenti si omette (lieve sovra-corrispondenza, nessuna perdita).
            else:
                out.append(SEPARATOR)
        elif ch in REGEX_SPECIAL:
            out.append("\\" + ch)
        else:
            out.append(ch)
    body = "".join(out)

    if host_anchor:
        body = HOST_PREFIX + body
    elif start_anchor:
        body = "^" + body
    if end_anchor:
        body += "$"
    return body


def _network(line: str, res: Result) -> None:
    exception = line.startswith("@@")
    if exception:
        line = line[2:]

    pattern, options = line, ""
    if "$" in line:
        idx = line.rfind("$")
        candidate = line[idx + 1:]
        if OPTIONS_RE.match(candidate):
            pattern, options = line[:idx], candidate

    if pattern.startswith("/") and pattern.endswith("/") and len(pattern) > 2:
        res.skipped += 1  # regex ABP: non convertibili in modo affidabile
        return

    trigger: dict = {}
    types: set[str] = set()
    negated_types: set[str] = set()
    whole_site = False

    for opt in filter(None, options.split(",")):
        key, _, value = opt.partition("=")
        key = key.lower()
        neg = key.startswith("~")
        name = key.lstrip("~")
        if name in ("third-party", "3p"):
            trigger["load-type"] = ["first-party" if neg else "third-party"]
        elif name in ("first-party", "1p"):
            trigger["load-type"] = ["third-party" if neg else "first-party"]
        elif name in ("domain", "from"):
            parsed = _parse_domains(value, "|")
            if parsed is None:
                res.skipped += 1
                return
            pos, negd = parsed
            if pos and negd:
                res.skipped += 1  # WebKit non combina if-domain e unless-domain
                return
            if pos:
                trigger["if-domain"] = pos
            if negd:
                trigger["unless-domain"] = negd
        elif name == "match-case":
            trigger["url-filter-is-case-sensitive"] = True
        elif name == "document" and exception:
            whole_site = True
        elif name in TYPE_MAP:
            (negated_types if neg else types).add(TYPE_MAP[name])
        elif name in IGNORED_TYPES or name in NEUTRAL_OPTIONS:
            continue
        else:
            res.skipped += 1  # popup, redirect, csp, removeparam, elemhide, ...
            return

    if whole_site:
        # @@||sito.it^$document → nessun blocco su quel sito.
        m = re.fullmatch(r"\|\|([a-z0-9.-]+)\^?", pattern, re.I)
        if not m:
            res.skipped += 1
            return
        res.exceptions.append({
            "trigger": {"url-filter": ".*", "if-domain": ["*" + m.group(1).lower()]},
            "action": {"type": "ignore-previous-rules"},
        })
        return

    regex = pattern_to_regex(pattern)
    if regex is None:
        res.skipped += 1
        return
    trigger = {"url-filter": regex, **trigger}

    if types or negated_types:
        chosen = types if types else set(ALL_TYPES) - negated_types
        if not chosen:
            res.skipped += 1
            return
        trigger["resource-type"] = sorted(chosen)

    rule = {"trigger": trigger, "action": {"type": "ignore-previous-rules" if exception else "block"}}
    (res.exceptions if exception else res.blocks).append(rule)


def convert(text: str, cosmetic: str = "specific") -> Result:
    """cosmetic: 'none' | 'specific' (solo filtri legati a un dominio)."""
    res = Result()
    lines = [l.strip() for l in text.splitlines()]

    # $badfilter annulla la regola identica senza l'opzione.
    bad = set()
    for l in lines:
        if "badfilter" in l and "$" in l:
            bad.add(re.sub(r"[$,]badfilter", "", l).rstrip("$,"))

    specific: dict[tuple, list] = {}
    for line in lines:
        if not line or line[0] in "![" or line in bad or "badfilter" in line:
            continue
        m = COSMETIC_RE.match(line)
        if m:
            if m.group("sep") != "##" or cosmetic == "none":
                res.skipped += 1
                continue
            sel, domains = m.group("body").strip(), m.group("domains")
            if not domains or not _ascii(sel) or any(t in sel for t in CSS_UNSUPPORTED) or sel.startswith("+js"):
                res.skipped += 1
                continue
            parsed = _parse_domains(domains, ",")
            if parsed is None or parsed[1] or not parsed[0]:
                res.skipped += 1
                continue
            specific.setdefault(tuple(sorted(parsed[0])), []).append(sel)
            continue
        if "#" in line and ("##" in line or "#@#" in line):
            res.skipped += 1
            continue
        _network(line, res)

    for domains, selectors in specific.items():
        uniq = list(dict.fromkeys(selectors))
        for i in range(0, len(uniq), MAX_SELECTORS_PER_RULE):
            res.cosmetics.append({
                "trigger": {"url-filter": ".*", "if-domain": list(domains)},
                "action": {"type": "css-display-none", "selector": ", ".join(uniq[i:i + MAX_SELECTORS_PER_RULE])},
            })

    res.blocks = _dedupe(res.blocks)
    res.exceptions = _dedupe(res.exceptions)
    return res


def _dedupe(rules: list) -> list:
    import json
    seen, out = set(), []
    for r in rules:
        k = json.dumps(r, sort_keys=True)
        if k not in seen:
            seen.add(k)
            out.append(r)
    return out


def chunk(res: Result, max_rules: int) -> list[list]:
    """Divide in liste ≤ max_rules. Le eccezioni sono ripetute in coda a ogni lista,
    perché in WebKit ignore-previous-rules agisce solo dentro la stessa lista."""
    body = res.blocks + res.cosmetics
    room = max_rules - len(res.exceptions)
    if room < 1000:
        raise ValueError("troppe eccezioni per max_rules")
    if not body:
        return []
    return [body[i:i + room] + res.exceptions for i in range(0, len(body), room)]
