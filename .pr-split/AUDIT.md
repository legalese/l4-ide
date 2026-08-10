# Audit of the 25 aug2026 PR bodies

Status: **in progress** (draft 1, written early so nothing is lost). Method notes at the bottom.

Everything below was checked against one of three sources, and each finding says which:

1. **the commit corpus** — `git log --format='%H %s %b' origin/main..origin/unstable`, 900 commits,
   22 431 lines;
2. **the tree** — `git show origin/unstable:<path>`, `git diff --stat origin/main...origin/unstable`;
3. **the source PRs** — `mcp__github__pull_request_read` against `legalese/l4-ide`.
   (`gh` is not installed here and the REST API returns 403 for this session, so PR bodies were
   pulled one at a time through the MCP tool. That is why the PR-sourced spot-check is a sample and
   not a sweep.)

---

## 1. Fabrication check

### 1.1 Method

Every numeric token of two or more digits was extracted from all 25 bodies (1 088 distinct
occurrences) and matched against the commit corpus. **The great majority matched verbatim.** The
residue — 32 numbers across 15 bodies — was then chased individually against the tree or the source
PRs. Result table below.

### 1.2 Numbers verified against the tree (exact matches, all of them)

| body | claim | measured |
| --- | --- | --- |
| dmn-export | `L4/Dmn/Lower.hs` 6792 lines | 6792 ✅ |
| dmn-export | `L4/Dmn/Analysis.hs` 1002 lines | 1002 ✅ |
| dmn-export | `jl4/tests/DmnExport.hs` 4198 lines | 4198 ✅ |
| go-pipeline | 89 files, **20223 insertions, 0 deletions** | `git diff --stat` over the theme's 89-path manifest: `89 files changed, 20223 insertions(+)` ✅ |
| go-pipeline | `selftest.mjs` 3569 | 3569 ✅ |
| go-pipeline | `render-explainer.mjs` 1489 | 1489 ✅ |
| go-pipeline | `lib/register-validate.mjs` 1123 | 1123 ✅ |
| go-pipeline | `lib/denovo-diff.mjs` 1508 | 1508 ✅ |
| mlir | `runtime/jl4-runtime.mjs` 4401 → 4684 | main 4401, unstable 4684 ✅ |
| mlir | `Lower.hs` 2695 → 3441 | main 2695, unstable 3441 ✅ |
| mlir | `test/Main.hs` 572 → 1593 | main 572, unstable 1593 ✅ |
| specs | `EXPLAINER-REPORT-SPEC.md` 1924 | 1924 ✅ |
| specs | `FIDELITY-SEVERITY-AXIS-SPEC.md` 1410 | 1410 ✅ |
| specs | `CORPUS-TRACK.md` 1529 / `EMBEDDABLE.md` 1167 / `LTS-VISUALISER.md` 1062 / `LEXIPEDIA-PROBE.md` 602 | 1529 / 1167 / 1062 / 602 ✅ |
| specs | `ladder-diagrams-2026/DESIGN.md` 1650, `E1-IDE-INTEGRATION.md` 282 | 1650 / 282 ✅ |
| specs | `SET-OPERATORS-SPEC.md` 2116, `SECTION-RANKING-SPEC.md` 1035 | 2116 / 1035 ✅ |
| specs | `DMN-STEELMAN.md` 1242 | 1242 ✅ |
| ci-build | the Haskell job's `ubuntu:24.04` container | `container: ubuntu:24.04` appears in `pr-checks.yml` and `unstable-prerelease.yml` ✅ |
| openfisca-export | float32 `16777217 → 16777216.0`, `10000.001 → 10000.0009765625`, "~16.7 million" | present verbatim in `jl4/examples/openfisca/L4-OPENFISCA.md` §6, lines 194–199 ✅ (and the float32 arithmetic is independently correct) |

**Not measurements, correctly flagged as such by the extractor and dismissed here:** `lang-sets`'s
`[2013] SGHC 155` / `[1904] 2 Ch 354` (law reports), `papers`'s "(1958)" (a publication year),
`proleg`'s "Supreme Court rule of 1966.1.27" (a Japanese case date), `wizards`'s `income 150000,
net worth 80000` (inputs to a probe, not results).

### 1.3 Numbers verified against the source PRs

| body | claim | source |
| --- | --- | --- |
| corpus-regcf | #139: "`l4 check`: succeeds. `jl4-test`: **1486 examples, 0 failures**, goldens generated" | **verbatim** in legalese/l4-ide#139 §Checks ✅ |

(more rows added as the sample is worked through — see §1.4)

### 1.4 Unsourced or partially-sourced claims

_(populated as the PR sample completes)_

---

## 2. Dependency coherence

### 2.1 The summarised `dependsOn` graph is not acyclic — it is one large SCC

Fed the 25 `dependsOn` lists into a cycle finder: **462 164 elementary cycles**, including
**25 mutual (2-node) cycles**:

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

