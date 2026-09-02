#!/usr/bin/env python3
"""eId agreement harness for the Blawx exporter (BLAWX-EXPORT-SPEC R4, §11 W3).

R4 anchors every emitted rule in the workspace named after its CLEAN section
eId, and Blawx derives that name itself, from the `rule_text` we synthesise:
`RuleDoc.save()`'s `pre_save` signal runs clean-law's `generate_akn` over the
text and `parse_an.py` names each canvas `<eId>_section`.  So a workspace whose
name does not match what clean-law's parse yields is simply ORPHANED - it
imports, it stores, and the canvas belongs to no section of the Act.  Nothing in
the golden bytes shows this: both halves are ours and both are self-consistent.

This harness closes that gap.  For each `.blawx` given (default: every golden
under jl4/examples/blawx/expected), it

  1. reads `rule_text` and every `workspace_name` out of the fixture YAML;
  2. runs clean-law's own `generate_akn` over the `rule_text`;
  3. compares the AKN's `<section eId=...>` set against the numbered workspace
     names, and reports any workspace the parse does not produce.

Only flat `sec_N` sections are compared - sub-provision canvases are out of
Mode-A scope (R4 "flat numbered sections for v1", §11 W3(b)).

Optional-when-present, NEVER a build dependency: exits 0 with a notice when
clean-law or pyparsing is absent.  Exits 1 on any disagreement.  clean-law is
what Blawx pins (`blawx/requirements.txt`: `clean-law >=0.0.4`); install it and
`pyparsing` into any interpreter, or point CLEAN_LAW_SRC at an unpacked sdist:

    python3 -m venv /tmp/cl && /tmp/cl/bin/pip install pyparsing pyyaml
    pip download --no-deps -d . clean-law==0.0.4 && tar xzf clean-law-0.0.4.tar.gz
    CLEAN_LAW_SRC=$PWD/clean-law-0.0.4 /tmp/cl/bin/python etc/blawx-eid-harness.py

Measured 2026-09-02 with clean-law 0.0.4 + pyparsing 3.3.2: 12 of 12 goldens
agree.  Before §11 W3 the two seeds whose authors wrote the section number in
their own prose did NOT: `rps.blawx` produced `sec_1_ 4` and `sec_3_ 3` against
workspaces `sec_1_section`..`sec_3_section`, and `beard.blawx` produced a single
`sec_1_ 1` against three workspaces, because `"1. 4. The winner ..."` matches
clean-law's `section_index` INSERT INDEX (`number ('.' number)* '.'`).  Every
canvas in both was orphaned.  That is the defect this file exists to catch.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(REPO, "jl4", "examples", "blawx", "expected")


def notice(msg):
    print("blawx-eid-harness: " + msg + "; skipping (never a build dependency)")
    sys.exit(0)


src = os.environ.get("CLEAN_LAW_SRC")
if src:
    sys.path.insert(0, src)
try:
    import yaml  # noqa: F401
except ImportError:
    notice("PyYAML not importable")
try:
    from clean.clean import generate_akn
except ImportError as e:
    notice("clean-law not importable (%s); see this file's docstring" % e)


def sections_of(path):
    """(rule_text, flat numbered workspace names) out of one .blawx fixture."""
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    rule_text, workspaces = None, []
    for entry in doc:
        if entry.get("model") == "blawx.ruledoc":
            rule_text = entry["fields"]["rule_text"]
        elif entry.get("model") == "blawx.workspace":
            workspaces.append(entry["fields"]["workspace_name"])
    flat = sorted(w for w in workspaces if re.fullmatch(r"sec_\d+_section", w))
    other = sorted(w for w in workspaces if w != "root_section" and w not in flat)
    return rule_text, flat, other


def main(argv):
    paths = argv[1:] or sorted(
        os.path.join(DEFAULT_DIR, f)
        for f in os.listdir(DEFAULT_DIR)
        if f.endswith(".blawx")
    )
    failed = 0
    for path in paths:
        rule_text, flat, other = sections_of(path)
        if rule_text is None:
            print("BAD  %s: no blawx.ruledoc entry" % path)
            failed += 1
            continue
        # generate_akn wants the trailing newline addExplicitIndents assumes.
        akn = generate_akn(rule_text + "\n")
        eids = sorted(
            e + "_section" for e in re.findall(r'<section eId="([^"]+)"', akn)
        )
        name = os.path.basename(path)
        if eids == flat:
            extra = " (+%d non-flat workspace(s) not compared)" % len(other) if other else ""
            print("ok   %s: %s%s" % (name, ", ".join(flat) or "no numbered sections", extra))
        else:
            print("BAD  %s: clean-law yields %s, workspaces are %s" % (name, eids, flat))
            failed += 1
    print(
        "blawx-eid-harness: %d checked, %d failed; clean-law from %s"
        % (len(paths), failed, os.path.dirname(sys.modules["clean.clean"].__file__))
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
