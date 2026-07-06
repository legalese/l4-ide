> **Status (audited 2026-07-03):** roadmap reviewed — 1 of 7 items now implemented (plus 1 partial); see per-item annotations.
>
> Since this list was written, **regulative rules** (syntax + semantics) shipped: `Regulative`/`Deonton`/`DMust`/`DMustNot` in `jl4-core/src/L4/Syntax.hs` and evaluation in `jl4-core/src/L4/EvaluateLazy/Machine.hs` + `ContractFrame.hs`. **Ellipsis linting** is partially scaffolded (`jl4-core/src/L4/Lint/AndOrDepth.hs`) but is not ellipsis-specific and not yet wired into diagnostics. Remaining items (three-caret repeat, bounded deontics + reasoner backends, web-app generation, set UNION/INTERSECT, WHEN-free CONSIDER branches) are still open. Note: some referenced spec paths use a stale `dev/specs/todo/` prefix — the asyndetic spec is now in `specs/done/`.

# Future Features

**Ellipsis linting**: LSP diagnostics to warn when ellipsis forms appear adjacent to mismatched operators (e.g., `...` near OR, `..` near AND). See [spec](../done/ASYNDETIC-DISJUNCTION-SPEC.md).

Three carets together will mean "repeat everything above to the end of the line".

Syntax and semantics for regulative rules. — ✅ DONE (Syntax.hs:228 `Regulative`/`Deonton`; EvaluateLazy/Machine.hs:500 + ContractFrame.hs:50)

Syntax and semantics for property assertions and bounded deontics. Transpilation to verification reasoner backends: UPPAAL, NuSMV, SPIN, Maude, Isabelle/HOL, Lean. See [BOUNDED-DEONTICS-SPEC](../todo/BOUNDED-DEONTICS-SPEC.md).

Transpilation to automatic web app generation.

Set-theoretic syntax for UNION and INTERSECT. Sometimes set-and means logical-or.

WHEN should not be needed at each line in a CONSIDER.

**Homoiconic introspection of imported constructs.** Motivated by Housing Act 1988 Sch. 2 Ground 1A(a) — "a lease granted for a term certain of more than 21 years and not terminable before the end of that term by notice" — which asks us to _introspect another L4 instrument_ rather than evaluate one (the L4 sketch: [`housing-act-ground-1A.l4`](../../jl4/experiments/housing-act-ground-1A.l4)). When sketching Ground 1A I reached for three things that, on reflection, are **cleverly functional, not homoiconic**:

- _model-as-data_ — re-describe the salient features as a typed `Disposal` record (`termYears`, `terminable`) and read its fields. But that inspects a hand-authored re-description, not the construct itself.
- _behavioural_ — run the construct through `#TRACE` and watch whether a "terminate by notice" event reduces it. This is black-box property-over-trace (the letter-vs-spirit check), i.e. _execution_, not reflection.
- _schema_ — query the lowered MLIR Schema. That is reflection over a derived, lossy projection, not code-as-data.

None of these gives the Lisp property: the construct's _own syntax tree_ available, inside L4, as an ordinary L4 value you can pattern-match and `EVAL` back. Genuine homoiconic introspection (the **R10 "Rule Graph Introspection" stretch goal** of [HOMOICONICITY-SPEC](../todo/HOMOICONICITY-SPEC.md)) would need: a reified `Syntax` type mirroring the L4 AST; a `QUOTE` that yields an imported definition's _source_ tree (precisely the structure the MLIR lowering throws away); an `EVAL`/unquote inverse to close the loop; and binding hygiene, so "is _this_ lease terminable by notice" resolves `terminable` in the imported construct's own vocabulary, not the querying contract's. Caveat: L4's surface (mixfix, layout, inert prose) is _not_ a uniform s-expression, so even with QUOTE/EVAL this is Template-Haskell-style staged reflection over a reified AST — not Lisp-strict code≡data. Lisp gets introspection for free because its surface _is_ its data structure; L4 has to build the reification.

**Actor-indexed actions (typed deontic parties).** Today `DEONTIC Actor Action` takes the actor and action types _independently_, so `PARTY Tenant MUST \`order possession\`` type-checks even though only a Court orders possession and only a landlord seeks it. The wish: make the set of actions depend on the actor, so mis-pairings are a _static_ error. This need not mean full dependent types — there is a ladder, and empirically L4 already climbs the lower rungs:

- **Rung 1 — value-level invariant.** A `GIVEN p IS AN Actor, a IS AN Action GIVETH A BOOLEAN \`p may perform a\`` predicate plus a guard/`#ASSERT`. Works today, end to end (including through the deontic layer, since it is just a checked boolean). Auditable and _amendable as data_ — which, for law, is often the right register: "who may do what" is frequently the regulated content and changes with the statute, so it belongs in data, not in rigid types (cf. the State-as-Ledger / [homoiconicity](../todo/HOMOICONICITY-SPEC.md) theme: reserve _types_ for true invariants, push _contingent legal content_ into inspectable data). This is also just Hohfeld — a power or liberty is always _someone's_, but _whose_ is contingent.

