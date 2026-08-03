# The Single-Instruction Demo — "SEC Regulation Crowdfunding: go"

**Status (2026-08-03): PARTIALLY IMPLEMENTED — milestone G1 runs; the de novo path runs its
deposit-validating half.** `etc/go/go.sh run --milestone g1 --subject regcf` drives the committed
corpus through every reachable projection and emits conversion report v0. `--milestone g2` runs
P1, P2, P3-encode, P4 and P5 as **deposit-validating** stages: they do not fetch, search, encode or
find forks — those are agent acts needing the network or a model — but they check what an agent
deposited and report `SKIPPED`/`DEGRADED`/`PASS` with an exit code (ORCHESTRATOR.md §5.2). P8's
script **runs** as of 2026-08-03 (`l4 verify`, R5 rung 1) though the driver does not yet declare
it; P10 remains a scaffolded entry point that refuses with a named blocker. `g2 COMPLETE` is completeness
of accounting over those stages and is **not** the G2 acceptance, which is §8's diff oracle and is
called by no stage. With R4 ruled (2026-08-02), the remaining encode/fork blocker is unbuilt
tooling — and by end of day R5 (the ROBDD-first
ladder), R2 (probe/note/contact three-step) and R1 in full (`legalese/canon`, public,
Apache-2.0 + carried source-terms) had been ruled as well, so **no stage anywhere in the
pipeline waits on an open ruling**: every remaining blocker is engineering or an HG2 act.
P8 was the seventh refuser and is one no longer: R5's **rung 1** (`l4 verify`, the query-planner
ROBDD over the boolean skeleton) is built, and P8 below now carries a pass condition where it
carried none. The orchestrator's own present-tense inventory is
[ORCHESTRATOR.md](./ORCHESTRATOR.md); §5 below still names what does not exist (BKM emission, the
ladder IDE steps, the LTS visualiser proper, the corpus-of-law repo, and P8's rungs 2 and 3).
§5 is the verified inventory and §6 is the gap register.
This document owns the pipeline decisions; per-projection rulings stay in their own specs
(`DMN-EXPORT-PROGRAM-MODEL-SPEC.md`, `lexipedia-superset/SPEC.md`,
`ladder-diagrams-2026/DESIGN.md`, `QUESTION-ORDERING-SPEC.md`,
`EXPLAINER-REPORT-SPEC.md`), which this spec cites but does not override.

---

## 1. The instruction

> **"SEC regulation crowdfunding: go"**

One instruction from Meng. The system pulls the source regulation, encodes it isomorphically in
L4, satisfies itself adversarially that the encoding is as good as it can be, generates tests,
emits every projection we are capable of, writes a conversion report, and publishes the lot.
Reasonably long-horizon; human gates at the points named in §7.3 and nowhere else.

## 2. Thesis and provenance

**R0 — ANSWERED 2026-07-31 (Meng): "the execution is the exhibit."** For a demo whose audience
spans both sophistication classes of evaluator — the Leidos/TNA/Mendix-class screener and the
first-time rules-as-code engineer — only artifacts that _run_ exhibit anything. Two prongs, one
obligation:

1. **Soup-to-nuts.** The demo shows the whole pipeline landing as a new lexipedia-grade entry
   with **working** BPMN and DMN embedded, commentary and ladder diagrams alongside. Lexipedia
   chose the OMG standards; we respect that choice and cooperate with it. For the BPMN leg,
   "working" is defined by the acceptance-bar ruling of 2026-08-01
   (`lexipedia-superset/PROCESS-TRACK.md` §8): the diagram renders and is sound, and it wires
   to the emitted DMN — engine execution of the _process_ is a non-goal there, because process
   execution runs on the parties.
2. **The good-faith bypass.** Some scenarios rightly skip the BPMN/DMN lowering: the MCP
   projection serving AI consumers directly, a web-app projection deployed straight from L4, a
   legal engineer reviewing and signing off on the L4 itself. That argument is credible only
   because prong 1 demonstrates we did as much as humanly (and agentically) possible to work
   _with_ the standards, not against them.

The DMN-side consequence of R0 (corpus export must execute → BKM emission is demo-critical) is
recorded in `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §6.2 by an edit landed **in this same PR**, per
the repo recording rule ("a decision is recorded in its owning document in the same PR, or it
is not decided").

## 3. Scope

**Regulation Crowdfunding only** (17 CFR Part 227, under Securities Act §4(a)(6)) — the
regulation lexipedia represents at
<https://www.lexipedia.xyz/doku.php?id=reg_cf_exemptions>. A de novo run starts from the SEC's
entry point,
<https://www.sec.gov/education/smallbusiness/exemptofferings/regcrowdfunding>, and follows it
to the eCFR text. Other regulations are out of scope for the demo; the pipeline is written so
that the instruction's subject is a parameter, but nothing beyond Reg CF gates acceptance.

## 4. Pipeline stages

Each stage names its deliverable, and the deliverable is the interface: a later stage may read
only what an earlier stage committed.

### P1 — Ingest

Pull the current and historical rule text (the 2016 adoption, the 2017 and 2022 inflation
adjustments, the 2021 amendments, the COVID-19 temporary rules) with Federal Register citations
attached. Deliverable: a source bundle with provenance (URL, retrieval date, FR cites) that P3
encodes from and P9 cites. Machine-readable format:
[`schemas/source-bundle.schema.json`](./schemas/source-bundle.schema.json) — defined and
validated 2026-08-02; no stage writes one yet.

### P2 — External-modification sweep (added by Meng 2026-07-31; runs concurrent with P1)

The published text does not know what has happened to it. While P1 pulls the regulation as
printed, parallel web searches ask what the print cannot say: has a court struck down, stayed,
or read down any provision; has the regulator settled — or created — an ambiguity through
interpretive guidance (for the SEC: C&DIs, no-action letters, staff bulletins) or a practice
direction; are amendments proposed or expected (Federal Register proposed rules, the agency's
regulatory agenda, litigation in flight).

Deliverable: an **external-modification register**, one entry per finding, with provenance
(source, URL, retrieval date) and a classification that routes it:

- **(a) binding modification** → informs P3 directly: a struck provision is still encoded but
  marked inoperative on the rule-version axis, citing the striking authority — so the encoding
  shows both what the text says and what the law now is;
- **(b) interpretive guidance** → routed to P4's fork register: guidance that settles a reading
  closes a fork (the fork stays recorded, with the authority that resolved it); guidance that
  reveals a reading nobody drafted for opens one;
- **(c) prospective** → a dated future regime where a date exists; otherwise flagged as
  currency risk in the P9 report.

Searching is read-only and triggers no human gate. Misses matter as much as hits: the P9
report states what was searched, not only what was found, so "no post-enactment modification
found" is a checked claim rather than an assumption. Machine-readable format:
[`schemas/external-modifications.schema.json`](./schemas/external-modifications.schema.json) —
defined and validated 2026-08-02, with a `searches[]` section carrying that last sentence's
contract (a search records its scope and, required, what it does **not** cover) and a
completeness join over the source bundle's annotation inventory.

### P3 — Encode, isomorphically, in inert style

The **first-class deliverable**: a domain expert must be able to review the L4 against the
regulation for correctness, section by section. House rules apply and the adversarial gate (P5)
enforces them:

- inert style, per the drafting guidance in the repo skill
  (`.claude/skills/writing-l4-rules/references/drafting-patterns.md`) — including the
  enumeration-label ruling of 2026-08-03: an inert string that restates the active node beside it
  is deleted, and only the statutory item's label survives, on its node's line, joined by `...`.
  `p3-check.sh` reads the surviving labels and **warns** (never fails) when a rule quotes them out
  of order; gaps are counted and reported as information, because a repealed limb is a legitimate
  gap in a consolidated text;
- `GIVEN` preferred to `ASSUME` (unbound assumed terms stall `#EVAL` — they evaluate only when
  bound via `#CHECK … WITH` / `#TRACE … WITH` or promoted to caller-supplied parameters by
  `@export` — so plain `#EVAL` goldens over ASSUME-style modules do not exercise the logic;
  this same distinction drives P6's carrier choice);
- `BRANCH` preferred to `ELSE IF` chains;
- multiple rule versions represented with the shipped temporal mechanisms
  (`EVAL UNDER RULES EFFECTIVE AT`, dated `BRANCH` chains — see
  `TEMPORAL-RULE-VERSION-DESIGN.md`), with `@ref` FR citations on every dated arm.

### P4 — Ambiguity forks and TYPICALLY defaults

The encoding agent is prompted **away** from its usual best-guess-what-the-humans-meant
strategy toward pedantic sensitivity to multiple possible interpretations: implement them all —
or enough of them to illustrate the points of ambiguity — and flag each fork for review.
Deliverable: the forks themselves, in L4, plus a fork register naming the ambiguous source text
each fork interprets — cross-referenced against P2's external-modification register, so a fork
an authority has already settled carries that resolution rather than presenting as open. Where
world knowledge supports a sensible default, preload it as a `TYPICALLY` metadata default (the
feature is merged — PR #92). Representation of forks is ruled (R4, ANSWERED 2026-08-02): one
`Interpretation` record parameter, fork register entries mapping 1:1 to its fields — see
[R4-FORK-REPRESENTATION.md](./R4-FORK-REPRESENTATION.md). Machine-readable format:
[`schemas/fork-register.schema.json`](./schemas/fork-register.schema.json) — defined and
validated 2026-08-02, enforcing that 1:1 map. It also records forks that are **not**
materialised: the BNA smoke's twelve ambiguities were all resolved at encode time or delegated
to a fact-supplier, so `materialisation` is a discriminator rather than an assumption.

### P5 — Adversarial gate

No projection work starts until independent adversarial review is satisfied the encoding is as
good as it can be: isomorphism spot-checks against source text, house-style conformance
(including BRANCH-over-ELSE-IF), temporal closure (every dated constant carries its regime),
fork-register completeness, and disposition of every entry in P2's external-modification
register (consumed by the encoding, consumed by a fork, or explicitly deferred with a reason).
This is the same adversarial-workflow discipline used on the DMN
and ladder builds (#175/#176/#177/#178 all merged), aimed at the encoding instead of the
code.

### P6 — Tests

Comprehensive scenario tests: common cases, edge cases, and — for every ambiguity fork — cases
that **discriminate between the interpretations**, so a reviewer sees exactly where and how
much the readings diverge. Under R4's ruled representation this takes the two property classes
of R4-FORK-REPRESENTATION.md §4: **agreement** properties asserted `∀ interp` (where all
readings concur, the answer is interpretation-independent), and **divergence witnesses**
(searched fact patterns where two readings disagree, minimised and pinned as named cases, each
citing its fork-register entry). The test carrier (`#EVAL` goldens, `l4 batch`, or jl4-service
replay) is chosen at implementation time; measure which carriers support the GIVEN-record house
style before committing to one.

### P7 — Projections

All of the following, from the same reviewed encoding:

| leg             | artifact                                                                                                                   |
| --------------- | -------------------------------------------------------------------------------------------------------------------------- |
| ladder diagrams | interactive AND/OR ladders for the Boolean decision structure                                                              |
| DMN             | XML and dmnmd markdown, executable on KIE and Camunda                                                                      |
| BPMN            | process views of the regulative rules (bar: acceptance + soundness + DMN wiring, `lexipedia-superset/PROCESS-TRACK.md` §8) |
| LTS visualizer  | our own LTS view (the superset spec's P2 visualiser — unbuilt, see §5; interim: `l4 state-graph` DOT via graphviz)         |
| MCP             | the module served as tools via jl4-service                                                                                 |
| TNR round-trip  | Times-New-Roman prose regeneration; each run is NLG training data                                                          |
| web wizard      | query-planner-driven interview app                                                                                         |

Every leg ships with its fidelity/conversion notes; per R0, "it renders but cannot execute" is
a defect in the demo, not a caveat. (For the BPMN leg, "execute" is read per the 2026-08-01
acceptance-bar ruling — `lexipedia-superset/PROCESS-TRACK.md` §8: acceptance + soundness + the
DMN wiring, not engine execution of the process, which runs on the parties.)

### P8 — Formal verification (stretch)

Extract to reasoners and verifiers to hunt loopholes, bugs, race conditions, and
unsatisfiable/conflicting rule combinations. Constraint from Meng: CPU-based techniques
(SAT/BDD/model-checking) with model assistance capped at **Opus-level reasoning**, and prompts
framed as legal-drafting analysis (double binds, dead branches, unreachable entitlements) — not
security-exploit language. Stretch goal: P8 gates nothing in G0–G4 (§6).

**Pass condition (added 2026-08-02, with R5 rung 1).** This row was blank when R5 was ruled, and
a stage with no pass condition is `UNVERIFIED` by construction — so here it is, and it is
deliberately not "the corpus came back clean". A consistency checker that can never go red
reports every corpus clean; a green corpus is evidence about the checker only once the checker is
shown capable of going red, and of going red for the reason it claims.

> **P8 passes when**, in one run and from one binary, every committed control fixture reproduces
> its declared verdict — one clean module reporting zero findings, and one module per finding
> family reporting exactly that family and exiting non-zero — **and** every declared corpus
> module is analysed with zero findings. Controls holding while the corpus has findings is
> `DEGRADED`: the findings are the stage's output, reported in the report's own words, not a
> harness failure. A control that stops reproducing is `BROKEN`, because nothing the stage then
> says about the corpus can be trusted.

The pass is bounded and the receipt must carry the bound, not merely a spec paragraph: rung 1 is
propositional (every leaf is an opaque atom, so no numeric, interval, date or string
contradiction is in range), reads each `DECIDE` on its own without inlining callees, visits only
**top-level** decisions — a `WHERE`-local definition is a `DECIDE` and neither this command nor
the ladder's own entry point descends into one — and is sound but not complete. That last
exclusion is reported as a **number** (`summary.nestedNotVisited`, `nested_not_visited` on the
receipt: 7 across the Reg CF corpus), because `analysed + skipped` does not total the file and an
exclusion nobody can size is an exclusion nobody believes. Rungs 2 (R4 fork-space sweep) and 3 (external model checker) are unbuilt, and a
P8 receipt says which rung it is reporting. Implementation and measurement:
[ORCHESTRATOR.md](./ORCHESTRATOR.md) §5.1a.

### P9 — Conversion report

MD and/or HTML, published alongside the code: what the source said, what P2's sweep searched
and surfaced (including the misses), what the encoding decided (including every fork and every
externally-settled resolution), what each projection preserved and lost (the fidelity reports
are the raw material), test results, and — where an alternative system has published its own
representation of the same rule — a factual note of where we disagree with it.

#### P9.1 — The explainer report (a sibling, not a rewrite)

**Status (2026-08-03): DESIGNED, NOT BUILT.** No stage, template, renderer or narrative file
exists. The design is [EXPLAINER-REPORT-SPEC.md](./EXPLAINER-REPORT-SPEC.md), which owns every
decision about it; its ruling series is the **E-series**, cited elsewhere as `EXP-En`.

The conversion report above is an **audit** document, and its central rule — no digit-run may be
typed into `etc/go/report/template.md`, enforced by `render-report.mjs` before it opens a journal
and again in CI — makes it structurally incapable of explaining a regulation to anybody. The
explainer is its reader-facing sibling. It does a **dual** job that interleaves rather than
splitting: it explains **the law** to a lay reader, and alongside each substantive part it explains
**the L4 treatment of the formalization** — where the prose was vague and the code could not be,
what the type system refused, where an ambiguity had to fork, what each projection makes visible
that the others hide, and what the encoding honestly failed to capture. That second thread is what
makes the document an argument for the method rather than a summary of the rule, and it is held to
the same discipline: a claim about the encoding is licensed by the encoding, cited to a line.

Three rulings by Meng, 2026-08-03, recorded here and expanded in the owning spec:

- **D1 — narrative provenance.** The lay narrative is **agent-drafted, checked in, and
  HG1-reviewed**. It lives in the subject directory (`etc/go/subjects/<id>/explainer/`) with a
  provenance record naming the source it was drafted from, so a later run detects drift when the
  source text changes. Unreviewed narrative renders visibly marked as draft / "claimed, not
  verified". See EXPLAINER-REPORT-SPEC.md §5 for the file layout, the record's fields, the three
  drift classes, and the three-level draft marking.
- **D2 — a separate sibling artifact.** `explainer.md` + `explainer.html`, beside the existing
  `report.md` / `report.html`, from a separate stage. **P9's "no typed numbers in the template"
  invariant survives completely untouched** — `render-report.mjs` and `template.md` are not opened
  by that build. The two documents cross-link; per `EXP-E16` the link is one-way (explainer →
  report), because the explainer may legitimately not exist for a run and the report may not assert
  it does. See §2.
- **D3 — Reg CF first; the design is not Reg CF-shaped.** The BNA is the planned second subject and
  is **not in scope** for the v0 build. The spine is fixed by the spec; the body sections are
  declared per subject in that subject's `explainer/manifest.json`. See §4.1.

Constraints the design records rather than solves, because recording them is the point:
**there is no in-repo DOT→SVG path** (graphviz is a machine dependency, DOT carries no coordinates,
so a renderer would be a layout engine — `EXP-E12`); **BPMN/DMN are the opposite case**, since both
exporters already emit diagram interchange with computed coordinates, so a picture needs a
serializer and not a layout engine, deferred to v1 with the measurement attached (`EXP-E14`); and
**no live-deployment claim is available from this repo**, so the call to action is
stand-it-up-yourself (`EXP-E15`).

### P10 — Publish

GitHub first: a corpus-of-law repository **separate from l4-ide** (`jl4/examples/` and
`experiments/` are not the right long-term home — R1). Upload to lexipedia too if their format
and licensing admit it (R2). Publication is outward-facing and human-gated (§7.3).

## 5. Component inventory — verified 2026-07-31

Verified against unstable @ `a94a8f1d` (post-#178) and `gh` on 2026-07-31. "Merged" means on
unstable now.

| component                  | state                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reg CF corpus (hand-built) | `jl4/examples/legal/regcf/regcf.l4`, 1,236 lines, temporally closed (PR #172) — the diff oracle for the de novo run (§8)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| temporal rule versions     | `EVAL UNDER RULES EFFECTIVE AT` + dated `BRANCH` merged and CI-covered; design in `TEMPORAL-RULE-VERSION-DESIGN.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| BPMN export                | `l4 export --to bpmn`, byte-golden in `l4-cli-test`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| DMN export                 | `l4 export --to dmn` / `dmn-md`; itemDefinitions (PR #175), engine-intersection fixtures (PR #176), law-time (PR #178) all merged; two-engine CI                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| DMN executability          | MAYBE→typeRef + NOTHING lowering merged in #175 (§11-R8); hydration for computed fields + MAYBE→null (R8-d′) + isJust recognition delivered as **PR #180** (MERGED to unstable — emitted hydrators 44/44 on both engines); BKM emission (DMN spec Phase 5, sequenced after the Phase 4 un-lifting analysis) **not started** — the load-bearing gap                                                                                                                                                                                                                                                                                                 |
| ladder diagrams            | Steps 1 and 3 merged; Step 2 half-merged (metrics done, theming + leaf-wrapping open); Step 4 + S6 pan/zoom + S8 palette = PR #177 (MERGED to unstable); Step 5 (the side-by-side IDE toggle) unstarted; the default flip is Step 7, gated on 6a — E1 critical path 1→3→4→5→6a→7                                                                                                                                                                                                                                                                                                                                                                   |
| state-graph / trace dumps  | `l4 state-graph` (DOT only, to stdout) + `l4 trace` (dot\|png\|svg) merged                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| LTS visualizer proper      | **not built** — the P2 visualiser sits behind two falsification experiments and three preconditions (`lexipedia-superset/LTS-VISUALISER.md` §0), and `StateGraph` as shipped is explicitly not its scaffold (its Q8). A gap for G3; interim = state-graph DOT through external graphviz                                                                                                                                                                                                                                                                                                                                                            |
| MCP via jl4-service        | MCP server merged in tree (`jl4-service/src/McpServer.hs`, `WebMCPPage.hs`); a live deployment serving other corpus modules as MCP tools is reported by Meng (2026-07-31), not verifiable from this repo; Reg CF joins in P7                                                                                                                                                                                                                                                                                                                                                                                                                       |
| web wizard / query planner | wizard exports merged (PR #162; the law-time control added by PR #172); deploy legs outstanding per `lexipedia-superset/SPEC.md`; `QUESTION-ORDERING-SPEC.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| TYPICALLY defaults         | `TYPICALLY-DEFAULTS-SPEC.md` **and** the metadata-only implementation both merged (PR #92, 53dda002, 2026-07-08) — in this worktree's base                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| TNR round-trip             | **forward leg built 2026-08-02**: `l4 nlg FILE` emits the same payload as jl4-test's `jl4NlgAnnotationsGolden`, so `p7-tnr` regenerates and diffs the committed `.nlg.golden`s instead of hashing files it did not produce. The RETURN leg — carrying a prose edit back into the L4 — is still only the prototype on the unpushed local branch `nlg-roundtrip` (`specs/todo/tnr-prototype/`, incl. `tnr_proto.py`; ~28 files, ~5.6k lines over unstable)                                                                                                                                                                                           |
| inert-style guidance       | repo skill `.claude/skills/writing-l4-rules/` (inert guidance in `drafting-patterns.md`); fuller treatment in the user-level `l4` skill                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| adversarial workflows      | proven pattern (#175, #176, #178 merged; #177 built the same way and since merged); not yet packaged as a reusable pipeline stage                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| P8 verifier toolchain      | **rung 1 built 2026-08-02**: `l4 verify` compiles each boolean `DECIDE` through the ladder into the query-planner ROBDD (`jl4-query-plan`) and reports `unsat` / `dead-branch` / `vacuous-guard` / `unreachable-outcome`; text + JSON, exit 0/1, five control fixtures, driven by `etc/go/phases/p8-verify.sh`. Bounded: propositional, per-decision, sound but not complete. Rungs 2 (R4 fork-space sweep) and 3 (external model checker — TLA+/NuSMV/UPPAAL class) remain unbuilt                                                                                                                                                                |
| P2 sweep tooling           | no repo component needed for the searching — that is agent web search. The register format is now machine-readable: `schemas/external-modifications.schema.json`, validated by `etc/go/lib/register-validate.mjs` (added 2026-08-02, alongside the P1 and P4 contracts)                                                                                                                                                                                                                                                                                                                                                                            |
| orchestrator ("go")        | **milestones G1 and G2's deposit half run today** — `etc/go/go.sh run --milestone g1 --subject regcf` drives the committed corpus through every reachable projection and emits report v0; `--milestone g2` runs P1, P2, P3-encode, P4 and P5 as stages that VALIDATE an agent-produced deposit (2026-08-03), leaving P10 scaffolded and refusing with a named blocker. P8's script runs as of 2026-08-03 (`l4 verify`) but `go.sh` does not yet declare it, so `go.sh plan` still prints it among the refusers. Producing the deposits, and the §8 acceptance diff, stay agent work. Present-tense inventory: [ORCHESTRATOR.md](./ORCHESTRATOR.md) |
| corpus-of-law repo         | **exists as of 2026-08-03** — `legalese/canon`, public, scaffolded to R1's ruled shape (inspectable gates, two-axis versioning, sidecar class/instance layout, Apache-2.0 + carried source-terms + optional CC-BY prose) and holding **zero subjects**. Putting a subject in it is an HG2 act                                                                                                                                                                                                                                                                                                                                                      |

## 6. Gaps → milestones

- **G0 — spec accepted.** This PR merged; rulings R1–R7 answered or explicitly deferred.
- **G1 — replay run. BUILT 2026-08-02; see [ORCHESTRATOR.md](./ORCHESTRATOR.md) §1 for the
  measured run.** The orchestrator drives the **existing** corpus through every currently-green
  projection and emits conversion report v0. No de novo encoding. Entry condition (PR #177 and
  PR #180 landed) is satisfied — both merged to `unstable`. DMN may be non-executable at
  G1 **only if** the report says so in Blocking terms — which was the leg's state as built.
  Discharged 2026-08-02: PR #194 landed the corpus cases file, and the leg now reports `PASS`
  with oracle class `execution` on both engines (ORCHESTRATOR.md §5.4).
- **G2 — de novo run.** P1–P6 executed from the SEC source by agents; acceptance = the §8
  diff oracle. Entry condition satisfied 2026-08-02: fork representation ruled (R4, the
  `Interpretation` parameter). **Half built as of 2026-08-03**: `go.sh run --milestone g2` runs
  P1, P2, P3-encode, P4 and P5 as deposit-validating stages, each with an exit code over the
  agent's deposit and a `SKIPPED` naming the deposit it is waiting for; the sidecar's `denovo`
  section says where those deposits live. What is **not** built is anything that produces a
  deposit (agent work by design — the driver takes neither the network nor a model), and the
  wiring that would point `p3-check`, `p6-tests` and the p7 legs at a de novo module rather than
  at the committed corpus. The acceptance comparator was built 2026-08-02 as
  `etc/go/lib/denovo-diff.mjs`, designed in [DENOVO-DIFF-ORACLE.md](./DENOVO-DIFF-ORACLE.md);
  **no stage calls it**, so no `go.sh` verdict can assert G2 in this bullet's sense.
- **G3 — execution parity.** Every P7 leg executes: BKM emission (DMN spec Phase 5, with
  whatever of Phase 4 it needs — the owning spec sequences them) landed and the corpus DMN
  runs on both engines (**done 2026-08-02** — PRs #188 + #194, measured in ORCHESTRATOR.md
  §1); the BPMN leg meets its acceptance bar and wires to the emitted DMN
  (`lexipedia-superset/PROCESS-TRACK.md` §8 — engine execution of the process is a non-goal
  there); wizard deployed; ladders embedded in the entry (the framework-free
  ladder-svg controller from PR #177 suffices — the IDE toggle/flip, E1 Steps 5→6a→7, is not
  on this path); the LTS leg per its §5 row (the superset spec's P2 visualiser, or the declared
  graphviz interim); TNR leg producing prose. This is R0 discharged.
- **G4 — publish.** Corpus repo populated (R1), lexipedia contribution or comparison note
  (R2), conversion report public.

## 7. Orchestration

### 7.1 Conductor and delegation

**Fable or Opus calls the shots** (Meng, 2026-07-31), delegating to Fable, Opus, or Sonnet as
appropriate: frontier reasoning for encoding, ambiguity analysis, and adversarial gates;
mid-tier for mechanical transforms, golden regeneration, formatting, harness runs.

### 7.2 Shape

**Built 2026-08-02 (R3 ANSWERED).** What follows is the proposal as written; the shape as
built, and the four places it departs from this text, are in
[ORCHESTRATOR.md](./ORCHESTRATOR.md).

A thin skill (the instruction's entry point) plus workflow scripts per phase, so control flow
is deterministic and each phase is resumable after interruption — the same pattern the DMN and
ladder builds used. One builder per worktree at a time (the build lock); verification agents
read committed artifacts and never build.

### 7.3 Human gates

Exactly two: **HG1**, the domain-expert review of the inert-style L4 (after P5, before P6's
tests are treated as specifications); **HG2**, Meng's go on anything outward-facing — creating
the corpus repo, publishing the report, any lexipedia contact. Everything else runs
autonomously.

## 8. Acceptance test — the diff oracle

The de novo run (G2) re-derives Reg CF from source **without reading the existing corpus**,
then diffs its encoding against `jl4/examples/legal/regcf/regcf.l4`:

- **Agreements** validate both encodings.
- **Disagreements** are triaged: encoding error (fix), genuine ambiguity (both readings join
  the fork register), or improvement over the hand corpus (backport).
- The triage table goes into the conversion report. A de novo run that merely reproduces the
  corpus is a pass; one that finds a defect in it is a better pass.

**Built 2026-08-02, unexercised.** The comparator is `etc/go/lib/denovo-diff.mjs` and its pairing
format is `schemas/surface-map.schema.json`; the design, the two self-tests verbatim, and the list
of what the comparison cannot see are in [DENOVO-DIFF-ORACLE.md](./DENOVO-DIFF-ORACLE.md). It is
behavioural, not textual — two encodings of one statute share no names, so it pairs decisions by
declared correspondence and diffs answers over a shared fact battery. The three dispositions above
are judgements: the script emits the table with every row `UNTRIAGED` and never fills one in.
Its largest blind spot is stated there and repeated in every report it writes: the battery
exercises decisions, so a divergence confined to the deontic layer would not appear.

## 9. Open rulings

R-numbers are scoped to this document (house precedent: the DMN spec has its own R-series, the
lexipedia-superset spec its K-series, the explainer spec its E-series). Cross-references from
elsewhere should say "SI-Rn".

- **R0 — ANSWERED 2026-07-31**: the execution is the exhibit (§2).
- **R1 — corpus-of-law repository**: name, org, license, layout. Owner: Meng. **ANSWERED IN
  FULL 2026-08-02 (Meng), across one review session, five dimensions:** (0) **name/org:
  `legalese/canon`** — the final dimension, ruled last. (1) **visibility: PUBLIC from day
  one** — with draft-status markers per subject, **inspectable HG1/HG2** (the gate grants —
  signature files, waiver records, `gate-allowed-signers` — are in-repo artifacts a reader can
  verify with `ssh-keygen -Y verify`, which the gate machinery already supports), and **version
  numbering** (the encoding's version; orthogonal to the law-time axis, which stays
  `EVAL UNDER RULES EFFECTIVE AT`). (2) **layout: class/instance** — the generic "⟨body of
  law⟩: go" template (the subject-sidecar shape: descriptor + pins + known-defects + NOTES.md)
  is the class; each encoding job is an instance expected to veer, with its divergences recorded
  in its own sidecar files rather than by forking the template. (3) **license — ANSWERED in full 2026-08-02
  (Meng): Apache-2.0 + carried source-terms + optional CC-BY on prose.** Apache-2.0 on
  everything we author (encodings, cases, schemas, harnesses — the patent grant and NOTICE
  machinery are why it beats MIT here); quoted statutory text carries its own terms through
  per-subject SOURCE-LICENSE notes (US federal material is public domain, 17 U.S.C. §105 + the
  edicts doctrine; UK material rides under OGL v3, whose attribution lands in NOTICE — OGL v3
  declares itself CC-BY-4.0-compatible and is a content license in structure); prose artifacts
  (conversion reports, commentary, comparison notes) may carry CC-BY-4.0 in addition, so they
  flow one-way into BY-SA wikis (lexipedia is CC BY-SA 4.0, measured 2026-08-02) without
  ShareAlike ever reaching the encodings. The open-core → freemium-enrichment pathway stays
  open by construction. Nothing in R1 remains open; **creating** `legalese/canon` is a
  distinct outward-facing act and is HG2's, per §7.3 — the ruling names the repo, it does not
  create it.
- **R2 — lexipedia compatibility**: **ANSWERED 2026-08-02 (Meng), as a three-step pathway:**
  **probe now** (read-only: their DokuWiki format, contribution route, licensing — measured
  2026-08-02: the site is CC BY-SA 4.0, so a comparison note must be written in our own words
  with quotation, and our prose artifacts want CC-BY-4.0 so they can flow into BY-SA one-way
  without ShareAlike reaching the encodings); **comparison note at G4** (published on our side —
  that publication is the HG2 moment); **contact only with a live page in hand** (the superset
  entry deployed, not a spec). Meng owns the outreach and will ask Anson whether a different
  draft pathway for contribution is preferred; any contact remains HG2 regardless.
- **R3 — ANSWERED 2026-08-02, see [ORCHESTRATOR.md](./ORCHESTRATOR.md)**: orchestrator
  packaging is §7.2's shape — a thin skill (`.claude/skills/running-the-l4-pipeline/`) plus one
  workflow script per phase (`etc/go/phases/`), driven by a single deterministic, resumable entry
  point (`etc/go/go.sh`), in-repo. Built and measured rather than confirmed on paper: a G1 replay
  run against the committed Reg CF corpus reports thirteen receipts and verdict `COMPLETE`.
  What the build changed from the proposal, and why: (a) resumability is a **digest comparison**
  per stage, not a checkpoint file, so a re-entered run cannot report `replayed` for a stage whose
  inputs moved; (b) every `PASS` oracle declares a **class**, and `wellformedness`/`presence` are
  barred from `PASS`, because "PASS requires an oracle" without that bar is satisfied by any cheap
  checker; (c) the milestone verdict is completeness of **accounting**, not greenness, which is
  what §6's "only if the report says so in Blocking terms" already implied; (d) the two human
  gates are detached SSH signatures over a journal-derived payload, with `--waive GATE="reason"`
  as the recorded alternative — there is no unrecorded way past a gate.
- **R4 — ambiguity-fork representation**: **ANSWERED 2026-08-02, see
  [R4-FORK-REPRESENTATION.md](./R4-FORK-REPRESENTATION.md) §7.** Meng adopted the
  `Interpretation` record parameter (public interface + private per-reading implementations,
  exhaustiveness-checked delegation, exhaustive sweep over the fork space) over the three shapes
  this ruling originally listed (parallel `DECIDE`s, sibling modules, annotation-gated variants),
  and extended it to regulative rules: rules tend to be returned by `MEANS` functions anyway,
  so the `interp` argument threads through the scope of the deontic chain. Ruled, and half built:
  as of 2026-08-03 the P1–P5 stages validate the deposits an agent produces (the fork register
  enforces R4's 1:1 map), while producing them stays agent work — ORCHESTRATOR.md §5.2.
- **R5 — P8 toolchain**: **ANSWERED 2026-08-02 (Meng), as a ladder rather than a choice.**
  (1) **The query-planner ROBDD goes first** (PR #92's hand-rolled model counter): unsat
  conditions, dead branches and vacuously-true guards over the boolean skeleton — shipped
  machinery, zero new dependencies, script-side with exit codes, so `p8-verify` gets an honest
  `structural` oracle. (2) **The fork-space sweep second** (post-P4): R4's agreement/divergence
  properties, `∀ interp`, are quantified verification and P8 is their natural owner. (3)
  **External model checking last** — deontic/temporal properties (double binds, the reporting
  loop) wait for the LTS semantics to stabilise; deferred, not rejected. Honest bound on rung 1:
  the ROBDD is propositional — atoms are opaque, so arithmetic relations between atoms and
  temporal properties are invisible to it; those are rungs 2–3's business. Still gates nothing
  in G0–G4.
- **R6 — WITHDRAWN 2026-07-31, same day it was drafted**: it asked to "land
  `mengwong/typically-salvage`" — but that landed as PR #92 on 2026-07-08 (53dda002, in this
  worktree's base). The draft was written from a stale session memory; the adversarial
  verification pass caught it. Nothing blocks G2 on this axis.
- **R7 — report versioning**: one report per run, versioned by run date + source retrieval
  date, or a living document? Proposal: per-run, immutable, latest linked.

---

_What review changed (adversarial pass, 2026-07-31 — three read-only Opus lenses, 95 claims
confirmed, 15 findings, all repaired): TYPICALLY was described as unlanded from a stale memory —
it merged as PR #92 on 2026-07-08, so R6 is withdrawn; the R0/DMN consequence was claimed
"recorded" before the edit existed — the edit now lands in this PR; the ladder default flip was
misattributed to Step 5 (it is Step 7, gated on 6a; Step 2 is only half-merged); "Steps 1–3
merged" was sharpened beyond the owning spec's own hedge; the LTS row conflated the merged
DOT/trace dumps with the unbuilt visualiser (the superset spec's P2 track); BKM was mislabelled "Phase 4→5" (it is Phase 5);
the wizard's law-time control was misattributed to #162 (it came in #172); ASSUME's evaluation
semantics were overstated; the MCP live-deployment claim is now attributed to Meng's report
rather than presented as repo-verifiable; the status-header "one unstarted" undercounted._

_Amended 2026-07-31 (Meng): added **P2 — the external-modification sweep** (courts striking or
reading down provisions, regulator guidance and practice directions, pending amendments),
running concurrent with ingest and feeding both the encoding and the fork register; stages
renumbered P3–P10 accordingly. In the same commit, §5's DMN-executability row and G1's entry
condition were refreshed to name PR #180, which opened between the adversarial pass and this
amendment._
