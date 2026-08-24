# fix: four self-contained repairs — stdlib NOT-precedence, jl4-service deployment IDs, a spec status, an emacs mode

**11 files, +159/−25.** Four small, unrelated, individually complete repairs that arrived
inside larger upstream PRs; they are grouped here so each larger wave-2 PR stays on its own
subject.

## 1. The stdlib NOT-precedence fix (5 files, from #274)

`jl4-core/libraries/excel-date.l4` wrote `NOT a AND NOT b` expecting `(NOT a) AND (NOT b)`;
precedence made it something else, so `isWorkday` was wrong. Found while encoding the
sg-succession corpus (date-heavy), fixed with explicit parentheses at both sites.

Because the fix changes real evaluation results, its evidence travels with it:

- `jl4-core/libraries/tests/excel-date.ep.golden` — the exactprint golden for the new text;
- `jl4/examples/ok/excel-date/tests/workdays.golden` and
  `jl4/examples/ok/tests/excel-date-tests.golden` — the re-blessed evaluation goldens;
- `jl4/examples/dmn/expected/regcf-corpus.engine-baseline.txt` — the DMN engine baseline
  downstream of the same change.

Splitting fix from goldens would make two red PRs; together they are one green unit.
The guard against the bug class recurring (`etc/check-not-precedence.mjs`) rides in the
pipeline sibling with the rest of the CI wiring.

## 2. jl4-service deployment-ID validation (4 files, from #274)

`ControlPlane.hs` refactors deployment-ID validation into exported, testable rules
(`deploymentIdError`, `maxDeploymentIdLength`), with a new `DeploymentIdSpec` test suite
entry in `jl4-service.cabal` and a README note.

## 3. TYPICALLY-DEFAULTS-SPEC status truth-repair (1 file, #259)

The spec's status header had drifted from the tree; #259 re-audits it in place. Pure
documentation truth-repair, the anti-drift discipline this repo's CLAUDE.md mandates.

## 4. Emacs: stop Prelude reindenting yanked L4 (1 file, #282)

`etc/l4-mode.el` (+15): L4 is layout-sensitive; Prelude's yank-advice reindentation
corrupts pasted code. The mode now opts out.

## Evidence

- Each repair is self-consistent within this slice (fix + its own goldens travel together).
- Every file here reached `unstable` through the sequential merge queue (#282 cleared it
  minutes before the wave-2 cut), and the push-triggered full-matrix run at `bf355e79`
  **completed green** (24 Aug, after this PR opened).

## Independence

Nothing in wave 2 depends on this PR *except* an ordering note: the sg-succession corpus
goldens were cut against the fixed stdlib, so **this PR lands before sg-succession** (or
simultaneously via the `unstable → main` vehicle, which is how they actually land).

## Provenance

Upstream `unstable` PRs folded in: #274 (stdlib + service fixes only), #259, #282.
