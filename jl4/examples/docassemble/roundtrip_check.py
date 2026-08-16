"""Defensibility round-trip: load an interview emitted by `l4 docassemble`,
drive it headlessly in real docassemble.base (no server, no Redis, no Flask),
and assert the verdict/goal equals the L4 #EVAL oracle.

Usage (inside the docassemble venv -- recipe in README.md):
    python roundtrip_check.py <emitted.yml> <example-name> [--quiet]

<example-name> is one of: rodents-and-vermin, seam, enum-triage, defaults,
computed-and-shadow, assume-via-fn.
Each example carries one fixture case per #EVAL in its .l4 source; the drive
loop assembles, reads the pending question's field variable names, writes the
fixture's answer for each into the interview's user_dict, and re-assembles,
until a terminal (fieldless / deadend) screen is reached. A question for a
variable that has NO fixture is a hard failure -- deliberately: the seam
example's NotApplicable case carries only the scope answer, so being asked a
requirement question on that path fails the run (the R4 scope-first claim,
tested as a claim).

Debug defaults to True (--quiet turns it off): under debug the engine records
its seeking history, which is printed on failure.

Grown from specs/todo/docassemble-export/probe_headless.py (spec Appendix B).
The pyzbar stub and the ~13-hookimpl HeadlessPlugin are kept from the probe;
get_configuration serves the config dict directly (no config.load, no
config.yml). Never import docassemble.base.interview_cache: its get_index
hits get_server_redis unconditionally.
"""

import re
import sys
import types

# ---------------------------------------------------------------------------
# CLI arguments (parsed before any docassemble import: DEBUG feeds the config
# dict that the get_configuration hookimpl serves).
# ---------------------------------------------------------------------------

args = [a for a in sys.argv[1:] if not a.startswith("--")]
flags = {a for a in sys.argv[1:] if a.startswith("--")}
if len(args) != 2:
    raise SystemExit(__doc__)
YAML_PATH, WHICH = args
DEBUG = "--quiet" not in flags

# ---------------------------------------------------------------------------
# Stub pyzbar (barcode reading) so util.py imports without libzbar; the
# harness never decodes barcodes. Clean alternative: brew install zbar.
# ---------------------------------------------------------------------------

_pyzbar_mod = types.ModuleType("pyzbar.pyzbar")
_pyzbar_mod.decode = lambda *a, **k: []
_pyzbar_pkg = types.ModuleType("pyzbar")
_pyzbar_pkg.pyzbar = _pyzbar_mod
sys.modules.setdefault("pyzbar", _pyzbar_pkg)
sys.modules.setdefault("pyzbar.pyzbar", _pyzbar_mod)

# ---------------------------------------------------------------------------
# HeadlessPlugin: the pluggy seam new in docassemble 1.10.0. Registering
# these ~13 hookimpls makes docassemble.base parse AND assemble interviews
# in-process with no server at all. get_configuration serves the dict
# directly -- no config.load, no config.yml on disk. 'debug' matters: the
# engine only records its seeking history under debug.
# ---------------------------------------------------------------------------

import pluggy

hookimpl = pluggy.HookimplMarker("docassemble")

DACONFIG = {
    "debug": DEBUG,
    # Language/locale/timezone defaults are answered by the dedicated
    # hookimpls below; extend this dict if a KeyError ever surfaces.
}


class HeadlessPlugin:
    @hookimpl
    def get_configuration(self):
        return DACONFIG

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
    def get_default_voice(self):
        return None

    @hookimpl
    def get_default_timezone(self):
        return "America/New_York"

    @hookimpl
    def get_default_country(self):
        return "US"

    @hookimpl
    def get_debug_status(self):
        return DEBUG

    @hookimpl
    def get_hostname(self):
        return "localhost"

    @hookimpl
    def get_main_page_parts(self):
        return {}

    @hookimpl
    def get_default_table_class(self):
        return "table table-striped"

    @hookimpl
    def get_default_thead_class(self):
        return "table-primary"

    @hookimpl
    def url_finder(self, file_reference, kwargs):
        return ""

    @hookimpl
    def absolute_filename(self, the_file):
        return the_file


