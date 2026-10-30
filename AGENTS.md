# AGENTS.md

Coding guidelines for AI agents working in this repository.

## About L4

**L4 is a domain-specific programming language for law** — a layout-sensitive, strongly-typed functional language (Python-ish indentation, Haskell-ish types) for formalizing legal rules and contracts as executable specifications.

## Repository Structure

### Haskell (Cabal)

| Package            | Purpose                                        |
| ------------------ | ---------------------------------------------- |
| `jl4-core/`        | Core language (parser, typechecker, evaluator) |
| `jl4/`             | CLI (`l4`) and JSON schema generator           |
| `jl4-lsp/`         | Language Server Protocol for IDE support       |
| `jl4-repl/`        | Interactive REPL                               |
| `jl4-service/`     | REST API for decision evaluation               |
| `jl4-websessions/` | Session persistence service                    |
| `jl4-query-plan/`  | Query planning utilities                       |
| `jl4-wasm/`        | WASM build of L4 for in-browser evaluation     |

### TypeScript (npm workspaces + Turborepo)

| Package            | Purpose                                    |
| ------------------ | ------------------------------------------ |
| `ts-apps/vscode/`  | VS Code extension                          |
| `ts-apps/jl4-web/` | Web-based editor (Svelte)                  |
| `ts-apps/webview/` | Shared webview UI assets                   |
| `ts-shared/`       | Shared libraries (RPC client, visualizers) |

### Documentation

| Location      | Content                                                    |
| ------------- | ---------------------------------------------------------- |
| `doc/`        | L4 language docs (reference, courses, tutorials, concepts) |
| `specs/`      | Development specs (`todo/`, `done/`, `roadmap/`)           |
| `*/README.md` | Component-specific setup and usage                         |

### Extending the `l4` command line

The `l4` command table is a library, the `l4-cli` sublibrary of `jl4` (`mainWith` in `jl4/app/L4/Cli/Main.hs`), and `executable l4` is `mainWith noExtensions`.
Another package can depend on that library and build an executable of its own that adds top-level subcommands, `l4 export` formats and `l4 explore --emit` targets.
`L4.Cli.Extensions` (`jl4/app/L4/Cli/Extensions.hs`) defines what can be added, and its header says how each addition fails.
A package cloned into `etc/verify/`, which is gitignored, is built with the rest by `cabal build all` through `optional-packages:` in `cabal.project`.
With that directory absent, nothing changes, and nothing in this repository depends on such a package.
Cabal reads every package under `etc/verify/` when it plans a build, whatever you build.
One whose `.cabal` file does not parse, or whose dependencies cannot be solved, fails every cabal command in the checkout, the community packages' too, and `etc/verify-branch.sh` with them (measured 2026-10-30: `Cabal-7107` for a dependency that cannot be solved, and `etc/verify/<file>.cabal: error` for a file with no `name`).
One that plans but no longer compiles against this tree fails `cabal build all`, and so the gate, and not a build of a community target alone.
To recover, move the directory out of the checkout (`mv etc/verify ../verify-aside`), which gives back the community build, then update or fix the package and move it back.

## Essential Commands

```bash
cabal build all                          # Haskell
npm run build                            # TypeScript

cabal test all                           # Haskell tests
npm test                                 # TypeScript tests

npm run format                           # TypeScript formatting (required — CI rejects unformatted)

cabal run l4      -- run file.l4         # Typecheck and evaluate a file
cabal run l4      -- check file.l4       # Fast typecheck-only
cabal run jl4-repl -- file.l4            # REPL
```

**Before every commit:** `cabal test all && npm ci && npm run format`

## Git Workflow

Never commit to `main`. Create a feature branch, push, open a PR. After pushing, wait ~10 minutes for CI, then address any reviewer comments or failures without waiting for further input.

## Testing

### Golden files

First run creates the golden file (test fails). Second run validates (should pass). To regenerate: delete the golden files and run tests twice.

### Test locations

Tests live under `jl4/examples/`:

- `jl4/examples/ok/` — files that should succeed
- `jl4/examples/not-ok/` — files that should fail (subdirs: `tc/`, `nlg/`)
  - Except the three top-level `not-ok/export-*.l4` fixtures, which must type-check: their schema goldens pin that an `@export` in an unsupported position yields no default export.
