# Type theory

The formal foundations of L4's type system. This page is for readers who know some type theory or functional programming and want the precise mechanics behind L4's type checking, inference and evaluation.

For practical use of L4 types, see [Types](../../reference/types/README.md). For the intuitive account of records and enumerations, see [Types as legal categories](algebraic-types.md).

---

## Type System Overview

L4's type system draws from well-established foundations in programming language theory:

- **Paradigm:** Hindley-Milner-style with algebraic data types
- **Inference:** Bidirectional type checking (mixing inference and checking modes)
- **Purity:** Pure functional core with no side effects in the expression language
- **Effect type:** DEONTIC serves as a modal effect type for regulative rules
- **Evaluation:** Lazy (call-by-need), following Haskell semantics

The combination of Hindley-Milner inference with bidirectional checking means that most expressions do not require explicit type annotations, while top-level function signatures (via GIVEN/GIVETH) provide checking anchors that improve error messages and serve as documentation.

---

## Type Correspondence

How L4 constructs map to type theory, Haskell, other languages and category theory:

| L4 construct      | Type theory | Haskell             | Other languages                 | Category theory   |
| ----------------- | ----------- | ------------------- | ------------------------------- | ----------------- |
| DECLARE T HAS ... | Product     | data T = T { ... }  | struct/class/interface          | Product (×)       |
| IS ONE OF         | Sum         | data T = A \| B     | enum/union/variant/sealed class | Coproduct (+)     |
| GIVEN...GIVETH    | Arrow       | a -> b              | function signature/def/fn       | Exponential (B^A) |
| MAYBE T           | Option      | Maybe T             | Optional/null/nil/None/?        | T + 1             |
| LIST OF T         | List        | [T]                 | Array/List/Vec/Sequence         | Free monoid       |
| CONSIDER          | Match       | case...of           | switch/case/match/when          | Catamorphism      |
| BRANCH            | Guards      | \| cond = ...       | if-elseif chain/cond            | -                 |
| WHERE / LET...IN  | Binding     | where / let...in    | let/const/var/local             | Substitution      |
| DEONTIC           | Effect      | Custom monad        | - (domain-specific)             | Kleisli category  |
| 's genitive       | Accessor    | Record field / lens | dot notation / .field           | Projection        |

---

## Type Inference Rules

The following rules describe how types are assigned to L4 expressions. The notation uses a typing context (environment) written as a Greek capital gamma, and the turnstile symbol to mean "entails" or "has type".

### Variables

A variable has the type assigned to it in the environment:

```
Γ ⊢ x : τ    if (x : τ) ∈ Γ
```

### Application

If `f` has function type and `e` has the argument type, then the application `f e` has the return type:

```
Γ ⊢ f : τ₁ → τ₂    Γ ⊢ e : τ₁
─────────────────────────────────
         Γ ⊢ f e : τ₂
```

### Abstraction (Lambda / GIVEN...YIELD)

If, extending the environment with a binding for `x`, the body `e` has type τ₂, then the lambda (written `GIVEN x YIELD e` in L4) has arrow type:

```
   Γ, x : τ₁ ⊢ e : τ₂
──────────────────────────────
Γ ⊢ (GIVEN x YIELD e) : τ₁ → τ₂
```

### Conditional (IF/THEN/ELSE)

The condition must be BOOLEAN, and both branches must have the same type:

```
Γ ⊢ c : BOOLEAN    Γ ⊢ e₁ : τ    Γ ⊢ e₂ : τ
────────────────────────────────────────────────
       Γ ⊢ IF c THEN e₁ ELSE e₂ : τ
```

### Pattern Matching (CONSIDER/WHEN)

The scrutinee must have a known type T, and all branches must produce the same result type. Pattern variables are brought into scope within each branch:

```
Γ ⊢ e : T    Γ, vars(pᵢ) ⊢ eᵢ : τ  (for all i)
──────────────────────────────────────────────────
  Γ ⊢ CONSIDER e WHEN p₁ THEN e₁ ... : τ
```

---

## Bidirectional Type Checking

L4 uses a bidirectional type checking strategy that combines two modes:

### Checking Mode

In checking mode, the expected type flows **downward** into an expression. This is used when:

- A function definition has an explicit signature via GIVETH -- the declared return type is pushed into the function body
- Branches of IF/THEN/ELSE and CONSIDER/WHEN are checked against the type established by the first branch or the enclosing signature
- Arguments to functions with known parameter types

