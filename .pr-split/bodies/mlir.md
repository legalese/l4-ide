# fix(mlir): the parity campaign — silent wrong answers become right answers or loud refusals

**What this adds**

`jl4-mlir` compiles L4 to MLIR/WASM as an alternative execution backend to the
`jl4-service` interpreter. Before this change it would happily answer questions it had
got wrong: `factorial` returned `1` for every input, `sum [2,3,4]` evaluated to `3` in
the prelude, ordered comparisons on strings used JS UTF-16 code-unit order instead of
L4's code-point order, `CONSIDER` over `EITHER` never resolved, and a `DATE` operand in
`PLUS`/`MINUS` crashed the wasm module. This PR fixes eleven such wrong-answer classes
outright, converts a further set of constructs the backend genuinely cannot compile from
*silently wrong* into *loud structural refusal* (`supported: false`, which routes the
caller back to the reference evaluator), and lands the differential harness that found
them — a gate that deploys the same source to both backends, calls both with the same
arguments, and diffs the responses byte-for-byte.

**Why**

The backend had no way to know it was wrong. Every Haskell suite was green throughout,
the build compiled clean, and the answers were still bad — because "compiles" and
"computes the right thing" are different properties and only a differential sweep tests
the second. The campaign's governing rule (called Iron Rule 2 in the tree) is that a
*silent* wrong answer at `supported: true` is the cardinal sin: refusing is always
acceptable, because the caller falls back to `jl4-service` and still gets the right
answer, whereas a confident wrong number is unrecoverable. Everything here is an
application of that rule.

The campaign's own summary of what it cost to not have this: the source PR's merge
"compiled clean, every Haskell suite passed, and the backend was still wrong. The
differential sweep is the only thing in this repo that would have said so."

## What's in it

**Backend fixes — the wrong answer becomes the right answer**

- `lowerRatBinop` ABI split, so a `DATE` operand in `PLUS`/`MINUS` no longer crashes the
  wasm module.
- Same-arity top-level overloads dispatch by `Unique` instead of collapsing to one body
  (the `Weekday of` collision); the same fix for lifted local helpers, which is what made
  `sum [2,3,4]` return `3`.
- `enrichParamTypes` fills bare-head parameters (`DECIDE factorial x IS`, no `GIVEN`) from
  the typechecker's inferred `Fun` type. Without it the param schema defaulted to
  `{"type":"object"}`, `marshalArg` turned the JSON number into a struct pointer of `0.0`,
  and `0.0` as a rational-pool handle aliased the interned literal `0` — so `factorial`
  returned `1` for every input.
- A bundle-wide L4 type map (`funcL4Types`, projected from the typechecker's substituted
  `EntityInfo`) so helper-result `NUMBER` comparisons are classifiable.
- `__l4_str_cmp`: ordered STRING comparison, lexicographic by Unicode **code point** to
  match jl4-core's `Data.Text` `Ord` — explicitly not JS-native `<`, which orders UTF-16
  code units. Embedded NUL bytes are preserved through comparison.
- Code-point semantics for `STRINGLENGTH` / `INDEXOF` / `CHARAT` / `SUBSTRING` (`SUBSTRING`
  had also been reading its third argument as an end index rather than a length).
- Deontic: residual-obligation deadline is *last-observed*, not `MAX`; deadline arithmetic
  is exact-rational, for fractional-time parity; the deontic runtime matches jl4-service on
  events, breaches and `MAY` residuals.
- `CONSIDER` over `EITHER` resolves: `EITHER a b` is a payload-carrying builtin ADT, so it
  is now represented exactly like `MAYBE` — a 2-slot `[tag, payload]` record with `LEFT`
  tagged `0.0` and `RIGHT` `1.0` — and wired through construction, tag test and payload
  bind.
- Wire-format reconciliation with the reference (see Evidence): un-backticked constructor
  names, `MAYBE` empty as `null` rather than `"NOTHING"`, `MAYBE` present as the bare value
  rather than `{"JUST":["x"]}`.

**Fail-loud conversions — the silent wrong answer becomes an honest refusal**

Two new schema-build guards in `Schema.hs` refuse at bundle time rather than letting a
bad answer ship:

- `deonticExtractionFailed` — a `DEONTIC` export whose body cannot be reduced to a
  contract tree the runtime interpreter can walk. `deontonToContract` now returns
  `Maybe`, failing closed on an action carrying a `PROVIDED` guard (the runtime never
  evaluates it, so dropping it flips obligations that should have been inert), a
  non-literal deadline (the runtime does `Number(deadline)`, which is `NaN` for a computed
  deadline, and `NaN` makes every `at > deadline` test false, so nothing ever lapses), and
  a present-but-unextractable `HENCE`/`LEST` continuation.
- `unmarshallableReturn` — a return type the production decoder cannot walk: enum-with-data
  (`ONE OF … HAS …`) and anything transitively containing it, plus any `RSList` in an
  otherwise-decodable schema, because `unmarshalWithSchema` has no list case and would ship
  raw pointer bits or a silent `null`.

