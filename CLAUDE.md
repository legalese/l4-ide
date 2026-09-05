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
and `failFirstTime` is `True`, so a `.l4` with no `tests/` directory turns the whole suite red. You
will not see it: no paths filter matches a `.l4` under `jl4/examples/`, so the Haskell job does not
run on your PR, and the failure surfaces on the next person's branch instead.

**Which globs, exactly** (`jl4/tests/Main.hs:78-90`, kept in step by `etc/check-corpus-goldens.mjs:32-43`):
`ok/**`, `legal/**`, `not-ok/tc/**`, `not-ok/nlg/**`, `not-ok/export-*.l4`, `lsp/semantic-tokens/**`,
`lsp/hover/**`, and `jl4-core/libraries/*.l4`. **`jl4/examples/docassemble/` and
`jl4/examples/openfisca/` are in NO glob**, which is why their `.l4` files carry no `tests/`
directory and adding one there needs no goldens. State this rule with its scope: an earlier
unqualified reading of this paragraph sent a session hunting a golden trap in `docassemble/` that
does not exist there. Generate them by running `cabal test
jl4-test` once (it creates them and fails), then again to prove they hold, then commit **only** the
`.golden` files — `.actual` is gitignored. Read them before committing: blessing output you have not
looked at is how a wrong answer becomes the expected answer.

> **Why.** This went off twice in one day. The BNA corpus landed without goldens in PR #195 and was
> repaired by #202; eleven hours later the Jersey charities cleanroom did the same in #201 and was
> repaired by #212 — after it had already knocked another PR out of the merge queue. `etc/check-corpus-goldens.mjs`
> now runs in CI on every event with no filter and no build, and names the missing files. If you are
> reading this because that check failed, it has done its job.

**Pin `CAMUNDA_CHECK_JAVA_HOME`, and clear the harness's class cache when you change it.** The
Camunda leg picks its own JDK from a candidate list whose FIRST entry is
`/opt/homebrew/opt/openjdk/…` — deliberately "the newest JDK we can find" (`run.sh:51-53`), which
on a machine that also has plain `openjdk` is **26**, where CI runs **21**. The bare `java` on PATH
is irrelevant; the harness ignores it. Worse, `run.sh:84` recompiles `CamundaDmnCheck.java` only
when the class is **missing or the source is newer** — it does not key on the JDK — so a class
compiled by an earlier run under a different JDK is silently reused. Together those make a local
green possibly a different JVM _and_ different bytecode from CI's, with nothing said. Do not trust
which `java` you invoked: read the class-file major version
(`od -An -tu1 -N8 "$TMPDIR/l4-camunda-dmn-check/classes/CamundaDmnCheck.class"`; `65` is Java 21),
and reset with `rm -rf "$TMPDIR/l4-camunda-dmn-check/classes"`. The `kie-dmn-check` leg is immune
because it compiles `--release 11` (`etc/kie-dmn-check/run.sh:81`); `--release 21` on the Camunda
leg would fix it the same way. **That fix is deliberately not applied** — changing what every CI
run compiles is not a corpus or exporter branch's call, and two branches have now declined it on
that ground.

> **Why.** 2026-09-05: a deputy reported Camunda results, was asked to re-run them on 21, did, and
> reported them as reproduced. Both passes were in fact wrong in different ways — the first ran the
> engine on 26, and the second reused bytecode the first had not compiled either. The numbers did
> not move, but that was luck, and it was only visible after reading the class-file version. "I
> re-ran it on 21" is a weaker claim than it sounds: re-running a command is not the same as
> re-establishing a condition.

