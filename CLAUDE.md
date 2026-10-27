# CLAUDE.md — `legalese/l4-ide`

Repo-specific working notes.
Where a claim is time-sensitive, it says so.
If you find one of these wrong, **fix it here in the same PR as the work that revealed it** — a stale entry in this file is worse than a missing one, because it is believed.
The incidents behind these rules are in this file's git history (`git log -p -- CLAUDE.md`).

---

## 1. Topology: two repos, and what follows from it

- **`smucclaw/l4-ide`** is upstream. **Issues are filed there.**
- **`legalese/l4-ide`** is the fork where **PRs are raised and merged**.
- **`main`** is the GitHub default branch and is the stable/releasable line.
- **`unstable`** is a long-lived integration branch.
  **Feature branches PR into `unstable`, not `main`.**
  `unstable` reaches `main` through a wave of human-reviewable **topic PRs**, not one merge PR (ruling D9.1, `specs/todo/RELEASE-MODEL-SPEC.md`).
  The merge is **not** the release: the release is a manual `workflow_dispatch` of `main-tag.yml`, which mints its own tag from `github.run_number`.
  **A hand-pushed tag runs nothing.**
- **There are TWO release tracks, cut from different refs (D9.3), and "cut a release" is ambiguous between them.**
  The **VS Code extension** (with `jl4-service` and the LSP binaries) comes from `main` via `main-tag.yml`.
  Standalone **`l4` / `jl4-lsp` prereleases** come from `unstable` via the shelf at `legalese/prereleases`, tagged `unstable-<date>-<shortsha>`; its own description says "Not the stable line."
  Say which track you mean.
  **The consequence that catches people: the shelf ships off `unstable`, so anything merged there can reach users at the next cut — "not released yet" is not a defence for a known defect.**

### 1.0 The skills live in TWO repos — correct here, port in the same session

Every skill under `skills/` is duplicated in **`legalese/l4-plugin`**, at the same path: today `writing-l4-rules` (the language) and `encoding-a-subject` (encoding a whole body of law and filing it in canon).
`.claude/skills/<name>` are symlinks to them.
The pipeline skill, `running-the-l4-pipeline`, is in neither: Meng ruled on 2026-09-26 that it does not ship with the public plugin (recorded in `specs/todo/PLUGIN-DISTRIBUTION-PROPOSAL.md` on the `ci/skills-layout` branch), and it lives in the private `legalese/l4-pipeline`, cloned into `etc/go/`, which `.gitignore` excludes here.
**Nothing in this repo's CI runs the pipeline.**
This repo is upstream: the `package-plugin` job of `.github/workflows/main-tag.yml` packages `skills/` into `l4-plugin.zip` when that workflow is run by hand to cut a release.
There are two marketplace entries, `/plugin marketplace add legalese/l4-ide` and `/plugin marketplace add legalese/l4-plugin`; canon's `CLAUDE.md` sends people to the second.

**So a correction to a skill lands here first**, and its other copies are found and corrected in
the same session. The bundle names this repo as its source, so the
pointer home exists, and the path back down is the generator below.

**The bundle is generated, and its generator is in this repo: `etc/build-plugin-bundle.mjs`.**
`l4-plugin`'s README says in terms: _"This directory is generated. Do not edit it by hand … Every
file here was copied out of legalese/l4-ide by `etc/build-plugin-bundle.mjs`; edits made here are
lost on the next build."_
So a skill fix is ported by regenerating the bundle, never by hand-copying files into it:

1. Land the fix here first.
2. From an l4-ide checkout at the commit to publish (normally `unstable`), with a clone of `legalese/l4-plugin` beside it, run `node etc/build-plugin-bundle.mjs <l4-plugin clone> --l4-release latest`.
3. Review the diff in the clone and open a PR on `l4-plugin`. The bundle's README records the l4-ide commit it was generated from.

What the script does, sorted by how its failures show up:

- It empties the output directory, keeping only `.git`, then copies the skills and every repo file their text cites, each at its original path (except `jl4-core/libraries/`, which the `l4` binary carries), and writes the bundle's README and manifests.
- **Loud:** it then checks the bundle from the outside. Every citation and markdown link in the bundled skills must resolve, or it lists them and exits 1. That is a defect in the skill, not in the script.
- **Loud, not fatal:** with `--l4-release`, it pins `scripts/install-l4.sh` to a release on `legalese/prereleases`; if the shelf cannot be reached, it prints `NO INSTALLER EMITTED` and builds the rest.
- **Silent:** without `--l4-release`, no installer is written, and because the directory was emptied first, the bundle's existing `scripts/install-l4.sh` is deleted with no message. Pass the flag every time.

