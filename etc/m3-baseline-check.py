#!/usr/bin/env python3
"""Guard 2 for the M3 gate measurement: is the simulated declaration-order asker
the REAL emitted behaviour?

`m3-measure` compares three askers over a decision's boolean skeleton. The
plan-order asker is the shipped ranker, so it cannot be wrong about itself. The
declaration-order asker is a SIMULATION, and if it is a strawman -- "ask every
atom", a left-to-right walk that forgets short-circuit, or a walk over a
NORMALISED form the emitter never produces -- then every number downstream is
wrong in the planner's favour. This script is the falsification attempt.

WHAT IT CHECKS, per case, over a full enumeration of the fields the interview
can actually reach:

  (1) FIELD LEVEL. An independent lazy evaluator, written here against the
      emitted YAML's Python and sharing no code with the Haskell harness,
      predicts the exact sequence of questions the interview will ask. That
      prediction is compared against the sequence real docassemble actually
      asks, driven through the SHIPPED round-trip harness
      (jl4/examples/docassemble/roundtrip_check.py) in a real docassemble.base.
      Any disagreement means "lazy left-to-right with short-circuit" is not what
      the interview does, and the harness's baseline is wrong.

  (2) ATOM LEVEL. The same lazy walk, collapsed to the granularity m3-measure
      counts in -- a maximal non-boolean subexpression, i.e. a named `MEANS`
      code block or an inline leaf -- is compared against the `decl` trace
      m3-measure emitted with --traces for the same world. Any disagreement
      means the harness's simulated asker does not walk the emitted program.

WHY BOTH. (1) alone would validate a rule without validating the harness that
implements it; (2) alone would compare the harness against another simulation.
Together they chain the harness to a real interview.

THE UNIT GAP IS MEASURED HERE, NOT ASSUMED. (1) counts fields and (2) counts
atoms over the same runs, so the expansion factor between "ladder atom" and
"question a user sees" is an output of this script rather than a caveat. It is
reported per case AND pooled, because the pooled figure is dominated by whichever
case happens to enumerate the most worlds and is not a property of the emitter.

THREE THINGS THE FIRST VERSION OF THIS SCRIPT GOT WRONG, fixed here:

  * IT COVERED ONLY TIES. Its five in-scope interviews were all decisions where
    plan order and declaration order tie, so a baseline error could not have
    changed any verdict -- and the CNF-distribution bug, which lived on two of
    the eleven winners, walked straight through it. The case list now carries
    an adversarial probe of the exact shape that broke (etc/m3-probes) and one
    REAL WINNER from the de novo corpus, isolated by commenting out its file's
    other `@export`s in a derived copy (the corpus file is not touched).

  * IT IDENTIFIED ATOMS POSITIONALLY, mapping the driver's i-th atom to the
    harness's i-th atom, so on any decision whose two orders are a permutation
    of each other the identification was simply wrong and the leg could pass or
    fail for the wrong reason. Identification is now by normalised LABEL, and
    the result is audited: every bijection between the two atom lists is tried
    and the number that survive all worlds is reported, so a reader can see
    whether the data pins the correspondence or merely tolerates it.

  * IT ENUMERATED EVERY FIELD IN THE YAML, including fields no path from the
    driver can reach -- which on a large module means the world space explodes
    and the first MAX_WORLDS of the product vary only the alphabetically-last
    fields. Enumeration is now over the fields REACHABLE from the driver.

Usage:
  m3-baseline-check.py --repo <root> --l4 <l4 binary> --measure <m3-measure binary>
                       --python <docassemble venv python> [--out <json>]

It re-emits the interviews and re-runs m3-measure itself, so it has no stale
inputs. Exits non-zero on any mismatch.
"""

import argparse
import ast
import itertools
import json
import os
import re
import subprocess
import sys

# --------------------------------------------------------------------------
# The cases
# --------------------------------------------------------------------------
#
# `l4`       — the module to emit an interview from (repo-relative).
# `measure`  — the module to run m3-measure over, if different (repo-relative).
# `decision` — the harness decision to compare against. When absent the target
#              is chosen by matching atom counts, which is only safe in a file
#              with one candidate.
# `keepExport` — build the emitted module by copying `l4` and commenting out
#              every `@export` line that does not contain this substring. Used
#              to isolate ONE export out of a large module without editing the
#              corpus.
# `why`      — why this case is in the list.

