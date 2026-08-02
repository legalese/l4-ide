#!/usr/bin/env python3
"""Build the charities surface map for etc/go/lib/denovo-diff.mjs."""
import json, re, sys, os

CORPUS_DIR = "/Users/mengwong/src/legalese/l4wt/charities-cleanroom/paper/case-studies/charities-jersey-2014"
CLEAN = "/Users/mengwong/src/legalese/l4wt/charities-cleanroom/jl4/examples/legal/charities-cleanroom/charity-test.l4"

def fields(path, decl):
    txt = open(path).read()
    m = re.search(r"^DECLARE %s HAS\n(.*?)(?=\n\S|\n\n\S)" % re.escape(decl), txt, re.S | re.M)
    if not m:
        # fall back: read until a blank line followed by non-indented
        m = re.search(r"^DECLARE %s HAS\n((?:[ \t].*\n|--.*\n|\n)*)" % re.escape(decl), txt, re.M)
    body = m.group(1)
    out = []
    for line in body.splitlines():
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        mm = re.match(r"^`([^`]*)`\s+IS A", s) or re.match(r"^([A-Za-z][A-Za-z0-9_]*)\s+IS A", s)
        if mm:
            out.append(mm.group(1))
    return out

cp = fields(os.path.join(CORPUS_DIR, "part-3-charity-test.l4"), "CharitablePurpose")
cc = fields(os.path.join(CORPUS_DIR, "part-3-charity-test.l4"), "CandidateCharity")
ce = fields(os.path.join(CORPUS_DIR, "part-1-interpretation.l4"), "Entity")
kp = fields(CLEAN, "Purpose")
kc = fields(CLEAN, "Constitution")
kb = fields(CLEAN, "PublicBenefitFinding")
ke = fields(CLEAN, "Entity")

if "--dump" in sys.argv:
    for n, v in [("corpus CharitablePurpose", cp), ("corpus CandidateCharity", cc),
                 ("corpus Entity", ce), ("clean Purpose", kp), ("clean Constitution", kc),
                 ("clean PublicBenefitFinding", kb), ("clean Entity", ke)]:
        print(f"=== {n} ({len(v)}) ===")
        for x in v:
            print("  " + x)
    sys.exit(0)

# ---- purpose rename: corpus name -> cleanroom name -------------------------
def strip_head(s):
    return re.sub(r"^\((?:2\))?\(?[a-p]\)(?:\(i+\))?\s*", "", s)

norm = lambda s: re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()

MANUAL = {
    "(i) the provision of recreational facilities, or the organisation of recreational activities, with the object of improving the conditions of life for the persons for whom the facilities or activities are primarily intended":
        "the provision of recreational facilities, or the organisation of recreational activities, with the object of improving the conditions of life for the persons for whom they are primarily intended",
    "(p) any other purpose that may reasonably be regarded as analogous to any of the purposes listed in sub-paragraphs (a) to (o)":
        "reasonably regarded as analogous to any of the purposes listed in sub-paragraphs (a) to (o)",
    "(2)(c) the sport involves physical skill and exertion":
        "sport that involves physical skill and exertion",
    "(2)(d)(i) the facilities or activities are primarily intended for persons who have need of them by reason of their age, ill-health, disability, financial hardship or other disadvantage":
        "primarily intended for persons who have need of them by reason of their age, ill-health, disability, financial hardship or other disadvantage",
    "(2)(d)(ii) the facilities or activities are available to members of the public at large or to male or female members of the public at large":
        "available to members of the public at large or to male or female members of the public at large",
    "is purely ancillary or incidental to any of the entity's charitable purposes":
        "purely ancillary or incidental to any of the entity's charitable purposes",
    "(5) is the purpose of advancing a political party or promoting a candidate for election to any office, whether in Jersey or elsewhere":
        "for advancing a political party or promoting a candidate for election to any office, whether in Jersey or elsewhere",
}
UNMATCHED_OK = {"(2)(e) relief given by the provision of accommodation or care"}

kp_by_norm = {norm(x): x for x in kp}
prename = {}
unmatched = []
for f in cp:
    if f == "description":
        continue
    if f in MANUAL:
        prename[f] = MANUAL[f]
        continue
    cand = kp_by_norm.get(norm(strip_head(f)))
    if cand:
        prename[f] = cand
    else:
        unmatched.append(f)
