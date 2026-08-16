"""Defensibility round-trip: load an interview emitted by `l4 docassemble`,
drive it headlessly in real docassemble.base (no server, no Redis, no Flask),
and assert the verdict/goal equals the L4 #EVAL oracle.

Usage (inside the docassemble venv -- recipe in README.md):
    python roundtrip_check.py <source> <example-name> [--also=<source>] [--quiet]

<source> is EITHER a bare interview YAML (`l4 docassemble FILE -o out.yml`)
OR a package tree (`l4 docassemble FILE --package DIR`, M2/R11); the two are
told apart by os.path.isdir, and a package tree is resolved to its
docassemble/l4<slug>/data/questions/<stem>.yml with the package name and
sys.path entry that make its `modules: [.l4runtime]` block importable.

<example-name> is one of: rodents-and-vermin, seam, enum-triage, defaults,
computed-and-shadow, assume-via-fn, citations.
Each example carries one fixture case per #EVAL in its .l4 source; the drive
loop assembles, reads the pending question's field variable names, writes the
fixture's answer for each into the interview's user_dict, and re-assembles,
until a terminal (fieldless / deadend) screen is reached. A question for a
variable that has NO fixture is a hard failure -- deliberately: the seam
example's NotApplicable case carries only the scope answer, so being asked a
requirement question on that path fails the run (the R4 scope-first claim,
tested as a claim). The citations example uses the same device for the
short-circuit claim.

`--also=<source>` (repeatable) drives the SAME example against a second
source and asserts the per-case (goal, verdict, citations) triple is
identical. That is the M2 claim "packaging must not change meaning", tested
as a claim:

    python roundtrip_check.py out.yml citations --also=pkgdir

What the citations example additionally asserts, per case:
  * the explanation history docassemble accumulated (what
    logic_explanation() returns on the verdict screen) is EXACTLY the
    citations of the rules that fired, in order -- short-circuited rules did
    not decide anything, so citing them would be citing law that never fired;
  * the RENDERED verdict screen carries each citation verbatim, which is the
    only honest proof that Mako-hostile citation text survived escaping;
  * the interview's `auto terms:` glossary carries every L4 defined term.

Debug defaults to True (--quiet turns it off): under debug the engine records
its seeking history, which is printed on failure.

Grown from specs/todo/docassemble-export/probe_headless.py (spec Appendix B).
The pyzbar stub and the ~13-hookimpl HeadlessPlugin are kept from the probe;
get_configuration serves the config dict directly (no config.load, no
config.yml). Never import docassemble.base.interview_cache: its get_index
hits get_server_redis unconditionally.
"""

import os
import re
import sys
import types

# ---------------------------------------------------------------------------
# CLI arguments (parsed before any docassemble import: DEBUG feeds the config
# dict that the get_configuration hookimpl serves).
# ---------------------------------------------------------------------------

_raw = sys.argv[1:]
args = [a for a in _raw if not a.startswith("--")]
alsos = [a.split("=", 1)[1] for a in _raw if a.startswith("--also=")]
flags = {a for a in _raw if a.startswith("--") and not a.startswith("--also=")}
if len(args) != 2:
    raise SystemExit(__doc__)
YAML_PATH, WHICH = args
SOURCE_PATHS = [YAML_PATH] + alsos
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
#
# M2 adds three optional per-case keys, all exercised by the citations
# example: "explanations" (the EXACT ordered citation list the verdict screen
# must carry), "screen_contains" and "screen_omits" (substrings of the
# rendered verdict screen), plus one per-example key, "autoterms" (the
# `auto terms:` glossary docassemble must have parsed).
# ---------------------------------------------------------------------------

