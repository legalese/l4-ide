# The cross-validation harness for `l4 explore`

`l4 explore` turns an L4 contract into an explicit transition system by running the evaluator, and writes that graph out for mCRL2, TLC and NuSMV ([REGULATIVE-LOWERING-SPEC.md](../../../../specs/proposals/REGULATIVE-LOWERING-SPEC.md) §4 to §6.1).
This harness measures what that graph is worth, on the dinner fixtures of [`../brief/`](../brief/README.md): it is work package WP4 of the spec, §6.2 and §6.3.
It answers four questions.

1. **Is the graph the probes' model?** Each emitted `.aut`, relabelled, must be strongly and branching bisimilar to its vendored reference LTS (§6.2).
2. **Do the three checkers agree?** Every property on every fixture gets a verdict from the in-process checker, from TLC and from NuSMV, and they must agree with each other and with `expected.tsv` (§6.3).
3. **Can each check go red?** D1 must violate P1 by Sequence A (the positive control), each mutant must fail its one property, and the environment eventually acting must be violated under every fairness used (non-vacuity), and must hold when the environment is assumed fair (the trap it guards).
4. **Is every counterexample real?** Every counterexample, witness and lasso, from every column, is walked on the explored graph and replayed on the evaluator, every prefix, before the run can pass.

It reads nothing outside `jl4/examples/explore/` and the tools, and nothing from the private repository the references were relabelled from: the references are vendored, with their sources and hashes, in [`../brief/reference/`](../brief/reference/PROVENANCE.md).

## Running it

```sh
make -C jl4/examples/explore/harness check OUT=<work dir>
```

| variable                | what it names                                       | if unset                                                    |
| ----------------------- | --------------------------------------------------- | ----------------------------------------------------------- |
| `L4`                    | the `l4` binary                                     | this tree's `cabal list-bin exe:l4`, else `l4` on `PATH`    |
| `MCRL2_BIN`             | the directory holding `ltscompare` and its siblings | the directory of `ltscompare` on `PATH`                     |
| `TLA2TOOLS_JAR`, `JAVA` | `tla2tools.jar`, and a Java 11 or later to run it   | TLC is absent; `JAVA_HOME`, then `java` on `PATH`, for Java |
| `NUSMV`                 | the `NuSMV` binary                                  | `NuSMV` on `PATH`                                           |
| `OUT`                   | the work directory, cleared at the start of a run   | `l4-explore-harness` in the system temporary directory      |
| `RELEASE=1`             | the release gate (below)                            | off                                                         |
| `JOBS`                  | tool runs at a time                                 | 4                                                           |