CASES = [
    {"name": "seam", "l4": "jl4/examples/docassemble/seam.l4",
     "why": "the scope/requirement seam: NotApplicable must not be asked past"},
    {"name": "computed-and-shadow", "l4": "jl4/examples/docassemble/computed-and-shadow.l4",
     "why": "computed intermediate values and shadowed names"},
    {"name": "defaults", "l4": "jl4/examples/docassemble/defaults.l4",
     "why": "TYPICALLY defaults on record fields"},
    {"name": "rodents-and-vermin", "l4": "jl4/examples/docassemble/rodents-and-vermin.l4",
     "why": "the widest emitted interview: most worlds, most fields per atom"},
    {"name": "assume-via-fn", "l4": "jl4/examples/docassemble/assume-via-fn.l4",
     "why": "ASSUME threaded through a function"},
    {"name": "enum-triage", "l4": "jl4/examples/docassemble/enum-triage.l4",
     "why": "an enum-shaped decision; expected to be out of scope (non-boolean)"},
    {"name": "distribution-probe", "l4": "etc/m3-probes/distribution-probe.l4",
     "why": "REGRESSION for the CNF-distribution bug: ((A AND C) OR B) AND D, the "
            "shape of two of the eleven winners. The ladder's simplified form "
            "costs 3.125 here and the emitted interview costs 2.875."},
    {"name": "regcf-denovo-intermediary",
     "l4": "jl4/examples/legal/regcf/denovo/regcf-denovo.l4",
     "keepExport": "Determine whether a person is qualified to act as an intermediary",
     "decision": "`the person qualifies to act as an intermediary`",
     "why": "A REAL WINNER (decl 2.25 vs plan 1.75) driven in real docassemble. "
            "The first run of guard 2 validated only decisions that tie, so the "
            "decisions carrying the entire result had no empirical check at all."},
]

# A ceiling on the world enumeration per case, so a wide record cannot turn this
# into an overnight job. Below the ceiling the enumeration is EXHAUSTIVE; at or
# above it the first N worlds of the product are taken, and the output says which
# happened.
MAX_WORLDS = 2048

# Above this many atoms the exhaustive bijection audit is skipped (n! blows up)
# and the output says so.
MAX_BIJECTION_ATOMS = 7


# --------------------------------------------------------------------------
# Emitted-YAML model
# --------------------------------------------------------------------------


class Emitted:
    """The blocks of one emitted interview, in the shapes `l4 docassemble`
    actually produces. Deliberately narrow: it understands the emitter's output,
    not docassemble's whole block vocabulary."""

    def __init__(self, text):
        import yaml

        self.fields = {}
        self.code = {}
        self.driver = None
        for doc in yaml.safe_load_all(text):
            if not isinstance(doc, dict):
                continue
            if "fields" in doc:
                for f in doc["fields"]:
                    var, meta = None, {}
                    for k, v in f.items():
                        if k in ("datatype", "help", "default", "required", "choices"):
                            meta[k] = v
                        else:
                            var = v
                    if var is not None:
                        self.fields[var] = meta
            if "code" in doc:
                raw = doc["code"]
                label = None
                for line in raw.splitlines():
                    st = line.strip()
                    if st.startswith("# L4:"):
                        label = st[len("# L4:"):].strip()
                        break
                tree = ast.parse(raw)
                if doc.get("mandatory") is True:
                    self.driver = tree
                else:
                    for var in doc.get("sets", []):
                        self.code[var] = (tree, label, raw)


def block_expr(tree):
    """The expression a `sets:` block computes. ("expr", e) for `v = e`, or
    ("if", test, then, else) for the two-armed shape MAYBE erasure emits."""
    body = [s for s in tree.body if not isinstance(s, ast.Expr)]
    if len(body) == 1 and isinstance(body[0], ast.Assign):
        return ("expr", body[0].value)
    if len(body) == 1 and isinstance(body[0], ast.If):
        node = body[0]
        t = node.body[0].value if node.body and isinstance(node.body[0], ast.Assign) else None
        e = node.orelse[0].value if node.orelse and isinstance(node.orelse[0], ast.Assign) else None
        return ("if", node.test, t, e)
    raise SystemExit("m3-baseline-check: unrecognised code-block shape:\n" + ast.dump(tree))


def attr_name(node):
    parts = []
    cur = node
    while isinstance(cur, ast.Attribute):
        parts.append(cur.attr)
        cur = cur.value
    if isinstance(cur, ast.Name):
        parts.append(cur.id)
    return ".".join(reversed(parts))


