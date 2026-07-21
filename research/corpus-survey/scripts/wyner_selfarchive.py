#!/usr/bin/env python3
"""Recover Adam Wyner's self-archived author copies from the Internet Archive.

His self-archive lived at http://wyner.info/research/Papers/<year>/<file>.pdf but that
domain has lapsed (now parked). The PDFs were snapshotted by the Wayback Machine while
live, so we pull the archived author copies — a legitimate green-OA source (author
self-archiving, preserved by a library). No Sci-Hub, no publisher circumvention.

Input:  dossiers/wyner/wayback-cdx.json  (CDX rows [[hdr],[original,timestamp],...])
Output: dossiers/wyner/pdfs/selfarchive/<basename>.pdf  + selfarchive-status.json
Pacing: SLEEP_ITEM between downloads. Resumable (skips existing non-empty files).
"""
import json, os, subprocess, time, urllib.parse

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CDX = os.path.join(HERE, "dossiers/wyner/wayback-cdx.json")
OUT = os.path.join(HERE, "dossiers/wyner/pdfs/selfarchive")
STATUS = os.path.join(HERE, "dossiers/wyner/selfarchive-status.json")
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/125.0 Safari/537.36")
SLEEP_ITEM = float(os.environ.get("SLEEP_ITEM", "2.5"))

os.makedirs(OUT, exist_ok=True)


def curl(url, max_time=90):
    try:
        r = subprocess.run(["curl", "-sL", "--max-time", str(max_time), "-A", UA, url],
                           capture_output=True, timeout=max_time + 15)
        return r.stdout or None
    except Exception:
        return None


def is_pdf(b):
    return bool(b) and b[:5] == b"%PDF-"


def best_timestamp(original):
    """Ask the Wayback availability API for the closest good (200) snapshot timestamp.

    CDX collapse=urlkey yields the *earliest* capture, which is sometimes a bad
    redirect/partial; the availability API returns a known-good snapshot instead.
    """
    try:
        r = subprocess.run(
            ["curl", "-sL", "--max-time", "30", "-A", UA,
             f"http://archive.org/wayback/available?url={urllib.parse.quote(original, safe='')}"],
            capture_output=True, timeout=45)
        j = json.loads(r.stdout or b"{}")
        return j["archived_snapshots"]["closest"]["timestamp"]
    except Exception:
        return None


def main():
    rows = json.load(open(CDX))
    data = rows[1:] if rows and rows[0] and rows[0][0] == "original" else rows
    status = {}
    if os.path.exists(STATUS):
        try:
            status = json.load(open(STATUS))
        except Exception:
            status = {}

    print(f"[selfarchive] {len(data)} archived PDFs to recover (sleep {SLEEP_ITEM}s)", flush=True)
    for n, (original, ts) in enumerate(data, 1):
        base = original.split("/")[-1] or f"item{n}.pdf"
        if not base.lower().endswith(".pdf"):
            base += ".pdf"
        dest = os.path.join(OUT, base)
        if os.path.exists(dest) and os.path.getsize(dest) > 1000:
            status[base] = {"status": "downloaded", "bytes": os.path.getsize(dest),
                            "original": original, "cached": True}
            continue

        # raw archived bytes: the id_ suffix strips the Wayback wrapper/toolbar
        raw = f"http://web.archive.org/web/{ts}id_/{original}"
        b = curl(raw)
        if not is_pdf(b):
            # CDX gave the earliest capture, which may be a bad snapshot; re-resolve
            # the closest known-good snapshot via the availability API and retry.
            time.sleep(SLEEP_ITEM)
            bts = best_timestamp(original)
            if bts and bts != ts:
                b = curl(f"http://web.archive.org/web/{bts}id_/{original}", max_time=120)
                if is_pdf(b):
                    ts = bts
            if not is_pdf(b):
                time.sleep(SLEEP_ITEM)
                b = curl(raw, max_time=120)       # last polite retry on original ts
        if is_pdf(b):
            with open(dest, "wb") as f:
                f.write(b)
            status[base] = {"status": "downloaded", "bytes": len(b),
                            "original": original, "timestamp": ts}
            print(f"  [{n}/{len(data)}] OK   {base}  ({len(b)//1024}KB)", flush=True)
        else:
            status[base] = {"status": "failed", "original": original, "timestamp": ts}
            print(f"  [{n}/{len(data)}] MISS {base}", flush=True)

        json.dump(status, open(STATUS, "w"), indent=1)
        time.sleep(SLEEP_ITEM)

    dl = sum(1 for v in status.values() if v.get("status") == "downloaded")
    print(f"[selfarchive] done. downloaded={dl}/{len(data)}", flush=True)


if __name__ == "__main__":
    main()
