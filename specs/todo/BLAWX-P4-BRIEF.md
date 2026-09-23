# L4.Blawx P4 — implementation brief (the showcase ladder)

_Working brief for Blawx phase P4, 2026-08-19. Authority chain:
`specs/todo/BLAWX-EXPORT-SPEC.md` (§10 P4) and the P1/P3 briefs beside this one. Where this
brief conflicts with the ruled spec, the spec wins and the conflict is a finding to report.
Full corpus-scouting evidence:
`/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/4638d7ee-14b9-4ef5-8061-36a8c1ced864/scratchpad/p4-evidence/corpus-scout-report.md` — read it._

## The ladder (Meng's steer, 2026-08-19)

Meng: start with the smaller cases that ship by default in the jl4-web deployment (every
top-level `.l4` in `jl4/examples/legal/`, per `ts-apps/jl4-web/scripts/copy-examples.ts`),
plus `rodentsAndVermin`, before the heftier statute corpus. Three rungs, each a publishable
increment; the workflow delivers all three, smallest first, so a failure on a later rung
still leaves shipped value:

- **P4a — rodents-and-vermin.** `jl4/examples/ok/rodentsAndVermin.l4` (57 lines, pure
  boolean, one `GIVEN` record — exactly the P1 seed shape; verified to fit the v1 fragment
  as-is). The classic isomorphism demo.
- **P4b — the ASSUME→RInput widening**, which unlocks `anti-social.l4` (49 lines) and
  `imaginary-alcohol-act.l4` (99 lines) from the default-shipped set, and discharges P1's
  deferred `#abducible`-interview earmark for modules with no record inputs.
- **P4c — the statute showcase**: Housing Act 1988 Sch 2 **grounds 13, 15, 17 and 8**
  inlined into ONE self-contained module. The BNA is DECLINED for P4 (scout-verified: three
  `DATE` record fields are fatal — record fields are not reachability-filtered,
  `Blawx/Lower.hs:608` — and pre-resolving dates to booleans would delete the statute's
  actual legal content, the commencement boundary; plus ~20 of 44 names mangle to
  `p_1_1_a_…` warts).

## Facts the scout verified (do not re-derive; spot-check if suspicious)

- **Lowering is export-rooted** (`Relational/Lower.hs:2337-2341` walks `closureRefs` from
  `@export`ed decisions) — deontic tails and unreachable helpers are harmless if simply
  not exported. EXCEPT record fields: every field of every record in the module is
  declared (`Blawx/Lower.hs:608`), so DATE/STRING fields are fatal even when unread.
- **`buildCtx` is module-scoped** (`Relational/Lower.hs:590,414-420`): imported `DECLARE`s
  never become categories — a multi-file aggregator will NOT lower its imports' logic.
  Inlining is required, not stylistic.
- **`@desc` is the only NL channel reaching Blawx's `rule_text`** (`Blawx/Lower.hs:219`:
  `bsText = squash (fromMaybe (stubSection p) p.rpDesc)`, stub "Definition of <name>.").
  `@nlg` is deliberately unconsumed (recorded deviation, `Blawx/Lower.hs:55-68`); `@ref`
  reaches the IR (`rpRef`) and stops; inert verbatim prose is erased by design.
  **"Citations back to sections" = `@desc` on each `@export`. That is the authoring work.**
