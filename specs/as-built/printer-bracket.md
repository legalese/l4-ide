# Printer: bracket nested connectives (as built)

As built on `main` by legalese/l4-ide#547.
Source spec: none.
The rule came from `unstable`, where it was written for smucclaw/l4-ide#932; this page describes only what `main` has.

Scope: the operand-bracketing rule of `prettyLayout` (`parensIfOpenTailed`, its four call sites, and a `scanOp` that flattens a chain through the checker's desugared form).
No other spec under `specs/` owns `prettyLayout` grouping.

## What it does

`prettyLayout` turns a checked module back into L4 source.
`l4 batch` and the REPL re-emit a module through it and then parse and run the printed text, so a printer that loses grouping changes answers without any error.
Before this change each operand of an `AND`/`OR`/`RAND`/`ROR` chain was printed bare, so `(a OR b) AND c` came back as `a OR b AND c`, and `(NOT x) AND y` as `NOT x AND y`.
Now an operand is bracketed when it is itself a connective, a `NOT`, or has an open tail that would swallow the next connective; everything else stays bare.

## Where it lives

- `jl4-core/src/L4/Print.hs:331`, `:336`, `:341` and `:346`: the `And`/`Or`/`RAnd`/`ROr` arms of `printWithLayout` render `prettyConj "<op>" (fmap parensIfOpenTailed chain)`.
- `jl4-core/src/L4/Print.hs:447-487`: the note explaining both reasons to bracket, with the failures that motivated it.
- `jl4-core/src/L4/Print.hs:488-525`: `parensIfOpenTailed :: LayoutPrinterWithName a => Expr a -> Doc ann` and its local `openTailed` classifier.
- `jl4-core/src/L4/Print.hs:842-863`: `scanOp` and `scanOr`/`scanAnd`/`scanROr`/`scanRAnd`, which carry a `HasName a` constraint.
- `jl4-core/src/L4/Print.hs:865-870`: `prettyConj`, unchanged.
- Consumers: `jl4/app/L4/Cli/Batch.hs:132` and `jl4-repl/app/Main.hs:587`, `:670` and `:719`; also evaluation traces and `#EVAL` output.

## Behaviour and rules (read in code)

- `parensIfOpenTailed e` classifies `carameliseNode e`, i.e. what will be printed, so a desugared `App __GEQ__ [a, b]` counts as `Geq a b` and stays bare.
- Bracketed because it is a connective nested in a chain of a different kind: `And`, `Or`, `RAnd`, `ROr`, `Implies`, and `Not` (`NOT` binds looser than the connectives, per the note).
- Bracketed because of an open tail: `App` with at least one argument (`f OF x, y`), `AppNamed`, `Concat`, `List`, `Consider`, `MultiWayIf`, `IfThenElse`, `Regulative`, `LetIn`, `Where`, `Lam`, `Breach` with a `BY` or `BECAUSE`, `Post`, `Event`.
- Left bare: a bare `BREACH`, literals, variables, projections, and every other operator, including comparisons (`EQUALS`, `GREATER THAN`, …), which bracket their own operands or bind tighter.
- `scanOp` matches on `carameliseNode e` at every level, so a chain the checker left as `App __AND__ [a, b]` still flattens fully; without that, `a AND b AND c AND d` printed as `a AND (b AND (c AND d))`.
- An associative chain of one connective is therefore flattened and printed without brackets, and only a genuinely different nested operand reaches `parensIfOpenTailed`.
- `NOT` prints its own operand with plain `printWithLayout` (`Print.hs:351-352`). That is safe because the parser reads `NOT x AND y` as `NOT (x AND y)`.

## Diagnostics

None; this is a printer change.

## Tests and fixtures that pin it

- `jl4/tests-cli/Main.hs`, "l4 batch keeps the grouping the rule wrote": five cases run `l4 batch` on `jl4/tests-cli/fixtures/batch-bracket.l4` and check the answer the fixture's own `#EVAL` gives under `l4 run`.
  Each puts one kind of operand inside an `AND`: an `OR`, a `NOT`, an `IMPLIES`, an `IF … THEN … ELSE`, and a function call.
  With the printer as it was before this change, `l4 batch` answered `true` to all five, with `"status":"success"` and no diagnostic; `l4 run` and the fixed printer answer `false`.
- Three trace goldens show the brackets and would move if they were dropped:
  - `jl4/examples/ok/tests/lazytrace-exception.golden:33`, which prints `x AND (and OF xs)`;
  - `jl4/examples/legal/tests/ceo-performance-award.golden:59`, where the `PROVIDED` guard's `OR` of two `OF` applications is bracketed inside the `AND`, and each application is bracketed too;
  - `jl4/examples/legal/tests/ny-environmental-7.3.golden:8` and `:15`, where a `CONSIDER` conjunct is bracketed.
- Before this change, `l4 batch` on `main` re-printed `(a OR b) AND c` as `a OR b AND c` and `(NOT x) AND y` as `NOT x AND y`.
  The parser, which this change does not touch, reads those as `a OR (b AND c)` and `NOT (x AND y)`: measured with `#EVAL`, `TRUE OR FALSE AND FALSE` is TRUE where `(TRUE OR FALSE) AND FALSE` is FALSE, and `NOT TRUE AND FALSE` is TRUE where `(NOT TRUE) AND FALSE` is FALSE.

## Limits (verified on `main`)

- Nothing checks that every corpus file re-prints to source with the same answers.
  The batch cases above pin the five shapes they name; a shape they do not name, and the three goldens do not exercise, could regress without a failing test.
- The note at `Print.hs:454` and `:476` cites `regcf-wizard.l4` and `regcf.l4` and says they now live in legalese/canon; neither file is in this repository.
- `openTailed` has no arm for the state-ledger constructors (`Record`, `ReadCell`) or `Refuse`, because `main` does not have them.
  They fall to the `_ -> False` arm, which is the right answer for an atom and would need revisiting if a later change adds an open-tailed form of one.