missing_rhs = [x for x in kp if x != "description" and x not in set(prename.values())]
bad = [u for u in unmatched if u not in UNMATCHED_OK]
if bad or missing_rhs:
    print("UNMATCHED corpus purpose fields:", json.dumps(bad, indent=2), file=sys.stderr)
    print("UNPAIRED cleanroom purpose fields:", json.dumps(missing_rhs, indent=2), file=sys.stderr)
    sys.exit(3)
print(f"purpose rename: {len(prename)} pairs; corpus-only: {sorted(UNMATCHED_OK & set(unmatched))}",
      file=sys.stderr)

# ---- purpose object builders ----------------------------------------------
CORPUS_ONLY_PURPOSE = "(2)(e) relief given by the provision of accommodation or care"
HEADS = {c: c for c in cp}

def purpose(desc, **kw):
    """Canonical (corpus-vocabulary) purpose object; kw keys are short tags."""
    o = {"description": desc}
    for f in cp:
        if f == "description":
            continue
        o[f] = False
    for k, v in kw.items():
        matches = [f for f in cp if f.startswith(k)]
        assert len(matches) == 1, (k, matches)
        o[matches[0]] = v
    return o

def union_purpose(p):
    """Both vocabularies in one object, kept in sync — for nested list elements,
    which applyRename cannot reach."""
    o = dict(p)
    for a, b in prename.items():
        o[b] = p[a]
    return o

P = {}
P["poverty"] = purpose("relieving poverty in St Helier", **{"(a)": True})
P["education"] = purpose("running a school", **{"(b)": True})
P["sickness"] = purpose("preventing disease", **{"(2)(a)": True})
P["health"] = purpose("advancing health", **{"(d)": True})
P["care-home"] = purpose("providing accommodation and care", **{"(2)(e)": True})
P["relief-in-need"] = purpose("relief of those in need", **{"(n)": True})
P["chess"] = purpose("public participation in competitive chess", **{"(h)": True})
P["swimming"] = purpose("public participation in swimming", **{"(h)": True, "(2)(c)": True})
P["rec-closed"] = purpose("a members-only recreation ground", **{"(i)": True})
P["rec-need"] = purpose("a recreation ground for the disadvantaged", **{"(i)": True, "(2)(d)(i)": True})
P["rec-open"] = purpose("a recreation ground open to all", **{"(i)": True, "(2)(d)(ii)": True})
P["humanism"] = purpose("the advancement of humanism", **{"(2)(f)": True})
P["religion"] = purpose("the advancement of religion", **{"(c)": True})
P["political"] = purpose("campaigning for a political party", **{"(5)": True})
P["political-edu"] = purpose("electing candidates who favour our schools", **{"(b)": True, "(5)": True})
P["political-anc"] = purpose("campaigning, pleaded as merely incidental", **{"(5)": True, "is purely ancillary": True})
P["giftshop"] = purpose("running a gift shop to fund the school", **{"is purely ancillary": True})
P["commercial"] = purpose("selling groceries at a profit", **{})
P["citizenship"] = purpose("advancing citizenship", **{"(f)": True})
P["regeneration"] = purpose("urban regeneration", **{"(2)(b)(i)": True})
P["analogous"] = purpose("an analogous purpose", **{"(p)": True})

# ---- entity slot ------------------------------------------------------------
CLEAN_ORDER = "specified in an Order under Article 5(3) disapplying paragraph (2)"
CORPUS_ORDER = "an Order under Article 5(3) disapplies paragraph (2) in relation to this entity"
CORPUS_PB = "in giving effect to those purposes, it provides (or, in the case of an applicant, provides or intends to provide) public benefit in Jersey or elsewhere to a reasonable degree"
CORPUS_IDENT = "the entity benefits only one particular natural person or a group of identified natural persons"
CORPUS_CHAPEAU = "its constitution expressly permits its activities to be directed or otherwise controlled by, or any of its governors to be, a person of the following description, acting in that capacity"