Checking mode produces better error messages because the system knows what type it expects.

### Inference Mode

In inference mode, the type flows **upward** from subexpressions. This is used when:

- Expressions appear without an explicit type annotation
- Field access (`person's name`) -- the field type is looked up in the record declaration
- Operators -- the result type is determined by the operator's definition
- Literals -- NUMBER, STRING, BOOLEAN literals have known types

### How They Interact

In practice, top-level GIVEN/GIVETH declarations establish checking anchors, while inference fills in the types of internal expressions. This means you rarely need to annotate local bindings: the top-level signature provides enough information for the checker to propagate types throughout the function body.

---

## Parametric Polymorphism

L4 supports parametric polymorphism (generics) primarily through prelude functions. Type variables are implicit -- the system infers the concrete types at each call site.

Prelude functions like `map` and `filter` are polymorphic:

```
map    : (a -> b) -> LIST OF a -> LIST OF b
filter : (a -> BOOLEAN) -> LIST OF a -> LIST OF a
```

In L4 usage, the type variables are instantiated by inference:

```l4
IMPORT prelude

numbers MEANS LIST 1, 2, 3
doubled MEANS map (GIVEN x YIELD x * 2) numbers
```

Here `a` and `b` are both inferred as NUMBER from the multiplication operator and the type of `numbers`.

User-defined polymorphism is available through type parameters declared with `IS A TYPE`:

```l4
GIVEN T IS A TYPE
      xs IS A LIST OF T
GIVETH A MAYBE T
`the first item of` MEANS
    CONSIDER xs
    WHEN EMPTY THEN NOTHING
    WHEN x FOLLOWED BY rest THEN JUST x
```

`` `the first item of` (LIST 1, 2, 3) `` gives `JUST 1`, and `` `the first item of` (LIST "a", "b") `` gives `JUST "a"`: `T` is instantiated afresh at each call.

---

## DEONTIC as Modal Type

The DEONTIC type is L4's effect type for regulative rules. It has a modal logic interpretation that connects legal obligation theory (deontic logic) to type theory.

### Modal Operators

| L4 Keyword | Deontic Meaning | Modal Logic      | Symbol  |
| ---------- | --------------- | ---------------- | ------- |
| MUST       | Obligation      | Necessity        | Box     |
| MAY        | Permission      | Possibility      | Diamond |
| SHANT      | Prohibition     | Necessity of not | Box-Not |

In modal logic terms:

- **MUST p** asserts that p is obligatory -- in all compliant futures, p holds. This corresponds to the necessity operator.
- **MAY p** asserts that p is permitted -- there exists a compliant future where p holds. This corresponds to the possibility operator.
- **SHANT p** asserts that p is forbidden -- in no compliant future does p hold. This corresponds to the necessity operator applied to not-p, or equivalently to the negation of the possibility operator.

### Composition

DEONTIC expressions compose through:

- **HENCE** -- Sequential composition. After one obligation is fulfilled, the next obligation follows.
- **LEST** -- Alternative composition. If an obligation is breached, the LEST branch specifies consequences.
- **IF** -- Conditional guard. The deontic obligation only activates when the condition holds.
- **RAND / ROR** -- Parallel composition. Both obligations, or either one, must be fulfilled.

### Trace Semantics

A DEONTIC value is run against a start time and a list of events, with `#TRACE` or the `EVALTRACE` function. The result is again a DEONTIC value: `FULFILLED`, a breach, or the residual obligation still waiting for events. `l4 state-graph` draws the possible paths through a rule's `HENCE` and `LEST` branches as a graph. [How obligations unfold](../legal-modeling/regulative-rules.md) explains this behaviour without the formalism.

### Type Signature

A regulative rule has type `DEONTIC party action`, parameterised over the type of its parties and the type of its actions; a rule declares it with `` GIVETH A DEONTIC `Party` `Action` ``.

The two type parameters are both **monomorphic** when actors are encoded as values (the recommended style). With the value-actor encoding, the party and action types are concrete declared types (e.g., `Actor` and `Action`), and the contract head drives mixed-actor events without subtyping or GADTs.

Within the type system, DEONTIC acts as a custom monad (in Haskell terms) or, in category-theoretic terms, lives in a Kleisli category.

### Actor-Correctness: Value-Level Performer Check

Beyond the type-level check that the party and action types match the contract head, L4 enforces a **value-level actor-correctness** rule:

> In `PARTY p MUST a` (obligation) and `PARTY p DOES a` (event), the party `p` must equal the _performer_ of action `a` — the first actor-typed field of `a` in positional order (the **subject-first canon**).

This check is a complement to, not a replacement for, type-level `checkPartyActionAgreement`. It fires only when both `p` and the performer can be resolved statically; it is silent for computed actors or actions without actor fields (leaving legacy/flat-union contracts untouched).

A violation produces a diagnostic such as:

```
An actor may only perform its own actions.

  `eat` is performed by `Eater`, not by `Drinker`.
```

For the full design rationale (value-actors vs. type-indexed actors, the SVO canon, duplex actions, procurement) see:

- [actors-and-actions.md](../../concepts/legal-modeling/actors-and-actions.md) — syntax, worked examples, boundaries
- [ACTOR-ACTIONS-THEORY.md](../../concepts/legal-modeling/ACTOR-ACTIONS-THEORY.md) — theory & bibliography (thematic roles, STIT logic, agency law)

---

## Subtyping

L4 has **no subtyping**, and its types are **nominal**:

- Types are distinguished by name, not by structure. Two record types with identical fields but different names are different types.
- There is no structural subtyping or row polymorphism.
- There is one numeric type, NUMBER, for whole and fractional numbers alike, so there is no numeric tower to coerce along. Conversions between types, such as `TOSTRING`, are explicit function calls ([Coercions](../../reference/types/coercions.md)).

---

## Unit Type

The unit type (written `()` in Haskell) is **implicit** in L4 -- it is not directly exposed in the surface syntax.

Its primary manifestation is through nullary constructors in sum types:

```l4
DECLARE Status IS ONE OF Active, Closed
```

Here, `Active` and `Closed` are nullary constructors. Internally, they can be understood as functions from unit to Status (`() -> Status`), though this is not visible to the L4 programmer.

---

## Lazy Evaluation

L4 uses **call-by-need** evaluation semantics, following Haskell:

- **Expressions are not evaluated until their value is needed.** A WHERE binding that is never referenced in the result is never computed.
- **Once evaluated, the result is memoized.** Subsequent references to the same binding reuse the computed value.

### Implications

- **Infinite data structures** are possible in principle (e.g., infinite lists), though this is rarely needed in legal domain code.
- **Short-circuit evaluation:** AND and OR do not evaluate their second operand if the first operand determines the result. This is a natural consequence of laziness, not a special case.
- **WHERE bindings are lazy:** Definitions in a WHERE clause are only evaluated if referenced. This allows defining multiple helper values without paying for unused ones.
- **Evaluation traces:** The `#EVALTRACE` directive records which expressions were actually evaluated and in what order, providing visibility into the lazy evaluation process for debugging.

---

## Fixed Points and Recursion

Recursive definitions in L4 use **letrec semantics** in WHERE blocks. A function can refer to itself in its own definition:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
factorial MEANS
    IF n <= 1 THEN 1
    ELSE n * (factorial (n - 1))
```

In type-theoretic terms, this is interpreted as a fixed point:

```
factorial = fix (λf. λn. if n ≤ 1 then 1 else n × f(n - 1))
```

Where `fix` is the fixed-point combinator satisfying `fix f = f (fix f)`. The type checker handles recursive bindings by first assuming a type for the recursive name, then checking the body against that assumption, and finally verifying consistency.

Mutual recursion (multiple functions referencing each other in the same WHERE block) follows the same letrec semantics.

Recursive types are fixed points at the type level. The `` `legal document` `` type in [Types as legal categories](algebraic-types.md#recursive-types), whose sections contain lists of further documents, is the least fixed point

```
LegalDocument = μX. Section(STRING × STRING × List X) + Paragraph(STRING) + Definition(STRING × STRING)
```

and a function that recurses over it with CONSIDER, one branch per constructor, is a catamorphism (a fold) over that fixed point.

---

## See Also

- **[Types](../../reference/types/README.md)** -- Practical guide to all L4 types
- **[Types as legal categories](algebraic-types.md)** -- Conceptual explanation of product and sum types
- **[Exhaustiveness](exhaustiveness.md)** -- Why CONSIDER checks that every constructor is covered
- **[Regulative rules](../../reference/regulative/README.md)** -- MUST, MAY, SHANT and regulative rule structure
- **[Glossary](../../reference/GLOSSARY.md)** -- Complete language feature index
