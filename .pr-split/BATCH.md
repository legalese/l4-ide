## This PR was part of an interlock that has since been consolidated

An earlier revision of this section named a **15-PR merge batch** that had to land as one unit. That
is no longer the shape of the work, and the roster it listed is now largely closed. What happened:

Twelve of those PRs could not build separately, because the entangling changes are to *types* in
modules `main` already has — `Syntax.hs` removes the `Expr` constructor `Exponent`, widens
`MkAssume` 4→5, `MkTypedName` 4→5 and `MkOptionallyTypedName` 3→4, and adds strict fields to
`MkCheckState`; the evaluator widens `MkEvalDirectiveResult` 3→4. Every consumer had to change in
the same commit, in **both** directions, and the consumers were spread across six packages. No
ordering resolved it.

**Eight of them were therefore consolidated into [#257](https://github.com/legalese/l4-ide/pull/257),
the language core** — `lang-syntax-typecheck` (#245), `lang-eval-ledger` (#241), `ladder-viz`
(#240), `lang-printer` (#243), `lsp` (#246), `lang-sets` (#244), `lang-imports-stdlib` (#242) and
`actus-archive` (#230), all now closed. #257 was built by taking `unstable`'s version of whatever
the compiler rejected, to a fixed point, so it contains no hand-written intermediate code. It is
green: `cabal build all` clean, 7/7 suites, `jl4-test` 2039 examples 0 failures.

**What remains for this PR is a one-way dependency**, which ordering does resolve. It no longer has
to merge simultaneously with anything — it simply has to merge *after* its prerequisites. Those are
named in the metadata line at the top of this body and in the merge-order guide.

The full measurement — six builds, with the verbatim first error of each failing one — is recorded
in `.pr-split/DEPENDENCIES.md` on the branch `claude/unstable-branch-reorganization-6cle91`.