Alongside those: always-match patterns and overload collisions fail loud; a null deontic
contract is guarded and `MUSTNOT` refused; fail-closed ABI returns for user `LEFT`/`RIGHT`
enums and at the enriched-type altitude; type-guaranteed `NUMBER`/`STRING` comparison with
a loud failure otherwise; and unsupported diagnostics now propagate through the call graph
so an unsupported helper marks its callers unsupported too.

**The harness that found all of this**

- `scripts/parity-gate.mjs` (new) — pure, side-effect-free gate semantics with zero heavy
  dependencies (no runtime, no `execFileSync`, no `fetch`, no `fs`), so its unit test runs
  under bare `node`. `canonical` / `extractValue` / `ulpEqual` / `classifyOutcome` are
  faithful extractions from the harness; `gateVerdict` is the hardened single source of
  truth replacing an inline `parityFails = differs + wasm-error`.
- `scripts/parity-gate.test.mjs` (new, 645 lines) covers it, and
  `scripts/parity-harness.mjs` is reworked (472 → 577 lines).
- `runtime/jl4-runtime.mjs` grows 4401 → 4684 lines with substantial churn inside that;
  its unit test goes 179 → 720.

**By kind.** 54 files: 8 Haskell (`Lower.hs` is the bulk — 2695 → 3441 lines — plus
`Schema.hs`, `ABI.hs`, `Marshal.hs`, `Pipeline.hs`, `Runtime/Builtins.hs`, `app/Main.hs`,
and `test/Main.hs` at 572 → 1593), 5 `.mjs` (2 of them new), 7 markdown, 1 cabal file,
22 test fixtures (`.l4` probes and their `.cases.json` case tables), 10 files under
`coverage-report/`, and one `.cases.json` for an existing `jl4/examples` file.

**Documentation.** `PARITY-HUNT-LOG.md` (new, 558 lines) is the reviewer's guide: a
13-entry status ledger in three states — FIXED (the backend computes the correct answer),
FAIL-LOUD (silent-wrong eliminated, the backend refuses and routes to fallback, capability
gap still open), and OPEN (still silently wrong, or untested) — with the "what was tried and
rejected" for each. The ledger closes with **"There are no remaining OPENs"** — and says so
with its own caveat attached: the claim is bounded by the corpus and the curated cases, and
the log is explicit that "no known reds" and "no reds" are different statements.
`coverage-report/PARITY-COVERAGE.md` (new, 271 lines) carries the matrices.
`MLIR-REVIEW.md` (new, 99 lines) is the adversarial review. `README.md`,
`FEATURE-PARITY-PLAN.md` and `SOLIDITY-BACKEND-PLAN.md` are reconciled with the backend as
it actually is.

**One build-correctness fix worth its own line.** `runtime/jl4-runtime.mjs` is spliced into
the executable at compile time by Template Haskell. `extra-source-files` was declared inside
the `executable` stanza, where cabal rejects it as an unknown field and silently ignores it
— so editing the runtime did not trigger a re-embed, and the embedded runtime drifted from
source across incremental builds. It is now declared at package level, where cabal actually
monitors it.

## Evidence