class _Obj:
    pass


def put(ns, dotted, val):
    parts = dotted.split(".")
    if len(parts) == 1:
        ns[parts[0]] = val
        return
    cur = ns
    for p in parts[:-1]:
        if p not in cur or not isinstance(cur[p], _Obj):
            cur[p] = _Obj()
        cur = cur[p].__dict__
    cur[parts[-1]] = val


# --------------------------------------------------------------------------
# Structure vs atom
# --------------------------------------------------------------------------
#
# Boolean STRUCTURE is `and`, `or`, `not`, the driver's `if`, the block the
# driver names, and a block that is a bare alias for another block. Everything
# else is a LEAF -- which is exactly m3-measure's atom, because
# `vizExprToBoolExpr` maps an `App` or a projection to one BVar and does not
# descend into it either.


def transparent_blocks(em):
    names = set()

    def walk(stmts):
        for st in stmts:
            if isinstance(st, ast.If):
                for n in ast.walk(st.test):
                    if isinstance(n, ast.Name) and n.id in em.code:
                        names.add(n.id)
                walk(st.body)
                walk(st.orelse)

    walk(em.driver.body)
    for var in em.code:
        kind = block_expr(em.code[var][0])
        if kind[0] == "expr" and isinstance(kind[1], ast.Name) and kind[1].id in em.code:
            names.add(var)
    return names


def static_atoms(em, transparent):
    """The atoms of the emitted decision, left to right, each paired with the AST
    node that computes it (so it can be forced later)."""
    out, seen = [], set()

    def add(key, node):
        if key not in seen:
            seen.add(key)
            out.append((key, node))

    def go(node):
        if isinstance(node, ast.BoolOp):
            for v in node.values:
                go(v)
            return
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            go(node.operand)
            return
        # A bare True/False is the emitter's rendering of an INERT element --
        # grammatical scaffolding that evaluates to the identity of its
        # connective. The ladder maps those to `TrueE`/`FalseE`, which
        # `vizExprToBoolExpr` turns into BTrue/BFalse and never into a BVar, so
        # they are structure on both sides and must not be counted as atoms.
        if isinstance(node, ast.Constant) and isinstance(node.value, bool):
            return
        if isinstance(node, ast.Name) and node.id in em.code:
            if node.id in transparent:
                go_block(node.id)
            else:
                _tree, label, _raw = em.code[node.id]
                add(("block", node.id, label), node)
            return
        if isinstance(node, ast.Attribute) and attr_name(node) in em.fields:
            add(("field", attr_name(node)), node)
            return
        if isinstance(node, ast.Name) and node.id in em.fields:
            add(("field", node.id), node)
            return
        add(("expr", ast.unparse(node)), node)

    def go_block(var):
        kind = block_expr(em.code[var][0])
        if kind[0] == "expr":
            go(kind[1])
        else:
            go(kind[1])
            go(kind[2])
            go(kind[3])

    def walk_stmts(stmts):
        for st in stmts:
            if isinstance(st, ast.If):
                go(st.test)
                walk_stmts(st.body)
                walk_stmts(st.orelse)

    walk_stmts(em.driver.body)
    return out


def reachable_fields(em):
    """The fields some path from the driver can demand. Enumerating anything else
    multiplies the world space by values no question in this interview reads --
    which, on a module with 43 emitted questions and a 3-field decision, is the
    difference between 8 worlds and 2^43."""
    seen_blocks, fields = set(), set()

    def go(node):
        for n in ast.walk(node):
            if isinstance(n, ast.Attribute):
                nm = attr_name(n)
                if nm in em.fields:
                    fields.add(nm)
            elif isinstance(n, ast.Name):
                if n.id in em.fields:
                    fields.add(n.id)
                elif n.id in em.code and n.id not in seen_blocks:
                    seen_blocks.add(n.id)
                    go(em.code[n.id][0])

    go(em.driver)
    return fields


# --------------------------------------------------------------------------
# The independent lazy evaluator
# --------------------------------------------------------------------------


