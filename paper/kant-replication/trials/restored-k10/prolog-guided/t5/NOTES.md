# Notes

## Load check

Ran the permitted check:

```
swipl -q -g halt policy.pl queries.pl
```

Exit code 0, stdout empty, stderr empty — completely silent, confirmed by capturing stdout and
stderr separately. `q1`..`q9` were never called and `covered/1` was never invoked; only
consult-time loading was exercised, per the rules. `policy.pl` contains only `covered/1` plus its
helper rules and the two verbatim supporting predicates (`no_later_than/2`, `arose_out_of/2`); it
defines no `claim_*` facts. `queries.pl` asserts all 21 `claim_*` facts from `schema.md` for each
of `c1`..`c9` (verified by diff: the predicate set referenced in `policy.pl`, the set defined in
`queries.pl`, and the set listed in `schema.md` are identical). `:- discontiguous` directives were
added for the 21 `claim_*/2` predicates in `queries.pl` because facts are grouped by claim (as the
task's example shows), not by predicate, which would otherwise warn.

Note: `TASK.md`'s inline example comment says "all 18 facts", but `schema.md` — the document
`TASK.md` names as authoritative for the fact vocabulary — lists 21. I used all 21 listed in
`schema.md`, per the instruction to use "ALL OF, and ONLY" the facts it defines.

## Judgment calls in reading the policy (`policy.pl`)

- **§1.3 "still pending" vs. "satisfied in a timely fashion."** §1.1(3) requires, as of the
  hospitalization, that §1.3 be *either* still pending *or* already satisfied. I read "pending" as
  "the 7-month written-confirmation deadline has not yet arrived" (`hospitalization_month < 7`),
  which is true regardless of whether the wellness visit/confirmation have actually happened yet —
  they still have time. At `hospitalization_month >= 7` the deadline has arrived, so the claim must
  fall back on "satisfied": wellness visit ≤ month 6 with a qualified provider, and written
  confirmation ≤ month 7. The exact boundary (whether month 7 itself still counts as "pending") is
  not stated in the text; I resolved it as no-longer-pending at exactly 7, since "no later than the
  7th month anniversary" reads as the due date, not a moment still to come.
- **§1.2 cancelation for fraud/misrepresentation.** Modeled as absolute — if `claim_fraud_month` or
  `claim_misrepresentation_month` is a number at all, the policy is canceled — with no comparison
  to the hospitalization month. §1.2's language isn't time-qualified the way §1.3's is, so I didn't
  invent a timing test for it.
- **§4.6/§1.2 term expiry.** Modeled as `hospitalization_month > policy_term_months`, i.e. the last
  month of the term is still covered ("canceled at midnight ... on the last day of the policy
  term" reads as the last day itself being within the term).
- **§2.2 "in the United States" vs. §4.1.1 "anywhere in the world."** Read these as complementary
  rather than contradictory: the insured event (sickness/injury) can arise anywhere in the world
  (§4.1.1), but §2.2's Daily Hospital Income Benefit is explicitly conditioned on the *confinement*
  itself being in a US hospital. `benefit_triggered/1` requires `claim_confined_in_us_hospital(C,
  true)` as a hard condition. This is the most consequential reading in the whole encoding — see
  the Q4 note below.
- **§2.2 "not exceeding 365 days."** Modeled as a hard cap via `no_later_than(Days, 365)` on
  `claim_continuous_confinement_days` for the purposes of a boolean `covered/1` (rather than as a
  proration rule that would still pay for the first 365 days of a longer confinement). The schema
  gives one scalar fact for this, which reads more naturally as a threshold check than as a partial-
  payment calculation.
- **§4.2.1 "in no case ... before ... sixty (60) days after written proof of claim."** Treated as a
  general condition on any claim (not limited to disputes that went to arbitration), since the
  sentence reads "in no case," not "if there is a dispute." Converted 60 days to 2 months to match
  the schema's month-denominated facts, consistent with the granularity used elsewhere (e.g. the
  schema's own 6.5-month example). If `claim_recovery_sought_month` is `none`, the check is
  vacuously satisfied (recovery was never sought, so nothing can be premature).
- **§4.2.1 arbitration.** When `claim_dispute_arisen` is `false`, arbitration is moot. When `true`,
  extinguishment (complete loss of the right to claim) is tested only once
  `claim_unable_to_settle_month` is known — mirroring the same "not yet failed while still pending"
  logic used for §1.3 — and, independently, a valid arbitration award is required as a condition
  precedent to liability whenever a dispute exists at all.

## Judgment calls in reading the nine questions (`queries.pl`)

Per the task's instruction, facts not mentioned by a question were set favorably (true/none/well
within any deadline) so only the mentioned facts are load-bearing. Choices worth flagging:

- **Hospitalization month when only a confirmation month is given (Q4, Q6, Q7, Q9).** These
  questions state when wellness-visit confirmation was given but not when the hospitalization
  itself occurred. I set `hospitalization_month` to `max(7, confirmation_month)` so the given
  confirmation fact is actually evaluated against the real §1.3 "satisfied" deadline test, rather
  than being made moot by the "still pending" branch (which holds for any hospitalization month
  under 7 regardless of confirmation timing). A stricter literal reading of "set every fact
  unrelated to the question favorably" could instead default `hospitalization_month` low
  regardless — I judged that reading would silently discard the very fact the question is
  supplying, so I did not take it. This is the single biggest interpretive call in the file.
- **Q4 — "traveling abroad."** Read as the confinement itself occurring outside the US, so
  `claim_confined_in_us_hospital(c4, false)` — the only claim where this fact is not the favorable
  default. This is a direct, explicit fact in the question's text, not an "unrelated" one.
- **Q5 — "punching my own face to show off for my friends."** Classified
  `claim_hospitalization_ground(c5, accidental_injury)`, on the reading that the *harm* was
  unintended (a stunt that went wrong) even though the *act* was voluntary — the standard
  insurance-law sense of "accident." This is the most debatable ground classification of the nine;
  a reading that treats deliberate self-inflicted acts as `neither` would go the other way.
- **Q9 — "serving as a police officer at the time of hospitalization."** The bite came from "my
  son," with no causal link to police duty, so `claim_causes(c9, [other])`, not `[police_service]`.
  §3.1 excludes injury arising "directly or indirectly out of ... service in the police," which is
  about causal origin, not the claimant's occupation or status at the time. Treated the "police
  officer" detail as informational, not a cause.
- **Causal vs. status mentions generally.** Where a question ties the injury causally to an
  activity ("while doing my duty as a firefighter," "in a military training exercise," "while
  skydiving"), I included the matching excluded cause in `claim_causes`. Where an occupation/status
  is mentioned without a causal link (Q9), I did not.
- **Ground classification for the rest:** pneumonia (Q3) and heart attack (Q7) → `sickness`; burns
  (Q1), a fall (Q4), an injury while skydiving (Q6), a military-training injury (Q8), and a bite
  (Q9) → `accidental_injury`. Q2 gives no cause at all, so I used `sickness` as an arbitrary,
  coverage-neutral filler (either value works identically under `qualifying_ground/1`).
- **Numeric filler values** used when a fact is not mentioned at all: age 40, hospitalization month
  3, wellness-visit month 3, written-confirmation month 3, premium-paid month 0, written-proof-of-
  claim month 0, continuous-confinement days 1, policy term 12 months — all chosen to be
  unambiguously favorable to coverage and held constant across claims for consistency.
