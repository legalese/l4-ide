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
of a refusal), §11.9.2 (`<outputValues>` widened by `null`) and §11.9.3 (which also carries D6's
pre-commencement-gate ruling and why its DMN half was not taken), and **R13** and **R14**
are added by §11.17 and §11.18 (§5.3 discharged, §4.3 and §8 Q8 withdrawn), and §11.19 rules the
ORDER in which the cross-`IMPORT` hole is repaired — the refusal before the closure — while the
defect record itself lives at `OPEN-FINDINGS-2026-09-05.md` **OF-7**, because it spans `Export.hs`,
`Batch.hs` and `Print.hs` and needs an id that does not move when this section list grows. **Every one of the four authorises work that has not been done**;
each says so in its own status line and names what would make it true.

### 11.1 R0 — `ASSUME` is deprecated. RULED 2026-09-04.

**Ruling (Meng, 2026-09-04): `ASSUME` is deprecated.** Its three jobs go to three destinations:

| job                                | destination                                                                 | status                                                    |
| ---------------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------- |
| suppliable term (the ~550 uses)    | a section-level `GIVEN` discharged by the compiler into ordinary parameters | built (#333, #344); corpus rewritten 2026-09-06 (§11.1.2) |
| uninterpreted type (`… IS A TYPE`) | a bodiless `DECLARE T`, an opaque nominal type (§11.1.1)                    | built 2026-09-05 (#335); corpus rewritten 2026-09-06      |
| refusal / typed bottom             | `REFUSE "…"`, uncatchable, boundary-only, in no schema                      | built (#334; DMN image #339); corpus rewritten 2026-09-06 |

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
can (ruled 2026-09-06, being built separately, §11.1.2); (6) corpus and docs migration,
`doc/reference/types/ASSUME.md` carrying the notice and the recipe (CLAUDE.md §6) — **done
2026-09-06, §11.1.2**, except the Blawx- and relational-shaped fixtures that wait on those legs;
(7) keyword removal, together with the dead `LocalAssume` grammar — outstanding, and now also
blocked on the Blawx and relational legs reading the section binder (§11.1.2, finding).

**What this does not decide.** Nothing of the red team's remains open; R1–R12 are ruled in
§11.2–§11.13 below. Still owed from the riders: the pre-commencement gate design and the
CORPUS-TRACK §8 amendment (§11.9). Consistent with §10.7 above and the handoff's §7 ("`ASSUME` is not simply
to be deleted"): the refusal and type roles get their own constructs _before_ the keyword goes.

#### 11.1.2 The corpus is rewritten, and a checker warning is ruled. RULED 2026-09-06.

**Ruling (Meng, 2026-09-06), verbatim: "Yes the checker should have an ASSUME deprecation
warning but we should also just rewrite all our code to the new system using REFUSE and section
givens etc."**

Two halves. **The warning half is ruled and is being built in a separate PR** by another deputy;
as of this writing `l4 check` reports nothing for an `ASSUME`, and the keep-list below is exactly
the set of files that PR will re-golden when the warning lands. **The rewrite half is this PR**,
and this section records what it did.

**Measured, before and after** (comment-stripped `^\s*ASSUME\b` over `jl4`, `jl4-core` and
`doc`, on `unstable` at `cdc11501`):

| tree              | before        | after                                                                                                                                                                                                                                                   |
| ----------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `jl4/experiments` | 214 in 12     | 17 in 3: 14 inside `{- -}` blocks in `macma2.l4` (commented-out code), 1 bodied `ASSUME Person IS A TYPE / HAS ATTRIBUTE …` in `britishcitizen.l4`, a file that does not parse at HEAD, and 2 polymorphic placeholders in `macma3.l4` (the limit below) |
| everything else   | 127 in 48     | 70 in 15: 69 in 14 files kept deliberately (below), and 1 in `regcf.l4` blocked by the DMN finding below                                                                                                                                                |
| total             | **341 in 60** | **87 in 18**                                                                                                                                                                                                                                            |

The 254 migrated lines, by role: **87 type** (86 as `ASSUME T IS A TYPE` → `DECLARE T`, in place;
one, `not-ok/tc/typically-on-type.l4`'s `IS A TYPE TYPICALLY 42`, as a section `GIVEN … IS A TYPE`,
the one spelling that reproduces its error), **115 function** and **41 term** (→ a section `GIVEN` under the declaring section's own heading, or
under a synthesised title heading where the file had none or where every heading was `§§`-deep),
and **11 refusal** (→ one named definition per refusal whose body is `REFUSE "…"`, readers
unchanged): the encoding floor in `regcf-denovo.l4`, the DMN exhibits `gst-rate.l4` and
`ymd-dates.l4` and the five `dmn/not-ok/dated-chain-*.l4`, `daydate.l4`'s out-of-range `YMD`,
the polymorphic `TBD` in `experiments/thailand-cosmetics/prelude.l4`, and
`ok/check-display-typevars.l4`'s polymorphic `bottom`. **`regcf.l4`'s two refusals did not move**,
for the finding below. One of them was found already mis-migrated: the second curated bottom,
"the COVID-19 temporary rules … are not modelled here" (§10.6(d)), had been swept into a
**section `GIVEN`** on 2026-09-05 (#337), which made a refusal a suppliable input in the schema
and an `<inputData>` in the DMN model — the one thing R7 says a refusal must never be. The
sweep's refusal detector keyed on the words "no …" and "refused"; that name has neither. The
detector is left as it is, because a detector that recognises refusals by their wording will
always have a hole — the recipe is to read each site (§2.8's field test: could a person supply
this value?) — and the site itself is left as the sweep left it, with the floor, until the DMN
question is answered.

**The mechanism.** `etc/migrate-assume.mjs` gained `--types` (the type role, in place),
`--hoist-root` (a declaration above the first heading goes onto the first heading's `GIVEN` when
that heading is `§`-deep, and under a synthesised title `§` when every heading is deeper), a
prologue fix (the synthesised heading follows the file's `IMPORT`s; before the fix it went above
them and every prelude name became "could not find a definition"), and a gate on its refusal
detector (a function-typed name is a predicate, not a bottom: `registration refused`,
`is name change refusal` and three more in `jerseyCharities.l4` were being refused as refusals).
Its `overload` guard is **deleted**: the collapse it protected against was fixed by §11.15, whose
regression test and corpus witness are both on `unstable`, so `ok/tdnr.l4` (`foo` at three types)
and `ok/misc.l4` (`coerce` at four) — the two files §11.14 named as that repair's acceptance test
— now carry the section-`GIVEN` spelling, one parameter per type, and the `prettyLayout
round-trip` block is green on both. The two `ditto` fixtures (`ok/ditto.l4`,
`lsp/semantic-tokens/ditto.l4`) were rewritten by hand onto the `GIVEN`'s continuation lines,
which `^` copies positionally exactly as it copied the `ASSUME` line.

**Answer-preservation.** The script's `--verify` oracle (`l4 run --json`, HEAD against
worktree) over every rewritten `.l4` file on the final tree, 59 files: **54 identical, 0
reordered, 5 different**. The five: `not-ok/tc/parse-error2.l4` and `parse-error3.l4`, kept
files whose one-line keep comment moved the line number quoted inside their pre-existing parse
error; and `seatbelt.l4`, `purchase.l4` and `macma3.l4`, which fail to check at HEAD and whose
only differences are the line numbers quoted inside their pre-existing errors' caret excerpts
and, in `macma3.l4`, two "multiple definitions" diagnostics for `forfeiture`/`confiscation` that
disappear because both declaration pairs now sit in the heading's `GIVEN` above the use site —
exactly the declaration-order sensitivity §11.15's retracted attribution names, so a spurious
diagnostic gone, not a meaning changed. Every one of the 154 files in `jl4/experiments` keeps its
HEAD `l4 check` exit code (127 clean and 27 failing, before and after, per file), and every one
but `macma3.l4` keeps its diagnostics. Every goldened file's `.golden` was read: outside the
refusal sites the changes are the moved declaration in the exactprint, and line-number shifts
from a one-line keep comment. The refusal sites change what the reader is told, which is the
point: `ymd-constructor.l4` prints `The model refuses to answer: YMD refused an out-of-range
month or day` where it printed the bottom's own name as data (§2.8 predicted exactly that
display), and `regcf-denovo.schema.golden` loses the floor from the published inputs and from
`required` (`REFUSE.md` predicted exactly that removal).

**The DMN leg, measured on both engines** (KIE 8.44.0.Final, Camunda 8.7.6, locally, 2026-09-06).
Each floor leaves the `<inputData>` and becomes a `<decision>` whose literal is `null` and whose
`<description>` carries the reason (D1), so the engine harness no longer hands the floor in as
`-1`: `gst-rate.cases.json` 66/66 → **77/77** (eleven cases, seven decisions), `ymd-dates.cases.json`
**63/63**, 0 errors and 0 warnings on both engines, with every refusing decision's `null` licensed
by an explicit null in `expect` and the pre-commencement cases (F/J, F/G/H) re-pinned to `null`
on the rate, the fee and everything downstream — which is what L4 says a reached refusal does,
not what an engine said. `ymd-dates.l4`'s "nothing Blocking" test now excludes `D-REFUSE`, whose
Blocking on a strict consumer and a DRG root is D1's own calibration. The Reg CF corpus leg is
unchanged, because `regcf.l4` is unchanged.

**Finding: a refusal reachable from a tier-2 BKM un-BKMs it, and that blocks the Reg CF corpus's
own refusals.** Measured 2026-09-06 with this tree's binary on four variants of `regcf.l4`
(HEAD; HEAD with only the commencement floor spelled `REFUSE`; the same plus the COVID site
spelled `REFUSE`; each against HEAD's and the migrated `daydate.l4`, which made no difference):

| variant                               | BKMs | decisions | inputData | tally                           |
| ------------------------------------- | ---- | --------- | --------- | ------------------------------- |
| HEAD (floor an `ASSUME` bottom)       | 10   | 70        | 29        | 21 lossy, 133 advisory          |
| floor `REFUSE`, COVID a section GIVEN | 5    | 76        | 58        | 31 blocking, 44 lossy, 133 adv. |
| floor and COVID both `REFUSE`         | 5    | 77        | 56        | 31 blocking, 45 lossy, 134 adv. |

The five BKMs that vanish are exactly the decisions that can reach the floor — `investment
limit`, `financial statements required`, `offering is within the offering limit`, `investor is
within the investment limit`, `the transaction qualifies for the section 4(a)(6) exemption` —
and they reappear as parameterised decisions. §11.9.1 rules that a refusing decide is not
`DMN-SAFE` and does not un-lift, and `L4.Dmn.Lower` applies the same rule to BKM eligibility
(the "safety-refused tier-2 residue", `Lower.hs:5350`, `:6059`), so each demoted decision needs
its own `<inputData>` for `investor`, `offering`, `issuer`, `filing`, `arrangement` and `amount
to be sold in this transaction`: hence `investor_2` … `investor_6`, twenty-nine new inputs, and
`D-SCOPE`/`D-RENAME` notes on all of them. D1 was measured on `refuse.l4`, which has no BKM, so
this shape was never exercised. Three exporter tests written against the BKM shape fail on it
(§15.8's `financial statements required` BKM, the §15.12 `D-SVCEMPTY` claim, and R13's
"empties Blocking"), and the 23-case engine pins would all have to be re-derived against a model
with twice the inputs. That is an exporter ruling — should a refusing BKM stay a BKM, with the
refusal reaching it as a knowledge requirement? — and not a corpus rewrite, so `regcf.l4` is
byte-identical to HEAD in this PR and its two sites are the ones the DMN half of item 6 still
owes.

**Kept on `ASSUME`, deliberately — 14 files, each with a one-line comment saying so** (and,
separately, `regcf.l4`'s floor, blocked as above, and `macma3.l4`'s two polymorphic placeholders,
blocked by the limit recorded under "Refuted, and what changed"). The list was 27 files at the
first pass; the refuters below cut it to 14. Their
purpose is to exercise the deprecated keyword's own syntax, diagnostics or tooling, or they declare
something no `ASSUME`-free spelling can: the deprecation page's own example
(`doc/reference/types/assume-example.l4`); the semantic-token fixture; the two parse-error
fixtures and the misattached-`GIVEN` fixture (`not-ok/tc/parse-error2.l4`, `parse-error3.l4`,
`section-given-misattached.l4` — a `GIVEN` spelling reports a _different_ error, measured);
`ok/signatures.l4` and `ok/tbd.l4` (the signature spellings, and the polymorphic ones have no
section-`GIVEN` image, below); `ok/typically-basic.l4` (`jl4-service/test/QueryPlanSpec.hs`
pins ladder atom ids captured from it, and a TypeScript fixture in another repository pins the
same ids); and the **relational and Blawx trees** — `relational/assumed.l4`,
`not-ok/assumed-signatures.l4`, `not-ok/local-assume.l4`, `blawx/alcohol.l4`, `antisocial.l4`,
`not-ok/arity-two.l4` — whose input predicates are signature-style `ASSUME`s (next finding).

**Refuted, and what changed (2026-09-07).** Per the standing authorisation (BRIEF §14), seven
agents were run against this branch before it was reported: five Sonnet differentials, one per
tree, comparing `l4 run` (and `l4 check`) on every file — importers included — between
`cdc11501` and this head, and two independent Opus refuters each trying to produce a working
`ASSUME`-free rewrite of every kept file. The differentials: **933 files, 0 unexpected
differences** — libraries plus their 112 importers 128/0, `legal` 26/0, `ok`+`not-ok`+`lsp`
375/0, `experiments`+`dmn`+`docassemble`+`relational`+`blawx`+fixtures+`doc` 376/1, the keep-list
28/0 — the one being `macma3.l4`, where this PR's first rewrite of two polymorphic placeholders
(`combine`, `lifted or`) as `FOR ALL`-typed section-`GIVEN` parameters had replaced two
diagnostics with two different ones. Measured on the repair: **an explicit `FOR ALL` type on an
assumed term is not instantiated at a use site in either spelling** (`GIVEN pick IS FOR ALL a A
FUNCTION FROM a AND a TO a` and `ASSUME pick IS FOR ALL …` both report "You are giving 2 inputs
to pick … but it is not a function"); only the signature form (`GIVEN a IS A TYPE … GIVETH … ASSUME
f`) generalises, and that form has no section-`GIVEN` image. The two placeholders are back in that
form, `ASSUME.md` no longer claims the `FOR ALL` carry, and `ok/tbd.l4`'s keep reason is this
limit. The same differential found `ok/ymd-constructor.l4`'s own comment still describing the
pre-`REFUSE` "assumed term" stop; corrected.

The keep-list refuters produced working rewrites — same `l4 run`/`l4 check` output modulo
positions, and the same tool output where a tool is the fixture's subject — for **thirteen** of
the 27 files, each re-measured here before it moved: `blawx/not-ok/zero-arity.l4` (the same three
arity-0 rejections from `l4 blawx`), `docassemble/assume-via-fn.l4` (YAML and fidelity byte-identical
to the shipped golden), `not-ok/tc/typically-on-type.l4` (`GIVEN … IS A TYPE TYPICALLY 42` under a
heading reports the identical error — the stated reason had considered only `DECLARE`),
`ok/assumes.l4`, `relational/assumed-nullary.l4` (a nullary section `GIVEN` lowers to the identical
`RInput`), `tests-cli/fixtures/assert-assumed.l4`, `batch-assume-direct.l4`, `batch-assume-helper.l4`
(byte-identical NDJSON, including `Missing required field: 'x'`), `implicit-assume-test.l4` (whose
header claimed an implicit-extraction case that no longer existed: every name was declared),
`ok/assume-as-given.l4` (identical required-input sets on all four exports),
`ok/section-scoping-descendant-rebind.l4` (byte-identical, and by construction: the section
binder's elaboration _is_ the fully annotated 0-ary `ASSUME` the regression is about),
`tests-cli/fixtures/export-blocking-only.l4` (two rule `GIVEN`s with **distinct** names — `p q` and
`r s` — keep the report at `2 blocking` with no advisory; and the stated cause was wrong twice
over: the note a heading adds is `D-SVCEMPTY`, not `D-FLAVOR-NOSERVICE`, and it is caused by the
`§` heading alone, `ASSUME`s or not), and `ok/inert/grounding-variants.l4` (each decision now
declares its atoms as its own rule `GIVEN`s; measured through `jl4-lsp`'s decision-graph command,
all 42 box labels are byte-identical to HEAD, whereas a section `GIVEN` prefixes each with its
heading — the comment's quoted "(qualified at section X)" rendering was stale, `Print.hs` retired
it for the dotted form). Where the two refuters disagreed, measurement decided: `parse-error2.l4`
stays because the `GIVEN` spelling's error reads `unexpected GIVEN`, not the fixture's error;
`typically-basic.l4` stays for the atom-id pin above, which neither refuter could see.

**What survives is structural, not lexical** (the refuters' summary, confirmed): a section
`GIVEN` desugars to the very `ASSUME` node every tool reads, so no fixture of the form "how tool
X treats an `ASSUME`" keeps the keyword on its own account. The four things with no
`ASSUME`-free spelling are the signature form `GIVEN p IS A T / ASSUME f p IS A U` (a parse error
under a heading; the function-typed section `GIVEN` is refused on the export path), the
`GIVETH`-headed polymorphic form, the `WHERE`-local form, and the `§` heading a section `GIVEN`
drags in (which the DMN exporter and the ladder visualizer both react to).

**Finding: the Blawx bridge and the relational middle end are built on the `ASSUME` node, and that
blocks sequencing item 7.** `L4.Relational.Lower` lowers a top-level `ASSUME` to an `RInput`
predicate and `L4.Blawx.Lower` hangs it off a category; the same predicate as a section `GIVEN`
is function-typed, and `L4.Export.validateExportInputs` rejects a function-typed input on an
`@export`ed decision, so a Blawx seed in the section-`GIVEN` spelling has no export root and no
Blawx image at all (the seeds' own headers record the measurement). Removing the keyword
therefore costs those two legs their input predicates until they read the section binder. The
Blawx tutorial and `ASSUME.md` now say so; an earlier sentence in the tutorial claiming "the
exporter treats a section `GIVEN` exactly as it treats an `ASSUME` term" was false for Blawx (a
nullary section `GIVEN` is the arity-0 shape `not-ok/zero-arity.l4` pins as refused) and is
corrected.

**Docs.** `doc/reference/types/ASSUME.md` is the deprecation page: what the keyword did, the three
destinations with a before/after each, the function-typed limit above, and the recipe. Every
other page that taught `ASSUME` as the way to supply a fact now teaches the section `GIVEN`
(`keywords.md`, `TYPICALLY.md`, `DECLARE.md`, `A-AN.md`, `default-reasoning.md`,
`testing-your-rules.md`, `http-json.md`, the section-`GIVEN` tutorial's migration example, the
errors page); `REFUSE.md`'s limits no longer say the corpus refusals are unmigrated, and the
`daydate` pages say `YMD` refuses. Two stale "proposed, not landed" notes about supplying a
section `GIVEN` with `WITH` — in `errors/README.md` and `section-given.md` — were replaced with
what the discharge PR made true (probed: `#EVAL isAdult WITH age IS 25` answers; the same line
against an `ASSUME` is a check error).

**`legalese/canon` is untouched** and holds exactly one `ASSUME`,
`subjects/sg/child-support/encodings/legalese/sg-csp.l4:79`, refusal-role ("no Baby Bonus Cash
Gift rate is encoded for a birth before 2015-01-01"); it is the GM's to queue.

**What this does not decide.** Whether `daydate.l4`'s out-of-range `YMD` should answer `EITHER`
(the taxonomy row §2.8 puts it in) rather than refuse: that is a change to the library's
interface, which every date in the corpus relies on, and `REFUSE` is the one construct that keeps
the constructor loud without making its sentinel suppliable; recorded as a limit in `REFUSE.md`.
And sequencing item 7, keyword removal, which now waits on the two legs above as well as on the
warning.

#### 11.1.3 The deprecation warning, and the code action that stops offering `ASSUME`. BUILT 2026-09-06.

**Ruling (Meng, 2026-09-06), verbatim: "Yes the checker should have an ASSUME deprecation warning
but we should also just rewrite all our code to the new system using REFUSE and section givens
etc."** This addendum is the warning half — sequencing item 5 — together with the repointing of
the one code action that §11.14 Finding 2 tied to it. The rewrite half landed first and is
§11.1.2 above, which records its own sweep; this section is the warning it ruled.

**What the warning is.** `DeprecatedAssume` in `CheckWarning`
(`jl4-core/src/L4/TypeCheck/Types.hs`), emitted once per author-written `ASSUME` from
`inferAssume` (`jl4-core/src/L4/TypeCheck.hs`), severity `SWarn` and never `SError`, so nothing
that checked before stops checking and `l4 check` still exits 0. The 0-ary `ASSUME`s that
`desugarSectionGivens` prepends for a section `GIVEN` pass through the same `inferAssume`; they
are told apart by `isSectionBinderElaboration` — the name-based test every other consumer of the
elaborations already uses — and never draw it, which `ok/assume-deprecated.l4` pins with a section
`GIVEN` that must stay silent. A `WHERE`-local `ASSUME` (`LocalAssume`, the grammar item 7 removes)
draws it too.

**What it says.** The first line is fixed — _"ASSUME is an older way of introducing a name, and it
is being retired."_ — and the rest is phrased by the job the declaration's shape says it was doing,
read off the checked signature alone (`assumeRoleOf`):

| shape                                                                                      | role     | the line it offers, pasteable                                                                                                           |
| ------------------------------------------------------------------------------------------ | -------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `… IS A TYPE`, or `GIVETH A TYPE` above a bare `ASSUME T`                                  | type     | `DECLARE T` (with the head's parameters, `DECLARE T x`), citing §11.1.1                                                                 |
| result type is one of the declaration's own type variables, or no type written             | any-type | none: nothing can ever supply it, so `REFUSE "<the reason>"` alone                                                                      |
| everything else — a value, or a function (`… IS A FUNCTION FROM …`, or a head with inputs) | term     | `GIVEN name IS A type`, function type spelled out from the head's inputs, `TYPICALLY` carried across; `REFUSE` named as the alternative |

The term role names `REFUSE` as well because a term-shaped refusal (`regcf.l4:143`,
`daydate.l4:104`) is indistinguishable from a suppliable fact by shape; the rewrite half is what
resolves those. The type role's `DECLARE T` and the term role's `GIVEN` line are what
`etc/migrate-assume.mjs` writes, so the warning and the sweep agree. Function-typed `ASSUME` is
warned toward a section `GIVEN` of function type, which is what the item-6 sweep did with every one
it met (its plan carries both `term` and `function` roles to the same rewrite); no separate ruling
exists for that role, and `doc/reference/types/ASSUME.md` said "not yet ruled — keep the `ASSUME`"
until this addendum aligned the page with the sweep. Wording follows the diagnostic-voice rules of
PR #349: inputs, never binders; the name on its own line, as every neighbouring message does. In the
IDE the diagnostic additionally carries `DiagnosticTag_Deprecated`
(`jl4-lsp/src/LSP/L4/Rules.hs`), so editors strike the `ASSUME` through.

**"Never an error" had to be made true at three gates, not only in the checker.** Measured
2026-09-07 by running `jl4-core-test` over the tree: two `UnifySpec` cases that carry an `ASSUME`
and assert a successful check went red, because `checkWithImports`'s `tcdSuccess`
(`jl4-core/src/L4/Import/Resolution.hs`) was `null result.errors` — "no diagnostics at all", so
any warning, and even a `#CHECK` info, made the module unsuccessful through that one API while the
Shake rule, `l4 check` and `jl4-service` all key on `SError`. Two more gates in
`jl4-core/src/L4/API.hs` had the same blindness: `l4Eval` failed on anything that was not `SInfo`
(so every warning), and `l4VisualizeByName` on any diagnostic at all; `jl4-wasm`'s `l4QueryPlan`
copies the latter. All four now count `SError` only, which is what the checker's own `severity`
already said. The exhaustiveness warning had been tripping them for as long as it has existed;
the deprecation warning, which lands on far more files, is what made it visible.
`jl4-core/test/DeprecatedAssumeSpec.hs` pins the gate (a warning-bearing module has
`tcdSuccess = True` and exactly one `SWarn`) alongside the role classification of each shape and
the `TYPICALLY` carry. `jl4-wasm` is not in `cabal.project`, so its edit was not compiled locally;
the wasm CI job is the check.

**Where it is tested.** `jl4/examples/ok/assume-deprecated.l4`: one `ASSUME` per role (a value, a
function, a head with an input, a type, a type-variable result) plus the silent section `GIVEN`, and
its four goldens; `jl4-core/test/DeprecatedAssumeSpec.hs` for the API boundary and the roles.
Every other corpus file still carrying an `ASSUME` after the item-6 sweep gained
the warning in its check golden and nothing else — 18 files, each diff read before blessing:
13 under `ok/` (`assume-as-given`, `assumes`, `check-display-typevars`, `ditto`, `inert/grounding-variants`,
`misc`, `opaque-declare`, `section-scoping-descendant-rebind`, `sections`, `signatures`, `tbd`,
`tdnr`, `typically-basic`), `legal/regcf/regcf.l4` and `legal/regcf/denovo/regcf-denovo.l4`,
`jl4-core/libraries/daydate.l4`, and `not-ok/tc/section-given-misattached.l4` and
`not-ok/tc/typically-on-type.l4` (the two `not-ok/tc` files with a parse error never reach the
checker, so their goldens are unchanged). The `lsp/semantic-tokens` fixtures keep the keyword and
are unaffected, since token goldens carry no diagnostics. Only the entry file's own diagnostics
reach a golden, so `daydate.l4`'s warning appears in its own golden and in none of its importers'.
Documented for users at `doc/reference/errors/README.md` ("ASSUME is being retired", quoting the
term-role text verbatim) and `doc/reference/types/ASSUME.md`.

**The code action (§11.14 Finding 2).** `jl4-lsp`'s one code action, `outOfScopeAssumeQuickFix`,
inserted `ASSUME n IS A ty` for an out-of-scope name. Measured 2026-09-06 before touching it: 80
lines in `jl4-lsp/app/LSP/L4/Handlers.hs`, no test of any kind (`jl4-lsp-test` had two specs, hover
display and library resolution, and depends on the `jl4-lsp` library, which the `app/` handler is
not part of). It now declares the name the ruled way, and the stated fallback Finding 2 asked for is
the rule `GIVEN` that `doc/reference/types/ASSUME.md` teaches for exercising a rule inside the file:

- under the nearest enclosing `§` heading, as a parameter of that section's `GIVEN` — appended to
  an existing block, aligned with its first parameter, or as a new `GIVEN` line right after the
  heading, four columns past the `§` (R4);
- under no heading at all — the migration script's `root-section` refusal — as a parameter of the
  enclosing `DECIDE`/`MEANS`'s own `GIVEN`: appended, or inserted on the line above the
  declaration's own first line (its `GIVETH` if it has one, else its head), so an annotation above
  the declaration stays above it.

The edit is computed by a pure function, `outOfScopeGivenFix` in `jl4-lsp/src/LSP/L4/Actions.hs`,
so that it is testable without an IDE; the handler only fetches the checked module and wraps the
result. `jl4-lsp/test/OutOfScopeGivenFixSpec.hs` type-checks four small modules through the real
oneshot pipeline and asserts the position, indentation and text of each edit, plus that no edit
ever contains the keyword. One pre-existing limit is kept and now documented in the spec: a use
whose type is left as an inference variable (the overloaded `>=` does this to `age >= 18`) earns no
fix, since LSP 3.17 has no snippet support to leave a hole; the old action had the same guard.

**Refuted and repaired, 2026-09-07.** Under the standing authorisation for adversarial workflows
(BRIEF §14), ten Opus refuters attacked three claims about the warning — the role and line are right
(A), every author-written `ASSUME` warns exactly once (B), nothing else ever warns (C) — plus a
voice review of the texts against `doc/STYLE.md` and CLAUDE.md §7. Claim C held: 856 corpus files
swept, every warning traced to an `ASSUME` keyword or a ditto row continuing one; every CLI verb
exits the same with and without the `ASSUME`; the three severity gates above really are
severity-aware. Claims A and B did not hold. What they found, and what changed:

| finding (independent refuters)                                                                                                                                                                                                                                             | repair                                                                                                                                                                                                                                                                               |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| An author-written 0-ary `ASSUME` sharing a name with its own section's `GIVEN` drew no warning, was dropped by the printer and by `l4 render` (7 of 10 refuters; TDNR makes it legal)                                                                                      | `isSectionBinderElaboration` (`jl4-core/src/L4/Names.hs`) now requires identity as well as name: the elaboration carries no concrete tokens (`isSynthesisedAnno`). Its comment claiming "no reachable false positive" was false and is replaced. `ok/assume-beside-section-given.l4` |
| An infix or postfix head (`ASSUME a `plus` b …`) was named and anchored on its first input, which is not a name of anything (2)                                                                                                                                            | the warning and its context take the head from the checked, restructured `rappForm`                                                                                                                                                                                                  |
| A function over its own type variable (`ASSUME identity x IS AN a`) was called "a type that could be anything"; a bare `ASSUME w` whose type the uses pin was told the same (2)                                                                                            | any-type only with no inputs; a bare `ASSUME w` is a new `AssumeUntypedRole` that asks for the type                                                                                                                                                                                  |
| `IS A FOR ALL …` does not parse; a type variable the type never mentions withheld the line; an untyped input (`GIVEN n`) put a gensym (`n2`) on the line; a keyword name (`` `LIST` ``) printed bare; an `AKA` was dropped; `@desc`/`@ref` were not mentioned (A1, A2, A3) | `FOR ALL` takes no article; the hole is used only when the type mentions an own type variable or still holds an inference variable; keyword names are quoted; the `AKA` names and any annotation are named in the message                                                            |
| A `WHERE`-local `ASSUME` was sent to a section `GIVEN` it cannot reach (A1, A2, A3)                                                                                                                                                                                        | `AssumePlace`: a local `ASSUME` is sent to the rule's own `GIVEN`, a local type `ASSUME` to the top of the file. `ok/assume-in-where.l4`                                                                                                                                             |
| Voice: no line said nothing is broken; `REFUSE` had equal weight to the primary answer (§6 sequestration); "with nothing after the name" was false for `DECLARE T x`; "opaque" was unglossed; the tutorial and the skill still said "no warning"                           | line 2 now says so; `REFUSE` is one parenthetical; "with no parts listed"; glossed; both pages corrected                                                                                                                                                                             |

`ok/assume-heads-and-roles.l4` pins the middle rows; `jl4-core/test/DeprecatedAssumeSpec.hs` pins
each repair at the API. Held on re-measurement over the whole tree (`jl4/`, `jl4-core/`, `doc/`,
`jl4/experiments/` included): 333 live `ASSUME` declarations across the 58 files that reach the
checker, 333 warnings; the six files with a parse error never reach it.

**Found and NOT repaired here — owed elsewhere, each with its witness in the refuters' scratch.**

- **The `@export` gate treats the two function spellings differently.** `ASSUME f p IS A BOOLEAN`
  (inputs on the head) read by an `@export` rule passes `validateExportInputs`; the section `GIVEN`
  the warning offers for it, `GIVEN f IS A FUNCTION FROM Person TO BOOLEAN`, is refused with
  "Function type inputs are not supported for @export". Measured by rewriting every corpus
  `ASSUME` by its own suggested line: 34 of 38 head-form sites, in `blawx/alcohol.l4`,
  `blawx/antisocial.l4`, `blawx/not-ok/arity-two.l4`, `relational/assumed.l4` and
  `relational/not-ok/assumed-signatures.l4`, turn a clean file into an export error. So the ruled
  destination for a head-form function `ASSUME` has no spelling `@export` accepts, and
  `doc/reference/types/ASSUME.md`'s "refuses it either way" was false (corrected). **Needs a ruling**
  before the sibling rewrite touches those five files: widen the gate to the head form (consistent,
  and breaks those files' exports), or accept function-typed section `GIVEN`s that only helpers read. **RULED 2026-09-07 (R-X4,
  §11.20): neither, because the premise was false — the head form does not export either.** It
  passes `l4 check` and then fails every batch row, so the gate is inconsistent rather than
  protective. It is re-keyed on the AppForm's arity, refusing both spellings at check time.
  **BUILT 2026-09-08 (§11.21), and that is what makes the sibling rewrite of those five files safe:**
  neither destination exports, so the migration no longer trades a clean file for a broken one — it
  moves a file that was already refused. The count was five files, not the three §11.20 estimated.
- **`l4 batch` re-prints a TDNR section `GIVEN` wrongly.** `Export.rewriteModuleAssumes` keeps the
  surviving binders by raw name (`filterGivenSigTo`), so dropping one of two same-named
  elaborations keeps both `GivenSig` parameters and the reprint declares the name three times. Same
  family as §11.14 Finding 1's owed repair.
- **The quick fix can trade one error for another**: a section `GIVEN` for a name a sibling rule
  already takes as its own input raises R2 (`RestatedSectionBinder`), and appending to a called
  rule's `GIVEN` changes its arity at every call. Both edits parse and declare the name the ruled
  way; neither is a wrong edit, but the fix could prefer the rule `GIVEN` when a sibling rule
  declares the name. Not done.
- **The layout printer prints a keyword-usable name bare in every position.** `quoteIfNeeded`
  (`jl4-core/src/L4/Print.hs`) exempts `LIST` because a type head may spell it bare, but a
  `GIVEN` parameter or an `ASSUME`/`DECLARE` head may not, so a module declaring `` `LIST` `` does not
  survive `prettyLayout` ("unexpected LIST, expecting identifier"). The warning quotes it on its
  own line (pinned in `DeprecatedAssumeSpec`); the printer is not repaired here, which is why
  `ok/assume-heads-and-roles.l4` carries no such name — the `ok/**` round-trip would reject it.
- Pre-existing, unrelated: an imported module's diagnostics print once per import path (diamond
  imports triple them); `GIVEN a IS A TYPE / GIVETH A TYPE / ASSUME B a` is an error while the
  three neighbouring spellings pass; a `FOR ALL` type declares but is not applicable at a call site;
  `#CHECK` on a type name leaks a gensym; Catala and Blawx call a section `GIVEN` a "module-level
  ASSUME" in their own messages; `l4 batch` never surfaces a warning; `check --json` carries no
  structured severity.

**What this does not decide.** Nothing new. The compiler repair of §11.14 Finding 1 is still owed
before item 7, and item 7 itself (keyword removal, with `LocalAssume`) is unchanged.

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
declaration is exactly the section-`GIVEN`/function-`GIVEN` line). Measured cost zero **as of
2026-09-04**: across 607 files there were 235 term-role `ASSUME` names and 2,311 function `GIVEN`
names and no file where the two sets overlapped. Those counts are pre-sweep and are now stale —
2026-09-05, post-#337: 644 files, 101 term-role `ASSUME` lines. Restatement as an error rather than
a warning was part of the recommendation Meng accepted; it is the one sub-point he did not
separately voice.

**The cost is still zero, but not for the reason above, and it was not zero in between.** That count
measured a proxy — whether any file spells a name as both a term-role `ASSUME` and a function
`GIVEN` — rather than the check as built. The first implementation keyed on the raw name
**module-wide** and rejected `doc/tutorials/section-given/what-a-section-needs-to-know.l4`, a
before-and-after tutorial whose "before" section deliberately repeats a name that a **different,
later** section declares as a section `GIVEN`; `doc/test-docs.sh` went red on a correct file (#344).
Scoped to the binders _visible_ at the declaration — its own section and its ancestors — the check
now fires on **zero** files across `jl4/examples/ok`, `jl4/examples/legal`, `jl4-core/libraries` and
`doc`, measured 2026-09-05 post-sweep. Note for anyone re-deriving this: the column-1 reading is a
false lead. A column-1 `GIVEN` is never read as a section binder, so R4 was never in play.

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

**The per-root check was NOT BUILT until 2026-09-08 — measured 2026-09-07, and R-X2 (§11.20) ruled it
built as one job with the call-site type check.** `TypeCheck.hs:236-244` wired exactly two whole-module
implicit checks, both keyed to supply sites; nothing scanned a root's read-set. Witness on the shipped fixture
`ok/section-given-bridge.l4` plus two lines, `` `both` MEANS foo PLUS g `` and
``#EVAL `both` WITH foo IS 1``: under section 1 the answer is **991** (1 + 99×10 — the supply
reached one `foo`, the other fell to its default); the identical lines under section 2 give **11**.
`l4 check` succeeds both times. `ambiguousFor` (`Discharge.hs:476-479` @ `6e9b57bb`) could not see the case because
it requires the resolved `Unique` to be absent from the read-set, and here it is present.

**BUILT 2026-09-08, together with R-X2's call-site type check, as R-X2 required — one job, one
confusion.** `Discharge.ambiguousRootBinders` enumerates the roots (`Export.collectExportedDecides`
for the `@export`s, a section walk for the directives), and reports every group of two or more
same-spelled binders in a root's read-set as the new check error `AmbiguousRootBinders`. Each
candidate is named under its declaring section, via `sectionQualifiedWith` — the pure half of
`sectionQualified`, factored out in this change precisely so the whole-module checks (which run
outside `Check`) and the ambiguity diagnostics cannot drift to two spellings. Wired beside the other
two whole-module implicit checks in `TypeCheck.hs`. Fixture:
`not-ok/tc/section-given-root-ambiguous.l4`. Page: `doc/reference/syntax/section-given.md`, "One
name per thing you run".

**What building it settled that the ruling did not say: R3 has TWO shapes, and only one of them is
about a root's read-set as such.** The section is written as "a directive or export whose read-set
holds two binders of one name", and the first implementation took that literally: it tested every
directive's read-set, unsubtracted, and every export's. Both halves of that were wrong, and both were
found by adversarial passes on 2026-09-08 rather than by the corpus, which stayed green throughout.

- **A directive with no `WITH` has nothing to be ambiguous between.** There is no supply channel;
  every binder it reaches takes its own `TYPICALLY` default and the answer is total and
  deterministic. Testing it refused the very sibling-section drafting R3 exists to permit —
  `ok/section-given-fruit.l4`, `doc/reference/syntax/sections-example.l4` and the section-`GIVEN`
  tutorial each went red on one added `#ASSERT`, with **no way out**, because a directive cannot be
  rewritten to reach fewer binders. It also refused `#EVAL g WITH foo IS foo` — the bridge the
  error's own message tells the writer to write.
- **Grouping on spelling alone conflates R3 with the TDNR overload.** `ok/section-given-tdnr.l4` and
  `ok/misc.l4` — the two files §11.16 left un-migrated _as this repair's acceptance test_ — each went
  red on one added directive, and the diagnostic offered two candidates printed under **identical**
  section-qualified spellings with three remedies none of which applies. Two binders of one name at
  different types are not two answers to one question; they are two questions. The check now keys on
  `(spelling, typeKey)`, `typeKey` being the annotation-insensitive skeleton overload resolution
  already uses, so the two cannot drift on what "the same type" means.

**As built, therefore:**

| shape           | test                                                                                                                   | why                                                                                 |
| --------------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `@export`       | its read-set holds two same-spelled, same-typed binders — unconditional                                                | the read-set is published as a request schema, and a row cannot carry one key twice |
| a `WITH` supply | the callee's read-set holds two same-spelled, same-typed binders, and the supplied name's `Unique` matches one of them | the value reaches exactly one; the other falls back to its default. This is the 991 |

The supply test's second clause keeps it disjoint from `ambiguousImplicitSupplies`, which fires when
the supplied `Unique` matches **none**. A site is reported at most once.

**The witness still fires**, which is the point: `#EVAL `both` WITH foo IS 1` supplies, and `both`'s
read-set holds both `foo`s. `not-ok/tc/section-given-root-ambiguous.l4` pins it.

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

**EXTENDED 2026-09-06 to `DECLARE` record fields (D7.3, upstream #645).** R8 as written governs
`GIVEN` binders and `TYPICALLY.md:69-72` carves record fields out. D7.3 rules that a `MAYBE`-typed
field may be declared `field IS A MAYBE T TYPICALLY NOTHING`, and only then may a construction
site omit it — same principle, one declaration, the default living where the name is declared.
Ruled 2026-09-06, **not built**, and **blocked on R8's own named-site half**. The governing text for
that ruling is `TYPICALLY-DEFAULTS-SPEC.md:420-428` and the record is
`SURFACE-SUGAR-CLUSTER-2026-09.md` §D7.3, which also rules the source/boundary asymmetry R8 does not
reach: the JSON and service boundary keeps defaulting an absent `MAYBE` field to `NOTHING`
(`Machine.hs:2282`, `Backend/Jl4.hs:436-441`, `JsonSchema.hs:264`), and `TYPICALLY NOTHING` does not
gate it.

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
`PROPS-REDTEAM-2026-09-03.md` §2.8 (~~DMN omits the refusing row, non-Blocking `D-REFUSE`,
`MayRefuse` safety kind~~ — **DMN's third of that image is SUPERSEDED by §11.9.1 below**; Catala no
definition; Docassemble a terminal screen; evaluator, CLI, batch and service a `refused` kind);
order-dependence under lazy `AND`/`OR` written down. The taxonomy row is split: "the law does not
apply / is not in force" is a value or gate that savings and transitional provisions can reach;
"the model does not cover this" is `REFUSE`.

**Consequence to carry, so two documents do not contradict.** The split reclassifies Reg CF's
pre-commencement case, which `specs/todo/lexipedia-superset/CORPUS-TRACK.md` §8 ruling R2 and
`regcf.l4:135-143` record as a curated refusal, and the temporal design's generated "not in force
on <day>" arm (`TEMPORAL-RULE-VERSION-DESIGN.md` item 3), which becomes a gate. Neither has a gate
design yet. Until one exists the commencement arm stays a `REFUSE`, and the PR that lands `REFUSE`
amends CORPUS-TRACK §8 in the same change.

### 11.9.1 D1 — the DMN image of a refusal. RULED 2026-09-05 (marked accept).

**A `REFUSE` lowers to FEEL `null`. The refusing row is NOT omitted. `DMN-SAFE` is withdrawn from
any decision that can refuse, and the existing call-site calibration sets the severity of a new
`D-REFUSE` code. `MayRefuse` is dropped.** This AMENDS §11.9's reference to
`PROPS-REDTEAM-2026-09-03.md` §2.8; that paragraph's DMN sentence is superseded, and §2.8 and §6
item 6 say so in this same change.

The reason string is written into the artifact twice, which is the property omission could not
have had: on the refusing `<rule>`'s `<description>` (`OTHERWISE — REFUSE: …`), and on a new
`<decision>` `<description>` (`REFUSE: …`) covering the two shapes with no row — a whole body that
refuses, and an `OTHERWISE` that became a `defaultOutputEntry` under `UNIQUE`.

**What decided it.**

1. **The baseline, reproduced rather than inherited.** Before this change the exporter wrote the L4
   source text into a FEEL literal (`Dmn/Lower.hs:2285`, `Refuse {} -> verbatim e`), and KIE
   8.44.0.Final answered `ERROR [ERR_COMPILING_FEEL] … syntax error`, `BUILD 1 error(s)`,
   `VERDICT … <<< FAILED` — it did not merely mark the file Blocking, it failed to compile it.
   After the change the same module is `XSD valid / VALID clean / BUILD clean`.
2. **§2.8's argument for omission cannot choose between the options.** It read "FEEL `null` is
   already spent on `NOTHING`, so `REFUSE → null` would launder". Measured: an omitted row and a
   `null` row are **engine-identical under both hit policies this exporter emits** — under
   `HitFirst` the catch-all is a rule (`Lower.hs:695`) and deleting it leaves nothing matching;
   under `HitUnique` the `OTHERWISE` is the `defaultOutputEntry` (`Lower.hs:1651`) and deleting it
   has the same effect. Both answer `null`. Given the equivalence, `null` is the cheaper arm (one
   case alternative, versus recomputing eight `informationRequirement` sets) and the only one that
   keeps the author's sentence, because omission deletes the `<rule>` whose `<description>` would
   hold it.
3. **What replaces the laundering worry.** Not a promise, three mechanisms: a refusal is a `REFUSE`
   clause in `analyzeSafety`, so a refusing decide is **not** `DMN-SAFE` and does not un-lift; the
   clause **propagates to callers** carrying the callee's own reason, which is §2.8's `Ref(f)`
   fixpoint over the graph that already existed; and `D-REFUSE` is raised at the severity
   `D-PARTIAL` already uses (extracted into one shared helper, not copied) — `Lossy` when every
   call site is a lazy arm, `Blocking` on any strict consumer or none at all. §2.8's "non-Blocking
   `D-REFUSE`" is overruled by the DRG-root case, where a caller gets `null` with status SUCCEEDED
   and nothing to tell it apart from an answer.
4. **Neutrality, measured not assumed.** All ten existing DMN golden subjects regenerate
   byte-identically (`.dmn` and `.fidelity.txt`, 20/20, after normalising the harness's `main.l4:`
   source prefix). No corpus module contains a `REFUSE` the DMN exporter can see, and
   `analyzeSafety`'s documented cross-module gap keeps `prelude.l4`'s `TBD` invisible to it.

**The condition Meng's acceptance attached, and what each half became.**

- _A case that evaluates through a refusal, on both engines._ Built as
  `jl4/examples/dmn/refuse.l4` + `refuse.cases.json`, an eleventh golden subject holding one of
  each position a refusal can occupy. **KIE: `5 case(s), 0 error(s), 0 warning(s), 35/35 SUCCEEDED,
35/35 value(s) as expected, 25/25 service output value(s) as expected`. Camunda 8.7.6: `5
case(s), 1 parsed, 0 error(s), 35/35 evaluated, 35/35 value(s) as expected`.** Wired as its own
  step in the DMN engine job.
- _`--fail-on=blocking` actually exercised._ Wired into the `p7-dmn` leg's export
  (`etc/go/phases/p7-dmn.sh` step 1, gated at step 4b). Measured green first: the Reg CF corpus
  exports **0 blocking** notes today (21 lossy, 133 advisory), so the gate is not red on arrival.
- _The enum case._ See §11.9.2, which is where it stopped being a precondition and became a
  ruling of its own.

**A correction to the precondition as written.** "A pre-commencement case in each of
`regcf-corpus.cases.json`, `gst-rate.cases.json` and `ymd-dates.cases.json`" was already true of
two of them: `gst-rate` has cases F (1990-01-01) and J (1994-03-31), `ymd-dates` has F, G and H.
Only `regcf-corpus` has none — all 22 cases sit at 2016-09-01 or later against a 2016-05-16
commencement. The substantive half of the finding stands for all three and is **not** discharged by
this change: none of those cases evaluates through a `REFUSE`, because all three still spell the
floor as an `ASSUME` the harness supplies as `-1`. `refuse.l4` is what makes that migration safe to
attempt; the migration itself is the next change, and it is where the `regcf-corpus` case belongs,
since a case added now would pin the `ASSUME` image it is about to replace.

**Owner's note on the second per-backend image.** The dmnmd/markdown carrier is ruled here too:
**a refusing table is omitted, loudly.** No code was needed for the omission — `mdOutput` already
refuses anything outside S-FEEL and FEEL `null` is not S-FEEL — but the message was wrong, naming
the enumeration ("parentheses, a comma, or an expression outside S-FEEL") rather than the instance,
which is the mistake `cellSyntaxReason`'s own header records having made once already over dates.
Both `D-MD-CELLSYNTAX` and `D-MD-NOLITERAL` now name the refusal and carry the reason. The
projection of `refuse.l4` to markdown is an empty document, and that is the finding rather than a
defect in the fixture: dmnmd cannot say `null`, and a bare `null` cell would be read back as the
STRING `"null"`.

### 11.9.2 D1a — `<outputValues>` is widened by `null`. RULED 2026-09-05 on measurement.

**When a decision table's output entry can be FEEL `null` and the table declares an
`<outputValues>` domain, `null` joins that list — unquoted, as the FEEL keyword. The type's own
`<itemDefinition>`/`<allowedValues>` is untouched. A `D-OUTPUTVALUES-NULL` note (Lossy) records
it.**

**What decided it, and it is the finding of this whole change.** D1's third precondition called
`null`-against-an-enum "the concrete silent-wrong-answer path". It is not silent, and it is not
loud either — **the two target engines disagree**. Measured 2026-09-05 on a
`Band IS ONE OF standard, reduced, exempt` table whose `OTHERWISE` refuses:

| engine                    | what it does with `null` against `<outputValues>`                                                                                       |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| KIE 8.44.0.Final          | runtime **ERROR**, decision **FAILED** — `Invalid result value on rule #3, output #1. Value null does not match list of allowed values` |
| Camunda 8.7.6 (zeebe-dmn) | returns the `null` **silently**, `0 error(s)`, decision evaluated                                                                       |

One artifact, two meanings, which is a stronger reason to act than either engine alone would have
been. Widening the list reconciles them (re-measured: KIE `2/2 SUCCEEDED`, Camunda `2/2 value(s) as
expected`) at a cost of exactly one value of domain assertion — a value the table genuinely can
produce, so declaring it is more accurate than not, not less.

**Isolated by probe, not by argument.** The same enum is declared twice: on the type's
`<allowedValues>` and on the table's `<outputValues>`. Widening `allowedValues` alone does **not**
stop the KIE error; widening `outputValues` alone does. So the TYPE keeps its exact L4 domain for
every other consumer, and only the table that can decline says that it can.

**Not refusal-specific, deliberately.** The condition is "an output entry renders as bare `null`",
which since R8-d′ is also true of a `MAYBE`-valued table. That case carried the same latent
divergence and is closed by the same line. No existing golden moves, so the corpus has no such
table today.

**Kept honest by a pair, not a positive.** `jl4/tests-cli/fixtures/dmn-refuse-enum/` holds
`widened.dmn` and `unwidened.dmn`, differing in one token, and CI asserts KIE green on the first
and red-with-that-message on the second, **and Camunda green on both**. The positive alone would be
equally consistent with KIE having stopped checking `<outputValues>` at all, which is exactly what
the step claims to exclude. If either half moves, the widening is re-ruled rather than re-blessed.

### 11.9.3 D6's DMN half — NOT taken. RULED by Meng 2026-09-05 on the conflict.

**THE RULING. Keep D1's image: the refusing row stays and answers `null`.** Ruled by Meng
2026-09-05 on the conflict between D1 and D6 option 3, **having been shown the omission variant's
per-evaluation KIE warning and its cost in the reason string and the `@ref`** — that is, decided
_with_ the counter-evidence in hand, not in ignorance of it. The table of measurements below is
what he was shown. D6's long-run option 4 (the gate is a property of the rule-version axis) stands
unchanged.

D6 (accepted 2026-09-05) rules the pre-commencement gate to be a property of the rule-version axis
in the long run, and says its DMN half lands first as option 3: **"the refusing row is omitted, and
the table declares itself incomplete"**. On the one construct where D1 and D6 overlap — a dated
interval table (§15.3) whose floor arm refuses — **that contradicts D1, which rules the refusing
row is kept.** Both were accepted, 73 seconds apart.

**D1's image was built, and D6's was not.** Three reasons, stated so a later reader does not
mistake this for an oversight: D1 was adversarially checked and D6's refuter died on a session
limit, so D1 carries two opinions and D6 one; the measurement that decides D1 (omission and `null`
are engine-identical) applies unchanged to the floor row, so option 3 buys no engine-visible
loudness while losing the reason string; and two images for one construct inside one exporter is
the kind of split a later reader gets wrong. **Nothing in D6's own reasoning is contradicted** —
its deciding measurement is that every corpus bottom is `NUMBER`-typed so the gate cannot live
in the return type, which is equally true under D1's image.

**D6's blast-radius counts were wrong, and the re-measurement is below, ENUMERATED BY LINE so the
addition can be checked rather than taken.** D6 as accepted says "9 declarations and 22 floor-arm
sites across 9 `.l4` files" and "**0 sites in canon**".

| file                                              | decl   | floor arms, by line                        | type     |
| ------------------------------------------------- | ------ | ------------------------------------------ | -------- |
| `jl4/examples/legal/regcf/regcf.l4`               | `:143` | 154, 166, 175, 185, 195, 205, 215, 409 — 8 | `NUMBER` |
| `jl4/examples/legal/regcf/denovo/regcf-denovo.l4` | `:211` | 226, 232, 240, 246, 252, 258, 264 — **7**  | `NUMBER` |
| `jl4/examples/dmn/gst-rate.l4`                    | `:65`  | 79, 92 — 2                                 | `NUMBER` |
| `jl4/examples/dmn/ymd-dates.l4`                   | `:86`  | 92 — 1                                     | `NUMBER` |
| `dmn/not-ok/dated-chain-nested-otherwise.l4`      | `:29`  | 38 (an `ELSE`, not an `OTHERWISE`) — 1     | `NUMBER` |
| `dmn/not-ok/dated-chain-misordered.l4`            | `:35`  | 47 — 1                                     | `NUMBER` |
| `dmn/not-ok/dated-chain-mixed.l4`                 | `:31`  | 45 — 1                                     | `NUMBER` |
| `dmn/not-ok/dated-chain-rolling-date.l4`          | `:28`  | 39 — 1                                     | `NUMBER` |
| `dmn/not-ok/dated-chain-duplicate-date.l4`        | `:28`  | 40 — 1                                     | `NUMBER` |
| `canon .../legalese/sg-csp.l4`                    | `:79`  | 88 — 1                                     | `NUMBER` |

**10 declarations, 24 arms, 10 files.** Canon is **not** zero — `sg-csp.l4:79`,
`no Baby Bonus Cash Gift rate is encoded for a birth before 2015-01-01`, is a pre-commencement
bottom of exactly this shape. There are **five** `dmn/not-ok` fixtures with floor arms, not four; a
sixth, `dated-chain-regulative.l4`, declares no floor and is not counted.

**A correction to this paragraph's own first version, kept because the method error is the reusable
part.** It said **25**, and blamed the difference on `gst-rate.l4`'s second arm. Both were wrong.
That count was taken as "occurrences of the floor name, minus one for the declaration", which
silently counted **a comment at `regcf-denovo.l4:3035`** as an arm — so that file read 8 where the
enumeration above gives 7. `gst-rate.l4`'s two arms were never in dispute. Counting occurrences and
subtracting the ones you know about is not enumeration: it cannot tell an arm from a comment, and it
fails silently, in the direction of over-counting. That is why the table above lists line numbers.

**The second grep was wrong too, in the other direction.** The re-enumeration that produced that
table classified each occurrence by keyword, and keyed on `OTHERWISE` — so it dropped
`dated-chain-nested-otherwise.l4:38`, which is an **`ELSE`**, and reported 23. Two greps in a row,
two different wrong answers, neither of them careless. What caught it was printing the
**unclassified residue** rather than the total: a classifier that reports a number and not what it
failed to classify cannot tell you what it dropped. If a count matters, print the leftovers.

**What survives the recount is the load-bearing part**: every one of the ten is `NUMBER`-typed, so
D6's argument that the gate cannot live in the return type without making each a tagged union
stands, and stands over a slightly larger population than it claimed. Since D6 is one of the cards
whose adversarial refuter died, treat its remaining figures as unverified too.

**The measurement, taken 2026-09-05 rather than left owed.** `refuse.dmn`'s floor row was deleted
by hand from the emitted artifact — the exact shape option 3 asks for — and both engines were run
over the same five cases:

| image                        | values           | KIE 8.44.0.Final                                                                                                                                      | Camunda 8.7.6        | the reason, in the artifact                                                               |
| ---------------------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- | ----------------------------------------------------------------------------------------- |
| floor row KEPT, `null` (D1)  | 35/35            | `0 error(s), 0 warning(s)`                                                                                                                            | `0 error(s)`         | row `<description>`, `<decision>` `<description>`, and the arm's `@ref` `annotationEntry` |
| floor row OMITTED (D6 opt 3) | 35/35, identical | `0 error(s), 4 warning(s)` — `WARN … No rule matched for decision table 'the_filing_fee' and no default values were defined. Setting result to null.` | `0 error(s)`, silent | none — the `<rule>` that held all three is deleted                                        |

**So D1's "engine-identical" claim is confirmed on the VALUES, on both engines, and is incomplete
on KIE's diagnostics: omission does buy a runtime WARN that the `null` row does not.** That is a
real point for D6 and it is recorded here rather than argued away. What it buys is one-engine-only
(zeebe-dmn is silent either way) and per-evaluation; what it costs is the author's sentence, the
`@ref` citation and the `<description>`, at export time, on both engines. Both images are equally
loud in the FIDELITY REPORT, which carries `D-REFUSE` either way.

**Ruled 2026-09-05: D1's image stands.** The KIE warning is real and one-engine-only and
per-evaluation; what omission costs is the author's sentence, the `@ref` and the `<description>`,
at export time, on both engines. Meng saw both sides and kept the row. Should this ever be
revisited, the change is one arm of `datedTable`'s `ruleSpecs` and its goldens, and it would be an
amendment to §11.9.1 rather than a second image alongside it.

**One distinction D6 draws that the recount does not, folded in from the rulings branch 2026-09-05.**
These ten are not one population, and the migration must classify per site rather than sweep. Some
say _the law was not in force_ — `regcf.l4:143`, `dmn/gst-rate.l4:65`, `dmn/ymd-dates.l4:86`, the
five fixtures — and belong in the gate row. Two say _this encoding does not carry that period_:
`regcf-denovo.l4:211` ("no encoding of Part 227 exists for rule dates before 2022-09-20") and
canon's `sg-csp.l4:79`, whose own comment at `:70-78` says the encoding lacks the earlier rates.
Those are the `REFUSE` row of R7's taxonomy, not the gate row, even though both are guarded on a
date — and canon's is guarded on the **child's date of birth**, not on `RULES EFFECTIVE DATE`, so no
rule-version axis can answer it at all.

### 11.10 R10 — Backends. RULED 2026-09-04 (marked accept).

The transitive read-set pass lands first; the schema is keyed by (name, tier) with `x-l4-tier`;
check rejects an explicit parameter sharing a name with a discharged implicit; defaulted implicits
are not `required`; `BatchRequest` gains a `world` object; discharged implicits trail positional
parameters; OpenFisca puts scalar implicits in `parameters(period)` and refuses record ones;
`imaginary-alcohol-act.l4` migrates as fourteen scalar section `GIVEN`s. Detail:
`PROPS-REDTEAM-2026-09-03.md` §2.10.

#### R10's cost, measured outside this tree — 2026-09-07

R10 is ruled and unbuilt, so the backends still lower the module the author wrote (the _Deferred_
list under §11.16 says why that was the right sequencing). For Catala that is not degraded fidelity
but a **refusal**: a section `GIVEN` read by anything other than the exported decision itself does
not compile at all.

The mechanism, verified on `unstable` `30bbc026`. The parser elaborates a section `GIVEN` into a
0-ary `ASSUME` at the head of its section (`jl4-core/src/L4/Names.hs:61-65`); `collectAssumes` picks
that up like any other (`jl4-core/src/L4/Catala/Lower.hs:2116-2126`); and `assumeRef` rejects a read
wherever `cxAssumeOK` is `False` (`:1677-1683`), which is everywhere except inside an exported
decision's scope — `True` at `:1088`, `False` at `:387` for the toplevel and `:1208` for a helper.
`scopeCall` refuses the same thing one call deeper (`:1689-1691`).

Reproduced here on a three-declaration probe — a section `GIVEN`, a plain helper that reads it, an
`@export` decision that calls the helper — run on the `l4` built at `9d6536a9` with its embedded
prelude:

```
l4 catala: cannot compile these decisions to Catala:
  - in `the rank of the teacher`: ASSUMEd input `the teacher` is only readable inside an
    @export decision's scope (where it becomes a scope `input`); pass it to this helper as
    a parameter instead (pay.l4:10:5-18)
```

Exit 1, and no output file is written. **The refusal has an escape hatch, which is worth stating
because it changes what R10 is worth.** Marking the helper `@export` too lifts it, and the emitted
Catala is correct: the binder becomes an `input` on every scope and the caller threads it
(`output of TheRankOfTheTeacher with { -- the_teacher: the_teacher }`). So the construct is not
unusable under Catala — it costs one published scope per rule that reads the binder, where the
author wanted a helper. R10 buys back the helpers, not the ability to compile at all.

The `ofek` session then took that further than this probe could, and the result is worth recording
with its provenance, because the two halves were measured on different machines. It ran
`catala typecheck` on the emitted module (successful — the hatch is not merely well-formed text, it
passes the next tool), and then marked all 28 definitions taking a `GIVEN` in the real module:
**43 scopes emitted, `catala typecheck` successful, and the six worked cases return the same six
figures as the shipped single-`@export` build, digit for digit.** That turns "one scope per reader"
from a three-declaration probe into a whole-module measurement, and it retracted a claim on that
side — the row's fork register had carried F13 as "`@export` is not composable", now restated
(canon `64f6c02` on `mengwong/drafts`). The 28-export whole-module run is theirs; everything else
in this section has been reproduced here.

> **Correction, 2026-09-07.** An earlier revision of this section said "no `catala` toolchain exists
> on this machine". That was false, and it was written into three places before anyone checked it.
> `catala` and `clerk` 1.2.1 are installed here, in a **named opam switch** — `~/.opam/catala/bin`
> — so a bare `which catala` fails and looking in `~/.opam/default/bin` finds nothing. The slip
> underneath was inferring a separate machine from a separate session: the session that measured the
> Catala side is a peer on this same host. Anyone repeating this work: put
> `~/.opam/catala/bin` on `PATH`, and note that `catala typecheck` run outside a project directory
> fails with _"The standard library module Stdlib_en could not be found"_, which reads like a broken
> install and is not — run `clerk start` in a scratch directory first, as `etc/validate-catala.mjs`
> does.

> **CLOSED 2026-09-08 — the check now exists; see §11.10.1 below.** Everything from here to the end
> of this subsection describes the tree as it stood at `6e9b57bb` and is kept because it is the
> measurement that motivated the fix. Read the present tense in it as "before 2026-09-08": `l4
catala` no longer exits 0 on this shape.

**The hatch has an all-or-nothing condition, and `l4 catala` does not check it.** An `@export`ed
rule is published as a Catala _scope_, and Catala allows a scope call only from inside another
scope. One non-exported rule anywhere in the chain lowers to a toplevel definition, and the scope
call lands inside it. Reproduced here on their eleven-line witness — an exported `the base`, a plain
`the middle` that calls it, an exported `the pay` that calls `the middle`:

```
declaration the_middle content decimal
  depends on the_n content decimal
  equals ((output of TheBase with { -- the_n: the_n }).the_base + 1.0)
```

`l4 catala` **exits 0 and writes that file**; `catala typecheck` then rejects it with _"Scope calls
are not allowed outside of a scope"_ at `chain.catala_en:23.11-55`, exit 123, on `catala` 1.2.1.
Measured here, and independently in the issue thread
([#958 comment](https://github.com/smucclaw/l4-ide/issues/958#issuecomment-5571825701)).

**The control is what pins the diagnosis, and it is worth stating because the obvious reading is
wrong.** Delete the middle definition and point the second export at the first directly, leaving
_both_ `@export`s in place: `l4 catala` exit 0, `catala typecheck` exit 0, `Typechecking
successful!` — run here on a two-definition module. So the fault is not "two exports in one module"
— it is the non-exported definition routed between them. A module may export as many
rules as it likes. That distinction is exactly what the missing check would encode, and it is what
the current failure gives the reader no way to reach.

For a section `GIVEN` the condition is close to free,
since every reader of the binder has to be exported anyway; for anyone applying the hatch to an
ordinary helper it is the whole story, and nothing on the L4 side says so. **This is the upstream
candidate, and it is the silence rather than the composition** — the machinery to refuse is already
there and well-aimed at the adjacent case; it simply does not ask whether an exported helper has a
non-exported caller. The cost of the silence is not only the invalid file: that encoding's fork
register carried "`@export` is not composable" — false, and derived from exactly this failure — and
was believed for three days before the control retracted it (canon `64f6c02`). A diagnostic naming
the non-exported caller would have prevented the wrong lesson as well as the bad output, which is
the stronger argument for making it a refusal rather than a warning. **Filed upstream as
smucclaw/l4-ide#958**, with the eleven-line witness and a
suggested fix (walk each exported definition's callers, and `bad` a non-exported one in the same
voice as the `ASSUME` refusal). R10 does not close it: R10 removes the section-`GIVEN` refusal, and
this one is about `@export` composition and stays reachable.

**Why this is recorded here rather than left in the backlog.** The cost is now being paid by an
encoding outside `l4-ide`. The Israeli teachers' pay row in `legalese/canon`
(`subjects/il/ofek-hadash-2008`, `NOTES.md` §11, commit `d082a4e` on `mengwong/drafts`) declined the
section `GIVEN` for exactly this reason: its ninth module _is_ the Catala deliverable, and the `§`
heading where the repetition is worst carries ten identical `GIVEN`s. Its note calls the construct
"unusable" there; the probe above says the sharper thing, that it is usable at the price of
publishing ten scopes where the author wanted ten helpers — which for that row is the same decision
and a better reason for it.

Four things follow, and no more than four:

- **Catala's failure mode is refusal, not lost fidelity** — recoverable, but only by exporting
  every reader. Whether the other five backends degrade or refuse on the same shape is unmeasured;
  this note claims no ordering among them.
- **The phrasebook's remedy does not reach this case.** `writing-l4-rules` entry 11.9 answers the
  arity-zero problem with a `GIVEN`-parameterised twin per section rule — but the section's own
  delegating rule still reads the `ASSUME`, so under Catala every such rule would have to be
  `@export`. Entry 11.9 now says so.
- **The twin's unit is rules-exercised, not sections**, which the same row measured: 263 `#ASSERT`s
  across its nine modules — 254 of them in the eight hand-written ones, the ninth being generated —
  each handing a case in explicitly and so each needing its own twin, alongside five call sites in
  two other modules for the three rules under one `§§` heading. Entry 11.9's "one extra delegating
  rule per section is a much smaller price" is true for the statute shape it was written against and
  false for an arithmetic cascade; it now says which shape it means.
- **A user-facing page said this worked.** `doc/reference/syntax/section-given.md` listed "every
  export backend … treats a section `GIVEN` as it treats an `ASSUME` term" under _What else works_.
  That sentence is true of the mechanism and misleading about the result, because for Catala
  treating it as an `ASSUME` term **is** the refusal. Corrected in the same change, with the
  diagnostic on the page — §6 of `CLAUDE.md` asks a page to state its limits, and a limit filed
  under what works is worse than one left out.

#### 11.10.1 smucclaw#958 — ANSWERED 2026-09-08, built. See §8.1 of `CATALA-EXPORT-SPEC.md`.

`l4 catala` now refuses the composition instead of emitting it. The refusal names the callee, the
caller (via the enclosing `vIn`), and the remedy; exit is 1 and no file is written:

```
l4 catala: cannot compile these decisions to Catala:
  - in `the middle`: `Chain.the base` is @export'd, so it compiles to a Catala scope — and Catala
    allows a scope call only from inside another scope. This caller is not @export'd, so it
    compiles to a toplevel definition, and the call would land outside any scope (`catala
    typecheck` rejects that with "Scope calls are not allowed outside of a scope"). Mark this
    caller @export too — every rule along the chain has to be exported, not just the one being
    called — or inline `Chain.the base` here (R1, §8.1). (chain.l4:10:22-39)
```

**What the measurement changed about the diagnosis.** §11.10 above proposed "walk each exported
definition's callers, and `bad` a non-exported one". The built check is the dual of that and
strictly cheaper: refuse at the **call site**, where the caller's context is already in hand, rather
than computing a caller relation. No new traversal, and it cannot miss a call the lowerer reaches.

**Two things the pre-fix note did not know, both found by building it:**

1. **There were two emission sites, not one.** `scopeCall` guarded only `not (null ssAssumes) && not
cxAssumeOK` — so a callee with _no_ ASSUMEs was never checked at all. The second site is
   `fnRef1`, the combinator arm where R5 absorbs `map f xs`; it carried **no** context check
   whatsoever. Measured on the pristine tree at `6e9b57bb`: `l4 catala` exit 0, silent, emitting
   `(Decimal.sum of (map each item_double among xs to (output of Double with { … }).double))`, which
   `catala typecheck` rejects at the same error. A fix keyed to the direct-call path alone would
   have left it reachable. Both are pinned by their own fixture under
   `jl4/examples/catala/not-ok/`.
2. **The guard could not be `cxAssumeOK`.** An R7 `#[test]` scope IS a Catala scope — it may call
   one, and doing so is the whole of R7 — but it declares no inputs, so it may not read an `ASSUME`.
   `cxAssumeOK` is `False` in a test body, so keying the refusal on it would have refused every test
   scope the emitter produces. The two questions are now separate flags (`cxInScope`,
   `cxAssumeOK`), and the four-way table is in the haddock on `cxInScope`.

**What review changed.** The split also repaired both `ASSUME` refusals, which ended "not from a
toplevel helper" in a context where the caller is a test scope, not a helper. That wrong half had
reached a committed golden. It now says a test scope declares no inputs, which is the actionable
fact.

**Coverage the fix had to create before it could be trusted.** No `.l4` under
`jl4/examples/catala/` contained an `ASSUME` or a section `GIVEN` — zero of twelve, enumerated — so
while `collectAssumes` and `assumeClosure` do run on every module, nothing in the tree ever ran them
on a **non-empty** input, and §11.10's whole-module measurement (made outside this repo) was the
only evidence the `ssAssumes` threading worked at all.
`jl4/examples/catala/export-chain.l4` is now the positive twin of the refusal fixtures: a section
`GIVEN` with every rung `@export`ed, pinning that the binder becomes a scope `input` and that
`assumeClosure`'s fixpoint carries it **transitively** (`the top` never names the binder, reaches it
only through `the middle`, and must still declare and forward it). Validated by the real toolchain,
not merely goldened.

**Still open, found while building and deliberately not fixed here.** R7 cannot test a
binder-carrying scope at all: a `#[test]` scope declares no inputs, so a `#EVAL` of any rule that
reads a section `GIVEN` is skipped with a note rather than emitted. `export-chain.l4` carries such a
directive on purpose so the note appears in a committed golden rather than being rediscovered. The
consequence is that `clerk test` coverage is silently zero on exactly the modules the binder
machinery exists for — the same _shape_ of defect as #958 (a silence, not a wrong answer), and a
candidate for its own issue.

**The R9 harness now has a way to fail.** `etc/validate-catala.mjs` skipped and exited 0 whenever
the toolchain was absent, with no way to distinguish that from a pass, and it ran nowhere in CI —
`grep -rn catala .github/` returned nothing. It gains `CATALA_CHECK_REQUIRED=1` (the
`KIE_CHECK_REQUIRED` pattern), and `pr-checks.yml` gains a `catala` paths filter plus a
`catala-validate` job. The filter is the load-bearing half: a hand-edited `.catala_en` golden or a
new `.l4` under `jl4/examples/catala/` previously matched **no** filter in that file, so such a PR
ran no Catala-aware job — only the four unfiltered ones — and merged green. The job itself skips on a hosted runner — ubuntu-latest has no OCaml
catala and R9 forbids a hard dependency — and its header says so, so a green tick is not misread as
validation.

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

> **A third thing, found later. 2026-09-08: the sweep converted one line it should not have.** > `legal/regcf/regcf.l4`'s `the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here`
> is a **refusal-role** `ASSUME` — a deliberate bottom, of the kind §11.1.2 kept six files on, and of
> exactly the kind the same file documents two hundred lines earlier for its sibling marker. `978d9f83`
> made it a section `GIVEN` along with the other 45 sites, which put a marker that no input is ever
> routed through into the discharge population, and therefore into a read-set that crosses an
> `IMPORT`. It surfaced only when §11.19's refusal was built and named it. Reverted; the reasoning is
> in §11.22. **The lesson for any future sweep: "is an `ASSUME`" is not the test — "is an input" is,
> and the two are distinguishable only by reading what the name is for.**

**Status 2026-09-05: built on branch `props/assume-sweep`, rebased onto `props/opaque-declare`
(PR #335), NOT merged.** _Update 2026-09-06: merged as PR #337 (`b4fc3913`); the trees it held
back, the type and refusal roles, and the `overload` guard's lifting all landed with §11.1.2._
Everything below describes that branch as it was. The migration is
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
against **the type the name resolves to in the caller's scope** — not the binder's declared
type, which this sentence claimed until 2026-09-07 and which was never true; see R-X2 in §11.20 —
and records it with a negative index
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
**Refuted 2026-09-07 (R-X2, §11.20).** The argument is sound about answers a working
program already gives and silent about whether the program it turns the error into
is well-typed. It is not: the value is typed against the caller's resolution of the
name and delivered by spelling to a binder whose `typ` is never consulted, so
`l4 check` passes a `STRING` into a `GIVEN rate IS A NUMBER` and `l4 run` returns it
from a rule declared `GIVETH A NUMBER`. smucclaw/l4-ide#956.
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
the boundary ~~and the imported module's own `TYPICALLY` (or "assumed term")
applies~~. That is the remaining half of §2.2's "discharge happens at the module
boundary", and it is deferred. `ok/section-given-import-def.l4` and
`ok/section-given-import-call.l4` pin both the fix and the limit.

**Corrected 2026-09-05 — the conclusion holds, the message does not.** The
struck clause is a reasonable inference and it is kept, because the cost of
deleting it is that nobody learns the search term is wrong. **Predicted:** the
imported module's own `TYPICALLY`, or failing that "… is an assumed term".
**Measured:** neither. That binder carries no `TYPICALLY`, and the observable on
the corpus's own witness is a **`CONSIDER` exhaustiveness failure** — the
binder's value flows into `regcf-wizard.l4:345`'s three-arm `CONSIDER` and
matches no arm:

```
The value
  `the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here`
reached a CONSIDER that has no branch for it.
```

**How it was produced**, on `origin/unstable` `063ddd34` with that tree's own
binary — the arm needs a rule date inside the COVID window _and_ an aggregate
above tier 1 and at most 250,000 (`regcf.l4:510-513`), so both have to be forced:

```
l4 batch regcf-wizard.l4 -e 'raise check' -i plan.json   --fixed-now 2021-06-01T00:00:00Z          # aggregate 200000
```

**Severity is unchanged and "loud, not silent" stands** — `"status":"error"`, no
wrong answer. What changes is what a reader greps for: **anyone searching logs
for `assumed term` to find this class will miss every instance.**

**And the same row passes `--validate-only`.** `{"status":"valid","errors":[]}`,
because the export schema demands only the export's own record parameter
(`plan`) and never the imported binder — a green validate in front of a red run,
on the wizard. That half is recorded as `OPEN-FINDINGS-2026-09-05.md` **OF-7**,
which owns the defect; this section owns the ruling and the limit.

#### Deferred, each with why

- **Discharge does not cross `IMPORT`.** §2.2 says nothing implicit should, and
  the pass is per module, so an imported definition keeps the arity its own
  module gave it. Unreachable today: no file in `jl4/examples`,
  `jl4-core/libraries` or `doc/` that declares a section binder is `IMPORT`ed by
  another (measured 2026-09-05), no library declares one, and the sweep's own
  measurement is that none of its 46 headingless `ASSUME` files is imported
  either. If it is ever reached the failure is loud — a length mismatch naming
  the callee — not a wrong value. **Reachable outside this tree, 2026-09-07:** the
  `legalese/canon` row `subjects/il/ofek-hadash-2008` would have had a declaring
  module imported by two others had it adopted the construct, and declined it for
  the Catala reason in §11.10. The measurement above is scoped to this tree and
  stands; what has changed is that the class is no longer hypothetical. If we want
  it exercised, it wants a compiler test, not a corpus row.
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

> **What the unbuilt state surfaced as, measured 2026-09-07.** A caller in another module that
> supplies the binder by name gets `IllegalAppNamed` — _"You are giving named inputs to … but it is
> not a function, so it takes none."_ **That is not this ruling being implemented, and an
> implementer should not mistake it for one.** The error constructor predates the whole programme
> (`73947f0a`, 2025-01-09, Andres Loeh, "Add type- and scope-checking"); what routes to it is
> props-era. **Attribution corrected 2026-09-08:** this paragraph and the commit message of
> `b177feba` both said `294867c7`, 2025-03-17, PR #221. `git show 294867c7 | grep -c IllegalAppNamed`
> is **0** — that commit is the CLI-to-language-server refactor, and it moved `TypeCheck/Types.hs` to
> its current path, which is how a `git log -1 -- <path>` reading picks it up. The claim it supports
> survives and widens: 20 months before this programme, not 18. `inferAppNamed`
> (`TypeCheck.hs:3343-3358`) lets a 0-ary definition take named arguments only when every name
> passes `isSectionBinderSupply`, and that predicate asks `sectionBinderNames` — **this module's**
> binders. Across an `IMPORT` the callee's binder is not in the caller's set, the guard fails, and
> control falls through to the pre-existing message.
>
> So the diagnostic is not merely unhelpful, it is wrong about the cause: the callee _is_ a function
> of that binder in its own module, and the caller simply cannot name it. The refusal this section
> rules has to say that, which the existing message cannot be made to do — it is a different error.

**Ruling (with R13/R14, card `D5-computed-fields-purity`, option A′).** The measurement pass that
discharged §5.3 turned up a hole, and it is **filed as a defect rather than silently absorbed**.
What is ruled here is the **ordering, not a preference: the first required move is the REFUSAL, not
the closure.** `l4 check`/`l4 batch` must refuse an export whose read-set crosses an `IMPORT` before
the closure is allowed to find one — because closing the collector over imports on its own converts
a false green into a **demanded-then-silently-ignored** parameter, which is worse than the state it
replaces.

**Ruled 2026-09-05. The REFUSAL — the first move — is BUILT 2026-09-08. The closure, the second
move, is not, and remains R-X3's ruled end state.**

`Export.validateExportImplicitImports` refuses an `@export` whose transitive closure reaches a
definition in an imported module with a non-empty read-set, as the new check error
`ImplicitCrossesImport`. It is a **new, distinct** constructor with its own message, not a reroute of
`IllegalAppNamed`, for exactly the reason the blockquote above gives.

**How an importer can see a dependency's implicits at all**, which this section had not settled:
nothing already crossing the boundary carries them. `EntityInfo` holds the type a callee was
_checked_ with, and discharge appends its trailing parameters afterwards, so the type never records
them; `sectionBinderNames` is reset at the boundary by design. So this change adds the one fact that
has to cross — `CheckResult.implicitReaders`, merged by `unionImportedCheckEnv` into
`CheckEnv.importedImplicitReaders`. That is a `Set Unique`, not an AST: the importer learns _that_ a
callee has implicits, never _which_, which is all a refusal needs. Both merge sites
(`LSP.L4.Rules`, `L4.Import.Resolution`) were updated, as that function's own haddock demands.

**It took three sources, not one, and the second and third were each a measured hole.** The first
build used only `Map.keysSet (readSets …)`, and an adversarial pass broke it twice on 2026-09-08:

1. every definition with a non-empty read-set — the obvious one;
2. **every section binder itself.** The elaboration is a 0-ary `ASSUME`, and `readSets`' keys come
   from `decideBodiesFromModule`, which matches only `DECIDE`. So an `@export` in the importer that
   named the imported **binder** directly went unrefused — and because the probe's binder carried a
   `TYPICALLY`, it answered a wrong number with `"status":"success"`. Fixture
   `not-ok/import/binder-refused.l4`;
3. **every definition that reaches an already-imported reader.** A module in the middle of a chain
   (`A` imports `B` imports `C`, only `C` declares a binder) has no binders of its own, so its
   `sectionBinders` is empty, so `readSets` returns `Map.empty` and it contributed nothing. `A`'s
   export then validated a row it could not evaluate — **one hop further out than the defect this
   refusal was built for, and silent rather than loud.** Fixture
   `not-ok/import/chain-refused.l4` with `implicit-rate-wrapper.l4`.

**That third probe settles a question this section left open.** Its closing note said the review's
headline — that a `TYPICALLY` makes the failure a silent wrong answer — was "unestablished". It is
established now: `l4 batch` answered `"status":"success"` with the library's own default while the
value supplied under that name was accepted into the row and dropped. Established on the tree
_with the fix in place_, before source 3 was added.

**Gated on `@export`, deliberately.** An ordinary cross-`IMPORT` call of a reader works — §11.16's
`matchGivens'` fix made it work, and `ok/section-given-import-call.l4` pins it. It is the export
_boundary_, where a row of JSON meets a schema, that has no way to represent the input. A refusal
that fired on any cross-`IMPORT` call would turn that shipped fixture red; that was checked before a
line was written.

**Corpus fallout, measured 2026-09-08.** Exactly one shipped file:
`jl4/examples/legal/regcf/regcf-wizard.l4` (6 `@export`s, not the 8 OF-7 records), one export
(`raise check`). Repair and its reasoning in §11.22. All 458 files under `ok/`, `legal/`,
`jl4-core/libraries` and `doc/` were then re-swept: zero errors, zero firings.

Fixtures: `not-ok/import/{export,binder,chain}-refused.l4` with their libraries
`implicit-rate-lib.l4` and `implicit-rate-wrapper.l4` — a new corpus family, because a cross-`IMPORT`
refusal needs files sharing a directory (imports resolve importer-relative) of which only some may
fail, which no existing glob can express. Page:
`doc/reference/syntax/section-given.md`, "Across an `IMPORT`", which described the unrepaired state
in the present tense and now describes the refusal.

**The defect record — mechanism, probe, both halves, exposure — is
[`OPEN-FINDINGS-2026-09-05.md` OF-7](./OPEN-FINDINGS-2026-09-05.md), not this section.** It was
moved there 2026-09-05 because a defect that spans `Export.hs`, `Batch.hs` and `Print.hs` was never
a props-spec section, and because `OF-7` is a stable id while a §11 number is not: three branches
appended to §11 on one day and collided. **Cite `OF-7` for the defect and §11.19 for the ruling.**
Also recorded in `PROPS-REDTEAM-2026-09-03.md` §7.

**R-X3, 2026-09-07 (§11.20): the closure is the END STATE, and this section's ordering stands.**
Meng accepted "make the import transparent — the caller's value reaches the binder" on the
post-review bench. That is the closure this ruling already permits as the second move; the refusal
remains the first, for the reason given above and now measured twice more (the review's finding 4,
and the GM's own three-shape re-run, in which every shape returned `{"errors":[],"status":"valid"}`
for a row missing the imported binder). One thing the re-run did NOT confirm: the review's headline
that a `TYPICALLY` makes the failure a silent wrong answer. The GM's shapes failed loudly, two
different ways. The schema half is certain; the silent half is unestablished.

### 11.20 R-X1–R-X6 — the post-review bench. RULED 2026-09-07.

Six cards, "What the Review Left Open" (an artifact, **not in the tree**,
<https://claude.ai/code/artifact/1fdea3d4-eec3-4c06-a53c-25e3f4f9d35e>, db collection
`fix-rulings`), put to Meng after the adversarial review of `unstable` `caf6e656` (workflow
`wf_1f3eeb1e-5ca`: 56 agents, eight dimensions, two refuters per material finding; 23 survived, 1
killed, 9 unverified). Marked 06:34–06:39 UTC. Notes verbatim. **Cite R-Xn, not the section number.**
R-X5 and R-X6 concern the regulative window and are recorded in
`EVERY-EACH-QUANTIFIER-SPEC.md` §5.1.2.

| id   | question                              | mark       | ruling                                                                                                                                                                        |
| ---- | ------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R-X1 | does wave 3 (`unstable`→`main`) wait? | **accept** | Waits for R-X2 and R-X3 to be built. A release decision; also in the GM register and told to the merge manager.                                                               |
| R-X2 | how the `WITH` type check is fixed    | **accept** | Option c: check the supply against the **binder's** declared type AND build R3's per-root check (§11.4). One job, one confusion.                                              |
| R-X3 | cross-`IMPORT`: silent or loud?       | **accept** | Option b, the closure, as END STATE. §11.19's ordering stands: refusal first. See the note under §11.19.                                                                      |
| R-X4 | the `@export` gate, reframed          | **accept** | Option a: gate on **arity**; both spellings refused at check time. _"let's come back to this and backlog B for future work."_ — B is the predicate-as-row export, backlogged. |

**What decided each.**

- **R-X1.** The top finding is `l4 check` certifying a wrong-typed program (#956). Silent, not loud,
  which is the difference from known-defect releases shipped before.
- **R-X2.** The card first recommended option a alone; the GM moved it to c after measuring the
  991/11 swing on `ok/section-given-bridge.l4` (§11.4 note). The row reading, discussed the same day:
  `Discharge` already elaborates the read-set into a trailing record of parameters, closed and
  computed bottom-up, so this is the missing **type** of that record, not a new mechanism. R3's
  hybrid — child shadows ancestor, siblings must be distinct per root — is the row's well-formedness
  condition. **BUILT 2026-09-08**, both halves in one change as the ruling required: §11.4 for the
  per-root check, §11.22 for the call-site type check.
- **R-X3.** See §11.19. The card omitted §11.19 because it was written before that section was
  re-read; recorded here so the omission is not repeated. **The refusal is BUILT 2026-09-08; the
  closure — the accepted end state — is not.** The ordering held: nothing about the collector
  changed.
- **R-X4.** Measured by the GM on `blawx/antisocial.l4`: `Check succeeded`, then `--validate-only`
  demands eleven fields including `'is authorised'` and `'conduct'` — predicates over a `Person` —
  and a full row dies inside `antisocial.l4.batch1.l4` with "multiple definitions for the identifier
  effect … of type Consequence / FUNCTION FROM InputArgs TO Consequence". Cause:
  `checkAssumeFunctionInputs` (`Export.hs:672-679`) binds `MkAppForm _ paramName _ _` and tests the
  declared `ty`, discarding the argument list. Three shipped files, 18 `@export`ed rules, none
  invocable. §11.1.2's reason for keeping six files on `ASSUME` was true only of `l4 check`.
  **Backlogged (Meng's note):** teach the export path to take a predicate as an enumerated row of
  values. **BUILT 2026-09-08 — see §11.21**, which also records the count the estimate missed (five
  files, not three) and the second meaning of `@export` the build ran into.

### 11.21 R-X4 as built — the arity gate, and the second meaning of `@export` it exposed. BUILT 2026-09-08.

Branch `props/rx4-export-arity`, cut from `unstable` at `6e9b57bb`. Cite **R-X4** for the ruling
(§11.20) and **this section** for what the build found.

#### What shipped

- **The gate is keyed on the assumed name's arity.** `checkAssumeFunctionInputs`
  (`jl4-core/src/L4/Export.hs`) no longer discards the app form's argument list. An `ASSUME` read by
  an `@export`ed `DECIDE` is refused when it has arguments on its head, when its declared type
  contains a function, or both. The type half is unchanged and still uses
  `isFunctionTypeExpanded` — not an arrow-spine count — because `MAYBE OF FUNCTION FROM A TO B` has
  no spine and is just as unsendable.
- **A second constructor, not a widened one.** `ExportAssumeArityInput Resolved Resolved Int`
  (`jl4-core/src/L4/TypeCheck/Types.hs`). Reusing `ExportFunctionTypeInput` would have printed
  "has a function type" for an `ASSUME` whose declared type is literally `BOOLEAN` — false, and the
  kind of false that sends a reader to fix the wrong thing. The `Int` is the assumed rule's **total**
  arity: app-form arguments plus the arrow spine of the declared type, added, because
  `ASSUME f x IS A FUNCTION FROM B TO BOOLEAN` really is a rule of two inputs and
  `L4.Relational.Lower.assumeDef` already flattens them in that order.
- **The message names the rule, the export, the count, and three ways out** — define it, take its
  subject as an ordinary input, or drop the `@export`. `l4 check` on
  `jl4/examples/blawx/not-ok/arity-two.l4`:

  > The @export rule `qualifies` reads `severity exceeds`, which is assumed and takes 2 inputs of
  > its own. / A published rule's inputs travel as JSON, which can carry a value but not a rule, so
  > an assumed rule with inputs of its own can never be supplied — every request would stop on it. /
  > Give `severity exceeds` a definition (DECIDE or MEANS), or take what it is asked about as an
  > ordinary input of `qualifies`, or remove the @export.

- **Nine cases in `jl4-core/test/ExportValidationSpec.hs`**, including the two that keep the gate
  honest in the other direction: a nullary `ASSUME` is a value and still passes, and an app-form
  `ASSUME` no export reads still passes. One asserts the arrow spelling is **not** reclassified — a
  widened gate and a re-labelled one are different changes and the suite can now tell them apart.

#### Measured

`l4 check`, binary built on this branch, `JL4_LIBRARY_PATH` pinned to this tree. Errors are the new
refusal; every one of these files exited clean before.

| file                                                   | refusals | was |
| ------------------------------------------------------ | -------- | --- |
| `jl4/examples/blawx/antisocial.l4`                     | 21       | 0   |
| `jl4/examples/blawx/alcohol.l4`                        | 14       | 0   |
| `jl4/examples/relational/assumed.l4`                   | 6        | 0   |
| `jl4/examples/relational/not-ok/assumed-signatures.l4` | 3        | 0   |
| `jl4/examples/blawx/not-ok/arity-two.l4`               | 2        | 0   |

Five files, not the three §11.20 estimated; the two extra are the `not-ok` fixtures, whose subject is
a _lowering_ refusal reached only after a clean type-check. Three further probes under
`p4-design/scratch/` are also refused; nothing in CI reads them
(`.github/workflows/pr-checks.yml:271-275 @ 6e9b57bb` says so in the author's own words).

**Not one of the five is inside a corpus golden glob** (`jl4/tests/Main.hs:79-92 @ 6e9b57bb`;
`etc/check-corpus-goldens.mjs:32-47 @ 6e9b57bb`). Their coverage is bespoke: the relational Debug
goldens, the committed `.blawx`/`.pl` pairs, and ~11 assertions in `jl4/tests-cli/Main.hs`.

#### What the build found: `@export` carries two meanings, and R-X4 splits them

To `l4 batch`, `l4 export` and `jl4-service`, `@export` means **publish this over JSON**. To the
relational middle end and the Blawx bridge it means only **root the lowering here** —
`L4.Relational.Lower.lowerModule` returns `LENoExport` for a module with no `@export` at all
(`jl4-core/src/L4/Relational/Lower.hs:2589-2606 @ 6e9b57bb`).

Those two readings were compatible only because the gate could not see the app form. Once it can,
they are not, and the collision is total rather than partial:

- An `@export`ed decision may not **read** an assumed rule — the read-set is transitive, so hiding it
  behind a helper does not help.
- It may not **take** one as a `GIVEN` either, in either spelling: `checkGivenFunctionInputs` already
  refuses the function-typed parameter.
- So **an assumed-predicate module cannot be exported at all**, and being unexportable it has no
  root, and having no root it cannot be lowered. The `ASSUME` → `RInput` widening, the `#abducible`
  interview inputs, and every fixture that pins them would have become unreachable from any
  compilable module — not by anything R-X4 ruled, but by a marker the two legs happen to share.

**Resolution as built, and it is a judgement call, not a ruling.** The two legs part company at
exactly the two diagnostics that are _about_ JSON. `isExportPublicationRefusal`
(`jl4-core/src/L4/TypeCheck/Types.hs`) names `ExportFunctionTypeInput` and `ExportAssumeArityInput`
and nothing else; `L4.Cli.Blawx.loadBlawxDoc` reads `Rules.TypeCheck` instead of
`Rules.SuccessfulTypeCheck` and re-imposes the same "no `SError`" bar **minus those two**;
`jl4/tests/RelationalExport.hs` and `jl4-core/test/BlawxAssumeSpec.hs` do the same in-process. Every
other error still stops all three.

The justification is not convenience. An assumed predicate is a perfectly good input to a logic
program — it is precisely what the Blawx leg turns into an `#abducible` the interview asks a person
about — and it is not a thing a JSON request can carry. Backlog B of R-X4 ("teach the export path to
take a predicate as an enumerated row of values") is the JSON side learning what the ASP side
already does; until it lands, the legs disagree, and the disagreement is now written down instead of
being an accident of which diagnostic the gate could see.

**What it does NOT do.** `l4 check`, `l4 batch`, `l4 export` and `jl4-service` all refuse, unchanged
and at check time, which is what R-X4 ruled. There is no way to publish one of these modules. A user
who runs `l4 check` on a Blawx seed is told plainly that it cannot be published, and a user who runs
`l4 blawx` on it still gets a `.blawx` file.

**Evidence that it is behaviour-preserving for the legs:** all eight committed Blawx goldens
(`antisocial`, `alcohol` and their record-spelled twins × `.blawx`/`.pl`) are **byte-identical** to
freshly generated output on this branch, and `jl4-core-test` is 536 examples, 0 failures — including
all twelve `BlawxAssumeSpec` cases that a plain refusal would have taken down.

**If Meng would rather not split them**, the alternative is one line: delete
`isExportPublicationRefusal` and its three call sites. The cost, measured rather than estimated, is
five corpus files, eight committed goldens, twelve `BlawxAssumeSpec` cases, two `RelationalExport`
goldens and ~11 `tests-cli` assertions, and the `ASSUME` → `RInput` widening becomes dead code until
backlog B. That is the trade, stated so it can be reversed on sight.

#### Found by review, and repaired

Two adversarial refuters were run against the first green build, with distinct lenses — one on the
gate's scope (does it refuse exactly the right set?), one on the step-over (does it leak into any
path that publishes?). Between them, 938 `.l4` files were swept and roughly forty hand-written
probes run. Three findings were repaired here; the rest are recorded below rather than absorbed.

- **The result type has two spellings and the gate read only one. REPAIRED.** An assumed rule can
  put its type after `IS A` — `ASSUME f x IS A BOOLEAN` — or in a `GIVETH` above a bare `ASSUME f`.
  The first build read only the `IS A` slot, so `GIVETH A FUNCTION FROM NUMBER TO NUMBER` above
  `ASSUME f`, with no term `GIVEN` to backfill the app form, was **not refused**: `l4 check` exited
  0, `l4 run` died on "it is an assumed term", and `l4 batch` reported "multiple definitions for the
  identifier f". That is precisely the false green R-X4 exists to close, surviving inside the fix
  for it. The same hole undercounted the arity of `GIVEN x IS A NUMBER` / `GIVETH A FUNCTION FROM
NUMBER TO NUMBER` / `ASSUME f x` as 1 instead of 2. `checkAssumeFunctionInputs` now resolves the
  result type as `mty <|> extractReturnType tySig`. Two cases pin it, and they pin the
  classification as well as the count: the `GIVETH`-only form is the arrow form written the other
  way round, so it is refused as `ExportFunctionTypeInput`, while the mixed form counts 2. The exposure was not
  hypothetical: `jl4/examples/ok/signatures.l4:20-21` and `jl4/examples/ok/tbd.l4:4-6` are written
  that way, and §11.1.2 names the `GIVETH`-headed form as one of the four shapes with no
  `ASSUME`-free spelling.
- **`jl4-service` logged the wrong cause. REPAIRED.** The deploy was refused either way — the new
  diagnostic falls into `blockingErrs` — but its `exportFnTypeErrs` comprehension matched
  `ExportFunctionTypeInput` alone, so an arity refusal was logged as "module has type errors".
  Both constructors now have their own text, and the log line no longer says "FUNCTION-typed".
- **`l4 blawx` printed 22 KB of error-severity diagnostics and exited 0. REPAIRED.** A wall of red
  followed by success reads as a command that failed and lied. It now says, once, how many
  diagnostics it stepped over, why they do not apply to Blawx, and that `l4 check` will report the
  same ones and exit 1.

- **The CLI test harness deadlocked on the new stderr volume. REPAIRED.**
  `runL4In` (`jl4/tests-cli/Main.hs`) read stdout to EOF with the strict
  `BS.hGetContents` and only then read stderr. A child that writes more to stderr
  than the pipe buffer holds — about 16 KB on macOS — blocks on that write, never
  closes stdout, and the parent never returns. `l4 blawx` on `antisocial.l4` now
  emits about 22 KB of diagnostics on a run that exits 0, and it hung the whole
  suite: no output, no failure, nothing to point at, twice, until the process was
  killed by hand. The harness now drains stderr on a forked thread. **This is a
  latent trap independent of R-X4** — any future command verbose enough on stderr
  would have sprung it — and it is worth knowing that the symptom is a suite that
  never finishes rather than one that goes red.

#### Found by review, NOT repaired — each with its witness

- **A `WHERE`-local `ASSUME` is invisible to the gate, in both spellings.** `allAssumesFromModule`
  (`jl4-core/src/L4/Export.hs`) walks `Section` declarations only, and a `WHERE`-local `ASSUME`
  lives inside a body expression. An `@export` over one checks clean and dies at every request on
  the assumed term. **Pre-existing, not a regression**: the arrow half behaved this way before R-X4
  and the app-form half was never refused at all. Fixing it means walking body expressions in the
  collector, which changes what `assumesFromModule` reports to the schema as well — that is backlog
  B's territory, not this branch's. Witness: `jl4/examples/ok/assume-in-where.l4` is the construct;
  the refuter's probes are `w02.l4`/`w03.l4`.
- **A module that IMPORTs a refused one is not itself blocked.** `l4 check` on the importer exits 1
  (it inherits the diagnostic) while `l4 batch` and `l4 export` on the same file exit 0, because
  `success = null errors` is computed per module (`jl4-lsp/src/LSP/L4/Rules.hs:718-730 @ 6e9b57bb`).
  Nothing refused is actually published — a wrapper that re-exports the refused decision fails at
  `l4 batch` — but it fails with the old stuck-term message, which is the failure mode R-X4 replaces,
  surviving one `IMPORT` hop. Same family as §11.19/OF-7, one hop further out. **Pre-existing
  dependency model; newly reachable for eight files.**
- **The refusal never reaches the VS Code deploy sidebar.** `l4/getExportedFunctions`
  (`jl4-lsp/app/LSP/L4/Handlers.hs:848 @ 6e9b57bb`) is served from a plain `TypeCheck` with no
  `.success` check, so a module with 21 red squiggles still lists five deployable exports; pressing
  Deploy is refused server-side. **Pre-existing code, newly reachable** — and worth saying out loud,
  because R-X4's stated point is to refuse at check time rather than at the first request, and the
  IDE is the one surface where a user starts a request and is not told.
- **`l4 format` and `l4 ast` proceed on any module that parses**, refused or not. Pre-existing, and
  neither publishes nor serves — but it makes "`l4 blawx` is the only verb that proceeds" false as a
  sentence, so it is written down rather than repeated. Every verb that publishes or serves was
  enumerated and exits 1: bare `FILE`, `run`, `check`, `trace`, `state-graph`, `nlg`, `verify`,
  `batch`, `batch --validate-only`, `render`, `export --to dmn`, `export --to bpmn`, `openfisca`,
  `catala`, `docassemble`, and the separate `jl4-schema` binary.
- **`l4 blawx --roundtrip` steps over the refusal and `l4 blawx --import` does not**
  (`recordOracles` keeps `SuccessfulTypeCheck`, deliberately — it evaluates). Unreachable today:
  `L4.Blawx.Lift` never emits an `ASSUME`, so no lifted module can carry one. Nothing pins that.
- **`isFunctionTypeExpanded` is exponential in a diamond of type synonyms.** Its `visited` set stops
  cycles but not re-visits along sibling type arguments, so 26 nested `DECLARE Sᵢ IS A Pair OF
Sᵢ₋₁, Sᵢ₋₁` make `l4 check` take 9 s and 28 make it take 30 s. **Pre-existing and untouched** —
  `checkGivenFunctionInputs` blows up identically at the base commit — and R-X4 in fact _reduces_
  exposure, because the `not (null args)` guard short-circuits before the call. Self-recursive
  synonyms do not hang: the type checker rejects them first.
- **The read-set is syntactic, so a dead branch counts.** ``IF FALSE THEN `rate for` m ELSE 0``
  is refused although no request could reach the assumed rule. Conservative over-approximation,
  identical to the gate it replaces; the message's "every request would stop on it" is literally
  false for that file. Accepted rather than repaired: a reachability-aware read-set is a different
  and much larger change.

#### Deliberately not changed

- **`assumesFromModule`** (`jl4-core/src/L4/Export.hs:302-317 @ 6e9b57bb`) still filters on the
  declared type alone, so an app-form `ASSUME` still contributes a wrongly-typed field to a schema.
  That collector is exactly what backlog B rewrites, and a module now has to pass the gate before it
  reaches the collector. Making it _drop_ app-form assumes instead would be worse, not better: it
  converts a loud refusal into the demanded-then-silently-ignored parameter §11.19 rules against.
- **`jl4-service/src/Compiler.hs`** is untouched. Its `exportFnTypeErrs` branch still keys on
  `ExportFunctionTypeInput` only; the new constructor falls into `blockingErrs`, which renders the
  full message and rejects the deploy. Correct outcome, generic log line — worth tightening, not
  worth a coupling now.
- **`p4-design/widening-plan.md`** is a design record, not a spec, so its narrative is left standing
  — but two of its instructions were actively misleading and carry dated corrections in place. `:341-343
@ 6e9b57bb` told a future reader to keep `validateExportInputs` and `assumesFromModule` symmetric
  as complements; after R-X4 the validator counts inputs and the collector reads the declared type,
  so restoring that symmetry would undo this change. `§9.1 @ 6e9b57bb` prescribed the app form as
  the spelling that "therefore passes", which is exactly what R-X4 refuses. Both now point here.

#### Owed

- Backlog B — the predicate-as-row export. Until it lands, the five files above are compilable to
  Blawx and not publishable as a web API, and every one of them says so in its own header.
- The split above wants Meng's yes or no. It is recorded here rather than in a PR description
  because a PR description is not where a decision lives.

### 11.22 R-X2's call-site type check, as built — 2026-09-08

R-X2 ruled two things built as one job. The per-root half is recorded in §11.4 and the cross-`IMPORT`
refusal (R-X3's first move) in §11.19; this section is the other half — the call-site type check, and
what building all three changed about the design as ruled. Ref for every line number here:
`6e9b57bb`.

#### What it does

`L4.TypeCheck.implicitSupply` used to check the supplied value against `resolveTerm`'s answer, and
`resolveTerm` answers **in the caller's scope**. Where two sibling sections each declare `rate`, the
caller's is the one it finds; the value is then delivered by unqualified spelling
(`Discharge.suppliesBinder`) to the callee's, whose declared type nothing ever consulted. It now
resolves the supplied name to **the binder the callee reads** and checks against that binder's
declared type.

**WHICH binder: only ever the module's ONE binder of that spelling**, and nothing at all the moment
two share it. The binder that actually receives the value is decided by `Discharge.suppliesBinder`,
which matches the spelling against the **callee's read-set** — a whole-module fact that does not
exist while a body is being checked. With one binder of that spelling in the module the read-set can
hold no other, so the two questions cannot disagree. With two, they can.

**The first build guessed, and the guess was wrong.** It ranked the same-spelled candidates by
`sectionProximity` from the callee's own section. An adversarial pass broke it in one probe on
2026-09-08: a callee under one heading that reads a binder declared under **another** — transitively,
through a helper — takes its value from the read-set's binder, while proximity picks its own
section's. The checker then validated against a type nothing would receive, **rejecting a program
that worked and accepting one that crashed**. That is #956 moved, not fixed, and it is why the rule
is now the conservative one.

**A second defect from the same pass, fixed rather than stood down from.** The binder's declared type
was `inferType`d in the **supply site's** scope. A type name can be declared per section, so a
`GIVEN r IS A Rate` under one heading and a `DECLARE Rate` under another are two different types, and
the caller's `Rate` was silently used. It is now resolved under the binder's own section path
(`local (\ e -> e { sectionStack = d.sectionPath })`).

**So the two-binder case is a known, documented gap**, not a claim of coverage: a value of the wrong
type can still reach a binder when two headings declare that name. Closing it needs the read-set at
check time, which is the closure R-X3 rules as the second move. `doc/reference/syntax/section-given.md`
tells the reader so, in the reader's terms.

**Why the declared type is read off the PARSE and not out of the environment**, which is the one
non-obvious part. `Desugar.elaborateSectionBinder` gives the binder a 0-ary `ASSUME` with an empty
`GivenSig`, and `mergeResultTypeInto` drops the declared type for exactly that shape — so the entity
the module-wide signature scan installs carries an **inference variable** until that `ASSUME`'s own
body is inferred, in declaration order. A supply site in an EARLIER section would therefore not check
against a type at all: it would unify against an unsolved variable, silently, and poison the binder's
type for the rest of the module. `Desugar.collectSectionBinderDecls` reads the parsed module, which
is order-independent, and `inferType` resolves the type at the supply site; every `DECLARE` it can
mention is already in scope, because `withScanTypeAndSigEnvironment` scans declarations before any
signature or body.

#### Measured, before and after

The witness as shipped is a **`WHERE` local shadowing a single section binder**,
`not-ok/tc/section-given-supply-type.l4`:

```l4
§ `Rates`
    GIVEN rate IS A NUMBER TYPICALLY 0.05
GIVETH A NUMBER
scaled MEANS 100 TIMES rate
GIVETH A NUMBER
bad MEANS scaled WITH rate IS rate
    WHERE
        rate MEANS "5 percent"
```

The name left of `IS` is the callee's input, declared `A NUMBER` on the heading. The expression right
of it is read where it was written, and a local shadows a section binder absolutely, so it is a
`STRING`.

|            | before                                                                                                         | after                                                                                            |
| ---------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `l4 check` | clean                                                                                                          | a type error at the expression, naming the `GIVEN` line it must fit and the callee that reads it |
| `l4 run`   | **"Internal error … running bin op with invalid operation / value combination. Please report this as a bug."** | not reached; refused                                                                             |

"Before" was measured on **two independently built binaries at `6e9b57bb`** — the `props-rx4` and
`every-runtime` worktrees — because one stale binary is not a control.

**A second, softer effect, recorded because it is not a refusal.** Where the fix applies, the
corrected **expected** type also steers the type-directed resolution of the expression right of `IS`,
so a probe that had been delivering a string to a number resolved the right value and answered
correctly. A silent wrong answer becoming a right one, not a green build becoming red. The same
mechanism has a shadow side inside the documented two-binder gap: an adversarial pass showed a bridge
there can go **vacuous**, the right-hand name resolving to the callee's own binder so the writer's
value is discarded with no diagnostic. Not fixed here; it needs the read-set.

#### Two things the build changed about the design as ruled

**1. The supplied name resolves to the binder, not to the caller's scope — and that was not
optional.** An earlier version kept `resolveTerm` and substituted only the type. It refused the wrong
program, but with the **wrong diagnostic**: `resolveTerm` forks over the candidates and lets the
branch that succeeds downstream win, and with the expected type pinned, _both_ branches failed
identically, so the fork surfaced `AmbiguousTermError` — "there are multiple definitions for the
identifier `rate`" — for what is a plain type mismatch. Resolving the name to the binder directly
removes the fork, and gives the message in the table above.

It is also what `Discharge.suppliesBinder`'s own comment had been compensating for since the review:
_"the name to the LEFT of `IS` is one of `g`'s implicit inputs, but `L4.TypeCheck.implicitSupply`
resolved it in the CALLER's scope to get its type — so when two sibling sections both declare `foo`,
its `Unique` is the caller's and never matches the callee's."_ In the singleton case it now matches.
**The spelling fallback is not dead** — it still carries every two-binder case, which is exactly the
gap above — but it is no longer what the common case depends on.

**2. R3 turned out to have two shapes, not one.** See §11.4: an `@export`'s read-set is tested
unconditionally, a `WITH` supply's callee is tested when the supplied name matches one of two
same-spelled binders, and a bare directive is not tested at all. Named here because the halves were
built together and a reader of one will look for the other.

**3. The refusal needed three sources of `implicitReaders`, not one.** See §11.19. Two of the three
were holes an adversarial pass measured after the first build passed its own gate.

#### The corpus repair the refusal forced, and what it says about the sweep

The refusal fires on exactly **one** shipped file, measured 2026-09-08: `legal/regcf/regcf-wizard.l4`,
export `raise check`, reaching `regcf.l4`'s `financial statements required`. That is OF-7's own
measured probe, so the check found the thing it was built to find.

`regcf.l4`'s binder is **refusal-role**, and the file says so about its sibling two hundred lines
earlier:

> `ASSUME` makes this a deliberate bottom: an arm that reaches it stops evaluation with
> "… is an assumed term", naming this binding. … This is not the deprecated module-parameter `ASSUME`
> style: no input is ever routed through it.

`the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here` was written that way —
introduced as an `ASSUME` in `30ae2bde` (2026-07-29) — and the sweep, `978d9f83`
("migrate legal/ ASSUME to section GIVEN, 46 sites, 6 files"), converted it along with the rest. That
was a **mis-classification**: a deliberate bottom is not an implicit input, and turning it into a
section `GIVEN` is what put it in the discharge population and therefore in a read-set that crosses
an `IMPORT`. §11.1.2 had already kept six files on `ASSUME` for this very role; this line should have
been the seventh.

So the repair is to restore it, not to weaken the refusal. Recorded here because it is the first
thing the sweep is known to have got wrong, and §11.14's account of what the sweep swept did not have
it.

**What the repair does NOT fix, stated plainly.** With the marker back to an `ASSUME`,
`regcf-wizard.l4`'s `--validate-only` false green returns: the wizard's schema still never mentions
the marker, and a run still stops loudly. That is the older, out-of-scope hole — a term-role `ASSUME`
reached across an `IMPORT` — which OF-7's census already lists separately (`daydate`, the vendored
`thailand-cosmetics/prelude`) and which §11.16 classifies as loud, not silent. The refusal built here
covers section binders, which is what §11.19 rules. Extending it to imported `ASSUME`s is a separate
change with its own measurement, and it is **not** made here.

#### Not done

- **The two-binder type gap.** Where two headings declare one name, a `WITH` supply is still checked
  the old way. Sound closure needs the read-set at check time, which is R-X3's second move. Stated
  to the reader on `doc/reference/syntax/section-given.md`, not only here.
- **A vacuous bridge is silent.** Inside that same gap, a `g WITH foo IS foo` whose right-hand `foo`
  resolves to the callee's own binder discards the writer's value with no diagnostic. Measured
  2026-09-08; not fixed.
- **A top-level callee.** Where the callee is defined outside every section it has no recorded
  section path; the singleton rule still applies to it, but nothing about a multi-binder module does.
- The refusal names **one** imported reader per export, the first by `Unique` order. A chain is
  reached through that one, and naming every link would report a single mistake three or four times.
- One mistake in a shared definition is reported once per root that reaches it, so an `@export` plus
  three directives over one bad definition is four errors. Measured; judged acceptable against the
  alternative of guessing which root the author meant.
- `Discharge` now walks `sectionBinders` and `readSets` three times per module (two supply checks and
  the per-root check) rather than twice, plus a per-definition closure when — and only when — the
  module imports a reader. All of it is behind the empty-binder and empty-import early exits, so a
  module with neither pays nothing. Not otherwise measured.
- The closure over imports — R-X3's accepted end state — is untouched, which is the ordering §11.19
  rules.

#### What the adversarial pass cost, and why it is recorded

Three refuters with distinct lenses were run against the first build, after it had already passed
`cabal build all`, a 3030-example golden suite and a hand-written probe for each of the three
rulings. Between them they produced **nine real defects**, four of them regressions that turned
working programs red or accepted crashing ones, and two of them silent false greens in the very
refusal being landed. The corpus caught **none** of them: all 458 files stayed green through every
one, because the shapes involved — a callee reading a binder from off its own ancestry, a directive
over two sibling sections, an export naming an imported binder, a three-module chain — are each one
line away from a shipped file and in no shipped file.

That is the entry worth keeping. **A green corpus is not evidence that a whole-module check is
right**, because a corpus is a sample of what has been written, and a new check is a claim about
what could be. The measurement that mattered every time was a probe built to break the claim, and
the cheapest way to get those was to ask for them adversarially rather than to write them while
believing the code.
