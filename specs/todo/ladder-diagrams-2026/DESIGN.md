# Ladder Diagrams 2026 — Design Document

**Status:** Draft v1 (design-first; no code yet)
**Branch:** `mengwong/ladder-diagrams-3` · worktree `~/src/legalese/l4wt/ladder-diagrams-3`
**Author of record:** Meng (design), drafted with Claude
**Supersedes:** the Dagre + SvelteFlow layout path in `ts-shared/l4-ladder-visualizer`

---

## 0. Lineage — what we are refreshing

We have been through three iterations of the AND/OR ("ladder logic") visualizer:

| #                                                            | Stack                                                      | Layout method                                                                                                        | Centers?        |
| ------------------------------------------------------------ | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | --------------- |
| 1. Haskell `ladder-diagram` (`insert-ladder-diagram` branch) | Svelte + npm `ladder-diagram`, fed `RuleNode`/`AndOr` JSON | the library's relay-circuit renderer                                                                                 | n/a — dead IR   |
| 2. **layman** (`~/src/legalese/sandbox/mengwong/layman`)     | Next.js + React Flow                                       | hand-rolled **two-pass recursive**: lay children naively → measure bbox → `pos = (bbox − child)/2` on the cross-axis | ✅ intrinsic    |
| 3. **current** (`ts-shared/l4-ladder-visualizer`)            | SvelteFlow (xyflow) + **Dagre**                            | general DAG layout; OR-branches sandwiched with invisible source/sink "bundling" nodes                               | ❌ right-aligns |

**Root cause of the right-alignment infelicity (iteration 3):** Dagre is a general layered-graph drawer with no notion of "center this AND/OR nest under its parent." Nesting is faked with invisible bundling nodes. On top of that, `displayers/flow/layout.ts` converts Dagre's center-anchor to SvelteFlow's top-left anchor by subtracting `w/2, h/2` for normal nodes **but skips that shift for bundling nodes** — so group containers sit half a box off from their contents. The code comment already concedes "the anchor positions for the grouping nodes were indeed not being set correctly."

layman does not have this problem because centering is _intrinsic_ to its recursion. The design in `tmp/box model.pdf` is the fully-principled version of layman's idea, and is the north star for 2026.

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

- Replacing the Haskell `IRExpr` topology IR. (Boundary stays; we may _extend_ it — §11.)
- Re-deriving the LSP/eval protocol (`l4/evalApp`, `l4/inlineExprs`, `l4/queryPlan`). We consume it.
- General graph layout. This engine is _purpose-built_ for AND/OR trees, not arbitrary DAGs.

---

## 2. Consumers / output targets

The choice of technology is driven by the consumers, not vice-versa.

| Target                   | Context                             | Demands                                                                                   |
| ------------------------ | ----------------------------------- | ----------------------------------------------------------------------------------------- |
| **A. jl4-web**           | SvelteKit web app                   | embed in a Svelte component; interactivity; pan/zoom                                      |
| **B. VS Code extension** | webview (HTML/JS iframe)            | same as A, constrained viewport sizing                                                    |
| **C. Standalone**        | its own web page; embeddable widget | self-contained; no IDE deps; framework-light                                              |
| **D. Print artwork**     | A3+ poster, PDF                     | vector, resolution-independent; precise typography & hairlines; **headless** (no browser) |

A, B, C are all _browsers_ → same substrate. **D is the discriminator.**

---

## 3. Technology decision

### 3.1 Substrate: SVG

Print (target D) forces the choice. SVG is resolution-independent vector, native to all three browser targets, serializes to press-ready PDF at any size, and is the natural medium for Tufte-grade hairline rules and high data-ink ratio.

| Substrate          | A/B/C (browser)   | D (print A3+)                   | Connectors/ports         | Verdict   |
| ------------------ | ----------------- | ------------------------------- | ------------------------ | --------- |
| **SVG**            | native            | vector → PDF, any size          | first-class paths        | ✅ chosen |
| HTML/CSS flex      | auto-centers      | poor print, page-break fiddly   | needs SVG overlay anyway | ✗         |
| Canvas / WebGL     | fast, interactive | **raster — wrong for print**    | manual                   | ✗         |
| SvelteFlow + Dagre | DOM-bound         | not printable, headless-hostile | the current bug source   | ✗         |

### 3.2 The decisive call: a pure, substrate-independent layout core

> **Layout must not depend on DOM/browser text measurement.**

Every prior iteration bound layout to the browser (`node.measured.width`, React Flow measured nodes). That is _exactly_ why none can render headless for print. We invert it:

```
LayoutCore :  IRExpr  ×  TextMetrics  ×  ViewSpec   →   Scene IR
              (topology)  (injected)     (fold set,        (flat & resolved:
                                          eval, scale,      absolute coords, ports,
                                          orient, page?)    connector paths, tagged
                                                            primitives, pre-broken text)
```

`TextMetrics` is **injected** as a strategy:

- **Browser** (A/B/C): Canvas 2D `measureText` (no DOM reflow needed) — or a cached metrics table.
- **Headless/Node** (D): a font-metrics library (`fontkit` / `opentype.js`) loading the _same_ webfont, so screen and print agree to the pixel.
- **Small / Tiny scales**: measurement is constant → no font metrics required at all.

Because the geometry tree is computed analytically (sizes from intrinsic element size + margins, never from reflow), the same core feeds every renderer. This is the "write once, render everywhere" payoff, and it is what box-model.pdf's algebra was designed to enable.

The BBE tree (§5) is the core's _internal_ layout mechanism; what it _emits_ is a **Scene IR** (§4.2) — a flat, resolved, tagged drawing model that both renderers consume without re-deriving geometry. The single config both web and print accept is the **ViewSpec** (§4.3). These two contracts are what keep the renderer overlays thin (§4.1).

### 3.3 Where the core lives: TypeScript

All four consumers are JS-reachable (browsers + Node for headless print). A single TS core feeds all renderers; no divergence between a Haskell print path and a TS web path. Haskell remains topology-only and emits `IRExpr` JSON over the existing LSP/WASM channels.

---

## 4. Architecture overview

One shared base with two thin, _additive_ renderer overlays — the **90 / 10 / 10**
split. The overlays sum past 100% on purpose: they _add_ behaviour to a base that
never forks (§4.1).

