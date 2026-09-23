# BNA smoke test — pipeline report

**Date:** 2026-08-02. **Subject:** British Nationality Act 1981 s 1, encoded de novo (the G2
subject, "as is traditional" — Sergot et al., CACM 29(5), 1986). **Purpose:** smoke-test the demo
pipeline by hand, stage by stage, so that what was done here becomes the requirements document for
the `go` orchestrator's scaffolded stages. All L4 evaluation used the prebuilt `l4` binary from the
R12/R13 tree; no `cabal` was run.

## 1. What ran end to end

### The L4 leg — ran end to end, green

```
JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check jl4/examples/legal/bna/bna.l4   # exit 0, "Check succeeded."
JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 run   jl4/examples/legal/bna/bna.l4   # exit 0
```

42 `#ASSERT` + 1 `#EVAL`: the run log carries **84 `assertion satisfied` lines (each satisfied
assertion prints twice) and 0 `assertion failed` lines**. The `#EVAL` answers
`` `section 1 outcome at birth` `Peter` `` = `` `a British citizen from birth under subsection (1)` ``.
Assert-greenness is asserted here from **log content, not exit code** — see §3.2 for why the exit
code alone would be a false-green vector.

### The projection leg — emitted, zero blocking notes

`l4 export bna.l4 --to dmn -o bna.dmn --fidelity-report --flavor camunda` (exit 0) produces
`bna.dmn`: 43 decisions, three inputData (`person`, `adoption`,
`entitled_under_subsection_3_3A_or_4` — the D-PARAM-AS-INPUT un-lifting), one decision table (the
`BirthOutcome` cascade, FIRST hit policy). `bna.fidelity.txt` records **78 advisory notes and zero
blocking** ones. The `dmn-md` projection (`bna.dmn.md`) is **header-only**: 42 decisions are
literal expressions (D-MD-NOLITERAL) and the one decision table is dropped too (D-MD-CELLSYNTAX —
its output strings carry parentheses), so this corpus has no markdown shadow at all.

**As first measured (2026-08-02), it was not zero.** The dated constants `commencement`,
`the_appointed_day` and `the_relevant_day` emitted raw L4 (`YMD OF 1983, 1, 1`) with no FEEL
rendering — 3 blocking D-LITERALEXPR — and both engines refused the whole file. That is the history
recorded below, kept because the isolation move that pinned it is a reusable technique and because
the "0 of 1075 pins compared" arithmetic is the point of §3.1. The exporter fix landed in
legalese/l4-ide#196 and these artifacts were regenerated on it.

### The execution leg — both engines green on the shipped artifact

Cases: `bna.cases.json`, 25 cases x 43 expect pins, every pin derived from the L4 source by a
979-`#EVAL` probe run of the prebuilt binary (activation contract; the same run satisfied all 42
`#ASSERT`s), cross-checked in the generator against 18 `#ASSERT` ground truths — never from an
engine's output. The cases file has not been touched since; only the artifact under it changed.

Verbatim final banners on the **emitted** `bna.dmn`, re-measured 2026-08-03 after regeneration
(exit codes captured by redirect-then-echo):

```
KIE 8.44.0.Final VERDICT: 1 file(s), 25 case(s), 0 error(s), 0 warning(s), 1075/1075 decision(s) SUCCEEDED, 1075/1075 value(s) as expected, 325/325 service output value(s) as expected
Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s), 25 case(s), 1 parsed, 0 error(s), 1075/1075 decision(s) evaluated, 1075/1075 value(s) as expected
KIE on emitted bna.dmn: exit=0
Camunda on emitted bna.dmn: exit=0
```

The three literals now read `date("1983-01-01")` / `date("2002-05-21")` / `date("2010-01-13")` —
i.e. the emitter now writes exactly what the cause-isolation scratch had to be hand-edited to say.

#### The refusal that used to be here, and how it was pinned

Verbatim final banners on the pre-#196 `bna.dmn` (2026-08-02):

```
KIE 8.44.0.Final VERDICT: 1 file(s), 0 case(s), 6 error(s), 0 warning(s), 0/0 decision(s) SUCCEEDED, 0/0 value(s) as expected, 0/0 service output value(s) as expected   <<< FAILED
Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s), 0 case(s), 0 parsed, 1 error(s), 0/0 decision(s) evaluated, 0/0 value(s) as expected   <<< FAILED
```

Representative refusal lines (all three date constants failed identically):

```
ERROR [ERR_COMPILING_FEEL] DMN: Error compiling FEEL expression 'YMD OF 1983, 1, 1' for name 'commencement' on node 'commencement': syntax error near 'OF' (DMN id: decision_commencement_literal, Error compiling the referenced FEEL expression)
PARSE  INVALID: FEEL expression: failed to parse expression 'YMD OF 1983, 1, 1': Expected (binaryComparison | between | instanceOf | in | "and" | "or" | end-of-input):1:5, found "OF 1983, 1"
```

Cause isolation: a scratch copy of `bna.dmn` with **only** those three `<text>` literals rewritten
to FEEL date literals went fully green on both engines against the same cases file — 1075/1075 and
325/325, both exit 0. That prediction is what the regenerated artifact above now discharges without
a hand edit, at the same numbers.

