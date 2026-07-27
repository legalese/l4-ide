# The Lexipedia Superset — a soup-to-nuts programme spec

_Scoped 2026-07-25. Companion to [`doc/concepts/language-design/logic-not-flowcharts.md`](../../../doc/concepts/language-design/logic-not-flowcharts.md)
(which carries the critique), [`../ladder-diagrams-2026/E1-IDE-INTEGRATION.md`](../ladder-diagrams-2026/E1-IDE-INTEGRATION.md)
(the ladder plan, single-sourced there — this document does not restate it),
[GUARDED-ROWS.md](./GUARDED-ROWS.md) (the decision-side front end) and
[PROCESS-TRACK.md](./PROCESS-TRACK.md) (the process-side front end)._

---

## 0. The ask, in one line

Take the regulation Lexipedia drew as a flowchart, do the whole job in L4, and produce a
**superset** of what their page offers — including, deliberately, **their own artifact**,
generated rather than drawn.

The critique is already written and merged. This is the constructive half. The unit of
comparison is **one wiki page**, because that is the unit they ship.

---

## 1. What we are comparing against

Surveyed 2026-07-25 by reading the live site: the Reg CF page, the project's own template
(`sample_entry`), two further model pages (`cville-business`, `last_wills`), the raw wiki
source, and the page index.

**Lexipedia** (Center for Civic Innovation, CC BY-SA 4.0, DokuWiki) describes itself as "an
open-source project building standardized business process models for legal and civic
applications", using **BPMN and DMN**, for three audiences: entrepreneurs, agencies, and
legal engineers.

### 1.1 The declared page schema

`sample_entry` is ambitious: Process Item (ID / Status / Last Updated) → Overview + Quick
Facts (type, jurisdiction, risk level, regulatory framework, governance model) → Process
Definition (BPMN + actors: primary / supporting / oversight + key steps) → Legal Context
(primary regulations, standards, compliance requirements; risk controls: preventive /
detective / corrective) → Implementation (systems, integration points, data requirements;
required forms, records, retention) → Governance (approval authority, escalation paths,
emergency procedures; audit requirements, evidence collection) → Cross References (related
processes; standards / regulations / case law; LEI and authority control) → Statements /
Status Badges / Version History / Categories.

### 1.2 The delivered artifact

The Reg CF page (`reg_cf_exemptions`, last modified 2026-06-19) is: title → **Overview**
(two external links) → **Detailed Reg CF Requirements** (eight numbered prose items with
dollar figures and rule citations) → **BPMN Model** → **Discussion** (empty). Neither
`cville-business` nor `last_wills` follows the template either.

So: **the template is aspiration; the delivered artifact is prose plus one hand-drawn BPMN.**

### 1.3 Four findings that shape this programme

1. **DMN is advertised and never used.** The project states it uses BPMN _and_ DMN and ships
   primers for both. Across all three model pages inspected: **zero DMN blocks**. The
   decision logic that would be DMN — issuer eligibility, the investor-limit thresholds — is
   drawn instead as BPMN **gateways**. We do not have to impute the category error; it is the
   observed authoring behaviour of people who know the alternative exists. This is an
   empirical hook for the decision-tables section of `logic-not-flowcharts.md`.

2. **The BPMN is drawn by hand in an external tool and pasted in.** `last_wills` still
   carries `exporter="Camunda Modeler" exporterVersion="5.13.0"`. The wiki markup is a
   `<bpmnio type="bpmn">` plugin block with the BPMN 2.0 XML inline, rendered client-side.
   **Nothing connects the prose to the XML.**

3. **They have written the maintenance burden into the page.** `cville-business` carries a
   section called **"Notes for editors"** whose content is guidance on keeping the diagram
   and the text in sync. That is a standing manual reconciliation chore between two
   representations of one rule — and it is precisely the chore that disappears when both are
   _derived from a single source_. On the Reg CF page the investor threshold appears **twice**,
   once in prose and once inside the XML, and both are stale in the same way.

