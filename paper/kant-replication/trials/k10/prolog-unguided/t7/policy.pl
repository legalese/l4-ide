% =============================================================================
% Codex Insurance Limited -- Policy Encoding (Prolog)
% =============================================================================
%
% This file defines RULES ONLY: no claim-specific facts are asserted here.
% Per-claim facts belong in queries.pl, which is consulted after this file.
%
% ----------------------------------------------------------------------------
% Time convention
% ----------------------------------------------------------------------------
% Every date/time in this encoding (other than the claimant's age) is
% expressed as a number of months elapsed SINCE THE EFFECTIVE DATE of the
% policy (the effective date itself = month 0). The claimant's age is an
% absolute number of years. No predicate ever needs to compute an interval
% between two dates; every comparison is against a fixed contractual
% threshold (6 months, 7 months, 12 months, or 80 years).
%
% ----------------------------------------------------------------------------
% Expected input facts (asserted in queries.pl)
% ----------------------------------------------------------------------------
%   hospitalization_time(Claim, Months)
%       Time of the hospitalization for the sickness/accidental injury on
%       which the claim is premised, in months since the effective date.
%
%   claimant_age(Claim, Age)
%       The claimant's age, in years, at the time of the hospitalization.
%
%   wellness_visit_time(Claim, Months)
%       Time at which the Section 1.3 wellness visit itself took place, in
%       months since the effective date.
%
%   wellness_confirmation_time(Claim, Months)
%       Time at which written confirmation of that wellness visit was
%       supplied to the Company, in months since the effective date.
%
%   cause(Claim, Cause)
%       Zero, one, or more causes (direct or indirect) of the sickness or
%       accidental injury underlying the claim. Cause is an atom. The
%       atoms skydiving, military_service, firefighter_service and
%       police_service are recognised by Section 2.1(1)-(4); any other
%       atom (heart_attack, pneumonia, fall, ...) is purely descriptive
%       and triggers no exclusion.
%
%   fraud_or_misrepresentation(Claim)
%       Holds (no second argument) if the claimant committed fraud,
%       misrepresentation, or material withholding of information as
%       described in Section 1.2.
%
% All of the above are declared dynamic so that a claim which simply has
% no fact for one of them (e.g. no cause/2 fact at all, meaning no
% recognised cause is alleged) fails cleanly instead of raising an
% "unknown procedure" existence error.
% ----------------------------------------------------------------------------

:- dynamic hospitalization_time/2.
:- dynamic claimant_age/2.
:- dynamic wellness_visit_time/2.
:- dynamic wellness_confirmation_time/2.
:- dynamic cause/2.
:- dynamic fraud_or_misrepresentation/1.

% =============================================================================
% Section 1.1 -- Policy in effect
% =============================================================================
% "The payment of any benefit under this policy is conditioned on the
% policy being in effect at the time of the hospitalization ... The policy
% will be in effect if: (1) this agreement is signed, (2) the applicable
% premium has been paid, (3) the condition set out in Section 1.3 is still
% pending or has been satisfied in a timely fashion, and (4) the policy
% has not been canceled."
%
% Per the task brief, signature (1) and premium payment (2) are assumed
% throughout and are not modelled as conditions here.

policy_applies(Claim) :-
    policy_in_effect(Claim),
    \+ excluded(Claim).

policy_in_effect(Claim) :-
    \+ section_1_3_failed(Claim),
    \+ canceled(Claim).

% =============================================================================
% Section 1.2 -- Cancelation
% =============================================================================
% Cancelation is deemed to occur on any of:
%  (a) fraud, misrepresentation, or material withholding of information
%      provided to the Company;
%  (b) the Section 1.3 condition not having been satisfied in a timely
%      fashion (also captured directly in policy_in_effect/1 above, but
%      repeated here since 1.2 names it as a cancelation trigger too);
%  (c) automatic cancelation at the end of the one-year policy term
%      (Section 3.6), i.e. the hospitalization occurs at or after the
%      12-month anniversary of the effective date.

canceled(Claim) :-
    fraud_or_misrepresentation(Claim).
canceled(Claim) :-
    section_1_3_failed(Claim).
canceled(Claim) :-
    policy_term_expired(Claim).

% Section 3.6: the policy runs for one year (12 months) from the
% effective date, unless previously canceled under Section 1.
policy_term_expired(Claim) :-
    hospitalization_time(Claim, T),
    T >= 12.

% =============================================================================
% Section 1.3 -- Wellness-visit confirmation condition
% =============================================================================
% "No later than the 7th month anniversary of the effective date of this
% policy, you will supply us with written confirmation from the medical
% provider in question of a wellness visit for yourself with a qualified
% medical provider occurring no later than the 6th month anniversary of
% the effective date of this policy."
%
% This is two independent deadlines: the visit itself must occur by
% month 6, and written confirmation of it must be supplied by month 7.
% Missing either deadline is a failure of the Section 1.3 condition, and
% (via Section 1.2) triggers cancelation. Absent any evidence that a
% deadline has been missed, the condition is "still pending" (Section
% 1.1(3)) and does not by itself prevent the policy from being in effect.

section_1_3_failed(Claim) :-
    wellness_confirmation_time(Claim, C),
    C > 7.
section_1_3_failed(Claim) :-
    wellness_visit_time(Claim, V),
    V > 6.

% =============================================================================
% Section 2.1 -- General exclusions
% =============================================================================
% Items (1)-(4) exclude "any event causing sickness or accidental injury
% arising directly or indirectly out of" the named activity: the activity
% must be a CAUSE of the sickness or accidental injury, not merely a fact
% about the claimant's occupation or status at the time of hospitalization.
% This is modelled by keying the exclusion off cause/2, which represents
% the cause of the hospitalization -- not the claimant's status.
%
% Item (5) is different in kind: unlike (1)-(4) it is a status test on
% the claimant's age at the time of the hospitalization, with no causal
% requirement ("if your age at the time of the hospitalization is equal
% to or greater than 80 years of age").

excluded(Claim) :- cause(Claim, skydiving).
excluded(Claim) :- cause(Claim, military_service).
excluded(Claim) :- cause(Claim, firefighter_service).
excluded(Claim) :- cause(Claim, police_service).

excluded(Claim) :-
    claimant_age(Claim, Age),
    Age >= 80.

% =============================================================================
% Section 3 -- General conditions not modelled as coverage restrictions
% =============================================================================
% 3.1 The policy covers the claimant worldwide, 24 hours a day: there is
%     no geographic or time-of-day predicate to check, because no such
%     fact can ever narrow coverage under this policy.
% 3.2 Arbitration is a dispute-resolution / claims-procedure clause
%     (including a 60-day pre-suit waiting period and a 3-month
%     limitation period for commencing arbitration after a dispute
%     arises); it does not bear on whether a given hospitalization is,
%     in principle, covered, so it is not modelled as an exclusion.
% 3.3 Choice of law (New York) -- not a coverage condition.
% 3.4 Currency of payment -- not a coverage condition.
% 3.5 Premium payable in a lump sum at signing -- assumed satisfied per
%     the task brief (see note at top of file).
% 3.6 Policy term -- the one-year duration is modelled above via
%     policy_term_expired/1; the "effective date" itself is the origin
%     (month 0) of every relative time value in this encoding.
