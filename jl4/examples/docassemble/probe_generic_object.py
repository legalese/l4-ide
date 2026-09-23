"""R2 probe: does a `generic object:` fallback layer change which question the
engine asks, when a specific-instance question for the same attribute exists?

This is the experiment DOCASSEMBLE-EXPORT-SPEC.md §8.2 cites when it defers the
generic-object layer out of M2. R2 proposed emitting each stored record field as
a `generic object` question on `x.<field>`, covering any instance of the class;
M1 narrowed that to a specific-instance question on the concrete path
`i.<field>`. The question this probe answers is whether adding the generic layer
back would change anything today.

It drives the SAME emitted interview twice -- once as emitted, once with a
generic-object question for an attribute the interview already asks -- and
prints the id of every question actually asked. docassemble's `askfor` expands a
sought name into abstract variants and sorts candidates non-generic-first
(the four-key sort at parse.py:9092 in 1.10.7), so the expectation is that the
specific question wins and the generic layer is inert.

Usage (inside the docassemble venv -- recipe in README.md), from the repo root:

    python jl4/examples/docassemble/probe_generic_object.py /tmp/citations.yml

Reuses roundtrip_check.py's bootstrap (pyzbar stub, ~13-hookimpl HeadlessPlugin,
contextvar scope) by importing it with sys.argv pre-set; see spec §8.10 for why
each of those ingredients is needed.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

if len(sys.argv) != 2:
    raise SystemExit(__doc__)
YAML = sys.argv[1]

sys.argv = ["probe", YAML, "citations", "--quiet"]
sys.path.insert(0, HERE)

import roundtrip_check as rc  # noqa: E402

# The layer R2 proposed: one question defined for ANY DAObject instance, on the
# same attribute the emitted specific-instance question already sets.
GENERIC_LAYER = """
---
id: q_generic_amount_raised_in_12_months
generic object: DAObject
question: |
  GENERIC LAYER: amount raised in 12 months
fields:
  - "generic amount raised in 12 months": x.amount_raised_in_12_months
    datatype: number
"""

FIXTURES = {
    "amount_raised_in_12_months": 1000000,
    "sold_through_one_intermediary": True,
    "intermediary_is_registered": True,
}

CURRENT_INFO = {
    "user": {
        "is_anonymous": False, "is_authenticated": True, "theid": 1,
        "the_user_id": 1, "roles": ["user"], "firstname": "Probe",
        "lastname": "Harness", "email": "probe@example.com", "country": "US",
        "subdivisionfirst": None, "subdivisionsecond": None,
        "subdivisionthird": None, "organization": None,
        "timezone": "America/New_York", "language": "en",
        "session_uid": "probe-uid", "device_id": "probe-device",
    },
    "session": "probe", "secret": None, "yaml_filename": "interview.yml",
    "url": None, "url_root": None, "encrypted": False, "interface": "cli",
    "arguments": {},
}


def drive(content, label):
    """Assemble to a terminal screen, printing the id of each question asked."""
    source = rc.InterviewSourceString(
        content=content, path="interview.yml", package="docassemble.l4roundtrip")
    interview = rc.parse.Interview(source=source)
    fixtures = {rc.fuzz(k): v for k, v in FIXTURES.items()}
    user_dict = rc.parse.get_initial_dict()
    rc.functions.this_thread.current_info = CURRENT_INFO
    asked = []
    for _ in range(12):
        status = rc.parse.InterviewStatus(current_info=CURRENT_INFO)
        interview.assemble(user_dict, status)
        names = rc.field_variables(status)
        if not names:
            break
        first_line = str(status.question.content.original_text).strip().splitlines()[0]
        asked.append((getattr(status.question, "id", None), first_line, names))
        for varname in names:
            key, answer = rc.lookup(fixtures, varname)
            if key is None:
                raise SystemExit(f"no fixture for {varname!r}")
            rc.write_answer(user_dict, varname, answer)
    print(f"--- {label} ---")
    for qid, text, names in asked:
        print(f"   id={qid!r}  question={text!r}  sets={names}")
    print(f"   goal offering_exempt = {user_dict.get('offering_exempt')!r}")
    return asked


def main():
    with open(YAML, encoding="utf-8") as handle:
        base = handle.read()
    with rc.global_context(rc.empty_globals()):
        emitted = drive(base, "specific-instance questions only (what M1/M2 emit)")
        layered = drive(base + GENERIC_LAYER,
                        "specific-instance PLUS a generic-object layer")
    same = [q[0] for q in emitted] == [q[0] for q in layered]
    print()
    print("same questions asked, in the same order:", same)
    if not same:
        raise SystemExit(
            "the generic-object layer CHANGED which questions fire; §8.2's "
            "deferral rests on it being inert, so re-open that ruling")


if __name__ == "__main__":
    main()
