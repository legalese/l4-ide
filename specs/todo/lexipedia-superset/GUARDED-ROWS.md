# `GuardedRows` — one normaliser, two consumers

_Scoped 2026-07-25. Track D0/D1 of [SPEC.md](./SPEC.md). Fixes the R1 spike finding recorded
in [`../ladder-diagrams-2026/E1-IDE-INTEGRATION.md`](../ladder-diagrams-2026/E1-IDE-INTEGRATION.md) §6._

---

## 1. The problem

`translateExpr`'s `go` in `jl4-core/src/L4/Viz/Ladder.hs` ends at line 442 with

```haskell
      _ -> leafFromExpr e
```

and `leafFromExpr` labels the resulting box with `prettyLayout expr` — the whole
expression's own source text. Three constructs fall through it:

| L4 surface                            | AST                                  | rendered today |
| ------------------------------------- | ------------------------------------ | -------------- |
| `IF c THEN t ELSE e`                  | `IfThenElse Anno Expr Expr Expr`     | opaque box     |
| `BRANCH IF g₁ THEN b₁ … OTHERWISE b₀` | `MultiWayIf Anno [GuardedExpr] Expr` | opaque box     |
| `CONSIDER s WHEN p₁ THEN b₁ …`        | `Consider Anno Expr [Branch]`        | opaque box     |

The R1 corpus spike measured the consequence: **17 of the 22 widest diagrams have exactly
one leaf**, and the widest is 4372px — one box holding 247 characters of raw L4. Thirty-eight
labels in the corpus contain a literal newline, which SVG `<text>` collapses to a space. A
whole decision table renders as an unreadable ribbon.

The two fixes previously recorded (wrap the label; draw a structured table-leaf) both accept
the premise. **Neither asked why a `CONSIDER` is a leaf at all.** For the boolean-returning
case it need not be.

---

## 2. The transform

A first-match guarded chain has an exact And/Or reading. Row _i_ fires iff its guard holds
**and no earlier guard did**, so for boolean bodies:

```
⋁ᵢ ( ⋀_{j<i} ¬gⱼ  ∧  gᵢ  ∧  bᵢ )    ⋁    ( ⋀_{j≤n} ¬gⱼ  ∧  b₀ )
```

Three simplifications collapse that hard in the common case:

| When                     | Effect                                                  |
| ------------------------ | ------------------------------------------------------- |
| `bᵢ ≡ TRUE`              | drop the `∧ bᵢ`; the row is just its guard prefix       |
| `bᵢ ≡ FALSE`             | **delete the entire disjunct** — the row cannot conduct |
| guards pairwise disjoint | drop **every** `¬` prefix                               |

A boolean decision table with disjoint exhaustive guards and literal bodies therefore
collapses to

```
⋁ { gᵢ : bᵢ = TRUE }
```

— a flat OR of the guards that say yes. That is exactly a ladder rung stack. The ribbon
becomes the picture it always was.

**Cost in the bad case.** _n_ overlapping guards give n(n+1)/2 atom _occurrences_ — but only
_n_ distinct atoms. ladder-core is a DAG keyed by identity, so the repeats are shared nodes,
and the binding fan-out E1 needs anyway for repeated atoms (risk **R2**) is what makes
clicking `g₁` flip it in all its negated copies at once. R2 stops being a hazard and becomes
the enabling mechanism.

---

## 3. The IR

One normalised form, deliberately carrying _rows_ rather than a boolean tree, because the DMN
consumer needs the rows and the ladder consumer can derive its tree from them.

```haskell
-- | A first-match guarded chain, normalised.
data GuardedRows = MkGuardedRows
  { grScrutinee :: Maybe (Expr Resolved)             -- ^ CONSIDER's subject; Nothing for BRANCH
  , grRows      :: [(Expr Resolved, Expr Resolved)]  -- ^ (guard, body), in SOURCE order
  , grOtherwise :: Maybe (Expr Resolved)
  , grDisjoint  :: Disjointness
  }

data Disjointness = Overlapping | Disjoint DisjointnessWitness

-- | Why we believe the guards are pairwise exclusive. Recorded, not just asserted —
--   the DMN consumer reports it as the table's hit policy justification.
data DisjointnessWitness
  = DistinctConstructors   -- ^ CONSIDER over distinct nullary constructors
  | SyntacticComplement    -- ^ g₂ is the negation/operator-flip of g₁
  | SingleRow              -- ^ IF-THEN-ELSE: vacuously disjoint
```

