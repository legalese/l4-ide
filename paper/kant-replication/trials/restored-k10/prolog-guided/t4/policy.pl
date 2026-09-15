% policy.pl
%
% covered(C) is true exactly when a benefit is payable on claim C, under the
% CODEX INSURANCE LIMITED hospital-indemnity policy in fixtures/chubb-policy.txt.
%
% This file contains only rules (covered/1 and its helpers) plus the two
% supporting predicates reproduced verbatim from bench/schema-prolog.md, so
% that the file is self-contained. It defines no claim facts: every claim_*/2
% fact used below is supplied by the caller (see queries.pl).

% ---------------------------------------------------------------------------
% Supporting predicates (verbatim from bench/schema-prolog.md)
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Top-level rule
% ---------------------------------------------------------------------------

covered(C) :-
    policy_in_effect(C),
    benefit_ground(C),
    confinement_ok(C),
    claim_properly_made(C),
    \+ generally_excluded(C),
    arbitration_precondition_ok(C),
    recovery_not_premature(C).

% ---------------------------------------------------------------------------
% 1. POLICY IN EFFECT AND CONDITIONS (contract §1.1-1.3)
% ---------------------------------------------------------------------------

% §1.1: the policy is in effect, at the time of the hospitalization, if all
% four numbered conditions hold: signed, premium paid, §1.3 pending-or-met,
% and not otherwise canceled (fraud, misrepresentation, or term expiry -- the
% other named grounds for cancellation in §1.2).
policy_in_effect(C) :-
    agreement_signed(C),
    premium_paid(C),
    section_1_3_pending_or_satisfied(C),
    \+ fraud_occurred(C),
    \+ misrepresentation_occurred(C),
    \+ term_expired(C).

% §1.1(1)
agreement_signed(C) :-
    claim_agreement_signed(C, true).

% §1.1(2): the premium for the policy period has been paid, as of the
% hospitalization.
premium_paid(C) :-
    claim_premium_paid_month(C, M),
    claim_hospitalization_month(C, H),
    no_later_than(M, H).

% §1.2: fraud is a ground for cancellation.
fraud_occurred(C) :-
    claim_fraud_month(C, M),
    number(M).

% §1.2: misrepresentation or material withholding is a ground for
% cancellation.
misrepresentation_occurred(C) :-
    claim_misrepresentation_month(C, M),
    number(M).

% §1.2 (last sentence) / §4.6: the policy is automatically canceled at the
% end of its term, so a hospitalization after that point is not covered.
term_expired(C) :-
    claim_hospitalization_month(C, H),
    claim_policy_term_months(C, T),
    \+ no_later_than(H, T).

% §1.1(3) / §1.3: the wellness-visit condition. It is satisfied when the
% visit itself (with a qualified provider) occurred no later than the
% 6-month anniversary of the effective date, and written confirmation of it
% was supplied no later than the 7-month anniversary. Short of outright
% satisfaction, §1.1(3) also treats the condition as "still pending" (and so
% no bar to the policy being in effect) provided the 7-month deadline has
% not yet passed as of the hospitalization AND nothing on record already
% shows a deadline was missed.
section_1_3_pending_or_satisfied(C) :-
    ( section_1_3_satisfied(C)
    ; section_1_3_pending(C)
    ).

section_1_3_satisfied(C) :-
    claim_wellness_visit_month(C, WV),
    no_later_than(WV, 6),
    claim_wellness_visit_provider_qualified(C, true),
    claim_written_confirmation_month(C, WC),
    no_later_than(WC, 7).

section_1_3_pending(C) :-
    claim_hospitalization_month(C, H),
    no_later_than(H, 7),
    \+ section_1_3_already_broken(C).

section_1_3_already_broken(C) :-
    claim_written_confirmation_month(C, WC),
    number(WC),
    WC > 7.
section_1_3_already_broken(C) :-
    claim_wellness_visit_month(C, WV),
    number(WV),
    WV > 6.
section_1_3_already_broken(C) :-
    claim_wellness_visit_provider_qualified(C, false).

% ---------------------------------------------------------------------------
% 2. BENEFITS (contract §2.1-2.3)
% ---------------------------------------------------------------------------

% §2.1: the hospitalization must be as a result of sickness or accidental
% injury (as opposed to, e.g., a deliberate, non-medical act).
benefit_ground(C) :-
    claim_hospitalization_ground(C, Ground),
    ( Ground == sickness ; Ground == accidental_injury ).

% §2.2: the benefit is payable for continuous confinement in a hospital in
% the United States. (The 365-day cap in §2.2 bounds how many days are paid
% for, not whether any benefit is payable at all, so it is not encoded here
% as a coverage gate.)
confinement_ok(C) :-
    claim_confined_in_us_hospital(C, true),
    claim_continuous_confinement_days(C, D),
    number(D),
    D > 0.

% §2.3: a claim must be made setting out the basis for the claim.
claim_properly_made(C) :-
    claim_claim_made_setting_out_basis(C, true).

% ---------------------------------------------------------------------------
% 3. GENERAL EXCLUSIONS (contract §3.1)
% ---------------------------------------------------------------------------

generally_excluded(C) :-
    claim_causes(C, Causes),
    ( arose_out_of(Causes, skydiving)
    ; arose_out_of(Causes, military_service)
    ; arose_out_of(Causes, firefighting)
    ; arose_out_of(Causes, police_service)
    ).
generally_excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    number(Age),
    Age >= 80.

% ---------------------------------------------------------------------------
% 4. GENERAL CONDITIONS (contract §4.2 Arbitration)
%
% §4.1 ("insures You ... anywhere in the world") and §4.3-4.5 (governing
% law, currency, premium mechanics) impose no additional claim-level gate,
% so they have no corresponding rule here.
% ---------------------------------------------------------------------------

% §4.2.1: arbitration is only required where a dispute or disagreement has
% arisen. Where one has, arbitration must have been commenced within three
% months of the parties becoming unable to settle, and must have resulted in
% a valid arbitration award, or the claim is barred.
arbitration_precondition_ok(C) :-
    claim_dispute_arisen(C, Dispute),
    ( Dispute == false
    -> true
    ;  arbitration_completed_in_time(C)
    ).

arbitration_completed_in_time(C) :-
    claim_unable_to_settle_month(C, UM),
    claim_arbitration_commenced_month(C, AM),
    number(UM),
    number(AM),
    AM >= UM,
    AM =< UM + 3,
    claim_valid_arbitration_award_issued(C, true).

% §4.2.1 (final sentence): no recovery may be sought before the expiration
% of sixty days after written proof of claim was submitted. Judgement call:
% the schema tracks this in whole months, so 60 days is treated as 2 months
% (see NOTES.md).
recovery_not_premature(C) :-
    claim_written_proof_of_claim_month(C, PM),
    claim_recovery_sought_month(C, RM),
    number(PM),
    number(RM),
    RM >= PM + 2.
