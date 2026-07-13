# Specification: Question Ordering for the Query-Plan Wizard

**Status:** 🏗️ v1 LANDED IN TS (unmerged, branch `mengwong/question-ordering-v1`); v2 (priors) SPEC'd + UNBLOCKED once PR #92 lands.
**Goal:** Make the auto-generated citizen wizard ask the _fewest, most-relevant_ questions to reach a determined outcome.
**Related:** `specs/done/BOOLEAN-MINIMIZATION-SPEC.md` (§"TYPICALLY: Overrideable Defaults"), `specs/done/PARTIAL-EVAL-VISUALIZER-SPEC.md`, `specs/todo/TYPICALLY-DEFAULTS-SPEC.md`; `doc/reference/query-planning/{README,robdd}.md` (the reference docs); PR #92 (TYPICALLY metadata-only).
**Touches:** `ts-shared/boolean-analysis/src/{robdd.ts,decision-query.ts}`, `jl4-query-plan/src/L4/Decision/{BooleanDecisionQuery,QueryPlan}.hs`, `jl4-lsp/src/LSP/L4/Viz/QueryPlan.hs` (the weight seam), `jl4-core/src/L4/FunctionSchema.hs` (the TYPICALLY-extraction model to copy).

---

## 1. Scope and non-scope

**In scope:** improve the _dynamic next-question policy_ — given what the user has answered so far, choose which unknown to ask next so the wizard terminates quickly.

**Explicitly NOT in scope (and why):**

- **BDD variable reordering / sifting.** The variable order (`collectVarOrder`, `decision-query.ts:32`) only affects diagram _size_, not which question a user is asked. Chase it only if the BDD blows up; it is orthogonal to usability. This is the common conflation to avoid.
- **Formal decision-table analysis** (completeness / conflict / redundancy). Deferred per decision on 2026-07-06; tracked separately.
- **Building `TYPICALLY`.** No longer backed out: `TYPICALLY` shipped as **metadata-only** via PR #92 (parse + store + literal-vs-type check + JSON-schema `default`; the risky PEVAL/PASSERT machinery was dropped). This spec _consumes_ those weights but the policy itself does not depend on the keyword — v1 runs prior-free, v2 reads the weights.

---

## 2. Current mechanism and its limits

Two pieces, both in `ts-shared/boolean-analysis` (mirrored in `BooleanDecisionQuery.hs`):

- **Variable order** — `collectVarOrder` = first-occurrence DFS order over the ladder. Purely syntactic.
- **Next-question rank** — `rank` (`decision-query.ts:123`) scores each still-relevant atom by
  ```
  score(u) = [ -determinableCount(u), level(u) ]
  ```
  where `determinableCount ∈ {0,1,2}` = how many of {answer=true, answer=false} land directly on a terminal, and `level` = position in the syntactic order.

**Two defects:**

1. **No credit for progress.** A question that eliminates 90% of remaining scenarios without settling the outcome scores identically (`0`) to one that eliminates 1%. Early in a session almost every atom ties at `determinableCount = 0`.
2. **Syntactic tiebreak.** Ties break by `level`, i.e. source order — arbitrary to the user. Net effect: until something becomes directly determinable, the wizard asks questions in roughly the order they were written.

The loop shape is already correct: `query()` returns a fully `ranked` support each call, and the caller re-queries after each answer. So this is _already_ a per-step greedy policy — we only need a better score.

---

## 3. Design: model-count-weighted information gain

### 3.1 The one missing primitive — `prob`

Add a model-count function to the ROBDD, in **probability space** (skip-safe by construction — reduced BDDs omit variables, and the probability formulation ignores omitted variables automatically):

```
prob(⊤)      = 1
prob(⊥)      = 0
prob(node v) = (1 − w_v) · prob(low) + w_v · prob(high)
```

`prob(R)` = P(decision R evaluates TRUE) under an independent model where atom `v` is TRUE with weight `w_v`. Memoize by node id. ~10 lines. (`w_v = ½` gives `prob(R)·2^k` = exact satisfying-assignment count over `k` unknowns, if a raw count is ever wanted.)

### 3.2 The score

For each currently-unknown atom `X` in the restricted support:

```
R_T = restrict(R, X = true)
R_F = restrict(R, X = false)
IG(X) = H(prob(R)) − [ w_X · H(prob(R_T)) + (1 − w_X) · H(prob(R_F)) ]
```

where `H(p) = −p·log₂p − (1−p)·log₂(1−p)` is binary entropy (`H(0)=H(1)=0`). Ask `argmax IG(X)`, greedily, each step.

