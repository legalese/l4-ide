# Built-in names without spaces

## Summary

- `IS INTEGER` is renamed `ISINTEGER`, and `WAIT UNTIL` is renamed `WAITUNTIL`.
- These built-ins are removed: `EVER BETWEEN`, `ALWAYS BETWEEN`, `WHEN LAST`, `WHEN NEXT`, `VALUE AT`, `EVAL AS OF SYSTEM TIME`, `EVAL UNDER VALID TIME`, `EVAL UNDER RULES EFFECTIVE AT` and `EVAL UNDER RULES ENCODED AT`.

The old names are not kept as aliases. A file that uses one gets "I could not find a definition for the identifier".

## Why

**Renames: spelling consistency of built-ins.**
Every other built-in is written as one word: `STRINGLENGTH`, `TOSTRING`, `DATEVALUE`, `EVALTRACE`, or `TYPE_FIELD` for the date and time families (`DATE_DAY`, `TIME_HOUR`).
`IS INTEGER` and `WAIT UNTIL` were the only ones with a space, so they alone had to be written in backquotes.

**Removals: these should be library functions, not built-ins.**
The five range functions applied a function to each day of a range of dates. They also set a "valid time" and a "rules date" while doing so, but nothing in the evaluator read either.
Of the four `EVAL …` built-ins, only `EVAL AS OF SYSTEM TIME` changed a result, by moving what `TODAY`, `NOW` and `CURRENTTIME` read. The other three set temporal settings that nothing read.
No standard library used any of them; only the built-ins page, its example file and one test fixture did.

## What changed

- **Type checker** (`L4.TypeCheck.Environment`): the two names are renamed; the nine removed built-ins and their types are gone.
- **Evaluator** (`L4.EvaluateLazy.Machine`, `L4.Evaluate.Operators`, `L4.Evaluate.ValueLazy`, `L4.Print`): their frames, dispatch and binary and ternary operations are gone.
- **Temporal context** (`L4.TemporalContext`): reduced to what is read, the system time behind `TODAY`, `NOW` and `CURRENTTIME`, and the time zone set by `TIMEZONE IS`. `EvalClause`, `applyEvalClauses` and `withEvalClauses` are gone, with `TemporalContextSpec`.
- **MLIR lowering** (`jl4-mlir`): matches `ISINTEGER`.
- **Docs, examples and the `writing-l4-rules` skill** use the new names. The "Looking across days" section of the built-ins page and its example file are gone.
- **Specs:** `specs/todo/TEMPORAL-MASTER.md`, `TEMPORAL_EVAL_SPEC.md` and `TEMPORAL_PRELUDE_MACROS.md`, which planned these built-ins, are removed.

## Migration

| Before                                                                                               | After                                         |
| ---------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `` `IS INTEGER` x ``                                                                                 | `ISINTEGER x`                                 |
| ``(`WAIT UNTIL` t)`` in a `#TRACE`                                                                   | `WAITUNTIL t`                                 |
| `` `EVER BETWEEN` ``, `` `ALWAYS BETWEEN` ``, `` `WHEN LAST` ``, `` `WHEN NEXT` ``, `` `VALUE AT` `` | an ordinary function over the dates concerned |
| the four `` `EVAL …` `` built-ins                                                                    | none                                          |

## Tests

- `jl4/examples/ok/float.l4` uses `ISINTEGER`, and `jl4/examples/ok/contracts.l4` uses `WAITUNTIL`; their golden files are regenerated.
- `jl4/examples/ok/temporal-acceptance.l4`, which tested only the removed built-ins, is removed with its golden files.
