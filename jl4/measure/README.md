# `m3-measure` — the M3 gate measurement

`M3Measure.hs` builds the executable `m3-measure`. It answers one question with a
table: **over a fixed corpus, does information-gain question ordering ask fewer
questions than L4 declaration order — and if so, does it need to be adaptive?**
The docassemble backend spec gates milestone M3 on that being measured rather
than assumed, so the measurement is committed and re-runnable rather than run
once and quoted.

Read the module haddock in `M3Measure.hs` before the numbers. It states the unit,
the shared stopping rule, the two ladder forms, and what the sampling arms mean.
Everything below is operational.

## This is the SECOND run. What changed, and why it matters

The first run (commit `a8c9affb`) was attacked by two adversarial reviews and one
of the findings was load-bearing:

> **The declaration-order baseline walked the ladder's CNF-distributed form, not
> the shape the emitter lowers.** `LSP.L4.Viz.Ladder` runs `L4.Transform.simplify`
> = `cnf . nnf`, so `(A AND B) OR C` becomes `(A OR C) AND (B OR C)`. Under a lazy
> left-to-right walk those demand different atoms, and CNF distribution can only
> **add** demands — so the error was one-directional: it inflated the baseline and
> flattered the planner, which is exactly the bias the measurement was
> commissioned to look for. `L4.Docassemble.Lower` compiles from `L4.Syntax` and
> imports nothing from `LSP.L4.Viz.*`, so a real interview's declaration order is
> the SOURCE operand order.

So the harness now measures **both** forms side by side. The `source` arm
(`shouldSimplify = False`) is the headline; the `cnf` arm
(`shouldSimplify = True`) is what `l4 verify`, the ladder and the wizard see, kept
so the size of the distortion is a column rather than an argument.

Measured distortion: exactly two decisions move, `§ 227.503(a)(7)` and
`§ 227.503(a)(8)`, both by +0.25 questions and both winners. Headline
3.5758% → 3.3767%. **The `plan` mean is bit-identical between the two arms on all
138 decisions** — the BDD is canonical, so the planner was never affected; only
the baseline was.

Three further repairs, each from a confirmed finding:

- **A third asker, `stat`.** Reporting only `decl` vs `plan` silently assumed the
  only way to get plan order's benefit is to ship the planner. `stat` sorts each
  `AND`/`OR` node's operands ONCE at compile time by the planner's fresh-state
  info-gain ranking and then walks it lazily — a pure source-to-source rewrite of
  the emitted Python, with no BDD and no ranker in the artifact. See the results.
- **A synthetic-priors arm** (`--synthetic-priors N`). The corpus carries zero
  `TYPICALLY` priors that `collectTypicallyDefaults` can read, so the uniform and
  prior-weighted arms coincide *by construction* and the first run's guard 3 was
  not discharged — it could not say whether priors are where adaptive ordering
  earns its keep. Priors are now injected synthetically, fed to **both** the
  ranker and the world distribution (the arrangement that most flatters the
  planner), and the result reported.
- **`exported` and `subPredicate` columns.** `foldTopLevelDecides` picks up every
  top-level `DECIDE`/`MEANS`, so the 138-decision population is a **call graph**,
  not a set of interviews: 101 of the 138 are also counted as ONE atom inside
  another row. Per-decision means are therefore not composable into a
  per-interview question count, and the columns say so per row rather than
  leaving it to be discovered.

Guard 2 was rebuilt too; see below.

## Re-running it

```bash
cabal build m3-measure
JL4_LIBRARY_PATH=$PWD/jl4-core/libraries \
  ./dist-newstyle/build/*/ghc-*/jl4-0.1/x/m3-measure/build/m3-measure/m3-measure \
  jl4/examples/legal/regcf/regcf.l4 \
  jl4/examples/legal/regcf/regcf-wizard.l4 \
  jl4/examples/legal/regcf/denovo/regcf-denovo.l4 \
  jl4/examples/legal/charities-cleanroom/charity-test.l4 \
  jl4/examples/legal/bna/bna.l4 \
  jl4/examples/docassemble/*.l4 jl4/examples/docassemble/not-ok/*.l4 \
  --exhaustive-max 12 --samples 2000 --seed 20260817 --synthetic-priors 8 \
  --json jl4/measure/data/m3-ordering.json \
  --csv  jl4/measure/data/m3-ordering.csv
```

That corpus is the one the measurement was scoped to and it was fixed before any
number existed. Adding files to it is a *new*, separately labelled run, not an
extension of this one.

### Reproducing it after the tree has moved (read this before re-running)

**The committed artifacts reproduce bit-for-bit at the commit they were made at**
— verified 2026-08-18 by re-running the command above in a worktree at
`origin/unstable` (`afcef88f`): `diff -q` clean on both the CSV and the JSON.

They do **not** reproduce on a branch where the corpus has changed, and the two
globs above are why: `jl4/examples/docassemble/{,not-ok/}*.l4` expanded to 12
files when this ran and expands to 20 on the M4 branch, because M4 added six
examples and turned two refusal fixtures into supported constructs. Concretely,
`not-ok/just-payload-pattern.l4` and `not-ok/maybe-number.l4` no longer exist.

**This does not move the ruling**, and that was checked rather than assumed:
neither deleted file contributes a single row to the 138-decision eligible set
(both are refusals in the table; the only `not-ok/` file that reaches the
eligible set is `seam-ref-via-fn.l4`, two rows, both exact ties at 1.5/1.5).
No other measured file's content changed.

