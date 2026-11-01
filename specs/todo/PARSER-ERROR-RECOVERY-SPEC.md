# Parser Error Recovery

**Status:** Proposal. Nothing here is implemented.

## Problem

One compile reports one syntax error, even when a file has several. Whoever is fixing the file, a person or an agent, finds the next error only by fixing the current one and compiling again.

How often this happens when an agent edits L4:

- 295 of 299 parse failures reported exactly one error.
- Consecutive parse-failure-to-parse-failure edits were the largest class of fix-loop steps (211).

The goal is that one compile reports the independent syntax errors in a file, one per broken declaration, without inventing errors that are not there.

## What the parser does today

`topdeclWithRecovery` in `jl4-core/src/L4/Parser.hs` is the only use of `withRecovery`:

```haskell
topdeclWithRecovery n = do
  start <- lookAhead anySingle
  withRecovery
    (\e -> do
      _ <- takeWhileP Nothing (\t -> not (isSpaceToken t) && t.range.start.column > 1)
      current <- lookAhead anySingle
      registerParseError e
      if start == current
        then parseError e
        else topdeclWithRecovery n
    )
    topdecl
      <|> attachAnno (Section emptyAnno <$> annoHole (section (n + 1)))
```

So recovery exists, and it can report several errors: `DECLARE`, blank line, `DECLARE`, blank line, a valid rule gives two errors today. It almost never does, for three separate reasons. Each was confirmed against `l4 check`.

### 1. The skip stops at the first whitespace token

Whitespace tokens are in the stream, so `not (isSpaceToken t)` ends the skip after one run of adjacent tokens, not at the end of the declaration. For an error inside a declaration, recovery re-enters `topdecl` on a space token, which fails at once with no progress.

The one case that works is an error whose offending token is already at column 1: the skip takes nothing, that token starts the next declaration, and parsing goes on. That is the `DECLARE` example above.

### 2. A failed recovery discards every error found so far

If the recovery parser of `withRecovery` fails, Megaparsec reports the original error from the original state. Errors registered inside the recovery branch go with that state.

Recovery nests (the handler calls `topdeclWithRecovery`), and its no-progress branch ends in `parseError e`. So one failure at any depth collapses the whole chain to the outermost error. This is what turns "three broken declarations" into "exactly one error".

```text
GIVETH A NUMBER
b MEANS ) 2

GIVETH A NUMBER
c MEANS ) 3

GIVETH A NUMBER
d MEANS ( 4
```

reports only `2:9 unexpected )`.

### 3. Most errors are not failures of `topdecl`

An expression that stops early is a success. In `a MEANS 1 +`, `topdecl` returns `a MEANS 1` and leaves `+` unread. `manyLinesPos` then stops, because `+` is not at the section's column, the section ends, and `p <* eof` in `runJl4Parser` fails with `unexpected + ... expecting ;, end of input, ...`.

That failure happens outside `withRecovery`, so nothing recovers from it:

```text
GIVETH A NUMBER
a MEANS 1 +

GIVETH A NUMBER
b MEANS 1 +
```

reports only `2:11 unexpected +`.

The same goes for a section nested under `§`: its `manyLines` ends and the failure surfaces in whatever encloses it.

## Proposal

Declaration-level recovery with a single recovery loop that cannot fail. No expression-level recovery, and no AST from a file with errors.

### Design

Replace the section body's `lsepBy (const (topdeclWithRecovery n)) ...` with a loop that keeps the current success path, and adds three things:

1. **Handler that cannot fail.** When `topdecl` fails, register the error and resynchronise. Never call `parseError` from the handler. If the resync makes no progress, consume one token and resynchronise again, so the loop always terminates.
2. **Leftovers are errors.** After a successful `topdecl`, look at the next token that is not a space. If it is at the section's column, an end of input, or a `;` or `§`, carry on as today. Anything else is the case in reason 3: raise the same error the parser would have raised at that token (so the message and its `expecting` list do not change), register it, and resynchronise.
3. **A resync that skips to a declaration start.** Consume tokens, whitespace included, until the next token is a declaration start or the end of input.

A declaration start is a non-space token at the section's column whose token is one of:

- `GIVEN`, `GIVETH`, `GIVES`, `DECIDE`, `DECLARE`, `ASSUME`, `IMPORT`;
- a directive (`#EVAL` and the rest);
- `§`;
- an annotation (`@desc`, `@export`, `@nlg`, `@ref`, ...);
- an identifier, when the same line has a `MEANS` or `IS` after it (the bare `name MEANS ...` form).

The token set matters more than the column. A misindented body line, `THEN`, `ELSE`, or a continuation at column 1 must not count as a new declaration: see Risks.

`§` must keep working: today the section alternative after `<|>` relies on `topdecl` failing without consuming, and on the handler failing with it. The new loop has to check for `§` and for the end of input before it calls `topdecl`, so that neither is ever reported as an error.

Two limits keep the output honest:

- At most one error per declaration. After reporting an error, stay silent until the next declaration start.
- A cap (proposed: 20 errors per file), after which parsing stops. `parse/too-many-errors` would be a new diagnostic code for the note that says so; see `jl4-lsp/DIAGNOSTIC-CODES.md`.

### What stays the same

- `execParser` still returns `Left` when any error is registered. A file with a syntax error produces no AST, no type-check and no evaluation. Downstream rules are untouched.
- The first error of a file does not change: same position, same message, same `expecting` list. Recovery only adds errors after it.
- Each error keeps its `parse/...` code. Reason 3 leftovers get `parse/unexpected-<token kind>` like any other.

## Risks

**Cascading false errors.** This is the main risk. An error reported after the first may be caused by the first, and then a fix-loop chases something that is not wrong. Known sources:

- _Misindented continuations._ A body line at column 1 looks like a new declaration. The declaration-start token set is the defence: `1 + 2` or `ELSE 3` at column 1 is not a start.
- _An unclosed bracket or `IF`._ Text after it may parse as a different declaration. Resynchronising on keywords and not on brackets keeps this to one extra error at most; the one-per-declaration limit bounds it.
- _`GIVEN` and `GIVETH` split from their definition._ A `GIVEN` block is several lines at column 1 and one declaration. An error in the `GIVEN` resynchronises at `GIVETH`, which is then a signature with no definition problem of its own, so it stays quiet.
- _A resolved name with no definition._ Parsing does not resolve names, so a broken declaration leaves no "undefined name" errors behind: a file with a syntax error is never type-checked. This is why declaration-level recovery is much safer in the parser than it would be in the checker.

**Mixfix hints.** `GetMixfixRegistry` returns an empty registry when the hint-free first parse fails, and `GetParsedAst` then parses with no hints. Today that cannot matter, because the first parse stops at the same place. With recovery the parser keeps going, so a later declaration that needs a hint from this module or an import could report a false error. Options, best first:

1. Build the registry from the tokens or from the declarations parsed so far, even when the parse failed.
2. If the registry is empty because the first parse failed, report only errors in declarations that use no mixfix form.

This has to be settled before the feature ships. The fixtures below include this case.

**Import edges.** `GetImportEdges` also reads the first parse and returns no edges when it fails. That behaviour stays: a file with a syntax error has no edges. It does not get worse.

**Nested constructs that rely on failure.** `try` around alternatives such as `decidePatternMatch`, and the `clauseMemo` state, assume that failure backtracks. Recovery sits only at the section level, outside all of them, so they are not affected. `PState` (`nlgs`, `refs`, `comments`) is rolled back with a failed branch and must remain consistent for the declarations that parsed.

**Performance.** Each resync is linear in the tokens skipped, and each token is skipped once. The cap bounds pathological files. `clauseMemo` is keyed by offset and is unaffected.

**Client behaviour.** Clients see more diagnostics for a broken file. The Problems panel, the `blockingErrors` of `l4/getExportedFunctions` and `l4 check --json` all take a list already. Tools that report "the" parse error should take the first.

## Testing

**Fixtures.** Add `jl4/examples/not-ok/tc/parse-recovery-*.l4`, which the `tc fails` golden suite picks up, one file per behaviour:

- three broken declarations give three errors (reason 1 and 2);
- `a MEANS 1 +` twice gives two errors (reason 3);
- an error followed by `§`, and an error inside a `§` section, with a valid section after it;
- an error at the last token of the file, and a file ending mid-declaration;
- misindented body line at column 1 gives one error, not two;
- `ELSE` at column 1 gives one error;
- unclosed `(`, with valid declarations after it, gives one error;
- `GIVEN` block with a broken type, followed by its `GIVETH` and definition, gives one error;
- a declaration that uses a mixfix rule defined above a broken declaration, and one from an import: no false error.

**First error invariance.** A test over every existing `not-ok` fixture and a mutated corpus: the first error under recovery equals the error reported with recovery turned off. Keep a parser flag for this, used by tests only.

**Mutation corpus.** For each file in `jl4/examples/ok/`, delete or insert one token at seeded positions. With exactly one mutation the parser must report at least one error, and the number of errors must stay at or under a small bound. A rate of files that report more than one error is the false-cascade measure: track it, and require it to stay low (proposed: under 5%) before enabling this by default.

**Unchanged success path.** All `ok/` goldens and the exactprint identity suite must pass with no change, since recovery never runs on a valid file. Nothing in `ok/` may gain a diagnostic.

**Termination.** A property test over random token soup: the parser finishes, and the error count is at or under the cap.

**Replay.** Re-run the failing edits behind the numbers above against the new parser: count how many of the 211 consecutive parse-failure steps would have been avoided, and how many reported errors were false, by comparing each with the next transcript step.

## Out of scope

- Recovery inside a declaration, such as several errors in one `DECLARE`.
- Producing an AST, type errors or evaluation results for a file with syntax errors.
- Better wording for parse errors.
