#!/usr/bin/env python3
"""The cross-validation harness of REGULATIVE-LOWERING-SPEC.md sections 6.2 and 6.3 (work package WP4).

It explores the dinner fixtures with `l4 explore`, then measures what the explored graph is worth:

  * bisimulation of each emitted .aut, relabelled, against its vendored reference LTS (mCRL2 ltscompare);
  * agreement of every verdict between the in-process checker, TLC and NuSMV, and with expected.tsv;
  * the positive control (D1 violates P1 by Sequence A, in every column);
  * non-vacuity of fairness (the environment eventually acts is violated under every fairness used),
    and the trap it guards against (assuming the environment fair makes it hold);
  * the mutants (each fails the one property it was written to fail);
  * a replay of every counterexample and witness, from every column, on the explored graph and on the evaluator.

A tool that is not installed makes its cells unknown, never holds, and says so on stderr.
With --release (make check RELEASE=1) an unknown liveness or bisimulation cell fails the run.
Everything it writes goes to the work directory; it reads nothing outside jl4/examples/explore and the tools.
See README.md beside this file.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

HERE = Path(__file__).resolve().parent
EXPLORE = HERE.parent  # jl4/examples/explore
REPO = HERE.parents[3]  # the repository root
MARKER = ".l4-explore-harness"
FIXED_NOW = "2026-01-01T00:00:00Z"
REQUIRED_JAVA = 11

# The fairness variants a fixture can be explored and emitted under (fixtures.tsv names them).
#   alice: weak fairness on Alice's acts that move, the assumption every liveness verdict is answered under (spec 4.6).
#   none:  no --fair: nothing is fair beyond TLC's WF_vars(Next), which the safety runs use, and NuSMV's infinite paths.
#   world: --fair World: every act that moves is fair, the environment's included. This is the trap the
#          non-vacuity control exists to catch, so the control must HOLD here (spec 6.3, brief/README.md).
VARIANTS = {
    "alice": {"fair": ["Alice"], "role": "answers", "says": "weak fairness on Alice's acts that move (--fair Alice)"},
    "none": {"fair": [], "role": "control", "says": "nothing fair (no --fair)"},
    "world": {"fair": ["World"], "role": "trap", "says": "every act that moves fair, the environment's included (--fair World)"},
}

KIND_FLAG = {"always": "--always", "reachable": "--reachable", "stays": "--stays", "eventually": "--eventually"}

# ---------------------------------------------------------------------------
# Small things
# ---------------------------------------------------------------------------


def read_tsv(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    header: Optional[list[str]] = None
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        cells = line.split("\t")
        if header is None:
            header = cells
            continue
        if len(cells) != len(header):
            raise SystemExit(f"BROKEN  {path.name}:{n}: {len(cells)} cells, the header has {len(header)}")
        rows.append(dict(zip(header, cells)))
    return rows


@dataclass
class Ran:
    code: int
    out: str
    err: str


def run(cmd: list[str], cwd: Optional[Path] = None, timeout: int = 900, env: Optional[dict] = None) -> Ran:
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)
        return Ran(p.returncode, p.stdout, p.stderr)
    except FileNotFoundError as e:
        return Ran(127, "", str(e))
    except subprocess.TimeoutExpired:
        return Ran(124, "", f"timed out after {timeout} s")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(p: Path) -> str:
    try:
        return str(p.relative_to(REPO))
    except ValueError:
        return str(p)


def short(label: str, names: dict[str, str]) -> str:
    """A graph label as the reference names it (step(Buy) is Buy), or as it is when it has no reference name."""
    ref = names.get(label)
    if ref is None:
        return label
    m = re.fullmatch(r"step\((.*)\)", ref)
    return m.group(1) if m else ref


# ---------------------------------------------------------------------------
# The tools
# ---------------------------------------------------------------------------


@dataclass
class Tool:
    name: str
    present: bool
    found: str  # what was found, or why it was not
    version: str = ""
    cmd: list[str] = field(default_factory=list)
    broken: bool = False  # named explicitly, by an environment variable, and unusable: a defect, not an absence


def find_l4(given: Optional[str]) -> Tool:
    candidates: list[tuple[str, str]] = []
    if given:
        candidates.append((given, "--l4 / L4"))
    else:
        r = run(["cabal", "list-bin", "exe:l4"], cwd=REPO, timeout=120)
        if r.code == 0 and r.out.strip() and Path(r.out.strip()).is_file():
            candidates.append((r.out.strip(), "this tree's cabal build"))
        w = shutil.which("l4")
        if w:
            candidates.append((w, "PATH"))
    for path, how in candidates:
        h = run([path, "explore", "--help"], timeout=60)
        if h.code == 0 and "--emit" in h.out:
            v = run([path, "--version"], timeout=60)
            return Tool("l4", True, f"{path} ({how})", (v.out or v.err).strip().splitlines()[0] if (v.out or v.err).strip() else "", [path])
    tried = "; ".join(f"{p} ({how})" for p, how in candidates) or "none found"
    return Tool("l4", False, f"no l4 whose explore has --emit: tried {tried}. Build this tree (cabal build exe:l4) or set L4")


def find_mcrl2() -> Tool:
    d = os.environ.get("MCRL2_BIN")
    how = "MCRL2_BIN"
    if not d:
        w = shutil.which("ltscompare")
        d, how = (str(Path(w).parent), "PATH") if w else ("", "")
    if not d:
        return Tool("mCRL2", False, "not installed: no ltscompare on PATH and MCRL2_BIN unset")
    missing = [t for t in ("ltscompare", "ltsinfo", "mcrl22lps", "lps2lts") if not (Path(d) / t).is_file()]
    if missing:
        return Tool("mCRL2", False, f"{', '.join(missing)} not in {d} ({how})", broken=how == "MCRL2_BIN")
    v = run([str(Path(d) / "ltscompare"), "--version"], timeout=60)
    first = v.out.strip().splitlines()[0] if v.out.strip() else ""
    return Tool("mCRL2", True, f"{d} ({how})", first.replace("ltscompare ", ""), [d])


def find_java() -> tuple[Optional[str], str, bool]:
    """A Java new enough for TLC: (path, what was found, whether JAVA named one that is not)."""
    for path, how in ((os.environ.get("JAVA"), "JAVA"),
                      (str(Path(os.environ["JAVA_HOME"]) / "bin" / "java") if os.environ.get("JAVA_HOME") else None, "JAVA_HOME"),
                      (shutil.which("java"), "PATH")):
        if not path:
            continue
        r = run([path, "-version"], timeout=60) if Path(path).is_file() else Ran(127, "", "")
        m = re.search(r'version "(\d+)(?:\.(\d+))?', r.err + r.out)
        major = (int(m.group(1)) if m.group(1) != "1" else int(m.group(2) or 0)) if m else 0
        if major >= REQUIRED_JAVA:
            return path, f"{path} ({how}), Java {major}", False
        if how == "JAVA":
            return None, f"JAVA={path} is not a Java {REQUIRED_JAVA} or later", True
    return None, f"no Java {REQUIRED_JAVA} or later (set JAVA to a java binary)", False


def find_tlc() -> Tool:
    jar = os.environ.get("TLA2TOOLS_JAR")
    if not jar:
        return Tool("TLC", False, "not installed: TLA2TOOLS_JAR unset (the path to tla2tools.jar)")
    if not Path(jar).is_file():
        return Tool("TLC", False, f"TLA2TOOLS_JAR={jar} is not a file", broken=True)
    java, why, bad = find_java()
    if not java:
        return Tool("TLC", False, f"not runnable: {why}", broken=bad)
    return Tool("TLC", True, f"{jar}, {why}", "", [java, jar])


def find_nusmv() -> Tool:
    exe = os.environ.get("NUSMV") or shutil.which("NuSMV")
    how = "NUSMV" if os.environ.get("NUSMV") else "PATH"
    if not exe:
        return Tool("NuSMV", False, "not installed: no NuSMV on PATH and NUSMV unset")
    if not Path(exe).is_file():
        return Tool("NuSMV", False, f"NUSMV={exe} is not a file", broken=True)
    r = run([exe, "-h"], timeout=60)
    m = re.search(r"This is NuSMV (\S+)", r.out + r.err)
    if not m:
        return Tool("NuSMV", False, f"{exe} ({how}) does not say it is NuSMV", broken=True)
    return Tool("NuSMV", True, f"{exe} ({how})", m.group(1), [exe])


# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------


@dataclass
class Check:
    group: str
    name: str
    status: str  # pass | fail | unknown
    detail: str
    gate: str = ""  # liveness | bisim: an unknown here fails the release gate


@dataclass
class Path_:
    """A path or a lasso through the explored graph: states[i] --steps[i]--> states[i+1]."""
    states: list[int]
    steps: list[tuple[int, str, int]]
    loop: Optional[int] = None  # for a lasso, the index the last state re-enters: states[-1] == states[loop]
    source: str = ""
    problems: list[str] = field(default_factory=list)  # found while reading it
    ok: Optional[bool] = None  # on the graph, a witness to its verdict, fair, and as expected.tsv says
    replayed: Optional[bool] = None  # every prefix reaches its graph state on the evaluator


@dataclass
class Graph:
    stem: str
    variant: str
    contract: str
    at: str
    states: dict[int, dict]
    edges: set[tuple[int, str, int]]
    kinds: dict[tuple[int, str, int], str]
    labels: dict[str, dict[int, bool]]
    checks: list[dict]
    coverage: dict
    emit: Path
    base: str = ""


@dataclass
class Cell:
    fixture: str
    variant: str
    prop: str
    column: str  # in-process | TLC | NuSMV
    verdict: str  # holds | violated | unknown | n/a | broken
    detail: str = ""
    paths: list[Path_] = field(default_factory=list)


class Harness:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.out: Path = args.out
        self.checks: list[Check] = []
        self.cells: list[Cell] = []
        self.printed: list[str] = []  # counterexamples to print
        self.props = read_tsv(HERE / "properties.tsv")
        self.fixtures = read_tsv(HERE / "fixtures.tsv")
        self.expected = {(r["fixture"], r["variant"], r["property"]): r for r in read_tsv(HERE / "expected.tsv")}
        self.label_rows = read_tsv(HERE / "labels.tsv")
        self.graphs: dict[tuple[str, str], Graph] = {}
        self.replays: dict[str, list[Path_]] = {}

    # -- bookkeeping -------------------------------------------------------

    def check(self, group: str, name: str, ok: Optional[bool], detail: str, gate: str = "") -> None:
        self.note(self.checks, group, name, ok, detail, gate)

    @staticmethod
    def note(sink: list[Check], group: str, name: str, ok: Optional[bool], detail: str, gate: str = "") -> None:
        status = "unknown" if ok is None else ("pass" if ok else "fail")
        sink.append(Check(group, name, status, detail, gate))

    def names(self, design: str) -> dict[str, str]:
        return {r["act"]: r["reference"] for r in self.label_rows if r["design"] == design}

    @staticmethod
    def stem(fixture: str) -> str:
        return Path(fixture).stem

    @staticmethod
    def request_text(p: dict[str, str]) -> str:
        t = f"{p['kind']} `{p['decision']}`"
        return t + (f" if always `{p['premise']}`" if p["premise"] != "-" else "")

    # -- 1. explore -------------------------------------------------------

    def explore_all(self) -> None:
        jobs = [(fx, v) for fx in self.fixtures for v in fx["variants"].split(",")]
        for fx, v in jobs:
            if v not in VARIANTS:
                raise SystemExit(f"BROKEN  fixtures.tsv: {fx['fixture']} names the variant {v}, which harness.py does not define")
        sinks: list[list[Check]] = [[] for _ in jobs]
        with concurrent.futures.ThreadPoolExecutor(self.args.jobs) as pool:
            results = list(pool.map(lambda k: self.explore(*jobs[k], sinks[k]), range(len(jobs))))
        for (fx, v), g, sink in zip(jobs, results, sinks):
            self.checks += sink
            if g is not None:
                self.graphs[(self.stem(fx["fixture"]), v)] = g
        # the same fixture under another fairness is the same graph: fairness changes the emitted models only
        for fx in self.fixtures:
            s = self.stem(fx["fixture"])
            a = self.graphs.get((s, "alice"))
            for v in fx["variants"].split(","):
                g = self.graphs.get((s, v))
                if v == "alice" or a is None or g is None:
                    continue
                same = a.edges == g.edges and all(a.states[i]["residual"] == g.states[i]["residual"] and a.states[i]["ledger"] == g.states[i]["ledger"] for i in a.states) and a.states.keys() == g.states.keys()
                self.check("explore", f"{s}: explored under {v} is the graph explored under alice", same,
                           "same states, residuals, ledgers and edges" if same else "the graphs differ, so an emitted model of one is not a model of the other")

    def explore(self, fx: dict[str, str], variant: str, sink: list[Check]) -> Optional[Graph]:
        """One l4 explore run; its checks go to sink, so that a run in a thread reports in a fixed order."""
        fixture = EXPLORE / fx["fixture"]
        s = self.stem(fx["fixture"])
        emit = self.out / "emit" / f"{s}.{variant}"
        emit.mkdir(parents=True, exist_ok=True)
        cmd = [self.l4.cmd[0], "explore", str(fixture), "--until", fx["until"]]
        for p in self.props:
            cmd += [KIND_FLAG[p["kind"]], p["decision"]]
            if p["premise"] != "-":
                cmd += ["--if-always", p["premise"]]
        cmd += ["--json", "--emit", str(emit), "--fixed-now", FIXED_NOW]
        for f in VARIANTS[variant]["fair"]:
            cmd += ["--fair", f]
        r = run(cmd, cwd=fixture.parent)
        logs = self.out / "logs"
        logs.mkdir(parents=True, exist_ok=True)
        (logs / f"explore.{s}.{variant}.json").write_text(r.out)
        err = logs / f"explore.{s}.{variant}.err"
        err.write_text(" ".join(cmd) + "\n\n" + r.err)
        name = f"{s} under {variant}: l4 explore"
        # 0: everything held; 4: a property was violated; 5: complete, a liveness verdict unknown. All three ran to the end.
        if r.code not in (0, 4, 5):
            self.note(sink, "explore", name, False, f"exited {r.code}, which is neither 0, 4 nor 5; see {err}")
            return None
        try:
            js = json.loads(r.out)
        except json.JSONDecodeError as e:
            self.note(sink, "explore", name, False, f"printed no JSON ({e}); see {err}")
            return None
        if not isinstance(js, list) or len(js) != 1:
            self.note(sink, "explore", name, False, f"explored {len(js) if isinstance(js, list) else '?'} contracts, not one")
            return None
        j = js[0]
        cov = j["coverage"]
        complete = cov.get("complete") and cov.get("frontierExhausted") and not cov.get("refused") and not cov.get("untried")
        self.note(sink, "explore", name, bool(complete), cov["line"] + ("" if complete else "; the harness compares only a complete exploration"))
        if not complete:
            return None
        states = {st["id"]: st for st in j["states"]}
        edges = {(t["from"], t["label"], t["to"]) for t in j["transitions"]}
        kinds = {(t["from"], t["label"], t["to"]): t["kind"] for t in j["transitions"]}
        labels = {d: {int(k[1:]): v for k, v in m.items()} for d, m in j.get("labels", {}).items()}
        tlas = sorted(emit.glob("*.tla"))
        g = Graph(s, variant, j["contract"], j["at"], states, edges, kinds, labels, j.get("checks", []), cov, emit,
                  tlas[0].stem if len(tlas) == 1 else "")
        if not g.base:
            self.note(sink, "explore", f"{s} under {variant}: --emit", False, f"wrote {len(tlas)} .tla files to {emit}, not one")
            return None
        unlabelled = [d for d in {p["decision"] for p in self.props} | {p["premise"] for p in self.props if p["premise"] != "-"}
                      if set(labels.get(d, {})) != set(states)]
        self.note(sink, "explore", f"{s} under {variant}: every state labelled with every decision", not unlabelled,
                   "all " + str(len(states)) + " states" if not unlabelled else "not labelled: " + ", ".join(unlabelled))
        return g

    # -- 2. the oracle and the bisimulation (spec 6.2) ----------------------

    def provenance(self) -> None:
        refs = sorted({fx["reference"] for fx in self.fixtures if fx["reference"] != "-"})
        if not refs:
            return
        refdir = (EXPLORE / refs[0]).parent
        pins = {}
        for line in (refdir / "PROVENANCE.md").read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\|\s*`([^`]+)`\s*\|\s*`([0-9a-f]{64})`\s*\|", line)
            if m:
                pins[m.group(1)] = m.group(2)
        for r in refs:
            aut = EXPLORE / r
            src = aut.with_name(aut.stem + "-viz.mcrl2")
            for f in (src, aut):
                if f.name not in pins:
                    self.check("oracle", f"{rel(f)}: SHA-256 pinned", False, "PROVENANCE.md pins no hash for it")
                    continue
                ok = f.is_file() and sha256(f) == pins[f.name]
                self.check("oracle", f"{rel(f)}: SHA-256 as PROVENANCE.md pins it", ok,
                           pins[f.name] if ok else f"is {sha256(f) if f.is_file() else 'missing'}, PROVENANCE.md pins {pins[f.name]}")
            name = f"{rel(aut)}: rebuilt from {src.name}, byte-identical"
            if not self.mcrl2.present:
                self.check("oracle", name, None, f"mCRL2 {self.mcrl2.found}", "bisim")
                continue
            d = self.out / "oracle"
            d.mkdir(parents=True, exist_ok=True)
            b = Path(self.mcrl2.cmd[0])
            r1 = run([str(b / "mcrl22lps"), "-q", str(src), str(d / f"{aut.stem}.lps")])
            r2 = run([str(b / "lps2lts"), "-q", str(d / f"{aut.stem}.lps"), str(d / aut.name)]) if r1.code == 0 else r1
            if r2.code != 0:
                self.check("oracle", name, False, f"mcrl22lps or lps2lts exited {r2.code}: {r2.err.strip()[:300]}")
                continue
            same = (d / aut.name).read_bytes() == aut.read_bytes()
            self.check("oracle", name, same, "mcrl22lps then lps2lts give the vendored file" if same else f"differs from the vendored file: see {d / aut.name}")

    @staticmethod
    def read_aut(text: str) -> tuple[tuple[int, int, int], list[tuple[int, str, int]]]:
        lines = [l for l in text.splitlines() if l.strip()]
        m = re.fullmatch(r"des \((\d+),\s*(\d+),\s*(\d+)\)\s*", lines[0])
        if not m:
            raise ValueError(f"no des header: {lines[0]!r}")
        edges = []
        for l in lines[1:]:
            e = re.fullmatch(r'\((\d+),\s*"(.*)",\s*(\d+)\)\s*', l)
            if not e:
                raise ValueError(f"not an edge: {l!r}")
            edges.append((int(e.group(1)), e.group(2), int(e.group(3))))
        return (int(m.group(1)), int(m.group(2)), int(m.group(3))), edges

    @staticmethod
    def write_aut(path: Path, init: int, nstates: int, edges: list[tuple[int, str, int]]) -> None:
        path.write_text(f"des ({init},{len(edges)},{nstates})\n" + "".join(f'({a},"{l}",{b})\n' for a, l, b in edges))

    def ltscompare(self, eq: str, a: Path, b: Path, tag: str) -> tuple[Optional[bool], str]:
        ce = self.out / "bisim" / f"{tag}.{eq}.ce"
        r = run([str(Path(self.mcrl2.cmd[0]) / "ltscompare"), f"-e{eq}", "-c", f"--counter-example-file={ce}", str(a), str(b)])
        last = [l for l in r.out.splitlines() if l.strip()]
        if r.code != 0 or not last or last[-1].strip() not in ("true", "false"):
            return None, f"ltscompare exited {r.code} and printed {last[-1] if last else 'nothing'!r}: {r.err.strip()[:300]}"
        if last[-1].strip() == "true":
            return True, ""
        return False, ce.read_text().strip() if ce.is_file() else "(no distinguishing formula written)"

    def distinguishing_trace(self, formula: str, names: dict[str, str], g: Graph) -> str:
        """A distinguishing formula that is a chain of diamonds, <a><b>true, as the #TRACE of its acts (spec 6.2)."""
        if not re.fullmatch(r"(<[^<>\[\]]+>)+true", formula):
            return ""
        inverse = {v: k for k, v in names.items()}
        acts = re.findall(r"<([^<>]+)>", formula)
        if not all(a in inverse for a in acts):
            return ""
        return "\n".join([f"#TRACE {g.contract} AT {g.at} WITH"] + [f"    {inverse[a]} AT {g.at}" for a in acts])

    def bisimulation(self) -> None:
        (self.out / "bisim").mkdir(parents=True, exist_ok=True)
        relabelled: dict[str, Path] = {}
        for fx in self.fixtures:
            s = self.stem(fx["fixture"])
            g = self.graphs.get((s, "alice"))
            if g is None:
                continue
            names = self.names(fx["labels"])
            emitted = g.emit / f"{g.base}.aut"
            (init, ntrans, nstates), edges = self.read_aut(emitted.read_text())
            # the .aut is the graph: the same edges as the explorer's JSON, so the bisimulation is about the graph the checks saw
            same = set(edges) == g.edges and nstates == len(g.states) and init == 0
            self.check("bisim", f"{s}: {emitted.name} is the explored graph", same,
                       f"{nstates} states, {ntrans} transitions" if same else "its edges are not the JSON's")
            unmapped = sorted({l for _, l, _ in edges if l not in names})
            self.check("bisim", f"{s}: every label of the graph has a reference label in labels.tsv ({fx['labels']})", not unmapped,
                       f"{len({l for _, l, _ in edges})} labels" if not unmapped else "unmapped: " + "; ".join(unmapped))
            # two acts relabelled alike would be merged, and a merge can make two different graphs bisimilar
            used = sorted({l for _, l, _ in edges if l in names})
            merged = sorted({names[l] for l in used if sum(names[k] == names[l] for k in used) > 1})
            self.check("bisim", f"{s}: no two of its acts share a reference label", not merged,
                       "the relabelling is one to one" if not merged else "shared: " + ", ".join(merged))
            if unmapped or merged or fx["reference"] == "-":
                continue
            out = self.out / "bisim" / f"{s}.relabelled.aut"
            self.write_aut(out, init, nstates, [(a, names[l], b) for a, l, b in edges])
            relabelled[s] = out
            ref = EXPLORE / fx["reference"]
            (rinit, rtrans, rstates), _ = self.read_aut(ref.read_text())
            self.check("bisim", f"{s}: as many states and transitions as {rel(ref)}", (nstates, ntrans) == (rstates, rtrans),
                       f"{nstates}/{ntrans} against {rstates}/{rtrans}")
            for eq in ("bisim", "branching-bisim"):
                name = f"{s}: {'strongly' if eq == 'bisim' else 'branching'} bisimilar to {rel(ref)}"
                if not self.mcrl2.present:
                    self.check("bisim", name, None, f"mCRL2 {self.mcrl2.found}", "bisim")
                    continue
                ok, why = self.ltscompare(eq, out, ref, f"{s}.{eq}")
                if ok is False:
                    t = self.distinguishing_trace(why, names, g)
                    why = f"not bisimilar; distinguishing formula {why}" + (f"; as a #TRACE:\n{t}" if t else "")
                self.check("bisim", name, ok if ok is not None else False, f"ltscompare -e{eq} printed true" if ok else why, "bisim")
            # the near miss: the same graph less its first edge out of the outset must be told apart from the reference
            first = next(i for i, (a, _, _) in enumerate(edges) if a == init)
            miss = self.out / "bisim" / f"{s}.near-miss.aut"
            dropped = edges[first]
            self.write_aut(miss, init, nstates, [(a, names[l], b) for i, (a, l, b) in enumerate(edges) if i != first])
            for eq in ("bisim", "branching-bisim"):
                name = f"{s}: less its edge ({dropped[0]}, {short(dropped[1], names)}, {dropped[2]}), not {eq} to {rel(ref)} (control)"
                if not self.mcrl2.present:
                    self.check("bisim", name, None, f"mCRL2 {self.mcrl2.found}", "bisim")
                    continue
                ok, why = self.ltscompare(eq, miss, ref, f"{s}.near-miss.{eq}")
                self.check("bisim", name, (ok is False) if ok is not None else False,
                           f"ltscompare printed false; distinguishing formula {why}" if ok is False else (why or "ltscompare printed true: it cannot tell a missing edge"), "bisim")
        # across designs: D1's graph is not D3's reference
        crosses = [("d1-naive", "brief/reference/d3.aut")]
        for s, r in crosses:
            if s not in relabelled:
                continue
            name = f"{s}: not bisimilar to {r} (control)"
            if not self.mcrl2.present:
                self.check("bisim", name, None, f"mCRL2 {self.mcrl2.found}", "bisim")
                continue
            ok, why = self.ltscompare("bisim", relabelled[s], EXPLORE / r, f"{s}.cross")
            fx = next(f for f in self.fixtures if self.stem(f["fixture"]) == s)
            t = self.distinguishing_trace(why, self.names(fx["labels"]), self.graphs[(s, "alice")]) if ok is False else ""
            self.check("bisim", name, (ok is False) if ok is not None else False,
                       f"ltscompare printed false; distinguishing formula {why}" + (f"; as a #TRACE of {s}:\n{t}" if t else "") if ok is False
                       else (why or "ltscompare printed true"), "bisim")
        # mCRL2 loads every emitted .aut, mutants included (WP3's acceptance, re-run here)
        for (s, v), g in sorted(self.graphs.items()):
            if v != "alice":
                continue
            name = f"{s}: ltsinfo reads {g.base}.aut"
            if not self.mcrl2.present:
                self.check("bisim", name, None, f"mCRL2 {self.mcrl2.found}", "bisim")
                continue
            r = run([str(Path(self.mcrl2.cmd[0]) / "ltsinfo"), str(g.emit / f"{g.base}.aut")])
            ns = re.search(r"Number of states: (\d+)\.", r.err + r.out)
            nt = re.search(r"Number of transitions: (\d+)\.", r.err + r.out)
            ok = r.code == 0 and ns is not None and nt is not None and (int(ns.group(1)), int(nt.group(1))) == (len(g.states), len(g.edges))
            self.check("bisim", name, ok, f"{ns.group(1)} states, {nt.group(1)} transitions" if ns and nt else f"exit {r.code}: {(r.err + r.out).strip()[:200]}", "bisim")

    # -- 3. the models' own tables -------------------------------------------

    @staticmethod
    def header_tables(text: str, comment: str) -> tuple[dict[str, str], set[str]]:
        """The emitted header's action table (identifier to label) and the identifiers it marks fair."""
        idents: dict[str, str] = {}
        fair: set[str] = set()
        c = re.escape(comment)
        for line in text.splitlines():
            m = re.match(rf"^{c}   (\w+): (.*); (\d+)$", line)
            if m and not m.group(1) in ("fair", "none"):
                idents[m.group(1)] = m.group(2)
            f = re.match(rf"^{c}   fair: (\w+)", line)
            if f:
                fair.add(f.group(1))
        return idents, fair

    @staticmethod
    def actor_matches(label: str, name: str) -> bool:
        """Whether --fair <name> names this act's actor: its party, or the first words of its constructor (option C)."""
        m = re.match(r"PARTY (\S+) DOES `([^`]*)`", label)
        return bool(m) and (m.group(1) == name or m.group(2) == name or m.group(2).startswith(name + " "))

    def models(self) -> None:
        """The emitted TLA+ and NuSMV models are the explored graph: the same edges, the same labelled states, and
        weak fairness on exactly the acts of the actors named that move (spec 4.6), and on nothing else."""
        for (s, v), g in sorted(self.graphs.items()):
            tla = (g.emit / f"{g.base}.tla").read_text()
            smv = (g.emit / f"{g.base}.smv").read_text()
            t_idents, t_fair = self.header_tables(tla, "\\*")
            n_idents, n_fair = self.header_tables(smv, "--")
            # the edges
            t_edges, cur = set(), None
            for line in tla.splitlines():
                m = re.match(r"^(\w+) ==$", line)
                if m:
                    cur = m.group(1) if m.group(1) in t_idents else None
                    continue
                if cur:
                    # one edge is written "/\ s = i /\ s' = j", several "\/ (s = i /\ s' = j)" each
                    for a, b in re.findall(r"\bs = (\d+) /\\ s' = (\d+)", line):
                        t_edges.add((int(a), t_idents[cur], int(b)))
            n_edges = set()
            for a, b, w in re.findall(r"\(s = (\d+) & next\(s\) = (\d+) & next\(act\) = (\w+)\)", smv):
                base = w if w in n_idents else max((i for i in n_idents if w.startswith(i + "_still")), key=len, default=None)
                n_edges.add((int(a), n_idents.get(base, f"<{w}>") if base else f"<{w}>", int(b)))
            for tool, edges in (("TLA+", t_edges), ("NuSMV", n_edges)):
                extra, missing = edges - g.edges, g.edges - edges
                self.check("model", f"{s} under {v}: the {tool} model's transitions are the explored graph's", not extra and not missing,
                           f"{len(edges)} transitions" if not extra and not missing else f"{len(extra)} not in the graph, {len(missing)} of the graph's missing")
            # the labelled states
            bad = []
            for d in sorted({p["decision"] for p in self.props} | {p["premise"] for p in self.props if p["premise"] != "-"}):
                want = {i for i, b in g.labels.get(d, {}).items() if b}
                # NuSMV has no empty set, so a decision TRUE nowhere is written FALSE there
                for tool, text, pat in (("TLA+", tla, r"^\\\* `{d}`\n(\w+) == s \\in \{{([\d, ]*)\}}$"),
                                        ("NuSMV", smv, r"^  -- `{d}`: the states the evaluator labelled it TRUE in\n  (\w+) := (?:s in \{{([\d, ]*)\}}|FALSE);$")):
                    m = re.search(pat.format(d=re.escape(d)), text, re.M)
                    got = {int(x) for x in (m.group(2) or "").split(",") if x.strip()} if m else None
                    if got != want:
                        bad.append(f"{tool} `{d}`: {sorted(got) if got is not None else 'absent'}, the evaluator {sorted(want)}")
            self.check("model", f"{s} under {v}: each decision is TRUE in the same states in both models as the evaluator labelled", not bad,
                       "every decision the properties read" if not bad else "; ".join(bad))
            # the fairness: on the named actors' acts that move, and nothing else
            names = VARIANTS[v]["fair"]
            want = {l for (_, l, _) in g.edges if any(self.actor_matches(l, n) for n in names)
                    and any(a != b for a, ll, b in g.edges if ll == l)}
            t_fair_l = {t_idents[i] for i in t_fair if i in t_idents}
            n_fair_l = {n_idents[i] for i in n_fair if i in n_idents}
            wf = set(re.findall(r"WF_vars\((\w+)", tla.split("FairSpec ==", 1)[1].splitlines()[0])) if "FairSpec ==" in tla else set()
            justice = len(re.findall(r"^JUSTICE ", smv, re.M))
            ok = t_fair_l == want and n_fair_l == want and {t_idents.get(i) for i in wf} == want and justice == len(want)
            names_ = self.names(next(f["labels"] for f in self.fixtures if self.stem(f["fixture"]) == s))
            whose = ", ".join(names) + "'s acts that move" if names else "no act"
            self.check("model", f"{s} under {v}: weak fairness on exactly {whose}", ok,
                       (", ".join(sorted(short(l, names_) for l in want)) or "none") + f"; {len(wf)} WF_vars in FairSpec, {justice} JUSTICE" if ok
                       else f"want {sorted(short(l, names_) for l in want)}; the TLA+ header marks {sorted(short(l, names_) for l in t_fair_l)}, FairSpec has {sorted(wf)}, NuSMV has {justice} JUSTICE")

    # -- 4. TLC --------------------------------------------------------------

    def tlc_run(self, cfg: Path, tla: Path, tag: str) -> tuple[str, str, Optional[Path_], str]:
        """TLC on one configuration: (outcome, detail, trace, version); outcome is no error, invariant violated, temporal violated or broken."""
        java, jar = self.tlc.cmd
        meta = self.out / "tlc" / "meta" / tag
        # one temporary directory per run: TLC copies Naturals.tla into it, and two runs sharing one were measured
        # (2026-10-26) to fail with exit 150, "Cannot find source file for module Naturals"
        jtmp = self.out / "tlc" / "java-tmp" / tag
        meta.mkdir(parents=True, exist_ok=True)
        jtmp.mkdir(parents=True, exist_ok=True)
        r = run([java, f"-Djava.io.tmpdir={jtmp}", "-XX:+UseParallelGC", "-cp", jar, "tlc2.TLC", "-tool", "-workers", "1",
                 "-metadir", str(meta), "-config", str(cfg), str(tla)], cwd=tla.parent)
        log = self.out / "tlc" / f"{tag}.log"
        log.write_text(r.out + r.err)
        msgs = re.findall(r"@!@!@STARTMSG (\d+):(\d+) @!@!@\n(.*?)@!@!@ENDMSG \1 @!@!@", r.out, re.S)
        codes = {int(c) for c, _, _ in msgs}
        version = next((re.sub(r"\s+", " ", t).strip() for c, _, t in msgs if c == "2262"), "")
        done = next((t for c, _, t in msgs if c == "2199"), "")
        if r.code == 0 and 2193 in codes and "0 states left on queue" in done:
            return "no error", done.strip(), None, version
        if r.code == 12 and 2110 in codes:
            outcome = "invariant violated"
        elif r.code == 13 and 2116 in codes:
            outcome = "temporal violated"
        else:
            return "broken", f"TLC exited {r.code} with messages {sorted(codes)}; see {log}", None, version
        return outcome, next((t.strip() for c, _, t in msgs if c in ("2110", "2116")), ""), self.tlc_trace(msgs), version

    @staticmethod
    def tlc_trace(msgs: list[tuple[str, str, str]]) -> Path_:
        states: list[int] = []
        acts: list[str] = []
        p = Path_([], [], None, "TLC")
        for c, _, t in msgs:
            if c == "2217":
                s = re.search(r"^/\\ s = (\d+)$", t, re.M)
                a = re.search(r'^/\\ lastAct = "([^"]*)"$', t, re.M)
                if not s or not a:
                    p.problems.append(f"a state TLC printed has no s or lastAct: {t.strip()[:120]!r}")
                    continue
                states.append(int(s.group(1)))
                acts.append(a.group(1))
            elif c == "2122":
                m = re.match(r"(\d+): Back to state: <(\w+)", t)
                if not m:
                    p.problems.append(f"cannot read TLC's loop: {t.strip()[:120]!r}")
                    continue
                k = int(m.group(1)) - 1
                p.loop = k
                states.append(states[k])
                acts.append(m.group(2))
                if acts[k] != m.group(2):
                    p.problems.append(f"TLC's loop re-enters state {k + 1} by {m.group(2)}, whose lastAct is {acts[k]}")
            elif c == "2218":
                p.problems.append("TLC's counterexample ends in stuttering, which the graph has no edge for")
        p.states = states
        p.steps = [(states[i - 1], acts[i], states[i]) for i in range(1, len(states))]  # labelled by identifier until resolved
        return p

    def tlc_all(self) -> None:
        jobs = []
        for (s, v), g in self.graphs.items():
            tla = g.emit / f"{g.base}.tla"
            text = tla.read_text()
            idents, fair = self.header_tables(text, "\\*")
            cfgs = {}
            for cfg in g.emit.glob(f"{g.base}.*.cfg"):
                first = cfg.read_text().splitlines()[0]
                m = re.match(r"^\\\* (.*), on \w+\.tla:$", first)
                if m:
                    cfgs[m.group(1)] = cfg
            if v == "alice":
                jobs.append((s, v, "model", g.emit / f"{g.base}.cfg", tla, idents))
            for p in self.props:
                if not self.wanted(s, v, p["id"]):
                    continue
                cfg = cfgs.get(self.request_text(p))
                if cfg is None:
                    self.cells.append(Cell(s, v, p["id"], "TLC", "broken", f"no configuration for {self.request_text(p)} was emitted"))
                    continue
                jobs.append((s, v, p["id"], cfg, tla, idents))
        if not self.tlc.present:
            for s, v, pid, *_ in jobs:
                if pid == "model":
                    self.check("model", f"{s}: TLC loads {s}'s model and finds no deadlock", None, f"TLC {self.tlc.found}")
                else:
                    self.cells.append(Cell(s, v, pid, "TLC", "unknown", f"TLC {self.tlc.found}"))
            return
        (self.out / "tlc").mkdir(parents=True, exist_ok=True)
        with concurrent.futures.ThreadPoolExecutor(self.args.jobs) as pool:
            results = list(pool.map(lambda j: self.tlc_run(j[3], j[4], f"{j[0]}.{j[1]}.{j[2]}"), jobs))
        for (s, v, pid, cfg, tla, idents), (outcome, detail, trace, version) in zip(jobs, results):
            if version and not self.tlc.version:
                self.tlc.version = version
            if pid == "model":
                self.check("model", f"{s}: TLC loads {cfg.name} and finds no deadlock", outcome == "no error", detail)
                continue
            p = next(q for q in self.props if q["id"] == pid)
            verdict = {
                ("always", "no error"): "holds", ("always", "invariant violated"): "violated",
                ("reachable", "invariant violated"): "holds", ("reachable", "no error"): "violated",
                ("stays", "no error"): "holds", ("stays", "temporal violated"): "violated",
                ("eventually", "no error"): "holds", ("eventually", "temporal violated"): "violated",
            }.get((p["kind"], outcome), "broken")
            cell = Cell(s, v, pid, "TLC", verdict, f"{cfg.name}: {outcome}" + (f" ({detail})" if verdict == "broken" else ""))
            if trace is not None:
                trace.steps = [(a, idents.get(i, f"<no action {i}>"), b) for a, i, b in trace.steps]
                for a, l, b in trace.steps:
                    if l.startswith("<no action"):
                        trace.problems.append(f"TLC's action {l[11:-1]} is not in the model's action table")
                cell.paths.append(trace)
            self.cells.append(cell)

    def wanted(self, stem: str, variant: str, pid: str) -> bool:
        """The cells a fixture is checked on: every property under alice, the liveness ones under the other variants."""
        p = next(q for q in self.props if q["id"] == pid)
        return variant == "alice" or p["kind"] == "eventually"

    # -- 5. NuSMV ------------------------------------------------------------

    def nusmv_all(self) -> None:
        for (s, v), g in sorted(self.graphs.items()):
            wanted = [p for p in self.props if self.wanted(s, v, p["id"])]
            if not self.nusmv.present:
                for p in wanted:
                    self.cells.append(Cell(s, v, p["id"], "NuSMV", "unknown", f"NuSMV {self.nusmv.found}"))
                self.check("model", f"{s} under {v}: NuSMV finds fair states", None, f"NuSMV {self.nusmv.found}",
                           "liveness" if v != "none" else "")
                continue
            self.nusmv_one(s, v, g, wanted)

    def nusmv_one(self, s: str, v: str, g: Graph, wanted: list[dict[str, str]]) -> None:
        smv = g.emit / f"{g.base}.smv"
        text = smv.read_text()
        idents, fair = self.header_tables(text, "--")
        trans = {(int(a), w, int(b)) for a, b, w in re.findall(r"\(s = (\d+) & next\(s\) = (\d+) & next\(act\) = (\w+)\)", text)}
        lines = text.splitlines()
        names: dict[str, list[tuple[str, str]]] = {}
        for p in wanted:
            rt = self.request_text(p)
            found: list[tuple[str, str]] = []
            for i, line in enumerate(lines):
                if line == f"-- {rt}" or line.startswith(f"-- {rt}:"):
                    for nxt in lines[i + 1:]:
                        m = re.match(r"^(INVARSPEC|SPEC|CTLSPEC|LTLSPEC) NAME (\w+) :=", nxt)
                        if not m:
                            break
                        found.append((m.group(1), m.group(2)))
                    break
            names[p["id"]] = found
        cmds = [f"set input_file {smv}", "go", "print_reachable_states", "print_fair_states"]
        order: list[tuple[str, str, str]] = []
        for p in wanted:
            for kind, n in names[p["id"]]:
                cmds.append({"INVARSPEC": "check_invar", "SPEC": "check_ctlspec", "CTLSPEC": "check_ctlspec", "LTLSPEC": "check_ltlspec"}[kind] + f" -P {n}")
                order.append((p["id"], kind, n))
        cmds.append("quit")
        d = self.out / "nusmv"
        d.mkdir(parents=True, exist_ok=True)
        script = d / f"{s}.{v}.cmd"
        script.write_text("\n".join(cmds) + "\n")
        r = run([self.nusmv.cmd[0], "-source", str(script)], cwd=g.emit)
        log = d / f"{s}.{v}.log"
        log.write_text(r.out + "\n--- stderr ---\n" + r.err)
        reach = re.search(r"^reachable states: (\d+)", r.out, re.M)
        fairs = re.search(r"^fair states: (\d+)", r.out, re.M)
        ok_fair = fairs is not None and int(fairs.group(1)) > 0
        self.check("model", f"{s} under {v}: NuSMV finds fair states", ok_fair,
                   f"{fairs.group(1)} fair of {reach.group(1) if reach else '?'} reachable (states of s and act)" if fairs else f"no fair-state count; see {log}",
                   "liveness")
        blocks = re.split(r"^(?=-- (?:specification|invariant) )", r.out, flags=re.M)[1:]
        if r.code != 0 or len(blocks) != len(order):
            for p in wanted:
                self.cells.append(Cell(s, v, p["id"], "NuSMV", "broken", f"NuSMV exited {r.code} and printed {len(blocks)} verdicts for {len(order)} checks; see {log}"))
            return
        answers: dict[str, list[tuple[str, str, bool, Optional[Path_]]]] = {}
        for (pid, kind, n), b in zip(order, blocks):
            m = re.match(r"-- (?:specification|invariant) .* is (true|false)\s*$", b.splitlines()[0])
            if not m:
                answers.setdefault(pid, []).append((kind, n, False, None))
                continue
            trace = self.nusmv_trace(b, idents, trans) if m.group(1) == "false" else None
            answers.setdefault(pid, []).append((kind, n, m.group(1) == "true", trace))
        for p in wanted:
            a = answers.get(p["id"], [])
            kinds = [k for k, _, _, _ in a]
            truth = {k: t for k, _, t, _ in a}
            verdict, detail = "broken", f"the model has {', '.join(f'{k} {n}' for k, n, _, _ in a) or 'no property'} for it"
            if p["kind"] == "always" and sorted(kinds) == ["INVARSPEC", "SPEC"]:
                if truth["INVARSPEC"] == truth["SPEC"]:
                    verdict = "holds" if truth["SPEC"] else "violated"
                    detail = f"INVARSPEC and AG both {str(truth['SPEC']).lower()}"
                else:
                    detail = f"INVARSPEC is {truth['INVARSPEC']} and AG is {truth['SPEC']}: the two forms disagree"
            elif p["kind"] == "reachable" and sorted(kinds) == ["INVARSPEC", "SPEC"]:
                if truth["SPEC"] != truth["INVARSPEC"]:
                    verdict = "holds" if truth["SPEC"] else "violated"
                    detail = f"EF {str(truth['SPEC']).lower()}, never-invariant {str(truth['INVARSPEC']).lower()}"
                else:
                    detail = f"EF and the never-invariant are both {truth['SPEC']}: they must differ"
            elif p["kind"] in ("stays", "eventually") and kinds == ["LTLSPEC"]:
                verdict = "holds" if truth["LTLSPEC"] else "violated"
                detail = f"LTLSPEC {str(truth['LTLSPEC']).lower()}"
            cell = Cell(s, v, p["id"], "NuSMV", verdict, detail)
            cell.paths = [t for _, _, _, t in a if t is not None]
            self.cells.append(cell)

    @staticmethod
    def nusmv_trace(block: str, idents: dict[str, str], trans: set[tuple[int, str, int]]) -> Path_:
        p = Path_([], [], None, "NuSMV")
        cur: dict[str, str] = {}
        seq: list[tuple[int, str]] = []
        loop_next = False
        for line in block.splitlines()[1:]:
            if line.strip() == "-- Loop starts here":
                loop_next = True
            elif re.match(r"^\s*-> State: \S+ <-", line):
                seq.append((-1, ""))  # filled in as its assignments are read; NuSMV prints only what changed
                if loop_next:
                    p.loop = len(seq) - 1
                    loop_next = False
            else:
                m = re.match(r"^\s+(\w+) = (\S+)$", line)
                if m and seq:
                    cur[m.group(1)] = m.group(2)
            if seq:
                seq[-1] = (int(cur.get("s", -1)), cur.get("act", ""))
        if not seq:
            p.problems.append("NuSMV printed no trace")
            return p
        p.states = [st for st, _ in seq]
        if p.loop is not None and seq[-1] != seq[p.loop]:
            p.problems.append(f"NuSMV's loop does not close: it ends in {seq[-1]}, not {seq[p.loop]}")

        def label(w: str) -> str:
            if w in idents:
                return idents[w]
            bases = [i for i in idents if w.startswith(i + "_still")]
            return idents[max(bases, key=len)] if bases else f"<no action {w}>"

        for i in range(1, len(seq)):
            (a, _), (b, w) = seq[i - 1], seq[i]
            if (a, w, b) not in trans:
                p.problems.append(f"({a}, {w}, {b}) is not a transition of the NuSMV model")
            l = label(w)
            if l.startswith("<no action"):
                p.problems.append(f"NuSMV's act value {w} is not in the model's action table")
            p.steps.append((a, l, b))
        return p

    # -- 6. the in-process column ----------------------------------------------

    def inprocess_all(self) -> None:
        for (s, v), g in sorted(self.graphs.items()):
            for p in self.props:
                if not self.wanted(s, v, p["id"]):
                    continue
                c = next((c for c in g.checks if c["kind"] == p["kind"] and c["property"] == p["decision"]
                          and (c.get("premise") or "-") == p["premise"]), None)
                if c is None:
                    self.cells.append(Cell(s, v, p["id"], "in-process", "broken", "l4 explore printed no check for it"))
                    continue
                if p["kind"] == "eventually":
                    ok = c["verdict"] == "unknown" and c.get("reason", "").startswith("liveness")
                    self.cells.append(Cell(s, v, p["id"], "in-process", "n/a" if ok else "broken",
                                           c.get("reason", "") if ok else f"a liveness property answered {c['verdict']} in process"))
                    continue
                cell = Cell(s, v, p["id"], "in-process", c["verdict"] if c["verdict"] in ("holds", "violated") else "broken", c.get("reason", ""))
                if c.get("path"):
                    path = self.walk(g, c["path"]["events"], "in-process")
                    if c.get("replayed") is not True:
                        path.problems.append("l4 explore did not replay it on the evaluator before printing it")
                    cell.paths.append(path)
                self.cells.append(cell)

    @staticmethod
    def walk(g: Graph, events: list[str], source: str) -> Path_:
        p = Path_([0], [], None, source)
        for e in events:
            label = re.sub(r" AT [0-9.]+$", "", e)
            nxt = [b for a, l, b in g.edges if a == p.states[-1] and l == label]
            if len(nxt) != 1:
                p.problems.append(f"{label} leads from state {p.states[-1]} to {len(nxt)} states in the graph, not one")
                return p
            p.steps.append((p.states[-1], label, nxt[0]))
            p.states.append(nxt[0])
        return p

    # -- 7. every path, replayed -------------------------------------------------

    def judge_paths(self) -> None:
        """Each counterexample and witness: on the graph, against the property, under the fairness, and against expected.tsv."""
        for cell in self.cells:
            g = self.graphs.get((cell.fixture, cell.variant))
            if g is None or not cell.paths:
                continue
            p = next(q for q in self.props if q["id"] == cell.prop)
            fx = next(f for f in self.fixtures if self.stem(f["fixture"]) == cell.fixture)
            names = self.names(fx["labels"])
            fair_idents = self.fair_labels(g)
            exp = self.expected.get((cell.fixture, cell.variant, cell.prop), {})
            for k, path in enumerate(cell.paths, 1):
                problems = list(path.problems)
                for a, l, b in path.steps:
                    if (a, l, b) not in g.edges:
                        problems.append(f"({a}, {short(l, names)}, {b}) is not an edge of the explored graph")
                problems += self.witnesses(g, p, path, fair_idents)
                if p["kind"] in ("always", "reachable") and exp.get("path", "-") != "-":
                    got = ",".join(short(l, names) for _, l, _ in path.steps)
                    if got != exp["path"]:
                        problems.append(f"the path is {got}, and expected.tsv says {exp['path']}")
                what = {"always": "counterexample", "reachable": "witness", "stays": "counterexample", "eventually": "lasso"}[p["kind"]]
                form = f" ({k} of {len(cell.paths)})" if len(cell.paths) > 1 else ""
                name = f"{cell.fixture} under {cell.variant}: {cell.prop} {what} from {path.source}{form}"
                path.ok = not problems
                self.check("path", name, path.ok, self.describe(path, names) if path.ok else "; ".join(problems))
                if path.ok:
                    self.replays.setdefault(cell.fixture, []).append(path)

    def fair_labels(self, g: Graph) -> set[str]:
        idents, fair = self.header_tables((g.emit / f"{g.base}.tla").read_text(), "\\*")
        return {idents[i] for i in fair if i in idents}

    def witnesses(self, g: Graph, p: dict[str, str], path: Path_, fair: set[str]) -> list[str]:
        lab = g.labels.get(p["decision"], {})
        if not path.states:
            return ["the path is empty"]
        last = path.states[-1]
        if p["kind"] == "always":
            return [] if lab.get(last) is False else [f"`{p['decision']}` is not FALSE in its last state, s{last}"]
        if p["kind"] == "reachable":
            return [] if lab.get(last) is True else [f"`{p['decision']}` is not TRUE in its last state, s{last}"]
        if p["kind"] == "stays":
            return [] if any(lab.get(a) and lab.get(b) is False for a, _, b in path.steps) else ["no step on it goes from TRUE to FALSE"]
        # eventually: a lasso on which p never holds (and the premise always does), fair under the variant's assumption
        out = []
        if path.loop is None:
            return ["a liveness counterexample must be a lasso, and this has no loop"]
        if any(lab.get(st) is not False for st in path.states):
            out.append(f"`{p['decision']}` is TRUE somewhere on it")
        if p["premise"] != "-" and any(g.labels.get(p["premise"], {}).get(st) is not True for st in path.states):
            out.append(f"`{p['premise']}` is FALSE somewhere on it")
        loop_steps = path.steps[path.loop:]
        loop_states = set(path.states[path.loop:])
        for act in sorted(fair):
            moving = {(a, b) for a, l, b in g.edges if l == act and a != b}
            taken = any(l == act and a != b for a, l, b in loop_steps)
            disabled_somewhere = any(not any(a == st for a, _ in moving) for st in loop_states)
            if not (taken or disabled_somewhere):
                out.append(f"it is not fair: {act} is enabled throughout its loop and never taken")
        return out

    @staticmethod
    def describe(path: Path_, names: dict[str, str]) -> str:
        acts = [short(l, names) for _, l, _ in path.steps]
        if path.loop is None:
            return f"{', '.join(acts) or '(no events)'} to s{path.states[-1]}"
        return f"{', '.join(acts[:path.loop]) or '(no events)'}, then {', '.join(acts[path.loop:])} forever (s{path.states[path.loop]})"

    def replay_all(self) -> None:
        """Every path, every prefix of it, run by l4 run: the residual and the kept ledger cells must be the graph state's."""
        jobs = [(s, ps) for s, ps in sorted(self.replays.items())]
        with concurrent.futures.ThreadPoolExecutor(self.args.jobs) as pool:
            for s, results in zip([j[0] for j in jobs], pool.map(lambda j: self.replay(*j), jobs)):
                for name, ok, detail in results:
                    self.check("replay", name, ok, detail)

    def replay(self, s: str, paths: list[Path_]) -> list[tuple[str, bool, str]]:
        g = self.graphs[(s, "alice")]
        fx = next(f for f in self.fixtures if self.stem(f["fixture"]) == s)
        names = self.names(fx["labels"])
        fixture = (EXPLORE / fx["fixture"]).resolve()
        d = self.out / "replay" / s
        d.mkdir(parents=True, exist_ok=True)
        for sib in fixture.parent.glob("*.l4"):
            if sib.name != fixture.name:
                shutil.copyfile(sib.resolve(), d / sib.name)
        name = f"{s}: {len(paths)} paths replayed on the evaluator, every prefix"

        def failed(why: str) -> list[tuple[str, bool, str]]:
            for path in paths:
                path.replayed = False
            return [(name, False, why)]

        # every event of every state's path is at the outset's instant, so a path's events can all be put there
        instants = {m.group(1) if m else "?" for st in g.states.values() for e in st["path"] for m in [re.search(r" AT ([0-9.]+)$", e)]}
        if instants - {g.at}:
            return failed(f"events at {sorted(instants)}, so the harness cannot place a path's events in time")
        if any(g.kinds.get(st) == "tick" for path in paths for st in path.steps):
            return failed("a path takes a tick, which the harness does not place in time")
        original = fixture.read_text()
        text = original + ("" if original.endswith("\n") else "\n")
        line = text.count("\n") + 1
        prefixes: dict[tuple[str, ...], tuple[int, int]] = {}  # events -> (first line of its #TRACE, the state it must reach)
        users: dict[tuple[str, ...], list[Path_]] = {}
        clash = []
        for path in paths:
            for i in range(1, len(path.steps) + 1):
                # the explorer's own terminal self-loop is not an event, so it is not written into a #TRACE
                key = tuple(st[1] for st in path.steps[:i] if g.kinds.get(st) != "terminal")
                target = path.steps[i - 1][2]
                if not key:
                    continue
                users.setdefault(key, []).append(path)
                if key in prefixes:
                    if prefixes[key][1] != target:
                        clash.append(f"{', '.join(short(l, names) for l in key)} reaches s{prefixes[key][1]} on one path and s{target} on another")
                    continue
                text += "\n"
                line += 1
                prefixes[key] = (line, target)
                block = [f"#TRACE {g.contract} AT {g.at} WITH"] + [f"    {l} AT {g.at}" for l in key]
                text += "\n".join(block) + "\n"
                line += len(block)
        if clash:
            return failed("; ".join(clash))
        replay_file = d / fixture.name
        replay_file.write_text(text)
        r = run([self.l4.cmd[0], "run", "--fixed-now", FIXED_NOW, replay_file.name], cwd=d)
        (d / "l4-run.log").write_text(r.out + "\n--- stderr ---\n" + r.err)
        blocks = self.run_blocks(r.out)
        kept = {(e["ledger"], e["cell"]): e["kept"] for st in g.states.values() for e in st["ledger"]}
        bad = []
        for path in paths:
            path.replayed = True
        def view(residual: str, cells: dict[tuple[str, str], list[str]]) -> tuple:
            return (residual, tuple(sorted((k, tuple(cells.get(k, []))) for k in kept)))

        graph_views = {sid: view(st["residual"], {(e["ledger"], e["cell"]): e["values"] for e in st["ledger"]}) for sid, st in g.states.items()}
        for key, (start, target) in prefixes.items():
            b = blocks.get(start)
            why = []
            acts = ", ".join(short(l, names) for l in key)
            if b is None:
                why.append(f"l4 run printed no result for the #TRACE at line {start}")
            else:
                residual, ledger = b
                got: dict[tuple[str, str], list[str]] = {}
                for (lg, cell), how in kept.items():
                    vals = [v for c, v in ledger.get(lg, []) if c == cell]
                    got[(lg, cell)] = vals[-1:] if how == "latest" else vals
                mine = view(residual, got)
                # the evaluator's state must be the target's, and, since the comparison has to be able to tell, no other
                matching = sorted(sid for sid, gv in graph_views.items() if gv == mine)
                if matching != [target]:
                    if residual != g.states[target]["residual"]:
                        why.append(f"{acts}: the evaluator's residual is not s{target}'s")
                    want = dict(graph_views[target][1])
                    for k in kept:
                        if tuple(got.get(k, [])) != want.get(k, ()):
                            why.append(f"{acts}: {k[0]}'s `{k[1]}` is {got.get(k, [])} on the evaluator and {list(want.get(k, ()))} in s{target}")
                    if not why:
                        why.append(f"{acts}: the evaluator's state matches s{target} and also {[m for m in matching if m != target]}, so the comparison cannot tell them apart")
            if why:
                bad += why
                for path in users[key]:
                    path.replayed = False
        return [(f"{name} ({len(prefixes)} #TRACEs, one l4 run)", not bad,
                 f"each reaches its graph state's residual and kept ledger cells, and no other state's; see {replay_file}" if not bad else "; ".join(bad[:6]))]

    @staticmethod
    def run_blocks(out: str) -> dict[int, tuple[str, dict[str, list[tuple[str, str]]]]]:
        """l4 run's text, per Evaluation block: the line its directive starts at, the residual and the ledgers."""
        res: dict[int, tuple[str, dict[str, list[tuple[str, str]]]]] = {}
        parts = re.split(r"^(?=Evaluation\[\d+\] @ )", out, flags=re.M)
        for part in parts:
            m = re.match(r"Evaluation\[\d+\] @ \S+?:(\d+):\d+-\d+:\d+\n", part)
            if not m:
                continue
            lines = part.splitlines()
            try:
                i = lines.index("Result:")
            except ValueError:
                continue
            body: list[str] = []
            j = i + 1
            while j < len(lines) and not re.match(r"^(Ledger \(|Official record:|Trace:)", lines[j]):
                body.append(lines[j][2:] if lines[j].startswith("  ") else lines[j])
                j += 1
            while body and not body[-1].strip():
                body.pop()
            ledgers: dict[str, list[tuple[str, str]]] = {}
            current = None
            for l in lines[j:]:
                h = re.match(r"^Ledger \((.*)\):$", l)
                if h:
                    current = h.group(1)
                    continue
                if l == "Official record:":
                    current = "OFFICIAL"
                    continue
                if l.startswith("Trace:"):
                    break
                e = re.match(r"^\s+(?:RECORD|COMMIT|ATTEST) `([^`]+)` IS (.*?)\s{3}\[", l)
                if e and current:
                    ledgers.setdefault(current, []).append((e.group(1), e.group(2)))
            res[int(m.group(1))] = ("\n".join(body), ledgers)
        return res

    # -- 8. the matrix, the controls and the gate ------------------------------

    def judge_cells(self) -> None:
        by = {}
        for c in self.cells:
            by.setdefault((c.fixture, c.variant, c.prop), {})[c.column] = c
        seen = set()
        for (s, v, pid), cols in sorted(by.items(), key=lambda kv: (kv[0][1] != "alice", kv[0])):
            seen.add((s, v, pid))
            p = next(q for q in self.props if q["id"] == pid)
            exp = self.expected.get((s, v, pid))
            known = {k: c.verdict for k, c in cols.items() if c.verdict in ("holds", "violated")}
            broken = {k: c.detail for k, c in cols.items() if c.verdict == "broken"}
            unknown = [k for k, c in cols.items() if c.verdict == "unknown"]
            name = f"{s} under {v}: {pid} {self.request_text(p)}"
            problems = [f"{k}: {d}" for k, d in broken.items()]
            if len(set(known.values())) > 1:
                problems.append("the columns disagree: " + ", ".join(f"{k} {x}" for k, x in known.items()))
            if exp is None or exp["verdict"] not in ("holds", "violated"):
                problems.append("expected.tsv pins no verdict for it; measured " + (", ".join(f"{k} {x}" for k, x in known.items()) or "nothing"))
            else:
                problems += [f"{k} says {x}, expected.tsv {exp['verdict']} ({exp['source']})" for k, x in known.items() if x != exp["verdict"]]
            liveness = p["kind"] == "eventually"
            if not known and not unknown:
                problems.append("no column answered it")
            for k, c in cols.items():
                for path in c.paths:
                    what = "lasso" if path.loop is not None else "path"
                    if path.ok is False:
                        problems.append(f"{k}'s {what} failed its check on the graph (see the path checks)")
                    elif path.replayed is False:
                        problems.append(f"{k}'s {what} failed its replay on the evaluator (see the replay checks)")
            detail = ", ".join(f"{k} {c.verdict}" for k, c in cols.items())
            if problems:
                self.check("verdict", name, False, "; ".join(problems))
            elif unknown:
                self.check("verdict", name, None, detail + f"; expected {exp['verdict']}", "liveness" if liveness else "")
            else:
                self.check("verdict", name, True, detail + f"; expected {exp['verdict']} ({exp['source']})")
        for key, row in self.expected.items():
            if key not in seen and key[0] in {self.stem(f["fixture"]) for f in self.fixtures}:
                self.check("verdict", f"{key[0]} under {key[1]}: {key[2]}", False, "expected.tsv pins a verdict that no column computed")

    def controls(self) -> None:
        cells = {(c.fixture, c.variant, c.prop, c.column): c for c in self.cells}

        def verdict(s, v, pid, col):
            c = cells.get((s, v, pid, col))
            return c.verdict if c else "absent"

        def sound(c: Cell) -> bool:
            return bool(c.paths) and all(p.ok and p.replayed for p in c.paths)

        # the positive control: D1 violates P1, and every column prints Sequence A
        exp = self.expected.get(("d1-naive", "alice", "P1"), {})
        for col in ("in-process", "TLC", "NuSMV"):
            c = cells.get(("d1-naive", "alice", "P1", col))
            name = f"positive control, {col}: D1 violates P1 by Sequence A ({exp.get('path', '?').replace(',', ', ')})"
            if c is None or c.verdict == "unknown":
                self.check("control", name, None, c.detail if c else "no cell")
                continue
            ok = c.verdict == "violated" and sound(c)
            self.check("control", name, ok,
                       f"violated; {len(c.paths)} counterexample(s), each Sequence A, on the graph and replayed on the evaluator" if ok
                       else f"{c.verdict}; {len(c.paths)} counterexample(s): {c.detail}. If D1 passes P1, suspect the encoding before you believe it")
        # non-vacuity: under every fairness a liveness verdict is answered under, the environment need never act
        for s in sorted({s for s, v in self.graphs if v in ("alice", "none")}):
            for v in ("alice", "none"):
                if (s, v) not in self.graphs:
                    continue
                for col in ("TLC", "NuSMV"):
                    c = cells.get((s, v, "C", col))
                    name = f"non-vacuity, {col}: {s} under {v} ({VARIANTS[v]['says']}) has a fair run in which Bob never buys"
                    if c is None or c.verdict == "unknown":
                        self.check("control", name, None, c.detail if c else "no cell", "liveness")
                        continue
                    ok = c.verdict == "violated" and sound(c)
                    fx = next(f for f in self.fixtures if self.stem(f["fixture"]) == s)
                    self.check("control", name, ok,
                               f"`eventually Bob has bought` violated; its lasso is on the graph, fair, Bob never buys on it, and it replays on the evaluator: {self.describe(c.paths[0], self.names(fx['labels']))}" if ok
                               else f"{c.verdict}: {c.detail}; a liveness verdict under {v} may be vacuous", "liveness")
        # the trap: assume the environment fair and the control holds, which is what the control is there to catch
        for (s, v) in sorted(self.graphs):
            if v != "world":
                continue
            for col in ("TLC", "NuSMV"):
                c = cells.get((s, v, "C", col))
                name = f"vacuity trap, {col}: {s} under world, the control holds (the non-vacuity check can fail)"
                if c is None or c.verdict == "unknown":
                    self.check("control", name, None, c.detail if c else "no cell", "liveness")
                    continue
                self.check("control", name, c.verdict == "holds",
                           "with Bob's purchase assumed fair, `eventually Bob has bought` holds, so non-vacuity would flag a liveness verdict here" if c.verdict == "holds"
                           else f"{c.verdict}: the trap did not spring, so the non-vacuity check is not shown to be able to fail", "liveness")
        # the harness's own fairness check can fail: a lasso that pauses forever with Alice able to move, found where
        # nothing is fair, must be judged unfair under alice's fairness (else the lassos it passes prove nothing)
        for (s, v) in sorted(self.graphs):
            if v != "none" or (s, "alice") not in self.graphs:
                continue
            ga = self.graphs[(s, "alice")]
            p5 = next(p for p in self.props if p["id"] == "P5")
            fair = self.fair_labels(ga)
            for col in ("TLC", "NuSMV"):
                c = cells.get((s, "none", "P5", col))
                if c is None or c.verdict != "violated" or not c.paths:
                    continue
                verdicts = [self.witnesses(ga, p5, path, fair) for path in c.paths]
                ok = all(any("not fair" in w for w in ws) for ws in verdicts)
                fx = next(f for f in self.fixtures if self.stem(f["fixture"]) == s)
                self.check("control", f"fairness check, {col}: {s}'s P5 lasso found where nothing is fair is unfair under alice", ok,
                           f"{self.describe(c.paths[0], self.names(fx['labels']))}: " + "; ".join(w for ws in verdicts for w in ws if "not fair" in w) if ok
                           else "the harness judged it fair, so a lasso it passes may not be fair")
        # the mutants: each fails the property it was written to fail, and no other of P1 to P4
        for s, target in (("d3-cancel", "P4"), ("d3-double", "P2")):
            if (s, "alice") not in self.graphs:
                continue
            for col in ("in-process", "TLC", "NuSMV"):
                vs = {pid: verdict(s, "alice", pid, col) for pid in ("P1", "P2", "P3", "P4")}
                name = f"mutant {s}, {col}: fails {target} and no other of P1 to P4"
                if "unknown" in vs.values():
                    self.check("control", name, None, f"{col} not installed")
                    continue
                ok = vs[target] == "violated" and all(x == "holds" for k, x in vs.items() if k != target)
                self.check("control", name, ok, ", ".join(f"{k} {x}" for k, x in vs.items()))

    # -- 9. report ---------------------------------------------------------------

    def matrix(self) -> list[str]:
        out = []
        cols = ("in-process", "TLC", "NuSMV")
        by = {(c.fixture, c.variant, c.prop, c.column): c.verdict for c in self.cells}
        for v in VARIANTS:
            rows = sorted({(s, pid) for (s, vv, pid, _) in by if vv == v}, key=lambda r: ([self.stem(f["fixture"]) for f in self.fixtures].index(r[0]), [p["id"] for p in self.props].index(r[1])))
            if not rows:
                continue
            out.append(f"Verdicts under {v}: {VARIANTS[v]['says']}")
            out.append(f"  {'fixture':<11} {'property':<9} {'expected':<10} " + " ".join(f"{c:<11}" for c in cols))
            for s, pid in rows:
                exp = self.expected.get((s, v, pid), {}).get("verdict", "-")
                kind = next(p["kind"] for p in self.props if p["id"] == pid)
                out.append(f"  {s:<11} {pid + ' ' + kind[:5]:<9} {exp:<10} " + " ".join(f"{by.get((s, v, pid, c), '-'):<11}" for c in cols))
            out.append("")
        return out

    def counterexamples(self) -> list[str]:
        """The positive control and one non-vacuity lasso per design, as #TRACEs (spec 5.4)."""
        out = []
        for c in self.cells:
            if not c.paths:
                continue
            if not ((c.fixture, c.variant, c.prop) == ("d1-naive", "alice", "P1") or (c.prop == "C" and c.variant == "alice" and c.column == "NuSMV")):
                continue
            g = self.graphs[(c.fixture, c.variant)]
            fx = next(f for f in self.fixtures if self.stem(f["fixture"]) == c.fixture)
            names = self.names(fx["labels"])
            path = c.paths[0]
            stem = path.steps if path.loop is None else path.steps[:path.loop]
            what = "Sequence A, the positive control" if c.prop == "P1" else "a fair run in which Bob never buys (non-vacuity)"
            out.append(f"-- {c.fixture}, {c.prop} {'counterexample' if path.loop is None else 'lasso'} from {c.column}: {what}")
            out.append(f"#TRACE {g.contract} AT {g.at} WITH")
            out += [f"    {l} AT {g.at}" for _, l, _ in stem]
            if path.loop is not None:
                out.append(f"-- and then, forever: {', '.join(short(l, names) for _, l, _ in path.steps[path.loop:])}")
            out.append("")
        return out

    def report(self) -> int:
        lines = []
        lines.append("Tools:")
        for t in (self.l4, self.mcrl2, self.tlc, self.nusmv):
            lines.append(f"  {t.name:<6} {'present' if t.present else 'ABSENT '}  {t.version + '  ' if t.version else ''}{t.found}")
        lines.append("")
        for c in self.checks:
            tag = {"pass": "PASS   ", "fail": "FAIL   ", "unknown": "UNKNOWN"}[c.status]
            detail = c.detail.replace("\n", "\n            ")
            lines.append(f"{tag} [{c.group}] {c.name}: {detail}")
        lines.append("")
        lines += self.matrix()
        lines += self.counterexamples()
        fails = [c for c in self.checks if c.status == "fail"]
        unknowns = [c for c in self.checks if c.status == "unknown"]
        gating = [c for c in unknowns if c.gate in ("liveness", "bisim")]
        absent = [t.name for t in (self.mcrl2, self.tlc, self.nusmv) if not t.present]
        counts = f"{len(self.checks)} checks: {len(self.checks) - len(fails) - len(unknowns)} pass, {len(fails)} fail, {len(unknowns)} unknown"
        if fails:
            banner, code = f"EXPLORE HARNESS VERDICT: FAIL. {counts}.", 1
        elif unknowns:
            gate = (f" The release gate FAILS: {len(gating)} unknown liveness or bisimulation checks." if self.args.release
                    else " Not a pass: run with every tool installed, and with RELEASE=1 for the release gate.")
            banner = f"EXPLORE HARNESS VERDICT: INCOMPLETE. {counts}; not installed: {', '.join(absent) or 'none'}.{gate}"
            code = 1 if (self.args.release and gating) else 0
        else:
            banner, code = f"EXPLORE HARNESS VERDICT: PASS. {counts}; every column of every cell answered and agreed.", 0
        lines.append(banner)
        text = "\n".join(lines) + "\n"
        sys.stdout.write(text)
        (self.out / "report.txt").write_text(text)
        (self.out / "cells.tsv").write_text("fixture\tvariant\tproperty\tcolumn\tverdict\tdetail\n" + "".join(
            f"{c.fixture}\t{c.variant}\t{c.prop}\t{c.column}\t{c.verdict}\t{c.detail}\n" for c in self.cells))
        for t in (self.mcrl2, self.tlc, self.nusmv):
            if not t.present:
                print(f"UNKNOWN  {t.name}: {t.found}. Every cell it would answer is unknown, never holds.", file=sys.stderr)
        print(f"Work directory: {self.out}", file=sys.stderr)
        return code

    # -- main -----------------------------------------------------------------

    def main(self) -> int:
        self.l4 = find_l4(self.args.l4)
        self.mcrl2 = find_mcrl2()
        self.tlc = find_tlc()
        self.nusmv = find_nusmv()
        if not self.l4.present:
            print(f"BROKEN  {self.l4.found}", file=sys.stderr)
            print("EXPLORE HARNESS VERDICT: FAIL. l4 is the thing under test, and there is none that can explore.")
            return 1
        for t in (self.mcrl2, self.tlc, self.nusmv):
            if not t.present:
                print(f"UNKNOWN  {t.name}: {t.found}", file=sys.stderr)
        for t in (self.mcrl2, self.tlc, self.nusmv):
            if t.broken:
                self.check("tool", f"{t.name} as configured", False, f"{t.found}: a tool named explicitly and unusable is a defect, not an absence")
        self.explore_all()
        self.models()
        self.provenance()
        self.bisimulation()
        self.inprocess_all()
        self.tlc_all()
        self.nusmv_all()
        self.judge_paths()
        self.replay_all()
        self.judge_cells()
        self.controls()
        return self.report()