assert CORPUS_ORDER in cc and CORPUS_PB in cc and CORPUS_IDENT in cc and CORPUS_CHAPEAU in cc, cc
assert CLEAN_ORDER in ke, ke

nested_entity = {"name": "the entity under test"}
for f in ce:
    if f == "name":
        continue
    nested_entity[f] = False
nested_entity["(d) a foundation"] = True
nested_entity["is a body corporate"] = True

def constitution(desc, **kw):
    o = {"description": desc}
    for f in kc:
        if f == "description":
            continue
        o[f] = False
    for k, v in kw.items():
        matches = [f for f in kc if f.startswith(k)]
        assert len(matches) == 1, (k, matches)
        o[matches[0]] = v
    return o

def pbf(desc, **kw):
    o = {"description": desc}
    for f in kb:
        if f == "description":
            continue
        o[f] = False
    for k, v in kw.items():
        matches = [f for f in kb if f.startswith(k)]
        assert len(matches) == 1, (k, matches)
        o[matches[0]] = v
    return o

def charity(name, purposes, *, pb=True, identified=False,
            chapeau=False, minister=False, states=False, foreign=False,
            gov_mode=False, capacity=True, order=False, applicant=False,
            intends=False, restricted=False, section_only=False,
            regard_a=True, regard_b=True, presumed=False):
    """One charity fact-pattern, carrying BOTH vocabularies in sync."""
    o = {
        # --- corpus (left) vocabulary, top level -----------------------------
        "entity": nested_entity,
        "purposes": [union_purpose(p) for p in purposes],
        CORPUS_PB: pb,
        CORPUS_IDENT: identified,
        CORPUS_CHAPEAU: chapeau,
        "(2)(a) a Minister": minister,
        "(2)(b) a member of the States Assembly": states,
        "(2)(c) any equivalent of such a person in another jurisdiction": foreign,
        CORPUS_ORDER: order,
        # --- cleanroom (right) vocabulary, top level -------------------------
        "name": name,
        "an applicant": applicant,
        "constitution": constitution(
            "constitution of " + name,
            **{
                "express permission for the entity's activities to be directed or otherwise controlled by a Minister": chapeau and minister and not gov_mode,
                "express permission for the entity's activities to be directed or otherwise controlled by a member of the States Assembly": chapeau and states and not gov_mode,
                "express permission for the entity's activities to be directed or otherwise controlled by any equivalent": chapeau and foreign and not gov_mode,
                "express permission for any of the entity's governors to be a Minister": chapeau and minister and gov_mode,
                "express permission for any of the entity's governors to be a member of the States Assembly": chapeau and states and gov_mode,
                "express permission for any of the entity's governors to be any equivalent": chapeau and foreign and gov_mode,
                "that permission extended to such a person acting in that capacity": capacity,
            }),
        "the public benefit finding": pbf(
            "finding for " + name,
            **{
                "public benefit in Jersey or elsewhere, to a reasonable degree, provided": pb and not intends,
                "public benefit in Jersey or elsewhere, to a reasonable degree, intended": intends,
                "benefit provided only to one particular natural person": identified,
                "benefit provided to a section of the public only": section_only,
                "any condition on obtaining that benefit": restricted,
                "regard had to the comparison required by Article 7(2)(a)": regard_a,
                "regard had to the question required by Article 7(2)(b)": regard_b,
                "a particular charitable purpose presumed": presumed,
            }),
    }
    return o

ROWS = []
def row(name, slots, note=None):
    r = {"name": name, "slots": slots}
    if note:
        r["note"] = note
    ROWS.append(r)

# purpose-only seeds
for tag, p in P.items():
    row(f"purpose:{tag}", {"purpose": p, "charity": charity("host for " + tag, [P["education"], p])})

