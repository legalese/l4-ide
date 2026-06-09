# Specification: Negation as Failure via `MAYBE BOOLEAN`

**Status:** 📝 PROPOSED (draft, 2026-06-09)
**Scope:** Prelude combinators + documentation. No compiler/lexer/parser changes required.
**Related:** `TYPICALLY-DEFAULTS-SPEC.md` (rebuttable presumptions), `BOUNDED-DEONTICS-SPEC.md` (deontic modalities), `doc/reference/libraries/prelude.md`

## Executive Summary

Prolog and its descendants have a mature, well-understood semantics for **negation as
failure (NAF)**: `\+ Goal` succeeds precisely when `Goal` cannot be proven. We want the
same expressive power in L4, but rather than bolt on a special operator we observe that
L4's functional heritage already gives us everything we need.

The entire treatment of NAF reduces to one idea:

> A proposition that may or may not have been settled is a `MAYBE BOOLEAN`. Negation as
> failure is the **closed-world assumption** — the act of defaulting "unproven" to FALSE —
> and that act is *already* expressed by the prelude's `fromMaybe FALSE`.

No new keyword, no new type machinery. The proposal is to **name** the combinators (so
they read like the legal concept) and to **document** the design, including the optional
three-valued (Kleene) lift for users who want NAF to propagate through connectives.

```l4
DECLARE DefBool IS A MAYBE BOOLEAN     -- JUST TRUE | JUST FALSE | NOTHING

holds p MEANS fromMaybe FALSE p        -- closed-world: no proof ⇒ FALSE
naf   p MEANS NOT (holds p)            -- succeeds exactly when p is unprovable
```

## Motivation

### Why borrow from Prolog

Logic programming has spent forty years working out what "not" should mean when knowledge
is incomplete (Clark's completion, 1978; the well-founded semantics of Van Gelder, Ross &
Schlipf, 1991; the stable-model semantics of Gelfond & Lifschitz, 1988). Legal reasoning is
shot through with the same pattern: a rule applies *unless* an exception is shown; a fact is
presumed *until* rebutted; an act is permitted *because* nothing forbids it. These are all
NAF in disguise. We should reuse the mature semantics rather than reinvent it.

### Why L4 can do it in three lines

L4 is a typed functional language. It already has:

- `MAYBE a` (built-in) with constructors `JUST x` and `NOTHING`;
- `fromMaybe default x` in the prelude, returning `default` on `NOTHING` and `x` on `JUST x`;
- classical two-valued `BOOLEAN` with `AND` / `OR` / `NOT`.

That is exactly the kit needed for NAF. The contribution of this spec is conceptual clarity,
not new code.

## The Core Representation

A **Default Boolean** is a proposition in one of three epistemic states:

| Value        | Reading                                   |
|--------------|-------------------------------------------|
| `JUST TRUE`  | proven true                               |
| `JUST FALSE` | proven false                              |
| `NOTHING`    | no proof either way (the open question)   |

```l4
DECLARE DefBool IS A MAYBE BOOLEAN
```

The closed-world assumption grounds the open question to FALSE. This is `fromMaybe FALSE` —
the user's hypothesised `isProvable` is literally already in the prelude:

```l4
GIVEN p IS A DefBool
GIVETH A BOOLEAN
holds p MEANS fromMaybe FALSE p
```

Negation as failure is its De Morgan complement:

```l4
GIVEN p IS A DefBool
GIVETH A BOOLEAN
naf p MEANS NOT (holds p)
```

### Truth tables (verified against `jl4-cli`)

| `p`          | `holds p` | `naf p` |
|--------------|-----------|---------|
| `JUST TRUE`  | TRUE      | FALSE   |
| `JUST FALSE` | FALSE     | TRUE    |
| `NOTHING`    | FALSE     | TRUE    |

`holds` defaults to FALSE on `NOTHING`; `naf` succeeds on everything that is not provably
true — i.e. both the *refuted* (`JUST FALSE`) and the *unknown* (`NOTHING`) cases. That is
the behaviour Prolog's `\+` exhibits under SLDNF resolution.

## Why `MAYBE BOOLEAN` is the *right* representation, not merely a short one

The elegance is not the brevity — it is that **the type keeps three states distinct while
the eliminator deliberately collapses two of them.**

`MAYBE BOOLEAN` is honest about the difference between *proven false* (`JUST FALSE`) and
*unprovable* (`NOTHING`). The closed-world assumption is precisely the act of conflating
those two into FALSE — and `fromMaybe FALSE` is exactly that conflation (`JUST FALSE ↦
FALSE`, `NOTHING ↦ FALSE`).

