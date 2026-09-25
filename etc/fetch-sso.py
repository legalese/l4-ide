#!/usr/bin/env python3
"""Fetch a Singapore Statutes Online (sso.agc.gov.sg) Act as of a date.

    fetch-sso.py ACT_ID [--valid-date YYYYMMDD] [--mode fragment|pdf] [--timeline] [--out DIR]

Measured 2026-09-02: SSO serves point-in-time text to a plain HTTP client (no bot
wall). The HTML page lazy-loads its provisions, so `?WholeDoc=1` alone only holds
the table of contents for long Acts; the body comes from
/Details/GetLazyLoadContent, whose parameters are the page's `lazyLoadFilter`
plus SeriesId (a fragment key), FragSysId and `_` (both from the page's
`fragments` map). Fetching the ROOT fragment returns the whole statute body.
`--mode pdf` uses `?ViewType=Pdf` and pdftotext instead. `--timeline` lists the
ValidDate values the site knows for the Act.
"""
import argparse, html, json, re, subprocess, sys, pathlib, urllib.parse, urllib.request

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"
BASE = "https://sso.agc.gov.sg"

def get(url, referer=None, xhr=False):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **({"Referer": referer} if referer else {}), **({"X-Requested-With": "XMLHttpRequest"} if xhr else {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read(), r.headers

def to_text(h):
    h = re.sub(r"<script.*?</script>|<style.*?</style>", " ", h, flags=re.S)
    h = re.sub(r"</(p|div|li|tr|h\d|td)>", "\n", h)
    t = html.unescape(re.sub(r"<[^>]+>", " ", h))
    t = re.sub(r"[ \t]+", " ", t); t = re.sub(r"\n\s*\n+", "\n", t)
    return t.strip() + "\n"

def page(act, valid):
    q = f"?ValidDate={valid}&WholeDoc=1" if valid else "?WholeDoc=1"
    url = f"{BASE}/Act/{act}{q}"
    body, _ = get(url)
    h = body.decode("utf-8", "replace")
    blocks = [json.loads(html.unescape(m)) for m in re.findall(r'<div class="global-vars" data-json=\'(.*?)\'>', h, re.S)]
    gv = next((b for b in blocks if "tocSysId" in b), None)   # the page carries two: site-level, then document-level
    if gv is None: sys.exit("no document-level global-vars block; page shape changed")
    return url, h, gv

def fragment(act, valid, gv, referer):
    frags = gv["fragments"]; root = gv["rootFragSysId"]
    key = next(k for k, v in frags.items() if v["Item1"] == root)
    filt = {k: ("" if v is None else v) for k, v in gv["lazyLoadFilter"].items()}
    filt.update(SeriesId=key, FragSysId=root, _=frags[key]["Item2"])
    url = f"{BASE}{gv['lazyLoadContentUrl']}?{urllib.parse.urlencode(filt)}"
    body, hdr = get(url, referer=referer, xhr=True)
    return body.decode("utf-8", "replace"), hdr.get("XmlTag")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("act"); ap.add_argument("--valid-date"); ap.add_argument("--mode", default="fragment", choices=["fragment", "pdf"])
    ap.add_argument("--timeline", action="store_true"); ap.add_argument("--out", default=".")
    a = ap.parse_args()
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    stem = f"{a.act}-{a.valid_date or 'current'}"
    url, h, gv = page(a.act, a.valid_date)
    if a.timeline:
        for it in gv["timelineItems"]:
            print(re.search(r"ValidDate=(\d{8})", it["Item2"]).group(1), it["Item2"])
        return
    if a.mode == "pdf":
        pdf, _ = get(f"{BASE}/Act/{a.act}?{'ValidDate='+a.valid_date+'&' if a.valid_date else ''}ViewType=Pdf")
        (out / f"{stem}.pdf").write_bytes(pdf)
        subprocess.run(["pdftotext", "-layout", str(out / f"{stem}.pdf"), str(out / f"{stem}.pdf.txt")], check=True)
        print(stem, "pdf", len(pdf), "bytes;", (out / f"{stem}.pdf.txt").stat().st_size, "chars of text")
        return
    frag, tag = fragment(a.act, a.valid_date, gv, url)
    (out / f"{stem}.html").write_text(frag)
    t = to_text(frag); (out / f"{stem}.txt").write_text(t)
    print(stem, f"XmlTag={tag}", len(frag), "bytes html;", len(t), "chars text;", "title:", gv["legisTitle"])

if __name__ == "__main__": main()
