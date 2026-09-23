# Sets, and the Two Meanings of "And"

Legal drafters write _and_ where a logician expects _or_, and it is not a mistake:

| Clause                                               | Reading                          |
| ---------------------------------------------------- | -------------------------------- |
| "cruel **and** unusual punishments"                  | must be **both**                 |
| "residents of New York **and** New Jersey may apply" | resident of **either** qualifies |

The second one looks paradoxical only because one word is doing two jobs. In the first clause, _and_ joins two **conditions about the same punishment** — logical conjunction. In the second, _and_ joins two **groups of people into a bigger group** — set union. And union is secretly disjunctive one level down: you are in the union of A and B exactly when you are in A **or** in B.

Courts see this ambiguity constantly. The Singapore Court of Appeal has read the same word _and_ as union in one case (_Nam Hong Construction_ [2016] SGCA 42) and as conjunction in another (_Sit Kwong Lam_ [2018] SGCA 14) — same court, same Chief Justice, opposite results, and correctly so both times. The word underdetermines the meaning; the context decides. As the U.S. Supreme Court put it: "Really, it all depends" (_Pulsifer v. United States_, 601 U.S. 124, 140 (2024)).

L4's answer: give the two jobs two **types**, and two **spellings**. Sentence-level conjunction keeps the word `AND`; term-level union is written `UNION`. The type checker enforces the split: `AND` between two sets is a compile-time error, so the drafter is forced to say which reading the source text's _and_ meant. This tutorial shows how.

## Sets in one minute

No mathematics background needed — a **set** is just a collection of things where two facts are ignored: **order** and **repetition**. The set of New York residents is the same set however you list them, and listing "alice" twice doesn't create two alices. (This is the one way a set differs from L4's ordinary `LIST`, which keeps both.)

Four operations do almost all the work, and each has a plain-English name a drafter already uses:

| Operation        | Everyday phrasing                          | Symbol | Example (NY = {alice, bob}, NJ = {carol}) |
| ---------------- | ------------------------------------------ | ------ | ----------------------------------------- |
| **union**        | "members of A **and** of B" / "either one" | A ∪ B  | NY ∪ NJ = {alice, bob, carol}             |
| **intersection** | "those in **both**"                        | A ∩ B  | NY ∩ NJ = {} (nobody is in both)          |
| **difference**   | "A **less** those in B"                    | A \ B  | employees \ probationers                  |
| **membership**   | "is x **in** the set?"                     | x ∈ A  | alice ∈ NY is true                        |

Two relationships round it out: A is a **subset** of B (A ⊆ B) when every member of A is also in B, and two sets are **equal** when each is a subset of the other — which is why order and repetition don't matter. That is the whole vocabulary; the rest of this tutorial is how L4 spells it.

## Building sets

The prelude provides `SET OF a`, a collection in which order and duplicates don't matter:

```l4
IMPORT prelude

`new yorkers`   MEANS setFromList (LIST "alice", "bob")
`new jerseyans` MEANS setFromList (LIST "carol")

#EVAL "alice" `is in` `new yorkers`        -- TRUE
#EVAL setSize `new yorkers`                -- 2
```

`setFromList` discards duplicates: `setFromList (LIST 1, 1, 2)` has size 2. You can also write two or more elements directly with `SET OF`:

```l4
`new yorkers` MEANS SET OF "alice", "bob"      -- same as setFromList (LIST "alice", "bob")
```

One catch: `SET OF` needs at least two elements. With a single argument, `SET OF x` reads `x` as the contents list — so `SET OF "carol"` is a type error. For a one-element set, stay with `setFromList (LIST "carol")`.

## The two ANDs, side by side

Here is the whole point of the feature in four lines:

```l4
-- term-level union: spelled UNION. Three people are eligible.
`eligible` MEANS `new yorkers` UNION `new jerseyans`
#EVAL setSize `eligible`                   -- 3

-- sentence-level AND: BOOLEAN AND BOOLEAN → conjunction.
`violates 8th amendment` MEANS `is cruel` AND `is unusual`
```

Same word in the statute; two different operations in the formalization — and the types police the boundary. If you transcribe the statute's _and_ verbatim between two sets, L4 rejects it with a type error: the only `AND` is boolean conjunction, and a set is not a boolean. The error is the feature — it is the exact point where a human once had to choose between the conjunctive and the union reading, surfaced at the exact token where the choice was made. Writing `UNION` records the choice in the source.

