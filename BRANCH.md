# BRANCH — Fix the shallow `DEONTIC` action-type check

**Branch:** `mengwong/fix-deontic-action-type-check` (off `unstable`)
**Origin:** drafted as `specs/issues/deontic-action-type-shallow-check.md` on
`mengwong/housing-act-ground-1` (PR #37); promoted here to marching orders.

## Goal (one line)

Make the regulative `MUST`/`MAY` action type-check against the contract's
`DEONTIC <ActorType> <ActionType>` parameter **deeply** — full unification,
including type arguments — so parametric / actor-indexed action types are
enforced through the deontic layer, not just at function boundaries.

## Definition of done

- **R2** below becomes a type error matching **R3**'s shape ("expected `Action OF
  Court`, but is here of type `Action OF Landlord`").
- **R1** still errors; **R3** still errors (no regression in function-boundary
  unification).
- The existing corpus is unaffected — plain-enum actions have no type arguments,
  so head-only and deep checks coincide. Re-run the housing-act sweep and the
  `jl4/examples` suite green.
- A regression fixture is added under the regulative type-error tests (a `MUST`
  with a wrong-indexed parametric action must fail to check), with golden output.

## Step 0 — confirm the locus (this was a black-box hypothesis in the writeup)

Trace the regulative path in `jl4-core/src/L4/TypeCheck.hs` (`inferContract` and
the `RAction` `MUST`/`MAY` action checking) and find where the action's type is
compared against the contract's `DEONTIC` second type argument. Confirm it is a
head-constructor comparison rather than the full unifier used for function
arguments, then make it use the same deep unification. Keep the diagnostic
message as legible as the function-boundary one.

---

## Reference: the bug writeup

### Summary

When type-checking a regulative `PARTY p MUST|MAY <action>` clause against a
contract's declared type `DEONTIC <ActorType> <ActionType>`, the checker verifies
the action against `<ActionType>` only up to the **head type constructor** — it
does not unify the type *arguments*. So a contract declared `DEONTIC Party
(Action Court)` accepts an action of type `Action Landlord` in its `MUST` slot,
even though the same value is rejected where an `Action Court` is required at an
ordinary function boundary (which performs full unification).

This is harmless for the common case where actions are a plain enum (no type
arguments — the head *is* the whole type). It surfaces — and blocks — as soon as
actions are given a type parameter, e.g. the phantom-indexed "actor-typed actions"
pattern (see `specs/roadmap/future-features.md`, "Actor-indexed actions"), where
the index is exactly what we want the deontic layer to enforce.

### Environment

- Repo: `legalese/l4-ide`, branch `mengwong/housing-act-ground-1`, commit `da417b75`.
- Binary: `l4` (cabal `list-bin l4`), run with `JL4_FIXED_NOW=2025-01-01T00:00:00Z`.

### Reproductions

#### R1 — non-parametric mismatch IS caught (the check exists)

```l4
IMPORT prelude
DECLARE Party   IS ONE OF JudgeCourt, ALandlord
DECLARE ActionA IS ONE OF doA
DECLARE ActionB IS ONE OF doB

GIVETH A DEONTIC Party ActionA
`mismatched action type` MEANS PARTY JudgeCourt MUST doB WITHIN 30
```

`l4 check` → **error** (as expected):

```
... is expected to be of type
      DEONTIC OF Party, ActionA
    but is here of type
      DEONTIC OF Party, ActionB
```

#### R2 — parametric (phantom) mismatch is NOT caught (the bug)

```l4
IMPORT prelude
DECLARE Court    IS ONE OF TheCourt
DECLARE Landlord IS ONE OF TheLandlord
DECLARE Party    IS ONE OF JudgeCourt, ALandlord
DECLARE Action a HAS `action name` IS A STRING

GIVETH AN Action Court
`order possession` MEANS Action WITH `action name` IS "order possession"
GIVETH AN Action Landlord
`seek possession`  MEANS Action WITH `action name` IS "seek possession"

-- contract pinned to Court actions, but MUST a Landlord-typed action:
GIVETH A DEONTIC Party (Action Court)
`bad court duty` MEANS PARTY JudgeCourt MUST `seek possession` WITHIN 30
```

`l4 check` → **`Check succeeded.`** (expected: an error — `seek possession` is
`Action Landlord`, not `Action Court`). The reverse pairing
(`DEONTIC Party (Action Landlord)` with `order possession`) also wrongly succeeds,
so the second type argument is simply not being constrained.

#### R3 — the same parametric mismatch IS caught at a function boundary (full unification works elsewhere)

```l4
IMPORT prelude
DECLARE Court    IS ONE OF TheCourt
DECLARE Landlord IS ONE OF TheLandlord
DECLARE Action a HAS `action name` IS A STRING
GIVETH AN Action Court
`order possession` MEANS Action WITH `action name` IS "order possession"

GIVEN x IS AN Action Landlord
GIVETH A BOOLEAN
`landlord does` x MEANS TRUE

#EVAL `landlord does` `order possession`
```

`l4 check` → **error**:

```
The first argument of function `landlord does` ...
    is expected to be of type
      Action OF Landlord
    but is here of type
      Action OF Court
```

### Expected vs actual

- **Expected:** the `MUST`/`MAY` action in a regulative clause is unified with the
  contract's declared `Action` type the same way a function argument is unified
  with its parameter type — i.e. *deeply*, including type arguments. R2 should be a
  type error, matching R3.
- **Actual:** R1 is caught but R2 is not. Together with R3 this indicates the
  regulative action check compares only the **head type constructor** of the action
  type (`Action` == `Action`) and ignores its arguments (`Court` vs `Landlord`).

### Likely locus

The regulative action carrier is `RAction { modal, action :: Pattern n, provided }`
(`jl4-core/src/L4/Syntax.hs`). The shallow comparison is presumably where the
`MUST`/`MAY` action's type is checked against the contract's `DEONTIC` action
parameter during regulative type-checking (`jl4-core/src/L4/TypeCheck.hs`,
`inferContract`/regulative path) — using a head-constructor comparison rather than
the full unification used for ordinary function arguments. (Hypothesis from
black-box behaviour; **confirm in Step 0**.)

### Impact

- **None** for plain-enum actions (the entire current corpus): such types have no
  arguments, so head-only and deep checks coincide.
- **Blocks** giving `Action` a type parameter to make actions *actor-indexed*
  (phantom-typed or, eventually, GADT-indexed), because the deontic layer — the one
  place we actually want `PARTY Court MUST <a court action>` enforced — silently
  accepts the wrong index. Deepening this check is a prerequisite for rung 2b of the
  "Actor-indexed actions" roadmap item.

### Suggested direction

Use the same (full, argument-recursive) unification for the regulative
`MUST`/`MAY` action against the contract's `Action` parameter that is already used
for function-argument checking, so R2 fails with the R3-style message.
