# Drop-in-replacement parity coverage

**The question this answers:** can the MLIR/WASM backend stand in for jl4-service
— i.e. does it return jl4-service's _answer_, not merely produce wasm? That is a
different (and stronger) question than the compile-coverage sweep in
[`FINDINGS.md`](./FINDINGS.md), which only checks that a file _lowers cleanly_
(`supported: true`). Compile-coverage is necessary but **not** sufficient: a
function can lower cleanly and still compute the wrong value — or crash.

Measured with `scripts/parity-harness.mjs` (LLVM 22.1.7 — Homebrew `llvm` +
`lld` — against a live jl4-service): compile each `.l4` to wasm, deploy the same
source to jl4-service, evaluate the same args on both, diff the responses.
jl4-service is the reference.

## Corpus & matrix

The 36 `clean` + 2 `has-unsupported` exportable files from the compile-sweep
(38 files), now with branch-crossing curated `cases.json` across the
arithmetic-heavy files (see below). All 38 compiled and deployed — zero
`compile-fail`, zero `deploy-fail`.

| Outcome               | Cells | Meaning                                                        |
| --------------------- | ----: | -------------------------------------------------------------- |
| `byte-identical`      |   124 | WASM response == jl4-service, byte-for-byte (across 33 files)  |
| `differs`             |     2 | **silent wrong answer** — `desc::factorial` (see below)        |
| `wasm-error`          |     9 | **WASM crash, svc OK** — DATE-param arithmetic (see below)     |
| `refused-unsupported` |     2 | backend correctly flags `supported:false` → routes to fallback |
| `skip-no-cases`       |     1 | deontic fn (`ceo-performance-award`); needs event `cases.json` |

**124 of 126 real comparisons (98.4%) are byte-identical.** "Real comparisons"
counts only cells where both backends produced a value (`byte-identical` +
`differs`); the 9 `wasm-error` cells are a separate failure mode (WASM threw,
jl4-service answered) and the 2 `refused`/1 `skip` are correct/untested-not-failed.

The curated cases nearly doubled real branch coverage (76 → 124) over the first
pass — and in doing so surfaced a **second** bug class beyond the `factorial`
finding.

## Finding 1: untyped scalar param → silent wrong answers 🔴

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

**Silent** (`supported: true`, never routes to fallback). The base cases
coincidentally return `1` and the trivial generated input hid it entirely. This
is the textbook bug differential parity exists to catch, and why compile-coverage
overstates readiness. Tracked in `specs/todo/mlir-parity-fixes.md`; regression
case in `jl4/examples/ok/desc.cases.json` (xfail-style — currently `differs`).

**Scope is narrow.** This is the **only** instance: it is specifically the
_bare-head positional param_ style (`DECIDE foo x IS` with no `GIVEN`), the lone
example in the corpus. The follow-up hunt confirmed the rest of the value core is
solid (see "Curated cases" below).

## Finding 2: DATE-typed parameter in arithmetic → WASM crash 🔴

Functions that take a `DATE` parameter and feed it to `MINUS`/`PLUS`/comparison
crash on the WASM backend while jl4-service answers correctly:

| function (`datetime-probe.l4`) | args                        | jl4-service | WASM      |
| ------------------------------ | --------------------------- | ----------: | --------- |
| `days-between`                 | `2024-01-01` → `2024-12-31` |       `365` | **crash** |
| `shift-date`                   | `2024-01-01` + 30           |  `2024-...` | **crash** |
| `is-a-weekday`                 | `2024-01-01`                |      `TRUE` | **crash** |

The crash is `TypeError: Cannot read properties of undefined (reading 'num')`.
Root cause is an **ABI split**: DATE values are raw f64 day-serials throughout
the date intrinsics and `marshalArg` hands a date param over as that raw serial,
but `Lower.hs` lowers `MINUS`/`PLUS` on _any_ operands (including dates) to the
generic _rational_ ops (`__l4_rat_sub`), which `ratUnbox` their args
(`ratPool.get(serial)` → `undefined` → `.num`). All three functions ship
`supported: true`.

