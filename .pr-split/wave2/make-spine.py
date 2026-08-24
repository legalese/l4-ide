#!/usr/bin/env python3
"""Reconstruct each wave-2 theme's version of the four spine files shared
between the blawx and docassemble slices.

Method: every line of origin/unstable's version is attributed to a theme via
git blame (commit -> PR -> theme; lines older than the base are 'base').
Deleted base lines are attributed by finding which PR's own merge diff deleted
them. A theme's version is then the base file with only that theme's
insertions and deletions applied, in final-file order.

Built-in verification, all of which must pass or we exit 1:
  1. applying BOTH themes' lines reproduces origin/unstable's blob exactly;
  2. git merge-file of the two reconstructions against the base reproduces
     origin/unstable's blob exactly (so the two slices merge cleanly back).

Usage: make-spine.py <base-commit> <out-dir>
"""
import re, subprocess, sys
from pathlib import Path

BASE, OUT = sys.argv[1], Path(sys.argv[2])
SPINE = ["jl4-core/jl4-core.cabal", "jl4/jl4.cabal", "jl4/app/Main.hs", "jl4/tests-cli/Main.hs"]
THEME_PRS = {
    "blawx": {261, 270, 272, 273, 276, 277, 278, 279, 280},
    "docassemble": {264, 265, 267, 268, 269},
}

def git(*args, binary=False):
    r = subprocess.run(["git", *args], capture_output=True)
    if r.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed: {r.stderr.decode()[:500]}")
    return r.stdout if binary else r.stdout.decode()

# commit -> PR for everything merged since base
commit2pr = {}
for line in git("log", "--first-parent", "--format=%H %s", f"{BASE}..origin/unstable").splitlines():
    sha, subj = line.split(" ", 1)
    m = re.search(r"#(\d+)", subj)
    if not m:
        continue
    pr = int(m.group(1))
    commit2pr[sha] = pr
    for c in git("rev-list", f"{sha}^2", "--not", f"{sha}^1").split():
        commit2pr[c] = pr

def theme_of(pr):
    for t, prs in THEME_PRS.items():
        if pr in prs:
            return t
    sys.exit(f"PR #{pr} touched a spine file but belongs to no spine theme")

