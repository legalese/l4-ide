% ==========================================================================
% policy.pl -- Prolog encoding of the CODEX INSURANCE LIMITED hospital
% indemnity policy (inputs/chubb-policy.txt).
%
% RULES ONLY. No claim-specific facts are asserted in this file. Every
% predicate that stands for a fact about a particular claim is declared
% dynamic below and is populated per-claim in queries.pl.
%
% Per the task brief: the agreement is assumed signed and the premium is
% assumed paid on time for every claim (Section 1.1, items 1-2), so no
% predicate models those two conditions at all. Also per the task brief,
% every date/time fact (other than the claimant's age) is a number of
% months relative to the policy's effective date -- never an absolute
% date, and never something requiring elapsed-time arithmetic between two
% dates -- so every temporal rule below is a plain comparison against a
% fixed month threshold taken from the contract (6, 7, or 12).
% ==========================================================================

% --------------------------------------------------------------------------
% Claim facts (populated in queries.pl). Declared dynamic so that a claim
% which never asserts one of these simply fails that check cleanly rather
% than raising an "unknown procedure" existence error.
% --------------------------------------------------------------------------

:- dynamic sickness/1.
% sickness(Claim) -- the hospitalization was on account of a sickness
% (Section 2.1).

:- dynamic accidental_injury/1.
% accidental_injury(Claim) -- the hospitalization was on account of an
% accidental injury (Section 2.1). An injury the claimant brought about
% intentionally is neither a sickness nor an ACCIDENTAL injury, so such a
% claim should assert neither this fact nor sickness/1.

:- dynamic cause_of_injury/2.
% cause_of_injury(Claim, Activity) -- the sickness or injury arose directly
% or indirectly out of Activity, where Activity is one of the activities
% named in the General Exclusions (Section 3.1, items 1-4):
%   skydiving, military_service, firefighting_service, police_service.
% Omit this fact entirely for a claim whose cause is not one of those four
% activities. In particular, the claimant merely HOLDING one of the named
% occupations at the time of hospitalization is not by itself enough to
% assert this fact -- Section 3.1 excludes an event that arises "directly
% or indirectly out of" the activity, not merely one that is contemporary
% with it.

:- dynamic claimant_age_at_hospitalization/2.
% claimant_age_at_hospitalization(Claim, Age) -- the claimant's age, in
% years, at the time of the hospitalization (Section 3.1, item 5).

:- dynamic hospitalized_outside_us/1.
% hospitalized_outside_us(Claim) -- the confinement in hospital was NOT in
% a hospital located in the United States (Section 2.2). Omit for a claim
% confined in a US hospital.

:- dynamic wellness_confirmation_month/2.
% wellness_confirmation_month(Claim, Months) -- the number of months after
% the effective date at which written confirmation of the wellness visit
% required by Section 1.3 was supplied to the Company. Omit if no such
% confirmation has yet been supplied (i.e. the Section 1.3 condition is
% still pending, not failed).

:- dynamic wellness_visit_month/2.
% wellness_visit_month(Claim, Months) -- the number of months after the
% effective date at which the underlying wellness visit itself (as opposed
% to the confirmation of it) took place. Only needed if a claim's facts
% distinguish the visit date from the confirmation date; may be omitted
% otherwise.

:- dynamic hospitalization_month/2.
% hospitalization_month(Claim, Months) -- the number of months after the
% effective date at which the hospitalization giving rise to the claim
% occurred. Needed only to test the one-year policy term (Section 4.6).

:- dynamic fraud_or_misrepresentation/1.
% fraud_or_misrepresentation(Claim) -- there was fraud, misrepresentation,
% or material withholding of information by the claimant in connection
% with the policy (Section 1.2 treats all three as equivalent triggers for
% cancelation). Omit for a claim with no such misconduct.

% queries.pl groups each claim's facts together by question rather than by
% predicate, so clauses of the same fact predicate are not textually
% contiguous there. Declare them all discontiguous (in addition to
% dynamic) so that is not treated as a style warning.
:- discontiguous sickness/1.
:- discontiguous accidental_injury/1.
:- discontiguous cause_of_injury/2.
:- discontiguous claimant_age_at_hospitalization/2.
:- discontiguous hospitalized_outside_us/1.
:- discontiguous wellness_confirmation_month/2.
:- discontiguous wellness_visit_month/2.
:- discontiguous hospitalization_month/2.
:- discontiguous fraud_or_misrepresentation/1.

% --------------------------------------------------------------------------
% Section 2.1 / 2.2 -- what kind of event is capable of being covered at
% all, before any exclusion is considered.
% --------------------------------------------------------------------------

% The event triggering hospitalization must be a sickness or an accidental
% injury (Section 2.1).
covered_event(Claim) :- sickness(Claim).
covered_event(Claim) :- accidental_injury(Claim).

% Section 2.2 restricts the payable Daily Hospital Income Benefit to
% confinement in a hospital in the United States. Section 4.1.1 separately
% guarantees that the insured PERIL (the sickness or injury itself) is
% on-cover wherever in the world it occurs; that is a different question
% from where the confinement that would trigger payment takes place. Read
% together: an event happening abroad does not by itself void cover, but a
% hospitalization confined entirely to a non-US hospital has no benefit
% payable under Section 2.2.
confined_appropriately(Claim) :- \+ hospitalized_outside_us(Claim).

% --------------------------------------------------------------------------
% Section 3.1 -- General Exclusions.
% --------------------------------------------------------------------------

excluded(Claim) :- cause_of_injury(Claim, skydiving).
excluded(Claim) :- cause_of_injury(Claim, military_service).
excluded(Claim) :- cause_of_injury(Claim, firefighting_service).
excluded(Claim) :- cause_of_injury(Claim, police_service).
excluded(Claim) :-
    claimant_age_at_hospitalization(Claim, Age),
    Age >= 80.

% --------------------------------------------------------------------------
% Section 1.3 -- the wellness-visit condition, and what it takes for it to
% have FAILED (as opposed to still being pending, or having been met).
% --------------------------------------------------------------------------

% The visit itself must occur no later than the 6th month anniversary of
% the effective date.
condition_1_3_failed(Claim) :-
    wellness_visit_month(Claim, VisitMonths),
    VisitMonths > 6.
% Written confirmation of it must reach the Company no later than the 7th
% month anniversary of the effective date.
condition_1_3_failed(Claim) :-
    wellness_confirmation_month(Claim, ConfirmationMonths),
    ConfirmationMonths > 7.

% --------------------------------------------------------------------------
% Section 4.6 -- the one-year policy term. (Section 1.2 cross-references
% "the policy term described in Section 5 below" for the automatic
% end-of-term cancelation, but Section 5 is "BENEFIT AND PREMIUM AMOUNTS"
% and never mentions a term; the one-year term actually appears in Section
% 4.6. Treated here as a drafting cross-reference slip and encoded from
% Section 4.6's one-year term -- see NOTES.md.)
% --------------------------------------------------------------------------

policy_term_expired(Claim) :-
    hospitalization_month(Claim, Months),
    Months > 12.

% --------------------------------------------------------------------------
% Section 1.2 -- Cancelation.
% --------------------------------------------------------------------------

canceled(Claim) :- fraud_or_misrepresentation(Claim).
canceled(Claim) :- condition_1_3_failed(Claim).
canceled(Claim) :- policy_term_expired(Claim).

% --------------------------------------------------------------------------
% Section 1.1 -- the policy is "in effect" (at the time of the
% hospitalization) whenever it has not been canceled. Items 1-2 of Section
% 1.1 (agreement signed; premium paid) are assumed true throughout, per
% the task brief, so they are not modeled. Item 3 (the Section 1.3
% condition being "still pending or ... satisfied in a timely fashion") is
% exactly the negation of condition_1_3_failed/1 above, so it is already
% folded into "not canceled" together with item 4.
% --------------------------------------------------------------------------

policy_in_effect(Claim) :- \+ canceled(Claim).

% --------------------------------------------------------------------------
% Top-level predicate: does the policy apply to (i.e. is a benefit payable
% for) this claim?
% --------------------------------------------------------------------------

covered(Claim) :-
    covered_event(Claim),
    confined_appropriately(Claim),
    policy_in_effect(Claim),
    \+ excluded(Claim).
