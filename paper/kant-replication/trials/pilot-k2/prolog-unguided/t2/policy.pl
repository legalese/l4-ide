% =====================================================================
% policy.pl -- Prolog encoding of the CODEX INSURANCE LIMITED policy
%
% Convention: every time-valued fact is a number of MONTHS relative to
% the policy's effective date (never an absolute calendar date), per
% the task's own instructions -- there is never a need to compute the
% elapsed time between two dates. Age is the one absolute quantity,
% expressed in years as at the time of hospitalization.
%
% This file defines RULES ONLY. Per-claim facts belong in queries.pl.
% =====================================================================

% ---------------------------------------------------------------------
% Dynamic declarations for the per-claim facts this policy depends on.
% Declaring them dynamic means that if queries.pl does not assert a
% given fact for a given claim, calling it simply FAILS rather than
% raising an "unknown procedure" existence_error -- which is exactly
% the behaviour we want for a condition a query leaves unmentioned
% (see Section 1.1(3): the Section 1.3 condition may be "still
% pending", i.e. neither satisfied nor yet violated).
% ---------------------------------------------------------------------
:- dynamic fraud/1.
:- dynamic misrepresentation/1.
:- dynamic material_withholding/1.
:- dynamic wellness_visit_time/2.
:- dynamic wellness_confirmation_time/2.
:- dynamic hospitalization_time/2.
:- dynamic hospitalization_cause/2.
:- dynamic age_at_hospitalization/2.

% ---------------------------------------------------------------------
% Top level.
%
% Section 1.1: "The payment of any benefit under this policy is
% conditioned on the policy being in effect at the time of the
% hospitalization for sickness or accidental injury on which the claim
% for such benefit is premised."
%
% Per the task's own instructions we assume the agreement is signed
% and the premium has been paid, so of the four numbered sub-conditions
% of Section 1.1 only (3) and (4) remain to be encoded -- and (3) turns
% out to be the mirror image of one of the cancelation grounds in
% Section 1.2 ("the condition set out in Section 1.3 has not been
% satisfied in a timely fashion"), so both (3) and (4) are captured
% together simply by "the policy has not been canceled", together with
% the general exclusions of Section 2.1.
% ---------------------------------------------------------------------
covered(Claim) :-
    policy_in_effect_at_hospitalization(Claim),
    \+ excluded(Claim).

policy_in_effect_at_hospitalization(Claim) :-
    \+ canceled(Claim).

% ---------------------------------------------------------------------
% Section 1.2: cancelation.
%
%   "Cancelation will be deemed to have occurred if there is fraud, or
%   any misrepresentation or material withholding of any information
%   provided by you to the Company in connection with any
%   communication or information relating to this policy, or if the
%   condition set out in Section 1.3 has not been satisfied in a
%   timely fashion. It will also be automatically canceled at
%   midnight ... on the last day of the policy term described in
%   Section 5 [i.e. Section 3.6] below."
% ---------------------------------------------------------------------
canceled(Claim) :- fraud(Claim).
canceled(Claim) :- misrepresentation(Claim).
canceled(Claim) :- material_withholding(Claim).
canceled(Claim) :- wellness_condition_failed(Claim).
canceled(Claim) :- term_expired(Claim).

% ---------------------------------------------------------------------
% Section 1.3: the wellness-visit condition.
%
%   "No later than the 7th month anniversary of the effective date of
%   this policy, you will supply us with written confirmation from the
%   medical provider in question of a wellness visit for yourself with
%   a qualified medical provider occurring no later than the 6th month
%   anniversary of the effective date of this policy."
%
% Two distinct deadlines are set: the visit itself must occur within 6
% months of the effective date, and written confirmation of it must
% reach the insurer within 7 months. Violating either one means the
% condition was "not satisfied in a timely fashion" per Section 1.2.
% If a claim gives no value for one of these two facts, that half of
% the condition simply cannot be shown to have failed here -- i.e. it
% is treated as "still pending", exactly as Section 1.1(3) contemplates.
% ---------------------------------------------------------------------
wellness_condition_failed(Claim) :-
    wellness_visit_time(Claim, VisitMonths),
    VisitMonths > 6.
wellness_condition_failed(Claim) :-
    wellness_confirmation_time(Claim, ConfirmMonths),
    ConfirmMonths > 7.

% ---------------------------------------------------------------------
% Section 3.6: policy term.
%
%   "...will last for a period of one year from that date [the
%   effective date], unless previously canceled pursuant to Section 1
%   above."
% ---------------------------------------------------------------------
term_expired(Claim) :-
    hospitalization_time(Claim, Months),
    Months > 12.

% ---------------------------------------------------------------------
% Section 2.1: general exclusions.
%
%   "Your policy will not apply to, and no benefit will be paid with
%   respect to, any event causing sickness or accidental injury
%   arising directly or indirectly out of:
%     1. Skydiving; or
%     2. Service in the military; or
%     3. Service as a fire fighter; or
%     4. Service in the police; or
%     5. If your age at the time of the hospitalization is equal to or
%        greater than 80 years of age."
%
% Items 1-4 exclude an event by its CAUSE, not by the claimant's
% occupation or status in the abstract: the text excludes an event
% "arising ... out of" one of those activities, so what matters is
% whether that activity is what caused the sickness or injury being
% claimed for -- not whether the claimant happens to hold that job or
% role at the time of hospitalization. hospitalization_cause/2
% therefore records the operative CAUSE of the event, e.g. a serving
% police officer injured by an unrelated domestic accident is NOT
% excluded by item 4, because service in the police did not cause the
% injury (see NOTES.md for discussion of this judgement call).
% ---------------------------------------------------------------------
excluded(Claim) :- hospitalization_cause(Claim, skydiving).
excluded(Claim) :- hospitalization_cause(Claim, military_service).
excluded(Claim) :- hospitalization_cause(Claim, firefighting_service).
excluded(Claim) :- hospitalization_cause(Claim, police_service).
excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.