Two practical warnings for whoever re-runs this:

- **A glob is the wrong way to pin a corpus.** It reads as a fixed set and
  silently is not. If you re-run, pass the 17 paths explicitly — they are the
  distinct values of the `file` column in `data/m3-ordering.csv`, which is the
  authoritative record of what was actually measured.
- **The harness aborts on a missing input** with a bare
  `openFile: does not exist` and a GHC backtrace, writing no CSV and no JSON, so
  a moved corpus fails loudly but unhelpfully. It was also observed exiting the
  same way on a corpus passed in a different argument order, with the named file
  present on disk; that brittleness is not diagnosed. If you are re-running in
  anger, check out the measurement commit rather than porting the corpus forward.

Takes about three minutes. The run is deterministic: 247 of the 250
ladder-accepted decisions are enumerated exhaustively over all `2^k` worlds, and
the 3 that are not are sampled from `--seed` with the xorshift64\* written out in
`M3Measure.hs`, so the same seed reproduces the same worlds anywhere. The
synthetic prior draws are derived from the same seed.

## Results, and how to read the table

- `data/m3-ordering.csv` — one row per decision in the corpus, refusals
  included. Refused rows carry the refusal reason verbatim and nothing else.
- `data/m3-ordering.json` — the same, plus per-atom labels, input refs, priors,
  worst cases, the synthetic-prior draws, and (with `--traces`) per-world ask
  sequences. Each row carries a `source` block and a `cnf` block.

Column notes that are easy to get wrong:

| column | means |
| --- | --- |
| `atomClasses` | **the unit.** Ladder atoms after atomId coalescing — identical to `l4 verify`'s `atomClasses`. NOT the number of questions a user sees. |
| `declAtomsMean_*` / `planAtomsMean_*` / `statAtomsMean_*` | mean questions to a settled **verdict** (`BDQ.verdictOf`), not to a settled truth value. |
| unprefixed columns vs `cnf_*` | the SOURCE ladder form (what the emitter lowers) vs the CNF form (what `l4 verify` sees). Read the unprefixed ones. |
| `*_uniform` vs `*_prior` | the world DISTRIBUTION, not the ranker's inputs — the ranker always gets the L4-declared priors. With no priors in the corpus the two arms are the same distribution, which is why `--synthetic-priors` exists. |
| `declRefsMean_*` | distinct input refs the ladder recorded. A coarser handle, **not** a question count: the ladder's ref map is measurably incomplete (see the haddock). |
| `declLazyOnlyMean_uniform` | declaration order with the shared verdict pre-check switched off. Where it exceeds `declAtomsMean_uniform`, the BDD saw determinism the lazy evaluator could not; the decision's `anomalies` column says so. |
| `atomWinFrac` / `atomTieFrac` / `atomLossFrac` | probability mass of worlds, not decisions. A decision can tie on the mean and still lose on some worlds. |
| `planBeatsStatFrac_uniform` | world mass on which the ADAPTIVE asker beats the compile-time reorder. This is the only column that measures what M3 buys over the cheap alternative. |
| `exported` / `subPredicate` | population shape. `subPredicate` = this decision's name occurs inside another measured decision's atom label, i.e. it is also charged as ONE atom somewhere else. |

## Guard 2: is the declaration-order baseline the real emitted behaviour?

`etc/m3-baseline-check.py` is the falsification attempt, and the measurement is
not trustworthy without it. It re-emits each interview, drives it in a real
`docassemble.base` through the shipped `roundtrip_check.py`, and checks two things
per world: that an independent lazy evaluator predicts the real ask sequence
exactly, and that `m3-measure`'s `decl` trace is that same walk at atom
granularity.

```bash
python3 etc/m3-baseline-check.py \
  --repo $PWD \
  --l4 ./dist-newstyle/.../l4 \
  --measure ./dist-newstyle/.../m3-measure \
  --python <a python with docassemble.base installed> \
  --out jl4/measure/data/guard2-baseline.json
```

It exits non-zero on any mismatch, **and on a case list that covers no decision
the planner wins on** — because the first version of this guard covered five
interviews, every one of them a decision where the two askers TIE, so a baseline
error could not have changed a verdict, and the CNF bug above walked straight
through it. The case list now carries:

- `etc/m3-probes/distribution-probe.l4`, the exact shape that broke
  (`((A AND C) OR B) AND D`), where the CNF form costs 3.125 and the emitted
  interview really costs 2.875; and
- `regcf-denovo-intermediary`, a **real winner** (2.25 → 1.75) driven in real
  docassemble, isolated by commenting out its module's other `@export`s in a
  derived copy — the corpus file itself is never edited.

Two more repairs: atoms are identified between driver and harness by normalised
LABEL rather than by position, and the choice is **audited** — every bijection
between the two atom lists is tried and `bijectionsPassing` reports how many
survive all worlds (1 means the data pins the correspondence, so the choice
cannot have been load-bearing). And world enumeration now ranges over the fields
**reachable from the driver**, not every field in the YAML, which is what makes
isolating one export out of a 43-question module tractable.

`data/guard2-baseline.json` holds the last run, including the measured
atom-to-field expansion factor. Read the **per-case** ratio, not the pooled one:
the pooled figure is dominated by whichever case enumerates the most worlds and
is a property of the case list rather than of the emitter.

## What is deliberately NOT here

No recommendation, and no edit to the spec's rulings. This directory produces the
number; whether M3 gets built is a separate decision recorded in the spec that
owns it.