def workdir(given: Optional[str]) -> Path:
    base = Path(given or os.environ.get("EXPLORE_HARNESS_OUT") or Path(tempfile.gettempdir()) / "l4-explore-harness").resolve()
    if base.exists() and any(base.iterdir()) and not (base / MARKER).exists():
        raise SystemExit(f"BROKEN  {base} is not empty and was not made by this harness; give another with OUT=")
    if base.exists():
        shutil.rmtree(base)
    base.mkdir(parents=True)
    (base / MARKER).write_text("made by jl4/examples/explore/harness/harness.py; cleared at the start of every run\n")
    return base


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", help="the work directory (default: $EXPLORE_HARNESS_OUT, else l4-explore-harness in the system temp directory)")
    ap.add_argument("--l4", default=os.environ.get("L4"), help="the l4 binary (default: $L4, else this tree's cabal build, else l4 on PATH)")
    ap.add_argument("--release", action="store_true", default=os.environ.get("RELEASE") == "1",
                    help="the release gate: an unknown liveness or bisimulation check fails the run")
    ap.add_argument("--jobs", type=int, default=int(os.environ.get("JOBS", "4")), help="tool runs at a time (default 4)")
    args = ap.parse_args()
    args.out = workdir(args.out)
    return Harness(args).main()


if __name__ == "__main__":
    sys.exit(main())
