% queries.pl
%
% Nine claims (c1..c9), one per benchmark question (inputs/queries-blind.md). Each qN
% succeeds exactly when covered/1 succeeds for claim cN. Every fact not addressed by a
% question is set to whichever value most favors coverage, per the standing preamble:
% "Assuming all other conditions are met and no other exclusions apply (where by 'other,'
% I mean anything not referenced in the query that follows)". Per the same preamble, all
% nine assume the agreement is signed and the premium is paid on time (month 0).

:- discontiguous
       claim_agreement_signed/2,
       claim_premium_paid_month/2,
       claim_hospitalization_month/2,
       claim_hospitalization_ground/2,
       claim_age_at_hospitalization/2,
       claim_causes/2,
       claim_fraud_month/2,
       claim_misrepresentation_month/2,
       claim_wellness_visit_month/2,
       claim_wellness_visit_provider_qualified/2,
       claim_written_confirmation_month/2,
       claim_dispute_arisen/2,
       claim_unable_to_settle_month/2,
       claim_arbitration_commenced_month/2,
       claim_valid_arbitration_award_issued/2,
       claim_written_proof_of_claim_month/2,
       claim_recovery_sought_month/2,
       claim_policy_term_months/2.

% --- Q1: hospitalized by burns suffered while doing my duty as a firefighter ---
q1 :- covered(c1).
claim_agreement_signed(c1, true).
claim_premium_paid_month(c1, 0).
claim_hospitalization_month(c1, 1).
claim_hospitalization_ground(c1, accidental_injury).
claim_age_at_hospitalization(c1, 30).
claim_causes(c1, [firefighting]).
claim_fraud_month(c1, none).
claim_misrepresentation_month(c1, none).
claim_wellness_visit_month(c1, 1).
claim_wellness_visit_provider_qualified(c1, true).
claim_written_confirmation_month(c1, 1).
claim_dispute_arisen(c1, false).
claim_unable_to_settle_month(c1, none).
claim_arbitration_commenced_month(c1, none).
claim_valid_arbitration_award_issued(c1, false).
claim_written_proof_of_claim_month(c1, none).
claim_recovery_sought_month(c1, none).
claim_policy_term_months(c1, 12).

% --- Q2: 78 years old at the time of hospitalization ---
q2 :- covered(c2).
claim_agreement_signed(c2, true).
claim_premium_paid_month(c2, 0).
claim_hospitalization_month(c2, 1).
claim_hospitalization_ground(c2, sickness).
claim_age_at_hospitalization(c2, 78).
claim_causes(c2, []).
claim_fraud_month(c2, none).
claim_misrepresentation_month(c2, none).
claim_wellness_visit_month(c2, 1).
claim_wellness_visit_provider_qualified(c2, true).
claim_written_confirmation_month(c2, 1).
claim_dispute_arisen(c2, false).
claim_unable_to_settle_month(c2, none).
claim_arbitration_commenced_month(c2, none).
claim_valid_arbitration_award_issued(c2, false).
claim_written_proof_of_claim_month(c2, none).
claim_recovery_sought_month(c2, none).
claim_policy_term_months(c2, 12).

% --- Q3: pneumonia 5 months after the effective date; age 65 at hospitalization ---
q3 :- covered(c3).
claim_agreement_signed(c3, true).
claim_premium_paid_month(c3, 0).
claim_hospitalization_month(c3, 5).
claim_hospitalization_ground(c3, sickness).
claim_age_at_hospitalization(c3, 65).
claim_causes(c3, []).
claim_fraud_month(c3, none).
claim_misrepresentation_month(c3, none).
claim_wellness_visit_month(c3, 1).
claim_wellness_visit_provider_qualified(c3, true).
claim_written_confirmation_month(c3, 1).
claim_dispute_arisen(c3, false).
claim_unable_to_settle_month(c3, none).
claim_arbitration_commenced_month(c3, none).
claim_valid_arbitration_award_issued(c3, false).
claim_written_proof_of_claim_month(c3, none).
claim_recovery_sought_month(c3, none).
claim_policy_term_months(c3, 12).

% --- Q4: fall while traveling abroad; wellness-visit confirmation given at month 8 ---
q4 :- covered(c4).
claim_agreement_signed(c4, true).
claim_premium_paid_month(c4, 0).
claim_hospitalization_month(c4, 10).
claim_hospitalization_ground(c4, accidental_injury).
claim_age_at_hospitalization(c4, 30).
claim_causes(c4, [other]).
claim_fraud_month(c4, none).
claim_misrepresentation_month(c4, none).
claim_wellness_visit_month(c4, 1).
claim_wellness_visit_provider_qualified(c4, true).
claim_written_confirmation_month(c4, 8).
claim_dispute_arisen(c4, false).
claim_unable_to_settle_month(c4, none).
claim_arbitration_commenced_month(c4, none).
claim_valid_arbitration_award_issued(c4, false).
claim_written_proof_of_claim_month(c4, none).
claim_recovery_sought_month(c4, none).
claim_policy_term_months(c4, 12).

