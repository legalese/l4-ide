# P4c — `jl4/examples/blawx/housing-grounds.l4`, as built

_Written by the implementing agent on 2026-08-19, against the tree as it stands. Everything marked
MEASURED was produced by running the `l4` built in THIS worktree at this commit, after the P4b
widening landed under it. Where `corpus-plan.md` §3 and the tree disagree, this file records the
tree._

Companion to `seeds-as-built.md` (P4a/P4b). Scope: the Housing grounds module, its two goldens, its
`tests-cli` registration, and the two harness runs.

---

## 1. What shipped

| file                                    | shape                | directives              | goldens          |
| --------------------------------------- | -------------------- | ----------------------- | ---------------- |
| `jl4/examples/blawx/housing-grounds.l4` | four `GIVEN` records | 45 `#EVAL`, 4 `#ASSERT` | `.blawx` + `.pl` |

Sources left untouched, as the brief requires: `jl4/experiments/housing-act-ground-{8,13,15,17}.l4`
and `jl4/experiments/housing-act-common.l4`.

Runs, all on this tree:

- `cabal build all --enable-tests` clean under `-Werror`.
- `l4-cli-test` **281 examples, 0 failures** (was 278; +3 — two goldens and the arity-2 gap test).
  Now **282**, after the review added the `not-ok/arity-two.l4` refusal fixture
  (`fix-dispositions.md` F2/F6).
- `etc/blawx-tier1-harness.py` over the FULL population: **150 / 150 passed** (was 101; +49),
  40 s wall clock for the whole population. The summary line now splits that into **115 distinct +
  35 twin replays** of a byte-identical program; 150 is the number of rows executed, 115 is the
  number that may be quoted as coverage (`fix-dispositions.md` F7).
- `etc/blawx-fixpoint-harness.mjs`: **181 rows checked, 0 failed, 0 empty-skipped** (was 116; +65 —
  15 workspaces + 49 query tests + the interview).
- `etc/check-corpus-goldens.mjs`: 355 corpus files, all four goldens present (the seed lives under
  `examples/blawx/`, which `jl4/tests/Main.hs` does not glob, so it carries no four-golden
  obligation — same as the other nine blawx seeds).

---

## 2. Two things `corpus-plan.md` got wrong, both about directive syntax

### 2.1 `#ASSERT` cannot take a parenthesised argument on a continuation line

`corpus-plan.md` §3.5 rewrote every directive as an inlined record literal without distinguishing
the two directive parsers. MEASURED, on a four-line probe
(`p4-design/scratch/p4c/assert-continuation.l4`):

```
#EVAL p
        (R WITH x IS TRUE)     -- parses

#ASSERT p
        (R WITH x IS TRUE)     -- parse error at the `(`:
                               -- "unexpected (, expecting %, ;, OF, end of input, or space token"
```

`Assert` is built from `singleLineExpr` (`L4.Parser`, the directive `choice` block), which is
line-oriented; `#EVAL` is not. The fix is the idiom `rodents.l4` already uses — the `OF … WITH`
spelling, whose layout continues legally:

```
#ASSERT `Ground 8 made out` OF
            Ground8Claim
            WITH
                `the basis on which rent is payable` IS `weekly or fortnightly`
                …
```

All four `#ASSERT`s in the file are written that way. It is not a workaround: `OF … WITH` is the
same record literal, and it reaches `lowerQuery`'s record-literal branch identically (all four
emitted a test — q1, q16, q26, q36 — and all four pass tier-1).

Worth filing, NOT in P4 scope: `#EVAL` and `#ASSERT` accept different expression grammars for no
reason a reader can see, and the error message names `OF` without saying why.

### 2.2 The plan's §3.5 tables are values, not a directive list

§3.5 tabulates every predicate's value in every scenario (five rows × three predicates for grounds
13 and 15, six × four for 17). Emitting a directive per cell would be 73 tests. The file emits
**49**, chosen so that every scenario appears at least once and every exported decision is exercised
on both sides of its own boundary; the cells left out are the ones whose value is forced by a cell
that is in. Directive count and test count agree exactly (49 `q`-tests, `q1`…`q49`, no gaps), which
is the check §0.2 says matters — a silently dropped directive shows up as a gap or as a pairing
failure in the tier-1 harness.

### 2.3 The two dropped shapes, re-measured here

`corpus-plan.md` §0.2's finding is the reason every directive in this file was rewritten, so it was
re-measured rather than borrowed. `p4-design/scratch/p4c/dropped.l4` carries three directives — an
`#EVAL` over a record literal, an `#ASSERT NOT` over a record literal, and an `#ASSERT` over a named
scenario constant. `l4 blawx` on it exits **0 with empty stderr** and emits **one** test (`q1`) plus
the interview. Both the `NOT` form and the named-constant form vanish without a word.

