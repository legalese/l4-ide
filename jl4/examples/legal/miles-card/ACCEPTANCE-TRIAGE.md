# Triage of the 55 acceptance failures — sg-miles-card

Run `2026-09-21-2e987f68-001`, p6-tests DEGRADED, receipt
`sha256:8894658530171acc57ac6e2f2e461f865db8afd1fccbd0af39b2340139639557`.
184 assertions over `cheatsheet-2026-06`, 129 satisfied, 55 failed.

Every one of the 55 was evaluated on the branch binary before being classified: a probe file
outside the corpus (symlinked into a scratch directory, because L4 import resolution has no
parent-directory step and `JL4_LIBRARY_PATH` is a single path, not a list) `#EVAL`ed each failing
expression plus `miles per dollar if the merchant flags online`, its card-present twin,
`depends on the merchant indicator`, `earns the bonus rate`, `status`, `conditions`,
`cap`'s `capped`, `bonus spend per month` and `pool`. 430 evaluations, 43 distinct calls.

## 1. Classification count

| letter | what it means | count |
| --- | --- | --- |
| (a) | the cheat sheet is wrong on the text | 9 |
| (b) | the encoding is wrong | **0** |
| (c) | genuinely conditional on the merchant indicator | 18 |
| (d) | unheld document, expired document, or rounding | 28 |
| | **total** | **55** |

Breakdown by cluster, in the order the disputed file prints them:

| § | cluster | letter | failures |
| --- | --- | --- | --- |
| 1 | UOB Lady's Solitaire, 6 mpd claimed, 4 in the T&C | d | 10 |
| 2 | DBS yuu, 10 is 10.08 and ~S$822 is S$822.857 | d | 11 |
| 3 | DBS yuu at SimplyGo, the cap admits S$811.27 | a | 1 |
| 4 | POSB PAssion, Promotion Period ended 30 Sep 2025 | d | 7 |
| 5 | DBS Woman's World, the indicator decides | c | 11 |
| 6 | Citi Rewards online limb, cl.6(ii) | c | 5 |
| 7 | HSBC Revolution online, cl.6 | c | 2 |
| 8 | HSBC Revolution at MCC 5411, not an Eligible Transaction | a | 4 |
| 9 | Citi Rewards and the mobile wallet | a | 4 |

## 2. Category (b) — the most important output — is EMPTY

No failure is a case of the cheat sheet being right and a card module misreading its own text.
What was checked, cluster by cluster, and against what:

- **Solitaire 6 → 4.** `uob-ladys-cards-tnc` states 4 twice by two routes: heading A
  ("10X UNI$ per S$5 spent (equivalent to 4 miles per S$1 spent)") and cl.2(b) + cl.2(c)
  (0.4 base + 3.6 bonus). The sheet's own gloss for its 6 is "4 card + 2 savings"; the savings
  uplift is in no document in `source/`. Module right.
- **yuu 10 → 10.08, ~S$822 → S$822.857.** cl.7 chapeau states the cap in POINTS (28,800), so the
  cap figure needs no conversion: 28,800 / 35 = 822.857. cl.12 values a point at 0.28 miles;
  1 + 9 + 26 = 36 points × 0.28 = 10.08. The additive reading is a live fork
  (`F-yuu-bonus-additive`, which is why these answers are `Unconfirmed`), but the rejected
  `replacement` reading gives 7.56, further from the sheet's 10, so the fork cannot rescue the
  cell either way. Module right.
- **PAssion → 0.** cl.3 verbatim: "The Promotion is valid from 1 October 2023 to 30 September
  2025". Fixtures are dated June 2026. Module right, and it says `Source expired` rather than
  guessing a rollover.
- **HSBC at 7-Eleven and Cheers.** Measured: the string `5411` does not occur anywhere in
  `hsbc-revolution-reward-points-tnc.txt` or `hsbc-revolution-faq.txt`. cl.7's list has no
  groceries or convenience limb. cl.8 gives the base 1 point per SGD1. Module right.
- **Citi wallet on the MCC limb.** Measured: `mobile wallet` occurs in the Citi bundle exactly
  twice, both at cl.6(ii) or the FAQ's restatement of it, and nowhere in
  `citi-rewards-exclusion-list.txt`. cl.6(i) carries no wallet language. All four fixtures are
  cl.6(i) charges by MCC (5641, 5641, 5651, 5311). Module right.
- **The indicator clusters.** `dbs-womans-card-tnc` cl.13, `citi-rewards-10x-tnc` cl.6(ii) and
  `hsbc-revolution-reward-points-tnc` cl.6 each say in terms that the issuer does not determine
  the indicator. Reporting the lower branch as the headline is the domain's documented design
  (`miles-card-domain.l4`, "The answer"), not a misreading. Module right.

### Two module defects found in passing — real, but NOT category (b)

Neither is a case of the cheat sheet being right, so neither belongs in the disputed file. Both
are worth filing against the modules.

