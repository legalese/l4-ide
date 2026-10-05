# Referential transparency for the static analyses — inlining local `WHERE`/`LET` bindings

_Status: **implemented** for `l4 verify` — zero-arity local bindings on 2026-08-27 (branch
`mengwong/where-inlining`), and on 2026-09-29 parameterised local bindings and calls to other
boolean rules (branch `feat/verify-beta-reduction`, §9). The ladder default view and the
exporter's descent are scoped out and reasoned about in §7._

**One-line summary.** `x WHERE x MEANS e` and `e` mean the same thing to the evaluator and
different things to the analyser. This spec makes them mean the same thing to the analyser too:
local bindings are substituted before analysis (§5), and a call to another rule is read through
to what that rule means (§9).

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

| Case                                                  | Why                                                                                                                                                                         | What happens instead                                                                       |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Bindings with parameters — `` `the smaller of` a b `` | Substituted by beta reduction since 2026-09-29, at a call whose argument count matches (§9.2). A reference at another arity — the helper passed as a value — is not a call. | Left alone at other arities, and the binding it needs is kept.                             |
| Recursive and mutually recursive bindings             | Substitution does not terminate.                                                                                                                                            | Left opaque; the cycle is detected, not hit.                                               |
| `LocalAssume`                                         | An `ASSUME` is uninterpreted by construction; there is no definiens to substitute.                                                                                          | Left opaque.                                                                               |
| Bindings the body never references                    | Nothing to do.                                                                                                                                                              | Dropped from the residual `WHERE` only if every binding was inlined; otherwise left alone. |

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

### 3.1 What the ladder does with calls today — measured 2026-09-23

This section reports measurements, not rules.
It asks what the "parameters" row of §3 costs the ladder, and whether a section `GIVEN` changes that.

**Rig.**
A six-decision probe module, rendered by `~/.cabal/bin/jl4-lsp` (installed 2026-09-23, tree `20e71b65d`) over a websocket, using the same `codeLens` → `workspace/executeCommand` sequence as `ts-shared/ladder-svg/standalone/serve.mjs`'s `/render`.
The decisions: a two-parameter `` `limb` p q IF p AND q ``; a caller passing it two different pairs of actuals; a caller passing it the same pair twice; a section `GIVEN s, t` with `` `sect limb` IF s AND t ``; a same-section caller reading `` `sect limb` `` twice by name; and a same-section caller reading it once plainly and once `WITH s IS r`.

**1. A named same-section call is already zero-arity.**
`` `sect limb` `` arrives as a `UBoolVar` with `canInline: true`, and both occurrences carry one `atomId`.
A section `GIVEN` is elaborated into one binder shared by the section (`desugarSectionGivens`, `L4.Desugar`), so the rule genuinely takes no arguments and the call site passes none.
The "parameters" row of §3 does not reach this case; the existing `l4/inlineExprs` gesture inlines it today.
R1 does not, because R1 covers **local** bindings and `` `sect limb` `` is top-level — a scope question, not a capture question.

**2. `WITH` is the case that really substitutes.**
`` `sect limb` WITH s IS r `` arrives as one opaque `UBoolVar` labelled with the whole expression, `canInline: false`.
Inlining it means replacing the section binder by `r` throughout the definiens, which is the §3 case.

**3. A parameterised call arrives as `App`, with its actuals as children, and expanding it in the new engine drops them.**
`ts-shared/ladder-svg/standalone/playground.ts` expands ("hydrates") a call client-side by splicing the callee's body in place of the `App` (`buildDisplay`, lines 126–140).
The callee's leaves are its formals, so `limb OF a, b` and `limb OF c, d` both expand to `p AND q`, and the `App`'s children — the actuals — are discarded.
This is by reading; the playground was not driven in a browser.

**4. Expanded copies never share a value, whether or not they should.**
`ViewSpec.valuation` is keyed by display node id (`ladder-core/src/types.ts`, the `ViewSpec` header; `layout.ts`, "positional per-node").
Spreading one answer to every box of the same proposition is left to the host — `ts-apps/regcf-wizard/src/lib/components/Ladder.svelte` does it by `Unique` — and the playground does not.
So two expansions of `limb OF a, b` in one tree can show `p` true in one copy and unknown in the other.
For different actuals the independence is right and the labels are wrong; for the same actuals the labels are right and the independence is wrong.

