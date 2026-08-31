% =============================================================================
% policy.pl -- Rules-only encoding of the CODEX INSURANCE LIMITED hospital
% indemnity policy (Daily Hospital Income Benefit).
%
% This file defines RULES ONLY -- no claim-specific facts. All claim facts
% (the input vocabulary documented below) are supplied by queries.pl, one
% set of facts per claim.
%
% Per the task brief:
%   - the agreement is assumed signed and the premium assumed paid on time,
%     so Section 1.1(1)-(2) are not modelled as separate conditions;
%   - every time value is relative to the effective date of the policy,
%     expressed in months (may be fractional, e.g. 6.5) -- the claimant's
%     age is the one absolute-valued quantity a query may state;
%   - "will my policy apply" is read as "is a benefit payable on this
%     claim", i.e. Sections 2.1-2.3 read together with Sections 1 and 3.
%
% -----------------------------------------------------------------------
% INPUT VOCABULARY (all declared `dynamic`; queries.pl asserts a subset of
% these per claim). Every one of these is a *triggering* fact for an
% outcome unfavourable to coverage; leaving one unasserted for a given
% claim defaults to the reading favourable to coverage. This mirrors the
% task brief's instruction, for each query, to set facts/rules/parameters
% so that every condition/exclusion *not* the subject of that query is
% satisfied / not triggered.
%
%   hospitalized_due_to(Claim, sickness|injury)
%       The medical cause of the hospitalization. Required for every
%       claim -- there is no sensible favourable default for this one.
%       (Section 2.1)
%
%   intentional_self_harm(Claim)
%       Asserted only when the claimant deliberately inflicted the injury
%       on themselves. When asserted, the injury is not "accidental", so
%       it cannot trigger the benefit under 2.1 even absent any Section 3
%       exclusion naming self-harm. (Judgement call -- see NOTES.md.)
%
%   injury_caused_by(Claim, skydiving|military_service|firefighter_service|
%                            police_service)
%       Asserted only when the sickness/injury arose *directly or
%       indirectly out of* one of the named activities (Section 3.1).
%       Mere status (e.g. "I am a serving police officer") without a
%       causal link to the hospitalizing event is NOT this fact --
%       see NOTES.md.
%
%   age_at_hospitalization(Claim, Age)
%       The claimant's age, in years, at the time of hospitalization.
%       (Section 3.1, item 5)
%
%   fraud_or_misrepresentation(Claim)
%       Asserted only when the claimant committed fraud, misrepresentation
%       or material withholding of information. (Section 1.2)
%
%   wellness_confirmation_month(Claim, Month)
%       When (in months after the effective date) written confirmation of
%       the wellness visit was supplied to the Company, if it has been
%       supplied by the time of hospitalization. Left unasserted if no
%       confirmation has been supplied by then. (Section 1.3)
%
%   hospitalization_month(Claim, Month)
%       When (in months after the effective date) the hospitalization
%       occurred. Only needed when timing relative to the 7-month
%       confirmation deadline (and not already settled by
%       wellness_confirmation_month/2) or the 12-month policy term
%       matters.
%
%   confined_outside_us(Claim)
%       Asserted only when the hospital confinement itself took place
%       outside the United States. (Section 2.2; see NOTES.md for the
%       judgement call this reflects, given the tension with 4.1.1.)
% -----------------------------------------------------------------------

:- dynamic hospitalized_due_to/2.
:- dynamic intentional_self_harm/1.
:- dynamic injury_caused_by/2.
:- dynamic age_at_hospitalization/2.
:- dynamic fraud_or_misrepresentation/1.
:- dynamic wellness_confirmation_month/2.
:- dynamic hospitalization_month/2.
:- dynamic confined_outside_us/1.

% -----------------------------------------------------------------------
% Top level (Sections 2.1-2.3 read with Sections 1 and 3): the policy
% applies -- a benefit is payable -- exactly when there is a covered
% medical cause, the policy is in effect at the time of hospitalization,
% no general exclusion (Section 3) applies, and the Section 2.2 location
% condition on the benefit is met.
% -----------------------------------------------------------------------

