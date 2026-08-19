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

A seed written in the top-level `ASSUME` spelling has no evaluable directive of
its own (see TWINS below): for those, steps 2 and 4 read the tests and the
oracles off the seed's SEMANTIC TWIN and replay them against the ASSUME seed's
workspaces, so the expectation is still an `l4 run` measurement and never a
hand-derived number. The replay is a RE-EXECUTION, not a second independent
check — the two spellings emit byte-identical programs, which is the property
`twin_preflight` measures and fails on — so replayed rows are counted apart from
the distinct population in the summary line.

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
SEEDS = [
    "benefit", "mortality", "scores", "sumlist",
    "rodents",
    "antisocial", "antisocial-twin",
    "alcohol", "alcohol-twin",
    "housing-grounds",
]

# --- the ASSUME seeds' oracle, and why it is not written here --------------
#
# A module written in the top-level `ASSUME` spelling has NO evaluable
# directive. `ASSUME` is uninterpreted, so `l4 run` cannot answer for one of its
# decisions; and `lowerQuery` builds a test scenario only out of a record-literal
# query argument, so an `#EVAL` there would lower to a query with no facts at
# all. Such a seed's `.blawx` therefore carries the `interview` test and nothing
# else, and the pairing below would compare zero oracles against zero tests and
# report a PASS having executed nothing. A vacuous green is worse than a red: it
# looks like coverage.
#
# The honest anchor is a SEMANTIC TWIN — the same logic spelled with `DECLARE`
# records whose names and field names are the ASSUME'd names character for
# character. Because a boolean field reaches this leg through the
# boolean-projection peephole as the same signed unary goal an ASSUME'd input
# gives, and a value field gives the same binary goal an ASSUME'd accessor does,
# the two spellings mangle to the SAME s(CASP) atoms at the SAME arities.
#
# WHAT IS ACTUALLY BEING TESTED, stated plainly because the earlier wording of
# this comment ("one logic, two spellings, cross-checked") overclaimed:
#
#   * the twin supplies the ORACLE. Its `#EVAL`s run under `l4 run`, so no
#     expectation anywhere in this harness is hand-derived.
#   * the PROPERTY under test is the byte identity itself — that the ASSUME seed
#     and its twin emit the same rule stack and the same workspace encodings.
#     `twin_preflight` below measures it on every run and FAILS on divergence;
#     `twinsAgree` in `jl4/tests-cli/Main.hs` asserts the same thing in Haskell.
#   * the replay that follows is NOT independent coverage. Measured on this
#     tree, the seed's workspace encodings are byte-identical to the twin's, so
#     the program assembled for `alcohol/twin-qN` is character-for-character the
#     one assembled for `alcohol-twin/qN`. It cannot disagree. It is kept
#     because it executes the artifact a Blawx reader would actually load, and
#     because it is the thing that would start failing if identity were ever
#     lost — but it is counted separately in the summary and must never be
#     reported as extra queries covered.
TWINS = {"antisocial": "antisocial-twin", "alcohol": "alcohol-twin"}

PREAMBLE = """\
:- use_module(library(scasp)).
:- style_check(-discontiguous).
:- style_check(-singleton).
"""


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

def run_test(swipl, seed, test_name, query, program_body, oracle, keep_dir):
    goal = query[len("?- "):-1]  # chop "?- " and the final "."
    out_vars = re.findall(r"(?<![\w'])([A-Z_]\w*)", goal)
    show = "".join(
        f"format(\"BIND {v} = ~w~n\", [{v}]), " for v in out_vars
    )
    main = (
        f"main :-\n"
        f"    ( scasp(({goal}), [model(_), tree(_)])\n"
        f"    -> {show}format(\"MODEL~n\", [])\n"
        f"    ;  format(\"NOMODEL~n\", []) ),\n"
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
        main,
    ])
    pl = keep_dir / f"{seed}-{test_name}.pl"
    pl.write_text(program, encoding="utf-8")
    r = subprocess.run(
        [swipl, "-q", "-g", "main", str(pl)],
        capture_output=True, text=True, timeout=300,
    )
    binds = dict(re.findall(r"BIND (\w+) = (\S+)", r.stdout))
    model = "MODEL" in r.stdout and "NOMODEL" not in r.stdout

    if oracle is None:
        return False, "no oracle comment in the .l4"
    if oracle in ("TRUE", "assertion satisfied"):
        # "assertion satisfied" is what `l4 run` prints for an #ASSERT; the
        # emitted test carries the assertion as a `false :-` constraint, so
        # "a model exists" checks both the query and the constraint
        return (model, f"expected a model; got {'model' if model else 'NO model'}")
    if oracle == "FALSE":
        return (not model, f"expected no model; got {'model' if model else 'NO model'}")
    # value oracle: compare against the (single) output binding
    if not model:
        return False, f"expected {oracle}; got NO model"
    if len(out_vars) != 1:
        return False, f"expected one output variable in {goal!r}, saw {out_vars}"
    got = binds.get(out_vars[0])
    return (got == oracle, f"expected {oracle}; got {got}")


