#!/usr/bin/env python3
"""Derive a DMN cases file's `expect` block from L4 itself.

The engine harnesses (etc/kie-dmn-check, etc/camunda-dmn-check) already compare a
model's answers against each case's `expect`. But that block is HAND-WRITTEN, so a
green run says "the DMN agrees with what a human typed", not "the DMN agrees with
the L4 it was lowered from". Replace `expect` with L4's own answers and the
existing comparison becomes a differential -- no new engine integration.

    l4-derive-cases.py L4_BIN MODULE.l4 CASES.json -o DERIVED.json

Then, unchanged:

    etc/kie-dmn-check/run.sh     MODEL.dmn --cases DERIVED.json
    etc/camunda-dmn-check/run.sh MODEL.dmn --cases DERIVED.json

Results are read back by SOURCE LINE, not by position: `l4 run` reports each
#EVAL as a diagnostic carrying `Range: <line>:<col>-...` and `Source: eval`, so
the driver records which line it wrote each evaluation on and pairs on that. A
positional pairing would silently misattribute every value after the first
evaluation that fails to produce one.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

DATE_TAG = "$date"  # the fixture vocabulary's only spelling of a FEEL date


def feel_name(l4_name):
    """L4 name -> the FEEL name a cases file keys on.

    NOT `replace(" ", "_")`: DMN 9.2 rule 27 admits `.` `/` `-` `+` `*` inside a
    FEEL name, but the lowering does not keep them -- the ASSUME
    `no GST rate exists before commencement on 1994-04-01` is keyed
    `no_GST_rate_exists_before_commencement_on_1994_04_01`, hyphens and all
    folded to underscores. Getting this wrong silently fails to bind the
    assumption and the decision then reports UNEVALUABLE, which is how it was
    found.
    """
    return re.sub(r"[^A-Za-z0-9]+", "_", l4_name)


def l4_literal(v):
    """A JSON case value as an L4 expression. L4 spells a date day-first."""
    if isinstance(v, dict) and DATE_TAG in v:
        y, m, d = v[DATE_TAG].split("-")
        return f"(Date {int(d)} {int(m)} {int(y)})"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, float)):
        return f"(0 MINUS {abs(v)})" if v < 0 else str(v)
    if isinstance(v, str):
        return json.dumps(v)
    raise ValueError(f"no L4 spelling for {v!r}")


def parse_value(text):
    """Read one #EVAL result back.

    Conservative on purpose: an unrecognised shape becomes {"$unparsed": ...}
    and is reported, never guessed at. A differential that guesses is worse than
    one that declines to answer.
    """
    t = text.strip()
    if t in ("TRUE", "FALSE"):
        return t == "TRUE"
    if re.fullmatch(r"-?\d+", t):
        return int(t)
    if re.fullmatch(r"-?\d+\.\d+", t):
        return float(t)
    # `l4 run` prints a date as `DATE OF D, M, Y` -- day first, matching the
    # `Date D M Y` constructor rather than the ISO order the cases file uses.
    # Measured, not assumed: the constructor spelling `Date 1 4 1994` never
    # appears in output, so accept both and let anything else be $unparsed.
    m = re.fullmatch(r"DATE\s+OF\s+(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", t, re.I) \
        or re.fullmatch(r"Date\s+(\d+)\s+(\d+)\s+(\d+)", t)
    if m:
        d, mo, y = (int(x) for x in m.groups())
        return {DATE_TAG: f"{y:04d}-{mo:02d}-{d:02d}"}
    if len(t) >= 2 and t[0] == '"' and t[-1] == '"':
        try:
            return json.loads(t)
        except json.JSONDecodeError:
            pass
    return {"$unparsed": t}


def read_signatures(src):
    """Each definition's GIVEN parameters, read off the module.

    Read from the source rather than configured, so the driver cannot drift from
    the module it is evaluating.
    """
    params, pending = {}, None
    for line in src.splitlines():
        g = re.match(r"^GIVEN\s+(.*)$", line)
        if g:
            pending = re.findall(r"`([^`]+)`\s+IS\s+A|(\w+)\s+IS\s+A", g.group(1))
            pending = [a or b for a, b in pending]
            continue
        if re.match(r"^(GIVETH|@|--|\s*$)", line):
            continue
        d = re.match(r"^`([^`]+)`", line)
        if d:
            params[d.group(1)] = pending or []
            pending = None
        elif pending is not None and not line.startswith(" "):
            pending = None
    return params


ASSUME_RE = re.compile(r"^ASSUME\s+`([^`]+)`\s+IS\s+AN?\s+\w+\s*$", re.M)


def assumed_names(src):
    """Module-level ASSUMEs: declared without a value, so a driver must supply one."""
    return set(ASSUME_RE.findall(src))


def bind_assumes(src, ctx):
    """Rewrite `ASSUME x IS A T` as a definition when the case supplies a value.

    An ASSUMEd name is already bound, so a driver cannot shadow it by appending
    a definition -- the binding has to replace the declaration in place. This is
    why drivers are per-case: two cases can assume different values for the same
    name, as gst-rate's pre-commencement floor does.
    """
    def sub(m):
        name = m.group(1)
        key = feel_name(name)
        if key in ctx:
            return f"`{name}` MEANS {l4_literal(ctx[key])}"
        if name in ctx:
            return f"`{name}` MEANS {l4_literal(ctx[name])}"
        return m.group(0)
    return ASSUME_RE.sub(sub, src)


def build_driver(src, cases, decisions, params, rule_date_key):
    """Module + one #EVAL per (case, decision). Returns (text, {line: (ci, dec)})."""
    lines = src.rstrip().split("\n")
    lines += ["", "-- >>> differential driver (generated by l4-derive-cases.py) >>>"]
    index, skipped = {}, []
    for ci, case in enumerate(cases):
        ctx = case.get("context", {})
        lines.append(f"-- case {ci}: {case.get('name', '')}")
        rd = ctx.get(rule_date_key)
        for dec in decisions:
            sig = params.get(dec)
            if sig is None:
                skipped.append((ci, dec, "NOT-IN-MODULE"))
                continue
            args, missing = "", None
            for p in sig:
                # A parameter is supplied by the case context under its FEEL name.
                key = feel_name(p)
                if key in ctx:
                    args += " " + l4_literal(ctx[key])
                elif p in ctx:
                    args += " " + l4_literal(ctx[p])
                else:
                    missing = p
                    break
            if missing:
                # A module-level ASSUME is declared without being defined, and a
                # driver cannot redefine an already-bound name -- so an
                # unsatisfiable signature is REPORTED, never silently dropped.
                skipped.append((ci, dec, f"UNBOUND:{missing}"))
                continue
            expr = f"`{dec}`{args}"
            if rd is not None:
                # Per-expression law time. This is also what makes the corpus's
                # 15 unlowerable D-RULEDATE-UNBOUND decisions evaluable here even
                # though no <decision> exists for them.
                expr = f"`EVAL UNDER RULES EFFECTIVE AT` {l4_literal(rd)} ({expr})"
            lines.append(f"#EVAL {expr}")
            index[len(lines)] = (ci, dec)  # 1-based source line
    return "\n".join(lines) + "\n", index, skipped


