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

**◐ P2 — Live data.** Decode real `RenderAsLadderInfo` from the LSP; render real
statutes. Fixture `cheating-415-poh-yuan-nie.l4` already vendored (§15.4). **A1 done:**
`ts-shared/ladder-core/src/viz-adapter.ts` maps the `@repo/viz-expr` wire IR →
ladder-core `IRExpr` + lifts `valuation` and `provenance` side-channels. ☐ Remaining:
the live LSP transport (A2 — `l4/evalApp` · `l4/inlineExprs` · `l4/queryPlan`) and real
browser `measureText` metrics (A4).

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

### 21a. Normally-closed contacts — the idiom we skipped _(proposed; not built)_

The Mermaid exercise (§24.2) forced a re-read of the two alternatives above, and they were
the right ones. The reasoning, which §21 never made explicit:

**Structural NOT is not needed for expressiveness.** Negation normal form pushes every `¬` down
to the atoms, and a negated atom needs no gate — only a **polarity**. Ground `¬x` as `¬v(x)` and
negation vanishes from the circuit's structure entirely, becoming a property of a _contact_
rather than a thing _between_ contacts. This is not a trick: it is the **normally-closed contact**
`─┤/├─` of IEC 61131-3, the notation this whole diagram descends from. We inherited a ladder
language that already had negation, and drew a scope frame instead.

So the two mechanisms do **different jobs**, and we should ship both:

| Negand                | Render                                                      | Why                                                                                          |
| --------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| an **atom**           | **normally-closed contact** — the box, with a `/` across it | native, compact, and the reader sees the polarity _on_ the contact                           |
| a **complex subtree** | the §21 **scope frame + inverter bubble**                   | the reader must see the negation's **extent**; that is explanation, not expressive necessity |

And **"normalize negation" (De Morgan to NNF) becomes a real `ViewSpec` toggle**, not a
curiosity — it turns `¬(P) ∨ Q` into a flat disjunction of the ways to comply. That is close
kin to the sentence expander (`sentences.ts`: And = product, Or = union), and answers a
different question than the isomorphic view does: not _"what does the rule say?"_ but _"how may
I comply?"_. Keep the isomorphic view primary — NNF re-expresses the statute's own shape and so
breaks the read-back-against-the-text property that is the ladder's whole point (§0) — but offer
NNF as the second view.

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