from docassemble.base.plugin_manager import pm

pm.register(HeadlessPlugin())

import docassemble.base.functions as functions
import docassemble.base.parse as parse
from docassemble.base.interview_source import InterviewSourceString
from docassemble.base.thread_context import empty_globals, global_context

try:
    from docassemble.base.codec import from_safeid  # 1.10.x home
except ImportError:  # pragma: no cover - older layouts re-export it in parse
    from_safeid = getattr(parse, "from_safeid", None)

# ---------------------------------------------------------------------------
# Fixture tables: one case per #EVAL in the corresponding .l4 file. Keys are
# the sanitised L4 field names (matched prefix-insensitively against whatever
# variable the emitted interview actually asks, so `i.foo`, `t.foo`, and a
# flat `foo` all resolve); values are the #EVAL's record-field values.
# "goal" names the emitted goal variable's candidate spellings and the L4
# #EVAL value; "verdict", when present, is the R4 six-valued verdict expected
# from a seam-lowered driver, asserted iff a verdict variable is found.
# ---------------------------------------------------------------------------

EXAMPLES = {
    "rodents-and-vermin": {
        "goal_candidates": ["insurance_covered", "interview_goal"],
        "verdict_candidates": ["verdict", "insurance_covered_verdict"],
        "cases": [
            {   # the single #EVAL: everything FALSE => not covered
                "label": "all-false",
                "fixtures": {
                    "loss_or_damage_caused_by_rodents": False,
                    "loss_or_damage_caused_by_insects": False,
                    "loss_or_damage_caused_by_vermin": False,
                    "loss_or_damage_caused_by_birds": False,
                    "loss_or_damage_to_contents": False,
                    "any_other_exclusion_applies": False,
                    "a_household_appliance": False,
                    "a_swimming_pool": False,
                    "a_plumbing_heating_or_air_conditioning_system": False,
                    "loss_or_damage_ensuing_covered_loss": False,
                },
                "goal": False,
                "verdict": "Fails",  # non-seam boolean goal: Holds/Fails
            },
        ],
    },
    "seam": {
        "goal_candidates": ["notice_rule_satisfied", "interview_goal"],
        "verdict_candidates": ["verdict", "notice_rule_satisfied_verdict"],
        "cases": [
            {
                "label": "Complies",
                "fixtures": {
                    "is_a_residential_tenancy": True,
                    "written_notice_was_given": True,
                    "months_of_notice_given": 3,
                },
                "goal": True,
                "verdict": "Complies",
            },
            {
                "label": "InBreach",
                "fixtures": {
                    "is_a_residential_tenancy": True,
                    "written_notice_was_given": True,
                    "months_of_notice_given": 1,
                },
                "goal": False,
                "verdict": "InBreach",
            },
            {
                # Deliberately scope-only: per R4 the driver must resolve
                # scope first and never seek a requirement question on the
                # NotApplicable path. If the emitted interview asks for the
                # notice fields here, lookup fails and so does the run.
                "label": "NotApplicable",
                "fixtures": {
                    "is_a_residential_tenancy": False,
                },
                "goal": True,  # classical IMPLIES is vacuously TRUE in L4
                "verdict": "NotApplicable",
            },
        ],
    },
    "enum-triage": {
        "goal_candidates": ["notification_deadline_in_days", "interview_goal"],
        "verdict_candidates": ["verdict"],
        "cases": [
            # enum answers are the L4 constructor names as strings (R6)
            {"label": "Critical",
             "fixtures": {"assessed_severity": "Critical"},
             "goal": 3, "verdict": None},
            {"label": "Reportable",
             "fixtures": {"assessed_severity": "Reportable"},
             "goal": 30, "verdict": None},
            {"label": "Trivial (OTHERWISE arm)",
             "fixtures": {"assessed_severity": "Trivial"},
             "goal": 0, "verdict": None},
        ],
    },
    "defaults": {
        "goal_candidates": ["the_consumer_may_cancel", "interview_goal"],
        "verdict_candidates": ["verdict", "the_consumer_may_cancel_verdict"],
        "cases": [
            {   # absent path for both MAYBEs: yesnomaybe None IS NOTHING,
                # empty string IS NOTHING (R8)
                "label": "both absent",
                "fixtures": {
                    "was_concluded_at_a_distance": True,
                    "consumer_confirmed_waiver": None,
                    "promotional_code_used": "",
                },
                "goal": True,
                "verdict": "Holds",
            },
            {   # present waiver defeats; promo question must be pruned by
                # short-circuit, so no promo fixture is supplied
                "label": "waiver present",
                "fixtures": {
                    "was_concluded_at_a_distance": True,
                    "consumer_confirmed_waiver": True,
                },
                "goal": False,
                "verdict": "Fails",
            },
            {   # present, decisive string
                "label": "FINAL-SALE code",
                "fixtures": {
                    "was_concluded_at_a_distance": True,
                    "consumer_confirmed_waiver": False,
                    "promotional_code_used": "FINAL-SALE",
                },
                "goal": False,
                "verdict": "Fails",
            },
            {   # present, non-decisive string
                "label": "ordinary code",
                "fixtures": {
                    "was_concluded_at_a_distance": True,
                    "consumer_confirmed_waiver": False,
                    "promotional_code_used": "SPRING10",
                },
                "goal": True,
                "verdict": "Holds",
            },
        ],
    },
    "computed-and-shadow": {
        # Review repairs, 2026-08-16. The `alternative` field sanitises to
        # `alternative_` (DAObject-namespace exclusion): before the repair
        # the interview never asked it and the bound method rode in truthy,
        # so the 'lawful' case below flagged the silent wrong verdict. The
        # goal expression also inlines the computed (MEANS) field
        # `meets the minimum`.
        "goal_candidates": ["offer_lawful", "interview_goal"],
        "verdict_candidates": ["verdict", "offer_lawful_verdict"],
        "cases": [
            {"label": "lawful",
             "fixtures": {"salary_offered": 3500, "alternative": False},
             "goal": True, "verdict": "Holds"},
            {"label": "alternative accommodation defeats",
             "fixtures": {"salary_offered": 3500, "alternative": True},
             "goal": False, "verdict": "Fails"},
            {   # short-circuit prunes the alternative question entirely:
                # no fixture for it, so being asked would fail the run
                "label": "below minimum (alternative pruned)",
                "fixtures": {"salary_offered": 2000},
                "goal": False, "verdict": "Fails"},
        ],
    },
    "assume-via-fn": {
        # Review repair, 2026-08-16: `base rate` is an ASSUME referenced only
        # through the inlined `adjusted` function; before the repair its
        # question block was never emitted and assembly raised
        # DAErrorMissingVariable. ASSUME modules do not evaluate, so these
        # expectations are hand-computed (amount + base rate > 100), not
        # #EVAL-copied.
        "goal_candidates": ["over_threshold", "interview_goal"],
        "verdict_candidates": ["verdict", "over_threshold_verdict"],
        "cases": [
            {"label": "over (60 + 50 = 110 > 100)",
             "fixtures": {"amount": 60, "base_rate": 50},
             "goal": True, "verdict": "Holds"},
            {"label": "under (30 + 50 = 80 <= 100)",
             "fixtures": {"amount": 30, "base_rate": 50},
             "goal": False, "verdict": "Fails"},
        ],
    },
}

