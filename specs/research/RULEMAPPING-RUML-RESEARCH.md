# L4 → Rulemapping's RUML: expressive overlap and feasibility

_Status: **research memo, complete but thin by necessity.** Commissioned 2026-09-09 by Meng,
alongside the companion memo on Axiom Foundation's RuleSpec
([AXIOM-RULESPEC-POLICYENGINE-RESEARCH.md](AXIOM-RULESPEC-POLICYENGINE-RESEARCH.md)). No
transpiler is being built now. Evidence marks match the sibling memos in this directory:
**[E]** = a page fetched and read directly this session; **[E, prior]** = already established in
this repo from earlier, unrelated research (the von Cossel paper) and re-cited here, not
re-verified; **[U]** = secondary or inferred._

---

## A. Verdict

**Real methodology, real commercial platform, unpublished export format — revisit once RUML
actually ships.** "Rulemapping" the methodology is not new to this repo: a rooted-tree,
AND/OR/XOR-over-Boolean-leaves representation of statutes, evaluated bottom-up, was already
researched from the academic side (von Cossel 2026, arXiv:2605.16280) and written up in
`doc/concepts/language-design/logic-not-flowcharts.md` §"The strongest version of the tree:
Rulemapping (2026)" — see that document for the fuller prior treatment.
**This memo asks the narrower, different question the earlier research didn't**: is there an
actual interchange **file format** a transpiler could target? The answer, as of 2026-09-09, is
**not yet**. Rulemapping's own site states its export format — **RUML, the "Rulemapping Logic
Format"** — "is open and **will be published** for public access" **[E, quoted, present tense in
the original]**: future tense, no schema document found, no GitHub repository under any
Rulemapping-affiliated name, no example file obtainable. Unlike Axiom's RuleSpec (public,
2,600+ commits, real files this session could download and quote), RUML at research time is an
announced intention with a name, not yet a target with a spec. The honest thing to backlog is
**"watch for RUML's publication," not "here is what to build against."**

## B. What is actually known

**The company.** Rulemapping Group GmbH, a German company; CEO Till Behnke **[E, from
`rulemapping.com/stories/launch-of-rulemap-builder`]**. The site states ISO 27001 certification
**[E]**. The flagship product, **Rulemap Builder** (`builder.rulemapping.org`), launched
**2025-11-12** as a free, no-code visual tool: "create, visualize, and export digital, executable
decision models" **[E, quoted]**, aimed explicitly at non-programmers — the same "man on the
street" / SME nonconsumer targeting logic this project's own strategy discussions favour, applied
here to legal-drafting offices and compliance teams rather than end citizens. A companion
"Rulemapping Academy" offers training; an "integrated Library" lets users import and adapt
existing published Rulemaps, describing a nascent ecosystem rather than a single-tenant tool
**[E]**.

