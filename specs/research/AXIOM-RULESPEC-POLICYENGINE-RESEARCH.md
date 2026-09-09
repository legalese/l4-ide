# L4 → Axiom Foundation's RuleSpec, and PolicyEngine: expressive overlap and feasibility

_Status: **research memo, complete.** Commissioned 2026-09-09 by Meng, who asked for "Axiom
Foundation's PolicyEngine" to be added to the export-format backlog alongside Rulemapping (see the
companion memo, [RULEMAPPING-RUML-RESEARCH.md](RULEMAPPING-RUML-RESEARCH.md)). No transpiler is
being built now; this memo does the research and leaves representative examples so a future
session can decide whether to. Evidence marks follow the convention of the prior two memos in this
directory: **[E]** = primary source (a repo file, a README, a specification page) fetched and read
directly in this session; **[E, code]** = a real source file downloaded and read in full, quoted
verbatim below; **[U]** = secondary or inferred, not independently confirmed._

---

## A. Verdict, and one correction to the premise

**The premise names one organisation where there are two, and that distinction is the whole
story.** "Axiom Foundation's PolicyEngine" reads as if PolicyEngine belongs to Axiom. On the
evidence gathered, it is the other way round in seniority and separate in governance: **PolicyEngine**
is the older, independent project (a fork of OpenFisca-Core, in continuous development since
around 2021, AGPL-3.0, ~160 GitHub stars on the US package alone) that computes tax-and-benefit
microsimulations; **Axiom Foundation** is a new (launched 2025, fiscally sponsored by the PSL
Foundation) initiative, founded by the same person — Max Ghenis, who is also PolicyEngine's
founder — to publish machine-readable, cited, time-aware encodings of statutes in a format Axiom
calls **RuleSpec**, and Axiom uses PolicyEngine (alongside TAXSIM, UKMOD, EUROMOD, SOUTHMOD) as one
of several independent **oracles** to cross-validate its encodings **[E]**. So there are properly
three things to evaluate, not one: PolicyEngine (mature microsimulation engine, OpenFisca's
architectural sibling), RuleSpec (the new format, the actual novel prior art), and the
Axiom-Rules-Engine that compiles and runs it (Rust + WASM). This memo covers all three but the
verdict differs sharply between them:

- **PolicyEngine**: not a new target. Its core is literally "Forked from OpenFisca-Core" **[E,
  GitHub org description]**, and `policyengine-us`'s own package layout (`variables/`,
  `parameters/`, `entities.py`, `system.py`) is OpenFisca's own directory convention, confirmed by
  directly listing the package **[E]**. L4 already ships an OpenFisca backend
  (`jl4-core/src/L4/OpenFisca/{IR,Lower,Emit}.hs`, `BACKEND-PORTFOLIO-SPEC.md` §2.1). The honest
  claim is: **the nearest existing bridge is the right starting point**, not a new one — subject to
  actually verifying PolicyEngine's parameter/variable shape still matches upstream OpenFisca
  closely enough for the emitted YAML/Python to load unchanged, which this session did not test.
- **RuleSpec**: genuinely new and, on the evidence, **the closest structural match to L4's own
  design values of any backend researched in this programme so far** — cited, time-aware,
  first-class temporal versioning, a small boolean/arithmetic expression language over named
  facts, and an explicit citation-to-a-proof-atom discipline that goes further than anything this
  project has shipped. It is also large, real, and actively maintained: the `rulespec-us`
  monorepo alone shows 2,606 commits, 96 issues, 83 PRs, dual Apache-2.0/CC-BY-4.0 licensing, and
  per-state directories for all 50 US states plus federal **[E]**. Unlike every other backend
  researched to date in this repo (LegalRuleML, DataLex/yscript), this is not "found a paper and a
  demo" — it is "found a live, growing, multi-jurisdiction corpus with its own CI gates."

## B. What each of the three things is

