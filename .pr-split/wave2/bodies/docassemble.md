# feat(docassemble): the L4 → docassemble bridge — generated interviews, fidelity reports, and the measured M3 decline

**74 files, +16,131/−6, plus this slice's lines in four shared build files.** This PR is the
complete docassemble bridge arc: five upstream PRs that compile the decision-rule subset of
an L4 module to a runnable [docassemble](https://docassemble.org/) interview (YAML), with a
fidelity report saying exactly what did and did not survive the translation.

## What this adds

- **The backend** (`L4.Docassemble.IR/Lower/Emit` in `jl4-core`): lowering L4 decision
  logic to docassemble's question/logic model, then emitting interview YAML.
- **A CLI verb**: `l4 docassemble`, wired into `jl4/app/Main.hs` with its own
  `jl4/app/L4/Cli/Docassemble.hs`.
- **M2 and M4 feature waves**: gathered lists, payload patterns, paired `MAYBE`, date
  handling — each with `not-ok/` counterexamples that must keep failing.
- **The M3 gate, measured and DECLINED**: `m3-measure`, its own executable in `jl4/jl4.cabal`
  (an experiment over a corpus, deliberately not a mode on `l4`), measured whether
  information-gain question ordering beats declaration order. It does not, enough to matter;
  the decline and the numbers are recorded in `specs/todo/DOCASSEMBLE-EXPORT-SPEC.md`.
- **Examples and goldens**: `jl4/examples/docassemble/` with `expected/*.yml` for every
  example, plus `roundtrip_check.py`.
- **The spec**: `specs/todo/DOCASSEMBLE-EXPORT-SPEC.md` — note its date-idiom section
  overturns the original §10 design, recorded in place.

Two `not-ok/` fixtures (`maybe-number.l4`, `just-payload-pattern.l4`) were added mid-arc and
deleted when M4 made them legal; they net to zero and appear in no wave-2 slice.

## The shared build files

`jl4/jl4.cabal`, `jl4-core/jl4-core.cabal`, `jl4/app/Main.hs` and `jl4/tests-cli/Main.hs`
are also touched by the blawx slice. Each PR carries **only its own lines**, attributed by
git blame, with a proof the two versions sum to `unstable`'s blob. This slice's share: the
Docassemble module registrations, the `m3-measure` executable stanza, the `jl4-core`
test-dependency line, the `l4 docassemble` command wiring, and the docassemble block of
`tests-cli` cases (including the two one-line modifications: `isPrefixOf` in the import list,
`daCitationsSource` in the fixture list).

## Evidence

- Built locally from this exact tree: `cabal build all` (GHC 9.10.3), then
  `jl4-core-test` and `l4-cli-test`. Results recorded in the PR conversation.
- Every line of this PR reached `unstable` through the sequential merge queue, and the
  push-triggered full-matrix run at `bf355e79` **completed green** (24 Aug, after this
  PR opened).

## Independence

Self-contained against the wave-2 base: needs nothing from any sibling wave-2 PR, and no
sibling needs it. The blawx slice touches the same four build files but never the same lines.

## Provenance

Upstream `unstable` PRs folded in, in merge order:
#264 (bridge spec, M1), #265 (backend + CLI verb), #267 (M2), #268 (M4 — gathered lists,
payloads, paired MAYBE, dates), #269 (M3 measured and DECLINED, `m3-measure`).
