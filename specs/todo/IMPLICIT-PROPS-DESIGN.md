# Design Handoff: Implicit Environment (`props`) for L4

**Status:** Design exploration / pre-implementation
**Audience:** A Claude Code agent (or human contributor) who will turn this into a formal specification and, eventually, an implementation plan.
**Timing note:** L4 has effectively zero production users in the wild today. This is the moment to make breaking changes to the core calling convention. The bias should be toward getting the model _right_ now rather than toward backward compatibility.

---

## 0. How to read this document

This is a record of a design conversation, reorganized for a downstream agent. It is deliberately long and motivation-heavy. The intent is that you (the next agent) should be able to:

1. Understand _why_ this feature is being contemplated, not just what it is.
2. Reconstruct the reasoning from first principles so you can defend or revise individual decisions.
3. Identify the open questions that still need resolution before a real spec is frozen.

Where syntax is shown for _existing_ L4, it follows the current language (`GIVEN` / `GIVETH` / `MEANS`, `DECIDE ... IF`, `'s` field access, `§` sectioning, `WHERE` blocks). Where syntax is shown for the _proposed_ feature (notably `TAKING`), it is clearly marked as a proposal and is open to bikeshedding.

---

## 1. The problem

Consider a deep call stack. A function near the bottom needs a value that originates in the environment at the very top — a top-level entry point receives the value and must faithfully thread it down through a long chain of intermediate function applications that don't themselves care about it, purely so it arrives where it is finally consumed.

This pattern has names across the industry:

- **Parameter threading** (the neutral description of the act).
- **Parameter drilling** / **prop drilling** (the pejorative; "prop drilling" is the React-specific term for passing props down through intermediate components that don't use them).

It is at minimum tedious, and at scale it becomes genuinely intractable. The intermediate signatures get polluted with parameters that are only passing through.

### Why this matters specifically for L4

A toy demo with two or three positional parameters threaded down is fine. But L4 is meant to encode rule sets that may contain **thousands of rules**, depending collectively on **dozens of contextual values** (jurisdiction, effective date, party attributes, applicable schedule, and so on). At that scale:

- Manual positional threading is unmaintainable — you cannot pass tens of positional arguments down through every intermediate rule.
- The natural escape hatch developers reach for is "just pass a dictionary of context" — which is exactly React props, but _untyped_. At that point you've abandoned the explicit-in-the-signature ideal and gained none of the formal clarity, while inheriting all the opacity.

So the question is: **can L4 provide a first-class, properly typed, auditable mechanism for implicit environment passing — so developers never have to reinvent props badly by hand?**

---

## 2. The core tension (motivation)

### 2.1 Chesterton's Fence: why purity was the original hill

The original appeal of functional programming is **referential transparency** and **purity**: a function declares, in its type signature, _exactly_ the information it needs, and produces its result from that and nothing more. In the simple case the signature is a handful of simple values, and a first-time reader of the codebase can see the entire dependency surface at a glance.

We must not knock down this fence carelessly. It is the thing that makes formal verification and clear decision traces possible in the first place.

### 2.2 But purity alone doesn't scale ergonomically

Very quickly in the history of FP it became evident that you _do_ need to pass an environment / context / reader. Haskell's `Reader` monad exists precisely for this. The essential purity of the system remains intact — `Reader` is pure — but **ergonomically** something is lost: a developer reading the code sees a value being consumed and has to ask "where did this come from? who set it? what was its origin?" "I know it arrives via the reader environment" is true but unsatisfying. It begins to feel mysterious and magical.

So the tension is:

> **Explicit signatures** are transparent but, at scale, unmaintainable.
> **Implicit environments** are ergonomic but opaque about provenance.

L4 needs the ergonomics of the second without surrendering the auditability of the first — because explainability _is the product_. If a lawyer, regulator, or auditor reads a decision trace and sees a value used deep in a computation, they must be able to follow its provenance. Silent implicit context breaks exactly the property L4 sells.

### 2.3 Design stance: mechanism, not policy

We do **not** want to drag L4 into the muck of imperative environments. React in practice needs hooks, `useEffect`, and so on, drifting from the purity of its Elm-style origins; Haskell has `unsafePerformIO`. These compromises are made for good reasons.

The stance here is **mechanism, not policy**: if developers are going to need to bend the rules anyway, it is better that they get the rope from _us_, in a principled and visible form, than that they hack something together that is uglier and less transparent. `unsafePerformIO` is the model to emulate in spirit: the escape hatch is _marked and visible_ at the point of use, so a reader knows exactly where the contract is being stretched.

---

## 3. Prior art and language comparisons

This section is for the downstream agent to mine; each comparison carries a lesson.

| Source                                                 | What it does                                                                                                                                          | Lesson for L4                                                                                                                                                           |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Elm (Model–Update–View)**                            | Pure functions transform state; the architecture React later popularized. The conceptual origin of "purely functional transformation of input state." | The pure ideal is the baseline to preserve.                                                                                                                             |
| **React props**                                        | Values passed down a component tree.                                                                                                                  | The ergonomic target — but untyped props are the failure mode.                                                                                                          |
| **React + TypeScript**                                 | Props become structurally typed; the mechanism stays implicit forwarding, but the _contract_ (shape and types) is explicit and checkable.             | This is the sweet spot to aim for: implicit mechanism, explicit checkable contract.                                                                                     |
| **Reader monad**                                       | Pure threading of an environment; `local` rebinds the environment for a subtree.                                                                      | Gives us both the implicit-pass semantics _and_ the hypothetical-evaluation primitive (see §4.4).                                                                       |
| **`unsafePerformIO`**                                  | A visible, marked breach of purity.                                                                                                                   | The model for "principled rope": escape hatches must be visible.                                                                                                        |
| **Python closures / nested defs**                      | Inner functions capture enclosing scope, bypassing explicit threading.                                                                                | Ergonomic locally, but opaque: a reader must trace lexical scopes to discover captured dependencies. We want closure-like convenience _with_ Reader-monad transparency. |
| **Novice "everything is global"**                      | If you need it, grab it; if you must set it, write it; it all floats in one symbol table.                                                             | Seductively simple — and the thing we are, in a disciplined way, partly trying to recover. But unscoped globals don't stay tractable.                                   |
| **Prolog at scale**                                    | Arguably suffers the growing-global problem as programs grow.                                                                                         | Cautionary: implicit shared context must remain _scoped and tracked_, not a free-for-all.                                                                               |
| **OO-in-Haskell (narrowing/widening of record types)** | There is published work on object-oriented Haskell with principled type narrowing and widening.                                                       | A candidate formal basis for how `props` types may grow down the call stack (see §5).                                                                                   |
| **L4's existing `WHERE` blocks**                       | Haskell-style; the `WHERE` block has access to the function's environment, so helpers defined there are effectively closures.                         | This is the closest thing L4 has _today_ to implicit context. It is a starting point but not the destination.                                                           |

---

## 4. The proposed design

### 4.1 Every function carries an implicit `props` environment

Rather than an opt-in annotation (a function-annotation solution family feels like a code smell — necessary in languages like Python only because they didn't think of it early enough; we have the opportunity to think of it early), **make it universal by default**: every function implicitly receives a `props` environment — a typed set of properties — in addition to its explicit `GIVEN` parameters.

This is, in effect, imposing an invisible Reader monad over the whole language. But `props` is subject to the _same discipline as everything else in the language_ — it is typed, tracked, and inferable. It is not a mutable imperative bag, and it is not unscoped globals. Think of it as "mini-globals with a scope discipline."

### 4.2 Section syntax establishes the scope hierarchy

L4 already has section syntax (`§`, `§§`, `§§§`, …) used for document structure, analogous to `H1`/`H2`/`H3`. The proposal is to make this hierarchy _meaningful_ for `props` scope:

- `props` established at a section level is visible to functions defined under that section and its subsections.
- The section structure therefore **self-documents the scope hierarchy** — the same mechanism that organizes the document organizes the environment.

This is the answer to the closure-opacity problem: with closures you must trace lexical nesting by hand; here the section headings _are_ the visible scope boundaries.

### 4.3 Discover purity; don't annotate it

> **WITHDRAWN 2026-09-05 — see R14 (§11.18).** Nothing below was ever built, and the badge it
> proposes would be uninformative: 95 of the 745 `.l4` files under `jl4/` and `jl4-core/` carry a
> module-level `ASSUME` at all, so "very pure" would be true of roughly seven files in eight.
> The read-set that §4.3 wanted as its mechanism is separately real and shipped (PR #328); what is
> withdrawn is the classification painted on top of it. Retained unedited below because §8 Q8 and
> §9 cite it.

Because `props` is available everywhere by default, the interesting analysis is the inverse: **statically determine which functions actually use it.**

- Analyze each function and the **transitive closure of its callees** for any reference to a `props` component.
- If an entire subtree never touches the environment, mark it **"very pure"** — it can be reasoned about more strongly for formal verification, memoized aggressively, etc.
- Crucially, this is _purity discovered, not declared_. We are not hiding purity behind a universal `props`; we are revealing it precisely.

This is a strong explainability win: a decision trace can distinguish "this subtree is pure logic" from "these calculations are environment-dependent." Auditors see the boundary immediately, and verification tooling can apply stronger reasoning to the pure regions.

### 4.4 `local`-style hypothetical evaluation

The Reader monad's `local` gives exactly the primitive needed for **ceteris paribus / hypothetical evaluation**: rebind one component of the environment for a single subtree of computation, evaluate, then unwind — without imperative side effects.

For a decision service this is powerful: you can show alternate decision paths under different contextual assumptions ("what if jurisdiction were X instead of Y?") without manually threading modified parameters through the whole call stack, and without leaving the pure world.

The default ergonomic case is the opposite of restriction: a caller should be able to say, in effect, "**everything I know, I pass on** — I keep no secrets from the callee." `local` is then the disciplined exception used when you deliberately _do_ want to vary one assumption.

### 4.5 Provenance in traces

For every rule, the trace can surface the `props` it consumed and the provenance chain: "this rule applied with `jurisdiction` = X, established at section 3.2" and, with computed fields (§5.3), "`eligibility` was computed from `age` and `jurisdiction`." The implicit becomes explicit _in the output_ without cluttering the _source_.

---

## 5. Type-system design

### 5.1 Structural subtyping, growing down the stack

Real-world props grow at the developer's whim — fields get added as needed. We need a _principled_ version of this. The natural shape:

- **Shallow in the caller, rich deeper down.** The entry point's `props` is relatively small; as you descend the call stack, `props` accumulates more fields.
- A function that requires fields `{X, Y, Z}` can be called from a context that supplies _at least_ `{X, Y, Z}`. Narrower-required is satisfied by wider-available — i.e. a structural subtyping relation, in the TypeScript/duck-typing spirit.
- The published **narrowing/widening work on OO-in-Haskell** is a candidate formal grounding for the variance rules here. Get the variance direction right (what a callee _requires_ vs. what a caller _provides_) and the discipline holds across a large call graph.

### 5.2 Inference from usage (no manual annotation needed)

L4's compiler already infers structural shape from usage. We discussed how type inference against first-class values extends naturally to inference against dictionary values: if a rule states that `bob's age` must be greater than 21, the compiler already infers that `bob` belongs to a class carrying an `age` property of numeric type.

Extend the same inference to `props`: a reference to `props's jurisdiction` (or whatever the access syntax settles on) lets the compiler infer that `props` must carry a `jurisdiction` field of the appropriate type. Across the call graph the compiler builds the **minimal structural `props` type required at each level**, and checks that each call site supplies it (by widening, or by explicit binding at that site).

The intent is that **the developer never has to write the `props` requirements by hand** — the compiler infers them. Annotation is a smell we are explicitly trying to avoid.

### 5.3 Computed fields compose with `props`

> **DISCHARGED 2026-09-05 — see R13 (§11.17).** This section turns out to describe the tree
> rather than propose anything: a computed field reading a section binder type-checks, exports,
> and evaluates today (probe measured 2026-09-05, answer 109), because
> `jl4-core/src/L4/TypeCheck.hs:195-199` orders the two desugars so they do not interfere and
> `jl4-core/src/L4/Export.hs:353-356` walks a computed field's selector `DECIDE` like any other
> callee. Nothing is owed on it. Read the present tense below as reporting, not promising.

L4 already supports **computed fields** — properties defined entirely in terms of other attributes of the object (methods-as-fields). These compose cleanly with `props`: a derived property like `eligibility` can be computed from `age` and `jurisdiction` without explicit drilling, and the compiler tracks the dependency automatically. Whether a given field is a plain stored value or a computed one is "further magic" the inference layer resolves; the consuming rule shouldn't have to care.

---

## 6. Syntax & IDE proposal: `TAKING` (open to bikeshedding)

Decision functions today have an explicit `GIVEN` for parameter input. The proposal is a complementary clause — provisionally **`TAKING`** — that shows which values are drawn implicitly from the environment.

Illustrative (proposed, not final) shape:

```l4
GIVEN  applicant IS AN Applicant          -- explicit parameters, as today
TAKING jurisdiction FROM props            -- implicitly drawn from environment
       effectiveDate FROM props
GIVETH A BOOLEAN
DECIDE `applicant is eligible` IF
    ...
```

Key properties of the `TAKING` clause:

- **Compiler-inferred, not hand-written.** The developer does not have to author the `TAKING` list; the compiler derives it from usage (§5.2).
- **IDE-displayed.** The IDE shows the inferred `TAKING` clause as a visual aid, so a reader is never left wondering where `jurisdiction` came from. This mirrors how React + TypeScript surfaces the prop contract while leaving the forwarding implicit.
- **A clean visual split** between _what is handed in_ (`GIVEN`) and _what is drawn from context_ (`TAKING`).
- **Machine-readable dependency declaration** for verification, and a natural thing to print in a decision trace.

Net effect: **zero ceremony for the author, full transparency for the reader.** Optional to write, always known to the compiler, always displayable.

> Bikeshedding notes for the next agent: confirm the keyword (`TAKING` vs. `USING` vs. `FROM CONTEXT` …); decide the field-access syntax for `props` (reuse `'s`? a dedicated form?); decide whether `FROM props` is literal or whether `props` is implicit and only the field names are listed.

---

## 7. Implementation strategy (suggested ordering)

1. **Core `props` passing + inference.** Thread an implicit, typed environment through the calling convention; infer per-function structural requirements from usage. This is the load-bearing change.
2. **Section-scoped establishment of `props`.** Wire the `§`/`§§` hierarchy to environment scope.
3. **Purity discovery.** Transitive-closure analysis to mark "very pure" subtrees; expose the classification to tooling.
4. **`TAKING` surfacing.** Compiler emits the inferred clause; IDE renders it. (Largely presentation over the inference from step 1.)
5. **Computed fields over `props`.** Ensure derived fields compose and that provenance is tracked.
6. **`local`-style hypothetical evaluation.** The rebind-for-a-subtree primitive.
7. **Trace/provenance integration & formal-verification angle.** Surface `props` provenance in traces; feed dependency info to the verification backends.

Minimize the surface of the breaking change: existing explicit `GIVEN` threading should continue to typecheck and run. The new path is additive in authoring terms even though it changes the underlying calling convention.

---

## 8. Open questions for the spec

1. **Structural subtyping formalism.** Exactly which variance rules govern `props` growth down the stack? Adopt/adapt the OO-Haskell narrowing/widening treatment, or define our own? What are the soundness obligations?
2. **`props` access syntax.** Reuse `'s` field access, or introduce a distinct form to keep "from the environment" visually distinct from "from an explicit argument"?
3. **Keyword choice and grammar for `TAKING`.** (See §6 bikeshedding.)
4. **Establishing/extending `props`.** What is the authoring syntax for _adding_ to `props` at a section boundary or a call site? How explicit must that act be? (Establishment probably _should_ be visible even if consumption is inferred.)
5. **Interaction with `WHERE` closures.** How does the new `props` model relate to the existing `WHERE`-block environment access? Subsume it, coexist, or reframe `WHERE` in terms of `props`?
6. **Regulative rules.** How does implicit `props` interact with `PARTY`/`MUST`/`HENCE`/`LEST` and with `#TRACE` temporal testing? Does the environment flow through state transitions, and how is it shown in `#TRACE` output?
7. **Teaching story.** How do we _teach_ `props`? The mental model ("everything the caller knows is passed on, unless you deliberately use `local`") needs a crisp, honest framing that doesn't read as "we brought back globals."
8. ~~**Purity classification surface.** How is "very pure" exposed — diagnostic, hover, badge in the visualizer, attribute in generated artifacts?~~ **WITHDRAWN 2026-09-05, see R14 (§11.18)** — it asks where to paint a classification that was never built and would not inform; §4.3, which it depends on, is withdrawn with it.
9. **Error messages.** When a function references a `props` field not available in scope, the diagnostic must stay intelligible across a large call graph. What does a good error look like?

---

## 9. One-paragraph summary for a hurried reader

L4 should give every function an implicit, statically-typed `props` environment — a principled, scoped replacement for the untyped context dictionaries developers otherwise hand-roll, and for the unmaintainable manual threading of dozens of parameters through thousands of rules. The `§` section hierarchy defines `props` scope; structural subtyping lets `props` start small at the entry point and grow richer deeper in the call stack; the compiler infers each function's `props` requirements from usage (no annotations), discovers which subtrees are "very pure" because they never touch the environment, and surfaces the inferred dependencies through a `TAKING` clause that the IDE displays and the decision trace records. The Reader monad's `local` supplies hypothetical "what-if" evaluation without leaving the pure world. The guiding principle is _mechanism, not policy_: give developers visible, auditable rope rather than forcing them to hack together something opaque — preserving the referential transparency and explainability that are L4's whole reason for being.

---

## 10. `ASSUME`: the unprincipled prior implementation of `props` (measured snapshot, 2026-08-04)

**Status of this section:** an observation appended after the design above was written, recording a
conversation between Meng and a Claude session working in `smucclaw/dmnmd`. Nothing here is a
ruling; it is a measurement of the tree plus the migration question the design above implies but
does not currently pose. Sections 0–9 do not mention `ASSUME` at all, and it is not among the nine
open questions in §8 — that omission is the reason this section exists.

All counts below are over `origin/unstable` at `c873bb5d`, measured with
`git grep -c '^\s*ASSUME' origin/unstable -- '*.l4'`. Multi-line `ASSUME` declarations would be
undercounted by that line-based grep; none of the conclusions turn on exact totals.

### 10.1 What `ASSUME` is

An `ASSUME`d name is visible to every function in the module without threading, has no definition,
and evaluates to `ValAssumed` ("I needed this value and it is an assumed term"). It has **no**
axiom or SMT role — nothing in a verify path consumes it — and in DMN export, `Lower.hs` feeds
both `ASSUME`s and `DECIDE`/`GIVEN` parameters into the same `freeTermTypes` map, where both
become `inputData`. Per Meng, it is historically an early construct whose job was to declare
unimplemented types and terms so the typechecker would accept a partial example; as the language
matured, function definitions became more concrete and the construct stayed behind.

There are two categories, not more (an earlier three-way split into types / predicates / scalars
turned out to be arity dressed up as semantics — `ASSUME x IS A BOOLEAN` and
`ASSUME f IS A FUNCTION FROM Order TO BOOLEAN` are the same construct, an uninterpreted symbol):

| category                               | count |
| -------------------------------------- | ----- |
| uninterpreted **type** (`… IS A TYPE`) | 101   |
| uninterpreted **term**, any arity      | ~547  |

### 10.2 `ASSUME` already is an implicit environment — with every property §4 asks for missing

| §4 wants                                | `ASSUME` gives                                      |
| --------------------------------------- | --------------------------------------------------- |
| a value you can supply                  | none — an assumed name cannot be bound from outside |
| `§`-scoped visibility                   | module-wide, flat                                   |
| provenance in the trace                 | nothing to trace                                    |
| `local` for hypothetical rebinding      | no rebinding; already bound, cannot be shadowed     |
| inferred structural requirements (§5.2) | untyped ambient reachability                        |

The "cannot be bound from outside" row has a measured cost: the dmnmd↔L4 differential harness
(`etc/dmn-differential/`, PR #216) has to **generate one driver file per test case**, rewriting
`ASSUME` declarations in place, purely because there is no way to pass a value in. Under `props`
the fact set is a first-class value. That is the difference between a model you can evaluate under
varying worlds and one you have to edit.

### 10.3 Where the uses live: scaffolding, mostly — but not entirely

697 `ASSUME` lines total:

| where                | lines | note                                           |
| -------------------- | ----- | ---------------------------------------------- |
| `jl4/experiments`    | 418   | 60% — but see the caveat below                 |
| `jl4/examples` (all) | 204   | of which `examples/ok` 97, `examples/legal` 53 |
| `doc/reference`      | 71    | documentation                                  |
| everything else      | 4     | `tests-cli` 2, `jl4-core/libraries` 2          |

Of the 101 type declarations, 88 are in `jl4/experiments`; 6 are in the legal corpus.

The **legal corpus** uses `ASSUME` in six files, 53 lines: `anti-social.l4` (14),
`british-citizen-act.l4` (7), `imaginary-alcohol-act.l4` (14, plus a `tests/` copy),
`promissory-note.l4` (2), `regcf/regcf.l4` (2). (An earlier statement of this measurement said
"two files, 16 lines"; that was wrong, and this table is the correction.)

**Caveat on "experiments = scaffolding":** the directory name tells you maturity, not intent.
`jl4/experiments/macma3.l4` is a genuine draft formalisation of the Mutual Assistance in Criminal
Matters Act — `ASSUME`-heavy early-stage _real_ modelling that would face the same migration
question if promoted. Some fraction of the 418 is that, not operator demos.

### 10.4 What this adds to the spec's open questions

1. **The migration story for ~547 term uses is unwritten**, and it is probably the largest single
   piece of work this design implies. For the _authored_ corpus it is small (53 lines, six files);
   for experiments and fixtures it is large and arguably shouldn't be paid at all (next item).
2. **Fixtures and experiments are a real constituency, and `props` is worse for them.** A
   two-line example demonstrating one operator should not need an environment to exist. Either
   `ASSUME` survives as an explicitly test-and-experiment construct (possibly under a name that
   says so), or the teaching story (§8 Q7) has to cover "how do I write a minimal example".
3. **Uninterpreted _types_ need their own spelling.** `props` carries terms; `ASSUME x IS A TYPE`
   introduces an uninterpreted sort. That is an opaque/abstract type declaration and wants its own
   keyword. Six uses in the legal corpus; small and separable.
4. **Failure-time semantics change.** Today an under-specified model runs and fails at the point
   of demand, naming the missing fact; under total `props` with inference (§5.2) the same defect
   is a compile-time error. Better — but "run it and see what it asks for" is a workflow drafters
   plausibly rely on, and the change deserves an explicit ruling rather than arriving as a side
   effect.
5. **§4.4 `local` and DMN lowering must be read against each other before either freezes.**
   `local` generalises `EVAL UNDER RULES EFFECTIVE AT` — rebind one environment component for a
   subtree, evaluate, unwind. That is precisely the construct the DMN exporter cannot lower: a DMN
   decision is a 0-ary variable holding one value per evaluation, so a DRG has no scoped
   rebinding. Today that costs 15 dropped decisions (the `D-RULEDATE-UNBOUND` class — ruled R12 in
   `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.12, which is where the count lives in this tree.
   `DMN-DIFFERENTIAL-CI-SPEC.md`, which discusses the same class, is **not in this tree**: it and
   `etc/dmn-differential/` exist only on PR #216's branch `mengwong/dmn-differential-ci-handoff`,
   an open handoff marked not for merge); if `local` becomes a general feature, **every use of it
   is unlowerable by the same argument**, and the unlowerable surface grows in proportion to how
   much authors reach for hypothetical evaluation. Not an argument against `props` — an argument
   that this spec and `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` should cite each other. (As of the
   2026-08-04 snapshot neither did; the reciprocal citation was added to that spec's §2 on
   2026-09-04.)

### 10.5 Correction: a partial deprecation ruling already exists, and it couples to DMN export

An earlier draft of this section said no spec for deprecating `ASSUME` exists. That is wrong in
one important particular: **`specs/todo/lexipedia-superset/CORPUS-TRACK.md` §1.3** already
declares house style — "GIVEN/record throughout — no `ASSUME`" — and elsewhere calls the
module-parameter style "deprecated" by name (its regcf annotations distinguish a deliberate
`ASSUME` bottom from "the deprecated module-parameter ASSUME style"). What does not exist is a
_language-level_ deprecation plan; §1.3 is house style for one corpus, enforced by convention.

The same section records the fact that makes this spec's fate and the DMN exporter's fate one
question. The `dmn-exporter-assume-shaped` finding: **the exporter models a module as global
scalars plus decisions — the `ASSUME` shape — and it is the GIVEN/record house style it handles
worst** (duplicate-named `inputData`, unevaluable `f(x)` invocations, no BKM, records erased to
`Any`). `regcf.l4`, the flagship corpus and the canonical GIVEN/record module, cannot be demoed
through DMN export without exporter work. So today the codebase is pulled two ways: house style
deprecates the one module shape the DMN exporter can lower.

`props` resolves that tension, and this is the concrete thing it buys for DMN lowering: **a
`props` environment is isomorphic to a DMN input namespace.** DMN's evaluation model is a flat
set of typed `inputData` plus decisions over them — a Reader, not a lambda calculus. A module
written against typed `props` lowers naturally: props fields → `inputData`, functions over props
→ decisions, the inferred per-function props requirement (§5.2) → exactly the DRG's information
requirements. The exporter stops reverse-engineering an environment out of parameter threading
and reads it off the type. (What `props` does **not** buy: §4.4 `local` remains unlowerable —
see 10.4 item 5.)

### 10.6 The 53 legal-corpus uses, case by case (measured 2026-08-04)

The 53 lines reduce to 39 unique declarations — `tests/imaginary-alcohol-act.l4` is a
byte-identical copy of `imaginary-alcohol-act.l4` (verified with `git diff`, exit 0). They fall
into four dispositions, none of which is "keep as-is forever":

**(a) Module-parameter scalars — 14 unique declarations (28 lines), `imaginary-alcohol-act.l4`
×2.** Fourteen 0-ary `IS BOOLEAN` facts (`the person is a body corporate`, …) consumed by 0-ary
`DECIDE`s. This is precisely the style CORPUS-TRACK §1.3 deprecates, and precisely the shape
that is DMN-ready today: each fact is an `inputData` column, each `DECIDE` a one-row decision
table. **Disposition: the flagship `props` migration candidate** — the file reads naturally as
"functions over an implicit fact environment", which is what it already is, untyped.

**(b) Uninterpreted sorts + predicates over them — 21 lines, `anti-social.l4` (14) and
`british-citizen-act.l4` (7).** `ASSUME Person IS A TYPE` plus `is authorised : Person →
BOOLEAN`, `mother of : Person → Person`, etc. The pain is already written into the source:
`anti-social.l4` carries a comment explaining its main function is deliberately **not**
`@export` because calling it hits assumed-term errors on every invocation — a model that cannot
be run. **Disposition: `DECLARE` records** — `Person`/`Receiver`/`Conduct`/`Effect` become
records whose Boolean fields replace the predicates, making the modules evaluable _and_
exportable; the instance data then arrives via `props` or `GIVEN`. `british-citizen-act.l4` is
half-migrated already: the same file's "Improved Readability Version" uses `DECLARE Place`.
(`mother of`/`father of` want optional self-referential fields — the one genuinely non-trivial
case in the corpus.)

**(c) Sentinel values — 2 lines, `promissory-note.l4`.** `ASSUME NaN IS A NUMBER` (the comment
says "JS coders rejoice :D") and `ASSUME NO_COLLATERAL IS A STRING`. Not environment, not
modelling — absent-value hacks. **Disposition: defined constants or an optional/`MAYBE` type.**
Trivial; nothing to do with `props`.

**(d) Deliberate typed bottoms (curated refusals) — 2 lines, `regcf.l4`.** Both carry
paragraph-length comments: an arm that reaches them stops evaluation with "…is an assumed
term", _naming the refusal_ — "no Regulation Crowdfunding figure exists before commencement",
"the COVID-19 temporary rules … are not modelled here". This is a **fifth role** for `ASSUME`
that neither the term/type taxonomy in 10.1 nor `props` covers: refusal-with-provenance. One of
the two already names its designed replacement (`TEMPORAL-RULE-VERSION-DESIGN.md` item 3's
generated "not in force" arm) and says "delete this when it lands". **Disposition: keep until a
first-class refusal construct exists** — a `REFUSE "…"`-style typed bottom would let `ASSUME`
drop this job too, and is worth a line in any props-era deprecation plan.

> **Discharged 2026-09-04 (R7); the corpus migration is NOT part of it.** The construct exists.
> `REFUSE "message"` is an expression at any type whose evaluation stops with the author's reason,
> uncatchable by any rule, and absent from every export schema. The prelude's `TBD` is a `REFUSE`.
> The paragraph above therefore describes what `ASSUME` was used for, and the fifth role now has a
> construct of its own — but **no legal-corpus site has moved to it yet.**
>
> The `regcf.l4` and `regcf-denovo.l4` migration was written, and was **dropped from this PR on
> 2026-09-05** on a CI measurement. `L4.Dmn.Lower` lowers `Refuse {} -> verbatim e`
> (`Dmn/Lower.hs:2285`), so a migrated `regcf` exports DMN carrying the L4 source text inside a
> FEEL literal, and KIE 8.44.0.Final does not merely mark it Blocking — it **fails to compile the
> file**: `ERROR [ERR_COMPILING_FEEL] … syntax error near '"no Regulation Crowdfunding figure
exists before commencement on 2016-05-16"'`, twice, `VERDICT … <<< FAILED` (job 101189031152 of
> run 33924199101). The DMN Engine Checks job runs both engines end to end over every
> DMN-declaring subject, so the migration cannot land before the designed DMN image does.
>
> **Therefore the whole refusal-role migration waits on §6 item 6**, not just the two
> `jl4/examples/dmn/` exhibits: `regcf.l4` ×2, `regcf-denovo.l4` ×1, the `dmn/` exhibits, and
> `daydate.l4`'s out-of-range `YMD` (which §2.8 reclassifies as invalid INPUT rather than a
> refusal, so it is not a refusal site at all). The designed image — omit the refusing row, report
> a non-Blocking `D-REFUSE`, add a `MayRefuse` safety kind — is specified in §11.9 and unbuilt.
>
> **What this change did NOT do, and why.** The same work order bundled the uninterpreted-**type**
> role above (10.4 item 3 / 10.6 (b)): rewrite every `ASSUME T IS A TYPE` as `DECLARE T`. That is
> **deferred, not done**, because the target syntax does not parse on this tree. Measured
> 2026-09-04 with this branch's binary:
>
> ```
> DECLARE Jurisdiction
>
> GIVEN j IS A Jurisdiction
>   | ^^^^^  unexpected GIVEN / expecting AKA, HAS, IS, OF, or space token
> ```
>
> A `DECLARE` with no `HAS`/`IS` body is not accepted, so the migration has no landing site until
> either empty `DECLARE` parses or the role gets a different spelling. Anything that claims
> otherwise — including a source that cites `ok/set-operators-nested.l4` or `ok/consider-simple.l4`
> as evidence that empty `DECLARE` "parses today" — is wrong: both of those are ordinary
> declarations with `HAS` or `IS` on the following line. Splitting the two halves of the item is
> therefore a departure from the bundled sequencing, taken on that measurement.

**Reading of the whole:** the corpus does not argue for keeping `ASSUME`; it argues for building
`props`. Categories (a) and (b) — 49 of 53 lines — are authors reaching for an implicit typed
environment that does not exist yet, and paying for it with modules that either cannot be
evaluated (b) or cannot be supplied values without editing source (a). Category (c) is unrelated
debt. Category (d) is the only principled survivor, and it wants its own construct, not
`ASSUME`.

### 10.7 Bottom line as of 2026-08-04

Deprecation from **authored models** is feasible, desirable, and already half-ruled (CORPUS-TRACK
§1.3 as house style). `props` subsumes the term role with strictly better properties, at a
corpus migration cost of ~49 lines across five files — and, per 10.5, it is also the missing
piece that lets the DMN exporter handle idiomatic L4 at all. What blocks a clean "remove the
keyword": the fixture/experiment constituency (10.4 item 2), the uninterpreted-type role (10.4
item 3), and the curated-refusal role (10.6 d) — all three separable, the third wanting a
dedicated `REFUSE` construct.

---

## 11. Red-teamed position (2026-09-03) — R0 ruled, R1–R12 proposed

The scoping question this design left open (§4.2, §8 Q2/Q4) and the `ASSUME` migration §10 raises
were red-teamed by four adversarial reviews on 2026-09-03 and a second, eleven-agent review on
2026-09-04. The resulting position is `specs/todo/PROPS-REDTEAM-2026-09-03.md`, which on 2026-09-04
was revised to carry only the current proposal; the earlier strata and the verbatim reports are in
that file's history at `d119c521`. In one line: **`ASSUME` is deprecated; its term role is a
section-level `GIVEN` that the compiler discharges into ordinary parameters of every definition
that transitively reads it; supply is the existing named-argument `WITH`.** §4.2's section-scoped
establishment is withdrawn there (visibility already ships; `§` placement is a tiebreak), and
§5.1's structural subtyping is found unnecessary. R0–R12 are all recorded below, each with the mark Meng gave it on 2026-09-04. The red team's
rulings are closed; what remains is implementation in the order of `PROPS-REDTEAM-2026-09-03.md` §6.

**Added 2026-09-05, from a second rulings sheet Meng marked that day.** Four further rulings sit
below and are **not** part of the 2026-09-04 red team: **R7 is amended** by §11.9.1 (the DMN image
of a refusal), **R7.1** is added by §11.9.2 (the pre-commencement gate), and **R13** and **R14**
are added by §11.17 and §11.18 (§5.3 discharged, §4.3 and §8 Q8 withdrawn), and §11.19 rules the
ORDER in which the cross-`IMPORT` hole is repaired — the refusal before the closure — while the
defect record itself lives at `OPEN-FINDINGS-2026-09-05.md` **OF-7**, because it spans `Export.hs`,
`Batch.hs` and `Print.hs` and needs an id that does not move when this section list grows. **Every one of the four authorises work that has not been done**;
each says so in its own status line and names what would make it true.

### 11.1 R0 — `ASSUME` is deprecated. RULED 2026-09-04.

**Ruling (Meng, 2026-09-04): `ASSUME` is deprecated.** Its three jobs go to three destinations:

| job                                | destination                                                                 | status                    |
| ---------------------------------- | --------------------------------------------------------------------------- | ------------------------- |
| suppliable term (the ~550 uses)    | a section-level `GIVEN` discharged by the compiler into ordinary parameters | mechanism pending (R1–R5) |
| uninterpreted type (`… IS A TYPE`) | a bodiless `DECLARE T`, an opaque nominal type (§11.1.1)                    | built 2026-09-05          |
| refusal / typed bottom             | `REFUSE "…"`, uncatchable, boundary-only, in no schema                      | spec pending (R7)         |

**What decided it.** Not the design argument but the defect list. Of the eight proposal-independent
bugs found by the 2026-09-03/04 red teams (`PROPS-REDTEAM-2026-09-03.md` §7), five are
consequences of `ASSUME` being an input with no binder, so that every consumer invented its own
binding path and they disagree: the export schema's one-body-deep collector, the service's LetIn
inlining, Catala's and Docassemble's private transitive walks, DMN's free-term map, `l4 batch`'s
positional mis-application, OpenFisca's absence of any handling, and two promotion paths in
`Export.hs`, one keyed on an out-of-scope error. Measured 2026-09-04: **35 Haskell files, 752
occurrences, 16 named entry points** that collect, bind, promote or lower it (jl4-core 618,
jl4-service 88, jl4-mlir 46). After discharge there is one binding path, application, and those
collapse into the read-set pass plus ordinary parameters.

**Cost committed to.** 664 `ASSUME` lines in 105 files (legal 54, ok 97, not-ok 20, experiments 418,
doc 71, libraries 2, tests-cli 2), of which 113 are type-role; most are scriptable
(`PROPS-REDTEAM-2026-09-03.md` §6 gives the per-role recipe).

#### 11.1.1 The type role: a bodiless `DECLARE T` is an opaque type. RULED 2026-09-05.

**Correction first.** The table row above, and `PROPS-REDTEAM-2026-09-03.md` §1 and §6, said an
empty `DECLARE T` "already parses" and cited `ok/set-operators-nested.l4:36` and
`ok/consider-simple.l4:3`. **That was false.** Both citations are ordinary declarations whose body
sits on the _next_ line (`DECLARE Team` / `HAS members IS A SET OF STRING`;
`DECLARE TwoNumbers` / `IS ONE OF …`). Probed 2026-09-05 on the `unstable` binary, a genuinely
bodiless `DECLARE T` was a parse error in every position:
`unexpected GIVEN|DECLARE|§|end of input, expecting AKA, HAS, IS, OF`. The row's status
"available today" was wrong, and the migration recipe built on it would not have run.

**Ruling (Meng, 2026-09-05), verbatim: "Bodiless DECLARE T should parse similar to Haskell
`data T` as opaque type."**

**What shipped.** A fourth `TypeDecl` constructor, `OpaqueDecl`, and a parser alternative tried
last in `typeDecl` that consumes no input. `inferTypeName` gives it the very same entity
`scanTyDeclAssume` gives `ASSUME T IS A TYPE` — a `KnownType` with no expansion and no
constructors — so the two spellings are interchangeable and a file migrates one line at a time.
Parameterised heads (`DECLARE T x`, with or without an explicit `GIVEN x IS A TYPE`) are in scope
and work, matching `ASSUME T x IS A TYPE` at `ok/signatures.l4:13`.

**The measurement that mattered.** Because the new alternative always succeeds, the risk was that
a malformed `DECLARE` would silently parse as opaque instead of reporting its error. An
eight-case differential against the pre-change binary (2026-09-05) found no such regression: the
only inputs whose verdict changed are the three that are the new feature (`DECLARE Foo` followed
by another declaration; `DECLARE Foo AKA Bar`; `GIVEN x IS A TYPE` + `DECLARE Box x`). `DECLARE
Foo IS` and a bare `DECLARE` still error identically, because the body parsers consume their
leading keyword before failing and megaparsec does not backtrack over it. Two inputs
(`DECLARE Foo IS ONE OF` and `DECLARE Foo` + bare `HAS`) were accepted by _both_ binaries: an
empty constructor list is pre-existing behaviour, not a consequence of this change.

**Correction to the paragraph above, measured on the rebased tree 2026-09-05.** That paragraph
also claimed "a typo'd body keyword still errors identically". **Too broad, and the eight cases
did not cover the one that matters.** A typo'd body keyword on an _indented continuation line_
(`DECLARE Foo` / `  HSA` / `    x IS A NUMBER`) does still error, and so does a truncated body
(`DECLARE Foo HAS x IS A`); but a typo on the _head line_ does not, because it is absorbed as a
type parameter. `DECLARE Foo IZ NUMBER` went from one error on the pre-change binary to zero:
`DECLARE Bag x` and `DECLARE Foo IZ NUMBER` are the same shape, so no rule at the declaration can
separate a parameterised opaque head from a misspelt `IS`. This is inherent to the ruling, not a
defect in the implementation of it. **The mistake is still caught, one step later and under a
different name**: arity is enforced at use sites, so `GIVEN a IS A Foo` reports "The arities of
the types do not match. I expected 2 arguments, but I found 0." The residual hole is a misspelt
declaration that nothing uses, which reports nothing. Pinned by the exhibit
`not-ok/tc/opaque-head-absorbs-typo.l4` and stated as a limit in `doc/reference/types/DECLARE.md`.
(A related probe, `DECLARE Foo HSA x IS A NUMBER`, is accepted by _both_ binaries — head
`Foo HSA x`, synonym body `IS A NUMBER` — so it is pre-existing, like the two inputs above.)

**What review changed.** The first draft of the corpus exhibit `ok/opaque-declare.l4` carried an
`#EVAL` over identifiers that were never declared, which would have failed the `ok/**` glob. It
was rebuilt around the real limit instead: an opaque type has no constructors, so no expression in
a module can produce one of its values. The exhibit now evaluates a rule that carries opaque
values through a record without inspecting them (`TRUE`/`FALSE`), and states in a comment that
values arrive from outside.

**Deferred, measured.** 16 of the 25 type-role uses in `jl4/examples` were migrated. Nine were
kept deliberately, because their purpose is to exercise the `ASSUME` spelling, which is deprecated
but not removed: `lsp/semantic-tokens/assume.l4` (2, the token fixture for the keyword),
`relational/assumed.l4` (3) and `relational/not-ok/assumed-signatures.l4` (1) and
`blawx/not-ok/arity-two.l4` (1), whose headers explain why they are written as `ASSUME`,
`ok/signatures.l4` (1, every declaration in the file is an `ASSUME` signature), and
`not-ok/tc/typically-on-type.l4` (1, which pins the error for `TYPICALLY` on a type `ASSUME`; the
opaque spelling has no `TYPICALLY` form, so there is no analogue to move it to). The 88 uses in
`jl4/experiments` are out of scope for the same reason the sweep leaves that tree alone.

**Sequencing.** (1) the transitive read-set pass, in progress on `fix/export-transitive-readset`,
which is both a bug fix and step one of discharge; (2) the mechanism rulings R1–R3 and R7;
(3) discharge; (4) `REFUSE` and the empty-`DECLARE` migration of the type role, so that no refusal
and no sort is ever suppliable; (5) a deprecation warning in `l4 check` with a code action that
rewrites a term `ASSUME` to the ruled spelling — the warning does not land before the code action
can; (6) corpus and docs migration, `doc/reference/types/ASSUME.md` carrying the notice and the
recipe (CLAUDE.md §6); (7) keyword removal, together with the dead `LocalAssume` grammar.

**What this does not decide.** Nothing of the red team's remains open; R1–R12 are ruled in
§11.2–§11.13 below. Still owed from the riders: the pre-commencement gate design and the
CORPUS-TRACK §8 amendment (§11.9). Consistent with §10.7 above and the handoff's §7 ("`ASSUME` is not simply
to be deleted"): the refusal and type roles get their own constructs _before_ the keyword goes.

### 11.2 R1 — A call site is entirely positional or entirely named. RULED 2026-09-04.

**Ruling (Meng, 2026-09-04, in conversation: "i'm minded to allow all positional or all by-name but
not allow an admixture of styles").** There is no mixed form `f x WITH y IS v`. The grammar is
unchanged; the one compiler change is that `supplyAppNamed` may omit a parameter that is flowed
from a visible section binder or has a `TYPICALLY` default, and a section `GIVEN` in the callee's
read-set is a suppliable name at a `WITH` site. Implicits are keyword-only: at a positional site
they flow or default. A `WITH` names only what it overrides; the rest keeps flowing.

**What decided it.** The mixed form was never live code: it is a parse error on every binary that
exists, and the corpus's roughly a thousand `WITH` sites are all-named because nothing else parses.
Per-site practice already mixes styles across sites (`is adult`: one `WITH` site, fourteen
positional). The red team's original R1, a new mixed grammar, is struck. Detail:
`PROPS-REDTEAM-2026-09-03.md` §2.4.

### 11.3 R2 — Resolution is lexical; a function `GIVEN` never flows to a callee. RULED 2026-09-04.

**Ruling (Meng, 2026-09-04, on the resulting rule set: "a good balance between referential
transparency and DWIM convenience").** A bare name resolves at the definition to a `WHERE`/`LET`
local, the function's own `GIVEN`, a field opened from one, or a section `GIVEN`, else it is a
check error; there is no caller chain in resolution. Only section binders and an explicit
`WITH`/`LET` supply a callee's requirement; a function's own `GIVEN` never does. A function
`GIVEN` that restates a visible section `GIVEN` is a **check error**, so a name has one binder per
root (§11.4). Per-call variation is written, `callee WITH person IS person's guardian`.

**What decided it.** The argument recorded at `PROPS-REDTEAM-2026-09-03.md` §2.3: a name
coincidence would become a binding; `R(f)` would stop being the callee's; one program would have two
readings; every tradition that had dynamic parameter binding gave it up (Common Lisp's `special`
declaration is exactly the section-`GIVEN`/function-`GIVEN` line). Measured cost zero: across 607
files there are 235 term-role `ASSUME` names and 2,311 function `GIVEN` names and no file where the
two sets overlap. Restatement as an error rather than a warning was part of the recommendation Meng
accepted; it is the one sub-point he did not separately voice.

### 11.4 R3 — Distinct binders per section; one binder per name per root. RULED 2026-09-04.

**Ruling (Meng, 2026-09-04: "I had intended our module scope mechanism to allow" a `foo` defined
in each of four sibling sections, apple in 1 and 2, banana in 3 and 4).** Visibility is as shipped:
nearest ancestor section, falling back to all candidates when no ancestor matches. Same-named
section binders in different sections are distinct binders, each read by its own section and its
descendants. One binder per name is enforced per root, not per module: a directive or export whose
read-set holds two binders of one name is a check error naming both by section, and the ways out
are hoist to the title heading, rename, or bridge at the call with `g WITH foo IS foo`. Nesting: a
heading's binder covers its subtree; a child re-declaring an ancestor's name shadows within the
child; a parent reading a name several children declare is ambiguous. Tier (world vs subject) is
classified by call-site variation, never by placement.

**What decided it.** The first draft's one-binder-per-module would have merged silently the
"for the purposes of sections 1 and 2 … sections 3 and 4" pattern when the two are same-typed
inputs. As definitions the pattern runs today on the FIX D branch exactly as intended, and with
`ASSUME` in each section it checks identically; the shipped binary gets it wrong only through the
defect FIX D repairs. Preconditions: FIX D and the §3.3.4 drift, both on
`fix/section-scoping-ambiguity`. Detail: `PROPS-REDTEAM-2026-09-03.md` §2.1, §2.2.

### 11.5 R8 — `TYPICALLY` has one behaviour, filled in once at the root. RULED 2026-09-04.

**Ruling (Meng, 2026-09-04: "Agree with these three rules, please add"; on a definition as a
default, "Yes please").** A defaulted `GIVEN`, section or function, may be omitted at a supply site
and the evaluator honours the default, filled in once per evaluation at the root. Three rules: a
function's own defaulted `GIVEN` may be omitted only at a named site; each binder has one
declaration and its default lives there; a default is a module-scope expression, may name another
binder or a definition (`beta TYPICALLY phi`), is evaluated lazily at the root, and a cycle
`b ∈ R*(default(b))` is a check error, the default's read-set joining the requirement of every root
that may use it. Surfaces: the trace records a defaulted binder as its own event with the
declaration line and value; the JSON schema lists a `TYPICALLY` parameter as optional, never in
`required`, with its default (as source text when it is an expression) and description.

**What decided it.** Three images today (schema required-and-defaulted, Catala `context`,
evaluator discards) and a reference page saying defaults do not change evaluation. Meng's own
note: this expands `TYPICALLY` from a literal annotation into a defaulted expression, a language
change in its own right; `doc/reference/types/TYPICALLY.md` says so when R8 lands. Detail:
`PROPS-REDTEAM-2026-09-03.md` §2.5.

### 11.6 R4 — The section binder is the indented `GIVEN` on the line after the heading. RULED 2026-09-04.

**Ruling (Meng, 2026-09-04: "next-line-after-section, indented, to be the convention; having a
GIVEN at the rhs of the section heading text just looks weird").** A `GIVEN` belongs to a section
iff its keyword sits at a column greater than the heading's `§`, on the line after the heading. The
heading-line form `§ ⟨name⟩ GIVEN …` falls under the same rule and parses, but is not taught as a
style: docs show only the indented form and the formatter emits it ("if the parser needs to do it
that way, fine, but let's not teach it as the primary style"). A column-1 `GIVEN` stays the next
declaration's signature. `WHEREAS` and `WHEREIN` are struck.

```l4
§ `1. Issuer eligibility — Rule 100(b)`
    GIVEN issuer IS AN IssuerProfile
```

**What decided it.** Readability, against the red team's preference for the heading-line form on
the ground that it has no indentation hazard. The hazard is mitigated instead: a column-1 `GIVEN`
immediately after a heading whose names the next head does not bind is a check error; the
formatter never moves a `GIVEN` across the column boundary; and diagnostics about an implicit name
the heading line it was declared on. Measured 2026-09-04: the rival adjacency rule would
reinterpret 160 legal-corpus sites; the indentation rule collides with none. ExactPrint preserves
what was written; `prettyLayout` emits the indented form; both have round-trip goldens. Detail: `PROPS-REDTEAM-2026-09-03.md` §2.1.

### 11.7 R5 — Field-opening is lexical only. RULED 2026-09-04 (marked accept).

The fields of a record-typed `GIVEN`, function or section, are in scope by bare name within the
function that declares or sees the binder, never in its callees. Rank, innermost first:
`WHERE`/`LET` locals; the function's own `GIVEN`; fields opened from it; section `GIVEN`s; fields
opened from those; selectors. A collision between two opened records sharing a field name is an
error at the read naming both records and at the declaration that opens the second; `r's f` is
always available. A bare opened field elaborates to `Proj (App r []) field` in a post-typecheck AST
every backend consumes. Only binders are suppliable at `WITH`. **Sequencing note:** the sample that
motivated opening (the alcohol act as one record) was re-cut as fourteen scalars under R10, so
opening's remaining value is bare field names inside a rule; it is implemented after discharge
lands, and opt-in `OPENED` stays the fallback if reviewers cannot see binding class. Detail:
`PROPS-REDTEAM-2026-09-03.md` §2.7.

### 11.8 R6 — The `MAYBE`/`EITHER` propagation sugar is withdrawn. RULED 2026-09-04 (marked accept).

Declined on measurement: seven of seven rating sets against; no use-site marker; the FEEL claim
false; strictness under call-by-need; 28 functions, none exported; the deleted line is the
encoder's visible allocation of the not-proved case. The taxonomy of non-answers stands. If
revisited: a use-site `?`, bind at the nearest enclosing failure-typed node, lambda its own
boundary, `JUST` explicit, elaborated to `CONSIDER` before any backend. Detail:
`PROPS-REDTEAM-2026-09-03.md` §2.8, §5 item 11.

### 11.9 R7 — `REFUSE` stays, specified. RULED 2026-09-04 (marked accept).

A throw at force, never a value; `#ASSERT REFUSED e` with an optional message and a three-valued
assertion outcome; house style one named definition per refusal with its `@ref`, readers
byte-identical, polymorphic ones declared `GIVEN a IS A TYPE`; `Ref(f)` reported per reason string
with the prelude's `TBD` excluded and warned separately; the per-backend image of
`PROPS-REDTEAM-2026-09-03.md` §2.8 (DMN omits the refusing row, non-Blocking `D-REFUSE`,
`MayRefuse` safety kind; Catala no definition; Docassemble a terminal screen; evaluator, CLI, batch
and service a `refused` kind); order-dependence under lazy `AND`/`OR` written down. The taxonomy
row is split: "the law does not apply / is not in force" is a value or gate that savings and
transitional provisions can reach; "the model does not cover this" is `REFUSE`.

**Consequence to carry, so two documents do not contradict.** The split reclassifies Reg CF's
pre-commencement case, which `specs/todo/lexipedia-superset/CORPUS-TRACK.md` §8 ruling R2 and
`regcf.l4:135-143` record as a curated refusal, and the temporal design's generated "not in force
on <day>" arm (`TEMPORAL-RULE-VERSION-DESIGN.md` item 3), which becomes a gate. Neither has a gate
design yet. Until one exists the commencement arm stays a `REFUSE`, and the PR that lands `REFUSE`
amends CORPUS-TRACK §8 in the same change.

#### 11.9.1 R7 AMENDED 2026-09-05 — the DMN image of a refusal is FEEL `null`, and it withdraws `DMN-SAFE`

**Ruling (Meng, 2026-09-05, mark `accept` on rulings-bench card `D1-dmn-refuse-image`).** The DMN
half of R7's per-backend image above — "DMN omits the refusing row, non-Blocking `D-REFUSE`,
`MayRefuse` safety kind" — is **superseded**. The image is now:

- `l4 export --to dmn` lowers a reachable `REFUSE` to FEEL **`null`**, and **omits nothing**;
- the reason string rides on the surviving `OTHERWISE` row's `<description>`, under a new
  `D-REFUSE` code;
- the export **withdraws `DMN-SAFE`**;
- severity is set by the existing strictness calibration — `Lossy` when only lazy positions
  consume the refusal, `Blocking` from any strict consumer;
- **`MayRefuse` is dropped.** A safety kind that does not withdraw `DMN-SAFE` certifies a decision
  total when we can see it is not, which is the thing this ruling exists to stop.

Every other backend in R7's list (Catala no definition, Docassemble a terminal screen; evaluator,
CLI, batch and service a `refused` kind) is unchanged.

**Status: ruled 2026-09-05; NOT BUILT.** What is in the tree today is neither the old image nor
this one: `L4.Dmn.Lower` lowers `Refuse {} -> verbatim e` (`jl4-core/src/L4/Dmn/Lower.hs:2285`),
writing L4 source text into a FEEL literal, and KIE 8.44.0.Final then fails to compile the whole
DMN file (`ERR_COMPILING_FEEL`, measured 2026-09-05 while repairing PR #334; recorded in §10.6 and
in `doc/reference/control-flow/REFUSE.md`). What would make this ruling true: the `Refuse` arm at
`Lower.hs:2285` emitting `null`; a `D-REFUSE` row in `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §7;
`analyzeSafety` withdrawing `DMN-SAFE` on a reachable refusal; and the three conditions below.

**The three conditions. The ruling is not shipped without them** — Meng accepted the
recommendation _as written_, and it was written as "C, conditional on three things landing with
it", because C on its own ships a green pipeline over a region no test evaluates:

1. **A pre-commencement engine-differential case that does _not_ supply the floor**, in each of
   `jl4/examples/dmn/regcf-corpus.cases.json`, `gst-rate.cases.json` and `ymd-dates.cases.json`,
   with both engines' answers recorded in `jl4/examples/dmn/expected/regcf-corpus.engine-baseline.txt`.
   **Corrected against the tree 2026-09-05:** the condition as originally worded ("a
   pre-commencement case in each of the three") is already met by two of them and would have been
   discharged without testing anything. `gst-rate.cases.json` has two pre-commencement cases (F, J
   — rule dates 1990-01-01 and 1994-03-31 against commencement 1994-04-01) and `ymd-dates.cases.json`
   has three (F, G, H), whose rule dates are 1900-01-01 and 1982-12-31 against commencement
   1983-01-01 — and **every one of
   them supplies the floor itself as `-1` and expects `-1` back**, so the engines see a supplied
   number and never a refusal. `regcf-corpus.cases.json` has none at all: all 22 cases carry a
   rule date of 2016-09-01 or later, against commencement 2016-05-16. The condition that bites is
   therefore the un-supplied one.
2. **`--fail-on=blocking` actually passed by the `p7-dmn` leg** of `etc/go/go.sh`. Measured
   2026-09-05: the flag exists (`jl4/app/L4/Cli/Export.hs:234`, `Docassemble.hs:107`) and occurs in
   **no** `.github/workflows/*` file and **no** file under `etc/go/`. Until it is passed, a
   `Blocking` `D-REFUSE` is a line of report text that fails nothing.
3. **The enum-typed COVID refusal covered by its own case.** `regcf.l4:486` declares the refusal at
   type `FinancialStatementRequirement`, a nullary `IS ONE OF` (`regcf.l4:471-474`), and it is
   reached from one arm, `regcf.l4:501`. `null`-against-an-enum is the concrete silent-wrong-answer
   path, and no option on the card was designed with it in view.

**What decided it.** Not the design argument; the measurement that §2.8's reasoning turns on.
§2.8 rejected `null` on the ground that "FEEL `null` is already spent on `NOTHING`, so
`REFUSE → null` would launder". The D1 review measured that omission and `null` are
**engine-identical under both hit policies**, which leaves that argument unable to choose between
them: under `UNIQUE` the `OTHERWISE` is a `defaultOutputEntry` (`jl4-core/src/L4/Dmn/Lower.hs:695`)
and under the dated-chain form it is a floor row with no default (`Lower.hs:1645-1655`), and in
both an absent answer and an explicit `null` reach a consumer the same way. _(The two code sites
were re-verified 2026-09-05; the engine-level equivalence is the D1 review's measurement and was
not re-run here — running it needs the KIE and Camunda images.)_ Once they are equivalent, `null`
is the cheaper half — one arm at `Lower.hs:2285`, against recomputing the `informationRequirement`
edges of the eight output entries that reach `regcf.l4:143` (`regcf.l4:154, :166, :175, :185,
:195, :205, :215, :409`) — and it is the only half that keeps the reason string in the artifact at
all, because omitting the row deletes the very `<rule>` whose `<description>` would carry it.

The finding that decides how confident anyone should be is condition 1's: the two-engine check
reports `1540/1540 decision(s) SUCCEEDED, 1540/1540 value(s) as expected` on both KIE 8.44.0.Final
and Camunda 8.7.6, over 22 cases, **none of which evaluates through a refusal**. That number is
not evidence about this ruling.

**The second per-backend image, which R7 did not name: the dmnmd/Markdown carrier.** It is a
separate lowering (`jl4-core/src/L4/Dmn/Markdown.hs`) with **20 goldens of its own** under
`jl4/examples/dmn/expected/` — 10 `.dmn.md` renderings and 10 `.md.fidelity.txt` reports, beside
the DMN backend's 11 `.dmn` and 11 `.fidelity.txt` (counted 2026-09-05) — and its cell
grammar is S-FEEL only: `mdOutput` refuses anything that is not S-FEEL, and the code already
records that a `null` catch-all is the reachable case (`Dmn/Markdown.hs:404-412`, the R8-d′ note).
So ruling C, applied unchanged, makes a refusing table emit `D-MD-CELLSYNTAX` (Blocking, dmnmd
only) rather than a `null` cell. **Whether that is the wanted dmnmd image is OPEN and is not
decided here** — Meng ruled the DMN image, not this one. Recording it so the implementing PR does
not discover it in a golden.

**What review changed.** The card's own recommendation was C _with conditions_, and the conditions
are the substance: read without them, C ships a green pipeline over an untested region, which is
what an earlier reading of the prior analysis would have done. The card's adversarial pass had
already corrected the prior analysis on one count — `regcf.l4` carries **two distinct refusals**,
one `NUMBER`-typed reached from eight output-entry sites and one
`FinancialStatementRequirement`-typed reached from one, not "one refusal" — and re-measurement on
2026-09-05 confirms both figures. The one thing this record changes against the card is condition
1's wording, which was already satisfied in two of the three files by cases that supply the floor,
and is restated above as "does not supply the floor". `daydate.l4:104` stays out of scope by R7's
own taxonomy — an out-of-range month is invalid input, the `EITHER` row, not a refusal.

**Corpus sites that cite the superseded image by name**, and migrate with the implementing PR:
`jl4/examples/dmn/gst-rate.l4:62-65`, `jl4/examples/dmn/ymd-dates.l4:83-86`,
`jl4/examples/legal/regcf/regcf.l4:135-143`. `jl4-core/libraries/daydate.l4:102-104` does not.

##### 11.9.1a AMENDED 2026-09-05 (later the same day) — where D1 and D6 overlap, **D1's image wins**

**The conflict.** §11.9.1 (card D1) rules that the exporter must **not** omit a refusing row — keep
it and answer FEEL `null`. §11.9.2 (card D6) accepted "the refusing row is omitted and the table
declares itself incomplete" as the DMN half to land first. The two overlap on exactly one
construct: **a dated interval table (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.3) whose floor arm
refuses.** Both cards were marked `accept` on 2026-09-05, 73 seconds apart, and the conflict was
not visible on either card.

**Ruling (Meng, 2026-09-05).** **D1's image wins on that construct.** The refusing row is **kept**
and answers `null`. D6's long-run option 4 — the gate as a property of the rule-version axis —
**stands unchanged**; what is withdrawn is only option 3 as its DMN half. Nothing in D6's own
reasoning is contradicted: its deciding measurement — that the corpus bottoms are all
`NUMBER`-typed, so the gate cannot live in the return type without becoming a tagged union the
exporter refuses with `D-SUMTYPE` — is equally true under D1's image.

**The counter-evidence he ruled AGAINST, recorded because the outcome alone is not the record.**
Omission is **not** diagnostically silent. Measured by `gm-dmn-refusal` on a hand-built omission
variant of the emitted `.dmn`, over the same five cases:

| image                        | values           | KIE 8.44.0.Final                                                                                                                  | Camunda 8.7.6        |
| ---------------------------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------- | -------------------- |
| floor row KEPT, `null` (D1)  | 35/35            | `0 error(s), 0 warning(s)`                                                                                                        | `0 error(s)`         |
| floor row OMITTED (D6 opt 3) | 35/35, identical | `0 error(s), 4 warning(s)` — `No rule matched for decision table '…' and no default values were defined. Setting result to null.` | `0 error(s)`, silent |

So omission buys a **runtime WARN on KIE once per unmatched evaluation** that the `null` row does
not. That is a real point for D6. What omission costs is **the row and everything on it** — the
author's sentence on `<description>` and the `@ref` in the `annotationEntry` — at export time, on
both engines. Both images raise `D-REFUSE` in the fidelity report either way, and both give
**identical answers on both engines**.

**What decided it, against that.** Three reasons, in the order they weigh:

1. **Two opinions against one.** D1 was adversarially checked; D6's refuter died on a session limit
   (recorded in §11.9.2's own "Adversarial status" note below).
2. **Omission buys no answer-visible loudness.** D1's equivalence measurement applies unchanged to
   the floor row — 35/35 identical on both engines — so the KIE warning is the whole of the gain,
   and a warning on one of two engines is not the loudness the omission image was sold on.
3. **Two images for one construct inside one exporter is the split a later reader gets wrong.**

**Correction to §11.9.2's own reasoning, made here rather than left standing.** §11.9.2 says the
two rulings "do not conflict, because R7's own taxonomy puts them in different rows". That is true
of a site that migrates to the gate and stops being a refusal — but it is **not true of a floor arm
that is genuinely a `REFUSE`**, which §11.9.2 itself identifies two of (`regcf-denovo.l4:211` and
canon's `sg-csp.l4:79`, both "this encoding does not carry that period"). Those are dated interval
tables whose floor arm refuses, and they are exactly the overlap. The paragraph is marked in place.

**Status: ruled 2026-09-05; the D1 image is BUILT on branch `props/dmn-refusal`** (not merged as of
this writing). Its measurements — including the engine divergence on `null` against `<outputValues>`
and the new `D-OUTPUTVALUES-NULL` code — are recorded by `gm-dmn-refusal` in §11.9.3 and in
`DMN-EXPORT-PROGRAM-MODEL-SPEC.md`; they are not restated here.

#### 11.9.2 R7.1 — the pre-commencement gate lives on the rule-version axis. RULED 2026-09-05.

R7's "Consequence to carry" above says the taxonomy split reclassifies Reg CF's pre-commencement
case and the temporal design's generated "not in force on ⟨day⟩" arm, and that **neither has a gate
design yet**. This is that design.

**Ruling (Meng, 2026-09-05, mark `accept` on rulings-bench card `D6-precommencement-gate`).**

- The gate is a **property of the rule-version axis, answered once at the boundary** (the card's
  option 4). That is the design.
- ~~Its **DMN half lands first as the card's option 3**: the refusing row is **omitted** from the
  exported table, and the table **declares itself incomplete**.~~ **SUPERSEDED the same day —
  ANSWERED 2026-09-05, see §11.9.1a.** On the one construct where this overlapped §11.9.1 — a
  dated interval table whose floor arm refuses — **D1's image wins**: the row is kept and answers
  `null`. Option 4 below is unaffected; R7.1 now has no separate DMN half of its own.
- The gate is **not** a value in the return type (option 2, declined on measurement — see below).
- "Do nothing, leave the arm an `ASSUME` bottom until Phase 2 builds the axis" (option 1) is
  declined: R0 deprecates `ASSUME`, so doing nothing is not a stable resting place.

**Read this beside §11.9.1.** §11.9.1 rules that a `REFUSE` lowers to FEEL `null` and **omits
nothing**. R7.1 as first written ruled that a pre-commencement gate **omits its row**. **PARTLY
WRONG — corrected 2026-09-05, see §11.9.1a:** the two DO conflict, on a dated interval table whose
floor arm genuinely refuses, and that conflict was resolved in §11.9.1's favour. The paragraph
below is right about everything except the word "not", and is kept because the taxonomy argument it
makes is still what separates the two rulings everywhere else. ~~They do not conflict~~, because
R7's own taxonomy puts them in different rows: _"the law does not
apply / is not in force"_ is a value or gate — this ruling — and _"the model does not cover this"_
is `REFUSE` — §11.9.1. The migration is what makes the difference visible: a site that moves to the
gate stops being a refusal, and §11.9.1 stops reaching it. `regcf.l4:486`, the COVID-19 temporary
rules, stays a `REFUSE` and is governed by §11.9.1; the model genuinely does not cover it.

**Status: ruled 2026-09-05; NOT BUILT, on either half.** Option 4 needs the rule-version axis of
`TEMPORAL-RULE-VERSION-DESIGN.md` Phase 2, which is unstarted. Option 3 needs the DMN exporter to
omit a floor row and to mark the table incomplete, and no code does either today: `§15.3` emits the
floor row `< date(dₙ)` precisely so the table is **total** over the date axis, and §3.3.1's `SHALL`
is read as forbidding a default on a complete table. Until both land, the arms stay as they are.

**What decided it.** One measurement rules out the return-type answer, and it is the only one that
separates the options. **Every pre-commencement bottom in the tree is `NUMBER`-typed** — measured
2026-09-05, ten declarations across ten `.l4` files, every one `IS A NUMBER`. A gate carried in the
return type therefore has to widen `NUMBER` into a tagged union, and a payload-carrying
`IS ONE OF` read by a decision is exactly what the DMN exporter refuses today with a **`Blocking`
`D-SUMTYPE`** (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §7 and §4.2.1) — the same class of "raw L4 that
no engine can evaluate" that §11.9.1 is repairing for `REFUSE`. Option 2 would buy a gate by
creating, in ten places, the defect the sibling ruling exists to remove. That leaves the
shape of the table and the axis itself, which is what was ruled.

**Blast radius, measured 2026-09-05.** Ten declarations and **twenty-four floor-arm sites** across
ten `.l4` files:

| file                                              | declaration | floor arms |
| ------------------------------------------------- | ----------- | ---------- |
| `jl4/examples/legal/regcf/regcf.l4`               | `:143`      | 8          |
| `jl4/examples/legal/regcf/denovo/regcf-denovo.l4` | `:211`      | 7          |
| `jl4/examples/dmn/gst-rate.l4`                    | `:65`       | 2          |
| `jl4/examples/dmn/ymd-dates.l4`                   | `:86`       | 1          |
| five `jl4/examples/dmn/not-ok/dated-chain-*.l4`   | one each    | 1 each     |
| `canon` `subjects/sg/child-support/…/sg-csp.l4`   | `:79`       | 1          |

Also: **2 export-schema entries** in `jl4/examples/legal/regcf/denovo/tests/regcf-denovo.schema.golden`
(`:733` under `/properties`, `:757` under `/required`) and **one `<inputData>` per exported DMN with
a floor arm** disappear under options 3 and 4. **3 sg-succession sites** already use a value-shaped
gate for enum-returning sections and are unaffected. Under options 3 and 4 no existing program
changes meaning: each migrated site moves from a bottom that stops evaluation to a gate that stops
evaluation, and the only observable difference is at the backends, where a caller-supplied number
becomes a declared absence.

**Three corrections to the counts, all measured.**

1. The card counted **9 declarations, 22 arms, across 9 files, "four `dmn/not-ok` fixtures"**.
   There are **five** such fixtures (`dated-chain-rolling-date`, `-duplicate-date`, `-misordered`,
   `-nested-otherwise`, `-mixed`), which makes the l4-ide totals 9 declarations and 23 arms — and
   the card's own "across 9 `.l4` files" was already counting all five.
2. **A third recount, 2026-09-05, proposed 25 arms; the table above sums to 24 and stands.** The
   proposed extra was `dmn/gst-rate.l4`'s second floor arm, "easy to miss because both arms name
   the same binding" — but that arm is already counted: `gst-rate.l4` is listed at **2** above
   (`:79` and `:92`), which is why the l4-ide subtotal is 23 and not 22. Re-derived from source
   the same day, per file: `regcf.l4` `:143` → arms `:154 :166 :175 :185 :195 :205 :215 :409` (8);
   `regcf-denovo.l4` `:211` → `:226 :232 :240 :246 :252 :258 :264` (7); `gst-rate.l4` `:65` →
   `:79 :92` (2); `ymd-dates.l4` `:86` → `:92` (1); five `dated-chain-*` fixtures, one arm each
   (5); canon `sg-csp.l4` `:79` → `:88` (1). **8+7+2+1+5+1 = 24.** A sixth `dated-chain` fixture,
   `dated-chain-regulative.l4`, carries no floor declaration and is not in the count.

   **The trap that has now moved this count three times: `regcf-denovo.l4` grep-matches EIGHT
   times outside its declaration, but only SEVEN are arms.** The eighth, at `:3035`, is **inside a
   comment** — ``-- ASSUME `no encoding of Part 227 exists for rule dates before 2022-09-20`,``
   — part of a prose paragraph explaining what the encoding floor costs at the API boundary. A
   plain `grep -c` over that file returns 8 and is wrong by one. Any recount must drop lines whose
   first non-space characters are `--`; that is how the enumeration above was taken. The
   load-bearing half is unaffected either way: **all ten declarations are `NUMBER`-typed**, which
   is the measurement the ruling turns on.

3. The card said **"0 sites in canon — canon has no pre-commencement bottom."** It has one:
   `subjects/sg/child-support/encodings/legalese/sg-csp.l4:79`,
   ``ASSUME `no Baby Bonus Cash Gift rate is encoded for a birth before 2015-01-01` IS A NUMBER``,
   reached from one arm at `:88`. The card's other canon claim is right — `sg-child-support.l4`'s
   live transitional provision models "born before commencement" as an ordinary value — but that is
   a different site.

**A distinction the card did not draw, and the migration must.** These ten are not one population.
Some say _the law was not in force_ (`regcf.l4:143`, `gst-rate.l4:65`, `ymd-dates.l4:86`, the five
fixtures) and belong in the gate row. Others say _this encoding does not carry that period_ —
`regcf-denovo.l4:211` ("no encoding of Part 227 exists for rule dates before 2022-09-20") and
canon's `sg-csp.l4:79` ("this encoding does NOT carry the earlier rates", its own comment at
`:70-78`) — which is the `REFUSE` row of R7's taxonomy, not the gate row, even though both are
guarded on a date. Canon's is guarded on the **child's date of birth**, not on
`RULES EFFECTIVE DATE`, so no rule-version axis can answer it at all. **The migration classifies
per site against R7's taxonomy; it does not sweep the ten.**

**Adversarial status.** Card D6's refuter died on a session limit, so this ruling rests on **one
opinion, not two** — unlike D1, D2, D3, D4 and D5. The measurement it turns on (all bottoms
`NUMBER`-typed; a tagged union is `Blocking D-SUMTYPE`) was re-checked here and holds, but no
adversary looked for a reading it misses. Treat it accordingly.

### 11.10 R10 — Backends. RULED 2026-09-04 (marked accept).

The transitive read-set pass lands first; the schema is keyed by (name, tier) with `x-l4-tier`;
check rejects an explicit parameter sharing a name with a discharged implicit; defaulted implicits
are not `required`; `BatchRequest` gains a `world` object; discharged implicits trail positional
parameters; OpenFisca puts scalar implicits in `parameters(period)` and refuses record ones;
`imaginary-alcohol-act.l4` migrates as fourteen scalar section `GIVEN`s. Detail:
`PROPS-REDTEAM-2026-09-03.md` §2.10.

### 11.11 R11 — `@reads`. RULED 2026-09-04 (marked accept).

A function may annotate an implicit it reads, `@reads interp — …`, or override the section's
`@desc` with its own, so the per-decision fork register of the de novo Reg CF encoding survives
hoisting. Detail: `PROPS-REDTEAM-2026-09-03.md` §2.9.

### 11.12 R12 — Six pre-existing defects are fixed now. RULED 2026-09-04 (marked accept).

Independent of any ruling: the tutorial's flat `#CHECK … WITH` form; the section-scoping
parent-ambiguity defect and the §3.3.4 drift; the schema's one-body-deep collector; `#ASSERT`
collapsing an exception to a plain failure; `#CHECK` printing inference gensyms; `l4 batch`
mis-applying a directly-read `ASSUME`. Built and independently verified on four branches off
`origin/unstable` (`PROPS-REDTEAM-2026-09-03.md` §7); delivered as PRs into `unstable` on 2026-09-04: legalese/l4-ide#328 (export read-set), #329
(section scoping), #330 (assert/check reporting), #331 (docs).

### 11.13 R9 — `WITH` is the one override mechanism; `LET` is unchanged. RULED 2026-09-04 (marked alternative).

An in-body hypothetical is written as a named application at the call, `` `the issuer's headroom`
WITH interp IS `the strict reading` ``, which discharge carries down the callee's subtree; at a
directive supply is likewise `WITH`. `LET` keeps its present meaning: it does not reach callees,
and a `LET` shadowing a name in scope stays an error. `WHERE` never supplies. Supplying a name the
callee neither takes nor reads is the existing check error. For DMN, rebinding the rule date drops
per ruling R-C of `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.12.1; any other binder overridden at an
inner site lowers as a tier-2 knowledge model. The temporal form `EVAL UNDER RULES EFFECTIVE AT d e`
succeeds to `e WITH \`RULES EFFECTIVE DATE\` IS d` once sharing is measured.

**What decided it.** One mechanism after R1–R3, no second binder with dynamic extent to explain;
no existing program changes meaning (`LET` appears 127 times in the examples and libraries and 7 in
canon); no demand (`LET` has zero uses in the 26 legal files against 125 `WHERE` blocks, and the
corpus's only hypothetical, `EVAL UNDER RULES EFFECTIVE AT`, has nineteen uses all at the outermost
position of a directive **or export body**, measured 2026-09-03 over `jl4/examples/legal/**`).

**Corrected 2026-09-05.** The sentence above dropped the "or export body" qualifier its own source
carries (`PROPS-REDTEAM-2026-09-03.md` §2.11: "all 19 legal-corpus uses … sit at the outermost
position of a directive **or export body**, zero inside a rule, quantifier or lambda"), was undated
in one place and misdated in another, and did not say what it was counting over. The count itself
was and is right: re-measured 2026-09-05, `grep -rn 'EVAL UNDER RULES EFFECTIVE AT' --include='*.l4'
jl4/examples/legal/` returns **19** — 17 in `regcf.l4`, 1 in `regcf-wizard.l4`, 1 in
`regcf-denovo.l4`. Do not read this correction as saying the nineteen was overstated; it was not.
**What R9 schedules is separately re-ruled**: `TEMPORAL-RULE-VERSION-DESIGN.md` §1.4.3 (2026-09-05)
rules sub-question (c) that the fold of `EVAL UNDER RULES EFFECTIVE AT` into `WITH` **is not a
rename** — it re-schedules on the 21 interval-builtin sites that rebind the axis per iterated day,
and it cannot be defined without also defining `WITH` discharge to snapshot and to report its own
unfrozen arms. The cost, terseness when several calls share one
override, is met by a helper. Detail: `PROPS-REDTEAM-2026-09-03.md` §2.6.

### 11.14 Sequencing item 6 — the corpus and docs migration: what it swept, and the two things it found

**Status 2026-09-05: built on branch `props/assume-sweep`, rebased onto `props/opaque-declare`
(PR #335), NOT merged.** Everything below describes that branch, not `unstable`. The migration is
driven by `etc/migrate-assume.mjs`, which is committed with it: the script is idempotent and never
writes without `--write`, so the tree it produces is re-derivable — re-running it over the swept
trees is a no-op, and that is the intended way to review the mechanical half of the diff.

**One exception to that no-op, measured after the rebase**, so a reviewer who runs the script is not
misled by it: `props/opaque-declare` added two fixtures that did not exist when the sweep ran, and
the script reports **4 term-role sites** in them — `ok/opaque-declare.l4:84-85`
(`` `some person` ``, `` `some premises` ``) and `doc/reference/types/opaque-example.l4:40-41`
(`` `the applicant` ``, `` `the premises` ``). **They are deliberately not swept here.** Both files
name the keyword in their own prose — "a value arrives from outside — an `ASSUME` here, a JSON input
at a service boundary in production" — so rewriting the declarations without rewriting the
surrounding explanation would leave each page contradicting its own example, which is the drift this
migration repaired in `legal/anti-social.l4` and `legal/british-citizen-act.l4`. Whether those two
fixtures should teach the section-`GIVEN` spelling is a question about what the opaque-type
documentation says, and it belongs to whoever owns that page — sequencing item 5's documentation
pass, alongside `doc/reference/types/ASSUME.md`'s deprecation notice — not to a mechanical sweep.

**Swept.** 207 term- and function-role `ASSUME` declarations rewritten to the R4 section `GIVEN`
across 62 `.l4` files — counted off the branch diff itself (`grep -c '^-ASSUME '` over the changed
`.l4` files), by tree as rewrites/files: legal 46/6, ok 65/22, not-ok 13/8, dmn 12/8, lsp 7/1,
docassemble 2/1, `doc/reference` 62/16. 76 sites are left across those trees, each refused by name
and line with a per-role reason (keep 39, type 10, refusal 9, app-form 8, overload 7, ditto 2,
root-section 1); the untouched `blawx` and `relational` trees hold 33 further app-form sites.
`jl4/experiments` and `jl4/tests-cli` (204 further rewrites against 206 refusals, measured
2026-09-05) are deliberately held back as a separate, droppable commit — that tree is in no goldened
glob, so it is carried on the `--verify` oracle alone (6 identical, 1 differing only in the line
number quoted by a pre-existing lexer error). Measured 2026-09-05:
`canon` holds exactly one `ASSUME`, `subjects/sg/child-support/encodings/legalese/sg-csp.l4:79`,
and it is refusal-role — **no canon change is owed by this item.**

**Answer-preservation.** An oracle (`--verify`) diffs `l4 run --json` for every changed file, HEAD
against worktree: 58 identical, 1 reordered, 4 different, and all five non-identical results are one
benign class — a file that gained a section now qualifies the name in its diagnostic
(`` `Assert directive ambiguity`.foo ``), same error, same count, same types.

#### Finding 1: a section `GIVEN` cannot yet carry an overloaded name, and this blocks item 7

`resolveSectionGiven` (`jl4-core/src/L4/TypeCheck.hs:641`) pairs each `GivenSig` parameter with the
0-ary `ASSUME` elaboration that `desugarSectionGivens` prepended, keyed on the **raw name alone**
(`List.lookup (rawName nm) elaborations`), and takes that elaboration's type, resolved binder and
`TYPICALLY`. When a section `GIVEN` binds one name more than once at different types — type-directed
name resolution, R0's suppliable-term role at its most general — every occurrence finds the **first**
elaboration and inherits its type. The function's own comment claims the printed `GivenSig` "stays a
faithful re-spelling of the source"; that holds only while the names are distinct.

Measured 2026-09-05. The rewritten files `l4 check` clean (`Check succeeded`, zero diagnostics) and
evaluate identically, because the elaborations stay distinct and they are what runs; the goldens and
the oracle above are therefore both blind to it. Only the checked module's `GivenSig` node is wrong
— and `L4.Print.prettyLayout` prints exactly that node, so `l4 batch` and the REPL re-emit
`GIVEN foo IS NUMBER` once per parameter and the re-emitted module fails to type-check with
"multiple definitions for the identifier". The 2nd..nth occurrence is also `ref`'d to the first
binder, so IDE go-to-definition on them lands on the wrong parameter. Scope: dumping the printer's
output for all 333 files the round-trip block covers (`JL4_PRETTY_DUMP_DIR`) and diffing each
section `GIVEN` block against its source found exactly two files whose parameter types are lost —
`ok/tdnr.l4` (`foo` at `NUMBER`/`BOOLEAN`/`STRING`) and `ok/misc.l4` (`coerce` at four function
types) — and those are precisely the two files the `prettyLayout round-trip` block fails on, each
arrived at independently.

This is not a defect of the migration: it shipped latent with the section binder (legalese/l4-ide#333),
and the migration is the first thing to author a file that reaches it. **It is a blocker for
sequencing item 7 (keyword removal):** if `ASSUME` goes while a section `GIVEN` cannot express an
overloaded name, L4 loses type-directed name resolution.

**A retracted attribution, kept here because the retraction is the useful part.** An earlier revision
of this section offered `jl4/experiments/macma3.l4` as a second instance of the collapse: it `ASSUME`s
`` `forfeiture` `` at `FROM Order TO BOOLEAN` and `forfeiture` at `FROM Action TO BOOLEAN`, likewise
`confiscation`, and at HEAD the checker reports "multiple definitions for the identifier" for both;
migrated, those two errors **disappear**. The disappearance is real. **The stated cause was wrong.**

Measured 2026-09-05 while repairing `resolveSectionGiven`: moving only the two `Action`-typed
`ASSUME` lines under the section heading — **no `GIVEN`, so no collapse is possible** — loses the
same two diagnostics, and the repaired compiler produces identical numbers across all six variants
tried. So `macma3.l4` exhibits a **declaration-order sensitivity in TDNR candidate resolution that
predates section binders altogether**: a separate defect, still unowned, and not evidence for this
one. Three attempts to reduce it to a minimal witness failed.

What survives the retraction: the collapse described above is real and is demonstrated by
`ok/tdnr.l4` and `ok/misc.l4`, where the printed module loses every binding after the first; and
`macma3.l4` remains a correct `overload` refusal, because it does bind one name at two types. What
does not survive is the claim that this defect is what silences its diagnostics.

Handled on the branch by fixing the _migration_, not the compiler: `etc/migrate-assume.mjs` gained a
structural `overload` refusal role — a name `ASSUME`d more than once in a file is refused, citing
`TypeCheck.hs:641` — so `ok/tdnr.l4` is left whole and `ok/misc.l4` migrates only its one
non-overloaded binder. The guard keys on the identifier rather than its spelling, since a backticked
declaration and a bare one denote the same name; keying on the raw text is what let `macma3.l4`
through on the first pass. It is structural rather than a path list so that it also protects the
rewrites still owed in `jl4/experiments` and `jl4/tests-cli`, where it refuses 10 further sites that
no path list would have named. The compiler repair is **open**, and it is owed before item 7.

**`ok/tdnr.l4` and `ok/misc.l4` are left un-migrated deliberately, as that repair's acceptance test.
Do not migrate them as tidying-up.** They read like two files the sweep missed; they are the pass
condition. The repair is done when `resolveSectionGiven` consumes each elaboration at most once, so
repeated names map to distinct binders, and those two files come out of the script's `overload`
refusal list and into the sweep with nothing else changed. The test runs in **both** directions,
which is why the marker is two files and not one: the printed module must keep every binding rather
than only the first, **and** `ok/tdnr.l4` — which exists precisely to require that two definitions
sharing a name at different types coexist and resolve by type — must stay green. A fix that repairs
the printing while breaking the resolution has moved the defect, not repaired it. (`macma3.l4` is
**not** part of this acceptance test; see the retracted attribution above.)

#### Finding 2: the IDE's one code action inserts the deprecated spelling. RULED 2026-09-05: it lands with item 5, not with item 6.

`jl4-lsp` has exactly one code action, `outOfScopeAssumeQuickFix`
(`jl4-lsp/app/LSP/L4/Handlers.hs:1009`), and it **inserts a new `ASSUME`** for an out-of-scope name.
The IDE therefore offers, as its only automated repair, the spelling R0 deprecates.

**Ruling: repointing it belongs to sequencing item 5, together with the deprecation warning, and not
to this item.** Item 5 already requires that "the warning does not land before the code action can";
this finding widens that requirement from _adding_ a rewrite action to also _repointing_ the
existing insert action, since a quick fix that generates code the same release starts warning about
is worse than no quick fix. Three things decided the placement rather than the principle. The
migration branch is corpus-only — 129 files, all `.l4`, goldens and reference prose, no Haskell —
and a compiler or LSP change would alter both its review character and which CI jobs it fires.
`Handlers.hs` is also edited by `props/opaque-declare`, which lands ahead of it. And the repointing
is not mechanical: an out-of-scope name at a position with no enclosing `§` heading has no section
to receive a `GIVEN` at all — the migration script measures that case as its `root-section` and
`no heading` refusals — so the action needs a stated fallback, which is design work for item 5.

### 11.15 The section binder is paired with its elaboration by identity, not by raw name. FIXED 2026-09-05.

`L4.TypeCheck.resolveSectionGiven` paired each section-`GIVEN` parameter with the 0-ary `ASSUME`
that `L4.Desugar.desugarSectionGivens` prepends for it using `List.lookup (rawName nm)`. L4 has
type-directed name resolution, so one spelling may be bound several times at different types
(`jl4/examples/ok/tdnr.l4` does exactly that with three `ASSUME`s); through a section binder every
repetition of the name therefore collapsed onto the **first** elaboration. Fixed by consuming the
elaboration list — each elaboration is taken by at most one parameter, in order — which is the
one-to-one pairing the desugarer's invariant already guarantees.

**What decided it.** Measured on `props/tdnr-collapse` 2026-09-05, with
`jl4/examples/ok/section-given-tdnr.l4` (a section `GIVEN` binding `foo` at `NUMBER`, `BOOLEAN` and
`STRING`, the section-binder spelling of `ok/tdnr.l4`):

- Before: the checked `GivenSig` held `[(foo, NUMBER), (foo, NUMBER), (foo, NUMBER)]` on one
  `Unique`; `prettyLayout` printed `GIVEN foo IS NUMBER` three times; re-checking that text gave
  three `AmbiguousTermError`s and the `prettyLayout round-trip` property (`jl4-test`) failed.
- After: `[(foo, NUMBER), (foo, BOOLEAN), (foo, STRING)]` on three distinct `Unique`s, the printed
  text carries all three types, and the round-trip is green.

Nothing in the tree could have caught it: the elaborations stayed distinct and they are what
evaluates, so `l4 check` reported zero errors, no golden changed, and the sweep's oracle — which
compared error _counts_ — saw nothing. The regression guard is therefore
`jl4-core/test/SectionGivenTdnrSpec.hs`, which asserts **which** binder and **which** type stands at
each position (four of its seven examples fail on the pre-fix compiler) plus the corpus file above,
whose round-trip is the end-to-end form of the same property.

**This unblocks `PROPS-REDTEAM-2026-09-03.md` §6 item 7, measured on the sweep's own marker.**
Removing `ASSUME` no longer costs type-directed name resolution: the section-binder path now
expresses what overloaded module-level `ASSUME`s express. `props/assume-sweep` left `ok/tdnr.l4`
(`foo` at three types) and `ok/misc.l4`'s four `coerce` declarations un-migrated deliberately, as
the marker for this defect, and its `etc/migrate-assume.mjs` refuses them under an `overload` guard.
Running that script over both files with only that guard lifted, 2026-09-05:

|        | `l4 check` | `prettyLayout round-trip` | the printed `GIVEN`                                                |
| ------ | ---------- | ------------------------- | ------------------------------------------------------------------ |
| before | succeeded  | **failed, both files**    | `foo IS NUMBER` x3; `coerce IS FUNCTION FROM NUMBER TO BOOLEAN` x4 |
| after  | succeeded  | passed, both files        | all three `foo` types; all four `coerce` types                     |

The `l4 check` column is the whole reason this defect survived: it reads "Check succeeded" on both
files on the pre-fix compiler. Non-overloaded neighbours are unaffected either way — `ok/misc.l4`'s
`cat` prints correctly on both compilers — so the repair is confined to the repeated name. The
`overload` refusal, and those two files' migration, can be lifted once this and the sweep are both
on `unstable`; the corpus files themselves are the sweep's and are untouched here.

**Correction to the finding this discharges.** The sweep reported a "second, worse instance": that
migrating `jl4/experiments/macma3.l4` made two `AmbiguousTermError`s disappear, and attributed that
to this collapse. **The attribution is wrong and this fix does not repair it.** Measured 2026-09-05
on the pre-fix and post-fix compilers alike: taking the swept `macma3.l4` and _only_ moving its two
`ASSUME forfeiture`/`ASSUME confiscation` lines (the `Action`-typed pair, at the file's end) up to
just below the section heading — leaving them as `ASSUME`s, adding nothing to any `GIVEN` — loses
the same two diagnostics, 4 errors to 2. So the trigger is a **declaration-order sensitivity in
TDNR candidate resolution**, which the migration meets only because `desugarSectionGivens` prepends
elaborations to the head of the section. It is a separate, unfixed defect, present on `unstable`
before section binders existed.

**Its witness and its mechanism** (verified here 2026-09-05, after a reviewer pointed at the site;
line numbers are this tree's). Four lines are enough:

```l4
§ `S`
#EVAL f 1
ASSUME f IS A FUNCTION FROM NUMBER TO BOOLEAN
ASSUME f IS A FUNCTION FROM STRING TO BOOLEAN
```

Measured: one `AmbiguousTermError` as written; **zero** with the `#EVAL` moved below the two
`ASSUME`s. `scanFunSigAssume`'s `mergeResultTypeInto` (`jl4-core/src/L4/TypeCheck.hs:4891`, used at
`:4852`) folds an `ASSUME`'s own type into a `GIVETH` so the scan phase can record it — but its
first equation, for a signature with an empty `GIVEN` and no `GIVETH`, returns the signature
unchanged and drops that type on the floor. A bare `ASSUME f IS A FUNCTION FROM … TO …` is exactly
that shape, so it reaches the scan with no result type, and a use checked before `inferAssume` gets
to it sees a candidate that unifies with anything. Both controls are order-insensitive, measured the
same day: the identical overload written as two `DECIDE`s, and written as two `ASSUME`s in
`GIVEN`/`GIVETH` form, give zero ambiguities in either order.

That also explains the asymmetry in `macma3.l4` and why three earlier attempts here to shrink it
missed it: the use site sits at line 115, _between_ the `Order`-typed pair at 94 and the
`Action`-typed pair at 188, so exactly one candidate is scanned late; moving the late pair up puts
both before the use and the diagnostic goes. Every one of those three shrink attempts put the use
site _after_ all the declarations — the order-insensitive direction — which is why they all came
back clean.

**Not fixed here, same family, measured 2026-09-05.** `L4.Names.isSectionBinderElaboration` also
keys on the raw name, and its docstring's ground for that ("a section that also spells out an
`ASSUME` of a name its own `GIVEN` binds is already a duplicate definition, so the name-based test
has no reachable false positive") is false under TDNR. A section with `GIVEN foo IS A NUMBER` on its
heading and a hand-written `ASSUME foo IS A BOOLEAN` in its body type-checks; `prettyLayout` then
**drops the hand-written `ASSUME`** as though it were the binder's elaboration, and the printed
module fails to type-check. `L4.Export.rewriteModuleAssumes` and
`L4.Names.stripSectionBinderElaborations` share the helper and the hazard. The repair is not the
same one: the elaboration has to be identifiable _as_ an elaboration (a marker on its annotation, or
a `Resolved`-only `Unique` match, which the polymorphic `LayoutPrinterWithName` printer cannot use
as it stands). This is the shape the sweep will produce wherever a section acquires a binder and
keeps an overloaded `ASSUME` of the same name, so it wants an owner before item 7.

### 11.16 Discharge as shipped — 2026-09-05

> **Section number, on rebase.** The `ASSUME` sweep takes §11.14 and
> `props/tdnr-collapse` has also claimed §11.15. Whoever rebases this branch last
> must renumber rather than assume the number is free.

`PROPS-REDTEAM-2026-09-03.md` §6 item 5. What landed, where it lives, what it
was measured against, and what it deliberately does not do. Written against the
tree at `props/discharge`; every claim below was probed on the binary built from
it.

#### What shipped

**`L4.Discharge` (new module).** `dischargeModule :: Module Resolved -> Module
Resolved` computes `R(f)` for every module-level definition — the section
binders it names, plus those named by anything it reaches through the call
graph — and then, for every `f` with a non-empty read-set, appends those binders
to `f`'s `AppForm` and `GivenSig` and appends the matching arguments at every
reference to `f`. The read-set is `L4.Export.transitiveReferencedUniques`, the
pass PR #328 landed, intersected with the module's section binders; the one
addition to `L4.Export` is `transitiveReferencedUniquesWith`, the same closure
against an already-built edge table, so asking for every definition's read-set
at once is not quadratic. There is still exactly one implementation of the
read-set.

**The discharged parameter is the binder's own `Resolved`.** The evaluator's
environment is `Map Unique Reference` and `matchGivens` binds a closure's
parameters at exactly those keys, so a body that already refers to the binder
finds the argument with no renaming, and the pass never mints a `Unique`. It is
also what makes the fixpoint sound: `R(caller) ⊇ R(callee)`, so a caller always
holds the key its call site has to pass on.

**Where it runs: the evaluation entry points only** —
`L4.EvaluateLazy.execEvalModuleWithEnv` and `execEvalModuleWithJSON`. The
checked module the LSP hovers over, the printers re-emit and the six backends
lower is the module the author wrote. This is a deliberate narrowing of §2.2,
recorded under "deferred" below.

**`WITH` on a binder (R1).** `L4.TypeCheck.supplyAppNamed` accepts a named
argument that is not one of the callee's declared parameters when the name is
one the module's section `GIVEN`s bind (a new `CheckEnv.sectionBinderNames`,
filled from `L4.Desugar.collectSectionBinderNames` before desugaring), checks it
against the binder's declared type, and records it with a negative index
(`implicitSupplyIndex`, documented on `AppNamed` in `L4.Syntax`).
`inferAppNamed` accepts such a site on a callee with no function type at all,
which is the common case: before discharge a 0-ary rule is not a function, and
measured on the pre-change binary the error was `IllegalAppNamed` ("which is not
a function"), not `IncompleteAppNamed`. `dischargeModule` consumes every
negative index; one reaching the evaluator is an internal error naming the
callee, rather than being sorted into some other parameter's position.

**`TYPICALLY` at the root (R8).** A binder declared `TYPICALLY d` has its
elaboration rewritten from an `ASSUME` into an ordinary 0-ary definition whose
body is `d`. Every reader takes the binder as a parameter and every call passes
it on, so the only site that can reach that definition is a root that supplied
nothing — and a 0-ary definition is a shared thunk, so `d` is forced at most
once per evaluation and every reader sees the same value. `WITH` still wins,
being an argument. The default's own read-set joins the call graph, so R8 rule 3
("Closure") holds by construction. `doc/reference/types/TYPICALLY.md` now says
this is a change of meaning and says where it stops, which is Meng's own note in
§11.5.

**R2 as a check error.** `L4.Desugar.detectRestatedSectionBinders` reports a
declaration's own `GIVEN` that restates a section binder's name. Scope: the
signatures of `DECIDE`, `ASSUME` and `DECLARE`, including those of `WHERE` and
`LET` locals — keyed on `TypeSig`, which is exactly what excludes a section's
own bare `GivenSig` and a lambda's. A lambda parameter that shadows a binder is
left alone; that is the residual cost §2.3 records, not a second binder.

**Two whole-module checks that `supplyAppNamed` cannot make**, both from
`L4.Discharge` and both reported like `Export.validateExportInputs`:
`unreadImplicitSupplies` (a `WITH` naming a binder the callee does not read —
without it the override would silently do nothing) and
`ambiguousImplicitSupplies` (a `WITH` naming a binder the callee reads under two
same-spelled binders, and matching neither — see "Found by review" below).

#### Measured

| probe (2026-09-05, `props/discharge` binary)                        | before       | after             |
| ------------------------------------------------------------------- | ------------ | ----------------- |
| `#EVAL doubled WITH \`the rate\` IS 5`, binder read directly        | check error  | `10`              |
| `#EVAL quadrupled WITH \`the rate\` IS 5`, binder read via a helper | check error  | `20`              |
| `#EVAL bump WITH n IS 3, \`the rate\` IS 5`, own parameter + binder | check error  | `15`              |
| `#EVAL f WITH alpha IS 1, beta IS 2` (§2.2's cross-section example) | check error  | `5`               |
| in-body `quadrupled WITH \`the rate\` IS 10`                        | check error  | `40`              |
| `TYPICALLY 3` on a binder, nothing supplied                         | assumed term | `6`               |
| `WHERE` local reading the binder                                    | assumed term | `5`               |
| `map (GIVEN x YIELD bump x) (LIST 1, 2, 3)`, binder supplied        | assumed term | `LIST 10, 20, 30` |
| binder read, nothing supplied, no default                           | assumed term | assumed term      |
| `#EVAL bump 3 WITH \`the rate\` IS 10`(positional then`WITH`)       | parse error  | parse error       |

The last two rows are the ones that had to NOT change.

#### The oracle, and the one regression it caught

Every `.l4` file under `jl4/examples/ok`, `jl4/examples/legal` and
`jl4-core/libraries` — **334 files** — was run through `l4 run` twice: once on
the pre-change binary and once on the post-change binary, over one byte-identical
corpus, and the outputs diffed. The pre-change binary is the `props/refuse`
worktree at `6f767daf`, whose tree `git diff` reports as identical to `unstable`
at `b2a3faac`; it has to be that rather than any older build, because a binary
predating #334 cannot parse `REFUSE` in the current prelude and fails all 334
files with cascading "could not find a definition" errors (`CLAUDE.md` §3.1).

**Result: 325 of 334 byte-identical; the remaining 9 are clock-dependent.** The
control that establishes the second half is that the pre-change binary was run
twice and disagrees _with itself_ on exactly those 9 files and no others —
`ok/excel-date/serials.l4`, seven `ok/ledger/bitemporal-*` and `record-*` files,
and `ok/temporal-thunk-leak-basic.l4`, which stamp wall-clock transaction time.
That set is the one `CLAUDE.md` §3.2.1 already records as clock-dependent.

The oracle caught one real regression on this corpus, and it is worth stating
because it is the argument for running it at all. `valueReferenceHazards` — a
check that no longer exists, see "Found by review" — originally reported **any**
bare reference to a definition with declared parameters that reads a binder.
`ok/section-given-indented.l4:29` is `#CHECK \`tax on\``, and `#CHECK` reports the
type its argument was _declared_ with and never evaluates it
(`evalDirective (Check \_ \_) = pure []`), so nothing there has to carry the
discharged parameter. That one line was the _only_ site in the whole 334-file
corpus the check reached, and it turned a green file red. Eta-expansion has since
made the check unnecessary altogether, which is the better fix — but the oracle,
not a reading of the code, is what found it.

Footprint at the time of writing: twelve section-`GIVEN` sites in seven files,
all added by #333. The blast radius grows when the `ASSUME` sweep
(`PROPS-REDTEAM-2026-09-03.md` §6 item 7) rewrites term `ASSUME`s into section
binders, which is why the oracle is the gate and not the test suite alone.

**What to expect when the sweep lands — now measured, not predicted.** The same
differential was run over the sweep's own corpus (`props/assume-sweep` at
`a1525a89`, 334 files, its libraries pinned): **333 of 334 agree** once the
review fixes above are in. The one that does not is `regcf-wizard.l4`, and it is
the cross-`IMPORT` case recorded under "Found by review" — not a shape anyone had
to guess at. Before those fixes a second file, `legal/british-citizen-act.l4`,
also went red. Re-run `oracle/sweeprun.sh` after the sweep rebases rather than
trusting this paragraph; it is the cheapest way to find the shape nobody
predicted.

#### Ruled here

**An implicit that nothing supplies and nothing defaults is an error AT THE
ROOT, at evaluation, not at check time.** §2.4 says "an implicit that does
neither is an error at the root naming the binder and the chain of calls that
needs it"; the shipped diagnostic is the evaluator's, and it names the binder:

```
I could not continue evaluating, because I needed to know the value of
  `the rate`
but it is an assumed term.
```

Three things decided it. A check-time version needs the read-set, which is a
whole-module fact, so it would be the same post-check pass as
`unreadImplicitSupplies` — but it would have to know which roots are exports,
where §2.10 says nothing may fail, and getting that wrong turns a working corpus
red. It would also change the answer for every `ASSUME`-shaped file in the
corpus the moment the sweep rewrites it, which is exactly what the oracle exists
to prevent. And the existing diagnostic already satisfies the sentence's
substance. **Owed:** the chain of calls. The message names the binder but not the
path of definitions that demanded it, which is the part of §2.4 that is not yet
built.

#### Found by review, after the first gate was green

Four things an independent read of this branch turned up. Each is recorded with
the probe that settles it, because three of the four are invisible until the
`ASSUME` sweep (§6 item 7) lands and turns 664 `ASSUME` lines into section
binders.

**R3's "bridge at the call" did not work, and the page taught it.** Two sibling
sections both declaring `foo`, with `f MEANS g WITH foo IS foo`: the name left
of `IS` was matched by `Unique`, but `L4.TypeCheck.implicitSupply` resolves it in
the _caller's_ scope to get its type, so it was the caller's `foo` and never
matched the callee's. Now matched by **unqualified spelling** against the
callee's read-set when exactly one binder is so spelled — which is how declared
parameters were already matched (`lookupOptionallyNamedType` compares raw names),
so this removes an inconsistency rather than adding a rule. Safe by construction:
the spelling case can only fire where the `Unique` case failed, and such a supply
is an error today, so it can turn an error into a working program and can never
change an answer a working program already gives. Two same-spelled binders in one
read-set is `AmbiguousImplicitSupply`, a new error, rather than a guess.
`ok/section-given-bridge.l4` and `not-ok/tc/section-given-ambiguous-supply.l4`.

**A reader passed as a value was a check error.** See the deferrals below; it is
now built, and it was a real regression on the sweep's corpus, not a nicety.

**§2.2's read-set subtraction is implemented.** `readSets` is a fixpoint over
per-call-site edges in which a `WITH` removes what it supplies from the callee's
contribution, so `h MEANS alpha PLUS (g WITH beta IS 100)` no longer carries
`beta` as a dead trailing parameter — which matters for R10, where the export
schema is keyed off the discharged AST and would otherwise list it as required.
Edges are per call site, not per callee: a definition called once with a `WITH`
and once positionally in the same body still contributes its full read-set
through the second call.

**Cost, corrected 2026-09-05.** An earlier version of this section said "0.70 s
against 0.73 s undischarged — none", and cited the review branch's 0.77 s as
agreeing. Both figures were real and neither was comparable: they were taken
_before_ the `ASSUME` sweep gave `legal/regcf/regcf.l4` a section `GIVEN` at line
468, when `dischargeModule` was the identity on that file and genuinely free.
Re-measured post-sweep, five interleaved pairs on one machine under one load:
**baseline median 0.77 s against 1.19 s, so ~1.6x, +0.44 s.** Corpus-wide it is
invisible — all 344 files under `jl4/examples/ok`, `jl4/examples/legal` and
`jl4-core/libraries`, alternating runs, 86 s/88 s baseline against 87 s/88 s —
because only a file that carries a section `GIVEN` and has a large call graph
pays; the rest hit `dischargeModule`'s empty-binder early exit. **Not isolated:**
whether the 1.6x is this fixpoint or discharge as a whole is unmeasured.

The rule this cost us, worth more than the number: **a performance figure without
the corpus it was taken on is not a figure.** Two true measurements disagreed for
a week's worth of confusion in one evening because neither said which corpus it
ran on.

**The `TYPICALLY` call-graph edge is gone.** `readSets` used to add each binder's
default as an edge keyed by the binder's own `Unique`. A default is literal-only
so the edge is always empty, but if that restriction is ever lifted the edge
makes `rewriteCall` rewrite every reference to that binder — including the
value-bound parameter references inside readers — into an application. **R8 rule
3 ("Closure") is therefore DEFERRED, not implemented**, with the literal
restriction as its guard. The earlier wording here, that it "holds by
construction", was a sharpening past the evidence actually gathered.

**Crossing an `IMPORT` was reachable and crashed; it is now handled in the
evaluator.** Measured on the sweep tree (`a1525a89`): exactly one module declares
a section binder _and_ is imported by another —
`jl4/examples/legal/regcf/regcf.l4:468`, imported by `regcf-wizard.l4`. The
importer declares no binder, so `dischargeModule` is the identity on it and its
call sites still pass the callee's _original_ arity, while the callee gained
trailing parameters when its own module was discharged. Six sites in that file
died with `Internal error: given signatures' values' lengths do not match` — an
internal error, on a correct program, in the flagship's wizard.

`L4.EvaluateLazy.Machine.matchGivens'` now takes the closure's captured
environment and, when a call is UNDER-applied and **every** missing parameter is
a key that environment already holds, binds only what was supplied and lets the
rest resolve from there. Every parameter discharge appends is a section binder of
the callee's own module, so that is precisely the imported module's own binder
cell — what the callee read before discharge. It cannot mask a real arity
mistake: an ordinary parameter the writer forgot is a fresh binding no module
environment carries, and the checker rejects genuine arity errors long before
evaluation.

What the importer still cannot do is `WITH`-supply that binder:
`CheckEnv.sectionBinderNames` is per module, so the name is not suppliable across
the boundary and the imported module's own `TYPICALLY` (or "assumed term")
applies. That is the remaining half of §2.2's "discharge happens at the module
boundary", and it is deferred. `ok/section-given-import-def.l4` and
`ok/section-given-import-call.l4` pin both the fix and the limit.

#### Deferred, each with why

- **Discharge does not cross `IMPORT`.** §2.2 says nothing implicit should, and
  the pass is per module, so an imported definition keeps the arity its own
  module gave it. Unreachable today: no file in `jl4/examples`,
  `jl4-core/libraries` or `doc/` that declares a section binder is `IMPORT`ed by
  another (measured 2026-09-05), no library declares one, and the sweep's own
  measurement is that none of its 46 headingless `ASSUME` files is imported
  either. If it is ever reached the failure is loud — a length mismatch naming
  the callee — not a wrong value.
- **The backends still see the undischarged module.** R10 (§11.10) moves DMN,
  Catala, Docassemble, OpenFisca, Blawx and MLIR onto the discharged AST, keys
  the export schema by (name, tier), makes defaulted implicits optional and adds
  `BatchRequest.world`. Keeping them on the module the author wrote is what lets
  this change land without moving a single backend golden, and lets the sweep's
  269 rewrites be gated on their own oracle rather than on this one. The one
  construct they cannot see is an inner `WITH` on a binder, which
  `L4.Discharge.implicitSupplySites` names so a backend can refuse rather than
  answer wrongly; wiring that refusal into each backend is part of the same
  follow-up.
- **A rule's own defaulted `GIVEN` still cannot be omitted at a named site.**
  R8's other half. The default lives on the declaration's `GivenSig`, and
  `supplyAppNamed` sees only the callee's `Fun` type, which carries names and
  types but not defaults; supplying it needs the callee's `FunTypeSig` threaded
  to the call site. `TYPICALLY` therefore has two behaviours today, not the one
  R8 asks for — but they are two, down from three, and `TYPICALLY.md` says which
  is which.
- **R5, field-opening, is not built.** §11.7 already sequences it after
  discharge, and §11.7's own note is that the sample which motivated it was
  re-cut as fourteen scalars under R10, so what remains is bare field names
  inside a rule.
- **R11, `@reads`, and the hover/index surfaces of §2.9 are not built.** They are
  §6 item 6 with the backends.
- **A defaulted binder gets no dedicated trace event.** §2.5 asks for one naming
  the binder, the declaration line and the value. Because the default becomes an
  ordinary 0-ary definition, the trace records it as a definition force, which
  is accurate but is not the "alpha took its default 10" line the directive
  output was supposed to render from.
- ~~A rule that reads a binder cannot be passed as a first-class value.~~
  **Built after review.** The pass now eta-expands a bare reference to a reader
  with parameters of its own, minting `Unique`s with the sort char `'d'` (no
  other minter uses it). This was not cosmetic: measured on the `ASSUME` sweep's
  tree, `legal/british-citizen-act.l4:152` passes the 1-ary reader
  `` `is a British citizen (variant)` `` to a higher-order rule and lost both its
  `#EVAL`s without it. `ok/section-given-reader-as-value.l4` pins both spellings.
  `ImplicitReaderUsedAsValue` and its corpus file are gone with it.

---

### 11.17 R13 — §5.3 is discharged: computed fields already compose. RULED 2026-09-05.

**Ruling (Meng, 2026-09-05, mark `accept` on rulings-bench card `D5-computed-fields-purity`,
option A′).** §5.3, "computed fields compose with `props`", is **discharged**: it is a description
of the tree, not a proposal. Nothing is owed on it, and §5.3 above is retensed to say so.

**What decided it.** A probe, and two code facts.

- Probe `scratchpad/consult/adv-d5/cf1.l4`, re-run 2026-09-05 on the `l4-base2` binary: a
  `DECLARE Sale` whose `gst` field is `` MEANS `net` * `gst rate` `` — a computed field reading a
  section binder declared two declarations away — exports, demands `gst rate` in its schema, and
  `l4 batch cf1.l4 -i '{"x":{"net":100},"gst rate":0.09}'` answers **109**. Omit `gst rate` from
  the row and it answers `Missing required field 'gst rate' in JSON object`. The composition works
  and the schema knows about it.
- `jl4-core/src/L4/TypeCheck.hs:195-199` runs the two desugars in a stated order —
  `desugarSectionGivens (desugarComputedFields program)` — with the comment explaining why they do
  not interfere: computed-field desugaring only inserts `DECIDE`s after a `DECLARE`, and section
  binders are elaborated last so each `ASSUME` sits at its section's head.
- `jl4-core/src/L4/Export.hs:353-356` says in its own Haddock that a computed `MEANS` record field
  desugars to a top-level selector `DECIDE` and "must be walked like any other callee", which is
  why the read-set finds it.

**Blast radius: zero.** No file changes and no program re-means. The card counted computed fields
two ways — **89 indented-`MEANS` sites in 20 files** on its own heuristic, 50 in 12 on the prior
analysis's narrower one, and **0 in `/Users/mengwong/src/legalese/canon`** under both. Neither
count was re-measured here and neither is load-bearing: the ruling is that nothing is owed, and
that holds at any of these figures. Four of the card's 20 are libraries — `prelude.l4`,
`math.l4`, `excel-date.l4`, `negation-as-failure.l4` — which 159 and 65 files import, so the
exposure is wider than a file list suggests even though the count of changes is nil.

---

### 11.18 R14 — §4.3 and §8 Q8 are withdrawn: "very pure" is not built and would not inform. RULED 2026-09-05.

**Ruling (Meng, 2026-09-05, same card, option A′).** §4.3 ("Discover purity; don't annotate it" —
mark a subtree "very pure" when it never touches the environment) and §8 open question 8 ("Purity
classification surface" — how is "very pure" exposed) are **withdrawn**. §4.3 and §8 Q8 above are
retensed to say so.

**What decided it.** Two measurements, both taken 2026-09-05.

- **Nothing was ever built.**
  `grep -rniE 'very pure|veryPure|isPure|purity' --include='*.hs' --include='*.ts' --include='*.svelte' .`
  over the tree returns **nothing**. §4.3 has been a proposal for its whole life, and §8 Q8 asks
  how to surface a classification that does not exist.
- **The badge would be uninformative.** `grep -rlE '^[[:space:]]*ASSUME ' --include='*.l4' jl4 jl4-core`
  returns **95** files, against **745** `.l4` files under those two trees. So a "very pure" badge
  would be true of roughly seven files in eight, which is not a distinction a reader can act on.
  (The card gave this as "95 of 615"; the numerator reproduces exactly, the denominator does not —
  745 is what `find jl4 jl4-core -name '*.l4'` counts on this tree today. The ratio is more lopsided
  than the card's, not less.)

**What this does not withdraw.** The read-set itself, which R0/R10/R11 build and which PR #328
already landed, is the mechanism §4.3 wanted; what is withdrawn is the badge on top of it and the
question of where to paint it. If purity is ever wanted as an artifact attribute, it is a fresh
proposal against a read-set that by then exists, not a resumption of this one.

---

### 11.19 The cross-`IMPORT` hole. RULING here; the defect record is OF-7.

**Ruling (with R13/R14, card `D5-computed-fields-purity`, option A′).** The measurement pass that
discharged §5.3 turned up a hole, and it is **filed as a defect rather than silently absorbed**.
What is ruled here is the **ordering, not a preference: the first required move is the REFUSAL, not
the closure.** `l4 check`/`l4 batch` must refuse an export whose read-set crosses an `IMPORT` before
the closure is allowed to find one — because closing the collector over imports on its own converts
a false green into a **demanded-then-silently-ignored** parameter, which is worse than the state it
replaces.

**Ruled 2026-09-05; not built.**

**The defect record — mechanism, probe, both halves, exposure — is
[`OPEN-FINDINGS-2026-09-05.md` OF-7](./OPEN-FINDINGS-2026-09-05.md), not this section.** It was
moved there 2026-09-05 because a defect that spans `Export.hs`, `Batch.hs` and `Print.hs` was never
a props-spec section, and because `OF-7` is a stable id while a §11 number is not: three branches
appended to §11 on one day and collided. **Cite `OF-7` for the defect and §11.19 for the ruling.**
Also recorded in `PROPS-REDTEAM-2026-09-03.md` §7.
