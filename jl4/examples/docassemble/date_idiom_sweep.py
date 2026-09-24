"""Re-runnable evidence for the date-idiom finding in DOCASSEMBLE-EXPORT-SPEC §8.12 (R12).

The spec, `Lower.hs`, `Main.hs` and `roundtrip_check.py` all quote the same four
numbers — 13,514 birth dates, 27,028 comparisons, `date_difference(...).years`
disagreeing on 6,629 of them, `.plus(years=n)` on 9. Those numbers were measured
once during M4 and, until this file, only their conclusion survived, as prose in
four comments. They are now cited by the cross-backend date ledger
(`DATE-LIBRARY-SPEC.md` §3.7, requirement R-D10) as the witness for a rule every
backend is asked to follow, so they had better be checkable rather than merely
believed. This script re-derives them from scratch.

It is a hand-run probe, not a test: it needs a venv carrying real
`docassemble.base` (see README.md, "Prove it runs in real docassemble"), which is
local evidence and never a build dependency. Run it from the repo root:

    <venv>/bin/python jl4/examples/docassemble/date_idiom_sweep.py
    <venv>/bin/python jl4/examples/docassemble/date_idiom_sweep.py --emit-oracle-l4 /tmp/o.l4

Exit status is the number of idioms whose disagreement count differs from the
figure the spec claims, so a drift in docassemble's own date library fails it
loudly.

## What is being compared, and against what

The oracle is L4's `Date d m y`, which is the LENIENT, ROLLING constructor:
`Date 29 2 2022` evaluates to `DATE OF 1, 3, 2022`. `l4_anniversary` below models
that rolling rule in Python, because calling the L4 evaluator 27,028 times is not
worth the wall-clock — but a model of an oracle is not an oracle, so
`--emit-oracle-l4` writes an `.l4` file of `#EVAL`s over the dates where any
convention could differ (every 29/30/31-of-the-month birth date, every leap-day
birth date, and a fixed-seed sample of ordinary ones) which `l4 run` checks the
model against. Do that whenever you doubt the model; the disagreement counts
below are only as good as it.

The four candidate lowerings of "is this person n years old on the assessed
date", all of which a reasonable implementer might write:

    A  date_difference(starting=born, ending=assessed).years >= n     <- unsound
    B  born.plus(years=n) <= assessed                                 <- clamps
    C  born <= assessed.minus(years=n)                                <- exact
    D  born.minus(days=born.day-1).plus(years=n).plus(days=born.day-1) <= assessed

D is what the bridge emits. C is exact too; D is preferred because it keeps the
lawyer's named binding (`the eighteenth birthday`) as a named unit in the target
instead of dissolving it into an inequality that appears nowhere in the source —
the principle the ledger records as R-D11.
"""

import argparse
import datetime
import sys
import types

SPEC_CLAIM = {  # DOCASSEMBLE-EXPORT-SPEC.md §8.12, the table under "Which idiom, measured"
    "A date_difference(...).years >= n": 6629,
    "B born.plus(years=n) <= assessed": 9,
    "C born <= assessed.minus(years=n)": 0,
    "D first-of-month shift (shipped)": 0,
}
SPEC_BIRTH_DATES = 13514
SPEC_COMPARISONS = 27028

FIRST_BIRTH = datetime.date(1970, 1, 1)
LAST_BIRTH = datetime.date(2006, 12, 31)
AGE = 18


# ---------------------------------------------------------------------------
# The headless docassemble bootstrap (README.md §"the headless harness"; the same
# five ingredients roundtrip_check.py documents, minus the interview machinery).
# ---------------------------------------------------------------------------

def bootstrap_docassemble():
    _pyz = types.ModuleType("pyzbar.pyzbar")
    _pyz.decode = lambda *a, **k: []
    _pkg = types.ModuleType("pyzbar")
    _pkg.pyzbar = _pyz
    sys.modules.setdefault("pyzbar", _pkg)
    sys.modules.setdefault("pyzbar.pyzbar", _pyz)

    import pluggy

    hookimpl = pluggy.HookimplMarker("docassemble")

    class HeadlessPlugin:
        @hookimpl
        def get_configuration(self):
            return {"debug": False}

        @hookimpl
        def get_default_language(self):
            return "en"

        @hookimpl
        def get_default_dialect(self):
            return "us"

        @hookimpl
        def get_default_locale(self):
            return "US.utf8"

        @hookimpl
        def get_default_timezone(self):
            # A civil date has no timezone (ledger R-D4). Fixing UTC here keeps
            # the sweep independent of the machine's clock settings; the
            # comparisons below are all taken on .date() so it cannot leak in.
            return "UTC"

        @hookimpl
        def get_default_country(self):
            return "US"

        @hookimpl
        def get_debug_status(self):
            return False

    from docassemble.base.plugin_manager import pm

    pm.register(HeadlessPlugin())

    from docassemble.base.util import as_datetime, date_difference

    return as_datetime, date_difference


# ---------------------------------------------------------------------------
# The oracle: L4's rolling `Date d m y`
# ---------------------------------------------------------------------------

def l4_anniversary(born, years):
    """The nth anniversary under L4's LENIENT `Date d m y`, which ROLLS.

    `Date 29 2 2022` is `DATE OF 1, 3, 2022` (executed). So the anniversary of a
    29 Feb birth in a non-leap year is 1 March, NOT 28 February — which is what
    `dateutil.relativedelta` (and therefore docassemble's `.plus`) gives.
    """
    y, m, d = born.year + years, born.month, born.day
    while True:
        try:
            return datetime.date(y, m, d)
        except ValueError:
            # Overflow past the end of the month rolls into the next one, by the
            # amount of the overflow: 29 Feb -> 1 Mar, 31 Apr -> 1 May.
            last = _days_in_month(y, m)
            over = d - last
            m += 1
            if m == 13:
                m, y = 1, y + 1
            d = over


