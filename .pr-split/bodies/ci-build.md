# ci: the gate layer — six new PR jobs, an artifact-based merge-queue warm start, and a prerelease binary track

**What this adds**

This is the continuous-integration and build-plumbing layer that the rest of the August 2026 work
runs on. `.github/workflows/pr-checks.yml` grows from five jobs to eleven: alongside the existing
TypeScript, Haskell, WASM and Nix checks it now runs a corpus-goldens guard, the `go` orchestrator's
self-tests, a BPMN soundness gate, a two-engine DMN gate (KIE + Camunda), and two MLIR parity jobs.
The workflow also learns two new triggers it did not have — `push` and `merge_group` — so the merge
queue can report against required checks, and a queued PR now starts from a warm Haskell build state
downloaded as a workflow artifact instead of recompiling the tree from nothing. A second, entirely
new workflow, `unstable-prerelease.yml`, builds standalone `l4` and `jl4-lsp` binaries for Linux,
macOS and Windows and publishes them as a GitHub prerelease, so a contributor can obtain a working
`l4` without installing GHC. On the local side a `pre-push` hook refuses a push that CI's
`format:check` would reject, and `pre-commit` switches from a whole-repo check to lint-staged.

**Why**

Four separate problems drove this, each measured rather than assumed.

*The merge queue was paying a cache tax nothing could see.* GitHub scopes cache **reads** to the
run's own ref plus the default branch (plus the base branch, for `pull_request` only). Our queue
targets `unstable`, which is **not** the default branch (`main` is), and a `merge_group` run's own
ref is an ephemeral `gh-readonly-queue/…` ref — so the caches saved by pushes to `unstable` were
structurally invisible to every queue entry. This is upstream issue **smucclaw/l4-ide#911**.

*A PR could ship a corpus without its goldens and stay green.* No paths filter matches a `.l4` under
`jl4/examples/`, so the Haskell job never ran on the PR that introduced the gap; `failFirstTime =
True` then fired on the first branch that built everything, which belonged to somebody else. A trap
whose victim is never its author will keep going off.

