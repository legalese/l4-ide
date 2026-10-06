# Exponent removal (as built)

As built on unstable at 73a953821. Source spec: none. Differences from the source spec: not applicable.

## What it does

Nothing changes for users.
The `Expr` type loses its `Exponent` constructor, which no parser path produced, and every pattern-match arm that consumed it is deleted.
Exponentiation is still written as the prefix builtin `EXPONENT base exp` and still evaluates: `#EVAL EXPONENT 2 10` gives 1024 (`jl4/examples/ok/numeric-domain-errors.l4:10 @ 73a953821`).
Its commit message says it resolves legalese/l4-ide#74.

## Where it lives

#83 (one commit `91a43d793`, on unstable) removed code only: 12 files, +1/−47, no golden changed; the one inserted line is `formulaText`'s combined arm in `Export/Document.hs` without `Exponent{}`.
It removed the constructor from `jl4-core/src/L4/Syntax.hs` and the consuming arms from `Desugar.hs`, `Print.hs`, `TypeCheck.hs`, `TypeCheck/Annotation.hs`, `Parser/ResolveAnnotation.hs`, `Nlg.hs`, `Export/Document.hs`, `OpenFisca/Lower.hs`, `EvaluateLazy/Machine.hs`, and `jl4-mlir/src/L4/MLIR/{Lower,Schema}.hs`.
This PR carries the same deletions except `OpenFisca/Lower.hs`, which is not on main: 11 code files, +1/−42.
On unstable, `data Expr n` is at `jl4-core/src/L4/Syntax.hs:246 @ 73a953821`, and its arithmetic constructors end at `Modulo` (`:261`).
Measured on unstable: `grep -rn '\bExponent\b' --include=*.hs` finds no constructor or arm, only an unrelated comment about number literals in `jl4/app/L4/Cli/Batch.hs:509`.

## Behaviour and rules (read in code on unstable)

`EXPONENT` is an ordinary builtin function, renamed from `exponent` at `jl4-core/src/L4/TypeCheck/Environment.hs:54 @ 73a953821` and registered under `exponentUnique` (`:968`, `:1084`).
It parses to a function application, never to a binary-operator node.
`exponentName` is deliberately absent from `builtinBinFunctions` (`jl4-core/src/L4/Desugar.hs:238-253 @ 73a953821`), so print-time caramelisation never rebuilds a binary node for it, and the printer emits the prefix form.
`BinOpExponent` is kept, because the builtin computes through it: `runBinOp BinOpExponent` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:4950 @ 73a953821`), mapped to `exponentUnique` at `:6038`.
The MLIR backend lowers `EXPONENT` (and `POW`) to the runtime call `__l4_pow` (`jl4-mlir/src/L4/MLIR/Lower.hs:2043-2044 @ 73a953821`).
The commit message says the deletion was driven by `-Wincomplete-patterns` under `-Werror`, and that no construction site existed.

## Tests and fixtures that pin it

No test was added; the three core suites stayed green with zero golden changes (commit message).
`jl4/examples/ok/numeric-domain-errors.l4:7-10 @ 73a953821` evaluates `EXPONENT` for a finite result and for two domain errors.
`jl4-core/test/PrintRoundtripSpec.hs:23, 63 @ 73a953821` checks that `DECIDE e IS EXPONENT 2 10` prints back in prefix form and re-parses (added by #66 inside #77).
Neither file is on main or in this PR: on unstable, `numeric-domain-errors.l4` and its golden came with #53, and `PrintRoundtripSpec.hs` with #66.

## Limits and known defects on unstable (verified)

Two user-visible strings still use the old spelling `TO THE POWER OF`, which does not parse on unstable (`jl4-core/src/L4/Lexer.hs` has no `POWER` token):

- `LayoutPrinter BinOp` prints `BinOpExponent` as `TO THE POWER OF` (`jl4-core/src/L4/Print.hs:1603 @ 73a953821`);
- the domain-error message reads "TO THE POWER OF produced a non-finite result (overflow, 0 to a negative power, or a negative base raised to a fractional power)" (`Machine.hs:4953`), pinned by `jl4/examples/ok/tests/numeric-domain-errors.golden:7, 9`.

Neither string is #83's code: #83 deliberately kept `BinOpExponent`, and both strings predate it.
