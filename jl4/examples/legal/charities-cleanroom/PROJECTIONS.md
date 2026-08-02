# Projections of the cleanroom charity-test corpus

What the L4 → DMN / BPMN pipeline did with `charity-test.l4`, measured 2026-08-02, and
what it could not do. This is a **smoke test of the exporter**, not a golden: the corpus
was written cleanroom against jerseylaw.je with no sight of the pipeline, so every place
the pipeline stumbles here is a place it would stumble on a corpus it had not been tuned
for. The stumbles are the product.

Nothing here is queued or merged.

**Status: the emitted DMN does not execute on either engine.** Two decisions carry L4 list
quantifiers the exporter has no FEEL form for; both are Blocking in the fidelity report,
and both engines refuse the file. §3 has the verbatim banners; §4 isolates the cause and
measures what would happen if only that were fixed. The answer to §4 is the finding.

---

## 1. What was produced

| artifact                            | what it is                                                     |
| ----------------------------------- | -------------------------------------------------------------- |
| `projections/charity-test.dmn`      | DMN 1.3 XML, `camunda` flavor                                   |
| `projections/charity-test.fidelity.txt` | what the XML target could not carry                         |
| `projections/charity-test.dmn.md`   | the same module as dmnmd markdown — **three lines, no tables**  |
| `projections/charity-test.md.fidelity.txt` | what the markdown target could not carry — a longer list |
| `charity-test.cases.json`           | 25 worlds × 40 decisions = 1000 pins, all L4-evaluated (§2)     |
| `projections/make-cases.py`         | regenerates the cases file from the corpus and the emitted DMN  |
| `projections/probe-feel-quantifier.dmn` | the §4 cause-isolation probe — **hand-patched, not emitted** |
| `projections/evidence/`             | the raw output of every check quoted below                      |

Engine logs in `evidence/` have their oversized `EVAL context {…}` / `SVC … -> {…}` echo lines
truncated to 90 characters; those lines repeat the case context verbatim from
`charity-test.cases.json`, and no engine *answer* was removed. Every `VERDICT` banner is
untouched.

Commands (from the repo root, with `JL4_LIBRARY_PATH=$PWD/jl4-core/libraries`):

```sh
D=jl4/examples/legal/charities-cleanroom
l4 export $D/charity-test.l4 --to dmn    --fidelity-report -o $D/projections/charity-test.dmn
l4 export $D/charity-test.l4 --to dmn-md --fidelity-report -o $D/projections/charity-test.dmn.md
l4 export $D/charity-test.l4 --to bpmn   --fidelity-report -o /dev/null   # exits 1, see §5

npx --yes --package=dmn-moddle node etc/validate-dmn.mjs $D/projections/*.dmn

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  etc/kie-dmn-check/run.sh     $D/projections/charity-test.dmn --cases $D/charity-test.cases.json
env -u JAVA_HOME \
  etc/camunda-dmn-check/run.sh $D/projections/charity-test.dmn --cases $D/charity-test.cases.json
```

### Export stats

|                          | value                                                              |
| ------------------------ | ------------------------------------------------------------------ |
| decisions emitted        | **40**                                                              |
| **decision tables**      | **0**                                                               |
| boxed literal expressions | **40**                                                              |
| businessKnowledgeModels  | 1 (`the purpose is a charitable purpose`)                           |
| decisionServices         | 3 (all grouping-only)                                               |
| `inputData`              | 2 (`entity`, `purpose`)                                             |
| `itemDefinition`         | 4 (`Purpose` 26 components, `Constitution` 8, `PublicBenefitFinding` 8, `Entity` 6) |
| informationRequirements  | 75                                                                  |
| fidelity (XML)           | **2 blocking, 1 lossy, 101 advisory**                               |
| fidelity (markdown)      | **42 blocking**                                                     |
| dmn-moddle metamodel gate | `OK` on both the emitted file and the probe                        |

