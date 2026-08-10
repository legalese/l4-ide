# feat(bpmn): export the regulative layer as BPMN 2.0 — soundness gate, jBPM corroboration, and gateways that delegate to DMN

**What this adds.** L4's _regulative_ layer — `PARTY p MUST a WITHIN d HENCE … LEST …` — can now be
projected to BPMN 2.0 XML that opens in Camunda Modeler, complete with diagram interchange (real
coordinates, so the file is a picture and not just a model) and a **fidelity report** that names,
per element, what BPMN could not carry. Nothing here could be done before: on `main` there is no
BPMN backend at all. Alongside the exporter come four checkers, all new — a `bpmn-moddle` acceptance
parse, a zero-dependency exhaustive token-game soundness gate, a pinned jBPM/KIE harness that
actually executes the process, and a resolver that proves every `<businessRuleTask>` names a decision
that really exists in the emitted DMN — plus a dependency-free BPMN→SVG renderer. Six
golden diagrams ship, three of them cut straight from the 992-line Reg CF corpus rather than from a
hand-written stand-in.

**Why.** Track P1 of the lexipedia-superset programme. The argument in
`doc/concepts/language-design/logic-not-flowcharts.md` is that drawing a _predicate_ as a flowchart
is a category error — not that process notation is worthless. A regulative rule genuinely **is** a
transition system, so the split is: constitutive layer → ladder and DMN, regulative layer → state
graph and BPMN. The exhibit being answered advertises BPMN _and_ DMN, ships no DMN, and draws its
decisions as gateways; the better way is BPMN delegating decisions to DMN, which §8.3 of
`PROCESS-TRACK.md` mandated on 2026-08-01 and PR #198 built. The second checker was asked for
upstream in **smucclaw/l4-ide#926** ("add KIE as a second, independent BPMN sanity checker"); the
state-graph caption defects that several of these goldens encode were **smucclaw/l4-ide#927**.

---

## What's in it

**The exporter — 4 Haskell modules, ~3,000 lines** (`jl4-core/src/L4/Bpmn/`):

- `IR.hs` (398 lines) — the target IR. `BpmnProcess` is the semantics, `Diagram` is the picture, and
  nothing in the first refers to the second, because BPMN keeps them independent too.
- `Lower.hs` (2,165 lines) — `L4.StateGraph.StateGraph` → IR, including layout. `LEST` becomes an
  interrupting boundary event, a deadline a timer event definition, `RAnd`/`ROr` a parallel/exclusive
  gateway, parties become lanes, `TerminalBreach` an error end event. `IF`/`ELSE` over regulative
  arms peels into a guarded `OneOf` junction whose branches are exhaustive and mutually exclusive by
  construction; a `HENCE` back into the rule being extracted is a loop.
- `Emit.hs` (350 lines) — IR → BPMN 2.0 XML.
- `Wiring.hs` (81 lines) — **the whole of the coupling to the DMN backend**, deliberately one module
  and one function wide, one direction only. It indexes the _emitted_ DRG by source `DECIDE`, so a
  decision the DMN population filter dropped is simply absent from the table and its gateway is left
  unwired with a `P-NODMN` note. Re-deriving `decision_<name>` from the L4 source is the defect this
  design exists to make impossible: **a dangling `decisionRef` is unrepresentable, not merely
  unlikely.**

**The fidelity vocabulary.** `F1`–`F5` are losses of the _notation_ (F1: MUST/MAY/SHANT all draw as a
task, so the diagram cannot say which omission is a breach). `P-…` codes are places where _this
exporter_ approximated: `P-NOJOIN`, `P-DEADLINE`, `P-CYCLE`, `P-DANGLING`, `P-BRANCHGUARD`,
`P-DMNWIRED`, `P-NODMN`. The prefix means a BPMN approximation can never be mistaken for a DMN one
(`D-…`) in a combined report.

**Fixtures and goldens — 3 `.l4` sources, 6 golden pairs, 24 files under `expected/`:**

| fixture                          | covers                                                                                                  |
| -------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `offering.l4`                    | three parties, a four-way `RAND`, two `SHANT`s, timer boundary events, a breach terminal                 |
| `handover.l4`                    | a deadline that is a _name_ (no timer, no invented duration), a `RAND` and a `ROR`, lapse timers         |
| `consultation.l4`                | the only one that draws a **converging** parallel gateway                                                |
| `../legal/regcf/regcf.l4` × 3    | the real corpus: a renewing obligation drawn as a loop, `IF`-headed duties with guarded arms, two prohibitions |

