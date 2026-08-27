# Specification: Call Graphs, Materiality, and Counterfactual Explanation

**Status (2026-08-27): PROPOSED, not implemented.** Nothing below ships except where a section
explicitly says "exists today" and names the module or command. The empirical claims in §4 were
measured on 2026-08-27 with the installed `l4` binary dated 2026-08-04 (`~/.local/bin/l4`) against
the corpus at `origin/unstable` commit `3c5acd1a`; the exact protocol is in Appendix A. The static
dependency graph this spec consumes is owned by `GLOBAL-DEPENDENCY-GRAPH-SPEC.md` and is also not
yet built; this spec adds visualization and counterfactual analysis as a second and third consumer
of that graph, and does not re-decide anything that spec owns.

## 1. Motivation

A reader of an L4 corpus — a drafter, a reviewer, a citizen using a generated wizard, an LLM
calling the reasoner API — asks three questions in ascending order of value:

1. **Structure**: what does this top-level decision depend on? Which definitions feed it, which
   inputs reach it, and through what intermediate concepts?
2. **History**: in _this_ run — these facts, this scenario — what actually happened? Which rules
   fired, with what values, producing what result?
3. **Counterfact**: what would have changed the outcome? Which facts were _material_, and what is
   the smallest change to the world under which the answer flips?

Question 1 is a static call graph. Question 2 is a concrete evaluation trace projected onto it.
Question 3 is the one lawyers are actually paid to answer, and it is _not_ answerable from either
of the first two alone — which is the central design claim of this spec.

The distinction that matters is **reached versus material**. A subexpression is _reached_ when the
evaluator forced it; it is _material_ when some admissible change to it changes the verdict. L4's
evaluator is lazy and its connectives short-circuit (`And`/`Or`/`Implies` desugar to `IfThenElse`
in `L4.EvaluateLazy.Machine`), so the trace records only what was forced: an unevaluated call site
is _absent_ from the trace, not marked. Reached is therefore neither necessary nor sufficient for
material, and a visualizer that renders only the trace silently teaches its reader the but-for
fallacy (§2).

## 2. The materiality ladder

Four notions, in ascending strength. The gaps between rungs are where the design decisions live.

| Rung | Notion            | Definition                                                                                      | Computed from     |
| ---- | ----------------- | ----------------------------------------------------------------------------------------------- | ----------------- |
| M1   | Reached           | the evaluator forced this node in this run                                                      | trace alone       |
| M2   | Pivotal (but-for) | flipping this one fact alone flips the verdict                                                  | decision function |
| M3   | Material (NESS)   | this fact belongs to some _minimal set_ whose joint change flips the verdict                    | decision function |
| M4   | Responsibility    | graded: 1/(k+1) where k is the size of the smallest accompanying contingency (Chockler–Halpern) | decision function |

**The overdetermination trap (why M2 is the wrong implementation).** Consider an `OR` whose
disjuncts are both true — two independent qualifying routes. Flip either alone and the verdict
stands, so per-fact flip sensitivity (M2) marks _both_ immaterial. This is precisely the
two-fires-burn-the-house case where but-for causation fails and Wright's NESS test — necessary
element of a sufficient set — was invented to succeed. NESS is, almost verbatim, membership in a
prime implicant consistent with the instance. Rung 0 produced this trap as a concrete artifact: see
finding **F6** in §4 — tracing `either route` applied to `TRUE, TRUE` renders a trace in which the
second `TRUE` disjunct _does not appear at all_. A materiality engine must therefore compute
membership in minimal flip **sets**, never per-node sensitivity.

**The duality (why one engine feeds two explanations).** In the formal-explainability vocabulary,
minimal sufficient reasons (abductive explanations, AXps — "why yes") and minimal counterfactuals
(contrastive explanations, CXps — "what would make it no") are each other's minimal hitting sets,
in Reiter's sense. One enumeration engine therefore emits both sentences the wizard should say:
_"you qualify because {A, C} suffices"_ and _"the nearest ways this changes: drop A, or drop C and
E."_ Miller's survey argues people ask contrastive why-questions — _why P rather than Q_ — so the
CXp side is the one end-users want, and it is exactly the side the trace cannot produce (F6).

