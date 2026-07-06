# Design Handoff: Implicit Environment (`props`) for L4

**Status:** Design exploration / pre-implementation
**Audience:** A Claude Code agent (or human contributor) who will turn this into a formal specification and, eventually, an implementation plan.
**Timing note:** L4 has effectively zero production users in the wild today. This is the moment to make breaking changes to the core calling convention. The bias should be toward getting the model *right* now rather than toward backward compatibility.

---

## 0. How to read this document

This is a record of a design conversation, reorganized for a downstream agent. It is deliberately long and motivation-heavy. The intent is that you (the next agent) should be able to:

1. Understand *why* this feature is being contemplated, not just what it is.
2. Reconstruct the reasoning from first principles so you can defend or revise individual decisions.
3. Identify the open questions that still need resolution before a real spec is frozen.

Where syntax is shown for *existing* L4, it follows the current language (`GIVEN` / `GIVETH` / `MEANS`, `DECIDE ... IF`, `'s` field access, `§` sectioning, `WHERE` blocks). Where syntax is shown for the *proposed* feature (notably `TAKING`), it is clearly marked as a proposal and is open to bikeshedding.

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
- The natural escape hatch developers reach for is "just pass a dictionary of context" — which is exactly React props, but *untyped*. At that point you've abandoned the explicit-in-the-signature ideal and gained none of the formal clarity, while inheriting all the opacity.

So the question is: **can L4 provide a first-class, properly typed, auditable mechanism for implicit environment passing — so developers never have to reinvent props badly by hand?**

---

## 2. The core tension (motivation)

### 2.1 Chesterton's Fence: why purity was the original hill

The original appeal of functional programming is **referential transparency** and **purity**: a function declares, in its type signature, *exactly* the information it needs, and produces its result from that and nothing more. In the simple case the signature is a handful of simple values, and a first-time reader of the codebase can see the entire dependency surface at a glance.

We must not knock down this fence carelessly. It is the thing that makes formal verification and clear decision traces possible in the first place.

### 2.2 But purity alone doesn't scale ergonomically

Very quickly in the history of FP it became evident that you *do* need to pass an environment / context / reader. Haskell's `Reader` monad exists precisely for this. The essential purity of the system remains intact — `Reader` is pure — but **ergonomically** something is lost: a developer reading the code sees a value being consumed and has to ask "where did this come from? who set it? what was its origin?" "I know it arrives via the reader environment" is true but unsatisfying. It begins to feel mysterious and magical.

So the tension is:

> **Explicit signatures** are transparent but, at scale, unmaintainable.
> **Implicit environments** are ergonomic but opaque about provenance.

L4 needs the ergonomics of the second without surrendering the auditability of the first — because explainability *is the product*. If a lawyer, regulator, or auditor reads a decision trace and sees a value used deep in a computation, they must be able to follow its provenance. Silent implicit context breaks exactly the property L4 sells.

### 2.3 Design stance: mechanism, not policy

We do **not** want to drag L4 into the muck of imperative environments. React in practice needs hooks, `useEffect`, and so on, drifting from the purity of its Elm-style origins; Haskell has `unsafePerformIO`. These compromises are made for good reasons.

The stance here is **mechanism, not policy**: if developers are going to need to bend the rules anyway, it is better that they get the rope from *us*, in a principled and visible form, than that they hack something together that is uglier and less transparent. `unsafePerformIO` is the model to emulate in spirit: the escape hatch is *marked and visible* at the point of use, so a reader knows exactly where the contract is being stretched.

---

## 3. Prior art and language comparisons

This section is for the downstream agent to mine; each comparison carries a lesson.

| Source | What it does | Lesson for L4 |
|---|---|---|
| **Elm (Model–Update–View)** | Pure functions transform state; the architecture React later popularized. The conceptual origin of "purely functional transformation of input state." | The pure ideal is the baseline to preserve. |
| **React props** | Values passed down a component tree. | The ergonomic target — but untyped props are the failure mode. |
| **React + TypeScript** | Props become structurally typed; the mechanism stays implicit forwarding, but the *contract* (shape and types) is explicit and checkable. | This is the sweet spot to aim for: implicit mechanism, explicit checkable contract. |
| **Reader monad** | Pure threading of an environment; `local` rebinds the environment for a subtree. | Gives us both the implicit-pass semantics *and* the hypothetical-evaluation primitive (see §4.4). |
| **`unsafePerformIO`** | A visible, marked breach of purity. | The model for "principled rope": escape hatches must be visible. |
| **Python closures / nested defs** | Inner functions capture enclosing scope, bypassing explicit threading. | Ergonomic locally, but opaque: a reader must trace lexical scopes to discover captured dependencies. We want closure-like convenience *with* Reader-monad transparency. |
| **Novice "everything is global"** | If you need it, grab it; if you must set it, write it; it all floats in one symbol table. | Seductively simple — and the thing we are, in a disciplined way, partly trying to recover. But unscoped globals don't stay tractable. |
| **Prolog at scale** | Arguably suffers the growing-global problem as programs grow. | Cautionary: implicit shared context must remain *scoped and tracked*, not a free-for-all. |
| **OO-in-Haskell (narrowing/widening of record types)** | There is published work on object-oriented Haskell with principled type narrowing and widening. | A candidate formal basis for how `props` types may grow down the call stack (see §5). |
| **L4's existing `WHERE` blocks** | Haskell-style; the `WHERE` block has access to the function's environment, so helpers defined there are effectively closures. | This is the closest thing L4 has *today* to implicit context. It is a starting point but not the destination. |

---

## 4. The proposed design

### 4.1 Every function carries an implicit `props` environment

