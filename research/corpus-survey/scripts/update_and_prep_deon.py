#!/usr/bin/env python3
"""After the SpringerLink backfill: merge recovered DEON abstracts into enriched.json, then
chunk the now-abstract-bearing DEON papers for a fresh (abstract-based) judging pass."""
import json, os, math

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
SP = "/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/7c74365c-e8cf-487b-a5ba-00ebbcbd6c57/scratchpad/phase3/deon"
CHUNKS = os.path.join(SP, "chunks")
OUTS = os.path.join(SP, "verdicts")
os.makedirs(CHUNKS, exist_ok=True)
os.makedirs(OUTS, exist_ok=True)

enriched = json.load(open(os.path.join(DATA, "enriched.json")))
abstracts = json.load(open(os.path.join(DATA, "deon-abstracts.json")))
recovered = {k: v for k, v in abstracts.items() if v}

# merge into enriched.json
n = 0
by_key = {p["key"]: p for p in enriched}
for k, v in recovered.items():
    if k in by_key and not by_key[k].get("abstract"):
        by_key[k]["abstract"] = v[:1600]
        n += 1
json.dump(enriched, open(os.path.join(DATA, "enriched.json"), "w"), ensure_ascii=False, indent=1)
print(f"merged {n} recovered abstracts into enriched.json")

# chunk the DEON papers that now have abstracts (re-judge these with real content)
rejudge = [{
    "key": p["key"], "venue": p["venue"], "year": p["year"], "title": p["title"],
    "authors": (p.get("authors") or [])[:4], "abstract": (p.get("abstract") or "")[:1600],
    "tldr": p.get("tldr") or "",
} for p in enriched if p["venue"] == "DEON" and p["key"] in recovered]

N = max(1, math.ceil(len(rejudge) / 65))
size = math.ceil(len(rejudge) / N)
manifest = []
for i in range(N):
    ch = rejudge[i*size:(i+1)*size]
    if not ch:
        continue
    cp = os.path.join(CHUNKS, f"deon-{i:02d}.json")
    op = os.path.join(OUTS, f"deon-verdicts-{i:02d}.json")
    json.dump(ch, open(cp, "w"), ensure_ascii=False, indent=1)
    manifest.append({"i": i, "chunk": cp, "out": op, "n": len(ch)})
json.dump(manifest, open(os.path.join(SP, "manifest.json"), "w"), indent=1)
print(f"re-judge set: {len(rejudge)} DEON papers -> {len(manifest)} chunk(s) of ~{size}")
for m in manifest:
    print(f"  deon-{m['i']:02d}: n={m['n']}  chunk={m['chunk']}  out={m['out']}")