### Fidelity summary

XML target:

| code                    | severity  | n   | what it says                                                    |
| ----------------------- | --------- | --- | ---------------------------------------------------------------- |
| `D-LITERALEXPR`         | blocking  | 2   | `any` / `all` over a list; body could not be rendered as FEEL, raw L4 emitted |
| `D-ITEMDEF`             | lossy     | 1   | `Entity.purposes` is `LIST OF Purpose`; emitted `typeRef="Any"` because no collection itemDefinition is minted |
| `D-LITERALEXPR`         | advisory  | 39  | not a guarded chain, so no rows — a boxed FEEL literal, outside the analysable fragment |
| `D-FIXTURE`             | advisory  | 49  | the 25 scenarios and their 24 helpers, dropped at population time |
| `D-INERT`               | advisory  | 4   | the Article 1 / 2(4) / 2(6) / 2(7) prose carriers                 |
| `D-FLAVOR-NOSERVICE`    | advisory  | 3   | the three § services are grouping-only on the camunda flavor      |
| `D-SVCEMPTY`            | advisory  | 2   | `Scenarios` (all members dropped) and the interpretation § (no encapsulated member) |
| `D-PARAM-AS-INPUT`      | advisory  | 2   | `entity` (17 decisions) and `purpose` (21) merged to global inputs |
| `D-BKM` / `-CONSUMERS`  | advisory  | 1+1 | one tier-2 function, with the BKM-less-consumer caveat            |

Markdown target: `D-MD-NOLITERAL` × 40, `D-MD-NOBKM` × 1, `D-MD-NODRG` × 1 — i.e. **every
single decision**, plus the function, plus the 75 edges between them. `charity-test.dmn.md`
is a title and a comment.

---

## 2. The cases file

25 worlds. Each is an (entity, purpose) pair, because `D-PARAM-AS-INPUT` merged the two
`GIVEN` parameters into two global `inputData` — so a DMN world fixes one entity **and** one
purpose. Coverage: both carve-outs both ways (6(2)(c) sport gate ×2, 6(2)(d) recreation gate
×2), the 6(2)(a) widening, the 6(2)(f) deeming, 6(5) at both its reaches, A9 attached and
unattached, A10 vacuity with and without the benefit limb, A11 applicant and dormant, the
7(3)(b) bar, the A7 non-defeater, both A8 procedural divergences, and all four 5(2)/5(3)
limbs.

There are **no boundary pairs**, and that is inherited, not an omission: the corpus has no
dated constant and no monetary threshold, so nothing for `RULES EFFECTIVE DATE` to select
over. The FEEL date fix in the binary used here is therefore exercised by nothing in this
subject — the corpus renders no date at all.

**Every pin is L4-evaluated.** `projections/make-cases.py` appends one `#EVAL` per (world,
decision) to a copy of the corpus, runs `l4 --json`, and zips the results back against its
own plan; the contexts come from `#EVAL <the entity>` / `#EVAL <the purpose>` and are only
re-keyed, using the FEEL component names read out of the emitted DMN's own
`itemDefinition`s. Keys are the emitter's, values are the evaluator's. The only
hand-authored content is which pair each world probes.

---

## 3. Both engines: verbatim

`etc/validate-dmn.mjs` (dmn-moddle metamodel gate) — `projections/evidence/validate-dmn.txt`:

```
OK    jl4/examples/legal/charities-cleanroom/projections/charity-test.dmn
       40 decision(s): 0 table(s), 40 literal expression(s); 2 inputData; 1 diagram(s)
OK    jl4/examples/legal/charities-cleanroom/projections/probe-feel-quantifier.dmn
       40 decision(s): 0 table(s), 40 literal expression(s); 2 inputData; 1 diagram(s)
```

KIE — `projections/evidence/kie.txt`:

```
XSD    valid
VALID  2 error(s), 0 warning(s)
       ERROR [ERR_COMPILING_FEEL] DMN: Error compiling FEEL expression 'any OF `the purpose is a charitable purpose`, (entity's purposes)' for name 'the_entity_has_at_least_one_charitable_purpose' on node 'the_entity_has_at_least_one_charitable_purpose': syntax error near 'OF' (DMN id: decision_the_entity_has_at_least_one_charitable_purpose_literal, Error compiling the referenced FEEL expression)
       ERROR [ERR_COMPILING_FEEL] DMN: Error compiling FEEL expression '... "(a) all of its purposes are –" AND all OF (GIVEN purpose IS purpose254 YIELD `the purpose is charitable, or purely ancillary or incidental` OF entity, purpose), (entity's purposes)' for name '_5_1_a_all_of_its_purposes_are_charitable_or_ancillary' on node '_5_1_a_all_of_its_purposes_are_charitable_or_ancillary': syntax error near '..' (DMN id: decision__5_1_a_all_of_its_purposes_are_charitable_or_ancillary_literal, Error compiling the referenced FEEL expression)
BUILD  2 error(s) / 2 message(s)

KIE 8.44.0.Final VERDICT: 1 file(s), 0 case(s), 4 error(s), 0 warning(s), 0/0 decision(s) SUCCEEDED, 0/0 value(s) as expected, 0/0 service output value(s) as expected   <<< FAILED
```

Camunda — `projections/evidence/camunda.txt`:

```
PARSE  INVALID: FEEL expression: failed to parse expression 'any OF `the purpose is a charitable purpose`, (entity's purposes)': Expected (binaryComparison | between | instanceOf | in | "and" | "or" | end-of-input):1:5, found "OF `the pu"
FEEL expression: failed to parse expression '... "(a) all of its purposes are –" AND all OF (GIVEN purpose IS purpose254 YIELD `the purpose is charitable, or purely ancillary or incidental` OF entity, purpose), (entity's purposes)': Expected (start-of-input | ifOp | forOp | quantifiedOp | disjunction):1:1, found "... \"(a) a"

Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s), 0 case(s), 0 parsed, 1 error(s), 0/0 decision(s) evaluated, 0/0 value(s) as expected   <<< FAILED
```

Two independent engines, two independent front ends, **the same two nodes**. The refusal is
loud on both, which is the right failure: the fidelity report predicted both at Blocking
before either engine was run.

---

## 4. Cause isolation: the two nodes are the whole blocker, and fixing them naively is worse

`projections/probe-feel-quantifier.dmn` is `charity-test.dmn` with **exactly two `<text>`
bodies replaced by hand**, and nothing else touched:

| node                                              | emitted (raw L4)                                          | probe (FEEL)                                                     |
| ------------------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------- |
| `the_entity_has_at_least_one_charitable_purpose`  | ``any OF `the purpose is a charitable purpose`, (entity's purposes)`` | `some p in entity.purposes satisfies the_purpose_is_a_charitable_purpose(purpose: p, …)` |
| `_5_1_a_all_of_its_purposes_are_charitable_or_ancillary` | `... "(a) all of its purposes are –" AND all OF (GIVEN purpose IS purpose254 YIELD …)` | `every p in entity.purposes satisfies the_purpose_is_charitable_or_purely_ancillary_or_incidental` |

It is a **probe, not an emitter output**, and it is committed only as evidence for what
follows. Measured on the same 25-case file, verbatim:

```
KIE 8.44.0.Final VERDICT: 1 file(s), 25 case(s), 0 error(s), 0 warning(s), 1000/1000 decision(s) SUCCEEDED, 993/1000 value(s) as expected, 124/125 service output value(s) as expected   <<< FAILED
```

```
PARSE  ok: Charities (Jersey) Law 2014 — the charity test (40 decision(s))
Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s), 25 case(s), 1 parsed, 0 error(s), 1000/1000 decision(s) evaluated, 993/1000 value(s) as expected   <<< FAILED
```

Two findings, and the second is the important one.

**(a) Those two nodes are the entire blocker.** Patch them and the other 38 decisions,
the BKM, all 75 requirement edges and all three decision services build and run on both
engines, 1000/1000 evaluated. Nothing else in a 1472-line cleanroom corpus troubles either
engine.

**(b) The obvious fix is a silent wrong answer.** Both engines agree on 993/1000, and both
disagree with L4 on the *same seven pins*, in the *same three worlds*:

| world                                                    | pins wrong |
| -------------------------------------------------------- | ---------- |
| `the poverty trust with a charity shop` (2 purposes)      | 5 + 1 service output |
| `the poverty trust with a party-political object` (2)     | 1 |
| `the poverty trust with incidental campaigning` (2)       | 1 |

Every wrong world is one whose entity holds **more than one purpose**. The cause is visible
in the emitted BKM:

```xml
<formalParameter name="purpose" typeRef="Purpose"/>
<formalParameter name="_5_the_purpose_is_excluded_as_political" typeRef="boolean"/>
<formalParameter name="the_purpose_falls_within_paragraph_1" typeRef="boolean"/>
<text>the_purpose_falls_within_paragraph_1 and not(_5_the_purpose_is_excluded_as_political)</text>
```

The body **never reads `purpose`**. Its two λ-lifted parameters are the whole body, and every
call site binds them `name: name` to the global decisions — which read the *global* `purpose`
input. So `the_purpose_is_a_charitable_purpose(purpose: p, …)` is **constant in `p`**: the
quantifier's bound variable is inert. `_5_1_a_…` is worse still — the quantified body is a
plain decision, so `p` is not even mentioned.

This is the same λ-lift-to-globals hazard the Reg CF corpus recorded on
`the_over_limit_investor_case_qualifies`, but here it lands on the one mechanism a list
quantifier would have to use. **`D-PARAM-AS-INPUT` is unsound, not merely lossy, when the
call site's argument is a bound variable rather than a module-level expression** — and today
that unsoundness is masked by an unrelated refusal in the enclosing body. Fix the FEEL
lowering without fixing the binding and the refusal becomes a wrong answer.

Note also what nearly hid it: **22 of 25 worlds agree**, because in a single-purpose entity
the global `purpose` happens to equal the sole list element. Only the mixed-list worlds
separate the two readings. A case file built from one-purpose entities would have reported
1000/1000 and certified a broken lowering.

### The pipeline gaps this run found

1. **No FEEL form for `any` / `all` over a list.** *(blocking; both engines)* FEEL has
   `some x in xs satisfies e` and `every x in xs satisfies e`, so the target notation is not
   the obstacle. §4(b) is the reason it is not a one-line fix.
2. **`D-PARAM-AS-INPUT` is unsound under a binder.** *(latent; would surface the moment (1)
   lands)* Un-lifting a parameter to a global input is only meaning-preserving when every
   call site passes the same module-level expression. A call site inside a `GIVEN … YIELD`
   lambda passes the bound variable, and the merge silently substitutes the global. A
   decision applied under a binder must classify as tier 2, and its λ-lifted free references
   must be re-parameterised, not bound `name: name`.
3. **`LIST OF T` has no itemDefinition.** *(lossy, `D-ITEMDEF`)* `Entity.purposes` is emitted
   `typeRef="Any"`. `isCollection` is an attribute of `tItemDefinition`, so a collection needs
   an itemDefinition of its own. Both engines accepted the JSON array anyway, so this is a
   type-information loss rather than a runtime one — for now.
4. **A wholly constitutive statute lowers to ZERO decision tables.** *(advisory ×39, but
   structural)* Every one of the 40 decisions is a boxed literal expression, because
   `GuardedRows` normalises `IF` / `BRANCH` / `CONSIDER` and this cluster has none of them —
   it is AND/OR chains all the way down, which is what a definitional test *is*. So the
   entire DMN gap/overlap/consistency analysis reaches nothing here, and the dmnmd markdown
   projection is empty (42 blocking). Reg CF got 12 tables out of 67 decisions; this corpus
   gets 0 out of 40. **The exporter's analysable-fragment yield is a property of the statute's
   drafting style, not of the encoding effort** — and a conjunctive/disjunctive statute is the
   worst case. If DMN tables are to carry this kind of law, an And/Or chain over booleans
   needs a table lowering (e.g. one row per disjunct under `hitPolicy="ANY"`, or `COLLECT`),
   which does not exist today.
5. **A gensym leaks into the artifact.** *(cosmetic, inside a Blocking body)* The raw-L4
   fallback prints `GIVEN purpose IS purpose254` — an internal renaming counter. Harmless
   while the body is unevaluable; it should not survive into a body that is.
6. **`etc/validate-dmn.mjs` passes XML that is not well-formed.** *(latent gate gap; found
   by accident, then re-measured deliberately)* While annotating the probe I wrote an XML
   comment containing `--`, which XML forbids. Measured on that file
   (`projections/evidence/xmllint-vs-moddle.txt`):

   | checker | verdict |
   | --- | --- |
   | `xmllint --noout` | `parser error : Double hyphen within comment`, exit 1 |
   | Camunda 8.7.6 | `PARSE INVALID: … DmnModelException: Unable to parse model` |
   | KIE 8.44 harness | no output at all, exit 1 |
   | `etc/validate-dmn.mjs` (dmn-moddle/saxen) | **`OK` — 40 decision(s), 0 warnings** |

   The script's own header warns it is a metamodel check and not an import check, but this
   is weaker still: it accepted a file that is not XML. Today the emitter writes no comments,
   so nothing live is at risk; the gate is simply not the well-formedness backstop a reader
   might take `OK` to mean. The Xerces leg of `etc/kie-dmn-check` is the one that catches
   this class, which is the same asymmetry the DMN README already records for XSD ordering.

---

## 5. BPMN, and the state-graph leg

Both refuse, and both refusals are correct:

```
$ l4 export …/charity-test.l4 --to bpmn --fidelity-report
No regulative rules found in module — nothing to export as BPMN          (exit 1)

