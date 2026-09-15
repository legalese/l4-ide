% policy.pl -- CODEX INSURANCE LIMITED hospital indemnity policy, encoded as covered/1.
%
% Section references (e.g. "S1.1") are to the numbered paragraphs of the policy text
% in inputs/chubb-policy.txt. Claim facts (claim_*/2) are defined by the caller
% (see queries.pl); this file only reads them. No claim facts are defined here.

% ---------------------------------------------------------------------------
% Supporting predicates, copied verbatim from inputs/schema.md.
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Top-level rule.
% ---------------------------------------------------------------------------

%! covered(?C) is semidet.
%  True exactly when a benefit is payable on claim C.
covered(C) :-
    policy_in_effect(C),           % S1.1: policy must be in effect at the time of hospitalization
    hospitalization_basis_ok(C),   % S2.1: confinement must result from sickness or accidental injury
    \+ excluded(C),                % S3.1: general exclusions
    confinement_ok(C),             % S2.2: confinement must be in a US hospital, for some positive days
    claim_claim_made_setting_out_basis(C, true), % S2.3: a claim must be made setting out the basis
    arbitration_ok(C),             % S4.2.1: dispute -> arbitration -> valid award, if a dispute arose
    recovery_timing_ok(C).         % S4.2.1: no recovery sought within 60 days of written proof of claim

% ---------------------------------------------------------------------------
% S1.1 / S1.2 / S1.3 -- policy in effect.
% ---------------------------------------------------------------------------

%! policy_in_effect(+C) is semidet.
%  S1.1: the policy is in effect if the agreement is signed, the premium is paid,
%  the S1.3 wellness/confirmation condition is pending-or-satisfied, and the
%  policy has not been canceled (S1.2: fraud/misrepresentation, or the policy
%  term has expired).
policy_in_effect(C) :-
    claim_agreement_signed(C, true),
    premium_paid(C),
    condition_1_3_ok(C),
    \+ term_expired(C),
    \+ fraud_or_misrepresentation(C).

%! premium_paid(+C) is semidet.
%  S1.1(2): the applicable premium has been paid (a month is recorded; none = unpaid).
premium_paid(C) :-
    claim_premium_paid_month(C, PM),
    number(PM).

%! term_expired(+C) is semidet.
%  S1.2 (last sentence) / S4.6: the policy is automatically canceled once the
%  hospitalization falls after the end of the one-year policy term. Hospitalization
%  occurring on the last day of the term is still within the term (cancelation takes
%  effect at midnight ending that day), so this only fires when strictly later.
term_expired(C) :-
    claim_hospitalization_month(C, HM),
    claim_policy_term_months(C, TM),
    HM > TM.

%! fraud_or_misrepresentation(+C) is semidet.
%  S1.2: cancelation is deemed to occur if there is fraud or misrepresentation, at
%  any time (the text ties cancelation to the fact of fraud/misrepresentation, not
%  to any particular date). The policy text also mentions "material withholding of
%  information", for which the claim-fact schema has no separate field; it is not
%  separately modeled here (see NOTES.md).
fraud_or_misrepresentation(C) :-
    claim_fraud_month(C, FM),
    number(FM).
fraud_or_misrepresentation(C) :-
    claim_misrepresentation_month(C, MM),
    number(MM).

%! condition_1_3_ok(+C) is semidet.
%  S1.1(3): the S1.3 condition is "still pending or has been satisfied in a timely
%  fashion". Read relative to the hospitalization that grounds the claim: if the
%  hospitalization occurs no later than the 7-month confirmation deadline, the
%  condition cannot yet have failed, so it is still pending. Once the deadline has
%  passed as of the hospitalization, the condition must actually have been
%  satisfied (see NOTES.md for the judgement call).
condition_1_3_ok(C) :-
    claim_hospitalization_month(C, HM),
    (   no_later_than(HM, 7)
    ->  true
    ;   wellness_condition_satisfied(C)
    ).

%! wellness_condition_satisfied(+C) is semidet.
%  S1.3: written confirmation, from the medical provider, of a wellness visit with a
%  qualified medical provider occurring no later than the 6-month anniversary, must
%  itself be supplied no later than the 7-month anniversary.
wellness_condition_satisfied(C) :-
    claim_wellness_visit_month(C, VM),
    no_later_than(VM, 6),
    claim_wellness_visit_provider_qualified(C, true),
    claim_written_confirmation_month(C, CM),
    no_later_than(CM, 7).

% ---------------------------------------------------------------------------
% S2.1 / S2.2 / S2.3 -- benefits.
% ---------------------------------------------------------------------------

%! hospitalization_basis_ok(+C) is semidet.
%  S2.1: the benefit is payable only for confinement "as a result of sickness or
%  accidental Injury" -- not for confinement on some other basis (e.g. a deliberate,
%  non-accidental act; see claim_hospitalization_ground's "neither" value).
hospitalization_basis_ok(C) :-
    claim_hospitalization_ground(C, Ground),
    member(Ground, [sickness, accidental_injury]).

%! confinement_ok(+C) is semidet.
%  S2.2: the Daily Hospital Income Benefit is payable only for confinement in a
%  hospital in the United States, and only where there is at least one day of
%  continuous confinement. (The 365-day cap in S2.2 limits how many days are
%  compensated; it does not switch coverage off entirely, so it is not enforced
%  as a hard gate here -- see NOTES.md.)
confinement_ok(C) :-
    claim_confined_in_us_hospital(C, true),
    claim_continuous_confinement_days(C, Days),
    number(Days),
    Days >= 1.

% ---------------------------------------------------------------------------
% S3.1 -- general exclusions.
% ---------------------------------------------------------------------------

%! excluded(+C) is semidet.
%  S3.1: no benefit is payable for an event causing sickness or accidental injury
%  arising directly or indirectly out of skydiving, military service, firefighting,
%  or police service, or if age at the time of hospitalization is >= 80.
excluded(C) :-
    claim_causes(C, Causes),
    member(ExCause, [skydiving, military_service, firefighting, police_service]),
    arose_out_of(Causes, ExCause).
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

% ---------------------------------------------------------------------------
% S4.2.1 -- arbitration and recovery timing.
% ---------------------------------------------------------------------------

%! arbitration_ok(+C) is semidet.
%  S4.2.1: if a dispute or disagreement arose, arbitration must have been commenced
%  within 3 months of the date the parties were unable to settle, and a valid
%  arbitration award must have been issued (a condition precedent to liability).
%  If no dispute arose, this clause imposes nothing.
arbitration_ok(C) :-
    claim_dispute_arisen(C, Arisen),
    (   Arisen == true
    ->  claim_unable_to_settle_month(C, UM),
        number(UM),
        claim_arbitration_commenced_month(C, AM),
        no_later_than(AM, UM + 3),
        claim_valid_arbitration_award_issued(C, true)
    ;   true
    ).

%! recovery_timing_ok(+C) is semidet.
%  S4.2.1 (last sentence): recovery may not be sought before the expiration of 60
%  days (approximated here as 2 months, consistent with the month-granularity of
%  the rest of the schema) after written proof of claim has been submitted. If
%  recovery has not been sought, this clause imposes nothing.
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, RM),
    (   number(RM)
    ->  claim_written_proof_of_claim_month(C, PM),
        number(PM),
        RM >= PM + 2
    ;   true
    ).