```
              ┌────────────────────────────────────────────────────────┐
  Haskell     │  L4.Viz.Ladder → VizExpr.IRExpr   (topology only)       │
              └────────────────────────────┬───────────────────────────┘
                                JSON (LSP/WASM)  ← UNCHANGED boundary
  ViewSpec ──────────────┐                 │
  {foldSet, eval(s),     │   ┌─────────────▼───────────────────────────┐
   scale, orient, page?} └──▶│  @repo/ladder-core    (pure TS, no DOM)  │  ~75%
                             │    IRExpr → BBE tree (align-then-stack)  │
  TextMetrics ──────────────▶│    → SCENE IR  (flat, resolved, tagged)  │
  (injected; font-parity)    └────────────────────┬────────────────────┘
                                                   │  Scene IR — the contract
                             ┌─────────────────────▼───────────────────┐
                             │  @repo/ladder-svg   (shared SVG emit)    │  ~15%
                             │  Scene IR → <rect>/<path>/<text><tspan>  │
                             │  DOM-node sink (browser) │ string (Node) │
                             └────────┬────────────────────────┬────────┘
                                      │                        │
                   ┌──────────────────▼──────┐   ┌─────────────▼──────────────┐
                   │  web overlay        ~10% │   │  print overlay        ~10% │
                   │  events, fold carets,    │   │  page A3/A2…, ink theme,   │
                   │  hover, FLIP transitions │   │  bake ViewSpec, tile,      │
                   │  opt. foreignObject text │   │  SVG string → PDF          │
                   │  viewBox pan/zoom        │   │  (resvg / headless Chrome) │
                   └──────────┬───────────────┘   └────────────────────────────┘
          ┌──────────────────┼──────────────────┐
       jl4-web        VS Code webview      standalone widget
```

Packages (names provisional, §12):

- **`ladder-core`** — IRExpr → BBE → Scene IR. Pure; no DOM, no Svelte. (~75%)
- **`ladder-svg`** — Scene IR → SVG primitives; DOM-node sink (browser) + string sink (headless). Shared by both overlays. (~15%)
- **`ladder-web`** (or fold into `l4-ladder-visualizer`) — Svelte interactive overlay. (~10%)
- **`ladder-print`** — Node CLI: ViewSpec → SVG string → PDF, A3+. (~10%)

### 4.1 Why it sums to 110% — the factoring discipline

The two renderer overlays are not _slices_ of a pie that must total 100; they are
**additive** behaviour on a base that never branches. `ladder-core` and the shared
SVG emit (~90%) are byte-identical for every target. Each overlay then _adds_ a
little — events/animation for web, page-setup/PDF for print. Summing past 100% is
the signature of clean layering; if the overlays summed to _exactly_ 100% it would
mean the core had been forked per target. The two contracts below (Scene IR,
ViewSpec) are what hold the line.

### 4.2 Scene IR — the core → renderer contract

The core does **not** hand renderers a BBE tree; it hands a flat, resolved drawing
model. Every primitive carries absolute coordinates **and** semantic tags, so the
web overlay can attach behaviour and the print overlay can restyle — neither
re-derives geometry:

```ts
type ScenePrim =
  | {
      kind: "box";
      id: NodeId;
      atomId?: AtomId;
      rect: Rect;
      role: "leaf" | "group" | "placeholder";
      state: "live" | "inert" | "dead" | "eliminable";
      folded?: boolean;
      label?: TextRef;
    }
  | {
      kind: "wire";
      from: Port;
      to: Port;
      path: PathSeg[];
      role: "rail" | "rung" | "stub";
      state: ScenePrim["state"];
    }
  | { kind: "glyph"; at: Pt; role: "open-contact" | "power-terminal" }
  | {
      kind: "text";
      id: NodeId;
      lines: TextLine[];
      bbox: Rect; // pre-broken
      anchor: "start" | "middle";
      style: TextStyleRef;
    };
type Scene = { size: Size; prims: ScenePrim[]; viewSpec: ViewSpec };
```

Key points: coordinates are absolute (no nesting to resolve at paint time);
**text is already line-broken** by the core via `TextMetrics`; `id` is positional
(fold state, animation tracking — and the `eliminable` key, §15.2), `atomId` keys
leaf _values_. The Scene IR is the seam that keeps both overlays ~10%.

### 4.3 ViewSpec — the shared "what to draw"

Interactivity is dynamic on web; print needs a _frozen_ configuration. One
serializable record is the input to the core for **both**:

```ts
type ViewSpec = {
  foldSet: Set<NodeId>; // which interior nodes are collapsed
  eval: Record<AtomId, UBoolValue>; // leaf assignment(s); [] = no eval
  overlay?: ViewSpec[]; // multi-panel diff (e.g. two readings)
  scale: "full" | "small" | "tiny";
  orient: "LR" | "TB";
  page?: { size: "A4" | "A3" | "A2" | "A1"; tile?: boolean }; // print only
  theme: "screen" | "ink";
};
```

Payoff: the live web view's state _is_ a ViewSpec — serialize it and hand it to
the print path to **"print exactly what I'm looking at,"** including the two-panel
s 415 diff (`overlay`, §15.3). Print stops being an afterthought; it is "render
this ViewSpec to paper."

### 4.4 Text: `foreignObject` is enhancement-only; font parity

To keep print first-class, the **canonical** text path is SVG `<text>/<tspan>` —
the core pre-breaks lines (§4.2) so screen and paper lay text identically.
`foreignObject` (HTML text: wrapping, a11y, rich inline markup) is a **web-only
progressive enhancement layered over** the tspan path — never the _only_ way text
renders, or print breaks. Corollary: **font parity** — the injected `TextMetrics`
must be backed by the _same_ font file in browser (`measureText`) and Node
(`fontkit`), or line breaks diverge between screen and page. One font asset, two
agreeing metric providers. Colour→ink is a `theme` parameter in the SVG-emit step,
not a second layout.

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

**Parked-origin invariant:** the bounding box's top-left is always at local `(0,0)`. The _visible_ element may depart from the origin (pushed in by left/top margins); the bbox never does. This is what makes composition associative.

### 5.2 Margin operators

