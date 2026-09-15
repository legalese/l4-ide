% =============================================================================
% Nine benchmark queries against policy.pl
% =============================================================================
% Each claim (claim_1 .. claim_9) corresponds to one question (Q1..Q9) from
% fixtures/queries-blind.md. Facts are set so that every condition or
% exclusion NOT referenced by the question text is satisfied in the
% policyholder's favour -- per the standing preamble ("assuming all other
% conditions are met and no other exclusions apply, where by 'other' I mean
% anything not referenced in the query that follows") -- and only the facts
% the question text actually gives are taken from that text.
%
% Baseline "safe" values used whenever a question does not speak to that
% axis at all:
%   hospitalization_time        3    (well inside the 12-month policy term)
%   claimant_age                40   (well under the age-80 exclusion)
%   wellness_visit_time         3    (well inside the 6-month visit deadline)
%   wellness_confirmation_time  4    (well inside the 7-month deadline)
%   no cause/2 fact for any recognised exclusionary cause
%   no fraud_or_misrepresentation/1 fact (no fraud/misrepresentation alleged)
%
% Note on "proof/confirmation ... provided/given/submitted N months after
% the effective date" (Q4, Q6, Q7, Q9): this phrase describes the act of
% supplying written confirmation to the Company under Section 1.3, so it
% is encoded as wellness_confirmation_time/2, not wellness_visit_time/2.
% None of the nine questions independently states when the underlying
% wellness visit itself took place, so wellness_visit_time is left at its
% safe baseline (3) throughout.
% =============================================================================

:- discontiguous hospitalization_time/2.
:- discontiguous claimant_age/2.
:- discontiguous wellness_visit_time/2.
:- discontiguous wellness_confirmation_time/2.
:- discontiguous cause/2.

% ---- Q1: "will my policy apply if I was hospitalized by burns suffered
% while doing my duty as a firefighter?"
% The injury arises directly out of service as a firefighter (Sec 2.1(3)).
cause(claim_1, firefighter_service).
claimant_age(claim_1, 40).
hospitalization_time(claim_1, 3).
wellness_visit_time(claim_1, 3).
wellness_confirmation_time(claim_1, 4).

q1 :- policy_applies(claim_1).

% ---- Q2: "will my policy apply if I am 78 years old at the time of
% hospitalization?"
claimant_age(claim_2, 78).
hospitalization_time(claim_2, 3).
wellness_visit_time(claim_2, 3).
wellness_confirmation_time(claim_2, 4).

q2 :- policy_applies(claim_2).

% ---- Q3: "will my policy apply if I was hospitalized for pneumonia 5
% months after the policy's effective date, and my age at the time of
% hospitalization is 65?"
cause(claim_3, pneumonia).
hospitalization_time(claim_3, 5).
claimant_age(claim_3, 65).
wellness_visit_time(claim_3, 3).
wellness_confirmation_time(claim_3, 4).

q3 :- policy_applies(claim_3).

% ---- Q4: "will my policy apply if I was hospitalized due to a fall while
% traveling abroad and I had given confirmation of my wellness visit 8
% months after the policy's effective date?"
% Section 3.1 already covers the claimant worldwide, so "traveling
% abroad" needs no fact of its own. Confirmation at month 8 is later than
% the month-7 deadline fixed by Section 1.3.
cause(claim_4, fall).
wellness_confirmation_time(claim_4, 8).
claimant_age(claim_4, 40).
hospitalization_time(claim_4, 3).
wellness_visit_time(claim_4, 3).

q4 :- policy_applies(claim_4).

% ---- Q5: "will my policy apply if I was hospitalized for punching my own
% face to show off for my friends and I did not commit fraud or
% misrepresentation?"
% Judgement call: the policy text supplied for this encoding contains no
% exclusion for intentionally self-inflicted injury (Section 2.1 lists
% only skydiving, military/firefighter/police service, and age >= 80), so
% none is modelled here. "I did not commit fraud or misrepresentation" is
% represented by simply not asserting fraud_or_misrepresentation(claim_5).
cause(claim_5, self_inflicted_injury).
claimant_age(claim_5, 40).
hospitalization_time(claim_5, 3).
wellness_visit_time(claim_5, 3).
wellness_confirmation_time(claim_5, 4).

q5 :- policy_applies(claim_5).

% ---- Q6: "will my policy apply if I was hospitalized due to an injury
% sustained while skydiving, my age at the time of hospitalization was
% 79, and proof of my wellness visit was provided 6.5 months after the
% policy's effective date?"
cause(claim_6, skydiving).
claimant_age(claim_6, 79).
wellness_confirmation_time(claim_6, 6.5).
hospitalization_time(claim_6, 3).
wellness_visit_time(claim_6, 3).

q6 :- policy_applies(claim_6).

% ---- Q7: "will my policy apply if I was hospitalized for a heart attack,
% proof of the wellness visit was submitted 2 months after the policy's
% effective date, and my age at the time of hospitalization was 75?"
cause(claim_7, heart_attack).
claimant_age(claim_7, 75).
wellness_confirmation_time(claim_7, 2).
hospitalization_time(claim_7, 3).
wellness_visit_time(claim_7, 3).

q7 :- policy_applies(claim_7).

% ---- Q8: "will my policy apply if I was hospitalized after being injured
% in a military training exercise, the hospitalization occurred within
% the policy term, and I did not commit fraud?"
cause(claim_8, military_service).
hospitalization_time(claim_8, 3).
claimant_age(claim_8, 40).
wellness_visit_time(claim_8, 3).
wellness_confirmation_time(claim_8, 4).

q8 :- policy_applies(claim_8).

% ---- Q9: "will my policy apply if I was hospitalized due to my son
% biting me in the ankle, proof of my wellness visit was provided 6
% months after the effective date, and I was serving as a police officer
% at the time of hospitalization?"
% Judgement call: Section 2.1(4) excludes an event "arising directly or
% indirectly out of ... service in the police" -- a CAUSAL requirement.
% The claimant's occupation at the moment of the injury is not itself a
% cause of a bite from his son, so cause/2 is set to the actual cause of
% the injury and NOT to police_service; the fact that the claimant was a
% serving police officer at that moment is deliberately not asserted as a
% "cause" of the hospitalization.
cause(claim_9, bitten_by_family_member).
wellness_confirmation_time(claim_9, 6).
claimant_age(claim_9, 40).
hospitalization_time(claim_9, 3).
wellness_visit_time(claim_9, 3).

q9 :- policy_applies(claim_9).
