#!/usr/bin/env python3
"""Prep Phase 3: join enriched abstracts with pre-rank order, chunk into N files for the
Sonnet judge fan-out. Judge input deliberately EXCLUDES pre-rank signals (is_seed/composite)
so the LLM verdict is an independent second signal to cross-check against the graph pre-rank."""
import json, os, math

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
SP = "/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/7c74365c-e8cf-487b-a5ba-00ebbcbd6c57/scratchpad/phase3"
CHUNKS = os.path.join(SP, "chunks")
OUTS = os.path.join(SP, "verdicts")
os.makedirs(CHUNKS, exist_ok=True)
os.makedirs(OUTS, exist_ok=True)

enriched = {p["key"]: p for p in json.load(open(os.path.join(DATA, "enriched.json")))}
prerank = json.load(open(os.path.join(DATA, "prerank.json")))  # already sorted by composite desc

items = []
for r in prerank:  # keep pre-rank order
    e = enriched.get(r["key"], {})
    items.append({
        "key": r["key"],
        "venue": r["venue"], "year": r["year"],
        "title": r["title"],
        "authors": (e.get("authors") or [])[:4],
        "abstract": (e.get("abstract") or "")[:1600],  # cap to keep chunks lean
        "tldr": e.get("tldr") or "",
    })

N = 16
size = math.ceil(len(items) / N)
manifest = []
for i in range(N):
    chunk = items[i*size:(i+1)*size]
    if not chunk:
        continue
    cpath = os.path.join(CHUNKS, f"chunk-{i:02d}.json")
    opath = os.path.join(OUTS, f"verdicts-{i:02d}.json")
    json.dump(chunk, open(cpath, "w"), ensure_ascii=False, indent=1)
    manifest.append({"i": i, "chunk": cpath, "out": opath, "n": len(chunk)})

json.dump(manifest, open(os.path.join(SP, "manifest.json"), "w"), indent=1)
print(f"total items: {len(items)} (with_abstract={sum(1 for x in items if x['abstract'])})")
print(f"chunks: {len(manifest)} x ~{size}")
for m in manifest:
    print(f"  chunk-{m['i']:02d}: n={m['n']}")