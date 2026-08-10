# docs(agents): a CLAUDE.md for this repo, the statutory-drafting skill pages, and the repo-root design records

**What this adds.** This PR gives the repository the written-down operating knowledge that an agent
or a new contributor currently has to acquire by tripping over it. It adds a repo-level `CLAUDE.md`
(new, 220 lines) that states the two-repo topology and what follows from it, the worktree and
build-lock discipline, the three environment traps that produce fake test failures, which of the
repo's **two** printers is guarded by which test, and the rule that a decision is recorded in its
owning document or it is not decided. It extends the `writing-l4-rules` skill with three new
reference pages — statutory drafting patterns, the append-only state ledger, and `SET OF a` — plus a
`daydate` footgun entry in `gotchas.md` and skill-level coverage of `l4 export` and the `YMD`
constructor. It also lands the repo-root design records that had been living outside the tree — an
`l4-lint` RFC, a compiler-review codebase map, the discharged dmnmd→L4 build spec with the agent
workflow script that executed it, a marching-orders file, and the ladder-diagrams workplan. After
this, "how do I not break the golden suite", "how do I encode a proviso limb", and "why
did my `Date 1 (3 MINUS 6) 2025` land in January" all have answers in the tree instead of in a
commit message.

**Why.** Every rule in `CLAUDE.md` was written after an incident, and each carries its own **Why**
block naming it: five upstream issues (`smucclaw/l4-ide` #915, #920, #921, #922, #924) sat open for
days because `Fixes #n` cannot auto-close across a fork boundary into a non-default base branch;
three agents sharing one worktree produced a burst of phantom `renameFile:renamePath … .o.tmp does
not exist` failures; a corpus landed twice in one day without its goldens and turned the suite red
on somebody else's branch; and ruling **R7** was decided in three places while the spec that owns it
still read "open". The printer section exists because `prettyLayout` had no test of its own and had
drifted to where it could not render its own corpus back into parseable source — reported upstream
as `smucclaw/l4-ide#932`. The `README.md`/`AGENTS.md` edit is the documentation half of the commit
titled `fix(#63): remove dangling jl4-actus-analyzer refs from cabal.project/README/AGENTS` — both
files went on listing a package that `cabal.project` no longer builds. The skill pages
are the reverse case — knowledge that only ever existed in the head of whoever formalised the UK
Housing Act 1988 Schedule 2 corpus, and which a general-purpose model gets wrong by default.

## What's in it

Fourteen files: seven new at the repo root, three new skill reference pages, four modified.
`+3,644 / −24` — so this is almost entirely additive, and the 24 deleted lines are two package
tables being reflowed.

### `CLAUDE.md` — new, 220 lines

Five sections, each rule with a **Why**:

- **§1 Topology.** `smucclaw/l4-ide` is upstream and owns the issues; `legalese/l4-ide` is where PRs
  are raised; feature branches target `unstable`, not `main`. §1.1 spells out that issue auto-close
  never fires here (both conditions fail independently) and gives the `gh issue close` recipe. §1.2
  records the standing rule that this repo must never take a build dependency on `smucclaw/dmnmd`.
- **§2 Worktrees**, including §2.1 **the build lock** — one `dist-newstyle` per worktree; concurrent
  `cabal` invocations inside a single worktree corrupt each other.
- **§3 Build and test facts** — GHC 9.10.3, `-Wall -Wderiving-typeable -Wunused-packages -Werror`,
  `NoFieldSelectors` + `OverloadedRecordDot`, prettier pinned to `3.4.2`, `JL4_LIBRARY_PATH`. §3.1
  is the three traps that produce fake failures (unset library path, unpinned prettier, a corpus
  shipped without its four goldens).
- **§3.2 There are TWO printers, and they are guarded differently** — a table separating
  `Rules.ExactPrint` (concrete tokens, guarded by `exactprint identity` and the per-file
  `*.ep.golden`) from `L4.Print.prettyLayout` (AST re-rendered as fresh source, guarded by the
  round-trip property). §3.2.1 documents the `JL4_EVALDIFF` evaluation differential and says why it
  is deliberately a hand-run tool rather than a test. §3.2.2 records the one construct `prettyLayout`
  still cannot render, and that the obvious fix was built, measured and rejected.
- **§4 Recording decisions** and **§5 language gotchas** (`IMPORT` basename collision, library
  resolution order, `ASSUME` is uninterpreted).

### The `writing-l4-rules` skill — three new reference pages, two edited files

- **`references/drafting-patterns.md`** (new, 869 lines) — a "when the statute says… → the L4 shape
  → a real example file" catalogue, drawn from formalising 43 statutory grounds for possession (UK
  Housing Act 1988 Sch. 2 as amended by the Renters' Rights Act 2025) and later from the Reg CF and
  BNA corpora. Constitutive limbs (proviso, negative, gate, enumerated cases, checkbox relations,
  statutory tables as data); decision results (total enum over `MAYBE`, and where `MAYBE` is still
  right); leap-safe date windows; mandatory vs discretionary outcomes; provenance, repeal and
  aggregation. Two later sections carry rulings rather than idioms: **"When the source supplies no
  label, DECOMPOSE"** and **"Inert never shadows active — quote the label, not the sentence"**
  (Meng's ruling of 2026-08-03), with the `...` continuation token, the lexer's rejection of `…`
  quoted verbatim, and the three ways the rule is easy to get wrong.
- **`references/state-ledger.md`** (new, 133 lines) — `RECORD` / `COMMIT` / `ATTEST` / `RECALL`, the
  own-ledger vs official-record split, last-write-wins `RECALL` against collect-all `RECALL ALL`,
  and recipient-qualified `RECORD …'s` as the NOTIFY mechanism. Carries an explicit availability
  caveat naming the builds these constructs are in.
- **`references/sets.md`** (new, 50 lines) — `SET OF a`, the canonical vocabulary, the type-dispatched
  overloads, why bare `EQUALS` on two sets is a deliberate ambiguity error, and the one-level
  quotient caveat.
- **`references/gotchas.md`** (+31) — the `daydate` month-subtraction footgun: `Date` clamps a month
  ≤ 0 to January of the same year rather than rolling back a year, so `Date 1 (3 MINUS 6) 2025` is
  January 2025 and not September 2024. With the two correct shapes and the corpus files that use
  them.
- **`SKILL.md`** (+18/−1) — links the three new pages; adds `l4 export --to=dmn|dmn-md|bpmn` to the
  CLI list including where the fidelity report goes; and rewrites the date-literal paragraph around
  `YMD year month day`, keeping the little-endian `Date d m y` and stating the deliberate
  strict/lenient split (`YMD` bounds-checks and refuses; `Date` stays lenient because month
  arithmetic relies on it).

### Repo-root design records

- **`L4-LINT-DESIGN.md`** (new, 607 lines) — the `l4-lint` RFC: a safe layout formatter plus an
  opt-in codemod layer. Its §0 is a post-RFC resolution that **reverses the RFC's own ruling**: the
  lexer resolves the ditto token `^` by *display width*, not code points, settled by executing the
  real `l4` binary rather than reading the source.
- **`REVIEW-PART1-CODEBASE-MAP.md`** (new, 172 lines) — the orientation half of a two-part compiler
  review: pipeline, subsystem-by-subsystem invariants, the two parallel compilation drivers and
  their known divergences, the test/CI landscape and its glob gaps, and §7's prioritised **T1–T12**
  target list with per-target status.
- **`BUILD-SPEC-dmnmd-to-l4.md`** (new, 650 lines) and **`build-dmnmd-to-l4.workflow.js`** (new, 255
  lines) — the `dmnmd --to=l4` build spec, marked **DISCHARGED** in its header and retained only
  because dmnmd's `L4.hs` cites its section numbers in more than twenty comments, which makes them
  load-bearing. The workflow file is the phased agent script that executed the plan.
- **`BRANCH.md`** (new, 276 lines) — marching orders for the shallow `DEONTIC` action-type check,
  with the bug writeup kept as reference and an "Outcome (implemented + verified)" section.
- **`TODO.md`** (new, 342 lines) — the ladder-diagrams workplan: priority ladder, per-task sections
  A–J, and a dependency summary.

### Corrections to existing docs

- **`README.md`** (+11/−12) and **`AGENTS.md`** (+10/−11) — drop the `jl4-actus-analyzer` row from
  the Haskell package tables; the rest of each hunk is prettier re-padding the table columns after
  the longest row left.

### Known warts, flagged rather than hidden

A reviewer should know these before approving, because they are visible on first read:

- `TODO.md`'s own header describes it as a scratch file that is "**Not committed** (working-tree
  only)" — which it plainly no longer is. It is also dated ("Last reoriented: 2026-07-15") and
  narrates branch state that has since moved.
- `BRANCH.md` is marching orders for work that has already landed; it reads as a record now, not a
  plan.
- `REVIEW-PART1-CODEBASE-MAP.md` carries absolute paths under `/Users/mengwong/…` and a
  toolchain note for one machine.

None of these is load-bearing; all three files are inert prose. Retitling, relocating or re-tensing
them is a fine review outcome — but doing it here would fold an unrelated decision into a
documentation PR, which is exactly what `CLAUDE.md` §4 asks people not to do.

## Evidence

These pages are prose: they compile nothing and assert nothing at runtime, so they carry no
measurements of their own. The numbers below are the ones the **source PRs reported for the code
these pages document**, quoted because the pages quote them and a reviewer checking a claim in
`CLAUDE.md` should be able to trace it:

- **PR #214** (`fix(print): make prettyLayout round-trip…`), the source of `CLAUDE.md` §3.2/§3.2.1/§3.2.2:
  over the 300 files the golden suite type-checks, pre-fix "filter → print → **parse**" was
  "**50 / 300 fail**" and "filter → print → **type-check**" was "**24 / 300 fail**", with gensym
  reaching output in "**8 files**"; all three go to 0. The evaluation differential is reported as
  "**288 of 291 comparable files identical**", the three exceptions being clock-stamped files that
  "disagree with *themselves* across two runs of the original". Suites: `jl4-test` 2550/0,
  `jl4-core-test` 269/0, `l4-cli-test` 202/0, `jl4-service-test` 311/0, `jl4-lsp-test` 10/0.
- **PR #213** (`ci: fail the PR that ships a corpus without goldens…`), the source of the third trap
  in §3.1 and its **Why**: the check reports "`352 corpus file(s), each with all 4 goldens present`"
  on a good tree and exits 1 naming the four missing files on a bad one. The PR records the two
  incidents by number — BNA 1981 landed in #195 and was repaired by #202; the Jersey charities
  cleanroom did the same in #201, was repaired by #212, and "knocked **#207** out of the merge
  queue".
- **PR #208** (the enumeration-label ruling recorded in `drafting-patterns.md`): "**77** label-only
  sites across the four corpora … **73** operand-joined … **4** leading … **0** off-shape"; stripping
  every operand-joined label mechanically left `regcf.l4` (20 stripped) and `bna.l4` (16 stripped)
  **byte-identical** on re-evaluation; "**Zero occurrences of U+2026 in any of the four corpora**";
  Reg CF unmoved on both engines at "**1072/1072** decisions, **1072/1072** values" (KIE 8.44.0.Final
  and Camunda 8.7.6).
- **PR #174** (the `YMD` paragraph in `SKILL.md` and the footgun in `gotchas.md`): "`jl4-test`: 1854
  examples, 0 failures". The PR also records that "an earlier draft claimed YMD 'removes' the
  footgun and adversarial review killed the overclaim" — which is why the skill text says `YMD`
  makes the transposition harder to *write*, not impossible.
- **PR #122** (the source of `sets.md`): "**1136 examples, 0 failures** (includes 17 new goldens +
  refreshed prelude exactprint golden)". **PR #127**, which corrected the sets docs after variadic
  `SET OF` landed: "Doc example re-validated against merged unstable: **13/13 `#EVAL`s green.**"
