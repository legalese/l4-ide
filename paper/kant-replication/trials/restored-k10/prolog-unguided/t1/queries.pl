% =====================================================================
%  queries.pl -- the nine benchmark questions against policy.pl
% =====================================================================
%
%  Consulted after policy.pl. Each question below is encoded as a
%  small block of per-claim facts (the scenario) followed by a q<N>/0
%  predicate that succeeds exactly when the policy applies to that
%  scenario.
%
%  Standing preamble applied to every question (per queries-blind.md):
%  "Assuming all other conditions are met and no other exclusions
%  apply (where by 'other' I mean anything not referenced in the
%  query that follows)", and the agreement has been signed and the
%  premium paid on time. Concretely, this means: for any circumstance
%  a question does not mention, no fact is asserted for it, so
%  policy.pl's negation-as-failure defaults take over and treat that
%  circumstance as satisfied / not-excluded (see policy.pl's design
%  notes and NOTES.md). Where a covered peril is not itself the point
%  of the question (Q2), a neutral, unexceptionable peril (sickness)
%  is asserted so the underlying claim is otherwise unremarkable.
%
%  Facts are grouped per question below, so the same predicate (e.g.
%  injury/1) appears in several places non-contiguous in this file;
%  the discontiguous declarations below silence the resulting (and
%  harmless) SWI-Prolog warnings so that loading this file is silent.
% ---------------------------------------------------------------------

:- discontiguous injury/1.
:- discontiguous sickness/1.
:- discontiguous self_inflicted_intentionally/1.
:- discontiguous injury_arises_from/2.
:- discontiguous age_at_hospitalization/2.
:- discontiguous wellness_confirmation_month/2.
:- discontiguous hospitalization_month/2.
:- discontiguous hospitalized_outside_us/1.
:- discontiguous fraud_or_misrepresentation/1.

% ---------------------------------------------------------------------
%  Q1: "will my policy apply if I was hospitalized by burns suffered
%  while doing my duty as a firefighter?"
%
%  Burns are a bodily injury, and the phrase "while doing my duty as a
%  firefighter" is an explicit causal link to firefighting, so
%  Sec. 3.1(3) is asserted as triggered.
% ---------------------------------------------------------------------
injury(claim_1).
injury_arises_from(claim_1, firefighting).

q1 :- covered(claim_1).

% ---------------------------------------------------------------------
%  Q2: "will my policy apply if I am 78 years old at the time of
%  hospitalization?"
%
%  Only age is at issue; a neutral sickness peril is asserted so the
%  claim is otherwise unremarkable. 78 is below the Sec. 3.1(5)
%  threshold of 80.
% ---------------------------------------------------------------------
sickness(claim_2).
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% ---------------------------------------------------------------------
%  Q3: "will my policy apply if I was hospitalized for pneumonia 5
%  months after the policy's effective date, and my age at the time
%  of hospitalization is 65?"
%
%  Pneumonia is a sickness. Age 65 is below the Sec. 3.1(5) threshold.
%  The 5-month hospitalization timing is recorded for completeness; it
%  does not by itself threaten the Sec. 1.3 (7-month) or Sec. 4.6
%  (12-month) deadlines.
% ---------------------------------------------------------------------
sickness(claim_3).
age_at_hospitalization(claim_3, 65).
hospitalization_month(claim_3, 5).

q3 :- covered(claim_3).

% ---------------------------------------------------------------------
%  Q4: "will my policy apply if I was hospitalized due to a fall while
%  traveling abroad and I had given confirmation of my wellness visit
%  8 months after the policy's effective date?"
%
%  A fall is a bodily injury. "Hospitalized ... while traveling
%  abroad" is read as meaning the confinement itself took place
%  outside the US (Sec. 2.2 requires a US hospital) -- see NOTES.md
%  for the ambiguity this reading resolves. Confirmation at month 8 is
%  past the Sec. 1.3 7-month deadline.
% ---------------------------------------------------------------------
injury(claim_4).
hospitalized_outside_us(claim_4).
wellness_confirmation_month(claim_4, 8).

