# Measured dependencies between the aug2026 PRs

Derived mechanically by `depcheck.mjs`: for every Haskell module a theme ships, resolve its
imports against the modules the other themes ship, ignoring anything `main` already has.
Five edges exist. Everything not listed here has no compile-time dependency on a sibling.

    ladder-viz  <--  dmn-export  <--  bpmn-export  <--  service-cli
                          ^                                 |
                          +---------------------------------+
                     openfisca-export  <--------------------+

| edge | why |
| --- | --- |
| `dmn-export` needs `ladder-viz` | `L4.Dmn.Lower` imports `L4.Viz.GuardedRows`, the guarded-chain normaliser |
| `bpmn-export` needs `dmn-export` | `L4.Bpmn.Wiring` imports `L4.Dmn.IR`; `L4.Bpmn.IR`/`Lower` import `L4.Interchange.Fidelity`; the BPMN test imports the DMN test module. This is the "BPMN delegates decisions to DMN" mandate, not an accident of packaging. |
| `service-cli` needs `dmn-export`, `bpmn-export`, `openfisca-export` | `l4 export` is the CLI surface over all three back ends |

Suggested merge order: `ladder-viz` -> `dmn-export` -> `bpmn-export` / `openfisca-export` -> `service-cli`.
Every other PR may merge in any order.

`ci-build` should merge **last**: the workflow it ships references check scripts that arrive
with the feature PRs, so landing it early would redden `main` for checks whose subjects are
not there yet.

## A pre-existing golden gap on `main`, and what it means for merge order

`etc/check-corpus-goldens.mjs` (shipped by **ci-build**) fails on **plain `origin/main`**, today,
before any of this work: three fixtures carry no goldens —

    jl4/examples/not-ok/export-after-giveth.l4
    jl4/examples/not-ok/export-before-decide.l4
    jl4/examples/not-ok/export-between-given-giveth.l4

The twelve goldens that close that gap are in **lang-syntax-typecheck**, which is the only
slice that passes the check standalone. Every other slice merely inherits main's existing gap;
none of them introduce one.

So: **`ci-build` must merge after `lang-syntax-typecheck`.** Landing the checker first would
turn `main` red for a defect that predates all of these PRs.

## Two more edges, found by building and installing rather than by reading

- **`wizard-regcf` needs `ladder-viz`.** `ts-apps/regcf-wizard` depends on the workspace packages
  `@repo/ladder-core` and `@repo/ladder-svg`, and *both directories are new on unstable* — they do
  not exist on `main`. `npm ci` on the wizard slice alone fails with
  `404 Not Found - GET .../@repo%2fladder-core`. This is why the wizards are two PRs and not one:
  **`wizard-housing` needs nothing that is not already on `main`** (it uses `jl4-client-rpc`, which
  main has), so it ships a regenerated root lockfile and stands alone.

- **`cabal.project` is no longer a shared file.** It carried two unrelated one-line edits: dropping
  `./jl4-actus-analyzer` and adding `./jl4-proleg`. Each PR now makes its own edit, so neither can
  leave `cabal build all` pointing at a directory that is not there. (On `unstable` that exact
  mistake happened once already — PR #63 landed without its `cabal.project` edit and `f2f646fc`
  had to repair it the next day.)

## Note on the root lockfile

`package-lock.json` is touched by both **ci-build** (which adds `lint-staged`) and
**wizard-housing** (which adds a workspace). Whichever lands second needs a plain `npm install`
to reconcile. That is ordinary lockfile traffic, not a design problem.

## ci-build's own preconditions (both found by running the checks against plain `main`)

- The Haskell job's *"The sdist must carry the standard library"* step fails against `main` today:
  `data-files: libraries/*.l4` still sits **after** the flag stanzas, which is the exact defect the
  step detects. The reordering travels with **lang-imports-stdlib** (verified — that branch's
  `jl4-core.cabal` slice is precisely the `data-files` move).
- The corpus-goldens job fails against `main` today for the three `not-ok/export-*.l4` fixtures.
  Their goldens travel with **lang-syntax-typecheck**.
- `package-lock.json` names four workspace directories that only exist once **ladder-viz**,
  **wizard-housing** and **wizard-regcf** land.

So `ci-build` merges **after** lang-imports-stdlib, lang-syntax-typecheck, ladder-viz and both
wizards — which is the same conclusion as "merge it last", now with reasons.
