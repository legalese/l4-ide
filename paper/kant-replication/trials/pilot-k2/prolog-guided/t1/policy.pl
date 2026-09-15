% policy.pl — Codex Insurance Limited policy, encoded as covered(C).
%
% covered(C) is true exactly when a benefit is payable on claim C, given the
% claim_* facts asserted for C (see bench/schema-prolog.md) and no others.
%
% This file defines no claim facts — only covered/1, its helper predicates,
% and the two supporting predicates from the schema (reproduced verbatim
% below so the file is self-contained).

% ---------------------------------------------------------------------------
% Supporting predicates (verbatim from the schema — do not redefine).
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% covered(C) — top-level rule.
% ---------------------------------------------------------------------------

%! covered(+C) is semidet.
%  A benefit is payable on C exactly when: the policy is in effect at the
%  time of hospitalization (Section 1), the hospitalization is on a covered
%  ground and not for an excluded cause or age (Sections 1.1, 2.1), and the
%  procedural conditions on arbitration and on seeking recovery are met
%  (Section 3.2.1).
covered(C) :-
    in_effect(C),
    valid_hospitalization_ground(C),
    not_excluded_cause(C),
    not_age_excluded(C),
    arbitration_ok(C),
    recovery_timing_ok(C).

% ---------------------------------------------------------------------------
% Section 1.1 / 1.2 / 1.3 — policy in effect.
% ---------------------------------------------------------------------------

%! in_effect(+C) is semidet.
%  Section 1.1: the policy is in effect if the agreement is signed, the
%  premium has been paid, the Section 1.3 condition is still pending or was
%  satisfied on time, and the policy has not been canceled — for fraud or
%  misrepresentation (Section 1.2), or automatically at the end of the
%  policy term (Section 1.2 / 3.6).
in_effect(C) :-
    claim_agreement_signed(C, true),
    premium_paid(C),
    section_1_3_ok(C),
    not_canceled_for_fraud_or_misrepresentation(C),
    within_policy_term(C).

%! premium_paid(+C) is semidet.
%  Section 1.1(2) / 3.5.1: the premium is due in one lump sum at signing, so
%  it has been "paid" exactly when a month is on record for it.
premium_paid(C) :-
    claim_premium_paid_month(C, M),
    number(M).

%! section_1_3_ok(+C) is semidet.
%  Section 1.3: no later than the 7th month anniversary of the effective
%  date, you supply written confirmation — from the medical provider, of a
%  wellness visit with a qualified provider — that visit itself occurring
%  no later than the 6th month anniversary. Section 1.1(3) treats this as
%  met both while it is still pending (the 7-month deadline has not yet
%  arrived as of the hospitalization) and once it has actually been
%  discharged on time.
section_1_3_ok(C) :-
    claim_hospitalization_month(C, HM),
    (   HM >= 7
    ->  claim_wellness_visit_month(C, WM),
        no_later_than(WM, 6),
        claim_wellness_visit_provider_qualified(C, true),
        claim_written_confirmation_month(C, CM),
        no_later_than(CM, 7)
    ;   true
    ).

%! not_canceled_for_fraud_or_misrepresentation(+C) is semidet.
%  Section 1.2: fraud, or any misrepresentation or material withholding of
%  information, cancels the policy whenever it occurred.
not_canceled_for_fraud_or_misrepresentation(C) :-
    claim_fraud_month(C, none),
    claim_misrepresentation_month(C, none).

%! within_policy_term(+C) is semidet.
%  Section 1.2 / 3.6: the policy is automatically canceled on the last day
%  of the policy term, so the hospitalization must fall on or before it.
within_policy_term(C) :-
    claim_hospitalization_month(C, HM),
    claim_policy_term_months(C, TM),
    no_later_than(HM, TM).

% ---------------------------------------------------------------------------
% Section 1.1 / 2.1 — covered ground and general exclusions.
% ---------------------------------------------------------------------------

%! valid_hospitalization_ground(+C) is semidet.
%  Section 1.1: any benefit is premised on hospitalization for sickness or
%  accidental injury. A hospitalization on neither ground (e.g. a
%  deliberate, non-accidental act) is not a covered event at all.
valid_hospitalization_ground(C) :-
    claim_hospitalization_ground(C, Ground),
    ( Ground == sickness ; Ground == accidental_injury ).

%! not_excluded_cause(+C) is semidet.
%  Section 2.1(1-4): no benefit is paid for sickness or accidental injury
%  arising directly or indirectly out of skydiving, military service,
%  firefighting, or police service.
not_excluded_cause(C) :-
    claim_causes(C, Causes),
    \+ arose_out_of(Causes, skydiving),
    \+ arose_out_of(Causes, military_service),
    \+ arose_out_of(Causes, firefighting),
    \+ arose_out_of(Causes, police_service).

%! not_age_excluded(+C) is semidet.
%  Section 2.1(5): excluded outright when age at the time of hospitalization
%  is 80 or more, independent of cause.
not_age_excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age < 80.

% ---------------------------------------------------------------------------
% Section 3.2.1 — arbitration and the recovery waiting period.
% ---------------------------------------------------------------------------

%! arbitration_ok(+C) is semidet.
%  Where a dispute or disagreement has arisen: arbitration must have been
%  commenced within 3 months of the parties becoming unable to settle it
%  (failing which the claim is extinguished completely), and the issuance
%  of a valid arbitration award is a condition precedent to liability.
%  Where no dispute has arisen, none of this engages.
arbitration_ok(C) :-
    claim_dispute_arisen(C, false).
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_unable_to_settle_month(C, USM),
    number(USM),
    claim_arbitration_commenced_month(C, ACM),
    Limit is USM + 3,
    no_later_than(ACM, Limit),
    claim_valid_arbitration_award_issued(C, true).

%! recovery_timing_ok(+C) is semidet.
%  Recovery may not be sought before the expiration of sixty (60) days —
%  taken here as 2 months, consistently with the month-granularity of every
%  other date in this policy — after written proof of claim was submitted.
%  Not having sought recovery at all cannot itself violate this.
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, none),
    !.
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, RSM),
    number(RSM),
    claim_written_proof_of_claim_month(C, PCM),
    number(PCM),
    RSM >= PCM + 2.
