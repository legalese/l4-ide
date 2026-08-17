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
computed-and-shadow, assume-via-fn, citations (M1/M2), and tenant-list,
payload-enum, maybe-scalars, statutory-age, review-checklist, notice-letter
(M4 -- these are RED until M4 lands, and `l4 docassemble` refuses five of the
six outright, so there is nothing to drive; `m4_acceptance.sh` runs the whole
set in one command and prints each refusal verbatim).
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

import copy
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
from docassemble.base.thread_context import (
    empty_globals, global_context, user_dict_context)
from docassemble.base.util import as_datetime

try:
    from docassemble.base.codec import from_safeid  # 1.10.x home
except ImportError:  # pragma: no cover - older layouts re-export it in parse
    from_safeid = getattr(parse, "from_safeid", None)

# docassemble's own iterator resolver: `h.tenants[i].age` + the user_dict's
# current `i` -> `h.tenants[0].age` (parse.py:9921-9927 at 1b6678384).
substitute_vars_from_user_dict = getattr(
    parse, "substitute_vars_from_user_dict", None)

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
# The @ref on the EXPORTED decide, not on a WHERE binding. It is what makes the
# ordering of "explanations" load-bearing: the emitter puts `explain()` AFTER
# the assignment in every code block, and the goal block's assignment is what
# pulls on the sub-rules, so the goal completes LAST and its citation is last.
# Move any explain() above its assignment and this entry -- and only this entry
# -- changes position, which is what the assertion is here to catch.
CITE_EXEMPTION = "17 CFR 227.100 — the crowdfunding exemption"


class D:
    """A DATE fixture.

    `write_answer` normally does `exec(f"{var} = {value!r}", user_dict)`, which
    lands a date as a STRING -- and a string is not what the web layer stores.
    A submitted `datatype: date` answer is stored as
    `as_datetime(<submitted string>)` (webapp interview/views.py:1372 at
    1b6678384), i.e. a tz-aware DADateTime; comparing a DADateTime against a
    bare string raises TypeError. Writing a plain string would therefore make
    every date example fail for a reason that has nothing to do with the
    lowering, so a date fixture is wrapped and written through as_datetime,
    reproducing what views.py does.

    `str(DADateTime)` calls get_language() and needs the thread contextvar, so
    diagnostics use .isoformat().
    """

    def __init__(self, iso):
        self.iso = iso

    def value(self):
        return as_datetime(self.iso)

    def __repr__(self):
        return f"D({self.iso!r})"