So we separate **the data** (three-valued, honest about ignorance) from **its
interpretation** (the fold). This is L4's FP-heritage argument in miniature: *you choose
your epistemics at the eliminator, not at the type.* The same `DefBool` value can be read
under different assumptions without changing how it was produced.

## A lattice of readings, one combinator

Because the eliminator carries the epistemics, a single combinator — `fromMaybe d` — yields
a family of readings over the *same* data simply by varying the default `d`:

```l4
holds    p MEANS fromMaybe FALSE p   -- provably-true        (Prolog NAF / closed world)
presumed p MEANS fromMaybe TRUE  p   -- "not forbidden ⇒ permitted"  (deontic / open world)
decided  p MEANS isJust p            -- do we have a verdict at all?  (strong knowledge)
```

- `holds` / `fromMaybe FALSE` — the **closed-world** reading. Absence of proof is failure.
- `presumed` / `fromMaybe TRUE` — the **open-world** dual. Absence of a prohibition is
  permission. This is the natural default for deontic *permission* and connects directly to
  `BOUNDED-DEONTICS-SPEC.md`.
- `decided` / `isJust` — the orthogonal **epistemic** question NAF throws away: is there a
  verdict at all? A forbidden act is *decided*; a merely non-obligatory act may be only
  *undecided*. Deontic reasoning needs both axes.

**The default value is the knob** that turns NAF into general defeasible / default
reasoning, and flipping it `FALSE → TRUE` is exactly the closed-world / open-world switch.
This is the same conceptual territory as `TYPICALLY-DEFAULTS-SPEC.md`'s rebuttable
presumptions, approached from the value level rather than via a new keyword.

## A naming nuance (for the wordsmiths)

The user's working name `isProvable` deserves a second look. Under `fromMaybe FALSE`, the
case `JUST FALSE ↦ FALSE` means the function actually answers **"is it provably *true*?"**,
not "is it provable?". A proven-false proposition *is* provable — provably false — it just
is not true. We therefore recommend:

- `holds` (or `provablyTrue`) for the closed-world grounding `fromMaybe FALSE`;
- `decided` (≡ `isJust`) for "provable at all / settled either way".

Keeping these two words apart matters precisely because legal/deontic reasoning routinely
needs to distinguish "shown false" from "not shown at all".

## Connectives: leaf-level NAF vs. propagating three-valued logic

The three-line core applies NAF **at the leaves**, with ordinary two-valued `AND` / `OR`
above. That is sufficient for most isomorphic encodings and keeps the truth tables trivial.

If instead you want `NOTHING` ("unknown") to **flow through** the connectives — the road to
the well-founded and stable-model semantics that give Prolog NAF its maturity — lift the
operators to **Kleene strong three-valued logic** over `DefBool`, treating `NOTHING` as the
undefined element ⊥, and ground to two-valued *once*, at the top, with the same `holds`:

```l4
GIVEN p IS A DefBool
      q IS A DefBool
GIVETH A DefBool
p `kand` q MEANS
  CONSIDER p
  WHEN JUST FALSE THEN JUST FALSE          -- FALSE absorbs, even under uncertainty
  WHEN JUST TRUE  THEN q
  WHEN NOTHING    THEN CONSIDER q
                       WHEN JUST FALSE THEN JUST FALSE
                       OTHERWISE NOTHING   -- unknown ∧ true = unknown
```

Kleene `kor` and `knot` are the obvious duals (`knot` swaps `JUST TRUE`/`JUST FALSE`, fixes
`NOTHING`). The crucial design property is that **both layers share one grounding operator**:
`holds = fromMaybe FALSE` collapses the three-valued result back to a yes/no whenever a
decision is required.

| `p`       | `q`        | `p kand q`  |
|-----------|------------|-------------|
| `NOTHING` | `JUST FALSE` | `JUST FALSE` |
| `NOTHING` | `JUST TRUE`  | `NOTHING`    |
| `JUST TRUE` | `NOTHING`  | `NOTHING`    |
| `JUST FALSE` | anything  | `JUST FALSE` |

## Worked, verified examples

Both files below were checked with `jl4-cli`: `Checking succeeded`, every `#ASSERT`
satisfied, every `#EVAL` matching the comment.

### `naf.l4` — the core

