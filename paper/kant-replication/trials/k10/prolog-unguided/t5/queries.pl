% ===========================================================================
% Queries against the CODEX INSURANCE LIMITED policy encoding.
% ===========================================================================
%
% Standing preamble (applies to every question): assume all conditions for
% the policy to apply that are unrelated to the question are met, and no
% exclusion unrelated to the question applies. Concretely, for every claim
% below we fix the following "background" facts to values that satisfy the
% corresponding condition, then override only what the question actually
% puts in issue:
%   - age_at_hospitalization: a young default (30) unless the question
%     gives an age.
%   - hospitalization_month: an early default (1) unless the question
%     gives a time of hospitalization relative to the effective date.
%   - wellness_visit_month / wellness_confirmation_month: an early default
%     (1), well inside both the 6- and 7-month deadlines, unless the
%     question gives a time for the wellness-visit confirmation.
%   - fraud_or_misrepresentation, material_withholding: never asserted
%     (i.e. false) for any claim — no question describes either occurring.
%   - dispute_exists, proof_of_claim_submitted_days_ago: never asserted
%     for any claim — no question describes a dispute or a submitted
%     proof of claim, so the Section 3.2 conditions are vacuously
%     satisfied.
%   - cause_activity: asserted only when the hospitalization itself arose
%     out of one of the four listed activities; not asserted merely
%     because the claimant holds a relevant occupation.
%
% Each of these fact predicates is declared dynamic in policy.pl already;
% they are additionally declared discontiguous here because the facts
% below are grouped by claim (question) rather than by predicate.

:- discontiguous age_at_hospitalization/2.
:- discontiguous hospitalization_month/2.
:- discontiguous wellness_visit_month/2.
:- discontiguous wellness_confirmation_month/2.
:- discontiguous cause_activity/2.

% ---------------------------------------------------------------------------
% Q1. Hospitalized by burns suffered while doing my duty as a firefighter.
% ---------------------------------------------------------------------------
% The injury arose directly out of service as a fire fighter (Section
% 2.1, item 3).

age_at_hospitalization(claim_1, 30).
hospitalization_month(claim_1, 1).
wellness_visit_month(claim_1, 1).
wellness_confirmation_month(claim_1, 1).
cause_activity(claim_1, firefighter_service).

q1 :- covered(claim_1).

% ---------------------------------------------------------------------------
% Q2. 78 years old at the time of hospitalization.
% ---------------------------------------------------------------------------
% Age is below the "equal to or greater than 80" threshold in Section
% 2.1, item 5. No cause of hospitalization is given, and none of the
% four activity-based exclusions is in issue.

age_at_hospitalization(claim_2, 78).
hospitalization_month(claim_2, 1).
wellness_visit_month(claim_2, 1).
wellness_confirmation_month(claim_2, 1).

q2 :- covered(claim_2).

% ---------------------------------------------------------------------------
% Q3. Hospitalized for pneumonia 5 months after the effective date; age 65
% at the time of hospitalization.
% ---------------------------------------------------------------------------
% Pneumonia is a sickness, not one of the five enumerated exclusions.
% 5 months is comfortably inside the one-year policy term (Section 3.6).
% Age 65 is below the Section 2.1 item-5 threshold.

age_at_hospitalization(claim_3, 65).
hospitalization_month(claim_3, 5).
wellness_visit_month(claim_3, 1).
wellness_confirmation_month(claim_3, 1).

q3 :- covered(claim_3).

% ---------------------------------------------------------------------------
% Q4. Hospitalized due to a fall while traveling abroad; confirmation of
% the wellness visit was given 8 months after the effective date.
% ---------------------------------------------------------------------------
% Being abroad does not matter: Section 3.1.1 insures the claimant
% worldwide. A fall is an accidental injury, not one of the five
% enumerated exclusions. But confirmation at month 8 is later than the
% Section 1.3 deadline of "no later than the 7th month anniversary", so
% condition 1.3 was not satisfied in a timely fashion and the policy was
% canceled under Section 1.2. (The wellness visit's own, earlier,
% 6-month deadline is left at its default-compliant value: the question
% only puts the confirmation date in issue.)

age_at_hospitalization(claim_4, 30).
hospitalization_month(claim_4, 1).
wellness_visit_month(claim_4, 1).
wellness_confirmation_month(claim_4, 8).

