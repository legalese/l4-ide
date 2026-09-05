# SEC Regulation Crowdfunding — 17 CFR Part 227

<!-- Generated from L4. One table per decision; hit policy is the first header cell. -->

<!-- OMITTED: `Reg CF commenced` — a formula (date("2016-05-16")), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the 2017 inflation adjustment` — a formula (date("2017-04-12")), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the 2021 amendments` — a formula (date("2021-03-15")), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the 2022 inflation adjustment` — a formula (date("2022-09-20")), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `offering maximum in a 12-month period` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `income or net worth cut point` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `minimum permitted investment` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `maximum amount sold to any one investor in a 12-month period` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `tier 1 ceiling` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `tier 2 ceiling` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `first-time issuer review ceiling` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `holders of record threshold` — a formula (300), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `total assets threshold` — a formula (10000000), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `minimum days publicly available before any sale` — a formula (21), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `days to file the annual report after fiscal year end` — a formula (120), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `business days to file Form C-TR` — a formula (5), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `business days to file a progress update` — a formula (5), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the resale restriction in years` — a formula (1), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(1) — not organized under State or territorial law` — a formula (true and not(issuer.organized_under_and_subject_to_the_laws_of_a_State_or_territory_of_the_United_States_or_the_District_of_Columbia)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(2) — an Exchange Act reporting company` — a formula (true and issuer.subject_to_the_requirement_to_file_reports_pursuant_to_section_13_or_section_15_d_of_the_Exchange_Act), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(3) — an investment company` — a formula (true and issuer.an_investment_company_or_is_excluded_from_the_definition_of_investment_company_by_section_3_b_or_section_3_c), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(4) — subject to a bad-actor disqualification` — a formula (true and issuer.subject_to_a_disqualification_as_specified_in_section_227_503_a), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(5) — delinquent in ongoing annual reports` — a formula (true and issuer.has_sold_securities_in_reliance_on_section_4_a_6_and_has_not_filed_the_ongoing_annual_reports_required_during_the_two_years_immediately_preceding_the_filing_of_the_offering_statement), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(6) — no specific business plan, or a blank-check business plan` — a formula (true and issuer.has_no_specific_business_plan_or_has_indicated_that_its_business_plan_is_to_engage_in_a_merger_or_acquisition_with_an_unidentified_company_or_companies), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `issuer is excluded by Rule 100(b)` — a formula (false or (b_1_not_organized_under_State_or_territorial_law or (b_2_an_Exchange_Act_reporting_company or (b_3_an_investment_company or (b_4_subject_to_a_bad_actor_disqualification or (b_5_delinquent_in_ongoing_annual_reports or b_6_no_specific_business_plan_or_a_blank_check_business_plan)))))), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `issuer is eligible` — a formula (not(issuer_is_excluded_by_Rule_100_b)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `aggregate offering amount` — a formula (offering.aggregate_amount_sold_in_reliance_on_section_4_a_6_during_the_preceding_12_months + offering.maximum_offering_amount_the_issuer_will_accept), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the applicable measure of annual income or net worth` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `either annual income or net worth is less than the cut point` — a formula (investor.annual_income < income_or_net_worth_cut_point or investor.net_worth < income_or_net_worth_cut_point), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `aggregate amount sold to this investor including this transaction` — a formula (investor.aggregate_amount_already_sold_to_this_investor_across_all_issuers_in_reliance_on_section_4_a_6_during_the_preceding_12_months + amount_to_be_sold_in_this_transaction), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the accredited-investor carve-out applies to` — a formula (the_rules_in_force_include(amendment: the_2021_amendments, RULES_EFFECTIVE_DATE: RULES_EFFECTIVE_DATE) and investor.an_accredited_investor_as_defined_in_Rule_501), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the rule date is inside the COVID-19 temporary rules window` — a formula (RULES_EFFECTIVE_DATE >= date("2020-05-04") and RULES_EFFECTIVE_DATE <= date("2022-08-28")), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `financial statement requirement is satisfied` — a formula (assurance_level(required: supplied) >= assurance_level(required: financial_statements_required(offering: offering, aggregate_offering_amount: aggregate_offering_amount, first_time_issuer_review_ceiling: first_time_issuer_review_ceiling, the_COVID_19_temporary_rules_Rule_201_z_and_bb_are_not_modelled_here: the_COVID_19_temporary_rules_Rule_201_z_and_bb_are_not_modelled_here, the_rule_date_is_inside_the_COVID_19_temporary_rules_window: the_rule_date_is_inside_the_COVID_19_temporary_rules_window, tier_1_ceiling: tier_1_ceiling, tier_2_ceiling: tier_2_ceiling))), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `disclosure requirements are met` — a formula (true and filing.a_Form_C_offering_statement_was_filed_with_the_Commission_and_provided_to_investors_and_the_relevant_intermediary_prior_to_the_commencement_of_the_offering and (filing.the_Form_C_includes_the_information_required_by_section_227_201 and financial_statement_requirement_is_satisfied)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(a)(3) — conducted through a single complying intermediary` — a formula (true and arrangement.the_intermediary_complies_with_section_4A_a_of_the_Securities_Act_and_the_related_requirements_in_this_part and (arrangement.the_transaction_is_conducted_exclusively_through_the_intermediary_s_platform and (true and arrangement.the_number_of_intermediaries_used_for_the_offering = 1))), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the 21-day public availability period has run` — a formula (true and arrangement.the_days_the_issuer_information_has_been_publicly_available_on_the_intermediary_s_platform_before_any_sale >= minimum_days_publicly_available_before_any_sale), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the intermediary has discharged its investor-facing duties` — a formula (true and arrangement.the_intermediary_delivered_educational_materials_in_connection_with_establishing_the_investor_s_account and (true and arrangement.the_intermediary_has_a_reasonable_basis_for_believing_that_the_investor_satisfies_the_investment_limitations)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `intermediary obligations are met` — a formula (a_3_conducted_through_a_single_complying_intermediary and (the_21_day_public_availability_period_has_run and the_intermediary_has_discharged_its_investor_facing_duties)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `notice complies with Rule 204(b)` — a formula (true and notice.directs_investors_to_the_intermediary_s_platform and (true and (true and (true and not(notice.includes_information_beyond_that_permitted_by_paragraph_b))))), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `definition — terms of the offering` — a formula (true and true), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(1) — became an Exchange Act reporting company` — a formula (true and status.the_issuer_is_required_to_file_reports_under_section_13_a_or_section_15_d_of_the_Exchange_Act), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(2) — one annual report filed and fewer than 300 holders of record` — a formula (true and status.annual_reports_filed_since_the_most_recent_sale_of_securities_pursuant_to_this_part >= 1 and status.holders_of_record < holders_of_record_threshold), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(3) — three annual reports filed and total assets not exceeding $10,000,000` — a formula (true and status.annual_reports_filed_since_the_most_recent_sale_of_securities_pursuant_to_this_part >= 3 and status.total_assets <= total_assets_threshold), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(4) — all securities repurchased` — a formula (true and status.the_issuer_or_another_party_has_repurchased_all_of_the_securities_issued_in_reliance_on_section_4_a_6), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(b)(5) — liquidated or dissolved` — a formula (true and status.the_issuer_has_liquidated_or_dissolved_its_business_in_accordance_with_state_law), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `ongoing reporting obligation may terminate` — a formula (false or (b_1_became_an_Exchange_Act_reporting_company or (b_2_one_annual_report_filed_and_fewer_than_300_holders_of_record or (b_3_three_annual_reports_filed_and_total_assets_not_exceeding_10_000_000 or (b_4_all_securities_repurchased or b_5_liquidated_or_dissolved))))), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

## `ongoing reporting obligation`

| F | ongoing_reporting_obligation_may_terminate : Boolean | annual_cycles : Number | ongoing_reporting_obligation (out) : String |
| --- | --- | --- | --- |
| 1 | true | - | file a Form C-TR termination of reporting |
| 2 | - | <= 0 | fulfilled |
| 3 | - | - | file a Form C-AR annual report and continue |

<!-- OMITTED: `the first anniversary of the issuance` — a formula (transfer.date_the_securities_were_issued + floor(the_resale_restriction_in_years) * duration("P1Y")), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `days until the first anniversary of the issuance` — a formula ((the_first_anniversary_of_the_issuance - transfer.date_the_securities_were_issued).days), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `transfer is within the one-year restricted period` — a formula (transfer.date_of_the_transfer < the_first_anniversary_of_the_issuance), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `(a)(4) — a family or trust transferee, or a death-or-divorce circumstance` — a formula (false or (false or (transfer.to_a_member_of_the_family_of_the_purchaser_or_the_equivalent or (transfer.to_a_trust_controlled_by_the_purchaser or transfer.to_a_trust_created_for_the_benefit_of_a_member_of_the_family_of_the_purchaser_or_the_equivalent)) or (false or (transfer.in_connection_with_death_of_the_purchaser or (transfer.in_connection_with_divorce_of_the_purchaser or transfer.in_connection_with_a_circumstance_similar_to_death_or_divorce_of_the_purchaser))))), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `transfer falls within an exception in Rule 501(a)` — a formula (false or (true and transfer.to_the_issuer_of_the_securities or (true and transfer.to_an_accredited_investor or (true and transfer.as_part_of_an_offering_registered_with_the_Commission or true and a_4_a_family_or_trust_transferee_or_a_death_or_divorce_circumstance)))), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `transfer is permitted` — a formula (not(transfer_is_within_the_one_year_restricted_period) or transfer_falls_within_an_exception_in_Rule_501_a), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `a clean issuer` — a formula ({name: "Clean Co", organized_under_and_subject_to_the_laws_of_a_State_or_territory_of_the_United_States_or_the_District_of_Columbia: true, subject_to_the_requirement_to_file_reports_pursuant_to_section_13_or_section_15_d_of_the_Exchange_Act: false, an_investment_company_or_is_excluded_from_the_definition_of_investment_company_by_section_3_b_or_section_3_c: false, subject_to_a_disqualification_as_specified_in_section_227_503_a: false, has_sold_securities_in_reliance_on_section_4_a_6_and_has_not_filed_the_ongoing_annual_reports_required_during_the_two_years_immediately_preceding_the_filing_of_the_offering_statement: false, has_no_specific_business_plan_or_has_indicated_that_its_business_plan_is_to_engage_in_a_merger_or_acquisition_with_an_unidentified_company_or_companies: false}), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `a delinquent issuer` — a formula ({name: "Late Filer Inc", organized_under_and_subject_to_the_laws_of_a_State_or_territory_of_the_United_States_or_the_District_of_Columbia: true, subject_to_the_requirement_to_file_reports_pursuant_to_section_13_or_section_15_d_of_the_Exchange_Act: false, an_investment_company_or_is_excluded_from_the_definition_of_investment_company_by_section_3_b_or_section_3_c: false, subject_to_a_disqualification_as_specified_in_section_227_503_a: false, has_sold_securities_in_reliance_on_section_4_a_6_and_has_not_filed_the_ongoing_annual_reports_required_during_the_two_years_immediately_preceding_the_filing_of_the_offering_statement: true, has_no_specific_business_plan_or_has_indicated_that_its_business_plan_is_to_engage_in_a_merger_or_acquisition_with_an_unidentified_company_or_companies: false}), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `certified` — a formula ("financial statements certified by the principal executive officer, with tax return information"), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `reviewed` — a formula ("financial statements reviewed by an independent public accountant"), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `audited` — a formula ("financial statements audited by an independent public accountant"), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `a conforming filing` — a formula ({a_Form_C_offering_statement_was_filed_with_the_Commission_and_provided_to_investors_and_the_relevant_intermediary_prior_to_the_commencement_of_the_offering: true, the_Form_C_includes_the_information_required_by_section_227_201: true, the_financial_statements_supplied: reviewed}), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the base case qualifies` — a formula (the_transaction_qualifies_for_the_section_4_a_6_exemption(issuer: a_clean_issuer, offering: an_offering_of(prior_sales: 0, maximum: 500000, previously_sold: false), investor: an_investor_with(accredited: false, income: 60000, worth: 200000, already: 0), amount: 5000, arrangement: an_arrangement_with(days_available: 21, intermediaries: 1), filing: a_conforming_filing, aggregate_amount_sold_to_this_investor_including_this_transaction: aggregate_amount_sold_to_this_investor_including_this_transaction, aggregate_offering_amount: aggregate_offering_amount, disclosure_requirements_are_met: disclosure_requirements_are_met, either_annual_income_or_net_worth_is_less_than_the_cut_point: either_annual_income_or_net_worth_is_less_than_the_cut_point, intermediary_obligations_are_met: intermediary_obligations_are_met, issuer_is_eligible: issuer_is_eligible, maximum_amount_sold_to_any_one_investor_in_a_12_month_period: maximum_amount_sold_to_any_one_investor_in_a_12_month_period, minimum_permitted_investment: minimum_permitted_investment, offering_maximum_in_a_12_month_period: offering_maximum_in_a_12_month_period, the_accredited_investor_carve_out_applies_to: the_accredited_investor_carve_out_applies_to, the_applicable_measure_of_annual_income_or_net_worth: the_applicable_measure_of_annual_income_or_net_worth)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the delinquent-issuer case qualifies` — a formula (the_transaction_qualifies_for_the_section_4_a_6_exemption(issuer: a_delinquent_issuer, offering: an_offering_of(prior_sales: 0, maximum: 500000, previously_sold: false), investor: an_investor_with(accredited: false, income: 60000, worth: 200000, already: 0), amount: 5000, arrangement: an_arrangement_with(days_available: 21, intermediaries: 1), filing: a_conforming_filing, aggregate_amount_sold_to_this_investor_including_this_transaction: aggregate_amount_sold_to_this_investor_including_this_transaction, aggregate_offering_amount: aggregate_offering_amount, disclosure_requirements_are_met: disclosure_requirements_are_met, either_annual_income_or_net_worth_is_less_than_the_cut_point: either_annual_income_or_net_worth_is_less_than_the_cut_point, intermediary_obligations_are_met: intermediary_obligations_are_met, issuer_is_eligible: issuer_is_eligible, maximum_amount_sold_to_any_one_investor_in_a_12_month_period: maximum_amount_sold_to_any_one_investor_in_a_12_month_period, minimum_permitted_investment: minimum_permitted_investment, offering_maximum_in_a_12_month_period: offering_maximum_in_a_12_month_period, the_accredited_investor_carve_out_applies_to: the_accredited_investor_carve_out_applies_to, the_applicable_measure_of_annual_income_or_net_worth: the_applicable_measure_of_annual_income_or_net_worth)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the over-limit-investor case qualifies` — a formula (the_transaction_qualifies_for_the_section_4_a_6_exemption(issuer: a_clean_issuer, offering: an_offering_of(prior_sales: 0, maximum: 500000, previously_sold: false), investor: an_investor_with(accredited: false, income: 60000, worth: 200000, already: 9000), amount: 5000, arrangement: an_arrangement_with(days_available: 21, intermediaries: 1), filing: a_conforming_filing, aggregate_amount_sold_to_this_investor_including_this_transaction: aggregate_amount_sold_to_this_investor_including_this_transaction, aggregate_offering_amount: aggregate_offering_amount, disclosure_requirements_are_met: disclosure_requirements_are_met, either_annual_income_or_net_worth_is_less_than_the_cut_point: either_annual_income_or_net_worth_is_less_than_the_cut_point, intermediary_obligations_are_met: intermediary_obligations_are_met, issuer_is_eligible: issuer_is_eligible, maximum_amount_sold_to_any_one_investor_in_a_12_month_period: maximum_amount_sold_to_any_one_investor_in_a_12_month_period, minimum_permitted_investment: minimum_permitted_investment, offering_maximum_in_a_12_month_period: offering_maximum_in_a_12_month_period, the_accredited_investor_carve_out_applies_to: the_accredited_investor_carve_out_applies_to, the_applicable_measure_of_annual_income_or_net_worth: the_applicable_measure_of_annual_income_or_net_worth)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the short-availability case qualifies` — a formula (the_transaction_qualifies_for_the_section_4_a_6_exemption(issuer: a_clean_issuer, offering: an_offering_of(prior_sales: 0, maximum: 500000, previously_sold: false), investor: an_investor_with(accredited: false, income: 60000, worth: 200000, already: 0), amount: 5000, arrangement: an_arrangement_with(days_available: 20, intermediaries: 1), filing: a_conforming_filing, aggregate_amount_sold_to_this_investor_including_this_transaction: aggregate_amount_sold_to_this_investor_including_this_transaction, aggregate_offering_amount: aggregate_offering_amount, disclosure_requirements_are_met: disclosure_requirements_are_met, either_annual_income_or_net_worth_is_less_than_the_cut_point: either_annual_income_or_net_worth_is_less_than_the_cut_point, intermediary_obligations_are_met: intermediary_obligations_are_met, issuer_is_eligible: issuer_is_eligible, maximum_amount_sold_to_any_one_investor_in_a_12_month_period: maximum_amount_sold_to_any_one_investor_in_a_12_month_period, minimum_permitted_investment: minimum_permitted_investment, offering_maximum_in_a_12_month_period: offering_maximum_in_a_12_month_period, the_accredited_investor_carve_out_applies_to: the_accredited_investor_carve_out_applies_to, the_applicable_measure_of_annual_income_or_net_worth: the_applicable_measure_of_annual_income_or_net_worth)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `the under-assured-financials case qualifies` — a formula (the_transaction_qualifies_for_the_section_4_a_6_exemption(issuer: a_clean_issuer, offering: an_offering_of(prior_sales: 0, maximum: 700000, previously_sold: true), investor: an_investor_with(accredited: false, income: 60000, worth: 200000, already: 0), amount: 5000, arrangement: an_arrangement_with(days_available: 21, intermediaries: 1), filing: a_conforming_filing, aggregate_amount_sold_to_this_investor_including_this_transaction: aggregate_amount_sold_to_this_investor_including_this_transaction, aggregate_offering_amount: aggregate_offering_amount, disclosure_requirements_are_met: disclosure_requirements_are_met, either_annual_income_or_net_worth_is_less_than_the_cut_point: either_annual_income_or_net_worth_is_less_than_the_cut_point, intermediary_obligations_are_met: intermediary_obligations_are_met, issuer_is_eligible: issuer_is_eligible, maximum_amount_sold_to_any_one_investor_in_a_12_month_period: maximum_amount_sold_to_any_one_investor_in_a_12_month_period, minimum_permitted_investment: minimum_permitted_investment, offering_maximum_in_a_12_month_period: offering_maximum_in_a_12_month_period, the_accredited_investor_carve_out_applies_to: the_accredited_investor_carve_out_applies_to, the_applicable_measure_of_annual_income_or_net_worth: the_applicable_measure_of_annual_income_or_net_worth)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `W offering` — a formula (an_offering_of(prior_sales: 0, maximum: 3000000, previously_sold: false)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `I-3 investor` — a formula (an_investor_with(accredited: false, income: 110000, worth: 115000, already: 0)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `I-4 investor` — a formula (an_investor_with(accredited: false, income: 1240000, worth: 1240000, already: 0)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `A investor` — a formula (an_investor_with(accredited: true, income: 1000000, worth: 1000000, already: 200000)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `F offering` — a formula (an_offering_of(prior_sales: 0, maximum: 550000, previously_sold: true)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `investor` — a boxed context (a hydrated record), which dmnmd cannot express. Located, with its code, in the fidelity report. -->