- **PR #154** (the `l4 export` entry in `SKILL.md`): `l4-cli-test` "64 examples, 0 failures" →
  "**87, 0** — +23, all `l4 export`".
- **PR #156 / #164** (the `BUILD-SPEC` status header): no counts — the claims were checked by
  execution and by sweeping refs. #156 records that `package.yaml`, `stack.yaml` and
  `stack.yaml.lock` were "present on trunk **and on every other ref** — a sweep found none without
  `stack.yaml`"; #164 re-verified at push time "against `smucclaw/dmnmd` trunk `744b6b2`: no
  `package.yaml`, no `stack.yaml`, CI runs `cabal test` then `make corpus`."
- **`L4-LINT-DESIGN.md` §0**, self-contained in the file: the display-width finding was settled
  against the real binary — "a line of 43 code points containing one `中` reports `end column = 45`",
  with the width characterization "East_Asian_Width W/F → 2, else → 1, per code point" and the note
  that ZWJ emoji sequences are summed per code point with no grapheme clustering.

No quantitative claim is made here for the doc changes themselves beyond the diffstat
(`14 files, +3,644 / −24`) and the per-file line counts above, which were read off the tree.

## Independence

**It can merge alone and cannot break a build.** Nothing here is compiled, imported, linked or
executed by any test. `build-dmnmd-to-l4.workflow.js` sits at the repo root, outside the two npm
workspace globs (`ts-apps/*`, `ts-shared/*`), and nothing runs it; it is a record of an agent script.
The only automated gate these files face is repo-wide `format:check` (`prettier --check .`, pinned
to `3.4.2` in `package.json`, and `.prettierignore` does not exclude the repo root or `.claude/`),
which they satisfy.

