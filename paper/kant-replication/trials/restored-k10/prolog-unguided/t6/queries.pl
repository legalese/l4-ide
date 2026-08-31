% =====================================================================
%  queries.pl
%
%  Nine queries, one per benchmark question (fixtures/queries-blind.md).
%  Each q1..q9 succeeds iff the answer to its question is "yes", and
%  fails iff the answer is "no".
%
%  Standing preamble applied to every question (per fixtures/queries-
%  blind.md): assume all other conditions for the policy to apply are
%  met, and no other exclusion applies, and the agreement is signed
%  and the premium paid on time. Concretely, for every claim below
%  that means: the claimant is confined in a hospital in the United
%  States, a claim was duly made, and -- unless a question gives its
%  own timing -- the hospitalization is treated as having occurred
%  shortly (one month) after the effective date, comfortably inside
%  both the 7-month wellness-confirmation deadline and the 12-month
%  policy term, so section 1.3 is "still pending" rather than
%  breached. Facts a question does not mention (fraud, age, a
%  particular exclusion's triggering activity) are simply left
%  unasserted; because policy.pl declares every leaf predicate
%  dynamic, an unasserted fact fails cleanly rather than raising an
%  error, which is exactly "no such fact holds".
% =====================================================================

% The facts below are grouped by claim (one block per question) rather
% than by predicate, so clauses of the same leaf predicate are spread
% across the file. That is deliberate -- it keeps each question's
% facts together and readable -- so the predicates below are declared
% discontiguous to suppress SWI's (non-fatal) style warning about it.
:- discontiguous accidental_injury/1.
:- discontiguous sickness/1.
:- discontiguous age_at_hospitalization/2.
:- discontiguous confirmation_month/2.
:- discontiguous hospitalization_month/2.
:- discontiguous confined_in_hospital/1.
:- discontiguous hospital_in_us/1.
:- discontiguous confinement_days/2.
:- discontiguous claim_made/1.

% ---------------------------------------------------------------------
% Q1: hospitalized by burns suffered while doing my duty as a
% firefighter. The injury is causally tied to firefighter service, so
% exclusion 3.1.3 applies.
% ---------------------------------------------------------------------
accidental_injury(claim_1).
arose_from_firefighter_service(claim_1).
confined_in_hospital(claim_1).
hospital_in_us(claim_1).
confinement_days(claim_1, 1).
claim_made(claim_1).
hospitalization_month(claim_1, 1).

q1 :- covered(claim_1).

% ---------------------------------------------------------------------
% Q2: 78 years old at the time of hospitalization. 78 < 80, so the age
% exclusion (3.1.5) does not apply. Cause of hospitalization is
% unrelated to the question, so it is set to an unremarkable sickness.
% ---------------------------------------------------------------------
sickness(claim_2).
age_at_hospitalization(claim_2, 78).
confined_in_hospital(claim_2).
hospital_in_us(claim_2).
confinement_days(claim_2, 1).
claim_made(claim_2).
hospitalization_month(claim_2, 1).

q2 :- covered(claim_2).

% ---------------------------------------------------------------------
% Q3: hospitalized for pneumonia 5 months after the effective date;
% age 65. At month 5 the 7-month confirmation deadline has not yet
% arrived, so section 1.3 is "still pending" (no breach), and 65 < 80
% so the age exclusion does not apply.
% ---------------------------------------------------------------------
sickness(claim_3).
age_at_hospitalization(claim_3, 65).
hospitalization_month(claim_3, 5).
confined_in_hospital(claim_3).
hospital_in_us(claim_3).
confinement_days(claim_3, 1).
claim_made(claim_3).

q3 :- covered(claim_3).

% ---------------------------------------------------------------------
% Q4: hospitalized due to a fall while traveling abroad; confirmation
% of the wellness visit was given 8 months after the effective date --
% after the 7-month deadline, so section 1.3 has failed and the policy
% is canceled under 1.2, independent of the "abroad" fact. (The
% "abroad" fact is additionally modeled by not asserting
% hospital_in_us/1 for this claim -- see policy.pl's note on
% hospitalized/1 and NOTES.md.)
% ---------------------------------------------------------------------
accidental_injury(claim_4).
confirmation_month(claim_4, 8).
confined_in_hospital(claim_4).
confinement_days(claim_4, 1).
claim_made(claim_4).
% hospital_in_us(claim_4) is deliberately NOT asserted: the claimant
% was hospitalized abroad, not in a U.S. hospital.

q4 :- covered(claim_4).

% ---------------------------------------------------------------------
% Q5: hospitalized for punching my own face to show off for my
% friends; no fraud or misrepresentation. No exclusion in section 3.1
% covers self-inflicted or reckless injury, and fraud/misrepresentation
% is expressly denied, so nothing in the text blocks coverage.
% ---------------------------------------------------------------------
accidental_injury(claim_5).
confined_in_hospital(claim_5).
hospital_in_us(claim_5).
confinement_days(claim_5, 1).
claim_made(claim_5).
hospitalization_month(claim_5, 1).
% fraud_or_misrepresentation(claim_5) is deliberately NOT asserted.

q5 :- covered(claim_5).

% ---------------------------------------------------------------------
% Q6: injury sustained while skydiving; age 79; proof of the wellness
% visit given 6.5 months after the effective date. The skydiving
% exclusion (3.1.1) applies regardless of the (79 < 80) age fact and
% the (timely) 1.3 facts.
% ---------------------------------------------------------------------
accidental_injury(claim_6).
arose_from_skydiving(claim_6).
age_at_hospitalization(claim_6, 79).
confirmation_month(claim_6, 6.5).
confined_in_hospital(claim_6).
hospital_in_us(claim_6).
confinement_days(claim_6, 1).
claim_made(claim_6).

q6 :- covered(claim_6).

% ---------------------------------------------------------------------
% Q7: hospitalized for a heart attack; proof of the wellness visit
% submitted 2 months after the effective date; age 75. Sickness,
% timely section 1.3 compliance, no exclusion (75 < 80).
% ---------------------------------------------------------------------
sickness(claim_7).
age_at_hospitalization(claim_7, 75).
confirmation_month(claim_7, 2).
confined_in_hospital(claim_7).
hospital_in_us(claim_7).
confinement_days(claim_7, 1).
claim_made(claim_7).

q7 :- covered(claim_7).

% ---------------------------------------------------------------------
% Q8: injured in a military training exercise; hospitalization within
% the policy term; no fraud. The injury is causally tied to military
% service, so exclusion 3.1.2 applies regardless of the fraud denial.
% ---------------------------------------------------------------------
accidental_injury(claim_8).
arose_from_military_service(claim_8).
confined_in_hospital(claim_8).
hospital_in_us(claim_8).
confinement_days(claim_8, 1).
claim_made(claim_8).
hospitalization_month(claim_8, 1).
% fraud_or_misrepresentation(claim_8) is deliberately NOT asserted.

q8 :- covered(claim_8).

% ---------------------------------------------------------------------
% Q9: hospitalized because my son bit my ankle; proof of the wellness
% visit given 6 months after the effective date; I was serving as a
% police officer at the time of hospitalization. The ankle bite did
% not arise out of police service (it is a domestic incident), so the
% police exclusion (3.1.4) does not apply merely because of the
% claimant's occupation/status at that moment.
% ---------------------------------------------------------------------
accidental_injury(claim_9).
confirmation_month(claim_9, 6).
confined_in_hospital(claim_9).
hospital_in_us(claim_9).
confinement_days(claim_9, 1).
claim_made(claim_9).
% arose_from_police_service(claim_9) is deliberately NOT asserted: the
% ankle bite did not arise out of the claimant's police service.

q9 :- covered(claim_9).