*`cabal install exe:l4` had been producing a binary with an empty embedded stdlib for months*
(upstream **smucclaw/l4-ide#165**), because `cabal build` and `cabal install` build from different
sources and only the latter goes through the sdist. Nothing in CI built along that axis, so nothing
could catch it.

*There was no way to obtain an `l4` binary without building one.* `etc/go/go.sh` never builds — it
requires `L4` to point at an already-built binary and refuses otherwise — and the only `l4` the repo
shipped was the copy bundled inside the VS Code extension, whose most recent build predated
`l4 export`. A contributor wanting to run the pipeline had to install GHC and Cabal and do a full
Haskell build; on a sandbox whose setup script is capped at five minutes that is impossible, while
downloading a tarball is not.

---

## What's in it

Ten files: two GitHub Actions workflows, two git hooks, one new Node checker, two Nix files, and the
npm root manifest/lockfile/turbo config.

### `.github/workflows/pr-checks.yml` — 316 lines on `main`, 1852 on `unstable`

**New jobs (six).** `Corpus Goldens Present`, `Go Orchestrator`, `BPMN Soundness`,
`DMN Engine Checks (KIE + Camunda)`, `jl4-mlir Parity Gate (pure unit)`, `jl4-mlir Full Parity
Harness`. The last is `continue-on-error: true` by design, with a comment saying to flip it once the
toolchain is proven stable.

**New triggers.** `push: [main, unstable]` and `merge_group`, in addition to `pull_request`.
Concurrency is keyed on `github.event.merge_group.head_sha || github.ref` so queue entries cannot
cancel each other, and `cancel-in-progress` is now conditional on the event being a `pull_request`.
The `changes` job checks out with full history on `merge_group` and `push`, because `dorny/paths-filter`
diffs via git on those events and only uses the API for `pull_request`.

**Paths filters.** Three new filters (`bpmn`, `dmn`, `go`) join `haskell`, `typescript`, `docs` and
`mlir`. Several entries exist specifically because a PR touching only those files previously ran
*zero* jobs: `**/*.mjs` (which `**/*.js` does not match), `etc/**`, `.claude/skills/**`, and
`specs/**` under `docs`. `.github/workflows/pr-checks.yml` itself is now listed in five filters, so a
workflow-only PR re-runs the jobs it redefines — the alternative being that a change to the cache
steps of four jobs merges without any of those four jobs having run.

**Merge-queue warm start (the artifact route).** The push-to-`unstable` run of the Haskell job tars
its cabal store and `dist-newstyle` and uploads them as an artifact named `mq-warmup-haskell`
(retention 7 days, plain tar since `upload-artifact` compresses anyway). Each queue entry uses
`actions/github-script` to walk back up to 15 successful pushes for the newest non-expired copy,
downloads it and unpacks it before configure. Artifacts, unlike caches, are **not ref-scoped**, which
is the whole reason this route exists. Both `actions/cache/restore` steps are gated **off**
`merge_group` outright — not merely expected to miss — because a push to `main` writes the same
`pr-checks-*` keys into default-branch scope, which a queue entry *can* read, and restoring main's
stale store over a fresh warm start risks a mixed `package.db`. Every producer and consumer step is
`continue-on-error`: a warming failure costs one cold entry, never a red check.

**Cache hygiene.** Saves are gated to `push`; a `Prune superseded Haskell caches` step (needing
`actions: write` on the job) deletes stale entries before saving the fresh base cache, to stay under
GitHub's 10 GB cap; `setup-node`'s implicit `package-manager-cache` is switched off on `merge_group`
in every job that uses it, since it never hit there and only consumed budget. In the TypeScript job
*both* switches have to be turned off — `cache:` and `package-manager-cache:` — because leaving
`cache` empty falls through to a second code path in `setup-node@v5` where `package-manager-cache`
defaults to true and auto-detects npm. The first cut of that change disabled only one; the comment in
the file records that this was caught by the resolved inputs GitHub echoes into the log
(`package-manager-cache: true`), not by reading the action.

**The sdist stdlib guard.** A step in the Haskell job runs `cabal check` in `jl4-core`, fails on a
`parser-warning`, then greps `cabal sdist --list-only` for `libraries/prelude.l4`. This is the check
that catches a package-level field silently disabled by a section inserted above it.

**Engine gates.** The BPMN job runs `etc/check-bpmn-kie.sh` (the jBPM second opinion) with the Maven
repo cached and keyed on `etc/**/pom.xml`, JDK pinned to 17, and deliberately **no** `--allow-skip`,
so a missing toolchain in CI is a failure rather than a silent skip. The DMN job runs the KIE and
Camunda harnesses directly with `KIE_CHECK_REQUIRED` / `CAMUNDA_CHECK_REQUIRED` set, using two JDKs
(17 and 21) in two directories because the FEEL engine jars collide on one classpath.

### `.github/workflows/unstable-prerelease.yml` — new, 785 lines

`workflow_dispatch` only, `dry_run: true` by default. A `resolve` job refuses to build `main`; a
matrix `build` job produces `l4` and `jl4-lsp` for three platforms, smoke-tests the staged binaries,
and archives them; a `publish` job verifies the archive set is complete, generates `SHA256SUMS`,
composes a release body, tags `unstable-<YYYYMMDD>-<short-sha>` and publishes with `prerelease: true`
and `make_latest: "false"`. It **restores and never saves** caches, so it cannot evict anything from
the repo's cache budget. The file's header documents, in the present tense with dates, exactly how it
stays disjoint from `main`'s release track (`main-tag.yml`): different trigger, tag namespace,
concurrency group, and `contents: write` scoped to the `publish` job alone.

### `etc/check-corpus-goldens.mjs` — new, 112 lines

Walks the six globs whose results reach `jl4/tests/Main.hs`'s `tests` helper (`ok/**`, `legal/**`,
`jl4-core/libraries/*`, `not-ok/tc/**`, `not-ok/nlg/**`, `not-ok/export-*`) and asserts all four
goldens exist beside each file. No build, no GHC, no paths filter — the CI job that runs it carries
no `needs:` and no `if:`, because running where the filters cannot see is the entire point. It exits
**2** if a root has vanished or matches nothing, on the principle that a glob matching nothing passes
every check it makes.

### Git hooks and npm root

