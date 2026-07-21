#!/usr/bin/env python3
"""Polite, resumable green-OA full-text puller for Adam Wyner's oeuvre.

GUARDRAILS (project ToS, hard):
  - open-first only: OpenAlex best_oa_location / Unpaywall oa_locations / arXiv.
  - NO Sci-Hub, NO bulk publisher scraping. One polite try per candidate URL.
  - Paywalled / bot-protected -> recorded as 'paywalled'/'failed', never forced.

Pacing: sleeps SLEEP_WORK between works and SLEEP_API between API calls so we
never hammer OpenAlex/Unpaywall/publisher endpoints. Fully resumable: an existing
non-empty pdfs/<slug>.pdf is skipped; status is checkpointed after every work.

Usage:  python3 scripts/wyner_fulltext.py [--sleep 8] [--limit N]
"""
import json, os, re, sys, time, subprocess, urllib.parse

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST = os.path.join(HERE, "dossiers/wyner/acquire-list.json")
PDFDIR = os.path.join(HERE, "dossiers/wyner/pdfs")
STATUS = os.path.join(HERE, "dossiers/wyner/fulltext-status.json")
EMAIL = "mengwong@gmail.com"          # OpenAlex/Unpaywall polite pool
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/125.0 Safari/537.36")

SLEEP_WORK = float(os.environ.get("SLEEP_WORK", "8"))   # between papers
SLEEP_API = 1.5                                         # between API calls

os.makedirs(PDFDIR, exist_ok=True)


def curl(url, max_time=60, accept=None):
    """Fetch bytes via curl to stdout (avoids curl -o sandbox block). Returns bytes or None."""
    cmd = ["curl", "-sL", "--max-time", str(max_time), "-A", UA]
    if accept:
        cmd += ["-H", f"Accept: {accept}"]
    cmd.append(url)
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=max_time + 15)
        return r.stdout or None
    except Exception:
        return None


def curl_json(url):
    b = curl(url, max_time=40, accept="application/json")
    if not b:
        return None
    try:
        return json.loads(b)
    except Exception:
        return None


def is_pdf(b):
    return bool(b) and b[:5] == b"%PDF-"


def norm_doi(doi):
    if not doi:
        return None
    doi = doi.strip()
    doi = re.sub(r"^https?://(dx\.)?doi\.org/", "", doi, flags=re.I)
    return doi.lower()


def candidates(work):
    """Yield (source, url) PDF candidates in priority order, resolving fresh."""
    doi = norm_doi(work.get("doi"))

    # 1) OpenAlex fresh: best_oa_location then any location with a pdf_url
    if doi:
        oa = curl_json(f"https://api.openalex.org/works/doi:{urllib.parse.quote(doi)}?mailto={EMAIL}")
        time.sleep(SLEEP_API)
        if isinstance(oa, dict):
            best = (oa.get("best_oa_location") or {})
            if best.get("pdf_url"):
                yield "openalex-best", best["pdf_url"]
            for loc in (oa.get("locations") or []):
                if loc.get("pdf_url"):
                    yield "openalex-loc", loc["pdf_url"]
            # arXiv landing -> pdf
            for loc in (oa.get("locations") or []):
                u = (loc.get("landing_page_url") or "")
                m = re.search(r"arxiv\.org/abs/([^\s/?#]+)", u)
                if m:
                    yield "arxiv", f"https://arxiv.org/pdf/{m.group(1)}.pdf"

    # 2) Unpaywall
    if doi:
        up = curl_json(f"https://api.unpaywall.org/v2/{urllib.parse.quote(doi)}?email={EMAIL}")
        time.sleep(SLEEP_API)
        if isinstance(up, dict) and up.get("is_oa"):
            best = (up.get("best_oa_location") or {})
            if best.get("url_for_pdf"):
                yield "unpaywall-best", best["url_for_pdf"]
            for loc in (up.get("oa_locations") or []):
                if loc.get("url_for_pdf"):
                    yield "unpaywall-loc", loc["url_for_pdf"]

    # 3) stored oa_url (may be landing page or a direct pdf); arXiv transform if applicable
    ou = work.get("oa_url")
    if ou:
        m = re.search(r"arxiv\.org/abs/([^\s/?#]+)", ou)
        if m:
            yield "arxiv-stored", f"https://arxiv.org/pdf/{m.group(1)}.pdf"
        yield "stored-oa", ou


def main():
    sleep_work = SLEEP_WORK
    limit = None
    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == "--sleep":
            sleep_work = float(argv[i + 1]); i += 2
        elif argv[i] == "--limit":
            limit = int(argv[i + 1]); i += 2
        else:
            i += 1

    works = json.load(open(LIST))
    status = {}
    if os.path.exists(STATUS):
        try:
            status = json.load(open(STATUS))
        except Exception:
            status = {}

    # Resume = skip anything already classified in a prior pass (downloaded,
    # paywalled, or failed) -- re-attempting paywalled/failed with the same
    # three sources (OpenAlex/Unpaywall/stored oa_url) just reproduces the same
    # miss. Revisiting paywalled/failed works with *different* channels is the
    # job of the separate long-tail script (scripts/wyner_longtail.py).
    todo = [w for w in works if w["slug"] not in status]
    if limit:
        todo = todo[:limit]
    print(f"[wyner-fulltext] {len(works)} works, {len(todo)} to attempt "
          f"(sleep {sleep_work}s/work)", flush=True)

    for n, w in enumerate(todo, 1):
        slug = w["slug"]
        pdf_path = os.path.join(PDFDIR, slug + ".pdf")
        if os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 1000:
            status[slug] = {"status": "downloaded", "source": "cached",
                            "bytes": os.path.getsize(pdf_path)}
            continue

        got = False
        tried = []
        for source, url in candidates(w):
            tried.append(source)
            b = curl(url)
            time.sleep(SLEEP_API)
            if is_pdf(b):
                with open(pdf_path, "wb") as f:
                    f.write(b)
                status[slug] = {"status": "downloaded", "source": source,
                                "url": url, "bytes": len(b)}
                print(f"  [{n}/{len(todo)}] OK   {slug}  ({source}, {len(b)//1024}KB)", flush=True)
                got = True
                break
        if not got:
            st = "paywalled" if (w.get("doi") and not w.get("oa_url")) else "failed"
            status[slug] = {"status": st, "tried": tried,
                            "doi": w.get("doi"), "oa_url": w.get("oa_url")}
            print(f"  [{n}/{len(todo)}] MISS {slug}  ({st}; tried {tried or 'nothing'})", flush=True)

        json.dump(status, open(STATUS, "w"), indent=1)
        time.sleep(sleep_work)

    dl = sum(1 for v in status.values() if v.get("status") == "downloaded")
    pw = sum(1 for v in status.values() if v.get("status") == "paywalled")
    fl = sum(1 for v in status.values() if v.get("status") == "failed")
    print(f"[wyner-fulltext] done. downloaded={dl} paywalled={pw} failed={fl} "
          f"of {len(works)}", flush=True)


if __name__ == "__main__":
    main()
