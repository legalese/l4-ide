# CLAUDE.md — `legalese/l4-ide`

Repo-specific working notes. Everything here was verified against the tree on 2026-07-27; where a
claim is time-sensitive it says so. If you find one of these wrong, **fix it here in the same PR as
the work that revealed it** — a stale entry in this file is worse than a missing one, because it is
believed.

Each rule carries a **Why**. Those blocks are scaffolding for readers (human or model) who would
otherwise route around the rule; delete them once the rule is obviously self-justifying.

---

## 1. Topology: two repos, and what follows from it

- **`smucclaw/l4-ide`** is upstream. **Issues are filed there.**
- **`legalese/l4-ide`** is the fork where **PRs are raised and merged**.
- **`main`** is the GitHub default branch and is the stable/releasable line.
- **`unstable`** is a long-lived integration branch. **Feature branches PR into `unstable`, not
  `main`.** Releases are a `unstable` → `main` PR plus a tag.

### 1.1 GitHub issue auto-close never fires here — close by hand

Closing keywords (`Fixes #123`, `Closes #123`) only fire when a PR merges into **the repository's
own default branch**. Ours merge into `unstable`, and the issues live in a **different repository**.
Both conditions fail independently.

**So: when a PR lands, close the issues it fixes manually**, with a comment naming the PR:

```
gh issue close <n> --repo smucclaw/l4-ide \
  --comment "Resolved by legalese/l4-ide#<pr> — https://github.com/legalese/l4-ide/pull/<pr>"
```

> **Why.** Five issues (#915, #920, #921, #922, #924) sat open for days after their fixes had
> merged, because the keyword was assumed to have done the job. The tracker then said "open" while
> the code said "fixed" — which is how a later session nearly re-filed bugs that were already
> closed, and wasted a review cycle re-deriving fixes that existed.

### 1.2 `legalese/l4-ide` must never depend on `smucclaw/dmnmd`

dmnmd may be used as local evidence when it happens to be checked out (see
`etc/validate-dmn.mjs`, which skips silently when it is absent). It must never become a build
dependency.

---

## 2. Worktrees: never edit the main checkout

- `~/src/legalese/l4-ide` is the **reference checkout**. Do not develop in it.
- All work happens in a branch + worktree under `~/src/legalese/l4wt/<short-name>`:

```
git -C ~/src/legalese/l4-ide worktree add -b <branch> ~/src/legalese/l4wt/<name> origin/unstable
```

### 2.1 The build lock

**One `dist-newstyle` per worktree, and concurrent `cabal` invocations inside a single worktree
corrupt each other** — the symptom is a spurious `renameFile:renamePath ... .o.tmp does not exist`
that looks like a code error and is not. Separate worktrees are independent and safe to build in
parallel.

When several agents share a worktree, **exactly one may build at a time**. Prefer giving read-only
agents committed goldens and corpus files, which need no build at all.

> **Why.** Three agents were once told to "build first" in one shared worktree and produced a burst
> of phantom compile failures. The rule costs a little parallelism and buys back an entire class of
> unreproducible error.

---

## 3. Build and test facts

| fact                | value                                                                             |
| ------------------- | --------------------------------------------------------------------------------- |
| build               | `cabal build all` (GHC 9.10.3)                                                    |
| ghc-options         | `-Wall -Wderiving-typeable -Wunused-packages -Werror`                             |
| default extensions  | include `NoFieldSelectors` + `OverloadedRecordDot` — use `.field`, not a selector |
| prettier            | **pinned to `3.4.2`** in `package.json`                                           |
| golden library path | `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries`                                      |

Warnings are fatal. Note that shadowing is caught via `-Wall` implying `-Wname-shadowing`, not via
a dedicated flag — there is **no** `-Werror=name-shadowing` in this repo, and the only occurrence of
the string anywhere is `-Wno-name-shadowing` in `jl4-wasm`.

Test suites include `jl4-test` (goldens), `jl4-core-test`, `l4-cli-test`, `jl4-lsp-test`,
`jl4-service-test`, `jl4-mlir-test`, `jl4-websessions-test`.

### 3.1 Three traps that produce fake failures

**Pin `JL4_LIBRARY_PATH` when running goldens locally.** CI sets it
(`.github/workflows/pr-checks.yml`); without it you get unrelated failures that look like
regressions in your change. Some goldens capture import-resolution logs verbatim, so the detailed
candidate table is emitted **only when the variable is unset** — that is deliberate, for
machine-independence.

**Use the pinned prettier.** A bare `npx prettier` resolves to whatever is current, which reformats
markdown tables differently from `3.4.2` and fails `format:check` on files you did not mean to
touch. Run `npx prettier@3.4.2` or the repo-local binary.

**A new corpus ships its goldens in the same commit as its `.l4`.** `jl4-test` writes four goldens
per file (`<dir>/tests/<stem>.{golden,ep.golden,nlg.golden,schema.golden}`) and `failFirstTime` is
`True`, so a `.l4` with no `tests/` directory turns the whole suite red. You will not see it: no
paths filter matches a `.l4` under `jl4/examples/`, so the Haskell job does not run on your PR, and
the failure surfaces on the next person's branch instead. Generate them by running `cabal test
jl4-test` once (it creates them and fails), then again to prove they hold, then commit **only** the
`.golden` files — `.actual` is gitignored. Read them before committing: blessing output you have not
looked at is how a wrong answer becomes the expected answer.

> **Why.** This went off twice in one day. The BNA corpus landed without goldens in PR #195 and was
> repaired by #202; eleven hours later the Jersey charities cleanroom did the same in #201 and was
> repaired by #212 — after it had already knocked another PR out of the merge queue. `etc/check-corpus-goldens.mjs`
> now runs in CI on every event with no filter and no build, and names the missing files. If you are
> reading this because that check failed, it has done its job.

---

## 4. Recording decisions

**A decision is recorded in its owning document in the same PR, or it is not decided.**

Deciding a ruling in an issue body, a sibling spec, a PR description, or a commit message does not
record it. Find the document that owns the question — usually a spec under `specs/todo/` with a
numbered ruling — and update it in the same change.

When a spec carries numbered rulings, follow its existing house style: mark the ruling
`ANSWERED <date>, see §n`, state the measurement that drove it, and keep a "what review changed"
note so a later editor does not silently un-change a repair.

> **Why.** Ruling **R7** in `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` was decided, written into
> `specs/todo/lexipedia-superset/SPEC.md` as **K8**, and written into an upstream issue — while
> §11 of the spec that owns R7 still read "open". Meng sat down to read that spec to understand the
> state of the rulings and got a stale answer from the authoritative file.

### 4.1 Spec status headers

A spec that is not implemented says so in its header, in the present tense, with a date. Do not
describe planned behaviour as though it ships — see the anti-drift rules in the user-level
`CLAUDE.md`. When a spec is discharged, say so and say **why the file is retained** (usually
because code cites its section numbers, which makes them load-bearing and renumbering a breaking
change).

---

## 5. Language gotchas worth knowing before you debug them

- **A `.l4` file cannot `IMPORT` a library sharing its own basename.** The failure is a silent
  `GraphException`, not a "not found" error.
- **Library resolution order** is `JL4_LIBRARY_PATH → root → importer-relative → embedded → XDG →
bundle`. The embedded stdlib is seeded into the VFS under the `jl4-embedded` URI scheme
  specifically so it cannot collide with a real file path.
- **`ASSUME` is uninterpreted** — modules in that style typecheck but do not evaluate. Idiomatic L4
  threads a record as one `GIVEN` parameter instead.
