% =====================================================================
% policy.pl -- Prolog encoding of the CODEX INSURANCE LIMITED hospital
% indemnity policy (Daily Hospital Income Benefit for confinement due
% to sickness or accidental injury).
%
% This file defines RULES ONLY: no claim-specific facts are declared
% here. A "claim" is represented throughout by an opaque identifier
% (an atom such as claim_1) about which queries.pl supplies whatever
% facts are relevant to that scenario, using the predicate names listed
% below. Any fact a scenario omits is, by design, a condition that is
% not in dispute for that scenario, and defaults to the value that
% keeps the policy in force (see the per-predicate notes below).
%
% Units: every time-valued fact is a number of months, possibly
% fractional (e.g. 6.5), measured RELATIVE TO THE POLICY'S EFFECTIVE
% DATE (Section 4.6). The one exception is the claimant's age, which
% is in years.
%
% Out of scope (documented here, not modelled as predicates):
%   - Section 1.1 items 1-2 and Section 4.5 (the agreement has been
%     signed and the premium paid on time) -- assumed true throughout,
%     per the encoding task's own instructions.
%   - Section 2.1/2.3's requirement that a claim be made for a
%     hospitalization due to sickness or accidental injury -- every
%     scenario this file is used with IS such a claim, so no gating
%     predicate is defined for it, by analogy with the point above.
%   - Section 4.2 (arbitration), 4.3 (governing law -- New York), 4.4
%     (US currency) -- procedural/administrative clauses that do not
%     determine whether the policy applies to a claim.
%   - Section 5.1/5.2 (the $500 daily benefit and $2000 premium
%     amounts) -- quantum, not eligibility, and none of the questions
%     this benchmark asks are about dollar amounts; encoding them
%     would also require ground fact literals in this file, which the
%     task instructions forbid.
%
% Predicates defined here (all rules):
%   covered/1                          -- top-level yes/no coverage check
%   policy_in_effect/1                  -- Section 1.1/1.2
%   effective_hospitalization_month/2   -- helper, defaults unstated
%                                          hospitalization timing to month 0
%   policy_term_expired/1               -- Section 1.2 (last sentence) / 4.6
%   condition_1_3_status/3              -- Section 1.3
%   fraud_or_misrepresentation/1        -- Section 1.2 (first sentence)
%   excluded/1                          -- Section 3.1 (General Exclusions)
%
% Optional per-claim facts a scenario in queries.pl may supply (all
% declared dynamic below, so a claim that supplies none of them still
% loads and evaluates without error):
%   hospitalization_month(Claim, Months)         omit to mean month 0
%   wellness_confirmation_month(Claim, Months)    omit to mean "no
%                                                  confirmation yet on
%                                                  record" (pending)
%   age_at_hospitalization(Claim, Years)          omit to mean "the age
%                                                  exclusion is not in issue"
%   caused_by_skydiving(Claim)
%   caused_by_military_service(Claim)
%   caused_by_firefighting_service(Claim)
%   caused_by_police_service(Claim)
%   fraud(Claim)
%   misrepresentation(Claim)
%   material_withholding(Claim)
% =====================================================================

:- dynamic hospitalization_month/2.
:- dynamic wellness_confirmation_month/2.
:- dynamic age_at_hospitalization/2.
:- dynamic caused_by_skydiving/1.
:- dynamic caused_by_military_service/1.
:- dynamic caused_by_firefighting_service/1.
:- dynamic caused_by_police_service/1.
:- dynamic fraud/1.
:- dynamic misrepresentation/1.
:- dynamic material_withholding/1.

% ---------------------------------------------------------------------
% Top-level coverage determination.
%
% Section 2.1: "If you have been confined in a hospital as a result of
% sickness or accidental Injury, we will pay you the Daily Hospital
% Income Benefit ...", subject to the policy being in effect (Section
% 1.1) and to the General Exclusions (Section 3.1) not applying.
% ---------------------------------------------------------------------
covered(Claim) :-
    policy_in_effect(Claim),
    \+ excluded(Claim).