**IR-independence.** `@repo/viz-expr` now **does** carry TYPICALLY: `UBoolVar.typically`
(`optional(NullOr(Boolean))`), threaded end-to-end by the question-ordering v2 work
(PR #110) — one shared wire field, "build once", feeding both the v2 ordering weights
(`typicallyBridge`) and this provenance mark. The core still takes `provenance` as
injected data (no core change); `ts-shared/ladder-core/src/viz-adapter.ts` populates it
on the P2 decode path — a leaf whose `typically` is a concrete boolean (not `null`) is
marked `default`. Same staging as §15.

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

## 24. Embedding ladders in Markdown (GFM) — carriers, and why not Mermaid

**The ask.** `doc/concepts/language-design/logic-not-flowcharts.md` argues that a regulatory
condition is a Boolean predicate, that a flowchart is the wrong picture for it, and that the
ladder diagram is the right one — and then shows _no ladder_. It should. More generally: a
ladder should be able to travel in a README, a PR comment, an issue, a commit message.

### 24.1 The constraint that decides everything: where does the Markdown render?

`doc/` has a `SUMMARY.md` (the mdBook/GitBook convention) but **no `book.toml`** — it is not
built into a site today. It is read **on github.com**. So github.com's renderer is the binding
constraint, and it is a _sanitizing_ renderer. What it permits:

| Mechanism                            | On github.com | Notes                                                                                                                              |
| ------------------------------------ | ------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Fenced code block                    | ✅ verbatim   | universal — also PR comments, commit messages, terminals, email                                                                    |
| `![](x.svg)` / `<img src>`           | ✅ renders    | already used (`doc/README.md` → `![L4 Logo](./l4.svg)`). Loaded as an image ⇒ **no script, no CSS interaction, no links.** Static. |
| Inline `<svg>…</svg>`                | ❌ stripped   | GitHub's HTML sanitizer. _(verify before building — but the `<img>` route is the right one regardless, for portability)_           |
| ` ```mermaid `                       | ✅ native     | the **only** diagram DSL GitHub renders — and it is **current** Mermaid, not a pin. See §24.2, which corrects this row.            |
| `<picture>` + `prefers-color-scheme` | ✅            | ⇒ ship a light/dark SVG pair (our `theme: 'screen' \| 'ink'` palettes already exist)                                               |
| `<details>` / `<summary>`            | ✅            | ⇒ a poor-man's §16 fold: folded image in the summary, expanded inside                                                              |
| `$$…$$` MathJax                      | ✅            | no TikZ. Dead end for diagrams.                                                                                                    |

### 24.2 Mermaid — the verdict stands, the reasoning was wrong

> **This section was rewritten after an adversarial check** (`tmp/mermaid-planb.md`, which
> replayed GitHub's exact rendering pipeline and rendered candidates rather than reasoning from
> memory). **Two of the three premises the first draft rested on were false.** The conclusion —
> don't do it — survives, but on a different and much stronger argument. Keeping the record of
> the error here, because the first draft's confidence was unearned.

**What was wrong.** ① GitHub does **not** pin an old Mermaid: it renders in a sandboxed
`viewscreen.githubusercontent.com` iframe whose bundle's diagram registry is **identical to
current `mermaid@11.16.0`** (38 detectors), with no diagram-type allowlist. ② GitHub does
**not** sanitize directives: its `secure` list is only
`["secure","securityLevel","startOnLoad","maxTextSize"]`, so `%%{init}%%` / frontmatter
`config:` — including **`themeCSS`** — take effect, and its DOMPurify allowlist passes
`<style>`, so Mermaid's injected CSS survives. ③ And the first draft only tested `flowchart`
and `block-beta`. It never looked at **`railroad-beta`**.

**Railroad-beta is a ladder renderer.** Concatenation = series on one wire; alternation =
stacked rungs fanning off a common node; no arrowheads; power terminals at both ends. And —
this is the part that stings — reading the emitted SVG transforms shows it centres a `choice` on
**the vertical centre of its own bounding box**, with the parent `sequence` aligning to that
axis. That is **§5.3/§5.4 align-then-stack, compositional at arbitrary depth**: the very
property Dagre could not give us, and that this entire kernel was rebuilt to obtain, Mermaid's
railroad renderer already has. A hand-written s415 comes out looking startlingly like
`s415-court.svg`. With `themeCSS` you can further reach state colour, the §15 ghost rung, §22
fine-dashes, unboxed inert prose, and even §20 current-flow stroke weights — perhaps 70%
fidelity, on github.com, today.

**The NOT objection was also wrong** (correction #2 — the second draft claimed railroad "has no
NOT", so `¬P ∨ Q` and hence the material conditional were "structurally undrawable"). Meng:
_"railroad diagrams basically are ladder diagrams modulo a de Morgan treatment of negation."_ He
is right, and there are in fact **two** ways through, both rendered and verified:

1. **Negation normal form.** De Morgan pushes negation down to the atoms:
   `¬(upper ∧ (wall ∨ roof)) ≡ ¬upper ∨ (¬wall ∧ ¬roof)`. Negated atoms are just leaves, which
   railroad draws fine. A.3 comes out as a clean three-rung `choice`. **This is not even a hack:
   a negated atom in IEC 61131-3 ladder logic _is_ a primitive — the NORMALLY-CLOSED CONTACT
   `─┤/├─`.** NNF is the native ladder idiom, and we are the ones not using it (see §21a below).
2. **Factor and fold.** Railroad is a _grammar_ notation: several named rules. Write
   `complies = choice(nonterminal("NOT: A3 covers"), nonterminal("A3 requirement met"))` plus the
   two rules it names, and you get the material conditional at top level, with the antecedent
   folded — which is _exactly_ the L4 factoring, rule for rule. The cost is that the `NOT` is
   then only a **word**: nothing in the picture inverts, so the reader must read the negation
   rather than see it.
3. **Push it into grounding** (Meng again, and this is the general form of ①). A renderer needs no
   negation _primitive_ at all if the leaf carries a **polarity**: ground `¬x` as `¬v(x)` at
   valuation time. Negation then never appears in the circuit's _structure_ — it is a property of
   a contact, not a gate between contacts. Which is, once more, precisely the normally-closed
   contact. Any series/parallel notation whatever is then sufficient.

The right way to say it: **structural NOT is not needed for EXPRESSIVENESS at all** — NNF plus
leaf polarity covers every Boolean function. §21's scope frame earns its keep only for
**EXPLANATION**: showing a reader the _extent_ of a negation over an un-normalised subtree, which
is a presentation service, not an expressive necessity. Worth knowing which of the two we are
selling.

So: **Mermaid CAN draw our ladder.** Capability is no longer the argument, and after being wrong
twice about capability we should stop making capability arguments.

**What actually decides it is PROVENANCE — and it is the document's own thesis.**

> "a diagram is a good _view_ of legal logic and a bad _substrate_ for it… the language is the
> source, the picture is derived."

A hand-written Mermaid ladder in the Markdown is a **second, unverified source of truth.** It is
not derived from the L4; nothing checks it against the L4; it will drift. That is precisely the
inversion `logic-not-flowcharts.md` exists to condemn — and we would be committing it _inside the
document that condemns it_. Note that this objection does not depend on any capability claim, and
so cannot be falsified the way the last two were.

The moment you _generate_ it to prevent drift, you have conceded a build step — whereupon
**§24.3's option I-a strictly dominates**: same build step, zero fidelity loss, plus folding,
current flow, print and dark mode. So Mermaid's single prize (source-in-the-Markdown, no build
step) is collectible only in the form that makes the picture unverifiable.

**Verdict: still don't — but now for a reason about where truth lives, not about what Mermaid can
draw.** The residual capability gaps (no text wrapping for statutory prose, no folding, no
interactivity, no print) are supporting, not decisive.

### 24.2a Correction #3 — and the verdict finally flips. **`I-d`, SHIPPED**

The provenance argument above is sound, and it **only ever killed the _hand-written_ Mermaid
ladder.** Meng: _"surely we can justify building a Mermaid railroad outputter from our ladder
diagrams … or from the AST that generates the ladder diagrams."_ Quite. **Generated, the picture
is derived — which is the thesis, not a violation of it.** The whole objection evaporates.

And the fallback ("once you concede a build step, committed SVG dominates") was too quick. A
generated Mermaid fence beats a committed SVG on things the earlier drafts never weighed:

- it stays **text in the Markdown**, so `git diff` shows a _semantic_ change (`"in a wall"` →
  `"in a window"`), not two hundred lines of path coordinates;
- **no binary** in the repo (cf. the open H1 question);
- **no build tooling at render time** — github.com does the rendering.

SVG still wins on fidelity. But a _documentation figure_ does not need current flow, folding or
interactivity. It needs structure — and railroad has exactly ours.

**Cost: ~180 lines** (`src/mermaid.ts`), because `railroad-beta`'s grammar **is** our IR:

| IRExpr  | railroad        |                                         |
| ------- | --------------- | --------------------------------------- |
| `And`   | `sequence(...)` | series on one wire                      |
| `Or`    | `choice(...)`   | stacked rungs fanning off a common node |
| `Leaf`  | `nonterminal()` | a boxed, operative atom                 |
| `Inert` | `terminal()`    | unboxed grammatical prose (§17)         |
| `Not`   | see §21a        | fold to `NOT <name>`, or De Morgan      |

So it is a **pretty-printer over the same tree that feeds `layout()`**, not a second renderer.

**One real bug, caught only by rendering it.** Inert prose must _not_ survive into a `choice`.
In the ladder an inert child of an OR is a **heading** and carries no current (§17) — but every
child of a railroad `choice` is a live **branch**, so emitting the prose as a rung silently adds
a free pass-through path and makes the disjunction **trivially satisfiable**. Fix: hoist the
leading run in front of the fan (`sequence(terminal("either"), choice(...))`, where it reads as
the drafter's preamble) and drop the medial `"or"` glue, whose job the fan already performs.
Pinned in `test/mermaid.test.ts`. _Look at the render; do not trust the tree._

**Result.** `logic-not-flowcharts.md` now draws its ladder with the **same engine that draws its
flowcharts**, so the only thing differing between the two pictures is the notation — which is
much the strongest form of the argument. The fence is byte-identical to the generator's output,
so it is CI-checkable (regenerate; fail if dirty). The ASCII ladder (I-b) stays, in a
`<details>`, as the second carrier — demonstrating the page's own thesis in the page: **two
pictures, one source, neither of them the truth.**

**Two things to salvage.** (a) Mermaid `flowchart` should go **into** `logic-not-flowcharts.md`
as the exhibit for the _wrong_ picture — GitHub renders it natively, and the rendered GPDO
flowchart shows `permitted` duplicated **three times** and `BAD!!!` twice, which is exactly the
sub-condition duplication the document currently only _asserts_. Let Mermaid do the one thing
Mermaid is genuinely good at: drawing the wrong picture, convincingly. (b) `railroad-beta` is a
free external **oracle** for sanity-checking `ladder-core`'s layout on the AND/OR-only subset.

### 24.3 What to build instead: one Scene IR, many carriers

The architecture already anticipated this. `IRExpr → BBE → Scene IR` with an **injected
`TextMetrics`** and a **swappable renderer** was built for print parity (§4.4); the Scene IR is
the fork point, and each carrier is just another emit.

**I-a. Static SVG — committed, generated, CI-checked.** _(works on github.com today; zero new
rendering tech)_
A `ladder-md` build step scans `doc/**/*.md` for an L4 fence carrying a directive (` ```l4
ladder=window-rule `, or an adjacent `<!-- ladder: … -->`), pipes the L4 through **the bridge we
already have** (`standalone/serve.mjs`: L4 → `jl4-lsp` → `RenderAsLadderInfo.funDecl`), runs
`ladder-core` + `sceneToSvg` **twice** (screen + ink), writes `doc/…/figures/*.svg`, and
injects/refreshes a `<picture>` block after the fence. CI regenerates and fails if the tree is
dirty, so the picture **cannot drift** from the L4.

