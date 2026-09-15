% ============================================================================
% queries.pl
%
% Nine claims (claim_1 .. claim_9), one per benchmark question, plus the
% q1/0 .. q9/0 predicates the harness calls. Each q_N succeeds exactly when
% the answer to question N is "yes" (the policy applies) and fails when the
% answer is "no".
%
% Every question carries this standing preamble (queries-blind.md):
%   "Assuming all other conditions are met and no other exclusions apply
%   (where by 'other' I mean anything not referenced in the query that
%   follows)" -- and, per the paper's prompts, that the agreement is signed
%   and the premium paid on time.
%
% So for every claim below, facts that the question does not mention are
% set to values that satisfy the policy's conditions and trigger none of
% its exclusions, per TASK.md Step 2 instructions 6-7. Facts the question
% does mention are transcribed as given, in months elapsed since the
% effective date (never as absolute dates), except the claimant's age.
% ============================================================================

% The claim-fact predicates below are declared dynamic in policy.pl, but
% that only silences the cross-file "already defined elsewhere" warning.
% Facts are grouped by claim (question) rather than by predicate, for
% readability and auditability, so each predicate's clauses are genuinely
% scattered through this file; :- discontiguous says that is intentional.
:- discontiguous hospitalization_cause/2.
:- discontiguous hospitalization_time/2.
:- discontiguous age_at_hospitalization/2.
:- discontiguous activity/2.
:- discontiguous wellness_visit_occurred/2.
:- discontiguous wellness_confirmation_submitted/2.

% ---- Q1: hospitalized by burns suffered while doing my duty as a
% firefighter. ----
% "while doing my duty as a firefighter" directly ties the injury's cause to
% fire-fighter service, so it arises out of an excluded activity (Sec.
% 2.1.3). Age and timing are not referenced by the question, so they are set
% to unexceptional defaults that trigger no other exclusion and satisfy the
% Sec. 1.3 condition (by simply not putting it in issue).
hospitalization_cause(claim_1, accidental_injury).
activity(claim_1, firefighting).
age_at_hospitalization(claim_1, 30).

q1 :- covered(claim_1).

% ---- Q2: 78 years old at the time of hospitalization. ----
% Only age is referenced. 78 is under the Sec. 2.1.5 threshold of 80, so the
% age exclusion does not apply. The cause of hospitalization is not
% referenced, so it is set to an unexceptional "sickness" that plainly
% qualifies under Sec. 1.1 and triggers no Sec. 2.1 activity exclusion.
hospitalization_cause(claim_2, sickness).
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% ---- Q3: hospitalized for pneumonia 5 months after the effective date;
% age 65 at the time of hospitalization. ----
% Pneumonia is a sickness. Age 65 is well under the Sec. 2.1.5 threshold.
% Hospitalization at month 5 is within the one-year term (Sec. 3.6) and
% falls before the Sec. 1.3 confirmation deadline (month 7) is even due;
% the wellness-visit condition is not referenced, so it is left unasserted
% (treated, per condition_1_3_ok/1, as not in issue).
hospitalization_cause(claim_3, sickness).
hospitalization_time(claim_3, 5).
age_at_hospitalization(claim_3, 65).

q3 :- covered(claim_3).

% ---- Q4: hospitalized due to a fall while traveling abroad; confirmation
% of the wellness visit given 8 months after the effective date. ----
% A fall is an accidental injury; travelling abroad is expressly covered by
% Sec. 3.1's worldwide, 24-hour cover, so it is not itself a fact this
% encoding needs to react to. Confirmation at month 8 is after the Sec. 1.3
% deadlines (visit by month 6, confirmation by month 7); the question gives
% only one date, which is read as the date of both the visit and its
% confirmation (see NOTES.md). That single date already misses the earlier
% (month-6) threshold, so this claim fails Sec. 1.3 regardless. Age is not
% referenced, so it is set to an unexceptional default.
hospitalization_cause(claim_4, accidental_injury).
wellness_visit_occurred(claim_4, 8).
wellness_confirmation_submitted(claim_4, 8).
age_at_hospitalization(claim_4, 30).

