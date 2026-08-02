#!/usr/bin/env python3
"""Regenerate charity-test.cases.json.

EVERY expected value in the cases file is EVALUATED BY THE L4 BINARY, never
hand-typed. That is the whole activation contract of an engine-case file: a pin
copied off a DMN engine's own output is vacuous, and a pin typed by hand is a
second, unverified encoding of the law. This script closes both holes:

  * the pins come from `l4 --json` run over the corpus with generated `#EVAL`
    directives appended -- one per (world, decision) pair, in a deterministic
    order that is zipped back against the plan;
  * the CONTEXT for each world comes from `#EVAL <the entity>` /
    `#EVAL <the purpose>` -- i.e. the same evaluator prints the record, and this
    script only re-keys it, mapping field POSITION to the FEEL component name
    read out of the emitted DMN's own `<itemDefinition>`. So the JSON keys are
    the emitter's, the JSON values are the evaluator's, and neither is mine.

The only hand-authored thing here is WORLDS: which (entity, purpose) pair each
case probes, and the one-line reason. That is a choice of experiment, not a
claim about the law.

Usage (from the repo root):

    JL4_LIBRARY_PATH=$PWD/jl4-core/libraries \\
      python3 jl4/examples/legal/charities-cleanroom/projections/make-cases.py \\
        --l4 <path to the built l4 binary> \\
        --dmn jl4/examples/legal/charities-cleanroom/projections/charity-test.dmn

Writes ../charity-test.cases.json.
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, os.pardir, "charity-test.l4")
OUT = os.path.join(HERE, os.pardir, "charity-test.cases.json")

# (entity fixture, purpose fixture, why this world is here).
#
# The DMN model has ONE global `entity` and ONE global `purpose` input -- that is
# D-PARAM-AS-INPUT, and it is why a case is a PAIR rather than an entity alone.
WORLDS = [
    ("the St Helier poverty trust", "a poverty-relief purpose",
     "the clean base case: one charitable purpose, a sound finding, a clean constitution"),
    ("the poverty trust with a charity shop", "an ancillary fundraising purpose",
     "A9 satisfied - an ancillary purpose WITH a charitable purpose behind it"),
    ("the charity shop with nothing behind it", "an ancillary fundraising purpose",
     "A9 refused - the same ancillary purpose with nothing to be ancillary TO"),
    ("the poverty trust with a party-political object", "a party-political purpose",
     "6(5) purpose-level carve-out: a political purpose defeats 5(1)(a)"),
    ("the poverty trust with incidental campaigning", "an ancillary party-political purpose",
     "6(5) double reach: a political purpose cannot be rescued by calling it ancillary"),
    ("the grocery company", "a purely commercial purpose",
     "no Article 6(1) head reached at all"),
    ("the entity with no purposes", "a poverty-relief purpose",
     "A10 vacuous truth: no purposes, so 5(1)(a) passes and 5(1)(b) decides"),
    ("the entity with no purposes and no benefit", "a poverty-relief purpose",
     "A10 with the benefit limb also failing - why 5(1)(a)'s vacuity is nearly harmless"),
    ("the disease-prevention trust", "a sickness-prevention purpose",
     "6(2)(a) WIDENS head (d): sickness prevention without advancing health"),
    ("the pigeon fanciers' association", "a spectator-pastime purpose",
     "6(2)(c) GATE fails: a pastime that is not sport involving physical skill and exertion"),
    ("the island swimming association", "a physical-sport purpose",
     "6(2)(c) GATE passes"),
    ("the members-only tennis club", "a members-only recreation purpose",
     "6(2)(d) GATE fails: recreation neither need-directed nor open to the public"),
    ("the public recreation ground trust", "an open recreation purpose",
     "6(2)(d) GATE passes on its second limb"),
    ("the humanist society", "a philosophical-belief purpose",
     "6(2)(f) DEEMS philosophical belief into head (p) with no separate analogy judgement"),
    ("the Ministerially directed trust", "a poverty-relief purpose",
     "5(2) direction mode"),
    ("the Ministerially directed trust exempted by Order", "a poverty-relief purpose",
     "5(3): a Ministerial Order disapplies 5(2)"),
    ("the States-governed foundation", "a poverty-relief purpose",
     "5(2) governor mode, limb (b)"),
    ("the Guernsey-governed foundation", "a poverty-relief purpose",
     "5(2) governor mode, limb (c) - the foreign equivalent"),
    ("the trust with a Minister in a private capacity", "a poverty-relief purpose",
     "5(2) 'acting in that capacity' not extended, so no disqualification"),
    ("the dormant registered charity", "a poverty-relief purpose",
     "A11 negative: a registered charity that only INTENDS to provide benefit"),
    ("the applicant not yet operating", "a poverty-relief purpose",
     "A11 positive: the same finding, but the entity is an applicant"),
    ("the grandchildren's trust", "a poverty-relief purpose",
     "7(3)(b) hard bar defeats an affirmative 5(1)(b) finding"),
    ("the school with an unduly restrictive fee", "a poverty-relief purpose",
     "A7: 'unduly restrictive' is a consideration, not a defeater - the test still passes"),
    ("the church whose benefit was presumed", "a poverty-relief purpose",
     "A8: a presumption-tainted determination is improperly made, yet the test passes on the merits"),
    ("the entity whose determiner skipped 7(2)(b)", "a poverty-relief purpose",
     "A8/7(2)(b): the determiner skipped the question, so the determination is improperly made"),
]


def read_dmn(path):
    """FEEL component names per itemDefinition, and FEEL/L4 names per decision."""
    x = open(path, encoding="utf-8").read()
    items = {}
    for m in re.finditer(
        r'<itemDefinition id="[^"]+" name="([^"]+)">(.*?)</itemDefinition>', x, re.S
    ):
        items[m.group(1)] = re.findall(
            r'<itemComponent id="[^"]+" name="([^"]+)"', m.group(2)
        )
    decisions = [
        (m.group(1), unescape(m.group(2)))
        for m in re.finditer(r'<decision id="[^"]+" name="([^"]+)" label="([^"]*)">', x)
    ]
    return items, decisions


def unescape(s):
    for a, b in (("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"'),
                 ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")):
        s = s.replace(a, b)
    return s


def params_of(src_lines, l4name):
    """The GIVEN parameters of an L4 definition, read off the source."""
    for i, line in enumerate(src_lines):
        s = line.strip()
        is_def = s.startswith("DECIDE `" + l4name + "`") or (
            s.startswith("`" + l4name + "`") and " MEANS" in s
        )
        if not is_def:
            continue
        j = i - 1
        while j >= 0:
            t = src_lines[j].strip()
            if t.startswith("GIVEN "):
                body = t[len("GIVEN "):]
                out = []
                for part in body.split(","):
                    nm = re.split(r"\s+IS\s+", part.strip())[0].strip().strip("`")
                    if nm in ("entity", "purpose"):
                        out.append(nm)
                return out
            if t.startswith(("GIVETH", "@", "--")) or t == "":
                j -= 1
                continue
            break
        return []
    return []


TOK = re.compile(r'"(?:[^"\\]|\\.)*"|[(),]|[A-Za-z_][A-Za-z0-9_]*|\S')


class ValueParser:
    """Parse the evaluator's printed value syntax into JSON.

    Record arity comes from the emitted DMN's itemDefinitions, so element
    boundaries inside a printed LIST are recovered without guessing.
    """

    def __init__(self, toks, items):
        self.t, self.i, self.items = toks, 0, items
        self.arity = {k: len(v) for k, v in items.items()}

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else None

    def next(self):
        v = self.t[self.i]
        self.i += 1
        return v

    def expect(self, v):
        got = self.next()
        assert got == v, (v, got, self.t[max(0, self.i - 5):self.i + 5])

    def value(self):
        t = self.peek()
        if t == "(":
            self.next()
            v = self.value()
            self.expect(")")
            return v
        if t == "TRUE":
            self.next()
            return True
        if t == "FALSE":
            self.next()
            return False
        if t == "EMPTY":
            self.next()
            return []
        if t and t.startswith('"'):
            return json.loads(self.next())
        if t == "LIST":
            self.next()
            out = [self.value()]
            while self.peek() == "," and self.peek(1) in self.arity:
                self.next()
                out.append(self.value())
            return out
        if t in self.arity:
            ctor = self.next()
            self.expect("OF")
            vals = []
            for k in range(self.arity[ctor]):
                if k:
                    self.expect(",")
                vals.append(self.value())
            return dict(zip(self.items[ctor], vals))
        raise AssertionError("unexpected token %r near %r" % (t, self.t[self.i:self.i + 6]))


def parse_value(s, items):
    p = ValueParser(TOK.findall(s), items)
    v = p.value()
    assert p.i == len(p.t), "trailing tokens: %r" % (p.t[p.i:p.i + 6],)
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--l4", required=True, help="path to the built l4 binary")
    ap.add_argument("--dmn", required=True, help="path to the emitted charity-test.dmn")
    ap.add_argument("--note", default=None, help="path to a JSON array of note lines")
    a = ap.parse_args()

    items, decisions = read_dmn(a.dmn)
    src = open(CORPUS, encoding="utf-8").read()
    src_lines = src.split("\n")
    decs = [(feel, l4, params_of(src_lines, l4)) for feel, l4 in decisions]

    evals, plan = [], []
    for wi, (e, p, _why) in enumerate(WORLDS):
        evals.append("#EVAL `%s`" % e)
        plan.append((wi, "entity", None))
        evals.append("#EVAL `%s`" % p)
        plan.append((wi, "purpose", None))
        for feel, l4, ps in decs:
            args = "".join(" `%s`" % (e if q == "entity" else p) for q in ps)
            evals.append("#EVAL `%s`%s" % (l4, args))
            plan.append((wi, "dec", feel))

    tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "charity-test.cases.eval.l4")
    open(tmp, "w", encoding="utf-8").write(
        src + "\n\n§§ `Generated engine-case evaluations`\n\n" + "\n".join(evals) + "\n"
    )
    r = subprocess.run([a.l4, tmp, "--json"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("l4 failed (exit %d):\n%s" % (r.returncode, r.stderr[-4000:]))
    res = json.loads(r.stdout)["results"][-len(plan):]

    worlds = {}
    for (wi, kind, key), item in zip(plan, res):
        assert item["kind"] == "value", item
        w = worlds.setdefault(wi, {"context": {}, "expect": {}})
        if kind == "dec":
            assert item["value"] in ("TRUE", "FALSE"), (key, item["value"])
            w["expect"][key] = item["value"] == "TRUE"
        else:
            w["context"][kind] = parse_value(item["value"], items)

    order = [feel for feel, _l4, _ps in decs]
    cases = [
        {
            "name": "%s + %s - %s" % (e, p, why),
            "context": {"entity": worlds[i]["context"]["entity"],
                        "purpose": worlds[i]["context"]["purpose"]},
            "expect": {k: worlds[i]["expect"][k] for k in order},
        }
        for i, (e, p, why) in enumerate(WORLDS)
    ]
    note = json.load(open(a.note, encoding="utf-8")) if a.note else []
    json.dump({"note": note, "cases": cases}, open(OUT, "w", encoding="utf-8"), indent=1)
    print("wrote %s: %d case(s) x %d pin(s)" % (OUT, len(cases), len(order)))


if __name__ == "__main__":
    main()