Properties:

- **Subsumes the old heuristic.** An atom that _determines_ the outcome drives a branch to a terminal → `H = 0` → maximal gain. So "settles it now" is the top of the ranking, as before.
- **Adds progress credit.** An atom that merely halves the remaining space still scores well — fixing defect (1).
- **Near-optimal — and now citably so.** Greedy max-info-gain is the standard, cheap policy for minimizing expected question count; multi-step lookahead is exponential and out of scope. The guarantee this claim was leaning on without attribution is **Golovin & Krause's adaptive submodularity** (JAIR 42, 2011): where the objective is adaptive-submodular and adaptive-monotone, the greedy policy is within a `(ln(1/η) + 1)` factor of the optimal policy. Cite it; do not assert "near-optimal" bare. ⚠️ And note the sobering empirical baseline: **Lamy et al. (2024)** solve exactly this problem for clinical decision support, **prove the question-ordering problem NP-hard**, and then find that a _dumb frequency heuristic_ performs about as well as anything cleverer. We should beat that baseline on the Housing Act corpus, or explain why we need not.

### 3.3 Explainability (surface, not just rank)

The same `prob(·)` yields lay-readable rationale strings for the UI (L4 requires traceable reasoning everywhere). Prefer scenario language over bits:

- "This resolves your outcome immediately in ~P% of situations like yours" where `P = w_X·[R_T terminal] + (1−w_X)·[R_F terminal]`.
- "…and narrows the remaining cases the most." (from `IG`)

Keep the existing `impact` (`ifTrue`/`ifFalse` outcomes) — it already feeds the sidebar and is exactly the raw material for these strings.

---

## 4. Priors via `TYPICALLY`

`TYPICALLY` supplies `w_v` directly, auditable and drafter-declared (no telemetry needed):

| Declaration                                                        | `w_v`                                        |
| ------------------------------------------------------------------ | -------------------------------------------- |
| `x IS A BOOLEAN TYPICALLY TRUE`                                    | `0.9` (soft; see confidence, below)          |
| `x IS A BOOLEAN TYPICALLY FALSE`                                   | `0.1`                                        |
| numeric / string `TYPICALLY` (e.g. `age IS A NUMBER TYPICALLY 18`) | `½` — **ignored for ordering** (see wrinkle) |
| no `TYPICALLY`                                                     | `½` (prior-free)                             |

> **Wrinkle — only BOOLEAN `TYPICALLY` maps to an atom prior.** The policy orders Boolean _atoms_ (`age >= 18`, `citizen`), not parameters. A Boolean binder's default is a probability over its own atom: `TYPICALLY TRUE` → `w ≈ 0.9`. But a numeric/string default is **not** a probability over a derived comparison — `age TYPICALLY 18` says nothing about `P(age >= 18)`. So the v2 weight extractor reads priors **only** from Boolean binders whose atom is the binder itself; every numeric/string default (and every compound atom) stays at `½`. Those defaults still do their job as form-prefill and schema `default` — just not as ordering priors. Mapping every `TYPICALLY` to a weight is the correctness trap to avoid.

**Presumption falls out of the score.** A presumed atom (`w_v ≈ 0` or `≈ 1`) has near-zero expected information gain — you already believe the answer — so the greedy policy pushes it to the bottom of the ask-order automatically. That _reproduces_ the "rebuttable presumption → don't ask, allow override" behavior from `BOOLEAN-MINIMIZATION-SPEC.md` **without special-casing**, and — unlike the hard-imputation table there — it also orders the non-presumed atoms sensibly. The user can still override a presumed atom explicitly (an override is just a binding, which `restrict` already handles).

**Layering:**

