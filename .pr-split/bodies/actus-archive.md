# chore(actus): remove jl4-actus-analyzer; preserved at branch archive/actus-analyzer

**What this adds.** This is a subtraction, not an addition: it deletes the whole
`jl4-actus-analyzer/` package — a standalone static analyzer that read FIBO/ACTUS RDF ontologies
and classified an L4 contract encoding by ACTUS contract type (FXOUT, SWAPS, OPTNS, PAM, FUTUR,
MasterAgreement) and by FIBO ontology class, emitting Markdown, JSON or RDF/Turtle. After this
change the tree no longer builds the `jl4-actus` executable and no longer carries its library,
its ontology cache, or its six hspec suites. Nothing else in the repo loses a capability: the
package is a leaf, so what the rest of the tree can do is unchanged, and the build has one fewer
target to resolve — along with `rdf4h`, which after this change is referenced nowhere else in the
tree.

**Why.** The analyzer was written for a demo that is no longer active. Its commit message and PR
both make the case on weight: ~6.2k LOC that nothing `build-depends` on, that is not wired into
nix, into CI, or into any `hie.yaml`, and that no non-ACTUS `.l4` file reaches. Carrying it means
every contributor pays its dependency-resolution and compile cost for code no one runs. Rather
than let it rot in place, it was pushed to a named archive ref so it can be revived if and when
there is a plug-in architecture to host it as an optional extension. The upstream commits do not
cite a `smucclaw/l4-ide` issue number for this work; the only issue-shaped reference in the
history is to the fork-side PR (`legalese/l4-ide#63`) and its follow-up.

## What's in it

**The package deletion** — 27 files, 6,669 lines, all under `jl4-actus-analyzer/`:

- **16 library modules** under `src/L4/ACTUS/`:
  - `Analyzer.hs` — the top-level `analyzeFile` entry point and config
  - `FeatureExtractor.hs` — the largest module (622 lines); pulls domain indicators, deontic
    patterns, state transitions and type patterns out of the L4 AST
  - `Ontology/{Types,Loader,Cache,Query}.hs` — RDF loading via `rdf4h` plus a binary on-disk cache
  - `Matching/{Rules,Scorer,ACTUS}.hs` — the weighted pattern rules, confidence scoring, and the
    ACTUS→FIBO class table
  - `Qualia/{ObligationGraph,Essence,Archetypes,Hybrid}.hs` — the later "qualia" classifier layer
    that consumed `L4.StateGraph` from jl4-core
  - `Report/{JSON,RDF,Markdown}.hs` — the three output formats
- **1 executable**, `app/Main.hs` — the `jl4-actus` CLI (`--json`, `--rdf`, `--fibo`, `--no-cache`,
  `--rebuild-cache`, `--min-confidence`)
- **6 hspec suites** under `test/` (`ArchetypesSpec`, `EssenceSpec`, `FeatureExtractorSpec`,
  `HybridSpec`, `MatchingSpec`, `ObligationGraphSpec`), plus the one-line `test/Spec.hs`
  `hspec-discover` shim — note the shim is not in this theme's file manifest but must be deleted
  with the rest, or the directory is left with an orphan
- **package metadata**: `jl4-actus-analyzer.cabal`, `LICENSE` (MIT), and the package's own 363-line
  `README.md`

**Deliberately kept — this PR does not touch any of it.** The ACTUS *language* work is a separate
thing from the analyzer and stays:

- `jl4-core/libraries/actus{,-core,-daycount,-events,-schedule,-state,-terms}.l4` and their goldens
- `jl4/examples/ok/actus-library-test.l4`
- `doc/reference/libraries/actus.md`
- the ACTUS/QUALIA specs under `specs/`
- `holdings.l4`, an independent cap-table library that is only "inspired by ACTUS"

**Recoverability.** The package is preserved on `origin` at branch **`archive/actus-analyzer`** and
tag **`archive/actus-analyzer-v0.1.0`**, both pinned at pre-removal commit `fbc90947`. Both refs
are present on the remote today.

## Evidence