**PolicyEngine.** A nonprofit (funding/legal structure not independently verified this session)
building open-source microsimulation models of tax-and-benefit systems: `policyengine-us`,
`policyengine-uk`, `policyengine-canada`, `policyengine-ng` (Nigeria), `policyengine-il` (Israel),
plus a web app, REST API, and a large family of demo/analysis tools (givecalc, marriage-penalty
calculators, a CTC-expansion impact calculator) **[E, org repo listing]**. `policyengine-core` is
explicitly described in its own one-line GitHub description as "Core microsimulation engine for
PolicyEngine models. Forked from OpenFisca-Core." **[E]** — so PolicyEngine inherits OpenFisca's
Variable/Parameter/Entity/formula model rather than inventing a new one, which is precisely the
model L4's existing OpenFisca backend already targets.

**Axiom Foundation.** Launched 2025 (blog post dated as the launch announcement, read directly
**[E]**), "a fiscally sponsored project of the PSL Foundation" **[E, About page]**, founded by Max
Ghenis (CEO), Ariel Kennan (President) and Pavel Makarchuk (Product Lead) **[E]**. Its stated
mission: "open, machine-readable encodings of the world's rules, starting with tax and benefit
policy — statutes, regulations, and policy rules turned into cited, time-aware, executable code
that anyone can run, audit, or reform" **[E, quoted]**. At launch it claimed over 3,000 legal
provisions encoded, covering US federal tax and benefit programs (SNAP, tax credits named
specifically), with international expansion named as a goal **[E]**. Verification methodology:
"An AI-driven pipeline reads a statute, encodes it section by section, and runs the result against
oracles like PolicyEngine and TAXSIM" **[E, quoted]** — i.e., generation is AI-assisted
(`axiom-encode`, described in its own repo as "AI-assisted RuleSpec encoding infrastructure" **[E]**)
but every encoding must independently agree with at least one existing, hand-built microsimulation
engine before publication — a stronger evidentiary bar than this project currently applies to any
of its own LLM-touched tooling.

**RuleSpec, the format.** A declarative encoding format, authored in **YAML**, versioned
(`format: rulespec/v1` is a required top-level field; files without an exact-matching format
string are rejected outright — strict versioning by construction, not convention) **[E, from the
`axiom-rules-engine` README]**. Compiled and executed by a **Rust** runtime with **Python
bindings**, additionally compiling to **WASM** for in-browser execution (the `axiom-local` and
`dashboard-builder` tools run entirely client-side, "requiring no data transmission" **[E]**) —
compiled artifacts are cached as a JSON-serialised `CompiledProgramArtifact` (schema version 2 at
research time) so re-execution does not require recompiling **[E]**. Two execution modes exist:
`explain` (returns a trace) and `fast` (a dense-path optimisation) **[E]** — the same
golden-vs-executed-vs-explained distinction this project's own claim ladder (I3,
`BACKEND-PORTFOLIO-SPEC.md` §4) already makes explicit. Licensing: the engine is Apache-2.0; the
`rulespec-us` encodings are dual Apache-2.0/CC-BY-4.0 **[E]** — both properly open, unlike
LegalRuleML's dead ecosystem or DataLex's AGPL interpreter, and importantly unlike Rulemapping's
RUML, which at research time is announced but **not yet published** (see the companion memo).

## C. Worked example (verbatim, primary source)

Downloaded directly from the `rulespec-us` monorepo (`us/statutes/7/2015/e.yaml`,
`TheAxiomFoundation/rulespec-us`, `main` branch, read in full — 300 lines — this session) **[E,
code]**: an encoding of **7 U.S.C. § 2015(e)**, the SNAP student-eligibility exception. Excerpted
here (elisions marked `# …`):

