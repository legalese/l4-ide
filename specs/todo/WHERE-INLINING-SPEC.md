# Referential transparency for the static analyses — inlining local `WHERE`/`LET` bindings

_Status: **implemented in this PR** for `l4 verify`; the ladder default view and the exporter's
descent are scoped out and reasoned about in §7. Written 2026-08-27 on branch
`mengwong/where-inlining`._

**One-line summary.** `x WHERE x MEANS e` and `e` mean the same thing to the evaluator and
different things to the analyser. This spec makes them mean the same thing to the analyser too,
by substituting zero-arity local bindings before analysis.

---

## 1. The defect, measured

L4 evaluates referentially transparently: a name bound by `WHERE` is interchangeable with its
definiens, and `l4 run` agrees. The **static analyses** do not, because the ladder IR turns a
reference to a local binding into an opaque atom. Two spellings of one rule:

```l4
GIVEN `is a member` IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `flat` IF
        `is a member`
    AND NOT `is a member`

GIVEN `is a member` IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `hidden` IF
        `is a member`
    AND NOT enrolled
    WHERE
        enrolled MEANS `is a member`
```

```
flat    (1 atoms, 4 ladder nodes) — 1 finding(s)
    [unsat] at body
hidden  (2 atoms, 4 ladder nodes) — no propositional findings
```

`hidden` is a **top-level** decision and _is_ analysed. It is not covered by the "only top-level
decisions are visited" caveat, and a reader of that caveat would not predict this. `enrolled` and
`` `is a member` `` became two unrelated atoms, so the contradiction disappeared.

**This is the whole motivation.** The bug is not that nested definitions go unreported; it is that
a one-line `WHERE` silently defeats the analysis of the rule that uses it. A drafter who factors a
long condition into named parts — which is exactly what house style asks for, and what makes a
rule readable — pays for it in analysis coverage, invisibly.

### 1.1 Why the cheap fix does not fix it

The obvious reading of "descend into `WHERE`" is to swap `foldTopLevelDecides` for `foldDecides`
in `jl4/app/L4/Cli/Verify.hs:322`. Both folds already exist (`L4.Syntax`, 467 and 478), and verify
already calls the second one to _count_ what it skipped. One line.

It would not help. It yields a separate report on `enrolled`, and `enrolled MEANS \`is a member\``
is faultless on its own. **The contradiction exists only in the combination**, so the unit of
analysis has to be the caller with the callee substituted in — not the callee as a peer.

---

## 2. The rule

> **R1.** Before a decision is handed to a static analysis, every reference to a **zero-arity**
> local binding introduced by `WHERE` or `LET … IN`, in that decision, is replaced by the
> binding's definiens, to a fixed point.

Consequences, in order of importance:

- `hidden` and `flat` produce the same findings, because after R1 they are the same expression.
- Atom coalescing then does the rest: the two occurrences of `` `is a member` `` share an
  `atomId`, collapse to one atom, and the `[unsat]` falls out of the existing analysis unchanged.
- **No analysis logic changes.** R1 is a pre-pass. Every finding, verdict and caveat downstream
  keeps its current meaning.

## 3. What is deliberately _not_ inlined

| Case                                                  | Why                                                                                                                                                                                                                                                                        | What happens instead                                                                       |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Bindings with parameters — `` `the smaller of` a b `` | Substituting a definiens at a call site that has arguments is beta reduction, and doing it correctly needs capture-avoiding substitution. Out of scope, and the payoff is small: a parameterised helper is genuinely a function, and reading it as one leaf is defensible. | Left opaque, exactly as today.                                                             |
| Recursive and mutually recursive bindings             | Substitution does not terminate.                                                                                                                                                                                                                                           | Left opaque; the cycle is detected, not hit.                                               |
| `LocalAssume`                                         | An `ASSUME` is uninterpreted by construction; there is no definiens to substitute.                                                                                                                                                                                         | Left opaque.                                                                               |
| Bindings the body never references                    | Nothing to do.                                                                                                                                                                                                                                                             | Dropped from the residual `WHERE` only if every binding was inlined; otherwise left alone. |

> **The arity guard is new, and it matters.** `LSP.L4.Viz.Ladder.inlineExpr` — the interactive
> "expand this leaf" gesture behind `l4/inlineExprs` — documents itself as inlining "only 'App of
> no args' exprs", but its guard is
>
> ```haskell
> isRefOfTarget = \case
>   App _ resolved _args -> case resolved of
>     Ref _ uniq _ -> uniq.unique == target
>     _            -> False
> ```
>
> which **ignores `_args`**. It replaces `f x y` with `f`'s bare definiens and drops the
> arguments. In the IDE this is masked, because the uniques offered to the user come from
> zero-arity definitions; a pass that runs automatically over every binding would not be so
> lucky. §5 checks arity explicitly rather than inheriting this.

