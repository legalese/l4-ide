% queries.pl
%
% Per-claim facts and the nine yes/no questions, each encoded as a
% query predicate qN/0 that succeeds exactly when the answer to
% question N is "yes" and fails when it is "no".
%
% Per the standing preamble ("Assuming all other conditions are met
% and no other exclusions apply ... where by 'other' I mean anything
% not referenced in the query that follows"), each claim below states
% only the facts its question actually mentions. Everything else is
% left to the contract-faithful defaults built into policy.pl, which
% resolve unstated facts in favour of coverage (wellness condition
% still pending/on time, hospital presumed in the US, no fraud, a
% qualifying cause presumed to exist, hospitalization presumed within
% the policy term, confinement presumed within the 365-day cap) -- so
% that the outcome turns only on what each question actually asks
% about.
%
% The claim-fact predicates below are declared discontiguous because
% each is asserted once per claim, in claim order, rather than being
% grouped by predicate.

:- discontiguous claim_cause/2.
:- discontiguous claim_activity/2.
:- discontiguous claim_age/2.
:- discontiguous claim_confirmation_month/2.

% ---------------------------------------------------------------------
% Q1 -- hospitalized by burns suffered while doing my duty as a
% firefighter.
% Burns are an accidental injury; they were suffered while carrying
% out firefighting duty, which is a direct causal link to the
% activity excluded by section 3.1.3.
% ---------------------------------------------------------------------

claim_cause(claim_1, accidental_injury).
claim_activity(claim_1, firefighting_duty).

q1 :- covered(claim_1).

% ---------------------------------------------------------------------
% Q2 -- 78 years old at the time of hospitalization.
% No cause of hospitalization is stated, so a qualifying cause is
% stipulated, per the standing preamble. 78 is below the section
% 3.1.5 threshold of 80.
% ---------------------------------------------------------------------

claim_cause(claim_2, sickness).
claim_age(claim_2, 78).

q2 :- covered(claim_2).

% ---------------------------------------------------------------------
% Q3 -- hospitalized for pneumonia 5 months after the policy's
% effective date; age 65 at the time of hospitalization.
% Pneumonia is a sickness. At month 5 the section 1.3 wellness-visit
% deadlines (month 6 and month 7) have not yet arrived, so the
% condition is still pending, which section 1.1(3) treats as
% compliant.
% ---------------------------------------------------------------------

claim_cause(claim_3, sickness).
claim_age(claim_3, 65).
claim_hospitalization_month(claim_3, 5).

q3 :- covered(claim_3).

% ---------------------------------------------------------------------
% Q4 -- hospitalized due to a fall while traveling abroad; written
% confirmation of the wellness visit was given 8 months after the
% effective date.
% A fall is an accidental injury. Confirmation at month 8 is after
% the section 1.3 deadline of month 7, so it was not given "in a
% timely fashion" -- this cancels the policy under section 1.2, quite
% apart from the fact that "traveling abroad" also places the
% hospital outside the United States (see NOTES.md on section 2.2).
% ---------------------------------------------------------------------

claim_cause(claim_4, accidental_injury).
claim_hospital_abroad(claim_4).
claim_confirmation_month(claim_4, 8).

q4 :- covered(claim_4).

% ---------------------------------------------------------------------
% Q5 -- hospitalized for punching my own face to show off for my
% friends; no fraud or misrepresentation.
% Deliberately punching oneself is neither a sickness nor an
% accidental injury (it is an intentional act), so it does not meet
% the basic triggering condition of section 2.1 at all. claim_fraud/1
% is deliberately left unasserted, since the question stipulates no
% fraud occurred.
% ---------------------------------------------------------------------

claim_cause(claim_5, intentional_self_harm).

q5 :- covered(claim_5).

% ---------------------------------------------------------------------
% Q6 -- injury sustained while skydiving; age 79 at the time of
% hospitalization; proof of the wellness visit provided 6.5 months
% after the effective date.
% The injury arose directly from skydiving, excluded by section
% 3.1.1, regardless of age (79 is below the 80 threshold) or the
% wellness-visit timing (6.5 months is within the 7-month
% confirmation deadline).
% ---------------------------------------------------------------------

claim_cause(claim_6, accidental_injury).
claim_activity(claim_6, skydiving).
claim_age(claim_6, 79).
claim_confirmation_month(claim_6, 6.5).

q6 :- covered(claim_6).

% ---------------------------------------------------------------------
% Q7 -- heart attack; proof of the wellness visit submitted 2 months
% after the effective date; age 75 at the time of hospitalization.
% A heart attack is a sickness. Age 75 is below the section 3.1.5
% threshold. Confirmation at month 2 is comfortably within both the
% 6-month and 7-month section 1.3 deadlines.
% ---------------------------------------------------------------------

claim_cause(claim_7, sickness).
claim_age(claim_7, 75).
claim_confirmation_month(claim_7, 2).

q7 :- covered(claim_7).

% ---------------------------------------------------------------------
% Q8 -- injured in a military training exercise; the hospitalization
% is stated to occur within the policy term; no fraud.
% The injury arose directly from a military training exercise, i.e.
% "service in the military", excluded by section 3.1.2. The question
% already stipulates the hospitalization falls within the policy
% term, which is also policy.pl's default for an unstated
% hospitalization month, so no claim_hospitalization_month/2 fact is
% needed. claim_fraud/1 is deliberately left unasserted.
% ---------------------------------------------------------------------

claim_cause(claim_8, accidental_injury).
claim_activity(claim_8, military_service).

q8 :- covered(claim_8).

% ---------------------------------------------------------------------
% Q9 -- hospitalized because my son bit me in the ankle; proof of the
% wellness visit provided 6 months after the effective date; I was
% serving as a police officer at the time of hospitalization.
% Being bitten is an accidental injury. Confirmation at month 6 clears
% both section 1.3 deadlines. Critically, the injury did not arise
% from police duty -- it is a domestic incident that merely happened
% while the claimant held that occupation -- so claim_activity(claim_9,
% police_duty) is deliberately NOT asserted; section 3.1.4 requires the
% event to arise "directly or indirectly out of" the service, not
% merely that the claimant hold that status at the time. See NOTES.md.
% ---------------------------------------------------------------------

claim_cause(claim_9, accidental_injury).
claim_confirmation_month(claim_9, 6).

q9 :- covered(claim_9).
