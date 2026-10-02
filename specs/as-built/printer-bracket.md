# Printer: bracket nested connectives (as built)

As built on unstable at 73a953821. Source spec: none. Differences from the source spec: not applicable.

Scope: the grouping part of #214 (`parensIfOpenTailed`, its four call sites, and the caramelising `scanOp`), applied to main.
The rest of #214 (the checker-gensym fix, the Inert and obligation layouts, keyword quoting, the `prettyLayout round-trip` test block in `jl4/tests/Main.hs`, the CLAUDE.md §3.2 notes and the `l4 batch` format docs) is not carried here.
No spec under `specs/` owns `prettyLayout` grouping or cites smucclaw/l4-ide#932 (grepped on unstable).

## What it does

`prettyLayout` turns a checked module back into L4 source.
`l4 batch` and the REPL re-emit a module through it and then parse and run the printed text, so a printer that loses grouping changes answers without any error.
Before this change each operand of an `AND`/`OR`/`RAND`/`ROR` chain was printed bare, so `(a OR b) AND c` came back as `a OR b AND c`, and `(NOT x) AND y` as `NOT x AND y`.
Now an operand is bracketed when it is itself a connective, a `NOT`, or has an open tail that would swallow the next connective; everything else stays bare.

## Where it lives

- `jl4-core/src/L4/Print.hs:757-777` @ 73a953821: the `And`/`Or`/`RAnd`/`ROr` arms of `printWithLayout` render `prettyConj "<op>" (fmap parensIfOpenTailed chain)`.
- `jl4-core/src/L4/Print.hs:948-986` @ 73a953821: the note explaining both reasons to bracket, with the measured failures.
- `jl4-core/src/L4/Print.hs:987-1027` @ 73a953821: `parensIfOpenTailed :: LayoutPrinterWithName a => Expr a -> Doc ann` and its local `openTailed` classifier.
- `jl4-core/src/L4/Print.hs:1757-1789` @ 73a953821: `scanOp` and `scanOr`/`scanAnd`/`scanROr`/`scanRAnd`, which now carry a `HasName a` constraint.
- `jl4-core/src/L4/Print.hs:1791-1796` @ 73a953821: `prettyConj`, unchanged.
- Consumers: `jl4/app/L4/Cli/Batch.hs:244` and `jl4-repl/app/Main.hs:587`, `:678`, `:727` @ 73a953821; also evaluation traces and `#EVAL` output.

## Behaviour and rules (read in code)

- `parensIfOpenTailed e` classifies `carameliseNode e`, i.e. what will be printed, so a desugared `App __GEQ__ [a, b]` counts as `Geq a b` and stays bare.
- Bracketed because it is a connective nested in a chain of a different kind: `And`, `Or`, `RAnd`, `ROr`, `Implies`, and `Not` (NOT binds looser than the connectives, per the note).
- Bracketed because of an open tail: `App` with at least one argument (`f OF x, y`), `AppNamed`, `Concat`, `List`, `Consider`, `MultiWayIf`, `IfThenElse`, `Regulative`, `LetIn`, `Where`, `Lam`, `Breach` with a `BY` or `BECAUSE`, `Post`, `Event`.
- Left bare: a bare `BREACH`, literals, variables, projections, and every other operator, including comparisons (`EQUALS`, `GREATER THAN`, …), which bracket their own operands or bind tighter.
- `scanOp` matches on `carameliseNode e` at every level, so a chain the checker left as `App __AND__ [a, b]` still flattens fully; without that, `a AND b AND c AND d` printed as `a AND (b AND (c AND d))`.
- An associative chain of one connective is therefore flattened and printed without brackets, and only a genuinely different nested connective reaches `parensIfOpenTailed`.

## Diagnostics

None; this is a printer change.

## Tests and fixtures that pin it

- No test checks that printed source evaluates to the same answer; the `prettyLayout round-trip` block (#214's rest) checks only re-parse and re-type-check.
- Three trace goldens show the brackets and would move if they were dropped:
  - `jl4/examples/ok/tests/lazytrace-exception.golden:33` @ 73a953821, which prints `x AND (and OF xs)`;
  - `jl4/examples/legal/tests/ceo-performance-award.golden:58` @ 73a953821, where the `PROVIDED` guard's `OR` of two `OF` applications is bracketed inside the `AND`, and each application is bracketed too;
  - `jl4/examples/legal/tests/ny-environmental-7.3.golden:6` @ 73a953821, where a `CONSIDER` conjunct is bracketed.
- The by-hand evaluation differential (`JL4_EVALDIFF=1`, CLAUDE.md §3.2.1 on unstable; both came with the rest of #214 and are not on main or in this PR) is the check for this class of bug; it is deliberately not a test.
- Before this change, `l4 batch` on main re-printed `(a OR b) AND c` as `a OR b AND c` and `(NOT x) AND y` as `NOT x AND y`. The parser, which this PR does not touch, reads those as `a OR (b AND c)` and `NOT (x AND y)`: measured with `#EVAL`, `TRUE OR FALSE AND FALSE` is TRUE where `(TRUE OR FALSE) AND FALSE` is FALSE, and `NOT TRUE AND FALSE` is TRUE where `(NOT TRUE) AND FALSE` is FALSE.

## Limits and known defects on unstable (verified)

- The note at `Print.hs:955` and `:976` @ 73a953821 cites `regcf-wizard.l4` and `legal/regcf/regcf.l4`; neither file is on main (Reg CF now lives in legalese/canon), and this change re-words both citations to say so.
- On unstable, CLAUDE.md §3.2.1 cites the same stale `legal/regcf/regcf.l4` path, but that text is #214's rest.
- The guard is golden-and-manual only, so a regression in a shape the three goldens do not exercise would pass CI.

## Later changes

- `Record{}` and `ReadCell{}` in `openTailed` (`Print.hs:1012-1013` @ 73a953821) are #214's own lines, but they name constructors from #31 (state ledger); this change drops them, and #31 would need them back.
- #334 (REFUSE) adds `Refuse{} -> False` to `openTailed` (`Print.hs:1019`) and a `Refuse{}` atom arm to `parensIfNeeded`.
- #356 (NOT-reach single-line check, `1d0610096`) routes `Not`'s own operand through `parensIfOpenTailed` (`Print.hs:782-789` @ 73a953821), because the checker then refuses `NOT a AND b` on one line; with this change `NOT` still prints its operand with plain `printWithLayout`.
- The comment at `Print.hs:784` @ 73a953821 cites `SET-OPERATORS-SPEC §18.1`; it is #356's line, not this feature's.
- #214's rest lands the gensym fix, the obligation and Inert layouts, keyword quoting and the round-trip test around this code; `prettyObligation`'s window was later reshaped by #412.
