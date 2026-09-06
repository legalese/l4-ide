# DMN COLLECT — multi-hit tables for list-valued and aggregate decides

> **Status (2026-09-06): PROPOSED, NOT BUILT. Backlog.** Nothing in this document describes the
> tree except §2, which is a measurement of what the exporter does today, with `file:line`. What
> would make the rest true: the build plan in §7 landing with the goldens in §8. Every ruling in
> §0 is **open**; none has been marked by Meng.
>
> This document owns the question "why does the DMN exporter emit only single-hit tables, and
> what would it take to emit multi-hit ones". It amends `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` in two
> places it names (§2.4's R2, §17.7's `LIST OF τ` note) and does not restate either.

**Author:** Claude, from Meng's request on 2026-09-06
**Date:** 2026-09-06
**Branch:** `spec/dmn-collect`

---

## 0. Ruling status

| ruling                                  | state    | detail |
| --------------------------------------- | -------- | ------ |
| R1 — which policy: `RULE ORDER` vs `C`  | **open** | §5.1   |
| R2 — strictness of multi-hit outputs    | **open** | §5.2   |
| R3 — empty match set is an answer       | **open** | §5.3   |
| R4 — null never enters a collected list | **open** | §5.4   |
| R5 — collection `itemDefinition` first  | **open** | §5.5   |
| R6 — the engine harness compares lists  | **open** | §5.6   |
| R7 — aggregators: which, and typed how  | **open** | §5.7   |
| R8 — chains are never demoted           | **open** | §5.8   |

House style as in the program-model spec: mark a ruling `ANSWERED <date>, see §n`, state the
measurement that drove it, and keep a "what review changed" note.

---

## 1. Motivation and background

### 1.1 The request

Meng, 2026-09-06: "Any reason we shouldn't emit COLLECT?" and then "Please spec DMN COLLECT for
backlog, noting this background and motivation. I suspect we may have previously not done COLLECT
because we didn't get a round tuit. No real reason."

### 1.2 Where the question came from

It came out of a research thread that morning, not out of the exporter. A memo on Alchourrón &
Bulygin's _Normative Systems_ (session scratchpad, `gm/research/alchourron-bulygin-memo.md`,
2026-09-06; not in the tree) worked the EVERY/EACH quantifier question through A&B's table view
and found that the fork's multiplicity — one continuation per performer — is the one coordinate a
"case → solution" table lacks, because a solution in A&B is a _set_ and obliging twice is obliging
once. The table view has a name for the missing coordinate: a **Collect** table is
`Case → Multiset Solution`. The memo then observed that Collect is precisely the hit policy the
exporter does not emit.

That observation is about the constitutive side, not the deontic one. The deontic fork (`EACH`)
routes to BPMN under the R0 ruling ("deontic verdict table → BPMN"), where it is a parallel
multi-instance, not a hit policy. **This spec is about list-valued and aggregate `DECIDE`s only.**
§4.4 says so again where it matters.

### 1.3 Meng's hypothesis, tested against the history

The hypothesis is that the exclusion had no real reason. The record says: three reasons, of which
two do not bite and one survives as a constraint rather than a prohibition.

1. **"L4's guarded chains are single-hit by construction"** (`jl4-core/src/L4/Dmn/IR.hs:564-568`,
   restated at `Lower.hs:48-52`). True, and irrelevant: nobody proposes exporting a chain as
   Collect. It explains why Collect was never _needed_ for the constructs the exporter handles; it
   says nothing about the constructs it refuses.
2. **"Collect tables are outside every published analysis result"** — Semantic DMN restricts
   itself to single-hit policies, and KIE skips gap and overlap analysis for `COLLECT`
   (`specs/research/DMN-STEELMAN.md:308-316`). True, and it does not touch our own gate: the KIE
   check runs `VALIDATE_SCHEMA`, `VALIDATE_MODEL` and `VALIDATE_COMPILATION` only
   (`etc/kie-dmn-check/src/main/java/KieDmnCheck.java:277-279`), never the decision-table
   analysis. The analysis we would lose on a Collect table is one we do not run. It bites the
   _pitch_ — "the fragment you can verify" — and the fidelity report, and §6 says what may and
   may not be claimed.
