> **Status (audited 2026-07-03):** OPEN — no `EVERY`/`EACH` quantifiers; regulative rules bind a single `PARTY` only.
>
> - `EVERY`/`EACH`/`NO` are not lexer keywords (`jl4-core/src/L4/Lexer.hs`); `ALL` exists only for `FOR ALL`.
> - `obligation` parser takes exactly one party expr (`Parser.hs:1774-1775`); no barrier/fork semantics, `WHO`-filter, or `BarrierObligation` runtime. Syntax appears only in non-compiling aspirational examples (`jl4/experiments/regulative-powers.l4:4`).

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
    EVERY p                         -- p has type Person (from DEONTIC)
        WHO    predicate            -- predicate : Person -> Boolean
        MUST   action
        WITHIN deadline
        HENCE  success_continuation
        LEST   failure_continuation
```

The `WHO` clause takes a predicate expression. The bound variable `p` is implicitly inserted as the **first** argument to this predicate. This follows natural English where the person is the subject of the predicate.

For set membership, use `member_of` (Haskell's `elem`):

```l4
GIVEN signatories IS A LIST OF Person

GIVETH DEONTIC Person Action
sign_all MEANS
    EVERY p
        WHO    member_of signatories    -- expands to: member_of p signatories
        MUST   sign
        WITHIN 30 days
        HENCE  closing_complete
        LEST   deal_falls_through
```

The predicate `member_of signatories` expands to `member_of p signatories` where `member_of : a -> List a -> Boolean` (exactly Haskell's `elem`). This reads naturally as "is p a member of signatories?"

This design is more expressive than explicit set binding because:

1. **Type inference**: No redundant type annotation; `p`'s type comes from the deontic context
2. **Predicate is first-class**: Any `PartyType -> Boolean` function works
3. **Predicate subsumes sets**: `WHO member_of some_list` achieves explicit set binding
4. **Richer constraints**: `WHO is_adult AND is_shareholder AND NOT is_conflicted`
5. **Composable**: Predicates can be combined with AND/OR/NOT

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
EACH p_x
    SHANT  solicit_employees_of p_y
    WHERE  differs_from p_x p_y
```

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

`EVERY` and `EACH` are **not synonyms**—they have distinct continuation semantics:

| Quantifier | Semantics         | HENCE behavior                                               |
| ---------- | ----------------- | ------------------------------------------------------------ |
| `EVERY`    | Barrier/Join      | Collects all completions, fires HENCE **once** when all done |
| `EACH`     | Fork/Distributive | Fires HENCE **for each** completion independently            |

> **Proposed vocabulary — Meng, 2026-09-06, not yet ruled; researched the same night and the
> research recommends against.** _"The EVERY vs EACH semantics may not stand up to scrutiny from a
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

**Formal distinction:**

- `EVERY p ... HENCE h` ≈ `(P1 ||| P2 ||| P3) ; h` (CSP sequential composition after interleaving)
- `EACH p ... HENCE h` ≈ `(P1 ; h) ||| (P2 ; h) ||| (P3 ; h)` (CSP interleaving of each with its continuation)

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

The measure defaults to a count of performers. `EVERY` and `EACH` are **orthogonal** to this table:
they say where the continuation attaches (§3.1–3.2), the table says when the join fires. `EACH` with
a threshold is meaningless (a fork has no join); `EVERY` is `ALL OF` plus one continuation.

##### 2.2.7.4 Syntax

The memo's continuation marker (§7.2 there: `HENCE ONCE ALL HAVE …` / `HENCE FOR EACH …`) already
puts the join on the continuation. `ONCE` generalises by taking a threshold instead of the word
`ALL`:

```
ThresholdJoin ::= QuantifiedDeonton 'ONCE' Threshold [TemporalConstraint] [HenceClause] [LestClause]

Threshold     ::= 'ALL' 'HAVE'
                | 'ANY' 'HAS'
                | Count 'OF' Cast 'HAVE'           -- SOME 2 OF Director HAVE
                | Measure Comparison Expr          -- sum OF amount AT LEAST rent
                | Threshold 'AND' Threshold        -- the s 177 quorum

Count         ::= 'SOME' Number | 'AT' 'LEAST' Number       -- synonyms, see below
Measure       ::= 'count' | Aggregate 'OF' Binder            -- the Binder is a name bound in the action pattern
```

A quantifier-prefix spelling is sugar for the same thing when there is no per-act continuation:

```l4
SOME 2 OF Director d DO sign WITHIN 30 HENCE `resolution passes`
-- ≡  EVERY Director d DO sign  ONCE SOME 2 HAVE  WITHIN 30 HENCE `resolution passes`
```