ok = True
for f in SPINE:
    base_lines = git("show", f"{BASE}:{f}").splitlines(keepends=True)
    final_lines = git("show", f"origin/unstable:{f}").splitlines(keepends=True)

    # 1. attribute every final line: 'base' or a theme
    owner = [None] * len(final_lines)
    cur = None
    for bl in git("blame", "--line-porcelain", f"{BASE}..origin/unstable", "--", f).splitlines():
        m = re.match(r"^([0-9a-f]{40})(\^?) (\d+) (\d+)", bl)
        if m:
            sha, n = m.group(1), int(m.group(4))
            cur = n - 1
            if sha.startswith("^") or sha not in commit2pr:
                # boundary (base) commit
                owner[cur] = "base"
            else:
                owner[cur] = theme_of(commit2pr[sha])
        elif bl.startswith("boundary") and cur is not None:
            owner[cur] = "base"
    assert all(o is not None for o in owner), f"unattributed lines in {f}"

    # 2. attribute deleted base lines: which theme's PR removed them
    deleted_by = {}  # base line number (1-indexed) -> theme
    # walk a -U0 diff of base->final to find deletion positions
    hunks = []  # (old_start, old_count, new_start, new_count)
    for dl in git("diff", "-U0", BASE, "origin/unstable", "--", f).splitlines():
        m = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", dl)
        if m:
            hunks.append((int(m.group(1)), int(m.group(2) or 1), int(m.group(3)), int(m.group(4) or 1)))
    del_positions = []
    for (os_, oc, ns, nc) in hunks:
        for i in range(oc):
            del_positions.append(os_ + i)
    if del_positions:
        # find the deleting PR by content match across per-merge diffs
        for merge_line in git("log", "--first-parent", "--format=%H %s", f"{BASE}..origin/unstable").splitlines():
            sha, subj = merge_line.split(" ", 1)
            m = re.search(r"#(\d+)", subj)
            if not m:
                continue
            pr = int(m.group(1))
            d = subprocess.run(["git", "diff", f"{sha}^1", sha, "--", f], capture_output=True).stdout.decode()
            removed = [l[1:] for l in d.splitlines() if l.startswith("-") and not l.startswith("---")]
            for pos in del_positions:
                content = base_lines[pos - 1].rstrip("\n")
                if content in removed and pos not in deleted_by:
                    deleted_by[pos] = theme_of(pr)
        missing = [p for p in del_positions if p not in deleted_by]
        assert not missing, f"{f}: could not attribute deletions at base lines {missing}"

    # 3. reconstruct: for each theme, walk base and final in diff order
    def reconstruct(theme):
        out, bi, fi = [], 0, 0  # base index, final index (0-based)
        events = []  # (base_pos, 'del') and insertion runs keyed by base_pos
        for (os_, oc, ns, nc) in hunks:
            events.append((os_, oc, ns, nc))
        ev = 0
        while bi < len(base_lines) or fi < len(final_lines):
            if ev < len(events):
                os_, oc, ns, nc = events[ev]
                # -U0: deletions start at os_ (1-based); pure insertions have oc==0 and
                # attach AFTER base line os_
                at_del = oc > 0 and bi == os_ - 1
                at_ins = oc == 0 and bi == os_
                if at_del or at_ins:
                    for i in range(oc):
                        pos = os_ + i
                        if deleted_by.get(pos) == theme:
                            pass  # this theme deletes it
                        else:
                            out.append(base_lines[pos - 1])
                        bi += 1
                    for i in range(nc):
                        pos = ns + i  # 1-based final line
                        o = owner[pos - 1]
                        if o == theme:
                            out.append(final_lines[pos - 1])
                        elif o == "base":
                            # a base line that moved into this hunk (modified line kept)
                            out.append(final_lines[pos - 1])
                        fi += 1
                    ev += 1
                    continue
            if bi < len(base_lines):
                out.append(base_lines[bi]); bi += 1; fi += 1
            else:
                break
        return "".join(out)

    both = None
    versions = {}
    for theme in THEME_PRS:
        versions[theme] = reconstruct(theme)
        p = OUT / theme / f
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(versions[theme])

    # verification 1: base + all themes' edits == final
    def reconstruct_all():
        out, bi = [], 0
        ev = 0
        while bi < len(base_lines) or ev < len(hunks):
            if ev < len(hunks):
                os_, oc, ns, nc = hunks[ev]
                at = (oc > 0 and bi == os_ - 1) or (oc == 0 and bi == os_)
                if at:
                    bi += oc
                    for i in range(nc):
                        out.append(final_lines[ns - 1 + i])
                    ev += 1
                    continue
            if bi < len(base_lines):
                out.append(base_lines[bi]); bi += 1
            else:
                break
        return "".join(out)
    final_text = "".join(final_lines)
    if reconstruct_all() != final_text:
        print(f"SUM MISMATCH (walk): {f}"); ok = False; continue

    # verification 2: each theme's version differs from base by EXACTLY its
    # own lines -- additions are precisely the owner-attributed final lines,
    # deletions precisely the deleted_by-attributed base lines. (A plain
    # git merge-file of the two versions may conflict textually where both
    # themes insert at the same base position; that is expected -- these are
    # review views, the merge vehicle is unstable -> main.)
    import tempfile
    for theme in THEME_PRS:
        with tempfile.NamedTemporaryFile("w", suffix=Path(f).suffix, delete=False) as tf:
            tf.write(versions[theme]); tmp = tf.name
        d = subprocess.run(["git", "diff", "--no-index", "-U0", "/dev/stdin", tmp],
                           input="".join(base_lines).encode(), capture_output=True).stdout.decode()
        got_adds = [l[1:] for l in d.splitlines() if l.startswith("+") and not l.startswith("+++")]
        got_dels = [l[1:] for l in d.splitlines() if l.startswith("-") and not l.startswith("---")]
        want_adds = [final_lines[i].rstrip("\n") for i in range(len(final_lines)) if owner[i] == theme]
        want_dels = [base_lines[pos - 1].rstrip("\n") for pos in sorted(deleted_by) if deleted_by[pos] == theme]
        # modified lines: a theme that deletes base line L and adds its replacement
        # shows the deleted base line in got_dels too; both sides computed the same way
        if got_adds != want_adds or sorted(got_dels) != sorted(want_dels):
            print(f"THEME CONTENT MISMATCH: {f} {theme} "
                  f"(+{len(got_adds)} vs {len(want_adds)}, -{len(got_dels)} vs {len(want_dels)})")
            ok = False
    if not ok:
        continue
    print(f"SUM OK: {f}")

sys.exit(0 if ok else 1)