4. **No export, and no validation.** No download or export controls; the only machine-readable
   route is "view source and copy the XML". Registration is open and ungated, and the page
   index interleaves the legal models with a large volume of SEO and darknet spam. That is a
   substrate observation, not a jab: a wiki page has no typechecker and no CI, so nothing
   distinguishes a maintained model from an abandoned one from an injected one.

> **Standing courtesy constraint.** Everything above was obtained by reading published pages.
> No scraping, no bulk fetching, no account creation. Our redrawings and quotations are for
> criticism and comparison and must be attributed under CC BY-SA 4.0 wherever republished.

---

## 2. The per-page map

**Parity — what we must emit to match their page:**

| Their artifact                        | What it really is                   | Our equivalent                                                                                     | Status                  |
| ------------------------------------- | ----------------------------------- | -------------------------------------------------------------------------------------------------- | ----------------------- |
| Overview prose                        | hand-written                        | inert content in the `.l4`; NLG for generated prose                                                | have / partial (NLG)    |
| 8 numbered requirements               | the law, retyped by hand            | **the module itself** — `DECIDE`s + regulative rules                                               | Track C                 |
| Rule 503/504 citations                | inline link text                    | `@ref` provenance → citation-backed "why" in the wizard                                            | **have**                |
| dollar thresholds                     | hardcoded **twice**, prose and XML  | one constant, on the rule-version axis                                                             | `temporal-rule-version` |
| **BPMN Model** block                  | hand-drawn, pasted                  | **generated** from `L4.StateGraph`                                                                 | Track P                 |
| its gateways                          | decision logic mis-drawn as process | ladder + DMN export                                                                                | Tracks L, D             |
| DMN (claimed, absent)                 | —                                   | DMN 1.3 from the `DECIDE` layer                                                                    | Track D                 |
| actors (primary/supporting/oversight) | prose list                          | `PARTY` / actor-indexed deontics                                                                   | **have**                |
| audit trail / evidence collection     | prose description                   | `RECORD` / `COMMIT` / `ATTEST` + evaluation trace                                                  | **have**                |
| required forms + retention periods    | prose                               | obligations with deadlines                                                                         | **have**                |
| Version History                       | DokuWiki revisions                  | git **plus** the rule-version axis — two clocks: when the _page_ changed vs when the _law_ changed | partial                 |
| Discussion (empty)                    | talk page                           | PR / issue thread                                                                                  | have                    |
| Risk controls (prev/det/corr)         | prose taxonomy                      | **no analogue — genuinely theirs**                                                                 | acknowledge             |
| "Notes for editors: keep in sync"     | a permanent manual chore            | **deleted as a category**                                                                          | the argument            |

**Superset — what the page format cannot hold at all:** a runnable wizard that explains why
it reached its answer; a queryable API over the same rules; the answer _as of a date_ when
thresholds change; contradiction and gap detection across the rule set; tests as negotiated
scenarios; and a diagram that responds to being clicked.

---

## 3. The spine

Two independent front ends over the typechecked AST, each with two consumers. This is the
whole architecture:

```
                    ┌─ rowsToLadder ──→ VizExpr And/Or ──→ ladder, ASCII, Mermaid, wizard, ROBDD
   GuardedRows ─────┤
   (decision side)  └─ rowsToDmn ─────→ DMN 1.3 XML + DRG  ──→ decision tables
        ▲
        │ normalise:  IfThenElse | MultiWayIf | Consider
   L4 typechecked AST
        │ extract
        ▼
   StateGraph ──────┬─ stateGraphToDot ─→ GraphViz            (exists today)
   (process side)   └─ stateGraphToBpmn → BPMN 2.0 XML  ──────→ Camunda-importable
```

Three consequences worth stating plainly:

- **The "crude BRANCH converter" is not a side-quest.** It is the shared front end that the
  DMN exporter needs anyway. Building it first is the cheapest way to de-risk Track D.
