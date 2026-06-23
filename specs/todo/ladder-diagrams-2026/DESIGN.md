# Ladder Diagrams 2026 — Design Document

**Status:** Draft v1 (design-first; no code yet)
**Branch:** `mengwong/ladder-diagrams-3` · worktree `~/src/legalese/l4wt/ladder-diagrams-3`
**Author of record:** Meng (design), drafted with Claude
**Supersedes:** the Dagre + SvelteFlow layout path in `ts-shared/l4-ladder-visualizer`

---

## 0. Lineage — what we are refreshing

We have been through three iterations of the AND/OR ("ladder logic") visualizer:

| # | Stack | Layout method | Centers? |
|---|---|---|---|
| 1. Haskell `ladder-diagram` (`insert-ladder-diagram` branch) | Svelte + npm `ladder-diagram`, fed `RuleNode`/`AndOr` JSON | the library's relay-circuit renderer | n/a — dead IR |
| 2. **layman** (`~/src/legalese/sandbox/mengwong/layman`) | Next.js + React Flow | hand-rolled **two-pass recursive**: lay children naively → measure bbox → `pos = (bbox − child)/2` on the cross-axis | ✅ intrinsic |
| 3. **current** (`ts-shared/l4-ladder-visualizer`) | SvelteFlow (xyflow) + **Dagre** | general DAG layout; OR-branches sandwiched with invisible source/sink "bundling" nodes | ❌ right-aligns |

**Root cause of the right-alignment infelicity (iteration 3):** Dagre is a general layered-graph drawer with no notion of "center this AND/OR nest under its parent." Nesting is faked with invisible bundling nodes. On top of that, `displayers/flow/layout.ts` converts Dagre's center-anchor to SvelteFlow's top-left anchor by subtracting `w/2, h/2` for normal nodes **but skips that shift for bundling nodes** — so group containers sit half a box off from their contents. The code comment already concedes "the anchor positions for the grouping nodes were indeed not being set correctly."

layman does not have this problem because centering is *intrinsic* to its recursion. The design in `tmp/box model.pdf` is the fully-principled version of layman's idea, and is the north star for 2026.

**What we keep:** the Haskell side (`L4.Viz.Ladder` → `VizExpr.IRExpr`) is **topology-only** — n-ary `And`/`Or`/`Not`/`UBoolVar`/`App`/`InertE` with stable `id` and `atomId`, no geometry. That boundary is correct and stays.

---

## 1. Goals & non-goals

### Goals
- A single layout/render engine that serves **four consumers** (§2) from one source of truth.
- **Natural centering** of nested AND/OR groups down the z-axis (fix the headline infelicity).
- **Print-grade** output: A3 and larger, resolution-independent, Tufte-approved line work.
- Faithful realization of the **BBE box model** (`tmp/box model.pdf`) and the **ladder-logic semantics** (`tmp/ladder logic and or tree visualization.pdf`, 2023-05-21).
- Preserve the existing interactive features the IDE relies on (toggle leaf T/F/U, hover, inline-expr expansion, eval).

### Non-goals (for v1)
- Replacing the Haskell `IRExpr` topology IR. (Boundary stays; we may *extend* it — §11.)
- Re-deriving the LSP/eval protocol (`l4/evalApp`, `l4/inlineExprs`, `l4/queryPlan`). We consume it.
- General graph layout. This engine is *purpose-built* for AND/OR trees, not arbitrary DAGs.

---

## 2. Consumers / output targets

The choice of technology is driven by the consumers, not vice-versa.

| Target | Context | Demands |
|---|---|---|
| **A. jl4-web** | SvelteKit web app | embed in a Svelte component; interactivity; pan/zoom |
| **B. VS Code extension** | webview (HTML/JS iframe) | same as A, constrained viewport sizing |
| **C. Standalone** | its own web page; embeddable widget | self-contained; no IDE deps; framework-light |
| **D. Print artwork** | A3+ poster, PDF | vector, resolution-independent; precise typography & hairlines; **headless** (no browser) |

A, B, C are all *browsers* → same substrate. **D is the discriminator.**

---

## 3. Technology decision

