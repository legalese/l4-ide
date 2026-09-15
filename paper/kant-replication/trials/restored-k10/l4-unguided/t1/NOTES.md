# Notes on this encoding

## Checks run

Only `l4 check` was run (typecheck only, no evaluation), from the trial directory:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
-> Check succeeded.

JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
-> Check succeeded.
```

`apply.l4`'s check transitively re-checks `policy.l4` via `IMPORT policy`. I did **not** run
`l4 run`, `#EVAL`, or otherwise evaluate any of the nine claims against `covered`, per the rules
for this trial.

## Design

`policy.l4` defines a `Claim` record (11 fields covering age, the nature of the medical event,
each of the four causal exclusions, US-hospital location, months-after-effective-date of both
the hospitalization and the wellness-visit confirmation, and a fraud/misrepresentation flag) and
a single top-level `` `covered` `` function of one `Claim` argument. `apply.l4` builds one `Claim`
literal per question (`q1`..`q9`) and evaluates `` `covered` `` on each. No claim data appears in
`policy.l4`.

All date-like facts other than age are modelled as a plain `NUMBER` of months after the policy's
effective date (per the task brief), so no `DATE`/`daydate` arithmetic is used anywhere.

## Judgement calls

1. **Two wellness-visit deadlines collapsed into one.** §1.3 actually names two deadlines: the
   confirmation must reach the insurer by month 7, and the visit itself must have occurred by
   month 6. Every query gives at most one relative-time figure for this fact ("confirmation/proof
   ... provided/submitted N months after the effective date"), never two, so I treat that single
   figure as answering the operative (month-7) deadline and do not attempt to separately recover
   a month-6 visit date that no query ever supplies. This does not change any of the nine answers:
   the only query where the two thresholds could disagree (Q6, at 6.5 months) is independently
   excluded on other grounds (skydiving), so its outcome is the same either way.

2. **§2.2 "hospital in the United States" vs. §4.1 "anywhere in the world".** §2.2 says the Daily
   Hospital Income Benefit is payable only for confinement "in a hospital in the United States";
   §4.1 says the policy "insures You ... anywhere in the world". I read these as answering
   different questions rather than as a straight contradiction: §4.1 says the triggering event
   (sickness/injury) is covered no matter where in the world it happens to the insured; §2.2
   separately conditions the specific daily-benefit payment on the confinement itself being in a
   US hospital. I encoded `` `benefit location requirement met` `` literally per §2.2, defaulting
   it to `TRUE` for every query except Q4 ("hospitalized due to a fall while traveling abroad"),
   where I read the hospitalization itself as occurring outside the US. This call is **not**
   outcome-determinative for any of the nine questions: Q4 is independently disqualified by its
   late wellness confirmation (see the file's own comment), so the answer is "No" either way.
   `source-defects.md` (excluded from this trial) may already document this tension; I did not
   read it.

3. **"Accidental injury" excludes a deliberate, self-inflicted act (Q5).** §3.1 lists five
   exclusions and none of them is "self-inflicted injury". Even so, I read the basic coverage
   grant in §2.1 ("sickness or accidental Injury") as requiring the injury itself to be
   accidental, and a punch the claimant deliberately threw at his own face is not an unintended,
   unforeseen event merely because the resulting hospitalization was unwanted — the causing act
   was voluntary. I modelled this as a fact ("injury was self-inflicted and intentional") that
   gates the §2.1 threshold rather than as a §3.1 exclusion, and set it `TRUE` only for Q5. This
   is the single most contestable call in this encoding: a reading that "accidental" refers only
   to the _result_ being unintended (not the _act_), and that an insurer confined to five stated
   exclusions cannot add a sixth by inference, would instead treat Q5 as covered. I judged the
   stricter reading more likely intended, partly because the query goes out of its way to negate
   fraud/misrepresentation specifically (a §1.2 cancellation ground) without addressing whether
   the injury is "accidental" (a §2.1 threshold question) — suggesting the two are meant to be
   argued separately.

4. **Exclusions require causation, not mere co-occurrence (Q9).** §3.1 excludes an event "causing
   sickness or accidental injury arising directly or indirectly **out of**" skydiving/military/
   firefighting/police service. I read this as requiring that the listed activity actually caused
   the injury, not merely that the claimant happened to be engaged in it at the time. Q9's
   claimant is "serving as a police officer at the time of hospitalization", but the injury (his
   son biting his ankle) has no causal connection to police work, so I set
   `` `arose from service in the police` `` to `FALSE` for q9 and the exclusion does not fire.
   The equivalent flags for Q1 (firefighter burns "while doing my duty") and Q8 (injury "in a
   military training exercise") are set `TRUE`, since those queries describe the activity itself
   as the source of the injury.

5. **Unrelated facts defaulted to non-disqualifying values**, per the standing preamble ("assuming
   all other conditions are met and no other exclusions apply ... anything not referenced in the
   query"). Concretely: age defaults to 30 when not stated; nature of the medical event defaults
   to `Sickness` when the query gives no cause at all (Q2); wellness-confirmation month defaults
   to `JUST 0`; months-after-effective-date of hospitalization defaults to a small in-term value
   (1, or a query-consistent value where one is implied, e.g. 6 for Q8's "within the policy
   term" and 8 for Q4 to stay consistent with its own stated confirmation month); fraud/
   misrepresentation defaults to `FALSE`; all four causal-exclusion flags default to `FALSE`; US
   hospital location defaults to `TRUE`.

6. **Not modelled as separate gating rules:** §2.3 ("a claim must be made ... setting out the
   basis ... and for there being no exclusion or cancellation") is procedural and adds no
   substantive condition beyond what §1.1/§3.1 already capture, so it is assumed satisfied rather
   than given its own `Claim` field, in the same spirit as the task's own instruction to assume
   the agreement signed and the premium paid. §4.2 (arbitration), §4.3 (New York law) and §4.4
   (US-currency payments) are dispute-resolution/boilerplate clauses that no query exercises, so
   no rule was derived from them (noted in a comment in `policy.l4`).
