% ============================================================
% queries.pl
%
% Nine claim scenarios (Kant et al. 2025, Appendix A.2), one per
% question. Each qN/0 succeeds iff the answer to question N is
% "yes" (the policy applies) and fails iff the answer is "no".
%
% Per the standing preamble that accompanies every question --
% "Assuming all other conditions are met and no other exclusions
% apply (where by 'other' I mean anything not referenced in the
% query that follows)" -- only the facts explicitly given by a
% question are asserted for that question's claim. Every other
% optional fact from policy.pl is left unasserted, which, by
% construction of policy.pl's rules, is exactly the value that
% keeps every unrelated condition satisfied and every unrelated
% exclusion untriggered.
%
% All timings below are given in months relative to the policy's
% effective date, per the task brief; only the claimant's age is
% an absolute value.
% ============================================================

% The claim facts below are grouped by question (one block per
% qN), not by predicate, so that each question's facts read as a
% single unit. These three predicates each recur across several
% blocks, so they are declared discontiguous up front.
:- discontiguous(hospitalized/1).
:- discontiguous(age_at_hospitalization/2).
:- discontiguous(wellness_confirmation_month/2).

% ------------------------------------------------------------
% Q1: hospitalized for burns suffered while doing my duty as a
% firefighter.
% ------------------------------------------------------------
hospitalized(claim_1).
caused_by_firefighting_service(claim_1).

q1 :- covered(claim_1).

% ------------------------------------------------------------
% Q2: 78 years old at the time of hospitalization.
% ------------------------------------------------------------
hospitalized(claim_2).
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% ------------------------------------------------------------
% Q3: hospitalized for pneumonia 5 months after the policy's
% effective date; age 65 at the time of hospitalization.
% ------------------------------------------------------------
hospitalized(claim_3).
hospitalization_month(claim_3, 5).
age_at_hospitalization(claim_3, 65).

q3 :- covered(claim_3).

% ------------------------------------------------------------
% Q4: hospitalized due to a fall while traveling abroad; had
% given confirmation of the wellness visit 8 months after the
% policy's effective date.
% ------------------------------------------------------------
hospitalized(claim_4).
wellness_confirmation_month(claim_4, 8).

q4 :- covered(claim_4).

% ------------------------------------------------------------
% Q5: hospitalized for punching my own face to show off for my
% friends; did not commit fraud or misrepresentation.
% ------------------------------------------------------------
hospitalized(claim_5).
% fraud_or_misrepresentation(claim_5) is deliberately NOT
% asserted -- that omission is exactly how "I did not commit
% fraud or misrepresentation" is represented under this
% encoding's closed-world convention. Section 3's General
% Exclusions do not list self-inflicted or intentionally caused
% injury as an excluded cause, so, absent fraud, an accidental
% injury from this stunt is not excluded by the text of the
% policy.

q5 :- covered(claim_5).

% ------------------------------------------------------------
% Q6: hospitalized due to an injury sustained while skydiving;
% age 79 at the time of hospitalization; proof of the wellness
% visit was provided 6.5 months after the policy's effective
% date.
% ------------------------------------------------------------
hospitalized(claim_6).
caused_by_skydiving(claim_6).
age_at_hospitalization(claim_6, 79).
wellness_confirmation_month(claim_6, 6.5).

q6 :- covered(claim_6).

% ------------------------------------------------------------
% Q7: hospitalized for a heart attack; proof of the wellness
% visit was submitted 2 months after the policy's effective date;
% age 75 at the time of hospitalization.
% ------------------------------------------------------------
hospitalized(claim_7).
wellness_confirmation_month(claim_7, 2).
age_at_hospitalization(claim_7, 75).

q7 :- covered(claim_7).

% ------------------------------------------------------------
% Q8: hospitalized after being injured in a military training
% exercise; the hospitalization occurred within the policy term;
% did not commit fraud.
% ------------------------------------------------------------
hospitalized(claim_8).
caused_by_military_service(claim_8).
% "the hospitalization occurred within the policy term" is
% represented by NOT asserting hospitalization_month/2 at all:
% policy_term_expired/1 only fires when a hospitalization_month
% fact places the hospitalization beyond month 12, so omitting it
% already encodes "within the policy term". fraud_or_misrepresentation(claim_8)
% is likewise deliberately not asserted, representing "I did not
% commit fraud".

q8 :- covered(claim_8).

% ------------------------------------------------------------
% Q9: hospitalized because my son bit me in the ankle; proof of
% my wellness visit was provided 6 months after the effective
% date; I was serving as a police officer at the time of
% hospitalization.
% ------------------------------------------------------------
hospitalized(claim_9).
wellness_confirmation_month(claim_9, 6).
% caused_by_police_service(claim_9) is deliberately NOT asserted:
% the claimant's son biting their ankle has no causal connection
% to their service as a police officer. Section 3.1 excludes a
% sickness or injury that arises "directly or indirectly out of"
% the named service, not merely one that happens to occur while
% the claimant holds that occupation.

q9 :- covered(claim_9).