# M4 adds these per-case keys, on top of M1's fixtures/goal/verdict and M2's
# explanations/screen_contains/screen_omits:
#
#   "undefined_after"  list of candidate-spelling lists. Every spelling in a
#                      group must be UNDEFINED when the interview ends. This is
#                      the claim `show if: {code:}` and the paired is-known
#                      question exist to make: a hidden field is not '' and not
#                      0, it is absent.
#   "never_asked"      substrings that must not appear in any asked variable
#                      name. (Omitting a fixture already fails the run when the
#                      variable is asked; this is for the case where a SIBLING
#                      element's fixture would otherwise satisfy the lookup.)
#   "post_conditions"  list of {"expr", "nonempty", "contains", "omits"} —
#                      evaluated in the finished user_dict. The attachment
#                      hazard is a SUCCESSFUL EMPTY RENDER, which raises
#                      nothing and logs nothing, so it can only be caught here.
#   "change_answer"    {var: new value} re-driven after the first terminal
#                      screen, the way a review-block Edit changes an answer
#                      (undefine + re-ask). Paired with "after", which carries
#                      goal/verdict/explanations for the re-drive. This is the
#                      M2 inherited defect (spec §8.4), whose named owner is M4.
#   "review_unanswered"  how many review rows must carry a never-asked marker.
#
# and these per-example keys:
#
#   "gather"           {"list": <attribute>, "n": <element count>} — answers a
#                      DAList's control questions (there_are_any /
#                      there_is_another / target_number) for a gather of n
#                      elements, whichever control shape the emitter chose.
#   "review"           {"labels": [...], "markers": [...]} — the review block's
#                      expected rows and the spellings accepted for "never
#                      asked".

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
                "explanations": [CITE_CAP, CITE_ONE_INTERMEDIARY, CITE_REGISTERED,
                                 CITE_EXEMPTION],
                "screen_contains": [CITE_CAP, CITE_ONE_INTERMEDIARY, CITE_REGISTERED,
                                    CITE_EXEMPTION],
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
                "explanations": [CITE_CAP, CITE_EXEMPTION],
                "screen_contains": [CITE_CAP, CITE_EXEMPTION],
                "screen_omits": [CITE_ONE_INTERMEDIARY, CITE_REGISTERED],
            },
            {
                # M4 owns this one. The M2 review pass bounded a defect to the
                # forward drive and named M4 as its owner (spec §8.4):
                # docassemble's explain() is session-scoped, so if the user
                # CHANGES an earlier answer the verdict screen can cite a rule
                # that no longer fires. Probing the shape the backend actually
                # emits found it is worse than documented -- the VERDICT itself
                # goes stale, not merely the citations -- and that no single
                # flag repairs it (`reconsider: True` alone makes the citations
                # ACCUMULATE contradictory rules; `initial: True` +
                # clear_explanations() empties them).
                #
                # Stated as a claim rather than as a design: after the change,
                # the goal, the verdict and the citations must be what they
                # would have been had the new answer been given first. Two
                # emission designs were verified to deliver that and this case
                # picks neither.
                "label": "cap exceeded, then corrected to 1,000 (M2 debt, M4 owns)",
                "fixtures": {
                    "amount_raised_in_12_months": 9000000,
                },
                "goal": False,
                "verdict": "Fails",
                "explanations": [CITE_CAP, CITE_EXEMPTION],
                "change_answer": {"amount_raised_in_12_months": 1000},
                "after": {
                    "fixtures": {
                        "amount_raised_in_12_months": 1000,
                        "sold_through_one_intermediary": True,
                        "intermediary_is_registered": True,
                    },
                    "goal": True,
                    "verdict": "Holds",
                    "explanations": [CITE_CAP, CITE_ONE_INTERMEDIARY,
                                     CITE_REGISTERED, CITE_EXEMPTION],
                    "screen_omits": [],
                },
            },
        ],
    },

    # ---------------------------------------------------------------- M4 ----

    "tenant-list": {
        # A. `LIST OF` via DAList gathering. The claim that matters is not that
        # a list can be gathered -- it is that PRUNING SURVIVES GATHERING.
        # `the tenant qualifies` is `age AT LEAST 18 AND signed`, and
        # docassemble prunes per element inside a gather (probed: element 0
        # aged 17 never had its second attribute asked), so a tenant who is
        # plainly a minor must never be asked whether they signed.
        #
        # Element fixtures are INDEXED (`tenants[0].age`). That is what makes
        # the pruning claim testable at all: the lookup resolves the exact
        # indexed spelling, so omitting `tenants[0].signed_the_agreement`
        # fails the run if it is asked -- while element 1's fixture, which is
        # present, cannot accidentally satisfy it.
        "goal_candidates": ["the_household_is_eligible", "interview_goal"],
        "verdict_candidates": ["verdict", "the_household_is_eligible_verdict"],
        "gather": {"list": "tenants"},
        "cases": [
            {
                "label": "two adult signatories, neither evicted",
                "gather_n": 2,
                "fixtures": {
                    "tenants[0].age": 30,
                    "tenants[0].signed_the_agreement": True,
                    "tenants[0].has_been_evicted": False,
                    "tenants[1].age": 25,
                    "tenants[1].signed_the_agreement": True,
                    "tenants[1].has_been_evicted": False,
                },
                "goal": True,
                "verdict": "Holds",
            },
            {
                # THE PER-ELEMENT PRUNING CLAIM. Element 0 is 17, so `all`
                # fails on it: nothing about element 0's signature, nothing
                # about element 1, and nothing about eviction can decide
                # anything. No fixture is supplied for any of them, so being
                # asked fails the run.
                "label": "first tenant is a minor (per-element pruning)",
                "gather_n": 2,
                "fixtures": {
                    "tenants[0].age": 17,
                },
                "goal": False,
                "verdict": "Fails",
                "never_asked": ["has_been_evicted"],
            },
            {
                "label": "second tenant was previously evicted",
                "gather_n": 2,
                "fixtures": {
                    "tenants[0].age": 30,
                    "tenants[0].signed_the_agreement": True,
                    "tenants[0].has_been_evicted": False,
                    "tenants[1].age": 25,
                    "tenants[1].signed_the_agreement": True,
                    "tenants[1].has_been_evicted": True,
                },
                "goal": False,
                "verdict": "Fails",
            },
            {
                # ZERO ELEMENTS. `all` over nothing is TRUE and `any` over
                # nothing is FALSE, so an empty household is "eligible" -- a
                # real drafting bug in the rule, pinned so the gather cannot
                # quietly paper over it. No element question may be asked.
                "label": "empty household (vacuously eligible)",
                "gather_n": 0,
                "fixtures": {},
                "goal": True,
                "verdict": "Holds",
                "never_asked": ["age", "signed_the_agreement", "has_been_evicted"],
            },
        ],
    },

    "payload-enum": {
        # B. Constructor payloads via `show if`. Two claims per case: the
        # follow-up for the constructor that was NOT chosen is never asked,
        # and it is left genuinely UNDEFINED afterwards -- not '', not 0.
        # Only the `{code: …}` spelling of `show if` does that; the
        # `{variable:, is:}` spelling is browser-side JavaScript and would
        # define every field on this drive.
        "goal_candidates": ["an_appeal_lies", "interview_goal"],
        "verdict_candidates": ["verdict", "an_appeal_lies_verdict"],
        "cases": [
            {
                "label": "granted (neither payload asked)",
                "fixtures": {"the_outcome": "granted"},
                "goal": False,
                "verdict": "Fails",
                "undefined_after": [
                    ["d.the_number_of_conditions", "the_number_of_conditions"],
                    ["d.the_stated_ground_of_refusal", "the_stated_ground_of_refusal"],
                ],
            },
            {
                "label": "granted on 2 conditions (within tolerance)",
                "fixtures": {
                    "the_outcome": "granted subject to conditions",
                    "the_number_of_conditions": 2,
                },
                "goal": False,
                "verdict": "Fails",
                "undefined_after": [
                    ["d.the_stated_ground_of_refusal", "the_stated_ground_of_refusal"],
                ],
            },
            {
                "label": "granted on 9 conditions (appealable)",
                "fixtures": {
                    "the_outcome": "granted subject to conditions",
                    "the_number_of_conditions": 9,
                },
                "goal": True,
                "verdict": "Holds",
                "undefined_after": [
                    ["d.the_stated_ground_of_refusal", "the_stated_ground_of_refusal"],
                ],
            },
            {
                # THE LEAK CLAIM. The NUMBER payload belongs to a constructor
                # that was not chosen. It must not arrive as 0 -- a 0 that
                # reached `GREATER THAN 3` would be answering a question the
                # law never put.
                "label": "refused for non-payment (no appeal)",
                "fixtures": {
                    "the_outcome": "refused",
                    "the_stated_ground_of_refusal": "non-payment of the fee",
                },
                "goal": False,
                "verdict": "Fails",
                "undefined_after": [
                    ["d.the_number_of_conditions", "the_number_of_conditions"],
                ],
            },
            {
                "label": "refused on the merits (appealable)",
                "fixtures": {
                    "the_outcome": "refused",
                    "the_stated_ground_of_refusal": "the premises are unsuitable",
                },
                "goal": True,
                "verdict": "Holds",
                "undefined_after": [
                    ["d.the_number_of_conditions", "the_number_of_conditions"],
                ],
            },
        ],
    },

    "maybe-scalars": {
        # C. MAYBE NUMBER / MAYBE DATE via paired is-known questions, plus
        # `WHEN JUST FALSE` (a payload-VALUE match).
        #
        # The is-known flag's emitted spelling is the implementer's to choose,
        # so every plausible spelling is supplied as an alias; unused fixtures
        # are reported, not failed. The VALUE fixtures are the load-bearing
        # ones: on an absence path no value fixture is supplied, so asking for
        # the value fails the run, and `undefined_after` then requires it to be
        # absent rather than 0 or ''.
        "goal_candidates": ["the_claim_must_be_referred", "interview_goal"],
        "verdict_candidates": ["verdict", "the_claim_must_be_referred_verdict"],
        "cases": [
            {
                "label": "1. income 2,500 declared (above threshold)",
                "fixtures": {
                    "declared_income_known": True,
                    "declared_income_is_known": True,
                    "has_declared_income": True,
                    "declared_income": 2500,
                },
                "goal": True,
                "verdict": "Holds",
            },
            {
                # A REAL ZERO. Read against case 3.
                "label": "2. income of ZERO declared (not referable)",
                "fixtures": {
                    "declared_income_known": True,
                    "declared_income_is_known": True,
                    "has_declared_income": True,
                    "declared_income": 0,
                    "date_last_worked_known": True,
                    "date_last_worked_is_known": True,
                    "has_date_last_worked": True,
                    "date_last_worked": D("2024-06-01"),
                    "the_qualifying_date": D("2024-01-01"),
                    "declaration_confirmed": True,
                },
                "goal": False,
                "verdict": "Fails",
            },
            {
                # ABSENCE. No value fixture: asking for the number fails the
                # run, and the number must be undefined at the end. A lowering
                # that lets a blank number field arrive as 0.0 answers this
                # case FALSE; one that erases the MAYBE answers case 2 TRUE.
                "label": "3. no income declared at all (referable)",
                "fixtures": {
                    "declared_income_known": False,
                    "declared_income_is_known": False,
                    "has_declared_income": False,
                },
                "goal": True,
                "verdict": "Holds",
                "undefined_after": [["c.declared_income", "declared_income"]],
            },
            {
                "label": "4. stale work history",
                "fixtures": {
                    "declared_income_known": True,
                    "declared_income_is_known": True,
                    "has_declared_income": True,
                    "declared_income": 500,
                    "date_last_worked_known": True,
                    "date_last_worked_is_known": True,
                    "has_date_last_worked": True,
                    "date_last_worked": D("2019-03-04"),
                    "the_qualifying_date": D("2024-01-01"),
                },
                "goal": True,
                "verdict": "Holds",
            },
            {
                # ABSENT DATE. Never worked is not a stale work history. If the
                # absent path arrived as '' this would raise TypeError against
                # a DADateTime -- loud, but still wrong.
                "label": "5. never worked (absence is not staleness)",
                "fixtures": {
                    "declared_income_known": True,
                    "declared_income_is_known": True,
                    "has_declared_income": True,
                    "declared_income": 500,
                    "date_last_worked_known": False,
                    "date_last_worked_is_known": False,
                    "has_date_last_worked": False,
                    "declaration_confirmed": True,
                },
                "goal": False,
                "verdict": "Fails",
                "undefined_after": [["c.date_last_worked", "date_last_worked"]],
            },
            {
                # `WHEN JUST FALSE`: the payload-VALUE match.
                "label": "6. declaration positively disclaimed",
                "fixtures": {
                    "declared_income_known": True,
                    "declared_income_is_known": True,
                    "has_declared_income": True,
                    "declared_income": 500,
                    "date_last_worked_known": True,
                    "date_last_worked_is_known": True,
                    "has_date_last_worked": True,
                    "date_last_worked": D("2024-06-01"),
                    "the_qualifying_date": D("2024-01-01"),
                    "declaration_confirmed": False,
                },
                "goal": True,
                "verdict": "Holds",
            },
            {
                # NOTHING is not JUST FALSE. The pre-repair `is None` lowering
                # answered this TRUE.
                "label": "7. declaration never answered (NOTHING != JUST FALSE)",
                "fixtures": {
                    "declared_income_known": True,
                    "declared_income_is_known": True,
                    "has_declared_income": True,
                    "declared_income": 500,
                    "date_last_worked_known": True,
                    "date_last_worked_is_known": True,
                    "has_date_last_worked": True,
                    "date_last_worked": D("2024-06-01"),
                    "the_qualifying_date": D("2024-01-01"),
                    "declaration_confirmed": None,
                },
                "goal": False,
                "verdict": "Fails",
            },
        ],
    },

    "statutory-age": {
        # D. Date literals and calendar-exact arithmetic. Cases 1 and 5 are
        # where `date_difference(...).years >= 18` answers FALSE and L4
        # answers TRUE (it reports 17.99900 on the applicant's own eighteenth
        # birthday). Case 3 is where `born.plus(years=18)` answers TRUE and L4
        # answers FALSE, because dateutil CLAMPS 2004-02-29 + 18y to
        # 2022-02-28 while L4's `Date` ROLLS FORWARD to 2022-03-01.
        #
        # Measured over every birth date 1970-01-01..2006-12-31, each tested on
        # the L4 majority date and the day before (27,028 comparisons):
        # date_difference disagrees on 6,629; .plus(years=18) on 9, all
        # leap-day births; born <= assessed.minus(years=18) on none.
        "goal_candidates": ["the_applicant_may_hold_a_licence", "interview_goal"],
        "verdict_candidates": ["verdict", "the_applicant_may_hold_a_licence_verdict"],
        "cases": [
            {"label": "1. ON the eighteenth birthday (date_difference says 17.99900)",
             "fixtures": {"date_of_birth": D("2001-03-01"),
                          "the_assessment_date": D("2019-03-01")},
             "goal": True, "verdict": "Holds"},
            {"label": "2. the day before (control)",
             "fixtures": {"date_of_birth": D("2001-03-01"),
                          "the_assessment_date": D("2019-02-28")},
             "goal": False, "verdict": "Fails"},
            {"label": "3. LEAP DAY: born 29 Feb, assessed 28 Feb (.plus says TRUE)",
             "fixtures": {"date_of_birth": D("2004-02-29"),
                          "the_assessment_date": D("2022-02-28")},
             "goal": False, "verdict": "Fails"},
            {"label": "4. LEAP DAY, one day later",
             "fixtures": {"date_of_birth": D("2004-02-29"),
                          "the_assessment_date": D("2022-03-01")},
             "goal": True, "verdict": "Holds"},
            {"label": "5. month-end boundary (date_difference says 17.99900)",
             "fixtures": {"date_of_birth": D("2001-01-31"),
                          "the_assessment_date": D("2019-01-31")},
             "goal": True, "verdict": "Holds"},
            {"label": "6. of full age, but before the scheme commenced (the literal)",
             "fixtures": {"date_of_birth": D("1990-01-01"),
                          "the_assessment_date": D("2014-01-01")},
             "goal": False, "verdict": "Fails"},
        ],
    },

    "review-checklist": {
        # E. The review block as a compliance checklist. `skip undefined:
        # False` FORCE-ASKS every undefined row (parse.py:5876-5904) and the
        # default silently drops them into a log line; the recipe that renders
        # a passive row for a never-asked variable is a `note:` carrying
        # showifdef(). The third case is the one this exists for: three of the
        # four inputs are short-circuited away and must still appear.
        "goal_candidates": ["the_filing_obligation_is_discharged", "interview_goal"],
        "verdict_candidates": ["verdict", "the_filing_obligation_is_discharged_verdict"],
        "review": {
            "labels": ["the return was filed", "the return was on time",
                       "the fee was paid", "a waiver was granted"],
            "markers": ["not asked", "unanswered", "no answer", "not reached"],
        },
        "cases": [
            {"label": "everything in order",
             "fixtures": {"the_return_was_filed": True, "the_return_was_on_time": True,
                          "the_fee_was_paid": True},
             "goal": True, "verdict": "Holds",
             "review_unanswered": 1},
            {"label": "fee unpaid but waived",
             "fixtures": {"the_return_was_filed": True, "the_return_was_on_time": True,
                          "the_fee_was_paid": False, "a_waiver_was_granted": True},
             "goal": True, "verdict": "Holds",
             "review_unanswered": 0},
            {"label": "nothing filed (three inputs never asked)",
             "fixtures": {"the_return_was_filed": False},
             "goal": False, "verdict": "Fails",
             "review_unanswered": 3},
        ],
    },

    "notice-letter": {
        # F. Document assembly. The hazard is not an exception -- a raising
        # body propagates ZeroDivisionError and an unaskable reference
        # propagates DAErrorMissingVariable, on both attachment paths (probed).
        # The hazard is a SUCCESSFUL EMPTY RENDER: the interview completes, the
        # variable is a healthy DAFileCollection, and the letter is blank.
        # Nothing raises; nothing is logged. `post_conditions` is the only
        # place that can catch it, and `variable name:` is what makes a
        # post-condition possible at all.
        #
        # Three of the six inputs decide nothing and exist only for the letter:
        # the attachment EXTENDS the interview's question set, which is why
        # they carry fixtures here.
        "goal_candidates": ["the_notice_to_quit_is_valid", "interview_goal"],
        "verdict_candidates": ["verdict", "the_notice_to_quit_is_valid_verdict"],
        "cases": [
            {
                "label": "valid notice (three months)",
                "fixtures": {
                    "the_landlord_name": "Marbury Estates Ltd",
                    "the_tenant_name": "A. Tenant",
                    "the_property_address": "14 Chancery Lane, Flat B",
                    "is_a_residential_tenancy": True,
                    "written_notice_was_given": True,
                    "months_of_notice_given": 3,
                },
                "goal": True,
                "verdict": "Holds",
                "post_conditions": [{
                    "expr": "notice_letter.html.content",
                    "nonempty": True,
                    "contains": ["A. Tenant", "14 Chancery Lane",
                                 "Marbury Estates Ltd", "the notice is valid"],
                    "omits": ["does not take effect"],
                }],
            },
            {
                "label": "short notice (one month) — the letter is still assembled",
                "fixtures": {
                    "the_landlord_name": "Marbury Estates Ltd",
                    "the_tenant_name": "A. Tenant",
                    "the_property_address": "14 Chancery Lane, Flat B",
                    "is_a_residential_tenancy": True,
                    "written_notice_was_given": True,
                    "months_of_notice_given": 1,
                },
                "goal": False,
                "verdict": "Fails",
                "post_conditions": [{
                    "expr": "notice_letter.html.content",
                    "nonempty": True,
                    "contains": ["A. Tenant", "does not take effect"],
                    "omits": ["the notice is valid"],
                }],
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


def name_candidates(varname):
    """Every spelling a fixture key may plausibly use for an asked variable,
    longest first: the full dotted/indexed name, then with each leading
    component dropped in turn.

    The longest-first order is what makes the per-element pruning claim
    testable. An asked `h.tenants[0].signed_the_agreement` tries
    `h.tenants[0].signed_the_agreement`, then `tenants[0].signed_the_agreement`,
    then `signed_the_agreement` -- so an INDEXED fixture table can supply
    element 1's answer without accidentally supplying element 0's, which a
    last-component-only lookup could not distinguish.
    """
    parts = varname.split(".")
    return [".".join(parts[i:]) for i in range(len(parts))]


def lookup(fixtures_fuzzed, varname):
    """Resolve an asked variable name against the fixture dict."""
    for candidate in name_candidates(varname):
        key = fuzz(candidate)
        if key in fixtures_fuzzed:
            return key, fixtures_fuzzed[key]
    return None, None


def field_variables(status, user_dict=None):
    """The variable names the pending question's fields would define.

    A question that asks a LIST ELEMENT's attribute is written over
    docassemble's iterator -- `h.tenants[i].age` -- and that is the spelling
    `field.saveas` carries, for every element: the concrete index lives in the
    user_dict, as `i`, at the moment the question is asked. So the raw saveas
    cannot distinguish element 0 from element 1, and a per-element claim
    ("the minor was never asked whether they signed") cannot be tested from it.

    docassemble resolves exactly this itself, with
    `substitute_vars_from_user_dict` (parse.py:9921-9927 at 1b6678384), which is
    what it uses to name an attachment variable inside a generic block
    (parse.py:7064). Reusing that function -- rather than re-deriving the
    substitution here -- keeps the harness reporting the variable docassemble
    would report.
    """
    names = []
    try:
        fields = status.get_field_list()
    except Exception:
        fields = getattr(status.question, "fields", []) or []
    is_generic = bool(getattr(getattr(status, "question", None), "is_generic", False))
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
        name = decoded if decoded is not None else str(saveas)
        if user_dict is not None and substitute_vars_from_user_dict is not None:
            try:
                name = substitute_vars_from_user_dict(name, user_dict, is_generic=is_generic)
            except Exception:
                pass
        names.append(name)
    return names


def write_answer(user_dict, varname, value):
    """Define a (possibly dotted) interview variable, as the web layer would
    on form submission. exec in the user_dict namespace handles both plain
    names and DAObject attribute paths.

    A `D(...)` fixture is written as the DADateTime the web layer would store
    (interview/views.py:1372), not as the string `repr` would produce -- see
    the class docstring.
    """
    if isinstance(value, D):
        user_dict["_l4_roundtrip_date"] = value.value()
        try:
            exec(f"{varname} = _l4_roundtrip_date", user_dict)
        finally:
            user_dict.pop("_l4_roundtrip_date", None)
        return
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
    # The name dump is several hundred entries, almost all of them
    # docassemble's own builtins, so it is gated on debug like the seeking
    # history above it: under --quiet a failure prints its transcript and its
    # reason and nothing else, which is what makes a RED run readable.
    if DEBUG and user_dict is not None:
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

class GatherAnswers:
    """Answers a DAList's CONTROL questions for a gather of exactly n elements.

    Which control questions exist is the emitter's choice and the RED phase
    declines to pick, so all three probed shapes are served:

      * `<list>.there_are_any`    -> n > 0
      * `<list>.there_is_another` -> True until n elements exist, then False
      * `<list>.target_number`    -> n   (the `ask_number: True` shape, which
                                          replaces BOTH of the above)

    Dropping either of the first two raises DAErrorMissingVariable in real
    docassemble (ablation-probed), so a gather that asks neither of them and no
    target_number is not a working gather -- and this class answering nothing
    is exactly how that surfaces.
    """

    def __init__(self, n):
        self.n = n
        self.another_said_yes = 0

    def answer(self, varname):
        """(handled, value) for a gather control variable."""
        tail = varname.split(".")[-1]
        if tail in ("there_are_any", "there_are_any_"):
            return True, self.n > 0
        if tail in ("there_is_another", "there_is_another_"):
            # element 0 exists once there_are_any is True; each further YES
            # adds one more.
            more = (1 + self.another_said_yes) < self.n
            if more:
                self.another_said_yes += 1
            return True, more
        if tail in ("target_number", "target_number_"):
            return True, self.n
        return False, None


def drive_case(interview, current_info, case, user_dict=None, fixtures=None,
               gather_cfg=None, gather_n=None, transcript=None):
    """Drive to a terminal screen. `user_dict` continues an existing session
    (that is what a review-block Edit does); omit it for a fresh one."""
    if fixtures is None:
        fixtures = case["fixtures"]
    fixtures_fuzzed = {fuzz(k): v for k, v in fixtures.items()}
    used = set()
    if user_dict is None:
        user_dict = parse.get_initial_dict()
    functions.this_thread.current_info = current_info
    if transcript is None:
        transcript = []
    gather = GatherAnswers(gather_n) if (gather_cfg and gather_n is not None) else None
    status = None
    for step in range(len(fixtures_fuzzed) + MAX_EXTRA_STEPS + 4 * (gather_n or 0)):
        status = parse.InterviewStatus(current_info=current_info)
        # user_dict_context is what docassemble_webapp enters around assemble;
        # without it get_current_user_dict() is None and functions.py:4234
        # makes defined()/value()/showifdef() return False for EVERY variable,
        # including defined ones -- which would silently break any review-block
        # assertion (measured).
        with user_dict_context(user_dict):
            interview.assemble(user_dict, status)
        qtype = getattr(status.question, "question_type", None)
        asked = field_variables(status, user_dict)
        transcript.append((step, qtype, asked))
        if not asked:
            # deadend / event verdict screen / any fieldless terminal
            return user_dict, status, transcript
        answered_any = False
        for varname in asked:
            if gather is not None:
                handled, value = gather.answer(varname)
                if handled:
                    write_answer(user_dict, varname, value)
                    answered_any = True
                    continue
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


def is_undefined(user_dict, spellings):
    """(True, None) when EVERY spelling fails to evaluate; otherwise the first
    one that does, with its value.

    "Undefined" is the whole point of `show if: {code: …}` and of the paired
    is-known question: a hidden field is not '' and not 0, it is absent. A
    lowering that leaves 0.0 behind passes an answer-only comparison and fails
    here.
    """
    for spelling in spellings:
        try:
            with user_dict_context(user_dict):
                value = eval(spelling, user_dict)
        except Exception:
            continue
        return False, (spelling, value)
    return True, None


def fire_event(interview, current_info, user_dict, event_name):
    """Assemble the block that `event: <event_name>` guards.

    An event block is reachable ONLY by firing it through
    current_info['action']; without it the interview simply ends (probed). The
    key must be absent the rest of the time -- process_action tests
    `'action' not in current_info`, so a literal `action: None` force-asks a
    None variable and crashes assemble (spec §8.10) -- and docassemble POPS the
    key itself during process_action, so this hands it a copy.
    """
    ci = copy.deepcopy(current_info)
    ci["action"] = event_name
    ci["arguments"] = {}
    functions.this_thread.current_info = ci
    status = parse.InterviewStatus(current_info=ci)
    with user_dict_context(user_dict):
        interview.assemble(user_dict, status)
    functions.this_thread.current_info = current_info
    return status


def review_event_name(yaml_text):
    """The `event:` of the block that carries `review:`, or None."""
    for block in re.split(r"^-{3,}\s*$", yaml_text, flags=re.M):
        if re.search(r"^\s*review:", block, flags=re.M):
            match = re.search(r"^\s*event:\s*(\S+)", block, flags=re.M)
            if match:
                return match.group(1)
    return None


def review_rows(status):
    """The rendered text of every row the review screen shows.

    A review row's rendered note lands in status.extras['note'] and its label
    in status.labels, keyed by row number; status.extras['ok'] says which rows
    were shown. A `note:` row has no saveas to evaluate, so it renders whether
    or not its variable exists -- which is what makes a never-asked row
    possible at all.
    """
    extras = getattr(status, "extras", {}) or {}
    okmap = extras.get("ok", {}) or {}
    notes = extras.get("note", {}) or {}
    labels = getattr(status, "labels", {}) or {}
    rows = []
    for number in sorted(set(list(okmap) + list(notes) + list(labels))):
        if number in okmap and not okmap[number]:
            continue
        text = notes.get(number) or labels.get(number) or ""
        rows.append(str(text))
    if not rows:
        rows = [rendered_screen(status)]
    return rows


def check_case(interview, current_info, example, case, yaml_text=""):
    user_dict, status, transcript = drive_case(
        interview, current_info, case,
        gather_cfg=example.get("gather"), gather_n=case.get("gather_n"))
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

    asked_names = [v for _, _, asked in transcript for v in asked]

    # M4/A, M4/B: a variable that must never have been ASKED. Omitting a
    # fixture already fails the run when the variable is asked; this covers the
    # case where a sibling element's fixture would satisfy the lookup.
    for needle in case.get("never_asked", []):
        hits = [v for v in asked_names if fuzz(needle) in fuzz(v)]
        if hits:
            problems.append(
                f"the interview asked {hits!r}, which nothing on this path can "
                f"need -- the short-circuit that makes this backend worth "
                f"having did not survive lowering")

    # M4/B, M4/C: a hidden or absent field must be UNDEFINED, not 0 and not ''.
    for spellings in case.get("undefined_after", []):
        undefined, found = is_undefined(user_dict, spellings)
        if undefined:
            checked.append(f"{spellings[0]} absent")
        else:
            spelling, value = found
            problems.append(
                f"{spelling} is defined as {value!r} at the end of the "
                f"interview, but on this path the law never asked for it; "
                f"absence must be absence, not a default")

    # M4/F: the attachment hazard. A SUCCESSFUL EMPTY RENDER raises nothing and
    # logs nothing, so the only defence is a post-condition on the content.
    for post in case.get("post_conditions", []):
        expr = post["expr"]
        try:
            with user_dict_context(user_dict):
                value = eval(expr, user_dict)
        except Exception as exc:
            problems.append(
                f"post-condition {expr!r} could not be evaluated "
                f"({type(exc).__name__}: {exc}) -- if this is a document, it "
                f"most likely has no `variable name:` and was filed under "
                f"_internal['docvar'][n] where nothing can assert about it")
            continue
        text = "" if value is None else str(value)
        if post.get("nonempty") and not text.strip():
            problems.append(
                f"post-condition {expr!r} evaluated to empty. This is the "
                f"document-assembly failure that is genuinely silent: the "
                f"interview completed, the variable is a healthy object, and "
                f"the letter is blank")
        for needle in post.get("contains", []):
            if needle in text:
                checked.append(f"{expr} carries {needle!r}")
            else:
                problems.append(
                    f"post-condition {expr!r} does not carry {needle!r}; got "
                    f"{text[:400]!r}")
        for needle in post.get("omits", []):
            if needle in text:
                problems.append(
                    f"post-condition {expr!r} carries {needle!r}, which "
                    f"belongs to the other branch of the letter")

    # M4/E: the compliance checklist. Reached by firing the review block's own
    # event; a row per L4 input, and a never-asked marker on exactly the rows
    # the short-circuit pruned away.
    review_cfg = example.get("review")
    if review_cfg is not None:
        event = review_event_name(yaml_text)
        if event is None:
            problems.append(
                "no `review:` block carrying an `event:` was emitted, so there "
                "is no compliance-checklist view to reach")
        else:
            rstatus = fire_event(interview, current_info, user_dict, event)
            rows = review_rows(rstatus)
            blob = "\n".join(rows)
            missing = [lbl for lbl in review_cfg["labels"] if lbl not in blob]
            if missing:
                problems.append(
                    f"the review screen has no row for {missing!r}; a checklist "
                    f"that lists only the questions that were asked says "
                    f"nothing about the ones the law never reached")
            marked = sum(1 for row in rows
                         if any(m in row.lower() for m in review_cfg["markers"]))
            want = case.get("review_unanswered")
            if want is not None and marked != want:
                problems.append(
                    f"{marked} review rows are marked as never asked, expected "
                    f"{want}; markers accepted are {review_cfg['markers']!r} "
                    f"and the rows were {rows!r}")
            elif want is not None:
                checked.append(f"review: {len(rows)} rows, {marked} never asked")

    # M4/E, inherited from M2 (spec §8.4): change an earlier answer the way a
    # review-block Edit does -- undefine and re-ask -- and the verdict AND the
    # citations must be what they would have been had the new answer been given
    # first.
    change = case.get("change_answer")
    if change is not None:
        after = case["after"]
        for name in change:
            resolved = None
            for asked_name in asked_names:
                if fuzz(name) in fuzz(asked_name):
                    resolved = asked_name
                    break
            if resolved is None:
                problems.append(
                    f"cannot change {name!r}: the interview never asked it")
                continue
            with user_dict_context(user_dict):
                exec(f"undefine({resolved!r})", user_dict)
        user_dict, status2, _ = drive_case(
            interview, current_info, case, user_dict=user_dict,
            fixtures=after["fixtures"], gather_cfg=example.get("gather"),
            gather_n=case.get("gather_n"), transcript=transcript)
        _, goal2 = find_variable(user_dict, example["goal_candidates"])
        verdict2_name, verdict2 = find_variable(user_dict, example["verdict_candidates"])
        cites2 = explanations_of(user_dict)
        if "goal" in after and not values_equal(goal2, after["goal"]):
            problems.append(
                f"after the answer was changed the goal is {goal2!r}, expected "
                f"{after['goal']!r} -- the verdict went STALE, not merely the "
                f"citations")
        # Guarded on the verdict variable EXISTING, exactly as the forward
        # check above is: only a seam-lowered export emits one (R4), and
        # `citations.l4`'s goal is a plain boolean, so `DABoolDriver` emits no
        # verdict variable at all. Without the guard this asserted a variable
        # the design deliberately does not produce, and reported it as the
        # staleness defect.
        if (after.get("verdict") is not None and verdict2_name is not None
                and verdict2 != after["verdict"]):
            problems.append(
                f"after the answer was changed the verdict is {verdict2!r}, "
                f"expected {after['verdict']!r}")
        if "explanations" in after and cites2 != after["explanations"]:
            problems.append(
                f"after the answer was changed the verdict screen cites "
                f"{cites2!r}, expected exactly {after['explanations']!r} -- a "
                f"citation to a rule that no longer fires is a citation to law "
                f"that does not apply")
        if not [p for p in problems if "after the answer" in p]:
            checked.append(f"after edit: goal={goal2!r} cites={len(cites2)}")
        rendered2 = rendered_screen(status2)
        for needle in after.get("screen_omits", []):
            if needle in rendered2:
                problems.append(
                    f"after the answer was changed the screen still cites "
                    f"{needle!r}")

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
                case["label"]: check_case(interview, current_info, example, case,
                                          yaml_text=content)
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