3. **R2 of the program-model spec made the no-Collect invariant load-bearing.** Its strictness
   refinement classifies "the output entry of a single-hit table, of which exactly one is used"
   as a _safe_ position for a partial expression, and says in terms: "`IR.hs:288`'s no-`Collect`
   invariant is what makes the second one true, and R2 promotes that invariant from tidy to
   **load-bearing** — a `Collect` table evaluates every matching rule's output entry"
   (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md:582-586`). This is a real reason. It survives as **R2 of
   this spec** (§5.2): the output entries of a multi-hit table are strict positions. It is a rule
   about how to lower, not a reason not to.

Verdict on the hypothesis: mostly right. The exclusion was introduced with the exporter's first
commit (`20992358`, 2026-07-25, "DMN 1.3 exporter driven by the GuardedRows normaliser (D1)") as
a scope note, not a ruling; no numbered ruling in the program-model spec excludes Collect. One
real consequence was later hung on it, and this spec carries that consequence forward.

---

## 2. What the tree does today (measured 2026-09-06 on `unstable` @ `cd4d4680`)

- **Two hit policies.** `data HitPolicy = HitUnique | HitFirst` (`IR.hs:568`), chosen by
  `grDisjoint` from `L4.Viz.GuardedRows` (`Lower.hs:9-11`): `U` when the guards are provably
  pairwise exclusive, `F` otherwise. The dmnmd renderer emits `U` or `F`, and demotes `U` to `F`
  when there is an OTHERWISE (`Markdown.hs:164-171`).
- **The input to a table is a chain.** `GuardedRows` is `grRows :: [(guard, body)]` in source
  order ("The order is load-bearing: first match wins"), `grOtherwise`, `grDisjoint`
  (`L4/Viz/GuardedRows.hs:48-56`). `normaliseGuarded` recognises `BRANCH`/`CONSIDER`/`IF`
  chains and nothing else. A `DECIDE` that is not a chain falls to the literal-expression
  path or a refusal (`D-LITERALEXPR`).
- **A `LIST OF τ` result is typed `Any`.** `classifyType` answers `DmnAny` with `tfList` set
  (`Lower.hs:3145-3146`, `:3072`); no collection `itemDefinition` is minted, because
  `isCollection` is an attribute of `tItemDefinition` (`Emit.hs:162-165`); reported `D-ITEMDEF`,
  `Lossy`; recorded as still open in the program-model spec §17.7 (`:6118-6122`), with the fix
  named: an `idfCollection` flag through `IR` and `Emit`, an element type out of `classifyType`,
  one minted definition per distinct element type.
- **The engine harness expects one value per decision.** `jl4/examples/dmn/reg-cf.cases.json`'s
  note: each input context is "paired with the value EVERY decision must produce under it"; both
  harnesses fail on any mismatch, on any decision absent from `expect`, and on any expectation
  naming a decision the model lacks. Whether either harness can compare a **list** expectation
  is **unverified** (§5.6).
- **The witnesses are not in the differential.** The differential runs `reg-cf`, `gst-rate`,
  `regcf-corpus` and the per-example cases (`.github/workflows/pr-checks.yml:1347-1519`).
  `regcf-wizard.l4`, which carries both witnesses below, is not exported anywhere under
  `jl4/examples/dmn/expected/`. So "the witness does not export today" is **unmeasured**; §7
  step 0 measures it.

### 2.1 The witnesses

Two `DECIDE`s in `jl4/examples/legal/regcf/regcf-wizard.l4`, same shape:

```l4
GIVEN plan IS A RaisePlan
GIVETH A LIST OF PAIR STRING BOOLEAN
`blockers considered` plan MEANS
    LIST (PAIR "Your company is not organized under … (17 CFR 227.100(b)(1))."
               (`(b)(1) — not organized under State or territorial law` (`issuer profile from` plan)))
       , (PAIR "Your company already files reports … (17 CFR 227.100(b)(2))."
               (`(b)(2) — an Exchange Act reporting company` (`issuer profile from` plan)))
       …   -- seven rows, :312-334

GIVEN plan IS A RaisePlan
GIVETH A LIST OF STRING
`blockers for` plan MEANS
    mapMaybe `label if it bites` (`blockers considered` plan)
    WHERE
        `label if it bites` item MEANS
            IF item's snd THEN JUST (item's fst) ELSE NOTHING        -- :334-340
```

and `termination conditions met by` over `termination conditions considered` (five rows,
`:536-559`). Each is a **source-literal list of (output, guard) pairs, filtered by the guard,
in source order**. That is a decision table with static rows and a multi-hit policy, and nothing
else. The goldens already pin three answers (`tests/regcf-wizard.nlg.golden:14-16`): empty for a
clean plan, count one for a delinquent plan, count one for an over-limit plan; and
`ep.golden:895` carries `#ASSERT (`blockers for` `a clean plan`) EQUALS EMPTY`.

### 2.2 What is _not_ a witness

