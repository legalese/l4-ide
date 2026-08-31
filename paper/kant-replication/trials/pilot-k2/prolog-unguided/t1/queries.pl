% =====================================================================
%  queries.pl -- the nine benchmark questions as facts + q1..q9
% =====================================================================
%
%  Consulted after policy.pl.  Each question becomes:
%    (a) a block of per-claim facts -- the scenario as stated, plus
%        explicit "compliant" defaults for every condition the question
%        does not mention, per the benchmark's own standing preamble to
%        assume anything not referenced is satisfied and that no
%        unreferenced exclusion applies;
%    (b) a qN/0 predicate that succeeds iff the claim is covered.
%
%  Boolean trigger facts (the four activity exclusions and
%  fraud_misrep_or_withholding/1) are simply left unasserted when they
%  do not hold for a claim -- policy.pl's rules reach them only through
%  negation-as-failure, so omission already *is* the "false" /
%  non-triggering default. Only the numeric month facts are asserted
%  for every claim, because condition_1_3_satisfied/1 and
%  hospitalization_within_policy_term/1 need concrete numbers to
%  compare against their deadlines -- an unasserted numeric fact would
%  make those checks fail outright, which is the wrong default
%  direction (it would read as "canceled" rather than "unimpeachable").
%
%  Declared discontiguous because facts are grouped by claim (so a
%  reviewer can see one scenario's whole fact set together) rather than
%  by predicate.
% ---------------------------------------------------------------------

:- discontiguous age_at_hospitalization/2.
:- discontiguous hospitalization_time_months/2.
:- discontiguous wellness_visit_time_months/2.
:- discontiguous confirmation_submitted_time_months/2.

% ---------------------------------------------------------------------
%  Q1. will my policy apply if I was hospitalized by burns suffered
%      while doing my duty as a firefighter?
% ---------------------------------------------------------------------

injury_arose_from_firefighter_service(claim_1).   % stated
hospitalization_time_months(claim_1, 0).          % unrelated to query
wellness_visit_time_months(claim_1, 0).           % unrelated to query
confirmation_submitted_time_months(claim_1, 0).   % unrelated to query

q1 :- covered(claim_1).

% ---------------------------------------------------------------------
%  Q2. will my policy apply if I am 78 years old at the time of
%      hospitalization?
% ---------------------------------------------------------------------

age_at_hospitalization(claim_2, 78).              % stated
hospitalization_time_months(claim_2, 0).          % unrelated to query
wellness_visit_time_months(claim_2, 0).           % unrelated to query
confirmation_submitted_time_months(claim_2, 0).   % unrelated to query

q2 :- covered(claim_2).

% ---------------------------------------------------------------------
%  Q3. will my policy apply if I was hospitalized for pneumonia 5
%      months after the policy's effective date, and my age at the
%      time of hospitalization is 65?
% ---------------------------------------------------------------------

age_at_hospitalization(claim_3, 65).              % stated
hospitalization_time_months(claim_3, 5).          % stated
wellness_visit_time_months(claim_3, 0).           % unrelated to query
confirmation_submitted_time_months(claim_3, 0).   % unrelated to query

q3 :- covered(claim_3).

% ---------------------------------------------------------------------
%  Q4. will my policy apply if I was hospitalized due to a fall while
%      traveling abroad and I had given confirmation of my wellness
%      visit 8 months after the policy's effective date?
% ---------------------------------------------------------------------
%  Traveling abroad is not an exclusion (Sec. 3.1: worldwide coverage).
%  Only the confirmation date is stated; the underlying visit's own
%  timeliness is not referenced, so it is asserted compliant.

hospitalization_time_months(claim_4, 0).          % unrelated to query
wellness_visit_time_months(claim_4, 0).           % unrelated to query
                                                   % (visit date itself
                                                   % not stated)
confirmation_submitted_time_months(claim_4, 8).   % stated

q4 :- covered(claim_4).

% ---------------------------------------------------------------------
%  Q5. will my policy apply if I was hospitalized for punching my own
%      face to show off for my friends and I did not commit fraud or
%      misrepresentation?
% ---------------------------------------------------------------------
%  Self-inflicted horseplay is not on the Sec. 2.1 exclusion list, and
%  fraud_misrep_or_withholding/1 is explicitly denied, so it is left
%  unasserted.

hospitalization_time_months(claim_5, 0).          % unrelated to query
wellness_visit_time_months(claim_5, 0).           % unrelated to query
confirmation_submitted_time_months(claim_5, 0).   % unrelated to query

q5 :- covered(claim_5).

% ---------------------------------------------------------------------
%  Q6. will my policy apply if I was hospitalized due to an injury
%      sustained while skydiving, my age at the time of hospitalization
%      was 79, and proof of my wellness visit was provided 6.5 months
%      after the policy's effective date?
% ---------------------------------------------------------------------

injury_arose_from_skydiving(claim_6).             % stated
age_at_hospitalization(claim_6, 79).              % stated
hospitalization_time_months(claim_6, 0).          % unrelated to query
wellness_visit_time_months(claim_6, 0).           % unrelated to query
                                                   % (visit date itself
                                                   % not stated)
confirmation_submitted_time_months(claim_6, 6.5). % stated

q6 :- covered(claim_6).

% ---------------------------------------------------------------------
%  Q7. will my policy apply if I was hospitalized for a heart attack,
%      proof of the wellness visit was submitted 2 months after the
%      policy's effective date, and my age at the time of
%      hospitalization was 75?
% ---------------------------------------------------------------------

age_at_hospitalization(claim_7, 75).              % stated
hospitalization_time_months(claim_7, 0).          % unrelated to query
wellness_visit_time_months(claim_7, 0).           % unrelated to query
confirmation_submitted_time_months(claim_7, 2).   % stated

q7 :- covered(claim_7).

% ---------------------------------------------------------------------
%  Q8. will my policy apply if I was hospitalized after being injured
%      in a military training exercise, the hospitalization occurred
%      within the policy term, and I did not commit fraud?
% ---------------------------------------------------------------------
%  A training exercise is still "service in the military" for purposes
%  of Sec. 2.1.2 -- the clause is not limited to combat or deployment.
%  fraud_misrep_or_withholding/1 is explicitly denied, so it is left
%  unasserted.

injury_arose_from_military_service(claim_8).      % stated
hospitalization_time_months(claim_8, 0).          % stated to be within
                                                   % the policy term
wellness_visit_time_months(claim_8, 0).           % unrelated to query
confirmation_submitted_time_months(claim_8, 0).   % unrelated to query

q8 :- covered(claim_8).

% ---------------------------------------------------------------------
%  Q9. will my policy apply if I was hospitalized due to my son biting
%      me in the ankle, proof of my wellness visit was provided 6
%      months after the effective date, and I was serving as a police
%      officer at the time of hospitalization?
% ---------------------------------------------------------------------
%  Being a serving police officer *at the time* of hospitalization is a
%  status fact, not a causal one: a bite from the claimant's own son
%  does not "arise ... out of" police service (Sec. 2.1.4), so
%  injury_arose_from_police_service/1 is deliberately NOT asserted for
%  this claim.

hospitalization_time_months(claim_9, 0).          % unrelated to query
wellness_visit_time_months(claim_9, 0).           % unrelated to query
                                                   % (visit date itself
                                                   % not stated)
confirmation_submitted_time_months(claim_9, 6).   % stated

q9 :- covered(claim_9).
