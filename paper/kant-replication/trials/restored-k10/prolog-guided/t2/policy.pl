% ===========================================================================
% policy.pl
%
% CODEX INSURANCE LIMITED -- Daily Hospital Income policy (inputs/chubb-policy.txt).
% covered(C) succeeds exactly when a benefit is payable on claim C.
%
% Self-contained: includes the two supporting predicates from
% inputs/schema.md verbatim. No claim facts are defined here -- those are
% supplied by whatever caller consults this file (see queries.pl).
% ===========================================================================

% ---------------------------------------------------------------------------
% Supporting predicates (from inputs/schema.md, verbatim). Do not redefine.
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Top level
% ---------------------------------------------------------------------------

covered(C) :-
    policy_in_effect_at_hospitalization(C),   % Section 1
    benefit_triggered(C),                     % Section 2.1
    \+ excluded(C),                           % Section 3.1
    claim_made_properly(C),                   % Section 2.3
    confinement_ok(C),                        % Section 2.2
    arbitration_ok(C),                        % Section 4.2.1 (arbitration)
    recovery_timing_ok(C).                    % Section 4.2.1 (60-day bar)

% ---------------------------------------------------------------------------
% Section 1 -- Policy in effect and conditions
% ---------------------------------------------------------------------------

% 1.1: the policy is in effect at the time of hospitalization iff the
% agreement is signed, the premium has been paid, condition 1.3 is either
% still pending or was satisfied on time, the policy was not cancelled for
% fraud or misrepresentation, and the hospitalization falls within the
% policy term (1.2's automatic cancellation at the term's end).
policy_in_effect_at_hospitalization(C) :-
    claim_agreement_signed(C, true),
    premium_paid(C),
    condition_1_3_ok(C),
    \+ cancelled_for_fraud_or_misrepresentation(C),
    within_policy_term(C).

premium_paid(C) :-
    claim_premium_paid_month(C, M),
    number(M).

% 1.3: no later than month 7, written confirmation from the medical
% provider of a wellness visit (with a qualified provider) that itself
% occurred no later than month 6.
condition_1_3_satisfied(C) :-
    claim_written_confirmation_month(C, CM),
    no_later_than(CM, 7),
    claim_wellness_visit_month(C, WM),
    no_later_than(WM, 6),
    claim_wellness_visit_provider_qualified(C, true).

% 1.1 item 3: at the time of hospitalization, condition 1.3 must either
% already have been satisfied on time, or still be open -- no confirmation
% yet on record, and the month-7 deadline for it not yet reached as of the
% hospitalization. A confirmation already on record but late (fails
% condition_1_3_satisfied/1 and is not `none`) is a completed breach and
% cannot fall back to "still pending" regardless of timing.
condition_1_3_ok(C) :-
    condition_1_3_satisfied(C).
condition_1_3_ok(C) :-
    claim_written_confirmation_month(C, none),
    claim_hospitalization_month(C, HospMonth),
    HospMonth =< 7.

% 1.2: fraud, or misrepresentation/material withholding, cancels the policy
% whenever it occurred.
cancelled_for_fraud_or_misrepresentation(C) :-
    claim_fraud_month(C, FM),
    number(FM).
cancelled_for_fraud_or_misrepresentation(C) :-
    claim_misrepresentation_month(C, MM),
    number(MM).

% 1.2 / 4.6: the policy is automatically cancelled at the end of its term.
within_policy_term(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_policy_term_months(C, Term),
    no_later_than(HospMonth, Term).

% ---------------------------------------------------------------------------
% Section 2 -- Benefits
% ---------------------------------------------------------------------------

% 2.1: confinement as a result of sickness or accidental injury.
benefit_triggered(C) :-
    claim_hospitalization_ground(C, Ground),
    memberchk(Ground, [sickness, accidental_injury]).

% 2.2: the Daily Hospital Income Benefit is payable only for continuous
% confinement in a hospital in the United States. (4.1.1's "anywhere in the
% world" describes where the insured peril -- the sickness or accidental
% injury -- may arise, not where the resulting hospital confinement may be;
% 2.2's US-hospital requirement is specific to this benefit and controls.)
% The 365-day cap bounds how many days are paid, not whether a benefit is
% payable at all, so it is not enforced here as a coverage gate.
confinement_ok(C) :-
    claim_confined_in_us_hospital(C, true),
    claim_continuous_confinement_days(C, Days),
    number(Days),
    Days >= 1.

% 2.3: a claim must be made to the Company setting out the basis for the
% claim (and for there being no exclusion or cancellation).
claim_made_properly(C) :-
    claim_claim_made_setting_out_basis(C, true).

% ---------------------------------------------------------------------------
% Section 3 -- General exclusions
% ---------------------------------------------------------------------------

% 3.1: no benefit for sickness or accidental injury arising directly or
% indirectly out of skydiving, military service, firefighting, or police
% service, or if the claimant's age at hospitalization is 80 or over.
excluded(C) :-
    claim_causes(C, Causes),
    excluded_cause(Cause),
    arose_out_of(Causes, Cause).
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

excluded_cause(skydiving).
excluded_cause(military_service).
excluded_cause(firefighting).
excluded_cause(police_service).

% ---------------------------------------------------------------------------
% Section 4 -- General conditions
% ---------------------------------------------------------------------------

% 4.2.1: where a dispute has arisen, arbitration must be commenced within
% three months of the parties becoming unable to settle, and (since there
% is a dispute) the issuance of a valid arbitration award is a condition
% precedent to liability. Where no dispute has arisen, none of this applies.
arbitration_ok(C) :-
    claim_dispute_arisen(C, false).
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_unable_to_settle_month(C, UM),
    number(UM),
    claim_arbitration_commenced_month(C, AM),
    Limit is UM + 3,
    no_later_than(AM, Limit),
    claim_valid_arbitration_award_issued(C, true).

% 4.2.1: in no case may recovery be sought within sixty (60) days -- taken
% as two months, since claim facts are dated to the month -- of written
% proof of claim being submitted.
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, none).
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, RM),
    number(RM),
    claim_written_proof_of_claim_month(C, PM),
    number(PM),
    RM >= PM + 2.
