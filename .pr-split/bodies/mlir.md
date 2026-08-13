# fix(mlir): the parity campaign — silent wrong answers become right answers or loud refusals

**What this adds**

`jl4-mlir` compiles L4 to MLIR/WASM as an alternative execution backend to the `jl4-service`
interpreter. Before the parity campaign it would happily answer questions it had got wrong:
`factorial` returned `1` for every input, `sum [2,3,4]` evaluated to `3` in the prelude, ordered
comparisons on strings used JS UTF-16 code-unit order instead of L4's code-point order, `CONSIDER`
over `EITHER` never resolved, and a `DATE` operand in `PLUS`/`MINUS` crashed the wasm module. The
campaign fixed eleven such wrong-answer classes outright and converted the constructs the backend
genuinely cannot compile from _silently wrong_ into _loud structural refusal_ (`supported: false`,
which routes the caller back to the reference evaluator).

**That campaign's changes land across two PRs, and this is the runtime-and-evidence half.** The
compiler half — `Lower.hs`, `Schema.hs`, `Marshal.hs`, `Pipeline.hs`, the executable and the
Haskell test driver, where the overload dispatch, `enrichParamTypes`, the `EITHER` representation
and the fail-loud schema guards live — was inseparable from the language-core type changes and
rides in [#257](https://github.com/legalese/l4-ide/pull/257). What lands **here** is everything
that surrounds and proves it:

- the **JS runtime** (`runtime/jl4-runtime.mjs`, 4401 → 4684 lines), which is where several of the
  wrong answers were actually fixed — code-point string semantics, exact-rational deontic deadline
  arithmetic, and the wire-format reconciliation with the reference service;
- the **differential harness and gate** (`scripts/`), which is what found every one of them;
- the **probe corpus** (22 fixtures + 8 coverage-report probes + 1 case table for an existing
  example), which is what pins them;
- the **documentation ledger** (`PARITY-HUNT-LOG.md` and friends), which is the reviewer's guide
  to the whole campaign;
- and the two Haskell files whose changes are freestanding: `ABI.hs` (a documentation truth-repair)
  and `Runtime/Builtins.hs` (the `__l4_str_cmp` declaration).

**Why**

The backend had no way to know it was wrong. Every Haskell suite was green throughout, the build
compiled clean, and the answers were still bad — because "compiles" and "computes the right thing"
are different properties and only a differential sweep tests the second. The campaign's governing
rule (called Iron Rule 2 in the tree) is that a _silent_ wrong answer at `supported: true` is the
cardinal sin: refusing is always acceptable, because the caller falls back to `jl4-service` and
still gets the right answer, whereas a confident wrong number is unrecoverable.

The campaign's own summary of what it cost to not have this: the source PR's merge "compiled
clean, every Haskell suite passed, and the backend was still wrong. The differential sweep is the
only thing in this repo that would have said so."

## What's in it

**48 files, +4,360 / −331.** By kind: 2 Haskell, 5 `.mjs` (2 new), 5 top-level markdown, 1 cabal
file, 12 files under `coverage-report/`, 22 test fixtures (`.l4` probes and their `.cases.json`
case tables), and one `.cases.json` for an `.l4` file that already exists on `main`.

**The JS runtime — where these fixes actually live**

- `__l4_str_cmp`: ordered STRING comparison, lexicographic by Unicode **code point** to match
  jl4-core's `Data.Text` `Ord` — explicitly not JS-native `<`, which orders UTF-16 code units.
  Embedded NUL bytes are preserved through comparison. Declared to the compiler in
  `Runtime/Builtins.hs` (+4 lines, the one semantic Haskell change here); the call sites that use
  it are emitted by #257's `Lower.hs`.
- Code-point semantics for `STRINGLENGTH` / `INDEXOF` / `CHARAT` / `SUBSTRING` (`SUBSTRING` had
  also been reading its third argument as an end index rather than a length).
- Deontic: residual-obligation deadline is _last-observed_, not `MAX`; deadline arithmetic is
  exact-rational, for fractional-time parity; the deontic runtime matches jl4-service on events,
  breaches and `MAY` residuals.
- Wire-format reconciliation with the reference: un-backticked constructor names, `MAYBE` empty as
  `null` rather than `"NOTHING"`, `MAYBE` present as the bare value rather than
  `{"JUST":["x"]}`.
- The runtime's unit test grows 179 → 720 lines alongside.

**The harness that found all of this**

- `scripts/parity-gate.mjs` (new, 259 lines) — pure, side-effect-free gate semantics with zero
  heavy dependencies (no runtime, no `execFileSync`, no `fetch`, no `fs`), so its unit test runs
  under bare `node`. `canonical` / `extractValue` / `ulpEqual` / `classifyOutcome` are faithful
  extractions from the harness; `gateVerdict` is the hardened single source of truth replacing an
  inline `parityFails = differs + wasm-error`.
- `scripts/parity-gate.test.mjs` (new, 645 lines) covers it, and `scripts/parity-harness.mjs` is
  reworked (472 → 577 lines). The harness deploys the same source to both backends, calls both
  with the same arguments, and diffs the responses byte-for-byte.

**The probe corpus**

22 fixtures under `test/fixtures/` — the `either-*` family (9 files probing payload-carrying
`EITHER` through returns, records, `MAYBE`, shadowing and inference), `list-probe` /
`list-ret-probe`, `str-ordering-probe`, `datetime-probe`, `intrinsics-probe`, the three
`deontic-*` case tables, and `test.cases.json` (324 lines) — plus, under `coverage-report/`, the
`str-index`, `str-nul`, `provided` and `deadline` probes. Two of those (`provided-probe`,
`deadline-probe`) carry `.cases.json.pending` extensions: they pin fail-closed extraction refusals
whose fix has no committed timeline, and the `.pending` name keeps the harness from auto-loading
them as green cells. `jl4/examples/implicit-assume-test.cases.json` is a case table for an `.l4`
file already on `main`, so it carries no corpus dependency.

**The documentation ledger**

`PARITY-HUNT-LOG.md` (new, 558 lines) is the reviewer's guide: a 13-entry status ledger in three
states — FIXED (the backend computes the correct answer), FAIL-LOUD (silent-wrong eliminated, the
backend refuses and routes to fallback, capability gap still open), and OPEN (still silently
wrong, or untested) — with the "what was tried and rejected" for each. The ledger closes with
**"There are no remaining OPENs"** — and says so with its own caveat attached: the claim is
bounded by the corpus and the curated cases, and the log is explicit that "no known reds" and "no
reds" are different statements. `coverage-report/PARITY-COVERAGE.md` (new, 271 lines) carries the
matrices. `MLIR-REVIEW.md` (new, 99 lines) is the adversarial review. `README.md`,
`FEATURE-PARITY-PLAN.md` and `SOLIDITY-BACKEND-PLAN.md` are reconciled with the backend as it
actually is.

**One documentation repair worth its own line.** `ABI.hs`'s header claimed NUMBER crosses the ABI
as "the f64 value directly (identity)". That was true once and is false now: NUMBERs are
arbitrary-precision rationals interned in a per-call pool, and the value crossing the ABI is the
integer _handle_ reinterpreted as an f64 — so arithmetic must go through the `__l4_rat_*`
builtins, never native `arith.addf`. The comment now says so, with the history. A reader trusting
the old comment would have written a backend bug of exactly the class this campaign exists to
catch.

**One build-correctness fix.** `runtime/jl4-runtime.mjs` is spliced into the executable at compile
time by Template Haskell. `extra-source-files` was declared inside the `executable` stanza, where
cabal rejects it as an unknown field and silently ignores it — so editing the runtime did not
trigger a re-embed, and the embedded runtime drifted from source across incremental builds. It is
now declared at package level, where cabal actually monitors it.

## Evidence

Quoted from the source PR (#190) and from `PARITY-HUNT-LOG.md`. These figures measure the campaign
whole — this PR's runtime, fixtures and harness together with #257's compiler half — because the
differential sweep can only run on a tree that has both.

**The regression a green build hid.** The merge took _zero_ textual conflicts in `jl4-mlir/` — no
unstable commit had touched the directory — and that is precisely what made it dangerous. The
sweep came back **"213 byte-identical / 14 differs against a documented board of 227/0."**
Nothing in `jl4-mlir/` had changed; `jl4-service` had, and `jl4-service` _is_ the reference. The
reference commit says outright why it moved: _"It was handing out a schema its responses fail."_
All 14 cells were silent wrong answers at `supported: true`, and the backticked-constructor one
was worse than cosmetic — the service declares the un-backticked spelling in its own
`returnSchema` enum, so a caller validating our response against our own schema would have
rejected it.

**Final boards.**

| board                                                                                           | result                                                                    |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Extended sweep (38-file coverage corpus + `list`/`either` probes + four `coverage-report/` probes) | **227 byte-identical, 0 differs, 0 wasm-error, 5 refused-unsupported — PARITY OK** |
| Committed CI Tier-2 gate                                                                        | **97 byte-identical, 0 refused, exit 0**                                   |
| `jl4-mlir-test`                                                                                 | **47 / 47**                                                                |
| JS runtime unit suite                                                                           | **89 passing + 2 xfail**                                                   |
| JS parity-gate unit suite                                                                       | **93**                                                                     |
| Trace sub-matrix (not a gate)                                                                   | **62 / 165**                                                               |

The Tier-2 97 decomposes as `test` 30 + `datetime-probe` 14 + `list-probe` 12 + `either-probe` 15 +
`desc` 4 + `deontic-sale` 12 + `deontic-seatbelt` 7 + `deontic-breach` 3.

**The 5 refusals are correct behaviour, not failures**: `ceo-performance-award` (unextractable
deontic), `orchestrator::evaluateClaim` (real IO — `callClaudeWithKey` does a POST — plus an
unmarshallable return), `mixfix-garden-path::tax-on` (an `@export`ed same-arity collision, which
is genuinely ambiguous at the JSON API and therefore refuses **by design**), and
`provided-probe` / `deadline-probe` (pinned fail-closed extraction refusals — the two `.pending`
files in this PR).

The trace sub-matrix figure of 62/165 is **exactly the figure `PARITY-HUNT-LOG.md` already
predicted** — corroboration that the pre-merge board was genuinely restored rather than merely
made to pass.

**Deliberate xfails.** The two `jl4-runtime` xfails are TDD placeholders for unrealized `MUSTNOT`
prohibition semantics (prohibited act before deadline → `BREACH`; respected → `FULFILLED`). They
throw `DeonticInputError` today, are logged `xfail (pending)`, and the harness reports **0
XPASS** — so if the feature lands they announce themselves instead of sitting green.

**Two asymmetries are deliberate and documented so nobody "cleans them up."** Within one deontic
`OBLIGATION` the reference spells the party plain and the action backticked —
``{"party":"the seller","action":"`deliver the goods`"}`` — because the party is an evaluated
constructor value (`constructorText`) and the action an unevaluated `Name` (`prettyLayout`).
Harmonising them in _either_ direction re-breaks half the cells. And a literal party is backticked
when **unobserved** and plain when **observed**; the sweep only revealed this by _reversing_ the
last two failures. The comment at that site had asserted literal parties "print identically either
way" — true before the reference moved, false after, and believed until the harness contradicted
it.

## Blast radius

**33 new files**, 15 modified.

Every file but one is under `jl4-mlir/`; the one exception is
`jl4/examples/implicit-assume-test.cases.json`, a new case table for an example already on `main`.
Of the 15 modified: the JS runtime and its test, the harness, the cabal file, six markdown /
coverage documents, three deontic case tables — and two Haskell files, `ABI.hs` (comment-only) and
`Runtime/Builtins.hs` (+4 lines declaring `__l4_str_cmp`). **No compiler logic changes in this
PR** — that is #257.

## Independence

- **#257 (the language core)** owns the compiler half of this campaign: `Lower.hs` (2695 → 3441),
  `Schema.hs`, `Marshal.hs`, `Pipeline.hs`, `app/Main.hs` and the Haskell test driver
  (572 → 1593), plus `enrichParamTypes` in `L4.Export` and the post-#245 AST adaptations. It also
  owns the `jl4-service` sources that are the differential reference — the wire format this PR's
  runtime was reconciled _to_. **This branch compiles and its CI is green without #257** (its two
  Haskell files are compatible with `main` as-is), but the campaign's claims are joint: run the
  harness on `main` + this PR alone and the sweep measures `main`'s compiler, which fails most of
  the probe corpus. The boards above describe the tree where both have landed.
- **ci-build (#233)** owns `.github/workflows/pr-checks.yml`, which is where the
  `jl4-mlir-parity-gate-unit` and `jl4-mlir-parity-full` jobs and the `mlir` paths filter live.
  Without it the scripts here exist but nothing runs them on a PR. (That workflow also added the
  `'**/*.mjs'` filter — before it, a PR touching only `.mjs` files ran zero jobs, including the
  one hosting `prettier --check .`, which is how this lane wrote `.mjs` for weeks unformatted.)
- **Softer couplings:** the extended 227-cell sweep reads case tables that live in other themes —
  `jl4/experiments/britishcitizen5.cases.json` (**experiments**),
  `jl4/examples/legal/ceo-performance-award.cases.json.pending` (**corpus-legal-new**),
  `jl4/examples/ok/desc.cases.json` and `assume-as-given.cases.json` (**#257**) — and
  `specs/todo/mlir-parity-fixes.md`, the per-item fix tracker `PARITY-HUNT-LOG.md` links to, is in
  **specs**. Those affect how much of the sweep can be reproduced, not whether this package
  builds. Running the full harness at all needs a built `jl4-service` binary.

## Risk if rejected

The campaign's compiler fixes in #257 land without the runtime that half of them call into
(`__l4_str_cmp` has no implementation, the deontic runtime keeps `MAX`-deadline and float
arithmetic, the wire format stays divergent on constructor spelling and `MAYBE`), without the
probe corpus that pins them, and without the differential harness that is the only mechanism in
the repo that can detect a silent wrong answer — every other suite was green the whole time these
bugs were live. The hunt ledger, the coverage matrices and the adversarial review disappear, so
the next person to touch the backend inherits neither the evidence nor the "tried and rejected"
history.

## This PR was part of an interlock that has since been consolidated

An earlier revision of this section named a **15-PR merge batch** that had to land as one unit. That
is no longer the shape of the work, and the roster it listed is now largely closed. What happened:

Twelve of those PRs could not build separately, because the entangling changes are to *types* in
modules `main` already has — `Syntax.hs` removes the `Expr` constructor `Exponent`, widens
`MkAssume` 4→5, `MkTypedName` 4→5 and `MkOptionallyTypedName` 3→4, and adds strict fields to
`MkCheckState`; the evaluator widens `MkEvalDirectiveResult` 3→4. Every consumer had to change in
the same commit, in **both** directions, and the consumers were spread across six packages. No
ordering resolved it.

**Eight of them were therefore consolidated into [#257](https://github.com/legalese/l4-ide/pull/257),
the language core** — `lang-syntax-typecheck` (#245), `lang-eval-ledger` (#241), `ladder-viz`
(#240), `lang-printer` (#243), `lsp` (#246), `lang-sets` (#244), `lang-imports-stdlib` (#242) and
`actus-archive` (#230), all now closed. #257 was built by taking `unstable`'s version of whatever
the compiler rejected, to a fixed point, so it contains no hand-written intermediate code. It is
green: `cabal build all` clean, 7/7 suites, `jl4-test` 2039 examples 0 failures.

**What remains for this PR is a one-way dependency**, which ordering does resolve. It no longer has
to merge simultaneously with anything — it simply has to merge *after* its prerequisites. Those are
named in the metadata line at the top of this body and in the merge-order guide.

The full measurement — six builds, with the verbatim first error of each failing one — is recorded
in `.pr-split/DEPENDENCIES.md` on the branch `claude/unstable-branch-reorganization-6cle91`.

## Provenance

This theme was re-cut in the 12 August reconciliation: its four `L4.MLIR.*` compiler modules,
`app/Main.hs` and `test/Main.hs` moved to #257, taking it from 54 files to 48.

- legalese/l4-ide#190 — _MLIR parity campaign: land the fail-loud bugfix ledger on unstable_
  (43 commits; this PR takes its `jl4-mlir/` runtime, scripts, fixtures and documentation, plus
  `jl4/examples/implicit-assume-test.cases.json` — its compiler modules are in #257, and its
  `.github/workflows`, `jl4-core/src/L4/Export.hs`, `specs/todo/`, and remaining `jl4/examples`
  and `doc/` changes belong to the `ci-build`, `specs`, `corpus-legal-new`, `experiments` and
  `docs` themes and to #257).
