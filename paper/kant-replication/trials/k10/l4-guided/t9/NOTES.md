# Notes on this encoding

## Checks run

I ran, from the trial directory root:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
```

Both printed `Check succeeded.` I did not run `l4 run` (or anything else that would
evaluate the `#EVAL` directives) on either file, and did not otherwise test the
encoding against the nine questions, per the rules.

I also diffed the `DECLARE` block and the two supporting-helper definitions in
`policy.l4` against the fenced code blocks in `inputs/schema.md` (via a scratch
`diff`) and confirmed they are copied verbatim, byte for byte.

## Judgement calls

- **"Still pending" reading of Section 1.3.** Section 1.1 conditions the policy
  being in effect _at the time of hospitalization_ on Section 1.3 being "still
  pending or ... satisfied in a timely fashion." I read this as: if the
  7-month deadline for supplying written confirmation hadn't arrived yet as of
  the hospitalization month, the condition is simply not yet due (`still
pending`), regardless of what happens to it afterwards — so a hospitalization
  early in the policy year can't be defeated by a later failure to comply with
  1.3. Only once the hospitalization occurs after month 7 do I require Section
  1.3 to have actually been satisfied (confirmation ≤ month 7, the underlying
  visit ≤ month 6, with a qualified provider). This is `` `section 1.3 pending
or satisfied` `` in `policy.l4`. This affects Q4, where I placed the
  hospitalization at month 9 (after the month-8 confirmation) specifically so
  the lateness the question describes is actually operative — see below.

- **Mapping "proof of the wellness visit was provided/given confirmation ...
  N months after the effective date" (Q4, Q6, Q9) to `written confirmation
month`, not `wellness visit month`.** The policy text's own vocabulary is
  "written confirmation ... of a wellness visit," so I treat all three
  questions' stated month as the confirmation date, and set the (unstated)
  underlying visit date favorably (≤ 6). For Q6 in particular this matters:
  6.5 sits between the two deadlines (visit ≤ 6, confirmation ≤ 7), so 6.5
  as a confirmation date is timely; it would not be timely as a visit date.
  It ends up moot for Q6 because skydiving independently excludes the claim,
  but I flag the mapping since it is a real interpretive choice.

- **Hospitalization month placed after the described events, when a question
  states a month and doesn't state a hospitalization month itself (Q4).**
  The claimant narrates "I had given confirmation ... 8 months after the
  effective date" in the past tense, as an already-completed fact — which
  presupposes the point of evaluation (hospitalization) is at or after month 8. I set `hospitalization month = 9` for Q4 so the lateness described is
  the thing actually being tested, rather than being mooted by the "still
  pending" escape above. For Q3, Q6, Q7, Q9, where the confirmation/visit
  month described is comfortably inside both deadlines, this choice doesn't
  affect the outcome, so I left `hospitalization month` at a small,
  unremarkable value.

- **60 days ≈ 2 months, "within three months" ≈ "at most 3 months."** The
  schema is month-granularity throughout, so I converted Section 3.2.1's
  "sixty (60) days" recovery bar to 2 months, and read "commenced within
  three (3) months from the day ... unable to settle" as an inclusive AT
  MOST, matching the inclusive convention the given `` `no later than` ``
  helper already uses.

- **Q9 — "serving as a police officer at the time of hospitalization" is a
  status, not a cause.** The stated cause of the hospitalization is the
  claimant's son biting their ankle. Section 2.1 excludes injury "arising
  directly or indirectly out of ... service in the police" — being a police
  officer while getting bitten by your own child is not the injury arising
  out of police service. I set `causes` to `LIST Other`, deliberately
  omitting `` `Police service` ``, since `causes` per the schema represents
  what the hospitalization _arose out of_, not the claimant's occupation.

- **Q5 — no self-inflicted-injury exclusion exists in the given text.** Q5
  describes punching one's own face for show, with no fraud or
  misrepresentation. The excerpt in `fixtures/chubb-policy.txt` contains no
  clause excluding intentional or self-inflicted injury (Section 2.1 lists
  only five specific exclusions: skydiving, military/fire/police service, and
  age ≥ 80). Given the instruction to encode `covered` from the text actually
  provided, `covered` treats this claim the same as any other accidental
  injury not on that list. I did not invent a self-inflicted-injury exclusion
  that the source text doesn't state.

- **Fraud/misrepresentation timing.** `fraud month` and `misrepresentation
month` are `MAYBE NUMBER`, not plain booleans, so I read the schema as
  wanting a timing comparison rather than a bare presence check: fraud (or
  misrepresentation) cancels the policy from the moment it occurs onward, so
  it only defeats a claim whose hospitalization is at or after that month.
  I implemented this by reusing the given `` `no later than` `` helper
  against `hospitalization month` rather than against a fixed deadline
  (`` `no disqualifying fraud or misrepresentation` `` in `policy.l4`). This
  doesn't change any of the nine answers (all nine claims have both fields
  `NOTHING`), but it seemed like the more textually faithful general
  encoding of Section 1.2.

- **`agreement signed` / `premium paid month` are presence checks, not
  deadline checks.** The text ties premium payment to "the signing" (Section
  3.5.1) without giving it its own numeric deadline distinct from signing, so
  `covered` only checks that the premium has been paid at all (`isJust`),
  not any particular month. Per the standing preamble, both are satisfied in
  all nine claims (`agreement signed = TRUE`, `premium paid month = JUST 0`).

- **Arbitration/recovery fields are all set to their "nothing has happened"
  defaults in every claim** (`dispute arisen = FALSE`, the timing fields all
  `NOTHING`, `valid arbitration award issued = TRUE` although moot), since
  none of the nine questions concern a dispute, arbitration, or a recovery
  timeline. `covered` still encodes Section 3.2.1's arbitration and 60-day
  conditions in general, in case they matter for claims outside this set of
  nine.

- **Default `hospitalization ground`, `age`, and `causes` when a question
  doesn't mention them (Q2 in particular).** I used `` `Accidental injury` ``
  as a neutral default ground and `LIST Other` / `EMPTY` interchangeably for
  an unexcluded, unspecified cause — both behave identically under `covered`
  since the exclusion check in Section 2.1 only tests for the four named
  activities, never for `Other`.