**The methodology**, established previously in this repo from the academic paper, not re-derived
here **[E, prior]**: a Rulemap is a rooted tree of `AND`/`OR`/`XOR` nodes (each optionally
negated) over Boolean leaves, authored by a lawyer in the visual builder, evaluated bottom-up. Two
decades of prior commercial deployment in German courts, firms and agencies predate the current
`rulemapping.org` product branding (the paper describes the older lineage; the current site is the
2025 relaunch as a self-serve builder). §3.1 of the paper explicitly positions this against
flowchart-style tools (naming McLachlan et al.'s _Lawmaps_ as the thing it is not) and against
PROLEG-style programming-formalism authoring, on the grounds that both reintroduce a
knowledge-acquisition bottleneck a lawyer-drafted tree avoids.

**RUML, the format.** Described on the Rulemapping homepage as "an open, JSON-based file format
that provides a machine-readable representation of laws, regulations and decision logic," intended
to make legal rules "understandable to software without altering their legal meaning," and scoped
as jurisdiction- and industry-independent (examples given: tax law, social benefits, building
permits, compliance checks, insurance logic, internal corporate policy) **[E, quoted]**. That is
the complete extent of what is publicly stated about RUML at research time. Not found, despite
searching: a schema document, a version number, an example `.ruml`/`.json` file, an SDK, an API
reference, or a GitHub organisation under `rulemapping`/`ruml`/`Rulemapping` (checked directly via
the GitHub API — no matching org exists) **[E]**. The "Law as Code Institute" is referenced by one
fetch as a possible authoritative source for fuller documentation but was not independently
investigated this session **[U]**.

## C. What a RUML encoding probably looks like, and why this is a guess

No worked example survives contact with the primary sources, so nothing here can be reproduced
verbatim the way the sibling memo reproduces RuleSpec YAML. What follows is inference from the
methodology paper's tree description, clearly marked as such:

- A JSON object per node, tagged with its connective (`AND`/`OR`/`XOR`), an optional negation flag,
  and either a list of child-node references (interior node) or a leaf proposition string plus a
  citation (leaf node) **[U, inferred from the paper's tree description, not from a published
  schema]**.
- Given the paper's own §7 admission that the representation is a **tree, not a DAG** — no node
  sharing, each recurring sub-condition duplicated wherever it is used — a RUML file for a
  non-trivial statute is likely to repeat identical leaf/subtree fragments verbatim rather than
  reference them, which is exactly the "update-anomaly surface" this repo's own design docs already
  flag as the tree representation's central weakness (`logic-not-flowcharts.md`, cross-referenced
  above).

This section should be treated as a placeholder to replace with real evidence, not as a design
input — do not build an emitter against this guess.

## D. Stratum-by-stratum overlap (provisional, methodology-level only)

Given no schema exists to check against, this table restates the **methodology's** known limits
(established previously in this repo) rather than a format-level mapping, and every row is
correspondingly coarser than the sibling memos' tables:

| L4 stratum                                                  | Rulemapping's tree                                                                                                                                                                                           | Verdict                                              |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| Boolean `AND`/`OR` connectives                              | direct match — `AND`/`OR` tree nodes                                                                                                                                                                         | **CLEAN**                                            |
| `NOT` / negation                                            | direct match — nodes carry an optional negation flag                                                                                                                                                         | **CLEAN**                                            |
| Exclusive-or                                                | `XOR` is a first-class connective in Rulemapping; L4 has no primitive XOR (would need a derived encoding)                                                                                                    | **CLEAN on their side, gap on ours**                 |
| Sharing / DAG structure, `WHERE`-bound reuse                | **OUT by design** — tree only, no sharing; §7 of the paper names this as a limitation, not an oversight                                                                                                      | **OUT**                                              |
| Arithmetic, numeric computation                             | not established either way — the paper's worked example (hate-speech classification) is purely Boolean over LLM-adjudicated leaves                                                                           | **UNKNOWN**                                          |
| `IMPLIES` / vacuity vs. negative conclusion                 | absent per the paper's own analysis — no way to distinguish "out of scope" from "assessed and found not to apply," both collapse to the same falsity                                                         | **OUT (a real semantic gap, not just a format gap)** |
| Deontic layer, temporal axis                                | absent per the paper                                                                                                                                                                                         | **OUT**                                              |
| Citations to source                                         | present — leaves and provisions link back to statutory text, per the paper and per the current site's "Provisions, exceptions, and references" framing                                                       | **CLEAN, qualitatively**                             |
| Case-based / neuro-symbolic leaf resolution (LLM at leaves) | this is the paper's own headline contribution — an LLM confined to fact-finding at the leaf level, not present at all in the base methodology or (as far as published) in the Rulemap Builder product itself | **Interesting, but orthogonal to export format**     |

## E. Family placement