class Walk:
    def __init__(self, em, world, transparent):
        self.em = em
        self.world = world
        self.transparent = transparent
        self.fields_asked = []
        self.atoms_asked = []
        self.atom_values = {}
        self.cache = {}

    def ask_field(self, var):
        if var not in self.fields_asked:
            self.fields_asked.append(var)
        return self.world[var]

    def eval_lazy(self, node, structural=True):
        if isinstance(node, ast.BoolOp):
            if isinstance(node.op, ast.And):
                for v in node.values:
                    if not self.eval_lazy(v, structural):
                        return False
                return True
            for v in node.values:
                if self.eval_lazy(v, structural):
                    return True
            return False
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            return not self.eval_lazy(node.operand, structural)
        # See `static_atoms`: a bare True/False is an inert element, structure on
        # both sides, never an atom.
        if isinstance(node, ast.Constant) and isinstance(node.value, bool):
            return node.value
        if isinstance(node, ast.Name) and node.id in self.em.code:
            return self.demand_block(node.id, structural)
        name = None
        if isinstance(node, ast.Attribute):
            name = attr_name(node)
        elif isinstance(node, ast.Name):
            name = node.id
        if name is not None and name in self.em.fields:
            if structural:
                return self.take_atom(("field", name), lambda: bool(self.ask_field(name)))
            return bool(self.ask_field(name))
        if structural:
            return self.take_atom(("expr", ast.unparse(node)), lambda: self.eval_leaf(node))
        return self.eval_leaf(node)

    def eval_leaf(self, node):
        """Evaluate a leaf, demanding the fields it mentions in source order and
        short-circuiting inside it too -- `a and (b >= 2)` must not demand b when
        a is False, which is what the real interview does."""
        if isinstance(node, ast.BoolOp) or (
            isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not)
        ):
            return self.eval_lazy(node, structural=False)
        mentioned = {}
        for n in ast.walk(node):
            if isinstance(n, ast.Attribute):
                v = attr_name(n)
                if v in self.em.fields:
                    mentioned[v] = None
            elif isinstance(n, ast.Name) and n.id in self.em.fields:
                mentioned[n.id] = None
        src = ast.unparse(node)
        ordered = sorted(mentioned, key=lambda v: src.find(v))
        ns = {}
        for var in ordered:
            put(ns, var, self.ask_field(var))
        return bool(eval(compile(ast.Expression(node), "<leaf>", "eval"), {}, ns))

    def take_atom(self, key, thunk):
        if key in self.cache:
            return self.cache[key]
        if key not in self.atoms_asked:
            self.atoms_asked.append(key)
        val = thunk()
        self.cache[key] = val
        self.atom_values[key] = val
        return val

    def demand_block(self, var, structural):
        tree, label, _raw = self.em.code[var]
        kind = block_expr(tree)
        if structural and var in self.transparent:
            if kind[0] == "expr":
                return self.eval_lazy(kind[1], True)
            _k, test, then_e, else_e = kind
            return (
                self.eval_lazy(then_e, True)
                if self.eval_lazy(test, True)
                else self.eval_lazy(else_e, True)
            )
        key = ("block", var, label)
        if key in self.cache:
            return self.cache[key]
        if structural and key not in self.atoms_asked:
            self.atoms_asked.append(key)
        if kind[0] == "expr":
            val = self.eval_lazy(kind[1], structural=False)
        else:
            _k, test, then_e, else_e = kind
            val = (
                self.eval_lazy(then_e, False)
                if self.eval_lazy(test, False)
                else self.eval_lazy(else_e, False)
            )
        self.cache[key] = val
        if structural:
            self.atom_values[key] = val
        return val

    def run_driver(self):
        self.exec_stmts(self.em.driver.body)

    def exec_stmts(self, stmts):
        for st in stmts:
            if isinstance(st, ast.If):
                if self.eval_lazy(st.test):
                    self.exec_stmts(st.body)
                else:
                    self.exec_stmts(st.orelse)
                return
            if isinstance(st, ast.Assign):
                continue
            if isinstance(st, ast.Expr):
                return


def force_all_atoms(em, world, transparent, atoms):
    """Every atom's value in this world, whether or not the lazy walk demanded
    it. The bit-string that indexes m3-measure's trace table is over ALL atom
    classes, so guessing False for an atom the walk short-circuited past would
    look up the wrong row. Uses a throwaway Walk so nothing here pollutes the
    ask sequences."""
    vals = {}
    for key, node in atoms:
        w = Walk(em, world, transparent)
        if key[0] == "block":
            vals[key] = bool(w.demand_block(key[1], structural=False))
        elif key[0] == "field":
            vals[key] = bool(world[key[1]])
        else:
            vals[key] = bool(w.eval_leaf(node))
    return vals


