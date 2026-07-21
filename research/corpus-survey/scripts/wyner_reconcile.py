#!/usr/bin/env python3
"""Reconcile the two full-text channels for Wyner's oeuvre and emit a coverage report.

Channels:
  - metadata:    dossiers/wyner/fulltext-status.json  (slug -> status/source)  [precise]
  - selfarchive: dossiers/wyner/pdfs/selfarchive/*.pdf (author copies via Wayback) [fuzzy match]

Self-archive filenames are author-initial + venue + year (e.g. WABCArgMAS2012 =
Wyner/Atkinson/Bench-Capon, ArgMAS, 2012), so we score each work against each filename
on (year, venue-acronym, distinctive title token, author surname) and take the best match
above a threshold. Errs toward matching so a held author copy is never mislabelled "missing".

Outputs a printed summary and, with --write, dossiers/wyner/FULLTEXT-ACQUISITION.md.
"""
import json, os, re, sys, time, difflib
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKS = os.path.join(HERE, "dossiers/wyner/works.json")
LIST = os.path.join(HERE, "dossiers/wyner/acquire-list.json")
FT = os.path.join(HERE, "dossiers/wyner/fulltext-status.json")
SA = os.path.join(HERE, "dossiers/wyner/selfarchive-status.json")
SADIR = os.path.join(HERE, "dossiers/wyner/pdfs/selfarchive")
REPORT = os.path.join(HERE, "dossiers/wyner/FULLTEXT-ACQUISITION.md")

STOP = set("the a an of on in for to and with from into over under is are as at by "
           "legal law case cases rule rules text argument arguments based approach "
           "analysis using toward towards paper papers final draft slides".split())

# acronym -> words that appear in the OpenAlex venue/title string for that venue
VENUE_EXPAND = {
    "argmas": ["argumentation", "multi-agent", "multiagent"],
    "jurix": ["frontiers in artificial", "legal knowledge", "jurix"],
    "comma": ["computational models of argument", "comma"],
    "ekaw": ["knowledge engineering", "knowledge acquisition", "ekaw"],
    "icail": ["artificial intelligence and law", "international conference on artificial"],
    "cmna": ["computational models of natural argument", "cmna"],
    "aamas": ["autonomous agents", "aamas"],
    "ruleml": ["rules", "rule", "ruleml"],
    "ecai": ["european conference on artificial", "ecai"],
    "lrec": ["language resources", "lrec"],
    "eacl": ["computational linguistics", "eacl"],
    "splet": ["semantic processing", "splet"],
    "clima": ["computational logic", "clima"],
    "climas": ["computational logic", "clima"],
    "itbam": ["information technology in bio", "itbam"],
    "epart": ["electronic participation", "epart"],
    "swaie": ["semantic web", "information extraction", "swaie"],
    "ker": ["knowledge engineering review", "ker"],
    "legalruleml": ["legalruleml"],
    "oasis": ["legalruleml"],
    "ontology": ["ontology"],
}
VENUE_ACRONYMS = list(VENUE_EXPAND.keys())

# author-initialism runs seen in his filenames -> surnames
INITIALISMS = {
    "wabc": ["wyner", "atkinson", "bench"],
    "abc": ["atkinson", "bench"],
    "wa": ["wyner", "atkinson"],
    "abcpw": ["atkinson", "bench", "prakken", "wyner"],
    "wab": ["wyner", "atkinson", "bench"],
}

# grey literature (not indexed works): slides, CV, CFPs, teaching, proceedings/CFP
GREY_RE = re.compile(r"(slides|curriculumvitae|_cv|classintro|crowdsource|lawtech|"
                     r"presentation|proceedings|^cfp|cfpmpm|workshop|papers\.pdf$|"
                     r"introduction|tutorial|coipresentation|_v1\.pdf$|think2013)",
                     re.I)