% --- Q5: hospitalized for punching own face to show off; no fraud or misrepresentation ---
q5 :- covered(c5).
claim_agreement_signed(c5, true).
claim_premium_paid_month(c5, 0).
claim_hospitalization_month(c5, 1).
claim_hospitalization_ground(c5, neither).
claim_age_at_hospitalization(c5, 30).
claim_causes(c5, [other]).
claim_fraud_month(c5, none).
claim_misrepresentation_month(c5, none).
claim_wellness_visit_month(c5, 1).
claim_wellness_visit_provider_qualified(c5, true).
claim_written_confirmation_month(c5, 1).
claim_dispute_arisen(c5, false).
claim_unable_to_settle_month(c5, none).
claim_arbitration_commenced_month(c5, none).
claim_valid_arbitration_award_issued(c5, false).
claim_written_proof_of_claim_month(c5, none).
claim_recovery_sought_month(c5, none).
claim_policy_term_months(c5, 12).

% --- Q6: injury sustained while skydiving; age 79; wellness-visit proof at month 6.5 ---
q6 :- covered(c6).
claim_agreement_signed(c6, true).
claim_premium_paid_month(c6, 0).
claim_hospitalization_month(c6, 8).
claim_hospitalization_ground(c6, accidental_injury).
claim_age_at_hospitalization(c6, 79).
claim_causes(c6, [skydiving]).
claim_fraud_month(c6, none).
claim_misrepresentation_month(c6, none).
claim_wellness_visit_month(c6, 1).
claim_wellness_visit_provider_qualified(c6, true).
claim_written_confirmation_month(c6, 6.5).
claim_dispute_arisen(c6, false).
claim_unable_to_settle_month(c6, none).
claim_arbitration_commenced_month(c6, none).
claim_valid_arbitration_award_issued(c6, false).
claim_written_proof_of_claim_month(c6, none).
claim_recovery_sought_month(c6, none).
claim_policy_term_months(c6, 12).

% --- Q7: heart attack; wellness-visit proof submitted at month 2; age 75 ---
q7 :- covered(c7).
claim_agreement_signed(c7, true).
claim_premium_paid_month(c7, 0).
claim_hospitalization_month(c7, 10).
claim_hospitalization_ground(c7, sickness).
claim_age_at_hospitalization(c7, 75).
claim_causes(c7, []).
claim_fraud_month(c7, none).
claim_misrepresentation_month(c7, none).
claim_wellness_visit_month(c7, 1).
claim_wellness_visit_provider_qualified(c7, true).
claim_written_confirmation_month(c7, 2).
claim_dispute_arisen(c7, false).
claim_unable_to_settle_month(c7, none).
claim_arbitration_commenced_month(c7, none).
claim_valid_arbitration_award_issued(c7, false).
claim_written_proof_of_claim_month(c7, none).
claim_recovery_sought_month(c7, none).
claim_policy_term_months(c7, 12).

% --- Q8: injured in a military training exercise; within the policy term; no fraud ---
q8 :- covered(c8).
claim_agreement_signed(c8, true).
claim_premium_paid_month(c8, 0).
claim_hospitalization_month(c8, 5).
claim_hospitalization_ground(c8, accidental_injury).
claim_age_at_hospitalization(c8, 30).
claim_causes(c8, [military_service]).
claim_fraud_month(c8, none).
claim_misrepresentation_month(c8, none).
claim_wellness_visit_month(c8, 1).
claim_wellness_visit_provider_qualified(c8, true).
claim_written_confirmation_month(c8, 1).
claim_dispute_arisen(c8, false).
claim_unable_to_settle_month(c8, none).
claim_arbitration_commenced_month(c8, none).
claim_valid_arbitration_award_issued(c8, false).
claim_written_proof_of_claim_month(c8, none).
claim_recovery_sought_month(c8, none).
claim_policy_term_months(c8, 12).

% --- Q9: son bit my ankle; wellness-visit proof provided at month 6; serving as a police
%         officer at the time (but the injury did not arise out of that service) ---
q9 :- covered(c9).
claim_agreement_signed(c9, true).
claim_premium_paid_month(c9, 0).
claim_hospitalization_month(c9, 8).
claim_hospitalization_ground(c9, accidental_injury).
claim_age_at_hospitalization(c9, 30).
claim_causes(c9, [other]).
claim_fraud_month(c9, none).
claim_misrepresentation_month(c9, none).
claim_wellness_visit_month(c9, 1).
claim_wellness_visit_provider_qualified(c9, true).
claim_written_confirmation_month(c9, 6).
claim_dispute_arisen(c9, false).
claim_unable_to_settle_month(c9, none).
claim_arbitration_commenced_month(c9, none).
claim_valid_arbitration_award_issued(c9, false).
claim_written_proof_of_claim_month(c9, none).
claim_recovery_sought_month(c9, none).
claim_policy_term_months(c9, 12).