**The copies are identical only just after a regeneration.**
Every skill change that lands here afterwards leaves the bundle behind until the next one, so read `diff -rq skills <l4-plugin>/skills` as "how far behind is the bundle", not as "this should be empty".
To ask whether anyone edited the bundle by hand, diff it against the l4-ide commit its README names.
`etc/check-canon-citations.mjs --dir <l4-plugin>/skills <l4-plugin>/specs` checks that the bundle's citations into canon still resolve.
One thing does not port: prose asserting something is "verifiable in situ" is false in the packaged bundle, which ships the skill **without** `jl4-core/src` beside it.
Say which tree a check needs.
Edit the tracked path, `skills/<name>/`, not the `.claude/skills/<name>` symlink.

### 1.1 GitHub issue auto-close never fires here — close by hand

Closing keywords (`Fixes #123`, `Closes #123`) only fire when a PR merges into **the repository's
own default branch**. Ours merge into `unstable`, and the issues live in a **different repository**.
Both conditions fail independently.

**So: when a PR lands, close the issues it fixes manually**, with a comment naming the PR:

```
gh issue close <n> --repo smucclaw/l4-ide \
  --comment "Resolved by legalese/l4-ide#<pr> — https://github.com/legalese/l4-ide/pull/<pr>"
```

### 1.2 `legalese/l4-ide` must never depend on `smucclaw/dmnmd`

dmnmd may be used as local evidence when it happens to be checked out (see
`etc/validate-dmn.mjs`, which skips silently when it is absent). It must never become a build
dependency.

---

## 2. Worktrees: never edit the main checkout

- Keep one clone of this repository as the **reference checkout**, on `unstable`. Do not develop in it.
- All work happens in a branch + its own worktree, one per branch:

```
git -C <reference checkout> worktree add -b <branch> <worktree root>/<short-name> origin/unstable
```

Where the reference checkout and the worktree root live is a fact about your machine, not about this repository, so this file does not record it.
Keep notes like that in your own `~/.claude/` files: Claude Code loads `~/.claude/CLAUDE.md` and `~/.claude/rules/*.md` in every project, and nothing there is committed.

### 2.1 The build lock

**One `dist-newstyle` per worktree, and concurrent `cabal` invocations inside a single worktree
corrupt each other** — the symptom is a spurious `renameFile:renamePath ... .o.tmp does not exist`
that looks like a code error and is not. Separate worktrees are independent and safe to build in
parallel.

When several agents share a worktree, **exactly one may build at a time**. Prefer giving read-only
agents committed goldens and corpus files, which need no build at all.

**Wait on a PID, never on a process name.** The obvious way to honour the rule above is
`until ! pgrep -f 'cabal test'; do sleep 20; done` — and it never exits, because **the waiting shell
is itself a process whose command line contains that string**, so `pgrep` matches the waiter. It
does not hang visibly: it reports "still running" forever, which is indistinguishable from a slow
build and is therefore believed. Use `until ! kill -0 <pid> 2>/dev/null`, which cannot self-match,
or wait on a file the run itself creates. A bracketed class (`pgrep -f '[c]abal test'`) works but is
a trick that survives only as long as the next person copying the line knows why the bracket is
there.

### 2.2 Cloud sessions (claude.ai/code): one shallow clone, and the toolchain is not on PATH

In a cloud session, read `specs/CLOUD-SESSIONS.md` before you build.
The clone is shallow, and the toolchain is installed but not on the agent's PATH.

---

## 3. Build and test facts

| fact                | value                                                                             |
| ------------------- | --------------------------------------------------------------------------------- |
| build               | `cabal build all` (GHC 9.10.2)                                                    |
| ghc-options         | `-Wall -Wderiving-typeable -Wunused-packages -Werror`                             |
| default extensions  | include `NoFieldSelectors` + `OverloadedRecordDot` — use `.field`, not a selector |
| prettier            | **pinned to `3.4.2`** in `package.json`                                           |
| golden library path | `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries`                                      |

