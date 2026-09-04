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
8. **Purity classification surface.** How is "very pure" exposed — diagnostic, hover, badge in the visualizer, attribute in generated artifacts?
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
   rebinding. Today that costs 15 dropped decisions (the `D-RULEDATE-UNBOUND` class in
   `specs/todo/DMN-DIFFERENTIAL-CI-SPEC.md`); if `local` becomes a general feature, **every use
   of it is unlowerable by the same argument**, and the unlowerable surface grows in proportion to
   how much authors reach for hypothetical evaluation. Not an argument against `props` — an
   argument that this spec and `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` should cite each other, which
   as of this snapshot neither does.

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
§5.1's structural subtyping is found unnecessary. R0–R8 and R10–R12 are recorded below, each with the mark Meng gave it on 2026-09-04; R9 is the
one open candidate, with a recommendation on the rulings sheet.

### 11.1 R0 — `ASSUME` is deprecated. RULED 2026-09-04.

**Ruling (Meng, 2026-09-04): `ASSUME` is deprecated.** Its three jobs go to three destinations:

| job                                | destination                                                                  | status                    |
| ---------------------------------- | ---------------------------------------------------------------------------- | ------------------------- |
| suppliable term (the ~550 uses)    | a section-level `GIVEN` discharged by the compiler into ordinary parameters  | mechanism pending (R1–R5) |
| uninterpreted type (`… IS A TYPE`) | an empty `DECLARE T`, which already parses (`ok/set-operators-nested.l4:36`) | available today           |
| refusal / typed bottom             | `REFUSE "…"`, uncatchable, boundary-only, in no schema                       | spec pending (R7)         |

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

**Sequencing.** (1) the transitive read-set pass, in progress on `fix/export-transitive-readset`,
which is both a bug fix and step one of discharge; (2) the mechanism rulings R1–R3 and R7;
(3) discharge; (4) `REFUSE` and the empty-`DECLARE` migration of the type role, so that no refusal
and no sort is ever suppliable; (5) a deprecation warning in `l4 check` with a code action that
rewrites a term `ASSUME` to the ruled spelling — the warning does not land before the code action
can; (6) corpus and docs migration, `doc/reference/types/ASSUME.md` carrying the notice and the
recipe (CLAUDE.md §6); (7) keyword removal, together with the dead `LocalAssume` grammar.

**What this does not decide.** In-body hypotheticals (R9), still a candidate on the rulings sheet
with a recommendation. Everything else the red team put up is ruled in §11.2–§11.12 below. Consistent with §10.7 above and the handoff's §7 ("`ASSUME` is not simply
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
`origin/unstable` (`PROPS-REDTEAM-2026-09-03.md` §7); delivery is four PRs into `unstable`.