```yaml
format: rulespec/v1
module:
  proof_validation:
    required: true
  source_verification:
    corpus_citation_path: us/statute/7/2015
  summary: |-
    (e) Students No individual who is a member of a household otherwise
    eligible to participate in the supplemental nutrition assistance
    program under this section shall be eligible to participate … [full
    statutory text of the subsection, verbatim, as the module summary]
rules:
  - name: student_under_age_exception_threshold_years
    kind: parameter
    dtype: Count
    source: 7 U.S.C. 2015(e)(1)
    metadata:
      proof:
        atoms:
          - path: versions[0].formula
            kind: amount
            source:
              corpus_citation_path: us/statute/7/2015
    versions:
      - effective_from: "2008-10-01"
        formula: |-
          18

  # … five more `kind: parameter` entries, each a single named threshold
  # (age 50, 4 years, 20 hours/week, ages 6 and 12), each carrying its own
  # `source:` pincite and its own `proof.atoms` citation object.

  - name: student_work_exception_applies
    kind: derived
    entity: Person
    dtype: Judgment
    period: Month
    source: 7 U.S.C. 2015(e)(4)
    metadata:
      proof:
        atoms:
          - path: versions[0].formula
            kind: exception
            source:
              corpus_citation_path: us/statute/7/2015
    versions:
      - effective_from: "2008-10-01"
        formula: |-
          employed_hours_per_week >= student_minimum_employment_hours_per_week
          or person_participates_in_state_or_federally_financed_work_study_program_during_regular_school_year

  - name: student_exception_applies
    kind: derived
    entity: Person
    dtype: Judgment
    period: Month
    source: 7 U.S.C. 2015(e)(1)-(8)
    metadata:
      proof:
        atoms:
          - path: versions[0].formula
            kind: exception
            source:
              corpus_citation_path: us/statute/7/2015
    versions:
      - effective_from: "2008-10-01"
        formula: |-
          student_age_exception_applies
          or person_is_not_physically_or_mentally_fit
          or student_assignment_or_placement_exception_applies
          or student_work_exception_applies
          or student_parent_child_care_exception_applies
          or person_receiving_benefits_under_state_program_funded_under_part_a_title_iv_social_security_act
          or person_enrolled_as_result_of_participation_in_work_incentive_program_under_title_iv_social_security_act_or_successor
          or student_single_parent_exception_applies

  - name: student_ineligible_for_snap_participation
    kind: derived
    entity: Person
    dtype: Judgment
    period: Month
    source: 7 U.S.C. 2015(e)
    metadata:
      proof:
        atoms:
          - path: versions[0].formula
            kind: condition
            source:
              corpus_citation_path: us/statute/7/2015
    versions:
      - effective_from: "2008-10-01"
        formula: |-
          person_is_member_of_household_otherwise_eligible_to_participate_under_this_section
          and person_is_enrolled_at_least_half_time_in_institution_of_higher_education
          and not student_exception_applies
```

Two structural observations worth carrying into any future emitter design:

1. **Every intermediate proposition gets its own named `derived`/`Judgment` rule**, even ones with
   no independent standing outside this one subsection (`student_work_exception_applies`,
   `student_parent_child_care_exception_applies`). This is the same "flatten every clause into a
   locally-scoped `WHERE`, name it, cite it" discipline this project's own house style already
   favours for `.l4` corpus files — RuleSpec just makes each such name a top-level, independently
   addressable identifier with its own `source:` pincite, which is stricter than L4 requires today.
2. **The identifier names are themselves the explanation.** There is no separate template layer
   (contrast DataLex's `@nlg`-free but structurally-generated explanations, or this project's own
   `@nlg` annotations) — `student_ineligible_for_snap_participation`'s formula reads, in
   `and`/`or`/`not` over named booleans, almost exactly as an English sentence would, because the
   identifiers were chosen to make it so. This is closer to Logical English's philosophy
   (`LOGIC-PROGRAMMING-BACKENDS-SPEC.md` §1.4) than to a typical programming-language variable
   name.

## D. Stratum-by-stratum overlap (RuleSpec)