Warnings are fatal. Note that shadowing is caught via `-Wall` implying `-Wname-shadowing`, not via
a dedicated flag — there is **no** `-Werror=name-shadowing` in this repo, and the only occurrence of
the string anywhere is `-Wno-name-shadowing` in `jl4-wasm`.

> **That said, GHC prints the string anyway, so do not read its output as contradicting the
> paragraph above.** A shadowing error arrives as `[-Wname-shadowing, Werror=name-shadowing]` — that
> is simply how GHC names the promotion from `-Wall` + `-Werror`, not a flag anyone configured.
> Grepping the error text against this file will otherwise look like it has found a contradiction.
> (A live example: `to` shadows `Optics.to`, imported unqualified in `jl4/tests/Main.hs`.)

Test suites include `jl4-test` (goldens), `jl4-core-test`, `l4-cli-test`, `jl4-lsp-test`,
`jl4-service-test`, `jl4-mlir-test`, `jl4-websessions-test`.

### 3.0 Run the gate with `etc/verify-branch.sh`, not by hand

```
etc/verify-branch.sh [--quick] [--base <ref>] <ABSOLUTE-worktree-path>
```

It runs the build, `jl4-test`, `l4-cli-test`, `jl4-core-test`, `jl4-service-test`,
`check-corpus-goldens`, `check-canon-citations`, the canon-mirror check (`sync-canon.mjs --check`),
`doc/test-docs.sh` and prettier, pins `JL4_LIBRARY_PATH` for you, and exits non-zero on any failure.
`--quick` skips `jl4-test`, which is the ~12-minute one.

**The worktree is an argument, not a `cd`, and it must be absolute.** That is the point of the
script rather than an inconvenience: the working directory of a shell command is not stable between
invocations in an agent harness, so "remember to `cd` first" is not a control. The tree that was
actually tested is printed at the top _and_ the bottom of every run, so a truncated log still says
which one it was.

It also refuses to start when a `cabal` is already running in that worktree (§2.1's phantom
`.o.tmp`), fails on stray `*.evaldiff.l4` before doing anything (they sit inside the corpus globs),
runs prettier only over changed files (a whole-repo `--check` in a fresh worktree fails on the
uninstalled `@repo/prettier-config`, which is an install gap and not a formatting defect), checks
that every commit with a Claude `Co-Authored-By:` line also carries a `Claude-Session:` trailer
(a commit written by hand needs neither), and tells you when `L4/Print.hs` is in the diff
that §3.2.1's evaluation differential is now owed by hand.
Three probes run only when the diff touches what they guard: parse time at 1,000 against 4,000 lines when `jl4-core/src/L4/Parser*` changes, the same `jl4-service` calls before and after a restart when `jl4-service/` changes, and a warning for CLI tests that compare output without dropping `'\r'` when `jl4/tests-cli/` changes (`specs/todo/MAIN-PRE-REVIEW.md` §6).

**A green run is not a green CI** — the script says so at the end, and lists what it did not run.

### 3.1 Five traps that produce fake failures

**Pin `JL4_LIBRARY_PATH` when running goldens locally.** CI sets it
(`.github/workflows/pr-checks.yml`); without it you get unrelated failures that look like
regressions in your change. Some goldens capture import-resolution logs verbatim, so the detailed
candidate table is emitted **only when the variable is unset** — that is deliberate, for
machine-independence.

**Use the pinned prettier.** A bare `npx prettier` resolves to whatever is current, which reformats
markdown tables differently from `3.4.2` and fails `format:check` on files you did not mean to
touch. Run `npx prettier@3.4.2` or the repo-local binary.

**A new corpus file ships its goldens in the same commit as its `.l4` — if it is under a goldened
glob.** `jl4-test` writes four goldens per file (`<dir>/tests/<stem>.{golden,ep.golden,nlg.golden,schema.golden}`)
and `failFirstTime` is `True`, so a `.l4` with no `tests/` directory turns the whole suite red.
No paths filter matches a `.l4` under `jl4/examples/`, so the Haskell job does not run on your PR.
`etc/check-corpus-goldens.mjs` is what catches the gap: it runs in CI on every event, with no filter and no build (`pr-checks.yml`, job `corpus-goldens`), and names the missing files.