**Honest status:** the L4 encoding runs end to end, and the shipped DMN artifact executes on both
engines with zero value mismatches over all 1075 pins. What the run does not cover is unchanged and
is listed in §3 — no deployment-time validation, no Modeler import, and the `dmn-md` shadow is
still empty for this corpus.

## 2. Stage ledger — what was done by hand, and what the real stage therefore needs

**p1-ingest.** By hand: fetched the legislation.gov.uk revised text of s 1 (banner: "up to date
with all changes known to be in force on or before 04 July 2026") via Wayback Machine captures,
because legislation.gov.uk itself sat behind an AWS WAF challenge; assembled `source-s1.txt` with a
provenance header, the verbatim section text with its F1–F19 amendment and C1–C5 modification
annotations, and a s 50 definitional annex. The real stage needs: input = an act/section citation;
output = exactly such a provenance-headed source artifact; requirements = an archive-fallback fetch
strategy, capture of the in-force banner, and preservation of the F/C annotation inventory —
downstream stages consume the annotations, not just the words (see p2).

**p2-sweep.** By hand: the scope decision — which subsections become predicates, which statutory
concepts arrive as `@ref` input fields (settled, armed forces, s 10A, good character), which
modifications are encoded (C3, as the grant gate) and which scoped out (C1/C4/C5, and — only after
review — C2). The measured lesson is defect §3.5: the human sweep disposed of four of the five
C-annotations and silently dropped one. The real stage needs: input = the annotated source; output
= a **complete disposition table over the annotation inventory** — every F and C key either cited
in the encoding or named in a scope-out — and that completeness must be machine-checked, because
"reviewer reads the source again" is exactly what failed.

**p3-encode.** By hand: `bna.l4` — inert-style isomorphic encoding, verbatim rule text riding
inline as inert prose, one `GIVEN` record per subject, zero top-level `ASSUME`, 42 asserts with
boundary pairs at each statutory day. Checked and run with the prebuilt binary. The real stage
needs: the l4 skill's inert-style guidance as the prompt substrate; `JL4_LIBRARY_PATH` pinned; and
its green gate must parse the run log for `assertion failed` rather than trust exit 0 (§3.2).

**p4-forks.** By hand: 12 ambiguities recorded as `-- AMBIGUITY:` comments at their sites, each
with both readings, the reading taken, and why; mirrored as the A1–A12 register in `README.md`.
Ruling **R4** (formal fork representation) is deliberately unruled, and this register is the
measured fork inventory that ruling should be made against: 12 forks over one section, all resolved
at encode time by an argued choice, none requiring runtime forking; and one of the 12 drifted from
the exact marker syntax so a convention scan found 11 (§3.7). The real stage therefore needs: R4 to
specify a **machine-checkable fork syntax** (the prose-convention marker is an interface, and it
already broke once), plus the both-readings/reading-taken/why fields this register shows every fork
naturally has.

**p5-gate.** By hand: an adversarial review of the encode and execute outputs, which confirmed 8
defects — including two the encoding stages could not have caught about themselves: a
fabricated-looking pinpoint citation whose exposure required fetching the actual 1986 CACM paper
(§3.3), and a test comment attributing a negative to a conjunct the fixture never isolated,
exposed by conjunct-level evaluation (§3.6). The real stage needs: (a) verify every provenance
claim against the fetched source it cites, treating quotation marks and pinpoint cites as claims to
be string-checked, not decoration; (b) for every negative assert whose comment names a cause, check
the cause is not overdetermined; (c) run the p2 completeness check and the p4 marker-conformance
scan. Disposition rule, applied here: legal-fidelity defects are fixed by making the encoding match
the statute and re-running everything the fix touches — never by weakening a test.

**p8-verify.** By hand: DMN export with fidelity report; cases generated from the L4 source under
the activation contract (pins from a 979-`#EVAL` probe, cross-checked against `#ASSERT` truths;
symmetric check — every decision in the DMN pinned in every case); both engines run; the whole-file
refusal measured; the cause isolated by a minimal 3-line scratch edit and the pins value-proven
1075/1075 on both engines. The exporter fix that isolation called for landed (§3.1) and the
artifacts were regenerated on it, so the shipped file now executes at those same numbers. The real
stage needs: banner-content gating rather than exit-code gating for the L4 legs (§3.2); and the
isolation-scratch move — rerun with the smallest possible edit to attribute a refusal — as a
standard debugging step, because "3 of 43 decisions lost" and "0 of 1075 pins compared" are the
same defect at two very different severities.

## 3. What broke or surprised

1. **Both engines refused the emitted DMN whole-file** on the three dated constants
   (D-LITERALEXPR, banners in §1). DMN has no partial-file execution on either engine, so three
   unrenderable expressions zeroed out all 1075 pins rather than losing 3/43 decisions. **Fixed in
   the exporter** (legalese/l4-ide#196): `YMD y m d` lowers to FEEL `date("YYYY-MM-DD")` for
   standalone dated constants — the regcf corpus never hit this only because its rule-version axis
   turned dated constants into guarded interval tables. The isolation run had proved this was the
   sole blocker, and regenerating these artifacts on the fixed exporter confirmed it: 1075/1075 on
   both engines with no hand edit.
2. **`l4 run` exits 0 when an assertion fails.** Measured on a scratch copy with one assert
   negated: the log carries `Severity: DiagnosticSeverity_Error` / `Result: assertion failed`, yet
   the process exits 0 (a syntactically broken file exits 1, so the exit code is meaningful for
   parse errors and blind to assert failures specifically). **Requirement (open):** any
   exit-code-gated pipeline stage will false-green; the orchestrator must gate on log content, or
   `l4` needs a strict exit-on-assert-failure mode. Every green claim in this report is
   log-content-gated for exactly this reason.
3. **The Sergot fixture's provenance was partly fabricated** (confirmed major): the paper's Peter
   was born **3 May 1983**, not 3 Aug; the cited "§2.1" does not exist (the paper uses named
   headings); the quoted phrase appears nowhere in it. Caught only by fetching the CACM PDF and
   text-extracting it. **Fixed:** date corrected in fixture and cases (outcome-neutral — both dates
   satisfy s 1(1); re-verified green), citation rewritten against the paper's PROLOG section
   (p. 372) and Figure 4 (pp. 376–377), and the README's overclaim about the 1986 implementation's
   extent corrected (~50 of 73 pages translated; ~150 rules was the memory-constrained demo subset;
   the paper estimates ~500 rules for the complete act).
4. **A second nonexistent pinpoint** (confirmed minor): the A4 ambiguity comment cited a Sergot
   section heading that does not exist. **Fixed:** now cites §"Some Difficulties with the
   Formalization of Negation" (pp. 378–381), where the closed-world discussion actually lives; the
   substantive parallel (rebuttal as explicit input) was and is accurate.
5. **Modification C2 was neither encoded nor scoped out** (confirmed minor): the one C-annotation
   of the fetched text with no disposition. Its substance (persons exempt from immigration control
   treated as settled for s 1(1)) is subsumed by the settled-as-input scope-out, so nothing
   computed wrongly. **Fixed:** named in both scope-out lists (`bna.l4` SCOPE block, README), with
   the subsumption stated.
6. **A test comment overclaimed what its assert demonstrates** (confirmed minor): the Peter s 1(3)
   negative was attributed to the chapeau, but plain Peter also fails both (3) limbs — the negative
   was overdetermined. **Fixed the strong way:** comment corrected, and a chapeau-isolating fixture
   added (`Peter with the subsection (3) limbs satisfied`: both limbs TRUE, entitlement still
   FALSE, solely because he is already a citizen under (1)) as the 42nd assert and the 25th engine
   case, with generator cross-checks pinning limbs TRUE / chapeau FALSE / entitlement FALSE.
7. **One of 12 ambiguity markers drifted from the exact `-- AMBIGUITY:` form** (confirmed minor):
   A12 had a parenthetical before the colon, so a convention grep found 11/12. **Fixed** (12/12
   now); the requirements consequence is in the p4 ledger entry — prose conventions used as
   machine interfaces need a checked syntax.
8. **The exit-code evidence trail was incomplete** (confirmed minor): the prior evidence file
   recorded 2 of the 5 exit codes the execute-stage report cited it for (the claims themselves
   re-verified true). **Fixed:** all five re-measured against the final artifacts in one recorded
   file, reproduced verbatim in §1.
9. **CLI surface surprises:** `--version` is not accepted; `l4 export --help` answers
   ``Invalid option `--help'`` (though it then prints usage); `l4 run` prints DATE values
   day-first (`DATE OF 3, 5, 1983`), so the cases generator decodes and sanity-checks the
   component order against the three known statutory days before trusting any date pin.
10. **Formatting is not CI-gated for this corpus:** the repo's `.prettierignore` excludes `jl4/`
    entirely, so none of these md/json files reach `format:check`. They were checked by hand with
    the pinned `prettier@3.4.2` (hand-written prose files conform; `bna.dmn.md` and
    `bna.cases.json` are emitted/generated artifacts kept byte-exact as their tools wrote them).

## 4. What this proves about G2, and what it does not

This smoke run proves that a fresh, never-encoded statute can be taken from fetched source to an
auditable inert-style L4 corpus — verbatim text riding inline, 12 argued ambiguity resolutions, 42
boundary-pair asserts all green — and projected to a DMN artifact whose 1075 case-pins execute
identically on two independent engines, in one hand-driven pass, with every stage leaving evidence
the next stage can check; and it proves the adversarial gate earns its place, catching a fabricated citation, a
scope omission, and an overdetermined test that the authoring stages sincerely believed in. It does
**not** prove: that the stages compose unattended (every one was driven and
judged by hand — the orchestrator exists only as scaffolding); that the approach scales past one
section of one act (the 1986 team translated ~50 pages and estimated ~500 rules; this is one
section with 43 decisions); or anything about the regulative layer, since s 1 imposes no
obligations and the corpus is purely constitutive.