MAX_EXTRA_STEPS = 8  # assemble passes beyond one-per-fixture before giving up


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fuzz(name):
    """Sanitise a name the way the emitter's pyIdent-shaped sanitiser does,
    so fixture keys match whatever exact spelling the backend chose."""
    return re.sub(r"_+", "_", re.sub(r"[^0-9a-zA-Z]+", "_", str(name))).strip("_").lower()


def lookup(fixtures_fuzzed, varname):
    """Resolve an asked variable name against the fixture dict: try the full
    (possibly dotted) name, then its last attribute component."""
    for candidate in (varname, varname.split(".")[-1]):
        key = fuzz(candidate)
        if key in fixtures_fuzzed:
            return key, fixtures_fuzzed[key]
    return None, None


def field_variables(status):
    """The variable names the pending question's fields would define."""
    names = []
    try:
        fields = status.get_field_list()
    except Exception:
        fields = getattr(status.question, "fields", []) or []
    for field in fields:
        saveas = getattr(field, "saveas", None)
        if saveas is None:
            continue
        decoded = None
        if from_safeid is not None:
            try:
                decoded = from_safeid(saveas)
            except Exception:
                decoded = None
        names.append(decoded if decoded is not None else str(saveas))
    return names


def write_answer(user_dict, varname, value):
    """Define a (possibly dotted) interview variable, as the web layer would
    on form submission. exec in the user_dict namespace handles both plain
    names and DAObject attribute paths."""
    exec(f"{varname} = {value!r}", user_dict)