# entity seeds
E = [
    ("the St Helier poverty trust", dict(purposes=[P["poverty"]])),
    ("the school with a gift shop", dict(purposes=[P["education"], P["giftshop"]])),
    ("the gift shop with nothing behind it", dict(purposes=[P["giftshop"]])),
    ("the school that campaigns", dict(purposes=[P["education"], P["political-anc"]])),
    ("the grocery company", dict(purposes=[P["commercial"]])),
    ("the entity with no purposes", dict(purposes=[])),
    ("the entity with no purposes and no benefit", dict(purposes=[], pb=False)),
    ("the care home", dict(purposes=[P["care-home"]])),
    ("the chess club", dict(purposes=[P["chess"]])),
    ("the swimming association", dict(purposes=[P["swimming"]])),
    ("the members-only tennis club", dict(purposes=[P["rec-closed"]])),
    ("the public recreation ground", dict(purposes=[P["rec-open"]])),
    ("the humanist society", dict(purposes=[P["humanism"]])),
    ("the family education trust", dict(purposes=[P["education"]], identified=True)),
    ("the Ministerially directed trust", dict(purposes=[P["education"]], chapeau=True, minister=True)),
    ("the Ministerially directed trust, exempted", dict(purposes=[P["education"]], chapeau=True, minister=True, order=True)),
    ("the States-governed foundation", dict(purposes=[P["education"]], chapeau=True, states=True, gov_mode=True)),
    ("the Guernsey-governed foundation", dict(purposes=[P["education"]], chapeau=True, foreign=True, gov_mode=True)),
    ("the trust with a Minister in a private capacity", dict(purposes=[P["education"]], chapeau=True, minister=True, capacity=False)),
    ("the applicant not yet operating", dict(purposes=[P["education"]], pb=False, applicant=True, intends=True)),
    ("the school with an unduly restrictive fee", dict(purposes=[P["education"]], section_only=True, restricted=True)),
    ("the church whose benefit was presumed", dict(purposes=[P["religion"]], presumed=True)),
    ("the determiner who skipped 7(2)(b)", dict(purposes=[P["education"]], section_only=True, regard_b=False)),
    ("the dormant registered charity", dict(purposes=[P["education"]], pb=False)),
]
for name, kw in E:
    row(f"entity:{name}", {"purpose": P["education"], "charity": charity(name, **kw)})

MAP = {
    "schema": "l4-go/surface-map@1",
    "subject": "charities-jersey-2014",
    "note": [
        "Two independent encodings of the Charities (Jersey) Law 2014 charity test.",
        "left = the committed corpus (paper/case-studies/, written 2026-07); right = the",
        "cleanroom encoding written 2026-08-02 without sight of it.",
        "The `charity` slot carries BOTH vocabularies in one object, kept in sync by the",
        "generator, because applyRename only reaches a slot's TOP level and the two",
        "encodings nest their Article 5(2)/Article 7 facts differently. It is therefore",
        "declared perturb:false — a single-field mutation would move one side's copy of a",
        "fact and not the other, and every such row would read as a divergence that is an",
        "artefact of the map. The `purpose` slot IS perturbed: its two vocabularies are",
        "1:1 apart from `(2)(e)`, which the cleanroom deliberately does not declare (its",
        "ruling A2), so perturbing `(2)(e)` is a genuine question and not an artefact.",
    ],
    "sides": {
        "left": {
            "label": "corpus",
            "module": "paper/case-studies/charities-jersey-2014/part-3-charity-test.l4",
            "timezone": "Europe/Jersey",
        },
        "right": {
            "label": "cleanroom",
            "module": "jl4/examples/legal/charities-cleanroom/charity-test.l4",
            "timezone": "Europe/Jersey",
        },
    },
    "slots": {
        "purpose": {
            "kind": "record",
            "left": {"type": "CharitablePurpose"},
            "right": {"type": "Purpose", "rename": prename},
        },
        "charity": {
            "kind": "record",
            "perturb": False,
            "left": {"type": "CandidateCharity"},
            "right": {"type": "Entity", "rename": {CORPUS_ORDER: CLEAN_ORDER}},
        },
    },
    "battery": {"rows": ROWS, "perturbation": {"enabled": True, "cross_pollinate": True}},
    "pairs": [],
}

def pair(pid, l, r, largs, rargs, citation, note=None):
    p = {"id": pid, "left": {"call": l, "args": largs},
         "right": {"call": r, "args": rargs}, "citation": citation}
    if note:
        p["note"] = note
    MAP["pairs"].append(p)