> The L4 stays the source _in the Markdown_; the SVG is derived and committed. That is the
> document's own thesis — "a diagram is a good _view_ of legal logic and a bad _substrate_ for
> it" — enacted in the build system. And the artifact then works everywhere: github.com, npm,
> VS Code preview, a future site, print.

**I-b. The ASCII ladder — the sleeper. SHIPPED** (`src/ascii.ts`). A fenced code block renders
**verbatim wherever Markdown exists**: github.com, PR comments, commit messages, terminals,
email, `git diff`. A ladder is now **diffable in git** and pasteable anywhere, and
`logic-not-flowcharts.md` finally shows the ladder it argues for — beside the L4 source, one
screen, no image load.

Two translations did the work. **Edges, not glyphs**: cells accumulate a direction mask plus a
weight and resolve to a character at the end, so junctions (`├ ┤ ┬ ┴ ┼`) fall out for free — a
wire meeting a box border yields `┤` unasked. **The Bézier fan becomes a bus**: sampling §18's
curves into characters would be mush, but every curve of one OR shares the group's port, so the
fan is recoverable and we draw the vertical ladder-logic bus the curve always depicted.

The visual language survives: the lightning model (§20) maps to heavy `━┃╋` (closed) / light
`─│┼` (streamer) / dashed `┈┊` (open); §22 presumptions keep their fine dash _and_ their
streamer cap; §15 eliminable rungs keep their coarse dash; §21 NOT keeps its frame and bubble.
T/F/U is **colour** in the SVG and colour cannot survive a code fence, so it moves into the box
as a `✓ / ✗ / ?` marker.

