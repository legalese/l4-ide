#!/usr/bin/env python3
"""Tier-1 execution harness for the Blawx exporter (BLAWX-EXPORT-SPEC §8/§10).

Runs every emitted golden under raw s(CASP) — swipl with the scasp pack, no
Blawx container — and compares each test query's answer to the L4 oracle.

For each seed pair jl4/examples/blawx/<name>.l4 + expected/<name>.blawx:

  1. parse the .blawx (the restricted YAML subset `l4 blawx` emits) into
     workspaces and tests;
  2. parse the `-- L4 oracle ==>` comments in the .l4 — one per #EVAL/#ASSERT
     directive, in directive order, matching the tests' q1..qn order (the
     oracle lives OUTSIDE the artifact, R11: a bridge bug that moved actual
     and expected together must not pass);
  3. assemble one program per test in reasoner.py's load order — preamble,
     vendored Blawx libraries (etc/blawx-vendored-libs.pl; fresh
     blawx_now/blawx_today appended, mirroring dates.py), the dedup-processed
     workspace encodings, the test encoding, the deduplicated marked rules —
     with `#pred` NLG directive lines filtered (s(CASP) source syntax, not
     consultable Prolog; answers unaffected);
  4. run swipl ONCE PER QUERY (a second sequential in-process scasp/2 call
     crashes scasp_solve:stack_parents/3 — the R7 measurement's finding) and
     compare: a value oracle against the output binding, TRUE against "a
     model exists", FALSE against "no model".

Optional-when-present, NEVER a build dependency: exits 0 with a notice when
swipl or the scasp pack is absent. Exits 1 on any mismatch.

The claim ladder (BLAWX-EXPORT-SPEC R11 requires this documented verbatim
from the OpenFisca doc, BACKEND-PORTFOLIO-SPEC I3): "Three tiers, always
distinguished in docs and PR descriptions: _golden_ (regression-stability
only), _executed round-trip_ (emitted artifact runs in the real target
toolchain and agrees with L4 on the test population), _law-validated_
(agreement with an independent authority: upstream implementation, published
worked example, oracle corpus)."  A green run of THIS harness is tier 2
against raw s(CASP) only — Blawx-the-container is tier 2's other half
(exercised in the design pass's tier-2 smoke, not here), and nothing in this
repo claims tier 3 for the Blawx leg.

THE IMPORT DIRECTION (BLAWX-EXPORT-SPEC R14, spec §10 P5) rides the same
machinery, from `jl4/examples/blawx/imported/`: the .l4 is what
`l4 blawx --import` LIFTED, its `-- L4 oracle ==>` lines are what the L4
engine answered, and the .blawx beside it is what `l4 blawx --import
--reemit` regenerated FROM THE PARSED BLOCKS via `renderScasp` (never the
stored, and usually stale, encoding).  So a PASS here is the cross-engine
claim P5 exists to make: the same query, put to L4 and to s(CASP), coming
back with the same answer.  See IMPORT_BRIDGE below for the one clause that
has to be added to make the comparison honest, and why.

Usage:  python3 etc/blawx-tier1-harness.py  [seed ...]
"""

import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
EXAMPLES = REPO / "jl4" / "examples" / "blawx"
VENDORED = Path(__file__).resolve().parent / "blawx-vendored-libs.pl"
SEEDS = ["benefit", "mortality", "scores", "sumlist"]

# The import direction's seeds: <stem> -> the subdirectory of jl4/examples/blawx
# holding BOTH `<stem>.l4` (lifted) and `<stem>.blawx` (re-emitted).
IMPORTED = {"bird": "imported"}

# UPSTREAM FINDING (legalese/blawx; belongs beside the quirk-fix issue #1).
#
# bird's span workspace asserts
#     holds(sec_5__span_pingu_section,-blawx_applies,sec_5_section,pingu).
# and NOTHING CONSUMES IT.  `blawx/ldap.py` declares #pred NLG for holds/4 and
# stops there; `scasp_generator.js` emits an `L(X) :- holds(S,L,X).` bridge only
# from an attributed_rule's THIRD clause and only for that rule's own section;
# `reasoner.py` contains no occurrence of `holds` at all.  So
# -blawx_applies(sec_5_section,pingu) is never derivable, the closed-world
# default `not -blawx_applies(...)` succeeds, NBA 5 applies to pingu after all,
# and `pingu_with_jetpack_cant_fly` comes back with NO MODEL -- contradicting
# its own pinned comment, the Act's own s.5 carve-out, and the L4 lift.
#
# The lift implements the INTENDED semantics (the span is effective), so the
# comparison is run against the bridged program.  Saying so here, in one place,
# is the difference between a green run that means something and a green run
# that is quietly claiming an agreement it does not have.
IMPORT_BRIDGE = """\
% Added by etc/blawx-tier1-harness.py -- see IMPORT_BRIDGE: the shipped
% generator emits no consumer for a `holds` block naming blawx_applies.
-blawx_applies(S,X) :- holds(_Z,-blawx_applies,S,X).
"""

