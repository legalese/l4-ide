# The Single-Instruction Demo — "SEC Regulation Crowdfunding: go"

**Status (2026-07-31): DRAFT — proposed, not implemented.** No single instruction runs this
pipeline today. Most stages exist at least in part; §5 names what does not (BKM emission, the
ladder IDE steps, the LTS visualiser proper, the orchestrator, the corpus-of-law repo — and P8
has no component row at all). §5 is the verified inventory and §6 is the gap register.
This document owns the pipeline decisions; per-projection rulings stay in their own specs
(`DMN-EXPORT-PROGRAM-MODEL-SPEC.md`, `lexipedia-superset/SPEC.md`,
`ladder-diagrams-2026/DESIGN.md`, `QUESTION-ORDERING-SPEC.md`), which this spec cites but does
not override.

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
encodes from and P9 cites.

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
found" is a checked claim rather than an assumption.

### P3 — Encode, isomorphically, in inert style

The **first-class deliverable**: a domain expert must be able to review the L4 against the
regulation for correctness, section by section. House rules apply and the adversarial gate (P5)
enforces them:

- inert style, per the drafting guidance in the repo skill
  (`.claude/skills/writing-l4-rules/references/drafting-patterns.md`);
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
feature is merged — PR #92). Representation of forks is an open design question (R4).

### P5 — Adversarial gate

