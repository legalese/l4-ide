# Spec Implementation — WIP Index

Tracks the Tier-1/Tier-2 implementation push + the spec staleness audit. All PRs target `unstable` (never `main`). `gh` authenticated as `mengwong`. Worktrees under `../l4wt/`. Git identity set globally; commits use `--no-verify` (husky hook has a perm-denied issue in this env).

**Status legend:** ⬜ todo · 🟡 implementing (bg agent) · 🛡️ hardening · 🚀 pushed · ✅ PR merged · ⏭️ skipped (already resolved) · ❌ blocked

## Staleness audit — ✅ DONE (PR #46 merged to unstable)

Audited all 31 todo specs + roadmap. 9 resolved specs moved to `specs/done/`; 18 reality-banners added; roadmap annotated. See PR #46.

## Tier-1

| #   | Spec                        | Verdict     | Branch                          | Status                                    | PR                                                |
| --- | --------------------------- | ----------- | ------------------------------- | ----------------------------------------- | ------------------------------------------------- |
| 1   | batch-json-output           | ✅ RESOLVED | —                               | ⏭️ archived→done                          | —                                                 |
| 2   | RUNTIME-CLOCK-AND-DATEVALUE | ✅ RESOLVED | —                               | ⏭️ archived→done                          | —                                                 |
| 3   | PATTERN-MATCHING (Phase 1)  | 🟢 OPEN     | `tier1/pattern-matching-p1`     | ✅ hardened (2 fixes, f030c28c) — PR open | [#49](https://github.com/legalese/l4-ide/pull/49) |
| 4   | MATH-LIBRARY (Phase 1)      | ✅ RESOLVED | —                               | ⏭️ archived→done                          | —                                                 |
| 5   | SECTION-LEXICAL-SCOPING     | 🟢 OPEN     | `tier1/section-lexical-scoping` | ✅ hardened (3 fixes, a6ac3e7a) — PR open | [#50](https://github.com/legalese/l4-ide/pull/50) |

## Tier-2

| Spec                              | Verdict               | Branch                           | Status                                    | PR                                                |
| --------------------------------- | --------------------- | -------------------------------- | ----------------------------------------- | ------------------------------------------------- |
| MULTILINE-MIXFIX                  | ✅ RESOLVED           | —                                | ⏭️ archived→done                          | —                                                 |
| LIST-SYNTAX-RELAXATION            | ✅ RESOLVED           | —                                | ⏭️ archived→done                          | —                                                 |
| REF-ANNOTATION                    | 🟢 OPEN               | `tier2/ref-annotation`           | ✅ hardened (3 fixes, f2acf556) — PR open | [#48](https://github.com/legalese/l4-ide/pull/48) |
| BATCH-PROCESSING (finish partial) | 🟡 PARTIAL            | `tier2/batch-processing`         | ✅ hardened (3 fixes, 291cd005) — PR open | [#47](https://github.com/legalese/l4-ide/pull/47) |
| L4-VERSIONING                     | ⚠️ premise superseded | —                                | ⏸️ HELD — awaiting scope decision         | —                                                 |
| PRODUCT-STRATEGY-2025-01          | roadmap doc           | —                                | ⏭️ not implementable                      | —                                                 |
| LIBRARY-RESOLUTION-SHADOW         | 🟢 OPEN (DX/infra)    | `docs/library-resolution-shadow` | ⬜ todo — spec only, no PR                | —                                                 |

> **LIBRARY-RESOLUTION-SHADOW** (classified Tier-2: DX/infra, low-risk, high-annoyance).
> `IMPORT` resolution searches ambient/global filesystem locations (XDG data dir, VSCode
> bundle) **above** the binary's own hermetic embedded stdlib, so during multi-worktree dev
> an XDG symlink into one checkout silently shadows edits made in another — with no
> diagnostic (the `@infixl` prelude incident; second occurrence of "XDG library shadow").
> Spec: `specs/todo/LIBRARY-RESOLUTION-SHADOW-SPEC.md`. Recommended path: Stage 1 = visible
> canonicalized logging + de-dup the two resolvers (`GetMixfixRegistry` vs `GetImports`);
> Stage 2 = surgical precedence flip (embedded above the two ambient locations, project-scoped
> overrides still above embedded) + ambiguity warning. Design sketch only — implementer
> should build against the spec's §8 acceptance criteria; anchors at `jl4-lsp/src/LSP/L4/Rules.hs:252-478`.

## Live lanes in ../l4wt/ (do NOT duplicate)

- `mengwong/consider-exhaustiveness` (active 83m ago) + `fix/consider-exhaustiveness-in-where` (60m ago) — **overlaps pattern-matching (CONSIDER/WHEN)**; coordinate at merge.
- `mengwong/bounded-deontics-paper` (3d), `verification-backend-lowering-spec` (3d) — deontics/verification (Tier 3/5).
- `dmnmd-to-l4` (18m), `ladder-diagrams-3` (2d) — active, unrelated.
- `bullet-list-syntax` — **ACTIVE, PR [#109](https://github.com/legalese/l4-ide/pull/109) → unstable** (2026-07-10). `•` bullet syntax + `hierarchy.l4` rose-tree library for isomorphic recitals/outlines. Rebased onto current unstable, multi-agent reviewed + hardened (stale-comment cleanup, doc-prose fixes, `BulletParserSpec` coverage, `indentedGE` corner case pinned — 0/571 corpus files affected). Fast-follow (not blocking): syntax-highlight `•` in `ts-shared/l4-highlight/src/monarch.ts`.

## Ladder diagram / visualizer

Home for the ladder rework: **`specs/todo/ladder-diagrams-2026/DESIGN.md` on branch `mengwong/ladder-diagrams-3`** (`../l4wt/ladder-diagrams-3`). Open upstream issues:

- **#630 — "visualizer expansion could use some improvement"** (mislabeled `bug`; really an **enhancement**). The current-codebase symptom is the narrow `canInline` (boolean same-file top-level `DECIDE` only; no functions-with-args / imported / `WHERE`-bound; inline name lost). **Superseded by the 2026 design** — see DESIGN.md §16 "Folding & progressive disclosure" + §16.1 (`NamedExpr`), where #630's write-up now lives. Fix = "adopt the §16 fold model," not a `canInline` patch.
- **#557** — viz sync race (inline-able subexpr + auto-refresh → stale ladder); scoping agent running. **#551** — jl4-web red gutter mispositioned; scoping agent running.

### question-ordering v2 (TYPICALLY priors) — ✅ MERGED 2026-07-10 (PR #110) — **SPEC: `specs/todo/QUESTION-ORDERING-SPEC.md` (§8)**

**PR [#110](https://github.com/legalese/l4-ide/pull/110) "TYPICALLY priors for question ordering (v2)" merged to `unstable`** (commit a030d0b9, worktree `../l4wt/question-ordering-v2`). Its merge_group run doubled as the #110 Tier-1 cache reproduction (see Infra RESOLVED banner). Point a resuming session at the spec for follow-ups. State: v1 prior-free info-gain = **PR #94**; TYPICALLY metadata = **PR #92** (both MERGEABLE, unmerged). v2 = prior-aware ordering, **boolean-only** (Meng-approved 2026-07-08: `TYPICALLY TRUE→0.9 / FALSE→0.1`, everything else ½).
**Blocking dependency is SHARED with #96 — do not build it twice.** TYPICALLY does not reach the wizard today (`PartialEvalAnalyzer` built from the `IRExpr` alone, `ladder.svelte.ts:322`; the default stops at the JSON schema). Both v2 (ordering weights) and #96's §22 tentative rendering need the SAME L4→atom flow: "which atoms are Boolean binders with a TYPICALLY default, and its value." #96 built the renderer but hand-feeds a demo `provenance` map; the real extraction is stubbed. → Fold that extraction into #96's productionization (cleanest: optional `typically?` field on viz `UBoolVar`, populated by the Haskell ladder builder); then v2 just reads it. Full detail + the backend-ranking alternative in QUESTION-ORDERING-SPEC.md §8.

## Next

- Once the 4 implementers push, run an **ultracode hardening workflow** (adversarial review) across all ready branches, apply fixes, open + PR each to `unstable`.
- Resolve L4-VERSIONING scope (see decision below).

## Infra loose ends

### ✅ RESOLVED 2026-07-09/10 — merge-queue cabal cache now WARM (Tier-1 warm-up shipped)

The "WON'T FIX" decision below was **reversed and fixed**. A `main`-scoped scheduled warm-up (`.github/workflows/cache-warmup.yml`, cron every 6h) builds `unstable`'s cabal deps and saves the store under an `mq-warmup-*` key; because the run's ref is `main` (the default branch), the save lands in the one scope merge_group runs can read. `pr-checks.yml` restores that key **only** on the merge_group path, so pull_request→main runs are unaffected. Shipped: **PR #107** (unstable) + **#108** (main copy) + **#109** (prettier fix / first validation).

- **Measured:** cold baseline (#102) Install-deps = **21m37s** → warm (#109, #110) = **1 second**. HIT on `mq-warmup-Linux-ghc-9.10.2-cabal-…`.
- **Reproduced independently 2026-07-10 on #110** (merge_group run 29102678896): same 1s Install-deps, HIT on `…plan-b4d34b6e…` — durable steady-state, not a one-off.
- **Remaining gap (Tier-1.5, deferred):** warm-up covers the cabal STORE only, not dist-newstyle → `Restore cached build artifacts` still MISSES on merge_group, Build step still ~6-7 min. Lower value / more churn (our own package sources change every PR). Tier-2 durable option = external S3 cabal-cache. Full mechanism in memory `mergequeue-cache-warmup-tier1`.
- Historical diagnosis (superseded, kept for provenance) below.

- **CI cache — PR runs WARM (8 min); merge QUEUE runs stay COLD (~35 min). DECISION 2026-07-07: WON'T FIX — live with it. [SUPERSEDED — see RESOLVED banner above]**
  Settled un-confounded by PR #52 (first PR into `unstable` after the base cache warmed), clean A/B on the same tree:
  **pull_request→unstable Haskell job = 8m03s** (inherited `refs/heads/unstable` `pr-checks-*-dist/cabal` base caches ✅);
  **merge_group `gh-readonly-queue/unstable/pr-52-*` Haskell job = 34m47s** (cold). ROOT CAUSE (proven from the run log):
  the merge_group run reported `Cache not found` for a dist/cabal key **byte-identical** to the one on `refs/heads/unstable`
  → pure **scope isolation**, not a key mismatch. GitHub scopes cache READS to {own ref, base, **default**}; a merge_group
  run's scope is {own `gh-readonly-queue/...` ref, default=`main`} and does NOT include the PR base `unstable`. That's why
  WASM (cached on `main`) stays warm in the queue but the Haskell base cache (on `unstable`) is invisible. So the ONLY
  ways to warm the queue are: (a) make `unstable` the default branch [REJECTED — `main` is an actively-developed,
  conservative line, not a release snapshot; it must stay default], or (b) put a cache on `main` that the queue can read —
  either main's own build (partial warmth ~20-25 min; `main` is 182 commits diverged so most modules still rebuild, deps
  warm) or a dedicated warmer workflow on `main` that builds `unstable` and saves the cache on `main` (near-full ~8-12 min,
  needs a new scheduled workflow + ref-scoped prune). **User chose to accept cold ~35-min queue runs** rather than add the
  machinery. If revisited: warmer-builds-unstable-saves-on-main is the near-full option; also ref-scope the pr-checks prune
  (`c.ref === context.ref`) first, else an unstable push deletes any `pr-checks-*` cache placed on `main`. Do NOT re-diagnose
  from scratch — the mechanism above is proven.

- **CI cache — FIX IN FLIGHT 2026-07-07 (PR #78 `fix/ci-cache-warming`, auto-merge armed) + one-time prune done.**
  Fix: gate both Haskell `Save cached …` steps on `github.event_name == 'push'` so PR/merge_group runs are pure
  cache CONSUMERS (restore base, never save → no per-PR churn); only base-branch pushes refresh the inheritable
  `refs/heads/unstable` cache. Added a push-only `Prune superseded Haskell caches` github-script step (needs job
  `permissions: actions: write`) that runs AFTER build+test and deletes older dist/cabal family entries (keeping
  THIS run's primary keys) so each family self-limits to one entry. Moved both Save steps after tests so a broken
  base build can't overwrite the last-good cache. One-time manual prune: deleted all 34 ephemeral-ref caches
  (`refs/pull/*` + `gh-readonly-queue/*`) via `gh api -X DELETE .../actions/caches/{id}` (zsh: iterate with
  `… | while read -r id`, NOT `for id in $ids` — zsh doesn't word-split) → repo cache **10 GB → 1.63 GB** (only the
  2 WASM base caches on `main` remain). Rollout: #78 is workflow-only so paths-filter skips heavy jobs → merges fast;
  first Haskell-touching push to unstable after it (e.g. #31's merge) warms the base cache; then #50/#58 restore it.
  NOTE confirmed: skipped required jobs report conclusion `skipped`, which the merge queue treats as PASS (that's why
  paths-filtered PRs merge). Original root-cause analysis below.
- **CI is too slow (~40 min/run) — ROOT CAUSE FOUND 2026-07-07: the Haskell `pr-checks` cache is cold on EVERY PR run.**
  Diagnosed against PR #31's live run + the repo cache API (`gh api repos/legalese/l4-ide/actions/caches`). Findings:
  - **No inheritable base-branch Haskell cache.** GitHub scopes cache _reads_ to {own ref, base branch, default branch}.
    A PR into `unstable` can only restore caches on `refs/heads/unstable` or `refs/heads/main`. There are **zero
    `pr-checks-*-dist-*` / `pr-checks-*-cabal-*` caches on those refs** — the only base-branch caches are the WASM job's
    (`ghc-wasm-9.10-Linux` 1.37 GB, `wasm-deps` 297 MB, both on `refs/heads/main`, which is why WASM stays warm). All 35
    Haskell `pr-checks` caches live on `refs/pull/N/merge` or `gh-readonly-queue/unstable/pr-N-*` refs — each run's PRIVATE
    scope, unreadable by other PRs. ⇒ a PR's `restore-keys` (`pr-checks-Linux-ghc-9.10.2-dist-` etc.) match nothing it may
    read ⇒ cold build: 2 min GHC setup + full deps (`cabal build all --only-dependencies` from empty store) + full
    `cabal build all`. (Live proof: #31's restore steps 9+10 finished in <1 s = nothing restored.)
  - **10 GB repo cache cap is saturated (10.07 GB / 38 entries) ⇒ LRU eviction churns out the base caches.** Every PR/queue
    run writes a fresh ~330 MB dist + ~150 MB cabal cache under a **unique-per-commit key** — the dist key is
    `…-dist-${hashFiles('**/*.hs','**/*.cabal')}` and the deps key `…-plan-${hashFiles('**/*.cabal','cabal.project')}`, so
    the PRIMARY key never repeats. `cache-hit` is therefore never `true` on a PR, so the `if: cache-hit != 'true'` Save
    steps re-write every run — dozens of single-use caches evict the rare push-to-`unstable` caches that PRs actually need.
  - GHC is pinned `9.10.2` (workflow line 141) so version drift is NOT the cause. Ruled out.
  - **Fix direction (do another time):** (1) warm a base-branch cache PRs can inherit — a `push: unstable` run (or a
    dedicated cache-warm workflow) that reliably SAVES dist+cabal on `refs/heads/unstable`; (2) stop the churn so it isn't
    evicted — drop `hashFiles('**/*.hs')` from the dist key (use a stable `pr-checks-${os}-ghc-${ghc}-dist` single entry, or
    save only on base/push runs and let PR runs restore-but-not-save); (3) optionally prune old caches / raise the base
    cache's access frequency. Files: `.github/workflows/pr-checks.yml` lines ~136–199 (Set up GHC + Restore/Save cache
    steps). (Surfaced during the 2026-07 unstable PR drain; diagnosed while PR #31 CI ran.)

## Log

- Staleness triage: 3/5 Tier-1 already resolved.
- Staleness audit PR #46 merged (9 archived, 18 banners).
- Tier-1 #3/#5 + Tier-2 ref-annotation/batch-processing implementers launched (background).
- 2026-07-07: logged CI-slowness loose end (~40 min/run, suspected cache failure) — see "Infra loose ends" above.
- 2026-07-09: merge-queue cabal cache RESOLVED — Tier-1 `main`-scoped warm-up shipped (#107/#108/#109). Install-deps 21m37s → 1s.
- 2026-07-10: #110 (question-ordering v2 / TYPICALLY priors) merged; its merge_group run independently reproduced the Tier-1 cache HIT (1s). Both lanes closed.