def run_l4(l4_bin, path):
    p = subprocess.run([l4_bin, "run", str(path)], capture_output=True,
                       text=True, timeout=1800)
    return p.returncode, p.stdout + "\n" + p.stderr


BLOCK = re.compile(
    r"Range:\s*(\d+):\d+-\d+:\d+\s*\n\s*Source:\s*(\w+).*?\n\s*Message:\s*(.*?)(?=\n\s*\w+:|\nFile:|\Z)",
    re.S)


def harvest(out):
    """{line: value} for eval diagnostics; {line: text} for errors on those lines."""
    vals, errs = {}, {}
    for ln, src, msg in BLOCK.findall(out):
        if src == "eval":
            vals[int(ln)] = msg.strip()
        elif src == "check":
            errs.setdefault(int(ln), msg.strip())
    return vals, errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("l4_bin"); ap.add_argument("module"); ap.add_argument("cases")
    ap.add_argument("-o", "--out")
    ap.add_argument("--driver", default="/tmp/diffh/driver.l4")
    ap.add_argument("--rule-date-key", default="RULES_EFFECTIVE_DATE")
    a = ap.parse_args()

    spec = json.loads(Path(a.cases).read_text())
    cases = spec["cases"]
    feel = sorted({k for c in cases for k in c.get("expect", {})})

    src = Path(a.module).read_text()
    params = read_signatures(src)
    l4_of_feel = {feel_name(n): n for n in params}
    decisions = [l4_of_feel.get(f, f.replace("_", " ")) for f in feel]

    # One driver PER CASE: an ASSUMEd name is already bound, so binding it means
    # replacing its declaration, and two cases may assume different values for
    # the same name (gst-rate's pre-commencement floor does exactly that).
    assumed = assumed_names(src)
    dpath = Path(a.driver)
    vals, errs, index, skipped = {}, {}, {}, []
    rc = 0
    for ci, case in enumerate(cases):
        bound = bind_assumes(src, case.get("context", {}))
        d, idx, sk = build_driver(bound, [case], decisions, params, a.rule_date_key)
        p = dpath.with_name(f"{dpath.stem}-{ci}{dpath.suffix}")
        p.write_text(d)
        r, out = run_l4(a.l4_bin, p)
        rc = rc or r
        v, e = harvest(out)
        # Re-key this case's line numbers into the global index.
        for line, (_, dec) in idx.items():
            index[(ci, line)] = (ci, dec)
            if line in v:
                vals[(ci, line)] = v[line]
            elif line in e:
                errs[(ci, line)] = e[line]
        skipped += [(ci, s[1], s[2]) for s in sk]
    if assumed:
        print(f"module ASSUMEs bound per case: {sorted(assumed)}", file=sys.stderr)

    derived, unevaluable = [], []
    report = {"AGREE-SHAPE": 0, "UNEVALUABLE": 0, "UNPARSED": 0}
    for ci, case in enumerate(cases):
        exp = {}
        for (c, line), (_, dec) in index.items():
            if c != ci:
                continue
            if (c, line) in vals:
                v = parse_value(vals[(c, line)])
                if isinstance(v, dict) and "$unparsed" in v:
                    report["UNPARSED"] += 1
                else:
                    report["AGREE-SHAPE"] += 1
                exp[feel_name(dec)] = v
            else:
                report["UNEVALUABLE"] += 1
                unevaluable.append((ci, dec, errs.get((c, line), "no value")))
        derived.append({"name": case.get("name", f"case {ci}"),
                        "context": case.get("context", {}), "expect": exp})

    hand = {(ci, k): v for ci, c in enumerate(cases) for k, v in c.get("expect", {}).items()}
    drv = {(ci, k): v for ci, c in enumerate(derived) for k, v in c["expect"].items()}
    disagree = sorted(k for k in hand.keys() & drv.keys() if hand[k] != drv[k])

    out_doc = {
        "note": [
            "GENERATED by l4-derive-cases.py -- do not hand-edit.",
            "`expect` is what L4 answers, not what an author expects. Feeding this",
            "to the engine harnesses turns their existing comparison into a",
            "differential between L4 and the DMN lowering.",
            f"module: {a.module}   source cases: {a.cases}",
        ],
        "cases": derived,
    }
    if a.out:
        Path(a.out).write_text(json.dumps(out_doc, indent=2) + "\n")

    print(f"l4 exit={rc}", file=sys.stderr)
    print(f"evaluations emitted : {len(index)}", file=sys.stderr)
    print(f"  values harvested  : {report['AGREE-SHAPE']}", file=sys.stderr)
    print(f"  unparsed shapes   : {report['UNPARSED']}", file=sys.stderr)
    print(f"  no value returned : {report['UNEVALUABLE']}", file=sys.stderr)
    print(f"skipped (unbound/absent): {len(skipped)}", file=sys.stderr)
    for s in skipped[:8]:
        print(f"    case {s[0]} {s[1]!r}: {s[2]}", file=sys.stderr)
    for u in unevaluable[:5]:
        print(f"    UNEVALUABLE case {u[0]} {u[1]!r}: {str(u[2])[:120]}", file=sys.stderr)
    print(f"\nhand-written vs L4-derived: {len(disagree)} disagreement(s) "
          f"over {len(hand.keys() & drv.keys())} shared expectation(s)", file=sys.stderr)
    for k in disagree[:10]:
        print(f"    case {k[0]} {k[1]}: hand={hand[k]!r} l4={drv[k]!r}", file=sys.stderr)

    # A disagreement here is not yet a DMN finding -- it is L4 vs the AUTHOR.
    # The DMN comparison happens when the engine harnesses consume --out.
    return 0


if __name__ == "__main__":
    sys.exit(main())
