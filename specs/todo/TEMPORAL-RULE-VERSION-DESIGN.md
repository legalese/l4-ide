# TEMPORAL-RULE-VERSION-DESIGN — reconciled decision doc

- **Status**: DECIDED (design) / Phase 0 spike specified below
- **Date**: 2026-07-08
- **Base**: `origin/unstable` @ `55bd0452` (includes PR#58 thunk-leak fix, PR#80
  deontic/temporal unwind hardening, and the T6 context-fingerprint cache)
- **Worktree**: `~/src/legalese/l4wt/temporal-rule-version`
  (branch `mengwong/temporal-rule-version`)
- **Supersedes** (as design authority; kept for archaeology):
  `specs/todo/TEMPORAL_EVAL_SPEC.md`, `specs/todo/TEMPORAL_PRELUDE_MACROS.md`,
  `specs/todo/TEMPORAL-MASTER.md`

**Decision in one line**: make the rule-validity axis load-bearing
**in-language** — a `RULES EFFECTIVE DATE` nullary builtin (reader of
`tcRuleValidTime`) now, an `@effective` same-name-DECIDE desugar later — and
serve encoding-history/commit counterfactuals as **driver-level two-run
comparison tooling**, never as an in-heap `EVAL UNDER COMMIT`.

---

## 1. Reality reconciliation: what is actually on `unstable`

The three stale specs describe the dropped _temporals-2_ vision (git-backed
`EVAL UNDER COMMIT`, a `MonadTemporal` layer, `temporal-prelude.l4` macros).
None of that shipped. What DID ship — and what the three design critiques
partially missed, because they were written against a pre-T6/pre-PR#80 mental
model — is the following.

### 1.1 Shipped and working

