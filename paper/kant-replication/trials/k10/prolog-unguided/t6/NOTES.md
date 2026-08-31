# Notes on this encoding

## Load check

Ran, exactly as permitted:

```
swipl -q -g halt policy.pl queries.pl
```

Output was empty and the exit code was `0` — a silent, clean load. (Confirmed with `echo
$?` immediately after.) I did not run `q1`..`q9` or otherwise query the loaded program, per
the rules.

Before writing the real files I also sanity-checked two SWI-Prolog behaviours on throwaway
files outside the trial directory (under the session scratchpad, since deleted), because
getting them wrong would have broken "loads silently" or "no procedure does not exist errors
when actually queried":

1. A predicate declared `:- dynamic` but never given a clause anywhere in either file is
   safely callable (fails cleanly) rather than raising an existence error, including when
   called through negation (`\+`). This is what lets `policy.pl` reference facts (e.g.
   `wellness_visit_month/2`, `fraud_or_misrepresentation/1`) that no single one of the nine
   questions ever needs to assert.
2. `:- dynamic` alone does **not** suppress SWI's "clauses ... are not together in the
   source-file" warning when a predicate's clauses are scattered across non-adjacent
   blocks (which they are in `queries.pl`, since I grouped facts by question rather than
   by predicate). A separate `:- discontiguous` directive is needed and does suppress it.
   Both files reflect the outcome of that check.

## Judgement calls

**Q5 (punching my own face to show off for my friends).** The base coverage grant in s.1.1
is for hospitalization "for sickness or accidental injury." I read a deliberate,
self-inflicted act performed for show as neither a sickness nor an *accidental* injury — the
injury may not have been the point, but the act that caused it was intentional, not
accidental, in the ordinary insurance sense of that word. On that reading the claim never
gets as far as the s.2 exclusion list at all (which, notably, has no self-inflicted-injury
item of its own) and I encoded `q5` to fail. This is genuinely arguable: someone reading
"accidental" as qualifying the *injury* rather than the *act* (i.e. you meant to punch
yourself but didn't mean to end up hospitalized) would encode this the other way, and the
absence of any explicit self-inflicted-injury exclusion in s.2 is some evidence for that
reading. I also take "I did not commit fraud or misrepresentation" in the question at face
value and simply never assert `fraud_or_misrepresentation(claim_5)` — that clause forecloses
the s.1.2 cancelation route, not the s.1.1 base-grant question the rest of my answer turns
on.

**Q9 (son biting me in the ankle; serving as a police officer at the time).** s.2.1's
chapeau excludes an event "causing sickness or accidental injury arising directly or
indirectly **out of**" the four listed activities/services. I read that as requiring a
causal link between the injury and the service, not merely that the claimant held the job
at the time of the injury — in contrast to s.2.1(5)'s age exclusion, which is phrased as a
bare status/threshold ("if your age ... is equal to or greater than 80") with no causal
element at all. Since a bite on the ankle from the claimant's own son has no stated
connection to police duties, I did not assert `arises_out_of(claim_9, police_service)`, and
`q9` succeeds. The textual contrast between the causal phrasing of (1)-(4) and the bare
status phrasing of (5) is what I'm relying on; a reader who thinks "at the time of
hospitalization" was meant to carry the same status-only force throughout s.2.1 would
disagree and exclude this claim.

**s.1.3's "still pending" language (s.1.1(3)).** I did not model any race between the
hospitalization date and the two s.1.3 deadlines (i.e., whether the hospitalization fell
before or after a deadline breach became final). The task brief says dates in a query are
always relative to the effective date and that there is never a need to compute elapsed
time *between two dates*, which I read as ruling out exactly that kind of cross-comparison.
Instead each s.1.3 sub-deadline is checked only against its own fixed threshold (visit by
month 6, confirmation by month 7), independent of when the hospitalization occurred. In
practice this only matters for Q3, where the hospitalization occurs at month 5 with no
wellness facts mentioned at all — I treated s.1.3 as simply not in issue there (still
pending, in the contract's own words), rather than trying to reason about whether month 5
is "early enough."

**s.1.3's two sub-deadlines, when a question gives only one number.** s.1.3 actually
imposes two dates: the wellness visit itself must occur by month 6, and written
confirmation of it must be *supplied* by month 7. Every question that mentions this
(Q4, Q6, Q7, Q9) gives a single figure phrased as the visit being "provided," "submitted,"
or (Q4) "confirm[ed]" at month N. I read all of these as describing the **supply/confirm**
act (the language tracks "you will supply us with written confirmation ... of a wellness
visit" in s.1.3 most directly), and so asserted each as `wellness_confirmation_month/2`
only, leaving `wellness_visit_month/2` unasserted for every claim (i.e. defaulting to "not
shown to be late," per the standing preamble's "assume anything not referenced in the
query is met"). `policy.pl` defines both thresholds so a future query that separately
specifies the underlying visit date can use it, but no one of the nine needs it.

**Missing Section 4 and the body of Section 5.** The supplied contract text has no
"Section 4" of any kind, and both s.3.5 ("[t]he premium described in Section 5 below") and
s.3.6 ("policy term ... described in Section 5 below") point forward to a Section 5 whose
actual text is not present in the fixture I was given. There is consequently no schedule of
benefits/amounts anywhere in the document. None of the nine questions asks about benefit
amounts, so this did not block encoding `covered/1`, and s.3.6's own prose independently
states the term ("will last for a period of one year from that date"), which is what
`policy_term_expired/1` uses. I'm flagging the gap rather than silently treating the
document as complete.

**Territorial scope (Q4's "traveling abroad").** s.3.1 grants unconditional worldwide,
24-hour coverage, so "traveling abroad" needs no fact of its own — there is nothing for it
to trigger. `territorial_scope_ok/1` is included in `covered/1` as a documented no-op
rather than silently dropping s.3.1 from the encoding.

**s.3.2 (arbitration) defined but not wired into `covered/1`.** I read the arbitration/
time-bar/60-day-moratorium provisions as conditions on a policyholder's right to *litigate
or recover on* a claim that is actually in dispute — a procedural layer on top of, and
analytically separate from, the substantive "is this event covered" question the nine
benchmark questions all ask. I fully defined the relevant predicates
(`claim_extinguished_for_late_arbitration/1`, `arbitration_condition_precedent_met/1`) for
completeness, but none of the nine questions puts a dispute in issue, so `covered/1` does
not consult them. s.3.3 (New York law) and s.3.4 (US currency) get no predicate at all, for
the same reason one level further: they don't gate coverage even procedurally.

**Numeric edge cases**, stated for the record since they're easy to get backwards:
age exclusion is `Age >= 80` ("equal to or greater than"); both s.1.3 deadlines are
"no later than," so exactly 6 or exactly 7 months is timely (the failure conditions are
strict `> 6` / `> 7`); the one-year term is treated as still current through and including
month 12 (failure condition `> 12`).