```l4
IMPORT prelude

DECLARE DefBool IS A MAYBE BOOLEAN

GIVEN p IS A DefBool
GIVETH A BOOLEAN
holds p MEANS fromMaybe FALSE p

GIVEN p IS A DefBool
GIVETH A BOOLEAN
naf p MEANS NOT (holds p)

#EVAL holds (JUST TRUE)     -- TRUE
#EVAL holds (JUST FALSE)    -- FALSE
#EVAL holds NOTHING         -- FALSE
#EVAL naf (JUST TRUE)       -- FALSE
#EVAL naf (JUST FALSE)      -- TRUE
#EVAL naf NOTHING           -- TRUE

#ASSERT holds NOTHING EQUALS FALSE
#ASSERT naf NOTHING
#ASSERT NOT (naf (JUST TRUE))
```

### `naf2.l4` — the dual, strong knowledge, and the Kleene lift

```l4
IMPORT prelude

DECLARE DefBool IS A MAYBE BOOLEAN

GIVEN p IS A DefBool
GIVETH A BOOLEAN
holds p MEANS fromMaybe FALSE p

GIVEN p IS A DefBool
GIVETH A BOOLEAN
`presumed` p MEANS fromMaybe TRUE p

GIVEN p IS A DefBool
GIVETH A BOOLEAN
naf p MEANS NOT (holds p)

GIVEN p IS A DefBool
GIVETH A BOOLEAN
decided p MEANS isJust p

GIVEN p IS A DefBool
      q IS A DefBool
GIVETH A DefBool
p `kand` q MEANS
  CONSIDER p
  WHEN JUST FALSE THEN JUST FALSE
  WHEN JUST TRUE  THEN q
  WHEN NOTHING    THEN CONSIDER q
                       WHEN JUST FALSE THEN JUST FALSE
                       OTHERWISE NOTHING

#ASSERT holds NOTHING EQUALS FALSE
#ASSERT `presumed` NOTHING EQUALS TRUE
#ASSERT naf NOTHING
#ASSERT NOT (decided NOTHING)
#ASSERT decided (JUST FALSE)
#ASSERT (NOTHING `kand` (JUST FALSE)) EQUALS (JUST FALSE)
#ASSERT holds (NOTHING `kand` (JUST TRUE)) EQUALS FALSE
```

## Proposed prelude additions

Minimal, additive, no breaking changes. Candidate home: `jl4-core/libraries/prelude.l4`
(alongside the existing `fromMaybe` / `isJust` Maybe-eliminators).

1. `holds : MAYBE BOOLEAN -> BOOLEAN` ≝ `fromMaybe FALSE` — closed-world grounding.
2. `naf   : MAYBE BOOLEAN -> BOOLEAN` ≝ `NOT (holds p)` — negation as failure.
3. *(optional)* `presumed : MAYBE BOOLEAN -> BOOLEAN` ≝ `fromMaybe TRUE` — open-world dual.
4. *(optional, separate module)* Kleene three-valued `kand` / `kor` / `knot` over
   `MAYBE BOOLEAN` for users who want NAF to propagate through connectives.

`DefBool` itself need not be added as a named type — `MAYBE BOOLEAN` is already legible —
but a documented alias may aid teaching.

## Open questions / design decisions

1. **Name of the grounding function.** `holds` vs `provablyTrue` vs `cwa`. `holds` reads
   well in rules (`IF holds (...)`); `provablyTrue` is more honest. Recommend `holds` with a
   doc note.
2. **Ship the Kleene lift in the prelude or keep it as a documented pattern?** It introduces
   a second algebra; some users will want two-valued connectives only. Leaning: separate
   optional library module, not the core prelude.
3. **Relationship to `TYPICALLY`.** `TYPICALLY` attaches a default to a *declaration* site;
   `holds`/`presumed` apply a default at the *use* site. They are complementary, not
   competing. Worth a cross-reference paragraph in both specs.
4. **Interaction with deontic modalities.** `presumed`/open-world is the natural reading for
   permission; `holds`/closed-world for obligation discharge. Coordinate with
   `BOUNDED-DEONTICS-SPEC.md`.

## References

- K. L. Clark, *Negation as Failure*, in *Logic and Data Bases*, 1978.
- A. Van Gelder, K. Ross, J. Schlipf, *The Well-Founded Semantics for General Logic
  Programs*, JACM 1991.
- M. Gelfond, V. Lifschitz, *The Stable Model Semantics for Logic Programming*, ICLP 1988.
- S. C. Kleene, *Introduction to Metamathematics*, 1952 (strong three-valued logic).