q4 :- covered(claim_4).

% ---------------------------------------------------------------------------
% Q5. Hospitalized for punching my own face to show off for my friends; no
% fraud or misrepresentation was committed.
% ---------------------------------------------------------------------------
% Judgement call: Section 2.1's five exclusions are the only grounds on
% which "your policy will not apply", and none of them addresses
% self-inflicted or foolhardy conduct. Rather than import an unwritten
% "intentional/self-inflicted injury" exclusion, this encoding takes
% Section 2.1 as exhaustive of the General Exclusions and does not treat
% this claim as excluded on that ground. The question's own assurance
% that there was no fraud or misrepresentation confirms Section 1.2's
% other cancelation ground is not in issue either, so
% fraud_or_misrepresentation/1 is left unasserted (false) for this claim.

age_at_hospitalization(claim_5, 30).
hospitalization_month(claim_5, 1).
wellness_visit_month(claim_5, 1).
wellness_confirmation_month(claim_5, 1).

q5 :- covered(claim_5).

% ---------------------------------------------------------------------------
% Q6. Hospitalized due to an injury sustained while skydiving; age 79 at
% the time of hospitalization; proof of the wellness visit provided 6.5
% months after the effective date.
% ---------------------------------------------------------------------------
% Skydiving is excluded directly under Section 2.1, item 1, regardless of
% age or the timeliness of the wellness-visit confirmation. Age 79 is
% still below the item-5 threshold of 80, and confirmation at 6.5 months
% is within the Section 1.3 7-month deadline, so neither of those two
% facts independently defeats coverage; the skydiving exclusion does.

age_at_hospitalization(claim_6, 79).
hospitalization_month(claim_6, 1).
wellness_visit_month(claim_6, 1).
wellness_confirmation_month(claim_6, 6.5).
cause_activity(claim_6, skydiving).

q6 :- covered(claim_6).

% ---------------------------------------------------------------------------
% Q7. Hospitalized for a heart attack; proof of the wellness visit was
% submitted 2 months after the effective date; age 75 at the time of
% hospitalization.
% ---------------------------------------------------------------------------
% A heart attack is a sickness, not one of the five enumerated
% exclusions. Age 75 is below the item-5 threshold. Confirmation at
% month 2 is well within the Section 1.3 7-month deadline.

age_at_hospitalization(claim_7, 75).
hospitalization_month(claim_7, 1).
wellness_visit_month(claim_7, 1).
wellness_confirmation_month(claim_7, 2).

q7 :- covered(claim_7).

% ---------------------------------------------------------------------------
% Q8. Hospitalized after being injured in a military training exercise;
% the hospitalization occurred within the policy term; no fraud was
% committed.
% ---------------------------------------------------------------------------
% The injury arose directly out of service in the military (Section 2.1,
% item 2). "Occurred within the policy term" is encoded directly as a
% hospitalization_month within the Section 3.6 one-year term.

age_at_hospitalization(claim_8, 30).
hospitalization_month(claim_8, 1).
wellness_visit_month(claim_8, 1).
wellness_confirmation_month(claim_8, 1).
cause_activity(claim_8, military_service).

q8 :- covered(claim_8).

% ---------------------------------------------------------------------------
% Q9. Hospitalized due to my son biting me in the ankle; proof of the
% wellness visit was provided 6 months after the effective date; I was
% serving as a police officer at the time of hospitalization.
% ---------------------------------------------------------------------------
% Judgement call: Section 2.1, item 4 excludes an event arising "directly
% or indirectly out of ... service in the police" — the hospitalization
% must arise out of that service, not merely coincide with the claimant's
% occupation. A son's bite to the ankle has no causal connection to
% police duty, so cause_activity(claim_9, police_service) is deliberately
% NOT asserted here; being a police officer at the time is treated as
% incidental, on the same footing as any other occupation. Confirmation
% at month 6 is within the Section 1.3 7-month deadline (and, since a
% confirmation cannot predate the visit it confirms, also implies the
% underlying visit was no later than month 6).

age_at_hospitalization(claim_9, 30).
hospitalization_month(claim_9, 1).
wellness_visit_month(claim_9, 1).
wellness_confirmation_month(claim_9, 6).

q9 :- covered(claim_9).
