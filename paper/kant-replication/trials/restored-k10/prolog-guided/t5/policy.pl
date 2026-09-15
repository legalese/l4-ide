% =============================================================================
% policy.pl -- Codex Insurance Limited hospitalization policy, encoded as
% covered(C): true exactly when a benefit is payable on claim C.
%
% Uses ONLY the claim_* facts defined in schema.md (asserted separately, e.g.
% in queries.pl) and the two supporting predicates below, reproduced verbatim
% from schema.md. This file defines no claim facts of its own.
% =============================================================================

% -----------------------------------------------------------------------------
% Supporting predicates (verbatim from schema.md -- do not redefine elsewhere)
% -----------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% -----------------------------------------------------------------------------
% Top-level rule
% -----------------------------------------------------------------------------

%! covered(+C) is semidet.
%  A benefit is payable on claim C iff: the policy was in effect at the time
%  of hospitalization (§1), the §2 benefit-triggering conditions hold, no §3
%  exclusion applies, the §4.2 arbitration conditions (when a dispute has
%  arisen) are met, and the §4.2 pre-suit waiting period has been respected.
covered(C) :-
    policy_in_effect(C),
    benefit_triggered(C),
    \+ excluded(C),
    dispute_resolution_ok(C),
    recovery_timing_ok(C).

% -----------------------------------------------------------------------------
% §1 POLICY IN EFFECT AND CONDITIONS
% -----------------------------------------------------------------------------

%! policy_in_effect(+C) is semidet.
%  §1.1: in effect at the time of hospitalization iff the agreement is
%  signed, the premium has been paid, the §1.3 condition is pending or has
%  been timely satisfied, and the policy has not been canceled (§1.2: fraud,
%  misrepresentation, or the policy term having expired).
policy_in_effect(C) :-
    claim_agreement_signed(C, true),
    claim_premium_paid_month(C, PremiumMonth),
    number(PremiumMonth),
    section_1_3_ok(C),
    \+ fraud_or_misrepresentation(C),
    \+ term_expired(C).

%! section_1_3_ok(+C) is semidet.
%  §1.1(3): the §1.3 condition is "still pending" (the final deadline has not
%  yet arrived, as of the hospitalization) or has "been satisfied in a
%  timely fashion" (the visit and its written confirmation already both
%  happened on time).
section_1_3_ok(C) :- section_1_3_pending(C).
section_1_3_ok(C) :- section_1_3_satisfied(C).

%! section_1_3_pending(+C) is semidet.
%  The 7-month written-confirmation deadline has not yet been reached as of
%  the hospitalization, so §1.3 cannot yet have failed.
section_1_3_pending(C) :-
    claim_hospitalization_month(C, H),
    number(H),
    H < 7.

%! section_1_3_satisfied(+C) is semidet.
%  §1.3: a wellness visit with a qualified medical provider no later than
%  the 6-month anniversary, confirmed in writing no later than the 7-month
%  anniversary.
section_1_3_satisfied(C) :-
    claim_wellness_visit_month(C, VisitMonth),
    no_later_than(VisitMonth, 6),
    claim_wellness_visit_provider_qualified(C, true),
    claim_written_confirmation_month(C, ConfirmMonth),
    no_later_than(ConfirmMonth, 7).

%! fraud_or_misrepresentation(+C) is semidet.
%  §1.2: fraud, or misrepresentation/material withholding, cancels the
%  policy outright, whenever it occurred.
fraud_or_misrepresentation(C) :-
    claim_fraud_month(C, M),
    number(M).
fraud_or_misrepresentation(C) :-
    claim_misrepresentation_month(C, M),
    number(M).

%! term_expired(+C) is semidet.
%  §1.2/§4.6: the policy is automatically canceled once its term has
%  elapsed; the last day (month) of the term itself is still in effect.
term_expired(C) :-
    claim_hospitalization_month(C, H),
    claim_policy_term_months(C, T),
    H > T.

% -----------------------------------------------------------------------------
% §2 BENEFITS
% -----------------------------------------------------------------------------

%! benefit_triggered(+C) is semidet.
%  §2.1: hospitalization must be for sickness or accidental injury.
%  §2.2: only continuous confinement in a US hospital counts, and only up to
%  365 days.
%  §2.3: a claim must be made to the Company setting out the basis for it.
benefit_triggered(C) :-
    claim_hospitalization_ground(C, Ground),
    qualifying_ground(Ground),
    claim_confined_in_us_hospital(C, true),
    claim_continuous_confinement_days(C, Days),
    no_later_than(Days, 365),
    claim_claim_made_setting_out_basis(C, true).

qualifying_ground(sickness).
qualifying_ground(accidental_injury).

% -----------------------------------------------------------------------------
% §3 GENERAL EXCLUSIONS
% -----------------------------------------------------------------------------

%! excluded(+C) is semidet.
%  §3.1: no benefit for sickness/injury arising directly or indirectly out
%  of skydiving, military service, firefighting or police service, or where
%  the claimant's age at hospitalization is 80 or more.
excluded(C) :-
    claim_causes(C, Causes),
    excluded_cause(Causes).
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

excluded_cause(Causes) :- arose_out_of(Causes, skydiving).
excluded_cause(Causes) :- arose_out_of(Causes, military_service).
excluded_cause(Causes) :- arose_out_of(Causes, firefighting).
excluded_cause(Causes) :- arose_out_of(Causes, police_service).

% -----------------------------------------------------------------------------
% §4.2 ARBITRATION
% -----------------------------------------------------------------------------

%! dispute_resolution_ok(+C) is semidet.
%  §4.2.1: vacuously satisfied when no dispute has arisen. When a dispute
%  has arisen, the right to claim is extinguished unless arbitration was
%  commenced within 3 months of the parties becoming unable to settle, and,
%  regardless, a valid arbitration award is a condition precedent to
%  liability.
dispute_resolution_ok(C) :-
    claim_dispute_arisen(C, false).
dispute_resolution_ok(C) :-
    claim_dispute_arisen(C, true),
    \+ arbitration_extinguished(C),
    claim_valid_arbitration_award_issued(C, true).

%! arbitration_extinguished(+C) is semidet.
%  True when the parties became unable to settle and arbitration was not
%  commenced within 3 months of that point (including never commenced).
arbitration_extinguished(C) :-
    claim_unable_to_settle_month(C, UnableMonth),
    number(UnableMonth),
    Deadline is UnableMonth + 3,
    claim_arbitration_commenced_month(C, ArbitrationMonth),
    \+ no_later_than(ArbitrationMonth, Deadline).

%! recovery_timing_ok(+C) is semidet.
%  §4.2.1: in no case may recovery be sought before the expiration of 60
%  days (taken as 2 months, consistent with the schema's month-denominated
%  facts) after written proof of claim has been submitted.
recovery_timing_ok(C) :- \+ premature_recovery(C).

premature_recovery(C) :-
    claim_recovery_sought_month(C, RecoveryMonth),
    number(RecoveryMonth),
    recovery_too_early(C, RecoveryMonth).

recovery_too_early(C, RecoveryMonth) :-
    claim_written_proof_of_claim_month(C, ProofMonth),
    (   number(ProofMonth)
    ->  MinRecoveryMonth is ProofMonth + 2,
        RecoveryMonth < MinRecoveryMonth
    ;   true  % no written proof of claim was ever submitted: any sought
              % recovery is necessarily premature
    ).
