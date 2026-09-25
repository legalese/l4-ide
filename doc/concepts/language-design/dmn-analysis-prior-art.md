# A Gap Analysis of Gap Analysis

_Who actually detects gaps and overlaps in DMN decision tables — the standard, the conformance
suite, the vendors, and the literature. Surveyed 2026-07-26/27 by reading primary sources._

**This file is the canonical copy.** [related-work.md](related-work.md) is organised by claim and
points here; [logic-not-flowcharts.md](logic-not-flowcharts.md) §"Where it runs out" makes the
argument this evidence supports. Corrections land here first.

---

## The one-sentence finding

The DMN specification **defines** completeness, exclusivity, overlap and disjointness and gives
them normative force — and **nowhere requires a conforming implementation to detect, compute or
report any of them.** Conformance is interchange plus evaluation. A vendor can be fully CL3
conformant while never telling a user their table has a gap, and the conformance suite could not
test for it even if it wanted to.

That is the gap in gap analysis: the property is specified, the algorithms are published and
efficient, and almost nobody ships it.

---

## 1. The standard says it, and does not ask for it

Verified against the OMG PDFs directly (DMN 1.5, `formal/24-01-01`; and DMN 1.1), text-extracted
rather than read through a summariser.

The concept is normative. Clause 8.1: _"a complete table contains all possible combinations of
input values (all the rules)."_ Clause 8.2: _"input values SHOULD be exclusive and complete"_, with
a worked illustration — _"the following two ranges are incomplete: <5, >5."_ And in the
decision-table semantics: _"A complete decision table SHALL NOT specify a default output value."_

But conformance (clause 2.1) is defined purely in terms of **interchange and evaluation** at every
level. CL1 need not interpret expressions at all; CL2 adds S-FEEL; CL3 adds full FEEL. **No level
requires any analytical capability.**

### The trap: "completeness" greps to zero, and that is not evidence of absence

The words `completeness`, `masked` and `exhaustiv*` appear **zero times** in DMN 1.1 and 1.5.
`DMN15.xsd` has zero occurrences of `complete`; `tHitPolicy` is a flat enum with no completeness
flag.

The reason is not that the standard never had the idea. **DMN 1.0 carried a completeness indicator
as a table element, and OMG removed it in 1.1.** Calvanese et al., _Information Systems_ 78 (2018),
footnote 1, p.113:

> "In the new version of DMN released in 2016 (DMN 1.1), the notion of completeness indicator was
> eliminated. However, this is purely a standardization decision. The problem of identifying
> missing rules remains a relevant problem from a tooling perspective. In this article, we refer
> to the completeness and hit indicators of DMN 1.0."

This is the single most likely source of confusion in the area, because it makes the spec side and
the literature side look like they contradict each other. They do not: the academic work formalises
a 1.0 element that the current standard no longer has. Their table tuple still carries `C ∈ {c,i}`.

**Consequence for our exporter:** a completeness indicator **cannot be emitted into conformant
DMN 1.1+ XML**. Only the hit policy survived. Whatever we know about a table's completeness has to
travel in the fidelity report, not in the DMN.

_Caveat: only 1.1 and 1.5 were checked. 1.0/1.2/1.3/1.4 were not, so treat any claim about those
versions as unverified._

---

## 2. The conformance suite cannot test it — structurally, not by convention

The [DMN TCK](https://github.com/dmn-tck/tck) is active (last commit 2026-07-20): 154 `.dmn`
models, 150 test files, 3,512 `<testCase>` elements. Its own scope statement is explicit about
being behavioural — _"We will focus on concrete input and output examples. We will avoid general
discussion about what should and should not generally be true."_

The decisive artifact is the 101-line `TestCases/testCases.xsd`. Its **entire** vocabulary is:
input node values, expected result node values, and an `errorResult` boolean. There is no element
or attribute for a property, an invariant, a table-level assertion, a coverage claim, or an
analysis result.

So "the TCK is runtime-only" is a **structural fact about its schema**, not an observation about
current practice. Even a vendor who wanted to demonstrate gap detection has nowhere to put it.

Two traps for anyone re-checking this by search:

- **`overlap` returns many hits, all irrelevant.** They are the FEEL builtin range functions
  `overlaps`, `overlaps before`, `overlaps after` — Allen interval relations from clause 10.3.4,
  listed alongside `during`, `met by`, `finishes`. Runtime functions, not table analysis.
- **`completeness` returns two hits in a different sense.** The project-goal bullet
  _"**Completeness**: we will aim to test all aspects of conformance level 3"_ is completeness _of
  the suite's spec coverage_, not _of a decision table_.

`gap` returns zero. There is one static check in CI (`runners/dmn-tck-validation`), and it only
XSD-validates files. It is not semantic analysis and should not be described as such.

---

## 3. What the vendors ship

|                      | Gap / overlap analysis | What it actually is                                                                                                                         |
| -------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **Camunda 7 & 8**    | **No**                 | Nothing in the modeler docs, the decision-table docs, or `bpmn-io/dmn-js`, whose README is "View and edit DMN 1.3 diagrams in the browser." |
| **Trisotech**        | **Yes**                | "Method & Style Decision Table Analysis" — gaps, overlaps, subsumption.                                                                     |
| **Red Hat / Drools** | **Yes**                | `ANALYZE_DECISION_TABLE`, one of three `validateDMN` options in `kie-maven-plugin`.                                                         |

Verbatim from the Drools docs, which show a clean three-way split where only the third is the thing
of interest: `VALIDATE_SCHEMA` checks XML against the XSD; `VALIDATE_MODEL` checks "the basic
semantic is aligned with the DMN specification"; **`ANALYZE_DECISION_TABLE`** — _"DMN decision
tables are statically analyzed for gaps or overlaps and to ensure that the semantic of the decision
table follows best practices."_

**Both of the two are narrower than they sound.** Trisotech's is a **style linter** tied to one
consultant's methodology (Bruce Silver's Method & Style), and
[logic-not-flowcharts.md](logic-not-flowcharts.md) §"Where it runs out" already records the limit
from Trisotech's manual: _"when generalized unary tests are used, it is no longer possible to use
DT Analysis."_ Red Hat's is **Maven build-time only** — no documented
live panel in the KIE editor — and needs data-type constraints declared in the table header, or gap
analysis has no finite domain to check.

