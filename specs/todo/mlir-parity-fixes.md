# jl4-mlir parity & correctness fixes

Tracking doc for the action items surfaced by the adversarial review
(`jl4-mlir/MLIR-REVIEW.md`, branch `mlir-review`). We're tackling these directly
rather than via GitHub issues.

**Status legend:** ⬜ todo · 🔄 in progress (background agent) · ✅ done · ⏸ deferred (needs decision)

Working branch for fixes: `mlir-review` (warm cabal cache). File ownership is
partitioned so the quick-win agents never edit the same file concurrently:
Haskell → QW1, JS runtime → QW2, docs → QW3.

---

## Quick wins (DONE — uncommitted on `mlir-review`)

Combined verification on the merged working tree: `cabal build jl4-mlir` clean
under `-Wall -Werror -Wunused-packages`; **22/22 Haskell tests pass**; all 3 JS
suites pass (jl4-runtime 40, rational 138, wasm-backend 6). 8 files changed,
+381 lines. (End-to-end `.l4 → .wasm` execution NOT exercised — LLVM toolchain
absent; tests assert on emitted MLIR text / schema flags / JS runtime functions.)

### QW1 — Fail-loud the silent wrong-answer paths in lowering ✅

Files: `Lower.hs`, `ABI.hs` (comment), `test/Main.hs`.

- ✅ **String-literal CONSIDER patterns** (Lower.hs:2246-2258) — now emit a real
  `__l4_str_eq` compare instead of `trueI1`.
- ✅ **`PatExpr` patterns** (Lower.hs:2289-2291) — `unsupportedMatch` →
  `supported:false`.
- ✅ **Unresolved enum tags** (Lower.hs:2220/2231/2237) — `unsupportedMatch` when
  the tag can't be resolved; new `unsupportedMatch`/`falseI1` helpers
  (Lower.hs:2299-2316) keep the `scf.if` condition well-typed.
- ✅ **Final WHEN branch now tested** (Lower.hs:2128) — removed the special case
  that ran a trailing single `WHEN` body unconditionally (a bare `OTHERWISE`
  still runs unconditionally, which is correct).
- ✅ **Same-arity overload collisions** — detected during lowering via a new
  `emittedBodies` LowerState field (`lowerDecide` ~1101-1126); a genuine
  collision flags the export `supported:false`. (Note: the `daydate.l4`
  four-`Date@1` repro is masked as a _dependency_ import by
  `registerDependencyModule`'s dedup, so the regression test uses three
  same-name overloads in the main module.)
- ✅ **ABI.hs doc comment** (ABI.hs:30) — corrected to the rational-pool-handle
  reality.
- ✅ Regression tests: `testStringPatternStrEq`, `testPatExprUnsupported`,
  `testOverloadCollisionUnsupported`.

### QW2 — Stop the silent deontic FULFILLED on the trace path ✅

Files: `runtime/jl4-runtime.mjs`, `runtime/jl4-runtime.test.mjs`.

- ✅ **Null-contract guard** — added on the trace path
  (`invokeFunctionWithReasoning`, :3115-3122) AND at the shared chokepoint
  (`runDeonticInternal`, :531-541); value path was already guarded. Missing
  contract now throws `DeonticInputError` instead of returning FULFILLED.
- ✅ **MUSTNOT refused loudly** (jl4-runtime.mjs:561-579) — modal is cleanly
  visible (`Schema.hs modalToText` emits `MUST|MAY|MUSTNOT`); a reached MUSTNOT
  node now throws "unsupported", covering both paths. Provably can't fire on the
  MUST/MAY sale/seatbelt/breach fixtures. (Correct prohibition semantics + the
  `DO≡MUST` collapse remain tracked below.)
- ✅ node regression test (+7 assertions; 33 → 40).

### QW3 — Reconcile stale / contradictory documentation ✅

Files: `README.md`, `FEATURE-PARITY-PLAN.md`, `SOLIDITY-BACKEND-PLAN.md`.

- ✅ README "Known gaps": strings de-stubbed (real `__l4_str_*` impls listed,
  genuine UTF-16/`SPLIT` gaps noted); deontic clarified as JS-runtime-over-
  schema-tree (not compiled wasm); state-graphs + traces marked existing, with
  `SimpleResponse` still the default envelope.
- ✅ FEATURE-PARITY-PLAN M4 slice 2b → DONE.
- ✅ SOLIDITY-BACKEND-PLAN: "56/56" → "20/20" with a cross-reference.

---

## Substantive items (tracked, not auto-fixed — need our hands / a decision)

### Correctness

- ⏸ **Deontic semantics, full fix** — MUSTNOT/prohibition (correct, not just
  refuse), `DO`≡`MUST` collapse, regulative `AND`/`OR` unsupported. Decision:
  port from jl4-core `Machine.hs` vs. refuse-and-route-to-fallback. NOTE: the
  two _silent-wrong_ lossy-extraction hazards here are now **closed
  fail-closed** (not yet computed correctly, but no longer wrong) — see the
  `deontonToContract` fix under Ledger #8 below: a `PROVIDED` guard and a
  non-literal deadline each now make extraction return `Nothing` →
  `supported:false` → jl4-service fallback, instead of shipping a
  guard-ignoring / NaN-deadline answer at `supported:true`.
