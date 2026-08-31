% policy.pl
%
% Encoding of the CODEX INSURANCE LIMITED hospital-income policy
% (fixtures/chubb-policy.txt) as Prolog rules.
%
% Design notes (see NOTES.md for the judgement calls behind these choices):
%
%   * All claim-specific facts are supplied by queries.pl, via the
%     claim_*/N predicates declared `dynamic` below. This file (policy.pl)
%     contains no facts of its own, only general rules, per the task
%     instructions.
%   * Every date/time fact is a number of months elapsed since the
%     policy's effective date (never an absolute date), except the
%     claimant's age, which is in years, as instructed.
%   * Section 1 ("policy in effect") is modelled by policy_in_effect/1
%     and canceled/1.
%   * Section 1.3 (the wellness-visit condition) is modelled by
%     wellness_condition_ok/1: the wellness visit itself must occur
%     within 6 months of the effective date, and written confirmation
%     of it must be supplied within 7 months. If a claim does not say
%     when (or whether) either event happened, that is read as "not
%     yet due" / "still pending" -- which section 1.1(3) treats as
%     just as good as having been satisfied -- so the default for
%     each is a value that clears its own deadline.
%   * Section 2 (benefits) is modelled by triggers_benefit/1: the
%     hospitalization must be for "sickness" or "accidental Injury"
%     (2.1) -- a deliberate, self-inflicted act is neither -- the
%     hospital must be "in the United States" (2.2, taken literally),
%     and the confinement must not exceed the 365-day cap (2.2).
%   * Section 3 (general exclusions) is modelled by excluded/1. Each
%     activity-based exclusion requires the sickness/injury to have
%     *arisen from* the listed activity (directly or indirectly), not
%     merely that the claimant held that occupation/status at the time
%     of hospitalization. The age exclusion requires age >= 80 (3.1.5).
%   * Section 4.2 (arbitration), 4.3 (governing law), 4.4 (currency)
%     and 4.5 (premium mechanics) are procedural/boilerplate terms that
%     do not bear on whether a described hypothetical event is a
%     covered event, so they are not modelled as coverage conditions.

% ---------------------------------------------------------------------
% Claim-fact vocabulary.
%
% Declared dynamic so that a fact simply being absent for a given
% claim makes the corresponding call fail (rather than raising an
% "unknown procedure" existence error) -- this is what lets queries.pl
% state only the facts each question actually mentions.
% ---------------------------------------------------------------------

:- dynamic claim_cause/2.                 % claim_cause(Claim, sickness | accidental_injury | Other)
:- dynamic claim_activity/2.              % claim_activity(Claim, skydiving | military_service | firefighting_duty | police_duty)
:- dynamic claim_age/2.                   % claim_age(Claim, AgeInYears)
:- dynamic claim_hospital_abroad/1.       % claim_hospital_abroad(Claim) -- flag: hospital confinement was outside the US
:- dynamic claim_confirmation_month/2.    % claim_confirmation_month(Claim, MonthsAfterEffectiveDate)
:- dynamic claim_visit_month/2.           % claim_visit_month(Claim, MonthsAfterEffectiveDate)
:- dynamic claim_hospitalization_month/2. % claim_hospitalization_month(Claim, MonthsAfterEffectiveDate)
:- dynamic claim_fraud/1.                 % claim_fraud(Claim) -- flag: fraud/misrepresentation/material withholding occurred
:- dynamic claim_confinement_days/2.      % claim_confinement_days(Claim, Days) -- days of continuous hospital confinement

% ---------------------------------------------------------------------
% Small accessors with contract-faithful defaults, used so that a
% fact a question does not mention is treated as satisfying its own
% condition rather than as unknown/erroring.
% ---------------------------------------------------------------------

% Written confirmation of the wellness visit: if no month is on file
% for this claim, no late confirmation has been reported, so default
% to month 0 (comfortably inside the 7-month deadline).
confirmation_month(Claim, M) :-
    ( claim_confirmation_month(Claim, M0) -> M = M0 ; M = 0 ).

% The wellness visit itself: same default reasoning, comfortably
% inside the 6-month deadline.
visit_month(Claim, V) :-
    ( claim_visit_month(Claim, V0) -> V = V0 ; V = 0 ).