def find_variable(user_dict, candidates):
    """First candidate defined at the top level of the user_dict, matched
    exactly and then by sanitised spelling."""
    for cand in candidates:
        if cand in user_dict:
            return cand, user_dict[cand]
    by_fuzz = {fuzz(k): k for k in user_dict if isinstance(k, str) and not k.startswith("_")}
    for cand in candidates:
        key = by_fuzz.get(fuzz(cand))
        if key is not None:
            return key, user_dict[key]
    return None, None


def values_equal(got, expected):
    if isinstance(expected, bool) or isinstance(got, bool):
        return bool(got) == bool(expected)
    if isinstance(expected, (int, float)):
        try:
            return abs(float(got) - float(expected)) < 1e-6
        except (TypeError, ValueError):
            return False
    return got == expected


def dump_debug(status, transcript, user_dict):
    print("---- drive transcript (step, question type, field variables) ----")
    for row in transcript:
        print("  ", row)
    if DEBUG and status is not None:
        try:
            print("---- docassemble seeking history ----")
            for entry in status.get_history():
                print("  ", entry)
        except Exception as exc:
            print("  (seeking history unavailable:", repr(exc), ")")
    if user_dict is not None:
        names = sorted(k for k in user_dict
                       if isinstance(k, str) and not k.startswith("_") and k not in ("__builtins__",))
        print("---- user_dict top-level names ----")
        print("  ", names)


class RoundTripFailure(AssertionError):
    pass


# ---------------------------------------------------------------------------
# The drive loop: assemble -> answer the asked fields from the fixtures ->
# re-assemble, until a terminal (fieldless) screen.
# ---------------------------------------------------------------------------

def drive_case(interview, current_info, case):
    fixtures_fuzzed = {fuzz(k): v for k, v in case["fixtures"].items()}
    used = set()
    user_dict = parse.get_initial_dict()
    functions.this_thread.current_info = current_info
    transcript = []
    status = None
    for step in range(len(fixtures_fuzzed) + MAX_EXTRA_STEPS):
        status = parse.InterviewStatus(current_info=current_info)
        interview.assemble(user_dict, status)
        qtype = getattr(status.question, "question_type", None)
        asked = field_variables(status)
        transcript.append((step, qtype, asked))
        if not asked:
            # deadend / event verdict screen / any fieldless terminal
            return user_dict, status, transcript
        answered_any = False
        for varname in asked:
            key, answer = lookup(fixtures_fuzzed, varname)
            if key is None:
                dump_debug(status, transcript, user_dict)
                raise RoundTripFailure(
                    f"interview asked for {varname!r}, which has no fixture in "
                    f"case {case['label']!r} -- either the emitter demanded an "
                    f"input the L4 evaluation does not need (R2/R4 pruning "
                    f"violation) or the fixture table is stale")
            write_answer(user_dict, varname, answer)
            used.add(key)
            answered_any = True
        if not answered_any:
            break
    dump_debug(status, transcript, user_dict)
    raise RoundTripFailure(
        f"case {case['label']!r} never reached a terminal screen "
        f"(unused fixtures: {sorted(set(fixtures_fuzzed) - used)})")


