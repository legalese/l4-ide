# Flattening Simple Recursions for DMN Export

_Status: **the flattening is proposed, not implemented; the interim decision in
[§7](#7-the-interim-decision-and-what-it-costs) has shipped.** Written 2026-08-02 on branch
`mengwong/dmn-phase5-bkm`, against `0253c21a`; §7 amended the same day, against `ba841f8f`. Nothing
in `jl4-core/src/L4/Dmn/` implements §§1–6 — the recognition rule in
[§4](#4-the-recognition-rule) has never been run over the corpus, and every count below that is not
attributed to a committed artifact is an estimate and is labelled as one. §7 is the exception and
says so in its own text._

> **Why this exists.** Phase 5's `regcf-corpus.dmn` failed the `dmn-moddle` metamodel gate on a
> decision that requires itself, which DMN 7.3.1 forbids. The immediate fix — recorded in
> [§7](#7-the-interim-decision-and-what-it-costs) and shipped on this branch — erases the self-edge
> and keeps the `D-CYCLE` note. That restores a valid artifact but says nothing about the
> recursion, which is real, faithful to the regulation, and the more interesting problem. This
> document is that problem.

---

## 1. The refusal we have today

`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §6.3-1 routes recursion to a `Blocking` `D-RECURSIVE`, and §763
records that **the measured refusal set _is_ recursion**. §5230's corpus table reports
`D-RECURSIVE` at **0** with the gloss "no L4 source reaches a KR cycle (recursion is never certified
total)".

That refusal is correct in general. DMN's requirement graph is a DAG by construction, FEEL has no
recursion, and a general recursive definition has no finite DMN image. Nothing below proposes
lifting the refusal. It proposes carving one decidable, checkable shape out of it.

## 2. The instance that motivates it

`jl4/examples/legal/regcf/regcf.l4` (17 CFR 227.202(a); 227.203(b)) — the reporting spine:

```l4
GIVEN status          IS A ReportingStatus
      `annual cycles` IS A NUMBER
GIVETH A DEONTIC Actor Action
`ongoing reporting obligation` status `annual cycles` MEANS
    IF   `ongoing reporting obligation may terminate` status
    THEN PARTY Issuer MUST `file a Form C-TR termination of reporting` WITHIN `business days to file Form C-TR`
    ELSE IF   `annual cycles` AT MOST 0
         THEN FULFILLED
         ELSE PARTY Issuer MUST `file a Form C-AR annual report` WITHIN `days to file the annual report after fiscal year end`
              HENCE `ongoing reporting obligation` status (`annual cycles` MINUS 1)
```

The source comment already reads it as an unrolling: _"`annual cycles` bounds the unrolling so the
residual is finite."_

## 3. The structural observation that makes this tractable

**At the recursive call site, `status` is passed through unchanged. Only the counter moves.**

That is the whole argument, and it is worth stating in the terms that decide feasibility:

- There is **no accumulator**. Each cycle's obligation is a function of `status` alone, not of any
  state threaded from the previous cycle. The recursion is a **map**, not a **fold**.
- The guard `` `ongoing reporting obligation may terminate` status `` is therefore
  **loop-invariant**: it has the same value at every depth, so it can be hoisted out entirely.
- Hoisted, the definition collapses to: _if it may terminate, one Form C-TR; otherwise `n` copies of
  the Form C-AR obligation, then `FULFILLED`._

Feasibility turns on map-vs-fold because **FEEL 1.3 has `for … in … return` but no `reduce`/fold**.
A threaded accumulator has no FEEL image without unrolling; a loop-invariant body has an immediate
one. Any proposal that ignores this distinction will look like it generalises and will not.

## 4. The recognition rule

A self-recursive definition `f p₁ … pₙ` is **flattenable** iff all of:

1. **R1 — single self-call.** The body contains exactly one call to `f`. (Two call sites are a tree
   recursion, not an iteration; refuse.)
2. **R2 — one moving argument.** At that call site, every argument is syntactically identical to the
   corresponding parameter, **except exactly one** numeric parameter `pₖ`.
3. **R3 — strict decrease by a literal.** That argument is `pₖ MINUS c` for a positive numeric
   literal `c`. (A computed decrement cannot be shown to terminate here; refuse.)
4. **R4 — a base case on the same parameter.** The recursion is guarded by a condition testing `pₖ`
   against a constant bound, on the arm that does not recurse.
5. **R5 — no other self-reference.** `f` does not appear in any guard, in the base arm, or under a
   binder in the body.

R2 is the load-bearing one and is deliberately **syntactic identity**, not semantic equivalence: it
is cheap, decidable, and false-negative-safe. A definition that threads an unchanged-but-rebuilt
record fails R2 and stays refused, which is the correct default when the alternative is emitting
something wrong.

Anything failing any of R1–R5 keeps today's `D-RECURSIVE` / `D-CYCLE` and its `Blocking` severity.

## 5. Two lowerings, and which one to take

|             | **A — DRG unroll**                       | **B — FEEL `for`**                                            |
| ----------- | ---------------------------------------- | ------------------------------------------------------------- |
| shape       | emit `f_1 … f_N` as a chain of decisions | one decision, body `for i in 1..pₖ return …`                  |
| the bound   | must be **statically known at export**   | stays a genuine `inputData`                                   |
| DRG         | acyclic, N nodes                         | acyclic, 1 node                                               |
| drags in    | the cap-overflow ruling (still open)     | nothing                                                       |
| engine risk | none beyond size                         | FEEL `for` in a boxed context; **unmeasured on both engines** |

**Recommend B.** It keeps `annual cycles` a parameter, which is what the L4 says it is; A silently
freezes a variable into a constant and then needs a policy for what happens past the cap. B's one
risk — whether KIE and Camunda agree on `for … return` inside the contexts we emit — is exactly the
kind of thing the two-engine harness exists to settle, and it must be **measured before this is
built**, not assumed. Nothing in `jl4-core/src/L4/Dmn/` emits a FEEL `for` today (verified by grep
at `0253c21a`), so there is no existing evidence either way.

## 6. What the projection loses, stated plainly

`HENCE` is a **temporal continuation**: obligation _k+1_ arises after obligation _k_ is discharged.
DMN has no notion of sequence. Under either lowering, `n` ordered obligations become an unordered
list, and the DMN artifact stops carrying the ordering.

**This is acceptable, and it is not a compromise.** Sequencing is BPMN's job; the BPMN/DMN split is
the claim that decisions belong in DMN and control flow belongs in BPMN. A DMN file that tried to
encode the ordering would be the thing we say is wrong with hand-drawn process models. What the
export must do is **say so**: a flattened recursion emits an `Advisory` note naming the lost
ordering and pointing at the BPMN projection of the same rule. Silent flattening is not acceptable.

## 7. The interim decision, and what it costs

**Ruled 2026-08-02 (Meng): erase the self-edge again; emit valid DMN and keep the `D-CYCLE`
note.** This reverses the Phase 5 build note at `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §2928 ("the
self-edge is no longer erased"), which was itself a deliberate change three days earlier. The
reasoning for the reversal: DMN cannot represent the recursion at all, the `D-CYCLE` finding is
what tells the truth about it, and an artifact no engine will load is not an exhibit — which is
what R0 ("the execution is the exhibit") requires. The reversal is recorded in that spec, in the
same PR that makes the code change.

**Built and landed 2026-08-02 as `ba841f8f`**, and the owning ruling is
`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` **§6.4.4-4a**, which carries the measurements — read that, not
this paragraph, for the numbers. In outline: the `Drg` keeps the self-edge (so `checkDrg` still
fires `D-CYCLE`, count 1 before and 1 after, and `regcf-corpus.fidelity.txt` did not move) and
`L4.Dmn.Emit` drops it via the new `L4.Dmn.IR.emittedRequirements` / `emittedKnowledgeReqs`. Scope
is `|SCC| = 1` **only** — a two-member cycle still emits every edge, pinned by
`cycle-p2-mutual-nullary` in `jl4/tests/DmnExport.hs`. `etc/validate-dmn.mjs` exits 0; KIE 8.44's
verdict on `regcf-corpus.dmn` goes from 34 errors to 32, the whole delta being the
cyclic-dependency error, once per leg.

The cost is that the emitted DRG no longer records that the recursion exists; only the finding
does. Anyone reading the `.dmn` alone sees a decision with one fewer requirement and no hint that
something was dropped. That is the gap this document closes when it is built.

## 8. Open questions

- **Q1.** Does `for … in … return` inside our emitted boxed contexts evaluate identically on KIE
  8.44 and Camunda 8.7.6? **Must be measured first** — everything in §5 is conditional on it.
- **Q2.** What does a flattened `DEONTIC` body lower _to_, elementwise? The current decision carries
  `typeRef="Any"`; a list of obligations wants a real itemDefinition, which is Phase 3 territory.
- **Q3.** Should R3 admit a decrement of a non-literal that is itself loop-invariant and provably
  positive? Cheap to allow, and it needs a positivity check we do not have.
- **Q4.** Does any corpus definition other than `ongoing reporting obligation` satisfy R1–R5? If the
  answer is "one", this is a one-instance feature and should be scheduled accordingly. **Unmeasured**
  — the recognition rule has never been run.
- **Q5.** Where does the `Advisory` ordering note from §6 sit in the fidelity taxonomy — is it a new
  code, or `D-PARTIAL` with a distinct message? See `FIDELITY-SEVERITY-AXIS-SPEC.md`.

## 9. Relationship to other documents

- `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §6.3-1, §6.3.9, §763, §2928, §5230 — the refusal this narrows,
  and the note §7 reverses. **§6.4.4-4a is where that reversal is owned and measured**; §7 here is
  its other side. **That spec owns the refusal; this one may not change it unilaterally.**
- `DMN-PHASE5-BUILD-PLAN.md` §P5.0a — `checkDrg` and the SCC routine the recognition rule would run
  beside.
- `FIDELITY-SEVERITY-AXIS-SPEC.md` — Q5.
- `specs/todo/TIER1-WIP-INDEX.md` — the backlog row.