q4 :- covered(claim_4).

% ---------------------------------------------------------------------
%  Q5: "will my policy apply if I was hospitalized for punching my own
%  face to show off for my friends and I did not commit fraud or
%  misrepresentation?"
%
%  Facial trauma is a bodily injury, but it was the direct, intended
%  physical consequence of the claimant's own deliberate act against
%  themselves, so it is not "accidental" (see policy.pl's
%  accidental_injury/1 and NOTES.md). "Did not commit fraud" is
%  represented by simply not asserting fraud_or_misrepresentation/1.
% ---------------------------------------------------------------------
injury(claim_5).
self_inflicted_intentionally(claim_5).

q5 :- covered(claim_5).

% ---------------------------------------------------------------------
%  Q6: "will my policy apply if I was hospitalized due to an injury
%  sustained while skydiving, my age at the time of hospitalization
%  was 79, and proof of my wellness visit was provided 6.5 months
%  after the policy's effective date?"
%
%  The injury is accidental (skydiving is a voluntary activity, but an
%  injury sustained while doing it is not itself intended), and it
%  arises directly out of skydiving, triggering Sec. 3.1(1). Age 79 is
%  below the Sec. 3.1(5) threshold of 80. Confirmation at month 6.5 is
%  within the Sec. 1.3 deadline. This claim is excluded on the
%  skydiving ground regardless of the other two (favourable) facts.
% ---------------------------------------------------------------------
injury(claim_6).
injury_arises_from(claim_6, skydiving).
age_at_hospitalization(claim_6, 79).
wellness_confirmation_month(claim_6, 6.5).

q6 :- covered(claim_6).

% ---------------------------------------------------------------------
%  Q7: "will my policy apply if I was hospitalized for a heart attack,
%  proof of the wellness visit was submitted 2 months after the
%  policy's effective date, and my age at the time of hospitalization
%  was 75?"
%
%  A heart attack is a sickness. Confirmation at month 2 is well
%  within the Sec. 1.3 deadline. Age 75 is below the Sec. 3.1(5)
%  threshold.
% ---------------------------------------------------------------------
sickness(claim_7).
wellness_confirmation_month(claim_7, 2).
age_at_hospitalization(claim_7, 75).

q7 :- covered(claim_7).

% ---------------------------------------------------------------------
%  Q8: "will my policy apply if I was hospitalized after being injured
%  in a military training exercise, the hospitalization occurred
%  within the policy term, and I did not commit fraud?"
%
%  An injury from a military training exercise arises directly out of
%  service in the military, triggering Sec. 3.1(2). "Within the policy
%  term" and "did not commit fraud" are both stipulated as satisfied;
%  no hospitalization_month fact is needed to represent this, since
%  the absence of one already defaults policy_term_expired/1 and
%  overdue_without_confirmation/1 to false. Neither of those favourable
%  facts overrides the independent activity-based exclusion.
% ---------------------------------------------------------------------
injury(claim_8).
injury_arises_from(claim_8, military_service).

q8 :- covered(claim_8).

% ---------------------------------------------------------------------
%  Q9: "will my policy apply if I was hospitalized due to my son
%  biting me in the ankle, proof of my wellness visit was provided 6
%  months after the effective date, and I was serving as a police
%  officer at the time of hospitalization?"
%
%  Being bitten by one's own son is a bodily injury with no element of
%  self-infliction. Being a police officer is a status, not a cause:
%  nothing about the injury arises out of police service, so
%  Sec. 3.1(4) is deliberately NOT asserted (see NOTES.md and
%  policy.pl's comment on excluded/1). Confirmation at month 6 is
%  within the Sec. 1.3 deadline.
% ---------------------------------------------------------------------
injury(claim_9).
wellness_confirmation_month(claim_9, 6).

q9 :- covered(claim_9).
