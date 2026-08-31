# Notes -- l4-guided, trial t2

## Checks run

Ran `l4 check` (typecheck only, no evaluation) on both files, from the trial directory:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
```

Both report `Check succeeded.` I did **not** run `l4 run` and did not evaluate any `#EVAL`
directive, per the task rules.

Getting there took several rounds of fixing genuine syntax problems (not just formatting
taste) -- recorded below because they bear on how literally "verbatim" can be taken, and
because two of the fixes are substantive enough to flag for review.

## Fixes needed to make the given schema/helpers actually typecheck

1. **`DECLARE Claim HAS ...` field names were not backtick-quoted in the schema, and needed to
   be.** `bench/schema-l4.md` writes e.g. `agreement signed IS A BOOLEAN` with no backticks,
   even though its own two helper `GIVEN` blocks correctly quote their multi-word parameters
   (`` `event month` ``, `` `limit month` ``). An unquoted multi-word span is not a legal L4
   identifier (confirmed against `doc/reference/syntax/identifier-example.l4` and every
   multi-word record field I could find under `jl4-core/libraries`, which are either single
   camelCase words or backtick-quoted, e.g. `` `Contract Event` ``'s fields). I added
   backticks around every multi-word field name in the `Claim` record. This is a pure syntax
   fix -- no field was renamed, retyped, added, or removed; the field vocabulary is identical
   to the schema's.

2. **The given `` `arose out of` `` helper does not typecheck as written.** The schema gives:
   `` `arose out of` MEANS c `elem` cs ``. L4 has no Haskell-style backtick-infix calling
   convention -- backticks only quote an identifier, they do not turn a prefix function into
   an infix operator. So that line parses as plain juxtaposition `c elem cs`, i.e. "apply `c`
   (a `Cause` value) to the arguments `elem` and `cs`", which fails to typecheck (`l4 check`:
   "type Cause ... which is not a function ... applying it to 2 arguments"). I changed the
   body to `elem c cs` (ordinary prefix application, matching `prelude.l4`'s actual signature
   `GIVEN a IS A TYPE, x IS AN a, list IS A LIST OF a GIVETH A BOOLEAN elem x list MEANS ...`).
   The helper's contract is unchanged: same name, same `GIVEN`/`GIVETH` signature, same
   "is `c` a member of `cs`" meaning -- only the internal expression that makes it compile is
   different. I did not touch the `` `no later than` `` helper; it typechecks as given.

3. **`DECIDE \`name\` claim MEANS ...` (a backtick multi-word name, a repeated parameter, and
   `MEANS`) does not parse**, even though `DECIDE factorial n MEANS ...` (a plain identifier)
   is a documented form. The parser error pointed at the `MEANS` token itself. I could not
   find a documented reason for the discrepancy within the permitted references; empirically,
   dropping `DECIDE` and keeping `` `name` claim MEANS ... `` (matching the style already used
   throughout `jl4-core/libraries`, e.g. `` `is fully paid` MEANS ... ``) fixed it. The two
   definitions this affected are `` `hospitalization is for sickness or accidental injury` ``
   and `` `recovery not sought before the waiting period expired` ``; both now omit `DECIDE`.

4. **`WHEN JUST _ THEN ...` does not parse**, though `doc/reference/control-flow/CONSIDER.md`
   shows `_` used as a wildcard after the mixfix pattern `head FOLLOWED BY _`. Applying `_`
   directly as a constructor argument (`JUST _`) was rejected by the lexer ("unexpected `_`").
   Fixed by naming the bound variable instead (`WHEN JUST v THEN TRUE`) in the `` `has
   occurred` `` helper, since I don't need the payload there.

None of these four are changes of legal substance -- they are what it took to get the given
material and my own additions to actually compile.

## Judgement calls on what the policy means

- **Section 1.3's "still pending or satisfied in a timely fashion" is read as one compound
  obligation due whole at the month-7 mark**, evaluated against `hospitalization month` (the
  clock fixed by 1.1: "in effect at the time of the hospitalization"). Before month 7,
  nothing about 1.3 has come due yet, so it cannot yet have failed ("still pending") --
  regardless of whether the wellness visit's own month-6 sub-deadline has separately passed.
  At or after month 7, the whole package must actually hold: confirmation given no later than
  month 7, of a visit no later than month 6, with a qualified provider. This is what makes
  Q3 (hospitalization at month 5, no wellness-visit facts otherwise given) turn on "still
  pending" rather than on the visit/confirmation facts themselves.