def check_case(interview, current_info, example, case):
    user_dict, status, transcript = drive_case(interview, current_info, case)
    problems = []
    checked = []

    goal_name, goal_value = find_variable(user_dict, example["goal_candidates"])
    if goal_name is not None:
        if values_equal(goal_value, case["goal"]):
            checked.append(f"{goal_name} = {goal_value!r}")
        else:
            problems.append(
                f"goal {goal_name} = {goal_value!r}, L4 #EVAL expected {case['goal']!r}")

    verdict_name, verdict_value = find_variable(user_dict, example["verdict_candidates"])
    if case.get("verdict") is not None and verdict_name is not None:
        if verdict_value == case["verdict"]:
            checked.append(f"{verdict_name} = {verdict_value!r}")
        else:
            problems.append(
                f"verdict {verdict_name} = {verdict_value!r}, expected {case['verdict']!r}")

    if not checked and not problems:
        problems.append(
            f"neither a goal variable {example['goal_candidates']} nor a verdict "
            f"variable {example['verdict_candidates']} is defined at the end of "
            f"the interview")

    unused = sorted(set(fuzz(k) for k in case["fixtures"])
                    - {fuzz(v.split('.')[-1]) for _, _, asked in transcript for v in asked}
                    - {fuzz(v) for _, _, asked in transcript for v in asked})
    flag = "OK" if not problems else "*** MISMATCH ***"
    detail = "; ".join(checked + problems)
    extra = f"  (fixtures never asked: {unused})" if unused and DEBUG else ""
    print(f"  [{case['label']}] {detail}  {flag}{extra}")
    if problems:
        dump_debug(status, transcript, user_dict)
        raise RoundTripFailure(f"case {case['label']!r}: " + "; ".join(problems))


def main():
    example = EXAMPLES.get(WHICH)
    if example is None:
        raise SystemExit(f"unknown example: {WHICH!r} (known: {sorted(EXAMPLES)})")

    with open(YAML_PATH, encoding="utf-8") as handle:
        content = handle.read()

    # current_info: the 'action' key must be ABSENT entirely --
    # process_action tests `'action' not in current_info`, so `action: None`
    # force-asks a None variable and crashes assemble (spec §8.10).
    current_info = {
        "user": {
            "is_anonymous": False,
            "is_authenticated": True,
            "theid": 1,
            "the_user_id": 1,
            "roles": ["user"],
            "firstname": "RoundTrip",
            "lastname": "Harness",
            "email": "roundtrip@example.com",
            "country": "US",
            "subdivisionfirst": None,
            "subdivisionsecond": None,
            "subdivisionthird": None,
            "organization": None,
            "timezone": "America/New_York",
            "language": "en",
            "session_uid": "roundtrip-uid",
            "device_id": "roundtrip-device",
        },
        "session": "roundtrip",
        "secret": None,
        "yaml_filename": "interview.yml",
        "url": None,
        "url_root": None,
        "encrypted": False,
        "interface": "cli",
        "arguments": {},
    }

    with global_context(empty_globals()):
        source = InterviewSourceString(
            content=content, path="interview.yml", package="docassemble.l4roundtrip")
        interview = parse.Interview(source=source)
        print(f"== round-trip: {WHICH} == ({len(interview.questions_list)} blocks, debug={DEBUG})")
        for case in example["cases"]:
            check_case(interview, current_info, example, case)
    print("ROUND-TRIP OK")


if __name__ == "__main__":
    main()