def twin_preflight(seed, twin):
    """Measure the property the twin discipline actually rests on: byte identity.

    This is the CHECK, not a preamble to one. The replay that follows re-runs a
    program assembled from the ASSUME seed's own workspace encodings; if those
    encodings and the twin's are identical — which is the claim — the replay is
    a tautology and proves nothing on its own. What carries the weight is that
    the two spellings emit the same rule stack and the same ontology, so that is
    what is measured here, on two fronts:

      * the emitted `.pl` (the whole rule stack plus the whole ontology), minus
        its first line, which is the provenance comment naming the source file
        and is expected to differ;
      * the `.blawx` workspace list, which is what the replay below actually
        loads. The `.pl` is derived from the same IR, but comparing the thing
        the replay uses costs nothing and closes the gap by construction.

    A divergence is FATAL. It used to be a printed note, on the reading that the
    replay would then still be "a weaker cross-check" — but a divergence in a
    predicate that only FALSE oracles exercise (8 of 18 rows for alcohol, 10 of
    17 for antisocial) would leave every one of those rows finding no model and
    "passing" having executed nothing against the seed's real atoms. That is the
    vacuous green this module's header refuses elsewhere, and it gets the same
    treatment here.

    Returns (ok, message).
    """
    a = EXAMPLES / "expected" / f"{seed}.pl"
    b = EXAMPLES / "expected" / f"{twin}.pl"
    if not (a.exists() and b.exists()):
        return False, f"missing .pl for {seed} or {twin} — cannot compare"
    ta = a.read_text(encoding="utf-8").split("\n", 1)[1]
    tb = b.read_text(encoding="utf-8").split("\n", 1)[1]
    if ta != tb:
        la, lb = ta.splitlines(), tb.splitlines()
        first = next(
            (i for i in range(max(len(la), len(lb)))
             if la[i:i + 1] != lb[i:i + 1]), 0
        )
        return False, (
            f"s(CASP) DIFFERS from the twin's (first at line {first + 2}: "
            f"{la[first:first + 1] or ['<eof>']} vs "
            f"{lb[first:first + 1] or ['<eof>']}) — the replay would compare "
            f"two DIFFERENT programs against one oracle"
        )
    ba = EXAMPLES / "expected" / f"{seed}.blawx"
    bb = EXAMPLES / "expected" / f"{twin}.blawx"
    if not (ba.exists() and bb.exists()):
        return False, f"missing .blawx for {seed} or {twin} — cannot compare"
    wa, _ = parse_blawx(ba)
    wb, _ = parse_blawx(bb)
    if wa != wb:
        names_a = [n for n, _ in wa]
        names_b = [n for n, _ in wb]
        return False, (
            f"workspace encodings DIFFER from the twin's "
            f"({names_a} vs {names_b}) — the replay below would load a "
            f"different program from the one the oracle was measured on"
        )
    return True, (
        "s(CASP) and workspace encodings byte-identical modulo the provenance "
        "comment — the replay below is therefore a re-execution, not an "
        "independent check"
    )