`mapMaybe`/`filter`/`sum` over **runtime** lists — a will's dispositions
(`cleanroom-2026-08/intestate-succession-act.l4:1645-1646`,
`sum (map … (filter … (`a will`'s `the dispositions made by the will`)))`), grants
(`wills-act.l4:2402`), guardians (`guardianship-of-infants-act.l4:1654`). These are not decision
tables: their rows are data. They need FEEL list expressions (`for … in`, `sum(…)`) at
conformance level 3, which is a different widening and out of scope here. The corpus count of
these combinators is large (81 lines in `guardianship-of-infants-act.l4` alone, 36 in the ISA,
28 in the PAA) and almost all of it is this runtime shape. The static-rows shape has **three
`mapMaybe` files in the whole corpus**, two of them the wizard; the third (`guardianship`) is
runtime.

---

## 3. What emitting Collect buys

- Two decides that today reach no table at all become tables a business analyst can read: seven
  and five rows, each row a citation and a limb predicate. That is the "list the grounds that
  apply" idiom — Housing Act Schedule 2 grounds, Reg CF blockers, BNA routes to citizenship — and
  it is the most natural decision-table shape in law after the fee schedule.
- The product formula from the A&B memo gains its missing coordinate on the constitutive side:
  `Case → Multiset Solution`. Whether that matters to anyone but us is not the point; the point
  is that the exporter stops silently dropping a shape the corpus uses.
- It does **not** buy any analysis. §6.

---

## 4. The source shapes and their policies

### 4.1 Shape A — list result, order preserved

`mapMaybe g xs`, `catMaybes (map g xs)`, or `filter p xs` where:

- `xs` is a **source-literal** `LIST` (after `WHERE`/`LET` peeling, the same two preparations
  every body gets) whose elements are `PAIR out guard` (or a record with exactly one BOOLEAN
  field and one output field — a possible extension, not proposed here);
- `g` is `IF item's snd THEN JUST (item's fst) ELSE NOTHING` up to α-renaming and projection
  order, or `p` is `item's snd`.

Rows: `(guard_i, out_i)` in source order. Policy: **`RULE ORDER`** (R1). Output: `LIST OF τ`
where τ is the type of `out_i`.

### 4.2 Shape B — numeric aggregate over static rows

`sum (map v (filter p xs))`, `count (filter p xs)`, and — only under R7 — `maximum`/`minimum`
of the same, with `xs` literal as in 4.1. Rows: `(guard_i, v(out_i))`. Policy: **`COLLECT`**
with aggregator `SUM`, `COUNT`, `MAX`, `MIN`. Output: a single `number`.

### 4.3 Shape C — boolean any-join (noted, not proposed)

`any p xs` over a literal is a single-hit disjunctive row, or DMN's `ANY` policy over rows that
all output `true`. The exporter already lowers `any` under a list quantifier (#936, Gap 2,
`Lower.hs:225-244`) by inlining; leave it.

### 4.4 Out of scope, by ruling elsewhere

- **Chains.** `BRANCH`/`CONSIDER`/`IF` are first-match and stay `U`/`F`. Under `F` an overlap is
  _resolved_; under Collect it _contributes_. Converting one to the other changes the answer. R8.
- **The deontic fork.** `EACH p MUST … HENCE h` is a BPMN parallel multi-instance under R0. Not a
  table. The A&B memo's "fork = Collect" is a table-view analogy and must not become a lowering.
- **Runtime lists.** §2.2.

---

## 5. Rulings proposed

### 5.1 R1 — `RULE ORDER` for lists, `COLLECT` only under an aggregator

DMN 1.3 §8.2.10 (recalled; verify the wording before build): `C` returns the outputs of all
satisfied rules **in arbitrary order**; `R` (rule order) returns them **in the order of the rules
in the table**; `O` (output order) by decreasing output priority; an aggregator on `C` reduces the
list to one value. `mapMaybe` over a literal preserves source order, and a golden that compares
lists positionally observes it. So: Shape A emits `R`, never bare `C`; Shape B emits `C` with an
aggregator, never bare `C`. Bare `C` is not emitted at all, because L4 has no construct whose
result is an unordered collection.

### 5.2 R2 — output entries of a multi-hit table are strict positions

Extends the program-model spec's R2 (§2.4). Its "safe" class rests on "the output entry of a
single-hit table, of which exactly one is used". A multi-hit table evaluates the output entry of
every matching rule, so for tables emitted under this spec **the output entries join the strict
class**: a partial expression in an `out_i` refuses the decision exactly as a partial input entry
does today. In the two witnesses every `out_i` is a string literal or a `CONCAT` of literals and
total `dollars` renderings, so both pass; state the rule anyway, because the next witness will
not be so tidy. The `IR.hs` comment that carries the invariant is rewritten to say _which_ tables
it now covers.