**Previously masked** as harmless `both-error`: the auto-generated input for a
date-string param is the literal `"x"`, which jl4-service _also_ rejects
("expected a DATE but got x"), so both sides errored and looked consistent. Valid
ISO dates unmask it — the same trivial-input masking as `factorial`. Tracked in
the spec; regression cases in `jl4-mlir/test/fixtures/datetime-probe.cases.json`
(date _construction_ — `make-date`/`make-datetime`/`make-time` — is byte-identical;
the three DATE-_input_ functions are `wasm-error` until fixed).

## Curated cases added (`cases.json`)

To move beyond one trivial input per function, the arithmetic-heavy files got
branch-exercising cases. Except the two findings above, **everything is
byte-identical** — strong evidence the value core (exact rationals, records,
enums, `MAYBE`, recursion, intrinsics, ASSUME binding) is faithful:

- `jl4-mlir/test/fixtures/test.l4` — **30/30 byte-identical**. Progressive tax
  brackets (rates 0.10–0.37, recursive `tax across brackets`), `effective tax
rate` (division), loan amortisation (`÷12`, `÷360`, `×0.049`), ticket pricing
  (`×0.5/0.7/0.85`), enum dispatch (filing status, tier), `MAYBE STRING`/`MAYBE
NUMBER`, nested records. Mirrors the file's own `#ASSERT`ed fixtures
  (alice/bob/carol, the four loan scenarios, the ticket orders). _In the CI
  default corpus — strengthens the gate._
- `jl4-mlir/test/fixtures/intrinsics-probe.l4` — **25/25 byte-identical**,
  including the _irrational_ `SQRT 2`, `LN 2`, `LN 10`, `LN 0.5` (both backends
  share the same f64 transcendental path + number formatting) and unicode
  `STRINGLENGTH` (`"héllo"`, `"日本語"`), `REPLACE`, `TOUPPER`, `CONTAINS`,
  `IS INTEGER`.
- `jl4/examples/ok/assume-as-given.l4` + `jl4/examples/implicit-assume-test.l4` —
  **18/18 byte-identical** at threshold-crossing inputs. Confirms `ASSUME` and
  _implicit_-`ASSUME` params bind correctly (schema-typed `number`/`boolean`,
  the lowering binds the value) — they are **not** subject to the `factorial`
  bug, which is specific to bare-head params.
- `doc/tutorials/deploying-rules/insurance-premium.l4` — 6/6 (all premium
  branches + discount boundary).
- `jl4/experiments/query-planner-tests/04-alcohol-purchase.l4` — 6/6 (boolean
  tree).
- `jl4/examples/ok/desc.l4` — factorial regression (Finding 1).

## What this number does NOT yet cover

1. **Branch depth on the remaining files.** The boolean/struct predicates
   (`britishcitizen4/5`, query-planner trees, parking) outside the curated set
   are still exercised at a single generated input each. The arithmetic files —
   the highest-risk for silent divergence — are now covered.
2. **Deontic.** `ceo-performance-award` is `clean` in the compile-sweep but its
   drop-in status is still `skip-no-cases` — it needs event `cases.json`.
3. **Whole-repo.** Only the exportable corpus is in scope; `no-exports` files
   are not evaluable.

## Reproduce

```sh
export PATH="/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH"
node jl4-mlir/scripts/parity-harness.mjs --out /tmp/parity \
  $(python3 -c "import json;print(' '.join(r['file'] for r in json.load(open('jl4-mlir/coverage-report/coverage.json'))['perFile'] if r['outcome'] in ('clean','has-unsupported')))")
```

(The gate _fails_ on this extended corpus — by design: it caught the two
divergences. The committed CI gate runs `test.l4` + the 3 deontic fixtures, which
are green; `datetime-probe`/`intrinsics-probe` are manual-corpus only.)
