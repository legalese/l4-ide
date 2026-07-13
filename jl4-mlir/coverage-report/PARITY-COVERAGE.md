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
| `byte-identical`      |   130 | WASM response == jl4-service, byte-for-byte                    |
| `differs`             |     0 | (was 2 — `factorial` fixed by `enrichParamTypes`)              |
| `wasm-error`          |     0 | (was 3 — the `is-a-weekday` crash class is gone)               |
| `refused-unsupported` |     6 | backend correctly flags `supported:false` → routes to fallback |
| `skip-no-cases`       |     0 | (was 1 — `ceo-performance-award` now refuses instead)          |

**130 of 130 real comparisons (100%) are byte-identical — the extended-corpus gate
passes (`PARITY OK`) for the first time.** Zero silent divergences, zero WASM
crashes; the 6 `refused` cells are correct behaviour (the backend declines and
routes to the fallback), not failures. The claim is bounded by the corpus and its
curated cases — "no known divergences" is the honest phrasing, and the
trivial-input-masking section of `../PARITY-HUNT-LOG.md` explains why the two
statements differ.

Movement across the campaign's last two steps:

- `differs` **2 → 0** — `factorial` fixed by `enrichParamTypes` (Finding 1); its
  formerly-xfail `desc.cases.json` flipped to 4/4 byte-identical.
- `wasm-error` **3 → 0** — `is-a-weekday` no longer crashes (same-arity overload
  dispatch fixed); it now _refuses_, pending the helper-result return-type map.
- `refused` **2 → 6** — `is-a-weekday` (+1), `ceo-performance-award` (+1, was
  `skip-no-cases`), and `britishcitizen5::is-British-citizen` (+2, **was
  `byte-identical`**). The `britishcitizen5` move is a deliberate, correct trade:
  that function holds dates as STRINGs and compares them with `GREATER THAN` in a
  helper the backend genuinely cannot compile (no string-ordering builtin), so it
  was running on an always-FALSE comparison and was byte-identical only because
  the one generated input happened to expect FALSE. A truthful refusal beats a
  lucky right answer.

Four bug classes have now been found by differential parity in files the
compile-sweep rated `clean` — and all four are now **fixed**: `factorial`
(Finding 1), DATE-arithmetic (Finding 2), same-arity overloads, and — via
call-graph diagnostic propagation — a **prelude** wrong-body collision that made
`sum [2,3,4]` return `3` (Finding 3).

## Finding 1: untyped scalar param → silent wrong answers ✅ FIXED

`desc.l4`'s `factorial x` has **no `GIVEN x IS A NUMBER`**. jl4-core infers
NUMBER, but the jl4-mlir schema emitter defaulted the param to
`{"type":"object"}`, so the WASM backend returned **`1` for every input**:

| input | jl4-service | WASM (before) | WASM (after) |
| ----: | ----------: | ------------: | -----------: |
|   `0` |         `1` |           `1` |       ✅ `1` |
|   `1` |         `1` |           `1` |       ✅ `1` |
|   `5` |       `120` |       `1` (✗) |     ✅ `120` |
|   `6` |       `720` |       `1` (✗) |     ✅ `720` |

**Silent** (`supported: true`, never routed to fallback). The base cases
coincidentally return `1` and the trivial generated input hid it entirely. This
is the textbook bug differential parity exists to catch, and why compile-coverage
overstates readiness.

**Mechanism** (fully traced): `marshalArg` dispatches on the schema type;
`"object"` routes a JSON number through `marshalStruct`, which returns pointer
`0` for a schema with no `properties`. That `0.0`, read back as a rational-pool
_handle_, aliases the pool's interned literal `0` — so `x EQUALS 0` was TRUE for
**every** input and the recursion never ran. Deterministically wrong, not
garbage.

**Fix**: `enrichParamTypes` in `L4.Export` — the parameter-side sibling of the
existing `enrichReturnTypes` (which was already fixing the _return_ type of this
very function). A param with no annotated type gets one from the typechecker's
inferred `Fun` type via positional zip against the leading given/head params;
ASSUME-appended params keep their own signatures; types still containing an
`InfVar` are left untyped rather than baked into the schema wrong. Guarded by a
Haskell regression test and by `desc.l4` + its (formerly xfail) `desc.cases.json`
— **now in the CI Tier-2 corpus, 4/4 byte-identical**.

**Scope was narrow, as predicted.** The bare-head positional style
(`DECIDE foo x IS` with no `GIVEN`) had exactly one instance in the corpus, and
the earlier hunt had already confirmed ASSUME / implicit-ASSUME params were
unaffected.

## Finding 2: DATE-typed operand in arithmetic → WASM crash ✅ FIXED

Functions that fed a `DATE` value to `MINUS`/`PLUS` crashed the WASM backend
(`TypeError: Cannot read properties of undefined (reading 'num')`) while
jl4-service answered correctly:

| function (`datetime-probe.l4`) | args                        | jl4-service | WASM (before) | WASM (after) |
| ------------------------------ | --------------------------- | ----------: | ------------: | -----------: |
| `days-between`                 | `2024-01-01` → `2024-12-31` |       `365` |         crash |     ✅ `365` |
| `shift-date`                   | `2024-01-01` + 30           |  `2024-...` |         crash |  ✅ `2024-…` |

Root cause was an **ABI split**: DATE values are raw f64 day-serials throughout
the date intrinsics, and `marshalArg` hands a date param over as that raw serial,
but `Lower.hs` lowered `MINUS`/`PLUS` on _any_ operands (including dates) to the
generic _rational_ ops (`__l4_rat_sub`), which `ratUnbox` their args
(`ratPool.get(serial)` → `undefined` → `.num`). **Previously masked** as harmless
`both-error`: the auto-generated input for a date-string param is the literal
`"x"`, which jl4-service _also_ rejects, so both sides errored — valid ISO dates
unmasked it (same trivial-input masking as `factorial`).