Each golden is a pair — `X.bpmn` (the document) and `X.fidelity.txt` (the loss list) — because a BPMN
file with a report bolted onto its front is not a file any tool can open.

**The checkers and the renderer — 12 files under `etc/`:**

- `check-bpmn-soundness.mjs` (796 lines, Node-only, zero dependencies, zero network) — **the gate**.
  Translates the process to a workflow net and explores every reachable marking, reporting van der
  Aalst's S1 (option to complete), S2 (no deadlock), S3 (no dead flow node), S4 (safe / 1-bounded),
  plus `STRUCTURE` findings for a file that lies about its own shape — including a gateway whose
  declared `gatewayDirection` contradicts its own edge counts, which is schema-valid and invisible to
  `bpmn-moddle`, and which shipped once. It refuses loudly (exit 3) on constructs it will not guess
  at rather than passing them. Proper completion is deliberately **not** an error, because the
  exporter emits unjoined `RAND`s on purpose.
- `validate-bpmn.mjs` — the `bpmn-moddle@10` parse, i.e. "will Camunda Modeler open this", plus a
  diagram-interchange check that every node is actually drawn.
- `check-bpmn-kie.sh` + `etc/kie/` (Java harness + pinned `pom.xml`) + `check-bpmn-kie-baseline.mjs` —
  jBPM/KIE 7.74.1, pinned, **executes** the process. Corroboration, not a gate: it explores one
  interleaving, chosen partly by our own adaptation, so it can prove a deadlock exists and never that
  one is absent. `etc/bpmn-kie-baseline.txt` pins, per file, whether it was checked at all, its
  error/warning counts and its verdict token, so a _new_ finding is visible rather than swallowed by
  a tolerated exit 1. Error _text_ is deliberately not pinned.
- `check-bpmn-dmn-refs.mjs` — resolves every `<businessRuleTask>`'s `(namespace, model, decision)`
  against the emitted DMN and fails on a dangling reference.
- `bpmn-to-svg.mjs` (528 lines, zero dependencies) — renders an emitted BPMN to a standalone SVG. It
  is a transform, not a layout engine: BPMN's diagram interchange already carries every coordinate.
  It throws on any construct outside the closed vocabulary `L4.Bpmn.IR` emits, which is the anti-rot
  mechanism.

Three of them ship a `.selftest.mjs` beside them — soundness, the KIE baseline comparator, and the
DMN-reference resolver — and those self-tests are mutation-tested in both directions, because a gate
that invents defects is as broken as one that misses them. `validate-bpmn.mjs` needs no self-test: it
is a thin wrapper over `bpmn-moddle@10`, pinned in its own header.

**Two fixture piles that exist to test the gate itself:** `sound/` holds diagrams the gate must
**not** flag (`joined-beside-breach.bpmn`, the shape that a checker modelling an error end as an
ordinary one-token sink wrongly calls a deadlock); `unsound/` holds five it **must** catch, on a named
property. One of the five is not hand-written — `historical-handover-edge-counted-join.bpmn` is the
verbatim output of the pre-fix exporter, recovered by reverting `addJoin`'s token proof to the
edge-counting predicate it replaced and re-running the CLI.

**The test suite** — `jl4/tests/BpmnExport.hs`, 1,841 lines, 102 `it` blocks across 25 `describe`
groups (counted in the file). It asserts _meaning_, not shape: reachability walks from each timer to
the terminals, token arguments over branch interiors, segment-versus-box arithmetic over the emitted
coordinates, and positive controls throughout, so an exporter that simply stopped emitting timers
would not score. The golden cases lower through the same DMN DRG the CLI does (`drgAsCli`), so they
pin the exporter that actually runs.

---

## Evidence

Quoted from the source PRs.

**The exporter's own defect history (#141).** The first version "passed `bpmn-moddle` at **zero
warnings** and **1581 green examples**" while emitting a converging parallel gateway that counted
edges rather than tokens — a join waiting forever. An adversarial review raised 22 findings of which
7 survived; the author's own pass found 2 more. Among them: `SHANT … WITHIN d` drew both arms
swapped; four `WITHIN` windows dropped in silence; 12 edge segments passing through unrelated nodes
and 40 collinear overlaps; and a cubic layout — "400 nodes / 5 lanes = 10.95s; the same graph at 1
lane = 0.13s". That PR closed at `1718 examples, 0 failures`.

