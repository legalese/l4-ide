> **Status (re-audited 2026-09-08 on `lang/every-runtime`, cut from `unstable` `6e9b57bb`):**
> the **FRONT END IS MERGED** — `every/build-1` landed on `unstable` as PR #360 (merge `734b8015`,
> 2026-09-07), so the lexer, parser, name resolution, type checker, printers, NLG, document export
> and state graph all carry `EVERY` and the join line on `unstable` today. **EVALUATION IS BUILT**
> on `lang/every-runtime` (2026-09-08, unmerged at the time of writing): §3.1's barrier, §3.2's
> fork, §3.3's distributive form, all four modals, R-T2's join deadline and nesting all run; see
> §11.0.1 for exactly what was built and what was not, and §11.0 for the roll-call rule that made
> it possible. The four witnesses are `jl4/examples/ok/every/run-{barrier,fork,roll,modals}.l4`.
>
> **THE ROLL IS NOW SAYABLE OUTRIGHT.** `EVERY Cast v IN xs` was RULED by Meng on 2026-09-08 and is
> BUILT on `lang/every-in` (branched from `lang/every-runtime`, unmerged at the time of writing):
> see **§11.0.2**, with `jl4/examples/ok/every/run-in.l4` as its witness and §2.4's grammar
> updated. `IN` is the spelling to reach for. The older inferred spelling of §11.0 —
> `WHO elem t xs` — still runs unchanged for a rule that writes no `IN`, and whether it should be
> deprecated is **open**, §13.5.
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
>   ruled, not built)**; **R-X5 (the window's edges, modified) and R-X6 (the early act, ruled),
>   §5.1.2, 2026-09-07, not built**; and three on 2026-09-08 — **W3, `THE OPENING` declined and
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
NO Tenant t WHO elem t tenants MAY sublet WITHIN term
    UPON  EACH                                -- the fork join, fixed by the sugar (R-Q1, RULED 2026-09-07)
    LEST  BREACH BY t                             -- the violator; the others are untouched
    HENCE `the term ended without a sublet`       -- SHANT's HENCE: the prohibition held

-- exactly:
EVERY Tenant t WHO elem t tenants SHANT sublet WITHIN term
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
> the barrier, `EACH` for the fork — is no longer the design. There is **one quantifier word,
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
   parties**. Today `RAND`/`ROR` breach carries **one operand** — the machine picks left for `RAND`
   and right for `ROR` by timestamp tie-break (`jl4-core/src/L4/EvaluateLazy/Machine.hs:1698-1730`,
   "consistently with CSL"). That is the same gap the six-ways page recorded for the any-join.
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
    EVERY Tenant t WHO elem t tenants
        MAY    Pay t theLandlord amount
        UPON   EACH                              -- fork: one receipt per cheque (R-Q1, RULED 2026-09-07)
        HENCE  PARTY theLandlord MUST Receipt theLandlord t amount WITHIN 5
    ONCE   sum OF amount AT LEAST rent               -- the state join is a measure over the cheques
    WITHIN due                                       -- one deadline, on the state
    HENCE  FULFILLED
    LEST   BREACH BY EVERY Tenant                    -- joint: everyone

-- divided rent: each tenant owes a share; no threshold; blame narrows
`rent owed severally` MEANS
    EVERY Tenant t WHO elem t tenants
        MUST   Pay t theLandlord amount PROVIDED amount AT LEAST share t
        WITHIN due
        UPON   EACH                              -- fork
        HENCE  PARTY theLandlord MUST Receipt theLandlord t amount WITHIN 5
        LEST   BREACH BY t
```

(Respelled 2026-09-07 under R-Q1 and R-Q4: `HENCE FOR EACH` → `UPON EACH … HENCE`, `EACH Tenant t`
→ `EVERY Tenant t … UPON EACH`, `WHO member_of tenants` → `WHO elem t tenants`. The two join lines
of the joint form are the two layers R-T2 and R-Q5 distinguish: the inner one is the act layer, the
outer one the state.)

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
| R-T3 — `BY` takes a party or a list of parties; a compound breach collects the set of unfulfilled operands                                   | **RULED 2026-09-06**, accept            |
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
- **R-T3.** `Breach Anno (Maybe (Expr n)) (Maybe (Expr n))` (`Syntax.hs:342`) holds one optional
  party; the compound case at `jl4-core/src/L4/EvaluateLazy/Machine.hs:1698-1730` picks one operand
  by operator and timestamp under a comment that the assignment "may be wrong if the events are
  passed out of order wrt time". A set is what a wizard or an export needs to answer "who is in
  breach". 34 golden files print a breach; those with compound failure will re-bless with the fuller
  answer when this is built.
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
holds) or to a ledger cell read at the join; a set-valued breach (R-T3); goldens under `ok/` for
the two rent forms and the s 177 quorum; and a page under `doc/` before the work is closed (repo
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
                                      -- The connective is 'OF' and only 'OF' (R-Q7A, §5.1.1). Unbuilt.
                     | 'BEFORE' Expr                      -- R-X5: an absolute DATE, the closing edge; 'BEFORE' Duration is refused. Unbuilt
                     | 'AFTER' (Duration ['OF' Anchor] | Expr)   -- R-X5: the opening edge, duration or DATE; never re-anchors. Unbuilt
                     | 'BY' Deadline                      -- unruled and unbuilt; TKBy serves FOLLOWED BY, DIVIDED BY, BREACH BY

Anchor ::= 'THE' ('JOIN' | 'DEADLINE' | 'ARMING' | 'OPENING')   -- 'OPENING' proposed by R-X5 (§5.1.2), residue   -- R-Q7B: the three lifecycle positions. THE is already
                                      -- a keyword (Lexer.hs:273); JOIN, DEADLINE and ARMING are matched by
                                      -- SPELLING and not reserved, exactly as EACH is in UPON EACH.
         | Event                      -- R-Q7: any recorded event, which the drafter has already named
         | Expr                       -- R-Q7C: anything of type DATE. The slot is a three-way union the
                                      -- checker discriminates; no new keyword. Spellings RULED 2026-09-07
                                      -- (R-Q7A/B/C, §5.1.1); unbuilt.

HenceClause ::= 'HENCE' Continuation

LestClause ::= 'LEST' Continuation

Continuation ::= Deonton
               | QuantifiedDeonton
               | 'FULFILLED'
               | 'BREACH' ['BY' PartyOrList]   -- R-T3: a party or a list of parties
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
| R-Q7 | the continuation clock: `HENCE` from what, `LEST` from what? | **modify** — _"e but with a as default when no OF?"_                                                                        | A drafter may name the anchor (`WITHIN 5 days OF …`); unanchored, `HENCE` counts from the join's firing (today's rule) and `LEST` from the missed deadline (§5.2) — the latter a **change** from today's revealing-event anchor.                                                                                                                          | §2.4, §5.1, §5.2                           |

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
  the same example** (owed list below).
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
  2026-09-07). The card's earlier `BY date` escape hatch is struck: R-T2 says nothing about `BY`, a
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
- `doc/reference/regulative/README.md:104` promises `BEFORE` for absolute deadlines. **R-X5
  (2026-09-07, §5.1.2) keeps that reading**, so the page becomes true when `BEFORE` is built rather
  than needing correction; `jl4/experiments/purchase.l4`'s seven `BEFORE n days` lines migrate to
  `WITHIN`.
- **The BPMN export cannot tell a barrier from a fork, and its fidelity report does not say so.**
  Measured 2026-09-07 by the GM on a binary built from `every/build-1`: one rule exported twice,
  once with `ONCE ALL HAVE` and once with `UPON EACH`, gives **byte-identical** BPMN XML and a
  **byte-identical** fidelity report. The report names the deontic modality (F1), the
  bearer-versus-performer gap (F2), the missing deadline unit and the absent as-of date (F5), and
  never mentions the join or the quantifier; the only trace of `EVERY` anywhere in the output is a
  lane label. This is introduced by this branch — `unstable` has no quantifier to lose — and it is
  the one export gap a reader cannot discover from the export, because the artifact whose job is to
  list the losses is silent about it. Recorded on `doc/reference/regulative/EVERY.md` as well.
  Not yet located: the collapse may be in the state graph the exporter reads or in
  `L4.Bpmn.Lower`; whoever fixes it should measure which before writing a finding.
- `doc/reference/regulative/README.md:82-95` documents `WITHIN 5 days OF notice` as an anchored form.
  **Probed 2026-09-07:** it is a parse error (`unexpected OF` at the `OF`) on the installed binary of
  27 August and on the 4 September probe binary, with or without `days`. The page is owed a correction
  in the PR that builds the anchor of R-Q7 (§5.1), or sooner.
- `doc/tutorials/obligations/what-follows.md:153` and `:470` teach today's `LEST` anchor (the first
  event after the deadline) and a `WITHIN 13` workaround built on it. When R-Q7's `LEST` default is
  built (§5.2) that page changes and the trace goldens re-bless.
- In this document: extend §3–§9 to `SHANT` (R-Q3); define the release / substitute / join events
  (R-Q6, §13.4). The fork's words (R-Q1) were ruled 2026-09-07 and are recorded above; **the anchor
  spellings (R-Q7) were ruled the same day and are recorded at §5.1.1** — `OF` alone as the connective,
  `OF THE JOIN`/`OF THE DEADLINE`/`OF THE ARMING` for the lifecycle positions, and a date-valued
  expression admitted in the slot. Ruled, not built.
- Opened by those rulings, and owed to nobody yet: **the `AFTER` window** (§5.1.2, sketched on Meng's
  request and not ruled — it owes the early-act semantics, the empty-window check, and its meaning
  under `LEST`); **an anchor picked by an expression** rather than named, which R-Q7B's note flags as
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
What the build does NOT do is §6.1's blame set — see §11.0.1.

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
  is the set (§6.1; a set-valued `BY` under R-T3). §2.2.7.6's `rent owed jointly` is the case: `MAY`
  acts inside, one `LEST` at `due`.
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
   **missed deadline** — §5.2, where it is recorded as a change.

The cost the ruling accepts: an early-completing cast gives the continuation an early deadline
("within five days of the last signature", not "on the completion date"); the named anchor is what
makes the other clause writable. The card's earlier escape hatch, "write an absolute `BY date`", is
struck: R-T2 ruled nothing about `BY` (its subject is `WITHIN` in two positions), and a deadline `BY`
is unruled and unbuilt (§2.4).

**The manual's `OF` form does not run.** `doc/reference/regulative/README.md:82-95` documents
`WITHIN 5 days OF notice` and `` WITHIN 5 days OF `order confirmation` `` as an anchored form.
Probed 2026-09-07 on the installed binary of 27 August and on the 4 September probe binary,
`JL4_LIBRARY_PATH` unset: both report `unexpected OF` at the `OF`, with or without `days`. The
`deadline` production is `WITHIN` followed by one expression (`Parser.hs:2534-2536`), and `OF` is not
an operator inside an expression. The page is owed a correction (§2.5's owed list, not made in the
change that recorded this section); this ruling is the design that would make its sentence true.

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

#### 5.1.1 The anchor's spelling — RULED 2026-09-07 (R-Q7A, R-Q7B, R-Q7C)

§5.1 above ruled the anchor's **mechanism** and its **defaults** and left its **spelling** open.
Three cards — the Anchor Bench, an artifact of 2026-09-07, **not in the tree**
(<https://claude.ai/code/artifact/0e3b1279-79c2-4616-ada7-bad7473e9630>) — closed it. All three were
marked **accept**, on the recommended option in each case, between 03:37 and 03:41 UTC on
7 September 2026. Meng's notes are quoted verbatim, and each one opens a follow-up rather than
qualifying the ruling; the follow-ups are listed at the end of this section and in §2.5's owed list. **None of this
is built**: the grammar in §2.4 carries it, and no parser production exists.

**R-Q7A — the connective is `OF`, and only `OF`.** Not `AFTER`, and not the two as synonyms. `OF` is
already a keyword (`Lexer.hs:268`, `TKOf`), so the slot reserves no new word, and it is the form
`doc/reference/regulative/README.md:82-95` already documents. This is a grammar addition either way:
measured 2026-09-07 on a binary built from this branch, `WITHIN 5 OF notice` is a **parse error at
the `OF`**, because `WITHIN` takes exactly one expression (`Parser.hs:2534-2536`) and `OF` is not an
operator inside one.

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
keyword (`Lexer.hs:273`, `TKThe`), and `JOIN`, `DEADLINE` and `ARMING` are matched by **spelling**
rather than reserved — the same move `UPON EACH` makes for `EACH`, ruled the same morning (R-Q1,
§2.5). So the whole of R-Q7B costs zero new reserved words. Measured 2026-09-07: none of the three
nouns appears as an identifier anywhere in the goldened corpus.

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
for the identifier_, because `days` names nothing. Add one line of ordinary L4 —
`GIVEN n IS A NUMBER GIVETH A NUMBER DECIDE n days IS n` — and the same file reports **Check
succeeded**. So `days`, `` `business days` ``, `` `weeks not containing a public holiday in
Singapore` `` are all already expressible through mixfix and backticked names; what is missing is a
calendar for them to consult, which is a library to write and not a keyword to reserve. The corpus
already writes `` WITHIN `five business days` `` 11 times, which is exactly this move made by hand.

**What these three do not settle.** The `AFTER` window (§5.1.2, sketched and not ruled); an anchor
picked by an expression rather than named (R-Q7B's note); the date library (R-Q7C's note); and
whether an anchored `WITHIN` under `LEST` may name `THE JOIN` at all, which is a well-formedness
question — under `LEST` the join did not fire.

#### 5.1.2 `AFTER` and `BEFORE`: the window's two edges — MODIFIED 2026-09-07 (R-X5); the early act RULED (R-X6); not built

This section answers the question in R-Q7A's note ("Shall we try to sketch a design for that now?").
R-X6 is ruled and R-X5 is a design Meng modified and asked to have worked through; both are
recorded below. **Nothing here is built.**

**The gap.** `WITHIN d` gives a window one edge, the closing one; the opening edge is the anchor
itself, so an obligation is performable from the instant it arms. Meng's cooling-off example is the
counter-case, and it is ordinary: _the customer may place a new order after a three-business-day
cooling-off period, within 30 days_. Nothing in the language today can say when a window **opens**.

**We have already written this construct.** `jl4/experiments/purchase.l4` — an aspirational sketch
that has never parsed — uses it throughout: a bare `BEFORE 30 days` at `:97` and `:102`, and the
full two-edged form in four nested continuations at `:152-168`. It is worth reading because it
disagrees with the note above on the one point that matters:

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

**`AFTER` does not re-anchor.** Both edges measure from the same anchor, so the statutory two-offset
window is the default and is written as the statute says it:

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

**What this does to earlier rulings and files.** `doc/reference/regulative/README.md:104`, which
promises `BEFORE` for absolute deadlines, becomes **true when built** instead of corrected.
`jl4/experiments/purchase.l4` migrates by one word per line — its `BEFORE n days` at `:97`, `:101`,
`:134`, `:153`, `:159`, `:164`, `:169` become `WITHIN n days` — with meaning preserved, because its
`AFTER` never re-anchored either. R-Q7C stands (a date as an **anchor**, `WITHIN 5 OF closingDate`,
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
**Not built.**

**Cost, measured 2026-09-07 on this branch.** `AFTER` and `BEFORE` are **not** keywords
(`jl4-core/src/L4/Lexer.hs`; the keyword table is an exact, case-sensitive `Map.lookup` on the raw
identifier text at `identifierOrKeyword`, `Lexer.hs:670-675` on `unstable` since #360 landed).
Reserving `AFTER` touches six lines of `.l4` in the whole
tree: four are `purchase.l4`'s aspirational `AFTER n days` above, in `jl4/experiments/`, which is
**in no goldened glob** and already fails to parse for unrelated reasons; the other two are inside
backticked section names in `housing-act-ground-5F.l4:605,:726`, and a backticked name never consults
the keyword table. Zero goldened corpus files, zero canon files, zero `doc/` files — the same shape
`UPON` measured at before it was taken.

**What this sketch owes before it could be ruled**: the early-act semantics above; whether `BEFORE`'s
offset is checked against `AFTER`'s at compile time (`AFTER 30 BEFORE 5` is an empty window and
should be an error, not a rule that can never fire); and what the pair means under `LEST`, where the
anchor is a missed deadline rather than a performance.

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

**What the machine does today, and why this is a change.** The machine anchors a `LEST`
continuation at the stamp of the event that **revealed** the miss, not at the deadline. The comment
at `Machine.hs:1550-1552` says so in terms — "the continuation's clock is anchored at the revealing
event's stamp (the README is silent on the anchor; this is the historical behavior)" — and
`:1583-1589` implements it, carrying the revealing event's `ev'timeR` into the continuation's frame.
The refuters' probe: `PARTY P MUST sign WITHIN 10 LEST PARTY Q MUST release WITHIN 5`, the miss
revealed by an event at 14, reports Q's deadline as 19 (14 + 5), not 15 (10 + 5); a release at 18
comes back `FULFILLED`. Under that rule the defaulting party controls when its own cure period starts
— a maker who misses the date and then stays silent has no return-of-funds deadline until someone
else acts — which is why the deadline anchor was chosen over the status quo (listed on the bench as
its own option so that choosing this was visibly a decision). The anchor is a timestamp computed
when the miss is revealed; firing still waits for an event, so no timer is needed.

Blast radius when built: the single-party `LEST` anchor and every trace golden that prints a
reparation deadline; and `doc/tutorials/obligations/what-follows.md:153` and `:470`, which teach
today's rule and a `WITHIN 13` workaround built on it (§2.5's owed list).

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
    (EVERY Director d WHO elem d board MUST sign WITHIN 30
        ONCE ALL HAVE
        HENCE FULFILLED
        LEST  BREACH)                     -- blame = the non-signers (§6.1), a set under R-T3
    RAND
    (PARTY secretary MUST file WITHIN 30
        HENCE FULFILLED
        LEST  BREACH BY secretary)
