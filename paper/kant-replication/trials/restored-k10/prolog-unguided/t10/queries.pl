% ===========================================================================
% queries.pl -- per-claim facts and the nine benchmark queries q1..q9.
%
% Each claim is named claim_1 .. claim_9, matching the corresponding
% question in inputs/queries-blind.md. Every query's standing preamble
% ("assuming all other conditions are met and no other exclusions apply,
% where by 'other' I mean anything not referenced in the query") is
% realized simply by never asserting a fact that would violate a
% condition, or trigger an exclusion, that the question itself does not
% raise.
% ===========================================================================

%% -----------------------------------------------------------------------
%% Q1: hospitalized by burns suffered while doing my duty as a
%% firefighter. Accidental injury, arising directly out of service as a
%% fire fighter (Sec 3.1.3) -- excluded.
%% -----------------------------------------------------------------------
claim_made(claim_1).
confined_in_hospital(claim_1).
hospital_in_us(claim_1).
caused_by_accidental_injury(claim_1).
caused_by_firefighting_service(claim_1).

q1 :- covered(claim_1).

%% -----------------------------------------------------------------------
%% Q2: 78 years old at the time of hospitalization. No cause is specified
%% by the question, so a qualifying, non-excluded cause is assumed, per
%% the "all other conditions are met" preamble. 78 < 80, so the age
%% exclusion (Sec 3.1.5) does not apply.
%% -----------------------------------------------------------------------
claim_made(claim_2).
confined_in_hospital(claim_2).
hospital_in_us(claim_2).
caused_by_sickness(claim_2).
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

%% -----------------------------------------------------------------------
%% Q3: hospitalized for pneumonia 5 months after the effective date, age
%% 65 at hospitalization. Pneumonia is a sickness (Sec 2.1). Age 65 < 80.
%% Hospitalization at month 5 is within the one-year term, and no fact
%% suggests the Sec 1.3 wellness-visit deadlines were missed.
%% -----------------------------------------------------------------------
claim_made(claim_3).
confined_in_hospital(claim_3).
hospital_in_us(claim_3).
caused_by_sickness(claim_3).
age_at_hospitalization(claim_3, 65).
hospitalization_month(claim_3, 5).

q3 :- covered(claim_3).

%% -----------------------------------------------------------------------
%% Q4: hospitalized due to a fall while traveling abroad; confirmation of
%% the wellness visit was given 8 months after the effective date --
%% after the Sec 1.3 7-month deadline, so Sec 1.3 was not satisfied in a
%% timely fashion and the policy stands canceled under Sec 1.2. A fall is
%% not a Sec 3.1 excluded activity, and Sec 4.1 covers the claimant
%% worldwide, so hospital_in_us/1 is left unasserted here only because
%% the question places the hospitalization abroad -- not because
%% location is what decides this claim (the late confirmation already
%% does). See NOTES.md.
%% -----------------------------------------------------------------------
claim_made(claim_4).
confined_in_hospital(claim_4).
caused_by_accidental_injury(claim_4).
confirmation_supplied_month(claim_4, 8).

q4 :- covered(claim_4).

%% -----------------------------------------------------------------------
%% Q5: hospitalized for punching my own face to show off for my friends;
%% no fraud or misrepresentation. The act was intentional and
%% self-inflicted, not an "accidental" injury, and not a sickness either,
%% so it does not meet the Sec 2.1 benefit trigger at all -- neither
%% caused_by_sickness/1 nor caused_by_accidental_injury/1 is asserted.
%% See NOTES.md for the judgement call this reflects.
%% fraud_or_misrepresentation/1 is correspondingly left unasserted, since
%% the question tells us it did not occur.
%% -----------------------------------------------------------------------
claim_made(claim_5).
confined_in_hospital(claim_5).
hospital_in_us(claim_5).

q5 :- covered(claim_5).

%% -----------------------------------------------------------------------
%% Q6: hospitalized due to an injury sustained while skydiving (Sec
%% 3.1.1 -- excluded, regardless of the other facts); age 79 at
%% hospitalization (< 80, not independently excluding); proof of the
%% wellness visit provided 6.5 months after the effective date (before
%% the Sec 1.3 7-month confirmation deadline, so this alone would not
%% cancel the policy). The skydiving exclusion controls.
%% -----------------------------------------------------------------------
claim_made(claim_6).
confined_in_hospital(claim_6).
hospital_in_us(claim_6).
caused_by_accidental_injury(claim_6).
caused_by_skydiving(claim_6).
age_at_hospitalization(claim_6, 79).
confirmation_supplied_month(claim_6, 6.5).

q6 :- covered(claim_6).

%% -----------------------------------------------------------------------
%% Q7: hospitalized for a heart attack (sickness); proof of the wellness
%% visit submitted 2 months after the effective date (well within the
%% Sec 1.3 deadlines); age 75 at hospitalization (< 80).
%% -----------------------------------------------------------------------
claim_made(claim_7).
confined_in_hospital(claim_7).
hospital_in_us(claim_7).
caused_by_sickness(claim_7).
age_at_hospitalization(claim_7, 75).
confirmation_supplied_month(claim_7, 2).

q7 :- covered(claim_7).

%% -----------------------------------------------------------------------
%% Q8: hospitalized after being injured in a military training exercise
%% -- an accidental injury arising directly out of service in the
%% military (Sec 3.1.2), so excluded regardless of the other facts given
%% (hospitalization within the policy term; no fraud).
%% -----------------------------------------------------------------------
claim_made(claim_8).
confined_in_hospital(claim_8).
hospital_in_us(claim_8).
caused_by_accidental_injury(claim_8).
caused_by_military_service(claim_8).

q8 :- covered(claim_8).

%% -----------------------------------------------------------------------
%% Q9: hospitalized because my son bit my ankle -- an accidental injury
%% arising out of a domestic incident, not out of the claimant's service
%% as a police officer, so the Sec 3.1.4 police exclusion (which requires
%% the sickness/injury to arise out of that service, not merely that the
%% claimant holds that job) does not apply; caused_by_police_service/1 is
%% deliberately left unasserted. Proof of the wellness visit was provided
%% 6 months after the effective date -- at, not after, the Sec 1.3
%% deadline, so it is timely.
%% -----------------------------------------------------------------------
claim_made(claim_9).
confined_in_hospital(claim_9).
hospital_in_us(claim_9).
caused_by_accidental_injury(claim_9).
confirmation_supplied_month(claim_9, 6).

q9 :- covered(claim_9).
