# Future Features

**Ellipsis linting**: LSP diagnostics to warn when ellipsis forms appear adjacent to mismatched operators (e.g., `...` near OR, `..` near AND). See [spec](dev/specs/todo/ASYNDETIC-DISJUNCTION-SPEC.md).

Three carets together will mean "repeat everything above to the end of the line".

Syntax and semantics for regulative rules.

Syntax and semantics for property assertions and bounded deontics. Transpilation to verification reasoner backends: UPPAAL, NuSMV, SPIN, Maude, Isabelle/HOL, Lean. See [BOUNDED-DEONTICS-SPEC](dev/specs/todo/BOUNDED-DEONTICS-SPEC.md).

Transpilation to automatic web app generation.

Set-theoretic syntax for UNION and INTERSECT. Sometimes set-and means logical-or.

WHEN should not be needed at each line in a CONSIDER.

**Homoiconic introspection of imported constructs.** Motivated by Housing Act 1988 Sch. 2 Ground 1A(a) — "a lease granted for a term certain of more than 21 years and not terminable before the end of that term by notice" — which asks us to *introspect another L4 instrument* rather than evaluate one. When sketching Ground 1A I reached for three things that, on reflection, are **cleverly functional, not homoiconic**:

- *model-as-data* — re-describe the salient features as a typed `Disposal` record (`termYears`, `terminable`) and read its fields. But that inspects a hand-authored re-description, not the construct itself.
- *behavioural* — run the construct through `#TRACE` and watch whether a "terminate by notice" event reduces it. This is black-box property-over-trace (the letter-vs-spirit check), i.e. *execution*, not reflection.
- *schema* — query the lowered MLIR Schema. That is reflection over a derived, lossy projection, not code-as-data.

None of these gives the Lisp property: the construct's *own syntax tree* available, inside L4, as an ordinary L4 value you can pattern-match and `EVAL` back. Genuine homoiconic introspection (the **R10 "Rule Graph Introspection" stretch goal** of [HOMOICONICITY-SPEC](../todo/HOMOICONICITY-SPEC.md)) would need: a reified `Syntax` type mirroring the L4 AST; a `QUOTE` that yields an imported definition's *source* tree (precisely the structure the MLIR lowering throws away); an `EVAL`/unquote inverse to close the loop; and binding hygiene, so "is *this* lease terminable by notice" resolves `terminable` in the imported construct's own vocabulary, not the querying contract's. Caveat: L4's surface (mixfix, layout, inert prose) is *not* a uniform s-expression, so even with QUOTE/EVAL this is Template-Haskell-style staged reflection over a reified AST — not Lisp-strict code≡data. Lisp gets introspection for free because its surface *is* its data structure; L4 has to build the reification.

---

## Recently Implemented

The following features have been implemented and moved from this list:

- **Asyndetic conjunction (`...`)**: Implicit AND using three-dot ellipsis syntax. See [Basic Syntax](20-basic-syntax.md#asyndetic-conjunction-).
- **Asyndetic disjunction (`..`)**: Implicit OR using two-dot ellipsis syntax. See [Basic Syntax](20-basic-syntax.md#asyndetic-disjunction-).
- **Inert elements**: String literals in boolean context as grammatical scaffolding. See [Boolean Logic](10-boolean-logic.md#inert-elements-grammatical-scaffolding).