**5. Unplanned: an `atomId` collision between a call and an argument.**
An `App` leaf's `unique` is its **node id** (`jl4-lsp/src/LSP/L4/Viz/Ladder.hs`, `uniq = vid.id` in the `App` case), while a `UBoolVar`'s is a **resolver `Unique`**.
`annotateLadderWithAtomIdsUsing` (`LSP.L4.Viz.QueryPlan`) re-keys both through `reAtom nm.unique` over one `Map Int Text`, so whenever the two numbers coincide the variable inherits the call's `atomId`.
Measured: in the different-actuals caller, `b` (resolver `Unique` 6) carried the `atomId` of `App#6`, `limb OF c, d`.
Positive control: adding one unused leading parameter shifts the resolver numbering by one, and the collision moved to `a` (now `Unique` 6) while `b` became distinct.
This failure is **silent**: anything that addresses that leaf by `atomId` addresses the call instead, with no diagnostic.
It sits inside the reconciliation `45ea9f94a` added for smucclaw/l4-ide#935, and is filed as smucclaw/l4-ide#991.
Re-measured 2026-10-01 on `unstable` @ `f9a504b77`, with the probe and the control both reproducing exactly; no commit in between touched either cited file.

**What this does to O2.**
With resolved names, avoiding capture is mostly bookkeeping, not the hard part.
A substitution that maps each formal's `Unique` to its actual never compares spellings, so it cannot capture.
It can duplicate the callee's own local binders when one body is expanded twice, which is a freshening chore.
The part that needs a ruling is **atom identity**: two expansions should share an atom exactly when their actuals are the same terms.
Findings 3 and 4 show the new engine currently gets that wrong in both directions.
A named same-section call meets the condition by construction (finding 1), and that is the common house-style case.
This paragraph is argued, not built.

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
- **O2.** Parameterised bindings (§3) via proper beta reduction. **ANSWERED 2026-09-29, see §9**
  (Meng's BETAMAX, which also asked for calls to top-level rules, across imports). The
  capture-avoidance story is §9.2: names are resolved to uniques first, so there is nothing to
  capture.
  §3.1 (2026-09-23) had measured the open question this leaves for the ladder: atom identity across
  expansions, which the expand gesture then got wrong in both directions. §10 takes it up.

## 9. Reading through calls to other rules (2026-09-29)

**What prompted it.** Textbook diagrams of the Penal Code — Woon's _Essential Criminal Law_ — end in an arrow: `[conditions] → not murder by reason of sudden fight`.
The encoding carries that as a separate rule (`` `Exception 4 to section 300 applies` ``) that the offence calls as a defeater.
The diagram's arrow is then a property of the encoding — the exception applying and the offence being made out never hold together — and `l4 verify` could not check it, because a call to another rule was an opaque leaf.
Measured before this change on a two-rule probe: a correct encoding and a deliberately broken one (the offence forgets its exception) both reported **no findings**.
The tool could not tell them apart.
Meng's ruling (BETAMAX): substitute through calls, arguments included.

### 9.1 The rule

> **R2.** When a decision is analysed, each leaf that is a call to a rule returning `BOOLEAN` — in the same module or any module it imports, transitively — is read through: its **meaning** is the called rule's body, unfolded all the way down, arguments in place of parameters, and every satisfiability check the analysis makes uses that meaning in place of the leaf.
>
> **Findings are still reported only at the decision's own sites.** The leaf stays one leaf of the decision's ladder; what changes is what the analysis knows it means.

The second paragraph is the design, and it is the one that took a measurement to find (§9.4).

### 9.2 Beta reduction, and why nothing can be captured

`L4.Transform.unfoldOnce` replaces a call `App _ r args` whose callee is known **and whose argument count equals the callee's parameter count** by the callee's body with each argument in place of its parameter.
The arity check is the guard: a reference at another arity is the rule passed as a value, not a call, and is left alone.
`inlineLocalBindings` uses the same step for local bindings, so a `WHERE` helper with parameters is now substituted too (§3's first row).

Capture cannot happen, and this is the whole of the "capture-avoidance story" O2 was waiting for.
Names are resolved to `Unique`s before any of this runs, and a parameter's unique belongs to its own definition, so an argument — built in the caller's scope — cannot contain the callee's parameter, and a binder inside the callee cannot bind anything the argument refers to.

Two things stay opaque: a **recursive** rule (`pruneRecursive` removes every definition that can reach itself; its unfolding would not terminate) and a rule whose body **applies one of its own parameters** as a function (substitution is then no longer replacement of a value).
Rules that do not return `BOOLEAN` are not candidates either: a numeric helper unfolded into a comparison leaves the comparison a leaf, with a longer label.

### 9.3 Imported rules, and the zonk they need

An imported body is carried into the importer's analysis.
The checked program's annotations are not zonked when `LSP.L4.Rules` builds the result, and an importer starts from an **empty** substitution, so a rule whose return type was _inferred_ (no `GIVETH`) carries an inference variable only its own module can resolve.
`l4 verify` therefore zonks each candidate body with its own module's substitution (`ApplySubst (Expr Resolved)`, new).
Measured: without it, such an imported rule is never recognised as boolean, never read through, and a contradiction through it is silently missed.
`tests-cli/fixtures/verify-unfold-rules.l4` omits `GIVETH` on purpose.

### 9.4 What review changed: unfolding the whole rule was the wrong unit

The first implementation substituted every call into the decision's body and analysed the result as one rule.
On the fixtures it was right; on the Penal Code deposit it failed twice, and both failures are why §9.1 has its second paragraph.

- **Noise.** `pc-body-b-sexual.l4` went from 102 findings to **787** (499 vacuous-guard, 288 dead-branch).
  Copy a general helper into a rule that already narrows it, and the helper's own limbs become dead or redundant _in that context_.
  True, and useless: it is how every genus-and-species rule is built, and the sites named (`body.and[4]`) do not exist in the caller's text.
- **Size.** Unfolding copies a shared rule into every caller, and the ladder then converts the result to CNF.
  `offence under s 325` has **four** atoms and an unfolded CNF past 4096 nodes; the homicide module went from 3 s to more than ten minutes.
  Meng's observation holds exactly: legal rules have small _n_.
  What grew was the representation.

R2 fixes both at once.
The caller's ladder is analysed as written, so the traversal and the sites are the caller's.
A meaning is drawn as a ladder **without** the CNF simplification — the decision diagram needs no normal form — so it is linear in the unfolded body.
Measured on the same three modules after the change: homicide 19 s (31 calls read through, none left opaque), hurt 11 s, sexual 30 s with the **same 102 findings** as before.

### 9.5 How a meaning is built

For each atom of the decision's ladder whose leaf (`LadderViz.getLeafExpr`, recorded as the ladder is drawn) is a call to a candidate:

1. unfold it (`unfoldCalls`), then substitute local bindings;
2. draw it as a ladder under the **caller's** name and parameters, so that a leaf such as `` f's `harm was caused` `` gets the same atomId it has in the caller, with CNF off;
3. renumber its atoms into the caller's atom space by atomId, minting fresh numbers for atoms the caller never mentions.

`satisfiable` replaces each call atom by its meaning before compiling the decision diagram.
The atomId is the only identity that crosses a rule boundary, so reading through requires atom coalescing, and `--no-coalesce-atoms` turns it off.

A call whose meaning cannot be drawn, or is over `--max-nodes` even without CNF, stays an opaque leaf.
It is **named** on its rule (`call left as a leaf: … — reason`) and counted in `summary.callsLeftOpaque`.
At that atom the analysis is the old, per-rule one, and it says so.

### 9.6 A soundness bug this exposed, fixed in the same change

Measured before this change, on no unfolding at all: `n > 3 AND b` was analysed as **one** atom, and `l4 verify` reported both conjuncts as vacuous — a false finding, from a tool whose findings are meant to be sound.
Whether it happened depended only on how many inputs were declared before `b`.
The ladder keyed a bare reference's variable by the name's unique and a compound leaf's by a fresh id from a counter that also started near zero, and nothing kept the two ranges apart.
Fixed in `LSP.L4.Viz.Ladder`: fresh ids now start above every unique in the rule.

Unfolding makes a second collision reachable.
Each module numbers its own names from the same starting point — an importer does not continue its dependencies' supply (`unionCheckStates`) — so two different imported names can share an Int.
A bare reference to a name from another module is therefore drawn as a compound leaf with a fresh id; coalescing by atomId still merges its occurrences.
"Another module" means the URI the typechecker stamped on the module being drawn (`MkModule _ uri _`), not the `moduleUri` a caller derives from the document id it passes in.
The first version compared against the latter; the service's query-plan tests pass a synthetic document id, so every name looked foreign, TYPICALLY defaults (keyed by the name's unique) were lost — two ask-order tests failed — and the suite then stalled in its ladder-budget group for 27 minutes before it was killed; with the fix the query-plan tests take 8 s.

The same ladder module serves the web wizard's query plan (`jl4-service`), so both fixes reach it.

### 9.7 The ladder's expand gesture

`l4/inlineExprs` used to replace `f x y` by `f`'s bare body and drop the arguments; it was masked only because the gesture was offered on bare references alone.
It now uses `unfoldOnce`, so it substitutes arguments and respects arity, and it is offered on a call **with** arguments to a rule of the same module (`callLeafTargets` maps the leaf's fresh id back to the rule).

### 9.8 What this does to existing behaviour

- Findings: a decision's findings now depend on what its calls mean.
  The first corpus-wide differential is recorded in §9.9.
- JSON: each analysed decision carries `callsReadThrough` and `callsLeftOpaque` (a list of names with reasons); the summary carries their totals.
- `--decision NAME` now filters on the name as written **before** analysing.
  It used to filter on the report's name, which the analysis produces, so every decision was analysed and most were thrown away — tolerable while analysis was cheap.

### 9.9 Measured over the corpus (2026-09-29)

Baseline `73a953821` against this branch, `l4 verify --format json` over every `.l4` under `jl4/examples/{ok,legal,canon}`, `jl4-core/libraries`, and the Penal Code first-cut deposit (`~/src/legalese/pc-encode/deposit`, not in this repository): 464 files.

- Both binaries analysed the same 1,998 decisions; none moved between analysed and skipped.
- 1,325 calls were read through, and none was left opaque.
- Findings went from 186 to 219, in 28 decisions.
  No finding was lost.
- Because none was lost, the id collision of §9.6 produced no false finding anywhere in this corpus as it stands; its fixture is the only witness.
- Of the 28 decisions, 23 were read against their source, and every finding is a true statement about the rule: most are literal `TRUE`/`FALSE` constants read through (the `ok/inert/` fixtures, `ok/set-operators-overloads.l4`, `ok/mixfix-*.l4`), and the rest are a call's meaning overlapping the caller's own conditions.
  Examples: in the Penal Code deposit, s 336(b)'s negligent-act limb adds nothing, because s 26F(2) makes rashness negligence; s 325's carve-out for s 334A can never apply given s 322's fault element; s 386 restates what `commits extortion` already requires.
  In canon, `robbery-390-392.l4`'s `liable under s 392` is a tautology over its facts, which its own comment says is by construction.
- Not read: `canon/sg/succession/sg-wills.l4` (1), `canon/us/chubb-hospital-cash/blind-guarded/chubb-denovo.l4` (2), `canon/us/regcf/cleanroom/regcf-denovo.l4` (1), `canon/contracts/payments/sg-miles-card/dbs-womans-world.l4` (1).

**Time.** Reading through costs an extra ladder drawing per call atom, and the satisfiability checks see bigger formulas.
On the three Penal Code modules timed one by one: homicide 3–4 s → 18–19 s, hurt 2 s → 11 s, sexual offences 19–20 s → 30 s.
`classify.l4` in the miles-card subject: 1.7 s → 2.7 s.
The whole Penal Code deposit, 36 files run one after another: 147 s → 263 s.