- **v1 (DONE in TS, PR #94 open → `unstable`):** all `w_v = ½`. Prior-free. `prob()` + info-gain `rank` on `mengwong/question-ordering-v1` (rebased onto unstable, tip `35dddae8`, 4 files, MERGEABLE); `rank` already takes an optional `weights` param defaulting to ½. The Haskell mirror is **not** done — `BooleanDecisionQuery.hs` still has no `prob()`.
- **v2 (priors — this brief):** feed `w_v` from the binder's `TYPICALLY` Expr into that `weights` param. _Same policy code_ — only the weight source changes. Extraction model: `FunctionSchema.hs` already reads the TYPICALLY Expr (`typicallyToJson`; the default sits in the 4th field of `MkTypedName`, the last field of `MkOptionallyTypedName`/`MkAssume`) — copy that, then map `TRUE→0.9 / FALSE→0.1` per the wrinkle above.

---

## 5. Implementation plan

**This is step 3 of a 3-step chain — sequence it, don't parallelize blindly:**

1. **PR #92** (`TYPICALLY` metadata) lands to `unstable`. _In flight, MERGEABLE._ Without it the planner has no field to read.
2. **TS v1 — PR #94 open** (`mengwong/question-ordering-v1` → `unstable`, MERGEABLE). `prob()` + info-gain `rank` + the `weights` param; on the mainline tree the TS planner is still `[-determinableCount, level]` with no `prob()`. This must merge before the priors have a policy to feed.
3. **The v2 wiring (this brief):**

   1. ~~`robdd.ts`: `prob(id, weights?)` with per-instance cache, default ½.~~ **DONE (v1).**
   2. ~~`decision-query.ts`: `rank` = info-gain over `prob`; optional `weights: Map<Unique, number>` on `compileDecisionQuery`.~~ **DONE (v1).**
   3. **TS weight extractor (mostly plumbing):** build `Map<Unique, number>` from Boolean-binder `TYPICALLY` (`TRUE→0.9 / FALSE→0.1`, everything else `½` — see §4 wrinkle), and pass it into the `weights` param the wizard's `compileDecisionQuery` call already accepts (`partial-eval.ts`).
   4. **Haskell — build `prob()` FIRST, then feed:** `BooleanDecisionQuery.hs` has **no** `prob()` yet, so the mechanical port of §3.1/§3.2 is a prerequisite, not an afterthought. Then the same Boolean-only extractor at the seam `jl4-lsp/src/LSP/L4/Viz/QueryPlan.hs` → `jl4-query-plan/.../QueryPlan.hs` (`inputScores`/`impactScoreFor`, which today hard-code prior-free weights). **Extraction model:** copy `FunctionSchema.hs` (`typicallyToJson` + the `mTypically` reads).
   5. **Duplication note:** 3rd TS/Haskell ROBDD double-implement; still not worth unifying, but the score is specified once (§3.2) so the two copies can't drift.

**Validation:** the Housing Act Schedule 2 wizard corpus. Metric: number of questions to reach a valid/​invalid ground for possession, over a sample of tenant/landlord fact patterns, old `rank` vs new (prior-free), vs new (TYPICALLY priors). Target: strict reduction in mean questions, no regression in worst case; presumed atoms demonstrably fall to the end of the ask-order.

---

## 6. Decisions

1. **`TYPICALLY` confidence — RESOLVED: soft.** Use `w = 0.1 / 0.9`, not hard `0 / 1`. Presumed atoms sink to the end of the ask-order but are still asked if they'd flip the outcome — safer for high-stakes rules. Make the constant per-atom-configurable later; not in this pass.
2. **Concrete score — RESOLVED: entropy.** Entropy `IG` (§3.2), surfaced to the user in scenario language (§3.3), not raw bits. (Entropy and "expected scenarios eliminated" rank almost identically; entropy is the cleaner default.)
3. **Per-question cost — DEFERRED (open):** future hook for "annoying to answer" questions → rank by `IG / cost`. Out of scope; note the seam.

### 6.1 New — resolved by this refresh

4. **Prior scope — RESOLVED: Boolean binders only.** The v2 extractor reads priors from Boolean `TYPICALLY` binders whose atom is the binder itself; numeric/string defaults and compound atoms stay at `½` (see §4 wrinkle).

---

## 7. v2 wiring brief (agent handoff)

**One-line task:** make the query planner read `TYPICALLY` presumptions as per-atom priors, so the wizard pushes "usually true/false" questions to the end of the ask-order.

**Preconditions (do not start step 3 before these merge):**

- PR #92 (`TYPICALLY` metadata) merged to `unstable`.
- PR #94 (TS v1 info-gain policy, `mengwong/question-ordering-v1`) merged to `unstable`.

**Work:**

1. **TS extractor (mostly plumbing).** Build `Map<Unique, number>` from Boolean-binder `TYPICALLY` (`TRUE→0.9`, `FALSE→0.1`; **everything else `½`**) and pass it to the `weights` param the wizard's `compileDecisionQuery` call already accepts (`partial-eval.ts`).
2. **Haskell `prob()` port (prerequisite).** `BooleanDecisionQuery.hs` has no `prob()` yet — port §3.1 (`prob`) + §3.2 (info-gain `rank`) first; it's pure arithmetic mirroring the TS.
3. **Haskell extractor + feed.** Same Boolean-only extraction at the seam `jl4-lsp/.../Viz/QueryPlan.hs` → `jl4-query-plan/.../QueryPlan.hs` (`inputScores`/`impactScoreFor`). Copy the `TYPICALLY`-reading pattern from `jl4-core/src/L4/FunctionSchema.hs` (`typicallyToJson`; default in `MkTypedName`'s 4th field / last field of `MkOptionallyTypedName`/`MkAssume`).

**Hard constraints (the traps):**

- **Boolean binders only** — do NOT map numeric/string `TYPICALLY` to a weight (§4 wrinkle). This is the correctness trap.
- **Soft weights** `0.9/0.1`, not hard `1/0` (§6.1).
- Keep `determined` / `impact` / `stats` outputs unchanged; only the ordering changes.
- Specify the score once (§3.2); the two ROBDD copies must not drift.

**Done when:** on the Housing Act Sch.2 corpus, presumed atoms demonstrably fall to the end of the ask-order, mean question count drops vs prior-free, worst case does not regress, and both runtimes (TS wizard + Haskell query plan) agree on the ranking for a shared fixture.

---

## 8. Post-#96: the shared provenance dependency (found 2026-07-08)

§7 step 1 ("build a `Map<Unique,number>` from Boolean-binder `TYPICALLY` and pass it to `compileDecisionQuery`") understated one thing: **the TS side has no source for that map today.** The wizard builds `PartialEvalAnalyzer` from the `IRExpr` alone (`ts-shared/l4-ladder-visualizer/src/lib/layout-ir/ladder-graph/ladder.svelte.ts:322`); nothing surfaces `parameterDefault`/`TYPICALLY` into the ladder-visualizer or client — the default stops at the JSON schema and never rides the atom. So v2's real prerequisite is a **per-atom provenance flow**: L4 typechecked binder → viz atom, carrying "this atom is a Boolean binder with `TYPICALLY = X`".

**This is not really a v2 dependency — it's the ladder's.** The same flow is what **PR #96 (`ladder-diagrams-3`, `ladder-core` §22 "TYPICALLY defaulted-vs-given")** needs to render presumed atoms as tentative on _real_ modules. #96 built the consumer (the rendering — dashed/amber "typically") but hand-feeds a demo `provenance`/`presumed` map; the L4→atom extraction is still stubbed. It gets built the moment tentative rendering ships for real contracts — independent of whether v2 ever happens.

**Consequence — one flow, two consumers.** Build the extraction ONCE and feed both:

- cleanest shape: an optional field on the viz `UBoolVar` (e.g. `typically?: boolean`), populated by the Haskell ladder builder (`L4/Viz/Ladder.hs` / the LSP viz) from the typechecked binder's `mTypically` (reuse the `FunctionSchema.hs` `typicallyToJson` read);
- #96 derives its `provenance` (tentative styling) from it; v2 derives `weights` (`TRUE→0.9 / FALSE→0.1`, else ½) from it.

**The one escape hatch (v2 only):** do v2 **backend-side** instead — the Haskell query-plan already has `TYPICALLY` natively, so it can compute the weighted info-gain and return only the _ranking_ (the weight never travels to the frontend). That sidesteps the viz field for v2, but needs the Haskell `prob()` mirror (§7 step 2) built first AND the wizard switched to the backend query-plan path — and #96 still needs the provenance flow regardless. So it does not save the shared plumbing; it only changes whether v2 consumes it.

**Recommended sequencing (Meng, 2026-07-08 — "defer & reuse"):**

1. Land PR #92 (`TYPICALLY`) + PR #94 (v1) to `unstable`.
2. Fold the L4→atom `TYPICALLY`-provenance extraction into **#96's productionization** (build once, shared): a `UBoolVar.typically` field + the Haskell populate.
3. v2 then becomes small: `PartialEvalAnalyzer` reads the field → `weights` → `compileDecisionQuery` (§7 step 1), plus the Haskell mirror/feed (§7 steps 2–3) for backend parity.

**Do NOT** build a v2-private weights path in parallel with #96's provenance — that is the same extraction twice. If #96 ships demo-fed and defers the real extraction, the extraction is still owed; name it as a shared step so it lands once. (Answering the open question from 2026-07-08: yes, this plumbing gets built regardless of sequencing — the only choice is once-shared vs twice-duplicated.)

---

## 9. Related work — and what we may honestly claim (added 2026-07-14)

This spec previously had **no related-work section at all**, and its "near-optimal" claim (§3.2) was uncited. A literature check found that we are working in a well-populated field, that our ingredients are all old, and that our actual contribution is narrower than the spec's tone implied. That is fine — but a reviewer who knows this literature and catches us claiming novelty would be entitled to be annoyed, so it is written down here.

**Every ingredient is old, and the pedigree is an asset, not an embarrassment.**

- **Shwayder (1974)**, "Extending the Information Theory Approach to Converting Limited-Entry Decision Tables to Computer Programs", _CACM_ 17(9):532–537. **Entropy-driven test ordering from a rule base — fifty years ago.** The direct ancestor of §3.2. Cite it _first_; the lineage is the point.
- **Montalbano (1962)**, "Tables, Flow Charts, and Program Logic", _IBM Systems Journal_ 1(1). His table→flowchart ordering heuristic — "ask those questions first which will make the two differentiated groups of rule identifiers as similar in size as possible" — is an information-gain criterion **24 years before ID3**.
- **Bryant (1986)**, "Graph-Based Algorithms for Boolean Function Manipulation", _IEEE Trans. Computers_ C-35(8). The ROBDD, and the fact our whole three-orders argument rests on: variable order changes diagram _size_ enormously but has **"no effect on the correctness of the results."**
- **Ünlüyurt (2004)**, "Sequential testing of complex systems: a review", _Discrete Applied Math_ 142. The survey of the field our next-question policy formally belongs to. We are doing **sequential testing**, and should say so.
- **Golovin & Krause (2011)**, _JAIR_ 42:427–486. The near-optimality guarantee for greedy (see §3.2).
- **Hadzic et al. (2004)** / **Andersen, Hadzic & Pisinger (2010)**, _JAIR_ 37. Compile a rule base to a BDD offline, drive a **backtrack-free** interactive configurator off it. Architecturally identical to a legal wizard; commercialised as Configit. Worth reading for the interaction model, not just the theory.

**The closest existing work, and the one to engage with directly:**

- ⭐ **Aucher, Berbinau & Morin (2019)**, "Principles for a Judgement Editor Based on Binary Decision Diagrams", _Journal of Applied Logics — IfCoLog_ 6(5):781–814. Built with the French **Cour de cassation** / IRISA. They compile legal rules to a propositional formula and thence to a **BDD whose nodes _are_ the questions put to the judge** — and add a "Multi-BDD" to reconcile substantive legal reasoning with the _procedural_ order mandated by trial protocol (which is a sharper version of our three-orders distinction, arrived at independently and from the bench). **They do not optimise the question order.** That is precisely, and only, our seam.

**Two verified negatives, both usable in a related-work section:**

- **Nobody has applied BDDs to DMN.** Full-text search of Calvanese et al. (BPM 2016 _and_ the IS 2018 extension) for "binary decision diagram" / "BDD" / "OBDD" returns **zero** occurrences; their method is purely geometric (hyper-rectangles + sweep-line).
- **AI & Law has essentially never used BDDs.** Full-text search of the journal _Artificial Intelligence and Law_ for "binary decision diagram" returns **zero**. The only three exceptions found anywhere are Aucher et al. (2019), Gasiola (2025, _CLSR_ 58 — the EU AI Act's risk classification as a BDD, conceptual rather than compiled), and Mues & Vanthienen (DEXA 2004, BDDs for rule-base anomaly checking). **Three exceptions, in three different communities, none citing the others.**

### The claim we may defend

> **Model-counting information gain over a compiled ROBDD, as the next-question policy for a legal rules engine, appears to be new. Every ingredient is old.** Entropy-driven test ordering is Shwayder 1974; the ROBDD is Bryant 1986; BDD-driven legal interviewing is Aucher et al. 2019; the greedy near-optimality guarantee is Golovin & Krause 2011. What has not been done, so far as we can find, is to put them together — and the reason is plainly that the three communities that hold the pieces (decision-table verification, BDD/formal methods, AI&Law) do not read each other.

Do **not** claim: that question ordering is a new problem; that nobody checks rule bases across tables; that BDDs are new to law; or that greedy info-gain is our invention.

⚠️ **Baseline to beat.** Lamy et al. (2024), _BMC Med. Inform. Decis. Mak._ 24:326, solve "minimise questions asked given a rule base" end-to-end, prove it **NP-hard**, and then find a **frequency heuristic** good enough. Validation on the Housing Act Sch.2 corpus (§5) should measure against a frequency baseline, not just against the old syntactic `[-determinableCount, level]` policy. If we cannot beat frequency, the honest finding is that we cannot, and the interesting contribution moves to _explainability_ (§3.3) rather than to question count.

_Full annotated bibliography with confidence markers ([V] read at primary source / [P] record verified / [U] unverified — do not cite): the DMN/decision-table literature review carried out 2026-07-14._
