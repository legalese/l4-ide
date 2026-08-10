# Audit of the 25 aug2026 PR bodies

Read-only audit of `.pr-split/bodies/*.md` against the tree, the commit corpus and the source PRs.
Nothing here was taken on trust from the drafters' own summary.

Sources, named per finding:

1. **the commit corpus** — `git log --format='%H %s %b' origin/main..origin/unstable`, 900 commits,
   22 431 lines;
2. **the tree** — `git show origin/<ref>:<path>`, `git diff --stat origin/main...origin/unstable`;
3. **the source PRs** — `mcp__github__pull_request_read` against `legalese/l4-ide`. (`gh` is not
   installed in this environment and the REST API returns 403 for this session, so PR bodies had to
   be pulled one at a time through the MCP tool. The PR-sourced check is therefore a **sample of
   six PRs**, chosen to cover every numeric claim that the commit corpus could not already source.)

**Headline.** No fabricated measurement was found. Every number chased to ground checked out, most
of them byte-exact. The problems are structural, not evidentiary: the `dependsOn` graph is not a
DAG, and — more seriously — **the Haskell half of this split cannot be merged one PR at a time and
keep CI green**, for a reason no existing analysis file records (§2.4).

---

## 1. Fabrication check

### 1.1 Method

Every numeric token of two or more digits was extracted from all 25 bodies and matched against the
commit corpus. The great majority matched verbatim. The residue — **32 numbers across 15 bodies** —
was then chased individually against the tree or the source PRs. All 32 resolved.

### 1.2 Verified against the tree (exact matches, all of them)

| body | claim | measured |
| --- | --- | --- |
| dmn-export | `L4/Dmn/Lower.hs` 6792 lines | 6792 ✅ |
| dmn-export | `L4/Dmn/Analysis.hs` 1002 lines | 1002 ✅ |
| dmn-export | `jl4/tests/DmnExport.hs` 4198 lines | 4198 ✅ |
| go-pipeline | 89 files, **20223 insertions, 0 deletions** | `git diff --stat` over the theme's 89-path manifest: `89 files changed, 20223 insertions(+)` ✅ |
| go-pipeline | `selftest.mjs` 3569 · `render-explainer.mjs` 1489 · `lib/register-validate.mjs` 1123 · `lib/denovo-diff.mjs` 1508 | 3569 · 1489 · 1123 · 1508 ✅ |
| mlir | `runtime/jl4-runtime.mjs` 4401 → 4684 | main 4401, unstable 4684 ✅ |
| mlir | `MLIR/Lower.hs` 2695 → 3441 · `test/Main.hs` 572 → 1593 | exact on both ✅ |
| specs | `EXPLAINER-REPORT-SPEC.md` 1924 · `FIDELITY-SEVERITY-AXIS-SPEC.md` 1410 · `CORPUS-TRACK.md` 1529 · `EMBEDDABLE.md` 1167 · `LTS-VISUALISER.md` 1062 · `LEXIPEDIA-PROBE.md` 602 · `ladder-diagrams-2026/DESIGN.md` 1650 · `E1-IDE-INTEGRATION.md` 282 · `SET-OPERATORS-SPEC.md` 2116 · `SECTION-RANKING-SPEC.md` 1035 · `DMN-STEELMAN.md` 1242 | **all eleven exact** ✅ |
| wizards | "91 files, 7,140 insertions, 1 deletion"; housing "36 files, 2,432 insertions" | `91 files changed, 7140 insertions(+), 1 deletion(-)`; `36 files changed, 2432 insertions(+)` ✅ |
| ci-build | the Haskell job's `ubuntu:24.04` container | `container: ubuntu:24.04` in `pr-checks.yml` and `unstable-prerelease.yml` ✅ |
| openfisca-export | float32 `16777217 → 16777216.0`, `10000.001 → 10000.0009765625`, "~16.7 million" | verbatim in `jl4/examples/openfisca/L4-OPENFISCA.md` lines 194–199 ✅ (and the float32 arithmetic is independently correct) |
| dmn-export | `1540/1540` decisions/values on two engines | present in the commit corpus ✅ |