- **`@export` placement is load-bearing**: above `GIVEN`. Between `GIVETH` and the head it
  "does not reliably attach" (benefit.l4 header — `getExportedFunctions` returned ONE of
  two decisions in Appendix A's original placement).
- **Top-level `ASSUME` is currently out of the fragment** (`Relational/Lower.hs:278-279`
  `ctxAssumes`, tracked and not lowered; local ASSUME bails at `:1076-1078`).
- Mangling is clean for the chosen grounds (13/15/17 have no digit-initial/final names;
  ground 8's `RentPeriod` enum and `13 TIMES`/`3 TIMES` arithmetic are in fragment).
- Grounds verified green with a prebuilt l4: 8, 13, 15(implied), 17(implied), plus
  10/7A/5H — but re-run `l4 check` yourself on the four you inline.

## P4a — rodents (smallest rung; do this first and completely)

1. Author `jl4/examples/blawx/rodents.l4`: the `ok/rodentsAndVermin.l4` logic (leave the
   original untouched), restyled to seed conventions: `@export` on `insurance covered`
   (and any helper worth an interview), `@desc` on each export carrying the policy
   language (the WHERE-clause names are near-verbatim already), oracle-commented test
   population — keep the existing all-FALSE `#EVAL`, add `#EVAL`s/`#ASSERT`s covering:
   covered-loss-by-rodents-to-contents-by-birds interplay, the ensuing-covered-loss
   override, an exclusion case. Verify every oracle comment by running `l4`.
2. Emit goldens (`.blawx` + `.pl`), register in tests-cli exactly as the four seeds are.
3. Tier-1 harness green on its queries; headless fixpoint harness green on its rows.
   An interview test per the P1 convention (`#abducible` inputs from the record fields).

## P4b — ASSUME→RInput widening (the middle-end rung)

R2 as ruled: "the blawx work can drive the relational middle end work." This is that.

1. `L4.Relational.Lower`: lower top-level `ASSUME`d names as predicates with
   `rpKind = RInput`, parameters from the ASSUME signature, zero clauses. ADDITIVE ONLY:
   every existing relational golden byte-stable; `ctxAssumes` sites and the module haddock
   updated; a new relational seed (`jl4/examples/relational/assumed.l4`) + Debug golden +
   a not-ok fixture for whatever remains out (e.g. higher-order ASSUME if expressible).
2. `L4.Blawx.Lower`: ASSUME-derived `RInput` predicates become declarations (category vs
   attribute by sort, same classification as record fields) and `#abducible` lines in
   interview tests — including for modules with NO record inputs (the P1 earmark: sumlist
   got no interview test; revisit whether it now can).
3. Blawx seeds from the default-shipped set: `jl4/examples/blawx/antisocial.l4` and
   `jl4/examples/blawx/alcohol.l4` (adapted from `jl4/examples/legal/{anti-social,
imaginary-alcohol-act}.l4`; leave the originals untouched), with `@export`/`@desc`.
4. **The oracle problem — solve it honestly.** ASSUME-style modules do not evaluate in L4
   (`ASSUME` is uninterpreted), so `l4 run` cannot anchor the tier-1 expectations.
   Preferred discipline: each seed ships a GIVEN-record **semantic twin** of its logic in
   the same file (or a sibling), `#EVAL`s over the twin supply the oracle values, and the
   harness runs the ASSUME-side Blawx encoding with the same facts asserted — one logic,
   two spellings, cross-checked. If the design pass finds a cleaner honest anchor, take it
   and record why. Hand-derived expectations with no executable anchor are the LAST
   resort and must be labelled as such in the harness.

## P4c — the Housing grounds module

1. Author `jl4/examples/blawx/housing-grounds.l4`: grounds 13, 15, 17, 8 inlined from
   `jl4/experiments/housing-act-ground-{13,15,17,8}.l4`. Each ground owns its Claim
   record; they compose without collision. Drop the deontic tails (`ground N possession
order`) and the `Actor`/`Action` import entirely (cleaner than leaving them
   unexported, and the file must be self-contained). Keep the grounds' own `#ASSERT`s,
   adding oracle comments; add interview-shaped `#EVAL`s (e.g. ground 8 arrears at the
   13-week boundary, both sides).
2. `@export` + `@desc` on every headline decision and interesting helper; the `@desc`
   text is a straight lift of the verbatim statutory words already present as inert
   prose, prefixed with the citation ("Sch 2 Ground 13: …"). Ground 8's two inert-only
   predicates (rent-lawfully-due, universal-credit) are NOT exported; their prose becomes
   `@desc` on neighbours.
3. Emission + goldens + tests-cli + tier-1 + headless fixpoint, as P4a.
4. Ground 8 carries two arity-2 computed predicates that get no declaration block
   (`Blawx/Lower.hs:45-48`, recorded gap — relationships start at arity 3). Confirm their
   rules still emit XML images and the fixpoint holds on those rows; if a row gaps, the
   P3 assertion will catch it — report, don't suppress.

## The one-liner that rides along

`Blawx/Lower.hs:219` → fall back through the citation: `p.rpDesc <|> p.rpRef` (squashed).
Gives any `@ref`-annotated corpus its citations for free (the BNA's 47, when dates land).
Add a regression case (a seed decision with `@ref` and no `@desc`). Cheap, scout-verified,
in scope.

## What the workflow does NOT do

Publishing to the container, the scenario-explorer interview, and the screen recording are
the coordinator's tier-2 work after this lands. Moving the wider Housing corpus under CI
(47 files, never covered — scout finding) is out of scope; note it for the coordinator.

## Facts that will bite (house)

- Repo is `-Wall -Werror`, `NoFieldSelectors` + `OverloadedRecordDot`. **ONE cabal
  invocation at a time in this worktree** (freshly cut — first build is full).
- The relational middle-end is SHARED **by design, not yet in fact**. CORRECTED 2026-08-19,
  measured: `grep` for `L4.Relational`/`RelProgram` over every `.hs` in the tree returns
  `jl4-core/src/L4/{Relational/*,Blawx/{IR,Lower,Emit}.hs,Desugar.hs}`,
  `jl4-core/test/{RelationalSpec,BlawxAssumeSpec}.hs`, `jl4/app/L4/Cli/Blawx.hs`,
  `jl4/tests/RelationalExport.hs` — i.e. **exactly one consumer, `L4.Blawx`**. `L4.Docassemble`
  and `L4.OpenFisca` exist and do not import it; there is no Catala module in this tree at all.
  So the additivity requirement is forward-looking, and the goldens that pin it are
  `jl4/examples/relational/expected/*` and `jl4-core/test/RelationalSpec.hs` — do not go looking
  for docassemble/openfisca goldens of the middle end, there are none. The widening must still
  not change any existing lowering (prove it with those goldens), and the `RInput` haddock in
  `Relational/IR.hs` must be updated to name the second source.
- Seed corpus conventions: oracle on the line after each directive (`-- L4 oracle ==>`);
  expected values live in the HARNESS, never the artifact (R11).
- `etc/blawx-tier1-harness.py` needs its expectation table extended for the new seeds;
  `etc/blawx-fixpoint-harness.mjs` discovers goldens by glob — check it picks up the new
  files.
- prettier 3.4.2 for markdown; goldens are not markdown. Do NOT commit; scratch in
  `p4-design/`.

## Definition of done (workflow's share of P4)

`cabal build all` clean under `-Werror`; all suites green including new tests-cli goldens
and relational goldens (existing ones byte-stable); tier-1 harness green over the FULL
seed population (old 16 + every new query) with honest oracles; headless fixpoint harness
green over every row of every golden, new seeds included; the `rpDesc <|> rpRef` fallback
in with a regression case; `p4-design/` records the authoring decisions (which prose
became which `@desc`, the P4b oracle discipline chosen); no changes outside `jl4-core/`,
`jl4/app/`, `jl4/tests-cli/`, `jl4/examples/blawx/`, `jl4/examples/relational/`, `etc/`,
`specs/todo/`, and `p4-design/`. The coordinator then publishes, drives the interviews,
records the screen capture, and writes §10 P4's EXECUTED entry.