**The enabling change — injectable `Geometry`.** TextMetrics was always injectable but the
kernel's pixel constants were _not_, so §3.2's substrate-independence only half held. A
character grid needs the paddings and gaps on whole cells too, or `round()` sends the same box
to 3 rows in one rung and 4 in the next. So `layout()` now takes a `Geometry` (default
`PIXEL_GEOMETRY` — bit-identical to the old constants; SVG output unchanged). `ASCII_GEOMETRY`
solves for exactness: `box h = lineHeight + 2·PAD_Y = 2 cells` and `stride = box h +
GAP_PARALLEL = 4 cells`, so every subtree height is an _even_ number of cells and BBE's
centering — `(boundingExtent − childExtent)/2` — also lands on a whole cell. Exact all the way
down; asserted in `test/ascii.test.ts`, because silent drift is the failure mode.

(Constraint: wide trees still need §7 Tiny scale or §16 folding to fit a column. The GPDO
window rule comes in at 93 columns.)

**I-c. A real fenced-block plugin.** A `markdown-it`/`remark` plugin that calls `ladder-core`
in-process and inlines the SVG — _interactive_ (fold, T/F/U cycling) on surfaces where **we**
control the renderer: a future docs site, and the **VS Code Markdown preview**, which accepts
markdown-it plugins contributed by an extension (`markdown.markdownItPlugins`) — and we already
ship a VS Code extension. Rides on the §13.1 `ladder-svg` split.

**Recommendation: I-a + I-b now; I-c with the IDE integration; Mermaid never.**

> **Status.** I-b is **shipped**. I-a (the generate-and-commit SVG build step) is the next
> increment, and it now has everything it needs — the playground bridge already does L4 →
> `jl4-lsp` → `funDecl`, and `sceneToSvg` already takes a theme. I-c waits on the §13.1
> `ladder-svg` split. "Mermaid never" **has now been stress-tested** (§24.2) and survives — but
> the first draft's reasons for it were wrong, and the rewrite records that.
>
> **Outstanding check:** the Mermaid findings come from replaying GitHub's pipeline byte-for-byte
> (its exact bundle, `initialize()` config, DOMPurify allowlist and viewscreen CSS), **not** from
> loading github.com. Before citing any of this in print, paste `tmp/mermaid-planb/honest.mmd`
> into an issue comment and hit Preview.

---

## 25. IMPLIES — the seam between scope and requirement _(proposed; not built)_

**The question (Meng, 2026-07-14):** _"do we draw implication as a new thing, or as a rung that
fits into our current formalisms?"_

> **SCOPE — decided 2026-07-14.** Build **"must be"** only: _material_ implication in
> **constitutive** rules, where the consequent is another **predicate**. **"Must do"** —
> _regulative_ rules, where the consequent is an obligation with a deadline and reparations — is
> a **different visualization problem** (Petri nets, Harel statecharts, DFAs), and §25.5 explains
> why the ladder must stop at its door rather than pretend. The gating conditions of a regulative
> rule look exactly like the work below and are reusable as-is; **the consequent is not.**

### 25.1 The status quo is not neutral, and our own document condemns it

Today the viz IR has no implication node (`IRExpr = And | Or | Not | UBoolVar | App | TrueE |
FalseE | InertE`), so an L4 `P IMPLIES Q` either falls through to an opaque leaf or is rewritten
by `Transform.simplify` into **`NOT P OR Q`** — two parallel rungs, the first negated. That is
what the ladder in `logic-not-flowcharts.md` currently shows.

It is truth-functionally impeccable. It is also **shape-destroying**, and that is exactly the
charge the document levels at flowcharts: _"it says more than the law, and less than the law."_
A statute has a **scope** (does this bite me?) and a **requirement** (then what must I do?), and
those are the first two questions any lawyer asks in that order. `¬P ∨ Q` answers neither. It
offers two escape routes; it inverts the antecedent; and it destroys the asymmetry that _is_ the
legal object. **We are committing a milder version of the flowchart's crime inside the tool we
are selling as the cure.** Truth-preserving, meaning-obscuring. Reject.

So: **`Implies` must be a real IR node.** But — and this is the good news — it need not be a new
_layout_ primitive.

### 25.2 It is not a new thing. It is the thing ladder logic was always drawing.

A real IEC 61131-3 rung is **`[contacts] ────( coil )`**: _if_ the contact network conducts,
_then_ energize the coil. **A rung IS an implication** — antecedent on the left, consequent on
the right. It is a Horn clause with a power rail.

Our diagrams have quietly omitted the right-hand half all along: we draw contact networks strung
between two power terminals, which is only ever the **antecedent**. So implication is not a new
shape; it is the shape we have been declining to finish.

_(Careful with the coil, though. In a **constitutive** rule — our scope — the right-hand side is
another **predicate**, so it is a second contact panel, not an output. The coil-as-**action**
reading belongs to **regulative** rules, and §25.5 explains why we are not drawing those.)_