**Fix** (`Lower.hs` `lowerRatBinop`): box DATE/TIME operands serial→handle
(`__l4_date_serial`) before the rational op, and unbox the result handle→serial
for additive ops that yield a date (`date + n`); `date − date` is a day-count
and stays a NUMBER. Comparison was already correct (DATE → `arith.cmpf` on the
raw serial). Verified byte-identical; full corpus 124 → 130 byte-identical, no
regressions. `datetime-probe` is now in the **CI Tier-2 corpus** to guard it.

**Residual:** `is-a-weekday` (which crashed via a _separate_ same-arity overload
collision, since fixed) now correctly **refuses** — `is weekend` compares a
helper-result NUMBER that `lowerCmp` can't classify, and that diagnostic now
reaches the export (Finding 3). Making it compile _natively_ rather than refuse
needs the bundle-wide return-type map, still open in the spec.

## Finding 3: an unsupported HELPER shipped silent wrong answers ✅ FIXED

`markUnsupported` keys a diagnostic on the **enclosing** function, but
`Schema.applyDiagnostics` only downgrades entries in `bundleExports`. A helper is
not an export — so its diagnostic was **dropped on the floor**, the exported caller
stayed `supported: true`, and the helper's fail-closed `0.0`/FALSE surfaced as a
**wrong answer** instead of a refusal. The backend had already _detected_ these
bugs and then thrown the evidence away.

Fixed in `Lower.hs`: `callL4`/`callL4Direct` record a static `callGraph`, and
`propagateDiagnostics` lifts every diagnostic to all transitive callers (BFS over
the reversed graph, so recursion terminates). Turning it on immediately exposed two
real silent-wrong bugs:

**3a — the prelude's `go` collision (severe).** Local helper names are scoped in L4
but **flat** once lambda-lifted. `prelude` defines ten separate recursive `go`
helpers (in `sum`, `product`, `count`, `reverse`, `dictSize`, `dictDelete`,
`groupPairs`, …); every arity-2 one sanitized to the bare symbol `go` and the
arity-only mangle collapsed them into **one body** — `count`'s won:

| call              | jl4-service | WASM (before) | WASM (after) |
| ----------------- | ----------: | ------------: | -----------: |
| `sum [2,3,4]`     |         `9` | `3` (LENGTH!) |       ✅ `9` |
| `product [2,3,4]` |        `24` | `4` (len + 1) |      ✅ `24` |

A silent wrong answer from the **standard library**, at `supported: true`. Fixed by
giving each lifted helper its own symbol (`go__loc0`, `go__loc1`, …), keyed on its
`Unique`. Guarded by `list-probe.{l4,cases.json}` — now **in the CI Tier-2 corpus**
(12/12 byte-identical; **7/12 differ** on the pre-fix build). Note `sum [1,1,1]` ==
`count [1,1,1]` == 3 even when broken: the cases use branch-separating values,
because trivial inputs mask this exactly like `factorial` and the DATE crash.

**3b — `britishcitizen5` ordered-STRING comparison.** It stores dates as STRINGs and
its helper `` `after` d c IF d GREATER THAN c `` has no string-ordering builtin, so
`after` was already `markUnsupported` → always FALSE. `is British citizen` shipped
`supported: true` on top of it, and was `byte-identical` only because the single
generated input happened to expect FALSE. It now refuses (the 2 cells that moved out
of `byte-identical`).

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
- `jl4-mlir/test/fixtures/datetime-probe.l4` — date construction (`make-date`/
  `make-datetime`/`make-time`) and, after the Finding 2 fix, date arithmetic
  (`days-between`, `shift-date`) are byte-identical. _In the CI Tier-2 corpus —
  guards the date-ABI fix._ (`is-a-weekday` refuses; see Finding 3.)
- `jl4-mlir/test/fixtures/list-probe.l4` — **12/12 byte-identical**, and **7/12
  differ on the pre-Finding-3 build**: prelude `sum`/`product`/`count`/`maximum`/
  `reverse` over inputs chosen so each is distinguishable from the others _and_
  from the list length. _In the CI Tier-2 corpus — guards the lifted-local-helper
  symbol collision._
- `jl4/examples/ok/assume-as-given.l4` + `jl4/examples/implicit-assume-test.l4` —
  **18/18 byte-identical** at threshold-crossing inputs. Confirms `ASSUME` and
  _implicit_-`ASSUME` params bind correctly (schema-typed `number`/`boolean`,
  the lowering binds the value) — they are **not** subject to the `factorial`
  bug, which is specific to bare-head params.
- `doc/tutorials/deploying-rules/insurance-premium.l4` — 6/6 (all premium
  branches + discount boundary).
- `jl4/experiments/query-planner-tests/04-alcohol-purchase.l4` — 6/6 (boolean
  tree).
- `jl4/examples/ok/desc.l4` — **4/4 byte-identical** after the Finding 1 fix
  (was 2/4 with `factorial 5`/`6` differing). _In the CI Tier-2 corpus — guards
  the bare-head-param enrichment._

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

(The extended-corpus gate now **passes** — 130 byte-identical, 0 differs, 6
refused, exit 0 — for the first time since the hunt began. The committed CI
Tier-2 gate runs `test.l4` + `datetime-probe` + `list-probe` + `desc.l4` + the 3
deontic fixtures — **65 byte-identical, 1 refused, exit 0**; `intrinsics-probe`
is manual-corpus only.)
