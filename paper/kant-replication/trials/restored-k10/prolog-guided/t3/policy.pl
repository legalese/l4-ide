% policy.pl -- CODEX INSURANCE LIMITED policy: covered/1
%
% Encodes Sections 1 (Policy in Effect and Conditions), 2 (Benefits),
% 3 (General Exclusions) and 4 (General Conditions) of the contract in
% inputs/chubb-policy.txt, against the claim-fact vocabulary and the
% two supporting predicates documented in inputs/schema.md.
%
% Self-contained: no claim facts are asserted here. They are supplied
% per-claim by queries.pl.

% ---------------------------------------------------------------------
% Supporting predicates (verbatim from inputs/schema.md)
% ---------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------
% Top-level rule
% ---------------------------------------------------------------------

%! covered(?C) is semidet.
%  True exactly when a benefit is payable on claim C.
covered(C) :-
    policy_in_effect(C),
    benefit_triggered(C),
    \+ excluded(C),
    claim_properly_made(C),
    \+ premature_recovery(C),
    arbitration_ok(C).

% ---------------------------------------------------------------------
% Section 1 -- Policy in Effect and Conditions
% ---------------------------------------------------------------------

%  1.1: the policy is in effect iff (1) the agreement is signed, (2)
%  the premium has been paid, (3) Section 1.3's wellness-visit /
%  written-confirmation condition is still pending or has been
%  satisfied in a timely fashion as of the time of the hospitalization,
%  and (4) the policy has not otherwise been canceled under 1.2
%  (fraud, misrepresentation, or expiry of the policy term).
policy_in_effect(C) :-
    agreement_signed(C),
    premium_paid(C),
    \+ section_1_3_failed(C),
    \+ fraud_occurred(C),
    \+ misrepresentation_occurred(C),
    \+ policy_term_expired(C).

agreement_signed(C) :-
    claim_agreement_signed(C, true).

premium_paid(C) :-
    claim_premium_paid_month(C, M),
    M \== none.

fraud_occurred(C) :-
    claim_fraud_month(C, M),
    M \== none.

misrepresentation_occurred(C) :-
    claim_misrepresentation_month(C, M),
    M \== none.

%  1.2 last sentence / 4.6: automatic cancellation at the end of the
%  policy term.
policy_term_expired(C) :-
    claim_hospitalization_month(C, H),
    claim_policy_term_months(C, T),
    H > T.

%  Section 1.3: no later than the 7-month anniversary of the effective
%  date, written confirmation must be supplied of a wellness visit --
%  with a qualified medical provider -- occurring no later than the
%  6-month anniversary.
%
%  "Failed" is judged as of the time of hospitalization, since 1.1
%  conditions payment on the policy being in effect "at the time of
%  the hospitalization". Before a deadline has passed as of that time,
%  the condition is merely still pending, which 1.1(3) allows; once a
%  deadline has passed unmet, it can no longer be satisfied "in a
%  timely fashion" and 1.2 deems the policy canceled.
wellness_visit_deadline(6).
written_confirmation_deadline(7).

wellness_visit_ok(C) :-
    claim_wellness_visit_month(C, WV),
    wellness_visit_deadline(D),
    no_later_than(WV, D),
    claim_wellness_visit_provider_qualified(C, true).

written_confirmation_ok(C) :-
    claim_written_confirmation_month(C, WC),
    written_confirmation_deadline(D),
    no_later_than(WC, D).

section_1_3_failed(C) :-
    claim_hospitalization_month(C, H),
    wellness_visit_deadline(WVD),
    H > WVD,
    \+ wellness_visit_ok(C).
section_1_3_failed(C) :-
    claim_hospitalization_month(C, H),
    written_confirmation_deadline(WCD),
    H > WCD,
    \+ written_confirmation_ok(C).

% ---------------------------------------------------------------------
% Section 2 -- Benefits
% ---------------------------------------------------------------------

%  2.1/2.2: the benefit is triggered by confinement -- for at least one
%  day of continuous confinement -- in a hospital in the United
%  States, as a result of sickness or accidental injury. (The 365-day
%  cap in 2.2 limits the period for which the benefit is payable; it
%  does not switch coverage off, so it is not enforced here as an
%  upper bound.)
benefit_triggered(C) :-
    hospitalization_ground_ok(C),
    claim_confined_in_us_hospital(C, true),
    continuous_confinement_ok(C).

hospitalization_ground_ok(C) :-
    claim_hospitalization_ground(C, G),
    ( G == sickness ; G == accidental_injury ).

continuous_confinement_ok(C) :-
    claim_continuous_confinement_days(C, D),
    number(D),
    D > 0.

%  2.3: a claim must be made, setting out the basis for the claim (and
%  for there being no exclusion or cancellation).
claim_properly_made(C) :-
    claim_claim_made_setting_out_basis(C, true).

% ---------------------------------------------------------------------
% Section 3 -- General Exclusions
% ---------------------------------------------------------------------

%  3.1: no benefit is payable for an event causing sickness or
%  accidental injury arising directly or indirectly out of skydiving,
%  military service, firefighting or police service; independently of
%  cause, no benefit is payable if the claimant's age at the time of
%  hospitalization is 80 or over.
excluded(C) :-
    claim_causes(C, Causes),
    ( arose_out_of(Causes, skydiving)
    ; arose_out_of(Causes, military_service)
    ; arose_out_of(Causes, firefighting)
    ; arose_out_of(Causes, police_service)
    ).
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

% ---------------------------------------------------------------------
% Section 4 -- General Conditions
% ---------------------------------------------------------------------

%  4.2.1: any dispute must be referred to arbitration; where a dispute
%  exists, the issuance of a valid arbitration award is a condition
%  precedent to liability. Once the parties are unable to settle,
%  arbitration must commence within three months of that date, or the
%  claim (and any cause of action) is extinguished completely.
arbitration_ok(C) :-
    claim_dispute_arisen(C, DisputeArisen),
    ( DisputeArisen == true
    ->  \+ arbitration_extinguished(C),
        claim_valid_arbitration_award_issued(C, true)
    ;   true
    ).

arbitration_extinguished(C) :-
    claim_unable_to_settle_month(C, UM),
    number(UM),
    claim_arbitration_commenced_month(C, AM),
    Deadline is UM + 3,
    \+ no_later_than(AM, Deadline).

%  4.2.1 last sentence: in no case may recovery be sought before 60
%  days have elapsed since written proof of claim was submitted. The
%  schema's claim facts are in months (fractional months are used
%  elsewhere, e.g. 6.5), so 60 days is taken as 60/30 = 2 months.
premature_recovery(C) :-
    claim_written_proof_of_claim_month(C, WP),
    number(WP),
    claim_recovery_sought_month(C, RS),
    number(RS),
    RS < WP + 2.
