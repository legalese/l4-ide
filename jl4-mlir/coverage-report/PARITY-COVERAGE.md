# Drop-in-replacement parity coverage

**The question this answers:** can the MLIR/WASM backend stand in for jl4-service
— i.e. does it return jl4-service's _answer_, not merely produce wasm? That is a
different (and stronger) question than the compile-coverage sweep in
[`FINDINGS.md`](./FINDINGS.md), which only checks that a file _lowers cleanly_
(`supported: true`). Compile-coverage is necessary but **not** sufficient: a
function can lower cleanly and still compute the wrong value.

Measured with `scripts/parity-harness.mjs` (LLVM 22.1.7 — Homebrew `llvm` +
`lld` — against a live jl4-service): compile each `.l4` to wasm, deploy the same
source to jl4-service, evaluate the same args on both, diff the responses.
jl4-service is the reference.

## Corpus & matrix

The 36 `clean` + 2 `has-unsupported` exportable files from the compile-sweep
(38 files). All 38 compiled and deployed — zero `compile-fail`, zero
`deploy-fail`.

| Outcome               | Cells | Meaning                                                        |
| --------------------- | ----: | -------------------------------------------------------------- |
| `byte-identical`      |    76 | WASM response == jl4-service, byte-for-byte (across 33 files)  |
| `differs`             |     2 | **real divergence** — `desc::factorial` (see below)            |
| `both-error`          |     3 | both sides reject the (degenerate) input, consistently         |
| `refused-unsupported` |     2 | backend correctly flags `supported:false` → routes to fallback |
| `skip-no-cases`       |     1 | deontic fn; needs a curated `cases.json` with events to test   |

**76 of 78 real comparisons (97.4%) are byte-identical.** The only divergence is
the single `factorial` bug. The non-comparison rows are all _correct_ behaviour:
`both-error` is consistent rejection (the trivial date inputs are invalid on both
sides), `refused-unsupported` is the backend honestly deferring (the overload
collision + unresolved-enum cases from the compile-sweep), and `skip-no-cases` is
an untested-not-failed deontic function.

## Headline finding: untyped scalar param → silent wrong answers 🔴

`desc.l4`'s `factorial x` has **no `GIVEN x IS A NUMBER`**. jl4-core infers
NUMBER, but the jl4-mlir schema emitter defaults the param to
`{"type":"object"}` and the scalar is never bound as a number, so the WASM
backend returns **`1` for every input**:

| input | jl4-service | WASM |               |
| ----: | ----------: | ---: | ------------- |
|   `0` |         `1` |  `1` | ✓ (base case) |
|   `1` |         `1` |  `1` | ✓ (coincides) |
|   `5` |       `120` |  `1` | ✗             |
|   `6` |       `720` |  `1` | ✗             |

This is **silent**: `factorial` is flagged `supported: true` (one of the 36
"clean" files), so it does not route to fallback — it just returns wrong
answers. The base cases (`0`,`1`) coincidentally return `1` and hid it; the
auto-generated trivial/`null` input hid it entirely. This is precisely the class
of bug differential parity exists to catch, and precisely why compile-coverage
overstates readiness. Tracked in `specs/todo/mlir-parity-fixes.md`; regression
case in `jl4/examples/ok/desc.cases.json` (xfail-style — currently `differs`,
flips to byte-identical when fixed).

## Curated cases added (`cases.json`)

To move beyond one trivial input per function, three high-value files got
branch-exercising cases, all **verified byte-identical** except the factorial bug:

- `doc/tutorials/deploying-rules/insurance-premium.cases.json` — all 3
  `calculate-premium` branches (risk>0.7 / existing-customer / else) + the
  `qualifies-for-discount` boundary (`risk = 0.5`). **6/6 byte-identical.**
- `jl4/experiments/query-planner-tests/04-alcohol-purchase.cases.json` — a
  6-way spread over the boolean tree (21+/under-21, married, beer-only,
  parental/spousal/emancipated), hitting both TRUE and FALSE. **6/6 byte-identical.**
- `jl4/examples/ok/desc.cases.json` — factorial at `0,1,5,6` (the regression case
  above). **2/4 differ — the bug.**

## Harness fix: no more spurious `service-error`

`genArgs` used to emit `null` for a param it couldn't synthesize (an untyped /
shapeless `object` param). jl4-service correctly 422s on `null`, which the
harness misread as a `service-error` "divergence". `genValue`/`genArgs` now
signal un-synthesizable params and the function is **skipped (`skip-no-cases`)**
— the same treatment as deontic functions — so a missing input is reported as
"needs a `cases.json`", never as a fake divergence.

## What this number does NOT yet cover

1. **Branch depth.** Outside the 3 curated files, each function is still
   exercised at a single generated input. A high byte-identity rate at one input
   is necessary, not sufficient — the `factorial` bug is the proof. The real
   metric is byte-identity × input-space coverage; expanding `cases.json` across
   the corpus is the ongoing work.
2. **Deontic.** Regulative functions need event `cases.json` to be parity-tested
   at all; `ceo-performance-award` is `clean` in the compile-sweep but its
   drop-in status is currently _unknown_, not _confirmed_.
3. **Whole-repo.** Only the exportable corpus is in scope; `no-exports` files
   (course material, fragments) are not evaluable.

## Reproduce

```sh
export PATH="/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH"
node jl4-mlir/scripts/parity-harness.mjs --out /tmp/parity \
  $(python3 -c "import json;print(' '.join(r['file'] for r in json.load(open('jl4-mlir/coverage-report/coverage.json'))['perFile'] if r['outcome'] in ('clean','has-unsupported')))")
```

(The gate _fails_ on this extended corpus — by design: it caught the `factorial`
divergence. The committed CI gate runs the 4-fixture default corpus, which is
green.)
