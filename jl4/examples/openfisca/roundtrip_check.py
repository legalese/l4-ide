"""Defensibility round-trip: load a module emitted by `l4 openfisca`, run it in
a real OpenFisca simulation, and assert the results match the L4 #EVAL values.

Usage (inside the openfisca venv):
    python roundtrip_check.py <generated_module.py> <flat-tax|benefit>
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
    elif which == "scale":
        # time-varying marginal-rate scale: brackets resolve by period.
        for per, sal, exp in [("2013-01", 2000, 60.0), ("2013-01", 15000, 660.0),
                              ("2015-01", 2000, 80.0), ("2015-01", 15000, 824.0),
                              ("2017-01", 2000, 40.0), ("2017-01", 15000, 816.0)]:
            check(tbs, "persons", {"p": {"salary": {per: sal}}},
                  "social_security_contribution", per, exp)
    else:
        raise SystemExit(f"unknown example: {which}")
    print("ROUND-TRIP OK")


if __name__ == "__main__":
    main()