**Tractability.** The question-ordering work already builds ROBDDs per decision, and `l4 verify`
already merges syntactically identical leaves by the same stable `atomId` the web wizard uses
(observed in its own output header, F10). On a BDD, the minimum-cardinality counterfactual is a
shortest path from the instance to the opposite terminal — linear in BDD size. Full AXp/CXp
enumeration via hitting-set duality is comfortable at statutory scale (dozens of atoms). Numeric
atoms arrive pre-phrased as threshold predicates, which is the form the NLG wants anyway.

## 3. What exists today (survey, verified 2026-08-27)

| Piece                                            | Where                                                                                                                                   | State                                  |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| Concrete-run trace → DOT                         | `l4 trace` (`jl4/app/L4/Cli/Trace.hs`), renderer `L4.EvaluateLazy.GraphViz2.traceToGraphViz` over `EvalTrace` (`L4.EvaluateLazy.Trace`) | **ships**; measured in §4              |
| Trace over the decision service                  | `POST /functions/:name/evaluation?trace=full&graphviz=true` (`jl4-service`)                                                             | ships                                  |
| Trace in the IDE                                 | `jl4-lsp` `Inspector.hs` receives the trace and discards it (`_mtrace`, two sites)                                                      | **computed, then thrown away**         |
| Regulative automaton → DOT                       | `l4 state-graph` (`L4.StateGraph`)                                                                                                      | ships; measured in §4                  |
| Static per-DECIDE propositional audit            | `l4 verify` (unsatisfiable rules, dead branches, vacuous guards; CNF-based; wizard-shared `atomId`)                                     | ships; boolean DECIDEs only            |
| "Which inputs still matter"                      | `jl4-query-plan` (`BooleanDecisionQuery`, `VarImpact`), surfaced via LSP `l4/queryPlan`                                                 | ships; intra-decision                  |
| Edge relation "who does this DECIDE reference"   | `freeRefs` + `classifyRef` in `L4.Dmn.Lower`, feeding DRD `informationRequirement` edges                                                | ships, but private to the DMN exporter |
| Reachability + topological rank over definitions | `UnitGraph`/`closure`/`rankByBlockId` in `L4.Export.Document`                                                                           | ships, private to the export path      |
| Global dependency graph                          | `GLOBAL-DEPENDENCY-GRAPH-SPEC.md` → `L4.DependencyGraph`                                                                                | **specified, not built**               |
| Intra-decision visualization                     | ladder pipeline: `L4.Viz.Ladder` → custom LSP methods → webview                                                                         | ships                                  |
| Partial-evaluation shading vocabulary            | `specs/done/PARTIAL-EVAL-VISUALIZER-SPEC.md`: live / short-circuited / irrelevant; Not Asked / Still Needed / Don't Care                | shipped for ladders                    |

The pattern: every ingredient exists, each private to one consumer. The call-graph visualizer is
mostly a _unification_ — one graph, three queries (structure, history, counterfact) — plus one
genuinely new component, the materiality engine (§5, D3).

## 4. Rung 0 findings (measured)

Protocol in Appendix A. Corpus subset: Reg CF (`legal/regcf/regcf.l4`), BNA (`legal/bna/bna.l4`,
42 `#ASSERT` scenarios + 1 `#EVAL`), CEO performance award (25 `#EVAL`, regulative), promissory
note (4 `#EVAL`, regulative), `ok/ledger/bitemporal-recall.l4`, plus a controlled micro-experiment
(Appendix A.2).

- **F1 — it works, fast, corpus-wide.** 43 BNA traces in under 2s; no failures on any chosen file.
  `maxTraceNodes` truncation was never hit (largest graph: 361 nodes).