- **The two sides are genuinely independent** and can be built in parallel by different
  people, which is what Fork 4 asked for. They meet only at the CLI and service surface.
- **Everything downstream of `VizExpr` is already built.** The normaliser emits ordinary
  `And`/`Or`/`Not`, so the ladder, the carriers, the sentence expander, the query plan and the
  ROBDD inherit the fix with **no TypeScript change at all**.

---

## 4. Tracks

Each track states its dependencies. Only L→E and D0→D1 are hard orderings.

### Track D — decision side

| ID     | Work                                                                               | Depends on |
| ------ | ---------------------------------------------------------------------------------- | ---------- |
| **D0** | `GuardedRows` normaliser + `rowsToLadder`, in `L4.Viz.Ladder`. See GUARDED-ROWS.md | —          |
| **D1** | `rowsToDmn` — DMN 1.3 XML + DRG, with the fidelity report                          | D0         |
| **D2** | §23/D1 structured table-leaf rendering for the **non-boolean** case                | D0, L      |

### Track P — process side (parallel, independent)

| ID     | Work                                                                             | Depends on |
| ------ | -------------------------------------------------------------------------------- | ---------- |
| **P0** | Harden the `L4.StateGraph` IR against the Reg CF obligation tail                 | —          |
| **P1** | `stateGraphToBpmn` — BPMN 2.0 XML, Camunda-importable, with the fidelity report  | P0         |
| **P2** | Improved process/LTS visualiser (Petri-net lineage). **Own spec, own timeline.** | P0         |

### Track L — the ladder

Single-sourced in [E1-IDE-INTEGRATION.md](../ladder-diagrams-2026/E1-IDE-INTEGRATION.md).
Not restated. Current position: Steps 1 / 2-metrics / 3 merged; critical path at **Step 4**.
Revised path to a shipped default is **4 → 5 → 6a → 7**, with 6b and the Step 8 deletion
trailing. First action is **H2**: this branch is that fresh branch off `origin/unstable`.

### Track E — the embeddable component

Build spec: [EMBEDDABLE.md](./EMBEDDABLE.md) — the element's API, the two data contracts, the
bundle settings, and the open rulings. **It corrects four things below, and the table and
blockquote here have been amended to match:**

1. **E0** — there is no Svelte interaction controller to factor, so E0 is an acceptance
   criterion on L Step 4, not a refactor (EMBEDDABLE §0, EK1).
2. **E2 does not depend on S1.** `POST …/query-plan` already returns `.ladder`
   unconditionally (`Backend/DecisionQueryPlan.hs:229,290`), so S1 is a GET-shaped alias, not
   a gate (EMBEDDABLE §5.2).
3. **The dependencies Track E really has** are ladder seams **S6** (pan/zoom) and **S8**
   (baked palettes) from E1-IDE-INTEGRATION.md §1 — a different numbering namespace from
   Track S's surfaces below (EMBEDDABLE §2).
4. **"Zero adoption cost" was false**, and the blockquote below is rewritten. The interactive
   embed costs one DokuWiki plugin install; only the non-interactive artifacts are free
   (EMBEDDABLE §1.1).

| ID     | Work                                                                                                                                                         | Depends on                       |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------- |
| **E0** | Factor the interaction controller (click-cycle, fold, FLIP, `viewBox` pan/zoom) as **vanilla TS** in `ladder-svg`, so the Svelte displayer is a thin wrapper | —, but must land _with_ L Step 4 |
| **E1** | `<l4-ladder>` custom element + `mount(el, …)`; single-file ESM + IIFE; no framework                                                                          | E0; ladder seams S6, S8          |
| **E2** | Two modes: **static** (given a `FunDecl` JSON) and **live** (pointed at a jl4-service deployment)                                                            | E1 (**not** S1 — see 2 above)    |