# --- Article 6(1) heads, purpose -> BOOLEAN ---------------------------------
pair("head-d", "head (d) as extended by Article 6(2)(a)", "(d) — the advancement of health",
     ["purpose"], ["purpose"], "Charities (Jersey) Law 2014, art 6(1)(d), 6(2)(a)")
pair("head-f", "head (f) as extended by Article 6(2)(b)", "(f) — the advancement of citizenship or community development",
     ["purpose"], ["purpose"], "art 6(1)(f), 6(2)(b)")
pair("head-h", "head (h) as gated by Article 6(2)(c)", "(h) — the advancement of public participation in sport",
     ["purpose"], ["purpose"], "art 6(1)(h), 6(2)(c)")
pair("head-i", "head (i) as gated by Article 6(2)(d)", "(i) — the provision of recreational facilities or activities",
     ["purpose"], ["purpose"], "art 6(1)(i), 6(2)(d)")
pair("head-n", "head (n) as extended by Article 6(2)(e)", "(n) — the relief of those in need",
     ["purpose"], ["purpose"], "art 6(1)(n), 6(2)(e)",
     note="The A2 fault line: the corpus gives 6(2)(e) an operand that widens head (n); the cleanroom holds 6(2)(e) declaratory and gives it none.")
pair("head-p", "head (p) as extended by Article 6(2)(f)", "(p) — any other analogous purpose",
     ["purpose"], ["purpose"], "art 6(1)(p), 6(2)(f)")
pair("within-6-1", "falls within a head of Article 6(1)", "the purpose falls within paragraph (1)",
     ["purpose"], ["purpose"], "art 6(1)")
pair("charitable-purpose", "is a charitable purpose", "the purpose is a charitable purpose",
     ["purpose"], ["purpose"], "art 6(1), 6(5)")
pair("political", "is a charitable purpose", "(5) — the purpose is excluded as political",
     ["purpose"], ["purpose"], "art 6(5)",
     note="NOT a like-for-like pair: the corpus has no standalone 6(5) predicate, so this row is EXPECTED to disagree by construction (one is the positive test, the other the exclusion). Retained only to show the oracle reporting a declared mispairing rather than hiding it.")

# --- Article 5(1)(a), per purpose -------------------------------------------
pair("ancillary", "is a purpose purely ancillary or incidental to a charitable purpose",
     "(ii) — the purpose is purely ancillary or incidental",
     ["purpose"], ["charity", "purpose"], "art 5(1)(a)(ii), 6(5)",
     note="The A9 fault line: the cleanroom reads 'its charitable purposes' referentially and gates the limb on the entity having at least one charitable purpose; the corpus does not.")
pair("charitable-or-ancillary", "is charitable, or purely ancillary or incidental to a charitable purpose",
     "the purpose is charitable, or purely ancillary or incidental",
     ["purpose"], ["charity", "purpose"], "art 5(1)(a)")

# --- entity level -----------------------------------------------------------
pair("5-1-a", "(a) — all of its purposes are charitable or purely ancillary",
     "5(1)(a) — all of its purposes are charitable or ancillary",
     ["charity"], ["charity"], "art 5(1)(a)")
pair("5-1-b", "(b) — provides public benefit to a reasonable degree", "5(1)(b) — public benefit",
     ["charity"], ["charity"], "art 5(1)(b), 7(3)(b)")
pair("7-3-b", "Article 7(3)(b) — benefits only identified natural persons",
     "7(3)(b) — the entity benefits only identified natural persons",
     ["charity"], ["charity"], "art 7(3)(b)")
pair("5-2", "Article 5(2) — constitution expressly permits government direction or governorship",
     "5(2) — a listed person is expressly permitted under either mode",
     ["charity"], ["charity"], "art 5(2)")
pair("5-2-bites", "the Article 5(2) knock-out bites", "5(2) — the government-control disqualification applies",
     ["charity"], ["charity"], "art 5(2), 5(3)")
pair("charity-test", "meets the charity test", "the entity meets the charity test",
     ["charity"], ["charity"], "art 5")

out = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdout"
open(out, "w").write(json.dumps(MAP, indent=2) + "\n")
print(f"wrote {out}: {len(MAP['pairs'])} pairs, {len(ROWS)} seed rows", file=sys.stderr)
