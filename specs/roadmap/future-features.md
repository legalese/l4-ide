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

---

## Recently Implemented

The following features have been implemented and moved from this list:

- **Asyndetic conjunction (`...`)**: Implicit AND using three-dot ellipsis syntax. See [Basic Syntax](20-basic-syntax.md#asyndetic-conjunction-).
- **Asyndetic disjunction (`..`)**: Implicit OR using two-dot ellipsis syntax. See [Basic Syntax](20-basic-syntax.md#asyndetic-disjunction-).
- **Inert elements**: String literals in boolean context as grammatical scaffolding. See [Boolean Logic](10-boolean-logic.md#inert-elements-grammatical-scaffolding).