**Why the token game and not the parser (#157).** On real pre-fix exporter output:
`bpmn-moddle` said "**OK — 0 warnings**, 15 flow nodes, 16 sequence flows, all drawn";
`check-bpmn-soundness.mjs` said "**UNSOUND**, S1+S2+S3 fail; `Join_1` starved". "bpmn-moddle passes
**all four** defective files at zero warnings. That is the case for the gate." Also measured there:
"`consultation.bpmn` and `offering.bpmn` are **byte-identical** pre- and post-fix. A golden suite of
those two would have shown nothing." And a false positive in the KIE census, once fixed: "offering
stable at 0 findings over 8 runs alone and 8 in the combination that used to fail 15/15." Suites at
that point: `check-bpmn-soundness.selftest.mjs` "8 fixtures, 0 failures"; `validate-bpmn.mjs` over
all 8 "8 OK, 0 warnings"; `jl4-test` 1807/0; `l4-cli-test` 87/0.

**Coverage, honestly counted (#157 → #162).** #157 measured "exactly **one** `exclusiveGateway` and
**zero** `conditionExpression`s and **zero** `default` flows" across the goldens then committed, and
said branching had never been exercised on exporter output. After the Reg CF goldens landed, #162
re-measured over the six: "**4** exclusive gateways, **4** parallel, **7** `conditionExpression`s,
**0** `default` flows", and its agreement table was corrected to list all 12 fixtures — "jBPM
compiles 6 and rejects 6".

**The `businessRuleTask` form was measured, not chosen (#198).** Seven probe files through both
checkers: "`bpmn-moddle` accepted **all seven at zero warnings** — so the K4 acceptance signal could
not have chosen … jBPM accepted **only G and H**." A bare `businessRuleTask`, `camunda:decisionRef`,
`zeebe:calledDecision` and a DMN `implementation` URI + `<import>` are each rejected; form G (the
Drools DMN language URI + standard `ioSpecification` data inputs) is `errors=0 warnings=0`. Form G
ships: "One vendor-specific _string_, zero vendor-specific _elements_." Negative controls were run
both ways — a hand-broken reference that pointed at a DMN `@id` rather than a decision `@name` exits
1 with "1 dangling reference(s)", and deleting a shape from a scratch copy exits 1 with
"`bpmn:BusinessRuleTask Decide_0` has no diagram interchange".

**Where the goldens stand with all three checkers (#198, verbatim):**

```
$ node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/expected/*.bpmn   # exit 0
consultation.bpmn      [the consultation]:              SOUND  (S1–S4 PASS)
handover.bpmn          [the handover]:                  SOUND  (S1–S4 PASS)
offering.bpmn          [the offering]:                  SOUND  (S1–S4 PASS)
regcf-advertising.bpmn [advertising restriction]:       SOUND  (S1–S4 PASS)
regcf-reporting.bpmn   [ongoing reporting obligation]:  SOUND  (S1–S4 PASS)
regcf-resale.bpmn      [resale restriction]:            SOUND  (S1–S4 PASS)
```

`validate-bpmn.mjs` over the same six plus `sound/joined-beside-breach.bpmn`: "OK — 0 warnings … all
drawn" on each. The three self-tests: `check-bpmn-soundness.selftest.mjs` "12 fixture(s) checked, 0
failure(s)"; `check-bpmn-kie-baseline.selftest.mjs` "PASS — 0 failure(s)";
`check-bpmn-dmn-refs.selftest.mjs` "PASS — 0 failure(s)". The reference resolver over the goldens and
the corpus DMN: "regcf-advertising.bpmn: OK — 1 businessRuleTask reference(s), all resolve" (and the
same for reporting and resale; the other three have no `businessRuleTask` to resolve).

**jBPM's standing, per file, and what it means (#186, re-measured 2026-08-01, jbpm-bpmn2 7.74.1.Final,
JDK 17.0.20):** consultation COMPLETED (0 errors); offering "ABORTED via error end event [Breach] —
modelled terminal, the LEST arm doing its job"; handover REJECTED (4), regcf-advertising REJECTED (4),
regcf-resale REJECTED (6) — all class (b), jBPM compiling our deliberately opaque L4-text
`conditionExpression` bodies as Drools; regcf-reporting REJECTED (1) — `Unknown gateway direction:
Mixed`, where `Mixed` is legal BPMN 2.0 §10.5.2 and jBPM has no node for a gateway that is both split
and join. That last one is **not fixable at the attribute level, measured**: "all four
`gatewayDirection` values run against the real 2-in/3-out gateway, all four rejected". The planned
remedy "was implemented, run, **falsified the same day**, and reverted before it shipped."

**Suite totals across the run of PRs, as reported:** `jl4-test` 1718/0 (#141) → 1807/0 (#157) →
1841/0 (#162) → 2102/0 (#186) → 2222/0 (#198); `l4-cli-test` 87/0 (#157) → 125/0 with DMN engines live
(#186) → 180/0 with 79 pending (#198).

**A contradiction found by the verify pass and fixed (#198).** `guardShape` resolved a gateway's guard
to a decision by `Unique`, and a `Unique` says which `DECIDE` a guard applies, not what it applies it
to. `IF conforms a THEN … ELSE IF conforms b THEN …` produced arm conditions
`["conforms", "not(conforms) and conforms", "not(conforms) and not(conforms)"]` — the second arm
unsatisfiable, so "the diagram silently asserted that a perfectly reachable obligation can never be
reached." Byte-neutral on the corpus; the guard shape now refuses unless every atom naming the
decision is the same atom text.

**Unmeasured, and said so (#198):** whether Camunda Modeler's DMN-link UI lights up without
`camunda:decisionRef`, and whether Camunda 8 / Zeebe would _execute_ the delegation without
`zeebe:calledDecision`, is not measured. `bpmn-moddle@10` is what bpmn-js parses with and it accepts
every golden at zero warnings, so the file _opens_ — that is the whole of the claim.

---

## Independence

**This PR is not standalone. It sits on top of four siblings and cannot compile without two of them.**

Hard code dependencies:

- **`ladder-viz`** owns `jl4-core/src/L4/StateGraph.hs`, which is the exporter's entire input.
  `main` already has a `L4.StateGraph`, but not the one `L4.Bpmn.Lower` imports: it exports neither
  `FanKind`, `BranchGuard`, `GuardAtom`, `branchGuardAtoms`, `renderBranchGuard` nor `lestArmWording`,
  all of which `Lower.hs` uses. **This will not compile against `main`'s `StateGraph`.** That theme
  also carries the #159 caption fix, whose wording several goldens' edge labels encode — a `SHANT`'s
  `LEST` arm reads `violation`, a lapsed `MAY` reads `lapses`, and a modal with no `WITHIN` reads
  `unreachable: no WITHIN`. Land `bpmn-export` without it and those goldens are wrong text.
- **`dmn-export`** owns `jl4-core/src/L4/Interchange/Fidelity.hs` (the shared report type every `F…`
  and `P-…` note is built from) and `jl4-core/src/L4/Dmn/IR.hs` (which `L4.Bpmn.Wiring` reads to build
  its table). It also owns `jl4/tests/DmnExport.hs`, from which `BpmnExport.hs` imports `drgAsCli` —
  a literal `import DmnExport (drgAsCli)` at line 35. And the three `regcf-*` goldens' wiring elements
  name decision ids minted by the DMN backend, so a `dmn-export` that lands in a different shape moves
  these goldens.
- **`service-cli`** owns `jl4/app/L4/Cli/Export.hs` — the `l4 export --to=bpmn --rule NAME
  --fidelity-report` front door. Without it the exporter is a library nothing calls, and the READMEs'
  copy-pasteable reproductions do not run.
- **`corpus-regcf`** owns `jl4/examples/legal/regcf/regcf.l4`. Three of the six goldens are cut from
  it by `l4 export`, so they are byte-sensitive to it: PR #172's rule-version work and the
  Rule 501(a) anniversary fix (`4fec076e`) each re-blessed `regcf-*` goldens.
- **`ci-build`** owns `.github/workflows/pr-checks.yml`, which hosts the BPMN Soundness job (a
  required status check), the `bpmn` path filter, and the `businessRuleTask` resolver step. #157
  records that `'**/*.js'` does not match `.mjs`, so a PR of only these files once ran **zero** jobs —
  meaning without the `ci-build` half, none of the gates described above actually run on a PR.
- **`specs`** owns `specs/todo/lexipedia-superset/PROCESS-TRACK.md`, the document that rules the
  acceptance bar (§8), classifies jBPM's objections (§8.1) and records the wiring design (§8.3). Per
  the repo's "a decision is recorded in its owning document in the same PR" rule, those rulings live
  there, not here; the code comments cite section numbers into that file.

Not owned by any theme manifest: **`jl4-core/jl4-core.cabal`** must list the four new `L4.Bpmn.*`
modules and **`jl4/jl4.cabal`** must list `BpmnExport` in `jl4-test`'s `other-modules`. Whoever
assembles the stack needs to carry those two edits with this PR or it will not build.

Genuinely self-contained within this PR: the four `etc/` checkers and the SVG renderer are Node-only
with zero runtime dependencies and no network, and their self-tests run without a Haskell build at
all — they read committed `.bpmn` files. The `sound/` and `unsound/` piles are hand-written or
historically-recovered XML and depend on nothing.

**One piece of housekeeping a reviewer will notice.** The twelve `expected/*.golden` files are
byte-identical duplicates of their bare-name siblings (verified by sha256 on all six pairs). The
harness reads the bare name — `goldenFile = root </> "expected" </> (out <> ext)` — so nothing reads
the `.golden` twins. They arrived in the evil merge `904192ea` that PR #183 documented as adding 20
duplicate goldens present in neither parent; the DMN half was deleted in `e692023a` and the BPMN half
was not. They are carried here because they are in the tree, and they are a safe deletion.

---

## Risk if rejected

Drop this and L4 has no process projection at all: the regulative layer becomes the one layer with no
externally-readable artifact, the lexipedia comparison loses the half of its argument that is about
BPMN, and `PROCESS-TRACK.md`'s track P1 and §8.3 wiring mandate have no implementation to point at.
The four `etc/` checkers go with it, and with them the only thing that ever tests a BPMN artifact at
all. The `dmn-export` sibling is unharmed — the coupling runs one way, from `L4.Bpmn.Wiring` into
`L4.Dmn.IR` — but it loses the named consumer that §16.5 of the DMN spec now points at for the
verdict-decision shape.

---

## Provenance

Unstable PRs folded into this one:

- **#141** — `mengwong/bpmn-export`: the original exporter (`L4.Bpmn.{IR,Lower,Emit}`), the first
  fixtures and goldens, and the nine defects an adversarial review found. Not listed in the theme
  manifest, but `git log` attributes `8df9205d` and the whole first wave of `L4/Bpmn/` commits to it.
- **#154** — `feat/export-surfaces`: `l4 export --to=dmn|dmn-md|bpmn`, the `--rule` / `--fidelity-report`
  / `--fail-on` surface. (The CLI module itself is in the `service-cli` theme; what lands here is the
  goldens' agreement with it.)
- **#157** — `test/bpmn-kie-checker`: the soundness gate, the jBPM/KIE harness, the `sound/` and
  `unsound/` piles, and the historical-output measurement. No Haskell changed.
- **#159** — `fix/stategraph-modal-labels`: the `LEST` caption derivation, whose wording the goldens
  encode. (Code in `ladder-viz`; `BpmnExport.hs` gains "the LEST caption where BPMN actually consumes
  it".)
- **#162** — `feat/regcf-projections`: BPMN cut from the real corpus, `IF`-headed rules, `TargetSelf`
  loops, branch guards on flows, `gatewayDirection` computed from edges and gated.
- **#172** — `mengwong/regcf-rule-version`: re-blessed goldens and a two-line `BpmnExport.hs` change
  riding the rule-version axis.
- **#183** — `mengwong/bkm-phase4-unlift`: DMN Phase 4; touches this theme only through the evil merge
  that introduced the duplicate `.golden` twins noted above.
- **#186** — `mengwong/bpmn-bar-ruling`: the acceptance bar (acceptance + soundness, engine execution a
  non-goal), the two-class decomposition of jBPM's rejections, the class-(a) remedy measured and
  falsified.
- **#198** — `mengwong/bpmn-dmn-wiring`: `L4.Bpmn.Wiring`, the `businessRuleTask` form probe, the
  verdict/guard/refuse shapes, `check-bpmn-dmn-refs.mjs`, and the one-decide-is-not-one-question fix.
- **#224** — `mengwong/go-explainer`: `etc/bpmn-to-svg.mjs`, so the emitted diagrams can be inlined in
  the explainer.