### 1.3 Verified against the source PRs

| body | claim | source |
| --- | --- | --- |
| corpus-regcf | #139: "`l4 check`: succeeds. `jl4-test`: **1486 examples, 0 failures**, goldens generated" | **verbatim** in #139 §Checks ✅ |
| bpmn-export | #157: "8 OK, 0 warnings"; `jl4-test` **1807/0**; `l4-cli-test` **87/0** | **verbatim** in #157 §Suites ✅ |
| go-pipeline | #197: `6800 evaluation(s) over 2944 row(s) × 13 pair(s) — 6800 agreed · 0 diverged`; the fourth perturbation's false green; `25 of 64 (pair, fact) leaves inert`; 48 cross-field `x-rules` | **verbatim**, including the ellipsised quotation marks ✅ |
| lang-printer / lang-syntax-typecheck / lang-imports-stdlib / docs | #109: "full golden suite green (1116 examples)", "9 new `BulletParserSpec` cases", "**0 of 571 `.l4` files**" | **verbatim** in #109 §Testing and §`indentedGE` ✅ |
| lang-imports-stdlib | #140: baseline **1481** / branch **1486**, "+5 is exactly this PR's one new fixture" | **verbatim** in #140 §Suite comparison ✅ |
| wizards | #200: `exportCount:6`; the four-row elicitation table; the two disagreeing `atomId`s; the five-date R8 table (`4000/4000/7500/7500/7500`) and the `2015-01-01` refusal; `viewBox="0 0 1062 180"`, rendered `685×116`; 2 `rect.lad-box` / 3 `polyline.lad-wire`; "exactly 1 violation, `style-src-attr`"; `47/47` | **verbatim throughout** ✅ |

### 1.4 Unsourced claims

**None found.** The one thing worth recording is a *presentational* hazard rather than a
fabrication:

- **Suite totals are quoted across PRs whose baselines differ, without saying so.**
  `corpus-regcf` quotes #139's `jl4-test` **1486**; `lang-imports-stdlib` quotes #140's *baseline*
  as **1481** and its branch as **1486**. Both are verbatim and both are honest, but #140's base
  commit (`3bc295db`) predates #139's merge by under an hour, so the two "1486"s count different
  things and the apparent 1486 → 1481 → 1486 sequence is an artifact. Several bodies already carry
  the right hedge (`lang-printer`: "whole-tree figures, not figures for this slice"). Recommend the
  same sentence wherever a suite total is quoted.

- Non-measurements correctly not treated as measurements: `lang-sets`'s `[2013] SGHC 155` /
  `[1904] 2 Ch 354` (law reports), `papers`'s "(1958)" (a publication year), `proleg`'s "Supreme
  Court rule of 1966.1.27" (a Japanese case date), `wizards`'s "income 150000, net worth 80000"
  (probe inputs).

---

## 2. Dependency coherence

### 2.1 The summarised `dependsOn` graph is not acyclic

Fed the 25 `dependsOn` lists to a cycle finder: **462 164 elementary cycles**, including **25
mutual (2-node) cycles**:

    actus-archive <-> agent-tooling      dmn-export <-> service-cli
    agent-tooling <-> ci-build           dmn-export <-> tests-cli
    bpmn-export   <-> service-cli        dmn-export <-> lang-syntax-typecheck
    bpmn-export   <-> ci-build           docs <-> lang-imports-stdlib
    ci-build      <-> wizards            go-pipeline <-> service-cli
    ci-build      <-> ladder-viz         ladder-viz <-> service-cli
    ci-build      <-> dmn-export         lang-eval-ledger <-> lang-syntax-typecheck
    ci-build      <-> go-pipeline        lang-eval-ledger <-> lang-printer
    ci-build      <-> mlir               lang-imports-stdlib <-> lang-syntax-typecheck
    lang-imports-stdlib <-> lsp          lang-printer <-> lang-syntax-typecheck
    lang-sets <-> lang-syntax-typecheck  lang-syntax-typecheck <-> service-cli
    openfisca-export <-> service-cli     openfisca-export <-> tests-cli
    service-cli <-> tests-cli