The `l4` must have `l4 explore --emit`: an `l4` installed before the explorer cannot run this, so the harness looks for this tree's build first and says which binary it used.
Finding that build runs `cabal list-bin`, which is a `cabal` in this tree; while another `cabal` builds here, set `L4` instead (two at once corrupt each other, l4-ide's `CLAUDE.md` §2.1).
Everything the run writes, emitted models, logs, TLC's state directories and Java's temporary files among them, goes to the work directory; it writes nothing into the tree.
It needs Python 3.9 or later and nothing outside the standard library.

The last line of the output is the verdict, and the full report is `report.txt` in the work directory, with every cell in `cells.tsv`:

- `EXPLORE HARNESS VERDICT: PASS.` Every check passed with every tool installed. Exit 0.
- `EXPLORE HARNESS VERDICT: FAIL.` Some check failed, or a tool named by its variable is not usable. Exit 1 (`make` reports it as 2).
- `EXPLORE HARNESS VERDICT: INCOMPLETE.` Nothing failed, but a tool is not installed, so its cells are `unknown`. Exit 0, unless `RELEASE=1`.

**A tool that is not installed makes its cells unknown, never holds**, and the run says so on stderr at the start and at the end.
**With `RELEASE=1` an unknown liveness or bisimulation check fails the run**, which is the release gate of §6.3: a liveness verdict is quoted only when TLC and NuSMV agree on it, and mCRL2 is the one oracle that does not come from the evaluator.
In practice every one of the three tools gates the release, since without TLC or NuSMV some liveness cell is unknown.
A tool named by its variable that is not there, or is not what it says, is a failure and not an absence: `NUSMV=/no/such/file` fails the run.

## What it checks

On 2026-10-26, with the `l4` built from this branch, mCRL2 202607.0, TLC 2.19 on Java 21 and NuSMV 2.7.0, the run made 287 checks and passed all of them, in 40 to 50 seconds with `JOBS=4`, under Python 3.9 and 3.14.

**Exploration.**
Each fixture of `fixtures.tsv` is explored once per fairness variant it names, with the seven properties of `properties.tsv`, `--json` and `--emit`.
The exploration must be complete (frontier exhausted, nothing refused, nothing untried), every state must be labelled with every decision, and the graph explored under each variant must be the same graph, since fairness changes the emitted models and nothing else.

**The oracle.**
Each vendored reference and its relabelled mCRL2 source must have the SHA-256 that `PROVENANCE.md` pins, and `mcrl22lps` then `lps2lts` must rebuild the reference byte for byte from its source.

**The bisimulation (§6.2).**
The emitted `.aut` must be the graph of the JSON, edge for edge.
Its labels are rewritten by `labels.tsv`, the act table of the fixtures' README; a label with no row, or two acts sent to one reference label, fails the run, because an unmapped label passed through or a merge could make two different graphs bisimilar.
Then `ltscompare -ebisim` and `ltscompare -ebranching-bisim` against the reference must print `true`, and the counts must match: 12/21, 15/30, 10/21.
Two controls show the comparison can answer no: the same graph less its first edge out of the outset is not bisimilar to its reference (distinguishing formula `!(<step(BobBuys)>true)`), and D1's graph is not bisimilar to D3's reference (`<step(CheckBought)><step(Buy)>true`, which the harness prints back as a `#TRACE` of D1).
Where a comparison that should hold does not, the distinguishing formula is printed, and, when it is a chain of acts, as a `#TRACE` that runs.
`mutants/d3-double.l4` is also bisimilar to D3's reference, which is expected: its mutation is in a ledger cell, which no label shows, and the property checks are what catch it.

**The emitted models.**
The TLA+ and the NuSMV model must each have exactly the graph's transitions, each boolean decision must be true in the same states as the evaluator labelled, and weak fairness must be on exactly the acts of the actors named by `--fair` that move, as the harness derives them from the graph (§4.6): `Abandon`, `Buy`, `CheckBought` on D1 under `--fair Alice`, and none on Bob's purchase or the message.
TLC must load each model and find no deadlock, and NuSMV must find fair states (19 of 19 reachable on D1, for instance).

**The verdicts (§6.3).**
Under the `alice` variant, `--fair Alice`, every property is checked on every fixture; under `none` and `world` the liveness properties only.

| property                                    | D1                   | D2        | D3        | `d3-cancel` | `d3-double` |
| ------------------------------------------- | -------------------- | --------- | --------- | ----------- | ----------- |
| P1 always: every dinner accepted while open | violated: Sequence A | violated  | holds     | holds       | holds       |
| P2 always: at most one dinner               | holds                | holds     | holds     | holds       | violated    |
| P3 reachable: Alice's belief is stale       | reachable            | reachable | reachable | reachable   | reachable   |
| P4 stays: one dinner is bought              | holds                | holds     | holds     | violated    | holds       |
| P5 eventually: Alice has bought or stopped  | holds                | holds     | holds     | holds       | holds       |
| P6 eventually one dinner, if always open    | holds                | holds     | holds     | holds       | violated    |
| C eventually: Bob has bought (non-vacuity)  | violated             | violated  | violated  | violated    | violated    |

The in-process checker answers P1 to P4, and reports P5, P6 and C `unknown (liveness: run the emitted model)` by design (§5.3), which the harness shows as `n/a`, not as unknown; TLC and NuSMV answer all seven.
The three agreed on every cell, and every cell agreed with `expected.tsv`, which says where each expectation comes from: the probes' P1 to P4 table, the TLC and NuSMV verdicts recorded when the emitters were built, or first measured here (the mutants' liveness cells, the `none` variant's control, the `world` variant's P5 and P6).
P6 fails on `d3-double` because a purchase there records two dinners, so exactly one is never bought; both model checkers say so, and nothing else in this table depends on it.
Under `none`, P5 and P6 hold on D1 and fail on D2 and D3 by a run that pauses forever, as the probes found without fairness.
NuSMV's two forms of each always property (the invariant and `AG`) must agree, as must its two forms of each reachable one (`EF` and the invariant that it never happens).

**The controls.**

- The positive control: D1 violates P1, and the counterexample is Sequence A, check, Bob's purchase, buy, in all three columns (NuSMV's two forms included), each one on the graph and replayed on the evaluator.
- Non-vacuity: under `alice` and under `none`, the two fairness assumptions a liveness verdict is answered under, `eventually Bob has bought` is violated in TLC and NuSMV on every fixture, and the harness checks the lasso itself: it is on the graph, it closes, Bob never buys on it, each fair act is taken on its loop or disabled somewhere on it, and it replays on the evaluator.
  `none` is the assumption TLC's safety runs make, `WF_vars(Next)` alone, under which pausing forever is a run.
- The trap: under `world`, `--fair World`, Bob's purchase is assumed fair, and the control holds on D1, D2 and D3 in both tools; so the non-vacuity check would have caught a run with that fairness, and P6 holding there says nothing.
- The harness's own fairness check can fail: each lasso by which P5 fails under `none` (D2 and D3, in both tools) is judged unfair under `alice`'s fairness, because Alice's answered request is enabled throughout its loop and never taken.
- The mutants: `d3-cancel` fails P4 and no other of P1 to P4, and `d3-double` fails P2 and no other, in all three columns.