| Thing                         | Where                                                                                                                                                                                                                                                                              | Notes                                                                                                                                                                                                                                                                   |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 8-axis `TemporalContext`      | `jl4-core/src/L4/TemporalContext.hs:33-56`                                                                                                                                                                                                                                         | `tcValidTime, tcSystemTime, tcRuleVersionTime, tcRuleValidTime, tcRuleEncodingTime, tcRuleCommit, tcDecisionTime, tcDocumentTimezone`                                                                                                                                   |
| 4 `EvalClause` variants       | `TemporalContext.hs:59-64`                                                                                                                                                                                                                                                         | `UnderValidTime, AsOfSystemTime, UnderRulesEffectiveAt, UnderRulesEncodedAt`; `applyEvalClauses` (83-105) is pure                                                                                                                                                       |
| 4 EVAL mixfix builtins        | registered `TypeCheck/Environment.hs:76-79`, types 303-324; intercepted `Machine.hs:781-804`; frame-1 handlers `Machine.hs:1042-1075`; frame-2 restores `Machine.hs:1192-1203`                                                                                                     | `EVAL AS OF SYSTEM TIME / UNDER VALID TIME / UNDER RULES EFFECTIVE AT / UNDER RULES ENCODED AT`, all `NUMBER(serial) -> a -> a`                                                                                                                                         |
| Interval builtins             | per-day stamps at `Machine.hs:1213,1228,1245,1262` (WHEN LAST/NEXT, EVER/ALWAYS iterate) and `2845-2886` (entry; `VALUE AT` at 2886)                                                                                                                                               | each stepped day re-applies `[UnderValidTime d, UnderRulesEffectiveAt d]`                                                                                                                                                                                               |
| **T6 fingerprint cache**      | `TemporalContext.hs:107-196` (`ReadObs`, `CtxReads`, `validFor`); `Machine.hs:605-646` (`noteCtxRead`, `swapCtxReads`, `readTcSystemTime`, `readTcDocumentTimezone`); `Machine.hs:2968-2971` (`updateThunkToWHNFWhen`); `Machine.hs:2982-3046` (`evalRef` serve/validate/re-force) | a thunk whose force READS a temporal axis is cached as `WHNFWhen fingerprint value` and served only while `validFor` holds; re-forced (with displaced-cache restore) otherwise. Goldens: `jl4/examples/ok/temporal-thunk-leak-*.l4`, `temporal-thunk-sharing-shapes.l4` |
| **Unwind hardening (PR#80)**  | `unwindFrame`, `Machine.hs:356-377`: all four `EvalXxx2` frames + all five iterator frames restore the saved `TemporalContext` on exception; `UpdateThunk` unwind closes the read span and `restoreThunkOnUnwind` (431-448) reinstates displaced caches                            | Goldens: `temporal-exception-scope-restore.l4`, `temporal-whnfwhen-exception-recovery.l4`                                                                                                                                                                               |
| READER CONTRACT               | `TemporalContext.hs:25-32`, `Machine.hs:595-601`                                                                                                                                                                                                                                   | any value-affecting axis read MUST go through an instrumented `readTc*` reader; adding a reader for a latent axis requires a new `CtxReads` field                                                                                                                       |
| Latent-axis sentinel golden   | `jl4/examples/ok/temporal-under-valid-time-latent.l4`                                                                                                                                                                                                                              | LOCKS that `tcValidTime` has no reader; flipping it is a conscious act                                                                                                                                                                                                  |
| Nullary builtin no-cache path | `Machine.hs:3035-3045` (`whnfConfig`), `evalNullaryBuiltin` at 3620-3667                                                                                                                                                                                                           | TODAY/NOW/CURRENTTIME/TIMEZONE re-evaluate per serve, reads recorded into the current span                                                                                                                                                                              |
| Acceptance fixture            | `jl4/examples/ok/temporal-acceptance.l4` + goldens                                                                                                                                                                                                                                 | interval builtins over `daydate`                                                                                                                                                                                                                                        |
| Test harness                  | `jl4/tests/Main.hs`                                                                                                                                                                                                                                                                | pins `JL4_FIXED_NOW` (fallback `2025-01-31T15:45:30Z`), self-sets `JL4_LIBRARY_PATH`; golden suite = `cabal test jl4-test`                                                                                                                                              |

### 1.2 The gap (unchanged)

The rule-version axes are **write-only**. `tcRuleValidTime`,
`tcRuleVersionTime`, `tcRuleEncodingTime`, `tcRuleCommit` are stamped by
`UnderRulesEffectiveAt`/`UnderRulesEncodedAt` (`TemporalContext.hs:92-105`)
and by the per-day iterator stamps, but **no reader exists**; `tcRuleCommit`
is only ever `Nothing`. `EVAL UNDER RULES EFFECTIVE AT` is bookkeeping. There
is no versioned-rule-set store, no git resolution, no selection mechanism.

Known latent bug carried in the stamp: `UnderRulesEffectiveAt` coerces
`tcRuleEncodingTime` to the _target rule day_ when unset
(`TemporalContext.hs:96-103`) — i.e. it fabricates "the encoding existed on
day D". Unobservable today (no reader); must be deleted before any encoding
axis reader ships. **Do not replicate this pattern.**

### 1.3 Critique claims neutralized by the current base

Several kill-shots in the three critiques were written against pre-T6 /
pre-PR#80 assumptions and are **already fixed** on `55bd0452`:

1. _"Taint analysis is unsound / degrades to call-by-name"_ (in-language KS#2,
   hybrid KS#2): superseded. The demanded "context-keyed cache in the Thunk
   type" **is** `WHNFWhen` + `CtxReads` + `validFor`, shipped with goldens.
   No whole-program taint analysis is needed: context-dependence is detected
   **dynamically per force** and fingerprinted per axis. Sharing is preserved
   for everything that does not read the axis (`NotRead` axes never constrain
   reuse).
2. _"Exception unwind leaks the overridden context into subsequent
   directives"_ (hybrid KS#1): fixed by PR#80 — `unwindFrame`
   (`Machine.hs:356-377`) restores the context for every temporal frame, and
   the frame enumeration is exhaustive-by-construction (no wildcard), so a new
   state-restoring frame without an unwind arm is a compile error.
3. _"Cross-module dispatch table stranded in per-module EvalState"_
   (in-language KS#3): mooted by this design — we adopt no runtime dispatch
   table at all (see §3). The dispatcher is ordinary compiled L4 riding the
   `Environment`, which both import paths already thread
   (`jl4-lsp/src/LSP/L4/Rules.hs:593-608`, `jl4-core/src/L4/API.hs:321-331`).

### 1.4 Critique claims that remain true (and shape this design)

1. **WHNF-scope boundary** (in-language KS#1) — **CLOSED 2026-08-03: the pin is
   DEEP.** See §1.4.1 below for the ruling, what it costs, and what boundary
   remains. The original text is kept because §1.4.1 is a decision _about_ it:

   > EVAL frames restore the context when the wrapped thunk reaches WHNF
   > (`Machine.hs:1192-1203`), so lazy substructure (list elements, record
   > fields) escaping the frame is forced later under the _ambient_ context.
   > This is a pre-existing property of all four shipped builtins (TODAY inside
   > `EVAL AS OF SYSTEM TIME` behaves identically today); T6 guarantees the
   > caches stay _sound_ either way — the question is scoping _intent_, not
   > cache corruption. Position: document it; scalar results
   > (NUMBER/BOOLEAN/DATE/STRING) are exact because WHNF = NF for them; a lint
   > for EVAL-wrapping-non-scalar-typed expressions is Phase 1 optional work;
   > a deep-forcing EVAL variant is deferred.

2. **Absence semantics** (in-language KS#4): a versioned rule queried before
   commencement / after repeal needs a story that does not crash interval
   scans. Resolved in §3 Phase 2: the desugar always has a total fallback
   (author's ELSE/base version), and a family without one gets a generated
   "not in force" error arm + a lint. The Phase 0 spike sidesteps it entirely
   (the fallback is "the rules in force now", total by construction).
3. **Amendment-cascade ceiling** (in-language KS#5): signature-changing
   amendments cannot be versioned in place. Accepted boundary, documented:
   v1 versioning covers signature-stable amendments; a signature change is a
   new name (as it is a new legal object). Not solvable by any of the three
   candidates without dependent-typing-adjacent machinery.
4. **Unique instability across compiles / entityInfo singleton / `project:/`
   URI collisions in `Import/Resolution.hs`** (git-backed KS#1, KS#2; hybrid
   KS#4): fatal to any design that splices a _separately compiled_ rule set
   into a live heap. This is the core reason `EVAL UNDER COMMIT` (in-heap) is
   rejected outright, see §2 and §4.
5. **Fallback/default coupling** (hybrid KS#8): what `RULES EFFECTIVE DATE`
   returns when `tcRuleValidTime` is unset couples axes whichever way it is
   decided. Recorded as an explicit Phase 1 decision point (§6 Q1); the spike
   ships the provisional "localized current day" fallback (same computation
   as TODAY), which at least matches "the rules in force now" intuition.

### 1.4.1 RULING: the pin is deep (2026-08-03)

_Status: **implemented** on branch `mengwong/eval-pin-and-shadowing`, rebased on
`origin/unstable` @ `16adc022`. Fixture `jl4/examples/ok/temporal-pin-deep.l4`;
implementation `startDeepPin` / `driveDeepPin` / `snapshotVal` / `snapshotRef`
in `jl4-core/src/L4/EvaluateLazy/Machine.hs`. Resolves
[smucclaw/l4-ide#934](https://github.com/smucclaw/l4-ide/issues/934) **for
functional values only** — see the four boundaries below, of which the
regulative one is open and material. Adversarially re-measured 2026-08-03
against a second pair of full-tree sweeps (base `16adc022` binary vs this
branch, `l4 run` over all 725 shared `.l4` files)._

**The defect, measured.** With the WHNF boundary as shipped, these two answer
differently, with no visible reason in the source and no diagnostic — the
second is the wrong legal regime:

    #EVAL EVAL UNDER RULES EFFECTIVE AT (Date 1 6 2023) GST rate         -- 7
    #EVAL EVAL UNDER RULES EFFECTIVE AT (Date 1 6 2023) (JUST GST rate)  -- JUST OF 9

§1.4's "Position: document it" underrated this. It is not a scoping-intent
nicety, and it bites precisely the shapes that carry real work: a record of
computed fields, a `MAYBE` built in a `CONSIDER` arm, a list of assessments.
The corpus is temporally closed across the 2017-04-12 Reg CF cliff and the
whole law-time axis rests on this pin; anything that composes `EVAL UNDER`
programmatically (batch harnesses, test generators, the §8 de novo diff
oracle) naturally builds the wrapping shape rather than the working one.

**The ruling.** `EVAL UNDER RULES EFFECTIVE AT`, its three sibling EVAL clause
builtins (`AS OF SYSTEM TIME`, `UNDER VALID TIME`, `UNDER RULES ENCODED AT`)
and `VALUE AT` now mean "the value of the argument, computed under this
context" rather than "the outermost constructor of the argument". The other
interval builtins need no change: EVER/ALWAYS BETWEEN and WHEN LAST/NEXT
demand a BOOLEAN or DATE from their predicate, for which WHNF is already
normal form.

**Forcing alone does not implement that, and this is the load-bearing
finding.** The obvious fix — deep-force the result under the pin — was
implemented first and measured to change nothing: the control still answered
`JUST OF 9`. A child reference of a pinned result is normally the _shared_
module-level thunk, because `allocate_` short-circuits a `Var` argument to
`expectTerm` instead of minting a fresh one. Forcing it under the pin installs
a `WHNFWhen` cache fingerprinted on the pinned axes; when the printer forces
it again after the context is restored, T6's `validFor` correctly rejects that
cache and re-forces under the ambient context. T6 is doing exactly its job.
**The value has to leave the scope, not merely be forced inside it.**

So the pin runs two passes, both under the pinned context:

1. **Force** every reachable child — an explicit worklist over the frame
   stack, de-duplicated by `Address`, to the same `maximumStackSize` (200)
   depth budget the printer uses.
2. **Snapshot** — rebuild the result with every reachable reference replaced
   by a _fresh_ reference holding a plain `WHNF`: a context-independent,
   final cache that nothing will ever re-derive. Originals are never mutated,
   so the rest of the program keeps its sharing and its own
   context-sensitivity. Pass 2 forces nothing (pass 1 already did), so it is
   ordinary monadic recursion rather than more frames, and can carry a memo
   keyed by `Address` — seeded with a placeholder before recursing, which is
   what makes a cycle in the pinned value terminate as a cycle in the
   snapshot.

Reachability is `Foldable` on `Value`, which is exactly what
`L4.EvaluateLazy.nfAux` traverses. Defining it by reference rather than
re-deriving it keeps one invariant worth stating plainly: **the pin covers
exactly the part of the value the evaluator prints.**

**Why this over the alternatives** (#934 offered three):

- _(a) Lexical capture — the pin travels with the thunk._ Rejected on
  measurement, not taste. Capture at allocation cannot fix the reported case
  at all, for the `allocate_` reason above: nothing is allocated under the pin,
  so there is nothing to stamp. Making capture work needs stamped _copies_ of
  the children — which is what pass 2 does, arrived at from the other end. A
  blunter "every thunk captures the ambient context" additionally contradicts
  shipped T6 semantics: `temporal-thunk-leak-basic.l4` case 2 requires a
  module-level thunk forced ambiently first to _re-evaluate_ under a later
  override, which capture would forbid.
- _(c) A diagnostic on lazily-escaping values._ It tells an author the answer
  may be wrong without making it right, and the honest static approximation —
  §6 Q4's "warn when an EVAL builtin wraps a non-scalar-typed expression" —
  fires on the common, legitimate case of pinning a record. Still available as
  a lint if the strictness cost below ever bites; not a substitute for a fix.

**What it costs.**

- _Strictness._ `EVAL UNDER` is now strict in the whole printed structure of
  its argument, so an error or a divergence hiding in a field the consumer
  never demands becomes reachable. Bounded by the printer's own depth budget,
  and by the visited-`Address` set, which makes the walk strictly tighter than
  the printer's (shared and cyclic structure is visited once per reference
  rather than re-expanded per path).

  Measured 2026-08-03, so the shape is on the record rather than left as a
  hedge. `Box good bad` with `bad MEANS 1 DIVIDED BY 0`, pinned, consumer reads
  only `good`: base `16adc022` prints `42` and exits 0, this branch prints
  `Division by zero` and exits 1. With `bad` replaced by a non-terminating
  recursion: base prints `7` and exits 0, this branch **does not terminate**
  (`timeout 45` → exit 124). So the honest statement is not "an error becomes
  reachable" but "a terminating program can become a non-terminating one" —
  the price of making the pin mean what it says. Nothing in the tree pays it
  (see the sweep below), and the §6 Q4 lint stays available if that changes.

- _Allocation._ One fresh reference per reachable reference of a pinned
  result, once, at the pin boundary.
- Measured on this tree: the full suite is unchanged apart from the two new
  fixtures. Re-measured adversarially by a whole-tree `l4 run` sweep (all 725
  `.l4` files present on both sides, base binary vs branch binary, outputs
  diffed): **no file's evaluated output changes.** Six files differ, five of
  which (`fetch-uuid`, `post-with-json`, `test-post`, `test-post-headers`,
  `thailand-cosmetics/orchestrator`) make live HTTP calls and differ in UUIDs
  and AWS trace ids between any two runs; the sixth is the #930 file, below.

**Four boundaries. Three are deliberate; the fourth is the ruling's real
limit.**

- **Closures** are opaque to both passes, exactly as they are to `nfAux`. A
  function returned from under a pin still reads the _ambient_ context when it
  is later applied: a pin cannot follow a value into a scope it does not
  dominate, and the working idiom is to apply inside the pin. Asserted as a
  live expectation rather than left to prose — `temporal-pin-deep.l4` case I
  pins a closure, applies it outside, and asserts the ambient 9, so if a later
  change makes closures pin-aware that golden moves and the decision gets
  re-taken on purpose.

  **Sharpened 2026-08-03**: case I pins a _bare_ closure, where the escape is
  at least legible at the pin site. Put the closure in a record FIELD and the
  pin site returns a _data_ value, with nothing in the source to say one field
  is still context-live — and the fix then makes the symptom harder to see,
  not easier. Measured on `Calc rate apply` pinned to 2023-06-01:

  | field                   | base `16adc022` | this branch |
  | ----------------------- | --------------- | ----------- |
  | `rate` (NUMBER)         | 9               | **7**       |
  | `apply` applied outside | 900             | 900         |

  Pre-fix the record was uniformly ambient: wrong, but internally consistent.
  Post-fix one record answers 7 and 900 at the same time, with no diagnostic.
  Asserted as case J so a future closure-capture change moves that golden.

- **Regulative values are not pinned at all** — not the followups, not even the
  first obligation's own deadline. This is the boundary that matters most in
  practice, because the corpus's law-time axis is deontic, and it is stated
  here as an open limitation rather than a design choice.

  Structural reason: `ValObligation`'s party and due are
  `Either RExpr (Value a)` and its `HENCE`/`LEST` followups are bare `RExpr`
  closed over an `Environment` (`jl4-core/src/L4/Evaluate/ValueLazy.hs:60`).
  `Foldable` on `Value` — the pin's reachability relation, and `nfAux`'s —
  reaches nothing in a freshly built obligation, where every one of those
  fields is still `Left rexpr`. The contract stepper evaluates them later,
  ambiently. Note what this does to the invariant above: "the pin covers
  exactly the part of the value the evaluator prints" remains true, but for an
  obligation the printer prints the deadline's unevaluated _source_
  (`WITHIN window`), so covering what it prints covers nothing that matters.

  Measured 2026-08-03, `window` = 30 under rules effective before 2024-01-01
  and 10 on or after, ambient clock 2025: `EVAL UNDER RULES EFFECTIVE AT
(Date 1 6 2023) duty` breaches an event at t=20 against deadline **10**, and
  its `HENCE` continuation against **11** — both the ambient answer, and both
  byte-identical on base `16adc022` and on this branch. Asserted as case K.

  Fixing it is not a rider on this change. It needs the pinned
  `TemporalContext` carried into the obligation's `Environment` (or a pinned-
  contract wrapper) and re-installed at every stepper site that evaluates a
  deadline or a followup — i.e. option (a) capture, scoped to regulative
  values — and it first needs a semantic ruling this document does not have:
  whether a contract pinned at trace start stays pinned across a multi-day
  trace whose own events carry timestamps. Tracked on #934's thread.

- **A back-edge** into a force we are still inside (a self-referential value
  whose recursion runs _through_ the pin) is skipped rather than forced. The
  first implementation did force it, and turned a program that printed a
  truncated list into one that raised "Infinite loop detected"; the deep pin
  must not do that. Verified 2026-08-03 to be sound as well as non-crashing:
  `xs MEANS EVAL UNDER … (GST rate FOLLOWED BY xs)` prints 200 sevens and no
  nines, because the skipped back-edge resolves to the pinned thunk itself,
  whose write-back is the snapshot.

- **Beyond the depth budget** the original reference is kept — exactly where
  the printer would have printed `…` anyway. Verified 2026-08-03 rather than
  assumed: a 300-element list of `GST rate` pinned to 2023-06-01 prints exactly
  200 sevens then `...`, with zero nines, and every consumer of a value goes
  through `NF` (`Print.hs`, `API.hs`, `ValueLazyJSON.hs`,
  `jl4-service/src/Backend/Jl4.hs`), which `nfAux` truncates at the same 200.
  So the budget boundary is unobservable, not merely tolerable.

---

## 2. The three candidates and why they fell

Full designs + adversarial critiques live in the session record; this section
preserves the load-bearing kill-shots.

### 2.1 Git-backed (compile snapshot per commit, splice References by RawName at EVAL entry)

REJECTED as the axis mechanism. Fatal, code-verified:

- **Unique disjointness is false on the proposed pipeline**: imports resolve
  through `moduleNameToProjectUri` → `project:/<name>.l4`
  (`jl4-core/src/L4/Import/Resolution.hs:97-99`), so two snapshots collide on
  URIs and unique supplies → silent wrong-type dispatch in pattern matches.
- **Cross-version values break both directions**: single caller-side
  `entityInfo` can't describe historical constructors; scalars-only guard
  reduces the feature to a demo.
- **Axis inert where load-bearing**: per-day re-stamps in interval builtins
  (`Machine.hs:1213-1262, 2845-2886`) would mean ~10k git resolutions for a
  30-year `WHEN LAST`, so the design pins them to bookkeeping — the canonical
  "rate changed mid-period" case is exactly what it then cannot serve.
- **Nested EVAL emits false provenance** (inner rebinding silently no-ops but
  stamps the inner sha); **config-gated semantic fork** (same document means
  different things per deployment); **mutable git refs** undermine the audit
  claim; **opm2l4 cannot emit it**; **anti-isomorphic for lawyers** (the
  document no longer contains its own semantics).

Salvaged: git snapshot _loading_ survives as Phase 3 driver tooling — two
fully separate evaluator runs compared at the JSON boundary. Nothing crosses
a heap.

### 2.2 In-language (VERSION arms → hidden bindings + runtime ValVersionDispatch + EvalState table)

SKELETON ACCEPTED, mechanism corrected. The critique's fatal findings and
their resolutions:

- _Laziness escapes the WHNF-scoped frame_ → true but pre-existing and
  cache-sound under T6; documented boundary (§1.4.1).
- _Taint analysis contradiction_ → dissolved by T6 (§1.3.1).
- _`ruleVersions` table stranded in per-module EvalState; both import paths
  thread only `Environment`_ → resolved by **not having a runtime table**:
  desugar to ordinary L4 at check time (§3 Phase 2). The dispatcher travels
  in the Environment like any other compiled code.
- _`NoRuleVersionInForce` poisons interval scans_ → total-dispatch requirement
  (§1.4.2).
- _Append-only discipline is unenforceable in-compiler_ → accepted: source
  history lives in ordinary git on the `.l4` file like all other source; the
  trace cites arm labels + source ranges; tamper-evidence beyond that is
  Phase 3's job (deployment-version pinning), not the evaluator's.

### 2.3 Hybrid (A: in-language validity axis; B: RuleVersionStore + EVAL UNDER COMMIT by-name foreign invocation)

**Part A adopted** — it is the same recommendation as 2.2's salvage, and its
two "must exist first" mechanisms (context-keyed cache, unwind restore)
already exist on this base (§1.3). **Part B rejected as designed**: cross-
version constructor values _silently select wrong CONSIDER branches_
(`sameResolved` mismatch falls through to the next branch — worse than
error); the current-compiler confound makes "audit-grade replay" a false
claim for any commit predating a semantics change; shared store races with
per-request contexts in jl4-service; git SHAs are the wrong key for a service
that already versions deployments (`2b28074e`). Part B's _goal_ ("decision
changed since version X") is served by Phase 3 tooling instead.

---

## 3. Recommendation and rationale

**Adopt: in-language rule-validity dispatch on `tcRuleValidTime`, with
encoding-history counterfactuals as out-of-evaluator driver tooling.**
Concretely:

1. **Phase 0 (spike, ~1 day)** — `RULES EFFECTIVE DATE`, a nullary DATE
   builtin reading `tcRuleValidTime` through a new instrumented
   `readTcRuleValidTime`, with a new `crRuleValidTime` fingerprint axis.
   This makes the axis genuinely load-bearing: the stamps already written by
   `EVAL UNDER RULES EFFECTIVE AT` and by every per-day iterator step finally
   have a reader, and T6 makes every dependent thunk cache-correct with zero
   new analysis. Versioning becomes expressible today as ordinary L4
   (`IF RULES EFFECTIVE DATE AT LEAST ... THEN new ELSE old`).
2. **Phase 1 (~1 week)** — semantics hardening: finalize the unset-axis
   fallback (§6 Q1), delete the `tcRuleEncodingTime` coercion bug, add
   `RETROACTIVE TO` sugar, provenance/trace polish, docs + l4-skill note.
3. **Phase 2 (~2-3 weeks)** — authoring ergonomics: `@effective` /
   `@repealed` decorators on _same-named_ DECIDEs, desugared at check time
   into one visible dispatcher over `RULES EFFECTIVE DATE` whose arms are the
   original, individually-addressable, individually-cited DECIDEs. No runtime
   dispatch value, no EvalState table, no hidden name mangling in the
   evaluator.
4. **Phase 3 (~1-2 weeks)** — encoding history _outside_ the evaluator:
   `l4 diff-eval` (CLI) and a jl4-service compare endpoint that compile and
   run two corpus versions as two independent evaluations and diff
   JSON-marshalled results of exported entry points. Keyed on jl4-service
   deployment versions, with git refs as one optional backing resolver.
   Honest framing: _source-level counterfactual under today's toolchain_.
5. **Rejected permanently (recorded)**: in-heap `EVAL UNDER COMMIT` — i.e.
   any mechanism that splices a separately-compiled module's References,
   constructors, or entityInfo into a live evaluation.

### Why this wins, grounded in the critiques

- **It is the convergent verdict of all three adversarial critiques.** The
  git-backed critique's salvage is "make effectivity in-language (S1) + keep
  git out of the heap as driver-level diff-eval". The in-language critique's
  verdict is "the skeleton is right; ship S1 now regardless". The hybrid
  critique's verdict is "the axis split is the right cut; Part A is close to
  viable; demote Part B". No critique defends any in-heap cross-version
  mechanism.
- **The expensive preconditions are already paid for.** The two mechanisms the
  critiques demanded before any reader ships — a context-keyed thunk cache
  and exception-time context restore — are shipped, golden-locked machinery
  on this exact base (T6 `WHNFWhen`, PR#80 `unwindFrame`). The marginal cost
  of the axis reader collapses from "evaluator surgery" to ~60 lines
  following an existing, documented contract (the READER CONTRACT even names
  this exact procedure).
- **Determinism and hermeticity.** Same source + same `TemporalContext` ⇒ same
  answer, in every driver (CLI, LSP, WASM, websessions, service), offline,
  with no repo convention, no resolver config, no deployment-dependent
  meaning for a published construct. This is the property the git-backed
  design could not offer and the one L4's pitch (deterministic, reproducible,
  isomorphic law) cannot trade away.
- **Isomorphism for lawyers.** Statutes carry their amendment history in the
  text; a consolidated rule with dated arms (Phase 2) — or even the v1 IF
  form — keeps both regimes visible, reviewable, diffable, and citable in the
  artifact under review. The trace cites the arm (label + source range) that
  fired and why.
- **The interval builtins work _for free_, correctly.** They already stamp
  `UnderRulesEffectiveAt d` per stepped day; with a reader, `VALUE AT` /
  `EVER BETWEEN` / `WHEN LAST` naturally compute the point-in-time reading
  ("under the rules in force each day") — the canonical rate-changed-
  mid-period case the git design had to pin to a no-op. Regime _pinning_ is
  already expressible compositionally, because nested EVAL wins innermost:
  `EVER BETWEEN a b (GIVEN d YIELD EVAL UNDER RULES EFFECTIVE AT <pin> OF pred d)`.
- **opm2l4 can target it.** OPM-style temporal rule versions are in-source
  attributes; only in-language dispatch is emittable by a code generator.
  (Caveat recorded: OPM _temporal attribute values_ are valid-time facts and
  must map to `tcValidTime`/interval machinery, NOT to rule regimes — the
  hybrid critique's category-error warning stands as a codegen review item.)
- **What it honestly does not do** (and where that lives instead): belief
  history / "what did our encoding conclude last March" (Phase 3 tooling);
  tamper-evidence stronger than source control + deployment versioning
  (Phase 3); signature-changing amendments (new name, documented boundary);
  NF-deep temporal scoping (documented; possible future EVAL variant).

---

## 4. Phased implementation plan (file:line insertion points, verified on 55bd0452)

### Phase 0 — spike: make `tcRuleValidTime` load-bearing (~1 day)

See §5 for the full spike spec. Summary of touch points:

| #   | File                                                        | Point                   | Change                                                                                                                                                                                            |
| --- | ----------------------------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `jl4-core/src/L4/Evaluate/ValueLazy.hs`                     | :88-92                  | add `NullaryRulesEffectiveDate` to `NullaryBuiltinFun`                                                                                                                                            |
| 2   | `jl4-core/src/L4/Evaluate/ValueLazy.hs`                     | :189-194                | `rnf NullaryRulesEffectiveDate = ()`                                                                                                                                                              |
| 3   | `jl4-core/src/L4/TemporalContext.hs`                        | :142-161                | add `crRuleValidTime :: !(ReadObs (Maybe Day))` to `CtxReads`                                                                                                                                     |
| 4   | `jl4-core/src/L4/TemporalContext.hs`                        | :163-171                | extend `Semigroup`, `noReads`                                                                                                                                                                     |
| 5   | `jl4-core/src/L4/TemporalContext.hs`                        | :187-196                | `validFor`: `&& axisValid tc.tcRuleValidTime r.crRuleValidTime`                                                                                                                                   |
| 6   | `jl4-core/src/L4/TemporalContext.hs`                        | :40-43, :114-117        | comments: `tcRuleValidTime` no longer latent; iterator-sharing note now qualified                                                                                                                 |
| 7   | `jl4-core/src/L4/EvaluateLazy/Machine.hs`                   | after :646              | `readTcRuleValidTime` instrumented reader (mirrors `readTcDocumentTimezone`, records the raw `Maybe` pre-fallback)                                                                                |
| 8   | `jl4-core/src/L4/EvaluateLazy/Machine.hs`                   | :3620-3667              | `evalNullaryBuiltin` case: `Just d -> ValDate d`; `Nothing ->` localized-today fallback (reuses `readTcSystemTime` + `readTcDocumentTimezone`, so the fallback is itself correctly fingerprinted) |
| 9   | `jl4-core/src/L4/EvaluateLazy/Machine.hs`                   | :3463-3465              | `rulesEffectiveDateRef <- allocateValue (ValNullaryBuiltinFun NullaryRulesEffectiveDate)`                                                                                                         |
| 10  | `jl4-core/src/L4/EvaluateLazy/Machine.hs`                   | :3527-3529              | `, (TypeCheck.rulesEffectiveDateUnique, rulesEffectiveDateRef)`                                                                                                                                   |
| 11  | `jl4-core/src/L4/TypeCheck/Environment.hs`                  | mkBuiltins list (:19-…) | append `"rulesEffectiveDate" \`rename\` "RULES EFFECTIVE DATE"` **at the end of the list** (mkBuiltins mints uniques positionally; appending keeps existing unique ints stable)                   |
| 12  | `jl4-core/src/L4/TypeCheck/Environment.hs`                  | :257-258                | `rulesEffectiveDateBuiltin = date` (clone of `todayBuiltin`)                                                                                                                                      |
| 13  | `jl4-core/src/L4/TypeCheck/Environment.hs`                  | :659-663                | `rulesEffectiveDateInfo = KnownTerm rulesEffectiveDateBuiltin Computable`                                                                                                                         |
| 14  | `jl4-core/src/L4/TypeCheck/Environment.hs`                  | :938-939                | `, (rawName rulesEffectiveDateName, [rulesEffectiveDateUnique])`                                                                                                                                  |
| 15  | `jl4-core/src/L4/TypeCheck/Environment.hs`                  | :1054-1055              | `, (rulesEffectiveDateUnique, (rulesEffectiveDateName, rulesEffectiveDateInfo))`                                                                                                                  |
| 16  | `jl4/examples/ok/temporal-rule-version-spike.l4`            | new                     | fixture (§5.3)                                                                                                                                                                                    |
| 17  | `jl4/examples/ok/tests/temporal-rule-version-spike*.golden` | auto                    | created by first `cabal test jl4-test` run (hspec-golden); inspect before committing                                                                                                              |

Explicit non-changes: `EvalClause` untouched (4 variants); `applyEvalClauses`
untouched; EVAL frame handlers untouched; interval-builtin stamps untouched;
`temporal-under-valid-time-latent.l4` golden untouched (we add **no**
`tcValidTime` reader). Existing goldens should be bit-for-bit stable — nothing
in the corpus calls the new builtin, and `NotRead` axes never constrain cache
reuse.

### Phase 1 — semantics hardening (~1 week)

1. **Fallback decision** (§6 Q1) — ✅ **DONE (option (b), 2026-07-08)**. Added
   `crValidTime` to `CtxReads`, instrumented `readTcValidTime`, made
   `RULES EFFECTIVE DATE` fall back rule-version → fact-time → localized-today,
   and consciously re-blessed `temporal-under-valid-time-latent.l4` (values
   unchanged; header updated to note the axis is no longer fully latent).
   New fixture `temporal-rule-version-validtime.l4`. Shipped in the same
   branch as the Phase-0 spike.
2. **Delete the encoding-time coercion**: remove the `tcRuleEncodingTime`
   fabrication from `UnderRulesEffectiveAt` (`TemporalContext.hs:96-103`).
   Unobservable today (no reader) ⇒ goldens silent; re-bless
   `temporal-acceptance` if trace output shifts.
3. **`RETROACTIVE TO` sugar**: register `evalRetroactiveTo`
   (`DATE -> a -> a`; the four EVAL builtins moved from `NUMBER` serials
   to `DATE` arguments 2026-07-29) beside the four EVAL builtins
   (`TypeCheck/Environment.hs:76-79` block + type + info + tables); its
   interception arm (`Machine.hs:781-804` pattern) pushes the
   `AsOfSystemTime` and `UnderRulesEffectiveAt` frames nested — no new
   `EvalClause` variant, no parser work. Semantics: old rules + knowledge
   frozen at d.
4. **Provenance polish**: extend the existing `EvalUnderRulesEffectiveAt1`
   handler (`Machine.hs:1058-1065`) to emit a trace action recording the
   stamped day, so `#TRACE` / service traces can say "computed under rules
   effective 2023-06-01". (The IF-dispatch itself is already visible in
   ordinary traces with source ranges.)
5. **Docs**: l4 skill + language reference: the WHNF-scope boundary
   (§1.4.1), the pinning idiom, `UNDER RULES ENCODED AT` explicitly
   documented as bookkeeping-only (consider a typecheck warning on use, to
   preempt the working-sibling illusion — in-language critique KS#6).

### Phase 2 — `@effective` authoring surface (~2-3 weeks)

Goal: the legislative authoring style — _same-named_ DECIDEs, each carrying
its amendment identity — without runtime machinery.

1. **Decorators**: extend the annotation recognizer
   (`jl4-core/src/L4/Parser/ResolveAnnotation.hs:723-729`, currently
   `export/default/nonexhaustive`) with `@effective YYYY-MM-DD`,
   `@repealed YYYY-MM-DD`, `@label "text"`. Mind the claiming-order
   subtleties documented near `ResolveAnnotation.hs:602`; add parser goldens.
2. **Family merge**: relax duplicate-name rejection (`AmbiguousTermError`,
   `jl4-core/src/L4/TypeCheck/Types.hs` — resolution seam ~:445 and error
   site ~:609) for the case where all same-name definitions carry
   `@effective` and share a `TypeSig`: desugar at check time into one visible
   dispatcher binding (an ordinary IF-chain over
   `DATE_SERIAL RULES EFFECTIVE DATE`, arms sorted by effective-from
   descending) plus the original definitions as addressable siblings
   (deterministic suffix, marked in `Anno` so presentation seams — LSP
   symbols, exact-print, NLG, ladder — can filter or show them by policy).
3. **Totality/absence**: a family with no versionless base definition gets a
   generated final arm raising a curated user error ("`<name>` not in force
   on <day>"); lint: warn on gaps/overlaps in effective spans; error on
   overlapping identical spans. Pre-commencement interval scans then fail
   loudly _only_ if the scan actually reaches an uncovered day and the author
   provided no base arm — and the fix (add a base arm) is in-language.
4. **Round-trip**: TNR/NLG anchors attach to the _arm_ DECIDEs (each keeps
   its own SrcRange and `@label` with the amending instrument), so amendment
   identity, citations, and diffability survive — this answers the
   hand-rolled-IF-chain ergonomics objection (hybrid KS#9) without hidden
   binders in the evaluator.
5. **Fixtures**: multi-arm family; family called from another module
   (imports Just Work — dispatcher is ordinary code in the Environment);
   `VALUE AT`/`EVER BETWEEN` across a version boundary; pinning idiom;
   pre-commencement error; perf golden for a multi-decade `WHEN LAST` over a
   versioned family (T6 note: `WHNFWhen` is a single-entry cache, so a
   version-reading thunk re-forces per regime change — bounded by regimes ×
   dependent cone, not days, because the fingerprint records `ReadEq (Just d)`
   per _day_… see §6 Q3 for the cache-granularity refinement if this golden
   is slow).

### Phase 3 — encoding-history counterfactuals as driver tooling (~1-2 weeks)

**No evaluator changes.**

1. `l4 diff-eval --entry <exported-name> --args <json> --before <ref> --after <ref>`
   (new module under `jl4/app/L4/Cli/`): resolve each ref to a source tree
   (git `ls-tree`/`cat-file` into the pure VFS —
   `jl4-core/src/L4/API/VirtualFS.hs:66,122` — or a plain directory), run two
   fully independent compile+eval passes via the existing
   `checkWithImports`/`evaluateImports` (`jl4-core/src/L4/API.hs:321-331`),
   invoke the entry point through the existing JSON function-invocation
   marshalling (as used by jl4-service), diff the JSON results. Two heaps,
   two entityInfos, zero cross-version values.
2. jl4-service endpoint comparing two _deployment versions_ (the service
   already persists these — `2b28074e`); git refs are one optional resolver
   behind the same interface, not the identity scheme.
3. Output framing is contractual: "source-level counterfactual under the
   current toolchain" — the report must carry toolchain version + both
   source identities, and a compile failure of an old version is a
   first-class result, not an error to paper over.
4. This, plus ordinary git on the corpus, delivers the dropped spec's
   "decision changed since commit" acceptance scenario without `UNDER COMMIT`.

### Phase 4 — deferred / rejected

- **Deferred**: deep-forcing EVAL variant (NF-scoped temporal clauses);
  `EVAL HISTORY OF`; regime-pinning surface sugar for interval builtins
  (compositional idiom exists); `UNDER RULES ENCODED AT` semantics (needs
  Phase 3 maturity first — and it would key on deployment versions, not
  commits); canonical block `EVAL … DO …` form (lexer collision with the
  `#EVAL` directive, per TEMPORAL-MASTER caution).
- **Rejected, recorded**: in-heap `EVAL UNDER COMMIT` / cross-version
  Reference splicing, per §2.1/§2.3 kill-shots (URI/Unique collisions,
  entityInfo singleton, `sameResolved` silent-mismatch, nested-EVAL false
  provenance, config-gated semantic fork, compiler confound). Any future
  revival must first solve URI namespacing in `Import/Resolution.hs` and
  cross-version value marshalling — treat those as hard gates, not chores.

---

## 5. Phase 0 spike design (full)

**Objective**: prove, on `origin/unstable` @ 55bd0452, that the same predicate
yields different results under two rule-versions selected via
`EVAL UNDER RULES EFFECTIVE AT`, with sound caching across context switches
and correct per-day regime selection inside an interval builtin.

### 5.1 Semantics

`RULES EFFECTIVE DATE : DATE` (nullary builtin, multiword name, referenced in
backticks like any spaced identifier):

- If `tcRuleValidTime = Just d` → `ValDate d`. The read is recorded as
  `crRuleValidTime = ReadEq (Just d)`.
- If unset → **provisional fallback**: the localized current day, computed
  exactly like TODAY (via the already-instrumented `readTcSystemTime` +
  `readTcDocumentTimezone`; requires `TIMEZONE IS`, errors otherwise with a
  message that names both the missing declaration and the
  `EVAL UNDER RULES EFFECTIVE AT` alternative). The unset observation is
  recorded as `crRuleValidTime = ReadEq Nothing` **pre-fallback** (the
  `crDocumentTimezone` pre-defaulting precedent, `TemporalContext.hs:145-147`)
  so a later force under a _set_ axis correctly invalidates the cache.

Cache-correctness is inherited, not built: the reader routes through
`noteCtxRead`, the force span records it, `updateThunkToWHNFWhen` tags the
cache, `validFor` revalidates per serve, `unwindFrame`/`restoreThunkOnUnwind`
handle the exceptional paths. The nullary value itself is never cached
(`whnfConfig`, `Machine.hs:3035-3045`).

### 5.2 Haskell changes

Exactly the 15 code touch points in the Phase 0 table (§4). New code, in
full:

```haskell
-- Machine.hs, after readTcDocumentTimezone (~:647)
-- | Instrumented reader for 'tcRuleValidTime' (see READER CONTRACT).
-- Records the raw 'Maybe' (pre-fallback): a read that falls back to the
-- current day is still an observation of the axis being 'Nothing'.
readTcRuleValidTime :: Eval (Maybe Time.Day)
readTcRuleValidTime = do
  tc <- getTemporalContext
  noteCtxRead noReads { crRuleValidTime = ReadEq tc.tcRuleValidTime }
  pure tc.tcRuleValidTime
```

```haskell
-- Machine.hs, evalNullaryBuiltin (~:3621), new case
NullaryRulesEffectiveDate -> do
  mDay <- readTcRuleValidTime
  case mDay of
    Just d -> pure $ ValDate d
    Nothing -> do
      -- Provisional fallback (see design doc §6 Q1): the rules in force
      -- "now" — the same localized-day computation as TODAY, built from
      -- instrumented reads so the fallback itself is fingerprinted.
      sysTime <- readTcSystemTime
      mTzName <- readTcDocumentTimezone
      case mTzName of
        Just tzName -> do
          mTz <- liftIO $ tryLoadTZ (Text.unpack tzName)
          case mTz of
            Just tz -> pure $ ValDate (localDay (TZ.utcToLocalTimeTZ tz sysTime))
            Nothing -> userException $ UserError $
              "Could not load timezone '" <> tzName <> "' for RULES EFFECTIVE DATE."
        Nothing ->
          userException $ UserError
            "TIMEZONE is not declared. RULES EFFECTIVE DATE (outside an EVAL \
            \UNDER RULES EFFECTIVE AT scope) requires 'TIMEZONE IS \"<IANA \
            \timezone>\"' in your document."
```

`CtxReads` grows one field (order: before `crLedgerOps`); `Semigroup`,
`noReads`, `validFor` extend mechanically. `mkBuiltins` gains
`"rulesEffectiveDate" `rename` "RULES EFFECTIVE DATE"` at the **end** of the
list (positional unique minting; appending keeps existing builtin unique ints
stable — if any golden churns anyway, that is a signal something serializes
uniques and must be investigated, not blessed).

### 5.3 Fixture — `jl4/examples/ok/temporal-rule-version-spike.l4`

```l4
-- Spike: the rule-version axis (tcRuleValidTime) becomes load-bearing.
-- `RULES EFFECTIVE DATE` reads the axis that `EVAL UNDER RULES EFFECTIVE AT`
-- stamps (and that the interval builtins re-stamp per stepped day), so the
-- same predicate yields different answers under two rule regimes.
-- Harness clock: JL4_FIXED_NOW = 2025-01-31T15:45:30Z, so the ambient
-- fallback day is 2025-01-31 (post-amendment regime).

IMPORT prelude
IMPORT daydate

TIMEZONE IS "Etc/UTC"

-- GST rose from 7 to 9 effective 2024-01-01: one consolidated rule,
-- in-language effectivity dispatch (Phase 2 sugars this into @effective arms)
`GST rate` MEANS
  IF DATE_SERIAL `RULES EFFECTIVE DATE` AT LEAST DATE_SERIAL (Date 1 1 2024)
  THEN 9
  ELSE 7

GIVEN amount IS A NUMBER
GIVETH A NUMBER
`GST payable on` amount MEANS (amount TIMES `GST rate`) DIVIDED BY 100

-- expected: 7 (pre-amendment regime)
#EVAL `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2023)) `GST rate`

-- expected: 9 (post-amendment; same shared thunk — the WHNFWhen fingerprint
-- on crRuleValidTime invalidates the 2023-regime cache)
#EVAL `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 7 2024)) `GST rate`

-- expected: 7 (cache correctness in the reverse direction)
#EVAL `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2023)) `GST rate`

-- expected: 9 (ambient: unset axis falls back to harness "today" 2025-01-31)
#EVAL `GST rate`

-- expected: 70 then 90 (dispatch composes through dependent rules)
#EVAL `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2023)) (`GST payable on` 1000)
#EVAL `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 7 2024)) (`GST payable on` 1000)

-- expected: 7 then 9 (interval builtins stamp the axis per day, so VALUE AT
-- selects the regime in force on the given day — the point-in-time reading)
#EVAL `VALUE AT` (Date 1 6 2023) (GIVEN d YIELD `GST rate`)
#EVAL `VALUE AT` (Date 1 7 2024) (GIVEN d YIELD `GST rate`)
```

### 5.4 Build, test, and manual proof

```sh
cd ~/src/legalese/l4wt/temporal-rule-version
cabal build jl4-core l4                          # compile the change
cabal test jl4-test                              # full golden suite;
                                                 # harness pins JL4_FIXED_NOW and
                                                 # self-sets JL4_LIBRARY_PATH
# focused re-run while iterating:
cabal test jl4-test --test-options='--match "temporal-rule-version-spike"'
# manual eyeball proof:
JL4_FIXED_NOW=2025-01-31T15:45:30Z cabal run l4 -- run jl4/examples/ok/temporal-rule-version-spike.l4
```

First `cabal test jl4-test` run auto-creates
`jl4/examples/ok/tests/temporal-rule-version-spike.golden` (plus `.nlg` /
`.ep` / `.schema` siblings); inspect them against §5.5 before committing.
Every _other_ golden must be bit-identical.

### 5.5 Expected before/after

**Before (unmodified 55bd0452)**: the fixture does not typecheck —
`` `RULES EFFECTIVE DATE` `` is an unknown identifier. The axis is
demonstrably write-only: any predicate wrapped in
`EVAL UNDER RULES EFFECTIVE AT (…2023…)` vs `(…2024…)` evaluates
_identically_ (e.g. a TODAY-based dispatch yields 9 under both clauses with
the pinned clock), because nothing reads `tcRuleValidTime`.

**After**: the eight directives evaluate, in order, to

```
7
9
7
9
70
90
7
9
```

i.e. `Evaluation successful`, per-directive results in the golden as
`temporal-rule-version-spike.l4:<line>:<cols>:` followed by the value —
proving the same predicate (`GST rate`, one shared 0-arg thunk) yields
different results under two rule-versions, flips back correctly (cache
soundness), composes through a dependent rule, and is regime-selected per-day
by an interval builtin.

### 5.6 Spike acceptance checklist

- [ ] fixture golden matches §5.5, all pre-existing goldens bit-identical
- [ ] `temporal-under-valid-time-latent.golden` untouched (no `tcValidTime`
      reader was added)
- [ ] directive 3 (7 after 9) actually re-forces — sanity-check by hand that
      the value is not a stale 9 (this is the T6 revalidation at work)
- [ ] `cabal build` warning-clean (`-Wincomplete-patterns` will catch any
      missed `NullaryBuiltinFun` match arm)

---

## 6. Open questions (with recorded leanings)

- **Q1 — unset-axis fallback** (Phase 1 gate). Options: (a) localized
  system-day ("the rules in force now" — spike's provisional choice; couples
  `AS OF SYSTEM TIME` to regime, which is arguably the _right_ replay
  intuition: knowledge frozen at t ⇒ regime of t); (b) `tcValidTime` first,
  then system-day (bitemporally orthodox, and _consistent with the interval
  builtins_, which hard-code regime = fact-day; requires `crValidTime`
  instrumentation + consciously flipping the latent-axis golden); (c) hard
  error (maximally explicit; hostile to the common "evaluate current law"
  case). **DECIDED (2026-07-08): (b).** Rationale: it is the only option
  consistent with the interval builtins (which already stamp
  `[UnderValidTime d, UnderRulesEffectiveAt d]` together per day), and it
  encodes the presumption against retroactivity (apply the law in force at
  the time of the facts); it couples the _right_ pair of axes (fact-time ↔
  law-time, overridable), leaving system/knowledge time independent, whereas
  (a) couples system-time to regime. **Implemented**: `crValidTime` axis in
  `CtxReads` + instrumented `readTcValidTime`; `RULES EFFECTIVE DATE` falls
  back rule-version → fact-time → localized-today. Fixture
  `jl4/examples/ok/temporal-rule-version-validtime.l4` (7/9/7/9) locks it; the
  latent golden was re-blessed (values unchanged — `TODAY` stays independent
  of valid-time). Suite green (1087/0).
- **Q2 — `tcRuleVersionTime` vs `tcRuleValidTime`**: currently both stamped
  identically by `UnderRulesEffectiveAt`. Either collapse the two fields or
  define a real distinction (e.g. version-label selection vs date
  effectivity) in Phase 2. Leaning: collapse; resurrect only with a concrete
  reader.
- **Q3 — cache granularity under day-stepping**: `WHNFWhen` records
  `crRuleValidTime = ReadEq (Just d)` per _day_, so a version-reading thunk
  re-forces every stepped day even within one regime. Correct but
  potentially slow for multi-decade scans over heavy rules. If the Phase 2
  perf golden hurts, refine the observation to the _selected regime boundary
  interval_ rather than the raw day (an `ReadObs` variant recording
  "in [from,until)") — a contained `TemporalContext.hs` + reader change.
- **Q4 — WHNF-scope boundary surfacing**: lint when an EVAL temporal builtin
  wraps an expression whose type is not scalar? (Cheap, high-signal;
  Phase 1 optional.)
- **Q5 — `UNDER RULES ENCODED AT` disposition**: keep parsing + stamping but
  warn on use ("bookkeeping only; see l4 diff-eval"), or hard-deprecate until
  Phase 3 gives it a real meaning keyed on deployment versions. Leaning:
  warn.

---

## 7. Cross-references

- Shipped machinery: `jl4-core/src/L4/TemporalContext.hs`,
  `jl4-core/src/L4/EvaluateLazy/Machine.hs` (frames :182-192, unwind
  :356-377, readers :605-646, interception :781-804, handlers :1042-1075 /
  :1192-1203, per-day stamps :1213-1262 / :2845-2886, evalRef :2982-3046,
  nullary :3620-3667, initialEnvironment :3454-3573),
  `jl4-core/src/L4/TypeCheck/Environment.hs` (:19 mkBuiltins, :60-79 renames,
  :257-324 types, :659-702 infos, :938-1009 name table, :1054-1121 unique
  table).
- Goldens locking current semantics: `jl4/examples/ok/temporal-*.l4` and
  `jl4/examples/ok/tests/temporal-*.golden`.
- Dropped temporals-2 material (reference only):
  `git show 8a7d3065:doc/todo/TEMPORAL_EVAL_SPEC.md`,
  `git show 8a7d3065:jl4-core/libraries/temporal-prelude.l4`,
  resurrectable frame-pair wiring in commit `273a60d7`.
- Related initiatives: STATE-AS-LEDGER (`crLedgerOps` interaction is already
  handled by T6's poison bit), jl4-service deployment versioning
  (`2b28074e`, the Phase 3 version key), TNR/NLG round-trip (Phase 2 anchor
  preservation), opm2l4 (Phase 2 codegen consumer; valid-time vs rule-time
  mapping review required).