| op     | meaning                                                  |
| ------ | -------------------------------------------------------- |
| `>>>`  | move element **right**, add left margin, grow bbox       |
| `<<<`  | add **right** margin (element does not move), grow bbox  |
| `\|/`  | move element **down**, add top margin, grow bbox         |
| `/\|\` | add **bottom** margin (element does not move), grow bbox |

### 5.3 Combine = **align, then stack**

To combine sibling BBEs along an axis:

1. **Align.** Find the max extent on the cross-axis (e.g. widest child `bbw=60`). Widen _every_ child's bbox to that max and **re-margin** to locate its element within — for centering, split the slack evenly into left/right (or top/bottom) margins. Centering falls out of the re-margining; no engine fights us.
2. **Stack.** Lay children along the main axis with a fixed gap (e.g. 8). The result is a new BBE whose single bbox contains the compound element.

### 5.4 The compound-nesting invariant (the elegant bit)

When stacking produces a new parent BBE:

- center it by moving its visible elements right by `leftMargin` and expand `bbw` by _both_ left and right margins, **but**
- **set the new BBE's `bblm` and `bbrm` to 0.**

Why: so that when this BBE later nests into a _grandparent_, its ports are computed at the very edges of its bounding box and land in the right place. This is the invariant layman and the Dagre version both lack, and it is what lets nesting compose cleanly down the z-axis.

### 5.5 AND vs OR; orientation

|                           | LR (default)                              | TB                            |
| ------------------------- | ----------------------------------------- | ----------------------------- |
| **AND (`All`)** = series  | stack **horizontally**, center vertically | stack vertically (series)     |
| **OR (`Any`)** = parallel | stack **vertically**, center horizontally | stack horizontally (parallel) |
| leaf                      | upright                                   | rotated 90° CW                |
| "true" line               | on top                                    | on the right                  |
| "false" line              | on the left                               | on top                        |
| parent margins            | left/right                                | top/bottom                    |
| ports default             | top, horizontal-center                    | vertically centered           |

### 5.6 PrePost labels

A disjunctive OR is often surrounded by prose ("if any of the following are true…"). That text needs a parking spot that does not interrupt the flow. Rather than abusing the top margin (breaks invariants), introduce **protrude params** (`protrudeT`, etc.) — an overflow band above/around the bbox reserved for labels. (Open: finalize the protrude model — §13.)

### 5.7 Ports & connectors

- Every BBE has **input/output ports**. Default in LR = "top" (offset from `bbtm` by a default amount) and horizontal "center". Ports may be restyled top/bottom/left/right/middle.
- Explicit port locations are relative to the **element origin** (go right by `bblm`, down by `bbtm`, then adjust by `pl/pt/pr/pb`).
- **Ports sit against the inner element, not the bounding box** — internal margins (`bblm/bbtm/bbrm/bbbm`) are accounted for when drawing connections.
- **Connectors** are drawn at _compound_ time (parent → each child's in/out port), because the child BBEs are absorbed into the parent and would otherwise have no one to draw them. The parent's own connectors sit at the very edges of its bbox — see §5.4 for why `bblm/bbrm=0` matters here.

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

Combinator highlighting: when one branch of an OR is true while siblings are unknown/false, show the circuit **closed over** the true element and **stopped** by false ones. True/false lines are drawn against the _inner_ element (margins-aware), per §5.7.

Combinators: **Leaf, Not, All, Any.** `All [A,B,C]` = series; `Any [A,B,C]` = parallel.

**Sub-ordering within groups (nice-to-have):** the sketch orders children for short-circuit legibility — for `All`, false → true → unknown; for `Any`, true → unknown → false; within a group, by selectivity then source order. This is a _presentation_ reorder, not a tree change. Flag as optional (§13) since it interacts with stable IDs and user expectations about source order.

---

## 7. Scale modes

A single `AAVScale` config drives box sizing; same layout logic, different leaf chrome:

| Scale     | Leaf content                                            | Use                                                 |
| --------- | ------------------------------------------------------- | --------------------------------------------------- |
| **Full**  | boxes grow/shrink to fit free text                      | primary reading view                                |
| **Small** | uniform-size boxes, paragraph numbers ("§12.a.1")       | dense overview                                      |
| **Tiny**  | no labels — just the leaf's `Either (Maybe Bool)` value | **minimap**; mouseover auto-recenters the main view |

Because Small/Tiny are uniform/constant-size, they need **no font metrics** — which also makes them the trivial case for headless print.

---

## 8. Text-measurement strategy (keystone for print)

```
interface TextMetrics {
  measure(text: string, style: TextStyle): { width: number; height: number }
}
```

- **Browser**: Canvas 2D `measureText` against the loaded webfont. No DOM reflow → works before mount, works in a worker.
- **Headless/Node (print)**: `fontkit`/`opentype.js` loading the _same_ font file → identical metrics to the browser.
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

- **layman**: the two-pass measure→center recursion is the proven kernel of §5.3. Port the _idea_, formalized via BBE.
- **`enhance/ladder-expressions` branch**: its use of `L4.ExactPrint` to render `App` nodes with their arguments as leaf text — applicable when we render `App ID Name [IRExpr]` leaves. (The branch's IR is dead; the technique is not.)
- **`insert-ladder-diagram` branch**: nothing structural (dead `RuleNode` IR), but the standalone-app build setup (SvelteKit + Vite, fetch-or-inline JSON polymorphism) is a useful reference for target C.

---

## 12. Package & repo layout (proposed)

```
ts-shared/
  ladder-core/        # pure: IRExpr → BBE → Scene IR (§4.2); no DOM; ViewSpec (§4.3)
  ladder-svg/         # Scene IR → SVG primitives (DOM sink + string sink)
  l4-ladder-visualizer/   # existing pkg, slimmed to the web interactive overlay
                          # (re-exports core/svg; drops Dagre/SvelteFlow layout)
tools/
  ladder-print/       # Node CLI: (IRExpr, ViewSpec) → A3+ SVG/PDF
