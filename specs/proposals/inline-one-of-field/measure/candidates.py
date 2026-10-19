#!/usr/bin/env python3
"""Detail on the single-field candidates found by census.py, plus the
'one field + signatures' class that only a NAMED inline form could serve."""
import os
import random
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(__file__))
import census as C  # noqa: E402


def subject_of(p):
    m = re.search(r"/subjects/(.+?)/encodings/([^/]+)", p)
    if m:
        return f"commons:{m.group(1)}"
    m = re.search(r"/jl4/examples/([^/]+(?:/[^/]+)?)", p)
    return f"l4-ide:{m.group(1)}" if m else p


def raw_span(files, toks, d):
    t = toks[d.file]
    lo, hi = t[d.start].line, t[d.end].line
    lines = files[d.file].split("\n")
    return lines[lo - 1:hi], lo, hi


def main(argv):
    roots = [a for a in argv if not a.startswith("--")]
    files, dupes = C.load(roots)
    toks, results = C.census(files)
    enums = [(d, s) for d, s in results if d.kind == "enum"]
    cands = [(d, s) for d, s in enums if C.bucket(d, s) in ("one-field", "one-payload")]

    print(f"candidates: {len(cands)} of {len(enums)} enums")
    subj = Counter(subject_of(d.file) for d, s in cands)
    print(f"distinct subjects/dirs holding a candidate: {len(subj)}")
    for k, v in subj.most_common(12):
        print(f"  {v:4} {k}")

    ncons, annot, ref, multi = [], 0, 0, 0
    for d, s in cands:
        span, lo, hi = raw_span(files, toks, d)
        text = "\n".join(span)
        if re.search(r"@(desc|nlg)", text):
            annot += 1
        if "@ref" in text:
            ref += 1
        if hi > lo:
            multi += 1
        # constructors: count commas + line-initial names after OF (rough)
        after = text.split("ONE OF", 1)[1] if "ONE OF" in text else ""
        after = re.sub(r"--.*", "", after)
        after = re.sub(r"@\w+[^\n]*", "", after)
        names = [x for x in re.split(r"[,\n]", after) if x.strip()]
        ncons.append(len(names))
    ncons.sort()
    print(f"constructors per candidate enum: median {ncons[len(ncons)//2]}, min {ncons[0]}, max {ncons[-1]}")
    print(f"candidates whose declaration carries @desc/@nlg: {annot}; @ref: {ref}; laid out over >1 line: {multi}")

    # Enums with exactly one field/payload site and >=1 signature site, nothing else.
    named_only = []
    for d, s in enums:
        rs = C.real_sites(s)
        fields = [x for x in rs if x[2] in ("field", "payload")]
        sigs = [x for x in rs if x[2] in ("given", "giveth", "assume")]
        if len(fields) == 1 and sigs and len(fields) + len(sigs) == len(rs):
            named_only.append((d, s))
    print(f"\none field site + only signature sites (named-inline-only class): {len(named_only)}")
    shared = [(d, s) for d, s in enums if C.bucket(d, s) == "shared"]
    twofields = sum(1 for d, s in shared
                    if sum(1 for x in C.real_sites(s) if x[2] in ("field", "payload")) >= 2)
    print(f"shared enums with >=2 field/payload sites: {twofields} of {len(shared)}")
    nofield = sum(1 for d, s in shared
                  if not any(x[2] in ("field", "payload") for x in C.real_sites(s)))
    print(f"shared enums with no field site at all: {nofield}")

    if "--list" in argv:
        for d, s in cands:
            x = C.real_sites(s)[0]
            adj = C.adjacency(toks, d, s)
            print(f"  {adj[0]:9} {adj[1]!s:>4} {d.name!r:40} {d.file}:{toks[d.file][d.start].line} -> {x[2]} of {x[4]!r} at :{x[1]}")
    if "--sample" in argv:
        random.seed(20261012)
        for d, s in random.sample(cands, 15):
            span, lo, hi = raw_span(files, toks, d)
            x = C.real_sites(s)[0]
            print(f"\n### {d.name} {d.file}:{lo}  -> {x[2]} of {x[4]} at :{x[1]}")
            print("\n".join(span[:8]))


if __name__ == "__main__":
    main(sys.argv[1:])