| L4 stratum                                                        | RuleSpec construct                                                                                                                                                                                                                       | Verdict                                                       |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Constitutive core, boolean `DECIDE`/`MEANS` over `AND`/`OR`/`NOT` | `kind: derived`, `dtype: Judgment`, `formula:` — a small expression language over named identifiers with `and`/`or`/`not`/comparisons                                                                                                    | **CLEAN**                                                     |
| Named constants / `@desc`-style parameters                        | `kind: parameter` rules — a name, a `dtype` (`Count` observed; presumably `Amount`, `Rate` etc.), a `source:` pincite, a literal `formula:`                                                                                              | **CLEAN**                                                     |
| `NUMBER` (exact rational), currency rounding                      | dedicated `rounding` config on numeric rules (`half_up\|half_even\|floor\|ceil`, per the engine README) — an explicit, named rounding-mode discipline, which is more honest than most execution targets researched so far                | **CLEAN, and stricter than us**                               |
| `DATE`, effective-dated rule versions                             | `versions:` is a list, each with its own `effective_from:` and `formula:` — directly the shape of L4's own `EVAL … UNDER RULES EFFECTIVE AT` temporal axis (`temporal-rule-version.md`)                                                  | **CLEAN, strongest structural match found in this programme** |
| Records/enums, typed data                                         | `entity: Person` (an entity-typed subject, OpenFisca-style) but no evidence of a general record/product type beyond the entity tag itself                                                                                                | **RESTRICTED, unconfirmed**                                   |
| `@ref` citation/provenance                                        | `source:` on every single rule, plus a separate `metadata.proof.atoms[].source.corpus_citation_path` — a **two-tier** citation discipline (a human pincite and a machine-resolvable corpus path) stronger than this project's own `@ref` | **CLEAN, and stricter than us**                               |
| Fork/ambiguity register                                           | not found — `known-validation-gaps.yaml` and `known-dangling.yaml` in `rulespec-us` track encoding debt, not competing legal readings                                                                                                    | **OUT (different concept)**                                   |
| `PARTY p MUST/MAY/SHANT`, deontic layer                           | none found — RuleSpec concludes numeric/boolean facts (eligibility, amounts), not obligations                                                                                                                                            | **OUT**                                                       |
| `HENCE`/`LEST`, effects/ledger                                    | none found                                                                                                                                                                                                                               | **OUT**                                                       |
| `#TRACE` / audit-grade explanation                                | the engine's `explain` execution mode returns a trace; the identifier-as-explanation discipline in §C also does real work here                                                                                                           | **CLEAN**                                                     |
| Recursion, higher-order functions                                 | not established either way this session — the formula language's full grammar was not read in the engine source, only inferred from examples                                                                                             | **UNKNOWN**                                                   |

## E. Family placement

**RuleSpec belongs in the execution family**, alongside OpenFisca and Catala
(`BACKEND-PORTFOLIO-SPEC.md` §1.1, "run the law") — it compiles to a real runtime (Rust/WASM) and
actually executes, unlike the interchange-family targets (DMN, LegalRuleML) which only assert
schema validity. Its nearest sibling is **OpenFisca** by subject-matter (both are tax-and-benefit
microsimulation formats) but its design is closer in spirit to **Catala** by rigour (explicit
citations, explicit rounding modes, an `explain` trace mode as a first-class execution mode rather
than a debugging afterthought). It should be census'd as its own row, not folded into the
OpenFisca row, because the format is genuinely different (RuleSpec's per-rule citation-and-version
discipline is stricter and differently shaped than OpenFisca's Variable-class-plus-YAML-parameter
convention) even though the domain overlaps heavily.

**PolicyEngine is not a new census row.** It is evidence that the existing, shipped OpenFisca
bridge (`BACKEND-PORTFOLIO-SPEC.md` §2.1) already targets an architecturally adjacent ecosystem —
worth a one-line note on that row, not a new one, unless a future session actually verifies
PolicyEngine-specific divergence from upstream OpenFisca (parameter file layout, entity
conventions, a PolicyEngine-only extension) that the existing emitter would need to accommodate.

## F. Feasibility, if ever pursued

Not scoped as a real proposal — no ruling ladder here, nothing is committed. Noted for whoever
picks this up:

- **The fragment needed is almost exactly L4's exportable core** (`BACKEND-PORTFOLIO-SPEC.md` §5):
  first-order boolean/arithmetic `DECIDE`/`MEANS` chains, no records beyond an entity tag, no
  regulative layer, no effects. This is a narrower ask than OpenFisca's own bridge already
  satisfies, so a RuleSpec emitter is plausibly a **thinner** build than any backend shipped to
  date, if the formula-language grammar turns out to be as small as the worked example suggests.
  This session did not read the engine's grammar/parser source, so "plausibly thinner" is an
  estimate, not a measurement — the first real step for a future session is reading
  `axiom-rules-engine`'s formula parser to confirm the operator set (comparisons, arithmetic,
  `and`/`or`/`not` — is there a ternary/`if`? string handling? list/set operations?).
