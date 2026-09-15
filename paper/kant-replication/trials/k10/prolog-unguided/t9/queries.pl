% =====================================================================
%  Per-claim facts and queries q1..q9
% =====================================================================
%
%  Standing preamble applied to every question (per queries-blind.md):
%  assume all other conditions are met and no other exclusions apply,
%  i.e. anything not mentioned in a question is set to whichever value
%  keeps the policy applying. Per policy.pl's design, that means: for
%  anything not mentioned below, no fact is asserted at all, and the
%  dynamic declarations in policy.pl make that default to "does not
%  block coverage".
%
%  Also per the standing instructions: the agreement has been signed
%  and the premium paid on time (not modeled -- see policy.pl).
%
%  claim_1 .. claim_9 correspond to Q1 .. Q9 in queries-blind.md.
%
%  Facts are grouped by claim (question) rather than by predicate, so
%  each of the per-claim predicates below is declared discontiguous to
%  match -- there is no missing clause, just an intentional layout.

:- discontiguous sickness/1.
:- discontiguous accidental_injury/1.
:- discontiguous hospitalization_time/2.
:- discontiguous age_at_hospitalization/2.
:- discontiguous confirmation_time/2.
:- discontiguous arises_out_of/2.

% ---------------------------------------------------------------------
% Q1. Hospitalized by burns suffered while doing my duty as a
%     firefighter.
% ---------------------------------------------------------------------
%  The injury arose directly out of service as a firefighter --
%  Section 2.1(3).
accidental_injury(claim_1).
arises_out_of(claim_1, firefighter_service).

q1 :- covered(claim_1).

% ---------------------------------------------------------------------
% Q2. 78 years old at the time of hospitalization.
% ---------------------------------------------------------------------
%  No cause of hospitalization is given; the question is only about
%  age, so a neutral qualifying event is asserted to stand in for
%  "some unspecified sickness" -- this is not itself excluded and is
%  not what the question is testing.
sickness(claim_2).
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% ---------------------------------------------------------------------
% Q3. Hospitalized for pneumonia 5 months after the effective date;
%     age 65 at the time of hospitalization.
% ---------------------------------------------------------------------
sickness(claim_3).
hospitalization_time(claim_3, 5).
age_at_hospitalization(claim_3, 65).

q3 :- covered(claim_3).

% ---------------------------------------------------------------------
% Q4. Hospitalized due to a fall while traveling abroad; confirmation
%     of the wellness visit given 8 months after the effective date.
% ---------------------------------------------------------------------
%  Being abroad triggers no exclusion (Section 3.1.1: the policy
%  insures the claimant anywhere in the world). The confirmation was
%  supplied after the Section 1.3 deadline of 7 months, so the
%  wellness condition was not satisfied in a timely fashion.
accidental_injury(claim_4).
confirmation_time(claim_4, 8).

q4 :- covered(claim_4).

% ---------------------------------------------------------------------
% Q5. Hospitalized for punching my own face to show off for my
%     friends; no fraud or misrepresentation committed.
% ---------------------------------------------------------------------
%  No fact is asserted for fraud/misrepresentation, which (via the
%  dynamic declaration in policy.pl) already defaults to "did not
%  occur" -- matching what the question states outright. See NOTES.md
%  for the judgment call on treating this as an accidental injury.
accidental_injury(claim_5).

q5 :- covered(claim_5).

% ---------------------------------------------------------------------
% Q6. Hospitalized due to an injury sustained while skydiving; age 79
%     at the time of hospitalization; proof of the wellness visit
%     provided 6.5 months after the effective date.
% ---------------------------------------------------------------------
accidental_injury(claim_6).
arises_out_of(claim_6, skydiving).
age_at_hospitalization(claim_6, 79).
confirmation_time(claim_6, 6.5).

q6 :- covered(claim_6).

% ---------------------------------------------------------------------
% Q7. Hospitalized for a heart attack; proof of the wellness visit
%     submitted 2 months after the effective date; age 75 at the time
%     of hospitalization.
% ---------------------------------------------------------------------
sickness(claim_7).
confirmation_time(claim_7, 2).
age_at_hospitalization(claim_7, 75).

q7 :- covered(claim_7).

% ---------------------------------------------------------------------
% Q8. Hospitalized after being injured in a military training
%     exercise; hospitalization occurred within the policy term; no
%     fraud committed.
% ---------------------------------------------------------------------
accidental_injury(claim_8).
arises_out_of(claim_8, military_service).
hospitalization_time(claim_8, 6).

q8 :- covered(claim_8).

% ---------------------------------------------------------------------
% Q9. Hospitalized due to my son biting me in the ankle; proof of the
%     wellness visit provided 6 months after the effective date;
%     serving as a police officer at the time of hospitalization.
% ---------------------------------------------------------------------
%  Being a police officer AT THE TIME of the injury is a fact about
%  the claimant's status, not about what caused the injury -- the
%  injury was caused by a family incident (the claimant's son biting
%  him), not by police service. So arises_out_of(claim_9,
%  police_service) is deliberately NOT asserted; see NOTES.md.
accidental_injury(claim_9).
confirmation_time(claim_9, 6).

q9 :- covered(claim_9).
