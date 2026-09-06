# Phase 4 exhibit — un-lifting, tiering, and the population filter

<!-- Generated from L4. One table per decision; hit policy is the first header cell. -->

<!-- OMITTED: `basic monthly benefit` — a formula (claimant.income * 0.3 + claimant.children * 50), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `benefit cap` — a formula (claimant.income * 0.5), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `capped benefit` — a formula (min(basic_monthly_benefit, benefit_cap)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `low estimate` — a formula (scaled_amount(amount: 100)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `high estimate` — a formula (scaled_amount(amount: 900)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `art3 applies` — a formula (s.reason = "emergency"), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `art7 applies` — a formula (s_2.reason = "gathering"), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `definition — benefit` — a formula (true and true), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `net payout` — a formula (gross * 0.9), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `payout a` — a formula (net_payout), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `payout b` — a formula (net_payout), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->