**Which globs, exactly** (`jl4/tests/Main.hs:88-119`; `etc/check-corpus-goldens.mjs:31-74` mirrors all of them except the two `lsp/` ones, which use a different mechanism):
`ok/**`, `legal/**`, `canon/**`, `not-ok/tc/**`, `not-ok/nlg/**`, `not-ok/export-*.l4`, `not-ok/import/*-refused.l4`, `not-ok/import/unresolved-*.l4`,
`lsp/semantic-tokens/**`, `lsp/hover/**`, and `jl4-core/libraries/*.l4`.
**`jl4/examples/docassemble/` and `jl4/examples/openfisca/` are in NO glob**, which is why their `.l4` files carry no `tests/` directory and adding one there needs no goldens.
Generate goldens by running `cabal test jl4-test` once (it creates them and fails), then again to prove they hold, then commit **only** the `.golden` files — `.actual` is gitignored.
Read them before committing: blessing output you have not looked at is how a wrong answer becomes the expected answer.

**The canon glob is the one exception to that procedure, and it is a prohibition.**
`jl4/examples/canon/` is a VENDORED MIRROR of blessed directories in `legalese/canon`, at the SHA
in `etc/canon-pin.json`. Do not edit it, and **do not bless its goldens by the procedure above** —
deleting the stale golden and running the suite twice is right everywhere else and is exactly the
wrong move here, because it makes this repository's copy disagree with canon silently. Edit the
file in canon, re-bless it there, then `node etc/sync-canon.mjs --bump <sha> --ref <branch>`. The
`Canon Mirror` CI job fails when the mirror and canon at the pin disagree.

**A merge can edit the mirror for you, with no conflict and no red test.** When one branch moves a
file into the mirror and another edits it at its old path, git's rename detection carries the edit
onto the mirror copy. `jl4-test` stays green, because the file and its `.ep.golden` moved and
changed together, and the conflict list is silent, because nothing conflicted. After any merge that
involves a branch moving subjects into canon, run `node etc/sync-canon.mjs --check`;
`etc/verify-branch.sh` now does. To repair, restore the mirror copies (`--pull` when the pin is
right) and make the intended edit in canon instead.

> **Do not wrap a code span in bold when the span itself ends in two asterisks.**
> Doing that unbalances markdown emphasis for the rest of the paragraph, and `prettier --write` then silently rewrites later, untouched text in it: the spaces around code spans disappear, and the single asterisk in a later glob such as `not-ok/export-*.l4` can become an underscore.
> Plain backticks with no bold are inert; use those.
>
> **The same applies inside a bold lead-in, where it fails worse.**
> Measured 2026-10-27 on the globs paragraph above: a lead-in containing such a code span turned `not-ok/export-*.l4` into `not-ok/export-_.l4`, escaped the asterisk in other globs, AND ate the spaces around several code spans.
> That is the shape the obvious fix invites, so name the glob in prose there — "the canon glob" — rather than in a code span.

**Pin `CAMUNDA_CHECK_JAVA_HOME`, and clear the harness's class cache when you change it** — why, and the two commands, are in `etc/camunda-dmn-check/README.md`.

**A binary must be at least as new as everything it will parse: prelude, corpus and docs alike.**
A binary older than the code it reads reports newly-landed prelude annotations (`@nonexhaustive` is one) and newly-landed syntax (a bodiless `DECLARE T`, the opaque-type spelling) as broken source, and the failure does NOT present as a version mismatch.
A prelude the binary cannot parse fails to load, so whatever you are checking drowns in cascading `could not find a definition` errors for `setFromList`, `UNION` and every other prelude name.
Newer syntax in a corpus file gives a parse error at the NEXT token, so the message points at the reader and not at the declaration.
Either reads as a broken spec or example.
The direction of safety is not symmetric and is easy to invert: a binary NEWER than the tree is fine, and the question is never "is my binary current" but "is it at least as new as everything it will parse".
Leaving `JL4_LIBRARY_PATH` unset lets the binary fall back to its own **embedded** prelude, which matches it by construction (resolution order: §5), so the trap is pinning `JL4_LIBRARY_PATH` at a tree newer than the binary; pinned-path and embedded-prelude runs can resolve different prelude versions.
Rebuild, or drop the pin.
`doc/test-docs.sh` is the usual route in, because it prefers any `l4` on `PATH` over the one you built (`doc/test-docs.sh:329`), so an `l4` installed there weeks ago is the one it finds: put your worktree's binary first on `PATH`, or run with no `l4` on it at all.
`git diff <binary's commit> HEAD -- jl4-core/libraries/` is a cheap check for the prelude, but **read the diff rather than its exit code**: deleted comment lines are safe, an added annotation is not.
How many errors a stale binary invents depends on both the binary and the corpus, so treat the count as a symptom to read, never a constant to memorise.