# --------------------------------------------------------------------------
# World enumeration -- domains derived from the emitted code, not chosen by hand
# --------------------------------------------------------------------------


def domains(em, only=None):
    """Per-field value domain. Booleans are exhaustive. A number field gets the
    two values straddling each threshold it is compared against IN THE EMITTED
    CODE, so every comparison in the interview is exercised on both sides; a
    string field gets each literal it is compared against, plus a non-matching
    one and the empty string. A field the emitter never compares directly (it
    only appears inside arithmetic) falls back to 0 and 1000, and the output
    names which fields those were."""
    nums, strs, fallbacks = {}, {}, []
    for _var, (tree, _label, _raw) in em.code.items():
        for node in ast.walk(tree):
            if isinstance(node, ast.Compare) and len(node.comparators) == 1:
                for a, b in ((node.left, node.comparators[0]), (node.comparators[0], node.left)):
                    name = attr_name(a) if isinstance(a, ast.Attribute) else (
                        a.id if isinstance(a, ast.Name) else None
                    )
                    if name in em.fields and isinstance(b, ast.Constant):
                        if isinstance(b.value, bool):
                            continue
                        if isinstance(b.value, (int, float)):
                            nums.setdefault(name, set()).add(b.value)
                        elif isinstance(b.value, str):
                            strs.setdefault(name, set()).add(b.value)
    out = {}
    for var, meta in em.fields.items():
        if only is not None and var not in only:
            continue
        dt = meta.get("datatype")
        if dt == "yesnomaybe":
            out[var] = [False, True, None]
        elif dt in ("yesno", "yesnoradio", "noyes", "noyesradio"):
            out[var] = [False, True]
        elif dt == "number":
            if var in nums:
                vals = set()
                for n in nums[var]:
                    vals.add(n - 1)
                    vals.add(n)
                out[var] = sorted(vals)
            else:
                out[var] = [0, 1000]
                fallbacks.append(var)
        else:
            vals = set(strs.get(var, set()))
            vals.add("")
            vals.add("ZZ-NO-MATCH")
            out[var] = sorted(vals)
    return out, fallbacks


# --------------------------------------------------------------------------
# Driving the real interview
# --------------------------------------------------------------------------

DRIVER = r'''
import importlib.util, json, sys
HARNESS, YAML, WORLDS_JSON = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = [HARNESS, YAML, "x"]
spec = importlib.util.spec_from_file_location("rtc", HARNESS)
rtc = importlib.util.module_from_spec(spec); spec.loader.exec_module(rtc)
current_info = {
    "user": {"is_anonymous": False, "is_authenticated": True, "theid": 1,
             "the_user_id": 1, "roles": ["user"], "firstname": "M", "lastname": "3",
             "email": "m3@example.com", "country": "US", "subdivisionfirst": None,
             "subdivisionsecond": None, "subdivisionthird": None,
             "organization": None, "timezone": "America/New_York",
             "language": "en", "session_uid": "m3", "device_id": "m3"},
    "session": "m3", "secret": None, "yaml_filename": "interview.yml",
    "url": None, "url_root": None, "encrypted": False, "interface": "cli",
    "arguments": {}}
worlds = json.load(open(WORLDS_JSON))
content = open(YAML, encoding="utf-8").read()
out = []
with rtc.global_context(rtc.empty_globals()):
    source = rtc.InterviewSourceString(content=content, path="interview.yml",
                                       package="docassemble.l4roundtrip")
    interview = rtc.parse.Interview(source=source)
    for w in worlds:
        case = {"label": "w", "fixtures": {k.split(".")[-1]: v for k, v in w.items()}}
        try:
            user_dict, status, transcript = rtc.drive_case(interview, current_info, case)
            seq = [v for _s, _q, asked in transcript for v in asked]
            out.append({"ok": True, "asked": seq})
        except Exception as exc:
            out.append({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
sys.stdout.write("@@JSON@@" + json.dumps(out) + "\n")
'''


