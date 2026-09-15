# Notes on this encoding

## Checks run

Ran, from the trial directory:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
```

Both printed `Check succeeded.` with no further output. `l4 check` typechecks only; it does not
evaluate `#EVAL` directives, so the nine questions were not run or otherwise tested against the
encoding, per the task rules.

## Judgement calls

- **Q5 (punching my own face to show off) -- `hospitalization ground IS Neither`.** The policy's
  trigger (2.1) is "sickness or accidental Injury"; §3.1's exclusion list has nothing about
  self-inflicted or intentional acts. I read "accidental" in its ordinary sense (unintended,
  by chance) rather than importing an unstated "no intentional acts" exclusion: deliberately
  punching one's own face is a voluntary act whose resulting injury is an expected, not
  unintended, consequence, so I classified it as neither a sickness nor an accidental injury.
  This is the single most consequential judgement call in the file -- an equally defensible
  reading treats the _result_ as unintended (the "accidental means vs. accidental result"
  split in real accident-insurance doctrine) and would classify it as `Accidental injury`,
  which §3.1 does not otherwise exclude.

- **Q9 (son biting my ankle while I was serving as a police officer) -- `causes IS LIST
Other`, not `` `Police service` ``.** §3.1 excludes injury "arising directly or indirectly
  out of ... service in the police" -- a causal test, not a status test. Being on duty as a
  police officer at the moment of an unrelated domestic injury does not mean the injury arose
  out of that service, so I did not add `` `Police service` `` to `causes`.

- **Q4 (fall while traveling abroad; confirmation given 8 months after the effective date).**
  Two fields not literally stated were set to track the one fact that _is_ stated, rather than
  to whatever would most favour coverage:

  - `confined in us hospital IS FALSE`, reading "hospitalized ... while traveling abroad" as
    hospitalization at the foreign location, not a US hospital. (§4.1's "insures You ...
    anywhere in the world" is the territorial scope of the risk, not a substitute for §2.2's
    separate requirement that the _confinement_ be in a US hospital -- the two clauses do
    different jobs, and I kept them distinct.)
  - `hospitalization month IS 8`, matching the one date given in the query. TASK.md directs
    setting unrelated fields so that "all conditions for coverage are satisfied" -- but
    `hospitalization month` is not really unrelated here: my `covered` function treats
    condition 1.3 as still "pending" (and so harmless) whenever hospitalization precedes the
    7-month mark, so picking an early month would have silently defeated the very fact the
    question supplies. I anchored it to the stated month instead of picking a coverage-favouring
    one, on the view that the question means to test the consequence of the late confirmation.

- **`misrepresentation month` stands for two things.** §1.2 cancels for "fraud, or any
  misrepresentation or material withholding of any information"; the schema has one field for
  misrepresentation and none for withholding. `misrepresentation month` is read as covering
  both misrepresentation and material withholding, since the schema gives no way to keep them
  apart.

- **"Condition 1.3 is still pending" is keyed to `hospitalization month LESS THAN 7`.** 1.3
  bundles a visit due by month 6 inside a confirmation due by month 7; I treated the outer
  (7-month) deadline as the point at which the whole compound condition either has been met or
  has not, and "still pending" as simply "that point hasn't arrived yet as of the
  hospitalization". None of the nine questions turn on the exact boundary (hospitalization at
  month 7 precisely), so this is untested by the fixture but recorded as a modelling choice.

- **The 60-day proof-of-claim wait (§4.2.1) is converted to 2 months** (60 / 30), since every
  other timing field in the schema is in months. `written proof of claim month` and
  `recovery sought month` are not referenced by any of the nine questions, so this conversion
  is not exercised by the fixture either, but `covered` still encodes it for fidelity to "all
  relevant criteria from the policy."

- **`continuous confinement days` must be present and positive.** 2.2 pays "for each (24 hour)
  day of continuous confinement," so `covered` requires some positive count rather than
  `NOTHING`; it does not gate on the 365-day cap, since exceeding the cap limits how many days
  are paid rather than voiding the claim entirely, and `covered` is a yes/no gate, not a payment
  calculation.

- **Fields genuinely unrelated to a given question** (e.g. arbitration/dispute fields and
  `written proof of claim month`/`recovery sought month` for all nine queries; wellness-visit
  figures for queries that don't mention them) were set to values that satisfy every condition
  and trigger no exclusion, per TASK.md -- e.g. `dispute arisen IS FALSE`, wellness visit and
  confirmation given early and by a qualified provider, `policy term months IS 12` (matching
  §4.6's one-year term).
