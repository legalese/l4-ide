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

### 3.1 Four traps that produce fake failures

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
JL4_EVALDIFF=1 jl4_datadir=$PWD/jl4 jl4_core_datadir=$PWD/jl4-core \
  JL4_LIBRARY_PATH=$PWD/jl4-core/libraries <jl4-test binary> -m "prettyLayout round-trip"
# then, per file, compare `l4 run <f>` against `l4 run <f>.evaldiff.l4`,
# keeping only the `Result:` blocks
find jl4 jl4-core -name '*.evaldiff.l4' -delete            # MUST clean up: these are inside the
                                                           # corpus globs and would be goldened
```

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

---

## 7. Retired vocabulary

L4's user-facing text is written for a **non-technical first-time critical thinker**. Most of that
is judgement. One part of it is not: a few words are ones **we coined and then retired**, and for
those, any occurrence in user-facing prose is a defect rather than a style preference.

**The list, with the date each was retired.** It is short on purpose.

| word       | retired    | say instead                                                                         |
| ---------- | ---------- | ----------------------------------------------------------------------------------- |
| **binder** | 2026-09-05 | "section `GIVEN`" or "rule `GIVEN`" for the construct; "input" for what it supplies |

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

**Adding a word here needs a ruling, not a preference.** Cite the date and the document. The
distinction that makes this list checkable by plain search is that a retired term is suspect
_everywhere_, and a merely discouraged one is not. Measured over `doc/`, with the checker's own
stripping, on `props/discharge` @ `3625b533`: `binder` 9 lines, `parameter` 140 lines across 49
files. A list that admitted the second word could only ever be advisory; this one can gate CI.
`discharge` and `assumed term` are current, in-use terms. `read-set`, `elaboration` and
`section binder` have no retiring ruling to cite, so they are not here.

**Plainer is not always truer, and one diagnostic is kept as evidence of that.**
`NonDistinctQuantifiers` in `jl4-core/src/L4/TypeCheck.hs` still says "All quantified variables in
a polymorphic type must have distinct names", sitting between four sibling messages that were
re-voiced into `constructors` / `fields` / `inputs`. Its subject is the type variables of a
polymorphic signature rather than a rule's inputs, so "input" there would be _false_, and
"quantified" and "polymorphic" each carry meaning no shorter word carries. It is deliberately
untouched, with a `Note [Vocabulary of the NonDistinct messages]` at the site saying so. A future
sweep that tidies it to match its neighbours would be trading a correct sentence for a consistent
one. If you have a better sentence, take it; a shorter one is not the same thing.

> **Why.** On 2026-09-05 the word was removed from `doc/reference/syntax/section-given.md` by
> #336 and put back into that same page **five times within hours** by #338, while everyone
> involved believed the ruling was being followed. Nothing caught it, and no `paths:` filter could
> have: the PR that reintroduced it was not a docs PR.
>
> The second half of the incident is the coupling. The same ruling had been enforced on every page
> a reviewer could reach and **ratified** on the text those pages quote, because quoted tool output
> is exempt — so the compiler went on saying the retired word, and the pages went on glossing it as
> "L4's own wording". When the diagnostics were finally re-voiced, four quoted screens and four
> glosses across four pages became false at once, silently. They were repaired in the same PR that
> re-voiced the messages. That is the rule above, and it is why it is a rule.