No projection work starts until independent adversarial review is satisfied the encoding is as
good as it can be: isomorphism spot-checks against source text, house-style conformance
(including BRANCH-over-ELSE-IF), temporal closure (every dated constant carries its regime),
fork-register completeness, and disposition of every entry in P2's external-modification
register (consumed by the encoding, consumed by a fork, or explicitly deferred with a reason).
This is the same adversarial-workflow discipline used on the DMN
and ladder builds (#175/#176/#178 merged, #177 open), aimed at the encoding instead of the
code.

### P6 — Tests

Comprehensive scenario tests: common cases, edge cases, and — for every ambiguity fork — cases
that **discriminate between the interpretations**, so a reviewer sees exactly where and how
much the readings diverge. The test carrier (`#EVAL` goldens, `l4 batch`, or jl4-service
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

### P9 — Conversion report

MD and/or HTML, published alongside the code: what the source said, what P2's sweep searched
and surfaced (including the misses), what the encoding decided (including every fork and every
externally-settled resolution), what each projection preserved and lost (the fidelity reports
are the raw material), test results, and — where an alternative system has published its own
representation of the same rule — a factual note of where we disagree with it.

### P10 — Publish

GitHub first: a corpus-of-law repository **separate from l4-ide** (`jl4/examples/` and
`experiments/` are not the right long-term home — R1). Upload to lexipedia too if their format
and licensing admit it (R2). Publication is outward-facing and human-gated (§7.3).

## 5. Component inventory — verified 2026-07-31

Verified against unstable @ `a94a8f1d` (post-#178) and `gh` on 2026-07-31. "Merged" means on
unstable now.

| component                  | state                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reg CF corpus (hand-built) | `jl4/examples/legal/regcf/regcf.l4`, 1,241 lines, temporally closed (PR #172) — the diff oracle for the de novo run (§8)                                                                                                                                                                                                                                |
| temporal rule versions     | `EVAL UNDER RULES EFFECTIVE AT` + dated `BRANCH` merged and CI-covered; design in `TEMPORAL-RULE-VERSION-DESIGN.md`                                                                                                                                                                                                                                     |
| BPMN export                | `l4 export --to bpmn`, byte-golden in `l4-cli-test`                                                                                                                                                                                                                                                                                                     |
| DMN export                 | `l4 export --to dmn` / `dmn-md`; itemDefinitions (PR #175), engine-intersection fixtures (PR #176), law-time (PR #178) all merged; two-engine CI                                                                                                                                                                                                        |
| DMN executability          | MAYBE→typeRef + NOTHING lowering merged in #175 (§11-R8); hydration for computed fields + MAYBE→null (R8-d′) + isJust recognition delivered as **PR #180** (opened 2026-07-31, open — emitted hydrators 44/44 on both engines); BKM emission (DMN spec Phase 5, sequenced after the Phase 4 un-lifting analysis) **not started** — the load-bearing gap |
| ladder diagrams            | Steps 1 and 3 merged; Step 2 half-merged (metrics done, theming + leaf-wrapping open); Step 4 + S6 pan/zoom + S8 palette = PR #177 (open); Step 5 (the side-by-side IDE toggle) unstarted; the default flip is Step 7, gated on 6a — E1 critical path 1→3→4→5→6a→7                                                                                      |
| state-graph / trace dumps  | `l4 state-graph` (DOT only, to stdout) + `l4 trace` (dot\|png\|svg) merged                                                                                                                                                                                                                                                                              |
| LTS visualizer proper      | **not built** — the P2 visualiser sits behind two falsification experiments and three preconditions (`lexipedia-superset/LTS-VISUALISER.md` §0), and `StateGraph` as shipped is explicitly not its scaffold (its Q8). A gap for G3; interim = state-graph DOT through external graphviz                                                                 |
| MCP via jl4-service        | MCP server merged in tree (`jl4-service/src/McpServer.hs`, `WebMCPPage.hs`); a live deployment serving other corpus modules as MCP tools is reported by Meng (2026-07-31), not verifiable from this repo; Reg CF joins in P7                                                                                                                            |
| web wizard / query planner | wizard exports merged (PR #162; the law-time control added by PR #172); deploy legs outstanding per `lexipedia-superset/SPEC.md`; `QUESTION-ORDERING-SPEC.md`                                                                                                                                                                                           |
| TYPICALLY defaults         | `TYPICALLY-DEFAULTS-SPEC.md` **and** the metadata-only implementation both merged (PR #92, 53dda002, 2026-07-08) — in this worktree's base                                                                                                                                                                                                              |
| TNR round-trip             | prototype on unpushed local branch `nlg-roundtrip` (`specs/todo/tnr-prototype/`, incl. `tnr_proto.py`; ~28 files, ~5.6k lines over unstable)                                                                                                                                                                                                            |
| inert-style guidance       | repo skill `.claude/skills/writing-l4-rules/` (inert guidance in `drafting-patterns.md`); fuller treatment in the user-level `l4` skill                                                                                                                                                                                                                 |
| adversarial workflows      | proven pattern (#175, #176, #178 merged; #177 built the same way, still open); not yet packaged as a reusable pipeline stage                                                                                                                                                                                                                            |
| P8 verifier toolchain      | not inventoried here — R5 asks which existing machinery or external tool goes first                                                                                                                                                                                                                                                                     |
| P2 sweep tooling           | no repo component needed — agent web search; the register format is defined in P2 itself                                                                                                                                                                                                                                                                |
| orchestrator ("go")        | **does not exist** — this spec is its birth certificate                                                                                                                                                                                                                                                                                                 |
| corpus-of-law repo         | **does not exist** (R1)                                                                                                                                                                                                                                                                                                                                 |

## 6. Gaps → milestones

- **G0 — spec accepted.** This PR merged; rulings R1–R7 answered or explicitly deferred.
- **G1 — replay run.** The orchestrator skeleton drives the **existing** corpus through every
  currently-green projection and emits conversion report v0. No de novo encoding. Entry: PR
  #177 and PR #180 landed. DMN may still be non-executable at G1 **only if** the report says
  so in Blocking terms.
- **G2 — de novo run.** P1–P6 executed from the SEC source by agents; acceptance = the §8
  diff oracle. Entry: fork representation ruled (R4).
- **G3 — execution parity.** Every P7 leg executes: BKM emission (DMN spec Phase 5, with
  whatever of Phase 4 it needs — the owning spec sequences them) landed and the corpus DMN
  runs on both engines; the BPMN leg meets its acceptance bar and wires to the emitted DMN
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

## 9. Open rulings

R-numbers are scoped to this document (house precedent: the DMN spec has its own R-series, the
lexipedia-superset spec its K-series). Cross-references from elsewhere should say "SI-Rn".

- **R0 — ANSWERED 2026-07-31**: the execution is the exhibit (§2).
- **R1 — corpus-of-law repository**: name, org, license, layout. Owner: Meng.
- **R2 — lexipedia compatibility**: probe their DokuWiki format, contribution route, and
  licensing; fallback is the comparison note in P9. Needs a read-only probe first; any contact
  is HG2.
- **R3 — orchestrator packaging**: proposed §7.2 (skill + phase workflows, in-repo). Confirm
  or redirect.
- **R4 — ambiguity-fork representation**: parallel `DECIDE`s in one module, sibling modules
  per interpretation, or annotation-gated variants? Interacts with the wizard and DMN legs
  (each fork is a distinct decision surface). **Design note drafted 2026-08-01 at Meng's
  direction — [R4-FORK-REPRESENTATION.md](./R4-FORK-REPRESENTATION.md): a fourth shape, the
  `Interpretation` record parameter (public interface + private per-reading implementations,
  exhaustiveness-checked delegation, exhaustive sweep over the fork space). Awaiting Meng's
  ruling; R4 remains OPEN until then.**
- **R5 — P8 toolchain**: which verifier first (the in-compiler exhaustiveness machinery, the
  query-planner ROBDD for unsat/dead-branch detection, an external model checker)? Stretch;
  does not gate G0–G4.
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