(The same goes for `OR` between two sets — "residents of NY and NJ" and "residents of NY or NJ" describe the same eligible population, and both are written `UNION`. An earlier design overloaded `AND`/`OR` on sets to mean union so verbatim transcription would typecheck; those overloads were **removed on 2026-07-28** because a second candidate for `AND`/`OR` made typechecking exponential in the depth of `AND`/`OR` chains — a real 27-operand statutory disjunction became uncheckable ([smucclaw/l4-ide#929](https://github.com/smucclaw/l4-ide/issues/929)). See the design record for the reversal and the conditions for reinstatement.)

## Union, intersection, difference

The rest of the vocabulary:

```l4
#EVAL setSize (`new yorkers` UNION `new jerseyans`)       -- 3
#EVAL setSize (`new yorkers` INTERSECT `new jerseyans`)   -- 0
```

For set difference, legal English says _less_: "all employees LESS those on probation". In L4, `LESS` needs backticks — the bare word belongs to the `LESS THAN` comparison — and `WITHOUT` is the alias that doesn't:

```l4
`all employees` MEANS setFromList (LIST "dilbert", "alice", "wally", "asok")
`on probation`  MEANS setFromList (LIST "asok")

#EVAL setSize (`all employees` `LESS` `on probation`)     -- 3
#EVAL setSize (`all employees` WITHOUT `on probation`)    -- 3
```

The word operators have no precedence, so parenthesize compounds: `A UNION (B INTERSECT C)`.

## PLUS and MINUS: precedence for free

Sets also answer to `PLUS` (union) and `MINUS` (difference), and because these ride L4's arithmetic operator table, they chain **without parentheses**:

```l4
a1 MEANS setFromList (LIST 1, 2, 3)
b1 MEANS setFromList (LIST 2, 3, 4)

#EVAL setSize (a1 PLUS b1 MINUS b1)        -- 1
```

But careful — sets are not numbers. Union has no inverse: `(A PLUS B) MINUS B` is not `A` (element 2 above was in both sets, and subtracting `b1` takes it away). If you reason about sets with arithmetic reflexes, this is the trap.

## Equality: say `set equals`

Bare `EQUALS` between two sets is a **compile-time error**, deliberately. Structural equality would be order-sensitive — `{1,2}` vs `{2,1}` — which is silently wrong for sets, so L4 refuses to guess and makes you say what you mean:

```l4
#EVAL (setFromList (LIST 2, 1, 1)) `set equals` (setFromList (LIST 1, 2))   -- TRUE
```

One caveat to keep in mind: this extensional treatment is one level deep. A set _inside_ another set, or inside a record field, compares by its written representation. When comparing records with set-valued fields, compare the fields with `` `set equals` `` rather than comparing the whole records. (See `ok/set-operators-nested.l4` in the examples for the full picture.)

## Why this matters: the otiosity test, executable

When a court has to decide whether _and_ means union or intersection, the decisive move is often the **redundancy canon**: a reading that makes one of the words do no work is presumed wrong. In _A-G of the Bahamas v Royal Trust_ [1986] UKPC 34, "education and welfare" was read disjunctively because education is a subset of welfare — on the intersective reading, "welfare" would be otiose. In _Re Best_ [1904] 2 Ch 354, "charitable and benevolent" was read conjunctively because the two genuinely overlap — both words do work.

With sets, that test is a program:

```l4
`education purposes` MEANS setFromList (LIST "schools", "universities", "scholarships")
`welfare purposes`   MEANS setFromList (LIST "schools", "universities", "scholarships",
                                             "housing", "recreation")

-- education ⊆ welfare: the intersective reading collapses; union forced
#EVAL `education purposes` `is subset of` `welfare purposes`               -- TRUE

`charitable objects` MEANS setFromList (LIST "almshouse", "school")
`benevolent objects` MEANS setFromList (LIST "school", "social club")

-- proper overlap: both terms do work; read the connective literally
#EVAL setSize (`charitable objects` INTERSECT `benevolent objects`)        -- 1
```

An empty intersection (like our New Yorkers and New Jerseyans) is the strongest signal of all: nobody writes an eligibility rule for the empty set, so the drafter must have meant union. A future L4 lint will make exactly this argument in a tooltip, with the citation attached.

Seen from engineering, the redundancy canon is a **Boolean-minimization presumption**: courts presume statutory text is already minimized — every term load-bearing, nothing a Quine–McCluskey pass would delete — so a reading that renders a term otiose is evidence of the wrong reading, exactly as a minimizer flags a redundant clause as evidence of a drafting slip. Turning canons of construction into checkable properties of Boolean structure is a running theme of the L4 research programme; for how this style of analysis performs on a live appellate problem, see _Poh Yuan Nie v Public Prosecutor_ [2022] SGCA 74, the worked example of the L4 papers series.

## Where next

- Reference: [Sets library](../../reference/libraries/sets.md)
- The full design record, with the case law verified against primary sources: [SET-OPERATORS-SPEC](../../../specs/todo/SET-OPERATORS-SPEC.md)
- Coming next: the ambiguity lint that surfaces the otiosity argument in the IDE