def main():
    ok, why = have_scasp()
    if not ok:
        print(f"blawx-tier1: SKIP ({why}) — the harness is optional-when-present")
        return 0
    swipl = shutil.which("swipl")
    seeds = sys.argv[1:] or SEEDS
    keep_dir = Path(tempfile.mkdtemp(prefix="blawx-tier1-"))
    # Three populations, deliberately NOT one counter. `seed_failures` counts
    # whole seeds that could not be run at all (they contribute no query rows);
    # `query_failures` counts rows that ran and disagreed. Subtracting the two
    # from one another — which the summary used to do — reports `n-1/n passed`
    # when nothing among the n rows failed, and can print a NEGATIVE numerator
    # when several seeds bail out and few rows run. `replayed` is the subset of
    # rows that are twin replays of a byte-identical program (see TWINS above):
    # real executions, but not independent coverage, and never to be added to a
    # headline "N queries" figure.
    seed_failures = 0
    query_failures = 0
    total = 0
    replayed = 0
    for seed in seeds:
        l4 = EXAMPLES / f"{seed}.l4"
        blawx = EXAMPLES / "expected" / f"{seed}.blawx"
        if not blawx.exists():
            print(f"blawx-tier1: {seed}: missing golden {blawx}")
            seed_failures += 1
            continue
        workspaces, tests = parse_blawx(blawx)
        # the "interview" test (#abducible declarations + a free-variable
        # query) has no L4 oracle — abduction is not evaluation — so it is
        # excluded from the directive pairing below
        tests = [(n, e) for n, e in tests if n != "interview"]
        oracles = parse_oracles(l4)
        prefix = ""
        twin = TWINS.get(seed)
        if twin is not None:
            # An ASSUME seed must contribute NOTHING of its own — if it ever
            # grows an evaluable directive, the twin discipline has been
            # misunderstood and the pairing below would silently mix sources.
            if tests or oracles:
                print(
                    f"blawx-tier1: {seed}: ASSUME seed has {len(tests)} tests and "
                    f"{len(oracles)} directives of its own; it must have none — "
                    f"its oracle comes from the twin {twin}"
                )
                seed_failures += 1
                continue
            ok_pre, why_pre = twin_preflight(seed, twin)
            status_pre = "ok" if ok_pre else "FAIL"
            print(f"blawx-tier1: {status_pre} {seed}: twin {twin} — {why_pre}")
            # FATAL, both for a missing file and for a real divergence: see
            # `twin_preflight`'s docstring. Replaying against a program whose
            # atoms no longer match the oracle's would let every FALSE row pass
            # by finding no model, which is exactly the vacuity the discipline
            # exists to prevent.
            if not ok_pre:
                seed_failures += 1
                continue
            # replay the twin's fact rows against THIS seed's workspaces
            _, tests = parse_blawx(EXAMPLES / "expected" / f"{twin}.blawx")
            tests = [(n, e) for n, e in tests if n != "interview"]
            oracles = parse_oracles(EXAMPLES / f"{twin}.l4")
            prefix = "twin-"
        if len(oracles) != len(tests):
            print(
                f"blawx-tier1: {seed}: {len(tests)} tests in the .blawx but "
                f"{len(oracles)} directives in the .l4 — cannot pair"
            )
            seed_failures += 1
            continue
        if not tests:
            print(
                f"blawx-tier1: {seed}: no executable test in the golden — a "
                f"vacuous pass, refusing to count it"
            )
            seed_failures += 1
            continue
        for (test_name, enc), (directive, oracle) in zip(tests, oracles):
            total += 1
            if twin is not None:
                replayed += 1
            query = next(
                (ln for ln in enc.splitlines() if ln.startswith("?- ")), None
            )
            if query is None:
                print(f"blawx-tier1: {seed}/{test_name}: no ?- query line")
                query_failures += 1
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
                swipl, seed, prefix + test_name, query, body, oracle, keep_dir
            )
            status = "PASS" if passed else "FAIL"
            # for a replayed row, say where the expectation came from: the
            # oracle must be traceable to an `l4 run` on a file that evaluates
            provenance = (
                "" if twin is None
                else f"  [oracle from {twin}/{test_name}: {oracle}]"
            )
            print(
                f"blawx-tier1: {status} {seed}/{prefix}{test_name}: "
                f"{directive}  [{detail}]{provenance}"
            )
            if not passed:
                query_failures += 1
    # `total` counts every row that ran, replays included; `total - replayed` is
    # the DISTINCT program population and is the only number a PR description or
    # a §10 EXECUTED entry may quote as coverage.
    distinct = total - replayed
    summary = f"blawx-tier1: {total - query_failures}/{total} queries passed"
    if replayed:
        summary += (
            f" ({distinct} distinct + {replayed} twin replays of a "
            f"byte-identical program, which are re-executions and not extra "
            f"coverage)"
        )
    if seed_failures:
        summary += f"; {seed_failures} seed(s) could not be run"
    if query_failures or seed_failures:
        summary += f" — programs kept in {keep_dir}"
    print(summary)
    return 1 if (query_failures or seed_failures) else 0


if __name__ == "__main__":
    sys.exit(main())