% ---------------------------------------------------------------------
% Section 1.1: the policy is in effect at the time of a hospitalization
% when (limiting ourselves to the conditions this file models; items 1
% and 2 of Section 1.1 are assumed satisfied, see file header):
%   - Condition 1.3 has not FAILED (it may be pending, or satisfied), and
%   - the policy has not been cancelled for fraud/misrepresentation/
%     withholding (Section 1.2, first sentence), and
%   - the one-year policy term has not lapsed (Section 1.2 last
%     sentence / Section 4.6).
% ---------------------------------------------------------------------
policy_in_effect(Claim) :-
    effective_hospitalization_month(Claim, HospMonths),
    condition_1_3_status(Claim, HospMonths, Status),
    Status \= failed,
    \+ fraud_or_misrepresentation(Claim),
    \+ policy_term_expired(Claim).

% The time of hospitalization, relative to the effective date. When a
% scenario does not say when the hospitalization happened, that timing
% is not in dispute for that scenario, so treat it as month 0 (the
% effective date itself), which trivially satisfies every deadline
% checked below. A scenario that does state a time should assert
% hospitalization_month/2 directly, which takes priority.
effective_hospitalization_month(Claim, Months) :-
    hospitalization_month(Claim, Months),
    !.
effective_hospitalization_month(Claim, 0) :-
    \+ hospitalization_month(Claim, _).

% ---------------------------------------------------------------------
% Section 1.2 (last sentence) / Section 4.6: the policy term is one
% year (12 months) from the effective date; the policy is automatically
% cancelled once that term has run.
% ---------------------------------------------------------------------
policy_term_expired(Claim) :-
    effective_hospitalization_month(Claim, HospMonths),
    HospMonths > 12.

% ---------------------------------------------------------------------
% Section 1.3: no later than the 7th month anniversary of the effective
% date, written confirmation of a wellness visit (itself occurring no
% later than the 6th month anniversary) must be supplied to the
% Company. Modelled here as a single "when was confirmation supplied"
% fact, tested against the outer (7-month) deadline -- see NOTES.md for
% why the inner 6-month visit sub-deadline is not modelled as a second,
% independent fact.
%
% Status is one of: satisfied, pending, failed. Section 1.1 treats
% "pending" and "satisfied" alike (both keep the policy in effect);
% only "failed" triggers cancellation under Section 1.2.
% ---------------------------------------------------------------------
condition_1_3_status(Claim, _HospMonths, satisfied) :-
    wellness_confirmation_month(Claim, Months),
    Months =< 7.
condition_1_3_status(Claim, _HospMonths, failed) :-
    wellness_confirmation_month(Claim, Months),
    Months > 7.
condition_1_3_status(Claim, HospMonths, pending) :-
    \+ wellness_confirmation_month(Claim, _),
    HospMonths =< 7.
condition_1_3_status(Claim, HospMonths, failed) :-
    \+ wellness_confirmation_month(Claim, _),
    HospMonths > 7.

% ---------------------------------------------------------------------
% Section 1.2 (first sentence): cancellation for fraud, misrepresentation
% or material withholding of information provided to the Company.
% Three named grounds for one disqualifying condition; a scenario may
% assert any one of them.
% ---------------------------------------------------------------------
fraud_or_misrepresentation(Claim) :- fraud(Claim).
fraud_or_misrepresentation(Claim) :- misrepresentation(Claim).
fraud_or_misrepresentation(Claim) :- material_withholding(Claim).

% ---------------------------------------------------------------------
% Section 3.1 General Exclusions: five independent grounds, any one of
% which removes cover for the event causing the sickness/injury.
% ---------------------------------------------------------------------
excluded(Claim) :- caused_by_skydiving(Claim).
excluded(Claim) :- caused_by_military_service(Claim).
excluded(Claim) :- caused_by_firefighting_service(Claim).
excluded(Claim) :- caused_by_police_service(Claim).
excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.
