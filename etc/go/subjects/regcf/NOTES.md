# regcf — subject idiosyncrasies

Free prose about **this corpus**, for humans and for the skill. **No script reads this file.**
Machine-readable subject facts live in `subject.json`; the CLI-surface pin in `pins.json`; the
measured negative controls in `known-defects.json`. When a fact below stops being true, fix it
here in the same change that moved it — a stale idiosyncrasy note misleads the next encoder.

## The corpus pair

- `regcf.l4` is the encoding proper and **carries no `@export` by design** — it is inert-style,
  reviewable section by section against 17 CFR Part 227.
- `regcf-wizard.l4` is the companion module that carries the `@export` surface. The MCP leg
  deploys the pair as one zip; a deployment that reports zero corpus tools usually means the
  wizard module did not deploy (measured 2026-08-02: the deployment reports 6 compiled
  functions, matched by 6 non-generic tools).
- The wizard's `render --format plan` output has **three measured plan defects** (no `asks`, no
  `inputs`, no question text), recorded as negative controls in `known-defects.json` — it is a
  disposition/reachability plan, not the interview query plan.

## House-rule tolerances

- **Thirteen `ELSE IF` sites** stand in the pair against P3's BRANCH-over-`ELSE IF` house rule
  (nine until 2026-08-09, when the 501(a)(4) decomposition added four wizard sites;
  measured with p3-check's own regex: `regcf.l4` ×2, `regcf-wizard.l4` ×11). They are
  tolerated, not endorsed: `p3-check` reports them as a finding and the leg rides
  DEGRADED. Do not add more; converting the thirteen is open corpus work.
- **`checks.min_dated_arms` is 2, and why.** `regcf.l4` has 5 `RULES EFFECTIVE DATE` sites, of
  which exactly 2 are _dated arms_ (compare against a `Date` literal on the same line — the
  COVID-window bounds at lines 475–476); the other 3 are comment prose ×2 and one parameterised
  `AT LEAST amendment`. `regcf-wizard.l4` has 1, a comment. The floor stops the temporal-closure
  check passing vacuously over an empty matched set (the matcher is single-physical-line; a
  reflow makes an arm invisible to it, measured 2026-08-02). Raise the floor when the corpus
  gains dated arms; never lower it to make a run pass. Negative control: deleting the `@ref`
  near `regcf.l4:472` makes the check report both arms.
- **`checks.min_assertions` is 20.** The pair carries well over that many `#ASSERT` directives;
  the floor exists because `results[]` satisfies "no failed assertion" vacuously when empty.

## De novo floors (`denovo.checks`, measured 2026-08-09)

- **`denovo.checks.min_assertions` is 39**, and 39 is the `assertions_total` sum out of
  `l4 run --json` results[] over `regcf-denovo.l4` — the figure `p6-tests` actually compares
  against. `grep -c '#ASSERT'` says 40, and the discrepancy is one comment
  (`regcf-denovo.l4:3590`, prose discussing why a DEONTIC value cannot be EQUALS-compared in an
  `#ASSERT`). Pin floors to the executed count, not the string count.
- **`denovo.checks.min_dated_arms` is 0, and 0 is the measured population, not a dodge.**
  `regcf-denovo.l4` has exactly one non-comment `RULES EFFECTIVE DATE` site (line 220), the body
  of a helper abstraction (`` `the rules in force include` change ``) that compares a
  _parameter_, so p3-check's matcher — which requires a `Date <digit>` literal on the same
  physical line — matches zero arms. The module IS temporally parameterised: the DMN exporter's
  `[D-RULEDATE]` advisory counts 8 decisions reading the rule date, all through the helper over
  `YMD`-shaped constants (`YMD 2022 9 20`, `YMD 2023 3 1`). Widening the matcher to see the
  abstraction would change the g1 count too and is not this floor's business. With a 0 floor,
  p3-check reports the temporal-closure sub-check **NOT CHECKED** for this module set rather
  than printing a vacuous "all 0 dated arm(s) carry an @ref".

## Temporal shape

- **The 2017-04-12 inflation-adjustment cliff is the canonical temporal boundary case.** Release
  33-10332 (82 FR 17545, instrs. 5–6) adjusted seven dollar constants effective 2017-04-12;
  every dated fixture and the DMN cases file exercise both sides of it. A further adjustment
  landed 2022-09-20.
- **The COVID-19 temporary rules (Rule 201(z)/(bb), 2020-05-04 through 2022-08-28) are
  deliberately NOT modelled** — a curated refusal in the corpus: inside that window the encoding
  answers with an explicit "not modelled here" value rather than guessing.
- The DMN cases file (20 cases as of 2026-08-03: the 16 PR #194 landed, plus the 4 seeds that
  close the total-assets and restricted-period leaves the §8 diff oracle reported inert) has
  **L4-evaluated expected values, never hand-typed** — that is the "earned green" condition under
  which the DMN leg's engine branch runs at all.

## Deontic spine

Three regulative rules, and only three: **advertising restriction**, **ongoing reporting
obligation**, **resale restriction**. They drive the BPMN leg (one process per rule, stems in
`subject.json`), the LTS leg (the digraph count must equal the rule count two compiler paths
agree on), and the `regulative_rules` pin in `pins.json`. A rename or a fourth rule must land in
all three places plus the committed goldens in one change.

## Golden quirks

- The committed DMN golden renders `@ref` provenance as `main.l4:<pos>` (the golden runner
  typechecks against an empty VFS) while the CLI renders `regcf.l4:<pos>`. That is the pipeline's
  D1 canonicalisation (`etc/go/lib/canon-diff.mjs`) — an exporter-harness defect, not a subject
  fact, but this subject is where it was measured: 23 differing lines, all provenance.
- The NLG goldens under `jl4/examples/legal/regcf/tests/` are produced **in-process by
  `cabal test jl4:jl4-test`**; no `l4` subcommand regenerates them, so the TNR leg reports
  NOT-REGENERATED by design.
