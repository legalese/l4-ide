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
They now print as `a`, `b` and so on, by order of first appearance, as the VS Code hover already did.
The web editor's hover and the REPL's `:info` and `:env`, which printed the internal names too, now print the same.
The deploy sidebar's inspector and the deployed schema's `returnType` already used the same printer.

A name that already appears as a type in the printed type is skipped, so that one printed type does not use one name for two things.
A name that is merely in scope is not skipped: the printed type depends only on the type, not on the other type names the module can see.

Measured on `jl4/examples/ok/check-display-typevars.l4`:

| Directive                   | `main`                          | this PR                      |
| --------------------------- | ------------------------------- | ---------------------------- |
| `#CHECK bottom`             | `a2`                            | `a`                          |
| `#CHECK GIVEN x YIELD x`    | `FUNCTION FROM x4 TO x4`        | `FUNCTION FROM a TO a`       |
| `#CHECK GIVEN x, y YIELD x` | `FUNCTION FROM x6 AND y8 TO x6` | `FUNCTION FROM a AND b TO a` |

Measured on `jl4/examples/ok/check-display-collision.l4`, which declares a type `a`, with the `l4` built from this PR before the names were skipped (`b3f799fa1`) and after:

| Directive                                         | `b3f799fa1`                  | this PR                      |
| ------------------------------------------------- | ---------------------------- | ---------------------------- |
| ``#CHECK GIVEN `the application` YIELD approved`` | `FUNCTION FROM a TO a`       | `FUNCTION FROM b TO a`       |
| `#CHECK GIVEN x, y YIELD approved`                | `FUNCTION FROM a AND b TO a` | `FUNCTION FROM b AND c TO a` |
| `#CHECK GIVEN x IS a YIELD x`                     | `FUNCTION FROM a TO a`       | `FUNCTION FROM a TO a`       |
| `#CHECK GIVEN x YIELD x`                          | `FUNCTION FROM a TO a`       | `FUNCTION FROM a TO a`       |

In the REPL, after `:load` of a file with the same `bottom`, `:type GIVEN x YIELD x` went from `FUNCTION FROM x5 TO x5` to `FUNCTION FROM a TO a`, and `:type bottom` from `a4` to `a`.

## What agrees with what

Each surface names the variables of the whole type it prints, so two surfaces that print the same whole type give the same text: `#CHECK`, `:type`, both hovers, `:info`, `:env`, the inspector and the deployed `returnType`.
A part of a type printed on its own is named afresh.
In `#CHECK GIVEN x, y YIELD y`, the `#CHECK` prints `FUNCTION FROM a AND b TO b`, and the hover on the `y` after `YIELD` prints `a`.

## Limits

- `DECLARE a` beside `#CHECK GIVEN x YIELD x` prints `FUNCTION FROM a TO a`, the same text as `#CHECK GIVEN x IS a YIELD x`.
  That is left so that a deployed `returnType` depends only on its type: skipping names in scope made jl4-service refuse a redeploy that only added an unrelated `DECLARE a`, even in a file two imports away, as a return type change (measured on a build of `c341b7b57`, a version of this PR that was not kept).
- A deployment made before this PR whose `returnType` contained such a collision is recompiled with the new text when the service restarts, so its clients see that `returnType` change once.
  Measured with `main`'s `jl4-service` then this PR's, on one store: `FUNCTION FROM a TO a` before the restart, `FUNCTION FROM b TO a` after, and every later redeploy is applied.
- The VS Code outline still prints the checker's internal names, as on `main`, in two places.
  A rule's row shows its result type alone (`jl4-lsp/app/LSP/L4/Handlers.hs:620`); naming that part on its own would disagree with the rule's own input rows and with `#CHECK`: with `DECLARE a` and `GIVEN r IS AN a, z` before `` `pickA` MEANS z ``, it showed `pickA | a` beside the input row `r | a`, where `#CHECK` gives `FUNCTION FROM a AND b TO b`.
  A `#CHECK` row prints the directive's expression (`:595`), whose untyped inputs carry their inferred types, such as `w IS w52`.
- The service's redeploy check compares `returnType` texts, so it cannot tell a display name from a declared type of the same name, on `main` or with this PR.
  With this PR it applies a redeploy that turns an open variable into a declared `b` printed with the same text: a result of `EITHER OF a, b` whose second part was any type, and is now the declared `b`, prints `EITHER OF a, b` both times; `main` rejects it, because it printed the first as `EITHER OF a, a`.
  The same holds for `GIVEN q IS A a, w YIELD w` becoming `GIVEN q IS A a, w IS A b YIELD w`, both `FUNCTION FROM a AND b TO b` with this PR.
  With this PR it rejects a real change that `main` applies: `GIVEN q IS A a, w YIELD w` becoming `GIVEN q IS A a, w YIELD q` goes from `FUNCTION FROM a AND b TO b` to `FUNCTION FROM a AND b TO a`, where `main` printed both as `FUNCTION FROM a AND a TO a`.
- Type-error messages still print the checker's internal names (`x3`): a message prints several types side by side, and naming each one separately could make a message disagree with itself.
- jl4-mlir's schema has its own `returnTypeDisplay` (`jl4-mlir/src/L4/MLIR/Schema.hs:1834`), which prints a type variable as `TYPE`.

## Where it lives

- `prettyTypeForDisplay` (`jl4-core/src/L4/Print.hs:123`) names the variables in order of first appearance and skips the names that `collectTypeNameTexts` (`:131`) finds in the type, the type names and `FOR ALL` binders.
- `prettyCheckError (CheckInfo t _)` uses it (`jl4-core/src/L4/TypeCheck.hs:4987`), and so do the REPL's `:info`, `:env` and `:type` (`jl4-repl/app/Main.hs:938`, `:993`, `:1040`), the web editor's hover (`jl4-core/src/L4/API.hs:546`), the VS Code hover (`jl4-lsp/src/LSP/L4/Actions.hs:448`), the inspector (`jl4-lsp/src/LSP/L4/Inspector.hs:470`) and `returnType` (`jl4-service/src/Compiler.hs:474`).

The skip costs time linear in the number of type variables and of type names.
`l4 check` on 4000 `#CHECK GIVEN x YIELD x` in a module declaring 4000 types named `a` to `v153` took 4.87 s at this PR's head, against 4.73 s for `b3f799fa1` (best of three, macOS arm64, measured at different times).
One `#CHECK` of a function from 4000 type variables into a function over those 4000 types took 1.26 s, against 1.38 s for `b3f799fa1`, which removed duplicate variables in quadratic time.

## Tests that pin it

- `jl4/examples/ok/check-display-typevars.l4` and `jl4/examples/ok/check-display-collision.l4`, each with its four goldens.
- The gensym lines in `ok/tests/tbd.golden`, `ok/tests/reverseaux.golden` and `not-ok/tc/tests/error-directive-ambiguity.golden` are re-blessed.
- The REPL's `:type`: `describe "the REPL's :type"` in `jl4/tests-cli/Main.hs:1773`; `:info` and `:env`: `describe "the REPL's :info and :env"` (`:1796`). Both drive the binary.
- The web editor's hover: `jl4-core/test/HoverApiSpec.hs`, which calls `l4Hover`.
- The VS Code hover: `jl4-lsp/test/HoverDisplaySpec.hs`.
- `#CHECK`, the inspector and the deployed `returnType` giving one text: `jl4-service/test/DisplayNamesAgreeSpec.hs`.