- `.husky/pre-push` (new, 94 lines): checks the pushed range with the repo-local
  `node_modules/.bin/prettier`, names the offending files and prints the remedy. It never writes and
  never stages. Missing `node_modules` warns and passes rather than blocking. `--diff-filter=d` so a
  deletion is not blocked by a check on the deleted file; base falls back merge-base `origin/unstable`
  → `origin/main` → the pushed commit's parent.
- `.husky/pre-commit`: whole-repo `npm ci && npm run format:check` → `npx lint-staged`.
- `package.json`: adds `lint-staged` and its `"*": "prettier --write --ignore-unknown"` config; the
  `vite` override moves from `^6.0.7` to a pinned `6.4.2`. `package-lock.json` is regenerated to
  match.
- `turbo.json`: `BASE_PATH` added to the `build` task's `env` list.
- `nix/default.nix` and `nix/configuration.nix`: register the `regcf-wizard` package and import its
  module. **Imported but not enabled** — the module defaults to off, so importing it changes nothing
  that is served.

---

## Evidence

Quoted from the source PRs.

**Merge-queue cache scoping (#209).** Across 10 `merge_group` runs on 2026-08-01/02,
`Install dependencies` printed `Up to date` in **0.4 s**, every time — #107's `mq-warmup-` restore
key worked as designed for the dependency store. `dist-newstyle` was never decoupled. Three events
within 31 minutes, all asking for the identical key
`pr-checks-Linux-ghc-9.10.2-dist-14bfce8b…`:

| event | run | cache step | `cabal build all` |
|---|---|---|---|
| merge_group (pr-197) | 30758870963 | `Cache not found for input keys: …` | **514.9 s** |
| pull_request (#206) | 30758436670 | `Cache restored from key: …` | 16.1 s |
| push (unstable) | 30758870728 | `Cache restored from key: …` | 19.1 s |

Aggregate: 12 `merge_group` runs executed the Haskell job on Aug 1–2, at 13m47–19m12 wall clock
against 9m39–12m55 for `pull_request` — **~98 min of runner time recompiling what was sitting in a
cache the run was not allowed to read.** The same PR measured the cache store at **10.65 GB against a
10 GB cap**, with **5.58 GB in 53 `gh-readonly-queue` entries, 44 never read once**. It also recorded
that `jl4-mlir Full Parity Harness` never hits either Haskell cache on any event — 1583 s cold on
`pull_request`, 1688 s on `merge_group` — because `actions/cache` versions an entry by paths *and
compression method*, and the Haskell job's `ubuntu:24.04` container has no zstd while the bare host
does. That one is documented in place and deliberately **not** fixed, because installing zstd
re-versions every `pr-checks-*` entry at once.

**The npm cache on `merge_group` (#209).** Measured `npm cache is not found` on merge_group run
30760823299, after which the run wrote 111 MB into its own doomed ref. 28 such `node-cache-*` entries
were live on 2026-08-02, totalling 1.89 GB, **20 of them never read once**.

**#209 and #227 are explicit about what is measured and what is predicted.** The merge_group half of
each fix could only be observed after landing, since a queue entry requires a human to queue the PR;
both PRs label that half a prediction and name the log line that would confirm it. #227's own first
draft was corrected by adversarial review before push: it had left the cache restores unconditional
on `merge_group` with a comment claiming they "always miss by construction", which is false whenever
the most recent Haskell-building push was to `main`.

**Corpus goldens (#213).** Measured in both directions:

```
$ node etc/check-corpus-goldens.mjs
check-corpus-goldens: 352 corpus file(s), each with all 4 goldens present     # exit 0

$ mv jl4/examples/legal/charities-cleanroom/tests /tmp/hold && node etc/check-corpus-goldens.mjs
check-corpus-goldens: 1 corpus file(s) have no goldens, ...                   # exit 1
```

The two incidents it exists for: the BNA 1981 corpus landed in #195 and was repaired by #202; the
Jersey charities cleanroom landed in #201, was repaired by #212, and **knocked #207 out of the merge
queue**. Both times the offending PR's own CI was green. Runs in about a second.

**Embedded stdlib / sdist guard (#167).** `cabal install exe:l4` had been producing an `l4` with an
empty embedded stdlib since `61653b0e` (19 Jan); all five store-built `l4` binaries then present in
`~/.cabal/store` — oldest 9 June — had no embedded stdlib. Moving `data-files` above the flag stanzas
takes jl4-core's sdist from **0 → 22** `.l4` files. Verified by a real `cabal install` into a temp
dir with `JL4_LIBRARY_PATH` unset: `exit 0` where the previous binary exited 1, with `prelude`,
`math`, `daydate` and `datetime` all RESOLVED. Suite at the time: 1826 + 311 + 269 + 96 examples, 0
failures.

**Pre-push hook (#221).** "Four PRs failed CI today on nothing but prettier." The hook was fed
simulated pre-push stdin on all five paths — clean range, misformatted file in range, new branch
(zero remote sha), branch deletion (zero local sha), and no `node_modules` — each behaving as
specified.

**jBPM gate (#163).** The check was held back purely on the ~44 MB of jars from Maven Central, which
the cache reduces to a one-off per pom change; versions are hard-pinned (`jbpm.version 7.74.1.Final`,
`maven-dependency-plugin:3.6.1`) which is what makes the key stable. The two fixture sets have
different contracts: `sound/` is gated strictly at exit 0, `expected/` tolerates exit 1 (2/3/4 still
fail) because it reports one known non-defect finding on `offering.bpmn`. That PR also recorded a
companion repo-settings change: **"BPMN Soundness" was made a required status check** on the
`unstable` ruleset (18543507).

**Prerelease cache borrow (#225).** Dry run **31302358588** (2026-08-09) hit the first restore-key on
all three platforms — a prefix match, since `unstable`'s `plan.json` hashes differently from main's —
and the build step took **396 s / 379 s / 398 s** (linux/darwin/win32) against the **1428 s / 1399 s /
1279 s** cold baseline. The ruling recorded: the workflow stays restore-only, and warmth is
opportunistic — borrowing works *iff* `main-tag.yml` ran within the last 7 days.

**Known gaps, stated in the sources rather than hidden.** #160 verified via
`gh api repos/legalese/l4-ide/rulesets/18543507` that the `dmn-engines` job is **not** a required
status check (the ruleset then listed only *TypeScript Checks*, *Haskell Build & Test*, *WASM Build &
Test*, *Nix Flake Check*), so its deliberate `exit 1` does not block a merge until that context is
added. #163 noted that tolerating exit 1 on `expected/` loses the new-finding signal until the
harness grows a baseline — which a later commit on this branch (`572972f4`) supplies.

---

## Independence

**This PR is not standalone, and it should not be reviewed as though it were.** It is the gate layer;
most of what it gates lives elsewhere.

*Hard dependency 1 — `npm ci` fails without it.* `package-lock.json` here is the regenerated
whole-workspace lock. It contains entries resolving to `ts-apps/housing-wizard`,
`ts-apps/regcf-wizard`, `ts-shared/ladder-core` and `ts-shared/ladder-svg`. The root `workspaces`
glob is `ts-apps/*` + `ts-shared/*`, so a lockfile naming workspace directories that are not on disk
will not install. Those four directories belong to **wizards** (the two apps) and **ladder-viz** (the
two shared packages). Either they land with or before this PR, or the lockfile has to be regenerated
against the reduced tree.

*Hard dependency 2 — this PR turns CI red without it.* The Haskell job's
`The sdist must carry the standard library` step fails on `main` as it stands: `main`'s
`jl4-core/jl4-core.cabal` still has `data-files: libraries/*.l4` at line 17, **after** the `safe-mode`
and `serialise-support` flag stanzas, which is exactly the defect the step detects. The reordering,
together with the TH `fail` and the diagnostic change, is #167's other half and travels with
`jl4-core/src/L4/API/EmbeddedLibraries.hs` in the **service-cli** theme. Worth flagging to whoever is
assembling the split: `jl4-core/jl4-core.cabal` appears in *no* theme's `.files` manifest, so it may
need to be added to service-cli explicitly.

*Jobs that skip harmlessly, but do nothing useful, without their sibling.* Each of these is gated
behind a paths filter, so if the sibling's files are absent the filter never fires and the job never
runs — no red check, just no coverage:

- `Corpus Goldens Present` runs unconditionally and is genuinely standalone (pure Node, no build),
  but its 352-file count only holds once the new corpora land — **corpus-legal-new**, **corpus-regcf**.
- `Go Orchestrator` needs `etc/go/**` and `.claude/skills/**` — **go-pipeline**, **agent-tooling**.
- `BPMN Soundness` needs `etc/check-bpmn-*`, `etc/kie/**`, `jl4/examples/bpmn/**` — **bpmn-export**.
- `DMN Engine Checks` needs `etc/kie-dmn-check/**`, `etc/camunda-dmn-check/**`,
  `jl4/examples/dmn/**` — **dmn-export**.
- The two `jl4-mlir` jobs need `jl4-mlir/scripts/parity-gate*.mjs` — **mlir**.
- `nix/default.nix` and `nix/configuration.nix` reference `./regcf-wizard/package.nix` and
  `./regcf-wizard/configuration.nix`, which are in **wizards**. `Nix Flake Check` will fail if those
  two files are not present, so this pairing is a hard one in the other direction — either both land
  or neither of the two nix lines does.

*Genuinely self-contained within this PR.* `unstable-prerelease.yml` (it builds `l4` and `jl4-lsp`
from whatever the tree contains), the two husky hooks, `turbo.json`'s `BASE_PATH` entry, and the
`lint-staged` / `vite` changes to `package.json`. Note that `turbo.json`'s `BASE_PATH` exists to serve
the wizard builds in **wizards**; it is inert but harmless without them.

*Nothing here is required by a sibling in order to compile or test locally.* Dropping this PR does not
break anyone's build; it removes the machinery that would have caught them breaking it.

---

## Risk if rejected

The merge queue goes back to recompiling the whole Haskell tree on every entry — the ~98 min of
runner time #209 measured over two days — and upstream smucclaw/l4-ide#911 stays open with no route
to closing it. More seriously, every gate the other twenty-four PRs rely on disappears: the corpus
that ships without goldens goes green again and reddens somebody else's branch, the DMN and BPMN
exporters land unchecked by any engine, the `go` orchestrator's skill is free to drift from its
driver, and `cabal install` quietly returns to producing an `l4` with no standard library.

---

## Provenance

Unstable PRs folded into this one (the CI/build portion of each; several span other themes):

- **#107** `ci: warm merge-queue Haskell cache (Tier 1 — main-scoped scheduled job)` — the original
  diagnosis of GitHub's cache read-scoping; superseded in mechanism by #227, retained in reasoning.
- **#116**, **#157**, **#162**, **#175**, **#176**, **#177**, **#178**, **#188**, **#189**, **#190**,
  **#193**, **#194**, **#196**, **#198**, **#204**, **#206**, **#207**, **#224** — incidental
  workflow, filter and lockfile edits carried alongside each feature branch.
- **#160** `fix(dmn): two engine flavors (R7)` — the `dmn-engines` job and its skip contract.
- **#163** `ci(bpmn): run the jBPM second opinion, cached, and gate the toolchain`. A follow-up
  commit on the same file, `572972f4 ci(bpmn): give the jBPM check a baseline, so a new finding
  cannot land green`, closes the gap #163 named.
- **#167** `fix(build): restore the embedded stdlib, and make its absence a build error` — the sdist
  CI step (its cabal/TH half is in **service-cli**).
- **#200** `wizard-deploy-ready` — the `nix/` registration lines.
- **#224** `The explainer stage, a BPMN renderer, the grouping tutorial, and the de novo Reg CF run`
  — a 151-file omnibus; what this PR takes from it is the `go` job's later steps and the arrival of
  `unstable-prerelease.yml` on `unstable`'s first-parent line (commits `a8b4eef4` and `4e6a439a`).
  Per #225's body, the same file reached `main` separately as PR **#218**, whose merge commit
  `a60cae2a` is no longer an ancestor of `main` after a history rewrite — so `main` does not
  currently carry it and this PR is the route by which it returns.
- **#209** `ci: let merge_group read dist-newstyle, and stop it writing caches nothing can read`.
- **#213** `ci: fail the PR that ships a corpus without goldens, not the next one`.
- **#221** `ci: pre-push hook that refuses what format:check would reject`.
- **#225** `ci(prerelease): cache borrow works inside a 7-day main-tag shadow — re-measure and rule`.
- **#227** `ci(mq): warm the merge queue via artifacts — no file on main required`.
