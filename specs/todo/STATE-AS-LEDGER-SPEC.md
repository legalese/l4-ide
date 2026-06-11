# Specification: State as an Event-Sourced Ledger

**Status:** 🎨 Design exploration / pre-implementation (June 2026)
**Audience:** A Claude Code agent (or human contributor) who will turn this into a frozen spec and an implementation plan.
**Companion docs:**
- `IMPLICIT-PROPS-DESIGN.md` (the **`props` / Reader** half — implicit context flowing *down* the call graph)
- `paper/l4-icail.tex` §`app:burden` and `jl4-proleg/docs/burden-of-proof.md` (the **burden-of-proof / Writer** monad)
- `RUNTIME-INPUT-STATE-SPEC.md` (the four-state `WithDefault a` and `resolve`)
- `SECTION-LEXICAL-SCOPING-SPEC.md` (`§` scope hierarchy)
- `NEGATION-AS-FAILURE-SPEC.md` (`MAYBE BOOLEAN`, on which the burden truth-dimension rides)

**Timing note:** L4 has effectively zero production users today. This is the moment to fix the core calling convention. Bias toward getting the model *right* over backward compatibility — but note (§8) that the changes here are largely *additive* to the existing evaluator.

---

## 0. The one-paragraph thesis

L4 needs three kinds of implicit threading, and they are exactly Wadler's three monads from *The Essence of Functional Programming* — **Reader, Writer, State**. The `props` design covers Reader (context handed *down*). The burden-of-proof appendix already commits L4's evidential layer to **Writer** — an accumulating *ledger* of who-must-prove-what. The new `RECORD <cell> IS …` direction looks like **State**, but in a domain where **audit is the product**, raw destructive `State` is the wrong primitive: it discards provenance at the moment a value changes — the one thing L4 sells. The claim of this spec is that **State should be implemented as Reader-over-Writer**: the symbol table is a *snapshot projection* over an append-only event ledger. `RECORD` *appends* an event; a bare cell read *reads the latest projection*. This collapses three bespoke effect systems into **one ledger primitive** that the burden monad has already paid the design cost of, gives mutation ergonomics *and* a complete audit trail for free, makes hypothetical/`local` evaluation a log operation rather than an imperative unwind, and rides directly on the deontic state machine the evaluator already threads.

---

## 1. The problem and the example

We want a deontic sequence to record facts that later steps depend on:

```l4
updateEnvExample MEANS
  PARTY Alice
  MAY webSearch "the freezing point of water" AS freezePoint
  HENCE
    RECORD `freezing point of water` IS freezePoint's result
```

Three things are happening, and they should be kept distinct:

1. **A deontic transition.** `PARTY Alice MAY webSearch … HENCE …` is a step in a state machine over obligations/permissions. The evaluator *already* models this: a `Regulative` expression evaluates to a `ValObligation` carrying its captured environment, party, action, deadline, HENCE, and LEST (`jl4-core/src/L4/Evaluate/ValueLazy.hs:57`, produced at `…/EvaluateLazy/Machine.hs:373`).
2. **A local result binding.** `AS freezePoint` binds the *outcome* of the action in the HENCE continuation — ephemeral, lexical, gone when the continuation ends. This is the same `ValEnvironment`-merge that HENCE already does when it binds pattern variables from the matched event (`…/EvaluateLazy/Machine.hs:897-927`).
3. **A durable commit to shared state.** `RECORD <cell> IS …` promotes a value *out* of the local continuation into a record that outlives it and is visible to later steps. This is the new thing.

Only (3) is novel, and it is the dangerous one. The rest of this spec is about getting (3) right.

### Why not just thread `env` as a `GIVEN`

It would be tempting to thread `env` explicitly as a `GIVEN`. That is exactly the **prop-drilling** the `props` design rejects: at the scale L4 targets (thousands of rules, dozens of contextual values) you cannot hand-thread a mutable record through every intermediate rule. The data cell should be **implicit**, threaded by the calling convention like `props` — *consumption inferred*. What stays **explicit** is the *mutation*: the `RECORD`/`COMMIT` write is a visible statement. This is the `props` doc's own rule ("establishment should be visible even if consumption is inferred") and the `unsafePerformIO` principle: the breach of referential transparency is *marked at the point of use*.