> **Why this is strategic — and what it actually costs.** ~~Their substrate accepts pasted
> blocks … at zero adoption cost.~~ **Withdrawn as false.** What the survey shows is that their
> wiki accepts a _registered plugin's_ syntax (`<bpmnio>`), not pasted HTML or `<script>`;
> DokuWiki disables HTML embedding by default and displays the code instead of executing it.
> The corrected claim: **the interactive embed costs one plugin install — the same act they
> already performed once, for `bpmnio` — and it needs no CSP change, because a DokuWiki plugin
> serves its own `script.js` from the wiki's origin. The non-interactive artifacts (an ASCII
> ladder in a `<code>` block, a rendered image) cost nothing at all and already exist in
> `ladder-core`.** Meeting them where they are is still the point; it is one admin action
> away, not zero. EMBEDDABLE §1 prices every channel and schedules the live check (E1d/E1e).

### Track C — the corpus

| ID     | Work                                                                                                                                                                     | Depends on |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| **C0** | **Mirror.** Ingest exactly their scope — issuer eligibility, offering limit, investor limits, then the disclosure / intermediary / advertising / reporting / resale tail | —          |
| **C1** | **Superset.** The investor limit as a _formula_; the obligation tail with real deadlines; resale as a 12-month deontic constraint; thresholds on the rule-version axis   | C0         |
| **C2** | The citizen wizard (housing-wizard façade pattern)                                                                                                                       | C0         |
| **C3** | Scenario tests — the negotiation-stage idea applied to a regulation                                                                                                      | C0         |

Build spec: [CORPUS-TRACK.md](./CORPUS-TRACK.md) — C0's residual gap, C1's four moves sized
against what is already built, C2/C3, and the M5 script. It also carries **the corrected Reg
CF regime table** (four regimes, three boundaries — the earlier three-regime reading omitted
the 2017-04-12 inflation adjustment) and the **temporal closure rule**: a function may be
dated only when every constant in its transitive read set is dated over the same window.
Both are load-bearing for M5 and were established by adversarial review; see its §9.

### Track S — surfaces

| ID     | Work                                                                    | Depends on |
| ------ | ----------------------------------------------------------------------- | ---------- |
| **S0** | `l4 export --to=dmn\|bpmn`, with `--fidelity-report`                    | D1, P1     |
| **S1** | `jl4-service`: `/functions/:name/ladder` returning `RenderAsLadderInfo` | —          |
| **S2** | `jl4-service`: the export endpoints                                     | D1, P1     |
| **S3** | Deployment-engine wiring                                                | S1, S2     |

> **S1 is nearly free — but the reason given here was half wrong, and it is not a gate.** > ~~`L4.Viz.Ladder` lives in `jl4-core`, not `jl4-lsp` … the route is plumbing.~~ There are
> **two** ladder implementations, and `jl4-service` uses the **`jl4-lsp`** one
> (`Backend/DecisionQueryPlan.hs:42,181` — `LadderViz.doVisualize`), not the `jl4-core` one.
> More importantly, `RenderAsLadderInfo` is **already served over HTTP today**:
> `QueryPlanResponse.ladder` is set unconditionally (`DecisionQueryPlan.hs:229,290`). So S1 is
> a GET-shaped, cacheable alias for a payload the service already computes — a real ergonomic
> win for a wiki embed, and **not a dependency of Track E's E2**. If built, it must return
> `cached.ladderInfo` verbatim rather than calling `visualizeByName`: two endpoints
> disagreeing about one diagram is worse than one endpoint. The conclusion survives — the
> Haskell serves data while the TypeScript draws, no sidecar. See EMBEDDABLE §5.2.

---

## 5. Milestones

