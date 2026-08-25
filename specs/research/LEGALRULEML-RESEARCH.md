# L4 → LegalRuleML: expressive overlap and feasibility

_Status: **research memo, complete.** Commissioned 2026-08-16 by the backend-portfolio session
(`BACKEND-PORTFOLIO-SPEC.md` §2.2 census row) and produced the same day by a dedicated research
agent; the census row and the `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` prior-art block are pinned to
this memo. Evidence marks are the researcher's own: **[E]** = primary document read or command
executed; **[U]** = secondary. The `scratchpad/osdist/` working copy of the OASIS distribution
named in §E was session-scratch and is ephemeral; every artifact it contained is fetchable from
the cited `docs.oasis-open.org` paths._

---

## A. Verdict

**Yes — but as a publication-and-provenance artifact, not an interoperability bridge, and only if
scoped to roughly a third of L4.** LegalRuleML is a real OASIS Standard (30 August 2021) with
three pre-generated monolithic XSDs and 30 shipped golden examples, and it was verified end-to-end
that a stock `xmllint --noent --loaddtd` validates **all 30 of them** against the compact and
normal schemas with zero installs. So the emitter has a genuine, offline, binary pass/fail gate on
day one — better than most export targets. The catch is that validity is _all_ you get.
LegalRuleML is deliberately semantics-free ("independent from any legal ontology and logic
framework", §2.3 [E]), every reasoner that ever consumed it is dead (Regorous returns HTTP 410,
SPINdle's host fails DNS with a 2017 binary, LIME refuses connections [E]), and the TC's own
GitHub repo has not been pushed since July 2020 [E]. Where it genuinely pays is the metadata layer
nobody else standardizes: `LegalSource`/`LegalReference` isomorphism with Akoma Ntoso naming
conventions, `TemporalCharacteristic` in-force/efficacy intervals, and `Alternatives` for
competing interpretations. Those three map onto L4's `@ref` provenance, temporal rule-version
axis, and ambiguity register **so precisely that they read as independent confirmation that L4's
annotation layer is designed correctly** — which is the actual prize here.

## B. Stratum-by-stratum overlap

| L4 stratum                                                                 | LegalRuleML construct                                                                                                                                                    | Verdict                            |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------- |
| Constitutive core (`GIVEN`/`GIVETH`/`DECIDE`/`MEANS`)                      | `lrml:ConstitutiveStatement` wrapping `ruleml:Rule`, `ruleml:if`/`then`, `ruleml:Atom`+`Rel`, `Var`, `Expr`+`Fun`                                                        | **RESTRICTED**                     |
| Records/enums, `CONSIDER`/`BRANCH`                                         | no counterpart; flatten to atoms + guards                                                                                                                                | **EMULATED**                       |
| `NUMBER` (exact rational), `DATE`, `STRING`, `BOOLEAN`                     | `ruleml:Data` with `@xsi:type` (XSD types)                                                                                                                               | **RESTRICTED** (no exact rational) |
| `PARTY p MUST/MAY/SHANT a`                                                 | `lrml:PrescriptiveStatement` → `lrml:Obligation`/`Permission`/`Prohibition`/`Right`, party via `ruleml:slot` + `lrml:Bearer`/`AuxiliaryParty`                            | **CLEAN**                          |
| `HENCE`/`LEST` reparation chain                                            | `lrml:SuborderList`, `lrml:PenaltyStatement`, `lrml:ReparationStatement`/`Reparation`/`appliesPenalty`/`toPrescriptiveStatement`                                         | **CLEAN for LEST, OUT for HENCE**  |
| `WITHIN` deadline                                                          | nothing — §4.3.5 models rule validity, explicitly _not_ "the temporal dimensions of the complex events that are the content of the provision" [E]                        | **OUT**                            |
| `FULFILLED`/`BREACH`                                                       | `lrml:Compliance`, `lrml:Violation` (as indications, not terminals)                                                                                                      | **RESTRICTED**                     |
| `RAND`/`ROR` parallel composition                                          | no counterpart                                                                                                                                                           | **OUT**                            |
| `#TRACE` residuation over event streams                                    | no counterpart — no execution model at all                                                                                                                               | **OUT**                            |
| `EVAL … UNDER RULES EFFECTIVE AT`                                          | `lrml:TemporalCharacteristic` + `forStatus` (`vocab#InForce`, `#Efficacious`) + `hasStatusDevelopment` (`#Starts`,`#Ends`) + `atTime` → `ruleml:Time`/`Data xs:dateTime` | **CLEAN**                          |
| Ambiguity register                                                         | `lrml:Alternatives` + `hasAlternative` + `fromLegalSources`                                                                                                              | **CLEAN**                          |
| `@ref`/`@ref-src`/`@ref-map`                                               | `lrml:LegalSources`/`LegalSource@sameAs`, `LegalReferences`/`LegalReference@refID`+`@refIDSystemName`, `Association`/`appliesSource`/`toTarget`                          | **CLEAN**                          |
| Inert-style verbatim statute text                                          | `lrml:Paraphrase`, `lrml:Comment`                                                                                                                                        | **CLEAN**                          |
| `TYPICALLY` defaults                                                       | `lrml:DefeasibleStrength` on a synthesized default rule                                                                                                                  | **EMULATED**                       |
| `SUBJECT TO`/`NOTWITHSTANDING` (spec-only)                                 | `lrml:Override`/`OverrideStatement`, `hasStrength` → `StrictStrength`/`DefeasibleStrength`/`Defeater`                                                                    | **CLEAN (prior art)**              |
| Ledger/effects (`RECORD`/`COMMIT`/`ATTEST`/`RECALL`, `FETCH`/`POST`/`ENV`) | none — confirmed absent                                                                                                                                                  | **OUT**                            |

Taking the five flagged questions in turn.

**(i) PARTY/MUST/WITHIN/HENCE/LEST.** The regulative layer splits cleanly in two. The
party-and-modality half is an unusually exact match: LegalRuleML's deontic operators are
_directed_, carrying `Bearer` and `AuxiliaryParty` role slots, so `PARTY p MUST action` is a
faithful `lrml:Obligation` with `p` in the `Bearer` slot — this is not emulation, it is the same
design. The `LEST` half maps onto `SuborderList`, whose §4.2.3.2 semantics is exactly right: "a
Deontic Specification in the SuborderList holds if all Deontic Specifications that precede it in
the SuborderList have been violated" [E]. That is Governatori & Rotolo's `⊗` operator, and an
`[OBL]A ⊗ [OBL]B ⊗ [FOR]C` chain is precisely a `MUST`…`LEST`…`LEST` cascade. But `WITHIN` and
`HENCE` fall off. There is no deadline slot anywhere in the standard — §4.3.5 rules event-time
out of scope by construction. And `HENCE` is a _success_ continuation; a `SuborderList` only
advances on violation, so the happy path has no representation. Concretely: a two-step L4
contract where paying triggers a delivery obligation cannot be a suborder chain at all. You would
need two `PrescriptiveStatement`s linked by a constitutive rule that derives "payment made",
which is a re-encoding, not a translation.

**(ii) Temporal.** The best surprise. `EVAL … UNDER RULES EFFECTIVE AT date` is asking exactly
the question `forStatus vocab#InForce` answers, and the spec's own motivation for the machinery
is rule-version pinning — it gives the example of "statutory damage 500$ in 2000, 750$ in 2006,
1000$ in 2010" and a reasoner selecting "the correct penalty according to the time of the crime"
[E]. That is L4's temporal axis restated in the standard's own words. Two caveats: LegalRuleML
models intervals as _paired point events_ (`Starts`/`Ends` at a `Time`) rather than as intervals,
so each pin becomes two `TemporalCharacteristic`s; and it distinguishes in-force from efficacy
from applicability, so you must decide which of the four EVAL pins maps to which axis — a genuine
design question, not a mechanical one.

**(iii) Ambiguity register → Alternatives.** A direct hit, and the standard's flagship example is
the same shape as ours. `examples/compactified/ex11-maternity_alternatives-compact.lrml` records
three rival readings of one maternity-benefit provision — the literal reading, the freelancer's,
and the employer's — as `<lrml:hasAlternative keyref="#literal"/>`, `#freelancer`, `#employer`,
under a `Comment` reading "These alternatives are mutually incompatible formalizations of the
same legal source" [E]. The spec is explicit that it "endeavours not to account for how different
interpretations arise, but to provide a mechanism to record and represent them" (§4.2.4) [E] —
exactly the ambiguity register's job description. If we export nothing else, export this: the BNA
12-entry ambiguity register is directly expressible, and per the literature survey no published
corpus exercises much of this machinery, so a real register over real legislation would be novel.

**(iv) `@ref` → isomorphism.** Also clean, and the fit is better than expected because
LegalRuleML's `LegalReference` carries `@refIDSystemName` naming a citation convention, with the
spec's worked example using `"AkomaNtoso3.0-2016-03"` and an Akoma Ntoso FRBR path [E].
`Association`/`appliesSource`/`toTarget` gives the N:M rule-to-provision relation `@ref-map`
needs, at the fine granularity the spec demands ("rules, fragments of rules, atoms, fragments of
atoms… letters, numbers, paragraphs, sentences, and word"). The `@key`/`@keyref` discipline means
every L4 node we want citable must carry a stable, document-unique key — an emitter design
constraint worth knowing early.

**(v) Override as third defeasibility datapoint.** Yes, and it is the strongest of the three.
Catala's exceptions and Blawx's defeat triples are each one system's design choice; LegalRuleML's
`Override`/`OverrideStatement` plus the `StrictStrength`/`DefeasibleStrength`/`Defeater` trio is
that same design ratified as an international standard, with §4.2.1 running through lex
specialis, lex superior and lex posterior and citing Prakken & Sartor's objection that
specificity alone is inadequate for legal reasoning [E]. Worth flagging precisely:
`specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md` §5.2 already describes strict/defeasible/defeater
plus priority ordering, attributing it to Prakken and Sartor — but never mentions that OASIS
standardized exactly this trio with an XML surface syntax. That is a one-line citation the spec
should carry, and it materially strengthens its case: the proposal is not inventing a mechanism,
it is adopting the standardized one.

**(vi) Where the functional core goes.** RuleML atoms are relational, so yes, the `L4.Relational`
middle-end claim applies and is load-bearing — this is the same A-normal-form flattening with an
output argument that the logic-programming targets need, so a LegalRuleML backend should sit
downstream of it rather than beside it. The good news is that Consumer RuleML is not pure
Datalog: `ruleml:Expr` + `ruleml:Fun` give function application in term position, and the spec's
own §6 example computes with them (`<ruleml:Fun iri=":subtract"/>` over a `Var` and a typed
`Data`) [E]. So arithmetic survives. What does not survive is the type system: there are no
record or sum types, `CONSIDER`/`BRANCH` must be flattened into guarded rules with the
constructor discriminated by an atom, and `ruleml:Data` is typed by XSD, which has no exact
rational — L4's `NUMBER` would go to `xs:decimal` (lossy for repeating fractions) or a two-field
ratio encoding. `MAYBE` and lists have no counterpart and need an encoding convention we invent.

## C. Feasibility

The emitter is genuinely easy; the modeling decisions are not. Serialization is ordinary XML
generation against a fixed vocabulary — the mechanical share is roughly 60%: emitting
`Statements`, `ConstitutiveStatement`, `PrescriptiveStatement`,
`Obligation`/`Permission`/`Prohibition` with `Bearer` slots, `LegalSources`, `Times`,
`TemporalCharacteristics`, `Alternatives`, and the `@key`/`@keyref` graph. Target the **Compact**
serialization: Normalized is more verbose, and the shipped XSLTs (`normalizer/`, `compactifier/`)
convert between them, so emit one and derive the other free. The design-heavy 40% is everything
above: the in-force/efficacy/applicability axis assignment, the record and `CONSIDER` flattening
convention, the exact-rational encoding, and deciding what to do with `HENCE`, `WITHIN`,
`RAND`/`ROR` and `#TRACE` — which have no representation and must either be dropped with an
explicit unsupported-construct diagnostic or smuggled into `lrml:Comment`. Dropping honestly is
the right call.

**Validation harnesses, ranked.**

1. **XSD validation via `xmllint`** — confirmed working, 30/30 shipped goldens pass, no install,
   no network, drops straight into `jl4-test` as a golden suite. One trap:
   `ex5-section29new-compact.lrml` fails until you pass `--noent --loaddtd`, because it declares
   namespaces through DTD entity references (`xmlns:lrml="&lrml;/"`); without those flags you get
   a misleading "No matching global declaration available for the validation root."
2. **The §7 conformance clause** — unusually testable, specifying five conditions "enforced by
   neither Relax NG nor XSD", chiefly document-unique `@key`s and `@index` agreement with sibling
   position. A ~50-line post-pass buys real conformance beyond schema validity [E].
3. **Differential re-import** — parse the emitted XML back to a normalized L4 shape and compare.
   Tests the emitter, not the standard.
4. **RDF triplification** via the shipped `xslt/lrml-rdf/triplifyMerger-ids.xsl`, the spec's own
   optional conformance item.

"Round-trip" in the usual sense is not available and we should say so plainly rather than imply
otherwise. There is no reference evaluator, and per Robaldo et al. no reasoner acts on
LegalRuleML directly — even LegalRuleML's own community transcodes to SPINdle first [E]. The
honest strongest claim is: _schema-valid, conformance-clause-conformant, structurally faithful on
the strata that map._

## D. Risks and unknowns

The dominant risk is presenting this as more than it is. Every artifact in the distribution is
timestamped 30-Aug-2021 and nothing has moved since; there is no v1.1, no package on PyPI or
Maven, and the ecosystem's most-starred repo (51 stars) is a bag of examples. A claim of
"LegalRuleML support" is a claim about a file format and must never be phrased as a claim about a
running system — that is the specific way this becomes a paper exercise. Second, semantic
underspecification cuts against L4's core value proposition: because the standard refuses to fix
the meaning of its deontic operators, an export cannot carry L4's operational semantics, only its
structure, and a consumer must re-supply the logic out of band. Third, `SuborderList` — the
construct we most want — is per the literature survey the least-exercised part of the standard,
with no published corpus using it, so we'd be both the first real user and without a second
implementation to check against. Fourth, XSD's lack of exact rationals is a silent-lossiness
hazard in exactly the fee-table and benefit-formula domains where L4 earns its keep; whatever
encoding is chosen, make the loss loud. Finally, schema versioning is a non-risk near-term
(frozen means stable) but means no path to fix known defects, including the one Lam & Hashmi
flagged where `lrml:Violation` at statement head yields a rule with no head literal.

## E. Sources

**Primary, read directly [E]:** OASIS LegalRuleML Core Specification v1.0, OASIS Standard,
30 Aug 2021 —
`https://docs.oasis-open.org/legalruleml/legalruleml-core-spec/v1.0/os/legalruleml-core-spec-v1.0-os.html`,
§§3.4 (node inventory), 3.6 (edges), 4.2.1 (defeasibility/`Override`), 4.2.2 (constitutive vs
prescriptive), 4.2.3.1 (deontic operators, `Bearer`), 4.2.3.2 (`SuborderList`/`Penalty`/
`Reparation`), 4.2.4 (`Alternatives`), 4.3.1 (sources/isomorphism), 4.3.5 (time/events), 4.4
(associations/context), 6.2 (Bologna maternity case), 7 (conformance). Editors Palmirani,
Governatori, Athan, Boley, Paschke, Wyner. Namespace
`http://docs.oasis-open.org/legalruleml/ns/v1.0/`. Distribution zip and all schemas/examples
under the same `os/` path. Validation run performed by the researcher [E]:
`xmllint --noent --loaddtd --noout --schema xsd-schema/{compact,normal}/lrml-{compact,normal}.xsd`
over `examples/{compactified,normalized}/*.lrml`, 30/30 pass.

**Repo files, read directly [E]:** `specs/done/APP-LIBS-SPEC.md:360` (sole LegalRuleML mention, a
"Related Work" bullet); `specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md:186`,
`paper/icail/l4-icail.bib:370`, `doc/concepts/legal-modeling/actor-actions.bib:286`,
`jl4-proleg/docs/burden-of-proof.md:254` (all cite Governatori 2005 RuleML, not LegalRuleML);
`specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md` §5.2 and its status header confirming the
override constructs are unimplemented. **There is no prior LegalRuleML awareness in this repo
beyond one bibliography line.**

**Secondary, via delegated research [U unless marked]:** tooling-decay evidence — Regorous
`research.csiro.au/bpli/our-research/bpc/` HTTP 410, SPINdle SourceForge last release 2017-02-27
and `spindle.data61.csiro.au` DNS failure, LIME `lime.cirsfid.unibo.it` connection refused,
`oasis-tcs/legalruleml` last push 2020-07-19 [all E by subagent]. Semantics-agnosticism
corroborated by Steen & Fuenmayor, RuleML+RR 2022, `arXiv:2209.05090`, and Robaldo et al., AI&Law
2024 [E by subagent]. Canonical papers: Athan et al., ICAIL 2013, `10.1145/2514601.2514603`;
Athan et al., Reasoning Web 2015, `10.1007/978-3-319-21768-0_6`; Governatori, IJCIS 14(2–3),
2005, `10.1142/S0218843005001092`; Lam, Hashmi & Scofield, TPLP 2016, `arXiv:1711.06128`;
Governatori & Palmirani, ICAIL 2025, `10.1145/3769126.3769257`.