### 5.3 R3 — an empty match set is an answer, and the report must say so

Under `R`, no matching rule yields the empty list; under `C+` the sum `0`; under `C#` the count
`0`. In L4, `sum EMPTY` and `count EMPTY` are `0` by definition (`prelude.l4:119`, `:265`, the
`go 0` accumulator), and `mapMaybe` over no hits is `EMPTY`. So the identities agree and the
empty case needs no row. **This is not a gap.** The clean plan's empty blocker list is the
_desired_ answer (`nlg.golden:14`), and in A&B's terms the empty multiset is a solution, not the
absence of one. The fidelity report therefore must not describe a multi-hit table with the
vocabulary it uses for `U`/`F` tables: no "missing rows" note, no "hit policy demoted" note.
A new advisory line, one per multi-hit table: _multi-hit; overlap is by construction; an empty
result is an answer._

### 5.4 R4 — null never enters a collected list

The recogniser admits only the shape in which `NOTHING` means "row absent" (§4.1). A `NOTHING`
therefore never becomes an element. Any other route by which a FEEL `null` could enter the
output list — an `out_i` of `MAYBE` type, an `out_i` that can evaluate to `null` under the
existing `D-MAYBE-NULL` story — refuses the decision, extending `D-MAYBE-NULL`'s message to name
the row. Rationale: a `null` element in a FEEL list is silent, and every consumer downstream of
this exporter has been built on "the export must never emit a table that says something the L4
does not" (`Lower.hs:57-59`).

### 5.5 R5 — mint the collection `itemDefinition` first

A Shape A table's output is a `LIST OF τ`, which today is `typeRef="Any"` with `D-ITEMDEF`
(§2). Both engines tolerate `Any`, so this is not a blocker, but shipping a feature whose _entire
output_ is untyped when the fix is already designed (program-model §17.7: `idfCollection`,
element type out of `classifyType`, one definition per element type) is the wrong order.
Proposal: land §17.7's collection `itemDefinition` as the first PR of this work, then the tables.
It moves `sumtype.fidelity.txt`, as §17.7 predicts.

### 5.6 R6 — the harness compares lists, and both engines agree on order

`cases.json` expectations are scalars today (§2). Both `KieDmnCheck.java` and
`CamundaDmnCheck.java` need a list-equality arm — order-sensitive for `R`, since that is what
`R` promises — and a case file for the wizard with, at minimum, the three answers the goldens
already pin. Whether Camunda 7's engine and KIE agree on `R` ordering for the same table is the
first thing that arm will measure; the note in `reg-cf.cases.json` about Camunda 8 tokenising
space-bearing names is the precedent for why the comparison is by value and not by status.

### 5.7 R7 — aggregators: `SUM` and `COUNT` first; `MAX`/`MIN` only from the `MAYBE` prelude forms

DMN's `+` and `#` have identities that match L4's (`0`). `>` and `<` over no matching rule return
`null` in DMN, and L4's `maximum`/`minimum` over `LIST OF NUMBER` are `@nonexhaustive` with no
`EMPTY` arm (`prelude.l4:332-338`, `:341-347`) — a partial decision, which R2 of the program-model
spec refuses at the boundary anyway. The `LIST OF MAYBE NUMBER` forms (`:381-387`, `:349-355`)
return `NOTHING` on `EMPTY`, and `NOTHING ↔ null` is the mapping `D-MAYBE-NULL` already governs.
So: lower `sum`/`count` unconditionally; lower `maximum`/`minimum` only when the L4 uses the
`MAYBE`-typed variant, else refuse with the existing partiality message. DMN restricts aggregation
to a single numeric output (recalled; verify): so Shape B requires exactly one output column and
`v(out_i)` of type `number`.

### 5.8 R8 — a chain is never demoted to Collect, and the differential proves it