### 3.1.1 A golden that captures an absolute path cannot fail locally

**Before blessing a new golden, grep it for an absolute path.** `grep -c /Users/ <golden>` is the
whole check.

Some goldens capture import-resolution logs verbatim, and an import resolved _importer-relative_ —
one corpus file importing its neighbour — logs the absolute path it found. If that path reaches the
golden, the test passes on the machine that generated it **forever**, and fails in CI **forever**.
Not through carelessness: the golden and the actual output come from the same filesystem, so on that
machine they agree _by construction_. Running the suite again, or through
`etc/verify-branch.sh`, cannot help. A local green is not weak evidence here — it is no evidence.

The harness scrubs four prefixes for exactly this reason (`mkPathScrubber`, `jl4/tests/Main.hs`): `JL4_LIBRARY_PATH` → `$JL4_LIBRARY_PATH`, the examples root → `$JL4_EXAMPLES`, the executable's directory → `$EXE_DIR`, and the XDG data store → `$XDG_DATA_JL4`.
If you add a resolution path that is rooted somewhere else again, scrub it there rather than hand-editing the golden — a hand-edit relocates the rake instead of removing it.

### 3.2 There are TWO printers, and they are guarded differently

| printer                 | what it prints                       | its guard                                                  |
| ----------------------- | ------------------------------------ | ---------------------------------------------------------- |
| `Rules.ExactPrint`      | the concrete tokens, byte-for-byte   | `exactprint identity`, plus the per-file `*.ep.golden`     |
| `L4.Print.prettyLayout` | the AST, re-rendered as fresh source | `prettyLayout round-trip (filter -> print -> parse; #932)` |

`prettyLayout` is what **`l4 batch` and the REPL** re-emit a module through (`filterIdeDirectives`
then print then re-run the front end), and what the DMN exporter falls back to for an expression it
cannot lower.

The round-trip block in `jl4/tests/Main.hs` runs over **every file the golden suite type-checks** —
`ok/**`, `legal/**`, `canon/**` and `jl4-core/libraries/*.l4` — and asserts three things per file:
no inference-variable gensym reaches the output, the printed text re-parses, and the printed text
re-type-checks. **There are no exclusions and no known-failure list**; if you need one, that is the
signal to fix the printer instead.

Debugging it: the output is thousands of columns wide, so set `JL4_PRETTY_DUMP_DIR=<dir>` and the
emitted module is written to `<dir>/<name>.l4.pl.l4` — a plain `.l4` file you can run
`l4 check` on.

**That dump is the FILTERED print, and it is the wrong file for an evaluation question.**
`filterIdeDirectives` has already removed every `#EVAL` and `#ASSERT` from it, so a module with six assertions dumps with none.
Use it to read the printed SHAPE; never to compare results.
`JL4_EVALDIFF=1` writes the UNFILTERED print instead, next to the source so its `IMPORT`s still resolve (§3.2.1).

#### 3.2.1 Re-parsing is not re-meaning — run the evaluation differential

Parse + type-check is a **weaker** property than it looks, and the gap is where the expensive bugs
live: a printer that drops a bracket emits source that parses fine, checks fine, and **evaluates to
a different answer**.
That is not hypothetical: `prettyConj` once rendered `(TRUE OR FALSE) AND FALSE` and `TRUE OR (FALSE AND FALSE)` as the _same_ string, silently, through `l4 batch`, with the round-trip property green throughout.

So when you touch `L4.Print`, run this too:

```bash
find jl4 jl4-core -name '*.evaldiff.l4' -delete            # always start clean
cp dist-newstyle/.../l4 "$SCRATCH/l4-evaldiff"             # SNAPSHOT: see below
JL4_EVALDIFF=1 jl4_datadir=$PWD/jl4 jl4_core_datadir=$PWD/jl4-core \
  JL4_LIBRARY_PATH=$PWD/jl4-core/libraries <jl4-test binary> -m "prettyLayout round-trip"
# then, per file, compare `$SCRATCH/l4-evaldiff run <f>` against the same on
# `<f>.evaldiff.l4`, keeping only the `Result:` blocks
find jl4 jl4-core -name '*.evaldiff.l4' -delete            # MUST clean up: these are inside the
                                                           # corpus globs and would be goldened
```