Note also that Meng drew this correctly in 2021, in the deck that started this: two panels,
_"Every window which… **⇒** must be…"_, each panel a nested Venn/ladder. That design was right.

### 25.3 The drawing: a two-panel seam. **Vacuity is a STATE, not a PATH.**

> **Correction (Meng, 2026-07-14).** The first draft drew the vacuous case as a **bypass rung**
> around the requirement. That is wrong, and not merely ugly. _"The bypass is true but vacuously
> obvious … the compliance state is 'your house has no windows' and any human would write **N/A**
> on the form. If we include the bypass in the circuit we would be accused of pedantry."_
>
> He is right, and the error is a **category** one. A bypass rung makes "the rule never reached
> you" a **co-equal way of complying**, drawn in parallel with actually complying. It is nothing
> of the kind. It is a way of **not being asked**. No form offers _"my house has no windows"_ as a
> compliance option; it greys the section and stamps it **N/A**.
>
> **So the bypass must never be ink.** It exists in the semantics, not in the drawing.

```
     ●──[ SCOPE ]════MUST════▶──[ REQUIREMENT ]──●
        on an upper floor            obscure-glazed
        AND (in a wall               AND (non-opening
        OR in a roof slope)          OR openable parts ≥ 1.7m)
```

**One path.** Two panels — **scope** and **requirement** — joined by a distinguished `⇒` / `MUST`
seam. In BBE this is nearly free: a **series whose connector is a seam glyph rather than a plain
wire**, so align-then-stack is unchanged.

**Flow (§20) is where it earns its keep.** The implication has _three_ outcomes, and the picture
distinguishes them **without drawing a third path**:

| Scope    | Requirement | Reading                      | Render                                                                                                       |
| -------- | ----------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **open** | —           | **N/A — the rule never bit** | the seam stamps **`N/A`**; the requirement panel **greys out** and is not evaluated. **No bypass is drawn.** |
| conducts | conducts    | **in scope, and compliant**  | current runs through both panels; seam closed                                                                |
| conducts | open        | **in scope, and IN BREACH**  | current reaches the seam and **stops**; the break is drawn AT the seam                                       |

> **Superseded in part by §25.4.** The two-sink form below does this better still: it needs no
> `N/A` stamp and no greying rule, because **N/A is simply "neither lamp lit"**. Keep §25.3's
> principle — _vacuity is a state, not a path_ — and take §25.4's mechanism.

**Same truth value, different ink.** `#EVAL` returns `TRUE` for a ground-floor window, and that is
correct — the conditional is vacuously true and L4 should not pretend otherwise. But a compliance
report that prints _"✓ complies with A.3"_ for a house with no windows is **telling the truth
misleadingly.** The renderer therefore distinguishes _true because satisfied_ from _true because
unreached_, exactly as §22 distinguishes _given_ from _presumed_ — a **provenance of the verdict**,
orthogonal to its value. The logic is untouched; only the ink changes.

That third row is the whole point: **breach is visible as a break at a named place.** And the
first row is the case Meng's IMPLIES commit says flowcharts lose — _"it is precisely at such
exits that real-world rules-as-code projects lose track of whether 'not covered' was supposed to
mean pass, fail, or undefined."_ Here it is not an unlabelled exit; it is a labelled bypass that
says **why** you are compliant: the rule never reached you.

### 25.4 Two sinks: the green lamp and the red lamp — **and N/A falls out for free**

> **Meng, 2026-07-14:** _"Maybe we can allow a form that treats the coil as a switch in its own
> right: we have one antecedent source on the left of the ladder but two sinks: if the compliance
> consequent is connected then we happy path to the green light. Otherwise we switch to the red
> light."_

This is the right shape, and it **supersedes** the `ViewSpec` polarity toggle the first draft
proposed. It is also, pleasingly, not an invention: it is a **changeover contact** — SPDT, one
pole and two throws — which is native relay-ladder vocabulary. The requirement does not merely
_conduct or not_; it **routes**.

```
                                             ╭──▶ ( ✓ GREEN — complies )
     ●──[ SCOPE ]══MUST══▶──[ REQUIREMENT ]──┤
                                             ╰──▶ ( ✗ RED — in breach )
```

One source on the left. **Two sinks** on the right. The requirement's verdict throws the blade.

**And now count the lamps.** Every outcome the rule has is legible from which lamp is lit, with
no extra ink and — crucially — **no bypass**:

| Scope     | Requirement   | Green   | Red     | Reading                                                          |
| --------- | ------------- | ------- | ------- | ---------------------------------------------------------------- |
| ✗ open    | _not reached_ | dark    | dark    | **N/A** — the rule never bit. The break is visible IN THE SCOPE. |
| ? unknown | ?             | dark    | dark    | **undetermined** — nothing is asserted yet                       |
| ✓ closed  | ✓ closed      | **LIT** | dark    | **complies**                                                     |
| ✓ closed  | ✗ open        | dark    | **LIT** | **IN BREACH**                                                    |