-- Two directors miss the date and the secretary files: the compound breach names the two
-- directors. Today's fold would name ONE operand by timestamp tie-break (Machine.hs:1699-1730).

-- (2) a quantified obligation as one operand of ROR: unanimous written consent OR a chair's decision
`consent or decision` MEANS
    (EVERY Director d WHO elem d board DO consent WITHIN 14
        ONCE ALL HAVE
        HENCE `resolution passes`)
    ROR
    (PARTY chair MUST decide WITHIN 14
        HENCE `resolution passes`)
-- Either branch fulfils the compound (Machine.hs:1757-1764); it is breached only when BOTH are
-- lost (:1699-1706), and then names both operands' non-performers under R-T3.

-- (3) a barrier whose HENCE is itself a RAND: after the last signature, two things follow in parallel
`sign then close` MEANS
    EVERY Director d WHO elem d board MUST sign WITHIN 30
        ONCE  ALL HAVE
        HENCE (PARTY escrow    MUST `release funds`       WITHIN 5
               RAND
               PARTY secretary MUST `file the resolution` WITHIN 7)
        LEST  BREACH
-- Both continuation clocks start at the join's firing, the last signature (R-Q7, §5.1).
```

What this needs before it can be a golden: the `ONCE` line (R-Q1); the set-valued `BY` (R-T3); and,
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
3. **The roll.** Every runnable example already writes it — §2.1's `WHO elem p signatories`,
   §2.2.7.6's `WHO elem t tenants`, and the corpus's `jl4/examples/ok/every/who-filter.l4`.
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

**Not built, and each one is a place a run gives a coarser answer than this document specifies:**

- **§6.1's blame set.** A failed barrier names ONE non-completer — the first in roll order —
  because `ReasonForBreach` carries one party. This is R-T3 (§2.2.7.5 point 4), unbuilt, exactly as
  that point predicted. Measured 2026-09-08: reversing the roll reverses which member is named,
  so the choice is deterministic and it is roll order.
- **§5.2's deadline anchor.** A `LEST` continuation is anchored at the revealing event's stamp, not
  at the missed deadline. §5.2 records that changing this changes the **single-party** path and
  every trace golden that prints a reparation deadline; the build deliberately made `EVERY` match
  the single-party path rather than diverge from it, so that §5.2 remains one change to make in one
  place. It is still owed.
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
EVERY Director d WHO elem d board MUST sign WITHIN 30 days
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
— visible now that R-T3's breach carries a set.

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

### 13.5 Should the INFERRED roll be deprecated? — OPEN, put to Meng 2026-09-08

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

**No recommendation is recorded here on purpose.** This is a question about what a drafter must
write, which §11.0.2 gives as the reason the build stopped short of it; the measurements above are
the whole of what the build knows, and they are here so the ruling can be made without redoing
them.

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

The measurement a ruling would need, and which nothing has yet run: **how many names in the corpus
are both a record field and a top-level definition.** If the answer is zero, R5's rank can be
extended to top-level names with a collision error and the silence closes. If it is not zero, the
extension is a breaking change and the count says how breaking.

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

temporal_constraint ::= 'WITHIN' duration_expr ['OF' anchor]   (* anchor: R-Q7, §5.1; unbuilt *)
                      | 'BEFORE' time_expr                      (* planned, unbuilt *)
                      | 'BY' time_expr                          (* unruled, unbuilt *)

hence_clause ::= 'HENCE' continuation

lest_clause ::= 'LEST' continuation

continuation ::= deonton | quantified_deonton | 'FULFILLED' | 'BREACH' ['BY' party_or_list]
```