**But several of its sentences are forward references, and a reviewer should decide deliberately
whether to merge prose ahead of the code it describes.** Specifically:

- `CLAUDE.md` §3.1's third trap and its **Why** name `etc/check-corpus-goldens.mjs` and say it "now
  runs in CI on every event with no filter and no build". That script and its workflow job belong to
  theme **ci-build**. Merged alone, this is a pointer to a file that is not there yet.
- `CLAUDE.md` §3.2 / §3.2.1 / §3.2.2 describe the `prettyLayout round-trip` property, the
  `JL4_EVALDIFF` differential and the `JL4_PRETTY_DUMP_DIR` debugging switch. Those belong with the
  printer work — theme **lang-printer**.
- `SKILL.md`'s new CLI bullet documents `l4 export --to=dmn|dmn-md|bpmn` with `--fidelity-report`.
  The subcommand is carried by **service-cli**, and the exporters behind it by **dmn-export** and
  **bpmn-export**.
- `SKILL.md`'s date paragraph and the `gotchas.md` footgun entry teach `YMD`, which lives in
  `jl4-core/libraries/daydate.l4` — theme **lang-imports-stdlib**.
- The `README.md` / `AGENTS.md` table edit is only *correct* once `jl4-actus-analyzer` is actually
  gone; that removal is theme **actus-archive**. Landing this first leaves the tables briefly
  understating the tree; landing actus-archive first without this leaves them overstating it. The
  second failure mode is the worse one, so the safe order is actus-archive first or both together.

