#!/usr/bin/env python3
"""Long-tail green-OA rescue for works the main wyner_fulltext.py pull could not
resolve (status 'paywalled' or 'failed').

Tries, in order, per work:
  1. Semantic Scholar Graph API openAccessPdf, by DOI (or title search if no DOI).
  2. arXiv title search (ti:"<title>" AND au:Wyner).
  3. If the work's stored oa_url or any OpenAlex/Unpaywall landing page we already
     recorded is a *landing page* (not a raw pdf), fetch the HTML and look for an
     obvious direct .pdf link on it (green-OA repository pattern: Swansea Cronfa,
     Aberdeen, Liverpool, KCL, ePrints, etc). No login/paywall circumvention.

Only ever accepts real %PDF- bytes. Fully polite: sleeps between every network call.
Updates dossiers/wyner/fulltext-status.json in place; writes PDFs to
dossiers/wyner/pdfs/<slug>.pdf so a subsequent run of wyner_fulltext.py picks them
up as cached.

Usage: python3 scripts/wyner_longtail.py [--sleep 4] [--limit N]
"""
import json, os, re, sys, time, subprocess, urllib.parse, html

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST = os.path.join(HERE, "dossiers/wyner/acquire-list.json")
PDFDIR = os.path.join(HERE, "dossiers/wyner/pdfs")
STATUS = os.path.join(HERE, "dossiers/wyner/fulltext-status.json")
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/125.0 Safari/537.36")

SLEEP = float(os.environ.get("SLEEP_LONGTAIL", "4"))

os.makedirs(PDFDIR, exist_ok=True)

REPO_HOST_HINTS = (
    "cronfa.swan.ac.uk", "swansea.ac.uk",
    "abdn.ac.uk", "aberdeen",
    "liverpool.ac.uk", "livrepository",
    "kcl.ac.uk", "kclpure",
    "eprints", "epubs", "repository", "openaccess", "hdl.handle.net",
    "arxiv.org", "core.ac.uk", "zenodo.org",
)


def curl(url, max_time=45, accept=None, extra_headers=None):
    cmd = ["curl", "-sL", "--max-time", str(max_time), "-A", UA]
    if accept:
        cmd += ["-H", f"Accept: {accept}"]
    for h in (extra_headers or []):
        cmd += ["-H", h]
    cmd.append(url)
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=max_time + 15)
        return r.stdout or None
    except Exception:
        return None


def curl_json(url, extra_headers=None):
    b = curl(url, max_time=30, accept="application/json", extra_headers=extra_headers)
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


def s2_by_doi(doi, backoff_state):
    url = (f"https://api.semanticscholar.org/graph/v1/paper/DOI:{urllib.parse.quote(doi)}"
           f"?fields=openAccessPdf,externalIds,title")
    for attempt in range(3):
        b = curl(url, accept="application/json")
        if b and b.startswith(b"{") is False and b"429" in b[:20]:
            pass
        try:
            j = json.loads(b) if b else None
        except Exception:
            j = None
        if j is not None:
            return j
        time.sleep(SLEEP * (attempt + 2))  # back off
    return None


def s2_by_title(title):
    url = ("https://api.semanticscholar.org/graph/v1/paper/search"
           f"?query={urllib.parse.quote(title)}&fields=openAccessPdf,externalIds,title,authors&limit=5")
    j = curl_json(url)
    if not isinstance(j, dict):
        return None
    for item in (j.get("data") or []):
        authors = " ".join(a.get("name", "") for a in item.get("authors", []))
        if "wyner" in authors.lower():
            return item
    # fall back to first hit if titles match closely
    data = j.get("data") or []
    if data and title.lower()[:20] in (data[0].get("title") or "").lower():
        return data[0]
    return None


def arxiv_title_search(title):
    q = f'ti:"{title}" AND au:Wyner'
    url = "http://export.arxiv.org/api/query?search_query=" + urllib.parse.quote(q) + "&max_results=3"
    b = curl(url, accept="application/atom+xml")
    if not b:
        return None
    m = re.search(rb"<id>http://arxiv\.org/abs/([^<]+)</id>", b)
    if m:
        arxiv_id = m.group(1).decode()
        arxiv_id = re.sub(r"v\d+$", "", arxiv_id)
        return f"https://arxiv.org/pdf/{arxiv_id}.pdf"
    return None