def _days_in_month(y, m):
    if m == 12:
        return 31
    return (datetime.date(y + (m // 12), (m % 12) + 1, 1) - datetime.timedelta(days=1)).day


def birth_dates():
    d, out = FIRST_BIRTH, []
    while d <= LAST_BIRTH:
        out.append(d)
        d += datetime.timedelta(days=1)
    return out


# ---------------------------------------------------------------------------
# Oracle validation: make `l4 run` check the Python model
# ---------------------------------------------------------------------------

def emit_oracle_l4(path):
    """Write #EVALs over every birth date where a convention could differ.

    Every 29th/30th/31st-of-the-month birth date in the sweep range, plus a
    fixed-stride sample of ordinary ones. If `l4 run` agrees with every #EVAL,
    `l4_anniversary` is L4's rule on the cases where rules disagree.
    """
    interesting = [d for d in birth_dates() if d.day >= 29]
    ordinary = [d for i, d in enumerate(birth_dates()) if d.day < 29 and i % 997 == 0]
    sample = sorted(set(interesting + ordinary))

    lines = [
        "-- GENERATED by jl4/examples/docassemble/date_idiom_sweep.py --emit-oracle-l4.",
        "-- Checks that the script's Python model of L4's rolling `Date d m y` IS",
        "-- L4's actual rule. Run `l4 run` on this file: every #EVAL must be TRUE.",
        "--",
        "-- The anniversary is built with the LENIENT `Date d m y` (which rolls) and",
        "-- compared against a `YMD y m d` literal (which is bounds-checked and",
        "-- refuses), so a rolled expectation cannot be smuggled past by the same",
        "-- leniency that produced it.",
        "",
        "IMPORT prelude",
        "IMPORT daydate",
        "",
        "GIVEN d IS A DATE",
        "GIVETH A DATE",
        f"`the {AGE}th anniversary of` d MEANS",
        f"  Date (DATE_DAY d) (DATE_MONTH d) ((DATE_YEAR d) PLUS {AGE})",
        "",
    ]
    for d in sample:
        want = l4_anniversary(d, AGE)
        lines.append(
            f"#EVAL (`the {AGE}th anniversary of` (YMD {d.year} {d.month} {d.day}))"
            f" EQUALS (YMD {want.year} {want.month} {want.day})"
        )
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    return len(sample)


# ---------------------------------------------------------------------------
# The sweep
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--emit-oracle-l4", metavar="PATH",
                    help="write the oracle-validation .l4 and exit (run it with `l4 run`)")
    args = ap.parse_args()

    if args.emit_oracle_l4:
        n = emit_oracle_l4(args.emit_oracle_l4)
        print(f"wrote {n} #EVAL cases to {args.emit_oracle_l4}")
        print(f"check the model with:  l4 run {args.emit_oracle_l4}")
        return 0

    as_datetime, date_difference = bootstrap_docassemble()

    def dt(d):
        return as_datetime(d.isoformat())

    counts = {k: 0 for k in SPEC_CLAIM}
    witnesses = {k: [] for k in SPEC_CLAIM}
    births = birth_dates()
    comparisons = 0

    for born in births:
        anniversary = l4_anniversary(born, AGE)
        b = dt(born)
        shifted = b.minus(days=born.day - 1).plus(years=AGE).plus(days=born.day - 1)
        for assessed in (anniversary, anniversary - datetime.timedelta(days=1)):
            comparisons += 1
            a = dt(assessed)
            oracle = assessed >= anniversary

            got = {
                "A date_difference(...).years >= n":
                    date_difference(starting=b, ending=a).years >= AGE,
                "B born.plus(years=n) <= assessed":
                    b.plus(years=AGE).date() <= assessed,
                "C born <= assessed.minus(years=n)":
                    born <= a.minus(years=AGE).date(),
                "D first-of-month shift (shipped)":
                    shifted.date() <= assessed,
            }
            for name, val in got.items():
                if val != oracle:
                    counts[name] += 1
                    if len(witnesses[name]) < 3:
                        witnesses[name].append((born, assessed, val, oracle))

    print(f"birth dates : {len(births)}   (spec claims {SPEC_BIRTH_DATES})")
    print(f"comparisons : {comparisons}   (spec claims {SPEC_COMPARISONS})")
    print()
    print(f"{'idiom':<38} {'disagreements':>13} {'spec':>8}  verdict")
    drift = 0
    for name, claimed in SPEC_CLAIM.items():
        got = counts[name]
        ok = got == claimed
        drift += 0 if ok else 1
        pct = f"{100.0 * got / comparisons:.1f}%" if got else "—"
        print(f"{name:<38} {got:>7} ({pct:>5}) {claimed:>8}  {'OK' if ok else 'DRIFT'}")
    print()
    for name, ws in witnesses.items():
        if ws:
            print(f"first witnesses for {name}:")
            for born, assessed, val, oracle in ws:
                print(f"    born {born}  assessed {assessed}  idiom={val}  L4={oracle}")

    if len(births) != SPEC_BIRTH_DATES or comparisons != SPEC_COMPARISONS:
        print("\nSWEEP SIZE DRIFT: the spec's denominators no longer describe this run.")
        drift += 1
    print("\n" + ("ALL FIGURES REPRODUCE" if drift == 0
                  else f"{drift} figure(s) drifted from the spec"))
    return drift


if __name__ == "__main__":
    sys.exit(main())