PREAMBLE = """\
:- use_module(library(scasp)).
:- style_check(-discontiguous).
:- style_check(-singleton).
"""

# UPSTREAM FINDING #2 (s(CASP) itself, not Blawx and not our emitter).
#
# Enumerating instead of committing to the first model -- see run_test -- turned
# up one query on which s(CASP) reports an answer L4 does not: benefit/q1 asks
# `benefit_amount(a1,X)` and gets BOTH 1000 (right) and 0.  The 0 comes from
#
#     according_to(sec_2_section,benefit_amount,A,0) :- applicant(A),
#                                                       not eligible_for_benefit(A).
#
# and it is not our clause being wrong: put that clause's own body to the SAME
# program as a query and s(CASP) refuses it.  Measured, with the .pl this
# harness keeps in its temp dir:
#
#     ?- applicant(a1), not eligible_for_benefit(a1).           -> 0 models
#     ?- according_to(sec_2_section,benefit_amount,a1,0).       -> 1 model
#
# A rule body that succeeds where the identical conjunction fails is an engine
# inconsistency, and the model it returns says so out loud: it contains
# `age(a1,70)` and `not age(a1,_)` together, and `-is_veteran(a1)` beside
# `not -is_veteran(_)` -- the dual of a body with a free variable over an
# unbounded domain, satisfied by an unbound witness rather than checked over
# the ground instances.
#
# The harness's posture, matching IMPORT_BRIDGE above: name it in ONE place,
# keep the agreement claim (the L4 oracle must be among s(CASP)'s answers),
# and PIN the surplus so it cannot grow or wander unnoticed.  A divergence that
# changes shape fails the run.  Delete an entry when the engine stops producing
# it -- an entry that no longer fires also fails, so this cannot rot.
KNOWN_SURPLUS = {
    ("benefit", "q1"): ["0"],
}


def have_scasp():
    swipl = shutil.which("swipl")
    if not swipl:
        return False, "swipl not on PATH"
    try:
        r = subprocess.run(
            [swipl, "-q", "-g", "use_module(library(scasp))", "-g", "halt"],
            capture_output=True, text=True, timeout=60,
        )
    except Exception as e:  # noqa: BLE001 - any failure means "absent"
        return False, f"swipl probe failed: {e}"
    if r.returncode != 0:
        return False, "scasp pack not installed"
    return True, ""


# --- .blawx parsing (the restricted subset `l4 blawx` emits) ---------------

def parse_blawx(path):
    """Return (workspaces, tests): lists of (name, encoding) in file order."""
    workspaces, tests = [], []
    model = name = None
    enc_lines = None       # collecting a |- block scalar when not None
    for line in path.read_text(encoding="utf-8").splitlines():
        if enc_lines is not None:
            if line == "" or line.startswith("      "):
                enc_lines.append(line[6:] if line.startswith("      ") else "")
                continue
            enc = "\n".join(enc_lines)
            (workspaces if model == "workspace" else tests).append((name, enc))
            enc_lines = None  # fall through to normal handling
        m = re.match(r"- model: blawx\.(\w+)", line)
        if m:
            model, name = m.group(1), None
            continue
        m = re.match(r"    (?:workspace|test)_name: (\S+)", line)
        if m:
            name = m.group(1)
            continue
        if line == "    scasp_encoding: |-" and model in ("workspace", "blawxtest"):
            model = "workspace" if model == "workspace" else "test"
            enc_lines = []
    if enc_lines is not None:
        enc = "\n".join(enc_lines)
        (workspaces if model == "workspace" else tests).append((name, enc))
    return workspaces, tests


# --- oracle parsing --------------------------------------------------------

