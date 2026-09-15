% queries.pl
%
% q1/0 .. q9/0 — one per benchmark question in inputs/queries-blind.md.
% Each succeeds exactly when covered/1 says "yes" for that question's claim.
% Every claim_* fact not addressed by the question is set to a value that
% keeps every other condition satisfied and triggers no exclusion, per the
% standing preamble ("assuming all other conditions are met and no other
% exclusions apply") and the note that the agreement is signed and the
% premium paid on time.

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

% ---------------------------------------------------------------------------
% Q1. Hospitalized by burns suffered while doing duty as a firefighter.
%     Tests the firefighting exclusion (Section 2.1(3)) — a real causal link
%     between the service and the injury.
% ---------------------------------------------------------------------------
q1 :- covered(c1).

claim_agreement_signed(c1, true).
claim_premium_paid_month(c1, 0).
claim_hospitalization_month(c1, 3).
claim_hospitalization_ground(c1, accidental_injury).
claim_age_at_hospitalization(c1, 30).
claim_causes(c1, [firefighting]).
claim_fraud_month(c1, none).
claim_misrepresentation_month(c1, none).
claim_wellness_visit_month(c1, 6).
claim_wellness_visit_provider_qualified(c1, true).
claim_written_confirmation_month(c1, 7).
claim_dispute_arisen(c1, false).
claim_unable_to_settle_month(c1, none).
claim_arbitration_commenced_month(c1, none).
claim_valid_arbitration_award_issued(c1, false).
claim_written_proof_of_claim_month(c1, 1).
claim_recovery_sought_month(c1, none).
claim_policy_term_months(c1, 12).

% ---------------------------------------------------------------------------
% Q2. 78 years old at the time of hospitalization.
%     Tests the age-exclusion boundary (Section 2.1(5): >= 80). 78 < 80.
% ---------------------------------------------------------------------------
q2 :- covered(c2).

claim_agreement_signed(c2, true).
claim_premium_paid_month(c2, 0).
claim_hospitalization_month(c2, 3).
claim_hospitalization_ground(c2, sickness).
claim_age_at_hospitalization(c2, 78).
claim_causes(c2, [other]).
claim_fraud_month(c2, none).
claim_misrepresentation_month(c2, none).
claim_wellness_visit_month(c2, 6).
claim_wellness_visit_provider_qualified(c2, true).
claim_written_confirmation_month(c2, 7).
claim_dispute_arisen(c2, false).
claim_unable_to_settle_month(c2, none).
claim_arbitration_commenced_month(c2, none).
claim_valid_arbitration_award_issued(c2, false).
claim_written_proof_of_claim_month(c2, 1).
claim_recovery_sought_month(c2, none).
claim_policy_term_months(c2, 12).

% ---------------------------------------------------------------------------
% Q3. Hospitalized for pneumonia 5 months after the effective date, age 65.
%     Ordinary coverage; also within the Section 1.3 "still pending" window
%     (hospitalization at month 5, before the month-7 deadline).
% ---------------------------------------------------------------------------
q3 :- covered(c3).

claim_agreement_signed(c3, true).
claim_premium_paid_month(c3, 0).
claim_hospitalization_month(c3, 5).
claim_hospitalization_ground(c3, sickness).
claim_age_at_hospitalization(c3, 65).
claim_causes(c3, [other]).
claim_fraud_month(c3, none).
claim_misrepresentation_month(c3, none).
claim_wellness_visit_month(c3, 6).
claim_wellness_visit_provider_qualified(c3, true).
claim_written_confirmation_month(c3, 7).
claim_dispute_arisen(c3, false).
claim_unable_to_settle_month(c3, none).
claim_arbitration_commenced_month(c3, none).
claim_valid_arbitration_award_issued(c3, false).
claim_written_proof_of_claim_month(c3, 1).
claim_recovery_sought_month(c3, none).
claim_policy_term_months(c3, 12).

% ---------------------------------------------------------------------------
% Q4. Fall while traveling abroad; wellness-visit confirmation given 8
%     months after the effective date. Tests the confirmation deadline
%     (Section 1.3: no later than month 7) — confirmation is late, and
%     hospitalization is placed after month 7 so the "still pending" arm
%     does not rescue it. "Traveling abroad" is a non-issue under Section
%     3.1 (worldwide, 24-hour cover).
% ---------------------------------------------------------------------------
q4 :- covered(c4).

claim_agreement_signed(c4, true).
claim_premium_paid_month(c4, 0).
claim_hospitalization_month(c4, 9).
claim_hospitalization_ground(c4, accidental_injury).
claim_age_at_hospitalization(c4, 30).
claim_causes(c4, [other]).
claim_fraud_month(c4, none).
claim_misrepresentation_month(c4, none).
claim_wellness_visit_month(c4, 6).
claim_wellness_visit_provider_qualified(c4, true).
claim_written_confirmation_month(c4, 8).
claim_dispute_arisen(c4, false).
claim_unable_to_settle_month(c4, none).
claim_arbitration_commenced_month(c4, none).
claim_valid_arbitration_award_issued(c4, false).
claim_written_proof_of_claim_month(c4, 1).
claim_recovery_sought_month(c4, none).
claim_policy_term_months(c4, 12).

% ---------------------------------------------------------------------------
% Q5. Hospitalized for punching own face to show off; no fraud or
%     misrepresentation. Tests the "neither" hospitalization ground: a
%     deliberate act is not an "accidental" injury, so it falls outside
%     Section 1.1's insured event regardless of fraud/misrepresentation.
% ---------------------------------------------------------------------------
q5 :- covered(c5).

claim_agreement_signed(c5, true).
claim_premium_paid_month(c5, 0).
claim_hospitalization_month(c5, 3).
claim_hospitalization_ground(c5, neither).
claim_age_at_hospitalization(c5, 30).
claim_causes(c5, [other]).
claim_fraud_month(c5, none).
claim_misrepresentation_month(c5, none).
claim_wellness_visit_month(c5, 6).
claim_wellness_visit_provider_qualified(c5, true).
claim_written_confirmation_month(c5, 7).
claim_dispute_arisen(c5, false).
claim_unable_to_settle_month(c5, none).
claim_arbitration_commenced_month(c5, none).
claim_valid_arbitration_award_issued(c5, false).
claim_written_proof_of_claim_month(c5, 1).
claim_recovery_sought_month(c5, none).
claim_policy_term_months(c5, 12).

% ---------------------------------------------------------------------------
% Q6. Injury while skydiving, age 79, wellness-visit proof given at 6.5
%     months. Tests that the skydiving exclusion (Section 2.1(1)) bars the
%     claim even though age (79 < 80) and the confirmation timing
%     (6.5 =< 7) are each, on their own, within bounds.
% ---------------------------------------------------------------------------
q6 :- covered(c6).

claim_agreement_signed(c6, true).
claim_premium_paid_month(c6, 0).
claim_hospitalization_month(c6, 7).
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
claim_written_proof_of_claim_month(c6, 1).
claim_recovery_sought_month(c6, none).
claim_policy_term_months(c6, 12).

% ---------------------------------------------------------------------------
% Q7. Heart attack; wellness-visit proof submitted at month 2; age 75.
%     Every figure is comfortably within bounds (age 75 < 80, confirmation
%     2 =< 7) and no exclusion applies.
% ---------------------------------------------------------------------------
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
claim_written_proof_of_claim_month(c7, 1).
claim_recovery_sought_month(c7, none).
claim_policy_term_months(c7, 12).

% ---------------------------------------------------------------------------
% Q8. Injured in a military training exercise; hospitalization within the
%     policy term; no fraud. Tests that the military-service exclusion
%     (Section 2.1(2)) bars the claim regardless of the other, satisfied,
%     conditions.
% ---------------------------------------------------------------------------
q8 :- covered(c8).

claim_agreement_signed(c8, true).
claim_premium_paid_month(c8, 0).
claim_hospitalization_month(c8, 6).
claim_hospitalization_ground(c8, accidental_injury).
claim_age_at_hospitalization(c8, 30).
claim_causes(c8, [military_service]).
claim_fraud_month(c8, none).
claim_misrepresentation_month(c8, none).
claim_wellness_visit_month(c8, 6).
claim_wellness_visit_provider_qualified(c8, true).
claim_written_confirmation_month(c8, 7).
claim_dispute_arisen(c8, false).
claim_unable_to_settle_month(c8, none).
claim_arbitration_commenced_month(c8, none).
claim_valid_arbitration_award_issued(c8, false).
claim_written_proof_of_claim_month(c8, 1).
claim_recovery_sought_month(c8, none).
claim_policy_term_months(c8, 12).

% ---------------------------------------------------------------------------
% Q9. Hospitalized after being bitten in the ankle by claimant's own son,
%     while serving as a police officer. Tests that the police-service
%     exclusion (Section 2.1(4)) requires an actual causal link — merely
%     holding that occupation when an unrelated domestic injury occurs does
%     not put the event "directly or indirectly" out of police service.
% ---------------------------------------------------------------------------
q9 :- covered(c9).

claim_agreement_signed(c9, true).
claim_premium_paid_month(c9, 0).
claim_hospitalization_month(c9, 6).
claim_hospitalization_ground(c9, accidental_injury).
claim_age_at_hospitalization(c9, 30).
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
claim_written_proof_of_claim_month(c9, 1).
claim_recovery_sought_month(c9, none).
claim_policy_term_months(c9, 12).