# The three citations carried by citations.l4, herald-stripped: L4's own
# `@ref ` prefix and the inline `<< >>` delimiters are L4 syntax and must
# never reach a user-facing docassemble screen.
CITE_CAP = "17 CFR 227.100(a)(1) — offering maximum"
CITE_ONE_INTERMEDIARY = "17 CFR 227.100(a)(3) — sales through one intermediary only"
# Deliberately Mako-hostile: BEGINS with `%` (a Mako control line at start of
# line, which would make the whole line vanish) and carries a literal
# `${ ... }` (a Mako expression, which would be evaluated). It must reach the
# rendered screen VERBATIM -- that is the R9.1 escaping claim, and rendering is
# the only place it can honestly be proven.
CITE_REGISTERED = "% of the proceeds retained is set out at ${ fee_schedule } — 17 CFR 227.300(a)"

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
    "citations": {
        # M2. Three sub-decisions, each carrying a statutory @ref, conjoined
        # by AND. CPython's `and` short-circuits, and docassemble only seeks a
        # variable it actually needs, so the SECOND case must fire rule 1 and
        # nothing else -- and must therefore cite rule 1 and nothing else.
        "goal_candidates": ["offering_exempt", "interview_goal"],
        "verdict_candidates": ["verdict", "offering_exempt_verdict"],
        # Every L4 defined term that must reach the `auto terms:` glossary.
        # Keys are as docassemble stores them: lowercased and
        # whitespace-collapsed (parse.py:2905 at 1b6678384).
        "autoterms": {
            "offering":
                "A securities offering made in reliance on the crowdfunding exemption",
            "within the annual cap":
                "The amount sold in reliance on the exemption in the preceding 12 months "
                "does not exceed $5,000,000",
            "sold through a single intermediary":
                "The offering is conducted exclusively through a single intermediary",
            "the intermediary is registered":
                "The intermediary is registered with the Commission as a funding portal",
        },
        "cases": [
            {
                "label": "exempt (all three rules fire)",
                "fixtures": {
                    "amount_raised_in_12_months": 1000000,
                    "sold_through_one_intermediary": True,
                    "intermediary_is_registered": True,
                },
                "goal": True,
                "verdict": "Holds",
                "explanations": [CITE_CAP, CITE_ONE_INTERMEDIARY, CITE_REGISTERED],
                "screen_contains": [CITE_CAP, CITE_ONE_INTERMEDIARY, CITE_REGISTERED],
            },
            {
                # Deliberately cap-only, the same device the seam example's
                # NotApplicable case uses: rules 2 and 3 are short-circuited
                # away, so being ASKED their questions fails the run, and
                # CITING them fails the run too.
                "label": "cap exceeded (rules 2 and 3 short-circuited away)",
                "fixtures": {
                    "amount_raised_in_12_months": 9000000,
                },
                "goal": False,
                "verdict": "Fails",
                "explanations": [CITE_CAP],
                "screen_contains": [CITE_CAP],
                "screen_omits": [CITE_ONE_INTERMEDIARY, CITE_REGISTERED],
            },
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


def resolve_source(path):
    """Return (yaml_text, package_name, label) for a bare YAML file or for a
    `l4 docassemble --package DIR` tree (M2/R11).

    For a package tree the interview lives at
    docassemble/l4<slug>/data/questions/<stem>.yml and its `modules:` block
    names `.l4runtime`. docassemble execs that as
    `from <question.package>.l4runtime import *` (parse.py:8569-8573 at
    1b6678384), so two things have to be right: the `package` we hand
    InterviewSourceString, and DIR being on sys.path so `docassemble.l4<slug>`
    is importable next to the installed `docassemble.base`. Both resolve
    because `docassemble` is a PEP 420 namespace package in the venv --
    site-packages/docassemble has no __init__.py -- which is exactly why R11
    forbids emitting one into the generated tree.
    """
    if os.path.isdir(path):
        ns = os.path.join(path, "docassemble")
        if not os.path.isdir(ns):
            raise SystemExit(
                f"{path!r} is a directory but has no docassemble/ inside it; "
                f"expected a `l4 docassemble --package` tree")
        pkgs = [d for d in sorted(os.listdir(ns))
                if os.path.isdir(os.path.join(ns, d))]
        if len(pkgs) != 1:
            raise SystemExit(
                f"expected exactly one generated package under {ns!r}, found {pkgs!r}")
        pkg = pkgs[0]
        qdir = os.path.join(ns, pkg, "data", "questions")
        if not os.path.isdir(qdir):
            raise SystemExit(f"package {pkg!r} has no data/questions/ directory")
        ymls = [f for f in sorted(os.listdir(qdir)) if f.endswith((".yml", ".yaml"))]
        if len(ymls) != 1:
            raise SystemExit(
                f"expected exactly one interview under {qdir!r}, found {ymls!r}")
        abspath = os.path.abspath(path)
        if abspath not in sys.path:
            sys.path.insert(0, abspath)
        with open(os.path.join(qdir, ymls[0]), encoding="utf-8") as handle:
            return handle.read(), f"docassemble.{pkg}", f"package:{path}"
    with open(path, encoding="utf-8") as handle:
        return handle.read(), "docassemble.l4roundtrip", f"yaml:{path}"


def explanations_of(user_dict, category="default"):
    """The explanation history docassemble's explain() accumulated, in order.

    explain() appends to this_thread.internal['explanations'][category]
    (util.py:13227 at 1b6678384) and assemble sets
    `this_thread.internal = user_dict['_internal']` (parse.py:8554), so
    reading it back off the user_dict is reading exactly what
    logic_explanation() (util.py:13259) returns on the verdict screen --
    without depending on how the screen chose to lay it out.

    Note explain() dedupes by string, so a repeated citation appears once;
    the assertions below are written to expect that.
    """
    internal = user_dict.get("_internal", {}) or {}
    return list((internal.get("explanations", {}) or {}).get(category, []))


def rendered_screen(status):
    """The Mako-rendered text of the screen the interview ended on.

    InterviewStatus.populate sets question_text/subquestion_text from the
    rendered content (parse.py:576-577), i.e. AFTER Mako. A citation that
    Mako ate -- a line-leading `%` swallowed as a control line, a `${ ... }`
    evaluated away -- is missing here and present in the YAML, which is why
    the escaping claim is asserted at this altitude and not on the emitted
    text.
    """
    parts = []
    for attr in ("question_text", "subquestion_text"):
        value = getattr(status, attr, None)
        if value:
            parts.append(str(value))
    return "\n".join(parts)


def check_autoterms(interview, example, label):
    """Assert the interview parsed an `auto terms:` glossary carrying every
    L4 defined term the example names.

    Asserted against interview.autoterms rather than against the YAML text so
    that it is docassemble, not this script, deciding the block was
    well-formed: a glossary emitted in a block that also has a `question` key
    is silently ignored (`if 'auto terms' in data and 'question' not in data`,
    parse.py:2878 at 1b6678384) and would simply not be here.
    """
    expected = example.get("autoterms")
    if not expected:
        return
    got = {}
    for lang_table in (getattr(interview, "autoterms", {}) or {}).values():
        for term, vals in lang_table.items():
            got[term] = vals["definition"]
    wrong = {t: d for t, d in expected.items() if got.get(t) != d}
    if wrong:
        raise RoundTripFailure(
            f"[{label}] the interview's `auto terms:` glossary is missing or wrong "
            f"for {sorted(wrong)}: got {got!r}, expected {expected!r}")
    print(f"  [glossary] {len(expected)} L4 defined terms present  OK")


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

    # M2: the citation claim. logic_explanation() must name EXACTLY the rules
    # that fired, in order. A short-circuited rule did not decide anything, so
    # a citation for it on the verdict screen is a citation to law that never
    # applied -- the failure this example exists to catch.
    got_explanations = explanations_of(user_dict)
    expected_explanations = case.get("explanations")
    if expected_explanations is not None:
        if got_explanations == expected_explanations:
            checked.append(f"citations {got_explanations!r}")
        else:
            problems.append(
                f"verdict-screen citations are {got_explanations!r}, expected "
                f"exactly {expected_explanations!r} in that order")

    # M2: the escaping claim, at the only altitude where it is honest -- after
    # Mako has rendered the screen.
    rendered = rendered_screen(status)
    for needle in case.get("screen_contains", []):
        if needle in rendered:
            checked.append(f"screen cites {needle!r}")
        else:
            problems.append(
                f"the rendered verdict screen does not carry {needle!r} verbatim "
                f"(Mako escaping, R9.1); rendered text was {rendered!r}")
    for needle in case.get("screen_omits", []):
        if needle in rendered:
            problems.append(
                f"the rendered verdict screen cites {needle!r}, a rule that was "
                f"short-circuited away and decided nothing on this path")

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
    # The observation `--also` compares across sources: packaging must not
    # change the meaning of the interview.
    return {
        "goal": goal_value,
        "verdict": verdict_value,
        "explanations": got_explanations,
    }


def main():
    example = EXAMPLES.get(WHICH)
    if example is None:
        raise SystemExit(f"unknown example: {WHICH!r} (known: {sorted(EXAMPLES)})")

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

    observations = {}
    with global_context(empty_globals()):
        for src_path in SOURCE_PATHS:
            content, package, label = resolve_source(src_path)
            source = InterviewSourceString(
                content=content, path="interview.yml", package=package)
            interview = parse.Interview(source=source)
            print(f"== round-trip: {WHICH} == [{label}] "
                  f"({len(interview.questions_list)} blocks, debug={DEBUG})")
            check_autoterms(interview, example, label)
            observations[label] = {
                case["label"]: check_case(interview, current_info, example, case)
                for case in example["cases"]
            }

        # M2: packaging must not change meaning. The same example driven from a
        # bare YAML and from inside a generated package must reach the same
        # goal, the same verdict and the same citations, case by case.
        labels = list(observations)
        for other in labels[1:]:
            for case_label, obs in observations[labels[0]].items():
                if observations[other][case_label] != obs:
                    raise RoundTripFailure(
                        f"case {case_label!r} differs between {labels[0]!r} and "
                        f"{other!r}: {obs!r} vs {observations[other][case_label]!r} "
                        f"-- packaging changed the meaning of the interview")
        if len(labels) > 1:
            print(f"AGREEMENT OK across {len(labels)} sources: {labels}")
    print("ROUND-TRIP OK")


if __name__ == "__main__":
    main()
