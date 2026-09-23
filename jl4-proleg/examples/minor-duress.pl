% Canonical PROLEG fixture: rescission by a minor buyer, defeated by duress.
% Source: K. Satoh, "PROLEG: Practical Legal Reasoning System" (Year-of-Prolog
% slides), the alice/bob real-estate demonstration.
%
% First-order dialect (predicates carry arguments). Used as the Phase 3 anchor
% for TYPE RECONSTRUCTION: positional, untyped args must be inferred into L4
% types / named record fields.
%
% NOTE: the original slides contain typos that untyped Prolog tolerates silently
% but L4's name+type checker would catch -- exactly the kind of latent bug the
% transpiler is meant to surface:
%   * "minifestation_by_duress" (should be manifestation_by_duress)
%   * "Maniester" / "Mnifestee" (should be Manifester / Manifestee)
% They are corrected here so the fixture is internally coherent.

%=============================== rulebase ===============================

right_to_handing_over_the_goods(Buyer, Seller, Object, ContractID) <=
    valid_purchase_contract(Buyer, Seller, Object, Price, Tcontract, ContractID).

valid_purchase_contract(Buyer, Seller, Object, Price, Tcontract, ContractID) <=
    agreement_of_purchase_contract(Buyer, Seller, Object, Price, Tcontract, ContractID).

exception(
    valid_purchase_contract(Buyer, Seller, Object, Price, Tcontract, ContractID),
    rescission_by_minor_buyer(Buyer, Seller, ContractID, Tcontract, Trescission)).

rescission_by_minor_buyer(Buyer, Seller, ContractID, Tcontract, Trescission) <=
    minor(Buyer),
    manifestation(rescission(ContractID), Buyer, Seller, Trescission),
    before_the_day(Tcontract, Trescission).

% Bridge from the asserted fact predicate to the rule-level concept.
% (The slides reference manifestation/4 in rules but assert manifestation_fact/4
% in the factbase; the connecting rule is implicit there, explicit here.)
manifestation(Action, Manifester, Manifestee, Taction) <=
    manifestation_fact(Action, Manifester, Manifestee, Taction).

exception(
    manifestation(Action, Manifester, Manifestee, Taction),
    manifestation_by_duress(Threatener, Manifester, Manifestee, Action, Taction, Tduress, Trescission)).

manifestation_by_duress(Threatener, Manifester, Manifestee, Action, Taction, Tduress, Trescission) <=
    fact_of_duress(Threatener, Manifester, Action, Tduress),
    before_the_day(Tduress, Taction).

%=============================== factbase ===============================

agreement_of_purchase_contract(alice, bob, this_real_estate, 200000, date(2018, 1, 1), contract0).
minor(alice).
manifestation_fact(rescission(contract0), alice, bob, date(2018, 3, 1)).
fact_of_duress(bob, alice, rescission(contract0), date(2018, 2, 1)).

% Legal question: can alice demand the goods under contract0?
% Expected: YES -- alice's minority would let her rescind, but the rescission
% was itself made under duress (exception-of-exception), so the contract stands.