The whole existing corpus must export byte-identically after this lands, except for the new
tables and the §17.7 `itemDefinition` change. That is the acceptance test that the recogniser
fired only on Shape A/B and never on a chain. Run the full DMN differential, not the three named
cases: the standing rule from the props programme applies ("run corpus differentials over ALL
files, not just files with the construct").

---

## 6. What may be claimed about a multi-hit table

Nothing about gaps or overlaps, from any tool: Semantic DMN excludes multi-hit from its
formalisation; KIE skips its gap/overlap analysis for `COLLECT` and throws on generalised unary
tests; Trisotech's manual says DT analysis is unavailable in the same conditions
(`DMN-STEELMAN.md:308-316`). The exporter's own `grDisjoint`-driven `U`-vs-`F` reasoning does not
apply either — there is no "first match" to reason about. The per-file line the exporter already
emits when a table crosses the analysable line is the right instrument: a multi-hit table is
outside the analysable fragment **by policy, not by cell content**, and the fidelity report says
which. What _can_ be claimed, and should be: the two engines evaluate it to the same list as
`l4 run`, per §5.6.

---

## 7. Build plan

0. **Measure.** Run `l4 dmn` on `regcf-wizard.l4` and record, in this section, which code fires
   on `blockers for` today (`D-LITERALEXPR` is the expectation, not a fact).
1. **`idfCollection`** per program-model §17.7 — its own PR; moves `sumtype.fidelity.txt`.
2. **IR.** `HitPolicy` gains `HitRuleOrder` and `HitCollect Aggregator`, with
   `data Aggregator = AggSum | AggCount | AggMax | AggMin`; `hitPolicyAttr` emits `RULE ORDER`
   and `COLLECT`; `Emit` adds the `aggregation` attribute on `COLLECT`.
3. **Recogniser** in `Lower`, beside `normaliseGuarded`, not inside it: `normaliseCollect ::
Expr Resolved -> Maybe CollectRows` over the two shapes of §4, after the standard peeling.
   Pure and total; `Nothing` leaves every existing path untouched (R8).
4. **Strictness.** The output entries of a `CollectRows` table are fed to the R2 classifier as
   strict positions (R2).
5. **Fidelity.** The R3 advisory line; the R4 refusal message; no `U`/`F` vocabulary on these
   tables.
6. **dmnmd.** `Markdown.hs`'s policy cell gains `R`, `C+`, `C#`, `C>`, `C<`. **Check first**
   that dmnmd reads them back — `etc/validate-dmn.mjs` skips when dmnmd is absent, and
   `legalese/l4-ide` must never depend on `smucclaw/dmnmd` (repo CLAUDE.md §1.2).
7. **Harness.** List-equality arm in both engine checks (R6); `jl4/examples/dmn/regcf-wizard.l4`
   plus `regcf-wizard.cases.json`; wire into the differential job.
8. **Goldens** for the new expected artifacts; **full-corpus differential** (R8).
9. **Docs.** `doc/exports/dmn-bpmn.md` gains a paragraph: which L4 idiom becomes a multi-hit
   table, what its report line means, and that no gap/overlap claim attaches. Repo CLAUDE.md §6:
   a feature is not done until `doc/` explains it.

---

## 8. Acceptance

- Both witnesses export as `RULE ORDER` tables of seven and five rows; `blockers for` on the
  three golden plans returns, from KIE and from Camunda, the same lists `l4 run` returns.
- Every existing expected artifact under `jl4/examples/dmn/expected/` is unchanged except for
  the §17.7 `itemDefinition` delta, measured by the full differential.
- A hand-written `BRANCH` with overlapping guards still exports `F`, and a test asserts it.
- The fidelity report for the wizard carries the R3 line and no `U`/`F` note for those tables.

---

## 9. Open questions, not rulings

- Should the `PAIR out guard` shape be widened to a record with a designated BOOLEAN field? The
  wizard's shape is `PAIR`; the Housing Act grounds are records. Measure before widening.
- Is there a place for an L4 surface form — a `COLLECT`-shaped `DECIDE` — rather than idiom
  recognition? Proposal: no. The idiom is already in the skill's phrasebook territory ("list the
  grounds that apply" → `mapMaybe` over literal pairs); recognising it costs nothing at the
  source, and a keyword would be one more thing to teach. Revisit if the recogniser grows a
  third shape.
- The deontic **any-join** — one sufficient performance by any party lets all proceed, `ROR`
  folded across a party set — has no quantifier today (register, 2026-09-06). It is a BPMN
  matter, not a table one, and is recorded here only so nobody reaches for `ANY` hit policy to
  express it.

---

## 10. Related documents

- `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` — R2 (§2.4) and §17.7, both amended by this
  spec; the fidelity-code table (§3).
- `specs/research/DMN-STEELMAN.md` — what the analysis literature covers and what the tools do
  with `COLLECT`.
- `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` and `EVERY-EACH-JOINT-SEVERAL-MEMO.md` — the
  quantifier question this grew out of; the deontic side that this spec does not cover.
- The Alchourrón–Bulygin memo of 2026-09-06 (session scratchpad, not in tree) — the "Collect is
  `Case → Multiset Solution`" observation, §6.3 there.