```haskell
normalise :: Expr Resolved -> Maybe GuardedRows
normalise = \case
  IfThenElse _ c t e  -> Just (MkGuardedRows Nothing [(c, t)] (Just e) (Disjoint SingleRow))
  MultiWayIf  _ gs b0 -> Just (MkGuardedRows Nothing
                                [(g, b) | MkGuardedExpr _ g b <- gs] (Just b0) (analyse gs))
  Consider    _ s brs -> considerRows s brs
  _                   -> Nothing
```

---

## 4. The ladder consumer

```haskell
rowsToLadder :: GuardedRows -> Viz IRExpr
rowsToLadder rs = orOf . catMaybes $ zipWith row [0 ..] rs.grRows ++ [fallback]
  where
    prefix i = case rs.grDisjoint of
      Disjoint _  -> []
      Overlapping -> [ vNot g | (g, _) <- take i rs.grRows ]

    row i (g, b) = case literalBool b of
      Just False -> Nothing                                    -- erase the row
      Just True  -> Just (andOf (prefix i ++ [go g]))
      Nothing    -> Just (andOf (prefix i ++ [go g, go b]))

    fallback = case (rs.grOtherwise, rs.grDisjoint) of
      (Nothing, _)                   -> Nothing
      (Just b0, _) | isFalse b0      -> Nothing
      (Just b0, _)                   -> Just (andOf (allNegated ++ bodyOf b0))
```

Slot the dispatch into `go` **immediately before** the catch-all at `Ladder.hs:442`:

```haskell
      e' | Just rows <- normalise e', boolReturning rows -> rowsToLadder rows
      _  -> leafFromExpr e
```

`boolReturning` reuses the existing `hasBooleanType` helper (already used by the `App` case at
`Ladder.hs:427`) over the whole expression _and_ every body.

**Why Haskell, and why here.** The output is ordinary `VizExpr.And`/`Or`/`Not`, so every
downstream consumer inherits the fix with **no TypeScript change**: ladder-core, the ASCII and
Mermaid carriers, the sentence expander, the wizard's query plan, and the ROBDD. One function,
whole-system blast radius.

---

## 5. Disjointness, cheapest first

| Tier  | Source                                                    | Cost                             |
| ----- | --------------------------------------------------------- | -------------------------------- |
| **1** | `CONSIDER` over distinct nullary constructors             | free — the pattern match says so |
| **2** | Syntactic complement: `x < k` vs `x >= k`; `p` vs `NOT p` | a few lines                      |
| **3** | Everything else → `Overlapping`; emit the prefixes        | sound, just verbose              |

Tier 1 is exact and needs no new analysis: the exhaustiveness checker already knows the
patterns are distinct constructors, and already knows whether `OTHERWISE` is reachable. That
is the `CONSIDER` exhaustiveness oracle earning a second keep.

Tier 2 is worth having in v1 because it is the flagship example's shape — an
income-or-net-worth threshold split as `< k` / `>= k`.

**Tier 4, deliberately deferred:** interval or SMT reasoning over the guards, which is what
DMN's completeness and consistency checkers have done since Montalbano (1962). Getting there
would mean re-deriving the capability `specs/research/DMN-STEELMAN.md` credits DMN with — a
good place to end up, and a bad place to start.

---

## 6. Scope boundaries — what this does **not** do

**Boolean-returning only.** The flagship investor-limit rule returns a _Number_ (a percentage,
not a yes/no), so it is **not** covered here; it stays an opaque leaf until the §23/D1
structured table-leaf lands (Track D2). But the same `GuardedRows` value feeds that renderer
_and_ the DMN exporter, so the sequencing is: normaliser first, ladder consumer now, table-leaf
and DMN consumers next.