% Time of hospitalization relative to the effective date: if not on
% file, treat it as happening immediately (month 0), safely inside
% the one-year policy term.
hosp_month(Claim, T) :-
    ( claim_hospitalization_month(Claim, T0) -> T = T0 ; T = 0 ).

% Days of continuous confinement: if not on file, treat it as a
% single day, safely inside the 365-day cap.
confinement_days(Claim, D) :-
    ( claim_confinement_days(Claim, D0) -> D = D0 ; D = 1 ).

% ---------------------------------------------------------------------
% Section 1.3 -- the wellness-visit condition.
%
% "No later than the 7th month anniversary of the effective date of
% this policy, you will supply us with written confirmation from the
% medical provider in question of a wellness visit for yourself with
% a qualified medical provider occurring no later than the 6th month
% anniversary of the effective date of this policy."
% ---------------------------------------------------------------------

wellness_condition_ok(Claim) :-
    visit_month(Claim, V),
    V =< 6,
    confirmation_month(Claim, M),
    M =< 7.

% ---------------------------------------------------------------------
% Section 4.6 / 1.2 -- the one-year policy term.
% ---------------------------------------------------------------------

within_policy_term(Claim) :-
    hosp_month(Claim, T),
    T =< 12.

% ---------------------------------------------------------------------
% Section 2.2 -- 365-day cap on continuous confinement.
% ---------------------------------------------------------------------

within_confinement_limit(Claim) :-
    confinement_days(Claim, D),
    D =< 365.

% ---------------------------------------------------------------------
% Section 1.2 -- cancellation.
%
% Cancellation occurs on fraud/misrepresentation/material withholding,
% on a definitive failure of the section 1.3 wellness condition, or on
% expiry of the one-year policy term.
% ---------------------------------------------------------------------

canceled(Claim) :- claim_fraud(Claim).
canceled(Claim) :- \+ wellness_condition_ok(Claim).
canceled(Claim) :- \+ within_policy_term(Claim).

% ---------------------------------------------------------------------
% Section 1.1 -- policy in effect.
%
% Conditions 1 (signed) and 2 (premium paid) are stipulated true by
% the task instructions and are therefore not modelled as facts.
% Condition 3 (the 1.3 wellness condition, "still pending or ... has
% been satisfied in a timely fashion") and condition 4 ("not
% canceled") collapse into a single check here: a 1.3 condition that
% has definitively failed is exactly what section 1.2 treats as a
% cancellation trigger, so there is no separate state that is
% "neither pending nor satisfied, yet also not cancelled".
% ---------------------------------------------------------------------

policy_in_effect(Claim) :- \+ canceled(Claim).

% ---------------------------------------------------------------------
% Section 3 -- general exclusions.
%
% Each activity-based exclusion requires the sickness/injury-causing
% event to have arisen (directly or indirectly) *from* the listed
% activity -- not merely that the claimant held that status/occupation
% at the time of hospitalization, with no causal link to the event.
% ---------------------------------------------------------------------

activity_exclusion(Claim) :- claim_activity(Claim, skydiving).
activity_exclusion(Claim) :- claim_activity(Claim, military_service).
activity_exclusion(Claim) :- claim_activity(Claim, firefighting_duty).
activity_exclusion(Claim) :- claim_activity(Claim, police_duty).

age_exclusion(Claim) :- claim_age(Claim, Age), Age >= 80.

excluded(Claim) :- activity_exclusion(Claim).
excluded(Claim) :- age_exclusion(Claim).

% ---------------------------------------------------------------------
% Sections 2.1/2.2 -- the benefit itself.
% ---------------------------------------------------------------------

qualifying_cause(Claim) :- claim_cause(Claim, sickness).
qualifying_cause(Claim) :- claim_cause(Claim, accidental_injury).

hospital_in_us(Claim) :- \+ claim_hospital_abroad(Claim).

triggers_benefit(Claim) :-
    qualifying_cause(Claim),
    hospital_in_us(Claim),
    within_confinement_limit(Claim).

% ---------------------------------------------------------------------
% Top-level: is the claim covered?
% ---------------------------------------------------------------------

covered(Claim) :-
    policy_in_effect(Claim),
    triggers_benefit(Claim),
    \+ excluded(Claim).