Quoted from the source PR (#190) and from `PARITY-HUNT-LOG.md`.

**The regression a green build hid.** The merge took *zero* textual conflicts in
`jl4-mlir/` — no unstable commit had touched the directory — and that is precisely what
made it dangerous. The sweep came back **"213 byte-identical / 14 differs against a
documented board of 227/0."** Nothing in `jl4-mlir/` had changed; `jl4-service` had, and
`jl4-service` *is* the reference. The reference commit says outright why it moved: *"It was
handing out a schema its responses fail."* All 14 cells were silent wrong answers at
`supported: true`, and the backticked-constructor one was worse than cosmetic — the service
declares the un-backticked spelling in its own `returnSchema` enum, so a caller validating
our response against our own schema would have rejected it.

**Final boards.**

| board | result |
| --- | --- |
| Extended sweep (38-file coverage corpus + `list`/`either` probes + four `coverage-report/` probes) | **227 byte-identical, 0 differs, 0 wasm-error, 5 refused-unsupported — PARITY OK** |
| Committed CI Tier-2 gate | **97 byte-identical, 0 refused, exit 0** |
| `jl4-mlir-test` | **47 / 47** |
| JS runtime unit suite | **89 passing + 2 xfail** |
| JS parity-gate unit suite | **93** |
| Trace sub-matrix (not a gate) | **62 / 165** |

The Tier-2 97 decomposes as `test` 30 + `datetime-probe` 14 + `list-probe` 12 +
`either-probe` 15 + `desc` 4 + `deontic-sale` 12 + `deontic-seatbelt` 7 + `deontic-breach` 3.

**The 5 refusals are correct behaviour, not failures**: `ceo-performance-award`
(unextractable deontic), `orchestrator::evaluateClaim` (real IO — `callClaudeWithKey` does a
POST — plus an unmarshallable return), `mixfix-garden-path::tax-on` (an `@export`ed
same-arity collision, which is genuinely ambiguous at the JSON API and therefore refuses
**by design**), and `provided-probe` / `deadline-probe` (pinned fail-closed extraction
refusals).

The trace sub-matrix figure of 62/165 is **exactly the figure `PARITY-HUNT-LOG.md` already
predicted** — corroboration that the pre-merge board was genuinely restored rather than
merely made to pass.

**Deliberate xfails.** The two `jl4-runtime` xfails are TDD placeholders for unrealized
`MUSTNOT` prohibition semantics (prohibited act before deadline → `BREACH`; respected →
`FULFILLED`). They throw `DeonticInputError` today, are logged `xfail (pending)`, and the
harness reports **0 XPASS** — so if the feature lands they announce themselves instead of
sitting green.

**Two asymmetries are deliberate and documented so nobody "cleans them up."** Within one
deontic `OBLIGATION` the reference spells the party plain and the action backticked —
`{"party":"the seller","action":"`deliver the goods`"}` — because the party is an evaluated
constructor value (`constructorText`) and the action an unevaluated `Name` (`prettyLayout`).
Harmonising them in *either* direction re-breaks half the cells. And a literal party is
backticked when **unobserved** and plain when **observed**; the sweep only revealed this by
*reversing* the last two failures. The comment at that site had asserted literal parties
"print identically either way" — true before the reference moved, false after, and believed
until the harness contradicted it.

**Whole-tree suites at the source merge**, for context (these cover far more than this
slice): `cabal build all` clean under GHC 9.10.3 with `-Wall -Werror`; `jl4-test` 2129
examples 0 failures; `jl4-core-test` 269/0; `jl4-service-test` 311/0; `jl4-lsp-test` 10/0;
`jl4-websessions-test` 1/0; `l4-cli-test` 125/0; `prettier --check .` clean.

## Independence

**Not standalone.** This PR is the `jl4-mlir` package only, and it needs three things from
siblings:

1. **`service-cli`** owns `jl4-core/src/L4/Export.hs`, which is where `enrichParamTypes`
   lives. `Schema.hs` here imports it directly, so this PR **does not compile** without
   that theme. `service-cli` also owns the `jl4-service` sources whose wire format
   (un-backticked constructors, `null` for empty `MAYBE`, bare value for present `MAYBE`)
   this PR's runtime and fixtures were reconciled *to* — the reference and the follower
   must land together or the differential gate goes red in whichever direction is behind.
2. **`lang-syntax-typecheck`** owns the AST shape changes this code was mechanically
   adapted to: `MkOptionallyTypedName` gained a fourth field (the `TYPICALLY` default) and
   the `Exponent` constructor was removed. `Lower.hs` and `Schema.hs` carry the matching
   pattern-match updates, so they will not typecheck against `main`'s `L4.Syntax`. That
   theme also owns `jl4/examples/ok/desc.cases.json`, which is 4 of the 97 Tier-2 cells.
3. **`ci-build`** owns `.github/workflows/pr-checks.yml`, which is where the
   `jl4-mlir-parity-gate-unit` and `jl4-mlir-parity-full` jobs and the `mlir` paths filter
   live. Without it the scripts here exist but nothing runs them on a PR. (That workflow
   also added the `'**/*.mjs'` filter — before it, a PR touching only `.mjs` files ran zero
   jobs, including the one hosting `prettier --check .`, which is how this lane wrote
   `.mjs` for weeks unformatted.)

**Softer couplings, worth naming but not blocking:** the extended 227-cell sweep reads case
tables that live in other themes — `jl4/experiments/britishcitizen5.cases.json`
(**experiments**), `jl4/examples/ok/assume-as-given.cases.json` (**lang-syntax-typecheck**),
`jl4/examples/legal/ceo-performance-award.cases.json.pending` (**corpus-legal-new**) — and
`specs/todo/mlir-parity-fixes.md`, the per-item fix tracker that `PARITY-HUNT-LOG.md` links
to, is in **specs**. Those affect how much of the sweep can be reproduced, not whether this
package builds. Running the full harness at all needs a built `jl4-service` binary.

**What is self-contained:** `jl4/examples/implicit-assume-test.cases.json` is a case table
for an `.l4` file that already exists on `main`, so it carries no corpus dependency.

## Risk if rejected

The backend keeps computing wrong answers with `supported: true` — `factorial` returns `1`,
`sum [2,3,4]` returns `3` in the prelude, string ordering follows UTF-16 rather than code
points, and `DATE` arithmetic crashes — and, worse, the tree loses the only mechanism that
can detect any of this, since every other suite was green the whole time these bugs were
live. If `service-cli` lands without this, the two backends' wire formats diverge on
constructor names and `MAYBE` encoding, so a caller validating a wasm response against the
service's own published schema will reject it.

## Provenance

- legalese/l4-ide#190 — *MLIR parity campaign: land the fail-loud bugfix ledger on unstable*
  (43 commits; only its `jl4-mlir/` and `jl4/examples/implicit-assume-test.cases.json`
  contents are taken here — its `.github/workflows`, `jl4-core/src/L4/Export.hs`,
  `specs/todo/`, and remaining `jl4/examples` and `doc/` changes belong to the `ci-build`,
  `service-cli`, `specs`, `lang-syntax-typecheck`, `corpus-legal-new`, `experiments` and
  `docs` themes).