- ✅ **Ledger #8 — `ceo-performance-award` deontic export: honest, loud refusal.**
  Investigated `Eligible Service Requirement`: it refuses for two real reasons — (1)
  call-graph propagation from helper `Musk In Eligible Service` (enum-`EQUALS` on a
  record projection the lowering can't type; ledger-#6 family), and (2)
  `extractDeonticContract` returns `Nothing` because `exprToGuard` can't represent an
  IF guard that is a **helper-call application** (`Forfeiture Applies award state`) and
  `deontonToContract` **drops the action's `PROVIDED` guard** (the very hazard above).
  Because interpreting it would risk a silent wrong answer, it MUST keep refusing
  (Outcome B). Fix (`Schema.hs`): `mkFunctionExport` now marks any
  `isDeontic && deonticContract == Nothing` export `supported:false` with a clear
  DEONTIC-extraction reason, and `applyDiagnostics` PRESERVES (prepends) that reason
  instead of overwriting it — closing the latent `supported:true`+null-contract landmine
  that would have surfaced only at evaluate time if gap (1) were fixed alone. Regression
  test `deontic unextractable contract → supported:false` (Haskell 33→34). The 3 deontic
  fixtures still extract non-null contracts / stay supported. Harness (`--port 9931`) over
  ceo + sale/seatbelt/breach: **8 byte-identical, 1 refused-unsupported, PARITY OK**.
  Branch-crossing curated cases (all 3 top-level branches) validated live against
  jl4-service and parked in `ceo-performance-award.cases.json.pending` (NOT a live
  `.cases.json` — a curated cell for a refusing fn would trip the harness
  partial-corpus-collapse guard). Note the full future fix also needs a jl4-service
  events-codegen fix: `CodeGen.hs:431` can't encode a sum-type-with-fields action
  (`maintain eligible service status <Service Status>`), so fielded-action
  fulfilled/breach sequences aren't expressible even against the reference today.
  - ✅ **Follow-up (lossy-extraction hardening) — `deontonToContract` now
    fail-closes on the two silent-wrong hazards an adversarial pass found reachable
    by natural adjacent inputs (the original Ledger #8 guard keyed on
    _total_ extraction failure, so these lossy-but-non-null cases slipped through
    at `supported:true`).** `deontonToContract :: Deonton -> Maybe DeonticContract`
    now returns `Nothing` when (a) `action.provided` is present — the runtime never
    evaluates the PROVIDED guard, so keeping it would answer as if the guard were
    always true; (b) the deadline is not a numeric literal — `dcDeadline` is only a
    pretty-printed string and the JS runtime does `Number(deadline)`, so any
    computed/aliased deadline (e.g. `WITHIN \`Deadline Days\``) becomes **NaN**,
making every `at > deadline` test false so nothing ever lapses (FULFILLED where
the reference says BREACH); or (c) a present HENCE/LEST continuation is itself
unextractable (`traverse`instead of`>>=`, so a branch we cannot represent
refuses rather than silently vanishes). Each routes through the existing
`deonticExtractionFailed`guard →`supported:false`. Regression tests: `deontic
    PROVIDED guard`, `deontic computed deadline`, `deontic literal deadline`
    (positive control) — Haskell 34→37. Shipped corpus unchanged (8 byte-identical
    - 1 refused, parityFails 0); the two adversarial probes
      (`jl4-mlir/coverage-report/provided-probe.l4`, `jl4-mlir/coverage-report/deadline-probe.l4`) that
      previously shipped `supported:true` silent-wrongs now both refuse.
- ✅ **`lowerCmp` InfoMap-miss fallback** — DONE (commit `65c94608`). Root cause
  was deeper than the review: `tcdInfoMap` isn't run through the typechecker's
  final substitution, so `typeOfExpr` returns `Just (InfVar …)` (not `Nothing`)
  and `isStringExpr` (no `bindingL4Types` fallback) let **STRING `==` on params
  lower to a bare `arith.cmpf` on pointers** — silently wrong for equal-content
  strings interned at different addresses. New `classifyOperand` dispatches
  NUMBER→`__l4_rat_cmp`, STRING `==`/`!=`→`__l4_str_eq`; ordered-STRING (no
  runtime builtin) and genuinely-unresolvable both fail loud (`supported:false`);
  BOOLEAN/enum/DATE keep `arith.cmpf`. 4 regression tests; 26/26 pass.
  Residual is now DONE — see "Bundle-wide L4 type map" below: helper-result
  comparisons classify via the callee's checked type from `EntityInfo`.
- ✅ **Same-arity overload collision → wrong-overload dispatch** — DONE. The
  arity-only mangle (`dedupAndSynthExterns`) gave two overloads sharing a name
  AND arity but differing in argument type (e.g. `daydate`'s `Weekday of`/`Day`
  on NUMBER vs DATE) the **same** WASM symbol, so one body won the dedup and both
  call sites bound to it — nondeterministic mis-dispatch (it's why `is-a-weekday`
  crashed: `Weekday of d` hit the NUMBER body `days MOD 7` on a raw-serial date).
  **Fix** (`Lower.hs`): the typechecker already gives each overload a distinct
  `getUnique`, and a reference shares its definition's unique, so
  `computeOverloadSymbols` precomputes a per-group-indexed symbol (`name__ovN`)
  for every same-arity overload set and `symbolFor` applies it consistently at
  the definition, every call site, and the dep-dedup/`funcSigs` keys. Groups with
  an `@export` member are left alone (an exported same-arity collision is
  API-ambiguous → still `markUnsupported`, preserving the existing test). Verified:
  `Weekday of`/`Day`/`days-between`/`shift-date` now byte-identical; Haskell
  26/26 (the exported-collision test still flags `supported:false`); full corpus
  130 byte-identical / 2 differs (factorial), **no regressions**, the
  `is-a-weekday` crash class eliminated.
  - **Residual (2) is now DONE — see "Call-graph diagnostic propagation" below.**
    `is-a-weekday` correctly **refused** (`supported:false`) instead of
    silently answering. **Residual (1) is now also DONE — see "Bundle-wide L4
    type map" below**: `is weekend` compiles _natively_ and `is-a-weekday` is
    3/3 byte-identical.
- ✅ **Call-graph diagnostic propagation → an unsupported HELPER no longer ships a
  silent wrong answer through its exported caller** — DONE. `markUnsupported` keys
  a diagnostic on the **enclosing** function, but `Schema.applyDiagnostics` only
  downgrades entries in `bundleExports`. A helper is not an export, so its
  diagnostic was silently **dropped**: the exported caller stayed `supported:true`
  and ran a WASM module that cannot evaluate it, surfacing the helper's fail-closed
  `0.0`/FALSE as a **wrong answer** rather than a refusal.
  **Fix** (`Lower.hs`): `callL4`/`callL4Direct` — the two choke points for an L4→L4
  `func.call` — record a `callGraph` edge from `currentFunction` to the callee;
  `propagateDiagnostics` then lifts every diagnostic to all transitive callers
  (BFS over the reversed graph, so recursion/mutual recursion terminate). The
  inherited reason names the culprit (`depends on 'X', which the WASM backend
cannot compile: …`) so the refusal stays diagnosable.
  **This immediately exposed two real silent-wrong bugs** (below) that the backend
  had _already detected_ and then thrown away.
- ✅ **Lambda-lifted local helpers collided by (name, arity) → catastrophic
  wrong-body dispatch in the PRELUDE** — DONE, and the most severe bug found so
  far. Local helper names are scoped in L4 but **flat** once lambda-lifted to a
  top-level `func.func`. `prelude` defines **ten** separate recursive helpers named
  `go` (inside `sum`, `product`, `count`, `reverse`, `dictSize`, `dictDelete`,
  `groupPairs`, `foldl`, `foldr`, …). Every arity-2 `go` sanitized to the bare
  symbol `go` and the arity-only mangle collapsed them into **one body** — `count`'s
  won. Measured on the pre-fix build:

  | call              | expected |    WASM (before) |
  | ----------------- | -------: | ---------------: |
  | `sum [2,3,4]`     |      `9` | `3` (the LENGTH) |
  | `product [2,3,4]` |     `24` | `4` (length + 1) |

  `supported: true` throughout — a silent wrong answer from the standard library.
  **Fix** (`Lower.hs`): `localSymbolFor` gives each lifted helper its own numbered
  symbol (`go__loc0`, `go__loc1`, …), memoized on its `Unique` so the untraced pass,
  the `$trace` clone, and every call site (which reaches it via `symbolFor`) agree.
  Also **`emittedBodies` now records WHICH `Unique` claimed a symbol**: a lifted
  helper legitimately reaches `lowerDecide` twice (untraced + `$trace`), and keying
  on the symbol alone reported that benign re-emission as an "overload collision"
  against itself — a false positive that propagation would have turned into
  spurious refusals.
  Guarded by `jl4-mlir/test/fixtures/list-probe.{l4,cases.json}` **in the CI Tier-2
  corpus** (12/12 byte-identical; **7/12 differ on the pre-fix build**). Note
  `sum [1,1,1] == 3 == count [1,1,1]` is byte-identical even when broken — the cases
  deliberately use branch-separating values, or trivial-input masking hides it again.

- ✅ **Ordered STRING comparison → `britishcitizen5` now compiles natively**
  (ledger #7). `britishcitizen5` holds dates as STRINGs (`"1983-01-01"`) and
  defines `` `after` d c IF d GREATER THAN c ``. Formerly there was no
  string-ordering builtin, so `after` was `markUnsupported` and (via
  propagation) the export refused — a safe-but-degraded route to the fallback.
  **Fix, three parts:**
  1. **Runtime** `__l4_str_cmp` (`jl4-runtime.mjs`) — returns `-1/0/1`,
     lexicographic by Unicode **code point** (`codePointAt` iteration, NOT
     JS-native `<`, which orders UTF-16 code **units** and disagrees for
     astral-plane chars). Declared in `Runtime/Builtins.hs`.
  2. **Lowering** `lowerCmp`'s `CmpString` ordered arm routes through
     `__l4_str_cmp` and re-applies the predicate against `0.0` (mirrors
     `CmpNumber`/`__l4_rat_cmp`).
  3. **Two latent bugs this exposed** (masked while the export refused):
     (a) jl4-core's `typeToParameter` schema'd `DECLARE Date IS A STRING` as
     `format:date` (primitive **name** match precedes the declares table), so
     `marshalArg` parsed inputs to DATE serials — fixed WASM-side by
     `Schema.unfoldSynonymType`, which resolves `SynonymDecl` params to their
     underlying type before `typeToParameter`, so `Date` → `{"type":"string"}`.
     (b) the lowering **erases** synonyms, so `classifyOperand` mis-read a
     `Place`/`Date` operand as `CmpOther` → raw `arith.cmpf` on string pointers
     (`"Gibraltar" == "Gibraltar"` → FALSE) — fixed by a `typeSynonyms` map on
     `LowerState` that `classifyOperand` unfolds through (`Place` → STRING →
     `CmpString` → `__l4_str_eq`).
  4. **Embedded-NUL hardening** (str-ordering lane follow-up). Making ordered
     STRING `supported:true` newly reached a latent hole: a STRING input may
     legitimately contain `U+0000`, but the wire ABI stores strings
     NUL-terminated, so `readCString`'s NUL-scan truncated `"a\0b"` to `"a"` —
     `str_cmp`/`str_eq` then compared truncated prefixes while jl4-service
     (`Data.Text`) keeps the whole string (silent wrong answer at
     `supported:true`, the cardinal sin — and pre-existing for `str_eq`).
     Fixed WASM-side: `writeString` records each string's exact byte length in
     a per-eval `strLenByPtr` side table and `readCString` reads exactly that
     many bytes, embedded NULs included (marshalled inputs + every computed
     string route through `writeString`, so all are covered). Compiler-emitted
     string globals have no side-table entry and keep the NUL-scan, so a source
     `StringLit`/`PatLit` containing `U+0000` is instead **refused** at lowering
     (`markUnsupported`/`unsupportedMatch` → fallback). Guarded by
     `str-nul-probe.{l4,cases.json}` (branch-crossing embedded-NUL cells across
     `strGt/strGe/strLt/strLe/strEq`) and JS runtime `embedded NUL` unit tests.
     The **reference was pinned empirically**: jl4-service returns
     `"banana" > "apple" = true` for a `DECLARE Date IS A STRING` param — string
     comparison, ignoring `format:date`. Genuine builtin DATE is not a
     `SynonymDecl`, so it keeps serial marshalling (datetime-probe unaffected).
     Guarded by `britishcitizen5.cases.json` (5 branch-crossing cells: before /
     **exactly on** / after each date threshold; UK and Gibraltar paths),
     `str-ordering-probe.{l4,cases.json}` (the unicode trap), Haskell
     `STRING ordered < → __l4_str_cmp`, and JS `__l4_str_cmp` unit tests.
- ✅ **Untyped scalar param → silent wrong answers** — DONE (was the last open
  🔴). `desc.l4`'s `factorial x` has no `GIVEN x IS A NUMBER`; jl4-core infers
  NUMBER, but the jl4-mlir **schema emitter defaulted the param to
  `{"type":"object"}`** — so the WASM backend returned **`1` for all inputs**
  (`factorial(5)` → WASM `1` vs jl4-service `120`), at `supported: true`, never
  routing to fallback. Mechanism, fully traced: `marshalArg` on `"object"` routes
  a JSON number through `marshalStruct`, which returns pointer `0` for a schema
  with no `properties`; `0.0` read as a rational-pool handle aliases the interned
  literal `0`, so `x EQUALS 0` was TRUE for every input — deterministically
  wrong, not garbage. **Fix** (`L4.Export.enrichParamTypes`, called from
  `Schema.bundleExports`): the parameter-side sibling of `enrichReturnTypes` —
  fill each unannotated param from the function's inferred `Fun` type via
  positional zip against the leading given/head params (ASSUME-appended params
  keep their own signatures; `InfVar`-containing types are left untyped rather
  than emitted wrong). Verified: schema says `{"type":"number"}`;
  `factorial 5/6/10 = 120/720/3628800`; the formerly-xfail
  `jl4/examples/ok/desc.cases.json` is **4/4 byte-identical** and `desc.l4` is
  now in the **CI Tier-2 corpus**; Haskell regression test
  `bare-head param typed from EntityInfo` (30/30); jl4-core golden suite 46/46.
  **With this, the full extended corpus gates `PARITY OK`: 130/130 byte-identical,
  0 differs, 0 wasm-error, 6 honest refusals.**
  - **Scope (measured 2026-06-17):** this is **narrow**, not the tip of an
    iceberg. A follow-up hunt added branch-crossing `cases.json` for the rest of
    the exportable corpus and the value core held up everywhere: `test.l4`
    **30/30** byte-identical (tax brackets, loan amortisation, ticket pricing,
    enums, `MAYBE`, recursion); `intrinsics-probe` **25/25** including the
    _irrational_ `SQRT 2`/`LN 2`/`LN 0.5` and unicode `STRINGLENGTH`;
    `assume-as-given` + `implicit-assume-test` **18/18** (ASSUME / implicit-ASSUME
    params bind correctly — schema-typed `number`/`boolean`, not `object`). So
    `factorial` is specifically the **bare-head positional param** path
    (`DECIDE foo x IS` with no `GIVEN`), the lone instance of that style in the
    corpus.
- ✅ **DATE-typed operand in arithmetic → WASM crash** — DONE. Functions that
  fed a `DATE`/`TIME` value to `MINUS`/`PLUS` crashed the WASM backend with
  `TypeError: Cannot read properties of undefined (reading 'num')` while
  jl4-service answered correctly (`days-between` svc `365`, WASM crash;
  `shift-date`; all `supported: true`). Root cause was an **ABI split**: DATE
  values are **raw f64 day-serials** throughout the date intrinsics
  (`__l4_date_serial`/`_day`/`_month` do `Number(d)`; `make-date` returns a raw
  serial; runtime comment `jl4-runtime.mjs:2262`) and `marshalArg` hands a date
  param over as that raw serial (`:2417`), but `Lower.hs` lowered `MINUS`/`PLUS`
  on _any_ operand — including dates — to the generic **rational** ops
  `__l4_rat_sub`/`__l4_rat_add`, which `ratUnbox` their args
  (`ratPool.get(serial)` → `undefined` → `.num`). **Previously masked** as
  harmless `both-error`: the auto-generated input for a `{format:date}` param is
  `"x"`, which jl4-service _also_ rejects, so both sides errored — valid ISO
  dates unmasked it. **Fix** (`Lower.hs` `lowerRatBinop`): detect DATE/TIME
  operands (via the same `typeOfExpr`/`bindingL4Types` ladder as
  `classifyOperand`; new `isDateType`/`isTimeType` + `operandDateTimeKind`) and
  box serial→handle (`__l4_date_serial`/`__l4_time_serial`) before the rat op;
  for an _additive_ op with exactly one dated operand the result is itself a
  DATE/TIME, so unbox handle→serial (`__l4_date_from_serial`); `date − date`
  (both dated) is a day-count and stays a NUMBER handle. Comparison was already
  correct (DATE → `CmpOther` → `arith.cmpf` on the raw serial). `date MODULO n`
  directly is a jl4-core **type error**, so that path is unreachable via valid
  L4. Verified byte-identical: `days-between`, `shift-date`, `(DATE_SERIAL d)
MOD 7`, `(Day d) MOD 7`; full corpus 124 → **130 byte-identical, no
  regressions**; Haskell 26/26, runtime 184 + 2 xfail all green.
  `datetime-probe.l4` + its `cases.json` added to the **CI Tier-2 corpus** to
  guard the fix.
  - **Residual (separate bug): `is-a-weekday` still `wasm-error`.** Isolation
    probes show `(DATE_SERIAL d) MOD 7` and `(Day d) MOD 7` are byte-identical
    but `` `Weekday of` d `` crashes — i.e. daydate's `Weekday of` has same-arity
    `NUMBER` and `DATE` overloads that **collide** in jl4-mlir (the
    same-arity-overload issue from `MLIR-REVIEW.md`); the wrong (NUMBER) body
    runs on a raw-serial date. This is the overload-collision domain, not the
    date ABI — tracked under "Correctness" above. It is _not_ in
    `datetime-probe.cases.json` (auto-generates to a harmless `both-error`), so
    it doesn't gate CI, but it remains a silent-ish gap until same-arity
    overloads are mangled by argument type.
- ✅ **Bundle-wide L4 type map → helper-result comparisons classify** — DONE
  (commit `62f5f909`, clears PARITY-HUNT-LOG ledger #6). `funcSigs` records only
  MLIR types (all f64 under the uniform ABI), so `lowerCmp` refused any
  comparison whose operand was a helper's CALL RESULT — which kept daydate's
  `is weekend` (and the exported `is-a-weekday`) on the fallback. **Fix**
  (`Lower.hs` + threading in `Pipeline.hs`): project the typechecker's
  SUBSTITUTED `EntityInfo` (which unions dependencies) to
  `funcL4Types :: Map Unique (Type' Resolved)`; `classifyOperand` resolves any
  `App` operand via the callee's checked type — `resultTypeAtArity` (saturated
  `Fun` → return; partial application refuses) then `classifyGroundType`, which
  trusts ONLY builtin scalar heads (NUMBER/STRING/BOOLEAN/DATE/TIME). The closed
  set is load-bearing: an entity's recorded type is the definition's _generic_
  type, and a type-variable return slot is syntactically a nullary `TyApp` —
  trusting it as a raw-f64 comparison key would silently compare rational-pool
  handles (`LIST OF a -> a` at NUMBER). Haskell 33/33 (old unresolvable-cmp
  fixture became the positive `testHelperResultStringEq`; its replacement pins
  the tyvar guard); `is-a-weekday` 3/3 byte-identical on branch-crossing
  Mon/Sat/Sun cases added to `datetime-probe.cases.json`; Tier-2 65+1 → 68+0;
  extended corpus 130+6 → **133 byte-identical, 5 refused, 0 differs**.
  Residual (tracked): enum/record helper results still refuse — widening needs a
  reliable tyvar-vs-nullary-constructor discriminator.
- ✅ **CONSIDER over EITHER (`RIGHT`/`LEFT`) → resolved** — DONE (branch
  `mlir-fix/either-consider`, PARITY-HUNT-LOG ledger #10). `EITHER a b` is a
  payload-CARRYING builtin ADT (prelude `x IS AN EITHER a b`; `LEFT`/`RIGHT` are
  `Constructor` entities analogous to `JUST`), not a nullary `DECLARE ... IS ONE
OF` enum — so `testPatternTy` had no enum tag for the constructor and refused
  ("CONSIDER pattern constructor RIGHT could not be resolved to an enum tag").
  `orchestrator.l4`'s four helpers (`isViolation`, `getConfidence`, `getAllTests`,
  `extractText`) each raised it, and `propagateDiagnostics` lifted all 18
  copies into the exported `evaluateClaim`'s refusal chain. **Fix** (`Lower.hs`):
  represent `EITHER` exactly like `MAYBE` — a 2-slot `[tag, payload]` linear-memory
  record, `LEFT` tagged `0.0` and `RIGHT` `1.0` (mirroring `NOTHING`/`JUST`) — and
  handle `LEFT`/`RIGHT` at the three CONSIDER choke points: **construction**
  (`lowerExpr` App intrinsics, alloc-2 + store tag/payload, cloned from `JUST`);
  **tag test** (`testPatternTy` arity-1 `PatApp`: `RIGHT` = tag truthy like `JUST`,
  `LEFT` = tag falsy like `NOTHING`); **payload bind** (`bindPatternTy`: slot 1 for
  both). The arity-1 string dispatch is sound because a user-declared `LEFT`/`RIGHT`
  constructor is caught earlier by `lookupRecordFields`/`lookupEnumTag`; only the
  builtin reaches these arms. `EXACTLY` (`PatExpr`) patterns are untouched and still
  refuse. Verified: `either-probe.{l4,cases.json}` **15/15 byte-identical** on
  branch-crossing LEFT/RIGHT cases (NUMBER/STRING/BOOLEAN/LIST payloads distinct from
  the 0/1 tag, plus a nested CONSIDER mirroring `extractText`), added to **CI Tier-2**;
  Haskell `EITHER CONSIDER → supported dispatch` (34/34); `orchestrator::evaluateClaim`
  STILL refuses but now **only** for the legitimate IO reason (`depends on
'callClaudeWithKey' … POST (IO)`) — the `RIGHT`/`LEFT` enum-tag diagnostics are
  gone (before: 18 present; after: 0). Tier-2 68 → **83 byte-identical, 0 differs,
  0 wasm-error**.
  - ⚠️ **Post-refutation hardening.** The "caught earlier by `lookupRecordFields`/
    `lookupEnumTag`" soundness claim above was FALSE for `testPatternTy`/
    `bindPatternTy`: that lookup-first ordering existed only in the CONSTRUCTION
    path. A user `DECLARE Rev IS ONE OF RIGHT HAS rv …; LEFT HAS lv …`
    destructured in a CONSIDER hit the builtin string cases first → read the
    user's bare-tag value through EITHER's `[tag, payload]` slot layout →
    **silent wrong at `supported:true`** (`rev-dispatch(5)`: service `1005`,
    WASM `-995`). Fixed: `isUserConstructor` now gives user records/enums
    priority over the builtin JUST/NOTHING/LEFT/RIGHT/EMPTY cases in BOTH
    `testPatternTy` and `bindPatternTy`; and since construction lowers an
    enum-with-data / record constructor to a bare tag (no payload slot),
    destructuring an arity ≥ 1 user constructor now **REFUSES** (`supported:
false`) rather than compute a garbage/trapping payload bind. Nullary user
    enums are untouched. Full corpus still **104 byte-identical, 0 differs**.
    Guard: Haskell `user LEFT/RIGHT enum → supported:false` + committed
    `either-shadow{,2}.l4` (kept out of the gated corpus — they refuse fully).
  - ⚠️→✅ **Sibling silent-wrong: enum-with-data ABI RETURN.** Surfaced by the
    same shadow hunt (`either-ret.l4`): an `@export` `GIVETH A Rev` (returning a
    `ONE OF … HAS …` value) shipped `supported:true` but returned the bare tag
    `0` while jl4-service returns `{"RIGHT":{"rv":5}}` — payload silently lost.
    Pre-existing (construction `lookupEnumTag` arm dates to `13dd5419`, NOT
    ledger #10) and name-agnostic (a Foo/Bar control reproduces it). The first
    fix (`8ab7b531`, syntactic-GIVETH `dataEnums`/`isDataEnum` guard in
    `lowerDecide`) was **REFUTED as too narrow**: it missed enum-with-data
    nested in a record field, inside `MAYBE`/`LIST OF`, and inferred returns
    with no `GIVETH` — four reachable `supported:true` silent-wrongs.
    **Corrected fail-closed at the right altitude** (`buildExport`, `Schema.hs`):
    a non-deontic `@export` whose Forall/Fun-peeled `exportReturnType` yields
    `typeToRetSchema = Nothing` (which already covers enum-with-data and any
    record/list/optional transitively containing one) ships `supported:false`
    with `unmarshallableReturnReason`. Keys on the ENRICHED return type, so all
    four probes refuse. Old `dataEnums`/`givethTypeName`/`dataEnumReturnReason`
    machinery removed (subsumed). Nullary-enum, scalar-record, and
    list-of-scalar returns still produce a schema and stay byte-identical
    (verified). Guards: four Haskell tests (enum-with-data + record-of / MAYBE /
    inferred variants, `cabal test jl4-mlir` = **39/39**) and fixtures
    `either-ret{,-record,-maybe,-inferred}.l4` (all refuse). Fixtures parity =
    **122 byte-identical, 7 refused, 0 differs, 0 wasm-error — PARITY OK**.
- ⬜ **Fractional decimal input fidelity** — both host paths round fractional
  NUMBER inputs through IEEE Double before the exact-rational core
  (Marshal.hs:85; wasm-server.mjs:239). Preserve decimal text into
  `__l4_rat_parse`.
- ⬜ **`Schema.freeVarsOfExpr` vs `Lower.freeVarsOfExpr` drift** (Schema.hs:660
  vs Lower.hs:2531-2536) — they disagree on the App head; "kept verbatim so
  they agree" comment is now false. Re-unify (shared helper) before a
  non-filtered helper trips it.
- ✅ **Ledger #12 — code-point semantics for the index-carrying string builtins**
  (commit `198a1a38`). `__l4_string_length` / `__l4_index_of` / `__l4_char_at` /
  `__l4_substring` used JS-native ops (UTF-16 code **units**) where jl4-service
  is `Data.Text` (Unicode code **points**): any astral char (≥ U+10000) silently
  diverged at `supported:true` — `STRINGLENGTH "😀"` = 2 vs 1, unit-offset
  `INDEXOF`, `CHARAT` returning half a surrogate pair. `SUBSTRING` additionally
  read arg 3 as an END INDEX (JS semantics) instead of a LENGTH
  (`Text.take len . Text.drop start`) — wrong for any `start > 0` even on ASCII
  (`SUBSTRING "hello" 1 3` → `"el"` vs `"ell"`). All four now convert through
  code points with the reference's clamping (negative start → 0, `len <= 0` →
  `""`, oob `CHARAT` → `""`). Guards: `coverage-report/str-index-probe.{l4,cases.json}`
  (26/26 byte-identical live) + intrinsic-level JS unit tests (suite 89/89).
  Post-fix boards: Tier-2 97+0; extended sweep **227 byte-identical, 0 differs,
  0 wasm-error, 5 honest refusals**.
- ⬜ **Out-of-lane asymmetry inventory** (found by lane hunters; none is a
  silent wrong at `supported:true` — triaged, not chased):
  - **Lone surrogate in input JSON** — service 400s; WASM's UTF-8 encoder
    substitutes U+FFFD and answers. Loud-vs-lossy input validation gap. Fix
    direction: reject unpaired surrogates at marshalling (400-equivalent).
  - **Fractional NUMBER as string index** — reference floors; WASM `numToInt`
    throws loudly (fail-loud, never wrong). Decide: floor to match, or keep
    loud.
  - **Empty-needle `REPLACE`** — `Data.Text.replace` errors (service 5xx); JS
    `split/join` intersperses the replacement. Divergent error shape only;
    align by erroring on an empty needle if it ever matters.
  - **Invalid-enum event party (deontic)** — service 422s an event whose party
    fails enum validation; the WASM deontic interpreter accepts it and can
    fabricate a residual OBLIGATION. The one remaining fabricate-vs-refuse gap
    in the deontic path; fix = validate event parties against the declared
    enum before interpreting.
  - **`trace=full` NUL rendering** — trace envelopes differ on embedded NUL;
    the trace sub-matrix is not a gate (JS trace pool is a one-node stub).
  - **§-section first-export drop** — the first `@export` in a `§`-sectioned
    file is emitted as a helper. Probes work around it with a sacrificial
    leading export; root-cause it in the frontend section walker someday.
  - **Scalar-name-colliding user types** — a user `DECLARE` colliding with a
    scalar builtin name confuses schema typing (pre-existing, also
    service-side; ledger-#7's `unfoldSynonymType` fixed only the SynonymDecl
    slice of this).

### Verification (the meta-fix)

- ✅ **Differential parity in CI — gate hardened + wired** (adversarial workflow
  `ci-parity-gate`: survey → design → implement → 4-lens red-team (13 findings,
  6 blocker/major) → harden). Landed:
  - **`scripts/parity-gate.mjs`** (NEW, pure / side-effect-free) — `canonical`,
    `extractValue`, `ulpEqual` moved verbatim; `classifyOutcome` is a faithful
    extraction of the old inline `:337-350` ladder (no behaviour change); the
    hardened `gateVerdict(tally, {comparisonsRun, …})` is now the single source
    of truth. Fails on `differs`/`wasm-error` (preserved) **plus** the
    previously-silent `service-error`/`compile-fail`/`deploy-fail`, **plus** a
    **zero-comparison guard** so a vacuous run (empty/broken corpus, all
    refused/skip/both-error, every file dropped to compile/deploy-fail) can never
    print `PARITY OK`. Red-team hardening: non-finite `comparisonsRun` (NaN/Inf)
    can't disable the guard; `minComparisons` is clamped to a floor of 1; the
    harness counter is cross-checked against the tally and the gate fails on the
    smaller — _a harness bug can only make the gate stricter, never looser._
  - **`scripts/parity-harness.mjs`** — imports the pure module (inline copies
    deleted); broken default corpus (`../jl4-auth-proxy/validation/test.l4`) →
    in-repo 4-fixture manifest; **fail-loud `fs.existsSync` precheck** (missing
    input `exit(2)`, not a silent compile-fail); per-file **partial-corpus-collapse
    guard** (a curated `*.cases.json` cell that yields zero real comparisons fails
    with `corpus-collapse` — the per-file teeth `gateVerdict`'s aggregate floor
    lacks); writes `verdict` into `parity.json`/`parity.txt`; `exit(verdict.pass?0:1)`.
  - **`scripts/parity-gate.test.mjs`** (NEW, bare-node, no toolchain) — **93/93
    pass** (independently re-run). Covers all 7 `classifyOutcome` outcomes +
    boundaries, the moved helpers, the M4 ulp-must-not-gate invariant, and every
    false-negative trap incl. the NaN/Inf and `minComparisons`-floor regression
    locks. **This is the sole machine-verified anchor** in this environment.
  - **`.github/workflows/pr-checks.yml`** — `mlir: jl4-mlir/**` (+ the workflow
    file itself) added to the `changes` filter; **Tier 1** `jl4-mlir-parity-gate-unit`
    (always-on, pure node: runs the gate test, the other jl4-mlir `*.test.mjs`,
    and a corpus-fixtures-exist-and-non-empty check); **Tier 2**
    `jl4-mlir-parity-full` (LLVM/MLIR 19 + GHC 9.10.2, runs the harness on the
    explicit corpus, appends `parity.txt` to the step summary, uploads
    `parity-report` via `upload-artifact@v4`).
  - **End-to-end verified locally** (LLVM 22.1.7 — Homebrew `llvm` + `lld` —
    against a live jl4-service): `parity-harness.mjs` on the 4-fixture corpus →
    **20/20 byte-identical, `PARITY OK`, exit 0** (zero `differs`/`wasm-error`;
    trace=full sub-matrix is the known M5-slice-1 backlog, non-gating). The
    hardened verdict prints/exits correctly and the zero-comparison guard does
    not false-trip. The CI Tier-2 job is pinned to **LLVM 22** to match this
    proven toolchain (README + FEATURE-PARITY-PLAN both endorse 22). It still
    ships **`continue-on-error: true`** (advisory) until it's green on the
    _ubuntu_ runner a few times — the apt package resolution
    (`mlir-22-tools` etc.) and the ubuntu LLVM-22 IR surface are the only
    remaining unknowns — _then flip to `false` to make it required_. Residuals:
    on-disk fixtures have no required _compile_ coverage in the Haskell suite
    (Main.hs builds equivalent L4 inline, never reads the files);
    `allowCompileFail`/`allowDeployFail` stay aggregate-opaque (harness must
    subtract reviewed ids before building the tally).
- ⬜ **Flip Tier 2 to required** (`continue-on-error: false`) once the toolchain
  job is green a few times; add a `Main.hs` case that reads each fixture `.l4`
  from disk (with prelude-import/VFS wiring) so the corpus has required compile
  coverage.
- ⬜ **Expand the corpus** beyond the 12-fn fixture at single trivial inputs:
  non-degenerate `.cases.json` hitting TRUE branches, the ~35 clean exportable
  files, property/fuzz tests for the deontic state machine vs. jl4-core.
- ⬜ **Tests that execute wasm** — all 19 Haskell tests are `isInfixOf` string
  checks; none compiles/runs a module. (Needs the toolchain in CI — Tier 2.)

### Tests (TDD red→green)

Bold doc claims that are currently false are encoded as **expected-fail** tests
that go red now (falsifying the "DONE" claim) and green when realized:

- ✅ **`xfail` harness** in `runtime/jl4-runtime.test.mjs` — pending failures are
  logged + tallied but don't break the suite; a passing xfail prints `XPASS`
  (the nudge to promote it to a real `eq` assertion).
- 🔴 **MUSTNOT → BREACH** (prohibited act before deadline) and **MUSTNOT
  respected → FULFILLED** — encode jl4-core `Machine.hs:983/1038`; red today
  (QW2 refuses MUSTNOT). Promote + delete the "MUSTNOT refused" guard test once
  real prohibition lands.
- ⬜ **(deferred to post-lowerCmp, Haskell `test/Main.hs`)** xfail for
  `Schema.freeVarsOfExpr` vs `Lower.freeVarsOfExpr` agreement on an App-head
  case; xfail that a PROVIDED guard survives into the extracted
  `deonticContract`. Needs a `pending` facility added to the Haskell runner.
  (Held back to avoid colliding with the in-flight lowerCmp agent.)

### Hygiene / scope

- ⬜ **String-op fidelity** — code-point vs UTF-16 in length/substring/indexOf;
  `TOSTRING`/`JSON_ENCODE` formatting for small fractions & big ints; add
  missing `SPLIT`.
- ⬜ **CLI/runtime gaps** — DEONTIC unrunnable via CLI (`startTime`/`events`
  never forwarded, Main.hs:356-361); `--wasmtime`/`--wasmer` are stubs;
  `supported:false` functions run anyway with no fallback routing; `-k` no-op;
  `bundleVersion` hardcoded `"0.1.0"`.
- ⬜ **Delete/quarantine dead code** — `BoxKind` (ABI.hs), `Dialect/CF.hs`,
  `Dialect/MemRef.hs`, `scf.while`, unused `LLVM.hs` struct builders,
  `--finalize-memref-to-llvm` pass — advertises an abandoned architecture.
  Also 9 unused locals in `runtime/jl4-runtime.mjs` (trace-synthesis code:
  `residualContract`/`residualDeadline`/`givenParams`/`contractBodyText` ~1424-1511,
  `value`/`explicitBreach` ~1910, `node` ~3509, `EMPTY_REASONING` ~3953) flagged
  by the TS checker — pre-existing, not from the QW changes.
- ⏸ **Solidity/EVM backend** — plan-only, zero implementation. Don't let it
  inherit the WASM backend's unverified parity credibility.