- **The temporal match is the headline reason to prioritise this over other backlog items.**
  Every other execution-family target either lacks a temporal axis entirely (Catala, MLIR) or
  treats dates as a lossy afterthought (LegalRuleML's paired-point-events, per the sibling memo).
  RuleSpec's `versions[]`/`effective_from` is structurally the same shape as L4's own
  `EVAL … UNDER RULES EFFECTIVE AT` (`temporal-rule-version.md`), which makes this the first
  researched export target where L4's temporal layer would not need re-encoding into a foreign
  shape — it already speaks the same idiom.
- **A real differential oracle is buildable and, unusually, already partly exists upstream.**
  Axiom's own pipeline validates every RuleSpec encoding against PolicyEngine and TAXSIM before
  publication (§B above). A hypothetical L4→RuleSpec emitter inherits this for free on the
  `rulespec-us` side: disagreement between L4's evaluator and the compiled RuleSpec artifact, on
  the same `#EVAL` corpus this project already differentials every other execution bridge against
  (I2, `BACKEND-PORTFOLIO-SPEC.md` §4), would be independently checkable against a
  third engine (PolicyEngine) that neither L4 nor RuleSpec's own authors control. That is a
  stronger validation posture than any backend in this census enjoys today.
- **Domain narrowness is the real constraint, not technical difficulty.** RuleSpec is scoped to
  tax-and-benefit law, same as OpenFisca. A hypothetical emitter's value is bounded by how much of
  this project's own corpus is in that domain (Reg CF, the BNA, the housing-act and charities
  corpora are not) — this is a narrow-but-deep opportunity, not a general-purpose backend.
- **AI-assisted generation is Axiom's ingestion story, not an interop feature.** `axiom-encode`
  drafts RuleSpec from statute text; a future L4↔RuleSpec bridge would not use this (L4 already has
  its own ingestion story) — it is worth reading only as a second data point (after this project's
  own LLM-ingestion pipelines) on how another team scopes and gates AI-assisted legal encoding
  (their gate: agreement with an independent oracle before publication, tracked via named,
  CI-enforced "known gap" lists that may only shrink).

## G. Sources

**Primary, read directly in this session [E]:** `axiom.org/about`; `axiom.org/blog/axiom-launch`;
`axiom.org` (home); `github.com/TheAxiomFoundation` (org repo listing);
`github.com/TheAxiomFoundation/axiom-rules-engine` (README: format, compilation targets, license);
`github.com/TheAxiomFoundation/rulespec-us` (README: directory layout, identifier scheme, gap
lists, license, commit/issue/PR counts); `github.com/PolicyEngine/policyengine-us` (README:
license, install requirements) and its `policyengine_us/` top-level directory listing (`variables/`,
`parameters/`, `entities.py`, `system.py` — read via the GitHub contents API);
`github.com/orgs/PolicyEngine/repos` (full org repo listing, confirming `policyengine-core`'s own
description: "Forked from OpenFisca-Core").

**Primary code, downloaded and read in full [E, code]:**
`raw.githubusercontent.com/TheAxiomFoundation/rulespec-us/main/us/statutes/7/2015/e.yaml` (300
lines, read in two passes) — the source of every quotation in §C.

**Not independently verified this session [U]:** whether PolicyEngine's `variables/`/`parameters/`
shape still matches current upstream OpenFisca closely enough for L4's existing OpenFisca emitter
output to load without modification; RuleSpec's full formula-language grammar (only the operators
visible in one worked example were observed — `and`, `or`, `not`, `>=`, `<`, `>`, identifier
reference, integer/decimal literals); PolicyEngine's legal/nonprofit structure beyond what its
GitHub org states; whether Axiom's `axiom-compose` "deterministic program composer" is a distinct
IR from RuleSpec proper or a downstream stage of it.

**Related work already in this repo, for cross-reference:** `RULEMAPPING-RUML-RESEARCH.md` (the
sibling memo, same request); `LEGALRULEML-RESEARCH.md` and `DATALEX-YSCRIPT-RESEARCH.md` (the two
prior export-format research memos, same evidence-mark convention);
`BACKEND-PORTFOLIO-SPEC.md` §2.1 (Execution census, where this memo's RuleSpec row and the
OpenFisca/PolicyEngine cross-reference note are added) and §5 (the exportable core, against which
§F above sizes the RuleSpec fragment); `temporal-rule-version.md` (the L4-side temporal axis
RuleSpec's `versions[]` structurally matches).