- `jl4/examples/experiments/` — real-world examples
- `jl4/examples/legal/`, `jl4/examples/lsp/` — domain/LSP fixtures

### Filter tests

```bash
cabal test jl4-test --test-options='--match "pattern"'
```

## Adding Features

1. Write spec in `specs/todo/{FEATURE-NAME-SPEC}.md`
2. Add test fixtures under `jl4/examples/ok/` or `jl4/examples/not-ok/`
3. Implement in the relevant `L4.*` modules under `jl4-core/src/L4/`
4. Run `cabal test all` twice to establish golden files
5. Move spec to `specs/done/`
6. If you added keywords/types/operators, update `doc/reference/` and `doc/reference/GLOSSARY.md`
7. If you touched docs, run `./doc/test-docs.sh`

## L4 Language Pipeline

```
Source (.l4) → Parser → AST → Desugarer → Type Checker → Evaluator → Results
```

Key modules in `jl4-core/src/L4/`:

- `Parser.hs` — layout-sensitive parsing
- `Syntax.hs` — AST definitions
- `Desugar.hs` — mixfix resolution, sugar expansion
- `TypeCheck.hs` — bidirectional type checking
- `EvaluateLazy.hs` — lazy evaluation with traces

## Shell Quoting

Backticks are meaningful in L4 (quoted identifiers) but trigger command substitution in bash/zsh:

```bash
rg 'foo `bar`'     # Good — single quotes
rg "foo \`bar\`"   # Good — escaped
rg foo `bar`       # BAD — executes `bar`
```

## Package Manager

- `npm ci` for regular development (reproducible, faster)
- `npm install` only when adding/updating packages

## Requirements

- **Haskell:** GHC 9.10.2, Cabal 3.10+ (via GHCup)
- **Node.js:** >= 24
- **GraphViz:** `dot` for trace visualization

Nix users: `nix-shell nix/shell.nix` provides all dependencies.

## Writing Documentation

For authoring actual L4 rules, prefer the `writing-l4-rules` skill — it covers syntax, style, and validation in depth. This section is only about the docs tree.

### Structure

| Folder           | Purpose                                              |
| ---------------- | ---------------------------------------------------- |
| `doc/reference/` | Precise specs for keywords, types, operators, syntax |
| `doc/courses/`   | Structured learning paths                            |
| `doc/tutorials/` | Task-oriented guides ("How do I do X?")              |
| `doc/concepts/`  | Explanations of ideas and design decisions           |

Keep these index files accurate: `doc/README.md`, `doc/reference/GLOSSARY.md`, and each section's `README.md` / `SUMMARY.md`.

`doc/` is published at <https://legalese.com/l4>. Each section's `SUMMARY.md` becomes that tab's sidebar, which only shows the sub-pages of the branch the reader is in. The sidebar is for finding your way, not a full index:

- Keep a section's sidebar to a handful of entries.
- Fold variants and short pages into a parent page instead of adding entries; for example, multi-clause DECIDE is a section of DECIDE, not its own page.
- Let each section's `README.md` list the pages under it.
- Give each topic one home and link to it from elsewhere.
- Keep a page's H1 the same as its sidebar title.

When a page moves or is merged away, add its old slug to `doc/redirects.json` (`"reference/functions/WHERE": "reference/functions/LET#where"`), so released tools and search results that link to it keep working.

### L4 in docs

Prefer separate `.l4` files over inline code blocks so examples are validated:

```markdown
**Example:** [eligibility-example.l4](eligibility-example.l4)
```

All L4 code must compile. Validate with `l4 check path/to/file.l4` (or `cabal run l4 -- check path/to/file.l4` from a Haskell checkout) or the MCP validator.

Write identifiers that read like natural language for legal audiences: `` `the applicant` `` not `applicant`, `` `valid identification` `` not `hasValidID`. No camel-case or. Be very descriptive.

### Validating docs

```bash
./doc/test-docs.sh
```

This checks markdown links, compiles every `.l4` file in `doc/`, flags orphaned files (README.md and SUMMARY.md are exempt from the orphan check), and checks that every redirect in `doc/redirects.json` leaves a removed page and lands on an existing page and anchor. Fix all errors before committing. Use relative paths (`../concepts/README.md`) when cross-linking.