def drive_real(python, harness, yaml_path, worlds, tmpdir, tag):
    wj = os.path.join(tmpdir, f"worlds-{tag}.json")
    with open(wj, "w") as fh:
        json.dump(worlds, fh)
    dr = os.path.join(tmpdir, "driver.py")
    with open(dr, "w") as fh:
        fh.write(DRIVER)
    res = subprocess.run([python, dr, harness, yaml_path, wj],
                         capture_output=True, text=True)
    for line in res.stdout.splitlines():
        if line.startswith("@@JSON@@"):
            return json.loads(line[len("@@JSON@@"):])
    raise SystemExit(
        f"m3-baseline-check: the docassemble driver produced no result for {tag}\n"
        f"stdout tail:\n{res.stdout[-4000:]}\nstderr tail:\n{res.stderr[-4000:]}"
    )


# --------------------------------------------------------------------------
# Atom identification
# --------------------------------------------------------------------------


def normalise_label(t):
    """Fold an L4 atom label and an emitted Python identifier onto a common
    spelling: lowercase, `'s` and `.` become separators, every run of non
    alphanumerics becomes a single underscore."""
    t = t.replace("`", " ").replace("'s ", " ").replace(".", " ")
    t = re.sub(r"[^0-9a-zA-Z]+", "_", t.lower())
    return t.strip("_")


def label_bijection(driver_keys, harness_labels):
    """A driver-atom -> harness-atom map derived from the labels, or None if the
    labels do not pin down a bijection. Deliberately returns None rather than
    guessing: a wrong identification makes the atom leg pass or fail for the
    wrong reason."""
    if len(driver_keys) != len(harness_labels):
        return None
    hnorm = [normalise_label(h) for h in harness_labels]
    if len(set(hnorm)) != len(hnorm):
        return None
    out, used = {}, set()
    for key in driver_keys:
        cand = normalise_label(str(key[-1]) if key[-1] is not None else key[1])
        hit = [i for i, h in enumerate(hnorm) if h == cand and i not in used]
        if len(hit) != 1:
            return None
        used.add(hit[0])
        out[key] = harness_labels[hit[0]]
    return out


def atom_leg(mapping, driver_keys, harness_labels, worlds, preds, forced, traces):
    """Run the atom-level comparison under one driver->harness identification.
    Returns the list of mismatches (empty means it passed)."""
    bad = []
    for w, p, vals in zip(worlds, preds, forced):
        rev = {mapping[k]: k for k in driver_keys}
        bits = "".join("T" if vals[rev[h]] else "F" for h in harness_labels)
        t = traces.get(bits)
        if t is None:
            bad.append({"world": w, "bits": bits,
                        "error": "no m3-measure trace for this atom world"})
            continue
        gnames = [mapping[k] for k in p.atoms_asked]
        if ([normalise_label(x) for x in gnames]
                != [normalise_label(x) for x in t["decl"]]):
            bad.append({"world": w, "bits": bits,
                        "harness": t["decl"], "driver": gnames})
    return bad


