> **Status (re-audited 2026-09-08 on `lang/every-runtime`, cut from `unstable` `6e9b57bb`):**
> the **FRONT END IS MERGED** — `every/build-1` landed on `unstable` as PR #360 (merge `734b8015`,
> 2026-09-07), so the lexer, parser, name resolution, type checker, printers, NLG, document export
> and state graph all carry `EVERY` and the join line on `unstable` today. **EVALUATION IS BUILT**
> on `lang/every-runtime`, MERGED to `unstable` 2026-09-08 as PR #370 (merge `6247ba69`): §3.1's barrier, §3.2's
> fork, §3.3's distributive form, all four modals, R-T2's join deadline and nesting all run; see
> §11.0.1 for exactly what was built and what was not, and §11.0 for the roll-call rule that made
> it possible. The four witnesses are `jl4/examples/ok/every/run-{barrier,fork,roll,modals}.l4`.
>
> **THE ROLL IS NOW SAYABLE OUTRIGHT.** `EVERY Cast v IN xs` was RULED by Meng on 2026-09-08 and is
> BUILT on `lang/every-in` (branched from `lang/every-runtime`), MERGED to `unstable` 2026-09-08 as PR #374 (merge `28c48e3f`):
> see **§11.0.2**, with `jl4/examples/ok/every/run-in.l4` as its witness and §2.4's grammar
> updated. `IN` is the spelling to reach for. The older inferred spelling of §11.0 —
> `WHO elem t xs` — is **DEPRECATED** as of 2026-09-08 (§13.5). It still runs unchanged for a rule
> that writes no `IN`, and nothing warns you, but the corpus and the documentation have been
> migrated off it and removal is not scheduled.
>
> The pre-#360 bullets below are **kept as the record of the tree the design was written against**;
> the first two are now false of `unstable` and say so.
>
> - **FALSE since #360 (2026-09-07).** `EVERY`, `WHO`, `ONCE`, `HAVE`, `SOME`, `ALL` and `UPON`
>   are lexer keywords on `unstable` — `SOME` included (`Lexer.hs:350`), even though §2.2.7.4's
>   count join is not built. `EACH` is matched by spelling and is still not a keyword; `NO` and
>   `WHOSE` are still not keywords. The bullet as written described `unstable` before the merge:
>   `EVERY`, `EACH`, `NO`, `ONCE`, `HAVE`, `WHO`, `WHOSE` and `SOME` are not lexer keywords (the keyword
>   table in `jl4-core/src/L4/Lexer.hs`; `identifierOrKeyword` at `Lexer.hs:670-675` (since #360; `:654-659` before it) is an exact map
>   lookup, so there are no soft keywords). `ALL` is `TKAll` (`Lexer.hs:317`), consumed by `FOR ALL`
>   (`Parser.hs:1244-1245`) and `RECALL ALL` (`Parser.hs:2375`).
> - **FALSE since #360, and its last sentence false since 2026-09-08.** The bullet as written:
>   `obligation` takes exactly one party expression after `PARTY` (`Parser.hs:2503-2513`); `HENCE` and
>   `LEST` are parsed there and nowhere else (`Parser.hs:2538-2544`). No barrier, fork, filter or
>   `BarrierObligation` runtime exists. The syntax appears only in non-compiling sketches under
>   `jl4/experiments/` (`regulative-powers.l4:4`, `deontic-may.l4:99-101`, `jerseyAlcohol.l4:42`).
>   — There is now a filter and a barrier/fork runtime (§11.0.1); it is not shaped like §4.1's
>   `BarrierObligation`, and §11.1's `BarrierRuntime` record is still a design sketch, not a type in
>   the tree.
> - **Rulings so far:** R-T1–R-T6 (§2.2.7.8, 2026-09-06); the pattern spelling (§2.4, 2026-09-07);
>   **R-Q1–R-Q7 (§2.5, 2026-09-07)**; **R-Q7A–R-Q7C, the anchor's spelling (§5.1.1, 2026-09-07;
>   BUILT 2026-09-15 on `every/anchors`, witness `jl4/examples/ok/every/run-anchors.l4`; the
>   mechanism and the build decisions are recorded under §5.1.1 and §11.0.1)**; **§5.2's `LEST`
>   clock — R-Q7's unanchored default and R-Q5's failure time — BUILT 2026-09-16 on
>   `every/lest-anchor`, witness `jl4/examples/ok/every/run-lest.l4`, mechanism and decisions
>   under §5.2.1**; **R-X5 (the window's edges, modified) and R-X6 (the early act, ruled),
>   §5.1.2, 2026-09-07; R-X5 AMENDED 2026-09-16 — bare `AFTER d1 WITHIN d2` re-anchors,
>   two-offset is `WITHIN d2 OF THE JOIN` (§5.1.2.2); BUILT 2026-09-16 on `every/after-before`,
>   witness `jl4/examples/ok/every/run-after.l4`, mechanism and the T1 decision — a run-time
>   refusal of a date on a clock below `DATE_SERIAL (YMD 1 1 1)` — under §5.1.2's build block and
>   §11.0.1**; and three on 2026-09-08 — **W3, `THE OPENING` declined and
>   the anchor slot ruled to become a trace expression (§5.1.3, direction only, not built)**, and
>   **the roll call, how a run gets its cast (§11.0, ANSWERED and BUILT)**, and
>   **the roll said outright, `EVERY Cast v IN xs` (§11.0.2, RULED by Meng and BUILT)**.
>   Under R-Q1 there is
>   one quantifier word, `EVERY`, and a
>   mandatory join line under it whenever a continuation follows: `ONCE ALL HAVE` (barrier) or
>   `UPON EACH` (fork). The fork's words were RULED on 2026-09-07 and are no longer provisional;
>   `ONCE EACH HAS` does not parse. `EACH` is not a keyword and not a quantifier. The file keeps its
>   historical name.

# EVERY/EACH Quantifier Specification

**Status:** Draft
**Authors:** Meng Wong, with analysis from concurrency-legal-modeling agent
**Date:** 2025-01-26
**Branch:** mengwong/every-each

## 1. Motivation

### 1.1 The Problem

Legal contracts and legislation frequently contain clauses that range over quantified parties:

- "Each party shall keep confidential..."
- "Every shareholder must vote before the deadline..."
- "All signatories shall be bound by these terms..."

CSL (Hvitved's Contract Specification Language) provides primitives (conjunction ∧, disjunction ∨) to express such obligations, but the expression is verbose, requiring manual template instantiation for each party.

### 1.2 The Solution

L4 should provide first-class quantification constructs that:

1. Mirror natural legal language (isomorphism with source text)
2. Have precise formal semantics (trace-based, following CSL's CSP lineage)
3. Support proper blame attribution
4. Handle temporal forking when permissions are exercised
5. Compose cleanly with existing L4 constructs (HENCE, LEST, IF/THEN/ELSE)

### 1.3 Intellectual Lineage

CSL's trace-based semantics descend primarily from **CSP** (Hoare), not CCS (Milner). Key indicators:

- Denotational semantics via traces (not operational/LTS)
- External choice operator
- Alphabet-based parallel composition
- Trace refinement as the equivalence notion

L4's quantifiers should maintain this CSP lineage while adding legal-domain extensions (blame attribution, deadline handling, multi-party modeling).

## 2. Syntax

### 2.1 Basic Quantified Obligation

Since deontic expressions are already typed via `GIVETH DEONTIC PartyType ActionType`, the quantifier variable's type is inferred from context:

```l4
DECLARE Person
    HAS name IS A STRING

DECLARE Action IS ONE OF
    sign
    approve
    pay HAS amount IS A NUMBER

GIVETH DEONTIC Person Action
example MEANS
    EVERY p                         -- p has type Person (from DEONTIC); EVERY Person p selects a cast (§2.4)
        WHO    condition            -- a Boolean expression in which p is free (R-Q4)
        MUST   action
        WITHIN deadline
        ONCE   ALL HAVE             -- the join; mandatory when a HENCE or LEST follows (R-Q1)
        HENCE  success_continuation
        LEST   failure_continuation
```

> **Rewritten 2026-09-07 under R-Q4 (§2.5).** Until that date this section said the `WHO` slot held
> a point-free predicate with the bound variable inserted as its **first** argument
> (`WHO member_of signatories` → `member_of p signatories`). The refuters found that the rule cannot
> type this section's own advertised example, `WHO is_adult AND is_shareholder AND NOT is_conflicted`:
> `AND` and `NOT` are Boolean connectives, and under insertion they would be applied to functions,
> not to Booleans. The insertion rule is withdrawn; nothing else in this section changes its intent.

The `WHO` clause takes a **Boolean expression in which the bound variable is free**. The variable is
written where it is used, as in any other L4 expression; nothing is inserted for the drafter.

For set membership, apply the prelude's `elem` (`jl4-core/libraries/prelude.l4:465`) to the variable
(this document's `member_of` is `elem` under an illustrative name):

> **Read the example below for what a `WHO` condition is, NOT for how to give a rule its group.**
> It is kept in the `elem` spelling because `elem`-as-a-condition is its subject. Since 2026-09-08
> the group is written on its own clause — `EVERY p IN signatories` (§11.0.2) — and a bare
> `WHO elem p signatories` with no `IN` is the **deprecated** inferred roll of §13.5. The two are
> not in competition: `IN` says which list the group is drawn FROM, and a `WHO` condition, `elem`
> or otherwise, narrows what was drawn.

```l4
GIVEN signatories IS A LIST OF Person

GIVETH DEONTIC Person Action
sign_all MEANS
    EVERY p
        WHO    elem p signatories       -- "is p one of the signatories?"
        MUST   sign
        WITHIN 30 days
        ONCE   ALL HAVE
        HENCE  closing_complete
        LEST   deal_falls_through
```

This design is more expressive than explicit set binding because:

1. **Type inference**: no redundant type annotation; `p`'s type comes from the deontic context, or
   from the constructor in the pattern form `EVERY Person p` (§2.4)
2. **Any Boolean expression works**: a field comparison (`WHO t's arrears > 0`), a prelude call, a
   named helper applied to the variable (``WHO `owes rent` t``)
3. **Sets are one case of it**: `WHO elem p some_list` is explicit set binding
4. **Richer constraints**: `WHO is_adult p AND is_shareholder p AND NOT is_conflicted p`
5. **Composable**: conditions combine with `AND`/`OR`/`NOT` as Booleans, which is what they are

One scoping fact the refuters measured and this section must state: a helper that needs the bound
variable is **parameterised**, not closed over. A trailing `WHERE` block is attached to the completed
expression (`Parser.hs:1334-1338`, the only consumer of `TKWhere`) and cannot see a binder inside it —
probed 2026-09-07 with a `CONSIDER` pattern binder referenced from a trailing `WHERE`: `I could not
find a definition for the identifier r`. So ``WHO `owes rent` t`` with `` `owes rent` x MEANS x's
arrears > 0 `` in the `WHERE` is right, and `` WHO `owes rent` `` with a `WHERE` that mentions `t` is
not.

### 2.2 Distributive vs Collective: Real-World Legal Patterns

Before defining syntax, we must understand how quantified deontics appear in real legal texts. Legal language uses quantifiers with all three deontic modalities:

- **MUST** (obligation): "Each party shall maintain confidentiality..."
- **MAY** (permission): "Any party may terminate upon notice..."
- **SHANT** (prohibition): "No party shall disclose..."

We analyze patterns for each modality.

#### 2.2.1 Obligation Patterns (MUST)

**Pattern A: Distributive Obligation (Most Common)**

> "Each party shall maintain the confidentiality of all Confidential Information."

**Lawyer's interpretation:** Every individual party has their own separate obligation. If Alice breaches, Alice is liable; Bob and Carol's obligations are unaffected.

**Layperson's interpretation:** Same - "each of us has to keep secrets."

**CSP formalization:**

```
CONF(Alice) ||| CONF(Bob) ||| CONF(Carol)
-- where CONF(p) = ((maintain_confidentiality.p → CONF(p)) □ (breach.p → STOP))
```

Pure interleaving - each party's obligation is independent.

**Pattern B: Constitutive Rule Masquerading as Obligation**

> "All directors must approve the resolution before it takes effect."

**Lawyer's interpretation:** This is actually a **constitutive** rule ("must be"), not a **regulative** rule ("must do"). Directors bear no penalty for not approving—the resolution simply doesn't pass. The "must" here defines what counts as a valid resolution, not what directors are obligated to do.

**Layperson's interpretation:** "For this to be official, everyone needs to say yes."

**Constitutive vs Regulative distinction:**

- **Constitutive:** Defines what counts as X (e.g., "a goal must cross the line to count")
- **Regulative:** Imposes obligation to do X (e.g., "players must not handle the ball")

See [BOUNDED-DEONTICS-SPEC](BOUNDED-DEONTICS-SPEC.md) for a full treatment of this distinction, including how L4's two-level architecture (object-level contracts vs LTL/CTL assertions) allows constitutive rules to be phrased in regulative syntax when that fits human intuition.

To cast this constitutive notion into regulative form using permissions:

```l4
EVERY director
    MAY    approve the_resolution
    HENCE  the_resolution passes
```

This uses **barrier/join semantics**: all approvals must be collected before HENCE fires once. No director is _obligated_ to approve; each _may_ approve. Only when all have done so does the resolution pass.

**Contrast with fork semantics (EACH):**

```l4
EACH director
    MAY    approve the_resolution
    HENCE  company MUST notify all_other_directors that someone has approved
           WITHIN 24 hours
```

Here, **each approval triggers its own HENCE independently**—if 5 directors approve, the company sends 5 notifications. This is fork semantics, not barrier semantics.

**Pattern C: Joint and Several Liability**

> "The Guarantors shall be jointly and severally liable for the Debt."

**Lawyer's interpretation:** The creditor can pursue any guarantor for the full amount, or all of them proportionally. Each guarantor is individually liable for 100%, but the creditor can only collect 100% total.

**Layperson's interpretation:** "Any of us can be made to pay the whole thing."

**CSP formalization:** This requires tracking a shared resource (the debt amount):

```
GUARANTEE(debt) =
    (pay.g1?amount → GUARANTEE(debt - amount))
    □ (pay.g2?amount → GUARANTEE(debt - amount))
    □ (pay.g3?amount → GUARANTEE(debt - amount))
    □ ([debt <= 0] → SKIP)
```

**Pattern D: Collective Action (Truly Joint)**

> "The parties shall jointly execute the Closing Documents."

**Lawyer's interpretation:** All parties must participate in a single, coordinated act. This is not multiple independent signings; it's one event requiring all participants.

**Layperson's interpretation:** "We all sign together at the closing."

**CSP formalization:**

```
joint_execution.{Alice, Bob, Carol} → closing_complete
-- A single synchronized event requiring all parties
```

#### 2.2.2 Permission Patterns (MAY)

**Pattern E: Distributive Permission**

> "Each party may assign its rights under this Agreement with prior written consent."

**Lawyer's interpretation:** Every party individually has the permission to assign. Alice's decision to assign doesn't affect Bob's permission.

**Layperson's interpretation:** "Any of us can assign if we get consent."

**Key insight (Hvitved):** A MAY is meaningful because it creates correlative obligations on counterparties. "A may assign" implies "B and C must not prevent A's assignment" and "B and C must recognize the assignment as valid."

**Pattern F: First-to-Act Permission**

> "Any party may terminate this Agreement upon 30 days' written notice."

**Lawyer's interpretation:** Each party has permission to terminate. Once one party exercises it, the termination affects all parties.

**Layperson's interpretation:** "Whoever wants out first can end it for everyone."

**CSP formalization:**

```
TERMINABLE = (terminate.Alice → TERMINATED)
           □ (terminate.Bob → TERMINATED)
           □ (terminate.Carol → TERMINATED)
```

External choice - first event determines the outcome.

**Pattern G: Exhaustible Permission**

> "The Licensee may make up to three copies of the Software."

**Lawyer's interpretation:** Permission with a quota. Each exercise consumes one unit of the permission until exhausted.

**Layperson's interpretation:** "We can copy it, but only three times total."

#### 2.2.3 Prohibition Patterns (SHANT)

**Pattern H: Distributive Prohibition**

> "No party shall disclose Confidential Information to any third party."

**Lawyer's interpretation:** Each party is individually prohibited. This is logically equivalent to "Each party shall not disclose..."

**Layperson's interpretation:** "None of us can tell outsiders."

**CSP formalization:**

```
-- For each party p, the action disclose.p is not in the allowed alphabet
CONF(p) = (work.p → CONF(p))  -- disclose.p is simply not offered
```

**Pattern I: Collective Prohibition**

> "The parties shall not collectively hold more than 49% of the voting shares."

**Lawyer's interpretation:** The prohibition applies to the aggregate. Individual holdings are fine as long as the sum stays under the threshold.

**Layperson's interpretation:** "Together we can't own too much."

**Pattern J: Cross-Party Prohibition**

> "No party shall solicit the employees of any other party."

**Lawyer's interpretation:** Each party is prohibited from soliciting employees of each other party. Creates n × (n-1) prohibition instances.

**Layperson's interpretation:** "Don't poach each other's staff."

**L4 formalization:**

```l4
EVERY p_x
    SHANT  solicit_employees_of p_y
    WHO    differs_from p_x p_y      -- WHO, not WHERE (R-Q4, 2026-09-07); p_y is bound by an
                                     -- enclosing EVERY, as in §2.3
```

(Until 2026-09-07 this example wrote `EACH p_x … WHERE …`; it was the only `WHERE` filter in the
document against nine `WHO` spellings, and R-Q1 retired `EACH` as a quantifier word.)

**`NO` as sugar over the prohibition — RULED 2026-09-07 (R-Q3, §2.5).** The contract idiom "No
tenant may sublet" is admitted, as sugar and not as a third prohibition mechanism:

```l4
NO Tenant t IN tenants MAY sublet WITHIN term
    UPON  EACH                                -- the fork join, fixed by the sugar (R-Q1, RULED 2026-09-07)
    LEST  BREACH BY t                             -- the violator; the others are untouched
    HENCE `the term ended without a sublet`       -- SHANT's HENCE: the prohibition held

-- exactly:
EVERY Tenant t IN tenants SHANT sublet WITHIN term
    UPON  EACH
    LEST  BREACH BY t
    HENCE `the term ended without a sublet`
```

Two things the sugar must get right, both found by the refuters (the first draft of the ruling said
"no new semantics"; that was withdrawn):

1. **The continuation table is keyed off the modal.** Under `SHANT` (`DMustNot`) the deadline passing
   without the act routes to `HENCE` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:1592-1595`) and the act
   itself routes to `LEST` (`Machine.hs:1648-1651`); under `MAY` the act routes to `HENCE`
   (`Machine.hs:1669-1671`) and expiry to `LEST` (`Machine.hs:1596-1600`). The reader sees `MAY`; the
   machine runs `SHANT`. A `HENCE` under `NO` therefore means what `SHANT`'s does — the prohibition
   held to the deadline — and the page that introduces `NO` teaches the polarity in the same paragraph
   that introduces the word.
2. **A prohibition on a class fails on the first violation by one member.** That is the fork's blame
   (§6.3), not the barrier's set (§6.1); the sugar fixes the join as `UPON EACH`.

**Refused**, with a message that names what the sentence is: `NO … MUST` ("no tenant is obliged to
pay" — a liberty, Hohfeld's privilege, which L4 does not model), `NO … SHANT` and `NO … MUST NOT`
(double negatives). `NO … MAY NOT` cannot arise: there is no `MAY NOT` production (`Parser.hs:2520-2527`
parses `MUST NOT` and `SHANT` to `DMustNot`, and `MAY` alone).

**Meng's note on the mark, verbatim:** _"The NO P MUST A form feels like it belongs more to the
bounded deontics discussion of dominators."_ So the liberty form is **deferred**, not refused for
good. Its home is the "Deontics as Domination" paper (`paper/bounded-deontics/`, listed at
`paper/README.md:18`), whose second-order section reads a `MUST` as a fact about a fixed transition
system — the obligated act is the graph dominator of the goal
(`paper/hohfeld-higher-order/section-powers-as-higher-order-deontics.tex:23-25`). "No P is obliged
to a" is the statement that no act of P's dominates the goal: a claim about the graph, not a clause
to arm, and that discussion is where it is to be taken up.

**Owed regardless:** `SHANT` appears nowhere in §3–§9. The barrier and fork rules there are written
over `MUST` completion, and extending them to the polarity flip — a `SHANT` fails at the act and
succeeds at the deadline — is owed before this sugar is built.

#### 2.2.4 Representing These Patterns in Current L4

**Pattern A (Distributive)** - Expressible but verbose:

```l4
-- Manual expansion for 3 parties:
(PARTY Alice MUST maintain_confidentiality WITHIN contract_term)
RAND
(PARTY Bob MUST maintain_confidentiality WITHIN contract_term)
RAND
(PARTY Carol MUST maintain_confidentiality WITHIN contract_term)
```

**Problems:**

- Verbose: O(n) clauses for n parties
- Error-prone: easy to miss a party or introduce inconsistencies
- Not isomorphic: source text says "each party" once; L4 repeats it n times
- Maintenance burden: adding a party requires adding another clause

**Pattern B (Barrier)** - Expressible but very verbose:

```l4
-- Using recursion over a list:
GIVEN directors IS A LIST OF Director
`all must approve` MEANS
    CONSIDER directors
        WHEN []          THEN resolution_takes_effect
        WHEN (d :: rest) THEN
            PARTY d MUST approve WITHIN 14 days
            HENCE `all must approve` rest
            LEST resolution_fails
```

**Problems:**

- Imposes artificial sequencing (d1 must approve before d2 can)
- The legal text implies parallel, independent approvals converging at a barrier
- HENCE chains don't naturally express "all complete, then continue"
- Blame attribution is per-step, not "who among the set failed"

**Pattern C (Joint and Several)** - Difficult to express:

```l4
-- Would need explicit state tracking:
GIVEN debt IS A NUMBER
      guarantors IS A SET OF Party
`guarantee` MEANS
    IF debt > 0 THEN
        -- But how to express "any of them may pay any amount"?
        -- And track cumulative payments?
        -- This requires external state management
```

**Problems:**

- L4's deontic model doesn't naturally handle shared mutable state
- "Any may satisfy" is disjunctive permission with cumulative effects
- Current primitives don't compose well for this pattern

**Pattern D (Truly Joint Action)** - Not directly expressible:

```l4
-- No way to express "single synchronized action by all parties"
-- Would need to model as:
PARTY (parties_as_collective_entity) MUST execute_closing
-- But L4's PARTY expects an individual, not a set
```

**Problems:**

- L4's PARTY construct takes a single entity
- No primitive for "synchronized multi-party action"
- Would require defining a synthetic collective entity

#### 2.2.5 Why New Syntax is Needed

The analysis above reveals that current L4 primitives are:

| Pattern            | Expressible?    | Ergonomic?             | Isomorphic? |
| ------------------ | --------------- | ---------------------- | ----------- |
| A: Distributive    | Yes             | No (verbose)           | No          |
| B: Barrier         | Partially       | No (forces sequencing) | No          |
| C: Joint & Several | With difficulty | No                     | No          |
| D: Truly Joint     | No              | N/A                    | N/A         |

**The EVERY/EACH syntax addresses patterns A and B directly:**

```l4
-- Pattern A: Distributive (no HENCE/LEST barrier)
EACH p
    MUST   maintain_confidentiality
    WITHIN contract_term

-- Pattern B: Barrier (with HENCE/LEST)
EVERY d
    WHO    member_of directors
    MUST   approve
    WITHIN 14 days
    HENCE  resolution_takes_effect
    LEST   resolution_fails
```

**Benefits:**

- **Concise:** One clause regardless of party count
- **Isomorphic:** Mirrors source legal text structure
- **Correct semantics:** Barrier behavior for Pattern B is built-in
- **Proper blame:** Non-completers identified automatically

#### 2.2.6 EVERY vs EACH: Barrier vs Fork Semantics

> **SUPERSEDED 2026-09-07 by R-Q1 (§2.5).** The two-word scheme this section describes — `EVERY` for
> the barrier, `EACH` for the fork — is no longer the design. (Its code blocks are kept verbatim as
> the record of what was superseded, so they also still write the roll in the pre-2026-09-08
> `WHO elem d board` spelling, deprecated by §13.5. Do not copy the spelling out of a superseded
> block; the current one is `IN board`.) There is **one quantifier word,
> `EVERY`**, and the join is written on a **mandatory `ONCE` line** between the quantified act and its
> continuation:
>
> ```l4
> EVERY Director d WHO elem d board MUST sign WITHIN 30 days
>     ONCE ALL HAVE                        -- barrier: fires once, when the last has signed
>     HENCE `resolution passes`
>     LEST  BREACH                         -- blame = the non-signers (§6.1)
>
> EVERY Director d WHO elem d board MAY approve WITHIN 30 days
>     UPON EACH                        -- fork: once per approval, d bound to the approver
>     HENCE PARTY company MUST notify d WITHIN 24 hours
>
> EVERY Director d WHO elem d board MAY approve
>     HENCE PARTY company MUST notify d    -- REFUSED: a bare HENCE or LEST directly under EVERY
>                                          -- is a check error that names the two spellings above
> ```
>
> The **structure** is ruled: one quantifier, a mandatory join line, no silent default in either
> direction. The fork's **words** were RULED `UPON EACH` on 2026-09-07; see §2.5
> for the alternatives put to him. `HENCE FOR EACH` (the memo's spelling, used in §2.2.7 until this
> date) is withdrawn. What follows in this section is kept as the record of the two-word scheme and of
> the research that ruled it out; read its `EACH … HENCE …` as `EVERY … UPON EACH HENCE …` and its
> bare `EVERY … HENCE …` as `EVERY … ONCE ALL HAVE HENCE …`.

`EVERY` and `EACH` were, until 2026-09-07, **not synonyms**—they had distinct continuation semantics:

| Quantifier | Semantics         | HENCE behavior                                               |
| ---------- | ----------------- | ------------------------------------------------------------ |
| `EVERY`    | Barrier/Join      | Collects all completions, fires HENCE **once** when all done |
| `EACH`     | Fork/Distributive | Fires HENCE **for each** completion independently            |

> **Proposed vocabulary — Meng, 2026-09-06; researched the same night and the research recommended
> against; RULED 2026-09-07 by R-Q1 (§2.5) in the research's favour — one word, join on the
> continuation.** _"The EVERY vs EACH semantics may not stand up to scrutiny from a
> noob persona — we may prefer to say 'jointly' vs 'severally' for the barrier join vs the
> distributive semantics."_ The first reading of this (recorded here for an hour, and wrong) mapped
> the pair onto the classical joint-vs-several obligation distinction. The research memo,
> [`EVERY-EACH-JOINT-SEVERAL-MEMO.md`](EVERY-EACH-JOINT-SEVERAL-MEMO.md), finds the mapping fails on
> the one axis that touches performance:
>
> - **Common-law _joint_ asserts the opposite of the barrier on discharge.** Restatement (Second)
>   of Contracts § 293: _"Full or partial performance or other satisfaction of the contractual duty
>   of a promisor discharges the duty to the obligee of each other promisor of the same performance
>   to the extent of the amount or value applied."_ Under the barrier, Alice signing does nothing
>   for Bob, and §6.1 blames every non-completer. A lawyer reading `JOINTLY` expects one obligor to
>   be able to satisfy the whole — a wrong answer, not an approximation. Release of one joint
>   obligor discharges all (_Duck v Mayeu_ [1892] 2 QB 511; Restatement § 294(1)(a)); the barrier
>   has no such operation.
> - **The sign of _joint_ flips between traditions.** Louisiana Civil Code art. 1788 defines a
>   joint obligation as one where _"neither is bound for the whole"_ — the inverse of the common-law
>   sense. The civilian taxonomy itself fits four-for-four (several → fork, LCC art. 1787; joint/
>   divided → barrier; solidary → Pattern C; indivisible → Pattern D), because it classifies
>   obligation _structure_ where the common-law pair classifies _remedy and procedure_ — Restatement
>   § 288 calls the distinction "primarily remedial and procedural". A keyword whose meaning inverts
>   across the two traditions L4 encodes is not a keyword.
> - **Drafting practice has retired the words.** Ken Adams: _"ill understood. (At least, I didn't
>   understand them!)"_ … _"I've now decided that they're more trouble than they're worth."_ His
>   canonical _several_ example divides the payload ($50 + $50) where the fork replicates it. And
>   _severally_ fails the first-time reader worse than `EACH`: the numeral sense of _several_ has
>   dominated since the 1530s, so "severally, every Person must sign" reads as _some_ must sign.
> - **No formal contract language uses this vocabulary** — searched and not found in Symboleo,
>   FCL/Regorous, Hvitved's CSL, Accord/Ergo, Lexon. Adopting it would follow no one.
>
> **What the memo proposes instead (§7.2): mark the join at the continuation, not the quantifier.**
> §3.3 already concedes the distinction is a continuation property — without `HENCE`/`LEST` the two
> coincide — so encoding it in the quantifier is what manufactures the vocabulary problem:
>
> ```
> EVERY Person p MUST sign  HENCE ONCE ALL HAVE  notify        -- barrier
> EVERY Person p MUST sign  HENCE FOR EACH       notify p      -- fork
> ```
>
> One quantifier word, one new keyword, no glossary, no doctrine imported, and `JOINTLY` /
> `SEVERALLY` left free for Patterns D and C where they are doctrinally correct. Second best, if
> single modifiers are wanted: `TOGETHER` / `SEPARATELY`. Memo §7.4 gives the definitional sentence
> if `JOINTLY`/`SEVERALLY` are adopted regardless; it needs four denials, which is itself the
> argument.
>
> **Two corrections to this spec that hold whichever way the ruling goes:** (1) the barrier/fork pair
> already has exact established names in the workflow-patterns literature — **WCP-12 "Multiple
> Instances without Synchronization"** is the fork and **WCP-14** (run-time-known instance count) is
> precisely this spec's barrier — worth citing in §3.1–3.2 and §14 given the BPMN export; (2) §2.2's
> heading "Distributive vs Collective" is off in the formal vocabulary — in Norman & Reed and
> Royakkers & Dignum _both_ constructs are distributive, and a _collective_ obligation is one the
> group may discharge without every member acting, which L4 does not model. **One open question §13
> does not list:** what happens to an armed barrier when the inhabitant set changes after arming
> (WCP-14 vs WCP-15); doctrine's survivorship rule is a real design option not yet ruled on.
>
> **Measured (2026-09-06, `unstable` @ `cd4d4680`), still true and still relevant if the words are
> wanted for Patterns C/D:** neither `JOINTLY` nor `SEVERALLY` is a lexer keyword; the only bare
> uppercase corpus occurrences are two lines of one `--` comment in
> `sg-succession/cleanroom-2026-08/guardianship-of-infants-act.l4:1294`; the source texts use the
> words — 45 files under `jl4/examples`, 20 under `canon` — many in Reg CF's arithmetic sense
> ("calculated jointly with that person's spouse"), a third sense the phrasebook must keep apart.

**EVERY (barrier):**

```l4
EVERY director
    MAY    approve
    HENCE  resolution passes    -- fires once when ALL have approved
```

If 5 directors approve, the resolution passes once.

**EACH (fork):**

```l4
EACH director
    MAY    approve
    HENCE  company MUST notify others WITHIN 24 hours  -- fires for EACH approval
```

If 5 directors approve, company must send 5 notifications.

**Formal distinction** (spellings as ruled 2026-09-07; the CSP is unchanged):

- `EVERY p ... ONCE ALL HAVE HENCE h` ≈ `(P1 ||| P2 ||| P3) ; h` (CSP sequential composition after interleaving) — WCP-14
- `EVERY p ... UPON EACH HENCE h` ≈ `(P1 ; h) ||| (P2 ; h) ||| (P3 ; h)` (CSP interleaving of each with its continuation) — WCP-12

**Without HENCE/LEST, both behave identically** (pure distributive):

```l4
EVERY p MUST sign    ≡    EACH p MUST sign    -- when no HENCE/LEST
```

The semantic difference only manifests when continuations are present.

#### 2.2.7 Threshold joins: `ONCE`, `SOME m OF …`, and measures

> **Status (2026-09-06): PROPOSED, NOT BUILT.** This section replaces the three-paragraph
> "Collective Semantics (Future Work)" stub that stood here until 2026-09-06 (kept verbatim in
> §2.2.7.1). Nothing below describes the tree; §2.2.7.9 lists what would make it true. All six
> rulings in §2.2.7.8 were **RULED 2026-09-06 (marked accept)**; still nothing is built.

##### 2.2.7.1 What this section said before 2026-09-06

> Patterns C and D require additional constructs beyond EVERY/EACH:
>
> ```l4
> -- Pattern C: Joint and Several (proposed future syntax)
> JOINTLY AND SEVERALLY guarantors MUST pay debt
>     UNTIL debt_satisfied
>
> -- Pattern D: Truly Joint (proposed future syntax)
> ALL parties MUST JOINTLY execute closing_documents
> ```
>
> These collective patterns are deferred to a future specification. For now, EVERY/EACH addresses
> the most common patterns (A and B) which cover the majority of real-world quantified obligations.

The `UNTIL debt_satisfied` in that stub was the right instinct and the rest of this section is what
it turns into once it is worked through: Pattern C's join is a **threshold over a measure**, not a
count of performers, and Pattern D is not a threshold at all.

##### 2.2.7.2 Where this came from

Two remarks of Meng's on 2026-09-06, after the joint/several research
([`EVERY-EACH-JOINT-SEVERAL-MEMO.md`](EVERY-EACH-JOINT-SEVERAL-MEMO.md)) and the Alchourrón–Bulygin
pass that followed it (a session-scratchpad memo of 2026-09-06, **not in the tree**; every claim
taken from it below is restated here so this section stands alone):

1. _"Years ago we specified but never implemented some syntax for L4: `M OF N` allowed a '2 of 3'
   game scoring or '51 of 100' vote counting; perhaps we could excavate this idea and use it for
   '1 OF N' for joint / existential quantification or 'N OF N' for several / universal
   quantification."_ — No trace of `M OF N` survives in `legalese/l4-ide` or its archived refs
   (grepped 2026-09-06); if the old spec exists it is in the natural4 repository.
2. _"If five people are jointly liable for, say, the rent, what the landlord really cares about is
   receiving the full amount even if it is written as four separate cheques that add up to the
   right number. And that's a different modeling problem in the real domain. So not everything
   boils down to atomic events."_

The two are one observation. In a Petri net an all-join is a single transition with n input places,
but an m-of-n join **cannot** be drawn that way: it needs a counting place that every performance
drops a token into, and a join transition with an arc of weight m out of it. The moment the language
says `2 OF 3` it has stopped counting events and started measuring an accumulator. The rent is the
same net with a different measure: each cheque raises the marking of a "received" place, and
discharge is a transition with an arc weighted at the rent. Not everything is a firing; some things
are markings. Restatement (Second) of Contracts § 293 states the pro-tanto step in words —
performance by one promisor discharges the others _"to the extent of the amount or value applied"_.

##### 2.2.7.3 The family

One construct with a parameter, whose endpoints are the two folds this spec already has:

| spelling                                        | join condition                  | this spec / doctrine / patterns                                                                                       |
| ----------------------------------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `ANY OF` ≡ `SOME 1 OF` ≡ `AT LEAST 1 OF`        | count ≥ 1                       | the `ROR` fold; "one for all"; common-law _joint_ (§ 293); WCP-9 discriminator; **no quantifier today**               |
| `SOME m OF` ≡ `AT LEAST m OF`                   | count ≥ m                       | k-out-of-n partial join (WCP-30); bank mandates "any two signatories"; jury verdicts; quorum by number                |
| `ALL OF` ≡ `N OF N`                             | count = cast                    | the `RAND` fold; `EVERY` with one continuation (§3.1); WCP-14                                                         |
| `ONCE sum OF amount AT LEAST rent`              | a measure over the performances | the rent; Pattern C's primary obligation; § 293's "amount or value applied"                                           |
| `ONCE count AT LEAST 2 AND shares AT LEAST 10%` | two measures at once            | Singapore Companies Act s 177 quorum ("two or more members holding ≥ 10 %"), `corporate-resolutions/SPEC-NOTES.md:74` |
| `UPON EACH` (RULED 2026-09-07)                  | per performance; no join at all | the fork (§3.2); WCP-12; the old `EACH` quantifier, retired by R-Q1 (2026-09-07)                                      |

The measure defaults to a count of performers. Under R-Q1 (2026-09-07) the quantifier word is
**orthogonal** to this table: `EVERY` names the cast, and the `ONCE` line says when — and how often —
the continuation fires. The fork is the table's degenerate row (every performance, separately; nothing
accumulates), and the barrier is `ALL OF` plus one continuation. Before R-Q1 the fork was a second
quantifier word, `EACH`, and "`EACH` with a threshold is meaningless" was the way this paragraph said
that a fork has no join; the same fact now reads: a deonton carries at most one `UPON EACH` line,
and a state threshold over it is a second, outer `ONCE` line (§2.2.7.6).

##### 2.2.7.4 Syntax

The memo's continuation marker (§7.2 there: `HENCE ONCE ALL HAVE …` / `HENCE FOR EACH …`) already
puts the join on the continuation. `ONCE` generalises by taking a threshold instead of the word
`ALL`:

```
ThresholdJoin ::= QuantifiedDeonton 'ONCE' Threshold [TemporalConstraint] [HenceClause] [LestClause]

Threshold     ::= 'ALL' 'HAVE'
                | 'ANY' 'HAS'
                                                   -- the fork is NOT a Threshold: R-Q1 (2026-09-07) made it
                                                   -- its own Join alternative, 'UPON' 'EACH' (§2.4). Every
                                                   -- Threshold is level-triggered and fires once; the fork is
                                                   -- edge-triggered, so it cannot compose under the
                                                   -- 'Threshold AND Threshold' rule below.
                | Count 'OF' Cast 'HAVE'           -- SOME 2 OF Director HAVE
                | Measure Comparison Expr          -- sum OF amount AT LEAST rent
                | Threshold 'AND' Threshold        -- the s 177 quorum

Count         ::= 'ALL'                            -- added under R-Q2 (2026-09-07): the N-of-N endpoint
                | 'SOME' Number | 'AT' 'LEAST' Number       -- synonyms, see below
Measure       ::= 'count' | Aggregate 'OF' Binder            -- the Binder is a name bound in the action pattern
```

Under R-Q1 the `ONCE` line is not only the threshold's home but **the only place a continuation may
hang under a quantifier**: a `HENCE` or `LEST` written directly under `EVERY … Action [WITHIN …]`
with no join line is a check error naming the two spellings (`ONCE ALL HAVE`, `UPON EACH`).
§2.4 carries the production.

A quantifier-prefix spelling is sugar for the same thing when there is no per-act continuation:

```l4
SOME 2 OF Director d DO sign WITHIN 30 HENCE `resolution passes`
-- ≡  EVERY Director d DO sign  ONCE SOME 2 HAVE  WITHIN 30 HENCE `resolution passes`

ALL OF Director d DO sign WITHIN 30 HENCE `resolution passes`          -- R-Q2: the unanimity endpoint
-- ≡  EVERY Director d DO sign  ONCE ALL HAVE     WITHIN 30 HENCE `resolution passes`
```

`ALL OF` costs no new keyword (`TKAll` at `Lexer.hs:317`, `TKOf` at `Lexer.hs:268`). Without it the
only prefix spelling for unanimity would be `SOME n OF` with a literal `n`, which silently turns a
unanimous-assent clause into a majority rule when the register changes (refuters, R-Q2). The
`ANY OF` row of §2.2.7.3's table has no `Count` alternative here either; it is `SOME 1 OF` by that
table and is left for the build to add beside `ALL`.

`DO`, not `MUST`, in the prefix form — R-T5's style note (Meng, 2026-09-06): no single director owes a
signature, so the act is stated neutrally and the obligation lives on the join.

**Ruled in passing, Meng, 2026-09-06:** `SOME m OF …` is a synonym for `AT LEAST m OF …`. His note
on the word: _"some" is properly used in this sense in a sort of archaic sense_ — "some two of
them", where _some_ picks out an unspecified subset of the stated size. One hazard for the
definitional sentence, recorded because this spec's whole vocabulary debate was about first-time
readers: the modern collocation _"some 200 people"_ reads as _approximately_, so the page that
introduces `SOME m OF` must say _at least_ in its first sentence.

Name collisions were checked. `SOME` was not a keyword when this was written. **STALE since #360
(2026-09-07):** it is one now — `TKSome` at `jl4-core/src/L4/Lexer.hs:248`, in the keyword table at
`:350` — lexed but never parsed, since §2.2.7.4's count join is still unbuilt. The status header
already flags this; corrected here too, because this is the section that owns the claim.
An earlier proposal spelled an actor-agnostic contract head
`DEONTIC SOME who` and was **rejected** on arity and event-typing grounds
(`specs/done/DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md`, "Do NOT make the contract head
actor-agnostic"); that was a type, not a quantifier, and the rejection does not reach this use —
said here so that a later reader who greps for `SOME` does not conclude the quantifier was ruled
out. `ALL` and `NO` stood in §2.4's `Quantifier` production with no semantics given anywhere in this
document until 2026-09-07, when both were ruled out of it: `ALL` is not a quantifier — it is the
`N OF N` spelling inside the join (`ONCE ALL HAVE`) and the `ALL OF` head of the prefix family
(R-Q2, §2.5) — and `NO` is sugar over `EVERY … SHANT` with the fork join (R-Q3, §2.5, §2.2.3).

##### 2.2.7.5 Semantics, in six points

1. **The join is over an accumulator.** Each performance that matches the quantified pattern adds
   to a per-contract accumulator (a count, or the bound measure); the `ONCE` condition is evaluated
   against it after every matching event. A per-act continuation — written under the act's own
   `UPON EACH` line (R-Q1, 2026-09-07; until then spelled `HENCE FOR EACH`) — still fires per
   event (fork), independently of the state join.
2. **Acts inside, state outside.** In a threshold obligation the quantified modal is typically
   `MAY` — no single obligor owes any single act — and the `MUST` lives on the state at the `ONCE`
   line. This is the ought-to-do / ought-to-be split the A&B memo found (its §6.3): an ought-to-be
   continuation is idempotent under parallel composition, which is why the landlord is indifferent
   to how many cheques. Where the modal inside is `MUST` (divided shares, §2.2.7.6 second form) the
   threshold disappears and blame narrows to the performer. In the prefix form of §2.2.7.4 the house
   style is `DO`, not `MUST` (R-T5's style note, 2026-09-06).
3. **The deadline attaches to the `ONCE` line.** `WITHIN` after `ONCE` bounds the _state_, not each
   act. This fixes the defect of the only encoding available today — a contract recursing on the
   remaining balance re-arms its `WITHIN` on every payment, so the law's single due date on the
   total is not expressible without threading the clock by hand (cf. §5.1).
4. **Blame is a set.** `LEST BREACH BY EVERY t` (joint: the shortfall is everyone's) and
   `LEST BREACH BY EACH t WHO owes` (divided) both need the compound breach to carry a **set of
   parties**. Until 2026-09-15 a `RAND`/`ROR` breach carried **one operand** — the machine picked
   left for `RAND` and right for `ROR` by timestamp tie-break ("consistently with CSL"), the same
   gap the six-ways page recorded for the any-join. **BUILT 2026-09-15 (R-T3), see §6.1:** the
   breach carries a non-empty list of failures, each with its own detail and none deduplicated
   (ruled the same day), `RAND`/`ROR` carry both operands', a barrier names every non-completer,
   and `BY` takes a list. The quantified `BY EVERY t` spelling itself is not ruled and not built.
5. **The domain is the cast, filtered.** `EVERY Tenant t` over a constructor with a payload
   (`Tenant HAS name IS A STRING`) ranges over an open type and needs §2.1's `WHO member_of …`
   filter, exactly as the existing `EVERY` does. **This point is the one the run time turned into
   a rule: see §11.0, the roll call (ANSWERED 2026-09-08).** The performer check of the value-actor encoding is
   silent for computed actors (`doc/concepts/legal-modeling/actors-and-actions.md` §7), so
   "a tenant may only pay as payer" is a run-time check under this encoding.
6. **Without a continuation the whole family collapses**, for the reason §3.3 already gives for
   `EVERY`/`EACH`: obligation distributes over conjunction in any normal deontic logic, so with no
   `HENCE`/`LEST` and no `ONCE` there is nothing for a join to condition (A&B memo §6.1, Sergot
   2001). Everything in this section is about continuations.

##### 2.2.7.6 Worked example: the rent

Declarations in the value-actor style the concept page prescribes (actors are constructors of one
type; actions are records whose first actor field is the performer). **Unrun**, 2026-09-06.

```l4
DECLARE Actor IS ONE OF
    Landlord HAS name IS A STRING
    Tenant   HAS name IS A STRING

DECLARE Action IS ONE OF
    Pay     HAS payer  IS AN Actor, payee IS AN Actor, amount IS A NUMBER  -- performer: payer
    Receipt HAS issuer IS AN Actor, to    IS AN Actor, amount IS A NUMBER  -- performer: issuer

theLandlord MEANS Landlord OF "Ms Ng"
tenants     MEANS LIST (Tenant OF "Alice"), (Tenant OF "Bob"), (Tenant OF "Carol")
rent        MEANS 1500

-- joint rent: any tenant may pay any amount; the STATE must reach the rent by the due date
GIVEN due IS A NUMBER
GIVETH A DEONTIC Actor Action
`rent owed jointly` MEANS
    EVERY Tenant t IN tenants
        MAY    Pay t theLandlord amount
        UPON   EACH                              -- fork: one receipt per cheque (R-Q1, RULED 2026-09-07)
        HENCE  PARTY theLandlord MUST Receipt theLandlord t amount WITHIN 5
    ONCE   sum OF amount AT LEAST rent               -- the state join is a measure over the cheques
    WITHIN due                                       -- one deadline, on the state
    HENCE  FULFILLED
    LEST   BREACH BY EVERY Tenant                    -- joint: everyone

-- divided rent: each tenant owes a share; no threshold; blame narrows
`rent owed severally` MEANS
    EVERY Tenant t IN tenants
        MUST   Pay t theLandlord amount PROVIDED amount AT LEAST share t
        WITHIN due
        UPON   EACH                              -- fork
        HENCE  PARTY theLandlord MUST Receipt theLandlord t amount WITHIN 5
        LEST   BREACH BY t
```

(Respelled 2026-09-07 under R-Q1 and R-Q4: `HENCE FOR EACH` → `UPON EACH … HENCE`, `EACH Tenant t`
→ `EVERY Tenant t … UPON EACH`, `WHO member_of tenants` → `WHO elem t tenants`. Respelled again
2026-09-09 under §13.5, which deprecated that last step's output: `WHO elem t tenants` →
`IN tenants`. The two join lines of the joint form are the two layers R-T2 and R-Q5 distinguish: the
inner one is the act layer, the outer one the state.)

For contrast, the only form that runs today — a contract recursing on the balance, one `ROR`
alternative per tenant, `amount` bound as a fresh pattern name and related in `PROVIDED` (the idiom
of `jl4/examples/legal/ceo-performance-award.l4:404-412`) — is on the "Six Ways to Owe One Debt" page of 2026-09-06
(an artifact, <https://claude.ai/code/artifact/9c4ed1f6-91a4-4991-8381-ffb926cfc831>, **not in the
tree**) and carries the two defects points 3 and 4 above name: a re-arming deadline and a single-party
breach.

##### 2.2.7.7 Patterns C and D, restated

- **Pattern C (joint and several)** is `ANY OF` on the primary obligation — any one performance,
  or under a measure any accumulation, discharges all — with the creditor's election before it and a
  contribution fork after it. The memo (§7.1, point 5) finds `JOINTLY AND SEVERALLY` doctrinally
  correct as a name for exactly this composite and for nothing in Patterns A or B; the old stub's
  spelling is therefore kept as the candidate surface for the composite, with `UNTIL` replaced by
  `ONCE`.
- **Pattern D (the joint act)** is **not** a threshold. It is one transition with n input places:
  there is no per-performer state, no "two of three have signed", and nothing to accumulate. In L4
  it is a group-valued `PARTY` over a single action, not a quantifier. The six-ways page's note on
  shapes 2 and 5 records the test: a deed executed by several parties is Pattern D by default, and a
  _counterparts_ clause exists precisely to convert it into the barrier, so the law itself
  distinguishes them by needing a clause to move between them.

##### 2.2.7.8 Rulings: all six RULED 2026-09-06 (marked accept)

Meng marked all six cards of the "Threshold Joins Bench" (an artifact of 2026-09-06, not in the
tree; its marks are read back by the general-manager session) **accept**, between 14:21 and 14:24
UTC. Each accepts the card's recommendation as written. The recommendations were one reader's and
no adversarial pass ran on them; they are recorded here with what decided them, so that a later
reader need not open the artifact, and so that the measurements can be re-run.

| ruling                                                                                                                                       | state                                   |
| -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| R-T1 — the keyword is `ONCE`, for the barrier and the threshold alike                                                                        | **RULED 2026-09-06**, accept            |
| R-T2 — `WITHIN` in both positions: on a deonton it bounds the act; after `ONCE` it bounds the state                                          | **RULED 2026-09-06**, accept            |
| R-T3 — `BY` takes a party or a list of parties; a compound breach collects the set of unfulfilled operands                                   | **BUILT 2026-09-15**, see §6.1          |
| R-T4 — `Aggregate OF Binder` is sugar over a general Boolean condition; `AND` of thresholds is Boolean `AND`                                 | **RULED 2026-09-06**, accept            |
| R-T5 — the prefix `SOME m OF Cast …` is sugar only without a per-act continuation; the pattern spelling it needs was ruled 2026-09-07 (§2.4) | **RULED 2026-09-06**, accept, with note |
| R-T6 — the cast is fixed at arming; a change of cast is an explicit event; extended to `EVERY` and given its event shape by R-Q6 (§13.4)     | **RULED 2026-09-06**, accept, with note |
| `SOME m OF` ≡ `AT LEAST m OF`                                                                                                                | ruled 2026-09-06 (Meng, in passing)     |

**What decided each.** Measurements dated 2026-09-06 on `unstable` `cdc11501`.

- **R-T1.** `ONCE`, `UNTIL` and `HAVE` are all absent from the keyword table of
  `jl4-core/src/L4/Lexer.hs`. The memo's barrier marker already spells `HENCE ONCE ALL HAVE`
  (`EVERY-EACH-JOINT-SEVERAL-MEMO.md:380-389`), and a threshold is that barrier with another
  condition, so one word serves both; `HENCE UNTIL ALL HAVE` reads as its own opposite. Corpus
  `UNTIL` is 16 non-comment lines in 5 files, every one inside the backticked name `` `WAIT UNTIL` ``,
  which a new keyword would not break. Found on the way and owed elsewhere: the status header of
  `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` says `UNTIL` "exists as a keyword (`Lexer.hs:330`)"; it does
  not, and that line is to be corrected in that spec's next change, not this one.
- **R-T2.** Today's `Deonton` carries one `due :: Maybe (Expr n)` (`jl4-core/src/L4/Syntax.hs:396`),
  parsed after the action and its `PROVIDED` guard and before `HENCE`/`LEST`. §2.2.7.6's rent needs
  both a per-act deadline (the receipt within five days) and one deadline on the total, and the law
  draws exactly that distinction. The grammar cost is the optional `TemporalConstraint` §2.2.7.4
  already carries.
- **R-T3.** `Breach Anno (Maybe (Expr n)) (Maybe (Expr n))` (cited as `Syntax.hs:342`; measured
  2026-09-15 it is `:360` at `cdc11501` and on the build's HEAD alike, so that number was never
  right) holds one optional party expression; the compound case in
  `jl4-core/src/L4/EvaluateLazy/Machine.hs` (`:1698-1730` at `cdc11501`, verified) picked one operand by
  operator and timestamp under a comment that the assignment "may be wrong if the events are passed
  out of order wrt time". A set is what a wizard or an export needs to answer "who is in breach". 34
  golden files print a breach; those with compound failure will re-bless with the fuller answer when
  this is built. _Since built (2026-09-15): the syntax node is unchanged — the list reading is a
  typing rule, not a constructor — and the run-time `ReasonForBreach` carries a non-empty list of
  failures; one existing golden set with compound failure re-blessed
  (`ok/tests/deontic-breach-semantics.golden`, four traces, and its `.ep.golden` twin for comment
  lines), and the count of golden files containing `DEONTIC BREACHED` was eight at `e578654c` —
  not 34 — and is nine on the branch's HEAD counting the new `run-blame.golden`
  (`grep -rl 'DEONTIC BREACHED' jl4 jl4-core --include='*.golden'`; without the include the same
  grep also hits two `.hs` files and a README, and no grep tried reproduces 34). §6.1 has the
  build record._
- **R-T4.** The prelude already has `count`, `sum`, `product`, `maximum`, `minimum`, `all`, `any`,
  `elem` (`jl4-core/libraries/prelude.l4`); `OF`, `AT` and `LEAST` are keywords. The sugar desugars
  to the prelude call over the projected list of matching performances; the general Boolean form
  stays writable for what the sugar cannot say; the s 177 quorum is
  `ONCE count AT LEAST 2 AND sum OF shares AT LEAST 10%` with no special production.
  `maximum`/`minimum` keep their `@nonexhaustive`.
- **R-T5.** D7.6 (`SURFACE-SUGAR-CLUSTER-2026-09.md`) declined a standalone `EVERY Person p`
  desugaring because its per-party `HENCE` would later be re-meant by this spec's barrier; the
  restriction to no-per-act-continuation removes that hazard here, since a fork needs the `ONCE`
  form. The variable-position spelling — `EVERY p` (§2.4, §3.1) against `EVERY Person p` (the
  unmerged upstream draft `970a8705`) — was **ruled 2026-09-07 (§2.4): the pattern form `EVERY Tenant t`
  is primary and `EVERY t` is the unfiltered case**, so the prefix form is no longer blocked. **Meng's note, verbatim:** _"Suggest we stylistically prefer DO to MUST in this 'not
  all parties' special case"_ — where no single member of the cast owes the act, the neutral `DO` is
  the house style; §2.2.7.4's example and §2.2.7.5 point 2 now say so.
- **R-T6.** The memo's §1.3 table records release-of-one-discharges-all and survivorship, and
  nothing about what a count threshold does when its population changes; a live cast would silently
  re-mean a joint obligation as several. Fixed at arming, with a departure or joinder as an explicit
  event, is the reading under which nothing re-means silently, and a live-membership quorum stays
  writable as a measure over the ledger's member list. The card declared low confidence and that
  stands. **Meng's note, verbatim:** _"This is why novations etc are a thing"_ — a change of party is
  a new agreement, not a silent re-count.

##### 2.2.7.9 What would make this section true

A parser for the `ONCE` line and the `SOME`/`AT LEAST` count; a desugaring to a residual contract
carrying the accumulator (the recursion-on-balance form, with the clock threaded so that R-T2
holds) or to a ledger cell read at the join; a set-valued breach (R-T3 — **built 2026-09-15**, §6.1,
so this clause of the list is discharged independently of the rest); goldens under `ok/` for the
two rent forms and the s 177 quorum; and a page under `doc/` before the work is closed (repo
`CLAUDE.md` §6). Until then this section is a design record and the six-ways page is its
illustration.

### 2.3 Cross-Party References

```l4
EVERY p_x
    MAY    terminate
    UPON   EACH                              -- fork: once per termination (R-Q1, RULED 2026-09-07)
    HENCE  EVERY p_y
               WHO  differs_from p_y p_x         -- a Boolean expression naming p_y (R-Q4)
               MUST settle_outstanding_accounts_with p_x
               WITHIN 30 days                    -- no continuation, so no ONCE line (§3.3)
```

The filter `differs_from p_y p_x` (i.e., `p_y /= p_x`) reads "does p_y differ from p_x?" and narrows
the inner quantifier's domain to exclude the outer-bound variable. Until 2026-09-07 this section wrote
`WHO differs_from p_x` and relied on §2.1's first-argument insertion; that rule was withdrawn under
R-Q4 and the variable is now written out.

### 2.4 Full Grammar

```
QuantifiedDeonton ::=
    Quantifier Pattern [Roll] [Filter]
                                      -- Roll RULED and BUILT 2026-09-08 (§11.0.2); it precedes the
                                      -- Filter, in reading order
        DeonticModal Action
        [TemporalConstraint]
        [Join]                        -- REQUIRED whenever a HenceClause or LestClause follows
                                      -- (R-Q1, 2026-09-07)
        [HenceClause]
        [LestClause]                  -- siblings of the Join, not children of it: the parser accepts a
                                      -- bare continuation and the CHECKER refuses it, naming the two
                                      -- spellings. Written as children, the bare form would be a parse
                                      -- error, which is not what the compiler does.

Join ::= 'ONCE' Threshold [TemporalConstraint]
                                      -- the BARRIER family, level-triggered. Threshold is §2.2.7.4's:
                                      -- 'ALL' 'HAVE' (§3.1), and in phase 3 the count and measure forms
                                      -- and their conjunctions. A state join written over a deonton that
                                      -- already carries a fork join is §2.2.7.4's ThresholdJoin (§2.2.7.6).
       | 'UPON' 'EACH' [TemporalConstraint]
                                      -- the FORK, edge-triggered (§3.2). R-Q1 RULED 2026-09-07: not a
                                      -- Threshold, because a fork cannot compose with a barrier under
                                      -- 'Threshold AND Threshold'. 'EACH' is NOT a keyword; 'UPON' is,
                                      -- in this position only. 'UPON ANY' is not a form: that is
                                      -- 'ONCE ANY HAS'.

Quantifier ::= 'EVERY'                -- R-Q1: EACH is not a quantifier; R-Q2: nor is ALL; R-Q3: nor is NO

NoProhibition ::= 'NO' Pattern [Filter] 'MAY' Action [TemporalConstraint] [Join]
                                      -- R-Q3: sugar for  EVERY Pattern [Filter] SHANT Action … , with the
                                      -- Join fixed to UPON EACH; NO … MUST, NO … SHANT and
                                      -- NO … MUST NOT are refused with a naming message (§2.2.3)

Pattern ::= Constructor Variable      -- EVERY Tenant t   : the primary form; the constructor selects the cast
          | Variable                  -- EVERY t          : the unfiltered case; every value of the actor type

Roll ::= 'IN' Expr                    -- RULED and BUILT 2026-09-08 (§11.0.2): the LIST the group is
                                      -- drawn from, of the party type. Read ONCE for the whole group,
                                      -- with the bound variable OUT of scope, so it may not mention a
                                      -- member. Optional: with no IN, the roll is read out of an
                                      -- `elem v xs` conjunct of the Filter instead (§11.0), and where
                                      -- both are written the IN clause is the roll and the conjunct
                                      -- goes on narrowing like any other condition.

Filter ::= 'WHO' Expr                 -- R-Q4: a Boolean expression in which the bound variable is free;

                                      -- WHERE is not a filter word (it opens a where-block, Parser.hs:1334-1338).
                                      -- 'WHOSE' Expr is PROPOSED, not ruled (§2.5, R-Q4; open questions in §13.6)

DeonticModal ::= ('MUST' ['NOT'] | 'MAY' | 'SHANT' | 'DO') ['DO']
                                      -- 'DO' added 2026-09-07 (R-Q2; §2.2.7.4's house style). MUST NOT
                                      -- and the optional trailing DO are what the parser accepts
                                      -- (Parser.hs 'must'), measured 2026-09-07.

Action ::= Pattern ['PROVIDED' Expr]  -- the PROVIDED guard, measured working under EVERY 2026-09-07

TemporalConstraint ::= 'WITHIN' Duration ['OF' Anchor]   -- 'OF' Anchor: the named anchor of R-Q7 (§5.1).
                                      -- The connective is 'OF' and only 'OF' (R-Q7A, §5.1.1). BUILT 2026-09-15
                                      -- ('L4.Parser.deadline', Parser.hs:2806 after round 1): in the Duration slot OF is the
                                      -- anchor, so an application there is written '(f OF x)' or 'f x'.
                     | 'BEFORE' Expr                      -- R-X5: an absolute DATE, the closing edge; 'BEFORE' Duration is refused
                                      -- naming WITHIN. BUILT 2026-09-16 ('L4.Parser.before', Parser.hs:2771;
                                      -- the second constructor of 'L4.Syntax.Deadline', Syntax.hs:581).
                                      -- Act position only: on a join line it is refused by name ('BeforeOnJoinLine').
                     | 'AFTER' (Duration ['OF' Anchor] | Expr)   -- R-X5: the opening edge, duration or DATE. RE-ANCHORS (RULED 2026-09-16, §5.1.2.2): the WITHIN beside it counts from this edge; two-offset is 'WITHIN d OF THE JOIN'.
                                      -- BUILT 2026-09-16 ('L4.Parser.opening', Parser.hs:2787; the node is
                                      -- 'L4.Syntax.Opening', Syntax.hs:602, a field of 'Deonton' between the action and the deadline).
                                      -- The edges are written in ONE order, AFTER then WITHIN/BEFORE ('L4.Parser.edgeOrderGuard'); the join line takes no AFTER.
                     | 'BY' Deadline                      -- unruled and unbuilt; TKBy serves FOLLOWED BY, DIVIDED BY, BREACH BY

Anchor ::= 'THE' ('JOIN' | 'DEADLINE' | 'ARMING' | 'OPENING')   -- 'OPENING' proposed by R-X5 (§5.1.2), DECLINED (§5.1.3), unbuilt   -- R-Q7B: the three lifecycle positions. THE is already
                                      -- a keyword (Lexer.hs:283 at e578654c); JOIN, DEADLINE and ARMING are matched by
                                      -- SPELLING and not reserved, exactly as EACH is in UPON EACH.
                                      -- The three are BUILT 2026-09-15 ('L4.Parser.anchor', Parser.hs:2827 after round 1).
         | Event                      -- R-Q7: any recorded event, which the drafter has already named —
                                      -- served by the Expr form below: an expression whose value is
                                      -- that event's time (a ledger read, a recorded instant). BUILT.
         | Expr                       -- R-Q7C: a NUMBER (an instant on the trace's clock) or a DATE
                                      -- (lowered by its serial). The slot is a union the checker
                                      -- discriminates ('L4.TypeCheck.checkAnchor', TypeCheck.hs:2326 after round 2);
                                      -- no new keyword. Spellings RULED 2026-09-07 (R-Q7A/B/C, §5.1.1);
                                      -- BUILT 2026-09-15.

HenceClause ::= 'HENCE' Continuation

LestClause ::= 'LEST' Continuation

Continuation ::= Deonton
               | QuantifiedDeonton
               | 'FULFILLED'
               | 'BREACH' ['BY' PartyOrList]   -- R-T3: a party or a list of parties (BUILT 2026-09-15, §6.1)
```

The fork's words were RULED `UPON EACH` on 2026-09-07 (§2.5, R-Q1), so `'EACH' 'HAS'` has left
`Threshold` and the fork is the second `Join` alternative above. The rule that a continuation under a
quantifier needs a join line is unchanged. The `[TemporalConstraint]` on the fork is this document's
reading of the conditional note it replaces, which omitted it; see §2.5, R-Q1, "One reading the GM
should confirm".

(Until 2026-09-07 this grammar read `Quantifier ::= 'EVERY' | 'EACH' | 'ALL' | 'NO'`,
`Filter ::= 'WHO' Predicate | 'WHERE' Predicate`, and put `HenceClause`/`LestClause` directly under the
quantified act with no join. R-Q1–R-Q4 and R-Q7 changed it as marked; §2.5 records why.)

**RULED 2026-09-07 (Meng, in session, on the GM's measured recommendation), verbatim:** _"Ok: the
pattern form as primary, EVERY Tenant t, with EVERY t as the unfiltered case."_

**What decided it.** Under the value-actor encoding (`doc/concepts/legal-modeling/actors-and-actions.md`)
`Tenant` is not a type but a **constructor** of `Actor`, so the word before the variable is a
_pattern_ that selects the cast — exactly as `Pay t theLandlord amount` is a pattern over actions —
and not a type annotation. The bare `EVERY t` therefore ranges over every value of the actor type,
landlord included, until a `WHO` filter narrows it. Both spellings fit one production, `Quantifier
Pattern`, and the variable stays last, as in the unmerged upstream draft `970a8705`. Measured
2026-09-07 on `unstable`: this document wrote the bare form on 28 code lines (typed from the
`DEONTIC` signature) and the pattern form on 2 (§2.2.7.6); the upstream draft wrote `EVERY Person p`
throughout. **The bare-form examples below remain valid as the unfiltered case**; new examples use
the pattern form where a cast is meant. This ruling unblocks R-T5's prefix sugar (§2.2.7.8).
Nothing was built when this paragraph was written; the pattern form and the `Roll` line above it
have both since been built (#360 on 2026-09-07, §11.0.2 on 2026-09-08). R-T5's prefix sugar is
still unbuilt.

### 2.5 Rulings R-Q1–R-Q7 (2026-09-07)

Seven cards — "the Quantifier Bench", an artifact of 2026-09-06/07, **not in the tree**
(<https://claude.ai/code/artifact/fb431448-4363-47d8-bda2-f03d9e658bd6>) — were put to Meng after an
adversarial pass, and marked between 18:21 and 18:28 UTC on 6 September 2026. The marks are quoted
verbatim; where the general-manager session's reading of a mark goes beyond the mark, the text says
"GM's reading, 2026-09-07". Everything below was a design record when it was written; where an entry
has since been built, the entry says so and names the branch (R-Q1 is the one so far).
Measurements are dated 2026-09-07 on `unstable` `5dc0ca19` unless stated; every file:line was
re-opened on that tree when this section was written.

| id   | question, in a phrase                                        | mark, verbatim                                                                                                              | ruling, in a sentence                                                                                                                                                                                                                                                                                                                                     | recorded in                                |
| ---- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| R-Q1 | the join word: two quantifiers, or one word and a marker?    | **alternative** — _"E but with “ONCE EACH HAS \n HENCE”?"_                                                                  | One quantifier, `EVERY`; under it a continuation requires a join line: `ONCE ALL HAVE` (barrier), `UPON EACH` (fork; **words RULED 2026-09-07**); a bare `HENCE`/`LEST` is a check error. `HENCE FOR EACH` withdrawn.                                                                                                                                     | §2.2.6, §2.2.7.3–.6, §2.4, §3.1–§3.3, §15  |
| R-Q2 | does a bare `ALL Pattern` mean anything?                     | **accept** — _"How do the quantifies interact with RAND ROR combinators? Docs need to show an example."_                    | Not a quantifier. `ALL` keeps `FOR ALL`, `RECALL ALL`, `ONCE ALL HAVE`, and becomes the `ALL OF` head of the prefix family. `DO` joins `DeonticModal`. The note is a docs requirement: §8.3 gains the example.                                                                                                                                            | §2.2.7.4, §2.4, §8.3, §15                  |
| R-Q3 | is `NO Tenant t MAY sublet` a form, and of what?             | **accept** — _"The NO P MUST A form feels like it belongs more to the bounded deontics discussion of dominators."_          | Sugar for `EVERY … SHANT` with the fork join; `HENCE` keeps `SHANT`'s meaning; `NO … MUST`/`SHANT`/`MUST NOT` refused with a naming message; the liberty form deferred to the bounded-deontics discussion.                                                                                                                                                | §2.2.3, §2.2.7.4, §2.4, §15, status header |
| R-Q4 | the filter word, and what the slot holds                     | **accept** — _"Perhaps the WHOSE projection could take advantage of the field-opening logic from the section-givens work."_ | `WHO` only; the slot is a Boolean expression naming the bound variable; §2.1's insertion rule withdrawn. `WHOSE` is **PROPOSED**, sequenced after `IMPLICIT-PROPS-DESIGN.md` §11.7 R5 is built — but see **§13.6**, which measures what R5 does and does not settle for it, and records a layout-conjoined form that would not need to wait on R5 at all. | §2.1, §2.2.3, §2.3, §2.4, §15              |
| R-Q5 | early failure: `LEST` at detection, or at the deadline?      | **accept** — _"d"_                                                                                                          | No modifier. The failure time is fixed by the layer the `LEST` attaches to — the state's deadline on the `ONCE … WITHIN` line; on the act layer, by the modal. Success time by modal. §13.1 closed.                                                                                                                                                       | §3.4, §5.2, §13.1                          |
| R-Q6 | does R-T6's fixed cast bind `EVERY`; what on leave/join?     | **accept** — _"d"_                                                                                                          | Cast evaluated once at arming for the whole family; changes only on an explicit **edit** event (release / substitute / join) applied to the running barrier, completions and accumulator preserved. Events proposed, unbuilt.                                                                                                                             | §2.2.7.8 (R-T6 row), §13.4                 |
| R-Q7 | the continuation clock: `HENCE` from what, `LEST` from what? | **modify** — _"e but with a as default when no OF?"_                                                                        | A drafter may name the anchor (`WITHIN 5 days OF …`); unanchored, `HENCE` counts from the join's firing (today's rule) and `LEST` from the missed deadline (§5.2) — the latter a **change** from the tree's earlier revealing-event anchor, BUILT 2026-09-16 (§5.2.1).                                                                                    | §2.4, §5.1, §5.2                           |

**What decided each.**

- **R-Q1.** §3.3 already conceded that without a continuation the barrier and the fork coincide, so
  the distinction is a property of the continuation, not of the quantifier; keeping `EACH` as a second
  quantifier beside the accepted `ONCE` line (R-T1) left two mechanisms for one distinction. The
  refuters then showed why the marker must be **mandatory** rather than defaulted: today a `MAY …
HENCE` fires when the permission is exercised (`Machine.hs:1669-1671`), so a drafter who upgrades
  `PARTY p MAY approve HENCE notify` to `EVERY Director p MAY approve HENCE notify` under a barrier
  default would get one notification after all have approved, silently — and that upgrade is the very
  move §2.2.4–§2.2.5 sell the quantifier for. A fork default fails the other way (n closings for one)
  but at least visibly. Refusing the bare form has the shape of a non-exhaustive `CONSIDER` refusal:
  the language declines to guess. Both spellings are new machinery: today's `RAND` fold is a join
  with **no continuation slot** — `HENCE` is parsed only inside `obligation` (`Parser.hs:2538-2540`),
  so `(A RAND B) HENCE k` is a parse error (refuters' probe). Meng's mark chose option e's structure
  and proposed the fork's words.

  **The fork's words: RULED 2026-09-07 (Meng), verbatim:** _"Let's rule fork words in favour of
  UPON EACH. We can always change our minds about this in future at relatively low engineering
  cost."_ So the join line is `ONCE ALL HAVE` (barrier) or `UPON EACH` (fork); `ONCE EACH HAS` no
  longer parses.

  **What decided it.** His own mark, `ONCE EACH HAS`, carried a question mark, and "once each has
  signed" reads in ordinary English as the barrier ("once each of them has signed, then …") — the
  very reading the line exists to exclude. Of the four candidates, `UPON EACH` is the only one that
  changes the _keyword_ rather than the qualifier, and that matters structurally: every `ONCE`
  form is **level-triggered**, waiting for a condition and firing once, while the fork is
  **edge-triggered**, firing per completion. Putting the two under one `ONCE Threshold` production
  would have let phase 3's `Threshold AND Threshold` compose a fork with a barrier, which has no
  meaning. So the fork leaves `Threshold` and becomes its own `Join` alternative (§2.4), the count
  and measure forms stay under `ONCE`, and `UPON ANY` is deliberately not a form — that case is
  `ONCE ANY HAS`.

  **Cost, measured 2026-09-07 before the change.** Reserving `UPON` as a keyword costs zero
  goldened corpus files, zero canon files and zero `doc/` files. Five non-comment lines in
  `jl4/experiments` spell it (`purchase.l4:94`; `deontic-may.l4:16`, `:25`, `:100`, `:135`), all of
  them the aspirational rule-head form `UPON <event>` of `specs/todo/UPON-EXTERNAL-EVENTS-SPEC.md`
  (status OPEN; smucclaw/l4-ide#490) — a **different construct in a different position**, which the
  join line never competes with because a rule head cannot appear after an act. Neither file
  parsed before the change and neither parses after it; both now fail at their `UPON` line rather
  than further down. `jl4/experiments` is in no golden glob.

  **The candidates that were dropped:** `ONCE EACH HAS` (Meng's mark; the English hazard above),
  `AS EACH HAS` and `EACH TIME ONE HAS` (both put to him by the GM; both keep the qualifier-shaped
  reading and neither carries the edge-trigger in a keyword).

  **BUILT 2026-09-07** on `every/build-1`, front end only: lexer `TKUpon`; `Join` is a two-way sum
  (`JoinOnce Anno (Threshold n) (Maybe (Expr n))` | `JoinUpon Anno UponEach (Maybe (Expr n))`);
  `Threshold` keeps only `AllHave`. The fork's words live in exactly two definitions,
  `L4.Parser.uponEach` and `L4.Print.uponEachWords`, and the diagnostics read the printer's, so a
  later re-spelling is those two plus the goldens that quote the message — which is the "relatively
  low engineering cost" the ruling relies on.

  **The fork keeps its optional `WITHIN` — CONFIRMED 2026-09-07 (GM).** §2.4's conditional note
  wrote the fork as `'UPON' 'EACH' [HenceClause] [LestClause]`, omitting the `[TemporalConstraint]`
  that the `ONCE` branch carries. That omission is brevity, not a decision, and the build was right
  to keep the constraint: §2.5's own candidate-4 text says "the structure is unchanged"; dropping it
  would have removed a capability that already worked (`ONCE EACH HAS WITHIN 30` parsed and
  checked); and removing a working capability as a side effect of a spelling ruling is exactly the
  kind of silent narrowing this document exists to prevent. Both of the build's refuters reached the
  same reading independently. So `UPON EACH WITHIN 30` is legal: each continuation fires on its own
  member's act, and the whole is bounded by day thirty. Were this ever reversed, the fix is one
  alternative in `L4.Parser.joinLine` and one field.

- **R-Q2.** `ALL` already has two jobs (`Parser.hs:1244-1245`, `:2375`) and R-T1's `ONCE ALL HAVE`
  gives it a third inside the join. Nothing in §3–§9 ever gave a bare `ALL Pattern` a meaning distinct
  from `EVERY`, and the refuters supplied the reason it must not get one: in the common law "all"
  reads collectively by default (Restatement (Second) of Contracts § 288(2), as the joint/several memo
  quotes it, `EVERY-EACH-JOINT-SEVERAL-MEMO.md:105`), so "all the directors shall sign" is not the same
  sentence as "every director shall sign", and a language should give `ALL` the collective slot. The
  `ALL OF` head of the prefix family was added so the ruling does not foreclose the unanimity
  endpoint (§2.2.7.4). Meng's note is a documentation requirement, not a re-decision: §8.3 now carries
  a worked example of a quantified obligation as an operand of `RAND` and of `ROR`, and of a barrier
  whose `HENCE` is itself a `RAND`, with the breach naming under R-T3; **the build's `doc/` page owes
  the same example** (owed list below). _Discharged in part 2026-09-15: the breach naming is on the
  page (`doc/reference/regulative/EVERY.md`, "What runs today", and `BECAUSE.md`, "Several
  parties"); the `RAND`/`ROR`-of-`EVERY` shapes themselves still wait on §8.3's other blocker._
- **R-Q3.** `NO` is free — not a keyword, 0 bare identifier uses in the corpus (the refuters' count:
  62 non-comment lines in 5 files, all inside strings or backticked `§` headings; canon 0) — and the
  prohibition already exists twice (`MUST NOT` → `DMustNot`, `SHANT` → `DMustNot`,
  `Parser.hs:2520-2527`), so a third mechanism was never on the table; the question was whether the
  contract idiom earns sugar. The refuters measured our own statutory sources and found the statutory
  "No …" sentences are mostly nullity, capacity and evidentiary rules ("No will shall be valid
  unless …"), out of the sugar's reach; the idiom earns its keep in contracts. Two amendments came
  from review and are in §2.2.3: the `HENCE` polarity under `SHANT` (`Machine.hs:1592-1595`,
  `:1648-1651`) and the fork join. Meng's note deferred the liberty form (`NO P MUST a`) to the
  bounded-deontics discussion of dominators (§2.2.3 gives the citations).
- **R-Q4.** `WHERE` is `TKWhere` (`Lexer.hs:276`) with exactly one consumer, the where-block of a
  completed expression (`Parser.hs:1334-1338`); a `WHERE` filter would sit immediately before a legal
  `WHERE` block, and `EVERY t WHERE p WHERE q MEANS …` is a garden path the layout rule cannot
  backtrack across. Nine of the document's ten filter examples already wrote `WHO`; the tenth (§2.2.3
  Pattern J) is corrected. The slot question was added by review: §2.1's first-argument insertion
  cannot type its own `WHO a AND b` example, and the recommended example of the first draft did not
  compile either (a trailing `WHERE` cannot see the binder — probed, §2.1). Meng's note proposes
  `WHOSE`; searched and not found in any commit of this repository's history, in the upstream drafts,
  or in any upstream issue (refuters, `git log --all -S`). Recorded as **PROPOSED, not ruled
  syntax**: a filter in which the payload field names of the pattern's constructor resolve as
  projections of the bound variable —

  ```l4
  EVERY Tenant t WHOSE arrears > 0
      MUST Pay t theLandlord arrears WITHIN 7 days       -- ≡ WHO t's arrears > 0; `arrears` in the body is still t's

  EVERY Director d WHOSE `term expires` < closing AND NOT conflicted
      MUST sign WITHIN 30 days                           -- ≡ WHO d's `term expires` < closing AND NOT d's conflicted
  ```

  with five rules: (1) only the payload fields of the pattern's constructor are captured
  (`Tenant HAS name, arrears`); a name that is both a field and a global resolves to the field and the
  checker warns, as for any shadowing; (2) the variable stays mandatory, because the action needs it
  (`Pay t …`); (3) `WHO` and `WHOSE` are exclusive on one obligation; (4) the bare `EVERY t` form has
  no constructor, so `WHOSE` is a check error there naming the pattern form; (5) elaboration is
  textual — `WHOSE e` → `WHO e[f ↦ t's f]` for every captured field `f` free in `e` — so the machine
  never sees it. Whether the capture extends into the action and continuations (as the first example
  assumes) is the one open design choice. Per Meng's note the elaboration is the **field-opening**
  logic of the section-givens work: `IMPLICIT-PROPS-DESIGN.md` §11.7 R5, "Field-opening is lexical
  only", RULED 2026-09-04 (`IMPLICIT-PROPS-DESIGN.md:701`) and **not built**
  (`IMPLICIT-PROPS-DESIGN.md:1539`); `WHOSE` is therefore sequenced after R5 lands, and shares its
  lexical-only rule. Cost: one keyword (`WHOSE` has 0 corpus uses, comments included), the scoping
  rule, nothing in the machine.

- **R-Q5.** §3.4 had a "party fails" transition with no event behind it, and §13.1 recommended
  opt-in early failure. The refuters established that L4 has **no party-failure event**: the machine's
  only event is party + action + timestamp (`jl4-core/src/L4/Syntax.hs:208-215`); `REFUSE`, on which
  the first draft leaned, is the model declining to answer — "no rule in the language can observe or
  convert into an answer" (`Syntax.hs:361-371`) — not a party's act. So a modifier would have nothing
  to trigger on, and "early failure by default" would need a new repudiation event; and anticipatory
  repudiation, the counter-rule, gives the innocent party an _election_ to accept or affirm, which an
  automatic early failure would take away (refuters, unverified in-tree). "Fixed by the modal" alone
  was then found to contradict R-T2 on this document's own flagship example, where the `LEST` hangs off
  the `ONCE … WITHIN` state line with `MAY` acts inside — hence option d: **layer first, then modal**.
  Two corrections to what "today" means are recorded in §5.2: a `MUST` breaches only when a
  later-stamped event _reveals_ the miss, and the breach carries that event's stamp
  (`Machine.hs:1522`, `:1601-1606`), so "at the deadline" is a change to the stamp; time alone
  breaches nothing. Success time by modal (`MUST`/`DO` at the last performance; `SHANT`/`MAY` at the
  deadline) is what R-Q7's anchor needs.
- **R-Q6.** R-T6's row is not scoped to `SOME m OF`, and `EVERY` is `ALL OF` plus one continuation
  (§2.2.7.3), so the freeze already reached `EVERY` on a literal reading; §4.1's `boParties` and
  §6.1's `bo.parties` are fields captured at arming, and §3.4's `pending` only shrinks — the document
  had been assuming it. What review added was the **mechanism**: the first draft's "a novation clause
  re-arms" discards completions and reopens the deadline, which is the cost it charged against the
  re-arm option and the re-arming `WITHIN` R-T2 was ruled to kill; option d replaces it with an
  incremental edit. `StateGraph.hs` draws a fixed fan (`AllOf`/`OneOf`, `jl4-core/src/L4/StateGraph.hs:133-134`,
  extracted syntactically at `:511` and `:514`); a run-time-width fan is already needed for `EVERY`,
  and a width that changes mid-run has no drawing at all. §13.4 has the rule, its scope and its escape
  hatch.
- **R-Q7.** §5.1 proposed the last completion and nothing had ruled it. The refuters probed the
  installed binary: a single-party `HENCE` continuation is anchored at the completing event's own
  stamp (the matched scan sets `time = ev'time`, `Machine.hs:1612`; it is handed to
  `continueWithFollowup`, `:1669-1671`, which applies the followup to `[time, events]`,
  `:1798-1804`) — so "from the join's firing" is today's rule generalised, and the only option under
  which a cast of one behaves like today's `PARTY`. The `LEST` half is the opposite of today: the
  machine anchors a `LEST` continuation at the **revealing** event's stamp (`Machine.hs:1550-1552`,
  the comment; `:1583-1589`, the mechanism), which lets the defaulting party choose when its own cure
  period starts. Meng's mark chose the named-anchor mechanism (option e) with option a as the default
  for an unanchored `WITHIN`; the GM reads "a" as covering both halves of option a — `HENCE` from the
  firing, `LEST` from the missed deadline, the latter recorded in §5.2 as a change (GM's reading,
  2026-09-07) and built 2026-09-16 (§5.2.1). The card's earlier `BY date` escape hatch is struck: R-T2 says nothing about `BY`, a
  deadline `BY` is unruled and unbuilt, and `TKBy` today serves only `FOLLOWED BY`, `DIVIDED BY`
  (`Parser.hs:1659`, `:1663`) and `BREACH … BY` (`:2484`). The example is §5.1's escrow chain.

**What review changed.** Fourteen Opus refuters (workflow `wf_1f84100a-c6b`, 7 September 2026), two
per card — a facts lens that re-ran every count, opened every file:line and probed the machine where a
claim was about behaviour, and a design lens that tried to construct a legal scenario or a language
interaction where the recommendation gives a wrong result — with the tree at `unstable` `2e1e5b17`
read-only and this document at `0af4a369`. Their verdicts: thirteen "weakened", one "holds" (R-Q6's
facts). What moved: R-Q1's recommendation from a silent barrier default to the mandatory marker, and
`ONCE` to its own line per §2.2.7.4 rather than the memo's `HENCE ONCE ALL HAVE`; R-Q2's corpus count
(4 lines, not 8), its precedent (§ 288(2)), and the `ALL OF` head; R-Q3's "no new semantics" withdrawn
in favour of the polarity and the fork join, `NO … MUST` recognised as a liberty, counts corrected; R-Q4
gained the slot question and lost its non-compiling example; R-Q5 lost `REFUSE`, gained the layer
rule and the corrected breach stamp; R-Q6 gained the incremental-edit mechanism and R-T6's escape
hatch; R-Q7 was split, with the `LEST` half stated as a change and the named anchor added. The GM
re-verified every borrowed claim it repeated before the cards went to Meng, and this section re-opened
each citation again.

**Examples elsewhere in this document that still write the old spellings.** `EACH` as a quantifier
survives at §5.3, §6.3, §7.3, §9.1, §9.3 and §12.3; bare
`EVERY … HENCE …` without a `ONCE` line at §5.1's diagram sections, §9.2 and §12. They are left as
written — they are the history of the two-word scheme, and their semantics are unchanged — and are to
be read as: `EACH p … HENCE h` ≡ `EVERY p … UPON EACH HENCE h`; `EVERY p … HENCE h` ≡
`EVERY p … ONCE ALL HAVE HENCE h`. §9's heading, "EVERY (Barrier) vs EACH (Fork)", is now "the
`ALL HAVE` join vs the `UPON EACH` join"; its number is kept because it is cited. **That rename is
proposed, not made:** §9's heading still reads "EVERY (Barrier) vs EACH (Fork)" in this file.

**Owed, from these rulings** (repo `CLAUDE.md` §6: a feature is not done until `doc/` explains it;
none of the docs edits below were made in the change that recorded this section, because the docs
branch was in the merge queue at the time):

- `doc/tutorials/obligations/what-is-coming.md` (lines 54, 63, 65, 79, 102 at `5dc0ca19`) and
  `doc/concepts/legal-modeling/regulative-layer-whole.md` (lines 242, 249, 260) teach an
  `EVERY`/`EACH` pair and the `HENCE FOR EACH` spelling. Both already hedge the words; the correction
  is the one-word scheme, the mandatory join line, and `UPON EACH` as the fork's ruled spelling. The
  "Six Ways to Owe One Debt" page (an artifact, §2.2.7.6) describes the same pair.
- The build's `doc/` page for the quantifier owes the `RAND`/`ROR` worked example of §8.3 (R-Q2,
  Meng's note).
- `doc/reference/regulative/README.md:104` promised `BEFORE` for absolute deadlines. **R-X5
  (2026-09-07, §5.1.2) keeps that reading**, and the page became true on 2026-09-16 when `BEFORE`
  was built (its section is now `## BEFORE (Absolute Deadline)`); `jl4/experiments/purchase.l4`'s
  seven `BEFORE n days` lines migrated to `WITHIN` in the same change.
- **The BPMN export cannot tell a barrier from a fork, and its fidelity report does not say so.**
  Measured 2026-09-07 by the GM on a binary built from `every/build-1`: one rule exported twice,
  once with `ONCE ALL HAVE` and once with `UPON EACH`, gives **byte-identical** BPMN XML and a
  **byte-identical** fidelity report. The report names the deontic modality (F1), the
  bearer-versus-performer gap (F2), the missing deadline unit and the absent as-of date (F5), and
  never mentions the join or the quantifier; the only trace of `EVERY` anywhere in the output is a
  lane label. This is introduced by this branch — `unstable` has no quantifier to lose — and it is
  the one export gap a reader cannot discover from the export, because the artifact whose job is to
  list the losses is silent about it. Recorded on `doc/reference/regulative/EVERY.md` as well.
  **LOCATED 2026-09-14, by source read on `unstable` `75068010`: it is the state graph, and
  `L4.Bpmn.Lower` could not fix it — the distinction is gone before the exporter sees its input.**
  `extractDeonton` (`jl4-core/src/L4/StateGraph.hs:673`) destructures
  `MkDeonton{subject, action, due, hence, lest}` and **does not bind `join`**; because that is a
  record pattern it kept compiling when the constructor grew, so nothing announced the loss.
  `subjectText`'s header (`:884-890`) already says it outright — an `EVERY` is one node, the cast
  is not fanned out, and _"the `ONCE …` join line is likewise not drawn"_ — which was a correct
  phase-1 scope note and is a defect only because the language moved past phase 1. Corroborating:
  `JoinOnce`/`JoinUpon` are referenced in nine modules under `jl4-core/src` (`Syntax`, `Parser`,
  `Desugar`, `TypeCheck`, `TypeCheck.Annotation`, `Parser.ResolveAnnotation`, `Print`, `Nlg`,
  `EvaluateLazy.Machine`) and in **no** `L4/Bpmn/*.hs` and **not** in `StateGraph.hs`. The fix is
  scoped as **P2h** in `specs/todo/lexipedia-superset/LTS-VISUALISER.md` §4.9 and §7.2, which also
  records what it does to that track's `DeonticStep` and correlation key.
  **FIXED 2026-09-15** (`fix/join-on-state-graph`, P2h first half): the state graph carries the join
  (`TransitionLabel.labelQuantifier`), `l4 state-graph` draws `ONCE ALL HAVE` / `UPON EACH` on the
  edge, and `l4 export --to bpmn` lowers an `EVERY` to a parallel multi-instance task — the barrier
  is that activity's own completion; the fork is reported as `P-FORK` (lossy), since BPMN can only
  say once-per-member with a multi-instance subProcess the exporter does not emit. `P-CAST`
  (advisory) says the cardinality is a run-time fact and names the roll; `P-JOIN-DEADLINE` (lossy)
  says when the join line's own `WITHIN` is not drawn. The sentence "it moves P1's goldens" that
  stood here was a prediction, and it was wrong: no BPMN golden source contained an `EVERY`, so the
  six existing goldens did not move; two new ones (`jl4/examples/bpmn/tenancy.l4`) are the witness.
  `doc/reference/regulative/EVERY.md` corrected in the same change.
- ~~`doc/reference/regulative/README.md:82-95` documents `WITHIN 5 days OF notice` as an anchored form.
  **Probed 2026-09-07:** it is a parse error (`unexpected OF` at the `OF`) on the installed binary of
  27 August and on the 4 September probe binary, with or without `days`. The page is owed a correction
  in the PR that builds the anchor of R-Q7 (§5.1), or sooner.~~ **DISCHARGED 2026-09-15** by the
  build of R-Q7A/B/C (§5.1.1): the `OF` form parses and runs, and the page now shows examples
  that check (`doc/reference/regulative/within-example.l4`, type-checked by `doc/test-docs.sh`),
  states the three lifecycle anchors, the date form and the refusals, and says in one sentence
  that nothing separates a date-serial trace from a floating-origin one (§5.1.2.1 point 2, T1
  not built).
- ~~`doc/tutorials/obligations/what-follows.md:153` and `:470` teach today's `LEST` anchor (the first
  event after the deadline) and a `WITHIN 13` workaround built on it. When R-Q7's `LEST` default is
  built (§5.2) that page changes and the trace goldens re-bless.~~ **DISCHARGED 2026-09-16** by the
  build of §5.2 (§5.2.1): the page was rewritten for the deadline clock, its pasted residuals
  re-run (`WITHIN 13`, `WITHIN 6`), the workaround struck, and the trace goldens re-blessed in the
  same change.
- In this document: extend §3–§9 to `SHANT` (R-Q3); define the release / substitute / join events
  (R-Q6, §13.4). The fork's words (R-Q1) were ruled 2026-09-07 and are recorded above; **the anchor
  spellings (R-Q7) were ruled the same day and are recorded at §5.1.1** — `OF` alone as the connective,
  `OF THE JOIN`/`OF THE DEADLINE`/`OF THE ARMING` for the lifecycle positions, and a date-valued
  expression admitted in the slot. Ruled 2026-09-07; **BUILT 2026-09-15** (§5.1.1's build block).
- Opened by those rulings: **the `AFTER` window** (§5.1.2 — sketched on Meng's request, then ruled:
  the early-act semantics R-X6 on 2026-09-07, the empty-window check scoped to the explicitly
  anchored form and the re-anchoring default on 2026-09-16, §5.1.2.2; its meaning under `LEST` falls
  out of §5.2's clock; **BUILT 2026-09-16**, §5.1.2's build block); and, owed to nobody yet,
  **an anchor picked by an expression** rather than named, which R-Q7B's note flags as
  the natural place for that pressure to arrive; and **a date library** with plain days, business
  days, officially recognised holidays, widely observed non-holidays, and weeks free of public
  holidays in a named jurisdiction (R-Q7C's note). The last is a library, not a language change:
  §5.1.1 measures that `WITHIN 5 days` already parses and checks once `days` is defined.

## 3. Semantics Overview

### 3.1 EVERY: The Barrier Model

> Spelling as ruled 2026-09-07 (R-Q1, §2.5): the barrier is the **`ONCE ALL HAVE`** join under
> `EVERY`. In the workflow-patterns catalogue it is **WCP-14**, multiple instances with
> synchronisation (the joint/several memo's §7.5 asked for the citation here).

**BUILT 2026-09-08** on `lang/every-runtime`; witness `jl4/examples/ok/every/run-barrier.l4`.
What that build did NOT do was §6.1's blame set — **built 2026-09-15** on `every/blame-set`, witness
`jl4/examples/ok/every/run-blame.l4`; see §6.1 and §11.0.1.

`EVERY` with a `ONCE ALL HAVE` join has **barrier semantics**:

- **HENCE fires** when ALL parties complete (join point)
- **LEST fires** when the barrier becomes unachievable — at the deadline for `MUST`/`DO`/`MAY`
  members, at the act for a `SHANT` member (R-Q5, §3.4)

```l4
EVERY p MUST X ONCE ALL HAVE HENCE shared_h LEST shared_l
-- Desugars to barrier structure, NOT simple conjunction
```

**Process algebra correspondence for EVERY:**

| Model         | Representation                                                     |
| ------------- | ------------------------------------------------------------------ | --- | --- | --- | --- | --- | ------------------------------------------------------- |
| **Petri Net** | AND-join: all input places must have tokens for transition to fire |
| **CSP**       | `(P1                                                               |     |     | P2  |     |     | P3) ; HENCE` — interleaving with sequential composition |
| **Counting**  | Semaphore initialized to n; HENCE fires when count reaches 0       |

### 3.2 EACH: The Fork Model

> Spelling as ruled 2026-09-07 (R-Q1, §2.5): the fork is the **`UPON EACH`** join under `EVERY`,
> and `EACH` is no longer a quantifier
> word. In the workflow-patterns catalogue it is **WCP-12**, multiple instances without
> synchronisation.

**BUILT 2026-09-08** on `lang/every-runtime`; witness `jl4/examples/ok/every/run-fork.l4`.

`EVERY` with a fork join has **fork semantics**:

- **HENCE fires** independently for each party that completes
- **LEST fires** independently for each party that fails

```l4
EVERY p MUST X UPON EACH HENCE h(p) LEST l(p)
-- Desugars to: (p1 MUST X HENCE h(p1) LEST l(p1)) ||| (p2 MUST X HENCE h(p2) LEST l(p2)) ||| ...
```

**Process algebra correspondence for EACH:**

| Model         | Representation                                    |
| ------------- | ------------------------------------------------- | --- | --- | --------- | --- | --- | -------------------------------------------------- |
| **Petri Net** | Parallel independent transitions, no join         |
| **CSP**       | `(P1 ; h1)                                        |     |     | (P2 ; h2) |     |     | (P3 ; h3)` — each process has its own continuation |
| **Counting**  | No shared counter; each completion is independent |

### 3.3 Without HENCE/LEST: Both Equivalent

**BUILT 2026-09-08** on `lang/every-runtime`; witness `jl4/examples/ok/every/run-modals.l4`. The
desugaring below is what the build does, literally: the members become a right-nested `RAND` fold
over the cast, because `RAND` already gives every operand the whole event stream, which is the
interleaving this section means.

When there is no continuation there is no join to write, and the barrier and the fork coincide: a
quantified obligation with no `ONCE` line is the plain distributive obligation. Unchanged in
substance by R-Q1 (2026-09-07) — it is the observation R-Q1 rests on, since it shows the distinction
is a property of the continuation and not of the quantifier.

```l4
EVERY p MUST X                          -- no ONCE line, no HENCE/LEST
-- Desugars to: (p1 MUST X) ||| (p2 MUST X) ||| ...
-- (Until 2026-09-07 this read: EVERY p MUST X  ≡  EACH p MUST X.)
```

### 3.4 State Transitions (EVERY Barrier)

```
                    Pending
        (completed=∅, pending=parties, failed=∅)
                        │
           ┌────────────┼────────────┐
           │            │            │
     party completes   party fails   deadline passes
           │            │            │
           ▼            ▼            ▼
        Pending      Pending       Failed
    (completed∪={p}) (failed∪={p}) (blame=pending∪failed)
           │                         │
           │ pending=∅               │
           ▼                         ▼
       Achieved                   LEST fires
    (t_last=max(times))          (blame set)
           │
           ▼
      HENCE fires
    (clock starts at t_last)
```

**The "party fails" transition — RULED 2026-09-07 (R-Q5, §2.5; Meng's mark: _"d"_).** The diagram
had a `party fails` edge with no event behind it. L4 has no party-failure event: the machine's only
event is party + action + timestamp (`jl4-core/src/L4/Syntax.hs:208-215`), and `REFUSE` is the model
declining to answer, "that no rule in the language can observe or convert into an answer"
(`Syntax.hs:361-371`) — not a party's act. So the edge is taken as follows, **by the layer the `LEST`
attaches to, then by the modal**:

- On the **state layer** — a `LEST` after an `ONCE … WITHIN` line (R-T2) — the failure time is the
  state's deadline, whatever the acts' modals; the `LEST` fires once, at that deadline, and the blame
  is the set (§6.1; a set-valued `BY` under R-T3 — the set is built as of 2026-09-15, the state-layer
  `LEST`'s own naming of it is not, see §6.1). §2.2.7.6's `rent owed jointly` is the case: `MAY`
  acts inside, one `LEST` at `due`. _As built (§5.1.1.1, 2026-09-15; re-read 2026-09-16):_ when
  BOTH an act `WITHIN` and the `ONCE` line's `WITHIN` are written and a member's act deadline
  passes first, the `LEST` attaches to the act layer — the deadline actually missed, the member's
  — and this state-layer sentence applies only when every member completed and the last act
  landed after the state deadline (`barrierStateMissed`); the machine compares the state deadline
  only after the join (`Barrier3`/`Barrier4`, reached from `barrierJoined` alone). The exemplar
  here has no act `WITHIN`, so the ruling's words did not reach that case; witness
  `run-anchors.l4`'s `the tenancy, a member late` (act 14, `ONCE` 30, Bob late: 14 + 5 = 19, not 35) and §11.0.1 "Stacking B on C", whose "earliest by R-Q5" is the act-layer reading.
- On the **act layer** — a `LEST` under the fork join, or a barrier with no state `WITHIN` — the modal
  fixes it: **`SHANT` fails at the act** (the violating event's own stamp; today's single-party
  behaviour at `Machine.hs:1648-1651`); **`MUST`, `DO` and `MAY` fail at the deadline**.
- **No modifier.** §13.1's opt-in early failure is declined: there is nothing for it to trigger on;
  and "early failure by default" would take away the innocent party's election under anticipatory
  repudiation — accept the repudiation and sue at once, or affirm and wait for the day of performance
  (the refuters' point, unverified in-tree). A drafter who wants an earlier consequence writes an
  earlier milestone obligation and composes it with `RAND`, which reports the compound breach as soon
  as one operand breaches (`Machine.hs:1742-1754`; the refuters' probe: breach at day 7 with the
  sibling's deadline at day 100).
- **Success time**, which R-Q7's anchor needs (§5.1): a `MUST`/`DO` barrier achieves at the last
  performance (`t_last`, as the diagram has it); a `SHANT` or `MAY` barrier achieves at the deadline,
  because for those modals the machine's success event is expiry (`Machine.hs:1592-1600`).

What "at the deadline" costs, measured by the refuters and recorded in §5.2: today a `MUST` breaches
only when a later-stamped event **reveals** the miss, and the breach carries the revealing event's
stamp (`stamp` bound at `Machine.hs:1522`, written into the breach at `:1606`); time alone breaches
nothing. Dating the failure to the deadline changes that stamp, and the trace goldens that print it.
(The §5.2 build of 2026-09-16 moved the `LEST` continuation's CLOCK to the deadline and left this
stamp where it was — §5.2.1, "What is NOT moved".)
§4.1's `boFailed` ("parties who cannot complete") is therefore populated by a `SHANT` violation
before the deadline and by every non-completer at the deadline, and by nothing else.

## 4. Formal Semantics

### 4.1 Semantic Domain

```haskell
data BarrierObligation = BarrierObligation
    { boParties      :: Set Party           -- obligated parties
    , boAction       :: Party -> Action     -- parameterized action
    , boDeadline     :: Time                -- shared deadline
    , boCompleted    :: Set Party           -- parties who completed
    , boPending      :: Set Party           -- parties still pending
    , boFailed       :: Set Party           -- parties who cannot complete
    , boEntryTime    :: Time                -- when obligation was entered
    , boHence        :: Maybe Continuation  -- success continuation
    , boLest         :: Maybe Continuation  -- failure continuation
    , boStatus       :: BarrierStatus
    }

data BarrierStatus
    = Pending
    | Achieved Time              -- completion time (for HENCE clock)
    | Failed Time (Set Party)    -- failure time and blamed parties
```

### 4.2 Denotational Semantics

> **`parties = { p | p ∈ P, pred(p) }` below is not constructible, and §11.0 (2026-09-08) says
> what the run time does instead.** `P` is normally an open type, so the comprehension has no
> finite extension; the machine reads the cast off the filter's `elem` conjunct — the roll — and
> refuses when there is none.

The party type `P` is determined by the deontic context (`GIVETH DEONTIC P A`):

```haskell
⟦EVERY v WHO pred MUST act WITHIN δ HENCE h LEST l⟧ :: Trace -> Time -> Verdict
-- where v has type P from the enclosing DEONTIC context
⟦...⟧ tr t =
    let parties   = { p | p ∈ P, pred(p) }    -- P is the party type from context
        completed = { p | p ∈ parties, (p, act(p), t') ∈ tr, t' ≤ δ }
        pending   = parties \ completed

        status =

            if completed == parties
            then Achieved (max { t' | (p, _, t') ∈ completions })
            else if t > δ
            then Failed δ pending
            else Pending

    in case status of

        Achieved t_ach -> (Success, spawn(h, t_ach))
        Failed t_f blame -> (Breach t_f blame, spawn(l, t_f))
        Pending -> (Pending, [])
```

### 4.3 Operational Semantics (SOS Rules)

**Configuration:** `⟨B, σ, t⟩` — barrier B, trace σ, current time t

**Rule 1: Party Completes**

```
    p ∈ B.pending
    (p, B.action(p), t') ∈ σ
    t' ≤ B.deadline
─────────────────────────────────────────────────────────
    ⟨B, σ, t⟩ → ⟨B[completed ∪= {p}, pending \= {p}], σ, t⟩
```

**Rule 2: Barrier Achieved**

```
    B.pending = ∅
    B.failed = ∅
    t_last = max { t' | (p, _, t') ∈ completions }
────────────────────────────────────────────────────────
    ⟨B, σ, t⟩ → ⟨Achieved(t_last), σ, t⟩
    spawn(B.hence, t_last)
```

**Rule 3: Deadline Failure**

```
    t > B.deadline
    B.pending ≠ ∅
    blame = B.pending ∪ B.failed
─────────────────────────────────────────
    ⟨B, σ, t⟩ → ⟨Failed(B.deadline, blame), σ, t⟩
    spawn(B.lest, B.deadline)
```

**Rule 4: Early Failure (optional policy)**

```
    B.failurePolicy = EARLY_FAILURE_DETECTION
    ∃p ∈ B.pending. incapacitated(p)
─────────────────────────────────────────────
    ⟨B, σ, t⟩ → ⟨Failed(t, {p}), σ, t⟩
    spawn(B.lest, t)
```

## 5. Clock and Temporal Semantics

### 5.1 Reference Time for Continuations

**RULED 2026-09-07 (R-Q7, §2.5; Meng's mark: modify — _"e but with a as default when no OF?"_).**
Two things, the mechanism and the default (GM's reading of the mark, 2026-09-07: mechanism, not
policy — the drafter names the anchor, and the language supplies a default when none is named):

1. **The mechanism: a named anchor on the continuation.** A drafter may write the anchor —
   `` WITHIN 5 days OF `the last signature` ``, `` WITHIN 5 days OF `the closing date` `` — and the
   machine must expose four: **the join's firing**, **the missed deadline**, **the arming time**, and
   **any recorded event**. Their spellings are not ruled; §2.4 carries the production as
   `'WITHIN' Duration ['OF' Anchor]`.
2. **The default for an unanchored `WITHIN`.** Under `HENCE`, the continuation's clock starts at the
   **join's firing** — the last completion for a barrier, the k-th performance for `SOME m OF`, the
   moment the `ONCE` condition holds for a measure. This is today's single-party rule generalised: on
   the matched event the scan sets `time = ev'time` (`Machine.hs:1612`), the success branch hands that
   `time` to `continueWithFollowup` (`:1669-1671`), and the followup is applied to `[time, events]`
   (`:1798-1804`). The refuters' probe on the installed binary: `sign AT 3` with `HENCE … WITHIN 5`
   reports the continuation's deadline as 8 — act + `WITHIN`, not 5 (from arming) and not 15 (from
   the barrier's own deadline) — and an intervening `WAIT UNTIL` leaves it unmoved. It is the only
   option under which a cast of one behaves like today's `PARTY`. Under `LEST`, the default is the
   **missed deadline** — §5.2, where it was recorded as a change and, since 2026-09-16, as built
   (§5.2.1).

The cost the ruling accepts: an early-completing cast gives the continuation an early deadline
("within five days of the last signature", not "on the completion date"); the named anchor is what
makes the other clause writable. The card's earlier escape hatch, "write an absolute `BY date`", is
struck: R-T2 ruled nothing about `BY` (its subject is `WITHIN` in two positions), and a deadline `BY`
is unruled and unbuilt (§2.4).

**The manual's `OF` form did not run until 2026-09-15.** `doc/reference/regulative/README.md:82-95`
documented `WITHIN 5 days OF notice` and `` WITHIN 5 days OF `order confirmation` `` as an anchored
form. Probed 2026-09-07 on the installed binary of 27 August and on the 4 September probe binary,
`JL4_LIBRARY_PATH` unset: both reported `unexpected OF` at the `OF`, with or without `days`. The
`deadline` production was `WITHIN` followed by one expression (`Parser.hs:2693-2695` at `e578654c`;
`:2534-2536` when this paragraph was first written), and `OF` was not an operator inside an
expression. The page was owed a correction (§2.5's owed list); **the build of §5.1.1 on 2026-09-15
made the sentence true** — `WITHIN 5 days OF notice` now parses, and checks once `days` and
`notice` are defined — and the page was corrected in the same change.

When `HENCE` fires, an unanchored continuation deadline is relative to the join's firing — for a
barrier, the **last completion time**:

```
EVERY p
    MUST   sign
    WITHIN 30
    ONCE   ALL HAVE
    HENCE  PARTY escrow_agent MUST release_funds WITHIN 5
    LEST   PARTY escrow_agent MUST return_funds  WITHIN 5   -- from day 30, the missed deadline (§5.2)

Timeline:
t=0:  Obligation entered
t=10: Party A signs
t=20: Party B signs
t=25: Party C signs  ← barrier achieved, t_last = 25
t=25: HENCE spawns with reference time = 25
      escrow_agent's deadline = 25 + 5 = 30
```

#### 5.1.1 The anchor's spelling — RULED 2026-09-07 (R-Q7A, R-Q7B, R-Q7C); BUILT 2026-09-15

§5.1 above ruled the anchor's **mechanism** and its **defaults** and left its **spelling** open.
Three cards — the Anchor Bench, an artifact of 2026-09-07, **not in the tree**
(<https://claude.ai/code/artifact/0e3b1279-79c2-4616-ada7-bad7473e9630>) — closed it. All three were
marked **accept**, on the recommended option in each case, between 03:37 and 03:41 UTC on
7 September 2026. Meng's notes are quoted verbatim, and each one opens a follow-up rather than
qualifying the ruling; the follow-ups are listed at the end of this section and in §2.5's owed list. **All three
are built** as of 2026-09-15 (the block at the end of this section); when this paragraph was written
none was, and the grammar in §2.4 carried the production with no parser behind it.

**R-Q7A — the connective is `OF`, and only `OF`.** Not `AFTER`, and not the two as synonyms. `OF` is
already a keyword (`Lexer.hs:278` at `e578654c`; `:268` when this was written, `TKOf`), so the slot reserves no new word, and it is the form
`doc/reference/regulative/README.md:82-95` already documents. This is a grammar addition either way:
measured 2026-09-07 on a binary built from this branch, `WITHIN 5 OF notice` was a **parse error at
the `OF`**, because `WITHIN` took exactly one expression (`Parser.hs:2534-2536` then) and `OF` is not an
operator inside one. Built 2026-09-15: see the block at the end of this section for what the
addition had to decide about `OF`, which is ALSO application inside an expression.

> _"Forecasting the future here: a triggerable interval may not activate immediately upon the
> previous event; for instance, we might say: 'after the current order is delivered, the customer may
> place a new order AFTER a three-business-day cooling-off period, WITHIN 30 days starting at the end
> of the cooling-off-period.' So we might want to reserve AFTER for that sort of construct. Shall we
> try to sketch a design for that now?"_

So `AFTER` is **held, not rejected**: it is spoken for by a different construct — the
earliest-permitted edge of a window — sketched at §5.1.2, which answers the question in that note.

**R-Q7B — the three lifecycle anchors are `OF THE JOIN`, `OF THE DEADLINE`, `OF THE ARMING`.** Three
of the four anchors §5.1 requires are positions in the obligation's own life, not values a drafter
can point at; the fourth, a recorded event, already has a name the drafter chose. `THE` is already a
keyword (`Lexer.hs:283` at `e578654c`; `:273` when this was written, `TKThe`), and `JOIN`, `DEADLINE` and `ARMING` are matched by **spelling**
rather than reserved — the same move `UPON EACH` makes for `EACH`, ruled the same morning (R-Q1,
§2.5). So the whole of R-Q7B costs zero new reserved words. Measured 2026-09-07: none of the three
nouns appears as an identifier anywhere in the goldened corpus. **Re-measured 2026-09-15 on
`e578654c`** before building: `grep -rnw "JOIN\|DEADLINE\|ARMING" --include=*.l4 jl4/examples
jl4-core/libraries doc` → 47 hits, every one inside a `--` comment; and `grep -rn "WITHIN.*\bOF\b"
--include=*.l4` over the goldened globs → 0 hits. No corpus file could re-parse differently, and
the goldens confirm it: no eval, exactprint, NLG or schema golden of a parseable corpus file
moved. (Two parse-error goldens did, by one token: `not-ok/tc/every-join-misindented{,-barrier}`
list what may follow `WITHIN 14`, and `OF` now may — see §11.0.1's ledger entry.)

Why each is wanted. **The join's firing** is the `HENCE` default, so naming it is only ever emphasis.
**The missed deadline** is the `LEST` default, but a drafter may want it under `HENCE` — _the cure
period runs from the date performance fell due, not from the day the last party finally signed_.
**The arming time** is reachable no other way: it is when the obligation was entered, which is what
_within 30 days of this agreement_ means. The machine already computes all three (§5.1's
`Machine.hs` citations for the firing; the deonton's entry for the arming; R-Q5 for the missed
deadline), so this is a naming question and not a semantics question.

> _"Using 'the X' suggests that a drafter may want to reach for 'some other X' resolved using some
> expression, but let's not get too anxious; go with this for now, and just note a possibility that
> this would be the natural place for someone to want to add sophistication that we might not be able
> to support just yet."_

Noted, and it is a real forward pressure: `THE` is a definite article, and a definite article invites
an indefinite sibling. The shapes it would open — `OF SOME …`, `OF THE JOIN OF <rule>`, an anchor
picked by an expression rather than named — are **not designed and not ruled**, and nothing here
forecloses them. The one thing this ruling should not do is make them harder to add later, which is
why the three nouns are matched by spelling in one position rather than reserved globally.

**R-Q7C — the slot admits a date-valued expression.** `WITHIN 5 OF closingDate` is the way to write
an absolute deadline, and `WITHIN 0 OF (YMD 2026 6 30)` is _by 30 June_. This closes a hole §5.1
opened when it struck the `BY date` escape hatch: the strike was right on the law of it — R-T2 ruled
nothing about `BY`, and `TKBy` already serves `FOLLOWED BY`, `DIVIDED BY` and `BREACH BY`, so a
deadline `BY` would be a fourth meaning for that word — but it left _this must happen by 30 June_
with no ruled spelling at all. The cost is that the slot becomes a three-way union the checker
discriminates: a lifecycle anchor, a recorded event, or a `DATE`.

> _"we need to beef up our date libraries to better support things that people will want to put in
> this slot -- plain days; business days; holidays officially recognized; including non-holidays of
> widespread observance; weeks not containing public holidays in x jurisdiction; and so on."_

That is a **library** requirement, not a language one, and it is now on §2.5's owed list. The reason
it lands here rather than in the grammar is the one measurement that retired what had been a fourth
card: **unit words need no ruling and no grammar change**. Measured 2026-09-07 on a binary built from
this branch, `WITHIN 5 days` **parses**; it fails only the check, with _could not find a definition
for the identifier_, because `days` names nothing. (Re-measured 2026-09-15 by the adversarial pass:
that is the behaviour of a file with no mixfix operator in scope — no import, no local mixfix
`DECIDE`. With one in scope, `IMPORT prelude` being enough, `L4.Parser.mixfixPostfixOp` accepts only
the operator words it knows and the same line stops in the parser with _unexpected days_. Either
way `days` names nothing until it is defined, which is the point.) Add one line of ordinary L4 —
`GIVEN n IS A NUMBER GIVETH A NUMBER DECIDE n days IS n` — and the same file reports **Check
succeeded**. So `days`, `` `business days` ``, `` `weeks not containing a public holiday in
Singapore` `` are all already expressible through mixfix and backticked names; what is missing is a
calendar for them to consult, which is a library to write and not a keyword to reserve. The corpus
already writes `` WITHIN `five business days` `` 11 times, which is exactly this move made by hand.

**What these three do not settle.** The `AFTER` window (§5.1.2 — ruled since, on 2026-09-07 and
2026-09-16, and built 2026-09-16); an anchor
picked by an expression rather than named (R-Q7B's note); the date library (R-Q7C's note); and
whether an anchored `WITHIN` under `LEST` may name `THE JOIN` at all, which is a well-formedness
question — under `LEST` the join did not fire. (The build below takes the conservative reading of
the last one as a build decision, not a ruling; see "refusals".)

##### 5.1.1.1 BUILT 2026-09-15 — the mechanism, and the decisions the ruling left to the build

Built on `every/anchors`, cut from `unstable` `e578654c`, rebased onto `0b640727` on 2026-09-16 (and,
on `every/anchors-on-blame`, onto `every/blame-set`'s `cedbf7e6` the same day — §11.0.1 "Stacking B on C"). Witness:
`jl4/examples/ok/every/run-anchors.l4` (41 directives, each pinning one anchor to the deadline it
produces, or what a residual prints; 27 at the first commit, 14 added by the adversarial pass —
see the list at the end of §11.0.1's ledger entry); refusals witnessed by `jl4/examples/not-ok/tc/anchor-{top-level-join,lest-join,not-an-instant,no-deadline,on-join-line}.l4`;
highlighting by `jl4/examples/lsp/semantic-tokens/anchors.l4`. **Line numbers below are on
`every/anchors` at `82c61419`** — its tip before the stack onto `every/blame-set`, where they were
re-cited after the adversarial pass — and are NOT current on `every/anchors-on-blame`, where C's
insertions shift every `Machine.hs`, `ContractFrame.hs`, `TypeCheck.hs`, `Types.hs` and
`Syntax.hs` number cited below (measured: each file's first C hunk lies above its smallest cite).
The `Parser.hs`, `Print.hs` (`:959`, `:968` sit above C's first `Print.hs` hunk at `:1250`),
`Nlg.hs`, `Document.hs`, `Schema.hs` and `SemanticTokens.hs` cites still hold there; this section
cites no `ValueLazy.hs` or `Backend/Jl4.hs` line. Read the shifted ones with
`git show 82c61419:<file>`; §11.0.1 "Stacking B on C" carries live cites for `Machine.hs` and
`ContractFrame.hs` only — it does not re-cite the `TypeCheck.hs`, `Types.hs` or `Syntax.hs`
items.

**Syntax.** `Deonton.due` and the join line's deadline both become `Maybe (Deadline n)`
(`Syntax.hs:420`, `:491`, `:493`), where `Deadline n = MkDeadline Anno (Expr n) (Maybe (Anchor n))`
(`Syntax.hs:543`) and `Anchor n` is `AnchorJoin | AnchorDeadline | AnchorArming | AnchorAt (Expr n)`
(`Syntax.hs:585`). The parent's hole count is unchanged — one hole for the deadline — so exactprint
and the semantic tokens zip as before; inside the node the holes are `[duration, anchor]` in source
order and `WITHIN` is a token of the node's own `Anno`. Measured: `exactprint identity` and the
`prettyLayout round-trip` hold over the whole corpus with the witness included, and no `.ep.golden`
of a parseable corpus file moved (the two parse-error goldens that did, by one token, are listed
under R-Q7B above and in §11.0.1's ledger entry).

**The one thing the grammar had to decide: `OF` is also application.** `name OF args` is a
function call inside an expression (`Parser.hs:2176`, `app`), so with the duration parsed as an
ordinary expression `WITHIN period OF closingDate` would silently have been `period` applied to
`closingDate` (a check error for a nullary `period`; a wrong answer with exit 0 for a
`NUMBER → NUMBER` one), and `WITHIN period OF THE JOIN` a parse error at `THE`. Measured on
`e578654c` before building: `WITHIN period OF notice` parsed as the application. Decision: **in
the duration slot of a `WITHIN`, `OF` is the anchor**, by a flag in the parser's reader
environment (`Env.ofIsAnchor`, `Parser.hs:67`) that `deadline` sets and that parentheses and the
anchor itself reset (`inExprSlot`, `Parser.hs:1260`); `app` takes juxtaposed arguments only while
it is set. The flag is set for the WHOLE unbracketed duration, not for its head application only:
an `OF` inside an `IF` branch, an operator's operand or a `WHERE` in the duration is the anchor
too (measured by the adversarial pass: `WITHIN IF TRUE THEN twice OF 3 ELSE 1` is a parse error at
`OF`, `WITHIN 1 PLUS twice OF 3` fails the check on `1 PLUS twice` — a `__PLUS__` overload error
with `IMPORT prelude` in scope, whose set `__PLUS__` adds a second candidate, and a plain
second-input mismatch (`NUMBER` expected, `FUNCTION FROM NUMBER TO NUMBER` found) without it —
`WITHIN d WHERE d MEANS twice OF 3` re-associates
to `(d WHERE …) OF 3` and fails the check on `d` — each of which parsed as an application on
`e578654c`; none of the shapes occurs in the goldened corpus, and the one pre-existing
`WITHIN f OF x` anywhere in the tree, `jl4/experiments/jerseyCharities2-annual-returns.l4:214`,
sits in a file that did not parse before either, its first error being at line 244). An applied
duration is written `WITHIN (f OF x) OF …` or `WITHIN f x OF …`, which is also what `prettyLayout`
prints (`parensIfNeeded` brackets an application), so the round trip holds; and when a duration
next to an anchor fails to be a `NUMBER`, the checker's mismatch message says so in those words
(`ExpectAnchoredDurationContext`, `TypeCheck.hs:2021`, `checkDeadline`) — the unanchored wording is kept
for the unanchored form, whose golden did not move. The three nouns are matched by spelling in one
production (`anchor`, `Parser.hs:2745`); no expression begins with `THE`, so the alternatives are
disjoint on their first token, and `THE FOO` reports `expecting ARMING, DEADLINE, JOIN, or space
token` (verbatim; the trailing alternative is megaparsec naming the whitespace consumer).

**The enclosing-obligation rule.** The three lifecycle anchors name positions in the life of the
obligation whose `HENCE` or `LEST` the anchored obligation is the continuation of — the
**nearest** enclosing one, and **the one it is attached to when it runs**. For a continuation
written inline the two coincide. For one that arrives as a VALUE — a `GIVEN k IS A DEONTIC …`
parameter (`after k MEANS PARTY bob MUST … HENCE k`, the idiom `jl4/experiments/housing-act-*`
write as `onwards`), a `WHERE` local, a top-level rule named in a `HENCE` — the anchors name the
obligation whose hand-off applies it, not the one it was written under (witness: `handed on, the
join`, 50 + 5 = 55, the same instant the unanchored form counts from; `handed on, the deadline`,
103 + 5 = 108; `factored out`, a `WHERE` local reading its attaching obligation's arming, 0 + 5 = 5,
exactly as inline). The first commit's mechanism was lexical, so `OF THE JOIN` in a handed-on
value read the obligation it was WRITTEN under (3 + 5 = 8 where the unanchored default gave 55) —
which falsified the doc's "the default, said out loud" and the brief's own definition of
"enclosing"; the adversarial pass made it dynamic at the hand-off (next paragraph). Under a fork
the enclosing obligation is the member; under a barrier it is the `EVERY`. At the top level there
is none: `THE JOIN` and `THE DEADLINE` are refused there and `THE ARMING` is the obligation's own
arming, i.e. the default, allowed and pointless (witness: `own arming`). The checker sees only
where an anchor is WRITTEN, so a top-level rule and a `WHERE` local are refused `THE JOIN`/`THE
DEADLINE` (the refusal message says so) and allowed `THE ARMING`; what the checker cannot see, the
run time refuses when it happens (refusals 6 and 7 below). `THE ARMING` two levels down names the
MIDDLE obligation's arming, not the outermost rule's (witness: `of the arming`, deadline
5 + 40 = 45) — "within 30 days of this agreement" therefore reaches the agreement from ONE level
down, which is where the phrase is written, and the doc page now says so; whether a deeper
continuation should be able to reach the outermost arming is open, and would need a way to name a
non-nearest obligation (R-Q7B's note; §5.1.3's direction). For a kept `SHANT` the join is the
event that revealed the deadline had passed — the hand-off clock, `Machine.hs` `reofferResolve` —
not the deadline itself, so `OF THE JOIN` there is today's unanchored clock said out loud and `OF
THE DEADLINE` is the way to count from the discharge (witness: `kept, the join`, 30 + 3 = 33;
`kept, the deadline`, 10 + 3 = 13; the doc page states it). Binding `join` to the deadline on that
path instead was not done: it would part `OF THE JOIN` from the unanchored default. §5.2's track
(BUILT 2026-09-16, §5.2.1) moved the unanchored default under `LEST` — for the single-party path
and the barrier together, through one reference — and left this `HENCE` alone, so `OF THE JOIN` and
the unanchored clock still coincide here; whether both should move to the deadline is recorded in
§5.2.1 as open to Meng's ruling.

**Threading, chosen: bindings in the continuation's environment, rebound into its value.** At
every hand-off the machine builds a `Lifecycle` (`ContractFrame.hs:404`: the join instant under
`HENCE` only, the absolute deadline when there is one, the arming) and binds it into the
continuation's environment under three fixed uniques of a sort no name table uses
(`Machine.hs:2567-2585`, `bindLifecycle`), so no program can spell, shadow or capture them.
`continueWithFollowup` (`Machine.hs:2040`), `fireBarrierHence` (`:2476`), `barrierFail` (`:2506`)
and `barrierStateMissed` (`:2524`) all bind it. Three things the adversarial pass changed about the
binding. (1) It REPLACES all three: a position the hand-off does not have is deleted, where the
first commit left an outer binding in place — measured: an empty-cast barrier nested under an
obligation `WITHIN 10`, with `OF THE DEADLINE` in its `HENCE`, silently read 10 + 5 = 15, exit 0.
(2) It is made twice — into the environment the `HENCE`/`LEST` expression is evaluated in, and
again into the VALUE that expression produced, by a `Handoff` frame pushed under the `App1`
(`ContractFrame.hs:93` `Handoff`; `Machine.hs:2602` `rebindLifecycle`, which reaches a `ValObligation`, a
`ValQuantified` and a `ValROp`'s own environment). (3) A compound's OPERANDS are handed off one at
a time when the compound is applied: `App1`'s `ValROp` arm (`Machine.hs:1127`) and `RBinOp1`
(`:1903`) push a `Handoff` carrying the lifecycle read back from the compound's environment
(`lifecycleOf`, `:2614`; `operandHandoff`, `:2633`) before evaluating an operand that is still an
expression. Round 1 wrote that "the `RBinOp` paths need nothing, because `ValROp` captures the
environment for both operands"; that was false for an operand that is a VARIABLE bound to a
continuation built elsewhere — the value carries its own environment, and rebinding the two
operand expressions' shared environment does not reach it. Measured on the round-1 tree (`f2ba534d`
before the branch was rebased onto `origin/unstable`): `HENCE (k RAND
…)` with `k` a `GIVEN` parameter anchored `OF THE JOIN` read the join of the obligation `k` was
WRITTEN under (3 + 5 = 8, not 50 + 5 = 55); `OF THE DEADLINE` read 15, not 108; a `WHERE` local
inside a compound read its own arming; and `LEST (k RAND …)` with a handed-on `OF THE JOIN`
silently produced 8 where `LEST k` refused — all exit 0. An operand already reduced to a value is
NOT handed off: it was built by the machine in this compound's own context — a fork's members
(`randFoldWHNF`, whose environment binds `THE ARMING` to the `EVERY`'s own arming for a demoted
join-line deadline and must keep it) or this compound's residual (`RBinOp2`) — and carries the
bindings it needs. Witnesses: `handed on, in a compound, the join` (55 / 55), `… the deadline`
(108 / 108), `handed on, either way` (`ROR`, timely at 55), `factored out, in a compound` (5),
`handed under a LEST, in a compound` (refused). The dynamic rule is not the register the first
commit rejected: nothing is global, the bindings live in the one value being applied. What the
rebinding does is ADD the bindings a handed-on value needs, so its anchors resolve against the
obligation it is attached to; it never widens what the checker admits — every run is preceded by
a check, and a top-level rule named in a `HENCE` still cannot use `THE JOIN`/`THE DEADLINE`
because the checker refuses it where it is written. In the other direction the run is STRICTER
than the checker: refusals 6 and 7 below are exactly the programs the checker let through, because
it saw only where the anchor was written, and the run rejects where it is used (round 1's sentence
here read "MORE permissive than the checker, never less", which those two refusals contradict).
The arming had to be **kept**: the act frames overwrite `time` on every event, so each of the
eleven carries `armed` as well (`ContractFrame.hs:111` and siblings), set at `App1`
(`Machine.hs:1117`).

**Resolution and arithmetic.** The deadline is resolved ONCE, at the first event, when the frame's
`time` is still the arming time (`Contract4`, `Machine.hs:1544`): a lifecycle anchor is the
environment binding (`lifecycleRef`, `:2642`, with the obligation's own `armed` as `THE ARMING`'s
fallback), an expression is evaluated in the obligation's environment, and a `DATE` value is
lowered by its serial (`Contract4b`, `:1574` — the same arithmetic as `DATE_SERIAL`, not a call
through it: an `App` inserted into the AST would have no tokens and would break exactprint). Then
`Contract5` computes `deadline = anchor + d` instead of `time + d` (`:1594`) and the remaining
due is relative again; the anchor is spent. So a deadline already past at arming is revealed by the
first event (witness: `already expired`), and a residual that has met no event prints the source
form, anchor and all, while one that has prints the days remaining (witness: the last section).

**`THE DEADLINE` under a barrier, and the `RAND` question.** By slot. Under `HENCE`, THE DEADLINE
is the `ONCE` line's `WITHIN` when written (the deadline on the whole, R-T2; `Barrier4`, `:1880`),
and otherwise the **latest of the members' act deadlines** — the instant by which all performance
fell due, which is what §5.1.1's own motivation ("the cure period runs from the date performance
fell due") asks for — kept as a running maximum (`BarrierStepFrame.dueLatest`, `ContractFrame.hs:339`, forced per
completion by `Barrier2b`, `Machine.hs:1856`), so neither who completed last nor the roll's order can move it
(witnesses: `the tenancy`, 14 + 5 = 19; `the tenancy, bounded as a whole`, 30 + 5 = 35;
`per member`, Alice due 20 and Bob due 10, 20 + 5 = 25 from either roll and on a tie). The first
commit took "the act deadline of the member whose completion fired the join", which on a tie was
whichever member the roll named first (measured: `LIST alice, bob` FULFILLED, `LIST bob, alice`
BREACHED, same events) and on no tie was the last completer's rather than the group's; the
adversarial pass replaced it. Under `LEST`, THE DEADLINE is the deadline that was actually missed:
the failing member's act deadline when a member expired (`barrierFail`, carried by the sentinel) —
and once R-T3 is under this (§11.0.1 "Stacking B on C", 2026-09-16), _which_ failing member is the
one whose failure the `LEST` is anchored at: the earliest by its failure time — the missed
deadline since 2026-09-16 (§5.2.1), so two misses one event reveals are already ordered; until
then the revealing stamp, with a tie broken by the earlier deadline —
the `ONCE` line's when everyone acted but the last act landed after it (`barrierStateMissed`) —
witnesses `the tenancy` (LEST, 14 + 5 = 19), `the tenancy, a member late` (act 14 and `ONCE`
30 both written, Bob late: 14 + 5 = 19, not 35), `the tenancy, the group late` (30 + 5 = 35), `by
instant 105`. The first commit's prose said "the `ONCE` line's when written" for both slots, which
the code never did under `LEST`; corrected here, on the doc page and in the `Lifecycle` haddock.
Note that R-Q5's state-layer bullet, read by its words alone ("a `LEST` after an `ONCE … WITHIN`
line"), would put `the tenancy, a member late` on the state layer and its failure time at 30; the
build attaches the `LEST` to the layer whose deadline was actually missed, and R-Q5 now carries an
as-built note saying so (2026-09-16, the stack's round 2).
An EMPTY cast is joined at its arming (`BarrierEmpty`, `Machine.hs:1863`; `barrierJoined`, `:2452`) and goes through the same
`Barrier3`/`Barrier4` path, so THE DEADLINE is the `ONCE` line's `WITHIN` when written (witness:
`nobody, bounded as a whole`, 0 + 30 + 5 = 35 — the first commit bypassed that path and refused
with a message that blamed the wrong things). Going through that path means the empty cast is
NOT unconditionally a `HENCE`: `Barrier4` (`:1880`) compares the join time — here the arming —
against the state deadline, and an anchored `ONCE`-line `WITHIN` whose deadline already lies
BEFORE the arming (`ONCE ALL HAVE WITHIN 5 OF 0`, armed at 10) sends the empty cast to the `LEST`,
where `THE DEADLINE` is that state deadline (measured: 5 + 3 = 8). The unanchored form cannot
reach this (arming + d ≥ arming), so it is new with this track; the doc pages say so. The
alternative — an empty cast bypasses a state deadline already past and fires the `HENCE` — was
not taken: "nobody is late" is not what a deadline that expired before anyone could be asked
means, and the barrier's other paths do not special-case it either. Open to Meng's ruling; with only an act `WITHIN` there is no member deadline
and no `dueLatest`, so the run refuses, naming the empty cast (refusal 6; witness: `nobody, act
deadline only`, which is also the nested case that once leaked 15). To carry a member's deadline
to the barrier without running the member twice (§11.0.1's second-pass defect), the barrier's two
sentinels are minted with a unique of their own sort (`defSentinel`, `:2374`) and the member's
hand-off passes them a THIRD argument, the member's absolute deadline (`continueWithFollowup`,
`:2046`; `sentinelArgs`, `:2366`); every other continuation is applied to `[time, events]` exactly
as before, and the sentinels still print as `` `the join` `` / `` `the join fails` ``. A first
attempt applied the sentinel to the deadline as an expression, which made the residual print
``HENCE (`the join` OF `the deadline`)`` and moved `run-barrier.golden`; withdrawn. A `RAND`
continuation has ONE enclosing obligation — the one whose `HENCE`/`LEST` the `RAND` sits in — and
both operands see its bindings: an operand written inline evaluates in the compound's environment,
and an operand that arrives as a value is handed off with that same lifecycle when the compound is
applied (`operandHandoff`, above); that is the brief's "the one whose completion or failure fired
it", by construction.

**The join line's own `WITHIN`.** `OF THE ARMING` there is the `EVERY`'s arming, which is also what
it counts from unanchored (`Barrier3`, `:1868`); `OF e` is an instant (witness: `by instant 105`).
A join-line `OF e` is evaluated when the join fires — at `barrierFinish`, after the last member has
acted — not at the `EVERY`'s arming, unlike an act-line anchor (`Contract4`, once, at the first
event); and when the join-line deadline is demoted to the members (R-T2, no act `WITHIN`), each
member evaluates it again at its own first event, so a ledger-reading `e` is read once per member
and once more at the join. Stated as a limit; no witness reads the ledger in an anchor. In the
demoted case each member's environment binds `THE ARMING` to the `EVERY`'s arming (`memberEnv`,
`:2273`) so a nested `EVERY` does not read its enclosing obligation's arming there (witness:
`after delivery`, 5 + 14 = 19). On the ACT line of a nested `EVERY`, by contrast, `OF THE ARMING`
is the enclosing obligation's arming, as on a `PARTY` rule in the same place — so the same words
name an earlier instant on the act line than on the join line, and naming the anchor on the act
line moves the deadline EARLIER than leaving it off. The adversarial pass raised this as a trap and
the refuters upheld the semantics (they are this rule); the doc page now contrasts the two lines.

**Refusals — build decisions, each open to Meng's ruling** (`checkAnchor`, `TypeCheck.hs:2046`;
`AnchorRefusal`, `Types.hs:414`; the enclosing obligation is a `CheckEnv` field set with `local`
around each continuation, `Types.hs:785`, `TypeCheck.hs:2095`):

1. `THE JOIN` and `THE DEADLINE` with no enclosing obligation (top level) — refused.
2. `THE JOIN` under `LEST` — refused: the join did not fire. This is the conservative reading of
   the question this section left open; the alternative (bind it to the revealing stamp, the
   unanchored `LEST` clock of the time) was not taken because it would give the name a meaning
   §5.2 was about to take away from the default — and did, on 2026-09-16 (§5.2.1).
3. `THE JOIN` and `THE DEADLINE` on a join line — refused: that `WITHIN` is what defines both.
4. `THE DEADLINE` where the enclosing obligation has no `WITHIN` on its act or its join line —
   refused. Not in the brief; the checker can see it, and the run time would otherwise have had to
   invent a value.
5. An `OF` expression that is neither `NUMBER` nor `DATE` — refused naming both
   (`AnchorNotAnInstant`, `Types.hs:226`). The choice is biased: an inference variable is taken as
   `NUMBER`.

Two more are RUN-TIME refusals (`lifecycleRefusal`, `Machine.hs:2655`), because only a run can see them
— added by the adversarial pass, which also made the message name each cause instead of asserting
"not inside any HENCE or LEST" for a value that is:

6. `THE DEADLINE` in the `HENCE` of a barrier whose cast was EMPTY and whose `ONCE` line has no
   `WITHIN` — nobody had a deadline to meet. The alternative, arming + the act's `WITHIN` evaluated
   in the `EVERY`'s environment, was not taken: the act `WITHIN` may mention the member
   (`WITHIN grace t`), and inventing a value is what refusal 4 declines to do.
7. A continuation that arrived as a value and is attached where the position does not exist —
   `THE JOIN` under a `LEST`, `THE DEADLINE` under an obligation with no `WITHIN` — also when
   the value is one operand of a compound. The checker accepted the anchor where it was written;
   the run refuses it where it is used (witnesses: `handed under a LEST`, `handed under a LEST,
in a compound`, `handed to no WITHIN`).

**Printers and exporters.** `prettyLayout` prints `d [OF anchor]` with the duration bracketed
exactly as before (`Print.hs:959`, `:968`), so every unanchored deadline prints byte-for-byte as it
did; NLG says `within d of the join` (`Nlg.hs:246`); the document export renders "5 of the
deadline" and, unlike a bare `WITHIN 0`, does not drop `WITHIN 0 OF date` (`Document.hs:1113`); the
state graph's `labelDeadline` carries the source text, which the BPMN lowering reports as unparsed
(stated limit); the MLIR schema fails closed on any anchored deadline (`Schema.hs:926`); the LSP
highlights `JOIN`/`DEADLINE`/`ARMING` as keywords by the `UponEach` device
(`SemanticTokens.hs:224`); the service serialises an unevaluated anchored deadline as its source
text.

**Not built here.** `AFTER` (held, §5.1.2 — built 2026-09-16 by the next track, stacked on this
branch: §5.1.2's build block); §5.2's `LEST`
default (a different stack — `OF THE DEADLINE` on a `LEST` is that clock said explicitly, witness
`cure from the deadline`, and was the workaround until §5.2 landed on 2026-09-16, §5.2.1; the two
spellings now agree for every failure but a `SHANT` violation); T1's `COMMENCING`/sort
separation (§5.1.2.1) — so nothing separates a floating-origin trace from a date-serial one; a
`DATE` anchor on a trace that starts `AT 0` counted from a serial in the hundreds of thousands,
silently, until the `AFTER`/`BEFORE` track (2026-09-16) made the machine refuse a date on a clock
below `DATE_SERIAL (YMD 1 1 1)` by name, for the anchor as for the new edges (§5.1.2's build block;
the doc page says the remaining limit in one sentence); §5.1.3's expression-over-trace slot; `THE
OPENING` (declined); `SOME m OF`. Also not done: a residual re-armed on a SECOND `App1` (nothing in
`l4 run` does this) would resolve an unevaluated anchor at its second arming, not its first.

#### 5.1.2 `AFTER` and `BEFORE`: the window's two edges — MODIFIED 2026-09-07 (R-X5); the early act RULED (R-X6); the origin the absolute forms needed RULED 2026-09-09 (T1, §5.1.2.1); **`AFTER … WITHIN` RE-ANCHORS, RULED 2026-09-16 (R-X5 amended, §5.1.2.2)**; BUILT 2026-09-16

This section answers the question in R-Q7A's note ("Shall we try to sketch a design for that now?").
R-X6 is ruled and R-X5 is a design Meng modified and asked to have worked through; both are
recorded below, and both are **built** — the block at the end of this section ("BUILT 2026-09-16")
records the mechanism, the diagnostic channel R-X6 needed, the decision taken on T1's hole, and
what the build decided that no ruling had. The prose between here and there is the design as it
was ruled, with its "not built" sentences corrected in place.

**The gap.** `WITHIN d` gives a window one edge, the closing one; the opening edge is the anchor
itself, so an obligation is performable from the instant it arms. Meng's cooling-off example is the
counter-case, and it is ordinary: _the customer may place a new order after a three-business-day
cooling-off period, within 30 days_. Before this section was built nothing in the language could say
when a window **opens**; `AFTER` now does (the BUILT block below).

**We have already written this construct.** `jl4/experiments/purchase.l4` — an aspirational sketch
that has never parsed — used it throughout: a bare `BEFORE n days` (at `:97` and `:101` before the
migration of 2026-09-16; now `:97` and `:107`, reading `WITHIN 30 days` and `WITHIN 14 days`, with
a comment at `:98-103` saying why), and the full two-edged form in four nested continuations
(`:152-168` then; `:158-176` now, each `WITHIN` under an `AFTER` anchored `OF THE JOIN`; these
cites are on the round-2 tree — the round-1 fix grew the comment by a line and left its own cites
one short, R2). It is
worth reading because it disagrees with the note above on the one point that matters:

```
PARTY   seller
MAY     `water plant`
AFTER   5 days
BEFORE  8 days
```

That is a window of `[a+5, a+8]`: **two offsets from one anchor**. Meng's sentence is a window of
`[a+3, a+33]`: **an offset, then a length measured from where the offset ends**. Both readings are
attested in real drafting. Until 2026-09-07 this section proposed telling them apart by the closing
word; R-X5 replaced that, below.

**Meng's modify (R-X5, 2026-09-07), verbatim:** _"yikes. BEFORE more naturally mates with an
absolute date, and WITHIN more naturally mates with a duration. can you think about this
possibility?"_ Worked through here; it is better than the sketch it replaces, and the sketch's
re-anchoring `AFTER` is withdrawn.

**The design is type-directed, not keyword-directed.** Each edge word says which edge; the
argument's type says how the edge is computed.

| edge    | duration form          | absolute form   |
| ------- | ---------------------- | --------------- |
| opening | `AFTER d [OF anchor]`  | `AFTER <date>`  |
| closing | `WITHIN d [OF anchor]` | `BEFORE <date>` |

`WITHIN <date>` and `BEFORE <duration>` are check errors, each naming the other word. English
already draws the line here — _within 30 days_, _before 30 June_, never _within 30 June_ — and so
does the corpus: measured 2026-09-07, every `WITHIN` argument in the tree is a number or a backticked
duration, none date-shaped. `AFTER` needs no second word because _after 5 days_ and _after 1 January_
both read.

~~**`AFTER` does not re-anchor.** Both edges measure from the same anchor, so the statutory two-offset
window is the default and is written as the statute says it:~~ **STRUCK 2026-09-16 — see §5.1.2.2.**
The paragraph and the block below are kept as the record of what this section said between
2026-09-07 and 2026-09-16; the block's comment is what it USED to mean:

```
AFTER  3 OF `delivery`
WITHIN 30                          -- window [delivery+3, delivery+30]
```

The re-anchored window — Meng's cooling-off sentence, `[delivery+3, delivery+33]` — was proposed
here to use the mechanism R-Q7 built for naming anchors, with one more lifecycle position joining
R-Q7B's three, **`THE OPENING`** (the instant the window opened). **That proposal was DECLINED on
2026-09-08; see §5.1.3. The block below is the rejected spelling, kept because §5.1.3 argues from
it.**

```
AFTER  3 OF `delivery`
WITHIN 30 OF THE OPENING           -- window [delivery+3, delivery+33]
```

No arithmetic and no overloaded keyword; the two readings are told apart by an anchor, which is what
anchors are for. Mixed edges compose: `AFTER 3 OF delivery BEFORE (YMD 2026 12 31)` opens
relative and closes absolute, a real contract shape.

**What this does to earlier rulings and files.** `doc/reference/regulative/README.md`'s `BEFORE`
section (`## BEFORE (NOT YET IMPLEMENTED)` when this was written; now `## BEFORE (Absolute
Deadline)`, `:495`) promised `BEFORE` for absolute deadlines and became **true when this was built**
(2026-09-16) instead of being corrected.
`jl4/experiments/purchase.l4` migrates by one word per line — its `BEFORE n days` at `:97`, `:101`,
`:134`, `:153`, `:159`, `:164`, `:169` become `WITHIN n days` — with meaning preserved, because its
`AFTER` never re-anchored either. (Corrected 2026-09-16, when §5.1.2.2 made the bare form
re-anchor: the four lines that sit under an `AFTER` — `:153`, `:159`, `:164`, `:169` — migrated to
`WITHIN n days OF THE JOIN`, which is the two-offset window the file always meant; the three bare
ones to `WITHIN n days`; `jerseyAlcohol.l4:88`, not named here, the same way. Done with the
build.) R-Q7C stands (a date as an **anchor**, `WITHIN 5 OF closingDate`,
is still needed) but its awkward idiom for the degenerate case, `WITHIN 0 OF (YMD …)`, is no longer
the natural spelling; `BEFORE (YMD …)` is.

**Residue, now ruled:** whether `THE OPENING` is wanted, or the re-anchored form is rare enough to
write out by hand. Declined, and replaced with a direction — **§5.1.3**.

**`AFTER` alone is well-formed** — a permission that opens and never closes is an ordinary legal
object (a right that vests and does not expire).

**The `BEFORE` conflict this section carried until 2026-09-07 is closed by R-X5.** The manual's
reading (absolute date) wins; purchase.l4's reading (a duration) was `WITHIN`'s job all along, and
that file's lines migrate as above.

**The question a sketch cannot answer: what does an early act do?** Three readings, and they are not
interchangeable:

1. **Nullity.** The act does not count as performance. The obligation stays live, its clock
   untouched, and the party may act again inside the window.
2. **Breach.** Acting early violates the clause, the way acting late does.
3. **Not enabled.** The action is not offered at all — the machine has no transition for it.

For a `MAY`, (1) is the natural reading and (3) is how a wizard would render it. For a `MUST`, (1) is
harsh but is what a cooling-off period means, and (2) is what a source that says _shall not … before_
means — but a drafter with that source should be writing a `SHANT`, not an early `MUST`.

**RULED 2026-09-07 (R-X6, Meng: accept): (1), nullity, with a diagnostic.** The act does not
count as performance; the obligation stays live with its clock untouched; the party may act again
once the window opens; and the machine reports that the act fell outside the window rather than
swallowing it. A silent nullity is how a party loses a deadline it believed it had met. The card
offered "defer to the bounded-deontics discussion" as a legitimate mark and it was not taken.
**Built 2026-09-16** — the diagnostic is a `NOTE:` line beside the directive's result, through a
channel `l4 run` did not have and now does (the build block below).

**Cost, measured 2026-09-07 on this branch.** `AFTER` and `BEFORE` are **not** keywords
(`jl4-core/src/L4/Lexer.hs`; the keyword table is an exact, case-sensitive `Map.lookup` on the raw
identifier text at `identifierOrKeyword`, `Lexer.hs:670-675` on `unstable` since #360 landed).
Reserving `AFTER` touches six lines of `.l4` in the whole
tree: four are `purchase.l4`'s aspirational `AFTER n days` above, in `jl4/experiments/`, which is
**in no goldened glob** and already fails to parse for unrelated reasons; the other two are inside
backticked section names in `housing-act-ground-5F.l4:605,:726`, and a backticked name never consults
the keyword table. Zero goldened corpus files, zero canon files, zero `doc/` files — the same shape
`UPON` measured at before it was taken.

**What this sketch owed before it could be ruled — each now settled**: the early-act semantics
above (R-X6, ruled 2026-09-07, built 2026-09-16); whether `BEFORE`'s offset is checked against
`AFTER`'s at compile time (`AFTER 30 BEFORE 5` is an empty window and should be an error, not a
rule that can never fire — scoped on 2026-09-16 to the explicitly anchored `WITHIN d OF …` form,
§5.1.2.2, and built: a check error for literal offsets, a run-time note otherwise); and what the
pair means under `LEST`, where the anchor is a missed deadline rather than a performance (it falls
out of §5.2's clock with no plumbing of its own: `AFTER 3 WITHIN 30` under a `LEST` is
`[deadline+3, deadline+33]`, witnessed). What the section still owes is in the build block's
residue.

##### 5.1.2.0 BUILT 2026-09-16 — the mechanism, the diagnostic channel, and the T1 decision

Built on `every/after-before`, cut from `every/lest-anchor` `162e9382` plus the R-X5 ruling commit
`85d4b1c2` (fifteen commits over `origin/unstable` `0b640727`), so it lands AFTER `every/lest-anchor`.
Witness: `jl4/examples/ok/every/run-after.l4` (51 directives in ten sections: the cooling-off
window with `MUST` and `MAY`, the two-offset spelling and the four anchor combinations, the `LEST`
clock, `AFTER` alone, the absolute forms and their refusal on a floating trace, a barrier's
`HENCE`, barrier members, a fork and a fork bounded as a whole, a `SHANT`, the empty window a run
reveals, and the printers); refusals witnessed by
`jl4/examples/not-ok/tc/{within-a-date,before-a-duration,after-empty-window,after-wrong-order,after-date-anchored,after-not-an-instant,before-on-join-line}.l4`;
highlighting by `jl4/examples/lsp/semantic-tokens/after.l4`; the doc page
`doc/reference/regulative/AFTER.md` with `after-example.l4`. **Line numbers below are on the build
commit of this track** (subject `lang(every): the window's two edges …`), and are NOT re-cited by
later commits unless their ledger entries say so.

**Syntax.** `AFTER` and `BEFORE` are keywords (`Lexer.hs:254`, `:256`; the table
`:356`). Measured before reserving them (the survey of 2026-09-16, re-run on this HEAD): every
occurrence in a goldened glob, under `doc/`, in the libraries and in canon is inside a comment or a
backticked name; the non-comment hits are all in `jl4/experiments/` (no glob), and those in
`purchase.l4` migrated with this change (`BEFORE n days` → `WITHIN n days`, its `AFTER n days` kept
— that file still does not parse, for the reasons it never did: the lexer stops at the `+=` of
`UPDATE … +=` at `:143`, with `IF … AT` and an undefined `days` behind it; the first cut of this
sentence blamed `PERSON` and `SHOULD`, which are `jerseyAlcohol.l4`'s and occur in `purchase.l4`
only in the comment that blamed them — adversarial pass of 2026-09-16, G2). `Deonton` gains a field, `opens :: Maybe (Opening n)`, between the action and the deadline
(`Syntax.hs:429`), in source order as the exactprint zip requires; `Opening n =
MkOpening Anno (Expr n) (Maybe (Anchor n))` mirrors `Deadline` (`:602`), and `Deadline` gains a second
constructor, `MkBefore Anno (Expr n)` (`:581`), so the closing edge stays ONE hole of the parent
and `WITHIN` and `BEFORE` cannot both be written. The parser (`obligation`,
`Parser.hs:2577`) takes `opening` then `closingEdge` (`deadline <|> before`), then a guard that
fails by name when an `AFTER` follows the closing slot (`edgeOrderGuard`, `:2603`; its
look-ahead is `hidden`, so `AFTER` does not join the expected-token list of every parse error after
a `WITHIN`, which is how the two `every-join-misindented` goldens did not move). Inside the
`AFTER`'s offset, `OF` is the anchor by the same flag `WITHIN` uses (`ofIsAnchor`); inside a
`BEFORE`, which takes no anchor, `OF` is application. The join line's deadline slot takes
`closingEdge` too, so that a `BEFORE` written there is refused by the checker by name rather than
as an unexpected token; no `AFTER` is offered on a join line, as the brief required.

**Type checker.** Type-directed, as R-X5 says. `checkOpening` (`TypeCheck.hs:2216`) infers the
offset and reads it back with `checkAnchorAt`'s bias — `NUMBER` first (a duration, an anchor
allowed), then `DATE` (the instant; an anchor is refused, `AbsoluteEdgeAnchored`), else
`OpeningNotAnInstant` naming both. `checkDeadline` (`:2184`) keeps `checkExpr … number` for a
`WITHIN`, unchanged, and `checkExpr ExpectBeforeInstantContext … date` for a `BEFORE`; the
"name the other word" rule lives in the mismatch wording (`withinGotDate`, `:6978`; the
`ExpectBeforeInstantContext` arm), which appends a sentence only when the given type IS a `DATE`
(or a `NUMBER` after `BEFORE`), so every older mismatch wording holds byte for byte. The
empty-window check (`checkWindowNotEmpty`, `:2278`) fires only for two literal offsets
under a `WITHIN` that names an anchor, and only where the `AFTER` cannot open earlier than that
anchor — §5.1.2.2's scoping, made exact by the adversarial pass of 2026-09-16 (F1, R1-1): an
`AFTER` that names an anchor shares the origin when it names the SAME lifecycle noun; a bare
`AFTER` counts from the continuation's default origin (the join under `HENCE`, the failure time
under `LEST`, the arming at top level), and is compared against `OF THE ARMING` anywhere, `OF THE
JOIN` under `HENCE`, and `OF THE DEADLINE` under the `LEST` of a `MUST`/`DO`/`MAY` — never
against `OF THE DEADLINE` under `HENCE` (the join precedes the deadline: `AFTER 3 WITHIN 2 OF THE
DEADLINE` there is `[join+3, deadline+2]`, open; witness `bare after, deadline within`), never
under a `SHANT`'s `LEST` (the failure time is the violation, before the deadline; witness `cure
after violation, deadline within`), and never against `OF e` (witness `bare after, instant
within`: `[30, 205]`). The checker reads the enclosing obligation's slot and modal for this
(`EnclosingObligation.modal`, `Types.hs:523`, new), and — round 2 of the pass, R2-1 —
whether the deonton IS the continuation it is written in (`EnclosingObligation.direct`,
`Types.hs:524`): the slot and the modal are those of the obligation the deonton was
written under, and the machine binds the anchors at hand-off, dynamically (§5.1.1), so a deonton
that is an argument to a function or a `WHERE`/`LET` local may run under some other obligation's
`LEST` altogether. A literal `AFTER 3 WITHIN 2 OF THE DEADLINE` written under a `MUST`'s `LEST`
but handed into a `SHANT`'s runs as `[violation+3, deadline+2]`, open; the round-1 checker refused
it while the same program with the offsets as names ran and fulfilled at 20. Now `asValue`
(`TypeCheck.hs:952`) clears `direct` for every application's arguments and every local
declaration, and `sharesOrigin` compares the `JOIN` and `DEADLINE` cases only while it is set;
`THE ARMING` and the same-noun form are compared regardless, since they hold wherever the value
lands (witnesses `cure handed on, prohibition` — open, [14, 42] — and `cure handed on, obligation`
— the same literals handed into a `MUST`'s `LEST`, [43, 42], reported by the run). The first cut
compared a bare `AFTER` against ANY anchor and refused the three windows just named — all open —
with a wording that claimed "the AFTER counts from the same place"; the refuters found it by making
the offsets parameters, where the checker cannot look, and watching the run fulfil at 20. Two
different origins named on the two edges make no literal comparison. The anchor refusals of §5.1.1.1 apply to an `AFTER`'s anchor unchanged
(`checkAnchor` takes an `EdgeWord`, `Types.hs:449`, which only chooses the keyword in the
wording — the `WITHIN` wordings are the 2026-09-15 ones byte for byte, so the five `anchor-*`
goldens did not move). `hasDeadline` stays about the closing edge: `THE DEADLINE` under an
`AFTER`-only obligation is refused, and the machine binds none there.

**Machine.** The opening edge is resolved ONCE, at the first event, before the closing edge,
because a bare `WITHIN` beside it counts from it: `Contract4` (`Machine.hs:1634`) dispatches on the
opening — an anchored one through `Contract4oa` (the anchor, `resolveAnchor`, shared with the
deadline's), then `Contract4o` (the offset: a NUMBER added to the anchor or to the arming clock, a
DATE lowered by its serial) — and then hands the closing edge to `scrutinizeDue`
(`:2338`), which is what `Contract4` used to do on its own, with one more input: the
opening instant. `Contract5`'s `anchorT` became `origin` (`ContractFrame.hs:303`): what a duration
is added to — the anchor's instant for `WITHIN d OF …`, the opening instant for a bare `WITHIN`
beside an `AFTER` (re-anchor), the frame's clock otherwise; a `BEFORE`'s value is a DATE and is
absolute by itself (`Machine.hs:1692-1694`, the `ValDate` arm). The four combinations are witnessed: bare/bare `[13, 43]`,
bare/`OF THE JOIN` `[13, 40]`, `OF THE JOIN`/bare `[13, 43]`, `OF THE JOIN`/`OF THE JOIN`
`[13, 40]`, and two origins (`OF THE ARMING`/`OF THE JOIN`) `[3, 40]`. Under a `LEST` the
continuation's clock is already the FAILURE TIME (§5.2, §5.2.1) — the missed deadline for a
`MUST`/`DO`/`MAY`, the violating act's stamp for a `SHANT` — so `AFTER 3 WITHIN 30` there is
`[failure+3, failure+33]` with no plumbing of its own: `[deadline+3, deadline+33]` under a missed
`MUST` (witness `cure, bare`: 63 in time, 64 late), where `AFTER 3 OF THE DEADLINE WITHIN 30`
names the same instant; `[violation+3, violation+33]` under a `SHANT`, where `OF THE DEADLINE`
names the prohibition's end instead and the two windows differ (witness `cure after violation,
bare`: `[8, 38]`; `cure after violation, from the deadline`: `[33, 63]`). The first cut of this
sentence, and of the doc page, said "the missed deadline" unqualified and the page added "with or
without `OF THE DEADLINE`" — false for the `SHANT` case, which the regulative README had already
stated correctly (adversarial pass of 2026-09-16, F2). Under a barrier's `HENCE` it is
`[t_last+3, t_last+33]` (witness `barrier then window`).
After the first evaluation the value carries the opening as what is still to run until it opens
(`ValObligation`'s fourth field, `ValueLazy.hs:60`; `MaybeOpened` on every act frame,
`ContractFrame.hs:162`), `Just` while the window has not opened and `Nothing` once it has, and the
remaining due is measured from the OPENING while that is ahead (`relativeDue`,
`:2386`) — so a residual prints as the bare re-anchored window it is: `AFTER 1 WITHIN 30`
at 12 is `[13, 43]`, where the first cut printed `AFTER 1 WITHIN 31`, which under the bare reading
is `[13, 44]` — a wrong answer in the residual's own notation, caught by the first probe. `AFTER`
alone takes the `Left Nothing` shortcut with the opening still re-relativised, so `Contract10` can
see whether the window has opened. The early act (R-X6) is caught at `Contract10`
(`:1912`), the one frame at which party, action and `PROVIDED` have all matched: the note is
raised, and the event is passed over exactly as a non-matching one is — the absolute deadline is
untouched by construction (the `time + due` invariant), and the party may act again. For a
`SHANT` the same arm applies and the note says the prohibition had not started: not a violation
(witness `no smoking later`: 2 reported and ignored, 5 the violation, 2-then-40 kept). A member's
opening is threaded through `memberObligation` and `barrierMember` from the deonton, so a fork or
barrier member has its window; and a demoted join-line `WITHIN` beside a member's `AFTER` is
handed to the member anchored `OF THE ARMING` explicitly (`memberDueExpr`, `:2683`), because a
join-line deadline bounds the whole from the `EVERY`'s arming (R-T2) and must not re-anchor on the
act's opening (witness `fork bounded as a whole`: `[3, 30]`, not `[3, 33]`); without an `AFTER`
the demoted deadline is handed over as written, so no older residual prints differently.

**The diagnostic channel, which did not exist.** `l4 run`'s per-directive outputs were the value,
the trace and the ledger; nothing non-fatal reached a golden. Built: `EvalState.notes`
(`Machine.hs:279`), appended by `tellNote`, swapped fresh per directive beside the ledger
(`withFreshLedger`, `EvaluateLazy.hs:147`), read into `EvalDirectiveResult.notes`
(`:343`) and printed after the value, only when there are any — so no directive that raises none
prints a byte differently. **Which renderers carry it** (measured, adversarial pass of 2026-09-16,
G1/R1-2 — the first cut said "every renderer", and two did not): `prettyEvalDirectiveResult` as
`NOTE: …` lines (what the goldens see, and the LSP diagnostic's message); `l4 run` as a `Notes:`
section; `l4 run --json` as a `"notes"` array on the directive object (`Cli/Run.hs`,
`evalResultToJson` — added by the pass; the first cut's envelope built `{range, kind, value}` and
dropped the note, so a JSON consumer was handed exactly the silent nullity R-X6 forbids);
`l4 batch --json` through the `ToJSON EvalDirectiveResult` instance (`EvaluateLazy.hs:517`);
`L4.API`'s `"results"` objects (`API.hs:544`, added by the pass); the LSP inspector's `prettyText`
(`prettyEvalDirectiveResultWithFields`); and the REPL (`formatResult`, added by the pass).
**Not carried, and owed:** the decision service's `ResponseWithReason` (`jl4-service`,
`Backend/Api.hs`) has fields for the result, the reasoning and a graph and no place for a note; its
JSON shape is a public schema with its own tag scheme, swagger and TypeScript clients, so adding
a field there is a schema decision the pass did not take — a client of the service sees only the
residual. Recorded in the residue below and on the doc page. **A note is reported once per
directive** (`tellNote` drops an exact duplicate; F4): a `LEST` chain that re-arms the same empty
window a thousand times before the stall guard refuses it printed the note 1001 times beside the
refusal (354 KB in the `Notes:` section alone); now once (witness `stalled window`). The key is
the sentence, which names the party, the act pattern and the instants — not the obligation that
raised it, nor the event — so two obligations that render the same sentence share one note: the
two operands of a `RAND` with one party, act and window, two members of an `EVERY` roll naming one
party twice, or two events at one stamp on one obligation (round 2, R2-2; the first wording of
this sentence, "distinct facts stay distinct", was read as promising more than the key can
deliver). The reader is told the fact, not the count. Keying on the raising frame would revive
F4's thousand copies (each re-armed window is a fresh frame); keying on source position would
separate the `RAND` case alone. Whether multiplicity belongs in the note is a ruling, invited and
not taken. Twenty-one
positional pattern and construction sites across four packages (`jl4-core`, `jl4`, `jl4-lsp`,
`jl4-repl`; counted with `grep -rn MkEvalDirectiveResult`, the declaration and the record-syntax
sites excluded) took the new field; the price of "the goldens can see it", paid once. A note's party is rendered by `peekNF` (`Machine.hs:5788`), which follows references
already in WHNF and forces nothing — a party that has just been matched against an event prints
whole. Two notes exist: R-X6's early act (`earlyActNote` — "with its deadline untouched (the
window closes at N)" when there is a closing edge, "with no closing edge" for an `AFTER` alone,
which has no deadline to leave untouched; F5 — and, when the window closes before it opens, "but
its window closes at N, before it opens, so no act can be in time" in place of "may be performed
once the window is open", which a window that never opens made false; a `SHANT`'s reads "stays in
force until N, before the window opens, so nothing can violate it"; round 2, R2-4, witnesses
`cure handed on, obligation` at 41 and `window of, shant`), and the window a run finds empty
(`emptyWindowNote`, raised once at `Contract5` when both instants are first known, for offsets the
checker could not compare; witness `window of` 30 5). The empty-window note is **worded per the
shape it met** (F3, R1-3): the first cut said "both edges count from one anchor (the WITHIN names
it …) — drop the anchor from the WITHIN" for every shape, which was true only for the same-anchor
form and false for a `BEFORE` date earlier than the opening (no anchor anywhere), for two anchors
(two origins), for a bare `AFTER` beside an anchored `WITHIN` (the `AFTER` counts from the clock),
and for a demoted join-line `WITHIN`, which reaches the member anchored `OF THE ARMING` by the
machine's hand, so that "drop the anchor" told the drafter to drop an anchor they never wrote. Now
each shape gets its own sentence (witnesses `window of, arming`, `window of, two anchors`, `window
before`, `fork bounded, empty`). Round 2 (R2-3) found the shape the per-shape wording had missed:
an `AFTER` DATE beside an anchored `WITHIN`, which the frames carry only as a lowered instant and
whose `(YMD …)` is an application, not a literal, so the source node cannot tell it from an offset
— it was described as "both edges count from THE ARMING". `CheckTiming` and `ScrutinizeAnchor` now
carry `openAbsolute` (`ContractFrame.hs:254`, `:320`), set by `Contract4o` where the `ValDate` is
lowered, and the note's first anchored arm says the date is later than where the `WITHIN` closes
(witness `window from june`). The residual of an empty `BEFORE` window prints as `AFTER n WITHIN
-m` — a `BEFORE`'s residual is a remaining `WITHIN`, decision 9 of the build — which is legible if
odd, and is left.

**The T1 decision (the brief's item 4): (a), a run-time refusal, with the heuristic stated.**
`AFTER date` and `BEFORE date` are parsed and lower through the date's serial (the same arithmetic
as `DATE_SERIAL`, `lowerInstant`, `Machine.hs:5645`). What the machine can see at that
point is the obligation's arming instant, and what it checks is whether a calendar date could
have that serial at all: an arming below `DATE_SERIAL (YMD 1 1 1)` (365; `earliestDateSerial`,
computed, not a literal) is not on the date-serial scale, and the date is refused by name — the
edge, the date, the clock's reading, and what to do instead (witnesses `by june` and `from june`
`AT 0`). That catches every `AT 0` trace in the corpus and lets every `AT (DATE_SERIAL …)` trace
through; a floating trace that starts at 365 or above is not caught, and the doc page says so in
one sentence. (b) — parse and refuse always, naming T1 — was rejected because it would have
left `WITHIN 0 OF (YMD …)` silently running on the same floating trace while the one-word spelling
of the same deadline refused; (c) — not parsing the absolute forms — because R-X5's table is
type-directed and the absolute column is half of it. **A deviation the reviewer may reverse:** the
same refusal now guards the pre-existing anchor form, `WITHIN d OF date` (the code path is one
function), because the survey had probed it silently `FULFILLED` on an `AT 0` trace (§5.1.2.1's
point 2, the anchor half) and the doc page would otherwise have had to explain why the one-word
form refuses where the two-word form does not. No golden moved: every `DATE` anchor in the
corpus runs on a date-serial trace (measured before the change, confirmed by the suite). What T1
still owes is unchanged: a contract-level `COMMENCING` in both forms, and date/duration/instant as
distinct sorts, so that the check is a type and not a heuristic on the clock's reading.

**Printers.** The keyword moved from the caller into the node — `closingClause`/`openingClause`,
`Print.hs:940` — because the closing edge has two keywords now; `prettyObligation` takes the
window already rendered, and `residualWindow` (`:962`) prints a run-time residual's
`AFTER n` only while the window has still to open. Exactprint is byte-identical (the two new
nodes' keywords live in their own `Anno`s; the `.ep.golden`s of the witnesses equal their
sources), `prettyLayout` round-trips the whole corpus with the witness included and no exclusion
list, NLG says `after 3 within 30 of that` for the bare window (`Nlg.hs:252`), the document
export folds the window into one phrase with its own prepositions (`Document.hs:1120`; `CDeontic`'s
deadline slot now carries "within 30" rather than "30", and the three renderers stopped prefixing
"within" — no test or golden reads that slot), the state graph carries the opening as its own label
field and a `BEFORE` with its keyword (`StateGraph.hs:684`; the record pattern named the new
field rather than ignoring it), the BPMN lowering reports the opening edge as not drawn
(`P-WINDOW-OPENING`, blocking, `Bpmn/Lower.hs:1751`) and carries a `BEFORE` verbatim as a
condition through the existing unparsed-deadline path (its boundary `<documentation>` reads "not
discharged BEFORE …" — the first cut wrote "not discharged within BEFORE …", the label's keyword
under the caller's preposition; G8), the MLIR schema fails closed on any
opening (`Schema.hs:931`), the LSP highlights the two keywords through the derived
instances, and the service serialises an unevaluated opening as its source text and adds an
`opens` key to the `OBLIGATION` object only while there is one to reach.

**Existing goldens.** None moved in the build: no eval, exactprint, NLG, schema, parse-error or
semantic-token golden of a pre-existing file changed (run 1 of the suite failed on exactly the 33
goldens it created — four for the witness, four each for seven `not-ok/tc` witnesses, one for the
LSP fixture; run 2 on the extended witness was 4 created; run 3 green). The two things that would
have moved goldens were avoided deliberately: `AFTER` joining the expected-token list after a
`WITHIN` (the `hidden` look-ahead above), and a `WITHIN` mismatch wording that changed for the
non-`DATE` case (the sentence is appended only for a `DATE`). The adversarial pass moved ONE
pre-existing golden on purpose: `not-ok/tc/tests/anchor-no-deadline.golden` (from the anchors
track, 2026-09-15), whose message said the enclosing obligation "has no WITHIN" and advised "give
it a WITHIN" — a `BEFORE` now supplies the deadline too, so the message names both (G9). A
re-bless, not a regression: the refusal and its range are unchanged.

**Residue, owed by this section.** Backward windows from a future event ("not less than 10 days
before the meeting" — the corpus's common two-offset case, §5.1.2.2's measurement) are not
expressible: both edges count forward from an anchor. T1's `COMMENCING` and sorts, above. A
join-line `AFTER`. `THE OPENING` stays declined. The noun `JOIN` (§5.1.2.2, footnote 1) stays
open. **The decision service does not carry the R-X6 note** (the channel paragraph above): a
schema decision for `jl4-service`'s `ResponseWithReason`, owed. **A negative `AFTER` offset is
accepted** (F6): `AFTER -3 WITHIN 30` under a `HENCE` with the join at 10 is `[7, 37]`, the window
opening before the obligation exists — coherent arithmetic, contrary to no ruling, and the closing
edge's negative `WITHIN` is accepted the same way; refusing a literal negative offset at check time
would be a new rule of the language with no ruling behind it, so the pass documented it on the doc
page instead of refusing it, and a ruling is invited. **Two literal `DATE`s in reverse order**
(`AFTER (YMD 2026 6 20) BEFORE (YMD 2026 6 10)`) are not a check error, only the run-time note:
the check is scoped to the anchored `WITHIN` form (§5.1.2.2), and reading a `YMD` application as
a literal is more than a `Lit` pattern; recorded, not filed.

**What the adversarial pass of 2026-09-16 changed** (round 1: 20 findings raised by three
refuters, each checked by two independent checkers; none refuted by both; every one applied —
the verdicts are in the scratch `FINDINGS-round1.md`). In past tense, one line each:

- F1 / R1-1 (blocker): `checkWindowNotEmpty` compared a bare `AFTER` against ANY closing anchor and
  refused three open windows (`WITHIN d2 OF THE DEADLINE` under `HENCE`; under a `SHANT`'s `LEST`;
  `WITHIN d2 OF e`). Scoped to the anchors the clock cannot precede, reading the enclosing slot and
  modal (and, after round 2's R2-1, only for a deonton that is the continuation itself); the
  `EmptyWindow` wording no longer claims "the same place"; three `ok` witnesses and
  `not-ok/tc/after-empty-window-lest.l4` (the `MUST`-`LEST` case, still refused) added.
- F2 (major): the doc page and this block said the `LEST` clock is "the missed deadline" and the
  page added "with or without `OF THE DEADLINE`"; corrected to the failure time, with the `SHANT`
  divergence stated and witnessed (`cure after violation, *`).
- F3 / R1-3 (minor): `emptyWindowNote` claimed a shared `WITHIN` anchor for every shape; worded
  per shape, four witnesses added.
- F4 (minor): the notes channel had no dedupe; a note is now reported once per directive
  (witness `stalled window`: one note beside the stall refusal, not 1001).
- F5 (minor): `earlyActNote` said "with its deadline untouched" for an `AFTER` alone; now "with no
  closing edge" there (witness `vests` at 12; the skill's paragraph reworded).
- F6 (minor): a negative `AFTER` offset is accepted silently; documented on the doc page and in the
  residue above, not refused — no ruling.
- G1 / R1-2 (major): `l4 run --json`, `L4.API` and the REPL dropped the note; each now carries
  it; the "every renderer" sentence replaced by the measured list, the service named as not
  carrying it and owed.
- G2 (major): this block and `purchase.l4:101` blamed `PERSON`/`SHOULD` for `purchase.l4` not
  parsing; both are `jerseyAlcohol.l4`'s. Corrected to the `+=` at `:142` (`:143` after round 1's
  own edit grew the comment above it; re-cited in round 2).
- G3 (minor): the doc page quoted export strings the binary does not produce ("before 30 June";
  a comma in NLG); the actual strings quoted, with the `Date` constructor noted.
- G4 (minor): §2.4's cites for `deadline`, `anchor` and `checkAnchor` were stale (the last never
  true on this lineage); re-cited on this HEAD.
- G5 (minor): the doc page's quoted `NOTE` dropped the trailing citation; now verbatim, one line.
- G6 (minor): the scratch build notes miscounted the NLG golden (45 for 47); corrected there.
- G7 (minor): `GLOSSARY.md` and `reference/README.md` omitted `AFTER`/`BEFORE`; rows added.
- G8 (minor): BPMN boundary `<documentation>` read "within BEFORE …"; the preposition is dropped
  when the label carries its keyword.
- G9 (minor): the `THE DEADLINE` refusal said "has no WITHIN"; now names `WITHIN` or `BEFORE`
  (one pre-existing golden re-blessed, above).
- R1-4 (minor): "Nothing in the language today can say when a window opens" was present tense
  and false; rewritten. The `purchase.l4` line cites in the same paragraph updated. the `BEFORE` arm's cite
  (`Machine.hs:1676` then) widened to the case head and its arm; `Nlg.hs:252` was checked and is correct (both checkers refuted that
  half).
- R1-5 (minor): a second closing edge (`WITHIN 30 BEFORE date`) failed with megaparsec's token
  list; `edgeOrderGuard` now names the one-closing-edge rule (witness
  `not-ok/tc/after-two-closers.l4`), with the look-ahead `hidden` as before.
- Raised and refuted: none by both checkers. Refuted in part: R1-4's `Nlg.hs:252` (a definition
  line, not a comment); G4's attribution of the `checkAnchor` cite to this commit (it was stale
  when inherited); F6's proposed equivalence "`AFTER -3 WITHIN 30` = `AFTER 0`" (it is `AFTER 0
WITHIN 27`).

**Round 2 of the same pass** (8 findings — four on the round-1 fix as landed, four fresh — each
checked by two independent checkers; none refuted by both; all eight applied; the verdicts are in
the scratch `FINDINGS-round2.md`). In past tense, one line each:

- R2-1 (major): `checkWindowNotEmpty` scoped the `JOIN`/`DEADLINE` comparisons by the slot a
  deonton was WRITTEN in, and refused a literal window written under a `MUST`'s `LEST` but handed
  as an argument into a `SHANT`'s, which the machine runs open ([14, 42]); `EnclosingObligation`
  gained `direct`, cleared by `asValue` for application arguments and local declarations, and the
  two lifecycle-noun comparisons require it (`THE ARMING` and the same-noun form do not). Two
  `ok` witnesses (`cure handed on, *`); the doc page and this block say the scoping.
- R2-2 (major as raised; refuted on its verdict by one checker, confirmed as minor by the other):
  `tellNote`'s exact-text key collapses two obligations that render one sentence into one note,
  and the sentence "distinct facts stay distinct, since a note names its party, act and instants"
  promised otherwise. The key is unchanged — a frame key revives F4, a source-position key
  separates one case of three — and the claim was narrowed in `Machine.hs`, here, and on the doc
  page (`AFTER.md`, the "once per directive" sentence). Multiplicity in the note is a ruling,
  invited above.
- R2-3 (major): `emptyWindowNote` described an `AFTER` DATE beside an anchored `WITHIN` as an
  offset "counting from THE ARMING / THE JOIN / the obligation's own clock"; the lowered opening's
  shape (`openAbsolute`) now reaches the note from `Contract4o`, and a first arm says the date is
  later than where the `WITHIN` closes. Witness `window from june`.
- R2-4 (minor): on an empty window the early-act note still ended "may be performed once the
  window is open"; `earlyActNote` now says the window closes before it opens (and, for a `SHANT`,
  that nothing can violate it). The two blessed blocks in `run-after.golden` re-blessed and read;
  witnesses `cure handed on, obligation` at 41 and `window of, shant`.
- R2 cite (minor): the `purchase.l4` line cites round 1 wrote were one short — round 1's own edit
  to that file grew its comment by a line (`:107`, `:98-103`, `:158-176`, the `+=` at `:143`,
  `purchase.l4:102`'s self-cite too), and the pre-migration `:102` disagreed with `:101` three
  paragraphs down; re-resolved on this tree.
- R2 LEST scope (minor): the doc page (`AFTER.md`) and `EVERY.md` said the check fires under a
  `MUST`'s `LEST`; it fires under any `LEST` but a `SHANT`'s (`MUST`, `DO`, `MAY`). Both sentences,
  the §11.0.1 ledger copy, and the `TypeCheck.hs` haddock (which said `MUST`/`MAY`) corrected.
- R2 residual (minor): `AFTER.md` said the residual prints as a plain `WITHIN` "once the window has
  opened"; it prints as written until the obligation has looked at an event, so a negative or zero
  `AFTER` shows its `AFTER` at arming. The sentence now says when the residual is re-measured.
- R2 README cite (minor): this section's "What this does to earlier rulings" still cited
  `README.md:104` (now `### Examples`) and said `BEFORE` "becomes true when built" under a header
  that says BUILT; rewritten in the past tense with the section's present heading.
- Raised and refuted: none by both checkers. Refuted in part: R2-2's verdict (one checker; the
  observation stood with both).

##### 5.1.2.1 The absolute forms need an origin, and now have one — RULED 2026-09-09 (T1)

**The mark.** Bench card `T1`, collection `time-rulings`, artifact "Contract Time Model". Meng's
words: _"I prefer a and b."_ Recorded as **b**, because b's text is "**Also** make date, duration and
instant distinct sorts" — it contains a's epoch rather than competing with it. So the ruling is:
**declare the epoch, and separate the sorts.** Meng added a requirement neither option stated: the
commencement must come in **both** forms — a fixed date pinned to a YMD, and a floating "whenever the
contract begins" that starts the clock at day zero and expresses everything relative to it.

**Why this section owns it.** The table above gives each edge an absolute form, `AFTER <date>` and
`BEFORE <date>`, and those put a calendar quantity onto an axis whose zero point is per-contract and
nowhere declared. T1 was raised as blocking them. It no longer does.

**Meng's question, and the measurement that answers it.** _"doesn't a trace contain an initial time
(often stated as 0) which we could use for this purpose?"_ **Yes — and more than the bench card
allowed.** `#TRACE`'s start slot is an arbitrary expression, not a literal (`Contract Anno (Expr n)
(Expr n) [Expr n]`, `Syntax.hs:197`), so **both of Meng's forms already run today.** Probed
2026-09-09 against a binary built from this tree:

```l4
`pay within 14` MEANS PARTY Buyer MUST Pay WITHIN 14 HENCE FULFILLED LEST BREACH

#TRACE `pay within 14` AT 0                             WITH PARTY Buyer DOES Pay AT 3
                                                        -- FULFILLED   (floating: ticks from day zero)
#TRACE `pay within 14` AT (DATE_SERIAL (YMD 2026 6 30)) WITH PARTY Buyer DOES Pay AT (DATE_SERIAL (YMD 2026 7 5))
                                                        -- FULFILLED   (fixed: 5 days into a 14-day window)
#TRACE `pay within 14` AT (DATE_SERIAL (YMD 2026 6 30)) WITH PARTY Buyer DOES Pay AT (DATE_SERIAL (YMD 2026 7 20))
                                                        -- BREACH      (fixed: 20 days, window closed)
```

The calendar case works for the right reason: origin and stamps sit on one scale, so `WITHIN 14`
means fourteen **days**.

**So what is actually missing is narrower than "there is no origin", and it is exactly what a and b
name.**

1. **Nothing declares the origin at the CONTRACT level.** It lives in each `#TRACE`, so two traces of
   one contract can silently disagree about when it began, and an `@export`ed decision function or a
   bare `#EVAL` — neither of which has a trace — has no origin at all. That, and not the trace, is
   what blocks an absolute edge: `BEFORE 2026-06-30` has to mean something where no trace exists.
2. **Nothing checks that the scales agree.** Probed on the same binary:

   ```l4
   #TRACE `pay within 14` AT (DATE_SERIAL (YMD 2026 6 30)) WITH PARTY Buyer DOES Pay AT 3
   ```

   **checks clean — zero errors, zero warnings — and returns FULFILLED.** The act is 740,158 days
   _before_ the contract commenced and it discharges a fourteen-day duty. The reverse mixing (origin
   `0`, act stamped with a real date) returns `BREACH`, a right-looking verdict for the wrong reason.
   Both sides are `NUMBER` and nothing separates them. **That silent, verdict-changing failure is the
   whole case for the type separation in b**, and it is affordable now precisely because no corpus
   file writes a date-shaped stamp today.

**A consequence of wanting both forms that neither option stated, and that the build must handle.**
The fixed form lets an absolute edge lower statically — `DATE_SERIAL(d) − DATE_SERIAL(commencement)`
is computable at check time when the commencement is a literal date. **The floating form cannot**:
its origin is not known until the trace supplies it, so `BEFORE 2026-06-30` under a floating
commencement has to defer to run time. Option a's text ("absolute edges lower to
`DATE_SERIAL(d) − DATE_SERIAL(commencement)`") is a compile-time story that is only true of the fixed
form. R-X5's lowering is therefore **two mechanisms, not one**, and a design that assumes the
compile-time one will be surprised by the floating case.

**Not built** (T1 itself): no `COMMENCING` keyword exists and the sorts are not separated; those
are the two things to build, named here, and they stay named. R-X5 no longer waits for them: it
was built on 2026-09-16 (§5.1.2's build block), with a run-time refusal standing in for the
type — a date is refused on a clock that no calendar date has a serial for — until T1 is.

##### 5.1.2.2 `AFTER d1 WITHIN d2` re-anchors — RULED 2026-09-16 (Meng; R-X5 amended)

**The ruling, in Meng's words (2026-09-16, in session):** _"Ok let's rule in favour of re-anchor.
Two-offset explicitly `WITHIN … OF THE JOIN`."_ So:

- **Bare `AFTER d1 WITHIN d2` is the re-anchored window, `[a+d1, a+d1+d2]`**: the `WITHIN` counts
  from the instant the `AFTER` edge is reached, not from the anchor both edges would otherwise
  share. On the worked trace (delivery at 10, `AFTER 3 WITHIN 30`): opens 13, closes **43**.
- **The two-offset window is written with an explicit anchor on the closing edge**:
  `AFTER 3 WITHIN 30 OF THE JOIN` — `[a+3, a+30]`, opens 13, closes 40. `OF THE JOIN` is R-Q7B's
  spelling (§5.1.1), built on `every/anchors` (2026-09-15).
- **The sentence "`AFTER` does not re-anchor" above is struck.** It was never a ruling. The
  2026-09-07 morning sketch (`734b8015`) read `AFTER d OF a` as _re-anchoring_ — "it moves the
  reference time to `a + d`, and everything downstream measures from the moved anchor" — and spelled
  the two-offset window with `BEFORE`. Meng's R-X5 mark that afternoon reassigned `BEFORE` to
  absolute dates, which removed the second duration word that told the two readings apart; the spec
  then picked two-offset as the bare meaning with one sentence of reasoning and pushed the
  re-anchored reading onto a fourth noun, `THE OPENING`, which W3 declined on measurement
  (§5.1.3). The re-anchored default was thus lost as a side-effect, twice removed from any mark.
- **What stands unchanged:** the type-directed table above (`AFTER d` / `AFTER <date>`, `WITHIN d` /
  `BEFORE <date>`); R-X6 (an early act is a nullity, with a diagnostic); T1 (§5.1.2.1); W3 —
  `THE OPENING` stays declined and is now unnecessary under either reading; §2.4's grammar, which
  is unchanged (the comment on its `'AFTER'` line is corrected in this change).
- **What changes downstream:** the empty-window check this section owed ("`AFTER 30 BEFORE 5` is an
  empty window and should be an error") now applies only to the explicitly anchored form — bare
  `AFTER 30 WITHIN 5` is `[a+30, a+35]` and can never be empty. `doc/reference/regulative/README.md`
  and the `AFTER` page (`doc/reference/regulative/AFTER.md`, written with the build on 2026-09-16)
  teach the re-anchored reading first.

**What decided it — three measurements, none of them the L4 corpus.**

1. **History**, above: the re-anchored reading was the original and was dropped by accident.
2. **Formalisms.** CSL, the contract calculus whose residuation rules this evaluator follows,
   re-anchors: `after e1 within e2 ⇓τ (τ+n1, τ+n1+n2)` (Hvitved 2012, Fig. 2.6). A BPMN boundary
   timer starts when the token reaches the task, so the re-anchored shape is what a process
   modeller draws by default. MTL, TPTL and timed automata measure both edges from one clock — but
   nobody drafts in them.
3. **The wild text.** A 7.66-million-phrase extraction over the drafting-register subsets of the
   Pile of Law (legislation: uscode, cfr, state*code, eurlex, us_bills, federal_register, frcp, fre,
   constitutions; contracts: atticus_contracts, edgar, resource_contracts, cfpb_cc, tos), a
   stratified sample of 3,040 phrases classified by agents and blind-audited (20 of 80 per stratum),
   population estimates with Wilson intervals, recorded in
   `specs/todo/EVERY-EACH-WINDOW-CORPUS-EVIDENCE-2026-09-16.md` beside this file. Re-anchored
   windows edge out two-offset windows in both registers — contracts ≈ 89 k two-offset against
   ≈ 137 k re-anchored (0.65 : 1), legislation ≈ 30 k against ≈ 37 k (0.80 : 1); the direct
   measurement, phrases carrying both an opening and a closing edge, is 0 : 4 in legislation and
   1 : 3 in contracts. Both shapes together are 1–3 % of deadline phrases; the single closing edge
   is 97 %. **The decisive finding is qualitative: English never writes two bare offsets.** The
   two-offset shape is always *"not less than X nor more than Y before/after E"_ — paired
   comparators, and in contracts mostly \_backward_ from a future event — and the re-anchored shape
   is always _"within d2 after the end of the ⟨named⟩ period"_. Neither wild form is
   `AFTER d1 WITHIN d2`, so isomorphism cannot pick the bare reading; the cost argument does: under
   re-anchor the other shape needs an anchor that exists (`OF THE JOIN`); under two-offset it needs a
   noun that was declined or arithmetic on lifecycle values that is not built (§5.1.3 bench, B1).

**Footnote 1 — misgivings about the word `JOIN`, recorded at Meng's request.** Meng, 2026-09-16:
_"I have been racking my brains to find a better phrasing. 'Of the event'? 'Of the trigger'? Let's
go with 'OF THE JOIN' for now but footnote this as misgivings."_ `JOIN` is a term of art from the
barrier's mechanics (the point at which `ONCE ALL HAVE` fires); for a single-party obligation it
names the completing event, and for the drafter of a cooling-off clause it names nothing they
would say. The two alternatives weighed — `OF THE EVENT`, `OF THE TRIGGER` — are closer to a
drafter's vocabulary but each collides with something: `EVENT` is what a trace is made of and would
invite _which_ event; `TRIGGER` reads as the arming, which is a different anchor (`THE ARMING`).
The spelling is R-Q7B's (§5.1.1, ruled 2026-09-07, built 2026-09-15); changing it later is a rename of
one spelling-matched noun, not a grammar change, so the cost of deferring is low. **Open.**

**Footnote 2 — why the word matters.** Guzdial, _"Dijkstra Was Wrong About 'Radical Novelty':
Metaphors in CS Education"_, BLOG@CACM, 30 November 2020
(<https://cacm.acm.org/blogcacm/dijkstra-was-wrong-about-radical-novelty-metaphors-in-cs-education/>):
Dijkstra's _On the Cruelty of Really Teaching Computing Science_ (EWD 1036, 1988) held that computing
is a "radical novelty" to be learned without metaphor; the learning-sciences record since says the
opposite — _"I'm not aware of any evidence of anyone teaching or learning CS without metaphor."_
The anchor noun is the drafter's metaphor for a time point they already have a word for in their
own practice; a machine term in that slot asks them to learn ours. That is the reason the misgiving
above is recorded rather than waved off.

#### 5.1.3 `THE OPENING` declined; the anchor slot becomes an expression over the trace. RULED 2026-09-08 (W3)

**The mark.** Bench card `W3`, collection `wave-rulings`, marked `a` — _decline on measurement_ —
2026-09-07T22:37Z.

**The measurement it was declined on**, taken 2026-09-08 against `unstable` `6e9b57bb`:

| count | what                                                                  |
| ----- | --------------------------------------------------------------------- |
| 3     | lifecycle anchors ruled by R-Q7B                                      |
| 0     | corpus rules encoding a re-anchored window                            |
| 2     | corpus files mentioning cooling-off — both source text, not encodings |
| 2     | existing `WITHIN … OF` uses, both date arithmetic                     |

So §5.1.2's `WITHIN 30 OF THE OPENING` is **not** the ruled spelling, and the re-anchored window has
no spelling today. Write it out by hand until an encoding needs one. Same shape as the M3 decline:
the anchors cost no keywords, so the objection was never lexical — a fourth anchor names a moment
the other three do not, and would need its own answer for a window that never opens.

**The note replaced the question rather than answering it.** Meng's mark carried this, verbatim:

> "Suggest we facilitate event resolution relative to the trace, allowing arbitrary date/time
> expressions both absolute and relative to trace events and to other join/fork/etc time points in
> the deontics. This generalizes expressiveness. Please consult the CSP and LTS literature generally
> to see if there is anything we can borrow. We may have an agent persona defined which has the
> right priming and can assist with this."

**The direction, as this spec reads it: stop enumerating named anchors.** The anchor slot becomes an
**expression over time points in the trace** — absolute dates, trace events, and the lifecycle points
of _other_ rules. R-Q7B's three named anchors and R-Q7C's date-valued expression both become special
cases of one slot rather than two mechanisms sitting beside each other.

That subsumes three things this document has been carrying separately:

- **R-Q7A's held `AFTER`** — held, not rejected, for a window's opening edge (§5.1.1).
- **The open item "an anchor picked by an EXPRESSION rather than named"**, whose objection was that
  `THE` invites an indefinite sibling. Under a general slot the definite article stops carrying the
  grammar.
- **`THE OPENING` itself**, which needs no keyword once the opening edge is a time point the trace
  already knows.

**What is ruled here is the direction. None of it is ruled in detail, and one thing is now harder.**
The question that killed the simple `THE OPENING` — what a reference means when the referenced event
never occurs — does not go away under a general scheme; it gets worse, because an arbitrary
expression can name an event that no execution reaches, and the answer has to hold for every such
expression rather than for one keyword. Re-entrancy is the second: when a rule fires more than once,
_which_ occurrence does a reference to its join denote?

**Prior art commissioned 2026-09-08**, per the note's last two sentences: CSP and timed CSP, labelled
transition systems and their timed variants, timed automata (clocks, resets, guards), event
structures and causal models, MTL and TPTL — the freeze quantifier in particular — Allen's interval
algebra, and timed process calculi. This section carries the findings before anything is spelled.

### 5.2 LEST Reference Time

**RULED 2026-09-07 (R-Q7 for the anchor, R-Q5 for the failure time; §2.5) — and recorded as a
CHANGE from what the tree does.** When `LEST` fires, an unanchored continuation deadline is relative
to the **failure time**, which R-Q5 fixes by layer and then by modal (§3.4):

- state layer: `t_ref` = the state's deadline (the `WITHIN` on the `ONCE` line, R-T2);
- act layer, `MUST`/`DO`/`MAY`: `t_ref` = the act's deadline;
- act layer, `SHANT`: `t_ref` = the violating event's stamp.

The text of this section before 2026-09-07 — "deadline failure: `t_ref = deadline`; early failure:
`t_ref = detection_time`" — assumed an early-failure event the tree does not have (R-Q5); the
`SHANT` line above is what "early failure" turns out to mean.

**What the machine did before this was built, and why it was a change.** Until 2026-09-16 the
machine anchored a `LEST` continuation at the stamp of the event that **revealed** the miss, not
at the deadline. The comment at `Machine.hs:1550-1552` (on `unstable` `5dc0ca19`; `:1633-1637` on
`every/anchors-on-blame` `6a8295bf`, the commit this was built on) said so in terms — "the
continuation's clock is anchored at the revealing event's stamp (the README is silent on the
anchor; this is the historical behavior)" — and `reofferResolve` implemented it, carrying the
revealing event's `ev'timeR` into the continuation's frame. The refuters' probe: `PARTY P MUST sign
WITHIN 10 LEST PARTY Q MUST release WITHIN 5`, the miss revealed by an event at 14, reported Q's
deadline as 19 (14 + 5), not 15 (10 + 5); a release at 18 came back `FULFILLED`. Under that rule
the defaulting party controlled when its own cure period started — a maker who misses the date and
then stays silent had no return-of-funds deadline until someone else acted — which is why the
deadline anchor was chosen over the status quo (listed on the bench as its own option so that
choosing this was visibly a decision). The anchor is a timestamp computed when the miss is
revealed; firing still waits for an event, so no timer is needed.

#### 5.2.1 BUILT 2026-09-16 — one anchor mechanism, the state-layer stream, and what moved

Built on `every/lest-anchor`, cut from `every/anchors-on-blame` at `6a8295bf` (nine commits over
`origin/unstable` `0b640727`), so it lands AFTER that branch. Witness:
`jl4/examples/ok/every/run-lest.l4` (47 directives, twelve sections: the spec's own probe with its
anchored twin, silence, the barrier unanchored beside `run-stack.l4`'s anchored form, the fork,
`SHANT`, the state layer, `MAY` and `DO`, a chain, a `LEST` that names itself, `THE ARMING` under
`LEST` and `HENCE`, a layer whose deadline does not advance, and the chain that cannot end; 33 in
nine sections on the build commit, 39 in ten after round 1). Line numbers below
are on the round-1 fix commit of the adversarial pass (subject `lang(every): apply round 1 of the
LEST pass …`, the commit after `546965be`, which moved `Machine.hs` by up to 31 lines and
`ContractFrame.hs` by 2); the cites of the two earlier commits were re-pinned there, and they are
NOT re-cited by later commits, which say so in their own ledger entries (round 2 moved `Machine.hs`
by one line up from `:551` and by up to 36 down from `:566` — the new bound and refusal after
`isReoffered`, and the rewritten NOTE — and `ContractFrame.hs` by 12 from `:168`; its cites are in
the round-2 paragraphs and entry below, on the round-2 fix commit `a6b077d1`).

**The mechanism: one place, one reference.** `Contract5`'s expiry branch already computed the
absolute deadline (`Machine.hs:1612`) and allocated it as `deadlineR` for `THE DEADLINE` (`:1718`).
The change is that under `LEST` the continuation's CLOCK is that same reference: `clockAt`
(`:1723`) picks `deadlineR` for a `LEST` hand-off and the revealing event's stamp for a `HENCE`
hand-off, on both the re-offer branch and the consume branch (`:1733`, `:1742`; one branch since
round 2, `:1760-1780` on the round-2 commit), and `ResolveParty`
carries it to `continueWithFollowup` as the `time` the continuation is applied to (`:1851`;
`ResolvePartyFrame.time`, `ContractFrame.hs:591`). So `WITHIN d` and `WITHIN d OF THE DEADLINE`
under a `LEST` read one reference and cannot drift apart (item 4 of the build brief: they coincide
by construction, and the `Lifecycle` haddock says so, `ContractFrame.hs:617`). Nothing else
chooses a clock:

- A **barrier member** is an ordinary `ValObligation` whose `LEST` slot holds the failpoint
  sentinel, so its expiry goes through the same branch and hands the sentinel `deadlineR` as its
  anchor — its first argument — and, as its fourth, the very same reference (`continueWithFollowup`
  `:2242`; `sentinelArgs` `:2571`, whose haddock records that the two are one reference on purpose).
  `Barrier5` forces it as `failAt` (`:1979`), `earliestFailure` orders by it (`:2731`), and
  `barrierFail` (`:2825`) hands it on unchanged: the barrier's `LEST` counts from the
  earliest-failing member's deadline with **no code change in the barrier at all** — which is the
  "one mechanism" the old `barrierFail` haddock asked for. `THE DEADLINE` under a barrier's `LEST`
  and the unanchored default now agree (witness `staggered` vs `staggered, anchored`: 10 and 10).
- The **fork** carries the drafter's `LEST` on each member, so each member's reparation counts from
  that member's own deadline (witness `each signs or refund`: refunds due 10 and 19).
- **`SHANT`** was already R-Q5's failure time: `Contract10`'s `DMustNot` arm (`:1808`) hands the
  violating event's stamp as the clock, and the violating event is consumed, not re-offered.
  Untouched, and now the one failure where the plain `WITHIN` and `OF THE DEADLINE` differ
  (witness `no smoking`: due 8; `no smoking, anchored`: due 19).
- A **`MAY`** lapse routes to `LEST` (`:1749`) and counts from the deadline as a `MUST` does; a
  **`DO`** is a `MUST` here. Both witnessed (§7 of the witness).

**Ordering keys after the change.** `earliestFailure`'s primary key IS R-Q5's failure time for
every modal now, so for `MUST`/`DO`/`MAY` the stack's third key (`failDue`, `Barrier5b` `:1994`)
can no longer separate anything the first two tied — two such members with one anchor have one
deadline and are revealed by one event. It is kept, and its haddocks say it is redundant
(`barrierFinish` `:2677`, `BarrierFailedAt` `ContractFrame.hs:448`), rather than half-removed;
removing it is a larger diff than this change and touches the stack's witnesses. Which member a
barrier anchors at does not change: the revealing stamp was monotone in the deadline, and the
`run-stack.l4` tie cases (§3, §3b) give the same numbers — decided now on the first key, which the
witness's comments say. `run-stack.golden` is identical up to the source line ranges those
comment edits shifted (checked with the ranges normalised).

**The termination argument, re-read — and rewritten by the adversarial pass.** The build commit
kept the old rule that each real event is re-offered AT MOST ONCE, marked by store address, and
consumed when it revealed a second expiry, and called the second expiry "the intended semantics,
not a corner". That was wrong as semantics, and round 1 (R1-1, a blocker found twice) showed why:
with the clock at the deadline, one event can be past SEVERAL `LEST` windows at once — a chain of
three chances due at 3, 6 and 106 and a signature at 100 — and consuming the event at the second
layer drops it before it reaches the third, the one it was timely for. The verdict then depended on
how many events the trace carried (three chances due at 3, 6 and 9: `WAIT UNTIL 100` alone left
a residual, the same `WAIT` followed by a signature at 101 breached — one instant past every window,
two verdicts), and a residual reached that way printed its full `WITHIN` with a deadline already in
the past (R1-3). The round-1 rule marked a re-offered copy with the absolute deadline whose
expiry minted it and re-offered it again **only while the deadline strictly advanced**, consuming
it otherwise (a non-positive `WITHIN`, or an anchor that did not move) on the argument that this
was the one case in which unconditional re-offering would loop. Round 2 (R2-1, a blocker found
twice again) showed that argument was too wide: a chain of DISTINCT layers is finite by its syntax
whatever its deadlines do, and consuming the copy at a layer whose deadline had not advanced — a
`WITHIN 5 OF THE ARMING` under a `WITHIN 10`, or a `WITHIN 0` — dropped it before the next layer,
whose window was still open at the copy's stamp: a refund at 12 under layers due 10, 5, 15 left
the third layer as an untouched residual alone and gave `FULFILLED` after a `WAIT` at 11, the
round-1 signature exactly. **The rule since the round-2 fix commit: a re-offered copy is always
handed on to the next layer, whatever that layer's deadline.** The mark it carries
(`Reoffered`, `ContractFrame.hs:168-176`: `highWater`, the latest deadline the copy has revealed
the expiry of, and `stalled`, the hand-offs in a row that failed to pass it; `reofferedEvents`
is a `Map Address Reoffered`, `ev'reoffered :: Maybe Reoffered` through the five scrutiny frames)
no longer withholds the event from anything; it exists only so that the one chain the walk cannot
end — a continuation that reaches ITSELF with its deadline already past when it is entered: a
self-naming `LEST` with `WITHIN 0` or a negative `WITHIN`, a kept `SHANT`'s `HENCE` with a
negative one, an anchored deadline that never moves — is refused **by name** rather than walked
forever: past `maximumStalledReoffers` (1,000, `Machine.hs:570`) consecutive stalled hand-offs
`reofferResolve` (`:1760-1780`) raises `stalledChainRefusal` (`:580`), a `UserError` that names
the stamp, the high-water deadline, the three shapes and the three repairs. The bound is
deliberately generous and decides only how soon an ill-founded chain is reported, not whether: a
stalled layer costs about a microsecond, and no finite chain of distinct layers comes near it
(the build notes' round-1 objection to a cap — "a silently wrong answer" — was to a SILENT cap;
this one is loud, and the consume branch it replaces was the silent one). A chain whose deadlines
advance is finite whenever the durations are bounded away from zero (the high-water mark is
increasing and bounded above by the stamp); measured, a self-naming `WITHIN 1` walked 100,000
incarnations in 0.15 s. The residual class is a Zeno chain — durations shrinking geometrically,
`x d MEANS … WITHIN d LEST x (d DIVIDED BY 2)` — whose deadlines advance forever without reaching
the stamp. It is left to the machine's frame-depth guard (`maximumFrameDepth`, 1,000,000: every
nested hand-off leaves a `RestoreCurrentParty` frame on the stack — measured, a `WITHIN 1` chain
walked to 1,500,000 reports `Stack overflow: Recursion depth of 1000000 exceeded` in about 1.5 s
and 286 MB); the halving Zeno chain itself did not reach that guard in 120 s because its rationals
grow a bit per layer, so it is a hang in practice — the class ordinary non-terminating recursion
is already in (`f x MEANS f (x PLUS 1)` is a tail call that pushes no frame; measured, no answer
in 60 s). Witness §9 (`sign, or try again`: `WAIT UNTIL 100` alone is the thirty-fourth
incarnation with two days left, and the signature at 101 fulfils it; `third chance` and `three
chances` pin the chain with one event and with two); §11 (`stuck in the middle`, layers due 10,
5, 15, and `forthwith`, due 10, 10, 15: a refund at 12 is `FULFILLED` and at 20 `BREACHED`
reporting 15, each with one event and with a `WAIT` at 11 before it); §12 (`forthwith, forever`,
a self-naming `WITHIN 0`: the refusal). The corpus's recursive witness,
`deontic-breach-semantics.l4` (f), a negative `WITHIN`, now prints the refusal where the build
commit and round 1 printed the recursive obligation as a residual — its chain never advances past
-1, so there was never a layer its event could reach, and the residual was the silent form of the
same fact. `nested peel` (layers due 2, 5, 15) is walked to its end by the `WAIT` at 20 —
`BREACHED` dated 20 reporting 15 where the build commit had dated it 30 — and a delivery at 12,
timely for layer 3, is `FULFILLED`.

**The consume branch is gone** (round 2). Until the round-2 fix commit `reofferResolve` had a
second arm that applied the continuation to the events AFTER a marked copy whose deadline had not
advanced, and §5.2.1 called what it dropped "the documented limit of the guard". It was a wrong
answer with a witness (above), and the guard it served needed no consumption: a chain that stalls
is refused instead. What R1-3 observed — a residual reached that way printing its source `WITHIN`
with a deadline already past — cannot arise any more, because no residual is reached that way.

**The state-layer stream (R1-5 from the stack's round 1, applied here).** `barrierStateMissed`
(`:2852`) no longer hands the `LEST` the whole stream from the arming. It walks the barrier's stream
from its arming to the first event stamped strictly after the state deadline — three new frames,
`BarrierTrim` / `BarrierTrimEvent` / `BarrierTrimStamp` (`:2048-2074`; `ContractFrame.hs:88-97`,
records `:564-585`), one cons cell per step, modelled on `Contract1`–`Contract3` — and applies the
`LEST` to the stream from that cell on (`barrierStateLest`, `:2867`), the same shape the act layer
gives its `LEST`. The walk is a prefix-drop, not a filter: it stops at the first event past the
deadline and keeps everything after it. A trace is stamp-sorted (`TraceOrderingSpec`), so the two
readings agree on every trace `l4 run` can see; they would differ only on an unsorted stream fed
through the service, which is not exercised. Witness §6: a refund at 1, before anyone had acted,
no longer discharges the reparation (`BREACHED` reporting 15, where the whole stream gave
`FULFILLED`); a refund at 11 — after the state deadline of 10, before the late signature at 12 —
does, which the join's own residual `joinEvents` (starting after the LAST completion) would have
missed; 15 timely, 16 late; the anchored twin gives the same 15.

**The ledger (item 5 of the build brief) — a measurement, not a decision.** The brief asked
whether a `RECORD` inside a `LEST` continuation is stamped at the revealing event or at the
deadline. Neither: a ledger append's transaction time is the ROOT eval clock, a `UTCTime`
(`runRecord`, `getEvalTime`), never the contract clock, and no expression can read the contract
clock. Measured on both binaries with `JL4_FIXED_NOW` pinned (probe `ledger-lest.l4`, a `RECORD`
under a `LEST` reached by `WAIT UNTIL 14`): `at=2025-01-31T15:45:30Z` before and after, with only
the residual moving (`WITHIN 5` → `WITHIN 1`). No ledger golden moves. There is nothing here for
Meng to rule on unless the contract clock is one day made readable, at which point the question
returns. (The brief's path `doc/reference/ledger` does not exist; the ledger's page is
`doc/tutorials/multi-temporal-modeling/multi-temporal-rule-modeling.md`.)

**What is NOT moved, on purpose.**

- **The breach's own date.** A `DeadlineMissed` is still stamped at the event that revealed it and
  carries the deadline it missed (`:1764`; `EVERY.md`'s "dated at the event that revealed"). §3.4's
  last paragraph says dating the failure to the deadline would change that stamp and the goldens
  that print it; that is a separate change and no ruling asks for it.
- **A kept `SHANT`'s `HENCE`.** Its clock and its `THE JOIN` are still the revealing event's stamp
  (`clockAt True`, `:1723`; §5.1.1.1's "For a kept `SHANT` the join is the event that revealed the
  deadline had passed"; `README.md`'s kept-prohibition sentence; witness `run-anchors.l4` `kept,
the join`, 33). §3.4 says a `SHANT` barrier "achieves at the deadline", and R-Q7 says a `HENCE`
  counts from the join's firing, so a reading under which that `HENCE` should count from the
  window's end (10 + 3 = 13, what `OF THE DEADLINE` gives today) is available; the ruling of §5.2
  is about `LEST`, and this track did not move a `HENCE`. **Open to Meng's ruling**, recorded here
  as the next item on this axis. If moved: `run-anchors.golden` `kept, the join` 33 → 13,
  `README.md`'s sentence, `Syntax.hs`'s `THE JOIN` bullet, and a `SHANT` barrier's join time
  (`Barrier2`'s `tLast` becomes the window's end).
- **The layer a never-completing member fails on, when both `WITHIN`s are written.** With
  `EVERY Tenant t … WITHIN 14 … ONCE ALL HAVE WITHIN 10 … LEST … WITHIN 5` and one tenant who never
  signs, the machine fails the barrier on the ACT layer — Bob's missed 14 — and the reparation is
  due at 19, not at the state deadline plus 5 = 15; the same trace with no act `WITHIN` gives 15
  (the `ONCE` line's `WITHIN` is demoted to each member, `memberDue`). So writing a LOOSER act
  `WITHIN` moves the landlord's reparation later (act 30: 35), and the state deadline is compared
  only after the join (`Barrier3`/`Barrier4`, reached from `barrierJoined` alone; §3.4's as-built
  note). R-Q5's words — "the failure time is the state's deadline, whatever the acts' modals" —
  read alone give 15 here. Found by round 1 (R1-2): the `README.md` row and the skill's sentence
  had stated the state-layer rule without EVERY.md's "everyone acted, but the last act landed
  after" limit; both now carry it and the README names the 19. **Open to Meng's ruling** — the
  machine half (compare the state deadline at each member expiry when it is the earlier of the
  two) changes which layer, and so which deadline, a barrier anchors at, which the build brief put
  out of scope; the doc half is applied. The probe, for whoever rules:

  ```l4
  EVERY Tenant t IN tenants
      MUST   Sign (EXACTLY t)
      WITHIN 14
      ONCE   ALL HAVE WITHIN 10
      HENCE  FULFILLED
      LEST   (PARTY ll MUST Refund (EXACTLY ll) WITHIN 5)
  ```

  Carol signs at 3, Alice at 4, `WAIT UNTIL 20`, Bob never → `BREACHED` reporting 19; a refund at
  17 → `FULFILLED`; the same rule with no act `WITHIN` → 15.

- **A `LEST` clock earlier than the failed obligation's own arming** (round 2, R2-2 fresh). An
  anchored `WITHIN` may already be past when its obligation is entered (`Contract5`'s comment calls
  that "right and not an error"), and its `LEST` counts from that deadline like any other, so the
  reparation can fall due before the obligation it repairs existed. The probe
  (`probes/round2/past-anchor.l4`):

  ```l4
  PARTY alice MUST Sign (EXACTLY alice) WITHIN 100
  HENCE (PARTY bob MUST Approve (EXACTLY bob) WITHIN 5 OF 0
         HENCE FULFILLED
         LEST (PARTY bob MUST Refund (EXACTLY bob) WITHIN 10))
  ```

  Alice signs at 20 (Bob's obligation is entered at 20 with its deadline at 5), a `WAIT` at 21 →
  `BREACHED` at 21 reporting **15**, five days before either of Bob's obligations was entered;
  with `WITHIN 30` the residual at 21 reads `WITHIN 14`. Literal to R-Q5 (t_ref = the deadline)
  and not a wrong answer under it, but a consequence nothing had written down. **Open to Meng's
  ruling**: whether a `LEST`'s clock should be `max(missed deadline, the failed obligation's
arming)` when the anchored deadline predates the arming. No code change; `README.md`'s
  anchored-deadline paragraph now states the literal behaviour and that the question is open. If
  moved: `clockAt` (`Machine.hs:1723` on round 1) takes `max deadline time'`, no corpus golden
  moves (no corpus file has an unanchored `LEST` under a past-anchored obligation), and the
  barrier path's sentinel anchor needs the same floor.

- Which member a barrier anchors at (the stack settled it); `AFTER`/`BEFORE` (built by the next
  track on 2026-09-16, §5.1.2's build block; under a `LEST` the window counts from this section's
  clock with no plumbing of its own); `SOME m OF`.

**Goldens.** Read before promotion, each with the reason the diff is right:

- NEW `ok/every/tests/run-lest.{golden,ep.golden,nlg.golden,schema.golden}` — the 33 results
  hand-computed in the witness's comments before the run, and matched (39 after round 1, 47 after
  round 2, each addition hand-computed the same way); the pre-change numbers the
  comments quote were measured on the parent's binary.
- `ok/tests/deontic-breach-semantics.golden`: `anchor at reveal` — renamed `anchor at the
deadline` — residual `WITHIN 3` → `BREACHED` at 7 reporting 5 (the `LEST` counts from 2, is due
  at 5, and the re-offered Bob@7 reveals that too); `nested peel` `FULFILLED` → `BREACHED` at 30
  reporting 15 (layers due at 2, 5, 15; Bob's delivery at 35 is never reached); after round 2,
  `recursive lest` (f) residual → the `stalledChainRefusal` text (the chain never advances past
  -1, and the residual was that fact printed silently). Comments rewritten;
  `.ep.golden` moves with them.
- `ok/every/tests/run-blame.golden`: `staggered signing`'s refund deadline 11 → 8 (Carol's 5 + 3,
  not the revealing 8 + 3); the refund at 12 still late. Comment rewritten; `.ep.golden` moves.
- `legal/tests/promissory-note.golden`: the late-payment residual `WITHIN 61` → `WITHIN 44` — the
  reparation counts from the missed first deadline (day 41 after 4 February 2025), so 61 days end
  at day 102 and 44 remain on 3 April (day 58). Comment rewritten; `.ep.golden` moves.
- `ok/tests/contracts.golden`: the third trace `FULFILLED` → `BREACHED` at 9 reporting 8 (B's
  fine counts from the missed 5, not from the late payment at 6). A comment added; `.ep.golden`
  moves.
- `ok/every/tests/run-{stack,anchors}.{golden,ep.golden}`: comment edits only (the anchor
  sentence in each header; `run-stack.l4` §3/§3b say how the tie is now decided), so the
  `.ep.golden` moves and the `.golden` moves by source line ranges alone — every result block is
  identical with the ranges normalised, which is the check that which member anchors did not
  change. `run-blame.golden` likewise carries a shifted line cite inside a refusal message.
- Nothing else moved. Every `ok/ledger` golden is byte-identical (the ledger measurement above).

**Docs, same commit.** `doc/tutorials/obligations/what-follows.md`: the second-clock paragraph
rewritten for the deadline (`WITHIN 13` and `WITHIN 6` as the pasted residuals, day 21, no
workaround), Mr Lim's fourteen days from day 7 (his day-20 payment still timely; the day-22 case
measured), the recap bullet and the table row; every pasted output re-run. `doc/reference/regulative/README.md`:
the `WITHIN` paragraph's "today" sentence replaced, and the `LEST` section gains the rule by layer
and modal, in a table, with the `OF THE DEADLINE` equivalence and the `SHANT` exception.
`doc/reference/regulative/EVERY.md`: the two "not built" bullets deleted (the failed-barrier clock,
the state-layer stream), the `LEST` paragraph states the rule, the header's verified line dated.
`doc/concepts/legal-modeling/regulative-layer-whole.md`: the clock bullet and the built/proposed
table (the blame-set row, built 2026-09-15 by the parent branch, moved to the built column while
there). `skills/writing-l4-rules/references/regulative.md`: the unanchored default, which the
skill had never stated, added beside the anchored form. Three doc `.l4` files' outputs move
(`what-follows.l4`, `regulative-layer-whole-example.l4`, `courses/advanced/module-a2-cross-cutting-examples.l4`);
only the first has its residuals pasted on a page. Round 2: `README.md`'s chain-walk sentence now
states that a non-advancing layer makes no difference either, and the one limit — a self-naming
`LEST` whose window is never open is refused by name; its anchored-deadline paragraph states the
past-anchor consequence and that the floor is open (R2-2 fresh); the skill's `LEST`-clock
paragraph gains the walk and the refusal; `LTS-VISUALISER.md` §4.4's annotation says the walk is
unconditional and can end in a refusal. No doc `.l4` output moves in round 2.

**For downstream re-pinning (item 9 of the build brief).** The clocks that move: the unanchored
`LEST` deadline under a missed `MUST`/`DO`/`MAY` — single-party, fork member, and barrier
member-failure (`JoinFailed` in `lts/p2-stack`'s terms) — from revealing stamp plus `d` to deadline
plus `d`; **`THE ARMING` of a `LEST` continuation** — what `OF THE ARMING` names one level further
down, i.e. inside the continuation's own `HENCE`/`LEST` — which is the instant the continuation
was applied to, so it moves with the clock, from the revealing stamp to the missed deadline
(`App1` arms a continuation with `armed = time`, `Machine.hs:1133`; found by the adversarial pass,
witness `run-lest.l4` §10); and the state-layer `LEST`'s residual stream (events after the state
deadline). Unchanged: `memberDue`, `joinStateDue`, `MAY`-lapse routing (an expired `MAY` under a
fork spawns no continuation; under a barrier with no `LEST`, `FULFILLED`), the breach stamp, every
`HENCE` clock and every `HENCE` continuation's `THE ARMING` (`JoinExpired`'s included), `THE
DEADLINE`, the `SHANT` `LEST` (and its continuation's `THE ARMING`, the violating stamp as
before), and the number of times a barrier's `LEST` fires (once). Round 2 adds one outcome, not
a clock: a walk down a chain of continuations can now end in an evaluation error
(`stalledChainRefusal`) where before it ended in a residual — only for a continuation that reaches
itself with its deadline already past, never for a chain of distinct layers.

**Not verified here.** The full `etc/verify-branch.sh` as one run (the Verify stage's); the §3.2.1
evaluation differential (no printer is touched); `jl4-service-test`, `jl4-lsp-test`,
`jl4-websessions-test`, `jl4-mlir-test` beyond `cabal build all`; an unsorted event stream through
the service (where prefix-drop and filter would differ); `lts/p2-stack` and PR #395's pins, which
are not in this tree.

**What the adversarial pass of 2026-09-16 changed.** Round 1: fourteen findings raised, none
refuted by both checkers, all fourteen applied or routed (`scratchpad/every-lest/FINDINGS-round1.md`
has both verdicts on each):

- R1-1 (semantics and completeness, a blocker found twice): the at-most-once re-offer rule dropped a
  timely performance of the third layer of a `LEST` chain and made the verdict at an instant depend
  on the event count. Fixed: a re-offered copy is marked with its minting deadline and re-offered
  again while the deadline strictly advances (the termination paragraph above; round 2 removed
  the "while the deadline advances" condition, below). Goldens:
  `run-lest.golden` §9 (`WITHIN 3` → `WITHIN 2`; residual → `FULFILLED`), `deontic-breach-semantics.golden`
  `nested peel` (dated 30 → dated 20), `run-lest.l4` gains `third chance`, `three chances`, §10.
- R1-3 (semantics): a consume-branch residual printed a stale `WITHIN`. Fell away with R1-1 for
  every positive `WITHIN`; round 1 documented the non-advancing case as a limit, and round 2
  removed the branch (R2-1 below), so it cannot arise at all.
- R1-2 (semantics): the README row and the skill line stated the state-layer rule for a "late
  group" without the "everyone acted" limit. Both qualified; the S2 case (19 not 15) recorded under
  "What is NOT moved" and routed to Meng.
- R1-2 (completeness): `THE ARMING` of a `LEST` continuation moved with the clock and was not on the
  re-pin list. Listed there, stated in the README's anchor table and the entered-at paragraph,
  pinned by `run-lest.l4` §10 (`OF THE ARMING` two levels down under a `LEST`: 13, and under a
  `HENCE`: 7).
- R1-G1: prettier had turned "+ `d`" into a list bullet in the re-pin paragraph; rephrased.
- R1-G2: `regulative-layer-whole.md` said both that a group breach names one person and that the
  set is built; lines 121, 123 and 284 rewritten to the built state.
- R1-G3 and R1-4: §11.0.1's "anchor's VALUE is still the revealing stamp" (twice) past-tensed and
  annotated; the dangling "(next bullet)" repointed.
- R1-G4: §5.1.1.1's "tie on the revealing event broken by the earlier deadline" reworded to the
  first-key ordering.
- R1-G5: `promissory-note.l4`'s two comments quoted `Days in a month` as 30.4375; corrected to
  30.436875 (the arithmetic, 41/61/102/44, was already right).
- R1-G6: the build notes cited the vendored canon file without its `jl4/examples/` prefix;
  corrected in the notes.
- R1-3 (completeness): the cite `ContractFrame.hs:145` (which is `ScrutinizeEvents.time`) → the
  `ResolvePartyFrame.time` field (`:589` on `546965be`, `:591` here); every
  `Machine.hs` cite in this section re-pinned to the round-1 fix commit, which moved them.
- R1-5 (completeness): `regulative-rules.md:187` taught that a chained inner window starts from the
  event that triggered it; rewritten for `HENCE` at the act, `LEST` at the failure, and the
  anchored form.

Round 2: four findings raised, none refuted by both checkers, all four applied
(`scratchpad/every-lest/FINDINGS-round2.md` has both verdicts on each):

- R2-1 (fix-landed and fresh-attack, a blocker found twice): round 1's consume branch still dropped
  a re-offered copy at a layer whose deadline had not advanced (`WITHIN 5 OF THE ARMING` under a
  `WITHIN 10`; `WITHIN 0`), before the next layer it was timely for, so the verdict at an instant
  again depended on the event count. Fixed: the copy is always handed on; the mark became
  `Reoffered` (high-water deadline plus a stalled count) and a chain that stalls for
  `maximumStalledReoffers` (1,000) hand-offs in a row is refused by name (`stalledChainRefusal`)
  instead of consumed (the termination paragraph above). Goldens: `run-lest.golden` gains §11
  (`stuck in the middle` ×4, `forthwith` ×3) and §12 (`forthwith, forever`);
  `deontic-breach-semantics.golden` (f) residual → the refusal; `.ep`/`.nlg` with them. The
  "would loop forever" sentences in the `Contract5` NOTE and here narrowed to a continuation that
  reaches itself; `README.md:247`'s claim made true and given its one limit.
- R2-2 (fix-landed): §5.2.1 said "33 directives, nine sections" and "the 33 results" after round 1
  had made it 39 in ten; both now give the count per round (47 in twelve after round 2).
- R2-2 (fresh-attack): a `LEST` under an anchored `WITHIN` already past at arming counts from a
  deadline earlier than the failed obligation's own entry (`WITHIN 5 OF 0` entered at 20, its
  `LEST` with `WITHIN 10` due at 15); literal to R-Q5, written nowhere. Recorded under "What is
  NOT moved" as open to Meng (the `max(deadline, arming)` floor), and stated in `README.md`'s
  anchored-deadline paragraph. No code change.

### 5.3 Temporal Forking (MAY Exercise)

When a party exercises a MAY, the HENCE obligations activate relative to exercise time:

```l4
EVERY p_x
    MAY   terminate
    UPON  EACH                          -- fork (R-Q1, RULED 2026-09-07)
    HENCE EVERY p_y
              WHO    differs_from p_y p_x   -- R-Q4
              MUST   settle_with p_x
              WITHIN 30
```

If A terminates at t=10 and B terminates at t=15:

- A's termination spawns: C must settle with A by t=40, B must settle with A by t=40
- B's termination spawns: C must settle with B by t=45, A must settle with B by t=45

These are **independent obligation contexts** (CSP interleaving).

## 6. Blame Attribution

### 6.1 Precise Blame

When LEST fires, blame is attributed to exactly those who didn't complete:

```haskell
computeBlame :: BarrierObligation -> Trace -> Set Party
computeBlame bo tr =
    let completed = completedParties bo tr
    in bo.parties `Set.difference` completed
```

**Example:**

- Parties: {A, B, C}
- A and B complete; C doesn't
- Blame: {C}, not {A, B, C}

#### 6.1.1 BUILT 2026-09-15 (R-T3) — on `every/blame-set`; witness `jl4/examples/ok/every/run-blame.l4`

The sketch above is a design record and is left as it was written: `BarrierObligation`,
`computeBlame` and `Set Party` do not exist in the tree. What the tree has, and what each decision
below rests on, is recorded here against `every/blame-set`'s HEAD after the adversarial pass of
2026-09-15 — **`cedbf7e6`; the line numbers below are on that commit** and are NOT current on
`every/anchors-on-blame`, where B's insertions shift them (`git show cedbf7e6:<file>` reads them
as cited; §11.0.1 "Stacking B on C" has the live cites for the stacked tree). The first build's
shape is recorded where the pass reversed it, so a later reader can see what changed and why.

**The ruling that decided the shape.** Meng, 2026-09-15, in session, after the first build had
started: _"let's not bother deduping the ReasonForBreach -- maybe we need to be able to say, 'well,
Alice screwed the pooch two different ways'"_. Two things follow and both are built: **no
deduplication** — one entry per failed obligation, the same party as many times as she failed — and
**per-entry detail** — an entry says what was failed, not just who, because `[alice, alice]` cannot
say the two ways. The first build had done the opposite on both counts (a `NonEmpty` of bare
parties, deduplicated by ledger key, beside ONE anchoring action and deadline); the adversarial
pass found it (eleven blockers from three checkers, eight of them this one defect and three the
written claims that went with it) and replaced it.

**The representation is a non-empty list of failures, not `Set`.** Meng, 2026-09-15: _"did we
consider a NonEmpty list?"_ The sketch said `Set Party`, and a non-empty list had not been
considered. It was built as a non-empty list, for three reasons. (1) A failed barrier has at least
one non-completer and a failed `RAND` at least one failed operand, so the invariant belongs in the
type. (2) Roll order is already the determinism the goldens rely on (§11.0.1: "reversing the roll
reverses which member is named"), and the party is a heap `Reference` — a `Set` would need every
party forced and keyed by `partyKeyWHNF` just to have an `Ord`, and would then print in key order
rather than the drafter's. (3) The singleton prints byte-identically to the one-party form, so only
goldens with a compound failure move.

```haskell
-- jl4-core/src/L4/Evaluate/ValueLazy.hs:105-145
data Failure a
  = MissedDeadline a (RAction Resolved) Rational   -- the party, the action it owed, the deadline it missed
  | DeclaredBreach (Maybe a) (Maybe a)              -- BREACH [BY p] [BECAUSE r]: the party named, if any; the reason, if any

data Blame a = Blame { before :: [Failure a], anchor :: Failure a, after :: [Failure a] }

data ReasonForBreach a
  = DeadlineMissed a a Rational (Blame a)   -- revealing event's party, action and stamp; the failures
  | ExplicitBreach (Blame a)
```

**The entry is sum-typed** (`Failure`, `ValueLazy.hs:105`): a missed deadline carries the party, the
action and the deadline; a declared breach carries whom `BY` named, if anyone, and its `BECAUSE`, if
any. That is what lets the union across breach kinds carry each side's own detail without inventing
anything — which is the objection the first build raised against per-entry detail ("a party from an
`ExplicitBreach` operand has no deadline") and the ruling answered. A bare `LEST BREACH` is one
entry naming nobody, so two bare breaches under `RAND` are two entries (each prints
`BY (nobody named)`); no corpus golden has that shape.

**The anchor is marked by position, not by index or by a second copy** (`Blame`, `ValueLazy.hs:120`):
the list is a zipper `before ++ [anchor] ++ after`, so the anchor is always one of the entries, the
order is the drafter's, and there is no index to go out of range. The two constructors of
`ReasonForBreach` say what KIND of failure the breach is anchored at — `DeadlineMissed` carries the
revealing event beside the blame, `ExplicitBreach` carries no time — and a compound keeps the
anchor's constructor (`rebase`, `Machine.hs:2442`). That a `DeadlineMissed` is anchored at a
`MissedDeadline` is an invariant of construction, not of the type; every constructor site builds it
so, and the printer and both wires handle the other case as a well-formed object rather than a
crash.

**Order, and no deduplication.** Operand order for `RAND`/`ROR` (left operand's failures first),
roll order for a barrier, list order for `BY LIST`. Nothing collapses: `PARTY alice MUST Sign RAND
PARTY alice MUST Refund`, both missed, names Alice twice, once with each action (`run-blame.l4`,
`alice twice`); `BREACH BY LIST alice, bob, alice` names her twice (`joint and several`); a roll
that lists a member twice fails her twice. The first build's `BreachParties` frame, which forced
each party to key it, is gone — nothing needs the parties forced, and they stay thunks until the
result is normalised (`EvaluateLazy.hs`, `nfAux`, now a plain `traverse` over the derived
`Traversable`).

**`RAND`/`ROR`: the concatenation, anchored as before.** When both operands are breached, the
result keeps today's anchor — the earlier breach for `RAND`, the later for `ROR`, by the revealing
stamp, tie to the left for `RAND` and the right for `ROR`, an untimestamped `ExplicitBreach` treated
as simultaneous — and carries both operands' failures in operand order (`Machine.hs:1883-1891`;
`anchorLeft`/`anchorRight`, `ValueLazy.hs:179-184`). Only WHEN is decided by the anchor; each entry
keeps its own action and deadline or its own `BECAUSE`, so nothing is read off the wrong side. In
particular, when both sides wrote a `LEST BREACH … BECAUSE`, neither carries a time, so the anchor
falls to the left for `RAND` and the right for `ROR` regardless of when each was lost — that
affects only which side dates the breach, and since 2026-09-15 no user document claims the
surviving reason is "the side lost first/last" (the first build's docs did; the pass corrected
them). Two bare `BREACH`es are two entries naming nobody.

**The barrier runs every member before deciding.** `Barrier1` no longer ends the scan at the first
failure; each failure is recorded (`BarrierStepFrame.failures`, `ContractFrame.hs:284`) and
`barrierFinish` (`Machine.hs:2306`) decides once the queue is empty. One consequence the first
build did not record and the pass did: a member later on the roll is now evaluated after an earlier
one has failed, so an error in its `WITHIN` (or anywhere its run reaches — `probes/pQ-later-error.l4`
in the scratch dir: a `1 DIVIDED BY 0` deadline on the second member) is now the barrier's verdict
where before 2026-09-15 it was masked by the first member's breach. The same is true of `RAND`/`ROR`
only insofar as both operands were always run; it is new for the barrier.

- **no `LEST`:** one `DeadlineMissed`, anchored at the earliest failure by R-Q5's failure time —
  the smallest missed deadline for `MUST`/`DO`, the violating event's stamp for `SHANT`, both of which
  are the `deadline` the member's own anchoring `MissedDeadline` carries — and naming every failed
  member in roll order, each with its own action and deadline. Ties keep the first in roll order
  (`earliestFailure`, `Machine.hs:2352`, which returns the roll position so the concatenation is
  built around it, `Machine.hs:2310`).
- **with a `LEST`:** the `LEST` runs once, with the anchor and residual stream of the earliest
  failure. The ordering key is the failpoint sentinel's own anchor, forced (`BarrierFailedAt.failAt`,
  `ContractFrame.hs:298`; it is the same reference the `LEST` is handed), so whatever §5.2 makes the
  anchor read, the ordering follows — there is no second key to switch. On this branch the anchor
  read the revealing event's stamp (§5.2's deadline anchor was NOT built here; the anchor's VALUE
  was untouched, one change in one place for the §5.2 track — which made it on 2026-09-16, §5.2.1,
  after which the anchor IS the failure time and the "up to ties" reasoning that follows is
  history), which — **for `MUST`/`DO`/`MAY`** — ordered by the
  missed deadline **up to ties**: every member scans the same stream, so an earlier deadline is
  revealed by an earlier-or-equal event; two deadlines revealed by the same event tie, the tie
  keeps the first in roll order, and that is the same event — same anchor, same residual — so the
  answer cannot differ from ordering by deadline. **For `SHANT` that reasoning does not hold, and
  this build's roll-order tie-break was NOT harmless there** (found by round 1 of the stacked
  branch's adversarial pass, 2026-09-16): a `SHANT` member's stamp is its own violating event's,
  so two members violated at one stamp by two events are two failures with two residuals, and
  which residual the `LEST` got depended on the roll — measured on this branch's own binary
  (`cedbf7e6`, probe `H-shant-C.l4`: Bob smokes 3, the landlord refunds 3, Carol smokes 3,
  `WAIT UNTIL 20`, unanchored `LEST … WITHIN 5`): `FULFILLED` on `LIST alice, bob, carol` and
  `BREACHED` at 8 on the reversed roll, the same events. **Stacked under R-Q7B (2026-09-16, §11.0.1 "Stacking
  B on C") the `MUST` sentence stopped being sufficient too**: the `LEST` also reads `THE DEADLINE`
  from the chosen member, and a tie on the revealing event does differ there (measured 19 vs 10
  across the two rolls). The stacked branch therefore orders a stamp tie by the stream position
  first (`BarrierFailedAt.failPos`, forced by `Barrier5c`; only the same event ties it), then by
  the deadline missed (`BarrierFailedAt.failDue`, forced by `Barrier5b`), and roll order breaks
  only a tie on all three, which then names the same anchor, residual and deadline either way. The
  anchor's VALUE and the number of `LEST` firings are unchanged by it. (The first build's comment said "orders by the missed deadline" without the tie
  qualifier; the pass measured deadlines 5 and 6 under one `WAIT UNTIL 10`, both rolls, and found
  the residual identical, `probes/gate/g7-stamp-tie.l4`.) `run-blame.l4`'s `staggered signing` pins
  it: Carol, last on the roll with five days, fails first, and the landlord's reparation is anchored
  at her failure (deadline 11), not at Bob's (23).
- **`MAY` under a barrier with no `LEST`:** a lapsed permission is recorded as `lapsed`, and the
  verdict stays `FULFILLED` — the join cannot fire and nothing was owed — exactly as when the lapse
  ended the scan; `run-modals.l4`'s `the resolution` is unchanged.
- **What the `LEST` names.** A barrier's `LEST` is the drafter's expression, run as written: a bare
  `LEST BREACH` names nobody (`run-barrier.golden` unchanged), and `LEST BREACH BY LIST a, b` names
  whom the drafter named. The failed members are NOT injected into it. This section's first sentence
  — "when LEST fires, blame is attributed to exactly those who didn't complete" — is therefore
  delivered by the barrier WITHOUT a `LEST`, and not by one with a `LEST`; a `BY` that names the
  failing members from inside a barrier's `LEST` (`BY EVERY t`, §2.2.7.5 point 4) is not ruled, and
  the brief put it out of scope. Injecting the set into a bare `BREACH` was considered and not done:
  it is a language decision, not an implementation detail.
- The two REFUSALS of §11.0.1 and the same-instant tie imprecision are unchanged.

**`BREACH BY <list>`.** The checker (`checkBreachParty`, `TypeCheck.hs:1975`) infers the `BY`
expression and reads its type: a `LIST OF t` unifies `t` with the party type, anything else is the
party. Deterministic rather than a `choose` between the two readings, because an unresolved party
type would otherwise leave both branches viable and report an ambiguity where today there is none.
A `BREACH` checked against a known `DEONTIC` type — a `LEST`, a `RAND`/`ROR` operand under a
`GIVETH`, a top-level `x MEANS BREACH BY …` under a `GIVETH` — unifies with it FIRST (`checkExpr`,
`TypeCheck.hs:1899`), so the `BY` is read against the rule's party type rather than a fresh one;
the first build inferred it fresh and unified afterwards, which is why a mismatch there was reported
against "the HENCE clause" of the rule rather than the `BY`. A mismatch now says `BREACH BY`
(`ExpectBreachPartyContext`). Since round 2 of the pass a `RAND`/`ROR` checked against a known
`DEONTIC` type does the same — unifies first, then checks both operands at it
(`checkRegulativeBinOp`, `TypeCheck.hs:601`) — so under a `GIVETH` the party type reaches a
`BREACH` in EITHER operand; before that the compound was always inferred with a fresh party type
and a `GIVETH` never reached its left operand. The syntax node is unchanged and carries no mark, so
the machine decides by the value's shape (`BreachBy`, `Machine.hs:1809`): a `ValCons` is walked,
one declared failure per element in list order, duplicates kept, the head the (nominal) anchor;
anything else is the one party. Four things the pass changed here, three in round 1 and one in
round 2:

- **A party type that is itself a `LIST`** — `DEONTIC (LIST OF STRING) Action` with
  `BREACH BY (LIST "a", "b")` — type-checked and ran before this branch and the first build gave it
  up ("the list reading wins"). Restored: when the party type and the `BY` expression's type are
  both fully known and are the SAME list type (a structural comparison on `typeKey`, not a
  unification), the drafter named one party whose value is a list, and the checker rewrites the
  expression as the one-element list `LIST e`, which the machine walks into exactly that one party
  (`TypeCheck.hs:1975-2002`). The wrap is idempotent under re-check — `l4 batch` re-prints the
  module and the printed `LIST (LIST "a", "b")` takes the element reading, whose element type is the
  party type — and invisible to exactprint, which prints the parsed tree. Witness: `run-blame.l4`,
  `the pair delivers`; a list of such lists still names several. **The limit, found in round 2
  (R2-TC-1) and stated here because round 1's "restored" was unqualified:** the decision needs the
  party type, and a `BREACH BY <list>` that is reached by INFERENCE arrives with a fresh one — a
  top-level `x MEANS BREACH BY (LIST …)` with no `GIVETH`, or the LEFT operand of a `RAND`/`ROR`
  that has none. Round 1 took the element reading there, which pinned the party type to the
  element type and failed later, at the use site, with a `HENCE` or `AND` mismatch naming the wrong
  place; the same `RAND` passed with its operands swapped (`probes/round2/a4-rand-order.l4` vs
  `a5-rand-order-swapped.l4`, scratch), and a shape that type-checked at `e578654c`
  (`a-nogiveth-listparty.l4`, the list-typed party with no `GIVETH`) was rejected. Round 2 made it
  loud: a LIST after `BY` under a party type that is not yet ground is **refused at the `BREACH`**
  (`BreachByListNeedsPartyType`, `TypeCheck/Types.hs:212`; `checkBreachParty`,
  `TypeCheck.hs:1975-2002`), naming the two ways out — a `GIVETH A DEONTIC …` on the
  definition, or the `PARTY` operand first — and leaving the party type for the use site, so one
  cause is one error. Witness `jl4/examples/not-ok/tc/breach-by-list-needs-party-type.l4` (both
  shapes). So the shape that passed at `e578654c` and was rejected on round 1's HEAD is now
  rejected with a message that says why, not accepted: **that is a regression against `e578654c`
  for the no-`GIVETH` list-typed party, chosen over silence.** The fuller fix — defer the reading
  until the module's substitution is final and rewrite the tree then — would accept those shapes;
  it needs a post-check rewrite pass the checker does not have, and is NOT built.
- **A mismatch under the element reading names the list's own type** (round 2, R2-TC-2):
  `LEST BREACH BY LIST 1, 2` against a party type `Actor` reported `NUMBER` (the element type)
  against the range of the whole `LIST 1, 2`; it now reports `LIST OF NUMBER`, the type of the
  expression at that range, under the prefix that already says a list's elements must be the party
  type (`TypeCheck.hs:1998`). Narrowing the range to "the offending element" is undefined for a
  computed list, which decided it.
- **A list literal with nobody in it is refused at check time** (`EmptyBreachBy`,
  `TypeCheck/Types.hs:206`): `BY EMPTY` and `BY (LIST)` both, one error each, named at the
  expression. The first build refused only at run time and only when the `LEST` fired, so a rule
  whose `LEST` never fired shipped the defect silently. A COMPUTED list that turns out empty keeps
  the run-time refusal naming the clause (`emptyBreachByRefusal`, `Machine.hs:2448`;
  `run-blame.l4`, `blame nobody`). Witness for the check-time half:
  `jl4/examples/not-ok/tc/breach-by-empty.l4`.
- Dedup of the list's elements is gone (above).

**Printing.** Singletons print as before. A compound prints one entry per failure, in order, each
with its own detail (`Print.hs:1239-1291`). Under a missed-deadline anchor: the revealing event's
three lines (`party … who did action … at …`), then the ANCHOR in the singleton's own six lines
(`surpassed the deadline of party … who had to do obligatory action … before their deadline, which
was at …`) — so a compound's first nine lines are exactly what that one failure would print alone —
and then `and the breach names, in order` followed by every entry, the anchor among them, each a
party and, indented, its action and deadline, or a party and its `BECAUSE`. Under a declared
anchor, `BREACH` followed by one `BY p BECAUSE r` line per entry (a missed-deadline entry there is
`BY p` with its action and deadline indented under it; an entry naming nobody is `BY (nobody
named)`). Two headers were retired on the way, each for saying something false about the entries
under it. The first build's `surpassed the deadline of parties` listed bare parties under ONE
action and deadline, and printed Bob as having missed a deadline of 5 when his was 14
(`run-blame.golden`, `staggered signing, no reparation`) and Alice as having had to `deliver` when
she owed `pay 1` and was blamed by declaration (`deontic-breach-semantics.golden`, `explicit or
deadline`) — false statements, blessed. Round 1 replaced it with `revealed the breach of` over the
whole list, under the revealing event's stamp; round 2 (r2-blame-4) found that the stamp vouches
for the anchor only — an event at 8 cannot have revealed a deadline-10 miss, which a later event
did — so the list header now claims nothing about when each entry was revealed, and the anchor,
which the stamp does vouch for, is printed in the singleton's words. Both goldens re-blessed and
read twice.

**The wire** (`ValueLazyJSON.hs:108-168`; jl4-service `Backend/Jl4.hs:1260`; the jl4-mlir runtime
mirror `jl4-runtime.mjs:981`, its pure unit tests updated, the parity harness NOT run on this
branch). Additive over the one-party form:

- the scalars — `obligatedParty` / `obligationAction` / `deadline` on `deadline_missed`, `party` /
  `reason` (`detail` on the service wire) on `explicit_breach` — describe the **anchor**, so they
  are one coherent obligation and, for a single obligation's breach, exactly what the old wire
  carried. **This deviates from the brief's "keep a scalar `party` (the head)", deliberately:** the
  head is the anchor only for a left-anchored compound, and the first build's head-party beside the
  anchor's action and deadline named an obligation nobody had (`{"obligatedParty":"Bob",
"obligationAction":"MUST pay 100","deadline":5}` for `(Bob deliver/14) RAND (Alice pay/5)`, where
  the base `e578654c` wire said Alice — measured by three checkers on `probes/pG-json.l4`). The
  brief's own requirement that the scalar stay backward compatible for its readers is met by the
  anchor and not by the head.
- `obligatedParties` / `parties`: every party named, in order, with duplicates; an entry naming
  nobody contributes nothing (`[]`, not `null`, when none does).
- `failures`: one object per failed obligation, in the same order —
  `{"type":"deadline_missed","party","action","deadline"}` or
  `{"type":"explicit_breach","party","reason"}` (`"reason"`-keyed on the service wire, with
  `detail` for the text, matching its scalar vocabulary).
- `anchor`: the anchor's index into `failures`.

**Two invariants a downstream projection depends on, stated here because it re-pins against this
sentence** (cross-track notes of 2026-09-15 from the lts-diagrams sessions; the BPMN shape — one
interrupting timer on the multi-instance task, routed to ONE error end — and the `lts/p2-stack`
deontic step log both rest on them). (1) **A barrier's `LEST` fires ONCE, for the group.** The
blame LIST grows; the number of `LEST` firings does not (`barrierFinish`, `Machine.hs:2306`, runs
the `LEST` once with the earliest failure's anchor and residual). (2) **The anchor is the earliest
failure by R-Q5's failure time, and its VALUE is the revealing event's stamp** — the deadline
anchor of §5.2 is not built on this branch. (Built 2026-09-16 on `every/lest-anchor`, §5.2.1: the
anchor's VALUE is now the failure time itself — the missed deadline for `MUST`/`DO`/`MAY`, the
violating stamp for `SHANT`; invariant (1) stands.)

**Owed downstream, not done here.** The BPMN export's barrier `LEST` arm is a bare
`<endEvent errorRef="Error_breach">` (`L4.Bpmn.Emit`'s `sharedErrorId`, wired from
`L4.Bpmn.Lower`). Its concurrency review of 2026-09-15 called that acceptable BECAUSE R-T3 was
unbuilt; now that the runtime names the set of failed members, that error end drops something the
source says, and BPMN has no shape for a set of parties on an error event. Owed the day this
branch merges, by whoever holds the BPMN track (the lts-diagrams session has offered): a fidelity
note in `L4.Bpmn.Lower` and a dated line in `specs/todo/lexipedia-superset/LTS-VISUALISER.md` §4.9
(the note that raised this named the file and a `quantifierNotes` list by other names; neither is
in this tree at this HEAD — check before citing). `L4.Bpmn.Lower` is not touched on this branch.

**Measured on the branch's HEAD.** Goldens that moved against `e578654c`: one existing golden set
— `ok/tests/deontic-breach-semantics.golden` (its four both-breached traces, now one entry each with
its own detail) and its `.ep.golden` twin (comment lines only, 246 lines before and after) — plus
the new `ok/every/run-blame.{golden,ep.golden,nlg.golden,schema.golden}` and
`not-ok/tc/breach-by-empty.{golden,ep.golden,nlg.golden,schema.golden}`. `run-barrier.golden`,
`run-modals.golden`, `run-fork.golden`, `contracts.golden`, `prohibition.golden`,
`temporal-pin-deep.golden` and `regcf.golden` are unchanged (their failures are singletons, a bare
`LEST BREACH`, or a lapsed `MAY`). Goldens containing `DEONTIC BREACHED`: eight at `e578654c`,
nine on this HEAD counting the new `run-blame.golden` (`grep -rl 'DEONTIC BREACHED' jl4 jl4-core
--include='*.golden'`; without the include the same grep also hits `Print.hs`, `StateGraph.hs` and
a README, which is how the first build's "nine, measured with `grep -rl … jl4 jl4-core`" came to
name a command that returns twelve). Eleven `run-blame.l4` traces pin the six behaviours the brief
listed, the no-`LEST` staggered anchor, the un-deduplicated `alice RAND alice` and
`BY LIST alice, bob, alice`, the run-time empty-list refusal, the list-typed party, and (round 2)
the list-typed party as the LEFT operand of a `RAND` under a `GIVETH`. Round 2 moved
`run-blame.golden` and `deontic-breach-semantics.golden` once more (the print header) and added
`not-ok/tc/breach-by-list-needs-party-type.{golden,ep.golden,nlg.golden,schema.golden}`.

### 6.2 Causal Blame Analysis

When a party's failure is caused by another:

```haskell
data BlameAttribution = BlameAttribution
    { baDirectBlame   :: Set Party    -- simply didn't perform
    , baCausalBlame   :: Set Party    -- caused others' failure
    , baExcused       :: Set Party    -- excused due to causation
    }
```

**Example:**

- A completes
- B is prevented by A's wrongful interference
- C simply doesn't perform
- Result: Direct={C}, Causal={A}, Excused={B}, Final={A,C}

### 6.3 Indexed Blame for Distributive Obligations

For `EACH p MUST X` (no shared HENCE/LEST), each obligation has independent blame:

```haskell
data Verdict
    = Success
    | Breach Time (Set Party)
    | IndexedBreach Time (Map Party BlameInfo)  -- per-party tracking
```

## 7. MAY and Correlative Obligations

### 7.1 Hvitved's Insight

A contractual MAY is meaningful precisely because it imposes obligations on counterparties. Without this correlative, the MAY could be omitted without loss.

### 7.2 Correlative Structure

```l4
EACH p_x
    MAY   terminate
    HENCE EVERY p_y
              WHO  differs_from p_x
              MUST settle_outstanding_accounts_with p_x
```

The HENCE clause explicitly captures the correlative obligation. This is preferable to implicit correlatives because:

1. Uses existing HENCE machinery
2. Explicit about what the correlative requires
3. Composes naturally with other constructs

### 7.3 Expansion

For parties {A, B, C}:

```l4
A MAY terminate HENCE (B MUST settle_with A AND C MUST settle_with A)
B MAY terminate HENCE (A MUST settle_with B AND C MUST settle_with B)
C MAY terminate HENCE (A MUST settle_with C AND B MUST settle_with C)
```

Total: 3 permissions, each with 2 correlative obligations = 3 + 6 = 9 deontic atoms.

## 8. Compositionality

### 8.1 Nesting Quantifiers

```l4
EVERY seller s MUST deliver(s)
    HENCE EVERY buyer b MUST pay(amount_for s b) WITHIN 30
```

The inner barrier spawns when the outer barrier achieves, with:

- `entryTime = outer.achievementTime`
- Scope chain captures `s` binding for inner body

### 8.2 With IF/THEN/ELSE

```l4
IF condition THEN
    EVERY p MUST X
ELSE
    EVERY p MUST Y
```

Standard conditional; the quantified deontons are in the branches.

### 8.3 With RAND/ROR

```l4
(EVERY seller s MUST deliver ONCE ALL HAVE HENCE ...)
RAND
(EVERY buyer b MUST pay ONCE ALL HAVE HENCE ...)
```

Both quantified obligations must be satisfied (regulative conjunction).

**Worked example — PROPOSED, not built; added 2026-09-07 for R-Q2 (§2.5).** Meng's note on R-Q2,
verbatim: _"How do the quantifies interact with RAND ROR combinators? Docs need to show an
example."_ The composition is stated above in one line each way; nothing showed it worked. Three
shapes, in the value-actor style of §2.2.7.6, with the breach naming under R-T3's set-valued `BY`:

```l4
-- (1) a quantified obligation as one operand of RAND: the board signs AND the secretary files
`board signs and secretary files` MEANS
    (EVERY Director d IN board MUST sign WITHIN 30
        ONCE ALL HAVE
        HENCE FULFILLED
        LEST  BREACH)                     -- blame = the non-signers (§6.1), a set under R-T3
    RAND
    (PARTY secretary MUST file WITHIN 30
        HENCE FULFILLED
        LEST  BREACH BY secretary)
-- Two directors miss the date and the secretary files: the compound breach names the two
-- directors. Before 2026-09-15 the fold named ONE operand by timestamp tie-break; since then
-- (§6.1) a RAND names both operands' parties -- but the barrier's own `LEST BREACH` names
-- nobody, so as written this shape still needs the LEST left off to name the non-signers.

-- (2) a quantified obligation as one operand of ROR: unanimous written consent OR a chair's decision
`consent or decision` MEANS
    (EVERY Director d IN board DO consent WITHIN 14
        ONCE ALL HAVE
        HENCE `resolution passes`)
    ROR
    (PARTY chair MUST decide WITHIN 14
        HENCE `resolution passes`)
-- Either branch fulfils the compound (the ROR arms of RBinOp2 in Machine.hs); it is breached only
-- when BOTH are lost, and then names both operands' non-performers under R-T3 (built 2026-09-15).

-- (3) a barrier whose HENCE is itself a RAND: after the last signature, two things follow in parallel
`sign then close` MEANS
    EVERY Director d IN board MUST sign WITHIN 30
        ONCE  ALL HAVE
        HENCE (PARTY escrow    MUST `release funds`       WITHIN 5
               RAND
               PARTY secretary MUST `file the resolution` WITHIN 7)
        LEST  BREACH
-- Both continuation clocks start at the join's firing, the last signature (R-Q7, §5.1).
```

What this needs before it can be a golden: the `ONCE` line (R-Q1, built); the set-valued `BY` (R-T3,
**built 2026-09-15**, §6.1); and,
for shapes (1) and (2) with a continuation on the compound, a `HENCE` slot that compounds do not have
— `HENCE` is parsed only inside `obligation` (`Parser.hs:2538-2540`), so `(A RAND B) HENCE k` is a
parse error (`unexpected HENCE`; probed 2026-09-07 on the installed binary). Shape (3) puts the `RAND`
**inside** the `HENCE`, which is legal today for a single `PARTY`. **The build's `doc/` page owes this
same example** (§2.5's owed list).

### 8.4 With Pattern Matching

```l4
GIVEN parties IS A LIST OF Party
`sign in order` MEANS
    CONSIDER parties
        WHEN []          THEN FULFILLED
        WHEN (p :: rest) THEN PARTY p MUST sign
                              HENCE `sign in order` rest
```

Recursion over lists to build sequential HENCE chains. This is already expressible in L4 without new syntax.

## 9. Comparison: EVERY (Barrier) vs EACH (Fork)

### 9.1 EACH: Fork Expansion

```l4
EACH p MUST X HENCE h(p) LEST l(p)
-- Desugars to:
(p1 MUST X HENCE h(p1) LEST l(p1)) ||| (p2 MUST X HENCE h(p2) LEST l(p2)) ||| ...
```

- Each party has its own independent HENCE/LEST
- No synchronization between parties
- Blame per-party (individual accountability)
- HENCE fires as each party completes

### 9.2 EVERY: Barrier Expansion

```l4
EVERY p MUST X HENCE shared_h LEST shared_l
-- Desugars to barrier structure:
BARRIER { p1, p2, ... } MUST X HENCE shared_h LEST shared_l
```

- Single shared HENCE (fires once when ALL complete)
- Single shared LEST (fires once when barrier fails)
- Blame is the set of non-completers (collective accountability)
- Reference time for HENCE is max completion time

### 9.3 When to Use Which

| Keyword           | Semantics    | HENCE/LEST behavior          | Use Case                    |
| ----------------- | ------------ | ---------------------------- | --------------------------- |
| `EACH`            | Fork         | Fires for each independently | Individualized consequences |
| `EVERY`           | Barrier      | Fires once when all complete | All-or-nothing transactions |
| Either (no HENCE) | Distributive | N/A                          | Independent compliance      |

**Examples:**

```l4
-- Notifications for each approval (fork)
EACH director MAY approve
    HENCE company MUST notify_board WITHIN 1 day

-- Resolution passes only when all approve (barrier)
EVERY director MAY approve
    HENCE resolution passes
```

## 10. Verification

### 10.1 Complexity

For n parties:

- State space: O(2^n) completion states per barrier
- With k nested barriers: O(2^(n\*k))
- PSPACE-complete for finite instances

### 10.2 Decidable Fragments

Verification is decidable under:

- Finite party sets
- Bounded temporal depth (HENCE nesting)
- Acyclic HENCE graphs
- Discrete time with bounded horizon

### 10.3 Static Analysis

At contract analysis time, check for:

- **Deadlock**: Cyclic dependencies between barriers
- **Temporal impossibility**: Conflicting deadlines
- **Empty quantification**: Warn if domain might be empty

## 11. Implementation Notes

### 11.0 The roll call: where the cast comes from — ANSWERED 2026-09-08

**The question §4.2 left open.** The denotational semantics reads
`parties = { p | p ∈ P, pred(p) }` — a comprehension over the party type. That set is not
constructible: under the value-actor encoding a cast constructor with a payload
(`Tenant HAS name IS A STRING`) has **one constructor and infinitely many values**, and §2.2.7.5
point 5 says so in terms ("ranges over an open type and needs §2.1's `WHO member_of …` filter"). No
section of this document said how a machine gets from that filter to a list, and until 2026-09-08
nothing had to: the front end never asked.

**The ruling, and it is the only reading the language supports today.** The cast is drawn from the
**roll**: the list an `elem v xs` conjunct of the `WHO` filter names. At arming the machine reads
the filter left to right through `AND`, takes the first conjunct of the form `elem v xs` with `v`
the bound variable, evaluates `xs` to a `LIST`, and that list is the roll. Each entry is then
narrowed twice more — by the cast constructor when one is written (`EVERY Tenant t` drops a
landlord on the roll), and by the whole filter. What survives, in roll order, is the cast, fixed
from then on (R-Q6, R-T6). **A quantified obligation with no such conjunct refuses to run**, with a
message naming the spelling to add; it still parses and type-checks, so this is a run-time refusal
and not a new front-end rule.

**What decided it.** Three candidates were worked through against the tree on 2026-09-08.

1. **Enumerate the party type's constructors.** Measured: the evaluator can do this — `entityInfo`
   is in `EvalState` and `Machine.hs` already scans it for constructors at `:2375-2394`
   @ `6e9b57bb` (`:2649-2660` is a keyed lookup, not a scan, and does not support the point).
   But enumerating _constructors_ is not enumerating _inhabitants_, and
   the corpus's own casts are payload-carrying: it answers `{Tenant}`, not `{Alice, Bob, Carol}`.
   It would work only for a party type all of whose constructors are nullary, which no example in
   this document or in `doc/` uses.
2. **Discover the cast from the event stream.** Fatal for the barrier: "all who acted have acted"
   is vacuously true, so `ONCE ALL HAVE` would fire on the first event.
3. **The roll.** Every runnable example already wrote it — §2.1's `WHO elem p signatories`,
   §2.2.7.6's `WHO elem t tenants`, and the corpus's `jl4/examples/ok/every/who-filter.l4`.
   (Past tense as of 2026-09-09: §11.0.2 gave the roll its own `IN` clause, §13.5 deprecated this
   inferred spelling, and §2.2.7.6 and `who-filter.l4` have both been migrated. The argument below
   is the one that was made against the tree as it stood, and it is what `IN` was ruled from; §2.1's
   example is still in this spelling, deliberately, for the reason its own note gives.)
   Measured on the corpus at
   `6e9b57bb`: of the nine `ok/every/*.l4` front-end examples, exactly one rule
   (`who-filter.l4`'s first) carries the conjunct, which is why the new run-time examples are new
   files rather than `#TRACE` lines added to the old ones.

**The cost, stated plainly.** Three edges, all measured 2026-09-08 and all on the doc page:

- The conjunct is recognised by **spelling** — the function must be called `elem` — which is the
  device the parser already uses for `EACH` in `UPON EACH` and for `TIMEZONE`. A user-defined
  two-argument `elem` shadowing the prelude's would be taken as the roll.
- Only an `AND` chain is walked. `WHO elem t xs OR elem t ys` and `WHO NOT (elem t xs)` both
  refuse: the first has two candidate rolls and the second names who is out. Refusing is the right
  answer for the second and a real limit for the first; `append` is the workaround.
- A roll with **repeats** produces repeated members. `LIST alice, alice, bob` is a cast of three.
  Under a BARRIER one signature from Alice discharges both of her obligations, so nothing goes
  wrong beyond the group not being the size it looks. Under a FORK it is worse: the continuation
  fires once per copy, so one act earns two receipts (measured 2026-09-08). No de-duplication is
  done, because `EQUALS` on a party is a structural comparison the machine would have to run
  pairwise, and nothing in this document asks for it.

**What review should reconsider, and what it should not.** The refusal is not a placeholder: it is
the same move R-Q1 makes for a bare continuation and `CONSIDER` makes for a missing branch. What is
open is whether the roll deserves its own **syntax** — `EVERY Tenant t IN tenants` — instead of
being read out of the filter. That question was **not** ruled here, because R-Q4 fixed `WHO` as the
only filter word and a cast-source keyword is a new production, not an implementation choice. It is
put to Meng as an open question, not decided by the build.

> **ANSWERED 2026-09-08, see §11.0.2.** Meng ruled the syntax in: `EVERY Cast v IN xs` is built,
> and `IN` is the spelling to reach for. This section is NOT retracted — the inference it describes
> still runs, unchanged, for a rule that writes no `IN`. Of the three costs listed in the bullets
> ABOVE this note, `IN` avoids the first two and NOT the third: it is matched by keyword rather
> than by spelling, so no user-defined `elem` can capture it, and it needs no `AND` chain to be
> found in — but **a roll with repeats still produces repeated members**, because that is a
> property of the list, not of how the list was named. (Separately, `IN` also moves §11.0.1's
> circular-roll refusal from run time to check time.) Whether the inferred form should be
> deprecated is a further question, still open — §13.5.

### 11.0.1 What phase 2 built, and what it did not — 2026-09-08

**Built**, on `lang/every-runtime`, witnessed by `jl4/examples/ok/every/run-{barrier,fork,roll,modals}.l4`:

- the roll call (§11.0), fixed at arming (R-Q6/R-T6);
- the plain distributive form with no join line (§3.3), as the `RAND` fold this document always
  said it was — the members run over the same event stream, which is what `RAND` already means;
- the **fork** (§3.2, `UPON EACH`): each member carries its own copy of the continuation with the
  member variable bound, so `LEST BREACH BY t` names the member;
- the **barrier** (§3.1, `ONCE ALL HAVE`): `HENCE` once, anchored at the last completion and
  handed the event stream that followed it, which is R-Q7's "unanchored, `HENCE` counts from the
  join's firing" and §3.4's `t_last`;
- the join line's own `WITHIN` (R-T2): written alone, on either kind of join line, it bounds each
  act, because otherwise no member would ever expire; written alongside an act `WITHIN`, a barrier
  additionally checks it on the whole;
- all four modals under a join, including `SHANT` achieving at the deadline (§3.4's "success time
  by modal"). `MAY` is the one worth spelling out: a member who never exercises the permission has
  breached nothing, so under a barrier with **no** `LEST` the join simply never fires and the run
  reports `FULFILLED` — the same word a completed barrier gives. With a `LEST` on the join, that
  member's lapse does make the group fail. §2.2.1's Pattern B is the case this is right for, and
  the doc page says in terms that `FULFILLED` is not evidence the `HENCE` fired.
- nesting: a quantified obligation inside another's `HENCE`, armed at the outer join.

**Built 2026-09-15**, on `every/blame-set`, witnessed by `jl4/examples/ok/every/run-blame.l4` —
**§6.1's blame set (R-T3).** Until then a failed barrier named ONE non-completer, the first in roll
order, because `ReasonForBreach` carried one party (measured 2026-09-08: reversing the roll reversed
which member was named, so the choice was deterministic and it was roll order). Now `ReasonForBreach`
carries a non-empty list of FAILURES — one per failed obligation, each with its own action and
deadline or its own `BECAUSE`, no deduplication (Meng's ruling of 2026-09-15, quoted in §6.1.1); a
barrier runs every member before deciding and, with no `LEST`, names every non-completer in roll
order, anchored at the earliest failure; with a `LEST`, runs it once, anchored at the earliest
failure rather than the first in roll order; `RAND`/`ROR` carry both operands' failures; and
`BREACH BY` takes a list. §6.1.1 has the decisions, including the two this build did not make: a
barrier's own `LEST BREACH` still names whom the drafter names, and the anchor's VALUE was still
the revealing stamp until §5.2 was built on 2026-09-16 (next entry; the "Not built" bullet this
sentence used to point at is gone).

**Built 2026-09-16**, on `every/lest-anchor` (cut from `every/anchors-on-blame`), witnessed by
`jl4/examples/ok/every/run-lest.l4` — **§5.2's deadline anchor** (R-Q7's unanchored `LEST` default,
R-Q5's failure time). Until then a `LEST` continuation was anchored at the revealing event's stamp,
and this list carried it as "still owed" with the note that the phase-2 build had deliberately made
`EVERY` match the single-party path so that §5.2 stayed one change in one place. It was: the
single obligation's expiry now hands its `LEST` the missed deadline as the clock (`MUST`/`DO`/`MAY`;
a `SHANT`'s `LEST` already counted from the violation), and a barrier member — a single obligation
whose `LEST` slot holds the failpoint sentinel — carries that same reference to the barrier, so the
barrier's `LEST` counts from the earliest-failing member's deadline with no change of its own.
`THE DEADLINE` under a `LEST` and the unanchored default are one reference. The state-layer `LEST`
(`barrierStateMissed`) is now handed the events after the state deadline, not the whole stream
(the stack's round-1 finding R1-5, below). §5.2.1 has the mechanism, the decisions (a kept
`SHANT`'s `HENCE` is NOT moved and is recorded as open; so is the clock of a `LEST` under an
anchored deadline that predates its obligation's arming), the goldens that moved with one reason
each, the docs, and the clocks downstream re-pins against. Its own adversarial pass (two rounds,
the same day) replaced the at-most-once re-offer rule: an event past several `LEST` windows is now
offered to every layer in turn, unconditionally (round 1 stopped at a layer whose deadline had not
advanced; round 2 found that dropped a timely performance too), so a chain's third chance sees the
performance it was written for; the one chain that cannot end — a continuation that reaches itself
with its deadline already past — is refused by name after a bounded number of stalled hand-offs;
`THE ARMING` of a `LEST` continuation is named as a clock that moved; §5.2.1's last paragraph lists
the fourteen round-1 and four round-2 findings.

**Not built, and each one is a place a run gives a coarser answer than this document specifies:**

- **The residual of an unfinished barrier** is the outstanding members' obligations — with their
  deadlines correctly decremented, and carrying the machine's two sentinels in their `HENCE` and
  `LEST` slots (they print as `` `the join` `` and `` `the join fails` ``) — but WITHOUT the join
  line. Feeding that residual more events would run the members and not the join. Nothing in
  `l4 run` does that (a residual is the final answer), but a service that resumed a contract would
  need §11.1's `BarrierRuntime` to be a real value.
- **The performer/actor agreement check per member.** `TypeCheck.checkDeonton` said phase 2 would
  check it at run time. It does not: the machine checks that the EVENT's party is the member, which
  is a different question from whether the ACTION's own actor field names the performer. That
  comment is corrected in the same change.
- **§13.2's partial-completion visibility**, and the count and measure joins of §2.2.7.4.

**Two run-time REFUSALS this build had to add, neither of which the design anticipated.** Both are
cases the front end accepts and the run cannot answer; both are named rather than crashed on, and
both have a corpus witness.

- **A barrier's `HENCE` or `LEST` may not name the member.** §3.1 writes them `shared_h` and
  `shared_l`, and that is exactly the point: `ONCE ALL HAVE` fires once, after everybody has acted,
  so there is no member for the variable to denote. The type checker binds the variable throughout
  the rule (`TypeCheck.checkDeonton`), which is right for the fork — where each member carries its
  own copy — and wrong here. **This is arguably a front-end bug and the refusal is the run time
  compensating for it**: the better fix is for `checkDeonton` to drop the variable from scope in
  `HENCE`/`LEST` under a `JoinOnce`, which is a change to merged front-end behaviour and is left to
  review. Witness: `run-barrier.l4`'s `whose tenancy`.
- **The roll may not mention the member.** `WHO elem t (peersOf t)` type-checks and cannot be
  evaluated: the roll is read once, before there is any member. Witness: `run-roll.l4`'s
  `circular`.

**What the adversarial pass of 2026-09-08 changed, and it changed real answers.** Recorded so a
later reader knows these were found by attack, not by design:

- The barrier used to run a failing member's obligation **twice** — once to learn it had failed,
  once again with the `LEST` attached, to get the anchor and residual stream the `LEST` needed.
  Measured: two ledger writes where a single-party control produced one, and — where a member's
  `WITHIN` was itself a ledger read — a verdict of `FULFILLED` where the control said `BREACH`,
  because the second pass recomputed a later deadline. Fixed by a **second sentinel**: a barrier
  member's `LEST` slot holds a marker that reports the machine's own anchor and residual stream
  back to the barrier, which then runs the real `LEST` once. Nothing is applied twice.
- A fork's `WITHIN` on the join line was **read for no join at all**: `joinStateDue` matched only
  `JoinOnce`, so `UPON EACH WITHIN 10` with no act deadline left every member with no deadline and
  the rule could never fail. Fixed; the act deadline still wins when both are written, and the
  fork's own `WITHIN` is still not separately enforced in that case (a fork has no join event to
  check it against), which is the residue of R-T2 under a fork.
- The residual of an unfinished barrier reported each member's ORIGINAL deadline, not the
  decremented one — thirteen days out on a fourteen-day obligation with thirteen days elapsed —
  because the frame kept the pre-scan obligation rather than the residual the scan produced.

**One imprecision left in, deliberately, because fixing it needs machinery this build does not
have.** When two or more members complete at the **same instant**, the join's firing time is right
but the event stream handed to the continuation is the one belonging to whichever of them the roll
named first. So an event stamped exactly at the join can still reach the continuation — including a
tied member's own act, which then does double duty. Computing the correct stream (the shortest
suffix, or the whole stream trimmed to events strictly after the join) needs a trimming walk with
its own frames. A `SHANT` barrier ties by construction, but harmlessly: every member completes at
the same revealing event and their residual streams are identical.

**What the adversarial pass of 2026-09-15 changed, round 1** (the blame-set build, R-T3).
Eighteen findings were raised by three checkers and each put to two refuters; sixteen were
confirmed by both, two were split (SEM-7, G7), none was refuted by both, so all eighteen were
applied. Eleven were graded blocker: eight of them were one defect seen from six angles — the first
build implemented the paragraph of the brief that Meng's ruling had struck through — and one type
change discharged those eight (SEM-1, SEM-2, SEM-3, G1, G2, G3, F1, F2); the other three blockers
(SEM-4, G4, F3) were the written claims that went with it, fixed by wording. The rest are listed by
what actually changed:

- Replaced the deduplicated `NonEmpty` of bare parties beside one anchoring action/deadline with a
  non-empty list of sum-typed failures, each carrying its own detail, anchored by position; removed
  the `BreachParties` keying frame and the dedup in `BreachBy`, `RBinOp2` and `barrierFinish`
  (SEM-1, SEM-2, G1, G2, G3, F1, F2; §6.1.1, `ValueLazy.hs:105-145`). `alice RAND alice` now names
  Alice twice with each action; `BY LIST alice, bob, alice` names her twice; `explicit or deadline`
  no longer prints Alice as having had to `deliver`.
- Made the wire's scalars describe the anchor rather than the head, so `obligatedParty` /
  `obligationAction` / `deadline` are one obligation again (as on `e578654c`); added `failures` and
  `anchor` beside `obligatedParties` / `parties`, on `batch --json`, jl4-service and the jl4-mlir
  mirror (SEM-3, G3, F2). The deviation from the brief's "the head" is recorded in §6.1.1.
- Replaced the printed plural — bare parties under one action and deadline — with one entry per
  failure, each with its own detail; re-blessed and read `deontic-breach-semantics.golden` and
  `run-blame.golden` (G2, G3).
- Removed the claim that a compound's `BECAUSE` is "the side lost first / lost last" from
  `several-parties.md`, `what-follows.md` and the skill's `regulative.md`: with a `BECAUSE` on both
  sides neither carries a time, so it was always the left for `RAND` and the right for `ROR`. Each
  entry now carries its own `BECAUSE`, so the question no longer arises; the docs say what the
  anchor decides (the date) and what it does not (SEM-4, G4).
- Restored `BREACH BY <list>` for a rule whose party type is itself a `LIST`, which the first build
  had given up: a `BY` expression of exactly the party's list type is one party, wrapped as a
  one-element list for the machine; a `BREACH` checked against a known `DEONTIC` type unifies with
  it before reading the `BY`; a mismatch is reported against `BREACH BY` (SEM-5; witness
  `run-blame.l4` `the pair delivers`).
- Recorded that every barrier member is now run after an earlier failure, so a later member's
  error becomes the verdict where it used to be masked (SEM-6; §6.1.1, `barrierFinish` docstring,
  EVERY.md).
- Refused a literal empty list in `BREACH BY` at check time (`BY EMPTY`, `BY (LIST)`), keeping the
  run-time refusal for a computed list; witness `not-ok/tc/breach-by-empty.l4` (SEM-7 — one
  checker refuted it as beyond the brief, the other confirmed it as a loud-over-silent gain the
  brief neither required nor forbade; applied).
- Corrected §6.1.1's account of the brief ("left open", "scalar-plus-array the brief required")
  and recorded Meng's sentence verbatim, dated (F3).
- Corrected the R-T3 row's golden count to eight at `e578654c` and nine on this HEAD, by a command
  that reproduces it (G5); counted the `.ep.golden` twin among the goldens that moved (G6).
- Reworded "ordering by stamp orders by the missed deadline" to "up to ties" and said that the
  ordering key is the sentinel's anchor, so §5.2 cannot desynchronise them (G7 — one checker
  refuted the failure scenario, the other confirmed the over-sharpening; the wording changed, the
  ordering did not).
- Added `LEST BREACH BY LIST …` to the regulative README's BREACH syntax and examples (F4).

Raised and refuted by both checkers: none.

**What the adversarial pass of 2026-09-15 changed, round 2** (on round 1's HEAD `879a27ed`).
Eight findings were raised by two checkers — six against the landed fix, two fresh — and each put
to two refuters; all eight were confirmed by both, none refuted by both, all eight applied. Two
were graded blocker (the skill's date sentence, and the checker's order-dependent `BREACH BY`
reading), the rest minor:

- Refused a LIST after `BREACH BY` whose party type is not yet ground — a definition with no
  `GIVETH`, or the left operand of a `RAND`/`ROR` in one — at the `BREACH`, naming the two fixes
  (`BreachByListNeedsPartyType`), instead of pinning the party type to the element type and failing
  at the use site; the same `RAND` had passed with its operands swapped, and the no-`GIVETH`
  list-typed party that type-checked at `e578654c` had been rejected with a `HENCE` mismatch. Made
  `RAND`/`ROR` push a known `DEONTIC` type into both operands (`checkRegulativeBinOp`), so under a
  `GIVETH` the party type reaches either operand and the refusal's advice is true. Witnesses
  `not-ok/tc/breach-by-list-needs-party-type.l4` (both refused shapes) and `run-blame.l4`
  `the pair, breach first` (the `GIVETH` + `RAND` shape, accepted). Corrected `TypeCheck.hs`'s
  "falls to the scalar reading" comment, §6.1.1's unqualified "restored", BECAUSE.md and the
  build notes; the deferral that would accept the no-`GIVETH` shapes is recorded in §6.1.1 as not
  built (R2-TC-1).
- Reported a `BREACH BY <list>` mismatch with the list's own type as the given type, matching the
  whole-list range the error carries (R2-TC-2).
- Replaced the plural print header `revealed the breach of` — which put every entry under the
  revealing event's stamp although that event revealed only the anchor — with the anchor in the
  singleton's own six lines followed by `and the breach names, in order` over every entry; re-blessed
  and read `run-blame.golden` and `deontic-breach-semantics.golden`, re-pasted EVERY.md's example
  and this section's "Printing" (r2-blame-4).
- Reworded the skill's "dated at the side lost first/last" to the machine's rule: earlier/later
  stamp when both sides carry one, else simultaneous with the CSL tie-break — false before for a
  mixed missed-deadline/declared pair, in both orientations (r2-blame-1).
- Reworded EVERY.md's "dated at the earliest missed deadline" to "anchored at the member whose
  deadline was missed first, and dated at the event that revealed it" — the golden prints `at 8`
  against Carol's deadline of 5 (r2-blame-6).
- Corrected the round-1 count above from "eight blockers" to eleven, eight of them one defect, and
  "each refuted by two more" to "each put to two refuters" (r2-blame-2, r2-blame-5).
- Re-ran the golden suite on a binary newer than every source: round 1's second run had started
  before the last `Machine.hs` edit, so its 0 failures measured the tree one edit early
  (r2-blame-3; the build notes say so).

Raised and refuted by both checkers, round 2: none.

**A defect found on the way, and fixed here because the fork's own example needs it.** `EXACTLY e`
in the **second or later** argument of an action pattern raised `is not in scope` at run time.
`PatApp0` handed the ambient environment to the first sub-pattern and `PatApp1` then handed each
later sub-pattern the environment the PREVIOUS sub-pattern had produced — its bindings, not the
scope it was written in. The sibling `FOLLOWED BY` frames (`PatCons0`/`PatCons1`) always carried
the ambient environment separately. Nothing about it is quantifier-specific: reproduced with a
plain `PARTY alice MUST Pay payer (EXACTLY theLandlord)` on the 2026-08-27 installed binary, which
predates every line of this branch. It blocks any RUN of §2.2.7.6's own rent example, and of the
shape `fork.l4` writes (`Receipt (EXACTLY theLandlord) (EXACTLY t) (EXACTLY amount)`) — `fork.l4`
itself carries no directive at `6e9b57bb`, so it was never red, which is how the defect survived.
Witness: `jl4/examples/ok/regulative-exactly-later-argument.l4`.

#### Built 2026-09-15 — the anchored `WITHIN` (R-Q7A/B/C, §5.1.1), on `every/anchors`

**Built**, witnessed by `jl4/examples/ok/every/run-anchors.l4` (the mechanism and every decision
are in §5.1.1.1; this is the ledger entry):

- the grammar `WITHIN d [OF anchor]` in both positions, the act's and the join line's, with `OF`
  read as the anchor in the duration slot and as application everywhere else;
- the three lifecycle anchors `OF THE JOIN`, `OF THE DEADLINE`, `OF THE ARMING`, matched by
  spelling, naming the nearest enclosing obligation's join, deadline and arming — the obligation
  the continuation is attached to when it runs — through the single-party hand-offs, the
  barrier's `HENCE` (state deadline when the `ONCE` line has one, else the latest of the members'
  act deadlines; an empty cast joined at its arming), the barrier's `LEST` (the failing member's
  deadline — the earliest-failing member's once stacked on R-T3, see "Stacking B on C" below —
  or the state deadline when that is what was missed), the fork (each member's own),
  the demoted join-line deadline, and a continuation handed on as a value;
- the expression anchor, `NUMBER` or `DATE`, the latter lowered by its serial; a deadline already
  past at arming is revealed by the first event;
- five check-time refusals, each with a `not-ok/tc/` witness, and two run-time refusals with
  witnesses in `run-anchors.l4` (refusal 6: `nobody, act deadline only`; refusal 7: `handed
under a LEST`, `handed under a LEST, in a compound`, `handed to no WITHIN` — the second round
  added these three; round 1's ledger claimed both were witnessed when only 6 was); the
  `Lifecycle` bindings under unspellable uniques, replaced
  whole at every hand-off and rebound into the continuation's value; the arming kept on every act
  frame; the sentinels' extra argument, the member's deadline (their third here; the fourth since
  the stack's round 1 put the stream position before it — §11.0.1 "Stacking B on C"); the
  barrier's running maximum of member deadlines;
- all four printers (exactprint byte-identical, `prettyLayout` round-tripping, NLG, document
  export), the MLIR schema failing closed, LSP highlighting, the service's residual string;
- `doc/reference/regulative/README.md`'s `WITHIN` section rewritten with examples that check
  (`within-example.l4`), `EVERY.md`'s "Anchored deadlines under a join", and the
  `writing-l4-rules` skill's three copies of the "does not parse" claim corrected.

**Not built**, each named in §5.1.1.1's last paragraph: `AFTER` (built 2026-09-16 by its own
track, §5.1.2's build block and the entry below); §5.2's `LEST` default (built
2026-09-16 by its own track, §5.2.1); T1's epoch
and sorts (so the floating-origin/date-serial confusion is a stated limit, not a check — since the
`AFTER` track, a run-time refusal on a clock below `DATE_SERIAL (YMD 1 1 1)`); §5.1.3's
expression-over-trace slot; `THE OPENING`; `SOME m OF`; a way for a deep continuation to name a
non-nearest obligation's arming.

**Existing goldens.** No eval, exactprint, NLG or schema golden of a parseable corpus file moved:
the track adds syntax and touches no default. Two candidate regressions found on the way were
withdrawn before commit — a partial-constructor arm in `App1`, which turned `FULFILLED` applied to
`[time, events]` into `FULFILLED OF 4, EMPTY` in seventeen eval goldens, together with the
sentinel-as-application it served; and a `Deadline` printer that bracketed the duration in the
state graph's label, which moved the `regcf-resale` BPMN goldens. Two parse-error goldens were
re-blessed by one token each: `not-ok/tc/every-join-misindented.{golden,ep.golden}` and
`…-barrier.{golden,ep.golden}` list the tokens that may follow `WITHIN 14`, and `OF` is now one
of them. That is the parser telling the truth about the new grammar; hiding the alternative
(megaparsec's `hidden`) would have kept the goldens and made the message lie, and was not done.
A reviewer who reads rule 6 more strictly can reverse it with one `hidden` in
`L4.Parser.anchor`.

**What the adversarial pass of 2026-09-15 changed.** Eighteen findings were raised (seven on
semantics, five on golden/spec drift, six on completeness; two pairs of them duplicates), each
put to two independent refuters; none was refuted by both, so every one was applied or answered.
In §5.1.1.1's terms:

- Made the enclosing obligation dynamic at the hand-off: the `Handoff` frame rebinds the
  `Lifecycle` into the continuation's value, so a continuation passed as a `DEONTIC` parameter or
  factored into a `WHERE` anchors to the obligation it is attached to (`OF THE JOIN` ≡ the
  unanchored default again; witnesses `handed on, the join` / `the deadline`, `factored out`).
- Made `bindLifecycle` delete a position the hand-off lacks instead of leaving the outer binding
  in place (an empty-cast barrier's `HENCE` nested under a `WITHIN 10` read 15, exit 0; witness
  `nobody, act deadline only`, now a named refusal).
- Routed an empty cast through the `ONCE` line's `WITHIN` (`BarrierEmpty`, `barrierJoined`; witness
  `nobody, bounded as a whole`, 35) and rewrote `lifecycleRefusal` so it names the empty cast and
  the handed-on-value cases instead of asserting the rule is "not inside any HENCE or LEST".
- Replaced the barrier `HENCE`'s "last completer's act deadline" with the latest of the members'
  act deadlines (`dueLatest`, `Barrier2b`), so a same-stamp tie no longer flips the verdict with
  the roll's order (witness `per member`, three traces).
- Corrected the barrier `LEST` sentence in `EVERY.md`, in this section and in the `Lifecycle`
  haddock to "the deadline actually missed" (witnesses `the tenancy, a member late`, 19, and
  `the tenancy, the group late`, 35).
- Widened the "`OF` is the anchor" statement to the whole unbracketed duration (README, this
  section, the skill), named `jl4/experiments/jerseyCharities2-annual-returns.l4:214` as the one
  pre-existing `WITHIN f OF x` in the tree (a file that never parsed), and gave the checker an
  anchored-duration mismatch wording (`ExpectAnchoredDurationContext`) that says how to bracket.
- Reworded the `NoEnclosingObligation` refusal to say "not WRITTEN inside any HENCE or LEST — at
  the top level, or in a WHERE" (golden `anchor-top-level-join` re-blessed).
- README, and the skill's two copies (`references/regulative.md`,
  `source-patterns/04-dates-and-periods.md`): `THE` is a keyword, not matched by spelling; the
  undefined-`days` failure mode stated for both branches (checker error with no mixfix in scope,
  parser error with one — the finding's unconditional "parse error" was refuted by one refuter
  and the sentence now says what selects);
  the nearest-reach limit of `THE ARMING` on the `of this agreement` example; the kept-`SHANT`
  join; the two run-time refusals. `EVERY.md`: the act-line/join-line `OF THE ARMING` contrast on a
  nested `EVERY`, the join-line `OF e` evaluation time, the empty cast, the tie bullet.
- This section: the `.ep.golden` sentence qualified (two parse-error goldens did move); the `THE
FOO` message quoted verbatim, `…, or space token`; the unit-word measurement qualified by what is
  in scope.
- `jl4/examples/lsp/semantic-tokens/anchors.l4`: the barrier `HENCE` no longer names the member
  `t` (a shape the run refuses); golden re-blessed.

Raised and NOT changed, with the reason: binding `THE ARMING` on a nested `EVERY`'s act line to
the `EVERY`'s own arming (both refuters: it contradicts the nearest-enclosing rule and
`EVERY.md`'s "as on a `PARTY` rule in the same place"; a doc sentence was added instead);
binding a kept `SHANT`'s join to its deadline (it would part `OF THE JOIN` from the unanchored
clock, which §5.2's track owns; documented instead — that track, 2026-09-16, moved the `LEST`
clock only and left this open to Meng's ruling, §5.2.1); resetting the `OF`-is-anchor flag inside
`IF`/`WHERE`/operand positions of the duration (the whole-slot rule is the simpler statement and
the bracketing fix is one keystroke; documented, and the checker now names it); making the
`unexpected OF` parse error inside an unclosed `IF` list `OF` (megaparsec reports what the open
production expects; not attempted). Raised and refuted by both refuters: none.

**What the second round of the adversarial pass (2026-09-15, on the round-1 tree — `f2ba534d`
before the rebase onto `origin/unstable` `0b640727`) changed.** Nine
findings were raised (seven on the round-1 fixes as landed, two fresh attacks), each put to two
independent checkers; none was refuted by both, so every one was applied. In §5.1.1.1's terms:

- Handed each operand of a compound off when the compound is applied (`operandHandoff` in
  `App1`'s `ValROp` arm and in `RBinOp1`; `lifecycleOf` reads the lifecycle back from the
  compound's environment), so a continuation that arrives as a VALUE inside a `RAND`/`ROR`
  anchors to the obligation the compound is attached to, as it already did outside one. Round 1's
  "`ValROp` captures the environment for both operands" was false for a value operand (`HENCE (k
RAND …)` read 8 for 55, 15 for 108; a `WHERE` local in a compound kept its own arming; `LEST (k
RAND …)` with `OF THE JOIN` ran silently where `LEST k` refused — all exit 0). `rebindLifecycle`
  no longer recurses into operands; a value operand (a fork's members, a residual) is left alone
  on purpose. Witnesses `handed on, in a compound, the join` / `the deadline`, `handed on, either
way`, `factored out, in a compound`, `handed under a LEST, in a compound`; README, `EVERY.md`,
  this section, the `Machine.hs` and `ContractFrame.hs` haddocks corrected.
- Struck "the run time is now MORE permissive than the checker, never less" from the threading
  paragraph: refusals 6 and 7 are programs the checker admits and the run rejects, the opposite
  direction; the paragraph now says what the rebinding does (adds bindings) and does not (widen
  what the checker admits).
- Added refusal-7 witnesses to `run-anchors.l4` (`handed under a LEST`, `handed to no WITHIN`,
  and the compound one), so the ledger's "two run-time refusals with witnesses" is true; it was
  not — only refusal 6 had one.
- Rewrote the `kept, the deadline` witness so its trace is in time order and its comment names
  the event that actually reveals the kept prohibition: the events were authored `Sign AT 30,
Deliver AT 14`, the machine stable-sorts a trace by `AT`, so the delivery at 14 was itself the
  revealing event and Bob's signature was never reached; the golden's 13 was right, the comment's
  "Bob's signature at 30" was not. The trace now carries the delivery alone.
- Qualified "an empty barrier fires its `HENCE` at its arming" (`EVERY.md`, twice; this section):
  the empty cast goes through the `ONCE` line's `WITHIN` like any join, so an anchored state
  deadline that lies before the arming sends it to the `LEST` (measured: `WITHIN 5 OF 0` armed at
  10, `LEST … WITHIN 3 OF THE DEADLINE` reports 8). Recorded as a build decision open to ruling.
- README: the `WITHIN` summary row and the `BEFORE` section no longer call `WITHIN` relative-only
  (four sentences, `:29`, `:49`, `:477-491` on the round-1 tree, untouched by both earlier commits,
  contradicted the rewritten section's "anchored, the deadline is absolute").
- This section: `§2.4`'s `checkAnchor` cite moved from `TypeCheck.hs:2023` (a haddock line since
  round 1) to `:2029`; the `WITHIN 1 PLUS twice OF 3` measurement says what it is in each context
  (an overload error with `IMPORT prelude`, a plain `__PLUS__` mismatch without — one checker
  refuted the finding's "type mismatch" as equally context-bound, and the sentence now says both);
  round 1's ledger credits the undefined-`days` two-branch text to the skill's two copies as well
  as the README.

Raised and refuted by both checkers in round 2: none.

#### Built 2026-09-16 — the window's two edges (R-X5, R-X5 amended, R-X6; §5.1.2), on `every/after-before`

**Built**, witnessed by `jl4/examples/ok/every/run-after.l4` (the mechanism and every decision are
in §5.1.2's build block; this is the ledger entry):

- the keywords `AFTER` and `BEFORE`; the grammar `AFTER d [OF anchor]` \| `AFTER date` for the
  opening edge and `WITHIN d [OF anchor]` \| `BEFORE date` for the closing edge, in one order,
  on the act line only (the join line takes no `AFTER`; a `BEFORE` there is refused by name);
- the type-directed checks: a `DATE` after `WITHIN` and a `NUMBER` after `BEFORE` refused naming
  the other word, an anchor on `AFTER date` refused, a non-instant after `AFTER` refused naming
  both, the literal empty window refused where the `AFTER` cannot open before the `WITHIN`'s
  anchor (the same noun; a bare `AFTER` against `THE ARMING`, `THE JOIN` under `HENCE`, `THE
DEADLINE` under a `LEST` other than a `SHANT`'s — never under `HENCE`, a `SHANT`'s `LEST`, or
  `OF e` — and the last two only for a deonton that is the continuation it is written in, not
  a value handed to a function), a
  second closing edge a parse error naming the one-edge rule, the anchor refusals of §5.1.1.1
  applied to an `AFTER`'s anchor with the keyword substituted in the wording;
- the machine: the opening resolved once at the first event, before the closing edge; the bare
  `WITHIN` re-anchored on the opening (R-X5 amended), the anchored one on its anchor, a
  `BEFORE` absolute; the remaining due measured from the opening while it is ahead, so the
  residual prints as the window it is; `AFTER` alone as a window that never closes; the early
  act at `Contract10` as a nullity with a note, for every modal (R-X6); the opening threaded to
  fork and barrier members, and a demoted join-line deadline kept on the arming beside a
  member's `AFTER`; a run-time note for the empty window the checker could not see;
- the notes channel: `EvalState.notes`, `EvalDirectiveResult.notes`, printed after the value and
  only when non-empty by the goldens' printer, `l4 run` (text and `--json`), `l4 batch --json`,
  `L4.API`, the LSP diagnostic and inspector, and the REPL — NOT by the decision service, which is
  owed (§5.1.2.0's channel paragraph); one note per directive, keyed on the sentence, so two
  obligations that print one sentence share a note;
- the T1 decision: a date on either edge, and on a `WITHIN`'s anchor, refused by name when the
  obligation's clock at arming is below `DATE_SERIAL (YMD 1 1 1)`; the remaining limit (a floating
  trace at 365 or above) on the doc page in one sentence;
- all four printers (exactprint byte-identical, `prettyLayout` round-tripping, NLG, document
  export), the state graph's label and the BPMN fidelity note, the MLIR schema failing closed,
  LSP highlighting, the service's `opens` key;
- `doc/reference/regulative/AFTER.md` with `after-example.l4`, linked from `doc/SUMMARY.md` and
  the regulative README; the README's `WITHIN` section, its `BEFORE` section rewritten to what
  shipped, `EVERY.md`'s "What runs today", the concepts page's `BEFORE` sentence, and the
  `writing-l4-rules` skill's three copies of the "no `BEFORE`" claim corrected;
  `jl4/experiments/purchase.l4` migrated.

**Not built**: T1's `COMMENCING` and sorts (§5.1.2.1); a join-line `AFTER`; backward windows from a
future event; `THE OPENING` (declined); `SOME m OF`.

**Existing goldens.** None moved in the build (§5.1.2's build block says which two moves were
avoided and how); the adversarial pass re-blessed one on purpose, `anchor-no-deadline.golden`
(its message now names `BEFORE` beside `WITHIN`).

**What the adversarial pass of 2026-09-16 changed.** Round 1: twenty findings raised by three
refuters, none refuted by both checkers, all twenty applied — the list, one line each, is at the
end of §5.1.2's build block ("What the adversarial pass of 2026-09-16 changed"). The two that
mattered: the empty-window check refused open windows (a bare `AFTER` was compared against any
anchor; now only against an anchor its clock cannot precede), and `l4 run --json` dropped the R-X6
note (now a `"notes"` array). The decision service still does not carry the note, and says so.
Round 2: eight findings (four on the round-1 fix as landed, four fresh), none refuted by both
checkers, all eight applied — the list follows round 1's in the same place. The one that
mattered: the empty-window check read the slot a deonton was WRITTEN in, and refused a window
handed as a value into a `SHANT`'s `LEST` that the machine runs open; now a deonton that is an
argument or a local is compared against nothing but `THE ARMING` (`EnclosingObligation.direct`).
The other three fresh ones were wording: the note for an `AFTER` date beside an anchored `WITHIN`
called the date an offset; the early-act note in an empty window promised a window that never
opens; and "distinct facts stay distinct" promised more than a sentence-keyed dedup can deliver
(the key is unchanged; multiplicity in the note is a ruling, invited).

#### Stacking B on C (2026-09-16) — `every/anchors` rebased onto `every/blame-set`, branch `every/anchors-on-blame`

Witness `jl4/examples/ok/every/run-stack.l4`. Line numbers in this block are on the branch at the
commit that applies round 1 of its adversarial pass (subject `lang(every): apply round 1 of the
stack's adversarial pass …`, `b8a14d39`; its ledger is the second-to-last paragraph of this
block); round 2's commit (the last paragraph) touched `Machine.hs` and `ContractFrame.hs` by two
haddock edits with the same line count as the text they replaced, so every cite here reads the
same on either commit; the earlier stacking commit's numbers were superseded by round 1 and are
not repeated. B is the anchored `WITHIN` (three commits, this
section's block above); C is the blame set (§6.1.1, three commits). Both were cut from the same
`origin/unstable` (`0b640727`) and both rewrote the barrier's failure path, so `git rebase --onto
<C's HEAD> origin/unstable` conflicted in three files: `Machine.hs` (the `Barrier1` failpoint
arm, `barrierFinish`, `barrierFail`'s signature and haddock, the `Contract5` breach line,
`startBarrier`'s frame literal, and the `Barrier2`/`Barrier5` region at B's round-1 commit),
`ContractFrame.hs` (both tracks' new frame records, at B's round-1 commit) and `EVERY.md` (the
"What runs today" section, three hunks). Ten more shared files auto-merged in disjoint regions
(`Syntax.hs`, `ValueLazy.hs`, `TypeCheck.hs`, `TypeCheck/Types.hs`, `Print.hs`, `README.md`,
`Backend/Jl4.hs`, the skill, this spec) and were read; the merged tree built clean under
`-Werror` at the first attempt, before any repair.

**How each hunk was resolved — both intents kept.** The `Barrier1` failpoint arm matches the
sentinel with B's `sentinelArgs` (at the stacking commit two or three arguments; since round 1
three or four, the stream position added — below) and pushes C's `Barrier5` frame, now carrying
the sentinel's last argument, the member's absolute deadline
(`Machine.hs:1848-1851`; `BarrierFailStampFrame.dueRef`, `ContractFrame.hs:484`). `Barrier5`
forces the anchor as C had it and the chain ends in a `BarrierFailedAt` that carries B's deadline
reference beside C's anchor (`failDueRef`, `ContractFrame.hs:445`). `barrierFinish` keeps C's
shape — failures first, `earliestFailure` picks one, `lapsed` → `FULFILLED`, then pending, then
the join — and hands `barrierFail` the CHOSEN failure's anchor, residual and deadline
(`Machine.hs:2572`); its join tail is B's round-1 `barrierJoined` with `dueLatest`
(`Machine.hs:2652-2661`), and the `tLast = Nothing` arm is B's internal error, which C's
`lapsed` flag keeps unreachable (C's `Barrier1` records a lapsed `MAY` instead of returning it, so
without the flag an all-`MAY`-lapsed barrier would reach this arm with no completion; on both
parents a lapsed `MAY` fell through `Barrier1`'s catch-all and returned the barrier at once, never
reaching the join tail — an earlier version of this sentence said it "no longer returns through
the join tail", which described a history that did not exist). `barrierFail` has B's
four-argument signature and C's haddock about what the `LEST` names (`Machine.hs:2711`).
`startBarrier`'s frame literal has both tracks' fields (`dueLatest`, `failures`, `lapsed`;
`Machine.hs:2501-2502`). The `Contract5` breach line is C's `singleBlame` form with B's
`reofferResolve False` (`Machine.hs:1699-1700`). `ContractFrame.hs` keeps all four
new records (`BarrierFailStampFrame`, `BreachByFrame`, `BarrierDueFrame`, `BarrierEmptyFrame`).
`EVERY.md`'s "Runs" list is B's three widened bullets followed by C's blame bullet; its "coarser
than it looks" list is C's corrected `LEST BREACH` bullet (B's copy still said R-T3 was unbuilt)
and the clock bullet with B's `OF THE DEADLINE` workaround sentence appended.

**The interaction, as measured** (probe `probes/interaction.l4` in the session scratch, then the
witness; binary built from this tree, `JL4_LIBRARY_PATH` pinned to its own libraries). C decides
WHICH failure a barrier's `LEST` is anchored at — the earliest by R-Q5's act layer (a member's
expiry lands there even when the `ONCE` line also has a `WITHIN`: R-Q5's state-layer sentence
applies, as built, only when the group completes late — see the note under R-Q5 and §5.1.1.1's
`LEST` paragraph), `earliestFailure` (`Machine.hs:2619-2641`) — and B decides what `THE DEADLINE`
reads inside that `LEST`. Stacked,
the rule is: **`THE DEADLINE` under a barrier's `LEST` is the act deadline of the member whose
failure the `LEST` is anchored at — the earliest failure — and it is order-independent.** Measured,
with Carol last on the roll and due at 5, Bob due at 14, Alice signing at 1:

- a `LEST … WITHIN 5 OF THE DEADLINE`, Carol's miss revealed at 8 and Bob's at 20: the refund is
  due 5 + 5 = **10** on `LIST alice, bob, carol` and on the reversed roll (timely at 10, `BREACHED`
  reporting 10 at 11). Were it the first non-actor on the roll (Bob, 14) the refund would be due 19
  and both refunds timely.
- a **tie** — both misses revealed by one `WAIT UNTIL 20` — is where the two tracks' rules pulled
  apart. C's tie-break was roll order, harmless for C **for `MUST`/`DO`/`MAY`** because there a
  stamp tie is the same revealing event, so the anchor and the residual are the same
  member-for-member (NOT harmless for `SHANT` — round 1, below); B reads a deadline from the
  chosen member, and the merged tree as first resolved reported **19 on `tenants` and 10 on
  `tenants, reversed`** for the same events. Fixed at the stacking commit by a second ordering
  key: a tie on the anchor is broken by the deadline missed (`BarrierFailedAt.failDue`, forced by
  the `Barrier5b` frame, `Machine.hs:1915-1918`, `ContractFrame.hs:99`; `earliestFailure`,
  `Machine.hs:2619-2641`), and roll order breaks only a tie on every key, which then names the
  same deadline either way. After the fix: **10 on both rolls.** C's two invariants stand: the
  `LEST` fires once, and the anchor's value is still the revealing event's stamp (20) — until
  2026-09-16, §5.2.1; the anchor is now the failure time, Carol's deadline 5, and the two misses
  no longer tie on the first key at all (`run-stack.l4` §3's rewritten comment).
- a `SHANT` barrier: Carol smokes at 3 (R-Q5's failure time), Bob at 10; the `LEST` is anchored at
  Carol's violation and `THE DEADLINE` is her window's end, 5 (what a single `SHANT`'s `LEST` is
  handed): refund due **10**, both rolls. The primary key stays the anchor because for `SHANT` the
  deadline is not the failure time — and the deadline does not order `SHANT` failures at all: Bob
  (window 14) smoking at 2 and Carol (window 5) at 4 anchors at Bob, refund due 19, both rolls
  (round 1 probe `R1-2-shant-order.l4`; `run-stack.l4` §4 cannot show this, since there stamp
  order and window order agree). The keys cannot disagree between a `MUST` and a `SHANT` member of
  one barrier, since a barrier's members share one modal.
- a `RAND` of two anchored continuations both breached (`WITHIN 5 OF THE DEADLINE` → 15, `WITHIN 3
OF THE JOIN` → 7, both revealed at 20): C's compound anchors at the left operand and names both
  entries, each with the deadline B's `Contract5` computed (`Machine.hs:1608`): **15, then 7**.

**Goldens.** New: `ok/every/tests/run-stack.{golden,ep.golden,nlg.golden,schema.golden}` (read;
the `.golden` carries exactly the ten numbers above, since round 1 the five of §4b below, and
since round 2 the nine of §3b/§3c — the same shapes for `MAY` and `DO`).
Moved, and NOT a resolution error:
`ok/every/tests/run-anchors.golden`, one block — B's fork witness `receipts` (both landlord
deliveries breach at 17) now prints `and the breach names, in order` with two entries at 16, which
is C's blame list on a `RAND` of per-member obligations (the landlord twice, once per receipt: no
dedup, RULED 2026-09-15); the anchor and its deadline (16) are unchanged, and the source comment
was extended in place (`run-anchors.ep.golden` moved with it). Nothing else moved: the first
`cabal test jl4-test` run reported exactly those five (four created, one moved), 3182 examples.

**Not verified here.** The full `etc/verify-branch.sh` (the `--quick` gate and `jl4-test` were
run); the §3.2.1 evaluation differential (neither track's `Print.hs` change touches
`prettyLayout`'s module printing, and neither stacking commit touches a printer); a barrier whose
members have no `WITHIN` at all under a `LEST` (`failDue` is `Nothing` for every member, so the
deadline key never applies; since round 1 the stream key still does, and roll order decides only
a same-event tie, as it did on C alone). This branch is the drop-in for `every/anchors` ONCE
`every/blame-set` has merged; if B lands first instead, this branch is not the one to use.

**Round 1 of the adversarial pass (2026-09-16) — what it found, what was applied.** Two refuters
voted on each finding; every finding below was confirmed by both. Raised and refuted by both:
none.

- **A same-stamp `SHANT` tie was broken by the window's end (stack) or the roll (C), not by the
  stream — a timely reparation vanished and the verdict flipped.** BLOCKER, applied. For `SHANT`
  the sentinel's anchor is the member's own violating event's stamp (`Contract10`'s `DMustNot`
  arm, `Machine.hs:1744-1748`), so two members violated at one stamp by two events are two
  failures with two DIFFERENT residual streams; the stacking commit's premise that "a tie is the
  same event, hence the same anchor and the same residual" was `MUST`-shaped and false for
  `SHANT`. Measured before the fix (probe `B-shant.l4`): Bob smokes 3, the landlord refunds 3,
  Carol smokes 3, `WAIT UNTIL 20`, `LEST … WITHIN 5 OF THE DEADLINE` → `BREACHED` at 20 reporting
  10 on BOTH rolls — Carol chosen by her window end (5 < 14) although Bob's violation was first in
  the stream, and the refund that followed it dropped from her residual; with Alice and Bob (both
  window 14) and the refund between them, `FULFILLED` on `tenants` and `BREACHED` at 19 reversed —
  the roll deciding, on a branch that claimed order-independence. On C's own binary the Bob/Carol
  shape (`H-shant-C.l4`: Bob 3, refund 3, Carol 3, with an unanchored `WITHIN 5` — the only shape
  run on C's binary; the Alice/Bob shape was run on the stack's binary only) was already `FULFILLED` /
  `BREACHED` by roll, so "harmless for C" was false as measured, and the stack's deadline key had
  turned C's `tenants` verdict from `FULFILLED` to `BREACHED`. **The fix:** the scan counts the events it takes
  (`ScrutinizeEvents.seen` and the eleven records it is threaded through, `ContractFrame.hs:134`
  … `:302`; `seen = 0` at the arming, `Machine.hs:1129`; `seen + 1` at `Contract1`,
  `Machine.hs:1540-1545`; carried through `ResolvePartyFrame.seen`, `ContractFrame.hs:551`), the
  hand-off gives a barrier sentinel that position as its third argument, before the deadline
  (`continueWithFollowup`, `Machine.hs:2128-2137`; `sentinelArgs`, `Machine.hs:2458-2462`), the
  new `Barrier5c` frame forces it between the anchor and the deadline (`Machine.hs:1900-1918`;
  `BarrierFailPosFrame`, `ContractFrame.hs:490`; `BarrierFailedAt.failPos`, `ContractFrame.hs:435`),
  and `earliestFailure` orders a stamp tie by the stream position before the deadline
  (`Machine.hs:2619-2641`): only the same event ties the position, so the deadline key applies
  exactly where the stacking commit meant it to — two deadlines one event revealed — and roll
  order only where every key ties, which then names the same anchor, residual and deadline either
  way. Witness: `run-stack.l4` §4b (five traces): the dropped-refund shape is now `FULFILLED` on
  both rolls; Bob 3 / Carol 3 / refund 11 → `FULFILLED` (`THE DEADLINE` is Bob's 14, refund due
  19), refund 20 → `BREACHED` reporting 19 on both rolls. `H-shant-C.l4` on the round-1 binary:
  `FULFILLED` on both rolls. Every `MUST` case is unchanged: `probes/interaction.l4` is identical
  to the stacking commit's run, and `run-anchors`, `run-blame`, `run-barrier`, `run-fork`,
  `run-modals` are byte-identical to it. A design choice the reviewer may reverse: the ruling
  R-Q5 fixes only the failure TIME, and no ruling addresses two violating events at one stamp; the
  stream is the key chosen because it is the only one under which the `LEST`'s residual is the
  true residual after the earliest failure (the alternatives — window end, roll — both hand the
  `LEST` a stream with events before the chosen failure cut out). The no-`LEST` path
  (`BarrierBreached`) has no residual to hand on and carries no position; a same-stamp tie there
  still falls to roll order, which decides only which failure is the anchor of a breach that names
  every failure regardless.
- **The written claim "a tie is the same event, hence the same anchor and the same residual" /
  "harmless for C" was unqualified and false for `SHANT`.** BLOCKER, applied: the `barrierFinish`
  haddock (`Machine.hs:2529-2554`), the `BarrierFailedAt` haddock (`ContractFrame.hs:451-463`),
  §6.1.1's with-a-`LEST` bullet, the tie bullet above, `EVERY.md` (the "Inside the continuation"
  barrier bullet, the `LEST` paragraph, the blame-set bullet under "Runs") now scope the
  same-event reasoning to `MUST`/`DO`/`MAY` and state the `SHANT` rule as built. The
  `barrierFinish` haddock's "orders by the missed deadline UP TO TIES" (a separate finding, minor)
  is scoped the same way, with the measurement that the window end does not order `SHANT`
  failures.
- **§5.1.1.1's and §6.1.1's `file:line` cites are stale on this branch while their headers
  asserted currency** (raised twice, as minor and as major). Applied as one sentence per header,
  not a re-cite: §5.1.1.1's numbers are on `82c61419`, §6.1.1's on `cedbf7e6`, each header now
  says so, says the numbers are NOT current here, and points at this block for live cites. A
  re-cite would go stale at the next commit that touches `Machine.hs`; a sha does not. (The
  `Parser.hs` cites in §5.1.1.1 happen to hold here, as one refuter measured; the header says so.)
- **Two `earliest failure` tie rules in one tree: a barrier breaks a stamp tie by the stream and
  the deadline, `RAND`/`ROR` by operand side.** Minor; NOT applied, recorded: `RBinOp2`'s
  `leftAnchored` (`Machine.hs:2018-2021`) keys only on `breachTime` (`Machine.hs:2079-2080`), tie
  → left for `RAND`, right for `ROR`, and never reads a deadline. The barrier's extra keys exist
  because the `LEST` reads `THE DEADLINE` and the residual from the chosen member; nothing reads
  either from a compound's anchor — `MkLifecycle` is built at six sites (`Machine.hs:1666` —
  the expiry path's `lifecycleAt`, which is `MUST`/`DO` → `LEST`, `SHANT` → `HENCE`, `MAY` →
  `LEST` — `:1747`, `:1773`, `:2682`, `:2720`, `:2737`: the single-party expiry, `SHANT`
  violation and completion hand-offs, then the barrier's `HENCE`, `LEST` and state-missed
  `LEST`; round 1's ledger said five, missing `:1666` — round 2) and none is a compound, and
  `rebindLifecycle`
  (`Machine.hs:2807-2813`) rebinds a `ValROp`'s environment from the ENCLOSING hand-off, not from
  the compound's own breach. Operand side is also fixed in the source text where a roll is a
  runtime list (`tenants` vs `tenants, reversed` for one rule), so the compound's tie is not
  arbitrary in the way the barrier's was. The difference is therefore confined to which entry the
  compound's printed header and its JSON `anchor` scalar name (`run-stack.l4` §5: the landlord's
  15 over Bob's 7, both revealed at 20), and is left as C built it, on purpose.
- **`barrierStateMissed` hands the `LEST` the whole stream from the arming, so a reparation
  performed BEFORE the state deadline was missed discharges it.** Minor, pre-existing on
  `0b640727` (`git show 0b640727:jl4-core/src/L4/EvaluateLazy/Machine.hs`, lines 2284-2292 there;
  here `Machine.hs:2729-2737`, `App1 [tRef, ctx.events]`). NOT applied, documented: measured
  (probe `R1-5-statemissed.l4`, the `bounded` rule: act `WITHIN`,
  `ONCE ALL HAVE WITHIN 10 OF THE ARMING`, `LEST … WITHIN 5 OF THE DEADLINE`) a refund at 1 —
  before any member has acted — then
  Carol 3, Alice 4, Bob 12 (late for the 10), `WAIT UNTIL 20` → `FULFILLED`; with no refund →
  `BREACHED` reporting 15. The member-failure path does not do this (`barrierFail` gets the stream
  from the revealing event on). The obvious substitute, the join's residual `joinEvents` (in hand
  at `Barrier4`, `Machine.hs:1954-1964`), is wrong in the other direction: it starts after the
  LAST completion, which is after the state deadline, so a refund at 11 — after the trigger at
  10, before Bob's 12 — would be invisible. The right stream starts at the first event after the
  state deadline, which no frame computed then (it needs a stamp-walk of `ctx.events`), and it
  was §5.2-adjacent work, out of this stack's scope. `EVERY.md` stated the limit under "Runs,
  but not yet as the design says", next to the same-instant bullet. **Applied 2026-09-16 by the
  §5.2 track** (§5.2.1): the `BarrierTrim` frames walk the stream to the first event past the
  state deadline, witness `run-lest.l4` §6 (the refund at 1 no longer discharges; a refund at 11
  does), and the `EVERY.md` bullet is gone.
- **The stacking paragraph's `barrierJoined` and `earliestFailure` cite ranges were off by a line
  or stopped mid-function**, and its "(a lapsed `MAY` no longer returns through the join tail)"
  parenthetical described a history neither parent had (on both, a lapsed `MAY`'s `ValFulfilled`
  fell through `Barrier1`'s catch-all and returned the barrier at once, never reaching the join
  tail — `0b640727` `Machine.hs:1764-1766`, `82c61419` `Machine.hs:1836-1838`). Minor, both
  applied in place above, and the whole block re-cited on the round-1 tree.

**Round 2 of the adversarial pass (2026-09-16) — what it found, what was applied.** Eleven
findings CONFIRMED by both refuters (one major, ten minor; two of the ten are the same
`Machine.hs:1605` cite, raised on both tracks), every one applied; one raised and refuted by both,
not applied. No behaviour changed: the two source edits are haddocks, and every `MUST`,
`SHANT` and `RAND` block of `run-stack.golden` is byte-identical before and after.

- **The rule was witnessed for `MUST` and `SHANT` only, while `EVERY.md` said `run-stack.l4`
  pinned it for `MUST`, `DO` and `MAY`.** Major, applied: `run-stack.l4` §3b (`MAY Approve`, six
  traces: Carol's permission expires unexercised at 5, revealed at 8 → refund due 10, `FULFILLED`
  at 10, `BREACHED` reporting 10 at 11 on both rolls; the tie revealed at 20 → 10 on both rolls;
  the all-approve control → `FULFILLED`) and §3c (`DO Sign`, three traces: 10 / 10 / 10). The
  numbers were hand-computed in the source comments before the run and match the refuter's
  probes `A-may-lest.l4` and `L-chained.l4` §L5; a `MAY` member's expiry under a barrier WITH a
  `LEST` is routed to the failure sentinel (`Contract5`'s `DMay` arm, `Machine.hs:1689-1693`, `lest`
  present), which is why it orders and anchors exactly as a `MUST` miss does — only a `LEST`-less
  barrier records it as `lapsed`. `EVERY.md`'s `LEST` paragraph now names the section per modal.
- **R-Q5's state-layer sentence, read by its words, contradicts §5.1.1.1's built rule when both
  `WITHIN`s are written and a member expires first** (witness `the tenancy, a member late`: 14 + 5
  = 19, not 30 + 5). Minor, pre-existing on B; applied as an _as built_ note under R-Q5's
  state-layer bullet, a pointer back from §5.1.1.1's `LEST` paragraph, and "the earliest by R-Q5"
  above now says "R-Q5's act layer" with the reason (`Barrier3`/`Barrier4` are reached from
  `barrierJoined` alone, `Machine.hs:2652-2661`, so the state deadline is compared only after the
  join). The ruling is not changed; its exemplar has no act `WITHIN`, so its words never reached
  the both-written case.
- **`Machine.hs:1605` for the `Contract5` deadline was the stacking commit's number** (raised
  twice); on `b8a14d39` the binding is `:1608` (round 1's `seen` threading added three lines above
  it). Minor, applied above.
- **"`MkLifecycle` is built at five sites" — it is six**: the expiry path's `lifecycleAt`
  (`Machine.hs:1666`) was missed; the conclusion (no site is a compound) stands. Minor, applied
  above.
- **`EVERY.md` sent every case of "Anchored deadlines under a join" to `run-anchors.l4`,** which
  has no barrier-`LEST` tie case. Minor, applied: the sentence names `run-stack.l4` for those.
- **Two haddocks still called the member's deadline the sentinel's THIRD argument** —
  `continueWithFollowup`'s first paragraph (`Machine.hs:2104-2109`, contradicting its own
  `:2122-2127`) and `failDueRef` (`ContractFrame.hs:446-447`). Minor ×2, applied, each rewritten in
  the same number of lines so no cite moves.
- **§11.0.1's round-1 bullet called `H-shant-C.l4` "the second shape" (Alice/Bob)**; the probe is
  the Bob/Carol shape, and no Alice/Bob run on C's binary exists. Minor, applied above.
- **§5.1.1.1's header over-generalised which files' cites shift** (`Print.hs:959`/`:968` hold —
  they sit above C's first `Print.hs` hunk at `:1250`; the section cites no `ValueLazy.hs` or
  `Backend/Jl4.hs` line; this block re-cites only `Machine.hs` and `ContractFrame.hs`). Minor,
  applied: the header now lists what holds and what this block covers. One refuter corrected the
  finding's own evidence — `Syntax.hs:197` is a §5.1.2 cite, and every `Syntax.hs` cite inside
  §5.1.1.1 does shift — and the header follows the correction.
- **B's "Built" ledger (§11.0.1) still said "the sentinels' third argument"** with no pointer to
  this block. Minor, applied in place.
- **Raised and refuted by both: "`BUILD-NOTES.md` cites the extended `run-anchors.l4` comment at
  `:410`; it is at `:400`."** The `:410` cite is attached to the fork witness `receipts` — its
  `#TRACE` directive is at `:410` on both `82c61419` and this branch — and the comment edit is
  described in a separate sentence with no line number; changing it would have pointed the cite
  at a comment instead of the witness. Not applied.

Gate on the round-2 tree, as run: `cabal build all` EXIT 0 under `-Werror`; `jl4-test` run 1 =
3182 examples, 3 failures — the three `run-stack` goldens (`.golden`, `.ep.golden`,
`.nlg.golden`; `.schema.golden` unchanged), read before promotion: the fifteen prior result
blocks byte-identical and in order, nine new blocks (§3b, §3c) between the tie and the `SHANT`
section, the later blocks' source ranges renumbered; run 2 = 3182 examples, 0 failures;
`etc/verify-branch.sh --quick` EXIT 0; `doc/test-docs.sh` with the worktree `l4` on `PATH`:
1479 links, 102 L4 files, 0 orphans.

#### `EXACTLY` retired by #407 (2026-09-16) — the wave's files swept, PR-A

PR #407 (`lang/action-binder-reference`, merged to `unstable` as `cb07560d`, 2026-09-16;
`specs/todo/PATTERN-REFERENCE-RULE-SPEC.md`) made a bare name in a deontic action refer to what it
names — a lexical local (a `GIVEN`, a lambda, a `WHERE`/`LET`, an outer action binder, a `CONSIDER`
or `EVERY` variable) or a top-level value — and a fresh wildcard only when it names nothing. So
`EVERY Tenant t IN tenants MUST Sign t` is now the spelling: `t` refers to the member. Its R4
retired the rebind error (`QuantifierVariableRebound`, which refused exactly that spelling and
told the author to write `Sign (EXACTLY t)`); its fixture moved from
`not-ok/tc/every-rebinds-variable.l4` to `ok/every/every-rebinds-variable.l4`, where the same
spelling is now a positive witness, and the four `not-ok/tc` goldens were deleted (`1b0b5bfef`,
`559004560`, `2a54689ae`); `EXACTLY` in a regulative action is
deprecated, with a `DeprecatedExactly` warning carrying the replacement, until the sunset recorded
by #409 (2026-10-01). Snippets in this document written before 2026-09-16 keep the `EXACTLY`
spelling as a record of what was built and measured at the time; they are not rewritten.

The wave's own files were swept in the commit that carries this note (PR-A, `every/anchors-on-blame`,
rebased onto `unstable` `e966996f`): every `DeprecatedExactly` warning the rebased tip's own `l4
check` printed was applied as the compiler advised — all `DropTheKeyword` of a bare name, none of
the two "cannot simply be dropped" kinds — and the parentheses that had held the keyword were
dropped. Counts, `EXACTLY` before → after: `jl4/examples/ok/every/run-anchors.l4` 71 → 0,
`run-blame.l4` 12 → 0, `run-stack.l4` 11 → 0, `doc/reference/regulative/every-example.l4` 3 → 0,
`jl4/examples/not-ok/tc/anchor-on-join-line.l4` 2 → 0, `jl4/examples/lsp/semantic-tokens/anchors.l4`
2 → 0, and the six lines the wave had added to `doc/reference/regulative/EVERY.md` (three in
fenced L4, three in a pasted breach print, which now reads `MUST Sign t` as the run prints it).
The verdict-preserving differential — the same snapshot binary running the pre-sweep copy and the
swept file, `Result:` blocks only, the pre-sweep side's own `(EXACTLY x)` normalised to `x` —
was SAME for all 85 directives (`run-anchors` 50, `run-blame` 11, `run-stack` 24; the other three
files carry no directive), with the same exit code on both sides. The files commits 10–19 add or
re-introduce the keyword into (`run-lest.l4`, `run-after.l4`, `ok/contracts.l4`,
`legal/promissory-note.l4`, `lsp/semantic-tokens/after.l4`, `not-ok/tc/before-on-join-line.l4`,
`AFTER.md`, `what-follows.md`, …) are NOT swept here: PR-B (`every/after-before`) owes its own
sweep commit at its tip, which had not been made when this note was written.

### 11.0.2 The roll, said outright: `EVERY Cast v IN xs` — RULED 2026-09-08 (Meng), BUILT

**The ruling.** Meng, 2026-09-08, in session: _build `EVERY X x IN xs` syntax, and revise the
documentation accordingly._ §11.0 put exactly this to review as the one thing it declined to
settle — "a cast-source keyword is a new production, not an implementation choice" — and named
Meng as the person to settle it. It is now a production, built on `lang/every-in`, with
`jl4/examples/ok/every/run-in.l4` as its witness.

**The grammar.** §2.4 writes the same production, in its own vocabulary
(`QuantifiedDeonton ::= Quantifier Pattern [Roll] [Filter]`); the shape is:

```
Roll ::= 'IN' Expr                    -- a LIST of the party type: the group is drawn from it
```

placed between the `Pattern` and the `Filter`.

`IN` sits before `WHO`, in reading order — _every tenant t in tenants who is not carol_. It costs
no new keyword: `TKIn` has existed since `LET … IN` (`jl4-core/src/L4/Lexer.hs:239,341`
@ `03af495f`), and one name cannot be mistaken for it, because `name` (`Parser.hs:364-365`) never
matches a keyword token. Measured 2026-09-08: `LET … IN` is the only other `TKIn` consumer in the
tree (`Parser.hs:594`, `Parser.hs:612`), so there was no ambiguity to resolve.

Four questions §11.0 did not answer, each with the measurement that settled it.

**Q1 — does `IN` REPLACE the inferred roll, COEXIST with it, or supersede it on a deprecation
path? RULED: coexist, with `IN` winning wherever both are written.** Two things decided it.

- **Measured on the base tree `03af495f`, comment lines excluded:** 19 roll-supplying
  `WHO … elem v xs` conjuncts across 7 files (`ok/every/run-modals.l4` 7, `run-roll.l4` 5,
  `run-barrier.l4` 2, `doc/reference/regulative/every-run-example.l4` 2, `run-fork.l4` 1,
  `who-filter.l4` 1, `doc/reference/regulative/every-example.l4` 1). Two of the seven files are the
  pages a reader is pointed at. Not all 19 sit in rules a run would notice: `who-filter.l4` and
  `every-example.l4` carry no directive at all, and `run-roll.l4`'s `circular` already refuses — so
  the honest form of the claim is that replacing the inference would rewrite 19 conjuncts, change
  the answer of 15, and change `circular`'s answer in KIND rather than in substance — its refusal
  would move from run time to check time (§13.5 says the same, and says why that matters).

- **The deeper reason, and it is not migration cost.** `elem v xs` is a perfectly good FILTER in
  its own right — it was one before it was ever a roll. Reading a roll out of it _when no roll was
  written_ therefore takes nothing away from anybody and adds no second meaning to the conjunct;
  the two readings agree on every program that has only one of them.

**What is NOT ruled here, and is Meng's:** whether the inferred form should be deprecated —
warned on at check time, and eventually removed. That changes what a user must write, so the build
did not decide it. Recorded as an open question in §13.5.

**Q2 — a rule that writes `IN xs` AND carries an `elem v ys` conjunct. RULED: `IN` is the roll; the
conjunct keeps its ordinary job.** No new rule was needed and none was added: the conjunct is
evaluated per candidate exactly like every other part of the filter, so the cast is _the members of
`xs` that satisfy the whole filter, in `xs`'s order_. Where `xs` and `ys` are the same list the
conjunct is a redundancy every member passes; that is harmless and draws no diagnostic. Two
witnesses in `run-in.l4`:

- case 6, `IN (LIST alice)` beside `WHO elem t tenants`, **discriminates**: if the conjunct were
  still taken as the roll this would want three signatures, and Alice's alone completes the
  barrier. Measured by building the counterfactual, 2026-09-08.
- case 7, `IN tenants` beside `WHO elem t (LIST alice, bob)` — the roll is three, the conjunct
  narrows to two, and two signatures complete it. **This one does not discriminate**, and is kept
  as the readable illustration of the rule rather than as evidence for it: either reading produces
  the cast `{alice, bob}`. Said plainly because an earlier draft of this section claimed both cases
  discriminated, and the adversarial pass showed only case 6 does.

Note what this makes explicit: the same net behaviour was already reachable under §11.0 by writing
two `elem` conjuncts, where the leftmost silently became the roll and the rest silently narrowed
(§11.0's main text: "takes the FIRST conjunct of the form `elem v xs`"). `IN` does not change that
answer; it stops it being silent.

**Q3 — does the refusal now point at the new syntax? RULED: yes, and it does.**
`rollCallRefusal` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:1985` @ this branch) names
`EVERY Tenant t IN tenants MUST ...` first and mentions the `elem` spelling second, as still
working. Golden: `jl4/examples/ok/every/tests/run-roll.golden:5`.

**Q4 — does `EACH` take `IN`, and do §2.2.7's threshold joins? RULED: `EACH` does not; the built
joins get it for free; the unbuilt ones inherit a question §2.2.7 has never answered.**

- **`EACH` takes no `IN`, and the reason is that there is no `EACH` to take it.** R-Q1 (§2.5,
  2026-09-07) retired `EACH` as a quantifier. Re-measured 2026-09-08: the only `EACH` anywhere in
  the compiler is the fork's join word, matched by SPELLING as an ordinary identifier at
  `jl4-core/src/L4/Parser.hs:2633` @ this branch (`:2621` @ `03af495f`) — there is no `TKEach` —
  and a join word names _when the continuation fires_, not _who is in the group_. A join has no cast of its own to draw.

- **`ONCE ALL HAVE` and `UPON EACH` get the roll whatever its spelling, and needed no work.** The
  roll is drawn BEFORE the join is inspected: `startRollCall` (`Machine.hs:2021`) runs to
  completion and only then does `assembleQuantified` (`Machine.hs:2058`) look at
  `ctx.deonton.join`. Witnessed under both: `run-in.l4` cases 1–7, 9, 10 (barrier) and case 8
  (fork).

- **A consequence for phase 3, stated and deliberately NOT ruled.** §2.2.7.4 writes both the
  grammar's `Count 'OF' Cast 'HAVE'` — a cast INSIDE the threshold — and the prefix sugar
  `SOME 2 OF Director d DO sign …` (§2.2.7.8's R-T5 row names that sugar but writes no example of
  it). Neither says where its list comes from, and neither is built
  (`Threshold` has one constructor, `AllHave`, `jl4-core/src/L4/Syntax.hs:521`; `SOME` is lexed
  and never parsed, `Lexer.hs:248,350`). With `IN` in the language the natural reading is that the
  threshold's `Cast` NARROWS the roll rather than supplying a second one, and that the prefix sugar
  grows an `IN` slot — `SOME 2 OF Director d IN board DO sign …`. That is a reading offered to
  whoever builds §2.2.7.4, not a ruling: nothing was measured against it, because there is nothing
  to measure.

**One thing the explicit spelling buys that §11.0 could not have.** The `IN` roll is type-checked
with the member variable **out of scope** — `checkDeonton` checks it beside the join line's
`WITHIN`, before `extendKnown` opens the member's scope (`jl4-core/src/L4/TypeCheck.hs:1914`, with
`extendKnown` at `:1917`, @ this branch), against `LIST OF partyT` under a new
`ExpectQuantifierRollContext`. The language rule this makes uniform is worth stating in one
line: **what is read once for the whole group — the
join's deadline, and now the roll — cannot mention a member; what is read per member — the filter,
the action, the act's `WITHIN`, and a fork's continuations — can.**

So `EVERY Tenant t IN (peersOf t)` is a CHECK-time error, where §11.0's `WHO elem t (peersOf t)`
is a run-time refusal (`circularRollRefusal`). The inferred form cannot be given the same treatment
and this is not an oversight: the filter genuinely does bind the member, legitimately, for every
other conjunct, so the variable cannot be taken out of scope there. Witnesses:
`jl4/examples/not-ok/tc/every-roll-mentions-member.l4` (check time) beside `run-roll.l4`'s
`circular` (run time).

**Three limits carried in deliberately, all measured 2026-09-08.**

- The circularity rejection arrives as the generic _"I could not find a definition for the
  identifier t"_, the same poor wording the join line's identical restriction has had since
  2026-09-07 (the note is in the code, `jl4-core/src/L4/TypeCheck.hs:1896-1911`, and on
  `doc/reference/regulative/EVERY.md` for readers). A dedicated diagnostic is not built, and the
  two positions should get one together rather than separately.
- **The rejection depends on the member's name being UNBOUND, not on its being the member**, which
  is weaker than "the roll cannot mention the member" sounds. Measured 2026-09-08: with a top-level
  `t MEANS carol` in the module, `EVERY Tenant t IN (peersOf t) WHO NOT (t EQUALS carol)`
  type-checks and runs — the `t` in the roll silently means the top-level one and the `t` in the
  filter means the member. One identifier, one line, two meanings. This is ordinary lexical scoping
  and it is **inherited, not introduced**: the join line's `ONCE ALL HAVE WITHIN t` has exactly the
  same hole, and re-measured against the base binary at `03af495f` it behaves identically there.
  Closing it would mean ruling that an identifier merely SPELLED like the member is an error in
  these positions whatever else is in scope — a language change that would have to cover the join
  line too, and so not one this build made. Recorded rather than fixed; the doc page says it in the
  reader's terms.
- Adding a field to `Subject` changes the CBOR wire format (`Syntax.hs:1253`,
  `Serialise n => Serialise (Subject n)`). The boundary is not the repo's edge: `jl4-service`
  persists whole modules to disk inside this tree (`jl4-service/src/BundleStore.hs:80`,
  `SerializedBundle` carrying a `Module Resolved`, written by `saveBundleCbor` at `:197`). Nothing
  breaks, because `loadBundleCbor` at `:215` uses `deserialiseOrFail` (`:225`) and recompiles on
  failure — but an existing deployment's `bundle.cbor` cache goes stale on this change and is rebuilt, logging
  `"Corrupt bundle.cbor, will recompile"` against the deployment id (`BundleStore.hs:227-228`).

### 11.1 Runtime State

> **Still a sketch, 2026-09-08.** No such type exists; grep for `BarrierRuntime` finds nothing in
> `.hs`. The build carries the barrier's state in an evaluator FRAME
> (`L4.EvaluateLazy.ContractFrame.BarrierStepFrame`) rather than in a value, which is why an
> unfinished barrier's residual loses its join line (§11.0.1): a frame does not survive the answer
> being returned. A resumable contract — a service that stores a running barrier and feeds it more
> events later — is what would need this record to become real.

```haskell
data BarrierRuntime = BarrierRuntime
    { brParties     :: Set Party
    , brCompleted   :: Set Party
    , brPending     :: Set Party
    , brFailed      :: Set Party
    , brDeadline    :: Time
    , brEntryTime   :: Time
    , brCompletions :: [(Party, Time)]  -- for blame/timing
    }
```

### 11.2 Desugaring Strategy

1. **Parse** quantified deonton
2. **Expand** to barrier structure (not simple conjunction)
3. **Track** completion state at runtime
4. **Fire** HENCE/LEST at appropriate transitions
5. **Propagate** reference time to continuation

### 11.3 Scope Handling

For nested quantifiers, maintain scope chain:

```haskell
data Scope = Scope
    { scopeBindings :: Map Variable Value
    , scopeParent   :: Maybe Scope
    }

resolve :: Variable -> Scope -> Value
resolve v scope = case Map.lookup v (scopeBindings scope) of
    Just val -> val
    Nothing  -> maybe (error "unbound") (resolve v) (scopeParent scope)
```

## 12. Examples

### 12.1 Mutual NDA

```l4
GIVEN confidential_info IS A SET OF Information

EVERY p
    WHO    member_of parties
    MUST   keep_confidential confidential_info
    WITHIN contract_duration
    LEST   PARTY p MUST pay_damages
```

### 12.2 Document Signing with Barrier

```l4
EVERY d
    WHO    member_of directors
    MUST   sign_resolution
    WITHIN 14 days
    HENCE  company MUST file_with_registrar WITHIN 7 days
    LEST   resolution_fails
```

The filing obligation only triggers when ALL directors have signed.

### 12.3 Termination with Settlement

```l4
EACH p_x
    MAY    terminate upon 30 days notice
    HENCE  EVERY p_y
               WHO    differs_from p_x
               MUST   settle_outstanding_accounts_with p_x
               WITHIN 30 days
               HENCE  FULFILLED
               LEST   PARTY p_y MUST pay_penalty_to p_x
```

### 12.4 Sequential Signing by Seniority

```l4
GIVEN board IS A LIST OF Director

`sign in order` MEANS
    CONSIDER sortOn seniority board
        WHEN []          THEN FULFILLED
        WHEN (d :: rest) THEN
            PARTY d MUST sign WITHIN 7 days
                HENCE `sign in order` rest
                LEST signing_failed
```

Uses existing recursion; no new syntax needed.

## 13. Open Questions

### 13.1 Early Failure Policy

Should early failure detection (before deadline) be:

- Default behavior?
- Opt-in via modifier?
- Contract-level configuration?

**Recommendation:** Opt-in, as legal systems typically allow cure until deadline.

**CLOSED 2026-09-07 by R-Q5 (§2.5, §3.4; Meng's mark: _"d"_): none of the three.** No modifier and no
configuration; the failure time is fixed by the layer the `LEST` attaches to, then by the modal. The
recommendation's reason — cure until the deadline — holds for a `MUST` and is false for a `SHANT`,
which fails at the act, and it was silent about the state line R-T2 ruled. And an opt-in would have
nothing to observe: the machine has no party-failure event (`Syntax.hs:208-215`), and `REFUSE` is not
one (`Syntax.hs:361-371`).

### 13.2 Partial Completion Visibility

Should intermediate completion state be observable to other parts of the contract?

```l4
IF (count_completed parties action) >= quorum THEN ...
```

**Recommendation:** Yes, via accessor functions on barrier state.

### 13.3 Synchronization Modifiers

For complex coordination, consider explicit sync:

```l4
EVERY p
    MUST   X
    HENCE  ...
    COORDINATED WITH other_barrier
    SYNCHRONIZES ON final_settlement
```

**Recommendation:** Defer to future iteration; current design covers common cases.

### 13.4 Cast Survivorship — RULED 2026-09-07 (R-Q6, §2.5; Meng's mark: _"d"_)

The joint/several memo raised the question §13 did not list
(`EVERY-EACH-JOINT-SEVERAL-MEMO.md:101`, `:429-431`): what happens to an armed barrier when the
inhabitant set changes after arming — a member released, substituted, or joined mid-window? The
workflow-patterns catalogue splits here: WCP-14 (instance count fixed once started) against, by
analogy only, WCP-15 (count may change while running — a creation-side pattern; nothing in it
licenses withdrawal).

**The rule.** The cast is evaluated **once, at arming**, for the whole family — R-T6 (§2.2.7.8)
extended to `EVERY`, which is `ALL OF` plus one continuation (§2.2.7.3). It changes only on an
explicit **edit** event applied to the running barrier — a **release**, a **substitution**, or a
**joinder** — which adjusts the pending set and the blame set while **preserving the completions and
the accumulator**, and leaves the deadline where it was:

```l4
EVERY Director d IN board MUST sign WITHIN 30 days
    ONCE ALL HAVE
    HENCE `resolution passes`
    LEST  BREACH
-- `board` is read once, here: {Alice, Bob, Carol}.
-- day 2: Alice signs                        (completed = {Alice})
-- day 3: an explicit RELEASE of Bob         (illustrative; no such event exists yet):
--        pending = {Carol}; the blame set excludes Bob; Alice's signature kept; deadline unchanged.
-- day 9: Carol signs → ONCE ALL HAVE holds → HENCE fires.
-- Without the release: the barrier waits for Bob; day 30 → LEST, blame = {Bob} (§6.1).
```

**Why an edit and not a re-arm.** The first draft of the ruling said a novation clause "re-arms" the
barrier. A re-arm discards Alice's signature and reopens the deadline — the two costs that
disqualified the re-arm-on-any-change option — and a re-arming `WITHIN` is the very defect R-T2 was
ruled to remove (§2.2.7.5 point 3). Doctrine's release rule (Restatement (Second) of Contracts § 294,
as the memo records it at `:99`) is what the edit event models at the `ANY OF` end of the family,
where leaving a released obligor in the blame set would contradict a release the creditor has signed
— visible now that R-T3's breach carries a set (written 2026-09-07 in the present tense ahead of the
build; true since 2026-09-15, §6.1).

**Why not a live re-read.** Who is blamed would change silently with the cast expression; a cast that
depends on the ledger would be re-evaluated after every event; and a member could escape blame by
leaving. §4.1's `boParties` and §6.1's `bo.parties` are fields captured at arming, and §3.4's
`pending` only shrinks — the document had been assuming the freeze. The state graph is drawable
statically only under it: `StateGraph.hs` draws a fixed fan (`AllOf`/`OneOf`,
`jl4-core/src/L4/StateGraph.hs:133-134`, taken from the operands of `RAND`/`ROR` at `:511` and `:514`);
a run-time-width fan is already needed for `EVERY`, and a width that changes mid-run has no drawing at
all. The refuters' strongest attack — a shareholder vote, where a record date fixes the eligible roll
and later transfers do not change it — turned out to be the freeze exactly (Delaware DGCL § 213, from
the refuter's memory, unverified).

**Scope, and R-T6's escape hatch (stated here because §2.2.7.8 did not state it).** The rule bites
only on **computed casts** — a `WHO` filter, a `GIVEN` list, a ledger read; for a closed actor type the
bare `EVERY t` form makes it a no-op. And a population written as a cast filter is **frozen**, but a
**measure over the ledger** (`ONCE sum OF amount …`, a count over the member list) is **live** by
construction, so two spellings a drafter reads as synonyms answer differently — the s 177 quorum of
§2.2.7.3 can be written either way with no cue which you got. The page that introduces the join must
say which to use.

**Until the events exist**, the behaviour is "fixed at arming, no edits": a change of party is a new
agreement (Meng's R-T6 note, _"This is why novations etc are a thing"_), written as a clause. The
three events — their syntax, ledger entries and state-graph edges — are **proposed, not built**, and
R-T6's own low confidence carries over to the survivorship half. The memo's release-of-one-discharges-
all gap (`:99`) stays open: at the `ANY OF` end it needs a discharge operation the language does not
have.

### 13.5 The inferred roll is DEPRECATED — RULED 2026-09-08 (Meng); migrated 2026-09-09

§11.0.2 built `IN` and left the older spelling running: with no `IN` clause, the machine still
reads the roll out of the first `elem v xs` conjunct of the `WHO` filter (§11.0). The build did not
touch that, on the ground that removing it — or warning on it — changes **what a user must write**,
which is a ruling and not an implementation choice.

**The question.** Should a rule that relies on the inferred roll get a check-time warning naming
`IN`, and should the inference eventually be removed?

**What is measured, so that the question can be answered without re-deriving it.**

- **What it would cost, measured on `lang/every-in` itself and not on the tree §11.0.2 was written
  against.** After this branch's own migration there are **17 conjuncts across 6 files** still
  relying on the inference: `ok/every/run-modals.l4` 7, `run-roll.l4` 5, `run-barrier.l4` 2,
  `run-fork.l4` 1, `who-filter.l4` 1, `doc/reference/regulative/every-example.l4` 1. (At the base
  `03af495f` it was 19 across 7; this branch migrated `every-run-example.l4` outright and left
  `every-example.l4` one deliberate specimen.) Among the `doc/` example files only
  `every-example.l4` still relies on the inference, and it does so deliberately, as the specimen
  shown beside its `IN` equivalent. The older spelling is still _discussed_ on three `doc/` pages,
  which is intended: it is what a reader will meet in existing material.
- **Most of the rewrite is mechanical; one case is not.** `WHO elem t xs` becomes `IN xs`, and
  `WHO elem t xs AND p` becomes `IN xs WHO p`. The exception is `run-roll.l4`'s `circular`
  (`WHO elem t (LIST t, alice)`), which exists to witness the RUN-TIME refusal: rewriting it to
  `IN` moves the diagnostic to check time (§11.0.2) and destroys the witness. A deprecation would
  have to keep one un-migrated file, or accept losing that witness.
- **What deprecating it would buy.** Three sharp edges `IN` does not have. Two are §11.0's own
  costs: the roll is found by the SPELLING `elem`, so a user-defined two-argument `elem` is taken
  for it; and only an `AND` chain is walked, so `OR` and `NOT` refuse. The third is §11.0.1's: a
  circular roll is a run-time refusal rather than a check-time error, because the filter must bind
  the member for its other conjuncts. As long as the inference lives, so do all three. And note
  what deprecation would NOT buy: §11.0's _third_ cost — a roll with repeats producing repeated
  members — belongs to the list rather than to the spelling, so `IN` has it too.
- **What it would cost to build the warning.** Not free, and the reason is worth knowing before
  ruling: the inference lives in the EVALUATOR (`L4.EvaluateLazy.Machine.quantifierRoll`), not in
  the checker, so a check-time warning means teaching `checkDeonton` to recognise the same
  `elem v xs` shape. It is NOT a retyping job — `checkDeonton` has `rv :: Resolved` and
  `filterR :: Expr Resolved` in scope at `TypeCheck.hs:1914-1917`, which are exactly
  `quantifierRoll`'s argument types (`Machine.hs:1957`), so the call would compile as written. The
  obstacle is the module direction: `L4.EvaluateLazy.Machine` imports `L4.TypeCheck` and not the
  other way round, so sharing the function means MOVING it, and duplicating it instead leaves two
  copies of one rule in two phases — the arrangement that drifts. If the answer is yes, move the
  recognition into the checker and have the evaluator read what the checker recorded.
- **This document's own examples are NOT in the count above, and there are more of them than there
  are corpus rules.** Measured 2026-09-08: about ten code blocks in this specification still write
  `EVERY … WHO elem …` — §2.1's headline example, §2.2.3, §2.2.6, §2.2.7.6's rent, §8.3 and §12 —
  all of them unmarked, while the status header now says `IN` is the spelling to reach for. They
  were left alone deliberately: each illustrates a DIFFERENT ruling, and rewriting them in the same
  change that introduced `IN` would have churned sections this work did not review. If the answer
  to this section's question is yes, they are part of the job; if it is no, they should still be
  marked, because a reader learns the spelling from the examples and not from the header.
- **What NOT deprecating it costs.** Two spellings for one idea, indefinitely, in a language whose
  pitch is that there is one obvious way to write a rule.
- **What it would NOT touch.** The shadowing hole of §11.0.2 — an identifier spelled like the member
  resolving to a top-level binding of the same name — is untouched by this question. It is a
  scoping matter shared with the join line, and it survives whichever way this is ruled.

**No recommendation was recorded above, on purpose.** This is a question about what a drafter must
write, which §11.0.2 gives as the reason the build stopped short of it; the measurements are the
whole of what the build knew, and they were left as the whole of it so that the ruling could be made
without redoing them.

**RULED 2026-09-08.** Meng's mark, on the two halves put separately:

> _"1. Deprecate for inconsistency and redundancy."_

and, on the shape of the follow-through:

> _"reword the deprecation. no real code uses that style. just mechanically rewrite existing code
> that matches the deprecated style. don't think we really need a warning but your call if you want
> it."_

**What was ruled, and what "deprecated" means here.** The inferred roll is deprecated. It is not
removed: `EVERY Tenant t WHO elem t tenants` still runs, still means what it meant, and existing
code outside this repository keeps working. What changes is that it is no longer one of two ways to
say the same thing — it is the older way, the documentation says so on every page that mentions it,
and the corpus no longer teaches it except where a test needs it.

**The warning is DECLINED — my call, taken under the discretion Meng's mark gave.** The reason is
the measurement above and not a preference: the inference lives in the EVALUATOR
(`L4.EvaluateLazy.Machine.quantifierRoll`), and `L4.EvaluateLazy.Machine` imports `L4.TypeCheck`
rather than the other way round, so a check-time warning means either moving that function across a
module boundary or keeping two copies of one recognition rule in two phases — the arrangement that
drifts. Against that cost, after the migration below, a warning would fire on **six** sites in this
repository, **five of which are the tests that exist to keep the inference honest**: it would be a
diagnostic whose main effect is to annotate its own witnesses.

**State the cost of declining, because it is real.** A deprecation with no warning is enforced by
documentation alone. A drafter who writes `WHO elem t tenants` today gets no signal of any kind —
not a warning, not a note, nothing in the trace. The only thing that tells them is a page they have
to be reading already. If the deprecation is ever to become a removal, a warning has to come first,
and this ruling does not schedule one.

**What was migrated (2026-09-09).** Eleven conjuncts across four corpus files —
`ok/every/run-modals.l4` (7), `run-barrier.l4` (2), `run-fork.l4` (1), `who-filter.l4` (1) — by the
mechanical rule above. Verified semantics-preserving rather than assumed: each file was run before
and after and the outputs compared, and all four are identical modulo the file name, the line ranges
shifted by the removed `WHO` line, and the rule's own text where a residual obligation echoes it.
Goldens regenerated, read, and checked for absolute paths.

**What was kept, and why each one is not an oversight.**

- **`ok/every/run-roll.l4`, all five.** That file is the witness for the inference itself. One of
  the five — `circular`, `WHO elem t (LIST t, alice)` — witnesses a RUN-time refusal that has no
  `IN` counterpart at all, because an `IN` roll that mentions the member is caught at CHECK time
  (§11.0.2). Rewriting it would delete the only test of that path.
- **`doc/reference/regulative/every-example.l4`, one.** The labelled specimen, shown beside its `IN`
  equivalent, so a reader who meets the older spelling in existing material can recognise it. It is
  now labelled **deprecated** rather than "still runs".
- **`ok/every/run-in.l4`, two.** These are NOT this pattern, and a grep for `elem` reports them as
  though they were. Both already carry an `IN` roll; their `elem` is a deliberate narrowing
  condition, and the file exists to prove that `IN` wins over `elem` and that `elem` goes on
  narrowing. Rewriting them would destroy both witnesses. Noted here because the same grep will
  mislead the next person.

**This document's own examples are handled too**, as this section said they would be if the answer
was yes — but split, because they are not all the same kind of example. **Eight blocks were
rewritten** to `IN`, in §2.2.3 (the `NO` sugar, both halves), §2.2.7.6 (the joint and several rent),
§8.3 (all three `RAND`/`ROR` shapes) and §13.4 (the survivorship example): in every one of them the
roll is incidental and the block is illustrating something else. **Three sites were marked instead
of rewritten**, each with a note saying why: §2.1, whose subject IS `elem`-as-a-condition and which
now carries a note distinguishing the `IN` clause from a `WHO elem` narrowing; §2.2.6, whose code
blocks are kept verbatim as the record of a design that was superseded, with a line added to its
banner telling the reader not to copy the spelling out of it; and §11.0's own argument, whose
measurement is dated and true of the tree it was taken against, now marked past-tense. The blocks
that DESCRIBE the inference — §11.0, §11.0.1, §11.0.2, and this section — keep `elem`, because that
is their subject.

**Two user-facing messages were reworded** (`Machine.hs`). `rollCallRefusal`, which a run emits when
an `EVERY` has no roll at all, offered the `elem` spelling as a working alternative; it now names it
as the older one. `circularRollRefusal`, which can only be reached from the inferred spelling, told
the reader to write `WHO elem t tenants`; it now tells them to write `IN tenants`, which fixes the
circularity and migrates them in one step. Neither is a warning: they fire only where the run was
already refusing.

**What is NOT ruled.** Removal. There is no date, no deprecation window and no removal commit
planned, and this section should not be read as promising one. What has changed is which spelling
the language teaches.

**What this still does not touch.** The shadowing hole of §11.0.2 — an identifier spelled like the
member resolving to a top-level binding of the same name — is untouched, as this section said it
would be. It is a scoping matter shared with the join line and survives the ruling.

### 13.6 `WHOSE`, and the R-Q4 problem it does not escape — OPEN, raised by Meng 2026-09-08

> **Meng's mark, 2026-09-08, after the synthesis below was written:** _"Then my layout proposal fades
> back into existing conjunctive/disjunctive over multiple lines, compatible with inert style. I
> think this design had legs."_ The layout route is therefore **withdrawn by its proposer**, and the
> `WHOSE`-as-opening reading is endorsed as a **direction**. It is not thereby built or ruled: the
> three conditions under "What must be true" are unchanged and none has been discharged.

R-Q4 (§2.5) withdrew the insertion rule: the `WHO` slot no longer holds a point-free predicate with
the bound variable supplied as its first argument, because that rule could not type §2.1's own
advertised example — `WHO is_adult AND is_shareholder AND NOT is_conflicted` applies `AND` and `NOT`
to functions rather than to Booleans. Today the slot holds **a Boolean expression in which the bound
variable is free**, written where it is used.

Meng raised two things against that on 2026-09-08, one cosmetic and one not.

**The cosmetic one: `WHO` reads as a pronoun awaiting a complement.** `WHEN` was proposed as an
alternative. **It is not available.** `WHEN` is a lexer keyword (`("WHEN", TKWhen)`,
`jl4-core/src/L4/Lexer.hs:289 @ 28c48e3f`) carrying **1605 corpus uses**, load-bearing in
`CONSIDER … WHEN … THEN …`. Putting it in a second, unrelated grammatical role is not a rename, it
is an overload. `WHOSE` by contrast is entirely free: **zero** lexer entries, and all seven corpus
occurrences are English prose inside comments (`-- WHOSE RIGHT THIS IS`, in the
`guardianship-of-infants-act` and `probate-administration-act` encodings).

**The substantive one: computed fields make a possessive form attractive.** The proposal:

```l4
EVERY Tenant t IN arrears WHOSE monthly_rent AT LEAST 1000 MUST …
```

— where `arrears` is a dynamically constructed LIST of tenants behind on rent (the roll), not a
number. As sugar this is `WHOSE f` ≡ `WHO t's f`, and every part it needs already exists: `AT LEAST`
is an infix operator (`jl4-core/libraries/prelude.l4:780`), possessive projection is idiomatic
(`a's age`, `a's income`), and computed fields are implemented (`COMPUTED-FIELDS-SPEC.md`).

#### The objection, and why it does not land as stated

Meng's objection was that resolving `monthly_rent` re-introduces the shoehorned first argument.
**It does not, and the reason is a namespace separation rather than a convention.** `TypeCheck.hs`
`@ 28c48e3f`: for `Proj ann e l`, when the base is a **local binding** — which the quantifier's
member variable is — resolution goes straight to `inferRecordProjection` (`:3051-3053`), which
resolves the label through `resolveProjectionLabel` (`:3133`). **The term environment is never
consulted.** So:

|                          | the retracted insertion rule                           | `WHOSE`                                                     |
| ------------------------ | ------------------------------------------------------ | ----------------------------------------------------------- |
| what follows the keyword | resolved as a **term**                                 | resolved as a **field label**                               |
| what is supplied         | the member as a first **argument**                     | `t's` as a **projection**                                   |
| why R-Q4 killed it       | `AND`/`NOT` are terms, so they got the member inserted | connectives are not field labels; the question cannot arise |

#### Three things measured against the tree, one of which contradicts the obvious rule

1. **"`WHOSE` requires a cast" would be wrong.** A plain product actor needs no cast and already
   works: with `DECLARE Party HAS name IS A STRING`, `t's name EQUALS "alice"` type-checks and
   evaluates. The rule to state is **totality** — the field must exist on every constructor the
   member could still be. Product type: always. Sum type: only where the cast has narrowed to the
   arm declaring it. The cast requirement then falls out for sums instead of being imposed on
   products.

2. **A partial projection fails at RUN time, not check time, and says something unrelated.**
   With `Party IS ONE OF Landlord | Tenant HAS monthly_rent`, `t's monthly_rent` on a `Landlord`
   produces: _"The value `Landlord` reached a CONSIDER that has no branch for it. Add a WHEN branch
   for this case, or a catch-all OTHERWISE branch."_ A drafter who wrote neither a `CONSIDER` nor a
   `WHEN` will not recognise their own program in that sentence.

3. **The "same field on two arms, opposite polarity" hazard is already impossible — but by
   forbidding the modelling.** Declaring `Landlord HAS amount_due` beside `Tenant HAS amount_due`
   is refused at check time: _"There are multiple definitions for the identifier"_
   (`TypeCheck.hs:5806`). Field names are flat across a sum type's constructors. That forecloses
   the confusion, and it is worth recording that it forecloses it the blunt way; someone will
   eventually want per-constructor fields that share a name.

#### The angst, which is real and is NOT resolved by any of the above

`WHOSE x AT LEAST N AND y EQUALS M`.

Under one-atom scoping this is `t's x AT LEAST N AND y EQUALS M`, and **`y` resolves in the term
namespace**. It will not type-error the way `is_adult AND is_shareholder` did — no connective
receives an argument. It fails more quietly:

- no such term exists → _"could not find a definition for y"_. Loud, survivable.
- **a top-level `y` does exist → it silently means that instead.**

And the silent case is reachable, not theoretical: **a term and a field may share a name.**
`monthly_rent MEANS 42` alongside `DECLARE Party HAS monthly_rent` is accepted today (measured
2026-09-08). This is the same hazard §11.0.2 already records for the `IN` roll, where a top-level
`t MEANS carol` makes `IN (peersOf t)` resolve and check clean — one spelling, two meanings.

**So one-atom scoping does not remove R-Q4's problem. It relocates it from a type error to a silent
capture, which is worse.** That is the objection in its strongest form and it stands.

#### The three routes, with what each costs

- **`WHOSE` repeated per property** — `WHOSE x AT LEAST N AND WHOSE y EQUALS M`. English-natural,
  unambiguous, needs no new resolution rule. Cost: nothing stops a drafter omitting the second
  `WHOSE`, and the reward for omitting it is silence.
- **Field-first resolution across the whole `WHOSE` expression** — any bare name that is a field of
  the member's type becomes a projection. Gives the nicest surface. Cost: it is the retracted
  design's shape again, and it is only safe if a field name and a term name cannot collide — which
  today they can.
- **Restrict `WHOSE` to a single comparison**, conjunctions falling back to `WHO`. Cheapest and
  safest; buys the least.
- \*\*~~Layout-conjoined `WHOSE`, one constraint per line~~ — proposed by Meng 2026-09-08 and
  WITHDRAWN by him the same day, for two reasons that both turned out to be right. Kept here
  because the reasoning is what closes the question:

  ```l4
  EVERY Tenant t IN arrears
      WHOSE  monthly_rent  AT LEAST 1000
             standing      EQUALS   "current"
      MUST …
  ```

  **Always conjunction. Anything else — disjunction, negation, a mixed expression — must be written
  with `WHO`,** where every name is explicit and nothing is implied.

  **Why it dodges the whole problem rather than trading it.** The field is identified by
  **position**, not by resolution: the first token of each line is a field, full stop. No bare name
  inside a `WHOSE` ever has to be resolved against two namespaces, so R5's shadowing question does
  not arise here at all — it stays R5's question, on R5's own terms. And because no connective
  appears inside a `WHOSE`, the failure that killed the insertion rule has nothing to attach to.
  Each line's remainder (`AT LEAST 1000`) is an ordinary expression in the ordinary namespace; a
  constraint that needs another field says so with `t's`.

  **Why it is withdrawn — 1: the synthesis below makes it unnecessary.** Under opening, the field
  position is not what disambiguates a bare name; R5's rank is. One-constraint-per-line stops being
  a disambiguator and becomes a formatting choice, which is a much better thing for it to be.

  **Why it is withdrawn — 2: L4 already has it, and has had it all along.** The ellipsis operators
  are asyndetic con/disjunction: **`...` is implicit `AND`, `..` is implicit `OR`**
  (`skills/writing-l4-rules/references/gotchas.md`, "Asyndetic operators"). They exist precisely so
  a clause list "should read as a bulleted list rather than a prose 'A and B and C'", and they are
  not marginal — **591 asyndetic operator lines across the corpus, 405 of them `...`**. So the
  proposal was not a new mechanism, it was a second spelling of an existing one:

  ```l4
  EVERY Tenant t IN arrears
      WHOSE monthly_rent AT LEAST 1000
        ... standing     EQUALS   "current"
      MUST …
  ```

  And because `..` is already there beside `...`, the restriction the proposal needed —
  _always conjunction, anything else falls back to `WHO`_ — is not needed either. Disjunction comes
  for free in the same shape.

  **And it is compatible with inert style, which an operator-free form would have fought.** In inert
  style a string literal in Boolean context carries verbatim statutory prose and evaluates to its
  context's identity, so the prose _rides between the operands_ — which requires an operand
  position to ride in. Removing the connective removes the slot. That is the deeper reason the
  withdrawal is right rather than merely convenient: the house style depends on the very thing the
  proposal removed.

#### What this turns on — and it is already ruled elsewhere, and already sequenced

The route above that gives the nicest surface, field-first resolution, is **not a new proposal**. It
is `IMPLICIT-PROPS-DESIGN.md` §11.7 **R5, field-opening, RULED 2026-09-04 (accept)**: the fields of
a record-typed `GIVEN`, function or section are in scope **by bare name** within the function that
sees the binder, with a defined rank — `WHERE`/`LET` locals, the function's own `GIVEN`, fields
opened from it, section `GIVEN`s, fields opened from those, selectors — and a collision between two
opened records sharing a field name is an **error**, at the read naming both and at the declaration
that opens the second. `r's f` remains always available. It is ruled but **not built** ("implemented
after discharge lands").

And R-Q4's own mark already sequenced this work behind it, in Meng's words on 2026-09-07:

> _"Perhaps the WHOSE projection could take advantage of the field-opening logic from the
> section-givens work."_ — with `WHOSE` recorded **PROPOSED, sequenced after §11.7 R5 is built**
> (§2.5, R-Q4; and `Filter ::= 'WHOSE' Expr` already carries that note in §15).

So the question is not unanswered. It is **sequenced**, and this section's contribution is to say
what R5 does and does not settle for it.

**What R5 settles.** Two opened records sharing a field name collide loudly. A bare field name is a
real, ranked binding rather than an ad-hoc insertion, so `WHOSE x AT LEAST N AND y EQUALS M` would
resolve `y` as a field under an ordinary scoping rule — no whole-expression rewriting, and nothing
for a connective to be applied to. That is a materially better answer than either the retracted
insertion rule or one-atom sugar.

**What R5 does not settle, and what this section exists to record.** Its rank list is entirely
_local_: locals, `GIVEN`s, opened fields, section `GIVEN`s, selectors. **A top-level definition is
not in it.** The collision that bites `WHOSE` is not two opened records — it is an opened field
against a top-level `MEANS` of the same name, which is accepted today (measured 2026-09-08:
`monthly_rent MEANS 42` alongside `DECLARE Party HAS monthly_rent`). Under R5's rank the opened
field would presumably shadow the top-level name silently.

**Which means the hazard does not disappear under R5 — it reverses direction.** Without opening,
`y` silently means the top-level term. With opening, `y` silently means the field. Both are silent;
they differ only in which reading a drafter loses. **That reversal is the angst, stated exactly**,
and it is why this belongs in the spec rather than in a bench card: no mark on a card disposes of
it, because the choice is not between safe and unsafe but between two silences.

**The layout-conjoined route above would have been the one exception, by construction** — it did not
pick a side of the reversal, it removed the question from this construct by making the field
position syntactic. It is withdrawn anyway, because the synthesis below reaches the same place
without a new mechanism, and because the language already had the layout it asked for. What survives
from it is the observation that `WHOSE` need not wait on R5's top-level answer to be **useful**,
only to be **complete** — which is a change to R-Q4's recorded sequencing and should be ruled as
such.

#### The measurement — RUN 2026-09-09, and it does not say what was hoped

Across `jl4/examples/**` and `jl4-core/libraries/*`: **1146 distinct field names, 3462 top-level
names, 30 that are both.** Cross-file overlap only bites under `IMPORT`, so the number that counts
is **same-file collisions: 5** — four in `jl4/examples/legal/regcf/regcf-wizard.l4`, one in
`jl4/examples/blawx/imported/beard_tax.l4`.

**They are real, and they are deliberate.** `regcf-wizard.l4:597-602` is the purest form — a record
construction in which the field and the value share a spelling:

```l4
`what you must still line up`  IS  `what you must still line up`
`after you raise you must`     IS  `after you raise you must`
`law as in force`              IS  `law as in force`
```

Left of `IS` is a **field** (`:167`, `:168`, `:170`); right of it is a **top-level `MEANS`**
(`:363`, `:373`, `:393`). `beard_tax.l4` is the same idiom from the other side:
`DECIDE facial_hair_length_mm x IF isJust (x's facial_hair_length_mm)` (`:63-64`) — a derived
function named after the field it derives from, disambiguated by `x's`.

**So the hoped-for answer — zero, therefore extend R5's rank to top-level names with a collision
error — is not available.** That extension would refuse five sites of an idiom that says something
a drafter should be able to say: _this field is that concept_. Worse, under a rank in which opened
fields shadow top-level names, `` `law as in force` IS `law as in force` `` stops being a definition
and becomes a **self-reference**, silently.

**What the measurement does support**, and it is the better rule anyway: **an opened field must not
shadow a top-level name, and a collision is an error only at an AMBIGUOUS READ — never at the
declaration.** That is already R5's own shape for two opened records ("an error at the read naming
both records"), extended to the top-level case rather than to the declaration site. `r's f` remains
the escape hatch, and all five sites already use the explicit form where it matters.

Method and its limits, so the count can be re-derived or disputed: field names were taken from
lines matching `<name> IS A|AN|THE|ONE OF|LIST` indented under a `DECLARE`, top-level names from
column-zero `<name> MEANS` and `DECIDE <name>`. Backtick identifiers are handled; `GIVETH`-only
definitions and fields introduced by other spellings are not counted, so **5 is a floor, not a
ceiling**.

#### A synthesis, proposed 2026-09-08 (GM), not ruled: `WHOSE` is not sugar, it is R5 opening the member

Meng asked for a Hegelian reading, and suggested field-opening as the route. It is, and the reason
is that **thesis and antithesis share a false premise**.

- **Thesis** (pre-R-Q4): the filter holds a point-free predicate and the member is _supplied_ to it.
  Terse, English-shaped, and dead — because supplying means **applying**, and connectives are
  applicable too.
- **Antithesis** (R-Q4, current): the filter holds a Boolean expression and the member is _named_ in
  it. Composes with anything, and costs the drafter a repeated `t` in every conjunct — the
  "pronoun awaiting a complement" awkwardness that started this.

Both assume the member reaches the filter by **application** — the only question being who applies
it. R5 offers a third relation: the member reaches the filter by **scope**.

**So read `WHOSE` not as sugar over `t's`, but as the keyword that OPENS the member's fields over
the filter** — exactly what R5 already rules for a record-typed `GIVEN`, function or section, here
extended to the binder a quantifier introduces. Then:

```l4
EVERY Tenant t WHOSE monthly_rent AT LEAST 1000 AND standing EQUALS "current"
```

is not a rewrite of anything. `monthly_rent` and `standing` are **opened fields resolving under
R5's existing rank**; `AND` is just `AND`. Nothing is inserted, so the failure that killed the
thesis has nothing to attach to — and nothing is repeated, so the antithesis's cost is paid off.
The antithesis is preserved rather than discarded: `WHO t's monthly_rent …` stays available and
stays the answer wherever explicitness is wanted, and `r's f` is always available under R5 anyway.

**What this buys beyond the dilemma.**

- **The layout-conjoined form becomes optional style, not load-bearing.** Under opening, one
  constraint per line is a formatting choice a drafter may make for readability; it is no longer
  the only thing standing between `y` and the wrong namespace. That is worth having either way, but
  it should be chosen as style rather than adopted as a disambiguator.
- **The totality rule arrives from the other direction, and arrives better.** Opening can only put
  in scope the fields that exist on every constructor the member could still be. With a cast, that
  is the cast's arm. Without one, on a sum type whose field names are flat, it is the empty set —
  so `EVERY t WHOSE monthly_rent …` opens nothing and fails **at check time, naming the missing
  cast**, instead of reaching a run-time _"reached a CONSIDER that has no branch for it"_ that
  names neither the field nor the cast.

**What must be true for this to work, stated so it can be refuted rather than assumed.**

1. **R5 must extend from a record-typed binder to a CONSTRUCTOR's fields under a cast.** Its text
   (§11.7) says "the fields of a record-typed `GIVEN`, function or section"; a sum type narrowed by
   a cast is not that, and the extension is real work, not a reading.
2. **The quantifier's member must count as a binder the function "sees".** R5's rank is
   `WHERE`/`LET` locals, the function's own `GIVEN`, fields opened from it, section `GIVEN`s, fields
   opened from those, selectors. A quantifier member is none of those, so it needs a rank position
   of its own — innermost, since it is bound closest to the filter.
3. **It does NOT close the top-level collision.** An opened field against a top-level `MEANS` of the
   same name is still unresolved, because R5's rank has no entry for top-level names. The synthesis
   does not answer that — it **relocates it to R5, where it belongs**, and where the machinery to
   answer it (a rank plus a collision error) already exists. The measurement named above is what R5
   would need.

So the synthesis is not that the problem vanishes. It is that **the `WHOSE`-specific dilemma
dissolves into an already-ruled mechanism**, leaving exactly one question, in the document that owns
it, with the shape of its answer already ruled.

**No recommendation is recorded here on purpose**, and unlike §13.5 the reason is not only that this
changes what a drafter must write. It is that the question is **upstream of the quantifier**: it is
about how L4 resolves an unqualified name in the presence of records, it is already ruled in another
document as R5, and a filter clause is the wrong place to settle it.

## 14. Related Work

- **Hvitved's CSL**: Trace-based contract semantics, blame assignment
- **CSP (Hoare)**: Trace semantics, parallel composition, external choice
- **Petri Nets**: AND-join synchronization pattern
- **Hohfeld**: Jural correlatives (privilege/no-right)
- **Deontic Logic**: Obligation, permission, prohibition modalities

## 15. Appendix: Formal Grammar

Brought into line with §2.4 on 2026-09-07 (R-Q1–R-Q4 and R-Q7, §2.5), and again on 2026-09-08 for
the `roll` (§11.0.2). Until 2026-09-07 this appendix carried a `variable 'IN' set_expr` head that
§2.4 had already replaced with the pattern form, four quantifier words, a `WHERE` filter, and a
`predicate` sub-grammar that only the withdrawn insertion rule needed. `IN` is back as of
2026-09-08, but as a separate optional clause AFTER the pattern rather than as the head of it — the
pattern form is unchanged, and the roll is a `LIST`, not a `SET`.

```ebnf
quantified_deonton ::=
    quantifier pattern [roll] [filter]
    deontic_modal action_expr
    [temporal_constraint]
    [join]                          (* required whenever a continuation follows; R-Q1 *)

join ::= 'ONCE' threshold [temporal_constraint]
       | 'UPON' 'EACH' [temporal_constraint]
                                    (* threshold as §2.2.7.4: 'ALL' 'HAVE' is the barrier. The fork is
                                       'UPON' 'EACH', RULED 2026-09-07 (§2.5 R-Q1), and is NOT a
                                       threshold. hence_clause/lest_clause are siblings of the join in
                                       quantified_deonton above, not children of it: the parser makes a
                                       bare continuation a CHECK error, not a parse error. *)

quantifier ::= 'EVERY'              (* EACH, ALL, NO are not quantifiers: R-Q1, R-Q2, R-Q3 *)

no_prohibition ::= 'NO' pattern [filter] 'MAY' action_expr [temporal_constraint] [join]
                                    (* sugar for EVERY pattern [filter] SHANT …, join fixed to
                                       UPON EACH; R-Q3, §2.2.3 *)

pattern ::= constructor variable | variable

roll ::= 'IN' list_expr             (* the LIST the group is drawn from, of the party type. RULED and
                                       BUILT 2026-09-08 (§11.0.2). Read ONCE for the whole group, with
                                       the bound variable OUT of scope, so it may not name a member.
                                       Optional: with no roll, one is read out of an `elem v xs`
                                       conjunct of the filter instead (§11.0); with both, the roll is
                                       the IN clause and the conjunct merely narrows. *)

filter ::= 'WHO' boolean_expr       (* the bound variable is free in boolean_expr; R-Q4 *)
                                    (* 'WHOSE' boolean_expr: proposed, not ruled; §2.5 R-Q4 *)

deontic_modal ::= 'MUST' | 'MAY' | 'SHANT' | 'DO'

temporal_constraint ::= ['AFTER' (duration_expr ['OF' anchor] | date_expr)]   (* the opening edge: R-X5, §5.1.2; built 2026-09-16;
                                                                                act line only; written before the closing edge *)
                        ( 'WITHIN' duration_expr ['OF' anchor]   (* anchor: R-Q7, §5.1; built 2026-09-15. Beside an AFTER a bare
                                                                    WITHIN re-anchors on the opening (§5.1.2.2) *)
                        | 'BEFORE' date_expr )                   (* the absolute closing edge: R-X5; built 2026-09-16; act line only *)
                      | 'BY' time_expr                          (* unruled, unbuilt *)

hence_clause ::= 'HENCE' continuation

lest_clause ::= 'LEST' continuation

continuation ::= deonton | quantified_deonton | 'FULFILLED' | 'BREACH' ['BY' party_or_list]
```
