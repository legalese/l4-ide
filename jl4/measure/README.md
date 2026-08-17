# `m3-measure` — the M3 gate measurement

`M3Measure.hs` builds the executable `m3-measure`. It answers one question with a
table: **over a fixed corpus, does information-gain question ordering ask fewer
questions than L4 declaration order?** The docassemble backend spec gates
milestone M3 on that being measured rather than assumed, so the measurement is
committed and re-runnable rather than run once and quoted.

Read the module haddock in `M3Measure.hs` before the numbers. It states the unit,
the shared stopping rule, and what the two sampling arms mean. Everything below
is operational.

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
  --exhaustive-max 12 --samples 2000 --seed 20260817 \
  --json jl4/measure/data/m3-ordering.json \
  --csv  jl4/measure/data/m3-ordering.csv
```

That corpus is the one the measurement was scoped to and it was fixed before any
number existed. Adding files to it is a *new*, separately labelled run, not an
extension of this one.

Takes about 90 seconds. The run is deterministic: 247 of the 250 ladder-accepted
decisions are enumerated exhaustively over all `2^k` worlds, and the 3 that are
not are sampled from `--seed` with the xorshift64\* written out in
`M3Measure.hs`, so the same seed reproduces the same worlds anywhere.

## Results, and how to read the table

- `data/m3-ordering.csv` — one row per decision in the corpus, refusals
  included. Refused rows carry the refusal reason verbatim and nothing else.
- `data/m3-ordering.json` — the same, plus the per-atom labels, the input
  refs, the priors, the worst cases, and (with `--traces`) per-world ask
  sequences.

Column notes that are easy to get wrong:

| column | means |
| --- | --- |
| `atomClasses` | **the unit.** Ladder atoms after atomId coalescing — identical to `l4 verify`'s `atomClasses`. NOT the number of questions a user sees. |
| `declAtomsMean_*` / `planAtomsMean_*` | mean questions to a settled **verdict** (`BDQ.verdictOf`), not to a settled truth value. |
| `*_uniform` vs `*_prior` | the world DISTRIBUTION, not the ranker's inputs — the ranker always gets the L4-declared priors. With no priors in the corpus the two arms are the same distribution. |
| `declRefsMean_*` | distinct input refs the ladder recorded. A coarser handle, **not** a question count: the ladder's ref map is measurably incomplete (see the haddock). |
| `declLazyOnlyMean_uniform` | declaration order with the shared verdict pre-check switched off. Where it exceeds `declAtomsMean_uniform`, the BDD saw determinism the lazy evaluator could not; the decision's `anomalies` column says so. |
| `atomWinFrac` / `atomTieFrac` / `atomLossFrac` | probability mass of worlds, not decisions. A decision can tie on the mean and still lose on some worlds. |

## Guard 2: is the declaration-order baseline the real emitted behaviour?

`etc/m3-baseline-check.py` is the falsification attempt, and the measurement is
not trustworthy without it. It re-emits every interview, drives it in a real
`docassemble.base` through the shipped `roundtrip_check.py`, and checks two
things per world: that an independent lazy evaluator predicts the real ask
sequence exactly, and that `m3-measure`'s `decl` trace is that same walk at atom
granularity.

```bash
python3 etc/m3-baseline-check.py \
  --repo $PWD \
  --l4 ./dist-newstyle/.../l4 \
  --measure ./dist-newstyle/.../m3-measure \
  --python <a python with docassemble.base installed> \
  --out jl4/measure/data/guard2-baseline.json
```

It exits non-zero on any mismatch. `data/guard2-baseline.json` holds the last
run, including the measured atom-to-field expansion factor — which is what makes
the unit gap a number rather than a caveat.

## What is deliberately NOT here

No recommendation, and no edit to the spec's rulings. This directory produces the
number; whether M3 gets built is a separate decision recorded in the spec that
owns it.
