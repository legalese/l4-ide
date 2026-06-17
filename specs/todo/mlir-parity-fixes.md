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
  four-`Date@1` repro is masked as a *dependency* import by
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
  refuse), `DO`≡`MUST` collapse, **PROVIDED guards silently dropped** at
  extraction (Schema.hs:801-810 ignores `action.provided`), regulative
  `AND`/`OR` unsupported. Decision: port from jl4-core `Machine.hs` vs.
  refuse-and-route-to-fallback.
- ✅ **`lowerCmp` InfoMap-miss fallback** — DONE (commit `65c94608`). Root cause
  was deeper than the review: `tcdInfoMap` isn't run through the typechecker's
  final substitution, so `typeOfExpr` returns `Just (InfVar …)` (not `Nothing`)
  and `isStringExpr` (no `bindingL4Types` fallback) let **STRING `==` on params
  lower to a bare `arith.cmpf` on pointers** — silently wrong for equal-content
  strings interned at different addresses. New `classifyOperand` dispatches
  NUMBER→`__l4_rat_cmp`, STRING `==`/`!=`→`__l4_str_eq`; ordered-STRING (no
  runtime builtin) and genuinely-unresolvable both fail loud (`supported:false`);
  BOOLEAN/enum/DATE keep `arith.cmpf`. 4 regression tests; 26/26 pass.
  Residual (tracked): a STRING comparison whose operands are *helper results*
  still fails loud because `funcSigs` only stores MLIR types (f64) — recovering
  the L4 return type needs a bundle-wide return-type map (larger change).
- ⬜ **Fractional decimal input fidelity** — both host paths round fractional
  NUMBER inputs through IEEE Double before the exact-rational core
  (Marshal.hs:85; wasm-server.mjs:239). Preserve decimal text into
  `__l4_rat_parse`.
- ⬜ **`Schema.freeVarsOfExpr` vs `Lower.freeVarsOfExpr` drift** (Schema.hs:660
  vs Lower.hs:2531-2536) — they disagree on the App head; "kept verbatim so
  they agree" comment is now false. Re-unify (shared helper) before a
  non-filtered helper trips it.

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
    smaller — *a harness bug can only make the gate stricter, never looser.*
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
  - **NOT end-to-end verified here**: no LLVM toolchain (`mlir-opt`/`mlir-translate`/
    `llc`/`wasm-ld`) and no live jl4-service locally, so **Tier 2 ships
    `continue-on-error: true`** (advisory) until it's proven green in CI a few
    times — *then flip to `false` to make it required*. Residuals: on-disk
    fixtures have no required *compile* coverage (Main.hs builds equivalent L4
    inline, never reads the files); `allowCompileFail`/`allowDeployFail` stay
    aggregate-opaque (harness must subtract reviewed ids before building the
    tally); LLVM-19 apt package names unconfirmed on the runner.
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
