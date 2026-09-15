% queries.pl -- the nine benchmark claims, c1..c9, one per question in
% inputs/queries-blind.md. Each qN/0 succeeds exactly when covered(cN)
% succeeds. Every claim defines all 18 claim_* facts. Facts not referenced
% by the question are set so that all conditions for coverage are satisfied
% and no exclusion is triggered, per the standing preamble ("assuming all
% other conditions are met and no other exclusions apply"), and per the
% instruction that the agreement is signed and the premium paid on time.

% Each claim_*/2 fact is declared once per claim (nine times total, spread
% across the q1..q9 blocks below rather than grouped by predicate), so every
% one of them is discontiguous by construction.
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
% Q1. Hospitalized by burns suffered while doing my duty as a firefighter.
% Firefighting is an excluded cause (2.1(3)); expected to fail on that
% ground alone, with everything else favorable.
% ---------------------------------------------------------------------------
q1 :- covered(c1).

claim_agreement_signed(c1, true).
claim_premium_paid_month(c1, 0).
claim_hospitalization_month(c1, 1).
claim_hospitalization_ground(c1, accidental_injury).
claim_age_at_hospitalization(c1, 40).
claim_causes(c1, [firefighting]).
claim_fraud_month(c1, none).
claim_misrepresentation_month(c1, none).
claim_wellness_visit_month(c1, 3).
claim_wellness_visit_provider_qualified(c1, true).
claim_written_confirmation_month(c1, 5).
claim_dispute_arisen(c1, false).
claim_unable_to_settle_month(c1, none).
claim_arbitration_commenced_month(c1, none).
claim_valid_arbitration_award_issued(c1, false).
claim_written_proof_of_claim_month(c1, none).
claim_recovery_sought_month(c1, none).
claim_policy_term_months(c1, 12).

% ---------------------------------------------------------------------------
% Q2. 78 years old at the time of hospitalization. 78 < 80, so the age
% exclusion (2.1(5)) does not apply; no other exclusion is referenced.
% ---------------------------------------------------------------------------
q2 :- covered(c2).

claim_agreement_signed(c2, true).
claim_premium_paid_month(c2, 0).
claim_hospitalization_month(c2, 1).
claim_hospitalization_ground(c2, sickness).
claim_age_at_hospitalization(c2, 78).
claim_causes(c2, [other]).
claim_fraud_month(c2, none).
claim_misrepresentation_month(c2, none).
claim_wellness_visit_month(c2, 3).
claim_wellness_visit_provider_qualified(c2, true).
claim_written_confirmation_month(c2, 5).
claim_dispute_arisen(c2, false).
claim_unable_to_settle_month(c2, none).
claim_arbitration_commenced_month(c2, none).
claim_valid_arbitration_award_issued(c2, false).
claim_written_proof_of_claim_month(c2, none).
claim_recovery_sought_month(c2, none).
claim_policy_term_months(c2, 12).

% ---------------------------------------------------------------------------
% Q3. Hospitalized for pneumonia 5 months after the effective date; age 65
% at hospitalization. Sickness, age < 80, hospitalization well before the
% 7-month wellness-visit deadline (still pending).
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
claim_wellness_visit_month(c3, 4).
claim_wellness_visit_provider_qualified(c3, true).
claim_written_confirmation_month(c3, 6).
claim_dispute_arisen(c3, false).
claim_unable_to_settle_month(c3, none).
claim_arbitration_commenced_month(c3, none).
claim_valid_arbitration_award_issued(c3, false).
claim_written_proof_of_claim_month(c3, none).
claim_recovery_sought_month(c3, none).
claim_policy_term_months(c3, 12).

% ---------------------------------------------------------------------------
% Q4. Hospitalized due to a fall while traveling abroad; confirmation of
% the wellness visit was given 8 months after the effective date -- i.e.
% one month past the Section 1.3 deadline. The question does not state the
% hospitalization month; it is deliberately placed at month 8 (after the
% deadline) rather than defaulted to an early "still pending" month, so
% that the stated late confirmation is the operative fact rather than a
% moot one. See NOTES.md.
% ---------------------------------------------------------------------------
q4 :- covered(c4).

claim_agreement_signed(c4, true).
claim_premium_paid_month(c4, 0).
claim_hospitalization_month(c4, 8).
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
claim_written_proof_of_claim_month(c4, none).
claim_recovery_sought_month(c4, none).
claim_policy_term_months(c4, 12).

% ---------------------------------------------------------------------------
% Q5. Hospitalized for punching my own face to show off for my friends; no
% fraud or misrepresentation committed. Self-inflicted, foolish injury is
% not among the enumerated exclusions in Section 2.1.
% ---------------------------------------------------------------------------
q5 :- covered(c5).

claim_agreement_signed(c5, true).
claim_premium_paid_month(c5, 0).
claim_hospitalization_month(c5, 1).
claim_hospitalization_ground(c5, accidental_injury).
claim_age_at_hospitalization(c5, 40).
claim_causes(c5, [other]).
claim_fraud_month(c5, none).
claim_misrepresentation_month(c5, none).
claim_wellness_visit_month(c5, 3).
claim_wellness_visit_provider_qualified(c5, true).
claim_written_confirmation_month(c5, 5).
claim_dispute_arisen(c5, false).
claim_unable_to_settle_month(c5, none).
claim_arbitration_commenced_month(c5, none).
claim_valid_arbitration_award_issued(c5, false).
claim_written_proof_of_claim_month(c5, none).
claim_recovery_sought_month(c5, none).
claim_policy_term_months(c5, 12).

% ---------------------------------------------------------------------------
% Q6. Injury sustained while skydiving; age 79 at hospitalization; wellness
% visit proof provided 6.5 months after the effective date. Skydiving is an
% excluded cause (2.1(1)); age 79 < 80 does not independently exclude, and
% the wellness-visit timing is timely -- neither saves the claim from the
% skydiving exclusion.
% ---------------------------------------------------------------------------
q6 :- covered(c6).

claim_agreement_signed(c6, true).
claim_premium_paid_month(c6, 0).
claim_hospitalization_month(c6, 1).
claim_hospitalization_ground(c6, accidental_injury).
claim_age_at_hospitalization(c6, 79).
claim_causes(c6, [skydiving]).
claim_fraud_month(c6, none).
claim_misrepresentation_month(c6, none).
claim_wellness_visit_month(c6, 5).
claim_wellness_visit_provider_qualified(c6, true).
claim_written_confirmation_month(c6, 6.5).
claim_dispute_arisen(c6, false).
claim_unable_to_settle_month(c6, none).
claim_arbitration_commenced_month(c6, none).
claim_valid_arbitration_award_issued(c6, false).
claim_written_proof_of_claim_month(c6, none).
claim_recovery_sought_month(c6, none).
claim_policy_term_months(c6, 12).

% ---------------------------------------------------------------------------
% Q7. Hospitalized for a heart attack; wellness-visit proof submitted 2
% months after the effective date; age 75 at hospitalization. Sickness,
% age < 80, wellness-visit confirmation well within the 7-month deadline.
% ---------------------------------------------------------------------------
q7 :- covered(c7).

claim_agreement_signed(c7, true).
claim_premium_paid_month(c7, 0).
claim_hospitalization_month(c7, 1).
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
claim_written_proof_of_claim_month(c7, none).
claim_recovery_sought_month(c7, none).
claim_policy_term_months(c7, 12).

% ---------------------------------------------------------------------------
% Q8. Injured in a military training exercise; hospitalization occurred
% within the policy term; no fraud committed. Military service is an
% excluded cause (2.1(2)); being within the policy term and free of fraud
% are red herrings that do not rescue the claim from that exclusion.
% ---------------------------------------------------------------------------
q8 :- covered(c8).

claim_agreement_signed(c8, true).
claim_premium_paid_month(c8, 0).
claim_hospitalization_month(c8, 5).
claim_hospitalization_ground(c8, accidental_injury).
claim_age_at_hospitalization(c8, 40).
claim_causes(c8, [military_service]).
claim_fraud_month(c8, none).
claim_misrepresentation_month(c8, none).
claim_wellness_visit_month(c8, 4).
claim_wellness_visit_provider_qualified(c8, true).
claim_written_confirmation_month(c8, 6).
claim_dispute_arisen(c8, false).
claim_unable_to_settle_month(c8, none).
claim_arbitration_commenced_month(c8, none).
claim_valid_arbitration_award_issued(c8, false).
claim_written_proof_of_claim_month(c8, none).
claim_recovery_sought_month(c8, none).
claim_policy_term_months(c8, 12).

% ---------------------------------------------------------------------------
% Q9. Hospitalized because my son bit me in the ankle; wellness-visit proof
% provided 6 months after the effective date; I was serving as a police
% officer at the time of hospitalization. The injury did not arise out of
% police service (2.1(4)) -- it arose out of a domestic bite -- so
% claim_causes deliberately excludes police_service; being a police officer
% at the time is incidental status, not causation. See NOTES.md.
% ---------------------------------------------------------------------------
q9 :- covered(c9).

claim_agreement_signed(c9, true).
claim_premium_paid_month(c9, 0).
claim_hospitalization_month(c9, 1).
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
claim_written_proof_of_claim_month(c9, none).
claim_recovery_sought_month(c9, none).
claim_policy_term_months(c9, 12).