```

(Alternative: keep everything inside `l4-ladder-visualizer` as internal modules and only split packages once stable. Decide in §13.)

---

## 13. Open decisions

1. **Package split now vs later** — three packages up front, or one package with internal modules until the core stabilizes?
2. **PrePost / protrude model** — finalize how label bands attach without breaking the parked-origin invariant.
3. **Sub-ordering within groups** (§6) — implement the selectivity reorder, or preserve strict source order? Interacts with stable `atomId` and user mental model.
4. **`IRExpr` extensions** (§11) — what, if anything, must move into Haskell vs be derived in TS. **Leading candidate: a `NamedExpr` wrapper for subtree labels** (§16.1) — the wire IR currently can't name an interior node, which folding wants; `@repo/viz-expr` already stubs it out. Decide whether Haskell populates it from the inlined DECIDE/`Where` name, NLG fills it, or both.
5. **Pan/zoom** — `viewBox` hand-roll vs `svg-pan-zoom` dependency.
6. **SVG→PDF tool** — resvg (fast, Rust, no browser) vs headless Chrome (best CSS/font fidelity) vs Inkscape (designer-grade). _(P0 uses `rsvg-convert` for PNG previews.)_
7. **Interactivity in print?** — none, presumably; but confirm whether an "annotated" print mode (showing a worked T/F/U evaluation) is wanted.

---

## 14. Status board (where are we)

_As of 2026-07-08. Branch `mengwong/ladder-diagrams-3`, 22 commits; merged
`origin/unstable` on 2026-07-08 (conflict-free — all work is in new paths), so
**caught up with unstable**. **Pushed + PR'd → [#96](https://github.com/legalese/l4-ide/pull/96)**
into `unstable` (purely additive; ladder-core is standalone, not in the root workspace)._

**✅ P0 — Kernel (DONE).** Pure `IRExpr × TextMetrics × ViewSpec → Scene IR → SVG`,
no DOM (`ts-shared/ladder-core/`, `7136ec92`). Centering thesis proven on the s415
fixture — the Dagre right-alignment is gone. Scene IR (§4.2) + ViewSpec (§4.3)
contracts in place.

**✅ Target C — Standalone interactive page (DONE).** `standalone/` (`a43f8dc0`):
click-to-fold/expand, click-to-cycle T/F/U, reading + connective-style controls,
FLIP animation. `npm run standalone`. _(Not yet driven/screenshot-verified live.)_

**✅ Visual language (DONE, beyond the original plan).** §15 ELIMINABLE don't-care
rung; §16 folding + subtree labels; §17 unboxed inert elements (headings /
connectives / disjunctive-medial / straddle-wire); §18 Bézier fan connectors;
§21 NOT (scope frame + inverter bubble); §22 TYPICALLY defaulted-vs-given
(tentative box + streamer-cap).

**◐ P1 — Semantics (PARTIAL).** ✅ T/F/U valuation + per-node override pins (§19,
`04a8eb47`); ✅ current-flow rendering — leader + streamer "lightning model" (§20,
`3b911701`/`f9d5ffd1`); ✅ **`Either (Maybe Bool)` defaulted-vs-given / TYPICALLY**
(§22 — provenance axis, tentative box, streamer-weight presumption; injected data,
awaiting the viz-expr field once PR #92 lands). ❌ Still open: **Full/Small/Tiny
scales + minimap** (§7); group sub-ordering (§13.3); **predicate leaves / typed
values** (§23 — designed, not built: the membrane, `App`-drawn-open).

**☐ P2 — Live data.** Decode real `RenderAsLadderInfo` from the LSP; render real
statutes. Fixture `cheating-415-poh-yuan-nie.l4` already vendored (§15.4). Not started.

**☐ P3 — IDE integration.** Replace the Dagre path in `l4-ladder-visualizer`;
restore eval/inline interactivity; ship to jl4-web + VS Code. Not started.

**☐ P4 — Print pipeline.** `ladder-print` Node CLI; A3+ PDF; a poster. The
`ViewSpec`→SVG-string seam exists; no CLI/PDF yet. Not started.

**Cross-cutting open** (see also §13): `ladder-svg` package split still deferred
(§13.1); N-line straddle + trailing `Post` (§17); font parity for real metrics (§4.4,
P0 uses an estimator); `NamedExpr` wrapper for subtree labels (§13.4). **Landing:**
eventually push the branch and PR into `unstable`; re-merge unstable periodically to
avoid drift.

---

## 15. Proposed (added this session): rendering ELIMINABILITY — the don't-care rung

**Motivation.** A worked example — Penal Code s 415, _Poh Yuan Nie v PP_ [2022] SGCA 74 — produces a ladder in which one rung is provably _otiose_: under a given reading/fact-context it can **never carry current**. That is the legal doctrine of **surplusage** and the CS notion of **dead code / a don't-care variable** — the same thing. The §6 leaf model (true / false / unknown) cannot express it, yet it is the single most legible thing a ladder can show a lawyer.

### 15.1 A fourth leaf state: ELIMINABLE (don't-care)

Orthogonal to T/F/U:

| state                  | contact                         | meaning                                                                               |
| ---------------------- | ------------------------------- | ------------------------------------------------------------------------------------- |
| known-true             | closed bump                     | current flows                                                                         |
| known-false            | open gap                        | current stopped _here, now_                                                           |
| unknown                | grey passthrough                | value not yet supplied — **may still matter**                                         |
| **eliminable** _(new)_ | ghosted/dashed box, broken rail | value **cannot matter**: flipping it never changes the output over the region in view |

`eliminable ≠ known-false`: a false leaf could flip and change the result; an eliminable leaf is a don't-care — the function's **Boolean difference** w.r.t. it is identically zero. Render: dashed ghost box, reduced opacity, an open-contact break on the rail, optional "otiose" tag.

### 15.2 Source of the flag (both respect the pure-core boundary, §3.2)

- **Annotated** — `ladder-core` takes an `eliminable` map **keyed by node `id`** (positional, _not_ `atomId`: a repeated atom can be live in one rung and otiose in another, and interior `And`/`Or` rungs carry no `atomId`), computed upstream by a minimiser / don't-care prover (Quine–McCluskey / Espresso / a BDD don't-care pass / the Z3 region proof below — cf. the planned boolean-minimization spec, GH issue #638). Just more injected data, like `TextMetrics`. (Leaf **values** stay keyed by `atomId` — toggling a leaf sets it everywhere; only **eliminability** is positional.)
- **Intrinsic** — for small trees, compute it in-core from topology + a partial assignment (cofactor equality per leaf). O(leaves × cases); fine at Small/Tiny.

### 15.3 Minimisation / diff overlay (extends §13.7's "annotated print mode")

Render one geometry tree under two contexts (two interpretations, two fact-assignments, or before/after a minimisation pass) and mark which rungs changed state — especially which went **eliminable**. The headline artifact: two stacked panels of one circuit, the disputed rung live in one and ghosted in the other. The visual proof of a surplusage argument — and a strong poster (target D).

Worked SVG + generator (hand-rolled, pre-`ladder-core`): `~/src/legalese/sandbox/mengwong/layman/cheating-415-ladder.{svg,py}`.

### 15.4 A real fixture for P0 / P2

s 415's second limb is a clean, legally-meaningful AND/OR tree — `And[ Or[by-deceiving, dishonest-concealment], intentionally, causes-harm, Or[body, mind, reputation, property] ]` — exercising centering, parallel groups of 2 _and_ 4, and the new eliminable state. Better than a toy. Source of truth: `jl4/ok/inert/cheating-415-poh-yuan-nie.l4` — **now vendored in this branch** (cherry-picked from `poh-yuan-nie` `21b62316`, so the patch is identical and will merge to `unstable` without conflict). Canonical home stays the _Poh Yuan Nie_ work; if it diverges, reconcile on `unstable`. Its Z3 surplusage proof `cheating-415-surplusage.z3.py` (in `~/src/legalese/sandbox/mengwong/layman/`) is exactly the upstream minimiser that would emit the `eliminable` map.

---

## 16. Folding & progressive disclosure

Collapsing an interior `And`/`Or` (or any subtree) into a placeholder, and
expanding it back, is a first-class interaction — and the single best stress test
of the layout core, so P0 builds it in.

- **A fold is a core _input_, not a renderer trick.** A collapsed node lives in
  `ViewSpec.foldSet` (§4.3); the core treats it as a leaf-shaped placeholder and
  re-runs align-then-stack, so everything re-centers with no renderer special-casing.
  That folding "just works" is itself evidence the BBE architecture is right.
- **The placeholder keeps the verdict.** A folded subtree still carries its
  evaluation state — fold the _detail_, keep the _answer_: a collapsed satisfied OR
  renders live ("▸ ANY OF 4 ✓"); collapsed-unknown stays grey; collapsed-eliminable
  shows the ghost (§15). Scene IR marks it `role: 'placeholder'` with the rolled-up
  `state`.
- **Identity across fold/unfold** uses the keys we already have: positional `id`
  tracks structure (fold state + animation), `atomId` keys leaf values. FLIP
  animation is clean because the core yields exact pre/post rects — collapsing
  children scale/fade into the placeholder deterministically.
- **Eliminable ↔ fold are partners.** Surplusage = collapse-by-default: a dead
  subtree folds to a ghosted "otiose — collapsed" placeholder; expand to inspect.
- **Explainability payoff.** Fold to the top-level verdict, then expand only the
  branch that _did the work_ (the live path). "Why TRUE? → expand the satisfied
  OR." Auto-expand-the-deciding-path is a headline feature.
- **Heuristics & persistence.** Auto-fold beyond depth N for large statutes;
  "focus mode" folds siblings; the Tiny minimap (§7) stays fully expanded while the
  main view folds. Fold state persists per node-path across re-eval and sessions.

The s 415 fixture exercises it: fold the whole second limb to its verdict, then
expand just the deception gateway to watch the concealment rung go live (court's
reading) or ghost-and-fold (applicants').

### 16.1 Does the IR need a way to label a subtree?

A folded interior node needs a **name** to show. Three tiers, all worth supporting:

- **Tier 0 — synthesize from structure.** "▸ ALL of 4" / "▸ ANY of 2". Always
  available, no IR change, uninformative. The P0 fallback.
- **Tier 1 — synthesize from children (NLG-lite).** Join child labels: "deceiving
  OR concealment". Fine when shallow; degrades with depth. No IR change.
- **Tier 2 — an explicit subtree label on the IR.** The only way to get a _legible_
  fold like "there is a deception" or "harm to…". **The current wire IR cannot do
  this** — `And`/`Or` carry only `id` + `args`; interior nodes are anonymous, and
  the name is _lost_ at the Haskell boundary when a named DECIDE/`Where` body is
  inlined.

Recommendation: support all three, precedence Tier 2 → 1 → 0. For Tier 2, **do not
fatten `And`/`Or`** (keep them clean n-ary monoids); add an optional **`NamedExpr`
wrapper** `{ name, expr }` — which `@repo/viz-expr` _already stubs out_ (commented,
`viz-expr.ts` ~L198–211, alongside `AppNamed`). Populate it on the Haskell side
from the L4 name the subtree was inlined from, and/or via NLG (cf. the NLG
round-trip work). The core takes a label resolver; absent name → fall to Tier 1/0.
This also supplies the §5.6 PrePost heading text. **P0 already proves it:** the
core honours an optional `label?` on a group, so the `harm` fold renders
"▸ harm to…" not "▸ ANY of 4". Promoting that to the wire IR (`NamedExpr`) is the
durable step — tracked in §13.

**Relation to upstream #630 ("visualizer expansion could use some improvement").**
#630 is the _current-codebase symptom_ this section supersedes. Today expansion is
gated by an ad-hoc `canInline`: it fires only for a boolean `UBoolVar` that resolves
to a **same-file top-level `DECIDE`** (`jl4-core/src/L4/Viz/Ladder.hs:169-173,
380-392`); functions-with-arguments are unsupported (`App appAnno _fn args`,
`Ladder.hs:350`), imported / `WHERE`-bound refs don't expand, and the inlined name
is lost at the Haskell boundary. The 2026 model dissolves all four: fold/expand is a
first-class **core input** (`ViewSpec.foldSet`, §4.3), so _any_ subtree is
expandable without a special-case predicate; **Tier-2 `NamedExpr`** (§16.1) recovers
the lost inline name; and broadening to functions-with-args / imported / `WHERE`-bound
falls out for free. So #630's fix is **"adopt the §16 fold model"**, not another
patch to `canInline` — and #630 is an _enhancement_, not a bug.

---

## 17. Unboxed elements (inert content) — PrePost generalized

**The unification.** Four things we treated separately are one primitive:

| surface form                                                   | was                             |
| -------------------------------------------------------------- | ------------------------------- |
| "all of:" / "any of the following" group heading               | PrePost `Pre` on a group        |
| "either … or …" connective between rungs                       | inert string between atoms      |
| inert-style verbatim prose ("as such an officer or employee,") | `InertE` node, context-identity |
| the decoration the box model wanted to "park"                  | §5.6 protrude band              |

All four are **inert text**: the identity of their context (TRUE under AND, FALSE
under OR), so they carry **no current**. A thing that carries no current must not
be a **box** (boxes are operative atoms that open/close the circuit) — it renders
**unboxed**. That is the whole idea.

**PrePost is subsumed into positional `InertE`.** Inert style already places
headings and connectives by _position in the args list_, so we don't carry a
separate PrePost field on the wire IR; "PrePost" survives only as vocabulary:

- **leading** inert run → the group's `Pre` (heading)
- **medial** inert (between operative siblings) → a connective
- **trailing** inert → `Post`

The current IR already has `InertE` (with `InertAnd`/`InertOr` context); we were
about to _box_ it, which was the bug. (`Leaf` no longer includes `InertE`; it is
its own node.)

**Placement (locked, except as noted).**

- **OR heading → above the stack.** Seated in a protrude band (§5.6); P0 mirrors
  the band top+bottom so the stack stays centered and the rail stays straight.
- **"Left of a stack" is not a special case** — express it as a conjunction:
  `inert … (stack)`. In LR a series puts the leading inert to the left for free.
  So no dedicated "left heading" placement is needed.
- **Conjunctive (series) inerts → an unbroken wire, prose above** — the wire stays
  _continuous_ (inert = identity = always conducts, so the line must not break for
  it). This makes inert placement uniform: **all inert text lives above what it
  annotates** — headings above stacks, connectives above wires — one reading rule.
- **Long connectives straddle the wire** (default `connectiveStyle: 'straddle-wire'`,
  _adaptive_): prose wider than ~a box (`STRADDLE_MIN_WIDTH`) word-wraps to two
  width-balanced lines, half above / half below, the wire threading between —
  ~halving the horizontal footprint (which long verbatim inert prose otherwise
  wastes) at the cost of vertical space (which a series has to spare). Short prose
  stays a single line above, so `'straddle-wire'` is a strict superset of
  `'above-wire'`. `'below-wire'` and `'on-wire'` remain toggles; `'on-wire'` is
  discouraged (its gap reads like a contact, which inert never is).
- **Disjunctive medial inert → centered in the inter-rung gap.** An inert _between_
  two OR rungs (e.g. "or") sits unboxed, centered in the gap between the boxes,
  connected to nothing (it carries no current). The gap widens only if the text
  needs the room (`max(GAP_PARALLEL, lineHeight + 8)`) — minimal margin.
- _(Open: N-line straddle for very long statutory clauses; trailing inert as a
  `Post` below a group.)_

**Scene IR / layout.** The `text` prim gains roles `heading` and `connective`
(unboxed, italic, inert ink — no rect, no ports). `measureOr` extracts the leading
inert run as the heading; `measureAnd` measures inert children inline (`inertInline`
gives them left/right ports so the wire connects through). Folding prefers the
explicit label, then the leading inert (the Pre), then synthesizes — so folding the
deception group yields "▸ there is a deception (Expl. 1)".

**The payoff — the diagram _becomes_ the statute.** Boxed = operative predicates;
unboxed = verbatim inert prose. Read together, the rung reads as the section:
_"there is a deception (Expl. 1)" [by deceiving / dishonest concealment] →
intentionally → induces an act or omission that → causes harm → to any person in →
[body / mind / reputation / property]_. The visual form of inert style; the
isomorphism (source ↔ logic ↔ picture) made legible at once. **Proven in P0** —
`demo/s415.ts`, `demo/out/s415-court.svg`.

---

## 18. Connector style — the Bézier fan

Connectors are **cubic Béziers with horizontal tangents**, fanning from a group's
single in-port out to every rung (and converging again at the out-port) — the
Layman / box-model look (Layman sets `sourcePosition: Right` / `targetPosition: Left`
on ReactFlow's default bezier edges; we emit the curves directly). The OR's vertical
bus + right-angle stubs are gone; the organic curves now play against the
**rectilinear** term boxes and the **straight** spine (rails, series links, leads
stay linear). One reading: boxes + spine are rigid structure, curves are flow.

- Scene IR gains `{ kind: 'curve'; from; c1; c2; to }`; `hCurve(from, to, state)`
  builds it (tangent `t = clamp(max(0.6·|dx|, 0.35·|dy|), 22, 60)`); svg emits a
  `<path>` (class `lad-wire`, so it still fades on FLIP).
- An eliminable/dead rung's in-curve is dashed/ghosted with the open-contact break
  glyph at the curve's parametric midpoint (`cubicMid`).
- Curves carry the rung's `state` colour (green live / grey unknown / ghost dead).

---

## 19. Valuation, override & the gesture split

**Valuation.** `ViewSpec.valuation: Map<NodeId, UBoolValue>` — a _positional_ (by node
id) T/F/U. For a **leaf** it's the atom's value; for a **group** it's an **override /
pin**: the node is treated opaquely with that value and **its children are not
consulted**. Absent ⇒ groups derive from operative children (`nodeValue`, three-valued),
leaves are unknown / constant. Box render state = `vs.states.get(id)` (manual override,
e.g. eliminable) ?? `valueToState(value)`.

**Override, without a witness.** Pinning a group lets you assert _"deception is made
out"_ without committing to which child decides it — the parent is more determined than
its children. (Stance: **override** — the assertion wins; conflicting child values are
subsumed. The consistency-checking alternative is the essay's _contradiction-detector_,
deferred to a later layer.)

**The gesture split.** Every drawable carries an optional `ClickAct` the renderer turns
into a `data-value` / `data-fold` attribute (host-wired):

- **box** (leaf or folded placeholder) → `value`: click cycles U → T → F → U. A folded
  placeholder cycles the _parent's_ override.
- **heading**, **fan connector**, **▸ caret** → `fold`: click folds / expands that group.
  (Clicking a connector folds the group it belongs to; the caret expands a placeholder.)

This makes "value the parent" need no new concept — it's just "click a box," because a
folded subtree _is_ a box. Proven live in `standalone/` and the `s415-interactive`
snapshot: `harm` folded and pinned true renders a green `▸ ANY of 4` while its children
stay unknown.

**Next (P1): current flow.** The energization pass (DESIGN discussion): propagate
current from the source — closed paths drawn **thick + dark**, open ones thin + light,
the FALSE break-glyph at the stop — so cycling values visibly closes the circuit, and
satisfied-OR siblings ghost as don't-cares. Binary closed/open (UNKNOWN = open) per the
box-model spec.

---

## 20. Current flow — leader + streamer (the lightning model)

Cycling values closes the circuit, drawn by **darkening + thickening** the connectors
(box-model.pdf: _closed over true, stopped by false_). `ViewSpec.showCurrent` gates it
(off ⇒ static/print demos keep state-coloured connectors). Three levels per connector:

| level        | weight·ink        | meaning                                                                                                |
| ------------ | ----------------- | ------------------------------------------------------------------------------------------------------ |
| **closed**   | thick, near-black | reached by the **leader** — a closed run _from the source_                                             |
| **streamer** | medium, mid-grey  | **local closure** — a conducting element lights its own connectors even with no path to the source yet |
| **open**     | thin, light       | neither                                                                                                |

**Why the streamer (Meng).** A purely source-driven model only shows the leader
descending — it can't reveal that a TRUE leaf nested deep in `harm` is _locally_
closed. The metaphor is lightning: the bolt (leader) reaches down from the cloud while
**ground streamers rise to meet it** — they join in the middle. Showing local regions
of closure lets a reader piece a path across the circuit **without** imposing a
top-down / left-to-right direction of flow. As more atoms go true, streamers grow and
snap to `closed` when the leader arrives.

**Computation** (pure, DESIGN §3.2):

- `nodeValue` → three-valued value; `conducts(n) = value===TRUE` (inert conducts
  trivially; only a TRUE _atom/group_ — `trueConducts` — raises a streamer).
- `energize()` — forward (leader) reachability from the source: a series stops at the
  first non-conductor; an OR's output closes iff some branch conducts. Fills `inE/outE`.
- per connector: `flowFor(leader, local)` → leader ? `closed` : local ? `streamer` :
  `open`. Series link: leader = the upstream child's `outE`; local = either adjacent
  element conducts. OR fan: in-curve leader = OR's `inE`, out-curve leader = branch
  `outE`; local = the branch conducts.

Verified: `s415-streamer` — leader stops at `causes harm`, `body` TRUE streamers its
fan connectors. _(Future: a backward pass from the sink would let streamer + leader
distinguish a genuinely **complete** source-to-sink path from a merely partial one.)_

---

## 21. NOT — scope frame + inverter bubble

`not(complex)` poses two problems a bare `¬` can't: **scope** (is it `not(A and B)`
or `(not A) and B`?) and **inversion in the flow** (a negated region conducts when
its insides are _open_). The grammar:

- **Inverter bubble** — a small open circle on the negated element's **output port**
  (digital-logic convention). The _universal_ NOT mark: identical for leaf and
  complex, so the leaf case stops being special.
- **Scope frame** — for a _complex_ negand, a light dashed rounded enclosure tagged
  **NOT**. It draws the bracket the algebra implies. (A leaf negand gets just a small
  `NOT` tag + the bubble — no frame.)
- **Flip at the bubble.** The negand renders its **own** internal flow (its leaves'
  values, its leader/streamers). The wire _past_ the bubble is energized iff the
  inside is **open**: `not.outE = inE && !conducts(negand)`. You see the current flip
  at the mark.

**Nesting** (`not(x(not(ys)))`) falls out for free — frames within frames, each
NOT's bubble on its own output port at its own level. Two bubbles in series read as
double-inversion (they "cancel"), which is correct and legible. `nodeValue` /
`energize` already recurse through `Not`, so the compounded inversions compute right.

Layout: `measure(Not)` wraps the negand with symmetric padding (port stays centred,
rail straight), emits the frame, a lead in, the negand-output→bubble segment (inside
flow), the bubble, and the bubble→output segment (inverted flow). Scene IR gains a
`frame` prim and an `inverter` glyph.

Verified: `not-nested` — `not(And[registered, not(Or[sat, submitted])])`, leader thick
to the inner bubble, thin between the bubbles, thick past the outer one.

_Alternatives (not chosen): **evaluate-aside** — pull the negand off the main rung as
a sub-circuit driving a normally-closed contact (relay-accurate, more layout); **De
Morgan push-down** — rewrite NOT to the leaves (changes displayed structure; better as
an optional "normalize negation" view)._

---

## 22. Defaulted vs given — TYPICALLY presumptions

A leaf's value has a **provenance** the ladder should show: did it come from the user
(or real data), or is it riding a **rebuttable presumption** the user hasn't confirmed?
This is L4's **TYPICALLY** — `x IS A BOOLEAN TYPICALLY TRUE` — and the box-model.pdf's
default model `type Default = Either (Maybe Bool) (Maybe Bool)`, where **`Left` = a
default (system-supplied, no user input)** and **`Right` = user-given**. The four cells
map straight onto render:

| `Default` value  | provenance · value | reads as                                               |
| ---------------- | ------------------ | ------------------------------------------------------ |
| `Left (Just b)`  | `default` · b      | **presumed** b — tentative box, riding TYPICALLY       |
| `Left Nothing`   | — · unknown        | never asked, no default — plain grey (today's UNKNOWN) |
| `Right (Just b)` | `given` · b        | user answered b — solid box                            |
| `Right Nothing`  | `given` · unknown  | user said _don't-know_ — a **confirmed** unknown       |

**Provenance is a third axis** — orthogonal to the T/F/U value (§6) _and_ to the render
`State` (live/eliminable, §15). A leaf can be TRUE-and-presumed, TRUE-and-given,
FALSE-and-presumed… `ViewSpec.provenance: Map<NodeId, Provenance>` (`'given' | 'default'`,
absent ⇒ `given`) carries it — **injected data, keyed by node `id`**, exactly like the
`eliminable`/`states` maps (§15.2) and respecting the same pure-core boundary.

**The visual grammar (three moves, all shipped):**

- **Tentative box.** A `default` leaf renders **fine-dashed** (`1.5 3`, distinct from
  eliminable's coarser `5 4`) with **normal ink** — a presumption, not a ghost — plus a
  small amber **`typically`** tag. Solid box = grounded/given.
- **Streamer-weight closure.** Current flowing _through_ a presumed-true contact is
  capped at **streamer** weight (§20), never full leader-black: `flowFor(…, tentative)`
  degrades a would-be `closed` to `streamer`. A rebuttable presumption closes the circuit
  only **provisionally**. This _reuses_ the lightning model — streamer already means
  "closed, but not (yet) confirmed": by locality (a ground streamer) **or** by provenance
  (a presumption). Both are tentative closure; one channel, two reasons.
- **Defaults-used-vs-not, at a glance.** The box-model.pdf asked to show "defaults being
  used or not." The dashed/amber marks _are_ that view: they highlight exactly the inputs
  still resting on a presumption. Fold to the verdict (§16) and the tentative marks that
  survive answer **"how much of this outcome rests on presumptions?"** When every input is
  `given`, no tentative mark remains — the verdict is fully grounded. Inside one group the
  contrast is legible too (fixture: `mind` presumed → its OR-fan curves go streamer while
  `body`/`reputation`/`property` stay closed-black).

**Wizard tie-in** ([[question-ordering-wizard]]). A presumed-TRUE atom has ≈0 information
gain, so the greedy planner sinks it to the bottom of the ask-order — "don't ask, allow
override" falls out with no special-casing. The ladder is the _picture_ of that: the
tentative leaves are precisely the questions the wizard didn't need to ask. TYPICALLY is
the priors mechanism and the provenance mark at once.

**IR-independence.** `@repo/viz-expr` does **not** carry TYPICALLY yet (the metadata-only
salvage is PR #92, not in `unstable`; the 5th `MkTypedName` field on the Haskell side).
So the core takes `provenance` as injected data today; when #92 lands and the wire IR
grows the field, populate it from the L4 TYPICALLY — no core change. Same staging as §15.

*Future: (a) **propagate** tentativeness along the leader so a segment *downstream* of a
presumed contact also reads provisional (today only the presumed leaf's own adjacent
connectors cap — local, like §20's streamer); (b) distinguish `Left Nothing` (never
asked) from `Right Nothing` (a confirmed don't-know) — both grey today, but the latter is
a settled fact the wizard should not re-ask.*

**Shipped:** `types.ts` (`Provenance`, `ViewSpec.provenance`, box `tentative?`, text tag
`typically`), `layout.ts` (`presumedConducts`, `flowFor(tentative)` cap, tentative
`leafBox`), `svg.ts` (fine-dash box, amber tag). Verified: `demo/out/s415-defaults.svg`.

---

## 23. Predicate leaves — the membrane between circuit and data

A ladder is a **Boolean** circuit; its atoms conduct or don't. But a boolean atom is
usually a **predicate applied to a typed value** — `age ≥ 18` is `(≥ 18)` applied to
`age : Number = 21`. The **predicate is the membrane** between two worlds: **outside** it,
the boolean circuit (everything opens/closes); **inside** it, typed data (everything is a
value). This generalizes the default model of §22 from `Bool` to any `a` —
`type Default a = Either (Maybe a) (Maybe a)` — because the value under the predicate can
itself be defaulted (`age TYPICALLY 18`) or given.

**Rendering — a leaf with an interior.** A predicate leaf draws as an outer **predicate
band** carrying the leaf's T/F/U (the part that conducts) wrapping an inner **value chip**
— a small typed datum, e.g. `age = 21` set in a quoted/monospace pill. The contact state
(closed/open) _is_ the predicate's verdict on the value; the chip is just data. Sketch:

```
┌── age ≥ 18? ───────┐        the band booleanizes …
│    ┌─────────┐     │        … the chip it wraps
│    │ age = 21│     │        chip = typed value (Default a, §22)
│    └─────────┘     │        band = predicate (the membrane)
└────────────────────┘        band's border colour = T/F/U as usual
```

**The dual of folding.** Folding (§16) _collapses upward_: it hides a subtree of the
circuit behind one boolean placeholder — zoom out to the verdict. A predicate leaf
_expands downward_: it reveals the typed value **below the boolean floor** that feeds the
atom — zoom in to the datum. Same pivot (the leaf = the boolean floor), opposite
direction. "Why is `age ≥ 18` true? → open it → because `age = 21`."

**Not a new node — it's `App`, drawn open.** `@repo/viz-expr` already models these atoms
as **`App { fnName, args }`** — `App(">=", [Var "age", Lit 18])`. Today the core draws an
`App` leaf as one opaque box; a predicate leaf is just _looking inside_ that `App`:
`fnName` → the predicate band, the literal `arg` → the value chip. So §23 is largely a
**rendering** over structure the IR already has, plus value/type metadata (and, for a
defaulted chip, the §22 provenance) on the leaf.

**Why this explains the wizard's Boolean-only wrinkle.** [[question-ordering-wizard]]
notes the trap that `age TYPICALLY 18` is **not** `P(age ≥ 18)` — only a _boolean_
TYPICALLY is an atom prior. The membrane says why: that presumption lives on the value
chip **below** the membrane, while the wizard needs a prior on the boolean atom **above**
it. They're on opposite sides; to turn a value default into an atom prior you'd have to
push the distribution _through_ the predicate (`P(≥18 | age∼18)`). The picture makes the
category error visible.

**Scope.** v1 is a **static sketch** — the chip is display-only, rendered from injected
value/type metadata; live typed-value _editing_ (a real input widget) is a P3 web
affordance. Keep the boolean circuit the load-bearing layer; the membrane is a
progressive-disclosure detail on individual leaves. **Not built** (design captured here;
the `App`-open rendering + a `age = 21 / ≥ 18?` fixture are the next increment).

---

## Appendix — source materials

- `tmp/box model.pdf` — the BBE box model (margins, ports, connectors, align-then-stack, the `bblm/bbrm=0` nesting invariant, LR/TB, Full/Small/Tiny scales). Primary spec for §5–§7.
- `tmp/ladder logic and or tree visualization.pdf` (2023-05-21) — ladder-logic metaphor, `Either (Maybe Bool) (Maybe Bool)` default model, Leaf/Not/All/Any combinators, T/F/U leaf rendering, group sub-ordering. Primary spec for §6.
- `~/src/legalese/sandbox/mengwong/layman` — iteration 2; proven two-pass centering recursion.
- `ts-shared/l4-ladder-visualizer` — iteration 3; the code being refreshed.
- `jl4-core/src/L4/Viz/{Ladder,VizExpr}.hs` — the topology IR boundary we keep.