Part of this is a **terminology collision**: the drafters used `dependsOn` for any coupling — "will
not compile without", "its goldens encode", "its measurement is unreproducible without", "its prose
forward-references this". Under that reading a mutual edge is meaningful; under a merge-order
reading it is a deadlock.

**Recommendation.** Do not hand the summarised `dependsOn` field to reviewers as a merge order.
Split it into `blocksCompile` and `blocksEvidence`, or rename it `coupledWith`.

But do not dismiss it either — §2.4 shows that several of these mutual edges are **real, hard and
compile-level**, and that the file that reviewers *would* trust understates them.

### 2.2 `selfContained` is used inconsistently

- **`papers`** is `selfContained: true` *and* carries `dependsOn: [ladder-viz, specs, docs]`. On
  their face the two fields contradict. Reading the body, `true` is right in the sense that matters
  (nothing in CI reads `paper/`) and the `dependsOn` entries are stale-link risks only.
- **`specs`** and **`proleg`** are the only themes with `selfContained: true` and `dependsOn: []`.
  Both survive inspection — `specs` is markdown-only; `proleg` is a new package nothing imports.
- Every other theme is `selfContained: false`, which is honest but carries no information: it does
  not distinguish "will not compile" from "a sentence forward-references a sibling".

### 2.3 Bodies that carry another theme's behaviour — correctly disclosed

`lang-printer` is the model here and should be copied. It states plainly that **five of its six new
hspec specs test `lang-syntax-typecheck`'s code**, that four of its `.ep.golden` deltas record a
one-line `L4/Parser.hs` fix owned by that theme, and that **its own new `exactprint identity`
invariant is red without it**. That is exactly the "carries goldens for a printer it does not ship"
failure mode the audit was asked to hunt, found and disclosed by the drafter rather than hidden.

Two corrections to that disclosure, both verified against the tree:

- It attributes `Record` / `ReadCell` / `RecallMode` to **lang-eval-ledger**. They are `Expr`
  constructors declared in `jl4-core/src/L4/Syntax.hs` (unstable lines 263, 289, 344), which the
  manifests assign to **lang-syntax-typecheck**. The ordering advice ("lang-eval-ledger before or
  beside it") is therefore aimed at the wrong theme.
- Its closing "Ordering" paragraph says `service-cli` "may land in any order relative to this one".
  §2.4 shows that is not true.

### 2.4 The dependency that `DEPENDENCIES.md` misses, and it is the load-bearing one

`DEPENDENCIES.md` states: *"Five edges exist. Everything not listed here has no compile-time
dependency on a sibling."* That is measured by `depcheck.mjs`, which resolves **module imports**.
It cannot see **constructor-level** dependencies, because `L4.Syntax` is a module `main` already
has. Measured here:

**`lang-syntax-typecheck` removes the `Expr` constructor `Exponent`.** (`git show
origin/main:jl4-core/src/L4/Syntax.hs` line 216 has it; on `origin/unstable` it is gone. Expr goes
from 38 constructors to 39: −1 `Exponent`, +2 `Record`/`ReadCell`.)

The modules that pattern-match `Exponent` on `main`, and the theme each is assigned to:

| module | theme |
| --- | --- |
| `L4/Desugar.hs`, `L4/TypeCheck.hs`, `L4/TypeCheck/Annotation.hs`, `L4/Parser/ResolveAnnotation.hs` | lang-syntax-typecheck |
| `L4/EvaluateLazy/Machine.hs` | **lang-eval-ledger** |
| `L4/Nlg.hs`, `L4/Export/Document.hs` | **service-cli** |
| `L4/Print.hs` | **lang-printer** |
| `jl4-mlir/src/L4/MLIR/{Lower,Marshal,Schema}.hs` | **mlir** |

Consequences, both directions:

- **`lang-syntax-typecheck` alone does not compile.** Deleting the constructor leaves five other
  themes' modules referencing a data constructor that is not in scope — a hard error, not a
  warning.
- **Any of those five alone does not compile either.** The diff removes their `Exponent` arms
  (verified: `Machine.hs` drops `Exponent _ann e1 e2 -> pushFrame (BinOp1 BinOpExponent …)`;
  `Nlg.hs` / `Export/Document.hs` drop `Exponent{} -> True` and `Exponent _ a b -> bin 3 " ^ " a b`)
  while the constructor still exists → `-Wall -Werror` incomplete patterns, which §3 of `CLAUDE.md`
  confirms is fatal here.
- The symmetric hazard applies to the two **added** constructors: every exhaustive `case` over
  `Expr` in a theme that is not lang-syntax-typecheck goes incomplete the moment `Syntax.hs` lands
  without it, and vice versa.

**So the mutual edges `lang-syntax-typecheck ↔ lang-eval-ledger`, `↔ lang-printer`, `↔ service-cli`
and `↔ mlir` are genuine and unbreakable at file granularity.** They are a property of a
*file-level* split of a change that was semantically atomic. This is not fixable by reordering; it
is fixable only by merging those PRs as one queue batch, or by re-cutting the split at hunk level
for `Syntax.hs` the way `.pr-split/spine/hunks.json` already does for the five `.cabal`/`Main.hs`
spine files.

`DEPENDENCIES.md` should say, in its own words, that `depcheck.mjs` measures imports and is
therefore **known-incomplete for constructor-level edges**, and should name this one.

### 2.5 `actus-archive`'s stated dependency on `proleg` is stale

`actus-archive.md` §Independence says `cabal.project` "is owned by the **proleg** theme … it must
not merge before proleg", and the summary's riskNote repeats it. `DEPENDENCIES.md` (written 18
minutes later) records the opposite and says the problem was already fixed: *"`cabal.project` is no
longer a shared file … Each PR now makes its own edit"* — and `ship.sh` is documented as making
"the two special-case `cabal.project` edits". `cabal.project` appears in `analysis/spine.txt` but
**not** in `spine/hunks.json`, consistent with the special case.

