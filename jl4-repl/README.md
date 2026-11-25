# `jl4-repl`

Interactive Read–Eval–Print Loop (REPL) for L4, built on the same parsing + typechecking + evaluation pipeline as the LSP.

## Run

```bash
cabal run jl4-repl -- path/to/file.l4
```

Or start empty, then `:load`:

```bash
cabal run jl4-repl
```

## Common Commands

- `:help` — show built-in help
- `:load <file>` / `:reload` — load a file, or load the current file again
- `:import <lib>` (`:i`) — import a module into every line you type after it, without changing the loaded file (for example `:import prelude`)
- `:imports` — list what `:import` added
- `:reset` — remove what `:import` added, and load the current file again
- `:type <expr>` — show the inferred type for an expression
- `:info <name>` / `:env` — inspect names in scope

`:load`, `:reload` and `:reset` each read the file again from disk, with every module it imports, directly or not, and every module that `:import` added.
So an edit you save while the REPL runs is seen at the next of these commands.
Until then, a line answers from the files as the REPL last read them, so after an edit, `:reload` before you ask.

When the file is not there, each of them says so (`:load` replies `Error: there is no file <path>`), and the REPL goes on.
`:load` of a file that is not there keeps the file loaded before.

Only a fresh REPL sees a module added where `IMPORT` would look before the one in use, such as a `lib.l4` put in the `JL4_LIBRARY_PATH` folder while the `lib.l4` beside your file is in use.
The REPL's copy of a module it has read is looked at first (tier 0 in [How IMPORT finds libraries](../doc/reference/libraries/resolution.md)).

## Query Planning (Elicitation)

- `:decides` — list `DECIDE` declarations in the loaded file
- `:queryplan [DECIDE] [k=v ...]` (alias `:qp`) — print query-plan ranking under partial boolean bindings

Bindings are `key=true|false` (also accepts `t/f`, `yes/no`, `1/0`).

Examples:

```text
:decides
:qp compute_qualifies walks=true eats=false
:qp vermin_and_rodent i.some_field=true
```

## Tracing

- `:trace <expr>` / `:tr <expr>` — show evaluation trace as GraphViz DOT
- `:traceascii <expr>` / `:tra <expr>` — show evaluation trace as an ASCII tree
- `:tracefile <path|off>` — save DOT traces to `<path>-NN.dot` (or restore stdout with `off`)