### 3.1 Substrate: SVG

Print (target D) forces the choice. SVG is resolution-independent vector, native to all three browser targets, serializes to press-ready PDF at any size, and is the natural medium for Tufte-grade hairline rules and high data-ink ratio.

| Substrate | A/B/C (browser) | D (print A3+) | Connectors/ports | Verdict |
|---|---|---|---|---|
| **SVG** | native | vector → PDF, any size | first-class paths | ✅ chosen |
| HTML/CSS flex | auto-centers | poor print, page-break fiddly | needs SVG overlay anyway | ✗ |
| Canvas / WebGL | fast, interactive | **raster — wrong for print** | manual | ✗ |
| SvelteFlow + Dagre | DOM-bound | not printable, headless-hostile | the current bug source | ✗ |

### 3.2 The decisive call: a pure, substrate-independent layout core

> **Layout must not depend on DOM/browser text measurement.**

Every prior iteration bound layout to the browser (`node.measured.width`, React Flow measured nodes). That is *exactly* why none can render headless for print. We invert it:

```
LayoutCore :  IRExpr  ×  TextMetrics  ×  Config   →   Geometry tree (BBE)
              (topology)  (injected)     (orientation,    (absolute x/y/w/h,
                                          scale, margins)   ports, connector paths)
```

`TextMetrics` is **injected** as a strategy:
- **Browser** (A/B/C): Canvas 2D `measureText` (no DOM reflow needed) — or a cached metrics table.
- **Headless/Node** (D): a font-metrics library (`fontkit` / `opentype.js`) loading the *same* webfont, so screen and print agree to the pixel.
- **Small / Tiny scales**: measurement is constant → no font metrics required at all.

Because the geometry tree is computed analytically (sizes from intrinsic element size + margins, never from reflow), the same core feeds every renderer. This is the "write once, render everywhere" payoff, and it is what box-model.pdf's algebra was designed to enable.

### 3.3 Where the core lives: TypeScript

All four consumers are JS-reachable (browsers + Node for headless print). A single TS core feeds all renderers; no divergence between a Haskell print path and a TS web path. Haskell remains topology-only and emits `IRExpr` JSON over the existing LSP/WASM channels.

---

## 4. Architecture overview

```
            ┌─────────────────────────────────────────────────────────┐
  Haskell   │  L4.Viz.Ladder  →  VizExpr.IRExpr   (topology only)      │
            └───────────────────────────┬─────────────────────────────┘
                                         │  JSON (LSP / WASM)   ← UNCHANGED boundary
            ┌────────────────────────────▼────────────────────────────┐
            │  @repo/ladder-core  (pure TS, no DOM)                    │
            │    • IRExpr → BBE tree  (align-then-stack, §5)           │
            │    • TextMetrics interface (injected)                   │
            │    • Config: orientation (LR/TB), scale (Full/Small/Tiny)│
            │    • outputs: Geometry tree — absolute coords, ports,   │
            │      connector paths, leaf circuit states (T/F/U)       │
            └───────┬───────────────────────────────────┬─────────────┘
                    │                                   │
       ┌────────────▼───────────┐          ┌────────────▼────────────────┐
       │ SVG renderer (shared)  │          │ Headless print sink (Node)  │
       │  geometry → <svg> AST  │          │  geometry → SVG file → PDF  │
       └───────┬────────────────┘          │  A3/A2/A1, Tufte styling    │
               │                            └─────────────────────────────┘
   ┌───────────▼──────────────┐
   │ Interactive wrapper      │   ← Svelte component: events on SVG,
   │ (jl4-web, VS Code)       │     pan/zoom via viewBox, eval panel,
   └──────────────────────────┘     context menus, inline-expr toggle
   ┌──────────────────────────┐
   │ Standalone widget        │   ← same SVG renderer, minimal chrome
   └──────────────────────────┘
```

Three packages (names provisional, §12):
- **`ladder-core`** — pure layout + geometry. No DOM, no Svelte.
- **`ladder-svg`** — geometry → SVG (DOM nodes in-browser; string for headless).
- **`ladder-svelte`** (or fold into existing `l4-ladder-visualizer`) — interactive chrome for IDE targets.