Rather than an opt-in annotation (a function-annotation solution family feels like a code smell — necessary in languages like Python only because they didn't think of it early enough; we have the opportunity to think of it early), **make it universal by default**: every function implicitly receives a `props` environment — a typed set of properties — in addition to its explicit `GIVEN` parameters.

This is, in effect, imposing an invisible Reader monad over the whole language. But `props` is subject to the *same discipline as everything else in the language* — it is typed, tracked, and inferable. It is not a mutable imperative bag, and it is not unscoped globals. Think of it as "mini-globals with a scope discipline."

### 4.2 Section syntax establishes the scope hierarchy

L4 already has section syntax (`§`, `§§`, `§§§`, …) used for document structure, analogous to `H1`/`H2`/`H3`. The proposal is to make this hierarchy *meaningful* for `props` scope:

- `props` established at a section level is visible to functions defined under that section and its subsections.
- The section structure therefore **self-documents the scope hierarchy** — the same mechanism that organizes the document organizes the environment.

This is the answer to the closure-opacity problem: with closures you must trace lexical nesting by hand; here the section headings *are* the visible scope boundaries.

### 4.3 Discover purity; don't annotate it

Because `props` is available everywhere by default, the interesting analysis is the inverse: **statically determine which functions actually use it.**

- Analyze each function and the **transitive closure of its callees** for any reference to a `props` component.
- If an entire subtree never touches the environment, mark it **"very pure"** — it can be reasoned about more strongly for formal verification, memoized aggressively, etc.
- Crucially, this is *purity discovered, not declared*. We are not hiding purity behind a universal `props`; we are revealing it precisely.

This is a strong explainability win: a decision trace can distinguish "this subtree is pure logic" from "these calculations are environment-dependent." Auditors see the boundary immediately, and verification tooling can apply stronger reasoning to the pure regions.

### 4.4 `local`-style hypothetical evaluation

The Reader monad's `local` gives exactly the primitive needed for **ceteris paribus / hypothetical evaluation**: rebind one component of the environment for a single subtree of computation, evaluate, then unwind — without imperative side effects.

For a decision service this is powerful: you can show alternate decision paths under different contextual assumptions ("what if jurisdiction were X instead of Y?") without manually threading modified parameters through the whole call stack, and without leaving the pure world.

The default ergonomic case is the opposite of restriction: a caller should be able to say, in effect, "**everything I know, I pass on** — I keep no secrets from the callee." `local` is then the disciplined exception used when you deliberately *do* want to vary one assumption.

### 4.5 Provenance in traces

For every rule, the trace can surface the `props` it consumed and the provenance chain: "this rule applied with `jurisdiction` = X, established at section 3.2" and, with computed fields (§5.3), "`eligibility` was computed from `age` and `jurisdiction`." The implicit becomes explicit *in the output* without cluttering the *source*.

---

## 5. Type-system design

### 5.1 Structural subtyping, growing down the stack

Real-world props grow at the developer's whim — fields get added as needed. We need a *principled* version of this. The natural shape:

- **Shallow in the caller, rich deeper down.** The entry point's `props` is relatively small; as you descend the call stack, `props` accumulates more fields.
- A function that requires fields `{X, Y, Z}` can be called from a context that supplies *at least* `{X, Y, Z}`. Narrower-required is satisfied by wider-available — i.e. a structural subtyping relation, in the TypeScript/duck-typing spirit.
- The published **narrowing/widening work on OO-in-Haskell** is a candidate formal grounding for the variance rules here. Get the variance direction right (what a callee *requires* vs. what a caller *provides*) and the discipline holds across a large call graph.

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
- **A clean visual split** between *what is handed in* (`GIVEN`) and *what is drawn from context* (`TAKING`).
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
4. **Establishing/extending `props`.** What is the authoring syntax for *adding* to `props` at a section boundary or a call site? How explicit must that act be? (Establishment probably *should* be visible even if consumption is inferred.)
5. **Interaction with `WHERE` closures.** How does the new `props` model relate to the existing `WHERE`-block environment access? Subsume it, coexist, or reframe `WHERE` in terms of `props`?
6. **Regulative rules.** How does implicit `props` interact with `PARTY`/`MUST`/`HENCE`/`LEST` and with `#TRACE` temporal testing? Does the environment flow through state transitions, and how is it shown in `#TRACE` output?
7. **Teaching story.** How do we *teach* `props`? The mental model ("everything the caller knows is passed on, unless you deliberately use `local`") needs a crisp, honest framing that doesn't read as "we brought back globals."
8. **Purity classification surface.** How is "very pure" exposed — diagnostic, hover, badge in the visualizer, attribute in generated artifacts?
9. **Error messages.** When a function references a `props` field not available in scope, the diagnostic must stay intelligible across a large call graph. What does a good error look like?

---

## 9. One-paragraph summary for a hurried reader

L4 should give every function an implicit, statically-typed `props` environment — a principled, scoped replacement for the untyped context dictionaries developers otherwise hand-roll, and for the unmaintainable manual threading of dozens of parameters through thousands of rules. The `§` section hierarchy defines `props` scope; structural subtyping lets `props` start small at the entry point and grow richer deeper in the call stack; the compiler infers each function's `props` requirements from usage (no annotations), discovers which subtrees are "very pure" because they never touch the environment, and surfaces the inferred dependencies through a `TAKING` clause that the IDE displays and the decision trace records. The Reader monad's `local` supplies hypothetical "what-if" evaluation without leaving the pure world. The guiding principle is *mechanism, not policy*: give developers visible, auditable rope rather than forcing them to hack together something opaque — preserving the referential transparency and explainability that are L4's whole reason for being.