## 4. Where it lives

`L4.Transform` (`jl4-core`), whose header already reads "ad-hoc logical transformations of
resolved expressions" and whose existing `nnf`/`cnf` already carry `Where` cases. That placement
is what makes the pass reachable from all three consumers:

| Consumer        | Package                                           | Can reach `L4.Transform`? |
| --------------- | ------------------------------------------------- | ------------------------- |
| `l4 verify`     | `jl4/app` → depends on `jl4-core` _and_ `jl4-lsp` | yes                       |
| ladder / wizard | `jl4-lsp` → depends on `jl4-core`                 | yes                       |
| DMN/BPMN export | `jl4-core`                                        | yes                       |

Putting it in `jl4-lsp` beside the existing `inlineExprs` would have made it unreachable from the
exporter, since `jl4-core` cannot depend on `jl4-lsp` without a cycle.

## 5. The pass

```haskell
-- | Substitute zero-arity local WHERE/LET bindings into the body, to a fixed point.
inlineLocalBindings :: Expr Resolved -> Expr Resolved

-- | The same, over a decision's body, for consumers that hold a `Decide`.
inlineLocalBindingsInDecide :: Decide Resolved -> Decide Resolved
```

Algorithm, per `Where`/`LetIn` node, innermost first:

1. Collect candidates: `LocalDecide _ (MkDecide _ _ (MkAppForm _ n [] _) rhs)` — **empty parameter
   list**. Key by `n`'s unique.
2. Drop from the candidate set any binding reachable from its own definiens (self- or mutual
   recursion), computed as a reachability closure over references among the candidates.
3. Substitute surviving candidates into the body and into each other's definienda, iterating to a
   fixed point. Termination follows from step 2: the reference graph among the candidates is now
   acyclic, so each pass strictly reduces the number of remaining references.
4. A reference is `App _ (Ref _ u _) []` — **an empty argument list is required**, per §3.
5. If every binding was consumed, the node collapses to the substituted body; otherwise the node
   is retained carrying only the bindings that survived.

**Annotations.** The definiens is spliced with its own `Anno`, so a finding at an inlined
sub-expression points at the `WHERE` clause where the drafter wrote it. That is the right answer:
it is where the text is.

## 6. What this does to existing behaviour

- **`l4 verify`**: strictly more findings, never fewer — R1 only removes opacity. The
  `nestedNotVisited` accounting stays, because §7 keeps genuinely nested _analysis_ out of scope.
- **The caveat text** in `Verify.hs` must be corrected in the same change. It currently implies
  top-level decisions are analysed whole; after this change they are, and before it they were not.
  Leaving the old wording would be a false statement in the tool's own output.
- **Goldens**: any golden capturing `l4 verify` output for a file with `WHERE` may move. That is
  the intended effect; each mover is to be read, not blessed.

## 7. Scoped out, with reasons

**The ladder's default view.** `LSP.L4.Viz.Ladder`'s entry point stays as it is. Whether a leaf
that _is_ a named local binding should be drawn as one box or exploded into its definiens is a UX
question, not a soundness one — the whole point of the existing `l4/inlineExprs` gesture is to let
the reader choose. Making the pass mandatory there would delete a feature. Verify and the ladder
therefore _can_ disagree about the picture, and the comment at `Verify.hs:336` that forbids this
should be narrowed: what must not disagree is what a rule **means**, and after R1 they agree about
that. What may differ is how much of it is drawn at once.

**The exporter.** `L4.Export.Document` also uses the one-level fold (line 293), and a table-shaped
classifier inside a `WHERE` exports as nothing at all — an empty document, no error. But the fix
there is **descent, not inlining**: such a helper wants to become _its own decision table_, which
is the opposite operation. Inlining it into an arithmetic parent produces a parent that is still
not table-shaped. Separate change, separate spec.

> Worked example, measured 2026-08-27. `DECIDE d IS price TIMES rate WHERE rate MEANS CONSIDER …`
> exports to an empty `dmn-md` document. Lifting `rate` to a top-level `DECIDE` yields the full
> five-row decision table, hit policy `F`, with the enum constructors as cell values.

## 8. Open

- **O1.** Should the pass be available as a CLI flag (`--no-inline-locals`) so a user can see the
  pre-R1 picture? Argument for: it is how you'd tell whether a finding depends on the pass.
  Argument against: nobody wants the less sound analysis, and a flag that only makes the tool
  worse is a flag that exists to be misread. _Proposed: no flag; the finding's own atoms list
  already shows what it saw._
- **O2.** Parameterised bindings (§3) via proper beta reduction. Wanted eventually; wants a
  capture-avoidance story first.
