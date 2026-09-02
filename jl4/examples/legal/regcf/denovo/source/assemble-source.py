#!/usr/bin/env python3
"""Rebuild part227.txt — the provenance-headed source artifact P3 encodes from —
from the captured eCFR XML sitting beside this script.

    python3 assemble-source.py

Committed so the assembled artifact is REPRODUCIBLE rather than merely asserted:
source-bundle.json pins part227.txt by sha256, and re-running this over the
captured XML must reproduce that digest byte for byte. Nothing here reaches the
network; the captures are the inputs.
"""
import html
import os
import re

D = os.path.dirname(os.path.abspath(__file__))


def inline(s):
    s = re.sub(r"<I>(.*?)</I>", lambda m: "_" + m.group(1) + "_", s, flags=re.S)
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"[ \t\n]+", " ", html.unescape(s)).strip()


def render_section(path):
    return render_section_body(open(path, encoding="utf-8").read())


def render_section_body(x):
    out = []
    head = re.search(r"<HEAD>(.*?)</HEAD>", x, re.S)
    out.append("-" * 78)
    out.append(inline(head.group(1)))
    out.append("-" * 78)
    out.append("")
    cita = None
    for pm in re.finditer(r"<(P|CITA|EXTRACT)\b[^>]*>(.*?)</\1>", x, re.S):
        kind, inner = pm.group(1), pm.group(2)
        if kind == "P":
            out.append(inline(inner))
            out.append("")
        elif kind == "EXTRACT":
            for q in re.finditer(r"<P\b[^>]*>(.*?)</P>", inner, re.S):
                out.append("    " + inline(q.group(1)))
                out.append("")
        else:
            cita = inline(inner)
    if cita:
        out.append(cita)
        out.append("")
    return "\n".join(out)


def render_part(path):
    """Render the whole-part XML: part head, authority, source, then each subpart
    banner and each section with its citation note."""
    x = open(path, encoding="utf-8").read()
    out = []
    out.append(inline(re.search(r"<DIV5[^>]*>\s*<HEAD>(.*?)</HEAD>", x, re.S).group(1)))
    out.append("")
    for tag, label in (("AUTH", "Authority"), ("SOURCE", "Source")):
        mm = re.search(r"<%s>(.*?)</%s>" % (tag, tag), x, re.S)
        if mm:
            out.append("%s: %s" % (label, inline(re.sub(r"<HED>.*?</HED>", "", mm.group(1), flags=re.S))))
            out.append("")
    block = re.compile(
        r'<DIV6 N="([^"]*)" TYPE="SUBPART"[^>]*>\s*<HEAD>(.*?)</HEAD>'
        r'|<DIV8 N="([^"]*)" TYPE="SECTION"[^>]*>(.*?)</DIV8>',
        re.S,
    )
    for m in block.finditer(x):
        if m.group(1) is not None:
            out += ["=" * 78, inline(m.group(2)), "=" * 78, ""]
        else:
            out.append(render_section_body(m.group(4)))
    return "\n".join(out)


