% =====================================================================
% queries.pl -- the nine benchmark questions (Kant et al. 2025,
% Appendix A.2), each encoded as a claim-specific set of facts plus a
% q1/0 .. q9/0 predicate that succeeds iff the answer to that question
% is "yes".
%
% Standing preamble (applies to every question, per the benchmark and
% the task instructions): "Assuming all other conditions are met and no
% other exclusions apply (where by 'other,' I mean anything not
% referenced in the query that follows)", and the agreement has been
% signed and the premium paid on time. Concretely: for every claim
% below, any fact from policy.pl's optional-fact list that this
% scenario's question does not mention is simply left unasserted,
% relying on policy.pl's built-in defaults (age exclusion not in
% issue, no cause-of-injury exclusion in issue, no fraud/misrepresen-
% tation/withholding, Section 1.3 "pending" unless a confirmation
% month is given, hospitalization at month 0 unless a month is given).
%
% All times are in months relative to the policy's effective date,
% except the claimant's age, which is in years -- per the task
% instructions.
%
% The three fact predicates below are each supplied once per relevant
% question, so their clauses are not contiguous in this file; declared
% discontiguous to say so deliberately rather than leave the loader to
% warn about it.
% =====================================================================

:- discontiguous hospitalization_month/2.
:- discontiguous wellness_confirmation_month/2.
:- discontiguous age_at_hospitalization/2.

% ---------------------------------------------------------------------
% Q1: "will my policy apply if I was hospitalized by burns suffered
% while doing my duty as a firefighter?"
% Section 3.1 item 3 (service as a fire fighter) is squarely in issue.
% ---------------------------------------------------------------------
caused_by_firefighting_service(claim_1).

q1 :- covered(claim_1).

% ---------------------------------------------------------------------
% Q2: "will my policy apply if I am 78 years old at the time of
% hospitalization?"
% Section 3.1 item 5 excludes only age >= 80, so 78 does not trigger it.
% ---------------------------------------------------------------------
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% ---------------------------------------------------------------------
% Q3: "will my policy apply if I was hospitalized for pneumonia 5
% months after the policy's effective date, and my age at the time of
% hospitalization is 65?"
% Pneumonia is a sickness with no exclusion of its own; age 65 is below
% the Section 3.1 item 5 threshold. At month 5 the Section 1.3
% deadlines (6 and 7 months) have not yet passed, so that condition is
% still pending, which Section 1.1 treats as compatible with the
% policy being in effect.
% ---------------------------------------------------------------------
hospitalization_month(claim_3, 5).
age_at_hospitalization(claim_3, 65).

q3 :- covered(claim_3).

% ---------------------------------------------------------------------
% Q4: "will my policy apply if I was hospitalized due to a fall while
% traveling abroad and I had given confirmation of my wellness visit 8
% months after the policy's effective date?"
% Section 4.1.1 covers the insured worldwide, so travelling abroad is
% not itself an exclusion. Confirmation at month 8 is after the
% Section 1.3 deadline of 7 months, so that condition has failed and
% the policy has been cancelled under Section 1.2, regardless of when
% the hospitalization itself occurred.
% ---------------------------------------------------------------------
wellness_confirmation_month(claim_4, 8).

q4 :- covered(claim_4).

% ---------------------------------------------------------------------
% Q5: "will my policy apply if I was hospitalized for punching my own
% face to show off for my friends and I did not commit fraud or
% misrepresentation?"
% Section 3.1's five exclusions do not include self-inflicted or
% intentional conduct, so no caused_by_*/1 flag is asserted; fraud/1
% and misrepresentation/1 are left unasserted, as the question itself
% states neither occurred. See NOTES.md for the judgement call this
% question turns on.
% ---------------------------------------------------------------------
q5 :- covered(claim_5).

% ---------------------------------------------------------------------
% Q6: "will my policy apply if I was hospitalized due to an injury
% sustained while skydiving, my age at the time of hospitalization was
% 79, and proof of my wellness visit was provided 6.5 months after the
% policy's effective date?"
% Section 3.1 item 1 (skydiving) is squarely in issue and applies
% independently of the other facts below. Age 79 is below the age-80
% threshold in item 5, so that ground does not separately apply.
% Confirmation at month 6.5 is within the 7-month Section 1.3 deadline,
% so that condition is satisfied and does not independently cancel the
% policy -- the only disqualification here is the skydiving exclusion.
% ---------------------------------------------------------------------
caused_by_skydiving(claim_6).
age_at_hospitalization(claim_6, 79).
wellness_confirmation_month(claim_6, 6.5).

q6 :- covered(claim_6).

% ---------------------------------------------------------------------
% Q7: "will my policy apply if I was hospitalized for a heart attack,
% proof of the wellness visit was submitted 2 months after the policy's
% effective date, and my age at the time of hospitalization was 75?"
% A heart attack is a sickness with no exclusion of its own.
% Confirmation at month 2 is well within the 7-month deadline. Age 75
% is below the age-80 threshold.
% ---------------------------------------------------------------------
wellness_confirmation_month(claim_7, 2).
age_at_hospitalization(claim_7, 75).

q7 :- covered(claim_7).

% ---------------------------------------------------------------------
% Q8: "will my policy apply if I was hospitalized after being injured
% in a military training exercise, the hospitalization occurred within
% the policy term, and I did not commit fraud?"
% Section 3.1 item 2 (service in the military) is squarely in issue; a
% training exercise is read as an incident of military service, not
% something outside it. The hospitalization being within the policy
% term (Section 4.6) is stated explicitly, so a representative in-term
% month is recorded here. fraud/1 is left unasserted.
% ---------------------------------------------------------------------
caused_by_military_service(claim_8).
hospitalization_month(claim_8, 3).

q8 :- covered(claim_8).

% ---------------------------------------------------------------------
% Q9: "will my policy apply if I was hospitalized due to my son biting
% me in the ankle, proof of my wellness visit was provided 6 months
% after the effective date, and I was serving as a police officer at
% the time of hospitalization?"
% Being bitten is an accidental injury with no exclusion of its own.
% Confirmation at month 6 is within the 7-month Section 1.3 deadline,
% so that condition is satisfied. Section 3.1 item 4 (service in the
% police) is squarely in issue and is the operative exclusion here.
% ---------------------------------------------------------------------
wellness_confirmation_month(claim_9, 6).
caused_by_police_service(claim_9).

q9 :- covered(claim_9).
