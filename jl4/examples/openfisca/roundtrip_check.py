"""Defensibility round-trip: load a module emitted by `l4 export openfisca`, run it in
a real OpenFisca simulation, and assert the results match what L4 computes.

The expected numbers below are copied by hand from the #ASSERTs of each L4
source; they are not read from L4. `l4-cli-test` checks those #ASSERTs
separately (they must all be satisfied), and runs this script over every case
when L4_OPENFISCA_CHECK=1.

Usage (inside a venv with openfisca-core and numpy):
    python roundtrip_check.py <generated_module.py> <case>

where <case> is an example under jl4/examples/openfisca/ (flat-tax, benefit,
household, roles, housing, agecheck, incometax, basic-income, dated, scale) or
a fixture under jl4/tests-cli/fixtures/openfisca/ (gt-guard, scalar-formula,
role-status, carriage-return, python-keywords, not-scalar, scalar-arithmetic,
python-builtins, eternity-parameter).
"""
import importlib.util
import sys

from openfisca_core.simulation_builder import SimulationBuilder


def load_system(path):
    spec = importlib.util.spec_from_file_location("generated_of", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.L4TaxBenefitSystem()


def check(tbs, plural, situation, variable, period, expected):
    sim = SimulationBuilder().build_from_entities(tbs, {plural: situation})
    got = float(sim.calculate(variable, period)[0])
    ok = abs(got - float(expected)) < 1e-6
    flag = "OK" if ok else "*** MISMATCH ***"
    print(f"  {variable}({period}) = {got}  (L4 expected {expected})  {flag}")
    assert ok, f"{variable}: got {got}, expected {expected}"


def main():
    gen, which = sys.argv[1], sys.argv[2]
    tbs = load_system(gen)
    print(f"== round-trip: {which} ==")
    if which == "flat-tax":
        check(tbs, "persons",
              {"alice": {"salary": {"2026-01": 2000}}},
              "flat_tax_on_salary", "2026-01", 500.0)
    elif which == "benefit":
        sit_eligible = {"h1": {"income": {"2026-01": 1500},
                               "dependents": {"2026-01": 2}}}
        sit_ineligible = {"h2": {"income": {"2026-01": 3000},
                                 "dependents": {"2026-01": 2}}}
        check(tbs, "households", sit_eligible, "eligible_for_benefit", "2026-01", 1)
        check(tbs, "households", sit_eligible, "monthly_benefit", "2026-01", 700.0)
        check(tbs, "households", sit_ineligible, "monthly_benefit", "2026-01", 0.0)
    elif which == "household":
        # group entity: persons + a household whose members reference them
        sim = SimulationBuilder().build_from_entities(tbs, {
            "persons": {"A": {"salary": {"2026-01": 1000}},
                        "B": {"salary": {"2026-01": 1500}}},
            "households": {"h": {"members": ["A", "B"]}},
        })
        got = float(sim.calculate("household_income", "2026-01")[0])
        ok = abs(got - 2500.0) < 1e-6
        print(f"  household_income(2026-01) = {got}  (L4 expected 2500.0)  "
              f"{'OK' if ok else '*** MISMATCH ***'}")
        assert ok, got
    elif which == "roles":
        sit = {"persons": {"alice": {"salary": {"2026-01": 2000}},
                           "bob": {"salary": {"2026-01": 500}},
                           "carol": {"salary": {"2026-01": 0}}},
               "households": {"hh": {"adults": ["alice", "bob"],
                                     "children": ["carol"]}}}
        for var, e in [("number_of_adults", 2.0), ("adult_income", 2500.0),
                       ("any_high_earner", 1.0), ("all_adults_earn", 1.0)]:
            sim = SimulationBuilder().build_from_entities(tbs, sit)
            got = float(sim.calculate(var, "2026-01")[0])
            ok = abs(got - e) < 1e-6
            print(f"  {var} = {got}  (L4 expected {e})  "
                  f"{'OK' if ok else '*** MISMATCH ***'}")
            assert ok, got
    elif which == "housing":
        cases = [("tenant", 40, "housing_tax", 400.0),
                 ("free_lodger", 40, "housing_tax", 0.0),
                 ("owner", 100, "housing_tax", 1000.0),
                 ("free_lodger", 40, "owns_or_rents", 0.0)]
        for occ, sz, var, exp in cases:
            sim = SimulationBuilder().build_from_entities(tbs, {"households": {"h": {
                "occupancy_status": {"2026-01": occ},
                "accommodation_size": {"2026-01": sz}}}})
            got = float(sim.calculate(var, "2026-01")[0])
            ok = abs(got - exp) < 1e-6
            print(f"  {occ} sz={sz} {var} = {got}  (L4 expected {exp})  "
                  f"{'OK' if ok else '*** MISMATCH ***'}")
            assert ok, got
    elif which == "agecheck":
        def hh(members):
            return {"persons": {p: {"birth_year": {"2026-01": by}} for p, by in members},
                    "households": {"h": {"members": [p for p, _ in members]}}}
        sim = SimulationBuilder().build_from_entities(tbs, hh([("baby", 2020), ("teen", 2010)]))
        for var, e in [("age", 6.0), ("has_young_child", 1.0)]:
            got = float(sim.calculate(var, "2026-01")[0]); ok = abs(got - e) < 1e-6
            print(f"  {var} = {got}  (L4 expected {e})  {'OK' if ok else '*** MISMATCH ***'}")
            assert ok, got
        sim2 = SimulationBuilder().build_from_entities(tbs, hh([("teen", 2010)]))
        got = float(sim2.calculate("has_young_child", "2026-01")[0])
        print(f"  has_young_child(no kids) = {got}  (L4 expected 0.0)  "
              f"{'OK' if abs(got) < 1e-6 else '*** MISMATCH ***'}")
        assert abs(got) < 1e-6, got
    elif which == "incometax":
        # scalar legislation parameter (time-varying rate) read by period.
        for per, exp in [("2013-06", 260.0), ("2015-01", 300.0), ("2012-01", 320.0)]:
            check(tbs, "persons", {"p": {"salary": {per: 2000}}},
                  "income_tax", per, exp)
    elif which == "basic-income":
        # the country-template basic_income: dated formulas + scalar params.
        for per, age, sal, exp in [("2015-11", 18, 0, 0.0), ("2015-12", 18, 0, 600.0),
                                   ("2015-12", 17, 0, 0.0), ("2015-12", 18, 1200, 0.0),
                                   ("2016-12", 17, 0, 0.0), ("2016-12", 18, 1200, 600.0)]:
            check(tbs, "persons", {"p": {"age": {per: age}, "salary": {per: sal}}},
                  "basic_income", per, exp)
    elif which == "dated":
        # dated formulas: OpenFisca picks formula_YYYY_MM by period.
        for per, sal, exp in [("2015-11", 0, 0.0), ("2015-12", 0, 600.0),
                              ("2015-12", 1200, 0.0), ("2016-12", 1200, 600.0)]:
            check(tbs, "persons", {"p": {"salary": {per: sal}}},
                  "basic_income", per, exp)
    elif which == "scale":
        # time-varying marginal-rate scale: brackets resolve by period.
        for per, sal, exp in [("2013-01", 2000, 60.0), ("2013-01", 15000, 660.0),
                              ("2015-01", 2000, 80.0), ("2015-01", 15000, 824.0),
                              ("2017-01", 2000, 40.0), ("2017-01", 15000, 816.0)]:
            check(tbs, "persons", {"p": {"salary": {per: sal}}},
                  "social_security_contribution", per, exp)
    elif which == "gt-guard":
        # `y GREATER THAN 2015` is dated 2016, not 2015.
        for per, exp in [("2015-06", 100.0), ("2016-06", 200.0)]:
            check(tbs, "persons", {"p": {"salary": {per: 0}}}, "tax", per, exp)
    elif which == "scalar-formula":
        # a formula that reads no variable must give one value per person.
        sim = SimulationBuilder().build_from_entities(tbs, {"persons": {
            "a": {"salary": {"2015-01": 0}}, "b": {"salary": {"2015-01": 0}}}})
        got = [float(x) for x in sim.calculate("tax", "2015-01")]
        ok = got == [200.0, 200.0]
        print(f"  tax(2015-01), two persons = {got}  (L4 expected 200.0 each)  "
              f"{'OK' if ok else '*** MISMATCH ***'}")
        assert ok, got
    elif which == "role-status":
        sim = SimulationBuilder().build_from_entities(tbs, {
            "persons": {"a": {"salary": {"2026-01": 1000}}, "k": {"salary": {"2026-01": 5}}},
            "households": {"h": {"status": ["a"], "children": ["k"]}}})
        got = float(sim.calculate("status_income", "2026-01")[0])
        ok = abs(got - 1000.0) < 1e-6
        print(f"  status_income = {got}  (L4 expected 1000.0)  {'OK' if ok else '*** MISMATCH ***'}")
        assert ok, got
    elif which == "carriage-return":
        check(tbs, "persons", {"p": {"job": {"2026-01": "paid\rworker"}}}, "paid", "2026-01", 1)
        check(tbs, "persons", {"p": {"job": {"2026-01": "paid worker"}}}, "paid", "2026-01", 0)
    elif which == "python-keywords":
        check(tbs, "class_s", {"c": {"size": {"2026-01": 3}, "who": {"2026-01": "somebody"}}},
              "fee", "2026-01", 30.0)
    elif which == "not-scalar":
        # NOT / IMPLIES over a condition that reads no variable.
        for var, per, sal, exp in [("old_amount", "2026-01", 0, 200.0), ("old_amount", "2010-01", 0, 100.0),
                                   ("pre_reform", "2026-01", 0, 0), ("pre_reform", "2010-01", 0, 1),
                                   ("reform_test", "2026-01", 0, 0), ("reform_test", "2010-01", 0, 1),
                                   ("relief", "2026-01", 1000, 0.0), ("relief", "2010-01", 1000, 50.0),
                                   ("never", "2026-01", 0, 2.0)]:
            check(tbs, "persons", {"p": {"salary": {per: sal}}}, var, per, exp)
    elif which == "scalar-arithmetic":
        check(tbs, "persons", {"p": {"salary": {"2026-01": 7}}}, "notional_tax", "2026-01", 1000.0)
        check(tbs, "persons", {"p": {"salary": {"2026-01": 7}}}, "guarded_share", "2026-01", 7.0)
        check(tbs, "persons", {"p": {"salary": {"2031-01": 7}}}, "guarded_share", "2031-01", 200.0)
    elif which == "python-builtins":
        sit = {"s": {"band": {"ETERNITY": "low"}, "slot": {"ETERNITY": "offpeak"},
                     "float_": {"ETERNITY": True}, "salary": {"ETERNITY": 5}}}
        check(tbs, "super_s", sit, "tax", "2026-01", 5.0)
        check(tbs, "super_s", sit, "fare", "2026-01", 2.0)
    elif which == "eternity-parameter":
        # an ETERNITY variable, calculated at a month (openfisca-core cannot
        # pick a formula for the period ETERNITY itself).
        for inc, exp in [(10, 600.0), (2000, 0.0)]:
            check(tbs, "persons", {"p": {"income": {"ETERNITY": inc}}}, "grant", "2026-01", exp)
    else:
        raise SystemExit(f"unknown case: {which}")
    print("ROUND-TRIP OK")


if __name__ == "__main__":
    main()