# --------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--l4", required=True)
    ap.add_argument("--measure", required=True)
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--tmp", default="/tmp/m3-baseline")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    os.makedirs(args.tmp, exist_ok=True)
    env = dict(os.environ,
               JL4_LIBRARY_PATH=os.path.join(args.repo, "jl4-core", "libraries"))
    harness = os.path.join(args.repo, "jl4", "examples", "docassemble",
                           "roundtrip_check.py")

    # m3-measure is run once per distinct module, with --traces.
    measured, mods = {}, []
    for c in CASES:
        m = c.get("measure", c["l4"])
        if m not in mods:
            mods.append(m)
    for i, m in enumerate(mods):
        mj = os.path.join(args.tmp, f"measure-{i}.json")
        subprocess.run([args.measure, os.path.join(args.repo, m), "--traces", "--json", mj],
                       env=env, check=True, capture_output=True, text=True)
        measured[m] = [d for d in json.load(open(mj))["decisions"] if d["measured"]]

    report, failures = [], []
    for case in CASES:
        ex = case["name"]
        srcpath = os.path.join(args.repo, case["l4"])
        if "keepExport" in case:
            derived = os.path.join(args.tmp, f"{ex}.l4")
            lines = open(srcpath, encoding="utf-8").read().split("\n")
            out_lines = [
                ("-- " + ln) if (ln.startswith("@export") and case["keepExport"] not in ln) else ln
                for ln in lines
            ]
            with open(derived, "w", encoding="utf-8") as fh:
                fh.write("\n".join(out_lines))
            srcpath = derived

        yml = os.path.join(args.tmp, f"{ex}.yml")
        r = subprocess.run([args.l4, "docassemble", srcpath, "-o", yml], env=env,
                           capture_output=True, text=True)
        if r.returncode != 0:
            report.append({"case": ex, "why": case["why"], "emitted": False,
                           "reason": (r.stderr or r.stdout).strip()[:400]})
            continue
        em = Emitted(open(yml).read())
        transparent = transparent_blocks(em)
        atoms = static_atoms(em, transparent)
        order = [k for k, _n in atoms]

        if not order:
            # A non-boolean decision. The emitter gives it a driver that simply
            # demands the value and shows a result screen -- there is no boolean
            # structure, so there is no question ORDER to get right and nothing
            # for M3 to reorder. The ladder refuses these too (`l4 verify`:
            # "Can only visualize ... a DECIDE that returns a boolean"), so this
            # is out of the measurement's scope rather than a failure of it.
            report.append({"case": ex, "why": case["why"], "emitted": True,
                           "outOfScope": True,
                           "reason": "non-boolean decision: the driver has no "
                                     "boolean structure and the ladder refuses it"})
            continue

        reach = reachable_fields(em)
        dom, fallbacks = domains(em, only=reach)
        keys = sorted(dom)
        total = 1
        for k in keys:
            total *= len(dom[k])
        worlds = []
        for i, combo in enumerate(itertools.product(*[dom[k] for k in keys])):
            if i >= MAX_WORLDS:
                break
            worlds.append(dict(zip(keys, combo)))

        preds, forced = [], []
        for w in worlds:
            walk = Walk(em, w, transparent)
            walk.run_driver()
            preds.append(walk)
            forced.append(force_all_atoms(em, w, transparent, atoms))
        real = drive_real(args.python, harness, yml, worlds, args.tmp, ex)

        field_mismatch = []
        for w, p, r_ in zip(worlds, preds, real):
            if not r_["ok"]:
                field_mismatch.append({"world": w, "error": r_["error"]})
            elif r_["asked"] != p.fields_asked:
                field_mismatch.append({"world": w, "real": r_["asked"],
                                       "predicted": p.fields_asked})

        decisions = measured[case.get("measure", case["l4"])]
        target = None
        if "decision" in case:
            for d in decisions:
                if d["decision"] == case["decision"]:
                    target = d
                    break
            if target is None:
                raise SystemExit(
                    f"m3-baseline-check: case {ex} names decision {case['decision']!r} "
                    f"but m3-measure did not measure it")
        else:
            for d in decisions:
                if d["source"]["atomClasses"] == len(order):
                    target = d
                    break

        atom_mismatch, expansion, note = [], [], None
        bijections_passing, identification = None, None
        if target is None:
            note = (f"no ladder-accepted decision in {case['l4']} has {len(order)} atom "
                    f"classes, so the atom-level leg cannot run here; the "
                    f"field-level leg above still did. Driver atom order: "
                    f"{[k[-1] for k in order]}")
        else:
            src = target["source"]
            traces = {t["world"]: t for t in src["traces"]}
            harness_order = [a["label"] for a in src["atoms"]]
            if len(harness_order) != len(order):
                raise SystemExit(
                    f"m3-baseline-check: case {ex} targets {target['decision']!r} with "
                    f"{len(harness_order)} atom classes but the emitted driver has "
                    f"{len(order)} atoms")
            mapping = label_bijection(order, harness_order)
            if mapping is not None:
                identification = "label"
            else:
                identification = "positional (labels did not pin a bijection)"
                mapping = dict(zip(order, harness_order))
            atom_mismatch = atom_leg(mapping, order, harness_order, worlds, preds,
                                     forced, traces)

            # Audit the identification: how many of the n! bijections survive
            # every world? 1 means the data pins the correspondence and the
            # choice above cannot have been load-bearing.
            if len(order) <= MAX_BIJECTION_ATOMS:
                bijections_passing = 0
                for perm in itertools.permutations(harness_order):
                    cand = dict(zip(order, perm))
                    if not atom_leg(cand, order, harness_order, worlds, preds,
                                    forced, traces):
                        bijections_passing += 1

            if not atom_mismatch:
                rev = {mapping[k]: k for k in order}
                for r_, vals in zip(real, forced):
                    if not r_["ok"]:
                        continue
                    bits = "".join("T" if vals[rev[h]] else "F" for h in harness_order)
                    expansion.append((len(traces[bits]["decl"]), len(r_["asked"])))

        entry = {
            "case": ex,
            "why": case["why"],
            "l4": case["l4"],
            "isolatedExport": case.get("keepExport"),
            "emitted": True,
            "worlds": len(worlds),
            "worldSpace": total,
            "worldsExhaustive": total <= MAX_WORLDS,
            "fieldsEnumerated": keys,
            "fieldsInYaml": len(em.fields),
            "numberFallbacks": fallbacks,
            "driverAtomOrder": [k[-1] for k in order],
            "harnessDecision": target["decision"] if target else None,
            "harnessAtomOrder": [a["label"] for a in target["source"]["atoms"]] if target else None,
            "atomIdentification": identification,
            "bijectionsPassing": bijections_passing,
            "note": note,
            "fieldMismatchCount": len(field_mismatch),
            "fieldMismatches": field_mismatch[:10],
            "atomMismatchCount": len(atom_mismatch),
            "atomMismatches": atom_mismatch[:10],
            "expansion": {"atomsTotal": sum(a for a, _f in expansion),
                          "fieldsTotal": sum(f for _a, f in expansion),
                          "worldsCompared": len(expansion),
                          "ratio": (sum(f for _a, f in expansion) / sum(a for a, _f in expansion))
                          if sum(a for a, _f in expansion) else None},
        }
        if target:
            u = target["source"]["uniform"]
            entry["harnessMeans"] = {"decl": u["declAtomsMean"], "plan": u["planAtomsMean"],
                                     "stat": u["statAtomsMean"]}
            entry["isPlannerWin"] = u["planAtomsMean"] < u["declAtomsMean"] - 1e-9
            cnf = target["cnf"]
            if cnf["measured"]:
                entry["cnfDeclMean"] = cnf["uniform"]["declAtomsMean"]
        report.append(entry)
        if field_mismatch or atom_mismatch:
            failures.append(ex)

    covered = [e for e in report if e.get("atomMismatchCount") == 0 and e.get("harnessDecision")]
    wins = [e for e in covered if e.get("isPlannerWin")]
    pooled_a = sum(e["expansion"]["atomsTotal"] for e in covered)
    pooled_f = sum(e["expansion"]["fieldsTotal"] for e in covered)
    ratios = [e["expansion"]["ratio"] for e in covered if e["expansion"]["ratio"]]
    summary = {
        "casesWithAtomLeg": len(covered),
        "casesWithAtomLegThatArePlannerWins": len(wins),
        "plannerWinCases": [e["case"] for e in wins],
        "expansionPooled": (pooled_f / pooled_a) if pooled_a else None,
        "expansionPooledAtoms": pooled_a,
        "expansionPooledFields": pooled_f,
        "expansionPerCase": {e["case"]: e["expansion"]["ratio"] for e in covered},
        "expansionUnweightedMean": (sum(ratios) / len(ratios)) if ratios else None,
        "expansionLargestCaseShareOfAtoms": (
            max(e["expansion"]["atomsTotal"] for e in covered) / pooled_a) if pooled_a else None,
        "expansionCaveat": "The pooled ratio is dominated by whichever case enumerates the "
                           "most worlds; it is a property of this case list, not of the "
                           "emitter. Read the per-case column.",
        "identificationCaveat": "bijectionsPassing = 1 means the world data pins the "
                                "driver-atom -> harness-atom correspondence, so the choice "
                                "of identification cannot be load-bearing. Greater than 1 "
                                "means the case's shape is symmetric enough that several "
                                "identifications agree, and the leg is correspondingly weaker.",
    }
    out = {"summary": summary, "cases": report}
    print(json.dumps(out, indent=2, default=str))
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(out, fh, indent=2, default=str)
    if failures:
        print(f"\nGUARD 2 FAILED on: {failures}", file=sys.stderr)
        return 1
    if not wins:
        print("\nGUARD 2 INCOMPLETE: no case whose atom leg ran is a decision the "
              "planner wins on, so the baseline is validated only where it cannot "
              "change a verdict.", file=sys.stderr)
        return 1
    print(f"\nGUARD 2 PASSED: on every enumerated world of every emitted interview, "
          f"the real docassemble ask sequence equals the independent lazy-demand "
          f"prediction, and m3-measure's decl trace is that same walk at atom "
          f"granularity. {len(wins)} of the {len(covered)} atom-level cases "
          f"is a decision the planner WINS on ({', '.join(e['case'] for e in wins)}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
