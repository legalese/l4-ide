# L4 with IDE

**L4** is a domain-specific programming language for law. It formalizes legal rules and contracts as executable specifications, bringing software engineering rigor to legal drafting and analysis.

This repository contains the L4 compiler, IDE tooling (VS Code extension, LSP, REPL, web editor), and a decision service that exposes L4 rules as REST APIs and MCP tools.

## What You Get From a Single L4 File

- **REST APIs** — Expose functions as HTTP endpoints with `@export` annotations
- **AI tool integration** — MCP server for Claude, Cursor, and VS Code Copilot; WebMCP for in-browser agents
- **Interactive visualizations** — Ladder diagrams and evaluation traces rendered via GraphViz
- **Audit-grade explainability** — Every evaluation produces a trace you can follow from the top-level question down to the deciding condition
- **Test suites** — Golden-file tests and assertions
- **Generated schemas** — OpenAPI 3.0 specs and JSON schemas for integration

## Getting Started

- **Install the VS Code extension:** [L4 Rules-as-code on the Marketplace](https://marketplace.visualstudio.com/items?itemName=Legalese.l4-vscode)
- **Try the web editor:** <https://jl4.legalese.com/>
- **Encode a law or a contract:** [Encoding an Act or a Contract From Scratch](#encoding-an-act-or-a-contract-from-scratch) — prerequisites, and where to get an `l4` binary without building one
- **Learn L4:** [Foundation Course](doc/courses/foundation/README.md) — no prior programming experience required
- **Full documentation:** [doc/README.md](doc/README.md)

## Encoding an Act or a Contract From Scratch

This is the "I have a statute and I want it in L4" path. **The encoding is written by you and an AI coding assistant working together** — there is no script that reads a PDF and emits L4, and this repository does not pretend otherwise. What the repository provides is the language, the checker that tells you the moment you have written something it cannot mean, and — once an encoding exists — a pipeline that carries it out to every projection with a receipt for each one.

### What you need before you start

| #   | prerequisite                                                                 | why                                                                                                                                      |
| --- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | An `l4` binary                                                               | Every claim you make about the encoding is `l4 check` and `l4 run` telling you so. Without one you are writing text nobody has verified. |
| 2   | [Claude Code](https://claude.com/claude-code) and a clone of this repository | The two authoring skills live in `.claude/skills/` and load automatically when Claude Code starts in the clone. Nothing to install.      |
| 3   | The source text                                                              | The statute, regulation or contract, fetched from its authoritative source. Encode from the fetched text, never from memory.             |

Items 4 and 5 — Node.js ≥ 20 and GraphViz (`dot`) — are for the **pipeline**, and you do not need them on day one. They matter once the encoding exists and you want the projections and diagrams. **Claude Code can install any of these for you**; ask it to, rather than working through a toolchain by hand.

### Getting an `l4`: download it

The shortest route, and the one to try first — no Haskell toolchain, no compile:

**[github.com/legalese/prereleases/releases](https://github.com/legalese/prereleases/releases)**

These are standalone `l4` + `jl4-lsp` builds cut from this repository's `unstable` branch. Each archive extracts to a directory containing `l4`, `jl4-lsp`, a `libraries/` copy of the L4 standard library, and a `BUILD-INFO.txt` recording the exact commit it was built from. Every release body carries a copy-paste download, checksum and extract recipe for the three platforms built — `linux-x64`, `darwin-arm64`, `win32-x64`.

Prefer these over the stable line while `unstable` is far ahead of `main` — as at 2026-09-07 it is ahead by 1,470 commits.

Two things to know, because neither is obvious and both bite:

- **The shelf is cut by hand, so it can lag `unstable`.** Publishing is an outward-facing act with no cron behind it. Compare the `commit` line in the release body against the `git log` of your checkout; if the gap matters for what you are encoding, ask for a fresh cut, or build from source.
- **Never point an older binary at a newer standard library.** If the binary predates a prelude annotation your checkout has, the prelude fails to parse and you get a cascade of `could not find a definition` errors that read like a broken encoding and are nothing of the kind. Leave `JL4_LIBRARY_PATH` **unset** and the binary uses its own embedded stdlib, which matches it by construction. Only pin that variable when the binary and the tree are the same commit.

### Getting an `l4`: build it

If you need a binary at your checkout's exact commit, build it:

```bash
cabal build all
export L4=$(cabal list-bin l4)
```

**Requirements:** GHC 9.10.2, Cabal 3.10+. Nix users get a ready environment with `nix-shell nix/shell.nix`, which is the least painful version of this by some distance. Installing a Haskell toolchain from scratch is nobody's idea of a good afternoon — take the download route unless the commit gap genuinely matters.

### The workflow

Start Claude Code in the clone and describe what you want:

```bash
claude

> Here is the Act, at <url>. Encode Part 3 in L4, in the house style,
> with test assertions for each of the worked examples in the schedule.
```

The `writing-l4-rules` skill loads on any request of that shape. It carries the house style, the builtin libraries, eleven reference notes on recurring source patterns — definitions and scope, conditions, quantities, dates, duties and powers, presumptions, discretion, text that is not a rule — and the traps a general-purpose model gets wrong unaided.

From there it is the ordinary loop: draft a provision, `l4 check` it, add `#EVAL` assertions for the examples the source itself gives you, run them, and move on. Encode the source's own worked examples first — they are the only tests whose expected answers you did not invent.

### When the encoding exists, the pipeline picks it up

Only once there is an encoding does `etc/go/go.sh` become useful, and this is the right order: the pipeline **validates and projects an encoding**, it does not produce one. Register your body of law as a subject, and every later stage is scoped to it:

```bash
etc/go/go.sh new-subject sg-tax \
  --citation "Income Tax Act 1947" \
  --source-url "https://sso.agc.gov.sg/Act/ITA1947"

etc/go/go.sh doctor --subject sg-tax     # what will run, and what will not, before spending time
etc/go/go.sh plan   --subject sg-tax     # the declared stages, in order, executing nothing
```

Then, in Claude Code, the whole thing is one line — the name of the law, followed by `go`:

```
> Singapore Income Tax Act: go
```

That phrasing is the trigger for the `running-the-l4-pipeline` skill, which dispatches the driver and supplies the judgements no script can make. It carries the encoding through provenance capture, an amendment sweep, ambiguity forks, an adversarial gate, tests, and out to the projections — stopping at a human gate before anything outward-facing, and writing a hash-chained receipt for every stage. See [reviewing encoded law](doc/concepts/reviewing/reviewing-encoded-law.md) for what that run asks of you and what it hands back.

## Repository Layout

**Haskell (Cabal):**

| Package                             | Purpose                                                  |
| ----------------------------------- | -------------------------------------------------------- |
| [jl4-core](jl4-core/)               | Core language (parser, typechecker, evaluator)           |
| [jl4](jl4/)                         | CLI tool and JSON schema generator                       |
| [jl4-lsp](jl4-lsp/)                 | Language Server Protocol for IDE support                 |
| [jl4-repl](jl4-repl/)               | Interactive REPL                                         |
| [jl4-service](jl4-service/)         | REST API for decision evaluation                         |
| [jl4-websessions](jl4-websessions/) | Session persistence service                              |
| [jl4-query-plan](jl4-query-plan/)   | Query planning utilities                                 |
| [jl4-wasm](jl4-wasm/)               | WebAssembly build of L4 for browser/Node.js              |
| [jl4-mlir](jl4-mlir/)               | MLIR/WASM compiler backend: L4 → `.wasm` decision binary |

**TypeScript (npm workspaces + Turborepo):**

| Package                             | Purpose                                    |
| ----------------------------------- | ------------------------------------------ |
| [ts-apps/vscode](ts-apps/vscode/)   | VS Code extension                          |
| [ts-apps/jl4-web](ts-apps/jl4-web/) | Web-based editor (Svelte)                  |
| [ts-shared](ts-shared/)             | Shared libraries (RPC client, visualizers) |

**Documentation:** See [doc/](doc/) for the language reference, tutorials, courses, and concept guides.

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

## VS Code Extension

Provides syntax highlighting, type checking, inline evaluation, `@export` previews, deployment management, a built-in Legalese AI chat tab, and an automatically-registered local MCP server for any AI agent that speaks the protocol (Copilot, Claude Code, Cursor, ...). Connects to [Legalese Cloud](https://legalese.cloud) or a self-hosted `jl4-service` instance. See [ts-apps/vscode/README.md](ts-apps/vscode/README.md).

## Trace Visualization

Every tool in this repo can render an L4 evaluation as a GraphViz diagram:

- **CLI:** `l4 trace myfile.l4 > trace.dot`, then `dot -Tsvg trace.dot > trace.svg` (or `l4 trace myfile.l4 --format svg -o out/` to generate SVG files directly)
- **REPL:** `:trace <expression>`, or `:tracefile traces/session` to capture numbered `.dot` files
- **Decision Service:** `POST /deployments/{id}/functions/{fn}/evaluation?trace=full&graphviz=true`

Install GraphViz with `brew install graphviz` or `apt-get install graphviz` to render PNG/SVG outputs.

## Application Libraries

L4 ships with foundational libraries for building legal and commercial applications:

- [Jurisdiction](jl4-core/libraries/jurisdiction.l4) — ISO 3166 country codes, US states, Canadian provinces, EU
- [Currency](jl4-core/libraries/currency.l4) — ISO 4217 currency codes with integer minor-unit storage
- [Legal Persons](jl4-core/libraries/legal-persons.l4) — individuals, corporations, partnerships, LLCs, trusts
- [Holdings](jl4-core/libraries/holdings.l4) — ownership structures and beneficial ownership

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