### Two traps that make Camunda look like it has this

1. **The dmn-js analyser is an academic fork, not a Camunda feature.** `ulaurson/dmn-js` is
   confirmed via the GitHub API to have parent `bpmn-io/dmn-js`. It is the University of Tartu
   prototype (§4 below), last pushed **2016-05-19**.
2. **Camunda's best-practice page talks about completeness without providing it.** The Unique hit
   policy _"ensures your rules are 'complete'"_ and invalidates logic when rules _"overlap"_ — but
   that is **runtime enforcement plus human advice**, not static analysis. Read quickly it gives
   precisely the opposite impression.

A third-party Modeler plugin, `red6/dmn-check`, does detect duplicate, conflicting and shadowed
rules — overlap, but not gap/completeness. **Its existence as a plugin is itself evidence the base
product lacks this.**

_Honest limit: no Camunda staff denial was obtained (`forum.camunda.io` blocks automated fetch).
The supportable claim is "absent from all product documentation read", not "vendor confirmed
absent". Red Hat-branded doc pages 403, so cite Drools upstream, which was read directly._

This corroborates from the vendor side what Grohé, Corea & Delfmann (2021) found from the survey
side: of fourteen DMN tools, five supported any verification capability at all — "alarmingly low."

---

## 4. The literature: efficient, settled, and largely abandoned