This is the whole reason the two-sink form is better than anything above it. §25.3 had to
_special-case_ vacuity — grey the panel, stamp `N/A`. Here **N/A is simply "no current left the
scope"**, and the reader sees exactly _where_ it stopped. Nothing has to be drawn to say it, and
nothing has to be suppressed either. The pedantry problem dissolves rather than being managed.

_(N/A and "undetermined" are both dark lamps, and they are distinguished the same way a lawyer
distinguishes them: by looking at **where the break is**. A scope that is definitively `✗` shows a
clean open contact — tested, and it did not bite. A scope that is `?` is grey — not yet asked.)_

**The polarity toggle is no longer needed.** The first draft made the citizen and the Bad Man
read _different diagrams_. They now read the **same** diagram and simply care about different
lamps: the citizen asks _"is green lit?"_, the litigator asks _"can red be lit?"_ — which is a
**reachability query**, and one the verifier can actually discharge. The red lamp is the
white-hat Bad Man's target, drawn.

**And it completes §25.2.** We noted there that our diagrams have only ever drawn the antecedent
half of a rung — contacts strung between two power terminals, with the coil quietly omitted.
Here the coils arrive, and the right-hand side of the ladder finally means something. What was a
second power terminal becomes **two lamps that report the verdict**.

**Cost check — does the requirement appear twice?** No, and this is the point of the changeover.
The naïve encoding is `[Q]──(green)` in parallel with `[¬Q]──(red)`, which duplicates `Q` — the
very sin we charge trees with. The changeover has **one** requirement panel with a **two-way
exit**: current leaves upward if it conducts, downward if it does not. One `Q`, two throws.
(§21a's normally-closed contact is the same idea at atom scale; this is it at panel scale.)

**Where LEST attaches.** For regulative rules (§25.5, not in this build) the red lamp is not a
lamp at all — it is the **doorway**. Breach is where `LEST` hangs: the reparation, the statechart,
the obligation's afterlife. So the two-sink form gives the §25.5 port a natural anchor, and the
constitutive and regulative pictures agree on their skeleton even though only one of them is
ours to draw.

### 25.5 "Must be" vs "must do" — the seam is where the ladder ENDS

Two quite different things hide under the same English word, and the scope decision above turns
on telling them apart:

|             | **"must _be_"** — constitutive                           | **"must _do_"** — regulative                                   |
| ----------- | -------------------------------------------------------- | -------------------------------------------------------------- |
| the MUST is | **characterizing**: it says what a compliant window _is_ | **directive**: it tells a party to _act_, by a deadline        |
| consequent  | another **predicate**                                    | an **obligation**: deadline, fulfilment, breach, reparation    |
| formalism   | Boolean function                                         | a **labelled transition system**                               |
| the picture | a **ladder** (this document)                             | **Harel statechart / Petri net / DFA** (§ the doc's own table) |
| example     | A.3: obscure-glazed and non-opening                      | `PARTY insurer MUST pay WITHIN 30 days HENCE … LEST …`         |

A.3's "must be obscure-glazed" is the **first** kind. There is no process in it, no deadline, no
reparation — a window either satisfies the predicate or it does not. Formalising it as
`covers IMPLIES requirement-met` is therefore not a dodge; it is the honest reading.

**And this is exactly why the coil metaphor must not be pushed.** For a regulative rule the
consequent is not an output you energize. Meng: _"the coil is more than a coil: it's a
whole-ass graph."_ Quite — it is the obligation's entire lifecycle. Drawing that as a coil, or as
anything else the ladder owns, would be **the flowchart's own category error**, committed by us:
flattening a transition system into a picture that cannot hold one. `logic-not-flowcharts.md`
spends two hundred lines saying that decision logic and process are different semantic
categories. The ladder must therefore **stop at the seam.**

So for regulative rules the seam is **not a coil — it is a PORT**: the ladder renders the
**guard** (the conditions under which the obligation arises), which looks exactly like everything
built so far and is **reusable unchanged**, and then hands off. The consequent renders as a
**folded handle** (§16) that opens into a _different view_.

That gives the two formalism boundaries a pleasing symmetry, and they are the same idea twice:

| Boundary             | Opens         | From → To                | Handle                                       |
| -------------------- | ------------- | ------------------------ | -------------------------------------------- |
| **§23 the membrane** | **downward**  | circuit → **typed data** | a predicate leaf opens into its value chip   |
| **§25 the seam**     | **rightward** | circuit → **process**    | a deontic consequent opens into a statechart |

In both, the honest move is the same: **draw the boundary, render a handle, and let the other
formalism take over.** Never pretend the ladder can hold what it cannot.

_(One nicety we keep for the constitutive case: the seam glyph should read `MUST` when the source
said MUST and `⇒` when it did not — §17's argument, applied to the connective. The drafter's
register survives into the picture.)_

### 25.6 The seam in Mermaid: **the bottleneck was right.**

Meng: _"if we just had a convention where we have a `=>` node that looks like a bottleneck
between condition and coil, could we shoehorn into Mermaid?"_ Four encodings were rendered
(`specs/research/mermaid-planb/implies-seam-candidates.mmd`). **Yes — and it is the bottleneck.**

| Encoding                                    | Verdict                                                                                                                                                                                        |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `choice(NOT P, Q)` — status quo             | **Correct, shapeless.** Antecedent inverted; scope/requirement destroyed. What we ship today; §25.1 rejects it.                                                                                |
| `choice(NOT P, sequence(P, MUST, Q))`       | **Correct, and pedantic.** Draws the vacuous escape as a co-equal rung — the very error §25.3 now forbids — and duplicates `P` to do it. **Rejected.**                                         |
| `sequence(P, MUST, optional(Q))`            | **THE TRAP.** Draws exactly the picture we want and means the opposite: `optional` is an **ungated** bypass, `Q ∨ ⊤`, so it says **the requirement is moot**. Beautiful, and backwards. Never. |
| **`sequence(P, MUST, Q)`** — the bottleneck | **✅ USE THIS.** One path, no bypass ink, and it reads as the statute's own sentence: _"A.3 covers this window — **MUST** — A.3 requirement met."_                                             |

**Is that not alby's OR→AND bug in a new costume?** It is the fair objection, and the answer is
no — for a reason worth being precise about. Under a **strict railroad grammar** a `sequence` is
concatenation, so a purist (or a machine) reads `P ∧ Q` and would call a ground-floor window
non-compliant. But alby's bug was **silent**: nothing in his notation signalled the OR he had
dropped. Here the seam is labelled **`MUST`**, and no English reader parses _"covered — MUST —
compliant"_ as a conjunction. **The word carries the semantics.** A declared connective is not an
accident, and a notation is allowed to have conventions — that is what a notation _is_.

And the vacuous case reads correctly **because the scope is the first thing on the path**: a
ground-floor reader is stopped at the very first box, `A.3 covers this window`, and knows exactly
why. That is **N/A**, legibly — which is the form-filling behaviour §25.3 is modelling. The
residual risk is a machine consuming the figure as a grammar, and the figure is a **view**, not
the source. The L4 is the source. That is the whole thesis.

**What Mermaid still cannot do is the FLOW.** It has no way to grey out the requirement panel and
stamp `N/A`, and no way to break the circuit **at the seam** on breach. Structure it can carry;
state it cannot. Which is exactly the work §25b exists to do in the native renderer.

### 25.7 Work — **constitutive ("must be") ONLY**

- [x] **25a.** Add `Implies` to `VizExpr.IRExpr` (Haskell) + `viz-expr.ts`, and a case in
      `Viz.Ladder.translateExpr` — it used to fall through to `leafFromExpr`. **Stop
      `Transform.simplify` from rewriting it to `NOT P OR Q`** when the ladder is the consumer.
      **DONE.** `translateExpr` now peels the top-level implication off _before_ `simplify` runs and
      simplifies each side on its own, so the seam survives while the panels still get NNF/CNF —
      which is what we actually want, since simplification is a readability win _inside_ a panel and
      a shape-destroyer _across_ the seam. Pinned end-to-end in `jl4/tests/VizImplies.hs`.
- [x] **25b/c/d.** `ladder-core`: the `Implies` IR node, `measureImplies`, three-valued flow, the
      **changeover** (one pole, two throws) into a **green** coil (complies) and a **red** one (in
      breach). **No bypass drawn**; N/A is "neither lamp lit". Emitters: ASCII `(✓)`/`(✗)`/`┿`, SVG
      coils, Mermaid `sequence(P, IMPLIES, Q)` — never `optional()`. **No `ViewSpec.polarity`
      toggle**: the citizen and the Bad Man read the same diagram and watch different lamps.
- [x] **25e.** The seam's glyph, from the source's register. **DONE, but the ambition was defeated
      and the reason is worth keeping.** L4 spells the constitutive conditional two ways (`IMPLIES`
      and `=>`), and we wanted the picture to keep whichever the drafter used. It cannot: the
      typechecker desugars every binop into a function application (`desugarBinOpToFunction` at the
      `Implies` case), and its `annoNoFunName` rebuilds the annotation as two bare holes — destroying
      the concrete-syntax node that held the operator token. The node is _resugared_ back into an
      `Implies` afterwards, so the visualiser does get a real implication; but its annotation carries
      no tokens at all, and the spelling is gone. Recovering it means preserving concrete syntax
      across binop desugaring — a change to every operator in the language, for a cosmetic difference
      between two spellings of ONE operator. Not worth it: rendering `=>` as `IMPLIES` is of a kind
      with rendering `>=` as `≥`, and says nothing the source did not. The wire field stays free-form
      so a future NLG annotation (or a hand-authored scene) can still carry the statute's own words.

- [x] **25f.** The seam in the **wizard**: a `Verdict` on the query plan, and a planner that stops
      short-circuiting the interview when the verdict is not yet settled. See §25f below — the
      short-circuit turned out to BE the bug, not just its symptom.

**Two findings from the build, both worth keeping:**

- **The ink must not outrun the current.** The first cut fed the requirement→changeover wire from
  `scopeOut`, which drew a heavy live wire coming _out of a requirement that did not conduct_ — a
  picture asserting current flowed through a failed contact. It is now fed by the requirement's own
  conduction, so on a breach the current visibly goes in and does not come out, and the red lamp is
  fed from the changeover itself. That is honest: the pole is the rule's supply and the requirement
  merely **actuates** the switch. This compression (one device instead of a `[Q]`/`[/Q]` pair of
  rungs) is exactly what buys us "every atom appears once".
- **The vacuity error recurs one level up, in the wizard. FIXED — see §25f.** And the diagnosis
  above was too kind: it is not only a presentation bug.

**Explicitly NOT in this build** (§25.5): regulative / "must do" rules. The ladder will render
their **guard** — free, since it is the same machinery — and then **stop**, handing the obligation
to a statechart view via a folded handle. Drawing a deontic lifecycle as a coil, or as anything
else the ladder owns, would be the very category error this project exists to name.

### 25f. The seam in the WIZARD — **the short-circuit was the bug**

The finding recorded at §25b–e was that the query planner must not _report_ a vacuous TRUE as
"complies". True, and an under-diagnosis. Fixing it properly turned up something sharper:

> **The classical short-circuit is valid only if you are computing a truth VALUE.** If you are
> computing a **verdict**, a met requirement does **not** settle it — you must still establish the
> scope, because _"the rule never reached you"_ and _"you comply"_ are different answers, and only
> the scope tells them apart.

So the planner did not merely mislabel the vacuous case. Given `requirement = TRUE` and the scope
still unknown, `¬P ∨ Q` restricts to TRUE, the support goes **empty**, and the interview **stops** —
with the one question that would have distinguished N/A from compliance still unasked. It could not
have reported the right answer, because it had thrown away the means of reaching it. A presentation
fix alone would have papered over a planner that stops too early.

**What was built.**

- **`BoolExpr` gains `BImplies`** (`BooleanDecisionQuery.hs`, mirrored in `decision-query.ts`). It
  still compiles into the diagram classically — for settling whether the rule _holds_, `¬P ∨ Q` is
  exactly the proposition — but the two sides are **also kept as roots of their own, in the same
  BDD**. Hash-consing makes that nearly free, and it is the only way to tell the two TRUEs apart.
  `vizExprToBoolExpr` therefore hands the seam over **intact** instead of flattening it on the way in.
- **`Verdict`** — `Undetermined | Holds | Fails | Complies | InBreach | NotApplicable` — on
  `QueryPlanResponse`, on `QueryOutcome`, and so on every impact preview too (a preview that says
  "answer NO and you're compliant" is the same lie, just earlier). `determined` **stays**, unchanged
  and still correct: it is the function's truth value, which the API owes its callers. What changes
  is that the honest field is now the obvious one to switch on, and the note in the response says so.
- **Support is computed against the VERDICT**, not the value: the support of the two _sides_, with
  the requirement's dropped once the scope is settled FALSE (a rule established not to reach you is
  not worth another question). It costs questions in exactly one case — requirement met, scope open —
  and that is the trade, made deliberately: **a shorter interview that ends in the wrong word is not
  a bargain.**
- **Information gain is measured about the verdict**: `H(scope) + P(scope)·H(requirement)`. This is
  not decoration. With the old measure, the moment the function settled, every atom scored **zero**
  and the ranking went blind precisely when the fix needs it to keep working. It also earns
  "ask the scope first" from the arithmetic rather than from a hand-tuned rule — a requirement you
  may never be measured against carries less information about the verdict than the scope that
  decides whether you are measured at all.

**The verdict table is `lampsFor`'s table, deliberately.** Same rows, and the two engines' tests
assert it in the same words. A wizard and a diagram that disagreed about a case would be lying to the
same user, in the same window.

| scope | requirement | `determined` |    `verdict`    |
| :---: | :---------: | :----------: | :-------------: |
|   ✗   |    _any_    |   **TRUE**   | `NotApplicable` |
|   ✓   |      ✓      |     TRUE     |   `Complies`    |
|   ✓   |      ✗      |    FALSE     |   `InBreach`    |
|   ✓   |      ?      |      —       | `Undetermined`  |
|   ?   |      ✓      |   **TRUE**   | `Undetermined`  |
|   ?   |   _else_    |      —       | `Undetermined`  |

The two bold rows are the whole finding. Both are `determined = TRUE`; neither may be shown to a user
as compliance; and the second is the one that used to end the interview.

**Still open — the old visualizer.** `l4-ladder-visualizer` runs `expandImplies` at its single entry
point (§25a), so its LIR has no seam and its partial-eval never sees one. It is therefore _truthful_
— it prints the boolean and claims nothing about compliance — but it cannot draw the two lamps, and
in the IDE that is still the picture a user gets. The fix is not to retrofit a verdict into it; it is
`ladder-core`, which is what this whole project is for.

---

## Appendix — source materials

- `tmp/box model.pdf` — the BBE box model (margins, ports, connectors, align-then-stack, the `bblm/bbrm=0` nesting invariant, LR/TB, Full/Small/Tiny scales). Primary spec for §5–§7.
- `tmp/ladder logic and or tree visualization.pdf` (2023-05-21) — ladder-logic metaphor, `Either (Maybe Bool) (Maybe Bool)` default model, Leaf/Not/All/Any combinators, T/F/U leaf rendering, group sub-ordering. Primary spec for §6.
- `~/src/legalese/sandbox/mengwong/layman` — iteration 2; proven two-pass centering recursion.
- `ts-shared/l4-ladder-visualizer` — iteration 3; the code being refreshed.
- `jl4-core/src/L4/Viz/{Ladder,VizExpr}.hs` — the topology IR boundary we keep.
