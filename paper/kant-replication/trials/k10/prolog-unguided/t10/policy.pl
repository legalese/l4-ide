% =====================================================================
% policy.pl -- Codex Insurance Limited policy, encoded as Prolog rules.
%
% Rules only: no claim-specific facts are asserted here. Every
% per-claim datum (what caused the hospitalization, the claimant's
% age, relative timings, etc.) is a dynamic predicate whose clauses
% are supplied by queries.pl. Per the task instructions:
%   - all times other than the claimant's age are expressed in months
%     relative to the policy's effective date;
%   - the agreement is always taken to be signed and the premium
%     always taken to be paid on time (Section 1.1, items 1-2), so no
%     predicates are defined for those two items;
%   - whenever a claim-specific fact below is left unasserted for a
%     given claim, that aspect is not the subject of the query and is
%     treated as satisfied (for a condition) or as not triggered (for
%     an exclusion), per the task's Step 2 instructions 6-7.
% =====================================================================

:- dynamic hospitalization_ground/2.       % sickness | accidental_injury | intentional_self_inflicted
:- dynamic caused_by_skydiving/1.
:- dynamic caused_by_military_service/1.
:- dynamic caused_by_firefighter_service/1.
:- dynamic caused_by_police_service/1.
:- dynamic age_at_hospitalization/2.       % absolute age in years
:- dynamic claim_fraud/1.
:- dynamic claim_misrepresentation/1.
:- dynamic claim_material_withholding/1.
:- dynamic wellness_visit_months/2.        % months after effective date the wellness visit occurred
:- dynamic wellness_confirmation_months/2. % months after effective date written confirmation was supplied
:- dynamic hospitalization_time_months/2.  % months after effective date the hospitalization occurred

% queries.pl groups its facts by question rather than by predicate,
% so the clauses of these predicates are not contiguous in that file.
:- discontiguous hospitalization_ground/2.
:- discontiguous age_at_hospitalization/2.
:- discontiguous wellness_confirmation_months/2.
:- discontiguous hospitalization_time_months/2.

% ---------------------------------------------------------------------
% Top level (Section 1.1): a claim is covered when the policy is in
% effect at the time of the hospitalization, the hospitalization is
% for a qualifying sickness or accidental injury, and none of the
% general exclusions (Section 2.1) apply.
% ---------------------------------------------------------------------

covered(Claim) :-
    policy_in_effect(Claim),
    qualifying_hospitalization(Claim),
    \+ general_exclusion_applies(Claim).

% Section 1.1: "... hospitalization for sickness or accidental
% injury ...". A deliberate, self-inflicted act is neither a sickness
% nor an accident. If the claim's ground is not stated at all, that
% aspect is not what the query is testing, so it is assumed to
% qualify.
qualifying_hospitalization(Claim) :-
    ( hospitalization_ground(Claim, Ground)
    ->  ( Ground == sickness ; Ground == accidental_injury )
    ;   true
    ).

% ---------------------------------------------------------------------
% Sections 1.1/1.2: whether the policy is in effect.
%
% Section 1.1 conditions the policy being in effect on: (1) the
% agreement being signed, (2) the premium being paid, (3) the
% Section 1.3 wellness-visit condition being still pending or having
% been satisfied in a timely fashion, and (4) the policy not having
% been canceled. Items (1)-(2) are always true per the task's
% instructions and so are not modeled. Item (3) is exactly the
% negation of the second cancelation ground below ("still pending or
% timely" is the complement of "not satisfied in a timely fashion"),
% so "in effect" reduces to "not canceled".
% ---------------------------------------------------------------------

policy_in_effect(Claim) :-
    \+ canceled(Claim).

% Section 1.2: cancelation is deemed to occur on any of three
% independent grounds.
canceled(Claim) :-
    fraud_misrepresentation_or_withholding(Claim).
canceled(Claim) :-
    \+ wellness_condition_ok(Claim).
canceled(Claim) :-
    \+ term_not_expired(Claim).

fraud_misrepresentation_or_withholding(Claim) :-
    claim_fraud(Claim).
fraud_misrepresentation_or_withholding(Claim) :-
    claim_misrepresentation(Claim).
fraud_misrepresentation_or_withholding(Claim) :-
    claim_material_withholding(Claim).

% Section 1.3: no later than the 7-month anniversary of the effective
% date, written confirmation must be supplied of a wellness visit
% that itself occurred no later than the 6-month anniversary. Each
% half of the condition defaults to satisfied if its timing is not
% stated for the claim, since an unstated timing is not what the
% query is testing.
wellness_condition_ok(Claim) :-
    ( wellness_visit_months(Claim, VisitMonths)
    ->  VisitMonths =< 6
    ;   true
    ),
    ( wellness_confirmation_months(Claim, ConfirmMonths)
    ->  ConfirmMonths =< 7
    ;   true
    ).

% Section 3.6: the policy term runs for one year (12 months) from the
% effective date; Section 1.2 automatically cancels the policy at the
% end of the term. If the hospitalization's timing is not stated, it
% is assumed to fall within the term.
term_not_expired(Claim) :-
    ( hospitalization_time_months(Claim, Months)
    ->  Months =< 12
    ;   true
    ).

% ---------------------------------------------------------------------
% Section 2.1: General exclusions. Each exclusion requires the
% hospitalization to actually arise (directly or indirectly) out of
% the named activity; merely holding a status (e.g. being a serving
% police officer) at the time of the hospitalization, with no causal
% connection to it, does not by itself trigger the exclusion.
% ---------------------------------------------------------------------

general_exclusion_applies(Claim) :-
    caused_by_skydiving(Claim).
general_exclusion_applies(Claim) :-
    caused_by_military_service(Claim).
general_exclusion_applies(Claim) :-
    caused_by_firefighter_service(Claim).
general_exclusion_applies(Claim) :-
    caused_by_police_service(Claim).
general_exclusion_applies(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.
