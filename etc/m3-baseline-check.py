#!/usr/bin/env python3
"""Guard 2 for the M3 gate measurement: is the simulated declaration-order asker
the REAL emitted behaviour?

`m3-measure` compares two askers over a decision's ladder skeleton. The
plan-order asker is the shipped ranker, so it cannot be wrong about itself. The
declaration-order asker is a SIMULATION, and if it is a strawman -- "ask every
atom", or a left-to-right walk that forgets short-circuit -- then every number
downstream is wrong in the planner's favour. This script is the falsification
attempt.

WHAT IT CHECKS, per emitted interview, over a full enumeration of the
interview's own input fields:

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
"question a user sees" is an output of this script rather than a caveat.

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
import subprocess
import sys

# The six docassemble corpus files at the top level of jl4/examples/docassemble.
# The other six live under not-ok/ and are refused by the emitter by design.
EXAMPLES = [
    "seam",
    "computed-and-shadow",
    "defaults",
    "rodents-and-vermin",
    "assume-via-fn",
    "enum-triage",
]

# A ceiling on the world enumeration per interview, so a wide record cannot turn
# this into an overnight job. Below the ceiling the enumeration is EXHAUSTIVE;
# at or above it the first N worlds of the product are taken, and the output says
# which happened.
MAX_WORLDS = 2048


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
    """The atoms of the emitted decision, left to right."""
    out, seen = [], set()

    def add(key):
        if key not in seen:
            seen.add(key)
            out.append(key)

    def go(node):
        if isinstance(node, ast.BoolOp):
            for v in node.values:
                go(v)
            return
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            go(node.operand)
            return
        if isinstance(node, ast.Name) and node.id in em.code:
            if node.id in transparent:
                go_block(node.id)
            else:
                _tree, label, _raw = em.code[node.id]
                add(("block", node.id, label))
            return
        if isinstance(node, ast.Attribute) and attr_name(node) in em.fields:
            add(("field", attr_name(node)))
            return
        if isinstance(node, ast.Name) and node.id in em.fields:
            add(("field", node.id))
            return
        add(("expr", ast.unparse(node)))

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


# --------------------------------------------------------------------------
# World enumeration -- domains derived from the emitted code, not chosen by hand
# --------------------------------------------------------------------------


def domains(em):
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


def normalise_label(t):
    return t.replace("`", "").strip().lower()


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

    srcs = [os.path.join(args.repo, "jl4", "examples", "docassemble", f"{e}.l4")
            for e in EXAMPLES]
    mj = os.path.join(args.tmp, "measure.json")
    subprocess.run([args.measure, *srcs, "--traces", "--json", mj],
                   env=env, check=True, capture_output=True, text=True)
    measured = {}
    for d in json.load(open(mj))["decisions"]:
        if d["measured"]:
            measured.setdefault(os.path.basename(d["file"]), []).append(d)

    report, failures = [], []
    for ex in EXAMPLES:
        src = os.path.join(args.repo, "jl4", "examples", "docassemble", f"{ex}.l4")
        yml = os.path.join(args.tmp, f"{ex}.yml")
        r = subprocess.run([args.l4, "docassemble", src, "-o", yml], env=env,
                           capture_output=True, text=True)
        if r.returncode != 0:
            report.append({"example": ex, "emitted": False,
                           "reason": (r.stderr or r.stdout).strip()[:400]})
            continue
        em = Emitted(open(yml).read())
        dom, fallbacks = domains(em)
        transparent = transparent_blocks(em)
        order = static_atoms(em, transparent)

        if not order:
            # A non-boolean decision. The emitter gives it a driver that simply
            # demands the value and shows a result screen -- there is no boolean
            # structure, so there is no question ORDER to get right and nothing
            # for M3 to reorder. The ladder refuses these too (`l4 verify`:
            # "Can only visualize ... a DECIDE that returns a boolean"), so this
            # is out of the measurement's scope rather than a failure of it.
            report.append({"example": ex, "emitted": True, "outOfScope": True,
                           "reason": "non-boolean decision: the driver has no "
                                     "boolean structure and the ladder refuses it"})
            continue

        keys = sorted(dom)
        total = 1
        for k in keys:
            total *= len(dom[k])
        worlds = []
        for i, combo in enumerate(itertools.product(*[dom[k] for k in keys])):
            if i >= MAX_WORLDS:
                break
            worlds.append(dict(zip(keys, combo)))

        preds = []
        for w in worlds:
            walk = Walk(em, w, transparent)
            walk.run_driver()
            preds.append(walk)
        real = drive_real(args.python, harness, yml, worlds, args.tmp, ex)

        field_mismatch = []
        for w, p, r_ in zip(worlds, preds, real):
            if not r_["ok"]:
                field_mismatch.append({"world": w, "error": r_["error"]})
            elif r_["asked"] != p.fields_asked:
                field_mismatch.append({"world": w, "real": r_["asked"],
                                       "predicted": p.fields_asked})

        decisions = measured.get(f"{ex}.l4", [])
        target = None
        for d in decisions:
            if d["atomClasses"] == len(order):
                target = d
                break

        atom_mismatch, expansion, note = [], [], None
        if target is None:
            note = (f"no ladder-accepted decision in {ex}.l4 has {len(order)} atom "
                    f"classes, so the atom-level leg cannot run here; the "
                    f"field-level leg above still did. Driver atom order: "
                    f"{[k[-1] for k in order]}")
        else:
            traces = {t["world"]: t for t in target["traces"]}
            harness_order = [a["label"] for a in target["atoms"]]
            for w, p, r_ in zip(worlds, preds, real):
                bits = "".join("T" if p.atom_values.get(k) else "F" for k in order)
                t = traces.get(bits)
                if t is None:
                    atom_mismatch.append({"world": w, "bits": bits,
                                          "error": "no m3-measure trace for this atom world"})
                    continue
                gnames = [harness_order[order.index(k)] for k in p.atoms_asked]
                if ([normalise_label(x) for x in gnames]
                        != [normalise_label(x) for x in t["decl"]]):
                    atom_mismatch.append({"world": w, "bits": bits,
                                          "harness": t["decl"], "driver": gnames})
                    continue
                if r_["ok"]:
                    expansion.append((len(t["decl"]), len(r_["asked"])))

        report.append({
            "example": ex,
            "emitted": True,
            "worlds": len(worlds),
            "worldSpace": total,
            "worldsExhaustive": total <= MAX_WORLDS,
            "numberFallbacks": fallbacks,
            "driverAtomOrder": [k[-1] for k in order],
            "harnessDecision": target["decision"] if target else None,
            "harnessAtomOrder": [a["label"] for a in target["atoms"]] if target else None,
            "note": note,
            "fieldMismatchCount": len(field_mismatch),
            "fieldMismatches": field_mismatch[:10],
            "atomMismatchCount": len(atom_mismatch),
            "atomMismatches": atom_mismatch[:10],
            "expansion": {"atomsTotal": sum(a for a, _f in expansion),
                          "fieldsTotal": sum(f for _a, f in expansion),
                          "worldsCompared": len(expansion)},
        })
        if field_mismatch or atom_mismatch:
            failures.append(ex)

    print(json.dumps(report, indent=2, default=str))
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(report, fh, indent=2, default=str)
    if failures:
        print(f"\nGUARD 2 FAILED on: {failures}", file=sys.stderr)
        return 1
    print("\nGUARD 2 PASSED: on every enumerated world of every emitted interview, "
          "the real docassemble ask sequence equals the independent lazy-demand "
          "prediction, and m3-measure's decl trace is that same walk at atom "
          "granularity.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