def parse_oracles(path):
    """[(directive_line, expected_text)] in directive order."""
    oracles, pending = [], None
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("#EVAL") or s.startswith("#ASSERT"):
            if pending is not None:
                oracles.append((pending, None))
            pending = s
        elif s.startswith("-- L4 oracle ==>") and pending is not None:
            oracles.append((pending, s[len("-- L4 oracle ==>"):].strip()))
            pending = None
    if pending is not None:
        oracles.append((pending, None))
    return oracles


# --- reasoner.py's dedup pass ---------------------------------------------

VAR_RE = re.compile(r"[^\w]([A-Z_]\w*)")
REPLACEMENTS = list("ABCDEFGHIJKLMNOPQ")


def simplify_rule(rule):
    """reasoner.py:1036 — normalise variable names in appearance order."""
    for index, var in enumerate(VAR_RE.findall(rule)):
        if index < len(REPLACEMENTS):
            rule = rule.replace(var, REPLACEMENTS[index])
    return rule


def dedup(encodings):
    """reasoner.py:489-530 — strip markers, collect the marked line once."""
    ruleset, unique_rules = [], []
    for enc in encodings:
        ruleset.append("")
        register = False
        for line in enc.splitlines():
            if line == "% BLAWX CHECK DUPLICATES":
                register = True
            elif register:
                register = False
                simplified = simplify_rule(line)
                if simplified not in unique_rules:
                    unique_rules.append(simplified)
            else:
                ruleset.append(line)
    return "\n".join(ruleset + unique_rules)


def strip_preds(text):
    return "\n".join(
        ln for ln in text.splitlines() if not ln.lstrip().startswith("#pred ")
    )


# --- per-test program assembly and execution -------------------------------

def run_test(swipl, seed, test_name, query, program_body, oracle, keep_dir,
             bridge=""):
    goal = query[len("?- "):-1]  # chop "?- " and the final "."
    out_vars = re.findall(r"(?<![\w'])([A-Z_]\w*)", goal)
    # ENUMERATE, DO NOT COMMIT.  This was an if-then-else around scasp/2, which
    # takes the FIRST model and never looks again -- so a query with several
    # answer substitutions was compared on one of them and the rest were
    # invisible.  That is exactly the shape the lift renders `?- p(A).` into
    # (`filter p `all objects``, i.e. an enumeration of the universe), so the
    # one comparison most likely to disagree was the one least able to say so.
    # `sort/2` also dedupes: s(CASP) can return the same substitution under
    # more than one justification, which is not a disagreement.
    tmpl = "[" + ",".join(out_vars) + "]"
    main = (
        f"main :-\n"
        f"    findall({tmpl}, scasp(({goal}), [model(_)]), Rows0),\n"
        f"    sort(Rows0, Rows),\n"
        f"    ( Rows == [] -> format(\"NOMODEL~n\", [])\n"
        f"    ;  forall(member(Row, Rows), format(\"ROW ~q~n\", [Row])),\n"
        f"       format(\"MODEL~n\", []) ),\n"
        f"    halt(0).\n"
        f"main :- format(\"HARNESSERROR~n\", []), halt(1).\n"
    )
    now = time.time()
    today = now - (now % 86400)
    scasp_now = f"blawx_now(datetime({now})).\nblawx_today(date({today})).\n"
    program = "\n\n".join([
        PREAMBLE,
        strip_preds(VENDORED.read_text(encoding="utf-8")),
        scasp_now,
        program_body,
        bridge,
        main,
    ])
    pl = keep_dir / f"{seed}-{test_name}.pl"
    pl.write_text(program, encoding="utf-8")
    r = subprocess.run(
        [swipl, "-q", "-g", "main", str(pl)],
        capture_output=True, text=True, timeout=300,
    )
    rows = [split_row(m) for m in re.findall(r"^ROW (\[.*\])$", r.stdout, re.M)]
    model = bool(rows)

    if oracle is None:
        return False, "no oracle comment in the .l4"
    if oracle in ("TRUE", "assertion satisfied"):
        # "assertion satisfied" is what `l4 run` prints for an #ASSERT; the
        # emitted test carries the assertion as a `false :-` constraint, so
        # "a model exists" checks both the query and the constraint
        return (model, f"expected a model; got {'model' if model else 'NO model'}")
    if oracle == "FALSE":
        return (not model, f"expected no model; got {'model' if model else 'NO model'}")
    if len(out_vars) != 1:
        return False, f"expected one output variable in {goal!r}, saw {out_vars}"
    got = sorted({row[0] for row in rows})
    # The lift renders `?- p(A).` as `filter p `all objects`` -- an enumeration
    # of the object universe -- so its L4 counterpart is a LIST and s(CASP)'s
    # is the set of answer substitutions. Compare them as SETS: one element or
    # twenty, order is not meaning on either side, but a missing element is.
    if oracle.startswith("LIST "):
        want = sorted(i.strip().strip('"') for i in oracle[len("LIST "):].split(","))
        return (got == want, f"expected {want}; got {got}")
    # value oracle: the L4 answer must be among s(CASP)'s, and any surplus must
    # be exactly the pinned one (KNOWN_SURPLUS) -- absent, or larger, is a fail
    if not model:
        return False, f"expected {oracle}; got NO model"
    surplus = [g for g in got if g != oracle]
    pinned = KNOWN_SURPLUS.get((seed, test_name), [])
    if surplus != pinned:
        return False, (
            f"expected {oracle}"
            + (f" plus the pinned surplus {pinned}" if pinned else " and nothing else")
            + f"; got {got}"
        )
    detail = f"expected {oracle}; got {oracle}" + (
        f" (+ pinned s(CASP) surplus {pinned}, see KNOWN_SURPLUS)" if pinned else ""
    )
    return (oracle in got, detail)


