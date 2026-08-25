#!/usr/bin/env python3
"""Fetch Singapore Statutes Online sources for the sg-succession subject.

P1's fetch, made reproducible. For each Act this saves three artifacts:

  <ACT>.pdf   the official PDF — the AUTHORITATIVE TEXT, and what the
              source-bundle's sha256 is taken over. Unlike the HTML page it
              is complete for long Acts and it carries the Schedules.
  <ACT>.txt   pdftotext -layout extraction, used for mechanical quotation
  <ACT>.html  the landing page, kept only for the in-force banner and the
              amendment/version history the sweep (P2) reads

The HTML landing page is NOT a usable text source: for a long Act it returns
the table of contents only (PAA1934 came back with 70 headings and no bodies,
and both `?ViewType=Print` and `?WholeDoc=1` are WAF-blocked or stubbed). That
is why the PDF is primary. Recorded here because the next person WILL try the
HTML first.

SSO SOFT-404s WITH HTTP 200. A wrong Act id does not 404: `/Act/GOIA1934`
returns 200 with an HTML "Page Not Found" body, and `?ViewType=Pdf` on it
returns 200 with 24KB of HTML. `curl --fail` cannot see either, so a typo'd id
would be saved as a .pdf, fed to pdftotext, and land in a bundle with a real
sha256 over the wrong bytes. Every fetch therefore checks that what came back
is actually a PDF before it is written.

Usage: ./fetch-sso.py [--out DIR] [ACT_ID ...]   (default: all four Acts, here)
Requires: curl, pdftotext (poppler).
"""
import hashlib, html, json, re, shutil, subprocess, sys, pathlib

ACTS = {
    "ISA1967": "Intestate Succession Act 1967",
    "WA1838": "Wills Act 1838",
    "PAA1934": "Probate and Administration Act 1934",
    "GIA1934": "Guardianship of Infants Act 1934",
}
HERE = pathlib.Path(__file__).parent
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"


def curl(url: str, referer: str | None = None) -> bytes:
    cmd = ["curl", "-sS", "--fail", "--max-time", "120", "-H", f"User-Agent: {UA}"]
    if referer:
        cmd += ["-H", f"Referer: {referer}"]
    return subprocess.run(cmd + [url], capture_output=True, check=True).stdout


def must_be_pdf(act: str, url: str, blob: bytes) -> bytes:
    """Refuse a soft-404. See the module docstring."""
    if not blob.startswith(b"%PDF-"):
        head = blob[:200].decode("utf-8", "replace").replace("\n", " ")
        sys.exit(
            f"fetch-sso: {url} did not return a PDF ({len(blob)}B, starts {head!r}).\n"
            f"  SSO answers an unknown Act id with HTTP 200 and an HTML error page, so this\n"
            f"  is most likely a wrong id for {act!r}. Check the landing page in a browser."
        )
    return blob


def detag(raw: str) -> str:
    t = re.sub(r"(?is)<(script|style).*?</\1>", " ", raw)
    t = html.unescape(re.sub(r"(?s)<[^>]+>", " ", t))
    return re.sub(r"[ \t\xa0]+", " ", t)


def main(argv):
    if not shutil.which("pdftotext"):
        sys.exit("fetch-sso: pdftotext not found (brew install poppler)")
    out = []
    args = argv[1:]
    out_dir = HERE
    if args and args[0] == "--out":
        out_dir = pathlib.Path(args[1]).resolve()
        args = args[2:]
    out_dir.mkdir(parents=True, exist_ok=True)
    for act in args or list(ACTS):
        page = f"https://sso.agc.gov.sg/Act/{act}"
        pdf = must_be_pdf(act, f"{page}?ViewType=Pdf", curl(f"{page}?ViewType=Pdf", referer=page))
        (out_dir / f"{act}.pdf").write_bytes(pdf)
        subprocess.run(["pdftotext", "-layout", str(out_dir / f"{act}.pdf"),
                        str(out_dir / f"{act}.txt")], check=True)
        landing = curl(page).decode("utf-8", "replace")
        (out_dir / f"{act}.html").write_bytes(landing.encode())
        flat = detag(landing)
        m = re.search(r"Current version as at\s+(\d{1,2} \w+ \d{4})", flat)
        # every historical version SSO offers: the rule-version axis, and P2's
        # starting inventory of what has happened to this text
        versions = sorted({v for v in re.findall(
            rf"/Act/{act}/Historical/(\d{{8}})", landing)})
        out.append({
            "act_id": act,
            "short_title": ACTS.get(act, act),
            "url": page,
            "pdf_url": f"{page}?ViewType=Pdf",
            "retrieval_method": "direct",
            "sha256": hashlib.sha256(pdf).hexdigest(),
            "bytes": len(pdf),
            "text_sha256": hashlib.sha256((out_dir / f"{act}.txt").read_bytes()).hexdigest(),
            "in_force": f"Current version as at {m.group(1)}" if m else None,
            "historical_versions": versions,
        })
        print(f"{act}: pdf {len(pdf)}B, text {(out_dir/f'{act}.txt').stat().st_size}B, "
              f"{len(versions)} historical version(s), in_force={out[-1]['in_force']}")
    (out_dir / "fetch-manifest.json").write_text(
        json.dumps({"retrieved_from": "sso.agc.gov.sg",
                    "note": "PDF is authoritative; HTML landing page is TOC-only for long Acts",
                    "documents": out}, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