**Canonical citation:** Calvanese, Dumas, Laurson, Maggi, Montali & Teinemaa, "Semantics, Analysis
and Simplification of DMN Decision Tables", _Information Systems_ 78 (2018) 112–125. Freely
linkable near-equivalent: BPM 2016, [arXiv:1603.07466](https://arxiv.org/abs/1603.07466).

**Terminology:** their term is **missing rules**, not "gaps" — `gap` greps to zero in the IS 2018
full text. ("Contraction" and "misleading" are not their vocabulary at all.)

### How detection actually works

Everything reduces to geometry. Each rule is an **iso-oriented hyper-rectangle** in N-space, N =
number of columns — iso-oriented because S-FEEL permits only `attribute operator literal`, which
defines axis-parallel segments. Categorical columns are mapped to **disjoint intervals**
(`"Refinancing" → [0..1)`, …), so they are segments too; a multi-valued entry yields several
rectangles for one rule.

- **Overlap** = intersection-finding over hyper-rectangles. Naive pairwise is `O(N·|R|²)`; theirs is
  sweep-line plus range queries at `O(|R|·log^N |R|)`. Output is **maximal cliques of the overlap
  graph** rather than all pairs — deliberately, so the feedback stays readable.
- **Missing rules** = the difference between the facet-defined space and the union of the rule
  rectangles, with adjacent gaps merged so fewer and larger regions are reported.
- **The actual advance** is handling _overlapping numeric intervals_ natively. Every earlier
  decision-table algorithm requires boolean, categorical, or disjoint domains, so overlapping
  intervals force a table split that "in the worst case increases the size of the table
  exponentially in the number of numerical attributes."
- Measured on LendingClub-derived tables: sub-minute to ~1500 rules, degrading past ~13 columns.
  The `log^N` term bites in **N**, not in `|R|` — which is the right way round for law, where
  tables are long rather than wide.

### Formalised is not the same as implemented

`Correct_D` is defined as four things: facet correctness, completeness, hit-policy compatibility,
and a global input/output relation. **Three things are implemented**: overlap detection,
missing-rule detection, and merging-based simplification — which they class as _refactoring_, not
analysis.

- **Masked-rule detection is not a separate algorithm.** It falls out of overlap plus priority.
- **Subsumption is prose only** — two mentions, never a named task, never an algorithm.
- **Simplification is not solved.** Optimal rule merging is **optimal rectangulation of an
  orthogonal hyper-polygon, NP-complete at ≥3 dimensions.** Their Algorithm 2 is an explicit
  polynomial best-first heuristic. Nobody in this line does it exactly, and we should not imply we
  do either.

### Who has the richer catalogue

**Corea, Blatt & Delfmann**, "A Tool for Decision Logic Verification in DMN Decision Tables", BPM
Demo 2019, [CEUR Vol-2420](https://ceur-ws.org/Vol-2420/papeDT11.pdf) — note the path is `pape`,
not `paper`; the obvious URL 404s. It implements the seven separated capabilities Calvanese et al.
never break out: identical rule, equivalent rule, subsumed rule, interdeterminism, partial
reduction, overlapping condition, missing rule — and analyses errors **across** tables. It names
the limitation in as many words:

> "…those authors do not distinguish between identical rules, subsumed rules and overlapping rules,
> but denote all these error types as overlaps."

If we ever want subsumption as a first-class check, this is the reference, and
`gitlab.uni-koblenz.de/fg-bks/br-verification-tool` is still up.

### The closest published analogue to our own normaliser

**Batoulis & Weske**, "A Tool for the Uniqueification of DMN Decision Tables", BPM Demo 2018 —
transforms a table with overlapping rules into an **equivalent table containing only exclusive
rules**, motivated by tables with overlapping rules being "hard to understand and unsuitable for
analysis tasks."

That is _repair/normalisation_, complementary to Calvanese's _detection_, and it is the nearest
prior art to what `L4.Viz.GuardedRows` does. Ours normalises an L4 AST rather than a DMN table,
which is a real difference — but the operation is not new, and it is better to cite it than to have
a reviewer find it.

### Semantic DMN — formalised, never built

Calvanese, Dumas, Maggi & Montali, TPLP 19(4) 2019 ([arXiv:1807.11615](https://arxiv.org/abs/1807.11615)),
adds background knowledge: a Decision Knowledge Base = a DMN requirements graph plus FOL with
datatypes. Under `ALCH(D)` all seven tasks reduce to standard description-logic reasoning and
decide in **EXPTIME** on off-the-shelf OWL 2 reasoners. Two have no analogue in the geometric line
and are the interesting ones for law: **output coverage** (can a declared output value ever be
produced at all, given inter-table flow — their maritime example proves "outdoor" unreachable) and
**output determinability**.

**It has no implementation.** The paper's own conclusion: "we plan to realize this implementation."

### The survivorship finding

**Every hosted demo in this literature is dead.** `dmn.cs.ut.ee` (cited in both the BPM 2016 demo
paper and IS 2018 §5) no longer resolves; the Koblenz and HPI demo hosts are gone. Two of three
source repos survive and both are dormant — `ulaurson/dmn-js` at 4 stars, last pushed 2016.

The field is **academically settled and practically abandoned**, which is exactly consistent with
the vendor picture above. That conjunction is the argument: this is not an open research problem
that nobody has solved. It is a solved problem nobody ships.

---

## 5. What this means for L4

1. **The claim we can defend** is not "we can do analysis DMN cannot." It is that the analysis is
   _well understood, not required by conformance, and absent from the tool people actually use_ —
   while in L4 it is a typechecker pass that runs on every build.
2. **Completeness cannot ride in the DMN.** It has to be in the fidelity report.
3. **Cite Batoulis on `GuardedRows`,** and Corea et al. if we add subsumption.
4. **Do not claim optimal simplification.** It is NP-complete at ≥3 columns.
5. The geometric method's cost is exponential in **columns**, not rows — worth knowing before we
   assume our own analyses will scale the same way.

---

## Sources

Read directly and verified: OMG DMN 1.5 (`formal/24-01-01`) and DMN 1.1 PDFs; the `dmn-tck/tck`
tree including `TestCases/testCases.xsd`; Drools DMN documentation; Camunda 7/8 modeler and
decision-table documentation; `bpmn-io/dmn-js` and `ulaurson/dmn-js` (GitHub API for the fork
relationship); Calvanese et al. BPM 2016 (arXiv) and _Information Systems_ 78 (2018); Calvanese et
al. TPLP 19(4) 2019 (arXiv); Laurson & Maggi, BPM Demo 2016, CEUR Vol-1789 pp. 56–60; Corea, Blatt
& Delfmann, BPM Demo 2019, CEUR Vol-2420; Batoulis & Weske, BPM Demo 2018, CEUR Vol-2196 and BPM
Demo 2017, CEUR Vol-1920.

Metadata verified but **content not read** — do not quote: Calvanese et al., RuleML+RR 2017
(paywalled); Batoulis & Weske, BIS 2018 (paywalled); Hasić et al., RCIS 2020 (advertised OA copy
404s). Also unverified: a Trisotech release note naming a "DT Analysis button in the DMN ribbon";
the Laurson & Maggi claim that Signavio implements a comparable analysis.