**Never point an `l4` binary at a prelude newer than itself.** New prelude annotations
(`@nonexhaustive`, in `jl4-core/libraries/prelude.l4` since #256) are parse errors to a binary
built before them, and the failure does NOT present as a version mismatch: the prelude fails to
load, so whatever you are checking drowns in cascading `could not find a definition` errors for
`setFromList`, `UNION`, and every other prelude name — which reads as a broken spec or example. A
binary run with `JL4_LIBRARY_PATH` unset resolves its own **embedded** prelude, which matches by
construction (resolution order: `JL4_LIBRARY_PATH → root → importer-relative → embedded → XDG →
bundle`); the trap is pinning `JL4_LIBRARY_PATH` at a tree newer than the binary. Two rigs that
both "run the prelude" are therefore not interchangeable: pinned-path and embedded-prelude runs
can resolve different prelude versions. Rebuild, or drop the pin.

> **Why.** 2026-08-27: a 7 Aug `dist-newstyle` binary pointed at the current tree's libraries made
> a known-green Style 2 probe produce nine errors that looked like the prelude had lost
> `setFromList`. The same probe on the 4 Aug installed binary with its embedded prelude: zero
> errors. The mismatch was one `@nonexhaustive` annotation the older parser could not read, and
> nothing in the output said so.

**The same trap arrives from the CORPUS side, and the paragraph above does not cover it**: a binary
older than the code it reads reports newly-landed **syntax** as broken source. Since #335
(`f48cdddb`, in `unstable`) a bodiless `DECLARE T` is the opaque-type spelling; on any binary built
before it, `DECLARE Thing` followed by a rule is a parse error at the NEXT token — which reads as a
broken example, not a stale binary. **The direction of safety is not symmetric and is easy to
invert**: a binary NEWER than the tree is fine; it is older-than-what-it-reads that breaks. So the
question is never "is my binary current" but "is it at least as new as everything it will parse" —
prelude, corpus and docs alike. `doc/test-docs.sh` is the usual route in, because it prefers any
`l4` on `PATH` over the one you built (`:323`), and `~/.local/bin/l4` was a 27 Aug build when this
was written (2026-09-05); put your worktree's binary first on `PATH`, or run with no `l4` on it at
all. How many errors a stale binary invents is a function of BOTH the binary and the corpus, so
it is a symptom to read, never a constant to memorise — a count quoted from a previous session
is the first thing to distrust here.

> **Why.** 2026-09-05, twice in one evening and from both directions. `gm-docs`'s shim was pinned to
> a pre-#335 build and flagged the opaque-type spelling as invalid documentation. Independently
> confirmed here on this branch's own binary (base `b2a3faac`, which predates `f48cdddb`): the probe
> `DECLARE Thing` + a rule reading it is a `parser` error at `3:1-3:6`, the line AFTER the
> declaration — so the message points at the reader, not at the unsupported declaration, which is
> what makes it read as broken code. `git diff <binary's commit> HEAD -- jl4-core/libraries/` is a
> cheap check, but **read the diff rather than its exit code**: deleted comment lines are safe, an
> added annotation is not.

### 3.2 There are TWO printers, and they are guarded differently

| printer                 | what it prints                       | its guard                                                  |
| ----------------------- | ------------------------------------ | ---------------------------------------------------------- |
| `Rules.ExactPrint`      | the concrete tokens, byte-for-byte   | `exactprint identity`, plus the per-file `*.ep.golden`     |
| `L4.Print.prettyLayout` | the AST, re-rendered as fresh source | `prettyLayout round-trip (filter -> print -> parse; #932)` |

`prettyLayout` is what **`l4 batch` and the REPL** re-emit a module through (`filterIdeDirectives`
then print then re-run the front end), and what the DMN exporter falls back to for an expression it
cannot lower. It used to have no test of its own at all, which is how it accumulated a printer that
could not render its own corpus back into parseable source (smucclaw/l4-ide#932).

The round-trip block in `jl4/tests/Main.hs` runs over **every file the golden suite type-checks** —
`ok/**`, `legal/**` and `jl4-core/libraries/*.l4`, 300 files — and asserts three things per file:
no inference-variable gensym reaches the output, the printed text re-parses, and the printed text
re-type-checks. **There are no exclusions and no known-failure list**; if you need one, that is the
signal to fix the printer instead.

Debugging it: the output is thousands of columns wide, so set `JL4_PRETTY_DUMP_DIR=<dir>` and the
whole emitted module is written to `<dir>/<name>.l4.pl.l4` — a plain `.l4` file you can run
`l4 check` on.

#### 3.2.1 Re-parsing is not re-meaning — run the evaluation differential

Parse + type-check is a **weaker** property than it looks, and the gap is where the expensive bugs
live: a printer that drops a bracket emits source that parses fine, checks fine, and **evaluates to
a different answer**. That is not hypothetical — it was the state of this tree. `prettyConj`
rendered `(TRUE OR FALSE) AND FALSE` and `TRUE OR (FALSE AND FALSE)` as the _same_ string, so
`ok/logic.l4` went from `LIST TRUE, TRUE, FALSE, FALSE` to `LIST TRUE, TRUE, TRUE, TRUE`, an
assertion in `legal/regcf/regcf.l4` went from satisfied to failed, and the Tesla CEO award's
`PROVIDED` guard re-associated — all through `l4 batch`, silently, with the round-trip property
green throughout.

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

> **Why.** 2026-09-05 (`gm-module-boundary`): one file in a 493-file evaluation differential was
> scored SAME this way, and it surfaced only because a _different_ file in the same run recorded a
> DIFF that would not reproduce. Nothing about the false SAME was visible on its own. The same shape
> applies to any before/after probe that greps for a marker rather than checking the exit code —
> `l4 check`, `l4 export`, the engine harnesses. Assert that the run HAPPENED before you compare
> what it said.

Measured on this tree: **288 of 291 comparable files identical**. The three that differ are
clock-dependent, not printer defects — `ok/excel-date/serials.l4` and the bitemporal ledger files
stamp wall-clock transaction time (`at=2026-08-02T22:14:22Z` vs `…23Z`), and the original disagrees
with _itself_ across two runs. Eight more files exit non-zero on both sides by design.

It is deliberately **not** a test: it is slow, and the clock-dependent files would need exactly the
known-failure list §3.2 forbids. It is a tool you run by hand.

#### 3.2.2 The one thing `prettyLayout` still cannot render

Two mixfix operators that share a **head keyword, an arity and an argument type vector** print to
the same text, because a call site is resolved to the canonical pattern (`_ tax on _ …`) and the
printer can only re-emit the head keyword — no definition can be spelled any other way. The witness
is `ok/mixfix-garden-path.l4`, whose own comment predicted it: `tax on _ item costing _ as GST in _`
beside `… as VAT in _`. It fails **loudly** ("multiple definitions for the identifier"), and only
via the unfiltered print — `l4 batch` strips `#EVAL`, which is where both call sites live.

Re-emitting the surface form instead (`` `tax on` c `item costing` p ``) was built and measured and
**does not work**: definitions print from their restructured AppForm (`DECIDE andop a b c IS …`), so
the printed module has no later keywords to match, and `fixity-nary-guard.l4`'s `1 andop 2 hadop 3`
stopped resolving. A real fix has to thread `L4.Mixfix.MixfixRegistry` into the printer.

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

> **Why.** The transpiler programme shipped five backends — OpenFisca, Catala, Blawx, docassemble,
> DMN/BPMN — across dozens of merged PRs, with specs, rulings, goldens, executed harnesses against
> real third-party toolchains, and per-example READMEs. On 2026-08-27 Meng asked whether we had
> docs describing the work. We did not. Of the fifteen `l4` CLI verbs, five were transpilers and
> **none of them appeared anywhere in `doc/` or in `doc/SUMMARY.md`**; the only mentions of these
> systems in the whole user-facing tree were as ecosystem _neighbours_ in a concepts essay. A user
> reading the manual cover to cover could not have learned that `l4 docassemble` exists.
>
> The trap is that the work felt heavily documented, because it was — in `specs/`, which had grown
> past a hundred files, none of them addressed to a user. Volume of developer-facing writing is
> what made the user-facing hole invisible.
