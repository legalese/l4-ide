% ============================================================
% queries.pl -- the nine benchmark questions against policy.pl
% ============================================================
% Consulted together with policy.pl (policy.pl first). Each claim
% gets its own identifier (claim_1 .. claim_9) so that per-claim
% facts asserted here for one question cannot leak into another,
% since policy.pl's dynamic predicates are all keyed on that
% identifier.
%
% Standing preamble (applies to every question): "Assuming all
% other conditions are met and no other exclusions apply" -- so
% for each claim only the fact(s) the question actually turns on
% are asserted below. Everything else is left unasserted, which by
% construction of policy.pl's rules defaults in favour of coverage
% (see the header comment in policy.pl). The agreement is always
% taken to be signed and the premium always taken to be paid on
% time, per both the paper's prompt and Sec. 1.1 items 1-2.

:- discontiguous injury_arises_from/2.
:- discontiguous age_at_hospitalization/2.
:- discontiguous hospitalization_time_months/2.
:- discontiguous wellness_confirmation_time_months/2.

% ---- Q1: hospitalized by burns suffered while on duty as a
% firefighter -- Sec 2.1 item 3.
injury_arises_from(claim_1, firefighter_service).
q1 :- covered(claim_1).

% ---- Q2: 78 years old at the time of hospitalization -- below
% the Sec 2.1 item 5 threshold of 80.
age_at_hospitalization(claim_2, 78).
q2 :- covered(claim_2).

% ---- Q3: hospitalized for pneumonia 5 months after the policy's
% effective date (Sec 1.3's 7-month deadline has not yet passed,
% so the wellness condition is still pending); age 65.
hospitalization_time_months(claim_3, 5).
age_at_hospitalization(claim_3, 65).
q3 :- covered(claim_3).

% ---- Q4: hospitalized due to a fall while traveling abroad (no
% territorial exclusion, per Sec 3.1); wellness-visit confirmation
% given 8 months after the effective date, i.e. after Sec 1.3's
% 7-month deadline to supply it.
wellness_confirmation_time_months(claim_4, 8).
q4 :- covered(claim_4).

% ---- Q5: hospitalized for punching own face to show off for
% friends; no fraud or misrepresentation. No Sec 2.1 ground covers
% self-inflicted/horseplay injury, so nothing further needs to be
% asserted -- the absence of fraud_committed/misrepresentation_made
% facts already reflects "I did not commit fraud or
% misrepresentation".
q5 :- covered(claim_5).

% ---- Q6: injury sustained while skydiving (Sec 2.1 item 1); age
% 79 (below the Sec 2.1 item 5 threshold on its own); wellness-visit
% proof provided 6.5 months after the effective date.
injury_arises_from(claim_6, skydiving).
age_at_hospitalization(claim_6, 79).
wellness_confirmation_time_months(claim_6, 6.5).
q6 :- covered(claim_6).

% ---- Q7: heart attack; wellness-visit proof submitted 2 months
% after the effective date (well inside both Sec 1.3 deadlines);
% age 75.
wellness_confirmation_time_months(claim_7, 2).
age_at_hospitalization(claim_7, 75).
q7 :- covered(claim_7).

% ---- Q8: injured in a military training exercise (Sec 2.1 item
% 2); hospitalization occurred within the policy term -- this is
% exactly what policy.pl already defaults to when no
% hospitalization_time_months fact is asserted, so nothing further
% needs to be asserted for it; no fraud.
injury_arises_from(claim_8, military_service).
q8 :- covered(claim_8).

% ---- Q9: bitten by claimant's own son on the ankle; wellness-visit
% proof given 6 months after the effective date (on the Sec 1.3
% visit deadline, and inside the confirmation deadline); claimant
% was serving as a police officer at the time of hospitalization.
% Deliberately NOT asserting injury_arises_from(claim_9,
% police_service): Sec 2.1 item 4 excludes injury arising out of
% police service, and a bite from one's own son does not arise out
% of that service merely because the claimant happens to hold that
% job at the time -- see NOTES.md.
wellness_confirmation_time_months(claim_9, 6).
q9 :- covered(claim_9).
