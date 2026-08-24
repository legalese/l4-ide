# feat(blawx): the L4 → Blawx bridge — relational IR, emit, XML rendering, round-trip import, and the P4 showcase

**150 files, +45,848/−7, plus this slice's lines in four shared build files.** This PR is the
complete Blawx bridge arc: nine upstream PRs that took L4 from "no s(CASP) story" to a
two-way bridge against a real external reasoner, with a showcase and a recorded round trip.

## What this adds

- **A relational IR** (`L4.Relational.IR/Lower/Debug`) — the intermediate form that turns L4
  decision logic into predicate-style relations, built first because Blawx (a block-based
  front end over s(CASP)) consumes rules, not expressions.
- **The Blawx backend proper** (`L4.Blawx.IR/Lower/Emit/EmitXml/Xml/Blocks/Parse/Lift` —
  eight modules in `jl4-core`) — lowering, `.blawx` YAML + s(CASP) emission, Blockly XML
  rendering, and the parsing/lifting half that reads Blawx projects back.
- **A CLI verb**: `l4 blawx`, wired into `jl4/app/Main.hs` and its own
  `jl4/app/L4/Cli/Blawx.hs`.
- **Round-trip import (P5)**: Blawx's own bird-ontology example imported to L4 and re-emitted.
- **The P4 showcase**: `p4-design/` (21 files) plus examples under `jl4/examples/blawx/`
  with `expected/` goldens for every emission.
- **Tier-1 harness**: `etc/blawx-tier1-harness.py` runs the emitted projects against a live
  Blawx/s(CASP) instance.
- **Tests**: `RelationalSpec`, `BlawxAssumeSpec`, `BlawxImportImageSpec`, `BlawxLiftSpec`,
  `BlawxParseSpec` in `jl4-core-test`; `RelationalExport` in `jl4-test`; and this slice's
  block of black-box cases in `jl4/tests-cli/Main.hs`.
- **The spec**: `specs/todo/BLAWX-EXPORT-SPEC.md`, carrying the arc's 13 numbered rulings
  and the quirk register for upstream Blawx (4 quirks/bugs found; a fix for one is open as
  legalese/blawx#1, with three more fork-PR candidates recorded).

## The shared build files

`jl4/jl4.cabal`, `jl4-core/jl4-core.cabal`, `jl4/app/Main.hs` and `jl4/tests-cli/Main.hs`
are also touched by the docassemble slice. Each PR carries **only its own lines** of those
files, attributed mechanically by git blame; the two slices' versions provably sum to
`unstable`'s blob. This slice's share: the Blawx/Relational module registrations, the
`l4 blawx` command wiring, and the Blawx test cases.

## Evidence

- Built locally from this exact tree: `cabal build all` (GHC 9.10.3), then
  `jl4-core-test` and `l4-cli-test`. Results recorded in the PR conversation.
- Every line of this PR reached `unstable` through the sequential merge queue, and the
  push-triggered full-matrix run at the wave-2 cut tip `bf355e79` **completed green**
  (24 Aug, after this PR opened).

## Independence

Self-contained against the wave-2 base: needs nothing from any sibling wave-2 PR, and no
sibling needs it. The docassemble slice touches the same four build files but never the
same lines.

## Provenance

Upstream `unstable` PRs folded in, in merge order:
#261 (bridge spec + rulings), #270 (rulings R6–R9), #272 (relational IR, M1),
#273 (emit, P1), #276 (P2 evidence), #277 (Blockly XML rendering, P3),
#279 (import + bird round-trip, P5), #278 (P4 showcase, ASSUME widening),
#280 (docs + spec closure).