$ l4 state-graph …/charity-test.l4
No regulative rules found in module                                     (exit 1)
```

That is the corpus telling the truth about its subject. Articles 5–7 are wholly
constitutive: they say when a state of affairs **obtains**, never who must do what by when.
There is no `PARTY`/`MUST`/`WITHIN` in the file, so there is no process to draw and no
labelled transition system to explore — not a missing encoding, an absent one. The corpus
header says so at lines 41–45, independently of this run.

The officer-power material that *would* carry deontics — Article 5(4)–(8) and 7(4), the
guidance-publication machinery, and the whole of Parts 2 and 4–7 (registration,
deregistration, misconduct, required steps, the tribunal) — is out of the cleanroom scope.
**The LTS / BPMN leg of this subject is unexercised, and cannot be exercised without
extending the corpus into Part 4 or Part 5.** No BPMN artifact is committed, because none
was produced.

---

## 6. Cleanroom integrity for this stage

This stage read: the corpus and its two sibling documents; `jl4/examples/dmn/README.md` and
`jl4/examples/dmn/regcf-corpus.cases.json` (both explicitly permitted as the pattern to
follow); `etc/validate-dmn.mjs`, `etc/kie-dmn-check/run.sh`, `etc/camunda-dmn-check/run.sh`;
and its own emitted artifacts. No path matching `*charit*` outside this directory was opened,
no lexipedia resource was fetched, no probe or comparison document was read, and no
charity-term grep was run. No new contamination to disclose; the encoder's disclosed leak
(`references/drafting-patterns.md` naming a prior Part 6 encoding) is unchanged by this stage
and was not followed up.
