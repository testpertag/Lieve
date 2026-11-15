"""Test del convertitore e del formato pacchetto. Uso: python3 -m unittest discover filters/tests"""
import base64
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import abp2webkit as a  # noqa: E402
import build_pack as b  # noqa: E402

SAMPLE = r"""
[Adblock Plus 2.0]
! commento
||ads.example.com^
||tracker.net^$third-party
||cdn.site.com/ads/*.js$script,domain=site.com|other.org
/banner/ad_
|https://pixel.
@@||ads.example.com/allowed.js
@@||goodsite.org^$document
example.com##.ad-box
example.com,foo.org###sidebar-ad
~example.com##.generic
##.global-ad
example.com##+js(set, x, 1)
example.com##div:has-text(Sponsor)
||bad.com^$popup
||regex.com^$redirect=noop.js
/^https?:\/\/regex/
||mixed.com^$domain=a.com|~b.com
||neg.com^$~script
||dup.com^
||dup.com^
||cancel.com^
||cancel.com^$badfilter
||ünicode.com^
"""


def matches(rule, url):
    return re.search(rule["trigger"]["url-filter"], url, re.I) is not None


class ConverterTests(unittest.TestCase):
    def setUp(self):
        self.res = a.convert(SAMPLE, "specific")
        self.filters = [r["trigger"]["url-filter"] for r in self.res.blocks]

    def find(self, needle):
        return next(r for r in self.res.blocks if needle in r["trigger"]["url-filter"])

    def test_host_anchor(self):
        r = self.find("ads\\.example")
        self.assertTrue(matches(r, "https://ads.example.com/x.js"))
        self.assertTrue(matches(r, "https://sub.ads.example.com/"))
        self.assertTrue(matches(r, "https://ads.example.com:8080/"))
        self.assertFalse(matches(r, "https://notads.example.com.evil/"))
        self.assertFalse(matches(r, "https://ads.example.community/"))

    def test_options(self):
        r = self.find("tracker")
        self.assertEqual(r["trigger"]["load-type"], ["third-party"])
        r = self.find("cdn\\.site")
        self.assertEqual(r["trigger"]["resource-type"], ["script"])
        self.assertEqual(r["trigger"]["if-domain"], ["*site.com", "*other.org"])
        self.assertTrue(matches(r, "https://cdn.site.com/ads/x/y.js"))
        r = self.find("neg\\.com")
        self.assertNotIn("script", r["trigger"]["resource-type"])

    def test_substring_and_start_anchor(self):
        self.assertTrue(matches(self.find("banner"), "https://x.com/banner/ad_1.png"))
        r = self.find("pixel")
        self.assertTrue(r["trigger"]["url-filter"].startswith("^https://pixel"))

    def test_skipped(self):
        joined = " ".join(self.filters)
        for bad in ("bad\\.com", "regex\\.com", "mixed\\.com", "cancel\\.com", "regex"):
            self.assertNotIn(bad, joined)
        self.assertEqual(sum("dup\\.com" in f for f in self.filters), 1)
        self.assertFalse(any(not f.isascii() for f in self.filters))

    def test_exceptions(self):
        kinds = [e["trigger"] for e in self.res.exceptions]
        self.assertIn({"url-filter": ".*", "if-domain": ["*goodsite.org"]}, kinds)
        self.assertTrue(any("allowed\\.js" in k["url-filter"] for k in kinds))

    def test_cosmetics(self):
        sels = {tuple(r["trigger"]["if-domain"]): r["action"]["selector"] for r in self.res.cosmetics}
        self.assertEqual(sels[("*example.com",)], ".ad-box")
        self.assertEqual(sels[("*example.com", "*foo.org")], "#sidebar-ad")
        self.assertEqual(len(self.res.cosmetics), 2)  # generici, negati, scriptlet, procedurali scartati

    def test_webkit_constraints(self):
        rules = self.res.blocks + self.res.cosmetics + self.res.exceptions
        b.validate_rules(rules, "sample")

    def test_chunking(self):
        res = a.Result(blocks=[{"trigger": {"url-filter": f"x{i}"}, "action": {"type": "block"}} for i in range(2500)],
                       exceptions=[{"trigger": {"url-filter": "e"}, "action": {"type": "ignore-previous-rules"}}])
        chunks = a.chunk(res, 1200)
        self.assertEqual(len(chunks), 3)
        for c in chunks:
            self.assertLessEqual(len(c), 1200)
            self.assertEqual(c[-1]["action"]["type"], "ignore-previous-rules")


try:
    import cryptography  # noqa: F401
    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False


@unittest.skipUnless(HAS_CRYPTO, "pacchetto cryptography non installato")
class PackTests(unittest.TestCase):
    def test_signed_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            key = Path(d, "k.pem")
            subprocess.run(["openssl", "genpkey", "-algorithm", "ed25519", "-out", str(key)], check=True)
            pub = b.public_key_b64(key)
            self.assertEqual(len(base64.b64decode(pub)), 32)
            out = Path(d, "pack.lvp")
            b.write_pack(b.build_payload(offline=True, cache=None), out, key)
            pack = b.read_pack(out, pub)  # verifica con un'implementazione Ed25519 indipendente
            self.assertEqual(pack["format"], 1)
            self.assertTrue(any(s["world"] == "lieve" for s in pack["scripts"]))
            for rl in pack["ruleLists"]:
                json.loads(rl["json"])
            # Payload alterato → firma non valida
            data = bytearray(out.read_bytes())
            data[-1] ^= 1
            out.write_bytes(bytes(data))
            with self.assertRaises(Exception):
                b.read_pack(out, pub)


if __name__ == "__main__":
    unittest.main()