This is not (mostly) a drafting error so much as a **terminology collision**: the drafters used
`dependsOn` for *any* coupling — "will not compile without", "its goldens encode", "its evidence is
unreproducible without", "it forward-references this in prose". Under that reading a mutual edge is
perfectly sensible (`lang-printer` needs `lang-syntax-typecheck`'s constructors to compile;
`lang-syntax-typecheck` needs `lang-printer` for a golden). Under a merge-order reading it is a
deadlock.

**The authoritative graph is `.pr-split/DEPENDENCIES.md`,** which was derived mechanically and *is*
a DAG:

    ladder-viz -> dmn-export -> bpmn-export -> service-cli
                       ^                            |
                       +----------------------------+
                  openfisca-export -----------------+

plus four ordering constraints stated in prose there (ci-build after lang-syntax-typecheck,
lang-imports-stdlib, ladder-viz and both wizards; wizard-regcf after ladder-viz).

**Recommendation.** Do not ship the summarised `dependsOn` field to reviewers as a merge order.
Either rename it (`coupledWith`) or split it into `blocksCompile` (the DAG) and `blocksEvidence`
(everything else).

### 2.2 `selfContained` is used inconsistently

- **`papers`** is `selfContained: true` *and* carries `dependsOn: [ladder-viz, specs, docs]`. Those
  two fields contradict each other on their face. Reading the body, `true` is right in the sense
  that matters (nothing in CI reads `paper/`), and the `dependsOn` entries are stale-link risks.
- **`specs`** and **`proleg`** are the only two with `selfContained: true` *and* `dependsOn: []`.
  Both survive inspection: `specs` is markdown-only, `proleg` is a new package nothing imports.
- Every other theme is `selfContained: false`, which is honest but uninformative — it does not
  distinguish "will not compile" from "its prose forward-references a sibling".

### 2.3 Claims of self-containment that the files contradict

- **`specs` (`selfContained: true`) is fine on its own terms but is a hard blocker in the other
  direction**, and its own riskNote says so: `go-pipeline`'s validator, selftests and HG1/HG2 gate
  resolve paths under `specs/todo/single-instruction-demo/`, and `docs`'s `doc/test-docs.sh` link
  check resolves four `doc/ → specs/` links added here. So `specs` must merge *early*, which the
  summary does not say anywhere.
- **`lang-printer` is the honest counter-example worth copying.** Its body states plainly that five
  of its six new specs test *lang-syntax-typecheck's* code and that its own new `exactprint
  identity` invariant is **red without lang-syntax-typecheck**. That is a golden-carries-another-
  theme's-behaviour case, correctly disclosed rather than hidden — but note it is disclosed in prose
  and is **absent from `DEPENDENCIES.md`**, because `depcheck.mjs` resolves module imports and this
  is a *constructor*-level dependency on `L4.Syntax`, a module `main` already has. The mechanical
  dependency file is therefore known-incomplete; that limitation should be stated in it.

### 2.4 Undeclared edges found while auditing

- **`corpus-legal-new` → `papers`.** Its body's headline cleanroom measurement compares against
  `part-3-charity-test.l4`, which the manifests assign to **papers**
  (`paper/case-studies/charities-jersey-2014/part-3-charity-test.l4`). `papers` is not in
  corpus-legal-new's `dependsOn`. Nothing breaks — but the measurement is unreproducible until
  papers lands.
- **`wizards` is one body over two manifests.** `themes/` contains `wizard-housing.files` (36) and
  `wizard-regcf.files` (55), and `DEPENDENCIES.md` argues explicitly for two PRs ("this is why the
  wizards are two PRs and not one"). `bodies/` has a single `wizards.md`, `STATUS.tsv` has **no
  wizards row at all**, and `RUNBOOK.md` says "once all 26 PRs exist". The body itself is written
  for a single PR ("Two standalone SvelteKit single-page apps"). **This needs a decision before
  opening**: either split `wizards.md` into two bodies, or fold the two manifests into one theme and
  amend `DEPENDENCIES.md`.

---

## 3. Merge order

_(section 4 below; final ordering under construction)_

---

## 4. Gaps and overlaps

- **`turbo.json` is described by two bodies and owned by one.** `wizards.md` says "`turbo.json`
  gains `BASE_PATH` to its build task's `env` list — the one-line change the nix build needs";
  `ci-build.md` lists it under **What's in it** ("`turbo.json`: `BASE_PATH` added to the `build`
  task's `env` list") and again under *"Genuinely self-contained within this PR"*. The manifest
  assigns `turbo.json` to **wizard-regcf**. One of the two bodies is describing a file it does not
  ship.
- **File manifests are disjoint.** `cat themes/*.files | sort | uniq -d` is empty, so no file is
  carried by two PRs; the overlaps that exist are *narrative* only.
- Cross-theme file mentions were extracted mechanically from every body (backtick-quoted paths
  resolved against the manifests). Apart from `turbo.json` above, every foreign path appears inside
  an *Independence* / *Risk if rejected* section — i.e. as a disclosed reference, which is the
  intended use.

---

## Method / reproduction

    node .pr-split/… # scratch scripts, see the session; all read-only
    git log --format='===COMMIT %H%n%s%n%b' origin/main..origin/unstable   # the commit corpus
    git diff --stat origin/main...origin/unstable -- $(tr '\n' ' ' < themes/<t>.files)