# W1 threads -> keyword hints (lightweight)
THREADS = {
    "argumentation": ["argument", "argumentation", "argmas", "comma", "cmna", "scheme"],
    "cbr": ["case-based", "case based", "cbr", "factor", "precedent", "hypo", "cato"],
    "cnl": ["controlled natural", "cnl", "natural language", "boxer", "linguistic"],
    "legalruleml": ["legalruleml", "ruleml", "deontic", "defeasible", "standard", "markup"],
    "rule-extraction": ["rule extraction", "extraction", "regulation", "ingest", "isomorph"],
    "kr-nlp": ["ontology", "owl", "annotation", "mining", "nlp", "extraction",
               "recognizing", "rhetorical", "question answering"],
    "stewardship": ["history", "thirty years", "50 papers", "retrospective", "decade"],
}


def load_json_retry(path, tries=5):
    for _ in range(tries):
        try:
            return json.load(open(path))
        except Exception:
            time.sleep(0.4)
    return {}


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def title_tokens(title):
    return {t for t in norm(title).split() if len(t) >= 6 and t not in STOP}


def year_in(s):
    m = re.findall(r"(19|20)\d{2}", s or "")
    return set(int(y) for y in re.findall(r"((?:19|20)\d{2})", s or ""))


def score_match(work, fname):
    """Score how well self-archive filename matches a work. >=3 = confident."""
    fn = fname.lower()
    fyears = year_in(fn)
    wyear = work.get("year")
    wtext = norm(work.get("venue")) + " " + norm(work.get("title"))
    wtext_ns = wtext.replace(" ", "")
    coauth = norm(" ".join(work.get("coauthors") or []))
    score = 0
    # year (required-ish signal)
    year_ok = wyear and (wyear in fyears or (wyear - 1) in fyears or (wyear + 1) in fyears)
    if year_ok:
        score += 2
    elif fyears and wyear and min(abs(wyear - y) for y in fyears) > 2:
        score -= 3  # year clearly disagrees -> almost certainly not this work
    # venue acronym in filename, expansion words in work venue/title
    for ac in VENUE_ACRONYMS:
        if ac in fn:
            if any(w in wtext for w in VENUE_EXPAND[ac]) or ac in wtext_ns:
                score += 2
    # distinctive title token in filename
    for tok in title_tokens(work.get("title")):
        if tok[:7] in fn:
            score += 2
            break
    # author surname or initialism run at head of filename
    head = re.match(r"[a-z]+", fn)
    head = head.group(0) if head else ""
    if head in INITIALISMS and sum(1 for s in INITIALISMS[head] if s in coauth) >= 2:
        score += 2
    for sur in ["wyner", "bench", "atkinson", "governatori", "peters", "schneider",
                "hoekstra", "palmirani", "paschke", "sartor", "prakken", "wardeh",
                "hage", "vanengers", "milward", "moens"]:
        if sur in fn and sur in coauth:
            score += 1
    # fuzzy filename-stem vs title similarity — breaks ties between works that share
    # a strong token (e.g. several "legalruleml" works) by favouring the title the
    # filename most resembles. Scaled to 0..4.
    stem = re.sub(r"\.pdf$", "", fn)
    stem = re.sub(r"(19|20)\d{2}", "", stem)               # drop year
    stem = re.sub(r"(final|draft|v\d+|slides|demo)", "", stem)
    stem = re.sub(r"[^a-z0-9]", "", stem)
    ttl = re.sub(r"[^a-z0-9]", "", norm(work.get("title")))
    if stem and ttl:
        ratio = difflib.SequenceMatcher(None, stem, ttl).ratio()
        score += round(4 * ratio, 2)
    return score


def thread_of(work):
    t = norm(work.get("title")) + " " + norm(work.get("abstract"))
    hits = [name for name, kws in THREADS.items() if any(k in t for k in kws)]
    return hits[0] if hits else "other"


