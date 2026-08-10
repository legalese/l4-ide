# feat(eval): temporal axes and the bitemporal ledger — RULES EFFECTIVE DATE, stamped RECORD, context-sensitive RECALL

**What this adds**

This is the evaluator's time-and-state core. After this PR an L4 program can ask _which
version of the law applies_ (`RULES EFFECTIVE DATE`, a nullary `DATE` builtin that reads the
rule-version axis), can pin an evaluation to a legal regime or a fact date
(`EVAL UNDER RULES EFFECTIVE AT`, `UNDER VALID TIME`, `UNDER RULES ENCODED AT`,
`AS OF SYSTEM TIME`), and can keep state in an append-only, **bitemporally stamped** ledger:
every `RECORD` / `COMMIT` / `ATTEST` / `NOTIFY` append carries a transaction time (when it was
written) and a valid-from time (when the recorded fact is asserted to hold), and `RECALL` reads
_through_ the ambient temporal context rather than always returning the last write. The lazy
evaluator was taught to keep all of that sound under sharing: thunks forced inside a temporal
scope are cached with a context fingerprint, ledger writes fire exactly once, and an `EVAL` pin
now snapshots its result out of the pinned scope so a constructor's unforced children cannot
escape and be forced later under today's regime.

**Why**

Three gaps, each of which produced a well-typed, diagnostic-free _wrong answer_.