| #      | Deliverable                                           | Tracks                 |
| ------ | ----------------------------------------------------- | ---------------------- |
| **M0** | Ribbons stop being the typical outcome                | D0                     |
| **M1** | The new ladder is the IDE default in both apps        | L, E0                  |
| **M2** | A ladder embeds in an arbitrary web page              | E1, E2                 |
| **M3** | **The mirror page** — parity exhibit, page for page   | C0, C2, M2             |
| **M4** | DMN + BPMN out, each with its fidelity report         | D1, P1, S0             |
| **M5** | **The superset page** — temporal, verified, queryable | C1, **C2**, C3, S2, S3 |
| **M6** | Process/LTS visualiser                                | P2 (own spec)          |

**M0 first, and deliberately so.** It is the smallest change with the widest blast radius:
one Haskell function, no TypeScript, and it simultaneously improves every existing ladder,
removes the ugliest thing the R1 spike found, and constitutes the front half of the DMN
exporter. Nothing else on this list has that ratio.

---

## 6. Decisions locked 2026-07-25

| #      | Decision                                                                                                                                                                                                                                                                                                                                   |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **K1** | **Elicitation marks gate the default flip; chrome trails it.** Marks are correctness-adjacent — a picture that omits "you have not answered this yet" misleads in the same register §25f does. Menus are convenience.                                                                                                                      |
| **K2** | **The paths-list is not ported.** `expandSentences` substitutes. It answers the same question in a form that reads aloud, survives print, and needs no DAG. `node-paths-selection.ts` and `algebraic-graphs` die together at Step 8.                                                                                                       |
| **K3** | **Mirror their scope first, superset second — and the superset is not optional.** The page is the unit of comparison; a wider v1 blurs it. C1/C3 are committed work, not a stretch goal.                                                                                                                                                   |
| **K4** | **BPMN export targets Camunda import.** Their authoring flow is already Camunda Modeler → paste XML, so a paste-ready file slots into their workflow at zero cost. The fidelity report rides along as a second output rather than being the point. **Amended 2026-07-27 — see K8: Camunda is the target, but it is not the only checker.** |
| **K5** | **The process track is scoped to build in parallel.** P0/P1 share only the CLI and service surface with Track D. P2 spins out entirely.                                                                                                                                                                                                    |
| **K6** | **Exporters live in Haskell; the ladder stays TypeScript.** `jl4-core` already owns both IRs; Haskell exporters get CLI _and_ service for free. The service serves data, the browser draws.                                                                                                                                                |
| **K7** | **The normaliser is shared infrastructure, built first.** Not a ladder patch. See GUARDED-ROWS.md.                                                                                                                                                                                                                                         |

## 6.1 Decision locked 2026-07-27

| #      | Decision                                                                                                                                                                                                                                                    |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **K8** | **Two engines, both exporters.** Every export is checked against **both** the Camunda ecosystem and **KIE**, and the DMN exporter emits a **flavor per ecosystem**. One validator is one opinion, and each exporter is currently blind in the opposite eye. |

**Why, concretely.** The two exporters have inverted blind spots today:

|      | checked by                                                          | not checked by |
| ---- | ------------------------------------------------------------------- | -------------- |
| BPMN | `bpmn-moddle` — what `bpmn-js`, and so Camunda Modeler, parses with | KIE / jBPM     |
| DMN  | Drools/KIE 8.44.0.Final, the DMN TCK reference implementation       | Camunda        |

Neither gap is hypothetical. The BPMN exporter's first version passed `bpmn-moddle` at **zero
warnings** across 1581 green examples while emitting a **deadlocking** diagram — the converging
join counted edges rather than tokens, so an `ROR` or an interrupting boundary inside a `RAND`
branch produced a process that can never complete. A parser cannot see that; an engine that tries
to run it can. The DMN exporter was bitten the same way from the other side: schema-valid output
that no engine could execute, reported as advisory.

So the checks must be **independent implementations**, and ideally ones that _execute_ rather than
merely parse — parse-level agreement is nearly free and would have caught none of the nine BPMN
defects.