covered(Claim) :-
    covered_cause(Claim),
    policy_in_effect(Claim),
    \+ general_exclusion(Claim),
    \+ benefit_location_barred(Claim).

% -----------------------------------------------------------------------
% Section 2.1: the medical cause must be a sickness, or an *accidental*
% injury. An injury the claimant intentionally inflicted on themselves is
% not "accidental".
% -----------------------------------------------------------------------

covered_cause(Claim) :-
    hospitalized_due_to(Claim, sickness).
covered_cause(Claim) :-
    hospitalized_due_to(Claim, injury),
    \+ intentional_self_harm(Claim).

% -----------------------------------------------------------------------
% Sections 1.1/1.2: the policy is in effect (at the time of
% hospitalization) exactly when it has not been canceled. Signing and
% premium payment are assumed by the task brief and so are not separate
% conjuncts here.
% -----------------------------------------------------------------------

policy_in_effect(Claim) :-
    \+ canceled(Claim).

% Section 1.2: grounds for cancelation.
canceled(Claim) :-
    fraud_or_misrepresentation(Claim).
canceled(Claim) :-
    wellness_condition_breached(Claim).
canceled(Claim) :-
    policy_term_expired(Claim).

% Section 1.3, as cross-referenced by 1.2: the wellness-visit-confirmation
% condition is breached -- i.e. no longer merely "pending", and not
% "satisfied in a timely fashion" -- exactly when written confirmation is
% supplied later than the 7-month anniversary of the effective date, or
% has not been supplied at all by a hospitalization occurring after that
% anniversary. Before the 7-month mark, with no confirmation yet
% supplied, the condition is still "pending" and is not breached.
%
% (Section 1.3 in fact bundles two deadlines: the wellness visit itself
% occurring by month 6, and confirmation of it being supplied by month 7.
% Every question in this benchmark states only a single relative time,
% phrased as when confirmation/proof of the visit was "provided" or
% "submitted", so this encoding tests compliance against the single,
% controlling 7-month deadline that Section 1.2 itself cross-references
% as the trigger for cancelation. See NOTES.md.)

wellness_condition_breached(Claim) :-
    wellness_confirmation_month(Claim, T),
    T > 7.
wellness_condition_breached(Claim) :-
    \+ wellness_confirmation_month(Claim, _),
    hospitalization_month(Claim, H),
    H > 7.

% Section 4.6, as cross-referenced by 1.2: the policy term is one year
% (12 months) from the effective date; hospitalization after that point
% is outside the term, and the policy has by then been canceled.
policy_term_expired(Claim) :-
    hospitalization_month(Claim, H),
    H > 12.

% -----------------------------------------------------------------------
% Section 3.1: general exclusions. An exclusion applies only when the
% sickness/injury actually arose (directly or indirectly) out of the
% named activity -- mere status at the time of hospitalization is not
% enough -- or when the claimant's age at hospitalization is 80 or above.
% -----------------------------------------------------------------------

general_exclusion(Claim) :-
    injury_caused_by(Claim, skydiving).
general_exclusion(Claim) :-
    injury_caused_by(Claim, military_service).
general_exclusion(Claim) :-
    injury_caused_by(Claim, firefighter_service).
general_exclusion(Claim) :-
    injury_caused_by(Claim, police_service).
general_exclusion(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.

% -----------------------------------------------------------------------
% Section 2.2: the Daily Hospital Income Benefit is payable only for
% confinement in a hospital in the United States. Section 4.1.1
% separately establishes that the insured peril (the sickness/accidental
% injury itself) is covered worldwide; there is no separate predicate for
% 4.1.1 here because it is a permissive clause with nothing to gate on --
% it is read as meaning confined_outside_us/1 is about where the claimant
% was hospitalized, not about where the injury/sickness was incurred.
% See NOTES.md for the judgement call this reflects.
% -----------------------------------------------------------------------

benefit_location_barred(Claim) :-
    confined_outside_us(Claim).
