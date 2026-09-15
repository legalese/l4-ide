% ===========================================================================
% CODEX INSURANCE LIMITED — policy encoding
% ===========================================================================
%
% This file encodes the RULES of the policy only. It defines no facts about
% any particular claim; per-claim facts belong in queries.pl.
%
% Time convention: every date/time fact about a claim (other than the
% claimant's age) is expressed as a number of months elapsed since the
% policy's effective date (the date the Company countersigned the policy,
% Section 3.6). The claimant's age is in years. There is never a need to
% compare two absolute dates.
%
% Per the task instructions, the agreement is always taken to have been
% signed and the premium to have been paid on time (Section 1.1, items 1
% and 2), so no predicate is defined for either condition.

% ---------------------------------------------------------------------------
% Dynamic declarations for every per-claim fact this policy consults.
% Declaring these dynamic means a claim that simply omits one of these
% facts causes the dependent check to fail cleanly (as "not shown to be the
% case") rather than raising an existence_error, and it also lets the
% per-claim facts in queries.pl appear in any order without a "clauses not
% together" warning.
% ---------------------------------------------------------------------------

:- dynamic wellness_visit_month/2.
:- dynamic wellness_confirmation_month/2.
:- dynamic fraud_or_misrepresentation/1.
:- dynamic material_withholding/1.
:- dynamic hospitalization_month/2.
:- dynamic age_at_hospitalization/2.
:- dynamic cause_activity/2.
:- dynamic dispute_exists/1.
:- dynamic arbitration_commenced_in_time/1.
:- dynamic valid_arbitration_award_issued/1.
:- dynamic proof_of_claim_submitted_days_ago/2.

% ---------------------------------------------------------------------------
% Top level.
% ---------------------------------------------------------------------------
% A claim is covered exactly when: the policy is in effect, the event is
% not subject to a General Exclusion, and the two Section 3.2 conditions
% precedent to the Company's liability (arbitration, and the 60-day
% waiting period) are satisfied.

covered(Claim) :-
    policy_in_effect(Claim),
    \+ policy_excluded(Claim),
    arbitration_condition_satisfied(Claim),
    waiting_period_satisfied(Claim).

% ---------------------------------------------------------------------------
% Section 1.1 — Policy in effect and conditions.
% ---------------------------------------------------------------------------
% "The policy will be in effect if: (1) signed, (2) premium paid, (3) the
% condition set out in Section 1.3 is still pending or has been satisfied
% in a timely fashion, and (4) the policy has not been canceled."
%
% (1) and (2) are assumed always true (see header) and are not encoded.
% (3) is captured by the *absence* of a demonstrated 1.3 failure: as long
% as no fact shows condition 1.3 to have been missed, it counts as either
% "still pending" or "satisfied", either of which keeps the policy in
% effect.
% (4) is captured by canceled/1 below.

policy_in_effect(Claim) :-
    \+ condition_1_3_failed(Claim),
    \+ canceled(Claim),
    \+ policy_term_expired(Claim).

% ---------------------------------------------------------------------------
% Section 1.2 — Cancelation.
% ---------------------------------------------------------------------------
% Cancelation is deemed to occur on: fraud, misrepresentation or material
% withholding of information, OR condition 1.3 not being satisfied in a
% timely fashion. (The separate ground of automatic cancelation "at
% midnight ... on the last day of the policy term" is Section 3.6's
% one-year term, handled as policy_term_expired/1 below, since it turns on
% the same one-year clock rather than on anything claim-specific.)

canceled(Claim) :-
    fraud_or_misrepresentation(Claim).
canceled(Claim) :-
    material_withholding(Claim).
canceled(Claim) :-
    condition_1_3_failed(Claim).

% ---------------------------------------------------------------------------
% Section 1.3 — the wellness-visit condition.
% ---------------------------------------------------------------------------
% "No later than the 7th month anniversary of the effective date ... you
% will supply us with written confirmation ... of a wellness visit ...
% occurring no later than the 6th month anniversary of the effective
% date."
%
% This is two timely sub-conditions: the wellness visit itself must occur
% within 6 months, and written confirmation of it must be supplied within
% 7 months. Failing either means condition 1.3 was not satisfied in a
% timely fashion.

condition_1_3_failed(Claim) :-
    wellness_confirmation_month(Claim, ConfirmationMonth),
    ConfirmationMonth > 7.
condition_1_3_failed(Claim) :-
    wellness_visit_month(Claim, VisitMonth),
    VisitMonth > 6.

% ---------------------------------------------------------------------------
% Section 3.6 — Policy Term.
% ---------------------------------------------------------------------------
% The policy runs for one year (12 months) from the effective date and is
% automatically canceled at its expiry, independent of any other ground of
% cancelation.

policy_term_expired(Claim) :-
    hospitalization_month(Claim, Month),
    Month > 12.

% ---------------------------------------------------------------------------
% Section 2.1 — General Exclusions.
% ---------------------------------------------------------------------------
% "Your policy will not apply to ... any event causing sickness or
% accidental injury arising directly or indirectly out of: (1) Skydiving;
% (2) Service in the military; (3) Service as a fire fighter; (4) Service
% in the police; or (5) [being] 80 years of age or older at the time of
% the hospitalization."
%
% Items 1-4 exclude an event only when the sickness or injury itself
% arises out of that activity — not merely because the claimant happens to
% hold that occupation at the time of hospitalization for some unrelated
% cause. cause_activity/2 is therefore meant to record what the
% hospitalization arose out of, not the claimant's occupation as such.

policy_excluded(Claim) :-
    cause_activity(Claim, skydiving).
policy_excluded(Claim) :-
    cause_activity(Claim, military_service).
policy_excluded(Claim) :-
    cause_activity(Claim, firefighter_service).
policy_excluded(Claim) :-
    cause_activity(Claim, police_service).
policy_excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.

% ---------------------------------------------------------------------------
% Section 3.2 — Arbitration.
% ---------------------------------------------------------------------------
% Where a dispute or disagreement exists, referring it to arbitration
% (commenced within 3 months of the parties being unable to settle) and
% the issuance of a valid arbitration award are conditions precedent to
% the Company's liability. Absent any dispute, this condition is
% automatically satisfied — there is nothing to arbitrate.

arbitration_condition_satisfied(Claim) :-
    \+ dispute_exists(Claim).
arbitration_condition_satisfied(Claim) :-
    dispute_exists(Claim),
    arbitration_commenced_in_time(Claim),
    valid_arbitration_award_issued(Claim).

% 3.2.1 also bars recovery on the policy until 60 days after written proof
% of claim has been submitted. Absent any submitted proof of claim, this
% condition is automatically satisfied.

waiting_period_satisfied(Claim) :-
    \+ proof_of_claim_submitted_days_ago(Claim, _).
waiting_period_satisfied(Claim) :-
    proof_of_claim_submitted_days_ago(Claim, Days),
    Days >= 60.

% ---------------------------------------------------------------------------
% Clauses considered but not encoded as operative rules.
% ---------------------------------------------------------------------------
% Section 3.1 (worldwide, 24-hour coverage) is a grant of scope, not a
% restriction: there is no geographic or time-of-day condition to encode,
% which is precisely why nothing here ever tests location or time of day.
% Sections 3.3-3.5 (governing law, currency of payment, premium payable in
% one lump sum) go to the administration of the policy, not to whether a
% given claim is covered, and so have no bearing on covered/1.