Quoted from PR `legalese/l4-ide#63`:

> `cabal build all --dry-run` resolves all eight remaining packages cleanly after removal.

and its safety argument, verbatim:

> `jl4-actus-analyzer` is a **leaf package**:
>
> - nothing `build-depends` on it
> - not wired into nix, CI, or any `hie.yaml`
> - no non-ACTUS `.l4` file imports the `actus-*.l4` libraries

Size, read off `git diff --stat origin/main...origin/unstable -- jl4-actus-analyzer/`: 27 files
changed, 6,669 deletions. The PR itself reports 17 additions / 6,675 deletions over 30 files, but
that count spans commits belonging to other themes that happened to ride the same branch (a webview
sidebar fix and a tutorial URL edit) — only the 27-file, 6,669-line figure is this theme's.

No performance, coverage or agreement numbers were claimed, because none apply to a deletion.

## Independence

Not standalone. This PR deletes a directory that three files outside its manifest still point at,
and those three files belong to sibling themes:

- **`cabal.project`** still lists `./jl4-actus-analyzer` under `packages:`. That file is owned by
  the **proleg** theme (which adds `./jl4-proleg` to the same list). If this PR lands without that
  line being removed, `cabal build all` fails immediately with *"package location does not exist"*.
  This is not speculation: it is exactly what happened on `unstable`. PR #63 merged with its
  `cabal.project` edit left uncommitted, and commit `f2f646fc` (`fix(#63): remove dangling
  jl4-actus-analyzer refs from cabal.project/README/AGENTS`) had to repair it the next day.
  **The safest resolution is for this PR to carry the one-line `cabal.project` deletion itself**;
  failing that, it must not merge before proleg.
- **`README.md`** and **`AGENTS.md`** each carry a package-table row for `jl4-actus-analyzer`. Both
  files are owned by the **agent-tooling** theme. A stale row is cosmetic, not a build break, but
  it makes the tables lie until that sibling lands.
- **`specs/todo/QUALIA-BASED-CONTRACT-CLASSIFICATION-SPEC.md`** is the spec that the archived
  `Qualia/*.hs` modules implement. On `unstable` it gained an archive note pointing at the branch
  and tag, and was later moved to `specs/done/`. Those edits are owned by the **specs** theme. Per
  §4 of `CLAUDE.md` ("a decision is recorded in its owning document in the same PR"), that pointer
  is what stops a later reader from acting on a spec whose implementation has silently vanished —
  so specs should land with or shortly after this one.

It needs nothing from any other theme in the *other* direction: no sibling's code, goldens, or CI
config depends on the deleted package. It also does not conflict with **lang-imports-stdlib**,
which touches `jl4-core/libraries/actus-schedule.l4` — a different, retained artifact.

## Risk if rejected

Dropping this leaves ~6.7k lines of unbuilt, untested demo code in `main`, with `rdf4h` — a
dependency nothing else in the tree uses — still on the critical path of `cabal build all`, and
leaves `main` and `unstable` diverging on a whole package directory, which will keep producing
conflicts in
`cabal.project`, `README.md` and `AGENTS.md` for as long as the divergence lasts. Nothing breaks
functionally; the cost is carrying weight and merge friction indefinitely.

## Provenance

- **legalese/l4-ide#63** — *chore: remove jl4-actus-analyzer from main (archived)*, merged
  2026-07-06 into `unstable`. Substantive commits taken from it here:
  - `62d0fd8b` — `chore: remove jl4-actus-analyzer package from main`
  - `9c474726` — `docs: add archive pointer to Qualia classification spec` (this hunk belongs to
    the **specs** theme, listed for completeness)
- Follow-up on `unstable`, not part of PR #63: `f2f646fc` — `fix(#63): remove dangling
  jl4-actus-analyzer refs from cabal.project/README/AGENTS`. Its `cabal.project` hunk is the one
  called out under Independence above.

Preserved refs on `origin`: branch `archive/actus-analyzer`, tag `archive/actus-analyzer-v0.1.0`,
both at `fbc90947`.