If and when RUML publishes, the natural family is **interchange** (`BACKEND-PORTFOLIO-SPEC.md`
§1.1, "hand the law to a system") alongside DMN, BPMN and LegalRuleML — RUML is a structural
hand-off format, not an execution engine in its own right (there is no evidence of a RUML
_runtime_; the Rulemap Builder appears to be an authoring and visualization tool, with "export" as
a way to carry a finished model elsewhere, not a way to run it). Its nearest sibling by _shape_ is
actually **LegalRuleML**: both are JSON/XML interchange formats over a legal-rule structure, both
foreground citation/provenance as a first-class concern, and both currently sit at "FUTURE" in this
project's census because the interop story is aspirational rather than proven — LegalRuleML because
its consuming ecosystem is dead, RUML because it does not exist publicly yet. Census as **FUTURE**
under Interchange, cross-referencing this memo, with an explicit "recheck when RUML publishes" flag
rather than a normal dated pointer.

## F. Feasibility, and what to actually do next

Nothing is buildable against a format that has not been published. The concrete, low-cost next
step for whoever revisits this: **check `rulemapping.org` again** for the RUML spec (the site's own
language commits to eventual publication) and, if it has shipped, redo this memo as a full
stratum-overlap-with-worked-examples treatment matching the sibling RuleSpec memo's depth. Two
things are worth tracking in the meantime, both zero-cost:

- The **XOR gap** (§D) is worth noting regardless of RUML's publication status: if any future
  interchange emitter (LegalRuleML, RUML, or a hypothetical third) needs to represent exclusive-or
  faithfully, L4 has no primitive for it today and would need a derived encoding
  (`(a OR b) AND NOT (a AND b)`), which is worth flagging once, here, rather than rediscovering
  per-target.
- The **tree-vs-DAG sharing gap** already identified against the academic paper
  (`logic-not-flowcharts.md`) applies with full force to any future RUML emitter: an L4 `WHERE`-bound
  local reused across several call sites would have to be duplicated at every RUML leaf that needs
  it, which is a fidelity note any emitter must surface, not silently absorb.

## G. Sources

**Primary, read directly in this session [E]:** `rulemapping.org` (home — the RUML name,
"JSON-based," "will be published" language, use-case list); `rulemapping.com` (home);
`rulemapping.com/method` (methodology overview, Rulemap Builder, Rulemapping Academy);
`rulemapping.com/stories/launch-of-rulemap-builder` (launch date, CEO, ISO 27001, pricing);
`github.com` search and direct org-URL probes for `rulemapping`/`Rulemapping`/`ruml` (no matching
organisation or repository found).

**Established previously in this repo, cited not re-verified [E, prior]:** von Cossel, "Beyond
Imperfect Alternatives with Rulemapping: A Neuro-Symbolic Case Study on Online Hate Speech,"
arXiv:2605.16280, 10 Apr 2026, as already digested in
`doc/concepts/language-design/logic-not-flowcharts.md` (landed PR legalese#222).

**Not found / not verified this session [U]:** any RUML schema, version, or example file; the "Law
as Code Institute" reference surfaced by one fetch; whether the current commercial Rulemap Builder
product has any technical or corporate continuity with the academic paper's two-decades-of-prior-
deployment claim, beyond sharing the Rulemapping name and the same tree methodology.

**Related work already in this repo, for cross-reference:**
[AXIOM-RULESPEC-POLICYENGINE-RESEARCH.md](AXIOM-RULESPEC-POLICYENGINE-RESEARCH.md) (the sibling
memo, same request — contrast its depth against this memo's, which is the direct consequence of
one format being public and one not); [LEGALRULEML-RESEARCH.md](LEGALRULEML-RESEARCH.md) (nearest
sibling by shape, per §E); `doc/concepts/language-design/logic-not-flowcharts.md` (the owning
document for the methodology-level Rulemapping discussion); `BACKEND-PORTFOLIO-SPEC.md` §1.1 and
§2.2 (Interchange census, where this memo's FUTURE row is added).