Everything else — the five repo-root design records, `state-ledger.md`, `sets.md`, the drafting
patterns, and every part of `CLAUDE.md` other than §3.1's third trap and §3.2 — is genuinely
standalone prose that describes code already on `main`, or describes no code at all.

None of these forward references can fail a check. They read as stale documentation until the
sibling lands, which is the ordinary cost of splitting one branch into twenty-five PRs, not a
breakage.

## Risk if rejected

Dropping this while its siblings land means the repo gains the corpus-goldens CI check, the printer
round-trip property, `l4 export` and `YMD` — and keeps none of the writing that tells anyone they
exist or why: the build lock, the three fake-failure traps, the two-printers distinction, the
enumeration-label ruling, and the `Date`-clamps-to-January footgun all go back to being tribal
knowledge, and `README.md`/`AGENTS.md` go on advertising a package the tree no longer contains.
The concrete cost is that the incidents recorded in each **Why** block — five issues left open, a
worktree of phantom compile errors, a corpus landing twice in one day without goldens — have nothing
stopping them from happening again.

## Provenance

Unstable PRs folded into this one:

- **#116** — `mengwong/ladder-diagrams-3` (the `TODO.md` workplan state)
- **#122** — `mengwong/set-operators-phase1` (`references/sets.md`)
- **#127** — `mengwong/set-docs-followup` (the singleton boundary in `sets.md`)
- **#136** — `mengwong/lexipedia-superset` (tracker updates)
- **#154** — `feat/export-surfaces` (`l4 export` in `SKILL.md`)
- **#156** — `docs/build-spec-drift` (**`CLAUDE.md` itself**, in commit `8b69494b`, plus the
  `BUILD-SPEC` cabal-only correction)
