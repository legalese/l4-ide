% policy.pl -- CODEX INSURANCE LIMITED hospital income policy, encoded as covered/1.
%
% covered(C) is true exactly when a benefit is payable on claim C.
% This file contains no claim facts; those are supplied by queries.pl.

% ---------------------------------------------------------------------------
% Supporting predicates (copied verbatim from bench/schema-prolog.md).
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Top level.
% ---------------------------------------------------------------------------

%! covered(+C) is semidet.
%  True exactly when a benefit is payable on claim C: the policy was in force
%  at the time of hospitalization (S1), the benefit-triggering conditions of
%  S2 are met, no S3 exclusion applies, and the S4.2 dispute-resolution
%  preconditions (where applicable) are met.
covered(C) :-
    policy_in_force(C),
    benefit_conditions_met(C),
    no_exclusion_applies(C),
    dispute_resolution_ok(C).

% ---------------------------------------------------------------------------
% Section 1: policy in effect and conditions.
% ---------------------------------------------------------------------------

%! policy_in_force(+C) is semidet.
%  S1.1: the policy is in effect at the time of hospitalization if the
%  agreement is signed, the premium has been paid (by the time of
%  hospitalization), the hospitalization falls within the policy term, and
%  the policy has not been cancelled.
policy_in_force(C) :-
    claim_agreement_signed(C, true),
    claim_hospitalization_month(C, HospitalizationMonth),
    claim_premium_paid_month(C, PremiumPaidMonth),
    no_later_than(PremiumPaidMonth, HospitalizationMonth),
    claim_policy_term_months(C, PolicyTermMonths),
    no_later_than(HospitalizationMonth, PolicyTermMonths),
    not_cancelled(C).

%! not_cancelled(+C) is semidet.
%  S1.2: cancellation occurs on fraud, on misrepresentation, or on failure to
%  satisfy the S1.3 wellness-visit condition in a timely fashion. (The
%  policy-term expiry limb of S1.2 is already enforced in policy_in_force/1
%  via claim_policy_term_months.)
not_cancelled(C) :-
    not_cancelled_for_fraud(C),
    not_cancelled_for_misrepresentation(C),
    wellness_condition_ok(C).

%! not_cancelled_for_fraud(+C) is semidet.
%  Fraud cancels the policy from the month it occurs onward: a hospitalization
%  before the fraud month is unaffected, one at or after it is not covered.
not_cancelled_for_fraud(C) :-
    claim_fraud_month(C, FraudMonth),
    claim_hospitalization_month(C, HospitalizationMonth),
    \+ no_later_than(FraudMonth, HospitalizationMonth).

%! not_cancelled_for_misrepresentation(+C) is semidet.
%  Same treatment as fraud, per S1.2's "fraud, or any misrepresentation".
not_cancelled_for_misrepresentation(C) :-
    claim_misrepresentation_month(C, MisrepresentationMonth),
    claim_hospitalization_month(C, HospitalizationMonth),
    \+ no_later_than(MisrepresentationMonth, HospitalizationMonth).

%! wellness_condition_ok(+C) is semidet.
%  S1.3's condition (written confirmation, no later than month 7, of a
%  wellness visit occurring no later than month 6) is either still pending
%  (the hospitalization happens before the month-7 deadline, so the condition
%  cannot yet have been breached) or must already have been satisfied in a
%  timely fashion.
wellness_condition_ok(C) :-
    claim_hospitalization_month(C, HospitalizationMonth),
    (   HospitalizationMonth < 7
    ->  true
    ;   wellness_satisfied_timely(C)
    ).

%! wellness_satisfied_timely(+C) is semidet.
wellness_satisfied_timely(C) :-
    claim_written_confirmation_month(C, ConfirmationMonth),
    no_later_than(ConfirmationMonth, 7),
    claim_wellness_visit_month(C, VisitMonth),
    no_later_than(VisitMonth, 6),
    claim_wellness_visit_provider_qualified(C, true).

% ---------------------------------------------------------------------------
% Section 2: benefits.
% ---------------------------------------------------------------------------

%! benefit_conditions_met(+C) is semidet.
%  S2.1: hospitalization must result from sickness or accidental injury.
%  S2.2: benefit is payable only for continuous confinement in a US hospital.
%  S2.3: a claim must be made setting out the basis for the claim.
benefit_conditions_met(C) :-
    claim_hospitalization_ground(C, Ground),
    memberchk(Ground, [sickness, accidental_injury]),
    claim_confined_in_us_hospital(C, true),
    claim_continuous_confinement_days(C, Days),
    number(Days),
    Days > 0,
    claim_claim_made_setting_out_basis(C, true).

% ---------------------------------------------------------------------------
% Section 3: general exclusions.
% ---------------------------------------------------------------------------

%! no_exclusion_applies(+C) is semidet.
%  S3.1: no benefit is paid for an event arising directly or indirectly out
%  of skydiving, military service, firefighting, or police service, nor if
%  the claimant's age at hospitalization is 80 or older.
no_exclusion_applies(C) :-
    claim_causes(C, Causes),
    \+ arose_out_of(Causes, skydiving),
    \+ arose_out_of(Causes, military_service),
    \+ arose_out_of(Causes, firefighting),
    \+ arose_out_of(Causes, police_service),
    claim_age_at_hospitalization(C, Age),
    Age < 80.

% ---------------------------------------------------------------------------
% Section 4.2: arbitration and recovery timing.
% ---------------------------------------------------------------------------

%! dispute_resolution_ok(+C) is semidet.
dispute_resolution_ok(C) :-
    arbitration_ok(C),
    recovery_waiting_period_ok(C).

%! arbitration_ok(+C) is semidet.
%  S4.2.1: where a dispute has arisen, arbitration must be commenced within
%  three months of the parties becoming unable to settle, and a valid
%  arbitration award is a condition precedent to liability. Where no dispute
%  has arisen, these clauses are vacuous.
arbitration_ok(C) :-
    claim_dispute_arisen(C, Dispute),
    (   Dispute == false
    ->  true
    ;   claim_unable_to_settle_month(C, UnableToSettleMonth),
        number(UnableToSettleMonth),
        ArbitrationDeadline is UnableToSettleMonth + 3,
        claim_arbitration_commenced_month(C, ArbitrationCommencedMonth),
        no_later_than(ArbitrationCommencedMonth, ArbitrationDeadline),
        claim_valid_arbitration_award_issued(C, true)
    ).

%! recovery_waiting_period_ok(+C) is semidet.
%  S4.2.1: recovery may not be sought before the expiration of sixty (60)
%  days -- approximated here as two 30-day months, since the schema's time
%  facts are all month-granular -- after written proof of claim has been
%  submitted. Vacuous when no recovery is being sought.
recovery_waiting_period_ok(C) :-
    claim_recovery_sought_month(C, RecoverySoughtMonth),
    (   RecoverySoughtMonth == none
    ->  true
    ;   claim_written_proof_of_claim_month(C, ProofOfClaimMonth),
        number(ProofOfClaimMonth),
        EarliestRecoveryMonth is ProofOfClaimMonth + 2,
        RecoverySoughtMonth >= EarliestRecoveryMonth
    ).