> **Decision D1 (surface syntax — locked 2026-06-11).** `env` is implicit (threaded, reads inferred). The only explicit syntax is the *write*:
> - **`RECORD <cell> IS <expr>`** — append to the acting party's *own* ledger (the common case).
> - **`COMMIT <cell> IS <expr>`** — append to the shared *official* record (§8, R1). **`ATTEST`** is an accepted synonym for `COMMIT`.
>
> Reads are **bare** `<cell>` (the IDE supplies provenance via the READS badge); a *cross-party* read uses the genitive, `<party>'s <cell>`. No `:=` — use the `IS` copula, exactly as record construction already does (`Foo WITH field IS value`). No `env's` at the write site; no `GIVEN env`. *Rationale:* an earlier sketch wrote `UPDATE env's X := value` with `env` threaded as a `GIVEN`; D1 drops the prop-drilled `GIVEN`, the imperative `:=` (foreign to L4's register), and the explicit `env's` (which half-contradicts "implicit"). `RECORD`/`COMMIT` also name the append-only semantics honestly — you do not *update* a record, you add to it (D2).

---

## 2. The three threads are one ledger

| Monad | L4 surface | Legal role | Flow | Status today |
|---|---|---|---|---|
| **Reader** | `props` / `TAKING` | the *given circumstances* — jurisdiction, effective date, party attributes | **down** the call graph, scoped by `§` | `props` design; precedent in `TemporalContext` (§3) |
| **Writer** | the burden ledger | the *audit trail* — who must prove what; what was found, by whom, why | **out**, append-only | **implemented**: `MaybeT (Writer [Obligation])`, `jl4-proleg/src/L4/Proleg/Burden.hs` |
| **State** | `env` / `RECORD`·`COMMIT` | the *evolving findings* — facts established mid-process that later steps rely on | **along** the deontic timeline | this spec |

The burden monad is the load-bearing precedent. Its core type is

```haskell
type Provable = MaybeT (Writer [Obligation])   -- ≅ ([Obligation], Maybe a)
data Obligation = Obligation { onWhom :: Subject, what :: Text }
```

— a **truth dimension** (`Maybe`, with `Nothing` = undecided) over an **accumulating ledger** (`Writer [Obligation]`). Read the burden ledger as the general shape and the env ledger falls out by analogy: an env write is *another kind of ledger entry*, carrying not "party P must establish claim C" but "value V was established for cell X, by source S, at trace point T".

```haskell
-- the env ledger entry is the same shape as Obligation, one field richer
data Assignment = Assignment
  { cell       :: Path          -- e.g. `freezing point of water`
  , value      :: Value         -- 273.15
  , provenance :: Provenance    -- webSearch by Alice, at trace point t, ...
  }
type Ledger = [Event]           -- heterogeneous: Obligation | Assignment | DeonticTransition | ...
```

The **current symbol table is a projection** (a fold) over this ledger — last-write-wins per `cell`:

```haskell
snapshot :: Ledger -> Map Path Value          -- "env" as the user sees it
readCell :: Path -> Ledger -> Maybe Value     -- bare cell read X, "as of now"
```

So a bare cell read `X` is *not* a read of a mutable cell; it is `readCell X` over the ledger truncated at the current trace position. `RECORD X IS V` is `tell [Assignment X V prov]`. You get `IS`-copula write ergonomics on the surface, with a complete, ordered, provenance-tagged history underneath — which is precisely the artifact `#TRACE` and the decision service already want to emit.

> **Decision D2.** Do **not** add a primitive mutable `State` cell. Implement `env` as `snapshot` over an append-only `Ledger`. `RECORD`/`COMMIT` = append; a bare cell read = projected read. **(CONFIRMED 2026-06-11 — this is the load-bearing "Rung 3" decision of Appendix A: `RECORD <cell> IS V` compiles to `tellEvent (Assign …)`, not to a store. Everything else follows from it.)**

This is the central claim. Everything below is consequence.

---

## 3. There is already a state machine; `env` rides alongside it

Two facts about the current evaluator make this cheap rather than a rewrite.

**(a) The deontic configuration is already a threaded state.** A regulative rule is already a state transformer: a `ValObligation` is scrutinised against an incoming `(timestamp, events)` stream through the contract frames (`…/EvaluateLazy/ContractFrame.hs:6-53`), and on a match it tail-calls HENCE with a freshly-merged environment, else LEST, else `ValBreached`. `#TRACE` is the operational unrolling of that machine. The env ledger is a *second cell threaded by the same transitions* — it does not need its own scheduler.

**(b) L4 already threads an implicit, locally-rebindable context — and it is a `ReaderT` over an `IORef`.** `TemporalContext` (`jl4-core/src/L4/TemporalContext.hs:18`) lives in `EvalState` (`…/EvaluateLazy.hs:48-59`), is read implicitly through the `Eval` monad (`ExceptT EvalException (ReaderT EvalState IO)`, `…/EvaluateLazy.hs:90`), and is **locally overridden and restored** by `EVAL AS OF SYSTEM TIME` via a save/restore frame (`…/EvaluateLazy/Machine.hs:303-325`). That is a working, shipping precedent for: *implicit threading + scoped `local`-style rebinding*. The env ledger should be added to `EvalState` the same way `evalTrace` already is — an `IORef (DList Event)` appended through a `tellEvent :: Event -> Eval ()` helper modelled on `traceEval` (`…/EvaluateLazy.hs:250-255`).

> **Implication.** `local` (Reader, rebind context for a subtree), `EVAL AS OF SYSTEM TIME` (rebind the clock for a subtree), and the burden monad's `flipBurden` (relabel a sub-derivation's ledger at the exception boundary, `Burden.hs:92`) are **the same operation**: a scoped transformation of the threaded thing, applied and unwound around a subtree, without global mutation. Design them as one mechanism with three instances, not three features.

---

## 4. Reads are "as of now"; writes are events in order

A bare cell read `X` means *the value as of this point in the deontic sequence*. `HENCE` imposes a sequential order, so every program point has a well-defined snapshot, and the write is coherent despite looking destructive: there is no global "value of X", only "X as of trace position *n*". A read before a `RECORD` and a read after it legitimately differ, and the ledger records exactly why and when they diverged.

This is the same move the burden monad makes with its **accumulating** `conj`/`disj` (`Burden.hs:70-79`): conjunction does *not* short-circuit, so every conjunct's obligation is recorded "even if an earlier one fails — the responsibility map is *structural* (it reflects the rule, not the run)." For env: every `RECORD` on a reachable branch is recorded, so the ledger reflects the *process*, not merely its final snapshot.

---

## 5. The initial value of a cell is the presumption (the monoidal identity)

The burden appendix's sharpest result transfers directly. Before any `RECORD`, a cell `X` has a value — its **default** — and that default is not a language convenience but a **constitutional choice**. The appendix calls it the presumption and identifies it as the **monoidal identity**: "the value of a proposition before any evidence is combined in." `Bool` admits two monoids — De Morgan duals — `(∨, False)` (presumption of innocence) and `(∧, True)` (rebuttable presumption of the claim); *same elements, same operation, different unit — different morality* (`burden-of-proof.md` §4.2; tex `tab:presumption`).