**For DMN this is a flavor axis, not merely a second check.** It settles **R7** of
`../DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §11 ("Is Camunda a target?") as **yes** — which by that
ruling's own terms means the full §5 naming/mangling policy applies rather than collapsing to
"just stop emitting dots", and that §6.3-3 BKM emission needs gating. `§`-as-`decisionService`
(§2.3) is a third likely divergence point. **All three axes are ours and are verified; the
per-engine behaviour on each is not, and must be measured against both engines before the flavors
are designed** — the recurring lesson on this programme is that the validator's opinion and the
engine's are different things.

**Not a new target audience.** Camunda remains _the_ audience, because their authoring flow is
Camunda Modeler → paste XML. KIE is a correctness instrument, and the DMN KIE flavor exists so the
DMN↔BPMN pairing (the F4 seam) is consumable end-to-end in either ecosystem rather than half in
each.

---

## 7. Non-goals

- **Not** a Lexipedia competitor, a wiki, or a hosting product.
- **Not** BPMN or DMN _import_. (DMN→L4 is separately specified in
  `BUILD-SPEC-dmnmd-to-l4.md`; its mapping table inverts usefully for D1, but round-tripping
  is out of scope here.)
- **Not** a full formalisation of 17 CFR 227. C0 is bounded by their page; C1 extends only
  where it demonstrates something their format cannot **evaluate** — not something it cannot
  represent. (Anything can be typeset; the earlier "structurally cannot hold" framing did not
  survive review. See CORPUS-TRACK.md §2.0.) The 2020 COVID temporary rules
  (17 CFR 227.201(z)/(bb)) are in-scope material deliberately left unmodelled, named in
  CORPUS-TRACK.md §2.4.1 rather than silently omitted.
- **Not** a claim that BPMN is always wrong. It is wrong for predicates. `PARTY … MUST …
HENCE/LEST` genuinely _is_ process, and that is exactly what Track P exports.

---

## 8. Acceptance

The programme is done when a single URL does everything their page does and the things it
cannot, and when the artifact they would have hand-drawn falls out of ours as a download.

Concretely, for the mirror milestone (M3):

1. Every one of their eight numbered requirements is traceable to `.l4` source, and every
   answer the wizard gives cites the rule it came from.
2. The BPMN we emit **imports cleanly into Camunda Modeler** and describes the same obligation
   tail their diagram does — and **KIE agrees** (K8). Camunda import is the deliverable; KIE is
   the second opinion that catches what a parser cannot, such as a process that parses perfectly
   and then deadlocks.
3. The DMN we emit is accepted by **both** ecosystems, in each one's flavor (K8).
4. The fidelity report names, in their vocabulary, what BPMN and DMN each dropped — including any
   divergence between the two engines, which is a fidelity fact and not an implementation detail.
5. The ladder for the eligibility decision renders in a plain HTML page with a script tag, and
   clicking a term changes the verdict.

And for the superset (M5), the demonstration that lands the argument: **someone asks the same
question, with their own figures, under two different rule dates, and gets two different
answers**, each correct for its date — against a diagram whose threshold is a number someone
typed once and has to remember to change in two places.

Three qualifications on that sentence, established by review and detailed in
[CORPUS-TRACK.md §9](./CORPUS-TRACK.md):

- **"Someone asks" is load-bearing.** Two expected values in a golden file satisfy the
  sentence literally and demonstrate nothing a static table could not. The interactive
  surface is **C2**, which is why M5 now depends on it.
- **"Each correct for its date" is an accuracy claim about us**, and it fails unless every
  constant the demonstrated function reads is dated over the same window — not just the one
  the headline turns on. See CORPUS-TRACK.md §2.4 trap 5.
- **"What their format cannot hold" is the wrong standard** and is not used in the corpus
  track; anything can be typeset. The standard is what their format cannot **evaluate**,
  cannot be caught being **wrong** about, and cannot answer for **arbitrary inputs**. See
  CORPUS-TRACK.md §2.0.