- **Fraud and misrepresentation are treated as unconditional, not time-gated against
  `hospitalization month`** -- any `JUST` value cancels the policy, regardless of when it
  occurred relative to the hospitalization. This is a deliberate asymmetry with the §1.3
  treatment above: 1.2 explicitly gives §1.3 a pending/satisfied disjunction tied to a
  deadline, but says only "there is fraud" for the fraud trigger, with no comparable
  "pending" language. I did not invent a "did the fraud happen before the hospitalization"
  gate that the text does not state.

- **60 days (the pre-suit waiting period in §3.2.1) is converted to 2 months (60/30)** so it
  can be compared against `recovery sought month` / `written proof of claim month`, which are
  in the schema's month units throughout. This is the one place the contract itself switches
  units (days, not months); the conversion is a modelling necessity, not a reading of intent.

- **The §3.2.1 arbitration/award sub-clause (unable-to-settle -> arbitration -> valid award)
  is conditional on `dispute arisen`; the 60-day recovery clause is not.** The text's own
  phrasing supports the split: the arbitration sentences are introduced by "If any dispute or
  disagreement arises...", while the 60-day sentence is unconditional ("In no case shall
  You..."). All nine `apply.l4` claims set `dispute arisen = FALSE`, so this distinction is
  not exercised by any of the nine queries, but it does shape `covered`.

- **Section 1.1's `Neither` ground is read as "not a covered event type at all"**, gating
  coverage before §§1.2/1.3/2 are even reached -- 1.1 premises payment on "hospitalization
  for sickness or accidental injury"; a hospitalization for neither is not that kind of event.

## Judgement calls specific to individual `apply.l4` queries

- **Q4 / Q6**: "confirmation of my wellness visit" (Q4) and "proof of my wellness visit was
  provided" (Q6) are both read as the act of submitting `written confirmation`, not the
  underlying visit itself -- so only `` `written confirmation month` `` is set to the number
  given in the question, and `` `wellness visit month` `` is left at a compliant baseline
  (the question does not state when the underlying visit happened).

- **Q4**: the question does not state `hospitalization month`. I set it to 9 (after the given
  month-8 confirmation) so that the late confirmation is judged against a hospitalization that
  comes after the month-7 deadline has already passed without timely compliance -- i.e. so
  the question actually exercises the "confirmation was late" branch rather than "still
  pending". A smaller `hospitalization month` (< 7) would make this fact irrelevant under my
  reading of §1.3 above, which would arguably defeat the purpose of the question.

- **Q5** ("hospitalized for punching my own face to show off for my friends"): read as
  `` `hospitalization ground` = Neither ``, not `` `Accidental injury` `` -- a deliberate act
  done on purpose is not, in ordinary insurance usage, an "accident", even though the
  resulting injury's severity may not have been intended. This is the crux judgement call for
  Q5; the "did not commit fraud or misrepresentation" clause in the question reads as a
  distractor ruling out the *other* possible route to non-coverage.

- **Q9** ("I was serving as a police officer at the time of hospitalization"): this is read as
  an occupational-status fact, not a causation fact, and so `causes` is left `EMPTY` rather
  than `LIST \`Police service\``. Section 2.1 excludes an event "arising directly or
  indirectly out of ... service in the police" -- i.e. it requires the injury to be *caused
  by* that service. A son biting his parent's ankle has nothing to do with the parent's job;
  the parent merely happens to hold that job at the time. This is the crux judgement call for
  Q9, and is the one place across all nine queries where "a fact is mentioned" and "a fact is
  relevant to an exclusion" deliberately come apart.

- **Q6/Q8**: age 79 (Q6) and "did not commit fraud" (Q8) are included as stated but are not
  dispositive under my reading (skydiving and military-service are each independently
  sufficient exclusions) -- they are left in the `Claim` as given, not neutralised, since the
  task asks only that *unrelated* fields be set to non-triggering baselines, and both facts
  are facts the question itself supplies.

## Baseline values used for fields a given question does not mention

`agreement signed = TRUE`; `premium paid month = JUST 0`; `policy term months = 12`;
`wellness visit month` / `written confirmation month` set to a mutually consistent, fully
compliant pair (visit before month 6, confirmation before month 7) with
`wellness visit provider qualified = TRUE`; `fraud month = NOTHING`;
`misrepresentation month = NOTHING`; `causes = EMPTY`; `age at hospitalization = 40`;
`dispute arisen = FALSE` with the five dispute/arbitration/recovery fields at `NOTHING`/`TRUE`
values that make those clauses vacuously satisfied.