**Snapshot the binary before you probe with it, and never point a differential at
`dist-newstyle/.../l4` directly.** Any build in the same worktree relinks that path mid-run, and a
partially written binary fails on **both** sides — which a harness that compares outputs records as
"no difference". A crash on one side is loud; a crash on both is silent, and silence is the answer
this harness is looking for. The comparison above keeps only `Result:` blocks, so two runs that
produced no output at all compare **equal**: the instrument cannot tell "identical" from "neither
one started". Copy the binary somewhere unique first and point both sides at the copy.
The same holds for any before/after probe that greps for a marker instead of checking the exit code (`l4 check`, `l4 export`, the engine harnesses): assert that the run HAPPENED before you compare what it said.

Files that read the wall clock (`ok/excel-date/serials.l4`, the bitemporal ledger files) disagree with themselves across two runs unless `JL4_FIXED_NOW` pins the clock, so a difference confined to them is not a printer defect.
(Measured 2026-10-27 with the installed `l4`: `serials.l4` and `ok/ledger/bitemporal-stamps.l4` each differ across two runs, and are byte-identical across two runs under `JL4_FIXED_NOW=2025-01-31T15:45:30Z`.)
A few files exit non-zero on both sides by design.

It is deliberately **not** a test: it is slow, and the clock-dependent files would need exactly the
known-failure list §3.2 forbids. It is a tool you run by hand.

#### 3.2.2 Mixfix names, and the head-keyword collision that used to break them