- **#164** — `docs/build-spec-drift` (the same sentence, corrected again in the other direction)
- **#174** — `mengwong/ymd-constructor` (`YMD` in `SKILL.md`, the `daydate` footgun in `gotchas.md`)
- **#208** — `mengwong/inert-label-truncation` (the enumeration-label ruling in `drafting-patterns.md`)
- **#213** — `fix/corpus-goldens-guard` (`CLAUDE.md` §3.1's third trap)
- **#214** — `mengwong/printer-batch-and-gensym` (`CLAUDE.md` §3.2, §3.2.1, §3.2.2)
- **#224** — `mengwong/go-explainer` (the 501(a)(4) decomposition, genitive-and-last-connective and
  scaffolding-as-structure sections of `drafting-patterns.md`)

Note for the reviewer reconciling history: seven of the fourteen files did **not** originate in the
twelve PRs above — they reached `unstable` earlier, through batch merges, and the theme manifest
does not list those numbers. Traced by walking `--ancestry-path` from each file's adding or editing
commit to the first merge that contains it:

| file | added by | arrived via |
| --- | --- | --- |
| `references/drafting-patterns.md`, `references/state-ledger.md` (and the `gotchas.md` footgun) | `82491b1a` | batch merge of **#39** `mengwong/l4-skill-update` |
| `BUILD-SPEC-dmnmd-to-l4.md` (589 lines then), `L4-LINT-DESIGN.md`, `build-dmnmd-to-l4.workflow.js` | `978513ca`, `77866927` | batch merge of **#42** `dmnmd-to-l4` (`d0366176`) |
| `BRANCH.md` | `3e4d05c4` | batch merge of **#44** `mengwong/fix-deontic-action-type-check` |
| `REVIEW-PART1-CODEBASE-MAP.md` | `b6e51203` | **#59** `docs/review-part2-status` |
| `README.md`, `AGENTS.md` (the actus rows) | `f2f646fc` | **#77** `integration/batch-merge` |

Two further numbers show up in the path and are worth knowing about: the total-enum section of
`drafting-patterns.md` came in via **#145** (`docs/total-enum-style`), and the batch merge of **#76**
(`fix/npm-lockfile-sync`) carried a 12-line reformat of `REVIEW-PART1-CODEBASE-MAP.md`. All of these
are read off commit subjects and merge ancestry in `origin/main..origin/unstable`, not from the
theme manifest.