Fix the body (and drop `proleg` from actus-archive's `dependsOn`), or fix `DEPENDENCIES.md`. As it
stands the two files in the same directory give opposite instructions about the same file.

### 2.6 `actus-archive` should merge early, not late

The summary places `actus-archive` after `agent-tooling`, `specs` and `proleg`. But
`jl4-actus-analyzer` imports `L4.Syntax` in seven modules, and it is the only package no theme
updates for the `Expr` churn in §2.4 — it is simply deleted. **It should therefore land at or
before `lang-syntax-typecheck`,** not at the end. The only thing that argues for late is cosmetic:
`README.md` and `AGENTS.md` still name the package until `agent-tooling` lands, leaving a dangling
reference in prose for a while. Prose beats a red build.

### 2.7 Undeclared edge: `corpus-legal-new → papers`

`corpus-legal-new`'s headline cleanroom measurement compares its own `charity-test.l4` against
`part-3-charity-test.l4`, which the manifests assign to **papers**
(`paper/case-studies/charities-jersey-2014/part-3-charity-test.l4`). `papers` is absent from
`corpus-legal-new`'s `dependsOn`. Nothing breaks — but the measurement is unreproducible from the
PR until papers lands.

### 2.8 `specs` must merge early, and nothing says so

`specs` is `dependsOn: []`, which reads as "unconstrained". It is in fact a **hard blocker in the
other direction**: `go-pipeline`'s validator, selftests and HG1/HG2 gate resolve paths under
`specs/todo/single-instruction-demo/`, and `docs`'s `doc/test-docs.sh` link check resolves four
`doc/ → specs/` links that only exist once specs lands. Its own riskNote says this; the
`dependsOn` field cannot express it.

### 2.9 `wizards` is one body over two manifests

`themes/` has `wizard-housing.files` (36) and `wizard-regcf.files` (55); `DEPENDENCIES.md` argues
explicitly for two PRs (*"this is why the wizards are two PRs and not one"* — `npm ci` on a
regcf-only slice fails with `404 … @repo%2fladder-core`); `RUNBOOK.md` says "once all **26** PRs
exist". But `bodies/` has a single `wizards.md`, written for one PR ("Two standalone SvelteKit
single-page apps"), and `STATUS.tsv` has **no wizards row at all** — 24 rows, of which `tests-cli`
has no PR number.

**This needs a decision before the PRs are opened**: either split `wizards.md` in two, or fold the
manifests into one theme and amend `DEPENDENCIES.md`. Note that the merged form loses a real
property the split form has — that `wizard-housing` is the one front-end slice that stands alone on
`main`.

---

## 3. Merge order

### 3.1 The honest form of the answer

There is **no total order of 25 single PRs that keeps `main` green**, because of §2.4. What follows
is a five-wave order in which every *wave* is green, and only one wave (Wave 2) has to enter the
merge queue as a batch rather than one PR at a time.

### Wave 0 — additive, green alone, unblocks others

1. **`specs`** — markdown only. First, because go-pipeline and docs resolve paths into it (§2.8).
2. **`proleg`** — new package plus its own one-line `cabal.project` addition; nothing imports it.
3. **`actus-archive`** — deletes `jl4-actus-analyzer` plus its own `cabal.project` deletion. Early,
   not late (§2.6). Leaves a cosmetic dangling mention in `README`/`AGENTS` until Wave 4.
4. **`papers`** — `paper/**` only; nothing in CI reads it. Placed here so `corpus-legal-new`'s
   comparison target exists (§2.7).

### Wave 1 — front-end slice that stands alone

5. **`wizard-housing`** (if the split of §2.9 is kept) — needs only `jl4-client-rpc`, already on
   `main`. Its lockfile regeneration is the one to land *before* ci-build's, so ci-build's is the
   reconciling one.

### Wave 2 — the jl4-core Haskell train: **one merge-queue batch, not a sequence**

6. `lang-syntax-typecheck`, `lang-eval-ledger`, `lang-printer`, `lang-imports-stdlib`, `lang-sets`,
   `lsp`, `ladder-viz`, `dmn-export`, `bpmn-export`, `openfisca-export`, `service-cli`, `mlir`

   Within the batch, the stacking order that makes each *diff* reviewable is
   `lang-syntax-typecheck → lang-eval-ledger → lang-printer → lang-imports-stdlib → lang-sets →
   lsp → ladder-viz → dmn-export → {bpmn-export, openfisca-export} → service-cli → mlir`
   (the tail is `DEPENDENCIES.md`'s measured DAG, which is correct as far as it goes). But every
   intermediate state fails to build for the reason in §2.4, so **CI must be run on the tip, and
   the batch merged together.** If the queue cannot do that, the alternative is to re-cut
   `Syntax.hs` (and the five `Exponent` consumers) at hunk level, as the spine already does for the
   `.cabal` files.

### Wave 3 — corpora, fixtures and harnesses, after the code whose output they encode

7. `corpus-regcf` — the subject every projection theme regenerates from.
8. `corpus-legal-new` — its `bna.dmn`/fidelity sidecars are only reproducible once dmn-export has
   landed, and three of its goldens encode Wave-2 printer/typechecker behaviour.
9. `experiments`
10. `tests-cli`
11. `go-pipeline` — needs `specs` (Wave 0), `l4 verify`/`l4 nlg` (service-cli, Wave 2) and the
    regcf corpus.
12. `wizard-regcf` — after `ladder-viz` (`@repo/ladder-{core,svg}` do not exist on `main`).

### Wave 4 — prose

13. `docs` — after Wave 2 and `specs`: `doc/test-docs.sh` runs `l4` over three doc `.l4` files that
    need Wave-2 features, and link-checks into `specs/`.
14. `agent-tooling` — after `actus-archive` (it owns the `README`/`AGENTS` edits that remove the
    dangling reference) and after everything its prose forward-references.

### Wave 5 — the gate layer, last

15. **`ci-build`**.

### 3.2 PRs that must land after the features they gate

- **`ci-build` is the clear case, and `DEPENDENCIES.md` already argues it well.** Landing it early
  reddens `main` for defects that predate the whole exercise:
  - `etc/check-corpus-goldens.mjs` **fails on plain `origin/main` today** — three
    `jl4/examples/not-ok/export-*.l4` fixtures carry no goldens. The twelve goldens that close the
    gap are in **lang-syntax-typecheck**.
  - the new *"sdist must carry the standard library"* step fails on plain `main` — `data-files:
    libraries/*.l4` sits after the flag stanzas. The reordering travels with
    **lang-imports-stdlib**.
  - `package-lock.json` names workspaces that only exist once **ladder-viz** and both wizards land
    (`npm ci` otherwise 404s on `@repo/ladder-core`).
  - `nix/default.nix` and `nix/configuration.nix` reference `./regcf-wizard/{package,configuration}.nix`,
    owned by **wizards** — `Nix Flake Check` fails if those are absent. Hard pairing.
  - it also ships filters and jobs for `etc/check-bpmn-kie.sh` (**bpmn-export**) and `etc/go/go.sh`
    (**go-pipeline**).
- **`docs` is the second case** and is easy to miss: `main`'s `docs: doc/**` path filter runs the
  Haskell job, whose last step `doc/test-docs.sh` executes `l4` over doc `.l4` files. Landing docs
  before Wave 2 turns `main` red.
- **`tests-cli` and `go-pipeline`** gate on binaries that Wave 2 introduces (`l4 export`, `l4 nlg`,
  `l4 verify`, `l4 openfisca`); landing either early leaves cases invoking subcommands that do not
  exist.
- **The corpus themes** must land after Wave 2 for the reason `CLAUDE.md` §3.1 gives about goldens:
  a `.l4` whose goldens encode not-yet-landed behaviour turns `jl4-test` red, on someone else's
  branch.

---

## 4. Gaps and overlaps

### 4.1 One genuine overlap: `turbo.json`

`wizards.md` describes it — *"`turbo.json` gains `BASE_PATH` to its build task's `env` list — the
one-line change the nix build needs"* — and `ci-build.md` describes the same edit twice, once under
**What's in it** (*"`turbo.json`: `BASE_PATH` added to the `build` task's `env` list"*) and once
under *"Genuinely self-contained within this PR"*. `grep -l '^turbo.json$' themes/*.files` returns
**`wizard-regcf.files` only**. One of the two bodies is describing a file it does not ship, and
`ci-build`'s is the one to correct (it also claims it as evidence of self-containment).

### 4.2 No file is carried by two PRs

`cat themes/*.files | sort | uniq -d` is empty. The five genuinely shared files
(`cabal.project`, four `.cabal` files, `jl4/tests/Main.hs`) are split at hunk level via
`spine/hunks.json` and the two `ship.sh` special cases.

### 4.3 Cross-theme file mentions are disclosures, not overlaps

Every backtick-quoted path in every body was resolved against the manifests. Apart from §4.1, every
foreign path appears inside an *Independence* or *Risk if rejected* section — the intended use. The
density is a signal in itself: `bpmn-export` names ten foreign files, `dmn-export` eleven,
`go-pipeline` thirteen. Those bodies are doing the disclosure job well.

### 4.4 Coverage gap in the artifacts, not the bodies

`STATUS.tsv` tracks 24 themes and no wizards row (§2.9); `tests-cli` has a blank PR number. Before
opening, reconcile `STATUS.tsv`, `themes/INDEX.tsv` (26 manifests), `bodies/` (25 files) and
`RUNBOOK.md`'s "26 PRs" so all four agree on the count.

---

## Reproduction

    git log --format='===COMMIT %H%n%s%n%b' origin/main..origin/unstable        # the commit corpus
    git diff --stat origin/main...origin/unstable -- $(tr '\n' ' ' < .pr-split/themes/<t>.files)
    git show origin/main:jl4-core/src/L4/Syntax.hs | grep -n Exponent           # §2.4
    git grep -l Exponent origin/main -- '*.hs'                                  # §2.4
    cat .pr-split/themes/*.files | sort | uniq -d                               # §4.2