Fixed 2026-09-21 (smucclaw/l4-ide#967): two mixfix operators that share a head keyword used to print to the same text.
`L4.Print.restoreMixfixPatterns` is what fixed it, and it must run wherever a whole module is printed; `l4 batch` (`jl4/app/L4/Cli/Batch.hs`), the REPL (`jl4-repl/app/Main.hs`) and the round-trip harness (`jl4/tests/Main.hs`) already call it.
The residue is smucclaw/l4-ide#968, open on 2026-10-27: only mixfixes DEFINED IN THE MODULE are restored, so two IMPORTED operators that share a head keyword, an arity and an argument-type vector still print to the same text, and that one fails LOUDLY ("multiple definitions for the identifier").
No golden captures `prettyLayout` output; the guard is a CLI test (`l4 batch` over `jl4/tests-cli/fixtures/batch-mixfix-shared-head.l4`) plus the §3.2.1 differential.
The risk check on a file is one line:

```
grep -oE '^`[^`]+`' <file> | sort | uniq -d
```

---

## 4. Recording decisions

**A decision is recorded in its owning document in the same PR, or it is not decided.**

Deciding a ruling in an issue body, a sibling spec, a PR description, or a commit message does not
record it. Find the document that owns the question — usually a spec under `specs/todo/` with a
numbered ruling — and update it in the same change.

When a spec carries numbered rulings, follow its existing house style: mark the ruling
`ANSWERED <date>, see §n`, state the measurement that drove it, and keep a "what review changed"
note so a later editor does not silently un-change a repair.

### 4.1 Spec status headers

A spec that is not implemented says so in its header, in the present tense, with a date. Do not
describe planned behaviour as though it ships: write "proposed, not landed", and name what would
make it true. When a spec is discharged, say so and say **why the file is retained** (usually
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

---

## 6. A feature is not done until `doc/` explains it

**If a user can invoke it, it needs a page under `doc/` before the work is closed out** — a new CLI
verb, a new backend, a new language construct, a new annotation. Not "later", not "in the next
milestone": in the shipping PR, or in one that lands immediately behind it while the work is still
in your head.

**`specs/` is not user documentation.** A spec records why we built the thing and what we ruled
along the way; it is written for whoever maintains it next, and it assumes the whole context. A
`doc/` page is for someone who has never read the spec and wants to use the thing. Both are needed
and neither substitutes for the other. Ten thousand words of spec is not a reason to skip the page
— it is the reason the gap is easy to miss.

**Write it in the reader's world, not ours.** For anything that touches an external system, lead
with what that system _is_ and why someone would want it, then what compiling to it buys them —
"docassemble is an open-source guided-interview platform used across access-to-justice work, and we
compile to it so a member of the public can answer questions in a browser." Do not lead with our
module names or our IR.

**State the limits on the page.** What the export drops, what it refuses, where numbers stop being
exact. A user finds those out anyway; the only question is whether they find out from us or from a
wrong answer in production.

Mechanics: add the page, and link it from `doc/SUMMARY.md`. `doc/test-docs.sh` runs in CI
(`.github/workflows/pr-checks.yml`) and checks every markdown link, type-checks every `.l4` file
under `doc/`, and **fails on orphans** — a page nothing links to turns the build red. Run it
locally before pushing; it takes seconds. Note what it does _not_ check: that a page exists at all.
Nothing mechanical will tell you this rule was skipped.

---

## 7. Retired vocabulary

L4's user-facing text is written for a **non-technical first-time critical thinker**. Most of that
is judgement. One part of it is not: a few words are ones **we coined and then retired**, and for
those, any occurrence in user-facing prose is a defect rather than a style preference.

**This section records rulings; it does not make them.** Each row below is a decision already
taken, written down here so that `etc/check-retired-terms.mjs` has something to cite. The
citation points outward — the script cites the ruling, and this section merely holds it. A row
whose only support is this section is not a ruling, it is a preference wearing one.

**The list, with the date each was retired.** It is short on purpose.

| word       | retired    | say instead                                                                         |
| ---------- | ---------- | ----------------------------------------------------------------------------------- |
| **binder** | 2026-09-04 | "section `GIVEN`" or "rule `GIVEN`" for the construct; "input" for what it supplies |

Meng ruled it on **2026-09-04**, and his reason is the one worth keeping, because it is about the
reader rather than about us:

> never "binder" — to lawyers a binder is a ream of paper with ink and holes.

**The list binds the learning-oriented pages, not every page.** Meng ruled on **2026-09-05**:
the retired list is _"excluded from the tutorial and cookbook guides, but if they find their way
into a Diataxis theory reference we could allow that iff we appropriately introduce PLT
alongside"_ — `binder` being _"a PLT term for variable binding or symbol binding"_ that "will mean
nothing to a beginner L4 programmer".

| quadrant                                                      | rule                                                                                                                                                         |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `doc/tutorials/`, `doc/courses/`, the cookbook when it exists | **excluded.** Swept by CI.                                                                                                                                   |
| `doc/reference/`, `doc/concepts/`                             | **permitted iff the page introduces the term** — lay words first, then the technical label as a bold-quoted defined term, the house pattern from 2026-09-04. |

The mechanical test for "introduces" already exists in prose — _used before a bold-quoted definition on the same page_ — but **it is not yet enforced**; there is no script for it in the tree.
**A green CI run says nothing about a reference page.**
Whoever builds that check gets to delete this paragraph.

One narrowing worth stating, because the ruling's subject is broader than the list: the entry
matches `binder` and deliberately **not** `binding`. "Symbol binding" is the phrase the ruling
describes, but "a binding contract" is ordinary legal English and is everywhere in the corpus.
Only the coined noun was retired.

**Quoting is not using.** A page that documents an error message has to show it, and a page that
teaches a construct has to spell it. Fenced blocks, inline code spans and link targets are
therefore exempt, and `etc/check-retired-terms.mjs` blanks them before it looks. Where prose must
name a retired word outside those, put `<!-- RETIRED-TERM-OK: reason -->` on the line; the marker
is honoured only where there was a finding to suppress, and every use is printed so they stay
countable.

**But quoting couples the page to the wording.** A verbatim screen is only correct while the binary
still prints it, and nothing mechanical compares the two — `doc/test-docs.sh` checks links and
type-checks `.l4` files and has no opinion about the text inside a fence. So **whoever changes a
diagnostic owns every page that quotes it, in the same PR.**

**This section is not the style guide.** It holds only what is _retired by ruling_ and swept by
CI. The wording to lead with — the substitution table, the introduce-then-bold pattern, the
audience — is [`doc/STYLE.md`](doc/STYLE.md), and a word moves from there to here only by a
ruling.

**Adding a word here needs a ruling, not a preference.**
Cite the date and the document; the list holds only terms we coined and then retired, because for those a plain search is a sound check and for a merely discouraged word it is not.

**Plainer is not always truer:** the one diagnostic deliberately left in its technical wording is `NonDistinctQuantifiers` in `jl4-core/src/L4/TypeCheck.hs`, and `Note [Vocabulary of the NonDistinct messages]` there says why, so read it before tidying that message to match its neighbours.