`DO`, not `MUST`, in the prefix form — R-T5's style note (Meng, 2026-09-06): no single director owes a
signature, so the act is stated neutrally and the obligation lives on the join.

**Ruled in passing, Meng, 2026-09-06:** `SOME m OF …` is a synonym for `AT LEAST m OF …`. His note
on the word: _"some" is properly used in this sense in a sort of archaic sense_ — "some two of
them", where _some_ picks out an unspecified subset of the stated size. One hazard for the
definitional sentence, recorded because this spec's whole vocabulary debate was about first-time
readers: the modern collocation _"some 200 people"_ reads as _approximately_, so the page that
introduces `SOME m OF` must say _at least_ in its first sentence.

Name collisions were checked. `SOME` is not a keyword (`jl4-core/src/L4/Lexer.hs` has `OF`, `AT`,
`LEAST`, `ALL`; not `SOME`). An earlier proposal spelled an actor-agnostic contract head
`DEONTIC SOME who` and was **rejected** on arity and event-typing grounds
(`specs/done/DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md`, "Do NOT make the contract head
actor-agnostic"); that was a type, not a quantifier, and the rejection does not reach this use —
said here so that a later reader who greps for `SOME` does not conclude the quantifier was ruled
out. `ALL` and `NO` already appear in §2.4's `Quantifier` production with no semantics given
anywhere in this document; under this section `ALL` is the `N OF N` spelling and `NO` is still
unspecified.

##### 2.2.7.5 Semantics, in six points

1. **The join is over an accumulator.** Each performance that matches the quantified pattern adds
   to a per-contract accumulator (a count, or the bound measure); the `ONCE` condition is evaluated
   against it after every matching event. A `HENCE FOR EACH` continuation still fires per event
   (fork), independently of the join.
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
   filter, exactly as the existing `EVERY` does. The performer check of the value-actor encoding is
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
    EVERY Tenant t WHO member_of tenants
        MAY    Pay t theLandlord amount
        HENCE FOR EACH                               -- fork: one receipt per cheque
               PARTY theLandlord MUST Receipt theLandlord t amount WITHIN 5
    ONCE   sum OF amount AT LEAST rent               -- the join is a measure over the cheques
    WITHIN due                                       -- one deadline, on the state
    HENCE  FULFILLED
    LEST   BREACH BY EVERY Tenant                    -- joint: everyone

-- divided rent: each tenant owes a share; no threshold; blame narrows
`rent owed severally` MEANS
    EACH Tenant t WHO member_of tenants
        MUST   Pay t theLandlord amount PROVIDED amount AT LEAST share t
        WITHIN due
        HENCE  PARTY theLandlord MUST Receipt theLandlord t amount WITHIN 5
        LEST   BREACH BY t
```

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
| R-T6 — the cast is fixed at arming; a change of cast is an explicit event                                                                    | **RULED 2026-09-06**, accept, with note |
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
EACH p_x
    MAY    terminate
    HENCE  EVERY p_y
               WHO  differs_from p_x   -- differs_from : a -> a -> Boolean
               MUST settle_outstanding_accounts_with p_x
               WITHIN 30 days
```

The predicate `differs_from p_x` expands to `differs_from p_y p_x` (i.e., `p_y /= p_x`), reading as "does p_y differ from p_x?" This filters the inner quantifier's domain to exclude the outer-bound variable.

Note: Since `/=` is symmetric, the argument order doesn't affect the result. The key point is that `differs_from : a -> a -> Boolean` with `p_y` inserted as the first argument and `p_x` as the second.

### 2.4 Full Grammar

```
QuantifiedDeonton ::=
    Quantifier Pattern [Filter]
        DeonticModal Action
        [TemporalConstraint]
        [HenceClause]
        [LestClause]

Quantifier ::= 'EVERY' | 'EACH' | 'ALL' | 'NO'

Pattern ::= Constructor Variable      -- EVERY Tenant t   : the primary form; the constructor selects the cast
          | Variable                  -- EVERY t          : the unfiltered case; every value of the actor type

Filter ::= 'WHO' Predicate
         | 'WHERE' Predicate

DeonticModal ::= 'MUST' | 'MAY' | 'SHANT'

TemporalConstraint ::= 'WITHIN' Duration
                     | 'BEFORE' Deadline
                     | 'BY' Deadline

HenceClause ::= 'HENCE' Continuation

LestClause ::= 'LEST' Continuation

Continuation ::= Deonton
               | QuantifiedDeonton
               | 'FULFILLED'
               | 'BREACH'
```

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
Nothing is built.

## 3. Semantics Overview

### 3.1 EVERY: The Barrier Model

`EVERY` with HENCE/LEST has **barrier semantics**:

- **HENCE fires** when ALL parties complete (join point)
- **LEST fires** when the barrier becomes unachievable (deadline or early failure)

```l4
EVERY p MUST X HENCE shared_h LEST shared_l
-- Desugars to barrier structure, NOT simple conjunction
```

**Process algebra correspondence for EVERY:**

| Model         | Representation                                                     |
| ------------- | ------------------------------------------------------------------ | --- | --- | --- | --- | --- | ------------------------------------------------------- |
| **Petri Net** | AND-join: all input places must have tokens for transition to fire |
| **CSP**       | `(P1                                                               |     |     | P2  |     |     | P3) ; HENCE` — interleaving with sequential composition |
| **Counting**  | Semaphore initialized to n; HENCE fires when count reaches 0       |

### 3.2 EACH: The Fork Model

`EACH` with HENCE/LEST has **fork semantics**:

- **HENCE fires** independently for each party that completes
- **LEST fires** independently for each party that fails

```l4
EACH p MUST X HENCE h(p) LEST l(p)
-- Desugars to: (p1 MUST X HENCE h(p1) LEST l(p1)) ||| (p2 MUST X HENCE h(p2) LEST l(p2)) ||| ...
```

**Process algebra correspondence for EACH:**

| Model         | Representation                                    |
| ------------- | ------------------------------------------------- | --- | --- | --------- | --- | --- | -------------------------------------------------- |
| **Petri Net** | Parallel independent transitions, no join         |
| **CSP**       | `(P1 ; h1)                                        |     |     | (P2 ; h2) |     |     | (P3 ; h3)` — each process has its own continuation |
| **Counting**  | No shared counter; each completion is independent |

### 3.3 Without HENCE/LEST: Both Equivalent

When there is no continuation clause, EVERY and EACH are semantically equivalent—both produce distributive obligations:

```l4
EVERY p MUST X    ≡    EACH p MUST X    -- when no HENCE/LEST
-- Both desugar to: (p1 MUST X) ||| (p2 MUST X) ||| ...
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

When HENCE fires, continuation deadlines are relative to **last completion time**:

```
EVERY p
    MUST   sign
    WITHIN 30
    HENCE  escrow_agent MUST release_funds WITHIN 5

Timeline:
t=0:  Obligation entered
t=10: Party A signs
t=20: Party B signs
t=25: Party C signs  ← barrier achieved, t_last = 25
t=25: HENCE spawns with reference time = 25
      escrow_agent's deadline = 25 + 5 = 30
```

### 5.2 LEST Reference Time

When LEST fires, continuation deadlines are relative to **failure time**:

- If deadline failure: `t_ref = deadline`
- If early failure: `t_ref = detection_time`

### 5.3 Temporal Forking (MAY Exercise)

When a party exercises a MAY, the HENCE obligations activate relative to exercise time:

```l4
EACH p_x
    MAY   terminate
    HENCE EVERY p_y
              WHO    differs_from p_x
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
(EVERY seller MUST deliver HENCE ...)
RAND
(EVERY buyer MUST pay HENCE ...)
```

Both quantified obligations must be satisfied (regulative conjunction).

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

### 11.1 Runtime State

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

## 14. Related Work

- **Hvitved's CSL**: Trace-based contract semantics, blame assignment
- **CSP (Hoare)**: Trace semantics, parallel composition, external choice
- **Petri Nets**: AND-join synchronization pattern
- **Hohfeld**: Jural correlatives (privilege/no-right)
- **Deontic Logic**: Obligation, permission, prohibition modalities

## 15. Appendix: Formal Grammar

```ebnf
quantified_deonton ::=
    quantifier variable 'IN' set_expr [filter]
    deontic_modal action_expr
    [temporal_constraint]
    [hence_clause]
    [lest_clause]

quantifier ::= 'EVERY' | 'EACH' | 'ALL' | 'NO'

filter ::= 'WHO' predicate | 'WHERE' predicate

deontic_modal ::= 'MUST' | 'MAY' | 'SHANT'

temporal_constraint ::= 'WITHIN' duration_expr
                      | 'BEFORE' time_expr
                      | 'BY' time_expr

hence_clause ::= 'HENCE' continuation

lest_clause ::= 'LEST' continuation

continuation ::= deonton | quantified_deonton | 'FULFILLED' | 'BREACH'

predicate ::= 'is' 'not' variable
            | 'is' 'in' set_expr
            | 'meets' predicate_name
            | predicate 'AND' predicate
            | predicate 'OR' predicate
            | 'NOT' predicate
            | '(' predicate ')'
```
