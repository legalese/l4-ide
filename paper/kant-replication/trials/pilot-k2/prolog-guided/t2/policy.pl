% ---------------------------------------------------------------------------
% covered(+C) is semidet.
%
% True exactly when a benefit is payable on claim C, per the Codex Insurance
% policy. Structure mirrors the policy's own section numbers:
%
%   Section 1.1/1.2  -- the policy must be "in effect" at the time of the
%                        hospitalization: signed, premium paid, the Section
%                        1.3 wellness-visit/confirmation condition met or
%                        still pending, not canceled for fraud/misrepresentation,
%                        and within the policy term.
%   Section 1.1      -- the hospitalization itself must be for sickness or
%                        accidental injury (not "neither").
%   Section 2.1      -- none of the five general exclusions may apply.
%   Section 3.2.1    -- if a dispute has arisen, its arbitration preconditions
%                        must be met; in all cases, the 60-day post-proof-of-
%                        claim waiting period must be respected.
%
% This file is self-contained: it includes the two supporting predicates
% from the schema verbatim, and defines no claim_* facts of its own.
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
    policy_in_effect_at_hospitalization(C),
    hospitalization_ground_valid(C),
    \+ generally_excluded(C),
    arbitration_precondition_met(C),
    proof_of_claim_waiting_period_met(C).

% ---------------------------------------------------------------------------
% Section 1.1 / 1.2 -- policy in effect at the time of hospitalization
% ---------------------------------------------------------------------------

policy_in_effect_at_hospitalization(C) :-
    claim_agreement_signed(C, true),
    premium_paid(C),
    section_1_3_condition(C),
    \+ fraud_occurred(C),
    \+ misrepresentation_occurred(C),
    hospitalization_within_policy_term(C).

% 1.1(2): the applicable premium has been paid.
premium_paid(C) :-
    claim_premium_paid_month(C, PM),
    number(PM).

% 1.2: fraud triggers cancelation, whenever it occurred.
fraud_occurred(C) :-
    claim_fraud_month(C, FM),
    number(FM).

% 1.2: misrepresentation or material withholding of information triggers
% cancelation. The schema collapses "misrepresentation or material
% withholding" into the single claim_misrepresentation_month fact.
misrepresentation_occurred(C) :-
    claim_misrepresentation_month(C, MM),
    number(MM).

% 1.2: the policy is automatically canceled at the end of the policy term.
hospitalization_within_policy_term(C) :-
    claim_hospitalization_month(C, HM),
    claim_policy_term_months(C, TM),
    HM =< TM.

% 1.1(3): the Section 1.3 condition is still pending, or has been satisfied
% in a timely fashion. (These two clauses are the complement of 1.2's "has
% not been satisfied in a timely fashion" cancelation trigger -- there is no
% separate cancelation check to add for Section 1.3.)
section_1_3_condition(C) :- section_1_3_satisfied(C).
section_1_3_condition(C) :- section_1_3_pending(C).

% 1.3: a wellness visit with a qualified provider no later than month 6,
% confirmed in writing to the Company no later than month 7.
section_1_3_satisfied(C) :-
    claim_wellness_visit_month(C, VM),
    no_later_than(VM, 6),
    claim_wellness_visit_provider_qualified(C, true),
    claim_written_confirmation_month(C, WM),
    no_later_than(WM, 7).

% "Still pending": no written confirmation has been supplied yet, and the
% month-7 deadline by which Section 1.3 must be resolved has not yet passed
% as of the hospitalization.
section_1_3_pending(C) :-
    claim_written_confirmation_month(C, none),
    claim_hospitalization_month(C, HM),
    HM =< 7.

% ---------------------------------------------------------------------------
% Section 1.1 -- the claim must be premised on sickness or accidental injury
% ---------------------------------------------------------------------------

hospitalization_ground_valid(C) :-
    claim_hospitalization_ground(C, Ground),
    ( Ground == sickness ; Ground == accidental_injury ).

% ---------------------------------------------------------------------------
% Section 2.1 -- general exclusions
% ---------------------------------------------------------------------------

% 2.1(1)-(4): the hospitalization must not arise directly or indirectly out
% of skydiving, military service, firefighting, or police service.
generally_excluded(C) :-
    claim_causes(C, Causes),
    ( arose_out_of(Causes, skydiving)
    ; arose_out_of(Causes, military_service)
    ; arose_out_of(Causes, firefighting)
    ; arose_out_of(Causes, police_service)
    ).
% 2.1(5): age at the time of hospitalization must be under 80.
generally_excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

% ---------------------------------------------------------------------------
% Section 3.2.1 -- arbitration and the proof-of-claim waiting period
% ---------------------------------------------------------------------------

% No dispute has arisen: the arbitration machinery never engages.
arbitration_precondition_met(C) :-
    claim_dispute_arisen(C, false).
% A dispute has arisen: arbitration must have been commenced within three
% months of the parties becoming unable to settle, and must have produced a
% valid arbitration award (a condition precedent to liability).
arbitration_precondition_met(C) :-
    claim_dispute_arisen(C, true),
    claim_unable_to_settle_month(C, USM), number(USM),
    claim_arbitration_commenced_month(C, ACM), number(ACM),
    ACM =< USM + 3,
    claim_valid_arbitration_award_issued(C, true).

% "In no case shall You seek to recover on this Policy before the expiration
% of sixty (60) days [approximated here as 2 months, the schema's finest
% grain] after written proof of claim has been submitted." Vacuous unless
% both a submission month and a recovery-seeking month are on record.
proof_of_claim_waiting_period_met(C) :-
    claim_written_proof_of_claim_month(C, WPCM),
    claim_recovery_sought_month(C, RSM),
    ( WPCM == none -> true
    ; RSM == none -> true
    ; RSM >= WPCM + 2
    ).