This is **the same `Maybe`/default cell** that `RUNTIME-INPUT-STATE-SPEC.md` models as `WithDefault a = Either (Maybe a) (Maybe a)` and collapses with a function also named `resolve`. Three specs, one operation:

| Spec | undecided cell | the default/presumption | collapse |
|---|---|---|---|
| Burden monad | `Provable a` (`Nothing` = unproven) | monoidal identity; `resolve` fixes it to `False` (bearer loses) | `resolve :: Provable a -> Bool` |
| Runtime input state | `WithDefault a` (not-asked / I-don't-know) | `TYPICALLY` value | `resolve :: WithDefault Bool -> TriBool` |
| **Env ledger (this spec)** | cell `X` never written | the cell's declared presumption | `readCell` ∘ snapshot, then a `resolve` |

> **Decision D3.** A cell whose value has never been established reads as **undecided**, not as a runtime error and not as a silent zero. Its `resolve` default is the cell's **declared presumption**. Unify with `WithDefault`/`TYPICALLY` and the burden `resolve` rather than inventing a third "uninitialised" story. `freezePoint`'s result before the search is `NOTHING`; reading the bare cell `X` before it is established yields the presumption.

Concretely: `webSearch` may *fail to establish* the freezing point (network down, ambiguous answer). The cell then stays `NOTHING`, and downstream `resolve` applies the presumption — exactly the burden monad's "the bearer loses if unproven" logic, now over an environment value.

---

## 6. `webSearch` is an oracle, not a function

`MAY webSearch "…" AS freezePoint` crosses from specification into IO, and its result is **non-deterministic input from the world**. The evaluator already has effectful primitives — `FETCH`/`POST`, HTTPS-only and gated behind `safeMode` (`…/EvaluateLazy/Machine.hs:1664`, `:1469`; env-var read at `:1689`) — so `webSearch` is in the same family as `FETCH`, plus a provenance record. Two readings must be kept apart:

- **Execution** (decision service, live run): `webSearch` is a real tool call; its result is admitted to the ledger with a source tag. This is the LLM-tool-calling story — the "left brain" oracle whose answer enters a *typed, traceable* record.
- **Verification** (model checker, `#TRACE`/scenario search): `webSearch` is an **input/oracle** — a symbolic value with an optional constraint, *not* a computed quantity. The trace records "at this point a value of type `Temperature` entered the record from source `webSearch`," and scenario search ranges over its admissible values. This is what makes the deontic-temporal double-binds of the paper reappear as reachability/unsat queries once data state is in the model.

Legally this framing is flattering, not awkward: `MAY webSearch … AS freezePoint` is *Alice exercising a permission to enter a fact into evidence*, and `RECORD`/`COMMIT` is *committing that finding to the record*. The bearer-vs-establishment distinction the burden appendix insists on (`burden-of-proof.md` §5.1 — the plaintiff *bears* the six constitutive facts though the defendant *establishes* them by admission) is exactly the provenance we want on an `Assignment`: **who is responsible for the cell** is independent of **who supplied its value**.

> **Decision D4.** `webSearch`/oracle actions carry provenance into the `Assignment`. Under `safeMode` they are disabled (as `FETCH`/`POST` are); under verification they are modelled as typed inputs, not evaluated.

---

## 7. The frame problem, and what survives a breach

**Frame problem.** When you `RECORD` a new value for one cell, everything else must be specified to persist. Model `RECORD` as event-calculus `initiates`/`terminates` over fluents: the snapshot is the set of fluents holding at the current time; an `Assignment` initiates a new value (and terminates the prior binding for that `cell`); everything else persists by default. This keeps the cell **declarative** (a fold over events) rather than imperative, and connects to the event-calculus framing already in the paper.

**What survives failure — borrowed wholesale from the burden monad.** The burden appendix makes a load-bearing choice of transformer order: `MaybeT (Writer w)` keeps the ledger on a failed proof, whereas `WriterT w Maybe` discards it — and L4 chooses the former because "blame must survive failure" (`burden-of-proof.md` §4.1). The identical question arises for env: if a deontic branch **breaches** (`ValBreached`) after some `RECORD`s, do we keep those assignments? The burden answer dictates ours: **yes** — the audit trail of a *failed* contract execution, with the partial state that was reached before the breach, is precisely what an auditor needs.

> **Decision D5.** Ledger-outside-failure. On `ValBreached`/LEST, the `Assignment`s accumulated before the breach **remain** in the ledger (they are part of the trace), exactly as `MaybeT` keeps the obligation ledger. The snapshot at breach time is well-defined and inspectable.

---

## 8. Concurrency: the deontic race becomes a data race

This is where the design bites and where it most needs a decision. The paper's headline finding — a deontic double-bind discovered by model checking — generalises: once parties write a **shared** cell, interleaved `RECORD`s/`COMMIT`s introduce a *data* race on top of the deontic one. Two models:

- **Shared official record.** One ledger all parties append to. Writes need an ordering discipline and the checker must explore interleavings (state-space cost, but standard — this is what makes the loophole-as-exploit search now cover data state).
- **Per-party records + explicit commit points.** Each party accumulates a private ledger; a named, visible act merges findings into the shared "official record." This matches how law actually handles evidence (each side builds its case; the court's record is updated at defined moments) and avoids the "growing global" Prolog-at-scale failure the `props` doc warns about.

> **Recommendation R1.** Default to **per-party ledgers with explicit commit points**, with a single distinguished "official record." Treat the shared-mutable-bag model as opt-in. Rationale: it keeps the data-race surface small and named, it mirrors legal practice, and it preserves the burden appendix's *non-conflation* rule — the burden role (who-must-prove) must never be synthesised into a deontic `PARTY … MUST` (`burden-of-proof.md` §7); per-party records keep the three Hohfeldian lanes (on-the-hook / who-decides / who-must-prove) as separate projections rather than smearing them into one global cell.

---

## 9. Type system

**Schema: declared vs inferred.** Reads can be inferred exactly as `props` infers its structural requirements from usage (`props` design §5.2: `props's jurisdiction` ⇒ `props` carries a `jurisdiction : …`). But **writes need a target type**, which is genuinely different from the Reader case: `RECORD X IS V` constrains `X` to the type of `V`, and multiple writes to `X` must agree. Two sub-options:

1. **Inferred open schema.** Build the minimal `EnvironmentState` type from the lattice of all `RECORD`/read sites; check write/read agreement; let the record grow structurally down the call graph (the `props` widening story).
2. **Declared schema.** `EnvironmentState` is a `DECLARE`d record (as in Variation A); `RECORD`s and reads are checked against it; growth is explicit.

> **Recommendation R2.** Support **inference (1) as the default**, with an **optional `DECLARE` (2)** when the author wants the schema pinned and visible — same posture as `props` (`TAKING` is inferred but displayable). Establishment is visible (D1); the *shape* can be inferred but should be *displayable*, mirroring `TAKING`.

**Surfacing.** By analogy to the `props` design's `TAKING` clause (inferred, IDE-displayed), the IDE should surface, per rule: the cells it **reads** (with "as-of" provenance) and the cells it **writes**. A natural pairing:

```l4
-- inferred + IDE-rendered; author writes only the RECORD line
updateEnvExample MEANS
  PARTY Alice
  MAY webSearch "the freezing point of water" AS freezePoint
  HENCE
    RECORD `freezing point of water` IS freezePoint's result
  -- IDE badge:  READS ∅   WRITES `freezing point of water` : Temperature
  --             via webSearch (oracle), provenance: Alice@t
```

---

## 10. Implementation strategy (additive to today's evaluator)

The breaking-change surface is small because the precedents exist.

### Milestone ordering (de-risk Rung 3 first, grammar later)

The plan is **substrate-first**: prove the load-bearing claim (D2/Rung 3) end-to-end with *zero grammar changes* before touching the lexer, parser, or type checker. Each milestone is independently shippable and reviewable.

- **M0 — Ledger substrate (no new surface syntax). ✅ DONE (2026-06-11, branch `mengwong/state-ledger`).** Added `L4.Evaluate.Ledger` (`Path`, `Provenance`, `LedgerEvent(Assign)`, `Ledger = DList LedgerEvent`, `emptyLedger`, `snapshot`, `readCell`), an `envLedger :: !(IORef Ledger)` field on `EvalState`, and `tellEvent`/`currentLedger` modelled exactly on `traceEval`. The stored value reuses the evaluator's own `WHNF` (no import cycle). *Rung 3 was proven not via throwaway `__assign`/`__readCell` builtins (the original sketch) but more cleanly by an Eval-monad **HSpec unit test** (`jl4-core/test/LedgerSubstrateSpec.hs`): `tellEvent (Assign …) >> currentLedger` round-trips through the monad, last-write-wins holds, and a fresh ledger is empty.* Per-directive isolation (the #1 leak risk) is handled by `withFreshLedger` wrapping `nfDirective` — a `local` IORef swap, exception-safe — plus empty-init at all three `EvalState` construction sites. Builds green under `-Wall -Werror`; full suite 50/50. Adversarially verified (build+test, diff bug-hunt, regression) — no real defects. The user-visible `#EVAL`/`#TRACE` surfacing of ledger rows is deferred to M2 (it needs the real `RECORD` syntax from M1 to be worth wiring).
- **M1 — Surface WRITE syntax. ✅ DONE (2026-06-11, commit `b14beab2`).** Lexer tokens `RECORD` / `COMMIT` / `ATTEST` (the `IS` copula, `'s` genitive, and backtick idents already existed); parser production in `baseExpr'` (reachable in HENCE/LEST and as a `#EVAL` body); one new `Expr` constructor `Record Anno (Expr n) (Expr n) Bool` (cell, value, isOfficial); typecheck (cell : `STRING`, result : the value's type, so it chains); eval via two CEK frames → `tellEvent (Assign path whnf prov)` — an **append**, returning the written value. Cell is a flat string `Path` for M1; `isOfficial` recorded in `Provenance.source` pending M4. `RecordLedgerSpec` (5 tests); whole workspace green. *The one-new-constructor exhaustiveness blast radius reached **downstream** packages the Map phase hadn't covered — `jl4-lsp` (`ToSemTokens … Bool`) and `jl4-mlir` (`foldExprChildren`, free-vars, and `lowerExprCases → markUnsupported`); the adversarial regression check caught it. Lesson for later milestones: build `cabal build all`, not just `jl4-core`.*
- **M1.5 — Terse READ keyword `RECALL`. ✅ DONE (2026-06-12).** The bare-cell-vs-`dictLookup` fork was resolved in favour of a **terse keyword**: `RECALL <cell>` reads the cell's latest value, returning `MAYBE v`. (`THE` was the mockup but is already the article `A`/`AN`/`THE` — ambiguous; `RECALL` is free.) New `Expr` constructor `ReadCell Anno (Expr n)`; cell is the same flat string `Path` as `RECORD` (reuses the `cellExpr` helper, so a read and a write name a cell identically and it stays out of name resolution); typed `MAYBE a`; eval reaches the M0 ledger via a new `CurrentLedger :: Machine Ledger` op, `readCell`s the snapshot, and wraps `JUST`/`NOTHING` (the date-parse idiom). `withFreshLedger` isolation preserved (a `RECALL` in a later directive can't see an earlier directive's `RECORD`). `ReadCell` adds no primitive field, so unlike `Record` there is *no* new base instance — only the explicit `Expr`-match sites, including downstream `jl4-mlir`; `jl4-lsp` generic-derives it. 59/59 tests; whole workspace green; adversarially verified.
  - **Known limitation — the flat-ledger soundness gap (motivates R2).** `RECALL` is typed `MAYBE a` for a *fresh* `a` with no link to the type a `RECORD` wrote to that cell, so a number-valued cell can be recalled where a string is expected and the checker accepts it (the runtime stays dynamically typed). This is the inherent cost of the **flat string-keyed** ledger; the **typed `EnvironmentState` schema (R2, §9)** is the refinement that closes it — cross-checking each `RECALL`'s `a` against the cell's declared/inferred type.
  - The prelude **`Dictionary`** (`prelude.l4:737`) remains the conceptual snapshot model and powers M3's `resolve` (`dictFindWithDefault` ≡ `fromMaybe <presumption> (RECALL cell)`). `RECALL` itself reads via the M0 `readCell` primitive rather than materialising a `Dictionary` *value*; that materialisation is only needed if L4 code wants the whole env at once (deferred). Keep the Haskell `Map` for the internal snapshot (assoc-list `Dictionary` is O(n), fine for dozens of cells).
- **M2 — Deontic integration + provenance.** Capture `Provenance` (party, action, trace position) from the enclosing `Deonton` as the `RECORD` fires inside the `followup`/`lest` `RExpr`; interleave `RECORD` rows with the deontic rows in `#TRACE`. Verify **D5** falls out for free: because `tellEvent` is an `IORef` append and `ValBreached` does not roll back, pre-breach `Assign`s survive automatically.
- **M3 — Presumption / `resolve` (D3). ✅ DONE BY COMPOSITION (2026-06-12) — no new code.** Because `RECALL <cell> : MAYBE v`, "read-before-write returns the presumption" is just the existing prelude `fromMaybe`/`holds`/`presumed` applied to a `RECALL`. Verified through the `l4` CLI (`jl4/experiments/state-ledger.l4`): `fromMaybe 99 (RECALL \`never written\`)` → `99`; `holds (RECALL \`flag\`)` → `FALSE` (closed-world / presumption of innocence); `presumed (RECALL \`flag\`)` → `TRUE` (open-world dual). The presumption (the monoidal identity, §5) is supplied at the read site; the NAF combinators (`a930f62c`) are the boolean specialisations of `fromMaybe`, and the general form is `dictFindWithDefault` (`prelude.l4:838`). *Caveat surfaced while writing the demo:* prefer `fromMaybe <typed-default>` (e.g. `fromMaybe FALSE (RECALL …)`), which pins the value type. The *bare* named `holds`/`presumed` are resolved type-directedly, and over a free-`a` `RECALL` the resolver cannot always pin which one to use ("could not find a definition for `holds` … inferred to be of type …") — the flat-ledger soundness gap (M1.5) biting at the read site, and another nudge toward R2's typed schema. *What remains for a later refinement (R2):* **per-cell declared** presumptions, so the default need not be repeated at each read site — that rides on the typed `EnvironmentState` schema. Unify with `WithDefault`/`TYPICALLY`.
- **M4 — Per-party ledgers + `COMMIT`/`ATTEST` (R1) and `local` quarantine (Q5). 🔒 RATIFIED 2026-06-12: per-party + official record (R1).** `RECORD` writes the *acting party's own* private ledger; `COMMIT`/`ATTEST` promotes a value to one *shared official record*. Reads: bare `<cell>` = own; `<party>'s <cell>` = cross-party; the official record is read explicitly. The single `envLedger` becomes a per-party structure (a `Map Party Ledger`) plus a distinguished official ledger; `tellEvent` routes by the acting party (`RECORD`) or to the official ledger (`COMMIT`/`ATTEST`); `readCell` reads the current party's ledger by default. **Depends on M2:** routing a `RECORD` to "the acting party's" ledger needs the acting party that M2 captures from the enclosing `Deonton` — so M4 follows M2, and inherits whatever M2 concludes about party reachability (if M2 finds the party hard to thread, M4 must solve the same threading). `local` write-quarantine (Q5) lands here too.

The numbered steps below are the M0–M2 detail.

1. **Ledger in `EvalState`.** Add `envLedger :: IORef (DList Event)` to `EvalState` beside `evalTrace`/`temporalContext` (`…/EvaluateLazy.hs:48`); add `tellEvent` modelled on `traceEval` (`…/EvaluateLazy.hs:250`). `Event` subsumes the existing `Assignment`-shaped data and the burden `Obligation`.
2. **Cell read.** A projected read: fold the ledger (truncated at the current position) to a snapshot, return the `Maybe` value, defaulting to the cell's presumption (§5). A bare cell `X` resolves to this snapshot lookup; a cross-party read `Party's X` reuses the existing genitive `'s` accessor (as `p's truth`/`p's obligations` already do) — no new access syntax.
3. **`RECORD`/`COMMIT` expressions.** New AST node (a sibling of the existing effectful `Fetch`/`Post`/`Env` nodes in `Expr`, `jl4-core/src/L4/Syntax.hs:200`); evaluates its RHS, then `tellEvent (Assign …)` into the party's own ledger (`RECORD`) or the official ledger (`COMMIT`/`ATTEST`). Only legal inside a HENCE/LEST continuation (it is a deontic-sequence effect, not a constitutive one).
4. **Thread through contract frames.** The ledger rides the `ValObligation` scrutiny (`ContractFrame.hs`) untouched — it is `EvalState`-resident, not value-resident — so HENCE/LEST already see the accumulated ledger. Verify the save/restore needed for `local`/per-party scoping using the `EVAL AS OF SYSTEM TIME` frame as the template (`Machine.hs:303-325`).
5. **`local` / `flipBurden` / per-party scope as one combinator.** A scoped rebind-and-restore over the threaded ledger/context (§3).
6. **Trace/provenance integration.** `Assignment` events join the `#TRACE` stream; the decision service emits the snapshot history. The burden ledger and the env ledger print as one responsibility/record artifact with multiple lanes (§8, R1).
7. **Verification backend.** Feed the ledger into scenario search as data state; oracle reads (§6) become inputs.

Existing explicit-`GIVEN` threading continues to typecheck and run; the new path is additive in authoring terms even though it adds a cell to the calling convention.

---

## 11. Open questions

1. **Concurrency model (§8).** Per-party + commit points vs. shared official record — the soundness-critical decision for verification. Default proposed (R1); needs ratification and a formal interleaving semantics.
2. **Cell identity / paths.** *Partially resolved (2026-06-11):* the **runtime projection reuses the prelude `Dictionary k v`** (`prelude.l4:737`) — a flat string-keyed assoc-list materialised at the read boundary (M1.5), giving `dictLookup`/`dictFindWithDefault` for free. Flat/untyped is the default (it can't carry per-cell static types — a homogeneous `Dictionary Text v`); a **typed `EnvironmentState` record** with per-cell types remains the optional later refinement (R2), with the `Dictionary` as its erased runtime form. Still open: whether two parties' "same" cell are identical (bears on M4).
3. **`resolve` placement.** When exactly does an undecided env read collapse to its presumption — lazily at each read, or at a closing `resolve`/judgement pass as in the burden monad? Keep them the same operation (D3) — but is there one global close-the-world, or per-read defaulting?
4. **Reassignment policy.** Last-write-wins is the snapshot rule, but should *re-assigning an already-established cell* require a marked, distinct act (supersession) vs. a fresh `RECORD`? (Legal records distinguish "amend the finding" from "make a finding.")
5. **Interaction with `props`/Reader (`local`).** When a subtree is evaluated under `local` (rebinding `props`), are env writes from inside that subtree real (committed) or hypothetical (discarded on unwind)? Hypothetical evaluation that *also* mutates is a footgun; propose: `local` over env reads is fine, but env *writes* inside a hypothetical subtree are either forbidden or quarantined to a scratch ledger that is dropped on unwind.
6. **"Very pure" classification (from `props`).** A subtree that neither reads `props` nor reads/writes `env` is *maximally* pure — stronger memoisation/verification. Fold the env ledger into the purity-discovery analysis the `props` design proposes.
7. **Stacking with the burden truth-dimension.** `env`'s undecided cells are `Maybe`/`MAYBE BOOLEAN` (NAF spec); the burden monad is `MaybeT (Writer …)`. Is the env ledger literally the *same* Writer, with `Obligation` and `Assignment` as two event constructors, or two parallel ledgers? (Prefer one ledger, heterogeneous events — §2 — but confirm the monoid/identity story survives the merge.)
8. **Error messages.** A write whose RHS type disagrees with prior writes, or a read of a never-written cell with no declared presumption, must produce an intelligible diagnostic across a large call graph (the `props` design's open question, inherited).

---

## 12. Relationship to other specs

- **`props` / Reader design** — the *down-the-call-graph* dual of this *along-the-timeline* spec. Same `'s` accessor, same inference-but-displayable posture, same `local` primitive. **These two should ship as one calling-convention change**, not two.
- **Burden-of-proof monad** (`app:burden`, `jl4-proleg`) — the *already-implemented* Writer ledger this spec generalises. Reuse its transformer-order choice (D5), its bearer≠establishment provenance (§6), its `resolve`/presumption/identity theory (§5), and its non-conflation rule (R1).
- **`RUNTIME-INPUT-STATE-SPEC.md`** — its `WithDefault`/`resolve`/`TYPICALLY` *is* the presumption story for env cells (§5). Do not invent a parallel "uninitialised" state.
- **`NEGATION-AS-FAILURE-SPEC.md`** — `MAYBE BOOLEAN` is the truth-dimension carrier under both the burden monad and undecided env cells.
- **`SECTION-LEXICAL-SCOPING-SPEC.md`** — `§` scope governs where `props` is established and, plausibly, where per-party ledgers are scoped/committed (§8).
- **`TEMPORAL_EVAL_SPEC.md` / `TemporalContext`** — the existing implicit-context-with-`local` precedent the implementation copies (§3, §10).

---

## 13. One-paragraph summary for a hurried reader

`RECORD <cell> IS V` looks like a State monad, but in a language whose product is auditability, State should be **Reader-over-Writer**: an append-only, provenance-tagged event ledger with the symbol table as a snapshot projection (`RECORD` appends, a bare cell read returns the latest as-of-now value). This reuses the **Writer ledger the burden-of-proof monad has already built** — `Obligation` and `Assignment` are two entries in one ledger — and inherits its hard-won decisions: keep the ledger on failure (blame/state survives a breach), separate who-is-responsible from who-supplied-the-value, and treat the never-written cell's default as a *presumption* (the monoidal identity, unified with `TYPICALLY`/`WithDefault` and the burden `resolve`). Reads are inferred and threaded like `props`; only the `RECORD`/`COMMIT` write is explicit (`unsafePerformIO`-style marked breach). `webSearch` is an oracle — a real tool call at execution, a typed input under verification — recorded with provenance. The data cell rides the deontic state machine the evaluator already threads, added to `EvalState` exactly as `TemporalContext` and `evalTrace` are, with `local`/`flipBurden`/`EVAL AS OF` unified as one scoped-rebind primitive. The open crux is concurrency: default to per-party ledgers with explicit commit points so the deontic-race-becomes-data-race surface stays small and named, and so the three Hohfeldian lanes stay three projections rather than one global bag.

---

## Appendix A — Desugaring by stepwise refinement

We take the running example and rewrite it one layer at a time. Every rewrite is meaning-preserving; each removes one piece of sugar or makes one implicit thing explicit; each is annotated with the decision (**D1**–**D5**, **R1**) it realises. By the last step everything is a fold over a list of events you can evaluate by hand.

*Surface write syntax is **locked** per D1: `RECORD <cell> IS <expr>` (own ledger), `COMMIT`/`ATTEST <cell> IS <expr>` (official record), bare `<cell>` reads, `<party>'s <cell>` for cross-party reads. Other keywords below — `READS`/`WRITES`, `PRESUMED` — remain provisional, like `TAKING` in the `props` design.*

### The core vocabulary (the target of desugaring)

```haskell
type Path   = [Text]            -- `freezing point of water`  ==>  ["freezing point of water"]
data Value  = VNum Rational | VStr Text | VNothing | ...   -- an undecided cell reads as VNothing
type Ledger = [Event]           -- append-only, newest last
data Event
  = Assign  Path Value Provenance   -- emitted by RECORD (own ledger) and COMMIT/ATTEST (official)
  | Acted   Party Action TracePos   -- a party exercised a permission / discharged a duty
  | Breach  Party Deonton TracePos  -- a duty went unmet
  | Obliged Subject Text            -- the burden ledger entry (already exists, Burden.hs)
data Provenance = Prov { by :: Party, via :: Source, at :: TracePos }

tellEvent :: Event  -> Eval ()        -- append to EvalState.envLedger  (cf. traceEval, EvaluateLazy.hs:250)
snapshot  :: Ledger -> Map Path Value -- foldl; last Assign per Path wins
readCell  :: Path -> Ledger -> Value  -- snapshot lookup; default = the cell's presumption
```

### Step 0 — Surface (what the author types)

Per **D1**, no `GIVEN env`: the environment is implicit; only the write (`RECORD`) is visible.

```l4
updateEnvExample MEANS
  PARTY Alice
  MAY webSearch "the freezing point of water" AS freezePoint
  HENCE
    RECORD `freezing point of water` IS freezePoint's result
```

### Step 1 — Reveal the threaded ledger (the calling convention)

The implicit environment is a `Ledger` the calling convention threads in and out of every rule — like `props`, but along the timeline rather than down the call graph. The compiler infers, and the IDE displays, what each rule touches (the env analogue of the `props` design's `TAKING`):

```l4
-- IDE-rendered, inferred (the author does NOT write this):
updateEnvExample
    READS   ∅
    WRITES  `freezing point of water` : Temperature   -- via webSearch (oracle)
  MEANS
    PARTY Alice
    MAY webSearch "the freezing point of water" AS freezePoint
    HENCE
      RECORD `freezing point of water` IS freezePoint's result
```

Semantically the rule is now a transition `runRule :: Ledger -> Event -> Eval Ledger`. The ledger lives in `EvalState` (an `IORef`, exactly as `evalTrace`/`temporalContext` do, §3), so it never appears as a value parameter — that is what "implicit" buys.

### Step 2 — Desugar the deontic layer to a guarded continuation

`PARTY Alice MAY <action> AS x HENCE <k>` reads: *if* an incoming event is Alice performing `<action>`, bind its outcome to `x` and run `<k>`; otherwise the permission lapses with no effect (a `MAY`, unlike a `MUST`, has no `LEST`). This is the obligation scrutiny the contract frames already perform (`ContractFrame.hs:6-53`), written as a guard:

```
runRule ledger event =
  case match event (Alice, webSearch "the freezing point of water") of
    NoMatch       -> pure ledger                  -- permission not exercised; ledger unchanged
    Match outcome -> let freezePoint = outcome    -- the AS-binding, local to the continuation
                     in  runHENCE ledger freezePoint
```

**AS vs RECORD.** `freezePoint` is a *local* binding, alive only inside `runHENCE`; nothing durable has happened. And `outcome` is a *record*, not a bare number — the oracle returns its value plus provenance:

```
freezePoint = { result     = VNum 273.15
              , provenance  = Prov { by = Alice, via = WebSearch "...", at = t1 } }
```

### Step 3 — Desugar `RECORD … IS …` to `tellEvent (Assign …)`

This is **D2**: the assignment is not a store into a cell, it is an *append* to the ledger, carrying the provenance of the action that produced the value. (`COMMIT`/`ATTEST` is the identical desugaring, targeting the official ledger instead of the party's own.)

```
runHENCE ledger freezePoint =
  tellEvent (Assign ["freezing point of water"]
                    (freezePoint.result)        -- VNum 273.15
                    (freezePoint.provenance))   -- who / where / when
  -- tellEvent appends:  ledger' = ledger ++ [that Assign]
```

Dually, anywhere a *later* rule reads the bare cell `` `freezing point of water` `` desugars to `readCell ["freezing point of water"] ledger` — a lookup in `snapshot ledger`, defaulting to the cell's presumption if no `Assign` exists yet (**D3**, §5).

### Step 4 — Evaluate by hand (a concrete run)

Feed the rule one world-event: at `t1` Alice does the search and the oracle returns 273.15 K.

```
ledger₀ = []                                                -- nothing established yet
event   = Acted Alice (webSearch "...") t1,   outcome.result = VNum 273.15

runRule ledger₀ event
  ⇒ Match ⇒ runHENCE [] { result = 273.15, prov = Prov Alice (WebSearch "...") t1 }
  ⇒ tellEvent (Assign ["freezing point of water"] (VNum 273.15) (Prov Alice ... t1))
  ⇒ ledger₁ = [ Acted  Alice (webSearch "...") t1
              , Assign ["freezing point of water"] (VNum 273.15) (Prov Alice (WebSearch "...") t1) ]

snapshot ledger₁ = { ["freezing point of water"] ↦ VNum 273.15 }
```

What `#TRACE` prints (the ledger *is* the trace — `Assign` rows interleave with the deontic rows already there):

```
#TRACE updateEnvExample
  t1  ACT     Alice  webSearch "the freezing point of water"  ⇒ 273.15
  t1  RECORD  `freezing point of water` IS 273.15
              from webSearch (oracle)   by Alice   at t1
  ── snapshot @ t1 ──
      `freezing point of water` : Temperature = 273.15   (established)
```

Whole pipeline: surface `RECORD` ⇒ one `Assign` event ⇒ a fold gives the snapshot ⇒ the event list *is* the audit trail.

---

### Variation A — reading before writing: the presumption (D3)

A downstream rule needs the freezing point *before* Alice has run the search.

```l4
DECLARE EnvironmentState HAS
    `freezing point of water` IS A Temperature   PRESUMED NOTHING   -- the cell's identity (§5)

GIVETH A BOOLEAN
DECIDE `water would freeze at` t IF
    t `at or below` `freezing point of water`
```

Desugar the read:

```
readCell ["freezing point of water"] ledger
  | ledger has an Assign for it  = that value           -- established
  | otherwise                    = presumption of cell  -- here VNothing (undecided)
```

*Before* `t1`: the read is `VNothing`, the comparison is `MAYBE BOOLEAN = NOTHING`, and a closing `resolve` applies the presumption — the burden monad's "unproven ⇒ the bearer loses." *After* `t1`: the same read returns 273.15 and the comparison decides. Same syntax; the value is **"as of now"** (§4). Choosing `PRESUMED NOTHING` vs `PRESUMED 273.15` is the constitutional act — the monoidal identity (§5), unified with `TYPICALLY`/`WithDefault` and the burden `resolve`.

### Variation B — a write before a breach survives (D5)

Make it a duty with a deadline and a reparation, and have Alice record the fact but then miss a *second* duty:

```l4
recordThenReport MEANS
  PARTY Alice
  MUST webSearch "the freezing point of water" AS fp   BEFORE 2026-07-01
  HENCE
    RECORD `freezing point of water` IS fp's result
    HENCE PARTY Alice
          MUST `file report` WITH `freezing point of water`   BEFORE 2026-07-08
          LEST PARTY Alice MUST `pay penalty`
```

Alice does the search (ledger gets the `Assign`) but never files the report. The desugaring keeps the pre-breach `Assign`, because `tellEvent` already happened and the breach is just another event appended *after* it — there is no rollback:

```
ledger = [ Acted  Alice (webSearch ...) t1
         , Assign ["freezing point of water"] 273.15 (Prov Alice ... t1)   -- SURVIVES
         , Breach Alice (MUST `file report` ...) t2                        -- the failure
         , Acted  Alice (`pay penalty`) t3 ]                               -- the LEST reparation
```

This is **D5 = the burden monad's `MaybeT`-outside-`Writer`**: the ledger is kept on failure, so the audit shows *both* the partial state reached *and* the breach. A naive `State` with rollback would erase the very evidence an auditor needs.

### Variation C — two parties, one official record (R1)

`RECORD` writes the *acting party's own* ledger; promotion to the shared record is a separate, visible act — `COMMIT` (synonym `ATTEST`):

```l4
gatherEvidence MEANS
  PARTY Alice  MAY webSearch "freezing point" AS a  HENCE RECORD `fp` IS a's result
  PARTY Bob    MAY webSearch "freezing point" AS b  HENCE RECORD `fp` IS b's result
  HENCE
    PARTY Court
    MUST `reconcile`
    HENCE COMMIT `fp` IS `ruling over` (Alice's `fp`) (Bob's `fp`)
```

Desugar: `RECORD X` writes — and a bare read `X` reads — the *current party's* ledger (the snapshot is now per-party); `COMMIT X IS V` (or `ATTEST`) is an `Assign` into the distinguished shared *official* ledger, emitted only at the named commit point. The cross-party reads `Alice's fp` / `Bob's fp` keep the genitive because they reach into *another* party's record. Alice's and Bob's private writes **cannot race** — they touch different ledgers; the only shared write is the Court's single `COMMIT`. This is **R1**: the deontic-race-becomes-data-race surface shrinks to one named commit, and the three Hohfeldian lanes stay distinct — Alice and Bob *supply*, the Court *decides*, and (were `fp` a burden fact) some party *bears* it.

> **Footgun watch (open Q5).** If `gatherEvidence` were evaluated under a Reader `local` (a hypothetical "what if jurisdiction were X"), should Alice's and Bob's `RECORD`s be real or discarded on unwind? Proposed: env *reads* under `local` are fine; env *writes* (`RECORD`/`COMMIT`) are quarantined to a scratch ledger dropped on unwind, so a what-if can never silently mutate the official record.
