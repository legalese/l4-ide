# Notes on this encoding

## Checks run

Ran, from the trial directory root:

```
JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4
JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4
```

Both printed `Check succeeded.` I did **not** run `l4 run`, did not evaluate any `#EVAL`
directive, and did not otherwise test `covered` against the nine questions, per the task rules.
`l4 check` only typechecks; it does not evaluate.

## Judgement calls in `policy.l4`

- **1.1(3) "still pending or has been satisfied in a timely fashion."** There is no field
  representing "the current date/time of assessment" separate from the events themselves, so
  there is no way to distinguish "the 7-month deadline hasn't arrived yet" from "the deadline
  passed and nothing was filed." I collapsed the disjunction to "has been satisfied": condition
  1.3 is treated as failing whenever the wellness-visit or written-confirmation fields are
  `NOTHING` or fall outside their respective 6-/7-month windows. This means a Claim always has to
  affirmatively supply timely wellness-visit facts to keep the policy in effect, which is what the
  `apply.l4` claims do for every question that isn't itself about that condition.

- **2.2's 365-day cap.** "for a period not exceeding three hundred and sixty-five (365) days"
  reads as a cap on how many days are *payable*, not a condition that voids the whole claim for a
  longer stay. `covered` therefore only requires `continuous confinement days` to be present and
  positive; it does not additionally require `<= 365`. A stay of, say, 400 days would still leave
  a benefit payable for the first 365, so it stays "covered" under this reading.

- **Territorial scope, 2.2 vs 4.1.** 4.1 says the policy insures the person "anywhere in the
  world," but 2.2 says the Daily Hospital Income Benefit is payable only for confinement "in a
  hospital in the United States." I read these as compatible rather than contradictory: 4.1
  fixes where the *insured event* may occur (you can be hurt anywhere and still be within the
  policy's scope), while 2.2 is a narrower, benefit-specific condition that the confining hospital
  itself be in the US. `covered` enforces `confined in us hospital` as a hard requirement. This is
  a real tension in the source text and a different reading (territorial scope overrides the
  benefit clause) is defensible; I did not find a textual basis to prefer it.

- **Fraud / misrepresentation timing.** `fraud month` and `misrepresentation month` are read as
  "did this happen at all" (any `JUST` value cancels the policy), not compared against any
  deadline — the contract attaches no timing condition to this cancellation trigger, unlike the
  wellness-visit clauses.

- **Premium payment.** 4.5 says the premium is paid "in one lump sum at the signing of the
  policy," with no month-based deadline analogous to the wellness-visit ones. `premium paid` is
  therefore just "is `premium paid month` present at all," not compared against a limit.

- **Arbitration's three-month clock (4.2.1).** Where a dispute has arisen but the parties have
  not yet reached the "unable to settle" impasse (`unable to settle month = NOTHING`), I treated
  the three-month arbitration-commencement clock as not yet running (vacuously satisfied) rather
  than as already breached. Only once an impasse date is on record does lateness become
  checkable.

- **The 60-day no-action clause (4.2.1), unit mismatch.** The clause is stated in days ("sixty
  (60) days"), but the schema's fields are month-granularity (`written proof of claim month`,
  `recovery sought month`). I approximated 60 days as 2 months (`recovery sought month AT LEAST
  written proof of claim month PLUS 2`). This is a coarser test than the contract's own wording;
  I did not see a way to do better without a day-granularity field.

## Judgement calls in `apply.l4`

- **Q5** (punching one's own face "to show off for my friends"): coded `hospitalization ground`
  as `Neither`. A deliberate act performed on purpose is not "accidental" in the ordinary sense,
  even though the resulting injury's severity may not have been intended — so this is neither a
  sickness nor an accidental injury under the policy's own vocabulary.

- **Q4** (hospitalized "while traveling abroad"): read this as the confinement itself having
  occurred outside the United States, so `confined in us hospital = FALSE`. The question does not
  say in so many words where the hospital was, but "traveling abroad" most naturally describes
  being treated at the place one is traveling in.

- **Q8** (injured "in a military training exercise"): coded the cause as `Military service`. The
  exclusion reaches injury "arising directly or indirectly" out of military service, and a
  training exercise is part of that service.

- **Q9** (son bit claimant's ankle; claimant "was serving as a police officer at the time"):
  coded the cause as `Other`, not `Police service`. The exclusion requires the injury to arise out
  of the service; merely holding the job at the moment of an unrelated domestic injury (a child's
  bite) supplies no causal link to police duties.

- For every question, every `Claim` field not put in issue by that question's text was set to a
  value that keeps every other coverage condition satisfied and no exclusion triggered, per the
  standing preamble ("assuming all other conditions are met and no other exclusions apply").
  Where a question's own wording only partially determines a field (e.g. Q6's "proof of my
  wellness visit was provided 6.5 months after..." fixes `written confirmation month` but says
  nothing about the underlying visit date), the unstated part was filled in favorably (a wellness
  visit month within the 6-month window).

## Schema-field usage

`covered` and its helpers reference all 21 `Claim` fields listed in `schema.md`, and no others;
no new fields were added to `Claim`. Both given helpers (`` `no later than` `` and
`` `arose out of` ``) are used verbatim and are not redefined.