q4 :- covered(claim_4).

% ---- Q5: hospitalized for punching my own face to show off for my
% friends; no fraud or misrepresentation. ----
% This is a deliberate, self-inflicted act, not a sickness and not an
% accidental injury, so it does not reach the qualifying_hospitalization/1
% predicate at all (see NOTES.md) -- the claim fails the basic Sec. 1.1
% coverage trigger, independent of the Sec. 1.2/2.1 machinery. The express
% denial of fraud/misrepresentation in the question is honoured simply by
% never asserting fraud_or_misrepresentation/1 for this claim. Age is not
% referenced, so it is set to an unexceptional default.
hospitalization_cause(claim_5, intentional_self_inflicted_act).
age_at_hospitalization(claim_5, 30).

q5 :- covered(claim_5).

% ---- Q6: hospitalized due to an injury sustained while skydiving; age 79
% at the time of hospitalization; proof of the wellness visit provided 6.5
% months after the effective date. ----
% Skydiving is an excluded activity (Sec. 2.1.1) directly causing the
% injury. Age 79 is under the Sec. 2.1.5 threshold of 80, so age is not
% independently disqualifying. The wellness-visit date (6.5 months, read as
% both the visit and its confirmation, as in Q4) also misses the month-6
% deadline, so Sec. 1.3 independently fails too; either reason on its own
% is enough for the policy not to apply.
hospitalization_cause(claim_6, accidental_injury).
activity(claim_6, skydiving).
age_at_hospitalization(claim_6, 79).
wellness_visit_occurred(claim_6, 6.5).
wellness_confirmation_submitted(claim_6, 6.5).

q6 :- covered(claim_6).

% ---- Q7: hospitalized for a heart attack; proof of the wellness visit
% submitted 2 months after the effective date; age 75 at the time of
% hospitalization. ----
% A heart attack is a sickness. Age 75 is under the Sec. 2.1.5 threshold.
% The wellness visit/confirmation at month 2 is comfortably within both the
% month-6 and month-7 Sec. 1.3 deadlines. No excluded activity is in play.
hospitalization_cause(claim_7, sickness).
wellness_visit_occurred(claim_7, 2).
wellness_confirmation_submitted(claim_7, 2).
age_at_hospitalization(claim_7, 75).

q7 :- covered(claim_7).

% ---- Q8: hospitalized after being injured in a military training
% exercise; the hospitalization occurred within the policy term; no
% fraud. ----
% "injured in a military training exercise" directly ties the injury's
% cause to military service, so it arises out of an excluded activity (Sec.
% 2.1.2). The question itself confirms the hospitalization falls within the
% one-year term (Sec. 3.6). The express denial of fraud is honoured by
% never asserting fraud_or_misrepresentation/1 for this claim. Age and the
% wellness-visit condition are not referenced, so they are left at
% unexceptional defaults.
hospitalization_cause(claim_8, accidental_injury).
activity(claim_8, military_service).
hospitalization_time(claim_8, 1).
age_at_hospitalization(claim_8, 30).

q8 :- covered(claim_8).

% ---- Q9: hospitalized due to my son biting me in the ankle; proof of the
% wellness visit provided 6 months after the effective date; serving as a
% police officer at the time of hospitalization. ----
% Being bitten by one's own son is an accidental injury with no causal
% connection to police duties. Sec. 2.1.4 excludes sickness/injury "arising
% directly or indirectly out of ... [s]ervice in the police" -- a causal
% requirement, not a mere-employment-status one -- so simply being a police
% officer at the time, with no link between that service and the ankle
% bite, does not trigger it (see NOTES.md); no activity/2 fact is asserted
% for this claim. The wellness visit/confirmation at month 6 satisfies both
% the month-6 and month-7 Sec. 1.3 deadlines exactly. Age is not
% referenced, so it is set to an unexceptional default.
hospitalization_cause(claim_9, accidental_injury).
wellness_visit_occurred(claim_9, 6).
wellness_confirmation_submitted(claim_9, 6).
age_at_hospitalization(claim_9, 30).

q9 :- covered(claim_9).