The spike's own worst offender — `is adult`, 4372px, one leaf, a `CONSIDER` over jurisdiction
codes — **is** boolean-returning, so it is covered. The relief is immediate and measurable.

**Bail, do not guess, on two things:**

1. **Patterns that bind.** `PatVar`, `PatApp` with non-empty arguments, and `PatCons` all bind
   variables the body may reference, so the body is not a closed boolean expression and cannot
   be booleanised. Non-binding patterns — `PatApp _ c []`, `PatExpr`, `PatLit` — are fine, and
   become an `Equals` guard against the scrutinee.
2. **Effectful guards.** `BRANCH` short-circuits; the expansion is eager. If any guard contains
   `Fetch` or `Post`, expanding would change effect ordering. Bail to the leaf.

Both bail-outs are to the _existing_ behaviour, so they are strictly no worse than today.

**Three-valued evaluation degrades correctly.** Pure guards are safe: if `gᵢ` is UNKNOWN, the
expansion makes every downstream row UNKNOWN — which is the truthful answer, because you
genuinely do not know which row fires. Kleene monotonicity carries this without a special case.

---

## 7. The second consumer (Track D1, sketched here to fix the interface)

```haskell
rowsToDmn :: GuardedRows -> Either FidelityLoss DecisionTable
```

The correspondence is close to definitional:

| `GuardedRows`            | DMN                                                        |
| ------------------------ | ---------------------------------------------------------- |
| `grRows` in source order | rules, in rule order                                       |
| `Overlapping`            | hit policy `First` (order-dependent — DMN's own §8.2.10)   |
| `Disjoint _`             | hit policy `Unique`, with the witness as the justification |
| `grOtherwise`            | the default output / catch-all rule                        |
| a guard                  | an input entry — S-FEEL where it fits, full FEEL where not |
| a body                   | an output entry (**an expression** — DMN §8.2.9)           |

The **fidelity report** is the interesting output, and it falls out of this table rather than
needing separate machinery: every guard that does not fit S-FEEL is a named, located reason the
emitted table has left DMN's analysable fragment. That is `DMN-STEELMAN.md`'s surviving
criticism — _the fragment you can verify is not the fragment you are told to write_ — turned
from an essay into a per-file diagnostic.

---

## 8. Tests

| #   | Case                                              | Expect                                             |
| --- | ------------------------------------------------- | -------------------------------------------------- |
| T1  | `IF c THEN TRUE ELSE FALSE`                       | collapses to the single leaf `c`                   |
| T2  | `IF c THEN FALSE ELSE TRUE`                       | collapses to `NOT c`                               |
| T3  | `BRANCH` with all-TRUE bodies, overlapping guards | OR of prefixed ANDs; n(n+1)/2 occurrences, n atoms |
| T4  | `BRANCH` with a FALSE body                        | that disjunct is absent entirely                   |
| T5  | `CONSIDER` over 3 distinct nullary constructors   | flat OR, no negated prefixes                       |
| T6  | `CONSIDER` with a binding pattern                 | **unchanged** — still one leaf                     |
| T7  | `BRANCH` returning `NUMBER`                       | **unchanged** — still one leaf                     |
| T8  | guard containing `Fetch`                          | **unchanged** — still one leaf                     |
| T9  | `x < k` / `x >= k`                                | tier-2 complement detected; no prefixes            |
| T10 | UNKNOWN guard in row 1                            | rows 2..n evaluate UNKNOWN, not FALSE              |
| T11 | re-run the R1 corpus spike                        | p99 and max width fall; record the before/after    |

T11 is the acceptance gate and the honest one: the spike script already exists at
`ts-shared/ladder-svg/spike/corpus-sizes.ts` and drives every decision in the corpus through
the real pipeline. Re-running it turns "this should help" into a measured claim, and if the
numbers do not move, this design is wrong.