The tier-1 harness's `len(oracles) != len(tests)` guard would have caught the resulting imbalance,
but only as "cannot pair" — it cannot say which directive went missing. This file's counts agree
exactly (49 and 49), so the guard never fired.

---

## 3. The four renames, and what each cost

All four are forced by the single Blawx atom namespace (one file, because `buildCtx` is
module-scoped). Not carried over from `corpus-plan.md` — re-measured here, on this module, in this
tree: `p4-design/scratch/p4c/unrenamed.l4` is this seed with all four renames reverted, and
`p4-design/scratch/p4c/unrenamed.err` is what it produces. `l4 check` on it says **`Check
succeeded.`**; `l4 blawx` on it exits 1 with all four collisions named
(`rent period` / `RentPeriod`, `lodger or sub-tenant removal proviso` × 2, and the two shared
Ground13Claim/Ground15Claim fields). That split — legal L4, hard Blawx error — is the whole reason
inlining is not copy-paste.

| #   | was                                                                                              | is now                                                                                                           |
| --- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| 1   | `Ground8Claim`'s field `rent period` (vs the enum TYPE `RentPeriod`; both → `rent_period`)       | `the basis on which rent is payable`                                                                             |
| 2   | `lodger or sub-tenant removal proviso` in BOTH ground 13 and ground 15                           | `… (waste, neglect or default)` and `… (ill-treatment)`                                                          |
| 3   | `the responsible actor is a person lodging with the tenant or a sub-tenant of his` in 13 AND 15  | ground 15's → `the person ill-treating the furniture is a person lodging with the tenant or a sub-tenant of his` |
| 4   | `the tenant has not taken such steps … for the removal of the lodger or sub-tenant` in 13 AND 15 | ground 15's → `… for the removal of the lodger or sub-tenant who ill-treated the furniture`                      |

3 and 4 are a fidelity **gain**, not a tax: ground 15's own words are "in the case of ill-treatment
by a person lodging with the tenant", ground 13's are "in the case of an act of waste by … a person
lodging with the tenant". The shared spelling in the experiments files had erased a distinction the
two grounds actually draw.

MEASURED after the renames: `blawx_category/1` for `ground8_claim`, `ground13_claim`,
`ground15_claim`, `ground17_claim` and `rent_period`; 27 `blawx_attribute/…` facts across the four
categories; no collision diagnostic; `l4 blawx` exits 0 with empty stderr.

---

## 4. Which prose became which `@export` line

Fourteen exported decisions, fourteen numbered sections in `rule_text`, in export order. The table
is the mapping the brief asks to be recorded; the full text is on the `@export` lines in the seed
and reproduced verbatim in the `.blawx` golden's `rule_text` field.

| §   | decision                                                           | source of the words                                                                                                      |
| --- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| 1   | `Ground 8 made out`                                                | Ground 8's chapeau, verbatim + the RRA 2025 universal-credit rule (from the unexported `rule —` decision)                |
| 2   | `per-period threshold met`                                         | limbs (a) and (b) verbatim + the "rent means rent lawfully due" definition (from the unexported `definition —` decision) |
| 3   | `required arrears for the period`                                  | editorial statement of the two in-force thresholds + the RRA 2025 commencement citation                                  |
| 4   | `an in-force threshold applies to this rent period`                | editorial: why the omitted (c)/(d) limbs mean no threshold engages                                                       |
| 5   | `Ground 13 made out`                                               | editorial conjunction + ground 13's "common parts" definition, verbatim                                                  |
| 6   | `deterioration owing to waste, neglect or default`                 | limb 1 of ground 13, verbatim                                                                                            |
| 7   | `lodger or sub-tenant removal proviso (waste, neglect or default)` | ground 13's proviso, verbatim + the material-implication reading                                                         |
| 8   | `Ground 15 made out`                                               | editorial conjunction + the "in the opinion of the court" standard-of-proof note                                         |
| 9   | `furniture deteriorated owing to ill-treatment`                    | limb 1 of ground 15, verbatim                                                                                            |
| 10  | `lodger or sub-tenant removal proviso (ill-treatment)`             | ground 15's proviso, verbatim + the material-implication reading                                                         |
| 11  | `Ground 17 made out`                                               | editorial conjunction + the HA 1996 s.102 insertion and commencement citation                                            |
| 12  | `tenant is a grantee of the tenancy`                               | limb 1 of ground 17, verbatim                                                                                            |
| 13  | `landlord induced by a false statement`                            | limb 2 of ground 17, verbatim                                                                                            |
| 14  | `statement made by the tenant or at the tenant's instigation`      | limbs (a) and (b) of ground 17, verbatim                                                                                 |

