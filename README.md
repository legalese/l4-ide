![L4 Logo](doc/l4.svg)

# L4 with IDE

**L4** is a domain-specific programming language for law by [Legalese](https://legalese.com). It formalizes legal rules and contracts as executable specifications, bringing software engineering rigor to legal drafting and analysis.

This repository contains the L4 compiler, IDE tooling (VS Code extension, LSP, REPL, web editor), and a decision service that exposes L4 rules as REST APIs and MCP tools.

- [Design principles](https://legalese.com/l4/concepts/language-design/principles) — the principles behind L4's design and the style of writing that follows from them
- [Reading like the law](https://legalese.com/l4/concepts/language-design/linguistic-syntax) — how L4 borrows from natural language so that rules read like legal text
- [Definitions and duties](https://legalese.com/l4/concepts/legal-modeling/constitutive-vs-regulative) — constitutive and regulative rules, kept apart in the type system
- [Exceptions and defaults](https://legalese.com/l4/concepts/legal-modeling/default-reasoning) — a general rule followed by exceptions, the law's most common shape
- [How obligations unfold](https://legalese.com/l4/concepts/legal-modeling/regulative-rules) — who must, may or must not do what, by when, and what follows
- [Types as legal categories](https://legalese.com/l4/concepts/type-system/algebraic-types) — why algebraic data types fit legal structure
- [Exhaustiveness](https://legalese.com/l4/concepts/type-system/exhaustiveness) — every case of a determination handled
- [Type theory](https://legalese.com/l4/concepts/type-system/type-theory) — the formal foundations of L4's type system

## What You Get From a Single L4 File

- **REST APIs** — Expose functions as HTTP endpoints with `@export` annotations
- **AI tool integration** — MCP server for Claude, Cursor, and VS Code Copilot; WebMCP for in-browser agents
- **Interactive visualizations** — Ladder diagrams and evaluation traces rendered via GraphViz
- **Audit-grade explainability** — Every evaluation produces a trace you can follow from the top-level question down to the deciding condition
- **Test suites** — Golden-file tests and assertions
- **Generated schemas** — OpenAPI 3.0 specs and JSON schemas for integration

## Getting Started

- **Install the VS Code extension:** [L4 Rules-as-code on the Marketplace](https://marketplace.visualstudio.com/items?itemName=Legalese.l4-vscode)
- **Try the web editor:** <https://play.legalese.com/>
- **Learn L4:** [Foundation Course](https://legalese.com/l4/courses/foundation) — no prior programming experience required
- **Deploy your L4 projects to Legalese Cloud:** [Deploy your rules](https://legalese.com/l4/tutorials/deploying-rules/exporting-rules-for-deployment) — publish rules as APIs that apps and AI agents can call
- **Full documentation:** [legalese.com/l4](https://legalese.com/l4)

## Repository Layout

**Haskell (Cabal):**

| Package                                   | Purpose                                                  |
| ----------------------------------------- | -------------------------------------------------------- |
| [jl4-core](jl4-core/)                     | Core language (parser, typechecker, evaluator)           |
| [jl4](jl4/)                               | CLI tool and JSON schema generator                       |
| [jl4-lsp](jl4-lsp/)                       | Language Server Protocol for IDE support                 |
| [jl4-repl](jl4-repl/)                     | Interactive REPL                                         |
| [jl4-service](jl4-service/)               | REST API for decision evaluation                         |
| [jl4-query-plan](jl4-query-plan/)         | Query planning utilities                                 |
| [jl4-actus-analyzer](jl4-actus-analyzer/) | Static analyzer classifying L4 contracts by ACTUS / FIBO |
| [jl4-wasm](jl4-wasm/)                     | WebAssembly build of L4 for browser/Node.js              |
| [jl4-mlir](jl4-mlir/)                     | MLIR/WASM compiler backend: L4 → `.wasm` decision binary |

**TypeScript (npm workspaces + Turborepo):**

| Package                             | Purpose                                    |
| ----------------------------------- | ------------------------------------------ |
| [ts-apps/vscode](ts-apps/vscode/)   | VS Code extension                          |
| [ts-apps/jl4-web](ts-apps/jl4-web/) | Web-based editor (Svelte)                  |
| [ts-shared](ts-shared/)             | Shared libraries (RPC client, visualizers) |

**Documentation:** The language reference, tutorials, courses, and concept guides are published at [legalese.com/l4](https://legalese.com/l4); their source is in [doc/](doc/).

## VS Code Extension

Provides syntax highlighting, type checking, inline evaluation, `@export` previews, deployment management, a built-in Legalese AI chat tab, and an automatically-registered local MCP server for any AI agent that speaks the protocol (Copilot, Claude Code, Cursor, ...). Connects to [Legalese Cloud](https://legalese.cloud) or a self-hosted `jl4-service` instance. See [ts-apps/vscode/README.md](ts-apps/vscode/README.md).

## Building From Source

```bash
cabal build all          # Haskell
npm ci && npm run build  # TypeScript
```

See [AGENTS.md](AGENTS.md) for repository conventions and workflow, and [dev-start.sh](dev-start.sh) for running services locally.

**Requirements:** GHC 9.10.2, Cabal 3.10+, Node.js ≥ 20, and GraphViz (`dot`). Nix users can run `nix-shell nix/shell.nix` for a ready environment.

## The REPL

An interactive Read-Eval-Print Loop for exploring L4 code:

```bash
cabal run jl4-repl -- path/to/file.l4
```

The REPL provides live evaluation, module reloading (`:load`, `:reload`), query planning (`:decides`, `:queryplan`), and trace output (`:trace`, `:traceascii`, `:tracefile`). See [jl4-repl/README.md](jl4-repl/README.md) for the full command list.

## Trace Visualization

Every tool in this repo can render an L4 evaluation as a GraphViz diagram:

- **CLI:** `l4 trace myfile.l4 > trace.dot`, then `dot -Tsvg trace.dot > trace.svg` (or `l4 trace myfile.l4 --format svg -o out/` to generate SVG files directly)
- **REPL:** `:trace <expression>`, or `:tracefile traces/session` to capture numbered `.dot` files
- **Decision Service:** `POST /deployments/{id}/functions/{fn}/evaluation?trace=full&graphviz=true`

Install GraphViz with `brew install graphviz` or `apt-get install graphviz` to render PNG/SVG outputs.

## Application Libraries

L4 ships with foundational libraries for building legal and commercial applications:

- [Jurisdiction](https://legalese.com/l4/reference/libraries/jurisdiction) — ISO 3166 country codes, US states, Canadian provinces, EU
- [Currency](https://legalese.com/l4/reference/libraries/currency) — ISO 4217 currency codes with integer minor-unit storage
- [Legal Persons](https://legalese.com/l4/reference/libraries/legal-persons) — individuals, corporations, partnerships, LLCs, trusts
- [Holdings](https://legalese.com/l4/reference/libraries/holdings) — ownership structures and beneficial ownership

## Real-World Impact

L4 has been piloted with organizations in both public and private sectors:

- **Government regulatory compliance** — encoded secondary legislation to auto-generate citizen-facing web wizards; formal verification discovered a double-bind where contradictory clauses required and prohibited the same action.
- **Insurance policy analysis** — formalized contracts from major global providers, uncovering payout-formula ambiguities linked to significant claims leakage.
- **Legislative drafting** — working with government drafting offices on rules-as-code initiatives.
- **Commercial agreements** — transformed complex fee schedules and payment terms into L4, served via REST for enterprise integration.

## Community

- **[Discord](https://discord.gg/Q7a7NSEdNy)** — chat with the community
- **[GitHub Issues](https://github.com/legalese/l4-ide/issues)** — report bugs, request features
- **[Legalese](https://legalese.com)** — professional implementation services

L4 is published under the [Apache-2.0 License](LICENSE).