def main():
    write = "--write" in sys.argv
    works = json.load(open(WORKS))
    acq = json.load(open(LIST))
    ft = load_json_retry(FT)
    sa = load_json_retry(SA)
    slug_of = {}
    for w, a in zip(sorted(works, key=lambda z: 0), acq):
        pass
    # map work title -> acquire slug (acquire-list built from same works order)
    title_to_slug = {a["title"]: a["slug"] for a in acq}

    # hand overrides for acronym filenames the fuzzy matcher can't resolve
    # (filename -> distinctive lowercase substring of the target work title)
    FILENAME_OVERRIDE = {   # substrings must be in norm() form (no punctuation)
        "cnlp&p.pdf": "controlled natural languages properties",
    }

    sa_files_all = [k for k, v in sa.items() if v.get("status") == "downloaded"]
    grey_files = [f for f in sa_files_all if GREY_RE.search(f)]
    sa_files = [f for f in sa_files_all if f not in grey_files]  # candidate papers

    # assign each self-archive paper file to its best work
    file_to_work = {}
    work_has_sa = {}
    for f in sa_files:
        ov = FILENAME_OVERRIDE.get(f.lower())
        if ov:
            hit = next((w for w in works if ov in norm(w.get("title"))), None)
            if hit is not None:
                file_to_work[f] = (hit.get("title"), 99)
                work_has_sa[hit.get("title")] = f
                continue
        best, bestsc = None, 0
        for w in works:
            sc = score_match(w, f)
            if sc > bestsc:
                best, bestsc = w, sc
        if best is not None and bestsc >= 3:
            file_to_work[f] = (best.get("title"), bestsc)
            work_has_sa[best.get("title")] = f
    matched = len(file_to_work)
    unmatched_files = [f for f in sa_files if f not in file_to_work]

    # per-work coverage
    rows = []
    for w in works:
        title = w.get("title")
        slug = title_to_slug.get(title)
        md = ft.get(slug, {}) if slug else {}
        md_status = md.get("status")
        held = (md_status == "downloaded") or (title in work_has_sa)
        rows.append({
            "title": title, "year": w.get("year"), "cites": w.get("cited_by_count") or 0,
            "venue": w.get("venue"), "doi": w.get("doi"),
            "md": md_status, "md_src": md.get("source"),
            "sa": work_has_sa.get(title), "held": held, "thread": thread_of(w),
        })

    held_rows = [r for r in rows if r["held"]]
    n_held = len(held_rows)
    # channel breakdown for held
    md_dl = sum(1 for r in rows if r["md"] == "downloaded")
    md_src = Counter(r["md_src"] for r in rows if r["md"] == "downloaded")

    # missing high-cited (not held, sorted by cites)
    missing = sorted([r for r in rows if not r["held"]], key=lambda r: -r["cites"])

    # coverage by year bucket & thread (held)
    def bucket(y):
        if not y: return "n/a"
        return "pre-2010" if y < 2010 else ("2010-2019" if y < 2020 else "2020-2025")
    yb = Counter(bucket(r["year"]) for r in held_rows)
    yb_all = Counter(bucket(r["year"]) for r in rows)
    th = Counter(r["thread"] for r in held_rows)

    # ---- print summary ----
    print(f"works: {len(works)}")
    print(f"self-archive PDFs downloaded: {len(sa_files)} (matched to a work: {matched}, "
          f"unmatched: {len(unmatched_files)})")
    print(f"metadata downloaded: {md_dl}  sources: {dict(md_src)}")
    print(f"DISTINCT works held (either channel): {n_held}/{len(works)}")
    print(f"by year (held/all): " + ", ".join(f"{k} {yb[k]}/{yb_all[k]}" for k in yb_all))
    print(f"by thread (held): {dict(th)}")
    print("\nTop-20 highest-cited NOT held:")
    for r in missing[:20]:
        print(f"  {r['cites']:>4}c {r['year']} [{r['md'] or '-'}] {(r['title'] or '')[:60]}")
    print("\nUnmatched self-archive files (held but not linked to a work-list row):")
    for f in unmatched_files:
        print("  ", f)

    if not write:
        return

    # ---- write report ----
    def md_table_missing(rs, n=25):
        out = ["| Cites | Year | Title | metadata |", "|---:|---:|---|---|"]
        for r in rs[:n]:
            t = (r["title"] or "").replace("|", "/")
            out.append(f"| {r['cites']} | {r['year'] or ''} | {t[:70]} | {r['md'] or '—'} |")
        return "\n".join(out)

    lines = []
    lines.append("# Wyner full-text acquisition (green-OA only)\n")
    lines.append("> Full text was gathered from **open sources only**: the author's own "
                 "self-archived copies (recovered from the Internet Archive Wayback Machine, "
                 "since his `wyner.info` file host has lapsed), plus OpenAlex / Unpaywall / "
                 "arXiv / Semantic Scholar open-access locations. **No Sci-Hub, no paywall "
                 "circumvention** — paywalled items are recorded, not forced.\n")
    lines.append("## Coverage\n")
    lines.append(f"- **Distinct works with full text held: {n_held} of {len(works)}** "
                 f"(~{round(100*n_held/len(works))}%). The 154 denominator is the raw "
                 f"OpenAlex/DBLP work-list, which per the W1 caveat includes a few namesakes "
                 f"and non-article items, so this understates coverage of his genuine papers.")
    lines.append(f"- On disk we hold **{len(sa_files_all)} self-archive files**; {len(sa_files)} "
                 f"are papers (counted here) and {len(grey_files)} are grey literature "
                 f"(slides, CV, CFPs, workshop front-matter) kept as extras.")
    lines.append(f"- **His self-archive (author copies): {len(sa_files)} PDFs** recovered via "
                 f"Wayback — the dominant channel, heavy on his 2008–2014 argumentation / CBR / "
                 f"CNL / LegalRuleML core (many are workshop papers with no DOI and no gold OA).")
    lines.append(f"- **Metadata channel (OpenAlex/Unpaywall/arXiv/S2): {md_dl} PDFs** — thin, "
                 f"because most of his DOI-bearing work sits behind Springer LNCS / IOS / ACM.")
    lines.append(f"- Self-archive files confidently matched to a work-list row: {matched}; "
                 f"{len(unmatched_files)} more are held but not cleanly linked (older/renamed).\n")
    lines.append("### By year (held / total)\n")
    lines.append("| Bucket | Held | Total |\n|---|---:|---:|")
    for k in ["pre-2010", "2010-2019", "2020-2025", "n/a"]:
        if yb_all.get(k):
            lines.append(f"| {k} | {yb.get(k,0)} | {yb_all[k]} |")
    lines.append("\n### By research thread (held)\n")
    lines.append("| Thread | Held |\n|---|---:|")
    for k, v in th.most_common():
        lines.append(f"| {k} | {v} |")
    lines.append("\n## Per-channel PDF sources\n")
    lines.append(f"- Wayback self-archive: **{len(sa_files)}**")
    for s, c in md_src.most_common():
        lines.append(f"- {s}: {c}")
    lines.append("\n## Highest-cited works still WITHOUT full text\n")
    lines.append("These are the papers a human would pull via licensed institutional access "
                 "later (mostly Springer/IOS/ACM). Ranked by citations.\n")
    lines.append(md_table_missing(missing, 25))
    lines.append("\n## Notes\n")
    lines.append("- PDFs live in `dossiers/wyner/pdfs/` (metadata) and "
                 "`dossiers/wyner/pdfs/selfarchive/` (author copies); both are gitignored.")
    lines.append("- Self-archive→work matching is heuristic (year + venue acronym + title "
                 "token + author surname); the distinct-held count is therefore ±a few.")
    lines.append(f"- Self-archive files not linked to a work-list row: "
                 f"{', '.join(sorted(unmatched_files)) or 'none'}.")

    open(REPORT, "w").write("\n".join(lines) + "\n")
    print(f"\nwrote {REPORT}")


if __name__ == "__main__":
    main()