def find_pdf_link_on_page(url):
    """Fetch an HTML landing page and look for a direct .pdf link (green-OA repo)."""
    host = urllib.parse.urlparse(url).netloc.lower()
    if not any(h in host for h in REPO_HOST_HINTS):
        return None
    b = curl(url, accept="text/html")
    if not b:
        return None
    try:
        text = b.decode("utf-8", errors="ignore")
    except Exception:
        return None
    # look for href="....pdf" (relative or absolute)
    links = re.findall(r'href=["\']([^"\']+\.pdf[^"\']*)["\']', text, flags=re.I)
    if not links:
        return None
    link = html.unescape(links[0])
    if link.startswith("//"):
        link = "https:" + link
    elif link.startswith("/"):
        link = f"{urllib.parse.urlparse(url).scheme}://{host}" + link
    elif not link.startswith("http"):
        base = url.rsplit("/", 1)[0]
        link = base + "/" + link
    return link


def main():
    sleep = SLEEP
    limit = None
    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == "--sleep":
            sleep = float(argv[i + 1]); i += 2
        elif argv[i] == "--limit":
            limit = int(argv[i + 1]); i += 2
        else:
            i += 1

    works = json.load(open(LIST))
    status = json.load(open(STATUS)) if os.path.exists(STATUS) else {}
    by_slug = {w["slug"]: w for w in works}

    # resumable: skip works already attempted by a prior long-tail run (marked
    # longtail_tried) so repeated runs advance instead of re-checking the same head.
    todo = [s for s, v in status.items()
            if v.get("status") in ("paywalled", "failed")
            and not v.get("longtail_tried") and s in by_slug]
    if limit:
        todo = todo[:limit]
    print(f"[longtail] {len(todo)} long-tail candidates (sleep {sleep}s)", flush=True)

    rescued = 0
    for n, slug in enumerate(todo, 1):
        w = by_slug[slug]
        pdf_path = os.path.join(PDFDIR, slug + ".pdf")
        if os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 1000:
            continue
        title = w.get("title") or ""
        doi = norm_doi(w.get("doi"))
        got = None

        # 1) Semantic Scholar
        s2 = s2_by_doi(doi, None) if doi else None
        time.sleep(sleep)
        if not s2 or not (s2.get("openAccessPdf") or {}).get("url"):
            s2b = s2_by_title(title) if title else None
            time.sleep(sleep)
            if s2b and (s2b.get("openAccessPdf") or {}).get("url"):
                s2 = s2b
        if s2 and (s2.get("openAccessPdf") or {}).get("url"):
            cand = s2["openAccessPdf"]["url"]
            b = curl(cand)
            time.sleep(sleep)
            if is_pdf(b):
                got = ("s2", cand, b)

        # 2) arXiv title search
        if not got and title:
            axurl = arxiv_title_search(title)
            time.sleep(sleep)
            if axurl:
                b = curl(axurl)
                time.sleep(sleep)
                if is_pdf(b):
                    got = ("arxiv-title", axurl, b)

        # 3) Repository landing page scrape (only known repo hosts, no login bypass)
        if not got:
            for cand_url in filter(None, [w.get("oa_url"), status[slug].get("oa_url")]):
                pdflink = find_pdf_link_on_page(cand_url)
                time.sleep(sleep)
                if pdflink:
                    b = curl(pdflink)
                    time.sleep(sleep)
                    if is_pdf(b):
                        got = ("repo-page", pdflink, b)
                        break

        if got:
            source, url, b = got
            with open(pdf_path, "wb") as f:
                f.write(b)
            status[slug] = {"status": "downloaded", "source": f"longtail-{source}",
                             "url": url, "bytes": len(b)}
            rescued += 1
            print(f"  [{n}/{len(todo)}] RESCUED {slug} ({source}, {len(b)//1024}KB)", flush=True)
        else:
            status[slug]["longtail_tried"] = True   # mark so re-runs skip it
            print(f"  [{n}/{len(todo)}] still-miss {slug}", flush=True)

        json.dump(status, open(STATUS, "w"), indent=1)

    print(f"[longtail] done. rescued {rescued}/{len(todo)}", flush=True)


if __name__ == "__main__":
    main()
