% =============================================================================
% policy.pl -- Prolog encoding of the CODEX INSURANCE LIMITED policy.
%
% Scope: this file encodes the provisions that determine whether a
% hospitalization claim is COVERED under the policy (Sections 1.1, 1.2, 1.3,
% 2.1, 3.1 and 3.6). Sections 3.2-3.5 (arbitration procedure, governing law,
% currency of payment, premium payment mechanics) govern how a dispute is
% resolved or how money moves, not whether an event is covered, and none of
% the benchmark questions this file is meant to answer turn on them, so they
% are not modeled as callable predicates here.
%
% Per the task brief: the agreement is always assumed signed and the premium
% assumed paid on time (Section 1.1 items 1-2), so those two conditions are
% not modeled at all -- there is nothing for a caller to assert either way.
%
% Time convention: every *_month/2 fact below is a number of months elapsed
% since the policy's effective date (Section 3.6), per the task's instruction
% that all dates/times (other than the claimant's age) are given relative to
% the effective date. age_at_hospitalization/2 is the claimant's age in
% years and is NOT relative to the effective date.
%
% Only RULES are defined below. The predicates a caller must supply facts
% for (in queries.pl) are declared `dynamic` so that a claim which simply
% never mentions one of them (because the task's standing instruction is to
% treat anything not referenced in a query as satisfied / not triggered)
% fails cleanly instead of raising an existence error.
% =============================================================================

:- dynamic hospitalization_event/1.
:- dynamic hospitalization_cause/2.
:- dynamic age_at_hospitalization/2.
:- dynamic hospitalization_month/2.
:- dynamic confirmation_supplied_month/2.
:- dynamic wellness_visit_month/2.
:- dynamic fraud/1.
:- dynamic misrepresentation/1.
:- dynamic material_withholding/1.

% -----------------------------------------------------------------------
% Section 1.1 -- a claim is covered iff (a) it is a hospitalization for
% sickness or accidental injury, (b) the policy is in effect at the time
% of that hospitalization, and (c) no Section 2.1 exclusion applies to it.
% -----------------------------------------------------------------------

covered(Claim) :-
    hospitalization_event(Claim),
    policy_in_effect(Claim),
    \+ policy_excluded(Claim).

% -----------------------------------------------------------------------
% Section 1.1(4) / 1.2 -- the policy is in effect unless it has been
% canceled. (Section 1.1 items 1-2, signature and premium payment, are
% assumed true throughout -- see header -- and are deliberately not
% modeled. Section 1.1 item 3, the Section 1.3 wellness-visit condition,
% is folded into policy_canceled/1 via section_1_3_failed/1, matching
% Section 1.2's own second limb: failing Section 1.3 "in a timely
% fashion" IS a cancellation event, not a separate independent gate.)
% -----------------------------------------------------------------------

policy_in_effect(Claim) :-
    \+ policy_canceled(Claim).

policy_canceled(Claim) :-
    fraud(Claim).
policy_canceled(Claim) :-
    misrepresentation(Claim).
policy_canceled(Claim) :-
    material_withholding(Claim).
policy_canceled(Claim) :-
    section_1_3_failed(Claim).
policy_canceled(Claim) :-
    policy_term_ended(Claim).

% -----------------------------------------------------------------------
% Section 1.3 -- written confirmation from the medical provider of a
% wellness visit (the visit itself occurring no later than the 6-month
% anniversary of the effective date) must be supplied to the Company no
% later than the 7-month anniversary of the effective date. Section 1.2
% treats a failure to satisfy this "in a timely fashion" as a
% cancellation of the policy.
%
% - If the confirmation was supplied after month 7, Section 1.3 failed,
%   regardless of when the underlying visit happened.
% - If the confirmation was supplied by month 7 but the visit it attests
%   to happened after month 6, Section 1.3 also failed.
% - If no confirmation was ever supplied at all, Section 1.3 has only
%   failed once the hospitalization itself occurs at or after month 7
%   (before that, per Section 1.1 item 3, the condition is "still
%   pending" and does not yet defeat coverage).
% -----------------------------------------------------------------------

section_1_3_failed(Claim) :-
    confirmation_supplied_month(Claim, ConfirmedMonth),
    ConfirmedMonth > 7.
section_1_3_failed(Claim) :-
    confirmation_supplied_month(Claim, ConfirmedMonth),
    ConfirmedMonth =< 7,
    wellness_visit_month(Claim, VisitMonth),
    VisitMonth > 6.
section_1_3_failed(Claim) :-
    \+ confirmation_supplied_month(Claim, _),
    hospitalization_month(Claim, HospitalizationMonth),
    HospitalizationMonth >= 7.

% -----------------------------------------------------------------------
% Section 3.6 -- the policy term runs for one year (12 months) from the
% effective date, after which the policy is automatically canceled.
% -----------------------------------------------------------------------

policy_term_ended(Claim) :-
    hospitalization_month(Claim, HospitalizationMonth),
    HospitalizationMonth > 12.

% -----------------------------------------------------------------------
% Section 2.1 -- general exclusions. The policy does not apply to a
% sickness or accidental injury arising directly or indirectly out of one
% of five things: skydiving, military service, firefighter service,
% police service, or the claimant being 80 or older at the time of
% hospitalization. Each exclusion (other than age) is keyed off the CAUSE
% of the hospitalization, not the claimant's occupation or status in
% general -- Section 2.1 excludes sickness/injury "arising ... out of"
% the listed activities, so merely holding one of those jobs at the time
% of an unrelated hospitalization does not itself trigger the exclusion.
%
% Section 3.1 (worldwide, 24-hour coverage) means no geographic fact is
% ever needed here: location never excludes a claim, so it is simply
% never one of the causes checked below.
% -----------------------------------------------------------------------

policy_excluded(Claim) :-
    hospitalization_cause(Claim, skydiving).
policy_excluded(Claim) :-
    hospitalization_cause(Claim, military_service).
policy_excluded(Claim) :-
    hospitalization_cause(Claim, firefighter_service).
policy_excluded(Claim) :-
    hospitalization_cause(Claim, police_service).
policy_excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.
