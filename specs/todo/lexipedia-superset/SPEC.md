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

| ID     | Work                                                                                                                                                         | Depends on                       |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------- |
| **E0** | Factor the interaction controller (click-cycle, fold, FLIP, `viewBox` pan/zoom) as **vanilla TS** in `ladder-svg`, so the Svelte displayer is a thin wrapper | —, but must land _with_ L Step 4 |
| **E1** | `<l4-ladder>` custom element + `mount(el, …)`; single-file ESM + IIFE; no framework                                                                          | E0                               |
| **E2** | Two modes: **static** (given a `FunDecl` JSON) and **live** (pointed at a jl4-service deployment)                                                            | E1, S1                           |

> **Why this is strategic, not a convenience.** Their substrate accepts pasted blocks — that
> is the entire distribution mechanism of a DokuWiki. A drop-in that renders a live ladder
> and wizard inside a wiki page meets them exactly where they are, at zero adoption cost.

### Track C — the corpus

| ID     | Work                                                                                                                                                                     | Depends on |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| **C0** | **Mirror.** Ingest exactly their scope — issuer eligibility, offering limit, investor limits, then the disclosure / intermediary / advertising / reporting / resale tail | —          |
| **C1** | **Superset.** The investor limit as a _formula_; the obligation tail with real deadlines; resale as a 12-month deontic constraint; thresholds on the rule-version axis   | C0         |
| **C2** | The citizen wizard (housing-wizard façade pattern)                                                                                                                       | C0         |
| **C3** | Scenario tests — the negotiation-stage idea applied to a regulation                                                                                                      | C0         |

### Track S — surfaces

| ID     | Work                                                                    | Depends on |
| ------ | ----------------------------------------------------------------------- | ---------- |
| **S0** | `l4 export --to=dmn\|bpmn`, with `--fidelity-report`                    | D1, P1     |
| **S1** | `jl4-service`: `/functions/:name/ladder` returning `RenderAsLadderInfo` | —          |
| **S2** | `jl4-service`: the export endpoints                                     | D1, P1     |
| **S3** | Deployment-engine wiring                                                | S1, S2     |

> **S1 is nearly free and should be taken early.** `L4.Viz.Ladder` lives in **`jl4-core`**,
> not `jl4-lsp`, and `jl4-service` already depends on `jl4-core`. Ladder extraction is
> therefore already available service-side; the route is plumbing. This is what makes Track E
> mode 2 cheap, and it means the Haskell serves data while the TypeScript draws — no sidecar.

---

## 5. Milestones

| #      | Deliverable                                           | Tracks         |
| ------ | ----------------------------------------------------- | -------------- |
| **M0** | Ribbons stop being the typical outcome                | D0             |
| **M1** | The new ladder is the IDE default in both apps        | L, E0          |
| **M2** | A ladder embeds in an arbitrary web page              | E1, E2, S1     |
| **M3** | **The mirror page** — parity exhibit, page for page   | C0, C2, M2     |
| **M4** | DMN + BPMN out, each with its fidelity report         | D1, P1, S0     |
| **M5** | **The superset page** — temporal, verified, queryable | C1, C3, S2, S3 |
| **M6** | Process/LTS visualiser                                | P2 (own spec)  |

**M0 first, and deliberately so.** It is the smallest change with the widest blast radius:
one Haskell function, no TypeScript, and it simultaneously improves every existing ladder,
removes the ugliest thing the R1 spike found, and constitutes the front half of the DMN
exporter. Nothing else on this list has that ratio.

---

## 6. Decisions locked 2026-07-25

| #      | Decision                                                                                                                                                                                                                                           |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **K1** | **Elicitation marks gate the default flip; chrome trails it.** Marks are correctness-adjacent — a picture that omits "you have not answered this yet" misleads in the same register §25f does. Menus are convenience.                              |
| **K2** | **The paths-list is not ported.** `expandSentences` substitutes. It answers the same question in a form that reads aloud, survives print, and needs no DAG. `node-paths-selection.ts` and `algebraic-graphs` die together at Step 8.               |
| **K3** | **Mirror their scope first, superset second — and the superset is not optional.** The page is the unit of comparison; a wider v1 blurs it. C1/C3 are committed work, not a stretch goal.                                                           |
| **K4** | **BPMN export targets Camunda import.** Their authoring flow is already Camunda Modeler → paste XML, so a paste-ready file slots into their workflow at zero cost. The fidelity report rides along as a second output rather than being the point. |
| **K5** | **The process track is scoped to build in parallel.** P0/P1 share only the CLI and service surface with Track D. P2 spins out entirely.                                                                                                            |
| **K6** | **Exporters live in Haskell; the ladder stays TypeScript.** `jl4-core` already owns both IRs; Haskell exporters get CLI _and_ service for free. The service serves data, the browser draws.                                                        |
| **K7** | **The normaliser is shared infrastructure, built first.** Not a ladder patch. See GUARDED-ROWS.md.                                                                                                                                                 |

---

## 7. Non-goals

- **Not** a Lexipedia competitor, a wiki, or a hosting product.
- **Not** BPMN or DMN _import_. (DMN→L4 is separately specified in
  `BUILD-SPEC-dmnmd-to-l4.md`; its mapping table inverts usefully for D1, but round-tripping
  is out of scope here.)
- **Not** a full formalisation of 17 CFR 227. C0 is bounded by their page; C1 extends only
  where it demonstrates something their format structurally cannot hold.
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
   tail their diagram does.
3. The fidelity report names, in their vocabulary, what BPMN and DMN each dropped.
4. The ladder for the eligibility decision renders in a plain HTML page with a script tag, and
   clicking a term changes the verdict.

And for the superset (M5), the demonstration that lands the argument: **ask the same question
under two different rule dates and get two different answers**, each correct for its date —
against a diagram whose threshold is a number someone typed once and has to remember to
change in two places.