- **Rung 1.5 — lexical actor-tagging (Polish-notation action names).** A quick hack that sits between the invariant and the type machinery: bake the actor _into the action's identity_, actor-first like Polish prefix notation — `\`Court orders possession\``, `\`Landlord seeks possession\``— instead of a bare`\`order possession\``. No type-level guarantee (the checker still admits `PARTY Tenant MUST \`Court orders possession\``), but it costs nothing, it is self-documenting, the mispairing becomes *visible* (and greppable) at every clause site, and — usefully — it makes rung 1's `\`p may perform a\``**derivable** rather than hand-maintained: the action already names the actor it belongs to, so "does`p`own`a`?" is a structural check on the tag, not a lookup table to keep in sync. The structured form keeps the tag a real constructor instead of a string: `DECLARE Action IS ONE OF CourtDoes HAS a IS A CourtAction; LandlordDoes HAS a IS A LandlordAction`, where the `CourtDoes`/`LandlordDoes` head *is* the Polish prefix and each carries its own per-actor action enum. This is exactly the party-tagged *message label* of a session calculus / labelled-transition system (`Court ▹ orderPossession`), which is the right lineage for multi-party regulative protocols — and it composes with rung 1 (tag-derived invariant) without touching the type system. Trade-off: combinatorial enum growth and a convention a human or a lint must uphold, since nothing _stops_ a wrong tag.

- **Rung 2a — phantom indices at predicate boundaries (works today, no language change).** Give `Action` a phantom type parameter and pin it with smart constructors:

  ```l4
  DECLARE Court    IS ONE OF TheCourt
  DECLARE Landlord IS ONE OF TheLandlord
  DECLARE Action a HAS `action name` IS A STRING          -- phantom `a` = the owning actor

  GIVETH AN Action Court
  `order possession` MEANS Action WITH `action name` IS "order possession"
  GIVETH AN Action Landlord
  `seek possession`  MEANS Action WITH `action name` IS "seek possession"

  GIVEN x IS AN Action Court GIVETH A BOOLEAN
  `court performs` x MEANS TRUE

  #EVAL `court performs` `order possession`   -- ✓ checks
  #EVAL `court performs` `seek possession`     -- ✗ check-time error:
  --   "expected Action OF Court, but is here of type Action OF Landlord"
  ```

  Full parametric ADTs (`DECLARE Tree a IS ONE OF …`, `DECLARE Foo OF a, b`, `GIVEN a IS A TYPE`, `FOR ALL a AND b`) are all in the language, so this is available now and gives author-time enforcement with a legible error — for the _constitutive_ helpers. (The phantom is a constructor-boundary discipline, not airtight: nothing stops someone writing a fresh smart constructor that mislabels the index. True GADTs — constructors that _carry_ the index and refine it under pattern-match — would close that gap, but L4's `IS ONE OF` has no per-constructor result-type syntax today.)

- **Rung 2b — phantom/GADT indices _through_ the deontic layer.** This is where it currently stops: the regulative type-check of the `MUST`/`MAY` action against the contract's `Action` parameter is **shallow** — it compares the head type constructor but ignores its type arguments. So `DEONTIC Party (Action Court)` accepts a `seek possession` of type `Action Landlord` without complaint, even though the same mismatch at a plain function boundary is rejected by full unification. (A _non-parametric_ mismatch — `DEONTIC Party ActionA` with an action of unrelated enum `ActionB` — _is_ caught, confirming the check exists but is head-only.) Making it deep enough for indices to bite is a **bounded** type-checker fix, not dependent types — promoted to its own branch, `mengwong/fix-deontic-action-type-check` (see its `BRANCH.md` for the writeup, repros, and fix).

- **Rung 2c — per-party indices in one multi-party contract.** The real lift, and the thing that vindicates "dependent types won't be a walk in the park": the _point_ of actor-indexed actions is the multi-party clause — _Landlord MAY seek possession; Court MUST order possession_ — two parties and two differently-indexed actions in **one** `DEONTIC`. A single `Action` parameter can hold only one index; pin it to `Action Court` and the landlord's `seek` won't fit, widen it to a sum over both and the index is erased again. Threading a _per-party_ index needs either singletons (to bridge the `PARTY Court` _value_ to the `Court` type-index) or genuine dependency. Only this rung truly needs the heavy machinery; everything below it is reachable now or with a small, localized change.

---

## Recently Implemented

The following features have been implemented and moved from this list:

- **Asyndetic conjunction (`...`)**: Implicit AND using three-dot ellipsis syntax. See [Basic Syntax](20-basic-syntax.md#asyndetic-conjunction-).
- **Asyndetic disjunction (`..`)**: Implicit OR using two-dot ellipsis syntax. See [Basic Syntax](20-basic-syntax.md#asyndetic-disjunction-).
- **Inert elements**: String literals in boolean context as grammatical scaffolding. See [Boolean Logic](10-boolean-logic.md#inert-elements-grammatical-scaffolding).