1. The multi-axis `TemporalContext` shipped write-only — `EVAL UNDER RULES EFFECTIVE AT` stamped
   `tcRuleValidTime` and nothing ever read it, so rule versioning was pure bookkeeping
   (smucclaw/l4-ide#912, #913).
2. The State-as-a-Ledger store had no real timestamps — `Provenance` carried a free-form
   `position` whose own docstring deferred "real timestamps" to "a later milestone". Without them
   you cannot replay a recorded event under its own valid time and have it judged under
   contemporaneous law (smucclaw/l4-ide#914 Phase 1).
3. Laziness leaked across all of this. A shared thunk memoised inside `AS OF SYSTEM TIME` was
   served stale outside it (review target T6); a ledger-touching thunk re-forced under a second
   temporal scope **appended its write twice**; and the `EVAL` pin was dynamically scoped, so
   `JUST (GST rate)` under a 2023 pin printed `JUST OF 9` — the 2025 answer
   (smucclaw/l4-ide#934).

## What's in it

180 files: 7 evaluator modules, 12 unit-test spec modules, 30 new `.l4` fixtures with their 120
goldens, and 11 existing `.ep.golden` files re-blessed.

**Evaluator core — 7 Haskell modules** (`jl4-core/src/L4/`)

- `TemporalContext.hs` — the eight-axis context, `EvalClause`/`applyEvalClauses`, and the T6
  fingerprint types (`ReadObs`, `CtxReads`, `validFor`). It carries an explicit **READER
  CONTRACT** in the module haddock: any code that lets an axis influence a result must go through
  an instrumented `readTc*` helper, and adding a reader for a latent axis means adding its
  `crXxx` fingerprint field in the same change.
- `Evaluate/Ledger.hs` (new) — the pure, event-sourced substrate: `Path`, `Provenance` (now
  `txTime :: UTCTime` + `vtFrom :: Maybe Day`), `LedgerEvent`, the append-only `Ledger`,
  `snapshot`/`readCell`/`readCellAll`, the bitemporal projections
  `readCellBitemporal`/`readCellAllBitemporal`, and the per-party store (`LedgerStore`,
  `storeAppendOwn`, `storeAppendOfficial`). Bare `RECALL` is unchanged **by construction**:
  `readCell` is _defined_ as the unbounded instantiation of `readCellBitemporal`, so the two
  cannot drift.
- `EvaluateLazy/Machine.hs` (the bulk of the diff) — the stepper: temporal-scope frames and their
  exceptional-unwind restores, the `WHNFWhen` fingerprint cache, the split
  `crLedgerWrite`/`crLedgerRead` poison bits, `driveDeepPin` + `snapshotVal`/`snapshotRef` for the
  deep `EVAL` pin, deontic sequencing of state effects, `#TRACE` event ordering, and the
  at-most-once deadline-expiry re-offer.
- `EvaluateLazy.hs`, `EvaluateLazy/ContractFrame.hs`, `Evaluate/ValueLazy.hs`,
  `Evaluate/ValueLazyJSON.hs` (new) — per-directive fresh ledger and fresh heap, the obligation
  value shape, and JSON rendering for ledger-bearing values.

**Unit tests — 12 spec modules** (`jl4-core/test/`): `BitemporalSubstrateSpec` and
`BitemporalRecallSpec` (pure-fold matrix incl. differential compatibility with the
pre-bitemporal `snapshot`, same-tx positional tie-breaks, AS-OF tx-immunity, the shared-thunk
regression), `LedgerSubstrateSpec`, `LedgerRenderingSpec`, `LedgerThunkCacheSpec` (the
double-write and recall-coherence repros), `RecordLedgerSpec`, `M4PartyLedgerSpec`,
`M45ReadSpec`, `M5DeonticSequencingSpec`, `TraceOrderingSpec`, `TracePostprocessSpec`, and
`TemporalContextSpec`.

**Corpus fixtures — 30 new `.l4` files with their 120 goldens** (`.golden`, `.ep.golden`,
`.nlg.golden`, `.schema.golden` per file), all hermetic and clock-pinned via `JL4_FIXED_NOW`:

- `ok/ledger/**` (14) — `record-flat`, `record-block{,-commit,-lest,-mixed,-rand}`,
  `record-hence-flat`, `recall-flat`, `record-thunk-once`, and the five bitemporal fixtures
  (`bitemporal-{recall,stamps,correction,shared-thunk,iterator}`).
- `ok/temporal-*` (10) — the rule-version spike and valid-time fallback, the deep-pin fixture
  (19 directives, of which **I, J and K deliberately assert the boundaries** so a future change
  that makes closures or contracts pin-aware moves those goldens on purpose), the T6 thunk-leak
  and sharing-shape regressions, and the two exception-scope-restore fixtures.
- `ok/regulative-*` (5) and `ok/deontic-breach-semantics.l4` — actor/action reference shapes,
  multiparty residuation, and the breach-semantics regression pack (ROR/RAND over both-breached
  pairs, deadline-revealing-event re-offer, the at-deadline boundary trio, `MAY` expiry routing
  to `LEST`).

**11 existing `.ep.golden` files re-blessed** — `contracts`, `prohibition`, `literal`,
`timezone-tests`, `unless-keyword`, `datetime-tests`, `excel-date-tests`, `legal-persons-tests`,
`excel-date/serials`, `ceo-performance-award`, `ny-environmental-7.3`. These are not this
theme's own work: they are the corpus-visible half of the exactprint repairs (see
**Independence**). Before, `PARTY Alice DOES smoke AT 15` printed as `PARTY 15` with the operands
rotated a keyword slot, `TIMEZONE IS EST` printed as bare `EST`, and `"Österreich"` printed as
`"\214sterreich"`; after, each golden is byte-identical to its source.

## Evidence

Quoted from the source PRs.

- **#89** (rule-version axis load-bearing): "Golden suite: **1087 examples, 0 failures**."
  `temporal-rule-version-spike.l4`: `GST rate` → **7** under rules-effective-2023, **9** under
  2024 (one shared thunk, two rule-versions); `VALUE AT` regime-selects 7/9.
  `temporal-rule-version-validtime.l4`: facts-2019 → **7**, facts-2024 → **9**, explicit
  rule-version override → **7**, both unset → today → **9**.
- **#111** (bitemporal ledger): "jl4-core suite: **200 examples, 0 failures**"; "Golden suite:
  **full pass ×2**; the only changed existing goldens are `record-thunk-once`'s (deliberate)."
  New fixtures pin `LIST 7,9,7,9,0,9` (inline _and_ through one shared binding),
  `LIST 1,2,2,0` for corrections, `LIST 1,200,100` for iterator scoping. "Both adversarial-review
  repros verified fixed: `7,9,7,9` and `1,0,1`."
- **#211** (the pin is deep): measured against two binaries built from one worktree, a pre-fix
  base (`16adc022`) and the branch. Under a 2023-06-01 pin where `GST rate` is 7 before 2024:
  `JUST GST rate` `JUST OF 9` → `JUST OF 7`; `Rate GST rate` `Rate OF 9` → `Rate OF 7`;
  `LIST GST rate` `LIST 9` → `LIST 7`; `JUST (Rate GST rate)` `JUST OF (Rate OF 9)` →
  `JUST OF (Rate OF 7)`. Whole-tree `l4 run` sweep, base vs branch, **all 725 `.l4` files present
  on both sides**: "**one file changes**", `jl4/experiments/patterns_and_idioms.l4`, red → green.
  Depth budget: "a 300-element pinned list prints exactly 200 sevens then `...`, zero nines."
  Golden churn from that branch: "**zero existing goldens move**; eight new files."
- **#80** (the cache-poison hardening, whose commit is in this range): reproduced on the un-fixed
  tip — a single shared binding produced **two** `RECORD` rows (result `-1857`) and a shared
  RECALL+TODAY binding evaluated to `LIST 737789, 7, 7`, one binding with two values inside one
  directive. Post-fix: one ledger row, result `0`, `LIST 737789, 7, 737789`. Suites
  `jl4-core-test` 156/0, `jl4-test` 1080/0, `l4-cli-test` 48/0, "**No existing golden changed**".
- **#58** (T6): `TemporalContextSpec` +16 specs; "jl4-core 62/0, jl4 golden 903/0, l4-cli 20/0";
  "suite perf neutral (~59 s)".
- **#125** (event exactprint): "Regenerated the 9 `.ep.golden` files that recorded the scrambled
  output; each is now byte-identical to its `.l4` source." "jl4-core 169/0, jl4 goldens 1120/0."
- **#130** (format fidelity): "Whole corpus swept: **0/243** ok/legal/libraries files
  non-identity under `l4 format`." "jl4-core 219/0, jl4 goldens 1412/0."
- **#172**, whose `c57ca4df` retyped the four EVAL pins from serial `NUMBER` to `DATE` and
  migrated "84 call sites across the tree", 56 of them files in this PR: "`jl4-test`: **1849
  examples, 0 failures**."

**Known bound, carried forward honestly.** #211 records that the pin does **not** reach
regulative values: `ValObligation`'s party and due are `Either RExpr (Value a)` and its followups
are bare `RExpr` closed over an `Environment`, so the pin's reachability relation reaches nothing
in a freshly built obligation and the stepper evaluates them later, ambiently. Measured with
`window` = 30 before 2024 and 10 after, ambient clock 2025: a 2023 pin still breaches at
deadline **10**. Byte-identical pre- and post-fix, so it is not a regression — it is asserted as
fixture **case K** and stated as open in `specs/todo/TEMPORAL-RULE-VERSION-DESIGN.md` §1.4.1.
That spec text is not in this PR; it is in the **specs** theme.

## Independence

**This PR is not standalone, and the dependency is in the goldens, not the Haskell.**

- The evaluator modules here (`TemporalContext.hs`, `Evaluate/Ledger.hs`, `EvaluateLazy*.hs`,
  `Evaluate/ValueLazy*.hs`) are internally complete and compile as a unit.
- **Depends on `lang-syntax-typecheck`**, three separate ways, all hard:
  1. The surface syntax. `RECORD` / `COMMIT` / `ATTEST` / `NOTIFY` / `RECALL` / `RECALL ALL` and
     the `PARTY … DOES … AT …` event form are parsed and typechecked there
     (`L4/Parser.hs`, `L4/Syntax.hs`, `L4/TypeCheck.hs`). Every fixture in this PR uses them.
  2. The pin types. `c57ca4df` retyped the four EVAL pins as `DATE -> a -> a` in
     `jl4-core/src/L4/TypeCheck/Environment.hs`. Every fixture here writes the new form
     (`EVAL UNDER VALID TIME (DATE_FROM_DMY 1 1 2023) …`), which does **not** typecheck without
     that change.
  3. The 11 re-blessed `.ep.golden` files encode the output of the exactprint repairs in
     `L4/Syntax.hs` (the inverted `Event` `atFirst` branches, #919), `L4/Parser.hs`
     (`timezone'`, `infixUnless`, `decidePatternMatch`) and `L4/Lexer.hs` (`TStringLit` keeping
     the raw source slice). Land them without that code and those 11 goldens fail; land that code
     without them and they fail too. They are a matched pair.
- **Depends on `lang-printer`** only lightly: the `.ep.golden` shape is exactprint, whose
  annotation plumbing (`L4/Parser/Anno.hs`) lives there. Note that #214's `prettyLayout` work
  moved **no** exactprint golden and touched **none** of this PR's files, so `lang-printer` is a
  co-requisite for the corpus check, not a semantic one.
- **Does not depend on** `dmn-export`, `bpmn-export`, `openfisca-export`, `ladder-viz`,
  `service-cli`, `go-pipeline`, `corpus-regcf` or any wizard theme. Those consume the evaluator;
  none of them is needed to make these tests pass.
- **`corpus-regcf` depends on this, not the reverse.** The Reg CF corpus's four dated regimes are
  selected on `RULES EFFECTIVE DATE`, which is defined here.
- **The specs are elsewhere.** `TEMPORAL-RULE-VERSION-DESIGN.md`, `STATE-AS-LEDGER-SPEC.md` and
  the §1.4.1 ruling that records the regulative bound are in the **specs** theme; the
  multi-temporal tutorial is in **docs**. This PR's code haddocks (notably the READER CONTRACT in
  `TemporalContext.hs` and the D2/append-only note in `Evaluate/Ledger.hs`) are self-contained,
  but a reviewer wanting the decision record has to read the specs PR.

**Ordering that works:** `lang-syntax-typecheck` → this PR → `corpus-regcf` and the export
themes. `lang-printer` alongside or before.

## Risk if rejected

Dropping this drops the *reason* the rest of the temporal programme exists: `RULES EFFECTIVE
DATE` disappears, so `corpus-regcf`'s four dated regimes have nothing to select on and the M5
headline ("same investor, two dates, the answer moves the wrong way") stops being expressible;
the ledger reverts to a store with no real timestamps, so an event cannot be replayed under
contemporaneous law. Worse, the three soundness fixes go with it — the T6 stale-cache leak, the
double-`RECORD` on a shared thunk, and the shallow `EVAL` pin all return, and each of those
produces a well-typed answer that is simply wrong, with no diagnostic anywhere.

## Provenance

Unstable PRs folded into this one:

- #89 — feat(jl4-core): make the rule-version temporal axis load-bearing (RULES EFFECTIVE DATE)
- #111 — feat(jl4-core): bitemporal ledger — stamp RECORD, context-sensitive RECALL (#914 Phase 1)
- #125 — fix(syntax): un-swap Event exactprint atFirst branches (#919) — the re-blessed `.ep.golden` half
- #130 — fix(format): l4 format identity for TIMEZONE/UNLESS/unicode/multi-clause DECIDE — likewise
- #172 — feat(regcf): the rule-version axis — via `c57ca4df`, the DATE-typed EVAL pins and the 56 fixture migrations
- #174 — feat(daydate): YMD — the ISO-ordered date constructor (no file in this PR changed by its head commit; listed for completeness)
- #189 — Merge main into unstable (no file in this PR changed by the merge)
- #211 — fix(lang): the EVAL temporal pin is deep (#934) — the pin half only; the #930 shadowing half is `lang-syntax-typecheck`
- #214 — fix(print): make prettyLayout round-trip (touched none of this PR's files; listed because the manifest attributes it)

These files also carry evaluator work from earlier `unstable` PRs whose commits fall inside
`origin/main..origin/unstable` and are therefore included in this diff — verified with
`git log --oneline origin/main..origin/unstable -- <paths>`:

- #31 — L4 state-as-a-ledger: RECORD/COMMIT/ATTEST writes, RECALL reads, deontic sequencing (M0–M5)
- #57 — deontic breach semantics (RAND/ROR both-breached, deadline re-offer bound)
- #58 — fix(jl4-core): temporal-context leakage through thunk memoization (review T6)
- #80 — fix(jl4-core): harden deontic/temporal evaluator — unwind party restore + ledger-vs-WHNFWhen cache poison