def split_row(text):
    """Split a printed Prolog list `[a,b,c]` at TOP-LEVEL commas."""
    inner, depth, cur, out = text[1:-1], 0, "", []
    if not inner:
        return []
    for ch in inner:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    out.append(cur.strip())
    return out


def main():
    ok, why = have_scasp()
    if not ok:
        print(f"blawx-tier1: SKIP ({why}) — the harness is optional-when-present")
        return 0
    swipl = shutil.which("swipl")
    seeds = sys.argv[1:] or (SEEDS + sorted(IMPORTED))
    keep_dir = Path(tempfile.mkdtemp(prefix="blawx-tier1-"))
    failures = 0
    total = 0
    for seed in seeds:
        # Export seeds sit at examples/blawx/<seed>.l4 with their golden under
        # expected/; import seeds have both halves in one subdirectory, because
        # BOTH were produced by the pipeline rather than one being a golden.
        subdir = IMPORTED.get(seed)
        bridge = IMPORT_BRIDGE if subdir else ""
        if subdir:
            l4 = EXAMPLES / subdir / f"{seed}.l4"
            blawx = EXAMPLES / subdir / f"{seed}.blawx"
        else:
            l4 = EXAMPLES / f"{seed}.l4"
            blawx = EXAMPLES / "expected" / f"{seed}.blawx"
        if not blawx.exists():
            print(f"blawx-tier1: {seed}: missing golden {blawx}")
            failures += 1
            continue
        workspaces, tests = parse_blawx(blawx)
        # the "interview" test (#abducible declarations + a free-variable
        # query) has no L4 oracle — abduction is not evaluation — so it is
        # excluded from the directive pairing below
        tests = [(n, e) for n, e in tests if n != "interview"]
        oracles = parse_oracles(l4)
        if len(oracles) != len(tests):
            print(
                f"blawx-tier1: {seed}: {len(tests)} tests in the .blawx but "
                f"{len(oracles)} directives in the .l4 — cannot pair"
            )
            failures += 1
            continue
        for (test_name, enc), (directive, oracle) in zip(tests, oracles):
            total += 1
            query = next(
                (ln for ln in enc.splitlines() if ln.startswith("?- ")), None
            )
            if query is None:
                print(f"blawx-tier1: {seed}/{test_name}: no ?- query line")
                failures += 1
                continue
            # reasoner.py never consults the query line: it scans for the
            # final `?- …` and chops it out of the loaded program. Mirror
            # that — leaving it in would run the query as a plain-Prolog
            # consult-time directive, which can hang on programs that only
            # terminate under s(CASP)'s loop detection and prints spurious
            # consult warnings on failure.
            enc_body = "\n".join(
                ln for ln in enc.splitlines() if not ln.startswith("?- ")
            )
            body = strip_preds(
                dedup([e for _, e in workspaces] + [enc_body])
            )
            passed, detail = run_test(
                swipl, seed, test_name, query, body, oracle, keep_dir, bridge
            )
            status = "PASS" if passed else "FAIL"
            print(f"blawx-tier1: {status} {seed}/{test_name}: {directive}  [{detail}]")
            if not passed:
                failures += 1
    print(
        f"blawx-tier1: {total - failures}/{total} passed"
        + ("" if failures == 0 else f" — {failures} FAILED; programs kept in {keep_dir}")
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