**The replays.**
Every path a column prints is walked on the explored graph (each step an edge; for NuSMV also a transition of its model; for a lasso, the loop must close), and checked against its property: the last state of a counterexample to an always property must be labelled false, a witness's last state true, a stays counterexample must hold a step from true to false.
For an always or reachable property the path must also be the one `expected.tsv` names.
Each column reports a shortest path, and each path `expected.tsv` names is the only shortest one in its graph (counted breadth first on the explored graphs, 2026-10-26), so every column must find the same one.
Then every prefix of every path is written as a `#TRACE` appended to a copy of the fixture, and one `l4 run` per fixture evaluates them all: the residual contract and every ledger cell the explorer keeps must be those of the graph state the path claims, and of no other state.
In these fixtures the ledger cells do all the work: the residual is the same in every state (all 12 of D1's, measured 2026-10-26), and the cells are what tell Sequence A's state, s8, from Sequence B's, s6.

## The files

| file             | what it is                                                                                         |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `Makefile`       | the one target, `check`                                                                            |
| `harness.py`     | the harness; it knows nothing of the dinner, and reads the four tables below                       |
| `fixtures.tsv`   | each fixture: its label map, its reference LTS, its clock bound, and the fairness variants it runs |
| `properties.tsv` | P1 to P6 and the control C, as the boolean decisions of `../brief/properties.l4` and their classes |
| `labels.tsv`     | per design, each act's label in the graph and the reference label it stands for                    |
| `expected.tsv`   | every cell's verdict, its shortest path where there is one, and where the expectation comes from   |

The three fairness variants are defined in `harness.py`, because each is a set of `--fair` flags and a role, not data about a fixture: `alice` answers the liveness verdicts, `none` is the control where nothing is fair, and `world` is the trap.

## What fails loudly, and what fails silently

Loud failures, which a run reports and which need no vigilance:

- A tool absent: its cells are `unknown`, on stderr twice and in the banner, and the release gate fails.
- A tool configured and unusable, or a run of it that does not finish as one of its known outcomes: a failure, never a verdict. TLC is accepted only with exit 0 and its success message, exit 12 and an invariant violation, or exit 13 and a temporal violation; anything else, such as the exit 150 below, is broken.
- An exploration that is incomplete, refused, or untried: the harness compares only complete graphs.
- An emitted model whose transitions, labelled states or fairness differ from the graph's, a label with no reference label, two acts sharing one, a cell with no row in `expected.tsv`, or a row with no cell.
- Any disagreement between columns, or with `expected.tsv`, and any path that does not replay.

Silent failures, which a green run does not rule out:

- **A wrong expectation that every column shares.** If the evaluator, the emitters and both model checkers all gave the same wrong answer, and `expected.tsv` were pinned to it, the run would be green. Only the rows marked `brief` have an oracle outside this pipeline, the probes' hand models; the rows marked `measured` have only the columns' agreement.
- **A wrong label map.** `labels.tsv` is read off the fixtures' README, by hand. A row that maps an act to the wrong reference label, but one to one, fails the bisimulation only if the graphs then differ; the bisimulation is the check on the map as much as on the graph.
- **A stale oracle edited consistently.** The hashes guard the vendored files against an edit, and the rebuild guards each `.aut` against its source, but an edit to a source, its `.aut` and `PROVENANCE.md` together passes. Neither says the source is still the probes' brief.
- **The bisimulation does not see ledgers.** It compares labelled graphs, so a fixture that writes the wrong value to a ledger but moves through the same states is bisimilar to the reference, as `d3-double` is. The properties and the replays are what read the ledgers.
- **Only these fixtures.** Every path is replayed with its events at the outset's instant, which is right here because the explorer fires every act there and no guard reads the clock; a fixture whose events fall at other instants, or whose path takes a tick, makes the replay fail rather than guess, and is not yet supported.

## Traps measured while building it

- **TLC runs in parallel must not share a temporary directory.** TLC copies `Naturals.tla` into `java.io.tmpdir`; two runs sharing one failed with exit 150 and "Cannot find source file for module Naturals" (2026-10-26). The harness gives each run its own, in the work directory, and reads exit 150 as broken, which is how it was caught.
- **NuSMV prints a model's properties by class, not in source order** (CTL, then LTL, then invariants), and names none of them. The harness runs each property by name, `check_ltlspec -P <name>` and so on, from a command file, and reads the verdicts in the order it asked.
- **NuSMV has no empty set**, so a decision true in no state is emitted as `FALSE`, and TLA+ writes one edge without the disjunction it uses for several; a reader of the models has to know both forms.
- **`ltscompare` exits 0 whether or not the LTSs are equivalent**: the answer is the `true` or `false` it prints last, which is what the harness reads.

## Not done here

- **No CI job runs this yet.** The spec's WP4 row names one; it needs mCRL2, TLC and NuSMV installed on the runner with pinned archives and SHA-256 (NuSMV is in neither Homebrew nor conda), and none of those pins has been measured for a Linux runner.
- Apalache, Spin, TAPAAL and the `.pnml` and `.dot` outputs are not checked; `refused-number.l4` is the explorer's test (WP1), not this harness's.
- The user documentation of `l4 explore`, `doc/reference/regulative/explore.md`, is WP5.
