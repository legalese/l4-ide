> **Status (re-audited 2026-09-07 on `unstable` `5dc0ca19`; first audited 2026-07-03):** OPEN
> upstream — on `unstable`, nothing quantified is built and regulative rules bind a single `PARTY`
> only. The bullets below describe that tree. **On branch `every/build-1` the FRONT END is built**
> (2026-09-07, unmerged): the lexer, parser, name resolution, type checker, printers, NLG, document
> export and state graph all carry `EVERY` and the join line; evaluation is not built and says so.
> Where a claim below is false on that branch, the entry says which tree it describes.
>
> - On `unstable`: `EVERY`, `EACH`, `NO`, `ONCE`, `HAVE`, `WHO`, `WHOSE` and `SOME` are not lexer keywords (the keyword
>   table in `jl4-core/src/L4/Lexer.hs`; `identifierOrKeyword` at `Lexer.hs:654-659` is an exact map
>   lookup, so there are no soft keywords). `ALL` is `TKAll` (`Lexer.hs:317`), consumed by `FOR ALL`
>   (`Parser.hs:1244-1245`) and `RECALL ALL` (`Parser.hs:2375`).
> - `obligation` takes exactly one party expression after `PARTY` (`Parser.hs:2503-2513`); `HENCE` and
>   `LEST` are parsed there and nowhere else (`Parser.hs:2538-2544`). No barrier, fork, filter or
>   `BarrierObligation` runtime exists. The syntax appears only in non-compiling sketches under
>   `jl4/experiments/` (`regulative-powers.l4:4`, `deontic-may.l4:99-101`, `jerseyAlcohol.l4:42`).
> - **Rulings so far:** R-T1–R-T6 (§2.2.7.8, 2026-09-06); the pattern spelling (§2.4, 2026-09-07);
>   **R-Q1–R-Q7 (§2.5, 2026-09-07)**. Under R-Q1 there is one quantifier word, `EVERY`, and a
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

Name collisions were checked. `SOME` is not a keyword (`jl4-core/src/L4/Lexer.hs` has `OF`, `AT`,
`LEAST`, `ALL`; not `SOME`). An earlier proposal spelled an actor-agnostic contract head
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
    Quantifier Pattern [Filter]
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

Filter ::= 'WHO' Expr                 -- R-Q4: a Boolean expression in which the bound variable is free;
                                      -- WHERE is not a filter word (it opens a where-block, Parser.hs:1334-1338).
                                      -- 'WHOSE' Expr is PROPOSED, not ruled (§2.5, R-Q4)