---

## 5. The BBE layout core (the heart)

Transcribed and formalized from `tmp/box model.pdf`.

### 5.1 Types

A **BBE** is a (BBox, Element). The BBox augments the drawn element with margins and ports:

```
BBox = {
  bbw, bbh         // bounding-box width, height
  bblm, bbtm,      // left, top,
  bbrm, bbbm       // right, bottom margins
  ports: Port[]    // input/output connection points
  protrudeT?, …    // label-parking overflow (PrePost), §5.6
}
Element = drawn content (leaf box, or a compound of child BBEs)
```

**Parked-origin invariant:** the bounding box's top-left is always at local `(0,0)`. The *visible* element may depart from the origin (pushed in by left/top margins); the bbox never does. This is what makes composition associative.

### 5.2 Margin operators

| op | meaning |
|---|---|
| `>>>` | move element **right**, add left margin, grow bbox |
| `<<<` | add **right** margin (element does not move), grow bbox |
| `\|/` | move element **down**, add top margin, grow bbox |
| `/\|\` | add **bottom** margin (element does not move), grow bbox |

### 5.3 Combine = **align, then stack**

To combine sibling BBEs along an axis:

1. **Align.** Find the max extent on the cross-axis (e.g. widest child `bbw=60`). Widen *every* child's bbox to that max and **re-margin** to locate its element within — for centering, split the slack evenly into left/right (or top/bottom) margins. Centering falls out of the re-margining; no engine fights us.
2. **Stack.** Lay children along the main axis with a fixed gap (e.g. 8). The result is a new BBE whose single bbox contains the compound element.

### 5.4 The compound-nesting invariant (the elegant bit)

When stacking produces a new parent BBE:
- center it by moving its visible elements right by `leftMargin` and expand `bbw` by *both* left and right margins, **but**
- **set the new BBE's `bblm` and `bbrm` to 0.**

Why: so that when this BBE later nests into a *grandparent*, its ports are computed at the very edges of its bounding box and land in the right place. This is the invariant layman and the Dagre version both lack, and it is what lets nesting compose cleanly down the z-axis.

### 5.5 AND vs OR; orientation

| | LR (default) | TB |
|---|---|---|
| **AND (`All`)** = series | stack **horizontally**, center vertically | stack vertically (series) |
| **OR (`Any`)** = parallel | stack **vertically**, center horizontally | stack horizontally (parallel) |
| leaf | upright | rotated 90° CW |
| "true" line | on top | on the right |
| "false" line | on the left | on top |
| parent margins | left/right | top/bottom |
| ports default | top, horizontal-center | vertically centered |

### 5.6 PrePost labels

A disjunctive OR is often surrounded by prose ("if any of the following are true…"). That text needs a parking spot that does not interrupt the flow. Rather than abusing the top margin (breaks invariants), introduce **protrude params** (`protrudeT`, etc.) — an overflow band above/around the bbox reserved for labels. (Open: finalize the protrude model — §13.)

### 5.7 Ports & connectors

- Every BBE has **input/output ports**. Default in LR = "top" (offset from `bbtm` by a default amount) and horizontal "center". Ports may be restyled top/bottom/left/right/middle.
- Explicit port locations are relative to the **element origin** (go right by `bblm`, down by `bbtm`, then adjust by `pl/pt/pr/pb`).
- **Ports sit against the inner element, not the bounding box** — internal margins (`bblm/bbtm/bbrm/bbbm`) are accounted for when drawing connections.
- **Connectors** are drawn at *compound* time (parent → each child's in/out port), because the child BBEs are absorbed into the parent and would otherwise have no one to draw them. The parent's own connectors sit at the very edges of its bbox — see §5.4 for why `bblm/bbrm=0` matters here.

---

## 6. Ladder-logic semantics (TRUE / FALSE / UNKNOWN)

From the 2023-05-21 sketch. A leaf's state is:

```
type Default = Either (Maybe Bool) (Maybe Bool)
                       └── Left ──┘  └── Right ──┘
   Left  = no user input; fall back to "TYPICALLY yes/no" if a default exists
   Right = user input given (Yes / No / Don't Know)
```

Leaf rendering as a relay contact:
- **known true** → raised bump / closed contact (current flows through)
- **known false** → gap / open contact (current stopped)
- **unknown** → plain pass-through box (grey)

Combinator highlighting: when one branch of an OR is true while siblings are unknown/false, show the circuit **closed over** the true element and **stopped** by false ones. True/false lines are drawn against the *inner* element (margins-aware), per §5.7.

Combinators: **Leaf, Not, All, Any.** `All [A,B,C]` = series; `Any [A,B,C]` = parallel.

**Sub-ordering within groups (nice-to-have):** the sketch orders children for short-circuit legibility — for `All`, false → true → unknown; for `Any`, true → unknown → false; within a group, by selectivity then source order. This is a *presentation* reorder, not a tree change. Flag as optional (§13) since it interacts with stable IDs and user expectations about source order.

---

## 7. Scale modes

A single `AAVScale` config drives box sizing; same layout logic, different leaf chrome:

| Scale | Leaf content | Use |
|---|---|---|
| **Full** | boxes grow/shrink to fit free text | primary reading view |
| **Small** | uniform-size boxes, paragraph numbers ("§12.a.1") | dense overview |
| **Tiny** | no labels — just the leaf's `Either (Maybe Bool)` value | **minimap**; mouseover auto-recenters the main view |

Because Small/Tiny are uniform/constant-size, they need **no font metrics** — which also makes them the trivial case for headless print.

---

## 8. Text-measurement strategy (keystone for print)

```
interface TextMetrics {
  measure(text: string, style: TextStyle): { width: number; height: number }
}
```

- **Browser**: Canvas 2D `measureText` against the loaded webfont. No DOM reflow → works before mount, works in a worker.
- **Headless/Node (print)**: `fontkit`/`opentype.js` loading the *same* font file → identical metrics to the browser.
- **Small/Tiny**: constant metrics; the interface is satisfied by a stub.

This single injection point is the difference between "web-only, like every prior version" and "one engine, four targets including print."

---

## 9. Rendering & interactivity

### SVG renderer (`ladder-svg`)
- Pure function `Geometry → SvgNode` (a small VDOM-ish AST), with two sinks: build real SVG DOM (browser) or serialize to a string (Node).
- Tufte defaults: hairline strokes, restrained palette (green = evaluated leaf, grey = unknown, per the sketch), generous whitespace, no chartjunk, labels typeset not boxed where possible.

### Interactive wrapper (`ladder-svelte`, IDE targets)
- Pan/zoom by manipulating the SVG `viewBox` (no SvelteFlow needed) — or `svg-pan-zoom`.
- Event handlers on leaf `<g>` elements: click to toggle T/F/U; hover tooltip; right-click context menu.
- Wires the existing LSP calls: `l4/evalApp`, `l4/inlineExprs`, `l4/queryPlan`. The `atomId` from `IRExpr` remains the stable handle for binding values back.
- Minimap = a second `ladder-svg` render at Tiny scale sharing the same geometry tree; mouseover recenters the main `viewBox`.

### Memory note
The current code leaks `LirNode`s into a long-lived `LirContext` if not disposed. The pure-core design sidesteps this: geometry trees are plain data, recomputed per render, GC'd normally. The interactive wrapper holds only the current tree + view state.

---

## 10. Print pipeline (A3+, Tufte)

```
IRExpr (fixture or live export)
  → ladder-core (Config{ scale, orientation, page: A3|A2|A1, metrics: fontkit })
  → ladder-svg (string sink)
  → .svg  ──(resvg / rsvg-convert / headless Chrome / Inkscape)──►  .pdf  (press-ready)
```

- Resolution-independent: same geometry, any page size, no pixelation.
- Page fitting: compute geometry, then scale `viewBox` to the printable area with a fixed margin; optionally tile across multiple A3 sheets for very large trees.
- Deliverable for stakeholders: a poster of a real statute/contract's decision logic.

---

## 11. Relationship to existing code

### Keep
- `jl4-core/src/L4/Viz/{Ladder,VizExpr}.hs` — the `IRExpr` topology IR and its JSON.
- The LSP custom protocol (`l4/evalApp`, `l4/inlineExprs`, `l4/queryPlan`) and `atomId` identity.
- The TS `viz-expr` schema package (decode `RenderAsLadderInfo`).

### Replace
- `ts-shared/l4-ladder-visualizer/src/lib/displayers/flow/**` (Dagre + SvelteFlow layout, the bundling-node sandwiching, the anchor hack) → `ladder-core` + `ladder-svg`.
- The `LIR` + algebraic-graphs machinery → the BBE geometry tree (simpler, purpose-built).

### Possibly extend `IRExpr` (decide in §13)
- The current IR carries enough topology, but box-model features may want hints: PrePost label text (for §5.6), explicit leaf default (`Either (Maybe Bool) (Maybe Bool)` vs a bare three-valued `UBoolValue`), and possibly NLG labels. Prefer to derive in TS where possible; extend Haskell only when the data isn't recoverable frontend-side.

### Salvage from prior work
- **layman**: the two-pass measure→center recursion is the proven kernel of §5.3. Port the *idea*, formalized via BBE.
- **`enhance/ladder-expressions` branch**: its use of `L4.ExactPrint` to render `App` nodes with their arguments as leaf text — applicable when we render `App ID Name [IRExpr]` leaves. (The branch's IR is dead; the technique is not.)
- **`insert-ladder-diagram` branch**: nothing structural (dead `RuleNode` IR), but the standalone-app build setup (SvelteKit + Vite, fetch-or-inline JSON polymorphism) is a useful reference for target C.

---

## 12. Package & repo layout (proposed)

```
ts-shared/
  ladder-core/        # pure layout; no DOM; the BBE algebra + geometry types
  ladder-svg/         # geometry → SVG (DOM sink + string sink)
  l4-ladder-visualizer/   # existing pkg, slimmed to the interactive Svelte wrapper
                          # (re-exports the new core/svg; drops Dagre/SvelteFlow layout)
tools/
  ladder-print/       # Node CLI: IRExpr fixture → A3+ SVG/PDF
```

(Alternative: keep everything inside `l4-ladder-visualizer` as internal modules and only split packages once stable. Decide in §13.)

---

## 13. Open decisions

1. **Package split now vs later** — three packages up front, or one package with internal modules until the core stabilizes?
2. **PrePost / protrude model** — finalize how label bands attach without breaking the parked-origin invariant.
3. **Sub-ordering within groups** (§6) — implement the selectivity reorder, or preserve strict source order? Interacts with stable `atomId` and user mental model.
4. **`IRExpr` extensions** (§11) — what, if anything, must move into Haskell vs be derived in TS.
5. **Pan/zoom** — `viewBox` hand-roll vs `svg-pan-zoom` dependency.
6. **SVG→PDF tool** — resvg (fast, Rust, no browser) vs headless Chrome (best CSS/font fidelity) vs Inkscape (designer-grade).
7. **Interactivity in print?** — none, presumably; but confirm whether an "annotated" print mode (showing a worked T/F/U evaluation) is wanted.

---

## 14. Phased plan (proposed, post-approval)

- **P0 — Prototype the kernel.** Standalone page (target C) rendering hand-fed AND/OR trees through `ladder-core` → `ladder-svg`. Nail centering, ports, connectors, LR/TB. No LSP, no IDE. *Validates the headline fix visually.*
- **P1 — Ladder semantics.** TRUE/FALSE/UNKNOWN circuit states; Full/Small/Tiny scales; minimap.
- **P2 — Wire to live data.** Decode real `RenderAsLadderInfo` from the LSP; render real statutes/contracts.
- **P3 — IDE integration.** Replace the Dagre path in `l4-ladder-visualizer`; restore interactivity (toggle/eval/inline) on the SVG; ship to jl4-web + VS Code.
- **P4 — Print pipeline.** `ladder-print` CLI; A3+ PDF; a real poster.

---

## 15. Proposed (added this session): rendering ELIMINABILITY — the don't-care rung

**Motivation.** A worked example — Penal Code s 415, *Poh Yuan Nie v PP* [2022] SGCA 74 — produces a ladder in which one rung is provably *otiose*: under a given reading/fact-context it can **never carry current**. That is the legal doctrine of **surplusage** and the CS notion of **dead code / a don't-care variable** — the same thing. The §6 leaf model (true / false / unknown) cannot express it, yet it is the single most legible thing a ladder can show a lawyer.

### 15.1 A fourth leaf state: ELIMINABLE (don't-care)

Orthogonal to T/F/U:

| state | contact | meaning |
|---|---|---|
| known-true | closed bump | current flows |
| known-false | open gap | current stopped *here, now* |
| unknown | grey passthrough | value not yet supplied — **may still matter** |
| **eliminable** *(new)* | ghosted/dashed box, broken rail | value **cannot matter**: flipping it never changes the output over the region in view |

`eliminable ≠ known-false`: a false leaf could flip and change the result; an eliminable leaf is a don't-care — the function's **Boolean difference** w.r.t. it is identically zero. Render: dashed ghost box, reduced opacity, an open-contact break on the rail, optional "otiose" tag.

### 15.2 Source of the flag (both respect the pure-core boundary, §3.2)

- **Annotated** — `ladder-core` takes an `eliminable` map **keyed by node `id`** (positional, *not* `atomId`: a repeated atom can be live in one rung and otiose in another, and interior `And`/`Or` rungs carry no `atomId`), computed upstream by a minimiser / don't-care prover (Quine–McCluskey / Espresso / a BDD don't-care pass / the Z3 region proof below — cf. the planned boolean-minimization spec, GH issue #638). Just more injected data, like `TextMetrics`. (Leaf **values** stay keyed by `atomId` — toggling a leaf sets it everywhere; only **eliminability** is positional.)
- **Intrinsic** — for small trees, compute it in-core from topology + a partial assignment (cofactor equality per leaf). O(leaves × cases); fine at Small/Tiny.

### 15.3 Minimisation / diff overlay (extends §13.7's "annotated print mode")

Render one geometry tree under two contexts (two interpretations, two fact-assignments, or before/after a minimisation pass) and mark which rungs changed state — especially which went **eliminable**. The headline artifact: two stacked panels of one circuit, the disputed rung live in one and ghosted in the other. The visual proof of a surplusage argument — and a strong poster (target D).

Worked SVG + generator (hand-rolled, pre-`ladder-core`): `~/src/legalese/sandbox/mengwong/layman/cheating-415-ladder.{svg,py}`.

### 15.4 A real fixture for P0 / P2

s 415's second limb is a clean, legally-meaningful AND/OR tree — `And[ Or[by-deceiving, dishonest-concealment], intentionally, causes-harm, Or[body, mind, reputation, property] ]` — exercising centering, parallel groups of 2 *and* 4, and the new eliminable state. Better than a toy. Source of truth: `jl4/ok/inert/cheating-415-poh-yuan-nie.l4` — currently in the sibling **`poh-yuan-nie`** worktree (`~/src/legalese/l4wt/poh-yuan-nie/`), not yet in this branch or `unstable`; bring it in (or land it on `unstable`) when wiring P2. Its Z3 surplusage proof `cheating-415-surplusage.z3.py` is exactly the upstream minimiser that would emit the `eliminable` map.

---

## Appendix — source materials

- `tmp/box model.pdf` — the BBE box model (margins, ports, connectors, align-then-stack, the `bblm/bbrm=0` nesting invariant, LR/TB, Full/Small/Tiny scales). Primary spec for §5–§7.
- `tmp/ladder logic and or tree visualization.pdf` (2023-05-21) — ladder-logic metaphor, `Either (Maybe Bool) (Maybe Bool)` default model, Leaf/Not/All/Any combinators, T/F/U leaf rendering, group sub-ordering. Primary spec for §6.
- `~/src/legalese/sandbox/mengwong/layman` — iteration 2; proven two-pass centering recursion.
- `ts-shared/l4-ladder-visualizer` — iteration 3; the code being refreshed.
- `jl4-core/src/L4/Viz/{Ladder,VizExpr}.hs` — the topology IR boundary we keep.
