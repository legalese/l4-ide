# `#CHECK` and `:type` print stable type variables (as built)

As built on `main` by this PR, measured on `main` at `4c887e0db`.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.

Source: the type-variable half of PR #330 (`1679c8d43`).
The other half of #330, the `#ASSERT` outcomes, reached `main` through PR #696 and is not part of this PR.
#330's edit to `not-ok/tc/tests/section-scoping-ambiguous.golden` is not carried, because that file arrives with section scoping.

## What it does

`#CHECK` over a polymorphic term, and the REPL's `:type`, used to print the checker's internal names for its inference variables, such as `a24` or `x13`.
Those names are not in any scope, and they change whenever the file is edited.
They now print as `a`, `b` and so on, by order of first appearance, as hover already does.

Measured on `jl4/examples/ok/check-display-typevars.l4`:

| Directive                   | `main`                          | this PR                      |
| --------------------------- | ------------------------------- | ---------------------------- |
| `#CHECK bottom`             | `a2`                            | `a`                          |
| `#CHECK GIVEN x YIELD x`    | `FUNCTION FROM x4 TO x4`        | `FUNCTION FROM a TO a`       |
| `#CHECK GIVEN x, y YIELD x` | `FUNCTION FROM x6 AND y8 TO x6` | `FUNCTION FROM a AND b TO a` |

In the REPL, after `:load` of a file with the same `bottom`, `:type GIVEN x YIELD x` went from `FUNCTION FROM x5 TO x5` to `FUNCTION FROM a TO a`, and `:type bottom` from `a4` to `a`.

## Where it lives

- `prettyCheckError (CheckInfo t _)` renders with `prettyTypeForDisplay` instead of `prettyLayout` (`jl4-core/src/L4/TypeCheck.hs:4987`).
- `getExpressionType` in the REPL does the same (`jl4-repl/app/Main.hs:1038`).
- `prettyTypeForDisplay` itself is unchanged (`jl4-core/src/L4/Print.hs:120`).

## Tests that pin it

- `jl4/examples/ok/check-display-typevars.l4` and its four goldens.
- The gensym lines in `ok/tests/tbd.golden`, `ok/tests/reverseaux.golden` and `not-ok/tc/tests/error-directive-ambiguity.golden` are re-blessed.
- Nothing pins the REPL's `:type`; it was measured by hand as above.