Two decisions are deliberately **not** exported — `definition — rent means rent lawfully due from
the tenant` and `rule — universal credit housing amount not yet received is ignored`. Both are pure
inert prose over `TRUE`; exported they would be constant-true predicates in the ontology. Their
words ride on §2 and §1 respectively, so nothing is lost from the artifact, and they stay in the
source because the statute says them. MEASURED: they reach nothing — `rule_text` has exactly
fourteen sections, and neither name appears anywhere in either golden.

The `§` title reaches `ruledoc_name` verbatim, em dashes intact:
`Housing Act 1988 — Schedule 2 — Grounds 8, 13, 15 and 17`.

---

## 5. What was dropped, and the measurement that says it was safe

- **All three imports** (`prelude`, `housing-act-common`, `daydate`). `AT LEAST`, `TIMES`,
  `AND`/`OR`/`NOT` and `CONSIDER` need none of them. Dropping `daydate` is the load-bearing one: it
  keeps every DATE out of the module, and record fields are declared unconditionally rather than
  reachability-filtered, so a DATE field would reach the ontology even unread. MEASURED: `l4 check`
  succeeds with no imports at all.
- **The four `ground N possession order` deontic tails**, and with them `Actor`/`Action`. Lowering
  is export-rooted, so leaving them unexported would also have worked; deleting them is what makes
  the file self-contained. The modality survives in the `@export` prose (Part I "the court MUST",
  Part II "the court MAY").
- **`threshold met for arrears`**, folded into `per-period threshold met`. This is the one
  substantive shape change: the experiments file had TWO arity-2 computed predicates, and folding
  leaves exactly one, which is the site §6 measures.

---

## 6. The arity-2 site: MEASURED, and the shape is kept

`per-period threshold met` is `(Ground8Claim, NUMBER) -> BOOLEAN`. Total arity 2 with the boolean
output dropped, and the second parameter is neither record- nor enum-sorted, so it is not
attribute-shaped and does not reach the arity-3 relationship form either.

MEASURED on the emitted golden:

- **No declaration.** `blawx_attribute(ground8_claim,per_period_threshold_met…)` does not appear;
  the other 27 attributes do. This is the recorded relationships-start-at-arity-3 gap, now witnessed
  in the corpus rather than in a probe.
- **The rules and the query rows DO emit**, and every one carries a Blockly image. In the rule
  bodies it is imaged as `attributetype="object"`; in the four query rows as
  `attributetype="number"`, with `infix` set to the raw mangled atom `per_period_threshold_met`
  rather than a prettified phrase, because there is no `blawx_attribute_nlg` fact to draw one from.
  It is really a boolean relation on (claim, arrears), so both types are wrong and the infix is
  cosmetically wrong.
- **No row gaps.** `xml_content` is non-empty on all 65 rows (the `noBlankedBlawxRow` assertion in
  `tests-cli`, extended to this seed, checks the same thing in CI).
- **The fixpoint holds.** `etc/blawx-fixpoint-harness.mjs` re-saves all 65 rows, including the four
  `per_period_threshold_met` query rows: 181 checked, 0 failed, 0 empty-skipped.

**So the branch taken is §3.6's first one: keep the shape.** The fallback (two arity-1 wrappers,
`threshold met at the date of service` / `… of the hearing`) was not needed and was not built. The
brief asked to confirm, report and not suppress; the mis-imaging is reported below rather than
papered over with a wrapper that would have hidden it.

`jl4/tests-cli/Main.hs` pins both halves — the declaration is absent, the rules and query rows are
present — with a comment saying that a change which starts declaring arity-2 predicates should
delete the test rather than work around it.

---

## 7. Findings to carry forward (none in P4 scope)

1. **The arity-2 mis-imaging.** An undeclared arity-2 predicate is imaged as a value attribute with
   an invented type (`object` in rule position, `number` in query position) and the raw mangled atom
   as its `infix`. Witness: the `q2` query block in
   `jl4/examples/blawx/expected/housing-grounds.blawx`. A scenario-editor user sees a rule they
   cannot resolve against any declared attribute. P3 follow-up.
2. **`#ASSERT` and `#EVAL` accept different expression grammars** (§2.1). `#ASSERT` is
   line-oriented; a parenthesised argument on a continuation line is a parse error whose message
   names `OF` without saying why.
3. **The wider Housing corpus is still uncovered** — 47 files in `jl4/experiments/`, none under CI.
   Explicitly out of P4 scope; noted for the coordinator, as the brief asks.