HEADER = """\
================================================================================
SOURCE TEXT — 17 CFR Part 227, Regulation Crowdfunding
Securities and Exchange Commission (17 CFR ch. II, subch. A)
================================================================================

PROVENANCE
----------
Source URL   : https://www.ecfr.gov/api/versioner/v1/full/2026-08-03/title-17.xml?chapter=II&part=227
               (eCFR versioner API — the machine-readable rendering of
               https://www.ecfr.gov/current/title-17/chapter-II/part-227)
Fetched      : 2026-08-05
Fetch route  : DIRECT, over the eCFR versioner API. The eCFR *website* is not
               reachable from this environment — https://www.ecfr.gov/current/...
               answers HTTP 302 to https://unblock.federalregister.gov/ for both
               curl and WebFetch — but api.ecfr.gov's versioner endpoints answer
               200 without challenge, so the text below is the publisher's own
               bytes and no archive fallback was needed.
Currency     : The eCFR versioner's own currency record for title 17, verbatim
               (https://www.ecfr.gov/api/versioner/v1/titles.json, fetched
               2026-08-05):
                 {"number":17,"name":"Commodity and Securities Exchanges",
                  "latest_amended_on":"2026-07-26","latest_issue_date":"2026-07-27",
                  "up_to_date_as_of":"2026-08-03","reserved":false}
               For part 227 specifically the versioner reports
               latest_amendment_date 2023-03-01, latest_issue_date 2023-03-30
               over 85 section-version rows
               (https://www.ecfr.gov/api/versioner/v1/versions/title-17.json?part=227).
               So: the title is current to 3 Aug 2026; the part itself has not
               been amended since 1 Mar 2023. What happened on that date was an
               expiry, not an enactment — established by diffing the versioner's
               own renderings at 2023-02-28 and 2023-03-02, not inferred: three
               COVID-era provisions added by 86 FR 3590/3591/3592 with a built-in
               sunset lapsed together. § 227.201(bb) and § 227.301(e) were
               removed outright and § 227.100(b)(7) reverted to "[Reserved]",
               which is why a reserved paragraph survives below and why no
               "Effective Date Note:" annotations appear anywhere in the text.
               The window 14 Jan 2021 – 1 Mar 2023 is therefore a real dated arm
               for anyone encoding a rule-version axis over this part.
Corroboration: The GPO annual edition (CFR-2025-title17-vol3-part227.xml,
               revised as of 1 April 2025, https://www.govinfo.gov/content/pkg/
               CFR-2025-title17-vol3/xml/CFR-2025-title17-vol3-part227.xml)
               carries the same 22 sections. Word-level comparison of the
               section bodies (citation notes excluded, punctuation and
               whitespace normalised): 101,803 vs 101,802 characters,
               SequenceMatcher ratio 0.999907, ONE differing block — govinfo
               prints "offeringstatement" for "offering statement" in
               § 227.503(a)(1), a GPO typesetting artifact across a page break.
               No substantive divergence.
Amendments   : The part's own citation apparatus (the bracketed "[80 FR 71537,
               Nov. 16, 2015, as amended at ...]" notes printed under each
               amended section, reproduced verbatim below) names ten Federal
               Register documents. Each was resolved to a govinfo granule and
               then VERIFIED BY CONTENT — issuing agency, SEC release number,
               and a printed page range containing the cited page. That check
               was not ceremonial: govinfo's link service
               (https://www.govinfo.gov/link/fr/<vol>/<page>) resolves a page to
               the granule that BEGINS on it, not the one that contains it, and
               four of the ten cites point at a document's last page. Trusting
               it would have recorded 87 FR 57398 as a Coast Guard safety-zone
               rule instead of SEC Release 33-11098. The verified table is in
               ../source-bundle.json under this document's annotation inventory.
               The amendments' effects are already integrated into the text
               below; the FR granules themselves are not reproduced here,
               their preambles running to 225 FR pages for the 2015 release
               alone.
Rendering    : Plain-text rendering of the eCFR XML. Words are verbatim;
               whitespace is normalised and each <P> is one block paragraph.
               eCFR italics (<I>) are written _like this_, so that the
               "Instruction to paragraph (x)" headings and the defined terms the
               eCFR italicises survive the flattening. Nothing is elided: all
               22 sections of the part appear, in order, each followed by its
               citation note where the eCFR prints one.
Scope        : The subject is 17 CFR Part 227 (see etc/go/subjects/regcf/
               subject.json). Two provisions OUTSIDE the part are reproduced as
               an annex because the part's operative text depends on them for
               meaning: § 230.501 (the accredited-investor definition and the
               annual-income/net-worth calculation that § 227.100(a)(2) and its
               Instruction 1 incorporate) and § 270.3a-9 (the crowdfunding
               vehicle that § 227.100(d) excludes from "investor"). Other
               outward references — § 239.900 (Form C), § 249.2000 (Form Funding
               Portal), § 240.10b-10, § 240.17a-4(f), § 240.17f-2, § 230.152,
               § 230.241 — are named but NOT reproduced: they prescribe forms or
               procedures rather than supplying terms the part's rules turn on.
================================================================================

"""

ANNEX = """
================================================================================
ANNEX — provisions outside 17 CFR Part 227 relied on by its text
Fetched 2026-08-05 from the eCFR versioner API, same route as above:
  https://www.ecfr.gov/api/versioner/v1/full/2026-08-03/title-17.xml?part=230&section=230.501
  https://www.ecfr.gov/api/versioner/v1/full/2026-08-03/title-17.xml?part=270&section=270.3a-9
================================================================================

"""

body = render_part(D + "/part227.raw.xml")
text = (
    HEADER
    + body.rstrip()
    + "\n\n"
    + ANNEX
    + render_section(D + "/ref-230.501.xml").rstrip()
    + "\n\n"
    + render_section(D + "/ref-270.3a-9.xml").rstrip()
    + "\n"
)
open(D + "/part227.txt", "w", encoding="utf-8").write(text)
print("wrote", len(text), "bytes")