- **F2 — the trace is a tree, not a graph.** Edges = nodes − 1 in almost every output (BNA
  eval3: 361/360; the CEO award's largest: 261/262, exactly one shared-binding join). The
  binding-dedup machinery exists but sharing almost never survives to the picture. There is no
  call-graph _shape_ today; there is an expression tree.
- **F3 — corpus-scale outputs are posters, not diagrams.** The BNA `#EVAL` renders at 21818×2581 px
  at 72dpi (aspect ratio 8.5:1). Every large trace has the same pathology: top-down layout of a
  wide shallow tree.
- **F4 — most ink is redundancy.** Node labels embed the full text of the subexpression, so a
  parent's label textually contains its children's labels. The poster width of F3 is mostly this.
- **F5 — nullary bindings produce vacuous traces.** All four promissory-note directives trace
  nullary top-level bindings (e.g. `Monthly Installment Amount`); all four traces are a
  _single node_ — result with no derivation. Confirmed in isolation: a fresh module whose only
  directive traces a nullary `v` defined as `q OR p` still yields one node. Since bare-NOUN
  verdict constants are the dominant idiom in the legal corpus, **the most natural directive a
  legal author writes is exactly the one that yields no explanation.**
- **F6 — short-circuit absence, including the overdetermination trap.** Tracing `either route`
  applied to `TRUE, TRUE` (body `a OR b`) yields three nodes: the application, the function, and
  `a`. The second disjunct — also TRUE, also a qualifying route — is invisible. A reader concludes
  `b` did not matter; NESS says both routes are material. The trace, read naively,
  _teaches the but-for fallacy_.
- **F7 — argument nodes carry useless labels.** Forced arguments appear as nodes labeled by an
  internal parameter name (`a`), not the formal parameter name or the call-site expression. The
  unexplained little `a → TRUE` boxes in the CEO award traces are these.
- **F8 — ledger operations reach the trace.** In `bitemporal-recall.l4`, `RECORD`, `RECALL`, and
  `EVAL UNDER VALID TIME OF (DATE ...)` all appear as labeled trace nodes with values (`JUST OF 7`,
  `NOTHING`). The raw material for typed history counterfactuals (§6.3) already survives into the
  trace; nothing distinguishes the time axes in the rendering.
- **F9 — the state-graph skeleton is right, and stops exactly where the design begins.**
  `l4 state-graph` on the CEO award and the promissory note produces clean automata: obligation
  states, green fulfil edges, red dashed timeout/breach edges, terminal `Fulfilled`/`Breach`, and
  even static reachability annotations ("unreachable: no WITHIN"). Missing: winning-region
  shading, concrete `#TRACE` overlay, frontier marking (§6.1–6.2).
- **F10 — `l4 verify` is the embryo of the materiality engine, scoped to one DECIDE.** It audits
  the boolean decision skeleton per definition (everything non-boolean: "NOT ANALYSED"), CNF-based,
  with atoms coalesced by the wizard's stable `atomId`. The atom-identity layer D3 needs already
  exists and is already shared with the wizard; what is missing is inter-definitional scope,
  instance-relative analysis (verify is instance-free), and non-boolean leaves.

## 5. Design — decision-logic side

### D1. Static call graph = `L4.DependencyGraph` + a renderer

Build the graph `GLOBAL-DEPENDENCY-GRAPH-SPEC.md` specifies (its rulings govern; nothing here
overrides them), lifting `freeRefs`/`classifyRef` out of `L4.Dmn.Lower` and subsuming
`Export.Document`'s `UnitGraph`. Add a renderer to DOT (and Mermaid, for embedding) and a CLI
entry point (working name `l4 graph`; naming is R5). Filters: rooted at a chosen definition
(forward slice), reverse (who consumes this definition), depth-bounded. Node kinds follow that
spec's table; edge meaning is **"is defined in terms of"** — never control flow (§7).

Immediate legal payoffs, before any trace is involved: unreachable definitions from the entry
points = surplusage (a drafting smell with a canon named after it); high fan-in nodes = definitional
concentration risk — the single definition on which many rules hinge is where an ambiguity does the
most damage; SCCs = circular definitions.

### D2. Call-shaped collapse of the trace

Fix F2/F4/F5/F7 in the trace **post-processing** (a sixth stage after the existing five in
`L4.EvaluateLazy.Trace`, or in `GraphViz2` — placement is R2), not in the abstract machine:

- Collapse to **binding-grained** nodes: one node per (definition, application), labeled
  `name(args…) = result`, eliding the intermediate expression spine. F4 disappears with it.
- Correlate argument thunks to formal-parameter positions so argument nodes read
  `borrower's income = 42000`, not `a = 42000` (F7). The trace records `Enter (App n es)` and the
  thunk allocations; the correlation is bookkeeping, not new machinery.
- **Nullary bindings must trace their defining body** (F5). Whether that is an evaluator change
  (trace the thunk force under the directive's extent) or a post-processing change (splice the
  binding's own trace at its use site) is R1 — but the acceptance test is fixed: the promissory
  note's four directives must each produce a derivation tree, not a single node.
- Shared bindings render once with fan-in (restoring the graph-ness that F2 shows is lost).

### D3. The materiality engine and the overlay

The genuinely new component. Given a decision (rooted subgraph of D1) and an instance (the facts
of a run):

1. Compile the boolean skeleton to a BDD over wizard-`atomId` atoms — the compilation `l4 verify`
   and `jl4-query-plan` already perform intra-decision; the extension is inter-definitional
   (inline through the call graph to a chosen abstraction boundary, R3).
2. Enumerate AXps (minimal sufficient sets) and CXps (minimal flip sets) for the instance, via
   shortest-path for minimum cardinality and hitting-set duality for enumeration.
3. Annotate the D1 graph, per node: **reached** (from the D2 trace), **materiality class** (member
   of some CXp / some AXp / neither), and **responsibility grade** 1/(k+1) for continuous shading.
4. Render the overlay with the `PARTIAL-EVAL-VISUALIZER-SPEC.md` vocabulary: _live_ (reached and
   material), _short-circuited_ (unreached but still material — the branch the trace hides, F6),
   _irrelevant_ (no admissible change here can affect the outcome).

The same engine exports prose: "because {…}" from the covering AXp, "unless {…}" from the nearest
CXps — the wizard's explanation text and the LLM tool-call payload, from one computation.

### D4. Defeat edges

Where `SUBJECT TO` / rule-priority structure is in play, "why did rule R not apply" needs a
defeat-shaped answer, not a truth-functional one: _R was reached, would have fired, and was
defeated by exception E_. The subjection relation is an attack graph over rules (Dung); render
defeat as a distinct edge type, never as just another AND-NOT — flattening it loses exactly the
structure lawyers care about. (This is the third SUBJECT-TO consumer datapoint, after the
LegalRuleML and read-side work.)

### D5. Interactive folding is the answer to poster scale (ruled 2026-08-27)

A corpus-scale call tree need not fit a screen statically: the diagram folds and unfolds in
response to user clicks (ruling, 2026-08-27, addressing F3). Three consequences:

- **The fold boundary is the binding** — D2's call-shaped node. Folding collapses a definition's
  subtree to `name = value`; unfolding reveals its derivation. The reader navigates the same
  abstraction boundaries the drafter wrote, so fold state is a _view_ of the explanation, never a
  different explanation.
- **The default expansion state is materiality-driven** (D3): open along the live path, folded
  over short-circuited and irrelevant branches. The diagram opens showing _why_, with "what else
  could have mattered" one click away — the M1–M4 ladder doubles as the initial-view heuristic.
- **Format ladder.** `dot` remains for print and CI artifacts (posters are fine on paper); a
  **self-contained interactive HTML** (embedded SVG + fold state, no server) is the pipeline
  artifact and shareable form; the IDE webview (R6) renders the same payload live. All three
  consume one JSON topology, following the ladder pipeline's topology-only wire discipline.
- **Selection-synchronized commentary** (ruled 2026-08-27): the interactive form carries a
  commentary panel whose content tracks the most recently clicked node. Every commentary source is
  deterministic and already exists: the definition's source span and citation (the resolved AST
  carries ranges), its `@desc`/`@ref` annotations (the DOT renderer already harvests `@desc`), its
  value in this run (D2), and its materiality sentence from D3 — _"material: member of minimal
  flip set {…}"_ / _"unless …"_ scoped to the selected node — with `l4 nlg` linearization of the
  definition as an optional fifth. The panel is the explanation engine narrating one node at a
  time; LLM free-text elaboration is a later, optional layer and must be grounded in exactly this
  payload (the guardrailed left-brain/right-brain division of labour), never a replacement for it.

## 6. Design — event-trace side

### 6.1 The sliding-doors moment is a frontier crossing

On the regulative automaton (F9's skeleton), partition states by backward reachability: **open**
(both `Fulfilled` and `Breach` still reachable) versus **committed** (one verdict inevitable). A
pivotal event is a transition crossing the frontier — before it `EF fulfilled ∧ EF breach`, after
it `AG ¬fulfilled`. In runtime-verification terms this is LTL₃'s three-valued verdict leaving
_inconclusive_; in Kupferman–Vardi terms, the prefix becoming bad. Computation is backward
reachability on the automaton `l4 state-graph` already extracts — cheap; the timed refinement
(deadline clocks) is UPPAAL-shaped and deferred.

Two corollaries. **The most common pivot is an omission**: nobody acts, and at the deadline the
region flips. Causation-by-omission is a famous problem for counterfactual theories of causation;
in the automaton it dissolves — the timeout is an explicit LEST transition, as renderable as any
act. And **the frontier is where materiality is actionable**: before the crossing, "this fact is
material" is compliance advice ("you are still in the open region; the transition that closes it
fires on June 30"); after it, an autopsy. This extends the wizard's prospective mode (in the
argumentation literature: Odekerken–Bex _stability_ — can any future information change the
status?) from decision inputs to event sequences.

### 6.2 Trace counterfactuals: the metric is doctrine

"Minimal significant counterfactual" over a trace = minimal admissible edit (insert / delete /
retime events) reaching the other region. _Admissible_ is a legal parameter, not an algorithmic
one: breach analysis intervenes on the defendant's choices holding the claimant's fixed;
mitigation reverses that; frustration intervenes on neither. The **intervention set — whose
sliding doors were theirs to walk through — must be an explicit query parameter.** Preemption
(two breaches, the first triggers termination; Suzy's rock lands first) is native here: but-for
fails on the second, Halpern–Pearl witnesses handle it, and insurance proximate-cause doctrine
(_Wayne Tank_) is recognizably the same causal-selection problem.

Rendering: red-dot the frontier crossings on the concrete `#TRACE` run (the counterexample-
explanation idiom of Beer et al.); render the minimal admissible deviation as a **ghost branch** —
actual trace solid, counterfactual translucent from the pivot state, annotated "had X paid by
June 30".

### 6.3 Typed history counterfactuals through the ledger

Flat flip-sets have a consistency problem: history facts are entangled ("payment received March 3"
vs "paid in full"). Pearl's answer — intervene on exogenous variables, propagate through the
structural equations — and the ledger _is_ the structural model, made explicit: `RECORD`ed events
are exogenous, everything `RECALL`ed is derived (F8 shows these already reach the trace).
Counterfactuals over history are therefore interventions on base events with derivations
recomputed, and the bitemporal + rule-version axes **type** them:

| Axis                                           | Counterfactual                                  | Legal character                                          |
| ---------------------------------------------- | ----------------------------------------------- | -------------------------------------------------------- |
| valid time                                     | had the event not occurred                      | usually incurable (the accident happened)                |
| transaction time                               | had it been recorded / attested / known in time | often curable (rectify the record, file late with leave) |
| rule version (`EVAL UNDER RULES EFFECTIVE AT`) | had the amendment been in force                 | the legislature's; transitional-provision analysis       |

An explainer that reports _which axis the nearest counterfactual lives on_ is telling the client
whether anything can still be done — the difference between analysis and advice.

## 7. Non-goals and cautions

- **Not a flowchart.** The house position (`doc/concepts/language-design/logic-not-flowcharts.md`)
  stands. D1 edges mean "is defined in terms of"; 6.1's automaton edges mean "event/timeout"; no
  edge anywhere means "then do". Any rendering that invites a control-flow reading is wrong.
- **No silent per-node sensitivity.** M2 must never ship as the materiality semantics (§2). If a
  cheap mode is wanted, it must be labeled as but-for and visually distinct.
- **Label elision policy** for large records/lists on concrete runs is required before corpus-scale
  overlays are attempted. Folding (D5) answers _structural_ size (F3); elision is still owed for
  the value payload inside a single node (F4's cousin), and the commentary panel is the right
  home for the full value a node's label elides.
- **The metric-is-doctrine parameter (6.2) must be surfaced, not defaulted invisibly.** A tool that
  silently picks the intervention set is doing legal reasoning without saying so.
- This spec does not modify `#EVALTRACE`/`#TRACE` surface syntax and does not touch the exactprint
  or `prettyLayout` printers.

## 8. Open rulings

Recorded here when answered, per repo convention (`CLAUDE.md` §4).

- **R1 — nullary trace repair site** (F5): evaluator (trace the thunk force under the directive's
  extent) vs post-processing (splice the binding's trace at the use site)? Acceptance test fixed
  in D2 either way.
- **R2 — collapse placement** (D2): a sixth `Trace.hs` post-processing stage, or inside
  `GraphViz2`? The former benefits every consumer (text renderer, service, future IDE), and is the
  working assumption.
- **R3 — inlining boundary for the materiality BDD** (D3): inline through the whole call graph, or
  stop at `@export`/`GIVEN` boundaries and treat sub-decisions as atoms? Interacts with BDD size
  and with what the wizard treats as one question.
- **R4 — winning-region computation site** (6.1): inside `L4.StateGraph` (it already computes
  static reachability, F9) is the working assumption.
- **R5 — CLI surface**: extend `l4 trace` / `l4 state-graph` with flags, or a new `l4 graph`
  subcommand for D1 + overlays? Interacts with the pipeline artifact set (a per-subject
  `callgraph.dot` / `.mmd` joining `PROJECTIONS.md`).
- **R6 — IDE transport**: a custom `l4/callGraph` LSP method following the seven existing custom
  methods, feeding a webview; the LSP-standard call-hierarchy protocol (unimplemented today) as a
  cheap tree-view complement, or skipped? _Partially answered 2026-08-27 (see D5): the primary
  rendering mode at corpus scale is interactive fold/unfold with selection-synchronized
  commentary; what remains open here is transport only, and the wire payload must carry the
  per-node commentary sources._
- **R7 — defeat-edge source of truth** (D4): derived from SUBJECT-TO structure at which stage?
  Owned jointly with the SUBJECT-TO spec; record the ruling there and cite it here.
- **R8 — trace-counterfactual admissibility syntax** (6.2): how does a query name its intervention
  set? (Per-party? Per-action-class? Both?)

## 9. From spec to paper

The paper this spec carries: _"Reached versus Material: counterfactual explanation for
computational law"_ (working title). Mapping: §1–§2 → motivation + theory (the ladder, the
overdetermination trap, AXp/CXp duality applied to statutes); §6 → the trace extension (frontier
crossings as the formal semantics of the pivotal event; the metric-is-doctrine observation; typed
bitemporal counterfactuals — the claimed novelty, since the XAI literature does not type its
counterfactuals by time axis and legal remediability); §4 → the implementation-experience section
(F5 and F6 as evidence that trace-only explanation is not merely incomplete but actively
misleading); D3/6.3 → system description. Venue: ICAIL or JURIX; the argumentation-theory framing
(D4, stability) also fits COMMA. Related-work skeleton is §10 — all 22 references verified against
primary sources on 2026-08-27.

## 10. References (verified 2026-08-27)

- R.W. Wright, "Causation in Tort Law", _California Law Review_ 73:1735 (1985).
- H.L.A. Hart & T. Honoré, _Causation in the Law_, 2nd ed., Clarendon Press (1985).
- J.Y. Halpern & J. Pearl, "Causes and Explanations: A Structural-Model Approach. Part I: Causes",
  _BJPS_ 56(4):843–887 (2005).
- J.Y. Halpern, _Actual Causality_, MIT Press (2016).
- H. Chockler & J.Y. Halpern, "Responsibility and Blame: A Structural-Model Approach", _JAIR_
  22:93–115 (2004).
- H. Chockler, J.Y. Halpern & O. Kupferman, "What Causes a System to Satisfy a Specification?",
  _ACM TOCL_ 9(3) (2008); note the 2010 TOCL erratum if leaning on technical results.
- I. Beer, S. Ben-David, H. Chockler, A. Orni & R. Trefler, "Explaining Counterexamples Using
  Causality", CAV 2009; journal version _FMSD_ 40(1):20–40 (2012).
- A. Bauer, M. Leucker & C. Schallhart, "Runtime Verification for LTL and TLTL", _ACM TOSEM_
  20(4) (2011).
- O. Kupferman & M.Y. Vardi, "Model Checking of Safety Properties", _FMSD_ 19(3):291–314 (2001).
- D. Lewis, _Counterfactuals_, Harvard University Press / Blackwell (1973).
- R. Reiter, "A Theory of Diagnosis from First Principles", _AIJ_ 32:57–95 (1987).
- A. Ignatiev, N. Narodytska & J. Marques-Silva, "Abduction-Based Explanations for Machine
  Learning Models", AAAI 2019.
- A. Ignatiev, N. Narodytska, N. Asher & J. Marques-Silva, "From Contrastive to Abductive
  Explanations and Back Again", AIxIA 2020 (Springer LNCS volume published 2021).
- A. Darwiche & A. Hirth, "On the Reasons Behind Decisions", ECAI 2020, 712–720.
- T. Miller, "Explanation in Artificial Intelligence: Insights from the Social Sciences", _AIJ_
  267:1–38 (2019).
- P.M. Dung, "On the acceptability of arguments…", _AIJ_ 77:321–357 (1995).
- T. Bench-Capon, "Persuasion in Practical Argument Using Value-based Argumentation Frameworks",
  _J. Logic and Computation_ 13(3):429–448 (2003).
- A.J. García & G.R. Simari, "Defeasible Logic Programming: An Argumentative Approach", _TPLP_
  4(1–2):95–138 (2004).
- X. Fan & F. Toni, "On Computing Explanations in Argumentation", AAAI 2015, 1496–1502.
- D. Odekerken, A. Borg & F. Bex, "Estimating Stability for Efficient Argument-Based Inquiry",
  COMMA 2020; D. Odekerken, F. Bex, A. Borg & B. Testerink, "Approximating stability for applied
  argument-based inquiry", _Intelligent Systems with Applications_ 16 (2022) — the Netherlands
  Police intake deployment; antecedent: B. Testerink, D. Odekerken & F. Bex, FQAS 2019.
- D. Walton, C. Reed & F. Macagno, _Argumentation Schemes_, CUP (2008).
- _Wayne Tank and Pump Co Ltd v Employers' Liability Assurance Corporation Ltd_ [1974] QB 57 (CA).

## Appendix A — Rung 0 protocol

Binary: `~/.local/bin/l4` dated 2026-08-04. Corpus: `origin/unstable` @ `3c5acd1a`, copied to a
scratch directory (goldens untouched). `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries` throughout.

**A.1 Corpus runs.** In the scratch copies, `#EVAL ` → `#EVALTRACE ` (and in `bna.l4` only,
`#ASSERT ` → `#EVALTRACE `, yielding 43 traced scenarios), then per file:

```bash
l4 trace <file> --format dot -o <outdir> --fixed-now 2026-08-27T00:00:00Z
l4 state-graph <file> > <out>.dot        # regulative files
l4 verify <file>                          # decision files
dot -Tpng -Gdpi=72 <g>.dot -o <g>.png     # graphviz 14.1.0
```

Sizes: nodes = `grep -c ' \[label=' *.dot`, edges = `grep -c ' -> ' *.dot`. Headline numbers:
BNA eval3 361 nodes/360 edges at 21818×2581 px; CEO award eval25 261/262 (the sole shared-binding
join observed); Reg CF eval62 208/207; all 43 BNA traces generated in < 2 s wall clock.

**A.2 Micro-experiment** (`short-circuit.l4`, plus single-directive `solo.l4`):

```l4
`residency met` MEANS TRUE
`spouse is citizen` MEANS TRUE
`nullary verdict` MEANS `residency met` OR `spouse is citizen`
GIVEN x IS A BOOLEAN
`left biased or` x MEANS x OR `spouse is citizen`
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
`either route` a b MEANS a OR b

#EVALTRACE `nullary verdict`        -- 1 node  (F5)
#EVALTRACE `left biased or` TRUE    -- 3 nodes; body derivation invisible
#EVALTRACE `left biased or` FALSE   -- 3 nodes; forced disjunct still invisible
#EVALTRACE `either route` TRUE TRUE -- 3 nodes; second TRUE absent  (F6)
```

`solo.l4` (one nullary `#EVALTRACE` as the module's only directive) also yields 1 node, ruling out
cross-directive thunk memoization as the cause of F5: the vacuity is inherent to bare-NOUN
directive traces as post-processed today. The unexplained `a` labels are F7.
