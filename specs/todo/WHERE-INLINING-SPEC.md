# Referential transparency for the static analyses — inlining local `WHERE`/`LET` bindings

_Status: **implemented** for `l4 verify` — zero-arity local bindings on 2026-08-27 (branch
`mengwong/where-inlining`), and on 2026-09-29 parameterised local bindings and calls to other
boolean rules (branch `feat/verify-beta-reduction`, §9, merged into `unstable` on 2026-10-06 by PR #561). The ladder default view and the
exporter's descent are scoped out and reasoned about in §7._

_§10, call expansions in the ladder, is **merged into `unstable`** on 2026-10-06 by PR #561 (branch `mengwong/ladder-call-panels`, "this branch" below; merge commit `e6e037d81`), which also carried §9; PR #520, which carried §9 alone, was closed in favour of it.
Server: `afffcb6e5` (expansions on the wire) and `56e978951` (opt-in per request, mixfix labels).
Client: `ec7cae39e` (call panels) and `ab06af184` (real fixture, the IDE's click spreading, folded answers drive current).
§10's line citations are to the tree at `e6e037d81`._

_§10.7, named and polymorphic calls (smucclaw/l4-ide#1033), is built on branch `mengwong/ladder-dustpan`, not merged when this was written._

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
in verify's `topLevelDecides` (`jl4/app/L4/Cli/Verify.hs:359-360`). Both folds already exist
(`jl4-core/src/L4/Syntax.hs:800` and `:811`), and verify already calls the second one to
_count_ what it skipped (`nestedNotVisited`, `Verify.hs:386-390`). One line.

It would not help. It yields a separate report on `enrolled`, and `enrolled MEANS \`is a member\``
is faultless on its own. **The contradiction exists only in the combination**, so the unit of
analysis has to be the caller with the callee substituted in — not the callee as a peer.

---

## 2. The rule

> **R1.** Before a decision is handed to a static analysis, every reference to a **zero-arity**
> local binding introduced by `WHERE` or `LET … IN`, in that decision, is replaced by the
> binding's definiens, to a fixed point.

Since 2026-09-29 the same pass also substitutes a local binding **with** parameters, by beta reduction at a call whose argument count matches (§9.2).

Consequences, in order of importance:

- `hidden` and `flat` produce the same findings, because after R1 they are the same expression.
- Atom coalescing then does the rest: the two occurrences of `` `is a member` `` share an
  `atomId`, collapse to one atom, and the `[unsat]` falls out of the existing analysis unchanged.
- **No analysis logic changes.** R1 is a pre-pass. Every finding, verdict and caveat downstream
  keeps its current meaning.

## 3. What is deliberately _not_ inlined

| Case                                                           | Why                                                                                                                                                                         | What happens instead                                                                            |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Bindings with parameters — `` `the smaller of` a b ``          | Substituted by beta reduction since 2026-09-29, at a call whose argument count matches (§9.2). A reference at another arity — the helper passed as a value — is not a call. | Left alone at other arities, and the binding it needs is kept.                                  |
| Recursive and mutually recursive bindings                      | Substitution does not terminate.                                                                                                                                            | Left opaque; the cycle is detected, not hit.                                                    |
| `LocalAssume`                                                  | An `ASSUME` is uninterpreted by construction; there is no definiens to substitute.                                                                                          | Left opaque.                                                                                    |
| Bindings the body never references                             | Nothing to do.                                                                                                                                                              | Dropped individually once nothing refers to it; the node collapses if none survive (§5 step 5). |
| A binding that applies one of its own parameters as a function | Substituting a function-valued parameter is no longer plain replacement of a value (`unfoldableDecide`, `Transform.hs:151-159`).                                            | Left opaque; §10.4 does not expand a call whose callee keeps such a local.                      |

> **The arity guard matters.** A reference at another arity is the binding passed as a value, not a call, and substituting the bare definiens there drops the arguments.
> The pass checks arity explicitly (`L4.Transform.unfoldOnce`, `jl4-core/src/L4/Transform.hs:208-216`).
> The ladder's interactive "expand this leaf" gesture, `l4/inlineExprs`, uses the same step (`LSP.L4.Viz.Ladder.inlineExpr`, `jl4-lsp/src/LSP/L4/Viz/Ladder.hs:928-934`; §9.7).

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
`ts-shared/ladder-svg/standalone/playground.ts` expands ("hydrates") a call client-side by splicing the callee's body in place of the `App` (`buildDisplay`, lines 126–140 at `20e71b65d`).
The callee's leaves are its formals, so `limb OF a, b` and `limb OF c, d` both expand to `p AND q`, and the `App`'s children — the actuals — are discarded.
This is by reading; the playground was not driven in a browser.
_Changed:_ `ec7cae39e` removed the client-side splice; the playground now draws the server's expansions, arguments substituted (§10.3).

**4. Expanded copies never share a value, whether or not they should.**
`ViewSpec.valuation` is keyed by display node id (`ladder-core/src/types.ts`, the `ViewSpec` header; `layout.ts`, "positional per-node").
Spreading one answer to every box of the same proposition is left to the host — `ts-apps/regcf-wizard/src/lib/components/Ladder.svelte` does it by `Unique` — and the playground does not.
So two expansions of `limb OF a, b` in one tree can show `p` true in one copy and unknown in the other.
For different actuals the independence is right and the labels are wrong; for the same actuals the labels are right and the independence is wrong.
_Changed:_ the playground now spreads one click over every box with the clicked box's `atomId` (`spreadValue`, §10.3), and §10.1's identity rule decides which boxes those are.

**5. Unplanned: an `atomId` collision between a call and an argument.**
An `App` leaf's `unique` is its **node id** (`jl4-lsp/src/LSP/L4/Viz/Ladder.hs`, `uniq = vid.id` in the `App` case), while a `UBoolVar`'s is a **resolver `Unique`**.
`annotateLadderWithAtomIdsUsing` (`LSP.L4.Viz.QueryPlan`) re-keys both through `reAtom nm.unique` over one `Map Int Text`, so whenever the two numbers coincide the variable inherits the call's `atomId`.
Measured: in the different-actuals caller, `b` (resolver `Unique` 6) carried the `atomId` of `App#6`, `limb OF c, d`.
Positive control: adding one unused leading parameter shifts the resolver numbering by one, and the collision moved to `a` (now `Unique` 6) while `b` became distinct.
This failure is **silent**: anything that addresses that leaf by `atomId` addresses the call instead, with no diagnostic.
It sits inside the reconciliation `45ea9f94a` added for smucclaw/l4-ide#935, and is filed as smucclaw/l4-ide#991.
Re-measured 2026-10-01 on `unstable` @ `f9a504b77`, with the probe and the control both reproducing exactly; no commit in between touched either cited file.
_Changed:_ `feat/verify-beta-reduction` (#520, which landed through #561) fixed this on the LSP ladder by starting fresh ids above every unique in the rule (§9.6), measured 2026-10-05 (§10.2); the `jl4-core` mirror, which lacked that seeding, has it since `afffcb6e5` (§10.3).

**What this does to O2.**
With resolved names, avoiding capture is mostly bookkeeping, not the hard part.
A substitution that maps each formal's `Unique` to its actual never compares spellings, so it cannot capture.
It can duplicate the callee's own local binders when one body is expanded twice, which is a freshening chore.
The part that needs a ruling is **atom identity**: two expansions should share an atom exactly when their actuals are the same terms.
Findings 3 and 4 show the new engine currently gets that wrong in both directions.
A named same-section call meets the condition by construction (finding 1), and that is the common house-style case.
This paragraph is argued, not built.
_Changed:_ the substitution is built as §9.2's `unfoldOnce`, and for the ladder the identity question is answered by R3 (§10.1), ruled 2026-10-07: the same proposition is the same C1 term key.
The callee's own local bindings are inlined before it is drawn and a call whose body still binds locally is left unexpanded, so nothing needs freshening (§10.4).

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
-- | Substitute local WHERE/LET bindings into the body, to a fixed point
-- (parameterised ones by beta reduction, §9.2).
inlineLocalBindings :: Expr Resolved -> Expr Resolved

-- | The same, over a decision's body, for consumers that hold a `Decide`.
inlineLocalBindingsInDecide :: Decide Resolved -> Decide Resolved
```

Both are in `jl4-core/src/L4/Transform.hs` (`:93` and `:307`).
Algorithm, per `Where`/`LetIn` node, innermost first:

1. Collect candidates: every `LocalDecide` that `unfoldableDecide` accepts (`Transform.hs:152-161`), with any number of parameters.
   It refuses a definition whose body applies one of its own parameters as a function (§9.2).
   Key by the bound name's unique, and keep the parameters' uniques in order.
2. Drop from the candidate set any binding reachable from its own definiens (self- or mutual
   recursion), computed as a reachability closure over references among the candidates
   (`pruneRecursive`, `Transform.hs:219`).
3. Substitute surviving candidates into each other's definienda, iterating to a fixed point (`closeUnder`, `Transform.hs:232`), and then into the body.
   Termination follows from step 2: the reference graph among the candidates is now acyclic, so each pass strictly reduces the number of remaining references.
4. A reference is a call `App _ r args` to a candidate **whose argument count equals the candidate's parameter count**, replaced by the definiens with each argument in place of its parameter (`unfoldOnce`, `Transform.hs:256-264`).
   Since 2026-10-11 a call written with named arguments is such a call too, read as the positional call it stands for (`positionalCall`, `Transform.hs:201`; §10.7).
   A reference at another arity is left alone, per §3.
5. A binding is dropped once nothing refers to it any more, which for a zero-arity binding is always; a parameterised one can still be referenced at another arity (`Transform.hs:115-138`).
   If every binding was dropped, the node collapses to the substituted body; otherwise the node is retained carrying only the bindings that survived.

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
therefore _can_ disagree about the picture: what must not disagree is what a rule **means**, and
after R1 they agree about that. What may differ is how much of it is drawn at once.
Verify's own comment now says exactly this (`jl4/app/L4/Cli/Verify.hs:378-385`).
§10 keeps that choice with the reader: the default render still draws each call as one box, and a client that asks for it also gets the expansion of each call within §10.3's bounds, to open or fold.

**The exporter.** The DMN exporter reads only top-level declarations, descending into sections but not into `WHERE` (`topDecls`, `jl4-core/src/L4/Dmn/Lower.hs:6964-6970`), so a table-shaped classifier inside a `WHERE` never becomes a decision table.
But the fix there is **descent, not inlining**: such a helper wants to become _its own decision table_, which
is the opposite operation. Inlining it into an arithmetic parent produces a parent that is still
not table-shaped. Separate change, separate spec.

> Worked example, measured 2026-10-06 with the installed `l4` (built 2026-10-02).
> `DECIDE d price tier IS price TIMES rate WHERE rate MEANS CONSIDER tier WHEN …` exports to a `dmn-md` document with no table: `d` is `OMITTED` as a formula with `rate`'s `CONSIDER` substituted into it, under a blocking `D-MD-NOLITERAL` note, and the command exits 0.
> Lifting `rate` to a top-level `DECIDE rate tier IS CONSIDER tier …` yields its decision table, one row per enum constructor.

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
  expansions, which the expand gesture then got wrong in both directions.
  §10.1 answers it for the ladder with R3, ruled 2026-10-07.

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

_Changed 2026-10-11 (smucclaw/l4-ide#1033, §10.7):_ a call written with named arguments, `` `big` WITH k IS n ``, is such a leaf too, read as the positional call it stands for; until then it stayed an opaque atom.
Assumed, not ruled: R2 says "each leaf that is a call", and a named call is one.

### 9.2 Beta reduction, and why nothing can be captured

`L4.Transform.unfoldOnce` replaces a call `App _ r args` whose callee is known **and whose argument count equals the callee's parameter count** by the callee's body with each argument in place of its parameter.
A call with named arguments is read as its positional call first (`positionalCall`, since 2026-10-11, §10.7).
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
It now uses `unfoldOnce`, so it substitutes arguments and respects arity, and it is offered on a call **with** arguments to a rule of the same module that is drawn as a leaf (`callLeafTargets` maps the leaf's fresh id back to the rule; `leafFromExpr`, `jl4-lsp/src/LSP/L4/Viz/Ladder.hs:701-706`).
It is not offered on a call whose arguments are all `BOOLEAN`: that call is drawn as a `V.App` (`Ladder.hs:607-628`), which has no `canInline` field and no `callLeafTargets` entry.
Such a call can be drawn expanded only through §10, where it carries its expansion.
One request still unfolds **every** call to the rule in the decision, by design; since `afffcb6e5` its reply carries atomIds in the same namespace as the render it expands (§10.3).

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

## 10. Expanding calls in the ladder (2026-10-05)

_Merged into `unstable` on 2026-10-06 by PR #561; see the status header._

**What prompted it.** Meng saw a hand-built page on 2026-10-05 (session `ed4dacbb`'s scratchpad, `ladder/foldable-ladder.html`) in which a call to another rule opens in place, inside a box named after the call, and folds back.
He asked for the infrastructure under it to be made real and internally consistent, stacked on #520.
He also asked: _"Do we have the feature where a ground term appearing multiple places in one diagram behaves like a single thing — clicking in one term should toggle all instances to match"_ (2026-10-05).
How a panel and a NOT's bubble are drawn was ruled the same day and is recorded in `ladder-diagrams-2026/DESIGN.md` §27.

### 10.1 The identity rule

> **R3** (**ANSWERED 2026-10-07**, ruled by Meng). Two boxes of one diagram are the same proposition exactly when they carry the same **C1 term key**.
> A call box's key is the called rule together with the C1 keys of its arguments.
> An expansion's leaves are keyed in the **caller's** context after substitution: the called rule's body, with the call's arguments in place of its parameters, is keyed as if the caller had written it.
> So the `a` inlined from `limb a b` is the caller's own `a`, `limb a b` and `limb c d` share no atom, and two copies of `limb a b` share every atom.
> The `atomId` is that key's implementation; the printed-label `atomId` in place when this was ruled was interim, and wherever it differed from the C1 key that was a defect, not behaviour (smucclaw/l4-ide#1013).

Ruling, 2026-10-07, asked inline in session `ladder-ref-trans`: option "C1's term key", over "the printed label, as built" and "no sharing across copies"; condition: the key stays stable across recompiles and the ladder and the query plan agree on it (#935); Meng's note: "seems like we should be prioritizing correctness over ease of implementation".
What prompted the rule is Meng's question of 2026-10-05, quoted above ("clicking in one term should toggle all instances to match"), and its basis is the evaluator's identity ruling, C1 of `UNKNOWN-EVALUATION-SPEC.md` (bench card C1, accepted by Meng 2026-10-01, recorded at `:1171`), of which R3 is the ladder's projection.
C1 keys every term by its structure: "an input, a field path, a built-in operation over terms, a join, an assumed call, and a comparison over any of these" (`UNKNOWN-EVALUATION-SPEC.md:472`).
A call to a rule the module defines is not an atom there; it is unfolded, so `older 18` leaves no trace of `older` (`:308-309`).
The ladder keeps the call as a box, because that is what the reader wrote, but the call's expansion is that unfolding, and R3 gives each of its leaves the key it would have if the caller had written the argument in place.

**Implemented** by legalese/l4-ide#598 (branch `feat/r3-c1-atom-key`, smucclaw/l4-ide#1013), not yet merged when this was written.
_Changed:_ until then the `atomId` was a UUID5 over the function name, the leaf's **printed label**, and the labels of its transitive input references, which equals C1's term key only where printing is injective, and it is not everywhere (§10.6).

The key is `L4.Viz.AtomKey.termKey` in `jl4-core`, and the `atomId` is a UUID5 over the function name and that key (`atomIdOfKey`).
`termKey` strips every annotation from the leaf's expression and renames every name, so two keys are equal exactly when the two terms are structurally equal after renaming:

- a binder defined inside the leaf (a quantifier or lambda variable, a pattern variable) is named by its scope, de Bruijn style, so alpha-equivalent leaves share a key, and so do two copies of one lambda that substitution put into one leaf;
- a free name of the module becomes its binder path, from `mkKeyEnv`: the top-level declaration and the name, qualified by the named sections around it only where an earlier binder took that path, and by a source-order ordinal only where that is taken too, so renaming or inserting a section heading moves no id; binders that only ever occur inside one leaf get no path;
- a free name of another module, or a builtin, keeps that module's own number for it, beside the module's file name, numbered apart where two modules share one.

A `WHERE` or `LET` local is not a name of its own in the key: the leaf's own local bindings, and the decision's `WHERE` locals it reads, are put in before keying (`inlineLocalBindings`), as a callee's are before its expansion is drawn, so a caller's `total GREATER THAN 3 WHERE total MEANS n PLUS 1` and the same text in a callee key alike.
A local that cannot be put in (a recursive one) stays in the term with its definition, so two unfolded copies of it with different arguments stay apart; keyed by name, they were one atom, and `l4 verify` reported a satisfiable rule unsatisfiable.
A leaf whose value depends on when it is evaluated, because it reads or writes the ledger or the network or calls a rule of the module that does, is keyed per occurrence instead, numbered in drawing order (C1's `fresh`): C1 keys a built-in by its term because it is a function of its operands, and a `RECALL` is not, so two occurrences either side of a `RECORD` can be FALSE and TRUE in one evaluation.
Keyed by term, they were one atom, and `l4 verify` reported such a rule unsatisfiable; it now also keeps these apart across the meanings it reads through (`getFreshLeaves`).
Before showing the term, the key also drops an inference variable's counter (an untyped lambda parameter's type carries one, and it moves when anything checked earlier changes) and writes a call whose arguments are all named as the positional call.
It puts back the one thing the term does not carry: the type a `JSONDECODE` decodes into, which the evaluator reads off the node's annotation.
Each of these was found by adversarial review of the design or of the built key, and each has a test (`AtomKeySpec`, `LadderTermKeySpec`, `LadderCallExpansionSpec`, and `l4-cli-test`'s `verify-recursive-local-copies.l4`).

Both ladder builders key every leaf this way while they draw, including each leaf of an expansion over the substituted body, and record the key under the leaf's id (`getLeafKeys`); the query plan reads those keys (`leafKeyByUnique`) instead of computing ids of its own, so the diagram and the plan cannot disagree.
A call box is the term `f a b`, so its key is the rule's path with its arguments' keys, as R3 says.

> **R3a** (**ANSWERED 2026-10-09**, ruled by Meng). The four choices #598 made without a ruling stand as built.
> (1) An `atomId` keeps the decision's name, so ids are scoped per diagram, although R3's text read literally names a proposition without it.
> (2) Section names enter a binder path only where two binders would otherwise collide, so renaming or inserting a heading moves no id.
> (3) `WHERE` and `LET` locals are put into keys, so a call to a local keys as its unfolding, unlike a call to a rule, which is a call box.
> (4) A leaf that reads or writes the ledger or the network, or calls a rule of the module that does, is keyed per occurrence (C1's `fresh`); a bare reference to such a rule of no parameters is not, since it is evaluated once and shared.

Ruling, 2026-10-09, asked inline in session `ladder-ref-trans` (offered as a bench, SOMMELIER, not built): all four as recommended; no conditions; Meng's note: "i think we can skip SOMMELIER if i just say i accept your recommendations".

What it knowingly leaves, by kind of failure:

- **Silent, and the safe direction: equal propositions can get two keys** where they are different terms, such as `a AND b` and `b AND a` inside one leaf.
  That says "two questions" where the truth is one, never the reverse (C1).
- **An `atomId` is stable across recompiles and edits elsewhere in the module, not across everything.**
  It moves when a binder with the same name is added above one it names (the later of the two is then told apart by its sections), when an imported module it names changes, or on an L4 release that changes the AST, since the key is `show` of it.
  A per-occurrence leaf (R3a (4)) is numbered in drawing order, so it also moves when such a leaf is added or removed earlier in the same decision.
- **The planner still holds twins as two variables.**
  Two occurrences of one term share an `atomId`, and a binding by `atomId` reaches both, but the BDD does not know they are equal, so `X AND NOT X` over a compound `X` is undetermined rather than `FALSE`.
  `l4 verify` coalesces by `atomId`; the query plan does not. Not in scope here (smucclaw/l4-ide#1032).
- **Silent, and the unsafe direction, pre-existing: `carameliseExpr` resets an `INERT`'s AND/OR context under a comparison**, so two comparisons that evaluate differently are drawn as one term and share an `atomId` (smucclaw/l4-ide#1031).

### 10.2 What was measured before building (2026-10-05)

Rig: probe scripts in session `ed4dacbb`'s scratchpad (`ladder/inline.mts`, `ladder/probe991.mts`), each starting a copy of a `jl4-lsp` binary over a websocket and sending the `codeLens` → `workspace/executeCommand` sequence `ts-shared/ladder-svg/standalone/serve.mjs` sends.
Inputs `ladder/{joint,passthru,r991,r991pc}.l4` in the same scratchpad; binaries: the installed `jl4-lsp`, and one built from #520.

- **A client-side splice keyed "call-site atomId > callee atomId" is the wrong rule.**
  It keeps different calls apart and survives smucclaw/l4-ide#991, but it never links an inlined parameter to the caller's leaf: in `limb a b AND a` the inlined `p`, which is `a`, never links to the caller's `a`, and in `is creditworthy a AND a's has stable income` the inlined copy never links to the direct one.
- **#520's `l4/inlineExprs` gets identity right inside one reply, and only there.**
  In `record pass through` the inlined and the direct `a's has stable income` share an `atomId`.
  But one request unfolds every call to the rule; the reply skipped the atomId annotation, so ids changed namespace across an expand (the untouched `a's has collateral` was `627b865d` before and `ea1f4320` after), and a client's answers keyed by atomId were lost; and an all-`BOOLEAN` call (`limb a b`) is a `V.App` with no `canInline`, so it could not be expanded at all (§9.7).
- **smucclaw/l4-ide#991 is gone on #520's LSP ladder.**
  The `App` ids were 154 and 157 against argument uniques 5 to 8, and the positive control was clean, because fresh ids start above every unique in the rule (§9.6).
  The `jl4-core` mirror (`jl4-core/src/L4/Viz/Ladder.hs`, used by `L4.API` and `jl4-wasm`) did not have that seeding.

### 10.3 The design as built

**On the wire.**
`UBoolVar` and `App` carry an optional `expansion`, an `IRExpr`, omitted from the JSON when absent, so an older client reads the leaf exactly as before (`jl4-core/src/L4/Viz/VizExpr.hs:116-131`; in `ts-shared/viz-expr/viz-expr.ts`, the `UBoolVar` and `App` interfaces and their Effect schemas, without which the decoder would drop the field).

**Which leaves are calls.**
Three kinds, each only when the callee is a rule of the module being drawn (`hasDefForInlining`, `jl4-lsp/src/LSP/L4/Viz/Ladder.hs:333-338`):
a bare reference to a rule with no parameters (`varLeaf`, `:682-686`); a call drawn as a leaf (`leafFromExpr`, `:707-712`); and an all-`BOOLEAN` call drawn as a `V.App` (`:623-625`).

**How an expansion is built** (`expandCall`, `Ladder.hs:763-798`).
Only the call is reduced: the callee's parameters are replaced by the call's arguments at the call's root (`Transform.substParams`), and calls inside the arguments keep their own expansions.
Before that, the callee's own `WHERE` definitions are inlined into its body (`Transform.inlineLocalBindings`, as `l4 verify` does; `Ladder.hs:444-447`), and a callee whose body still binds anything locally after that is not expanded (§10.4).
The result is translated by the caller's own `translateGo` in the caller's state, so the function name, the fresh-id counter, TYPICALLY defaults and input references are the caller's.
An expansion is its own subtree in its own field; it is never spliced into the caller's flattened `And` or `Or`.

**Bounds.**
A callee already being expanded around the node is not expanded again (recursion).
All expansions of one decision together may add at most `expansionNodeBudget = 2000` IR nodes (`Ladder.hs:161-162`).
`doVisualize` deepens one level at a time and keeps the deepest pass that fits, so every call is expanded to the same depth rather than the first call in reading order taking the whole budget (`Ladder.hs:395-413`).
A call that is not expanded keeps `expansion` absent and draws as before.
With expansions on, fresh ids are seeded above every unique in the **module**, not only the rule, because other rules' bodies are translated in the same state (`Ladder.hs:436`, `:448-450`).

**Opt-in, per request.**
`VizConfig.expandCalls` is off by default (`Ladder.hs:100`, `:109`).
A client turns it on with a fourth argument to `l4.visualize`, `[verDocId, srcPos, simplify, {"expandCalls": true}]` (`VisualiseOptions` and `decodeVisualiseArgs`, `jl4-lsp/src/LSP/L4/Actions.hs:271-300`).
Three arguments, `{}`, or `"expandCalls": false` mean no expansions; unknown keys are ignored; a fourth argument that is not an object fails the request with "l4.visualize: cannot read the options argument: …".
The "Show decision graph" lens sends three arguments (`Actions.hs:192`), so VS Code, jl4-web and the webview get no expansions.
Auto-refresh and `l4/inlineExprs` reuse the setting of the most recent render.
The only caller that turns expansions on is `visualise` (`Actions.hs:343`); `l4 verify`, `jl4-service`, the REPL and the `jl4-core` mirror never do.
Making it opt-in was a choice made on this branch for cost (§10.5), not a ruling.

**One `atomId` namespace for every leaf on the wire** (`ladderAtomIds`, `jl4-lsp/src/LSP/L4/Viz/QueryPlan.hs:74-92`).
The query plan's variables keep exactly the ids they had.
Every other leaf, an `App`'s arguments and every leaf inside an expansion, is named by the same function over the same dependency closure (`atomIdsOfLabels`, `jl4-query-plan/src/L4/Decision/QueryPlan.hs:228`), with its references rendered against the plan's own labels.
An inlined leaf that **is** a plan variable, such as the caller's `a` inlined from `limb a b`, carries that variable's unique and so gets its id.
_Changed (smucclaw/l4-ide#1013):_ the one namespace is now that of §10.1's term key: every leaf's id is the hash of the key the ladder recorded for it, and `atomIdsOfLabels` is gone.
The caller's `a` inlined from `limb a b` gets the caller's id because it is the same term.
Expansion leaves are not added to the plan's variables: `vizExprToBoolExpr` makes a call one variable and descends into neither its arguments nor its expansion.

**The rest of the server.**

- `l4/inlineExprs` keeps its unfold-everywhere semantics, and its reply now goes through the same annotation (`renderAfterInlining`, `Actions.hs:402-408`), so an untouched leaf keeps its id across an expand (`627b865d` stays `627b865d`).
- `l4/queryPlan` plans from the ladder and state the last render stored instead of drawing the decision again (`queryPlanForRecent`, `Actions.hs:421-424`).
- `jl4-service` names its ladder's leaves with the same `ladderAtomIds` (`jl4-service/src/Backend/DecisionQueryPlan.hs:257`).
- The `jl4-core` mirror seeds its fresh ids above every unique in the rule (`jl4-core/src/L4/Viz/Ladder.hs:316`) and emits no expansions.

**The client** (`ts-shared`).

- `fromVizFunDecl(viz, { calls })` and `fromVizExpr` take `calls: "leaf" | "expand"` (`ts-shared/ladder-core/src/viz-adapter.ts`).
  `"leaf"`, the default, decodes byte for byte as before.
  `"expand"` decodes a call that has an expansion to a group `{ $type: "And", id: <the call's id>, label: <the call's wire label, prefix-normalised>, call: true, args: [<the expansion>] }`, with the label from `callLabel`, so `` `is creditworthy` OF a `` reads `is creditworthy a`; every expansion leaf joins the identity indexes.
  The label is not the call as the drafter wrote it: a prefix call loses its `OF` and commas, and a mixfix call reads in the surface form the server prints (§10.6), both without backticks.
  Leaf mode shows the wire label as it is, backticks and `OF` included, so ticking "draw calls in place" renames the box; that difference is kept, not designed.
- `spreadValue(identity, nodeId, value, valuation)` sets, or clears for unknown, the value on every node that shares the clicked node's `atomId`, and on that node alone when it has none (also `viz-adapter.ts`).
- An open call group is laid out as a **panel**, with the NOT scope frame (DESIGN §21) as its template (`measurePanel`, `ladder-core/src/layout.ts:1072`); `Scene.panelDepth` is the panel nesting of the whole decision, folds ignored (`panelLevels`, `:1053`).
  A value set on a call is set aside while its panel is open, so an open panel conducts by what it draws (`dropOpenPanels`, `:1042`).
- `ladder-svg` shades panels by layer and fills the NOT bubble by the NOT's output; both are DESIGN §27.
- The playground's client-side splice is gone (`ladder-svg/standalone/playground.ts`).
  Each example in `serve.mjs`'s `EXAMPLES` says whether it first decodes in `"leaf"` or `"expand"` mode (the three call examples expand, the older ones default to leaf), and the "draw calls in place" box decodes the same replies again in the other mode.
  It folds a panel through `foldSet` and sends a box click through `spreadValue`.
  `serve.mjs` asks for expansions and, when the reply is null, asks again with the lens's three arguments, so it works against an older server too.

**Tests.**

- `jl4-lsp/test/LadderCallExpansionSpec.hs`: pass-through, different and identical actuals, a record argument, an `App` call, recursion, `inlineExprs` parity, `WHERE` locals, a caller input shadowing a module rule, a module rule as an argument, stability under a line added above, the budget, and the wire's omission of an absent field.
  Each failed under a positive control that reverted the hunk it guards (`afffcb6e5`'s message).
- `jl4-lsp/test/VisualiseExpansionOptInSpec.hs`, five cases from the lens's own arguments through `visualise`; each of five mutations of `Actions.hs` (default forced on, auto-refresh or `inlineExprs` resetting the flag, auto-refresh forcing it, the decoder ignoring the options) failed at least one case.
- `jl4-core/test/LadderFreshIdSpec.hs` for the mirror's seeding; `jl4-service/test/QueryPlanSpec.hs:380-395` for IDE and service agreeing on an `App`'s arguments.
- `ladder-core/test/call-expansions.test.ts` and `call-panels.test.ts`, and `ladder-svg/test/panels.test.ts`.

### 10.4 What review changed

The server half went through three adversarial reviews before `afffcb6e5`; these are the findings that changed the design.

- **A callee's `WHERE` locals are inlined, not drawn as names.**
  `unfoldOnce` copies a callee's body with its local bindings, and a local name has one unique in every call of its rule, though it stands for a different proposition in each.
  Measured 2026-10-05: `ok WHERE ok MEANS p` called with `a` and with `b` was one atom; a callee local named `a` meaning `NOT p` was taken for the caller's input `a`; and a callee's `both` was the caller's own `both` (`Ladder.hs:740-748`).
  Each expansion now inlines the callee's locals first, as `l4 verify` does, and a call whose reduced body still binds locally (a recursive `WHERE`, an `ASSUME`, a local that applies one of its own parameters as a function, or one referenced at another arity) is not expanded.
- **Every leaf on the wire is in the plan's namespace** (`atomIdsOfLabels`).
  #520 re-keyed only the plan's variables, so an `App`'s arguments and every expansion leaf kept the visualiser's numeric-reference ids beside neighbours keyed by label.
  A first fix rendered references with the extra leaves' labels added, and then the call `limb OF the season is open, a` had one `atomId` drawn directly and another inside `wrap a`'s expansion (measured 2026-10-05).
  References now render against the plan's labels only.
  The cost is stated in the code: a reference to a module rule that is not a plan variable renders by its unique, so it is never taken for a caller input that shadows it, but its `atomId` moves when a line is added above (`jl4-query-plan/src/L4/Decision/QueryPlan.hs:223-227`); the stability test covers leaves whose references are inputs.
  _Changed (smucclaw/l4-ide#1013):_ that cost is gone; the term key names a module rule by its path, and `LadderCallExpansionSpec` pins the rule's `atomId` across a line added above.
- **`l4/queryPlan` stopped drawing again.**
  It ran every deepening pass and translated every expansion on each request, which the webview sends on every change to the bindings, only for the plan to discard the expansions: 536 ms per request against 9 ms after, on a module with 254 expansions (`afffcb6e5`'s message).
- **Service parity.**
  `jl4-service` used the plan-only map and left an `App`'s arguments with numeric-reference ids, so the IDE and the service gave `a` two different `atomId`s (measured 2026-10-05; `QueryPlanSpec.hs:380-385`).
  It now uses `ladderAtomIds`.
- **Opt-in.**
  `afffcb6e5` turned expansions on for every "Show decision graph" render, at about three times #520's time on `regcf.l4`; the flag of §10.3 followed, so a client that does not draw panels does not pay.

### 10.5 Measured on the built design

**Cost, with and without the flag** (2026-10-06; `ladder/fetch-expand.mts` in session `ed4dacbb`'s scratchpad, a copy of `fetch.mts` that sends the flag unless `EXPAND=0`).
All 43 "Show decision graph" lenses of `jl4/examples/canon/us/regcf/regcf.l4` in turn, three interleaved rounds; total milliseconds per run and bytes of reply:

| run   | this branch, no flag | #520    | this branch, with flag   |
| ----- | -------------------- | ------- | ------------------------ |
| 1     | 2705 ms              | 1812 ms | 7601 ms                  |
| 2     | 2526 ms              | 2760 ms | 8421 ms                  |
| 3     | 2402 ms              | 2453 ms | 6929 ms                  |
| bytes | 39,233               | 39,233  | 132,926 (142 expansions) |

Without the flag this branch is within run-to-run noise of #520, and its `regcf.l4` output is byte-identical to #520's (`cmp` printed nothing).
With the flag a render takes about three times as long and the reply is 3.4 times the size.

**Without the flag, against #520, on the five scratchpad fixtures** (`joint`, `passthru`, `r991`, `loan`, `visa`): every top-level leaf has the same `atomId`; an `App`'s arguments differ only where §10.4's namespace fix says they should (`passthru` one equal and one different, `r991` four different); everything else is identical.

**The playground.** Through `serve.mjs` on `standalone/examples/joint-loan.l4` and `work-visa.l4`: 3 and 11 expansions from this branch's binary; 0 from #520's, with the same decision names and no errors.

**Gates.** At `afffcb6e5`: `jl4-lsp-test` 63/0, `jl4-service-test` 380/0, `jl4-core-test` 817/0, `l4-cli-test` 438/0, `jl4-test` 3741/0.
With the opt-in flag: `jl4-lsp-test` 68/0, `jl4-service-test` 380/0.
With the mixfix labels of §10.6 and the folded-call conduction fix of `ladder-diagrams-2026/DESIGN.md` §27.1 as well (2026-10-06): `jl4-lsp-test` 69/0, `jl4-service-test` 380/0, `l4-cli-test` 438/0 (83 pending); `jl4-core-test` and `jl4-test` were not re-run.

### 10.6 Known gaps

- **Two mixfix calls that share a head keyword used to share a label, and so an `atomId`; on the LSP ladder they no longer do.**
  A call leaf's label is `prettyLayout` of the call (`Ladder.hs:616`, `:713`), which prints only the head keyword of a mixfix call unless the call is stamped with its pattern (CLAUDE.md §3.2.2).
  In `jl4/tests-cli/fixtures/batch-mixfix-shared-head.l4`, `gift stands` drew both `` `the will` w `is duly executed without` 3 `` and `` `the will` w `is revoked counting` 3 `` as `` `the will` OF w, 3 `` with one `atomId`, from this branch's jl4-lsp and from #520's alike (measured 2026-10-06).
  Pre-existing on #520, but harmless while the IDE keyed answers by Unique; once a click binds every copy of an `atomId` (the last bullet), one click answered both, so `X AND NOT Y` could never come out TRUE, in the IDE and in the playground.
  Fixed for the LSP: every path that draws for the IDE reads the module through `ladderModule` (`jl4-lsp/src/LSP/L4/Actions.hs:445-456`), which stamps every mixfix call the typechecker's `MixfixRegistry` knows with its pattern (`stampMixfixCalls`, `Ladder.hs:122-153`), so the two calls are labelled in surface form and get different `atomId`s.
  Unlike `restoreMixfixPatterns` it does not stop at operators defined in the module, since a label is never re-parsed; whether that reaches the cross-module case (smucclaw/l4-ide#968) is untested.
  Guarded by `VisualiseExpansionOptInSpec.hs` (the fixture above, with and without expansions; it failed with the stamping reverted) and by a `LadderModel` test on the captured shape.
  **Still open in `jl4-service`**, whose compiled module carries no registry: there a mixfix call still prints its head keyword only, so the service and the IDE give such a call different labels and `atomId`s, and two calls sharing a head keyword still share one.
  This is the clearest case of the printed key falling short of C1's term key, and under R3 it is a defect (smucclaw/l4-ide#1013).
  _Changed (smucclaw/l4-ide#1013):_ the `atomId` half is closed everywhere, the service included, since the term key names each operator by its own definition (`LadderTermKeySpec`); the service's LABELS still print the head keyword only.
- **The printed label is not C1's term key.**
  R3 requires the ladder's `atomId` to move onto C1's key (smucclaw/l4-ide#1013); the alignment point is #556 (UNKNOWN-EVALUATION step 3, stacked on #554, #553 and #541), which keys atoms by evaluated term in `jl4-core`; steps 4 to 7 of that spec are parked (MOTHBALL, #538).
  _Changed (smucclaw/l4-ide#1013):_ done for the ladder (§10.1), without waiting for #556, whose `Term` compares names by `Unique` and so cannot be the stable key as it stands.
  Owed when #556 lands: a test that the ladder's key and #556's `Term` agree where both are defined, which is only partly (an evaluator term exists only for what evaluation reached), and the name function shared between them, so the two cannot drift.
- **`hasDefForInlining` still compares against `cfg.moduleUri`** (`Ladder.hs:338`), the URI derived from the document id a caller passes, which is the pitfall §9.6 names; the `App []` case beside it already uses the typechecker's own URI (`Ladder.hs:584-588`).
  A caller that passes a synthetic document id would get no `canInline` and no expansions.
  No caller that turns expansions on does that today; not fixed here.
- **Panels in top-to-bottom orientation are not designed.**
  Their stubs follow the inner port and avoid the name band, and the series zig-zag predates this (`layout.ts` `measurePanel`); FLIP does not animate a panel's own rectangle (`ec7cae39e`'s message).
- **Cost with the flag on** is about three times a plain render (§10.5), which is why it is opt-in.
  A client that turns it on for a large module pays that on every auto-refresh too, since auto-refresh keeps the choice.
- **The IDE does not draw panels.**
  Its `LadderModel` keys answers by `Unique`, and a click now binds the Unique of every node sharing the clicked node's atomId, which is safe only because the LSP's labels now tell shared-head mixfix calls apart (the first bullet) (`#uniquesOfProposition`, `ts-shared/l4-ladder-visualizer/src/lib/model/ladder-model.ts`), the rule `spreadValue` applies in the playground.
  Unique alone was wrong even without expansions: on this branch's jl4-lsp, `may lend jointly` in `joint-loan.l4` draws its two `` `is creditworthy` OF a `` leaves with Uniques 157 and 166 and one atomId (measured 2026-10-06), because a compound leaf's unique is per occurrence (§9.6), so answering one left the other unknown.
  The sidebar's `setValueForUnique` still binds one Unique, so it still leaves such a twin unanswered.
- **`ts-apps/charge-generator`** substitutes call arguments itself and keys by rule name, so two calls of one rule with different arguments collapse; it could consume `expansion` instead.
  Not in scope here.

### 10.7 Named and polymorphic calls (2026-10-11, smucclaw/l4-ide#1033)

_Built on branch `mengwong/ladder-dustpan`; not merged when this was written._

smucclaw/l4-ide#1033 named three places where the ladder said less than R3's key does, measured after #598.
This section closes the first two.
The third, `p's adult` against `adult p`, was a ruling, not a defect; Meng ruled it on 2026-10-11 (fold them), and it is built on its own branch, `mengwong/ladder-record-accessor`, which records the ruling as R3b in §10.1 (not merged when this was written).

**A call with named arguments opened no expansion.**
`` `big` n `` opened into its panel and `` `big` WITH k IS n `` drew as one closed leaf, although R3 already keyed the two call boxes alike: the ladder matched only `App`, and so did every unfolding pass in `L4.Transform`.
`Transform.positionalCall` now reads a named call as the positional call it stands for when the checker's order says its arguments supply parameters `0 .. n-1`, each once, and every pass goes through it: `unfoldOnce`, `unfoldableCallSites`, `unfoldableDecide`, and `L4.Viz.AtomKey.positional`, so the key and the expansion agree by construction.
`callees` counts the head of every named call.
Three things follow beyond the panel.

- `l4 verify` reads a named call through, as §9.1 now says (`verify-unfold-named-calls.l4`).
- A `WHERE` helper that only a named call refers to is unfolded; `inlineLocalBindings` used to drop it, leaving the call pointing at nothing.
- A rule that calls itself, or another rule that calls it, through a named call is now seen as recursive and left opaque, like positional recursion. Base missed the edge and unfolded such a rule one level, which happened to be sound, so a few findings base made by accident are gone: with `` `r` n IF n > 5 AND (n < 3 OR (`r` WITH n IS n - 1)) ``, base found `` `r` n AND NOT n > 5 `` unsatisfiable, and the positional twin never was.

A named call is drawn as that call, its label and argument boxes in the order written, by both ladders; for an all-BOOLEAN one that is a call box over its arguments, with or without expansions, so the IDE's default lens shows the change too.
The panel title joins its arguments with commas (`callLabel`).
`positionalCall` refuses a named call the checker rejected and recovered from, since the IDE draws modules with type errors: an argument name it could not resolve is `OutOfScope`, and a named call to a rule of no parameters has no arguments.
A named call that supplies a section `GIVEN` (a negative order entry) stays opaque, since substituting for the parameters alone would not be the call.

**A polymorphic callee's `IF` was one opaque leaf inside its expansion.**
In `` `whichever applies` cond x y MEANS IF cond THEN x ELSE y `` under `GIVEN a IS A TYPE`, the `IF` carries type `a` in its annotation (rewriting that annotation is what makes it draw, as the gap-2 tests measure), substituting BOOLEAN arguments left it as it was, and the guarded-chain case draws an `IF` as structure only when it is BOOLEAN.
`instantiateTypes` (`LSP.L4.Viz.Ladder`) reads what each type variable stands for off the call, matching the body's type against the call's and each parameter's type, as annotated where the body uses it, against its argument's, and puts that in for every type in the body: annotations through the checker's final substitution, types written in the syntax as written.
The expand gesture (`l4/inlineExprs`) instantiates the same way.

**Adversarial review** (four lanes, each with probe binaries built from base and from the branch) found five defects in the first build, all fixed with a test each: the expand gesture did not instantiate, so it drew the `IF` the panel had opened as one box; an untyped lambda's parameter type was resolved in the callee's copy only, which keyed it apart from the caller's identical lambda; jl4-core's copy of the ladder still drew a named all-BOOLEAN call as one leaf; panel titles kept the printer's line breaks; and ill-typed named calls opened onto meanings the checker had refused.

**What it knowingly leaves**, by kind of failure:

- **Silent, the safe direction: a polymorphic helper defined as a `WHERE` local INSIDE a callee is not instantiated**, so its `IF` stays one leaf, as before; `inlineLocalBindings` puts it in without types to match against. A polymorphic local of the decision itself is instantiated.
- **Silent, the safe direction: `l4 verify` does not read a polymorphic rule through**, since it reads only rules whose body is BOOLEAN, so the IDE now opens a call that `verify` leaves opaque.
- **Slow, and loud only as a timeout: `l4 verify` on a chain of named calls whose meaning doubles at each level** builds the meaning up to the unfold budget (200,000 nodes) before `--max-nodes` refuses it. That was already so for positional calls; named ones now reach it (measured by the review, under load: a 12-level chain took 1.3 s on base and 27.4 s here for the whole file, and with `--decision top` 0.15 s against 8.0 s; its positional twin took 6.9 s on base). A size test before drawing the meaning would avoid it; not done here.
- **The node budget is all or nothing.** A polymorphic expansion now costs its full size, so a large one can push a decision over `expansionNodeBudget` and cost every call in it its expansion, as a large monomorphic one already could.
- **An all-BOOLEAN named call's argument ladders count against `l4 verify --max-nodes`**, as a positional call's already did.
- **Pre-existing, now reaching named calls:** a call box copied into a later row's negated prefix by `GuardedRows` gets a fresh id, and its evaluation maker is registered under the original's, so `l4/evalApp` on the copy finds none.
- **Not reachable today: if a named call may one day omit a defaulted parameter** (TYPICALLY-ONE-BEHAVIOUR-SPEC row W4), `positionalCall` cannot see the callee's arity, and the term key would read such a call as a shorter positional one. The unfolding passes compare arities and stay right.