1. **`dbs-yuu.l4:1031` prints the wrong number on the SimplyGo branch.** The condition string is
   `"this rate adds cl.7(a)'s 9 points to cl.7(b)'s 26; the T&C says neither that they add nor
   that cl.7(b) replaces cl.7(a)"`, and it is emitted on every branch where the additive reading
   is load-bearing — including SimplyGo, where cl.7(a) pays **9.5**, not 9. The arithmetic is
   correct (`dbs-yuu.l4:765` uses `9.5 PLUS ...`, and the cap comes out 28,800 / 35.5 = 811.27);
   only the sentence shown to the cardholder is wrong. A user reading the condition beside the
   SimplyGo answer would be told a figure that contradicts the cap printed next to it.
   *Silent failure: no diagnostic, correct number, wrong explanation.*

2. **`miles-card-domain.l4:309` documents `capped` more narrowly than any module uses it.** The
   comment says "`capped` FALSE means the T&C states no cap and the dollar figure is
   meaningless". Every issuer module instead uses FALSE to mean "this transaction does not run
   against the pool": PAssion answers `capped` FALSE on an expired promotion whose cl.8(b) DOES
   state a cap (5,000 yuu Points per Qualifying Month), and HSBC answers `capped` FALSE on a
   non-Eligible Transaction although cl.7.2 states a 9,000 Bonus Point cap. The usage is
   consistent across modules and `pool` is still named on both arms, so the modules agree with
   each other and the domain comment is the odd one out. Fix the comment, not the modules.

## 3. The two pre-registered rows

Both failed, which is the acceptance test's pass condition (spec §1, NOTES.md §5).

| pre-registered row | failure lines | fate |
| --- | --- | --- |
| §4.1 Woman's World: "Kris+/mobile-wallet in-store (counts as online)" | `cheatsheet-claims.l4:835` | **FAILED.** Classified (c). Fork-register `F-womans-online-definition`, readings `indicatorDecides` (taken) against `viaTheInternetDecides` (rejected); its own note predicts this exact cell. The module answers 0.4 as the headline and 4 on `miles per dollar if the merchant flags online`, so the sheet's figure is the upper branch stated as settled. |
| §4.2 Citi Rewards: "Does NOT earn: mobile wallet (Apple/Google Pay)", unqualified | `cheatsheet-claims.l4:886, 887, 906, 907` | **FAILED.** Classified (a). All four fixtures reach cl.6(i) by MCC, where no wallet language exists; `earns the bonus rate` is TRUE and the rate is 4. The household's "never pay Citi with a wallet" rule costs it 3.6 miles per dollar at exactly the shops the card was chosen for. |

Neither was found by being told where to look: both fell out of evaluating all 55.

## 4. The disputed file

`miles-card-disputed.l4` (beside this file)

- **112 assertions**, 623 lines, 9 `§§` clusters, covering all 55 failure lines and no others.
  One `#ASSERT NOT (...)` per failure restating the cheat sheet's claim verbatim, plus one
  positive `#ASSERT ... EQUALS <the text's answer>` on each, plus two extra assertions pinning
  the Woman's World wallet-tap row's upper branch and its `depends on the merchant indicator`.
- Fixtures are **imported, never redefined**: the file now carries `IMPORT `cheatsheet-claims``
  and every expression is copied unchanged from that file, negated in place.
- Two cap figures are written as divisions rather than decimal literals, so the assertion states
  the document's own arithmetic instead of a truncation: `28800 / 35` (yuu merchants) and
  `28800 / 35.5` (SimplyGo). Both verified to hold exactly.

### Gates

| check | result |
| --- | --- |
| `l4 run miles-card-disputed.l4` | 112 directives, 112 satisfied, **0 `assertion failed`**, **0 `DiagnosticSeverity_Error`**, 0 warnings |
| `l4 check miles-card.l4` | `Check succeeded.` (exit 0) |
| positive control | the same file plus one deliberately false assertion reports exactly 1 `assertion failed` and raises a `DiagnosticSeverity_Error` |

The positive control was not ceremonial: the first gate run used the grep `assertion .*: false`,
which matched nothing on either the green file or the control. The real failure string is
`assertion failed`. Had the control been skipped, a green count would have been reported from a
pattern that cannot fail.

### Goldens

The triage agent that wrote this report ran no `cabal` and left
`jl4/examples/legal/miles-card/tests/miles-card-disputed.{golden,ep.golden,nlg.golden,schema.golden}`
stale (the module grew from 26 lines to 623). They were regenerated by the coordinating session
before commit `1dd165f9c`, the same commit that carries the module: `jl4-test -m miles-card` run
twice (216 examples, 0 failures on the second pass), no absolute paths, and the run golden's diff
adds exactly 112 `assertion satisfied` lines and no failures or errors. An earlier version of this
paragraph said the goldens were still stale; that was true of the agent's hand-off, not of the
commit.
