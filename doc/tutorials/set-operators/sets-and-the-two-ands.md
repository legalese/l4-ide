# Sets, and the Two Meanings of "And"

Legal drafters write _and_ where a logician expects _or_, and it is not a mistake:

| Clause                                               | Reading                          |
| ---------------------------------------------------- | -------------------------------- |
| "cruel **and** unusual punishments"                  | must be **both**                 |
| "residents of New York **and** New Jersey may apply" | resident of **either** qualifies |

The second one looks paradoxical only because one word is doing two jobs. In the first clause, _and_ joins two **conditions about the same punishment** — logical conjunction. In the second, _and_ joins two **groups of people into a bigger group** — set union. And union is secretly disjunctive one level down: you are in the union of A and B exactly when you are in A **or** in B.

Courts see this ambiguity constantly. The Singapore Court of Appeal has read the same word _and_ as union in one case (_Nam Hong Construction_ [2016] SGCA 42) and as conjunction in another (_Sit Kwong Lam_ [2018] SGCA 14) — same court, same Chief Justice, opposite results, and correctly so both times. The word underdetermines the meaning; the context decides. As the U.S. Supreme Court put it: "Really, it all depends" (_Pulsifer v. United States_, 601 U.S. 124, 140 (2024)).

L4's answer: give the two jobs two **types**, and let the type checker pick the right operation. This tutorial shows how.

## Building sets

The prelude provides `SET OF a`, a collection in which order and duplicates don't matter:

```l4
IMPORT prelude

`new yorkers`   MEANS setFromList (LIST "alice", "bob")
`new jerseyans` MEANS setFromList (LIST "carol")

#EVAL "alice" `is in` `new yorkers`        -- TRUE
#EVAL setSize `new yorkers`                -- 2
```

`setFromList` discards duplicates: `setFromList (LIST 1, 1, 2)` has size 2.

## The two ANDs, side by side

Here is the whole point of the feature in four lines:

```l4
-- term-level AND: Set AND Set → union. Three people are eligible.
`eligible` MEANS `new yorkers` AND `new jerseyans`
#EVAL setSize `eligible`                   -- 3

-- sentence-level AND: BOOLEAN AND BOOLEAN → conjunction.
`violates 8th amendment` MEANS `is cruel` AND `is unusual`
```

Same token. Different types. Different operations. **Both correct.** You can transcribe the statute's _and_ verbatim — without first deciding what it means — and the type system routes it to conjunction or union as the operands dictate.

(`OR` on sets is _also_ union — "residents of NY and NJ" and "residents of NY or NJ" describe the same eligible population. That the two connectives coincide on sets is not a bug; it is the ambiguity the drafter left behind, made visible.)

## Union, intersection, difference

The explicit vocabulary, when you want to leave no doubt:

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

## Where next

- Reference: [Sets library](../../reference/libraries/sets.md)
- The full design record, with the case law verified against primary sources: [SET-OPERATORS-SPEC](https://github.com/legalese/l4-ide/blob/docs/set-operators-spec/specs/todo/SET-OPERATORS-SPEC.md)
- Coming separately: variadic construction (`SET OF NY, NJ` — [#123](https://github.com/legalese/l4-ide/pull/123)) and the ambiguity lint