DeonticModal ::= ('MUST' ['NOT'] | 'MAY' | 'SHANT' | 'DO') ['DO']
                                      -- 'DO' added 2026-09-07 (R-Q2; §2.2.7.4's house style). MUST NOT
                                      -- and the optional trailing DO are what the parser accepts
                                      -- (Parser.hs 'must'), measured 2026-09-07.

Action ::= Pattern ['PROVIDED' Expr]  -- the PROVIDED guard, measured working under EVERY 2026-09-07

TemporalConstraint ::= 'WITHIN' Duration ['OF' Anchor]   -- 'OF' Anchor: the named anchor of R-Q7 (§5.1); unbuilt
                     | 'BEFORE' Deadline                  -- documented as planned, unbuilt (doc/reference/regulative/README.md:102)
                     | 'BY' Deadline                      -- unruled and unbuilt; TKBy serves FOLLOWED BY, DIVIDED BY, BREACH BY

Anchor ::= `the join's firing` | `the missed deadline` | `the arming` | Event
                                      -- R-Q7: the four anchors the machine must expose; their spellings are not ruled

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
Nothing is built.

### 2.5 Rulings R-Q1–R-Q7 (2026-09-07)

Seven cards — "the Quantifier Bench", an artifact of 2026-09-06/07, **not in the tree**
(<https://claude.ai/code/artifact/fb431448-4363-47d8-bda2-f03d9e658bd6>) — were put to Meng after an
adversarial pass, and marked between 18:21 and 18:28 UTC on 6 September 2026. The marks are quoted
verbatim; where the general-manager session's reading of a mark goes beyond the mark, the text says
"GM's reading, 2026-09-07". Everything below was a design record when it was written; where an entry
has since been built, the entry says so and names the branch (R-Q1 is the one so far).
Measurements are dated 2026-09-07 on `unstable` `5dc0ca19` unless stated; every file:line was
re-opened on that tree when this section was written.

| id   | question, in a phrase                                        | mark, verbatim                                                                                                              | ruling, in a sentence                                                                                                                                                                                                            | recorded in                                |
| ---- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| R-Q1 | the join word: two quantifiers, or one word and a marker?    | **alternative** — _"E but with “ONCE EACH HAS \n HENCE”?"_                                                                  | One quantifier, `EVERY`; under it a continuation requires a join line: `ONCE ALL HAVE` (barrier), `UPON EACH` (fork; **words RULED 2026-09-07**); a bare `HENCE`/`LEST` is a check error. `HENCE FOR EACH` withdrawn.            | §2.2.6, §2.2.7.3–.6, §2.4, §3.1–§3.3, §15  |
| R-Q2 | does a bare `ALL Pattern` mean anything?                     | **accept** — _"How do the quantifies interact with RAND ROR combinators? Docs need to show an example."_                    | Not a quantifier. `ALL` keeps `FOR ALL`, `RECALL ALL`, `ONCE ALL HAVE`, and becomes the `ALL OF` head of the prefix family. `DO` joins `DeonticModal`. The note is a docs requirement: §8.3 gains the example.                   | §2.2.7.4, §2.4, §8.3, §15                  |
| R-Q3 | is `NO Tenant t MAY sublet` a form, and of what?             | **accept** — _"The NO P MUST A form feels like it belongs more to the bounded deontics discussion of dominators."_          | Sugar for `EVERY … SHANT` with the fork join; `HENCE` keeps `SHANT`'s meaning; `NO … MUST`/`SHANT`/`MUST NOT` refused with a naming message; the liberty form deferred to the bounded-deontics discussion.                       | §2.2.3, §2.2.7.4, §2.4, §15, status header |
| R-Q4 | the filter word, and what the slot holds                     | **accept** — _"Perhaps the WHOSE projection could take advantage of the field-opening logic from the section-givens work."_ | `WHO` only; the slot is a Boolean expression naming the bound variable; §2.1's insertion rule withdrawn. `WHOSE` is **PROPOSED**, sequenced after `IMPLICIT-PROPS-DESIGN.md` §11.7 R5 is built.                                  | §2.1, §2.2.3, §2.3, §2.4, §15              |
| R-Q5 | early failure: `LEST` at detection, or at the deadline?      | **accept** — _"d"_                                                                                                          | No modifier. The failure time is fixed by the layer the `LEST` attaches to — the state's deadline on the `ONCE … WITHIN` line; on the act layer, by the modal. Success time by modal. §13.1 closed.                              | §3.4, §5.2, §13.1                          |
| R-Q6 | does R-T6's fixed cast bind `EVERY`; what on leave/join?     | **accept** — _"d"_                                                                                                          | Cast evaluated once at arming for the whole family; changes only on an explicit **edit** event (release / substitute / join) applied to the running barrier, completions and accumulator preserved. Events proposed, unbuilt.    | §2.2.7.8 (R-T6 row), §13.4                 |
| R-Q7 | the continuation clock: `HENCE` from what, `LEST` from what? | **modify** — _"e but with a as default when no OF?"_                                                                        | A drafter may name the anchor (`WITHIN 5 days OF …`); unanchored, `HENCE` counts from the join's firing (today's rule) and `LEST` from the missed deadline (§5.2) — the latter a **change** from today's revealing-event anchor. | §2.4, §5.1, §5.2                           |

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

  **One reading the GM should confirm.** §2.4's conditional note wrote the fork as
  `'UPON' 'EACH' [HenceClause] [LestClause]`, omitting the `[TemporalConstraint]` that the `ONCE`
  branch carries. That omission is read here as brevity, not as a decision, because §2.5's own
  candidate-4 text says "the structure is unchanged" and because dropping it would have removed a
  capability that already worked (`ONCE EACH HAS WITHIN 30` parsed and checked). So the fork
  **keeps** its optional `WITHIN`, and `UPON EACH WITHIN 30` is legal: each continuation fires on
  its own member's act, and the whole is bounded by day thirty. If that reading is wrong the fix is
  one alternative in `L4.Parser.joinLine` and one field.

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
- `doc/reference/regulative/README.md:82-95` documents `WITHIN 5 days OF notice` as an anchored form.
  **Probed 2026-09-07:** it is a parse error (`unexpected OF` at the `OF`) on the installed binary of
  27 August and on the 4 September probe binary, with or without `days`. The page is owed a correction
  in the PR that builds the anchor of R-Q7 (§5.1), or sooner.
- `doc/tutorials/obligations/what-follows.md:153` and `:470` teach today's `LEST` anchor (the first
  event after the deadline) and a `WITHIN 13` workaround built on it. When R-Q7's `LEST` default is
  built (§5.2) that page changes and the trace goldens re-bless.
- In this document: extend §3–§9 to `SHANT` (R-Q3); define the release / substitute / join events
  (R-Q6, §13.4); rule the anchor spellings (R-Q7). The fork's words (R-Q1) were ruled 2026-09-07 and
  are recorded above.

## 3. Semantics Overview

### 3.1 EVERY: The Barrier Model

> Spelling as ruled 2026-09-07 (R-Q1, §2.5): the barrier is the **`ONCE ALL HAVE`** join under
> `EVERY`. In the workflow-patterns catalogue it is **WCP-14**, multiple instances with
> synchronisation (the joint/several memo's §7.5 asked for the citation here).

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

## 14. Related Work

- **Hvitved's CSL**: Trace-based contract semantics, blame assignment
- **CSP (Hoare)**: Trace semantics, parallel composition, external choice
- **Petri Nets**: AND-join synchronization pattern
- **Hohfeld**: Jural correlatives (privilege/no-right)
- **Deontic Logic**: Obligation, permission, prohibition modalities

## 15. Appendix: Formal Grammar

Brought into line with §2.4 on 2026-09-07 (R-Q1–R-Q4 and R-Q7, §2.5). Until then this appendix still
carried a `variable 'IN' set_expr` head that §2.4 had already replaced with the pattern form, four
quantifier words, a `WHERE` filter, and a `predicate` sub-grammar that only the withdrawn insertion
rule needed.

```ebnf
quantified_deonton ::=
    quantifier pattern [filter]
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
