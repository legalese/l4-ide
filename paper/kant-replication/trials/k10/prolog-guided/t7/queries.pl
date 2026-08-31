% queries.pl
%
% q1/0 .. q9/0 succeed exactly when the answer to the corresponding
% question in inputs/queries-blind.md is "yes", per policy.pl's
% covered/1. Each query defines all 18 claim_*/2 facts for its own claim
% (c1..c9); facts not implicated by the question's narrative are set to
% values that satisfy every other condition and trigger no exclusion, per
% the standing preamble ("assuming all other conditions are met and no
% other exclusions apply") and the paper's stipulation that the agreement
% is signed and the premium paid on time.
%
% See NOTES.md for the judgement calls behind the choices below.

:- discontiguous claim_agreement_signed/2.
:- discontiguous claim_premium_paid_month/2.
:- discontiguous claim_hospitalization_month/2.
:- discontiguous claim_hospitalization_ground/2.
:- discontiguous claim_age_at_hospitalization/2.
:- discontiguous claim_causes/2.
:- discontiguous claim_fraud_month/2.
:- discontiguous claim_misrepresentation_month/2.
:- discontiguous claim_wellness_visit_month/2.
:- discontiguous claim_wellness_visit_provider_qualified/2.
:- discontiguous claim_written_confirmation_month/2.
:- discontiguous claim_dispute_arisen/2.
:- discontiguous claim_unable_to_settle_month/2.
:- discontiguous claim_arbitration_commenced_month/2.
:- discontiguous claim_valid_arbitration_award_issued/2.
:- discontiguous claim_written_proof_of_claim_month/2.
:- discontiguous claim_recovery_sought_month/2.
:- discontiguous claim_policy_term_months/2.

% Q1: hospitalized by burns suffered while doing my duty as a firefighter.
q1 :- covered(c1).
claim_agreement_signed(c1, true).
claim_premium_paid_month(c1, 0).
claim_hospitalization_month(c1, 3).
claim_hospitalization_ground(c1, accidental_injury).
claim_age_at_hospitalization(c1, 40).
claim_causes(c1, [firefighting]).
claim_fraud_month(c1, none).
claim_misrepresentation_month(c1, none).
claim_wellness_visit_month(c1, 3).
claim_wellness_visit_provider_qualified(c1, true).
claim_written_confirmation_month(c1, 3).
claim_dispute_arisen(c1, false).
claim_unable_to_settle_month(c1, none).
claim_arbitration_commenced_month(c1, none).
claim_valid_arbitration_award_issued(c1, false).
claim_written_proof_of_claim_month(c1, 0).
claim_recovery_sought_month(c1, none).
claim_policy_term_months(c1, 12).

% Q2: 78 years old at the time of hospitalization (ground/cause unstated;
% neutral choices below since the question is solely about the age
% threshold).
q2 :- covered(c2).
claim_agreement_signed(c2, true).
claim_premium_paid_month(c2, 0).
claim_hospitalization_month(c2, 3).
claim_hospitalization_ground(c2, sickness).
claim_age_at_hospitalization(c2, 78).
claim_causes(c2, [other]).
claim_fraud_month(c2, none).
claim_misrepresentation_month(c2, none).
claim_wellness_visit_month(c2, 3).
claim_wellness_visit_provider_qualified(c2, true).
claim_written_confirmation_month(c2, 3).
claim_dispute_arisen(c2, false).
claim_unable_to_settle_month(c2, none).
claim_arbitration_commenced_month(c2, none).
claim_valid_arbitration_award_issued(c2, false).
claim_written_proof_of_claim_month(c2, 0).
claim_recovery_sought_month(c2, none).
claim_policy_term_months(c2, 12).

% Q3: hospitalized for pneumonia 5 months after the effective date; age 65.
q3 :- covered(c3).
claim_agreement_signed(c3, true).
claim_premium_paid_month(c3, 0).
claim_hospitalization_month(c3, 5).
claim_hospitalization_ground(c3, sickness).
claim_age_at_hospitalization(c3, 65).
claim_causes(c3, [other]).
claim_fraud_month(c3, none).
claim_misrepresentation_month(c3, none).
claim_wellness_visit_month(c3, 3).
claim_wellness_visit_provider_qualified(c3, true).
claim_written_confirmation_month(c3, 3).
claim_dispute_arisen(c3, false).
claim_unable_to_settle_month(c3, none).
claim_arbitration_commenced_month(c3, none).
claim_valid_arbitration_award_issued(c3, false).
claim_written_proof_of_claim_month(c3, 0).
claim_recovery_sought_month(c3, none).
claim_policy_term_months(c3, 12).

% Q4: hospitalized due to a fall while traveling abroad; confirmation of
% wellness visit given 8 months after the effective date (after the
% 7-month deadline in 1.3). Hospitalization month is not stated by the
% question; set to 9 (after the deadline, and after the confirmation) so
% the late-confirmation fact pattern is actually exercised rather than
% mooted by the "still pending" branch of 1.1(3). See NOTES.md.
q4 :- covered(c4).
claim_agreement_signed(c4, true).
claim_premium_paid_month(c4, 0).
claim_hospitalization_month(c4, 9).
claim_hospitalization_ground(c4, accidental_injury).
claim_age_at_hospitalization(c4, 40).
claim_causes(c4, [other]).
claim_fraud_month(c4, none).
claim_misrepresentation_month(c4, none).
claim_wellness_visit_month(c4, 5).
claim_wellness_visit_provider_qualified(c4, true).
claim_written_confirmation_month(c4, 8).
claim_dispute_arisen(c4, false).
claim_unable_to_settle_month(c4, none).
claim_arbitration_commenced_month(c4, none).
claim_valid_arbitration_award_issued(c4, false).
claim_written_proof_of_claim_month(c4, 0).
claim_recovery_sought_month(c4, none).
claim_policy_term_months(c4, 12).

% Q5: hospitalized for punching my own face to show off for my friends;
% no fraud or misrepresentation. Treated as an intentional, self-inflicted
% act -- neither a sickness nor an accidental injury. See NOTES.md.
q5 :- covered(c5).
claim_agreement_signed(c5, true).
claim_premium_paid_month(c5, 0).
claim_hospitalization_month(c5, 3).
claim_hospitalization_ground(c5, neither).
claim_age_at_hospitalization(c5, 40).
claim_causes(c5, [other]).
claim_fraud_month(c5, none).
claim_misrepresentation_month(c5, none).
claim_wellness_visit_month(c5, 3).
claim_wellness_visit_provider_qualified(c5, true).
claim_written_confirmation_month(c5, 3).
claim_dispute_arisen(c5, false).
claim_unable_to_settle_month(c5, none).
claim_arbitration_commenced_month(c5, none).
claim_valid_arbitration_award_issued(c5, false).
claim_written_proof_of_claim_month(c5, 0).
claim_recovery_sought_month(c5, none).
claim_policy_term_months(c5, 12).

% Q6: injury sustained while skydiving; age 79; proof of wellness visit
% provided 6.5 months after the effective date.
q6 :- covered(c6).
claim_agreement_signed(c6, true).
claim_premium_paid_month(c6, 0).
claim_hospitalization_month(c6, 3).
claim_hospitalization_ground(c6, accidental_injury).
claim_age_at_hospitalization(c6, 79).
claim_causes(c6, [skydiving]).
claim_fraud_month(c6, none).
claim_misrepresentation_month(c6, none).
claim_wellness_visit_month(c6, 6).
claim_wellness_visit_provider_qualified(c6, true).
claim_written_confirmation_month(c6, 6.5).
claim_dispute_arisen(c6, false).
claim_unable_to_settle_month(c6, none).
claim_arbitration_commenced_month(c6, none).
claim_valid_arbitration_award_issued(c6, false).
claim_written_proof_of_claim_month(c6, 0).
claim_recovery_sought_month(c6, none).
claim_policy_term_months(c6, 12).

% Q7: hospitalized for a heart attack; proof of wellness visit submitted
% 2 months after the effective date; age 75.
q7 :- covered(c7).
claim_agreement_signed(c7, true).
claim_premium_paid_month(c7, 0).
claim_hospitalization_month(c7, 3).
claim_hospitalization_ground(c7, sickness).
claim_age_at_hospitalization(c7, 75).
claim_causes(c7, [other]).
claim_fraud_month(c7, none).
claim_misrepresentation_month(c7, none).
claim_wellness_visit_month(c7, 1).
claim_wellness_visit_provider_qualified(c7, true).
claim_written_confirmation_month(c7, 2).
claim_dispute_arisen(c7, false).
claim_unable_to_settle_month(c7, none).
claim_arbitration_commenced_month(c7, none).
claim_valid_arbitration_award_issued(c7, false).
claim_written_proof_of_claim_month(c7, 0).
claim_recovery_sought_month(c7, none).
claim_policy_term_months(c7, 12).

% Q8: injured in a military training exercise; hospitalization occurred
% within the policy term; no fraud.
q8 :- covered(c8).
claim_agreement_signed(c8, true).
claim_premium_paid_month(c8, 0).
claim_hospitalization_month(c8, 6).
claim_hospitalization_ground(c8, accidental_injury).
claim_age_at_hospitalization(c8, 40).
claim_causes(c8, [military_service]).
claim_fraud_month(c8, none).
claim_misrepresentation_month(c8, none).
claim_wellness_visit_month(c8, 3).
claim_wellness_visit_provider_qualified(c8, true).
claim_written_confirmation_month(c8, 3).
claim_dispute_arisen(c8, false).
claim_unable_to_settle_month(c8, none).
claim_arbitration_commenced_month(c8, none).
claim_valid_arbitration_award_issued(c8, false).
claim_written_proof_of_claim_month(c8, 0).
claim_recovery_sought_month(c8, none).
claim_policy_term_months(c8, 12).

% Q9: hospitalized due to my son biting me in the ankle; proof of wellness
% visit provided 6 months after the effective date; serving as a police
% officer at the time of hospitalization. The bite does not arise directly
% or indirectly out of police service -- merely holding that job at the
% time is not the same as the injury arising out of it -- so police_service
% is not included among the causes. See NOTES.md.
q9 :- covered(c9).
claim_agreement_signed(c9, true).
claim_premium_paid_month(c9, 0).
claim_hospitalization_month(c9, 8).
claim_hospitalization_ground(c9, accidental_injury).
claim_age_at_hospitalization(c9, 40).
claim_causes(c9, [other]).
claim_fraud_month(c9, none).
claim_misrepresentation_month(c9, none).
claim_wellness_visit_month(c9, 5).
claim_wellness_visit_provider_qualified(c9, true).
claim_written_confirmation_month(c9, 6).
claim_dispute_arisen(c9, false).
claim_unable_to_settle_month(c9, none).
claim_arbitration_commenced_month(c9, none).
claim_valid_arbitration_award_issued(c9, false).
claim_written_proof_of_claim_month(c9, 0).
claim_recovery_sought_month(c9, none).
claim_policy_term_months(c9, 12).
