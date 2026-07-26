# The embeddable ladder — Track E

_Scoped 2026-07-27; revised 2026-07-27 after a three-lens adversarial review (disposition
in §11). Track E of [SPEC.md](./SPEC.md). Companion to
[`../ladder-diagrams-2026/E1-IDE-INTEGRATION.md`](../ladder-diagrams-2026/E1-IDE-INTEGRATION.md)
(the IDE plan; its **steps** are single-sourced there and not restated here — but see EK1,
which changes the content of its Step 4 and is cross-marked in that file) and
[GUARDED-ROWS.md](./GUARDED-ROWS.md) (the upstream fix that makes the pictures worth
embedding)._

Track E gates **M2** ("a ladder embeds in an arbitrary web page"), which gates **M3** (the
mirror page). M3 is the exhibit the programme exists to produce, so everything below is on
the critical path to the argument, not to a convenience.

> **Two numbering namespaces meet in this document, and they collide.**
> `S1`–`S11` are **seam** ids from E1-IDE-INTEGRATION.md §1 (S5 = "no DOM sink", S6 =
> pan/zoom, S8 = baked palettes). `S0`–`S3` are **surface** ids from SPEC.md §4 Track S
> (surface S1 = the `/functions/:name/ladder` route). They are different things and the
> overlap at "S1" is real. Below, every use is written **`seam S6`** or **`surface S1`**.
> Fixing the collision upstream is a rename neither document is worth churning for today.

---

## 0. The correction this spec exists to make

SPEC.md §4 says E0 is:

> Factor the interaction controller (click-cycle, fold, FLIP, `viewBox` pan/zoom) as **vanilla
> TS** in `ladder-svg`, so the Svelte displayer is a thin wrapper

**There is no Svelte interaction controller to factor.** Grounding found:

| Behaviour E0 names | Vanilla TS today                                                                     | Svelte incumbent                                                             | So E0 is                             |
| ------------------ | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------- | ------------------------------------ |
| click-cycle        | `ladder-svg/standalone/app.ts:178`, `standalone/playground.ts:255` — demo-local      | **yes** — `displayers/flow/sf-custom-nodes/ubool-var.svelte:93`, LIR-coupled | the **DOM half** only (see §3.2)     |
| fold               | `standalone/app.ts:185`, `standalone/playground.ts:261`                              | **none** — BBE folding has no production incumbent                           | promote + de-duplicate               |
| FLIP               | `standalone/app.ts:92,116`, near-verbatim copy at `standalone/playground.ts:138,167` | **none**                                                                     | promote + de-duplicate (~60 dup LOC) |
| `viewBox` pan/zoom | **zero lines anywhere in the repo**                                                  | SvelteFlow, which Step 8 deletes                                             | **write from scratch**               |

The logic half of the first two already shipped at ladder Step 3:
`ts-shared/l4-ladder-visualizer/src/lib/model/ladder-model.ts:96` (`cycleValue`) and `:112`
(`toggleFold`), in a class that is explicitly framework-free — no `LirContext`, no runes
(`ladder-model.ts:11-15`), with 10 vitest tests and no DOM.

And the vanilla code that does exist **is not in any package**.
`ts-shared/ladder-svg/tsconfig.build.json` pins `rootDir: "./src"` / `include: ["src"]`, and
`package.json` ships `files: ["dist"]` with `exports: {".": "./dist/index.js"}`. So
`standalone/app.ts` typechecks and nothing can import it. E1-IDE-INTEGRATION.md:104's
instruction to "port the FLIP from `ladder-svg/standalone/app.ts:96`", followed literally,
produces a **third** copy.

> **EK1 (locked). E0 is an acceptance criterion on ladder Step 4, not a sibling task.**
> Step 4 is the only thing that would ever write this code. If Step 4 lands first it writes
> the delegation, the FLIP and the pan/zoom inside a `.svelte` file with `$state`/`$effect`
> in the loop, and E0 degrades from "write it in the right place" to "unpick runes from a
> controller" — the extraction E1-IDE-INTEGRATION.md §2 says has no green big-bang commit.
> Written as a separate row, E0 invites exactly that. Its real content is: **Step 4 SHALL be
> a `ladder-svg` controller plus a thin `.svelte` shell.**
>
> **This changes E1-IDE-INTEGRATION.md's Step 4, so that file now carries a marker
> pointing here.** A single source that still describes the superseded shape is worse than
> two documents that disagree loudly.

---

## 1. The substrate, and the real adoption cost

SPEC.md's strategic claim was:

> Their substrate accepts pasted blocks — that is the entire distribution mechanism of a
> DokuWiki. A drop-in that renders a live ladder … at zero adoption cost.

**That premise is false, and this section is the correction.** SPEC.md has been amended to
match.

**Verified** (from the 2026-07-25 survey, recorded at SPEC.md §1.3 and
`doc/concepts/language-design/logic-not-flowcharts.md:431-433`): the page is DokuWiki; the
diagram arrives as a `<bpmnio type="bpmn">` **plugin** block with BPMN 2.0 XML inline,
rendered client-side; `last_wills` still carries `exporter="Camunda Modeler"`; registration is
open; there are no export controls.

What that evidence demonstrates is that the wiki accepts **a registered plugin's own syntax**,
which the plugin's PHP renderer turns into markup. It is not evidence that the wiki accepts
pasted HTML, and it is not evidence that it accepts a `<script>` tag. DokuWiki's documented
default is the opposite: HTML and PHP embedding are **disabled in the configuration, and when
disabled the code is displayed rather than executed** (dokuwiki.org, `config:htmlok` /
`faq:html`) — precisely the setting an admin of an openly-registerable, spam-indexed wiki
would leave off. _(Unverified against their instance; no page source is captured in this
repo, and we do not scrape. E1d resolves it.)_

There is a second, independent obstacle with a burn scar already in the tree.
`ts-apps/housing-wizard/svelte.config.js:20-33` records it: a `<meta>` CSP blocks a
cross-origin fetch **with only a console error**, `'self'` does not cover it, and the exact
scheme+host+port must be listed in `connect-src`. Neither `script-src` nor `connect-src` is
something a _paster_ controls; both are wiki-admin changes.

### 1.1 The channel ladder — what each channel really costs

The two obstacles are independent, and conflating them is the mistake this section exists to
undo. **Sanitisation** decides whether our markup survives at all; **CSP and network** decide
what the surviving markup is allowed to do. A channel has to clear both.

| Channel                                                                 | Clears sanitisation?                                                  | Clears CSP / network?                                   | Adoption cost                                                                    | Interactive? |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------ |
| **A. ASCII/Unicode ladder in a `<code>` block**                         | yes — it is ordinary wiki text                                        | n/a — no script, no network                             | **zero.** Any editor, no admin, no upload.                                       | no           |
| **B. A rendered image via the media manager (`{{ladder.png}}`)**        | yes                                                                   | n/a                                                     | one editor upload. (SVG upload depends on `mime.conf`; PNG always works.)        | no           |
| **C. A DokuWiki plugin we author (`<l4ladder>`), mirroring `bpmnio`**   | **yes, by construction** — the plugin's PHP renderer emits the markup | **yes** — script and data are same-origin (§1.2)        | **one admin installs one plugin** — the cost they already paid once, for bpmnio. | **yes**      |
| **D. An `<iframe>` to a page we host**                                  | only if an iframe/HTML plugin is already enabled                      | host CSP `frame-src` must allow our origin              | admin, unless already installed; plus we operate the framed page                 | yes          |
| **E. Raw `<script src>` + `<l4-ladder>` pasted into the wiki**          | **no**, on a stock instance (`htmlok` off)                            | would also need `script-src` (+ `connect-src` for live) | admin flips `htmlok` — an XSS footgun they should not flip                       | yes          |
| **F. Inversion — our page carries their content, with CC BY-SA credit** | n/a                                                                   | n/a                                                     | zero for them; but it is not an embed                                            | yes          |

Three things follow, and they are the whole of §1's contribution:

1. **"Zero adoption cost" is true only of channels A and B, and those are pictures.** The
   interactive artifact costs an admin action. The honest sentence is: _the interactive
   embed costs one plugin install — the same act they already performed for `bpmnio` — and
   the non-interactive artifact costs nothing at all._ That is still a good story. It is not
   the story SPEC.md told.
2. **Inline data is first-class, but not for the reason first given.** Channel E dies at
   sanitisation whether the data is inline or fetched, so inline data buys nothing there.
   What it buys is everything after sanitisation: **no `connect-src`, no reachable service,
   no second origin, and a cacheable page.** In channel C it is also the exact shape of the
   incumbent — `bpmnio` carries its BPMN XML inline in the block — so it is the shape the
   plugin's syntax component should take. Ranked against CSP and network hostility, not
   against the sanitiser.
3. **Channel A already exists in this repo and nothing in Track E is needed to ship it.**
   `ladder-core/src/ascii.ts:320` (`sceneToAscii`) plus `ascii.ts:56` (`monoMetrics`, a pure
   `TextMetrics` needing no canvas and no DOM) produce a pasteable ladder in Node today. All
   it lacks is a producer on the CLI — the `l4 ladder` subcommand that **R5** already asks
   about. That promotes R5 from ergonomics to _the only zero-admin channel we have_.

So the honest statement of the artifact constraint is not "zero adoption cost" but:

> **The artifact must survive the most hostile plausible substrate**: one file, no npm, no
> build step at the destination, no external network required, and no assumption that we
> control `script-src`, `connect-src`, or the sanitiser. Where the sanitiser wins, the same
> bytes must be re-servable by a ~100-line plugin, and the same picture must still be
> expressible as text.

### 1.2 What channel C does to the artifact's design

Channel C is not a wrapper decision to be taken later; it constrains the bundle. DokuWiki
collects **`script.js` from every enabled plugin and template, concatenates them into one
block, whitespace-compresses it, and serves it from `lib/exe/js.php` with `defer`**
(dokuwiki.org, `devel:javascript`). If our IIFE _is_ the plugin's `script.js`, then:

- **Same-origin, always.** The script is served by the wiki itself, so `script-src 'self'`
  suffices and no admin CSP change is needed for the script. Combined with inline data, a
  channel-C embed needs **no CSP change at all**. This is the single strongest argument for
  channel C over channel E, and it is not obvious from the outside.
- **`document.currentScript` is unusable.** The shipped precedent
  (`jl4-service/src/WebMCPPage.hs:59`) reads its base URL from
  `document.currentScript || document.querySelector('script[src*="embed.js"]')`. Under
  concatenation both are wrong: `currentScript` points at `js.php`, and no element matches.
  **Therefore all configuration lives on the element's attributes, never on the script tag**
  (§4.2), and the bundle must have no notion of "my own URL".
- **Concatenation hygiene is a build requirement, not a style preference.** The file is
  pasted between other plugins' JS: it must begin with a leading `;`, be a single IIFE, leak
  no globals beyond the one `--global-name`, terminate every statement (a whitespace
  compressor plus ASI is a live hazard), contain no ESM `import`/`export`, and no top-level
  `await`.
- **`defer` is a gift.** Deferred execution means the element's light-DOM children are
  already parsed when `customElements.define` upgrades it, so `connectedCallback` can read
  the inline `<script type="application/l4-ladder+json">` child synchronously. Channel E
  does **not** guarantee this (a `<script src>` in `<head>` upgrades before children parse),
  so §4.2a specifies the re-check that makes both safe.

None of this changes what E1 builds. It changes the constraints E1 builds under, and it
means the plugin (E1e) is a shim over the same bytes rather than a second implementation.

### 1.3 What is actually load-bearing

**E1a alone satisfies SPEC.md §8's fourth acceptance criterion** — "renders in a plain HTML
page with a script tag, and clicking a term changes the verdict" — with one file and no
service. M2 is "an arbitrary web page"; M3 is the mirror page, which is **ours**. So:

- The **track** and the **milestones** are load-bearing on E0→E1c and nothing else.
- The **DokuWiki channel** is load-bearing on the _distribution claim_ in SPEC.md §4 — the
  "meet them where they are" argument — and on nothing else. If R1 comes back "plugin only",
  the track completes and the claim gets rewritten to "one plugin install", which §1.1
  already does.

A reader who concludes "Track E is blocked on a wiki admin" has misread; so has a reader who
concludes "finishing Track E lands us on Lexipedia". **R1** is scheduled as **E1d** and has
its own acceptance criterion (§8.7), so it can no longer be answered by nobody.

---

## 2. What Track E builds on, and what it must not touch

**The kernel is framework-free, and the grep is the evidence.**

```bash
grep -rnE 'document|window|HTMLElement|navigator|svelte' ts-shared/ladder-core/src/   # → 0 hits
```

(Note the `-E`: without it the pattern is a literal string and the zero proves nothing. It
is genuinely zero either way.) Two smaller claims that an earlier draft leaned on are
**withdrawn as arguments**, though the conclusion stands:

- _Withdrawn:_ "the package's tsconfig does not extend `@repo/typescript-config/base.json`,
  which would pull in `lib: DOM`". Base does set `lib: ["es2022","DOM","DOM.Iterable"]`
  (`ts-shared/typescript-config/base.json`), but ladder-core/ladder-svg set **no `lib` at
  all** with `target: ES2020`, and TypeScript's default for an unspecified `lib` is
  `lib.es2020.full.d.ts`, which **already includes DOM**. So the tsconfig proves nothing
  about DOM-freedom — and, usefully, it also means `controller.ts` (§3) typechecks in
  `ladder-svg` with **no tsconfig change**. Recorded in §3.5 so nobody goes hunting.
- _Note:_ ladder-**svg** is not DOM-free and does not claim to be —
  `ladder-svg/src/metrics.ts:42` reads `globalThis.document`, guarded, and throws a legible
  error off-DOM. That is the intended shape.

Every cross-package import in both ladder packages is `import type`:

```
ladder-core/src/layout.ts:30      import type { Verdict } from "@repo/boolean-analysis"
ladder-core/src/viz-adapter.ts:36 import type { FunDecl as VizFunDecl, IRExpr } from "@repo/viz-expr"
ladder-svg/src/svg.ts:8           import type { Scene, ScenePrim, State, Theme, Flow } from "@repo/ladder-core"
ladder-svg/src/metrics.ts:19      import type { TextMetrics } from "@repo/ladder-core"
```

This matters more than it looks. `@repo/viz-expr` is built on `effect`'s `Schema`
(`ts-shared/viz-expr/viz-expr.ts:1`) and also pulls `ts-pattern`, `vscode-jsonrpc` and three
`vscode-messenger-*` packages — **all runtime values**. Because ladder-core touches viz-expr
type-only, none of it reaches a bundle. The single-file goal is architecturally already paid
for; §4.6 makes it a test rather than a hope.

**The runtime surface Track E consumes**, in full:

| symbol            | signature                                                    | site                             |
| ----------------- | ------------------------------------------------------------ | -------------------------------- |
| `layout`          | `(fn, vs: ViewSpec, tm: TextMetrics, k?: Geometry) => Scene` | `ladder-core/src/layout.ts:1043` |
| `verdictFor`      | `(fn, valuation) => Verdict`                                 | `layout.ts:248`                  |
| `defaultViewSpec` | `(partial?: Partial<ViewSpec>) => ViewSpec`                  | `types.ts:212`                   |
| `fromVizFunDecl`  | `(viz: VizFunDecl) => DecodedViz`                            | `viz-adapter.ts:119`             |
| `expandSentences` | `(root, foldSet?) => string[]`                               | `sentences.ts:97`                |
| `sceneToSvg`      | `(scene: Scene, theme?: Theme) => string`                    | `ladder-svg/src/svg.ts:162`      |
| `canvasMetrics`   | `(opts?: CanvasMetricsOpts) => TextMetrics`                  | `ladder-svg/src/metrics.ts:56`   |
| `sceneToAscii`    | `(scene: Scene, opts?: AsciiOpts) => string`                 | `ladder-core/src/ascii.ts:320`   |
| `monoMetrics`     | `(cellW?: number) => TextMetrics`                            | `ladder-core/src/ascii.ts:56`    |

(The last two are channel A's whole implementation. They are **not** in the element bundle —
§4.6 excludes the carriers — they are in the CLI producer, E2b.)

> **EK2 (locked). Track E never imports `l4-ladder-visualizer`.** That package is the
> SvelteFlow path; E1-IDE-INTEGRATION.md:108 deletes `displayers/flow/**`, `layout-ir/**`,
> `algebraic-graphs/**` and `data/viz-expr-to-lir.ts` at Step 8, and SPEC.md K2 kills
> `node-paths-selection.ts` with them. A widget that imported across that seam would either
> block the deletion or break at it. See §6 for the one thing Track E does want out of that
> package and how it gets it.

> **EK3 (locked, and restated). The string sink is correct here — pre-emptively, not as a
> strike.** Nobody ever recorded **seam S5** as a Track E dependency; E1-IDE-INTEGRATION.md:55
> records it as blocking **Step 6b chrome, in the IDE**. The reason it is worth writing down
> anyway is that a reader porting the IDE plan onto the widget would inherit it by reflex.
> S5's stated reason is that `{@html}` "cannot host Svelte children (bits-ui menus need real
> anchors)". A framework-free custom element has no Svelte children and wants no bits-ui, so
> `innerHTML = sceneToSvg(scene)` plus delegated listeners is the _right_ sink, and seam S5
> is simply out of scope.

**Two seams Track E genuinely does depend on**, neither of which appears in SPEC.md's Track E
row (now amended):

- **Seam S6 — pan/zoom.** Open, and total (§0). The R1 layout spike measured p99 width 2882px,
  max 4372px (E1-IDE-INTEGRATION.md:202-208). In a wiki column that is not optional.
- **Seam S8 — baked palettes.** `ladder-svg/src/svg.ts:20,29` define `SCREEN`/`INK` as
  constants and `svg.ts:52` emits `fill="#ffffff"` inline. A widget pasted into a host page
  whose colours we do not control reads as a foreign white rectangle. Ladder Step 2's theming
  half is still open (E1-IDE-INTEGRATION.md:102). Whether it gates E1 or trails it is **R8**.

And one that is half-open in an interesting direction: **seam S4**'s model half already
shipped — `ladder-model.ts:184` returns `Map<NodeId, ElicitationMark>` — while the render half
is untouched:

```bash
grep -rn 'marks' ts-shared/ladder-core/src ts-shared/ladder-svg/src   # → 1 hit, a comment (viz-adapter.ts:200)
```

`ViewSpec` (`types.ts:183`) has no `marks` field, and `ClickAct` (`types.ts:241`) still has
exactly `t: "value" | "fold"`. SPEC.md K1 says marks gate the IDE default flip because a
picture that omits "you have not answered this yet" misleads. A widget dropped in a
third-party page has _less_ surrounding context than the IDE, so the argument is stronger
there. **R7.**

---

## 3. E0 — the interaction controller

### 3.1 Deliverable

A new module `ts-shared/ladder-svg/src/controller.ts`, exported from
`ts-shared/ladder-svg/src/index.ts`, containing every browser-facing behaviour of an
interactive ladder and **no** framework. Plus three consumers converted to it: the Step 4
Svelte displayer, `standalone/app.ts`, and `standalone/playground.ts`.

### 3.2 The split: what the controller owns, and what it does not

The controller owns **layout + the DOM**. It does not own valuation, evaluation, or the
verdict — those are the model's, and the model already exists.

The seam is `ViewSpec`, not `Scene`, and that is forced by the code: `LadderModel` already
exposes `get viewSpec(): ViewSpec` (`ladder-model.ts:167`) and nothing that produces a
`Scene`. Layout is `layout(fn, vs, tm)` — pure, but parameterised by `TextMetrics`, which is
the one genuinely browser-shaped input (`canvasMetrics` needs a canvas;
`metrics.ts:42-53`). Put layout on the host side and every consumer re-writes the same three
lines and picks its own metrics backend — which is exactly the bug today, where both demos
are on `estimateMetrics` (`standalone/app.ts:87`, `standalone/playground.ts:58`). Put it in
the controller and the metrics option becomes load-bearing, `fit()`-on-size-change becomes
implementable, and there is one render path.

```
                 ┌──────────────────────────────────────┐
  host (Svelte   │  LadderController                    │
  shell, custom  │   • layout(fn, vs, metrics) → Scene  │
  element, demo) │   • innerHTML = sceneToSvg(scene)    │──▶ onAct({t:'value'|'fold', id})
                 │   • ONE delegated click              │
                 │   • FLIP between scenes              │
                 │   • viewBox pan / zoom / fit         │
                 └──────────────────────────────────────┘
                              ▲ render(viewSpec)
                              │ (or renderScene(scene), the escape hatch)
                 ┌──────────────────────────────────────┐
                 │  the brain: anything with a ViewSpec │
                 │  — LadderModel in the IDE, a bare    │
                 │  Map + verdictFor in the element     │
                 │  (EK5), a fixture in the demos       │
                 └──────────────────────────────────────┘
```

Proposed surface, deliberately small:

```ts
export interface LadderControllerOpts {
  /** Metrics for layout. Default `canvasMetrics()`; a headless test injects `measure`. */
  readonly metrics?: TextMetrics;
  readonly theme?: Theme;
  /** Off ⇒ no listeners attached at all: a static picture (see `interactive` in §4.2). */
  readonly interactive?: boolean;
  readonly animate?: boolean; // FLIP; default true
  readonly panZoom?: boolean; // default true
  readonly onAct?: (act: ClickAct) => void;
}

export declare class LadderController {
  /** `fn` is ladder-core's own `FunDecl` (the DRAWING tree, `types.ts`), i.e. `DecodedViz.fn`.
   *  The controller never sees a viz-expr wire type, so it never sees `effect`. */
  constructor(host: HTMLElement, fn: FunDecl, opts?: LadderControllerOpts);
  /** Lay out under `vs` with the injected metrics, then draw. FLIP-animates from the
   *  previous scene when `animate`. Returns the Scene so the host can read `size`/prims. */
  render(vs: ViewSpec): Scene;
  /** Escape hatch for a caller that already has a Scene (a worker, a cache, a golden test).
   *  Bypasses metrics entirely; still FLIPs, still wires clicks. */
  renderScene(scene: Scene): void;
  /** Swap the source tree (a live re-fetch). Invalidates the FLIP baseline. */
  setFunDecl(fn: FunDecl): void;
  fit(): void; // viewBox := scene bounds, centred
  zoom(factor: number, at?: Pt): void;
  pan(dx: number, dy: number): void;
  toSvgString(): string; // the last emitted string, verbatim
  destroy(): void; // remove listeners, cancel rAF, clear host
}
```

`ClickAct` is `ladder-core/src/types.ts:241` unchanged — the controller reads the
`data-value` / `data-fold` attributes `svg.ts:151,158-160` already emits and reports them; it
never interprets them.

Three constraints fall out of the code as it stands:

1. **One delegated listener, not per-node.** `standalone/app.ts:156-169` re-queries and
   re-attaches on every render. That is O(nodes) listener churn per click and it leaks across
   the `innerHTML` swap. E1-IDE-INTEGRATION.md:104 already specifies "**one** delegated click";
   the controller is where that lands, once, for all three consumers.
2. **Metrics are injected, and the default is `canvasMetrics()`.** Load-bearing precisely
   because `render(vs)` calls `layout`. Both demos are on the wrong backend today
   (`standalone/app.ts:87`, `standalone/playground.ts:58` use `estimateMetrics`, the
   `length * size * 0.56` estimator seam S7 names). `canvasMetrics` is lazy and fails loud
   off-DOM (`metrics.ts:35-54`), so a headless test injects `measure` and never touches a
   canvas — and `renderScene` lets a test skip metrics altogether.
3. **FLIP keys off the emitted `data-fnid`.** `flipIndex` (`standalone/app.ts:92-100`) indexes
   `box:<id>` from `p.rect` and `label:<id>` from `p.at`, then plays the invert across two
   `requestAnimationFrame`s. That algorithm is correct and tested by eye in two places; the job
   is to move it, not to redesign it.

### 3.3 Pan/zoom — the only genuinely new code

~60 lines, no dependency (E1-IDE-INTEGRATION.md:104 is right that this is simpler than
`svg-pan-zoom` under the webview CSP, and the same reasoning applies doubly to a host page
whose CSP we do not control). Mechanics:

- state is a `viewBox` rect over the `Scene`'s own coordinate space; `scene.size`
  (`types.ts:333`) is the initial one, which is what `sceneToSvg` already emits
  (`svg.ts:167`);
- `pointerdown`/`pointermove`/`pointerup` with pointer capture for pan; `wheel` with
  `ctrlKey`-or-plain for zoom, anchored at the cursor;
- `fit()` on first render and on any scene whose size changed by more than a threshold;
- the widget must **not** swallow page scroll: plain wheel scrolls the page unless the ladder
  has focus or the gesture is a pinch. A wiki page that traps the scrollwheel is worse than one
  with a wide picture.

### 3.4 The two demos become the first consumers

`standalone/app.ts` and `standalone/playground.ts` are rewritten to import the controller. This
is not tidying: **it is the proof that the factoring is real**, and it deletes ~60 lines of
acknowledged copy-paste (`playground.ts:136`'s own header reads `/* --- FLIP (app.ts) */`).
Everything except FLIP and pan/zoom is then testable under `tsx --test` with an injected
`measure`, matching the package's existing runner.

### 3.5 Landing checklist

- `ts-shared/l4-ladder-visualizer/package.json` **does not declare `@repo/ladder-core`**, yet
  `src/lib/model/ladder-model.ts:22` imports it. It resolves only through npm-workspace
  hoisting. `turbo.json` derives `build`/`check`'s `dependsOn: ["^build"]` from declared deps,
  so ladder-core's `dist/` is not ordered before this package — masked today only because CI
  runs a full `npm run build` first. Step 4 must add **both** `@repo/ladder-core` and
  `@repo/ladder-svg` there.
- **No tsconfig change is needed for DOM types** (§2): ladder-svg sets no `lib`, target
  ES2020, so `lib.es2020.full.d.ts` supplies `HTMLElement`/`SVGSVGElement`/`PointerEvent`
  already. Assert this rather than rediscover it — but if a future commit adds an explicit
  `lib`, `controller.ts` is what breaks first.
- Neither ladder package has a `lint` script or an eslint config, so `turbo lint` silently skips
  them. Adding the controller is a good moment to stop that being true, or to write down that
  it is deliberate.
- The repo has a known `package.json`/`package-lock.json` drift on `unstable`; any new
  dependency blocks the merge queue. The controller adds none, which is one more reason not to
  reach for a pan/zoom library.

---

## 4. E1 — `<l4-ladder>`

There is **no `customElements` usage anywhere in the repo**:

```bash
grep -rn 'customElements' ts-apps ts-shared --include='*.ts' --include='*.svelte' --include='*.js'   # → 0
```

This is new ground; the nearest precedent is the shipped `GET /.webmcp/embed.js`
(`jl4-service/src/Application.hs:64`, `WebMCPPage.hs`), a hand-written dependency-free IIFE
configured by `data-*` attributes, which reads its base URL off `document.currentScript.src`
(`WebMCPPage.hs:59`). `<l4-ladder>` should be the **second instance of that pattern, minus
the `currentScript` trick**, which channel C breaks (§1.2).

### 4.1 Registration

```js
// IIFE build: self-registering, idempotent, never throws on a second load.
if (!customElements.get("l4-ladder"))
  customElements.define("l4-ladder", L4LadderElement);
```

The ESM build exports the class and does **not** self-register; it exports
`defineL4Ladder(tag = 'l4-ladder')` and `mount(el, opts)` for hosts that want a plain element
or a different tag. Two wikis on one page must not fight over the registry, hence the guard —
and under channel C the file is concatenated with every other plugin's JS, where a second
`define` of the same tag is a hard `DOMException`.

### 4.2 Attributes

All are observed (`observedAttributes`) and reflected to same-named properties. Unknown
attributes are ignored, never fatal. **All configuration is on the element**; nothing is read
off the script tag (§1.2).

| Attribute     | Values                                                       | Default         | Notes                                                                                      |
| ------------- | ------------------------------------------------------------ | --------------- | ------------------------------------------------------------------------------------------ |
| `src`         | URL                                                          | —               | **static mode**: fetch a `FunDecl` JSON (§5.1)                                             |
| `endpoint`    | origin or base URL of a `jl4-service`                        | —               | **live mode** (§5.2); see **R10** before pointing it anywhere public                       |
| `deployment`  | deployment id                                                | —               | live mode; required with `endpoint`                                                        |
| `decision`    | function name, as it appears in L4 (spaces allowed)          | —               | live mode; URL-encoded into the path                                                       |
| `theme`       | `screen` \| `ink` \| `auto`                                  | `screen`        | `screen`/`ink` are `ladder-core`'s `Theme` (`types.ts:160`); `auto` needs seam S8 → **R8** |
| `connective`  | `on-wire` \| `above-wire` \| `below-wire` \| `straddle-wire` | `straddle-wire` | `types.ts:177`                                                                             |
| `scale`       | `Scale` (`types.ts:158`)                                     | `full`          |                                                                                            |
| `interactive` | boolean attribute                                            | present ⇒ on    | absent ⇒ a picture: no listeners, no pan/zoom, no cursor change                            |
| `values`      | `atomId=T,atomId=F` — see the escaping rule below            | —               | initial valuation, resolved through `nodesByAtomId` (`viz-adapter.ts:64-69`)               |
| `fold`        | comma-separated `NodeId`s — **pinned payloads only**         | —               | initial `foldSet`; see the stability note below                                            |
| `max-height`  | CSS length                                                   | none            | viewport for pan/zoom; without it the element is its natural height                        |
| `sentences`   | boolean attribute                                            | absent          | render `expandSentences` (`sentences.ts:97`) beneath the diagram                           |
| `caption`     | text                                                         | —               | a **convenience** for the JS path; the real caption is a light-DOM child (§5.3)            |

**The `values` microformat has an escaping rule, and it is not optional.** Keys are
`atomId`s; an `atomId` is an arbitrary L4-derived string and may contain `,` or `=`. So:
each key and each value is **percent-encoded**, `,` separates pairs, the **first** `=`
splits a pair, and values are exactly `T`/`F`/`U` (anything else is ignored with a
`console.warn`, never fatal). Label-keyed entries are **not** accepted — an earlier draft
allowed `label=T`, which is ambiguous with an atomId containing `=` and is unresolvable
without a second index. A host that wants label resolution uses the `setValue` property API.

**`values` is keyed by `atomId` and `fold` by `NodeId`, and that asymmetry is deliberate.**
`ladder-core/src/types.ts:163-166` states the doctrine itself: "Leaf _values_ would be keyed
by atomId; only structural facts (fold, eliminability) are positional." So `fold` is not a
violation of the NodeId-instability rule, it is the rule's other half. It is still brittle
across a re-typecheck, because positions move: **`fold` is specified only for a pinned
payload** — inline data, or a `src` whose bytes the author controls — and in live mode
unknown ids are ignored silently rather than erroring. The `l4-ready` event reports how many
`fold` ids were dropped so an author can notice.

**Inline data beats every attribute.** A child

```html
<l4-ladder interactive>
  <script type="application/l4-ladder+json">
    { "$type": "FunDecl", … }
  </script>
</l4-ladder>
```

is read on `connectedCallback` and used in preference to `src`/`endpoint`. It needs **no
network, no CSP `connect-src`, and no reachable service** — that is what earns it first-class
rank (§1.1-2). Browsers do not execute an unknown `type`, so the block is inert until we read
it. Under channel C it is also the shape the plugin's syntax component emits, mirroring how
`bpmnio` carries its BPMN XML inline — but note that under channel E the inline block is
sanitised away exactly as fast as a `<script src>` would be, so this is a CSP/network
property, not a sanitiser property.

### 4.2a Lifecycle — teardown and attribute mutation

Unwritten semantics here are how a widget leaks. Normative:

- `connectedCallback`: read inline JSON → else `src` → else `endpoint`. Construct the
  controller. **Then** schedule a microtask re-check for the inline child: under channel E a
  non-deferred script can upgrade the element before its children parse, and the child would
  be missed. Channel C's `defer` (§1.2) makes the first read sufficient; the re-check makes
  both safe, and is a no-op when the first read succeeded.
- `disconnectedCallback`: `controller.destroy()` — remove listeners, cancel any pending
  `requestAnimationFrame`, abort any in-flight `fetch` via `AbortController`, and drop the
  scene. Re-connection re-renders from retained state; it does **not** re-fetch.
- `attributeChangedCallback`, by attribute class:
  - **re-layout only** (`theme`, `connective`, `scale`, `max-height`, `sentences`): recompute
    the `ViewSpec`, `render(vs)`, keep the valuation and the `viewBox`.
  - **re-fetch** (`src`, `endpoint`, `deployment`, `decision`): abort in flight, re-fetch,
    reset the FLIP baseline via `setFunDecl`, `fit()`.
  - **re-seed** (`values`, `fold`): applied on the current tree; ignored for unknown keys.
  - **rewire** (`interactive`): attach or detach listeners; never rebuild the DOM.
  - `adoptedCallback` is a no-op.
- Setting the `funDecl` property directly always wins over every attribute and cancels any
  in-flight fetch.

### 4.3 Properties and methods

```ts
interface L4LadderElement extends HTMLElement {
  funDecl: VizFunDecl | null; // set directly to bypass fetch/parse entirely
  readonly verdict: Verdict | null; // boolean-analysis' six values (decision-query.ts:19)
  readonly valuation: ReadonlyMap<string, UBoolValue>; // keyed by atomId, not NodeId
  readonly scene: Scene | null;
  setValue(atomId: string, v: UBoolValue): void;
  reset(): void;
  fit(): void;
  reload(): Promise<void>;
  toSvgString(): string; // the exact string sceneToSvg produced — a download
}
```

`toSvgString()` is deliberate: SPEC.md §1.3-4 records that their page has **no export**. Ours
hands you the SVG from the element you are looking at.

`valuation` is keyed by **`atomId`, not `NodeId`**, because `NodeId` is positional and one
proposition can sit at several positions (E1-IDE-INTEGRATION.md R2). The identity index needed
for the translation already exists — `nodesByAtomId` / `atomIdByNode` in `DecodedIdentity`
(`viz-adapter.ts:64-69`). A host that writes `NodeId`s would be writing against an id that
changes when the module is re-typechecked.

### 4.4 Events

All `CustomEvent`, `bubbles: true`, `composed: true` (so they cross a shadow root if **R2**
lands that way).

| Event        | `detail`                                                                   | When                                                    |
| ------------ | -------------------------------------------------------------------------- | ------------------------------------------------------- |
| `l4-ready`   | `{ verdict, atoms: number, source: 'inline'\|'src'\|'live', foldDropped }` | after the first successful layout                       |
| `l4-change`  | `{ atomId, label, value, verdict }`                                        | after a click changes a value and the scene is redrawn  |
| `l4-verdict` | `{ verdict, previous }`                                                    | only when the verdict actually changes                  |
| `l4-error`   | `{ phase: 'fetch'\|'parse'\|'layout'\|'live', message, fatal: boolean }`   | any failure; **always** paired with visible degradation |

`l4-error` is not decoration. §5.3 makes it the contract for the failure the housing-wizard
already hit once. `fatal` distinguishes "nothing is on screen" from "what is on screen is
stale", which is the distinction §5.3's first-load row turns on.

### 4.5 Shadow DOM

Open question — **R2**. The tension is exact: a shadow root gives style isolation (a wiki's
`table { }` rules cannot reach in), but it also blocks inheriting the host page's colours,
which is the entire motivation for seam S8's CSS custom properties. Custom properties _do_
pierce shadow boundaries, so "shadow root + `--l4-*` custom properties with sensible
fallbacks" may get both; that needs one spike, not an argument. **R2 also has a channel-C
face**: light-DOM children are the no-JS fallback (§5.3), and a shadow root hides them unless
they are slotted — so whatever R2 decides must keep the fallback visible when the upgrade
never runs.

### 4.6 The build — concretely

`ts-shared/ladder-svg` already contains the only IIFE in the repo,
`standalone/build.sh` (`npx esbuild standalone/app.ts --bundle --format=iife`). E1 generalises
it. **Two entry points, because the two artifacts genuinely differ**: the IIFE self-registers,
the ESM one must not (§4.1). One entry cannot do both without a build-time `define`, and a
second entry file is three lines. Proposed `ts-shared/ladder-svg/element/build.sh`:

```bash
# element/index.ts  — exports { L4LadderElement, defineL4Ladder, mount }; registers nothing.
# element/iife.ts   — `import * as E from './index.js'; if (!customElements.get('l4-ladder')) …`
esbuild element/index.ts --bundle --format=esm  --target=es2020 --platform=browser \
  --minify --metafile=dist/element.esm.meta.json  --outfile=dist/l4-ladder.esm.js
esbuild element/iife.ts  --bundle --format=iife --target=es2020 --platform=browser \
  --global-name=L4Ladder --minify --metafile=dist/element.iife.meta.json \
  --banner:js=';' --outfile=dist/l4-ladder.js
```

- `--target=es2020` matches `ladder-core`/`ladder-svg`'s own tsconfigs (neither extends
  `@repo/typescript-config/base.json`; both are hand-rolled at ES2020).
- **No `--external`, ever.** A single external turns a paste into an install.
- `--banner:js=';'` is the concatenation guard channel C needs (§1.2).
- No `--splitting`, no code-splitting, no dynamic `import()`: one file is the requirement.
- `--sourcemap=external` is optional and must **not** be referenced from the minified file when
  the map is not shipped (a 404 in someone else's console is our bug).
- The IIFE artifact is byte-identical to the plugin's `script.js` (E1e). If it ever has to
  differ, channel C has stopped being a shim and needs its own row.

**Two build-time gates, both cheap, both non-negotiable** (they run in CI, not at the
destination — see §8's split):

1. **Dependency-closure test.** Read `--metafile`'s `inputs` and assert every path is under
   `ts-shared/ladder-core/`, `ts-shared/ladder-svg/`, or `<none>` — and additionally that
   `ascii.ts` and `mermaid.ts` are **absent** (carriers belong to the CLI, not the widget).
   This is what turns EK-"no framework" from a claim into a check, and it is precisely the
   trap worth catching: `ladder-core/package.json` declares `@repo/viz-expr` and
   `@repo/boolean-analysis` as regular `dependencies` even though every use is `import type`,
   and `viz-expr` drags `effect`, `ts-pattern`, `vscode-jsonrpc` and three
   `vscode-messenger-*` packages behind it. One accidental value import and the bundle grows a
   vscode-messenger tree. **This gate is also what enforces EK4 and EK5.**
2. **Size budget.** Raw TS for the screen-only path is 81,588 bytes across 6 files (109,270
   for all of `ladder-core/src` + `ladder-svg/src`, i.e. including the ASCII and Mermaid
   carriers). Budget: **≤ 60 KB gzipped for the IIFE**, asserted in the build script.
   _(Unverified — the source figures are measured, the minified+gzipped one is an estimate;
   no `node_modules` in this worktree. If the first real measurement blows it, the budget
   moves and the reason gets written down; the gate exists so that is a decision rather than
   a drift.)_

### 4.7 Where the file is served from

Three options, and **R6** picks:

| Option                  | Precedent                                                   | Cost                                                                                 |
| ----------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `jl4-service` serves it | `GET /.webmcp/embed.js` (`Application.hs:64`) — **shipped** | couples the Haskell build to a prior `npm run build`; CI runs those as separate jobs |
| GitHub Pages            | `deploy-webchat.yml` publishes `ts-apps/webchat` — shipped  | no coupling; a second origin in the host's CSP                                       |
| both, same bytes        | —                                                           | two publish paths to keep honest                                                     |

The embed.js route has one property the others do not: it already solved "our script on someone
else's page", down to carrying a WebMCP third-party origin-trial token minted for
`https://legalese.cloud` (`WebMCPPage.hs:54`). The embedding precedent is worth more than the
hosting convenience.

**But note what §1.2 does to this ruling.** In channel C the file is served by the wiki
itself, from the wiki's origin, and R6 is irrelevant to that channel — R6 governs channels D,
E and the general web. That makes R6 _smaller_ than it looked, and it removes the strongest
argument for `jl4-service` (third-party-origin delivery) in the one channel we most expect to
use.

---

## 5. E2 — the two modes

### 5.1 Static mode — the data contract

**The payload is a viz-expr `FunDecl`**, not a bespoke format:

- TypeScript: `ts-shared/viz-expr/viz-expr.ts:249` (`FunDecl` = `{$type, id: IRId, name: Name, params: Name[], body: IRExpr}`), body union at `:213`, leaves at `:289` (`UBoolVar`), `:338` (`InertE`), `:275` (`Implies`).
- Haskell (the producer): `jl4-core/src/L4/Viz/VizExpr.hs:71` — and note the wire key is
  `"name"` while the Haskell field is `fnName` (`VizExpr.hs:80`).
- A worked example, checked in: `ts-shared/ladder-core/test/fixtures/may-purchase-alcohol.viz.json`
  (2,080 bytes) — a **bare `FunDecl`**, not a `RenderAsLadderInfo`.

The element accepts either shape: a bare `FunDecl`, or a `RenderAsLadderInfo`
(`{verDocId, funDecl}` — `VizExpr.hs:44`, `viz-expr.ts:354`) from which it takes `.funDecl`.
Accepting both costs one line and means `curl … | jq .ladder` and `jq .ladder.funDecl` both
work.

> **EK4 (locked). The element does not validate with `effect`.** `makeVizInfoDecoder()`
> (`viz-expr.ts:363`) is the repo's decoder and it is `Schema.decodeUnknownEither` — a runtime
> `effect` value. Importing it would put `effect` in the bundle and blow §4.6's budget on the
> first commit. The element does a hand-rolled structural check (`$type === 'FunDecl'`, `body`
> present) and otherwise lets `fromVizFunDecl` (`viz-adapter.ts:119`) fail, caught and reported
> as `l4-error{phase:'parse'}`. Validation strictness is a _host-side_ concern: the producer of
> the JSON is us. §4.6's closure gate is what keeps this true.

**Producing a static payload today has no CLI.** `jl4/app/Main.hs:62-88` has
`run, check, format, ast, batch, trace, state-graph, render, openfisca` — no `ladder`, no
`export`. The one checked-in fixture was produced by driving a live `jl4-lsp` over WebSocket
JSON-RPC by hand (`ts-shared/ladder-core/test/viz-adapter.real-module.test.ts:1-24`). The
cheapest producer that exists **is the live endpoint** —
`curl -s -X POST …/query-plan -d '{"arguments":{}}' | jq .ladder` — which inverts SPEC.md's
E1→E2 dependency order: static mode's _data_ currently comes from live mode's machinery. An
`l4 ladder` subcommand (or `l4 export --to=ladder`) breaks that inversion for one afternoon's
work and belongs in Track S. **R5** — and §1.1-3 raises its stakes: the same subcommand,
emitting `sceneToAscii`/`sceneToSvg`, _is_ channel A and channel B, the only channels with
no adoption cost at all.

### 5.2 Live mode — the route, and whether it exists

SPEC.md §4 said:

> **Surface S1 is nearly free and should be taken early.** `L4.Viz.Ladder` lives in
> **`jl4-core`**, not `jl4-lsp` … the route is plumbing.

**The justification is half wrong and the conclusion is understated.** SPEC.md has been
amended.

Half wrong: there are **two** ladder implementations. `jl4-core/src/L4/Viz/Ladder.hs` (exposed
at `jl4-core.cabal:156`, header comment "simplified version … for use in WASM builds",
consumed by `L4.API` and `jl4-wasm`) and `jl4-lsp/src/LSP/L4/Viz/Ladder.hs` (`doVisualize`,
`inlineExprs`, `mkVizConfig`). They are near-duplicates. **`jl4-service` uses the `jl4-lsp`
one** — `jl4-service/src/Backend/DecisionQueryPlan.hs:181` calls `LadderViz.doVisualize`, and
imports it at `:42` — and `jl4-service.cabal` depends on `jl4-lsp` as well as `jl4-core`.

Understated: **`RenderAsLadderInfo` is already served over HTTP today.**
`DecisionQueryPlan.hs:229` gives `QueryPlanResponse` a field
`ladder :: !(Maybe VizExpr.RenderAsLadderInfo)`, and `:290` sets it unconditionally
(`ladder = Just cached.ladderInfo`). The route is declared at `jl4-service/src/DataPlane.hs:92`:

```
POST /deployments/{deploymentId}/functions/{name}/query-plan
POST /{deploymentId}/{name}/query-plan            -- short alias, DataPlane.hs:60-77
Body:  FnArguments — {"arguments": {}}            -- Backend/Api.hs:121,128
```

The response also carries `verdict`, `determined`, `stillNeeded`, `ranked`, `inputs`, `asks`,
`impact`, `impactByAtomId`, `note` (`DecisionQueryPlan.hs:216-231`) — i.e. the whole wizard
side, including the ROBDD-exact verdict and the elicitation ranking the marks (**R7**) want.

So **E2 does not block on surface S1**. S1 becomes a GET-shaped alias for a payload the
service already computes and caches, which is a genuine ergonomic win for a wiki
(`<l4-ladder src>` pointed straight at a service, no POST, no body, cacheable) but not a gate.
If it is built, it must reuse `buildDecisionQueryCacheFromCompiled` and return
`cached.ladderInfo` verbatim rather than calling `L4.Viz.Ladder.visualizeByName` — two
endpoints on one service disagreeing about the same diagram is worse than one endpoint. Note
also that `RenderAsLadderInfo` has hand-written `ToJSON`/`FromJSON` and **no `ToSchema`**
(`L4/Viz/VizExpr.hs:37-175`); `jl4-service` is `-Werror` and builds its OpenAPI doc by hand
(`OpenApiDoc.hs`, `Schema.hs`), so a new route follows that pattern.

**CORS permits the cross-origin call.** `Application.hs:168-172` is
`cors (const $ Just simpleCorsResourcePolicy { corsMethods = […,"OPTIONS",…], corsRequestHeaders = ["content-type","authorization"] })`,
and `simpleCorsResourcePolicy` has `corsOrigins = Nothing` ⇒ `Access-Control-Allow-Origin: *`.
A JSON POST from a wiki page preflights on `content-type`, which is allowed. _(Unverified by
execution: the origin semantics are read off wai-cors's definition, not observed.)_

**Two failure paths emit no CORS headers at all.** Middleware composes outside-in
(`Application.hs:146`): `concLimiter . contentLengthMiddleware . requestLog . corsMiddleware . …`.
The limiter is **outermost**, so the `503 "Service at capacity"` it returns
(`Application.hs:208`, `responseLBS status503 []` — an empty header list) never passes through
`corsMiddleware`; same for Warp's exception response. A browser embed hitting either sees an
opaque network failure, not a status code — the housing-wizard hung-spinner class of bug, one
layer down. Default `--max-concurrent-requests` is **20** (`Options.hs:116-120`). A wiki page
that goes even mildly viral hits it.

**There is no authentication in this repo.** No `BasicAuth`, no `AuthProtect`, no bearer check
anywhere in `jl4-service/src/`; the only `Authorization` mentions are documentation strings in
`ExplorerPage.hs:140,182,205` pointing at Legalese Cloud. The service trusts `X-L4-Origin` and
`X-Include-*` headers, each defaulting to `True` when absent (`Application.hs:249-261`), and is
built to sit behind a proxy that is not in this repo.

**Consequence, stated as a rule rather than a shrug.** An earlier draft called this "a design
input, not a blocker" and moved on, which quietly commissioned a public compute service that
nobody had agreed to operate. Corrected:

> **EK6 (locked). Live mode is opt-in per embed, and the bundle ships no default
> `endpoint`.** There is no origin baked into the artifact, no fallback service, and no
> "try the public one" path. An embed does live mode only because its author typed an
> `endpoint` they are entitled to point at. **Who, if anyone, operates a public
> `jl4-service` for third-party embeds is R10** — unanswered, and out of Track E's scope
> until it is answered. §8.4 is therefore satisfied by a `jl4-service` on `localhost`, and
> E2a's "a real deployment" means one we run for the demonstration, not a service offered to
> the public. Rate limiting, abuse posture and capacity are R10's, not §5.3's: §5.3 mitigates
> the _reader's_ rendering, and cannot mitigate the service.

### 5.3 Degradation — the ladder of last resorts

The strategic requirement ("survive the most hostile plausible substrate") is only met if this
table is implemented, not merely intended. **Every row is reachable; there is no undefined
cell.**

| Condition                                                         | Behaviour                                                                                                                                                                                          |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| inline `<script type=…json>` present                              | render immediately; **never touch the network**                                                                                                                                                    |
| `src` fetch fails / CSP blocks it                                 | keep any inline data; else the **no-data fallback** (below) and `l4-error{phase:'fetch', fatal:true}`                                                                                              |
| live `POST` fails **on the first request** (nothing rendered yet) | if inline or `src` data is in hand, render it statically and mark the element live-degraded; **if there is no local `FunDecl` at all, the no-data fallback**, `l4-error{phase:'live', fatal:true}` |
| live `POST` fails after a successful render                       | fall back to the last successfully rendered scene, mark the element stale, keep clicks working locally (see below), `l4-error{phase:'live', fatal:false}`                                          |
| live `POST` does not answer within **5 s**                        | abort it; treat as the matching failure row above. **There is no unbounded spinner in this element.**                                                                                              |
| service reachable but slow                                        | render the ladder from the _first_ response and let clicks resolve locally; do not block the picture on a round-trip                                                                               |
| JS disabled entirely, or `customElements` unsupported             | the upgrade never runs; the element's **light-DOM children stay visible** — that is the fallback (below)                                                                                           |

**The no-data fallback, specified once.** The element renders its own light-DOM children if
it has any, plus a one-line "diagram unavailable" note. It never shows an empty box and never
shows a spinner that hangs. The `caption` **attribute** is not the fallback — an attribute
renders nothing without JS, which was a real hole in an earlier draft. The fallback is a
**child**:

```html
<l4-ladder src="…/eligibility.json">
  <figcaption>Reg CF issuer eligibility — 17 CFR 227.100(b)</figcaption>
  <pre><code>… sceneToAscii output, channel A, pasted alongside …</code></pre>
</l4-ladder>
```

On a successful render those children are hidden (not removed, so a re-render or a
`disconnectedCallback` can restore them); on failure and on no-JS they are what the reader
sees. The `caption` attribute remains as a convenience: when present and no `<figcaption>`
child exists, the element synthesises one — for the JS path only. This also means **the
best-behaved embed carries its own ASCII fallback inside itself**, which is a pleasing
consequence of §1.1: channel A is not only the floor, it is the floor _inside_ channel C.

"Keep clicks working locally" is the substantive one, and it is what **R4** settles: with a
`FunDecl` in hand, `verdictFor` (`layout.ts:248`) computes a verdict from a valuation with no
network at all. It is _sound but not complete_ — conservatively `Undetermined` where the
wizard's ROBDD would settle a tautology (`ladder-model.ts:149-159`). A widget that degrades
from an exact verdict to a conservative one when the network drops is honest; a widget that
freezes is not.

---

## 6. What dies, and Track E's relationship to the deletion

SPEC.md K2 and E1-IDE-INTEGRATION.md:108 delete, at ladder Step 8: `displayers/flow/**`,
`layout-ir/**`, `algebraic-graphs/**`, `data/viz-expr-to-lir.ts` (the last `expandImplies` call
site), `node-paths-selection.ts`, and five dependencies (`@dagrejs/dagre`, `@xyflow/svelte`,
`graphology*`, `array-keyed-map`, `@repo/layout-ir`).

Track E's relationship to that is: **strictly downstream of the seam, and never coupled to the
package being gutted** (EK2). Three consequences:

1. **The element must not gate Step 8.** If E1 imported `l4-ladder-visualizer`, the deletion
   commit would have to unpick a published widget. It does not, so the deletion stays a Step 8
   internal.
2. **`expandSentences` is the paths-list, for us too.** SPEC.md K2 retires the graph highlight
   in favour of the sentence list. The `sentences` attribute (§4.2) is that decision applied to
   the embed — and it is a better fit there than in the IDE, since a wiki reader gets a list
   that reads aloud and survives print without a DAG.
3. **`LadderModel` must move — but it is not the element's brain.** It is the intended IDE
   brain (E1-IDE-INTEGRATION.md:89-90: "the one thing not to do: build `LadderSvg` on top of
   `LirContext`"), it is framework-free, it is tested — and it is **not exported**
   (`grep -n 'model' ts-shared/l4-ladder-visualizer/src/lib/index.ts` → no match; the file
   exports `viz-expr-to-lir`, `ladder-env`, `query-plan-override`, `@repo/layout-ir`,
   `ladder.svelte`, `node-paths-selection`, `LadderFlow` and the flow types). Where it lands
   is **R3**.

   **Its dependency inventory, corrected.** An earlier draft said "its imports are
   `@repo/ladder-core`, `@repo/viz-expr` (types) and the five surviving `eval/` modules",
   which understates the problem in three ways:
   - `ladder-model.ts:43,50-51` requires a `LadderModelDeps` of
     `{ l4Connection: L4Connection; verDocId: VersionedDocId }` — **a required constructor
     argument**, not an optional hook, used at `:127-128`. The only implementation of
     `L4Connection` imports `makeVizInfoDecoder` (`l4-connection.ts:2`) — a runtime `effect`
     value.
   - the `eval/` modules import `@repo/viz-expr` as a **runtime value**, not type-only:
     `eval/eval.ts:1` (`App, IRId`), `eval/partial-eval.ts:2` (`typicallyBridge`),
     `eval/type.ts:1-2` (`IRExpr`, `* as VE`). They also import `ts-pattern` at
     `eval/eval.ts:16`, `partial-eval.ts:3`, `type.ts:11`.
   - `eval/type.ts:9` imports a type from `$lib/layout-ir/ladder-graph/node-styles.js` — a
     path **inside the directory Step 8 deletes**. Type-only, so it is a compile-time
     obligation rather than a runtime one, but it must be moved or inlined by Step 8
     regardless.

   > **EK5 (locked). The element's brain is `verdictFor` + a valuation map, not
   > `LadderModel`.** Pulling `LadderModel` into the bundle would drag `effect`, `ts-pattern`
   > and a required `L4Connection` across §4.6's closure gate and straight through EK4 — the
   > three defects would surface together, at E1c, as a red build. Static mode does not need
   > it: `fromVizFunDecl` + a `Map<atomId, UBoolValue>` + `verdictFor` is the whole brain, and
   > `verdictFor`'s sound-not-complete gap is already documented and accepted (§5.3, R4).
   > R3 therefore decides where `LadderModel` lives **for the IDE**; the element adopts it
   > only if and when the eval modules shed their runtime `viz-expr`/`ts-pattern` imports and
   > the mandatory `l4Connection`, which is its own piece of work and is not scheduled here.

Nothing in Track E dies. Track E is additive by construction: `controller.ts` and `element/`
are new files in `ladder-svg`, and both demos get smaller.

---

## 7. Staging

Ordered against the ladder plan. Each row is one commit and leaves `npx turbo run check test`
green.

| #       | Increment                                                                                                                                                                            | Ships what                                                                           | Gate                      |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ | ------------------------- |
| **E0**  | `ladder-svg/src/controller.ts` + both demos converted                                                                                                                                | nothing user-visible                                                                 | **lands as Step 4** (EK1) |
| **E1a** | `<l4-ladder>` + inline `<script type=…json>` only. No fetch, no live, no pan/zoom beyond the controller's.                                                                           | **the smallest shippable increment** — a self-contained page that renders and clicks | E0                        |
| **E1b** | `src` fetch + the degradation table (§5.3, all rows) + `toSvgString()` + `sentences` + lifecycle (§4.2a)                                                                             | static mode, complete                                                                | E1a                       |
| **E1c** | The two bundles + metafile closure test + size budget (§4.6)                                                                                                                         | the paste-able artifact                                                              | E1b                       |
| **E1d** | **The channel probe — R1's scheduled answer.** Stand up a stock DokuWiki (container, `htmlok` off), paste channels A/B/C/D/E, record the outcome of each into §1.1. No product code. | **R1 answered with evidence instead of a leaning**                                   | E1c                       |
| **E1e** | **The DokuWiki plugin shim** — an `<l4ladder>` syntax component + `script.js` = the E1c IIFE **byte-identical**, inline JSON in the block like `bpmnio`'s XML                        | channel C, at its true cost: one admin install                                       | E1d                       |
| **E2a** | Live mode against `POST …/query-plan` as it exists today, against a deployment **we** run                                                                                            | a wiki page reading a deployment we operate (not a public service — EK6)             | E1c, **R10**              |
| **E2b** | `GET …/ladder` (surface S1) if **R5** says build it; `l4 ladder` producer emitting JSON **and** ASCII/SVG                                                                            | GET-shaped embeds, offline payload production, **and channels A + B**                | E2a                       |
| **E3**  | Marks in the embed, if **R7** says they gate                                                                                                                                         | K1's argument applied to the widget                                                  | ladder 6a                 |

**E1a is the increment that answers SPEC.md §8's fourth acceptance criterion** — "the ladder
for the eligibility decision renders in a plain HTML page with a script tag, and clicking a
term changes the verdict" — with a single file and no service at all. E1d/E1e are what turn
"an arbitrary web page" into "**their** page", and E2b is what makes the zero-admin channels
real. E1d and E1e can run in parallel with E2a; nothing after E1c is on the milestone path
(§1.3).

---

## 8. Acceptance

**Split, because an earlier draft's preamble ("no build tools") contradicted its own
build-time gate.**

### 8.A At the destination — on a machine with no `node_modules`, no build tools, and no network beyond fetching one script

1. A plain `.html` file containing one `<script src>` and one `<l4-ladder>` with an inline JSON
   block renders the Reg CF eligibility ladder and changes its verdict on click.
2. The same page works with the script served from a `file://` copy — no CDN, no npm.
3. Blocking `connect-src` entirely changes nothing about (1).
4. Pointing `endpoint`/`deployment`/`decision` at a running `jl4-service` — **`localhost` is
   sufficient and is what this criterion means** (EK6) — renders the same decision live;
   killing the service mid-session leaves the diagram usable and fires `l4-error`; killing it
   **before** first load leaves the fallback children visible and fires
   `l4-error{fatal:true}`, never a spinner.
5. `toSvgString()` on the rendered element yields an SVG that opens in Inkscape — the export
   their page does not have (SPEC.md §1.3-4).
6. With JavaScript disabled, the page still shows the `<figcaption>` child and any pasted
   ASCII fallback (§5.3).

### 8.B In CI

7. The metafile closure test passes: the bundle's inputs are `ladder-core` + `ladder-svg` +
   `element/` and nothing else, with `ascii.ts`/`mermaid.ts` absent; the gzipped IIFE is
   within budget (§4.6).

### 8.C Against a substrate we do not author — the criterion R1 was missing

8. E1d has been run against a stock DokuWiki with `htmlok` off, and §1.1's table records, for
   each of channels A–E, what survived. **A negative result closes this criterion**; what it
   must not do is stay unrun.
9. E1e's plugin renders the same diagram from the same bytes as (1), installed by the normal
   Extension-Manager route, with no CSP change on the host.

Criteria 8 and 9 do **not** gate M2 or M3 (§1.3). They gate the distribution claim.

---

## 9. Open rulings

- **R1 — the paste channel.** Does a stock DokuWiki accept a raw `<script>`/HTML block at all
  (§1)? The observed evidence is a _registered plugin's_ syntax, not raw markup, and
  dokuwiki.org documents HTML/PHP embedding as disabled by default with the code displayed
  rather than executed — which an openly-registerable, spam-indexed wiki would not change.
  Candidate shapes are channels A–F in §1.1. **Scheduled: E1d probes it, E1e delivers channel
  C, §8.8/8.9 accept it.** Its status is corrected: it is load-bearing for SPEC.md §4's
  _distribution claim_, **not** for the track or for M2/M3, which E1a alone satisfies (§1.3).
  Leaning: channel C is the answer, channels A/B are the floor, channel E is a trap.
- **R2 — shadow DOM or light DOM** (§4.5). Isolation versus inheriting the host's colours,
  _and_ versus keeping the light-DOM fallback visible. Leaning: open shadow root plus `--l4-*`
  custom properties with fallbacks and a `<slot>` for the caption/fallback children — but that
  is untested and interacts with **R8**.
- **R3 — where `LadderModel` lives** (§6.3). Note EK5 first: this is an **IDE** ruling, not an
  element one. Options: leave it in `l4-ladder-visualizer` and deep-import (rejected — EK2);
  export it from that package's `index.ts` (cheap, but couples to a package being gutted);
  move it plus the five `eval/` modules into `@repo/ladder-core` (largest blast radius,
  cleanest end state); or a new `@repo/ladder-model`. Leaning: the new package, because
  `ladder-core` is provably DOM-free and dependency-light while the eval modules import
  `viz-expr` and `ts-pattern` as runtime values (§6.3) and would be its first such dependency.
- **R4 — which brain, in which mode** (§5.3). Three positions: (i) the element always evaluates
  locally with `verdictFor`, and live mode only supplies the `FunDecl`; (ii) live mode
  round-trips every click to `POST …/query-plan` for the ROBDD-exact verdict and the ask
  ranking; (iii) local by default, one round-trip on demand. (ii) is the exact verdict and the
  marks, at the price of a network dependency per click and 20-concurrent-request headroom.
  Leaning (iii). Note the two verdicts genuinely differ: `verdictFor` is sound-not-complete
  (`ladder-model.ts:149-159`).
- **R5 — is surface S1 built at all, and does `l4 ladder` land** (§5.2). `POST …/query-plan`
  already returns `.ladder`, so S1 is a GET alias, not a feature. **The CLI half is the bigger
  half**: `l4 ladder` emitting JSON, ASCII and SVG is the entire implementation of channels A
  and B, the only zero-adoption-cost channels there are (§1.1-3). Raised in priority
  accordingly.
- **R6 — where the bundle is served from** (§4.7). `jl4-service` (`embed.js` precedent, couples
  the Haskell build to a prior `npm run build`), GitHub Pages (`deploy-webchat.yml` precedent,
  second origin in the host CSP), or both. Leaning: `jl4-service`. **But smaller than it
  looked** — in channel C the wiki serves the file from its own origin and R6 does not apply
  (§4.7).
- **R7 — do elicitation marks gate the embed** (§2). SPEC.md K1 says they gate the IDE default
  flip because omitting "you have not answered this yet" misleads. A wiki reader has _less_
  context than an IDE user, so the argument is stronger, not weaker — but marks need the render
  half of seam S4, which does not exist (`ViewSpec` has no `marks`; `ClickAct` has two verbs).
  If they gate, E1 waits on ladder 6a. Leaning: they gate E2/live (where the ask ranking is on
  the wire for free) and not E1a/static.
- **R8 — does seam S8 theming gate E1** (§2). Palettes are baked inline (`svg.ts:20,29,52`). A
  white rectangle in a dark host page is bad; a _wrong_ diagram is worse, and theming is not
  correctness. But `theme="auto"` (§4.2) is unimplementable without it. Leaning: E1 ships with
  `screen`/`ink` only and `auto` lands with S8. Watch the exhibit-churn risk
  E1-IDE-INTEGRATION.md:102 flags — default output should stay byte-identical.
- **R9 — leaf-label wrapping.** The ladder R1 spike found 17 of the 22 widest diagrams have
  exactly ONE leaf, max 4372px, because non-boolean constructs collapse to a source-text ribbon
  (E1-IDE-INTEGRATION.md:220-238). GuardedRows (D0, merged) removes the _typical_ case; the tail
  remains. Pan/zoom makes a wide ribbon navigable, not readable. Does E1 need the Step-2
  wrapping, or does the mirror corpus simply avoid the shapes that trigger it? Leaning: measure
  the Reg CF corpus specifically before deciding.
- **R10 — who, if anyone, operates a live backend for third-party embeds** (§5.2, EK6). The
  service has **no auth**, `Access-Control-Allow-Origin: *`, a default of **20** concurrent
  requests, and returns its 503 outside the CORS middleware so a browser sees an opaque
  failure. Nothing in this repo places it behind a proxy. Options: (a) nobody — live mode is
  for embeds whose author runs their own service, which is what EK6 assumes today; (b) we run
  one for the demonstration only, unadvertised, with the mirror page as its only client; (c) a
  real operated surface — which needs auth, quotas, an abuse posture and an owner, i.e. a
  product decision well outside Track E. Leaning (b) for M3, and (a) as the shipped default.
  **Until this is answered, no published embed points at a service we operate.**

---

## 10. Non-goals

- **Not a Svelte component, and not a React one.** The element is the integration surface; a
  framework wrapper, if anyone wants one, is twelve lines they write.
- **Not a wizard.** The embed draws a decision and answers "why". The full elicitation flow is
  Track C2 (`ts-apps/housing-wizard`'s façade pattern) and stays an app.
- **Not an editor.** No L4 source in the page, no round-trip. The payload is a `FunDecl`, which
  is downstream of the typechecker by construction.
- **Not a hosting product, and not an operated service.** R6 picks a place to put one static
  file. **R10** is the separate and unanswered question of whether anyone runs a backend for
  other people's embeds; EK6 says the artifact ships with no default endpoint, so the answer
  "nobody" is a working configuration rather than a gap.
- **Not a Lexipedia plugin we install ourselves.** E1e authors a plugin; installing it on
  their instance is their admin's decision and their editors' choice, and §1.1 prices it
  honestly.
- **Not BPMN or DMN rendering.** Those are Tracks P and D, and they emit files rather than
  widgets.

---

## 11. Disposition of the 2026-07-27 adversarial review

Three lenses (E0-realism, substrate, citation audit) returned **DEFECTIVE** with seven major
findings and a tail of minors. Every one is recorded here; none was dropped. "Fixed" means
the document changed; "rebutted" means the document now carries the counter-evidence.

| #       | Finding                                                                                             | Disposition                                                                                                                                                                                                                                                                                                                                       |
| ------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1**   | `LadderController` injects `metrics` it can never use, since `render(scene)` is pre-laid-out        | **Fixed.** The controller now owns layout: `constructor(host, fn, opts)` + `render(vs: ViewSpec) => Scene`, with `renderScene(scene)` as the escape hatch. Seam is `ViewSpec` because that is what `ladder-model.ts:167` actually produces (§3.2).                                                                                                |
| **2**   | §4.2 re-commits the plugin-syntax/pasted-HTML conflation; **no** E1 mode survives a stock sanitiser | **Fixed, and the design re-derived.** §1 rewritten: "zero adoption cost" is withdrawn as false; §1.1 prices five channels; §1.2 derives new bundle constraints from the plugin channel (no `currentScript`, concatenation hygiene, same-origin CSP); §4.2's inline-data rationale is re-based on CSP/network, not the sanitiser. SPEC.md amended. |
| **3**   | R1 "load-bearing premise of the whole track" but unscheduled and unaccepted                         | **Fixed both ways.** Scheduled as staging rows **E1d** (probe) and **E1e** (plugin shim), accepted at **§8.8/8.9**; and demoted — §1.3 states plainly that E1a alone satisfies SPEC.md §8.4, so the wiki channel is load-bearing for the distribution claim only.                                                                                 |
| **4**   | Degradation table undefined for a live-only **first**-load failure                                  | **Fixed.** §5.3 gains a first-request row, a 5 s timeout row, and a single specified **no-data fallback** shared with the `src` row. `l4-error` gains `fatal`.                                                                                                                                                                                    |
| **5**   | Live mode presumes a public unauthenticated backend nobody was assigned to operate                  | **Fixed.** **EK6** — live mode is opt-in per embed, no default `endpoint` ships, §8.4 is explicitly localhost-satisfiable, E2a is "a deployment we run". **R10** owns operator/capacity/abuse. Non-goals amended.                                                                                                                                 |
| **6**   | EK1 locked, but E1-IDE-INTEGRATION.md (the declared single source) still says "port the FLIP"       | **Fixed outside this file too**: E1-IDE-INTEGRATION.md's Step 4 row now carries a marker pointing at EK1/§3, and the header here says so. §3 keeps its Step-4 detail deliberately — the two documents now agree and the disagreement is loud rather than silent.                                                                                  |
| **7**   | SPEC.md left contradicting the S1 / S6+S8 / substrate corrections; pointer disclosed only E0        | **Fixed.** SPEC.md's Track E row, the `E2 … Depends on: E1, S1` cell, milestone M2, the §4 surface-S1 blockquote and the "zero adoption cost" blockquote are all amended, and the pointer now lists all four corrections.                                                                                                                         |
| **m1**  | §4.6 builds two bundles from one entry that must and must not self-register                         | **Fixed.** Two entries: `element/index.ts` (exports only) and `element/iife.ts` (registers).                                                                                                                                                                                                                                                      |
| **m2**  | §8's "no build tools" preamble contains a build-time gate                                           | **Fixed.** §8 split into 8.A destination / 8.B CI / 8.C substrate.                                                                                                                                                                                                                                                                                |
| **m3**  | "provably framework-free" grep is a literal-string grep; the tsconfig argument is wrong             | **Fixed and partly rebutted.** The grep is now `-rE` and is zero either way (re-run); the tsconfig argument is **withdrawn** — no `lib` is set, so `lib.es2020.full.d.ts` already supplies DOM, which is also why `controller.ts` needs no tsconfig change (§2, §3.5).                                                                            |
| **m4**  | `values`/`fold` microformats lack escaping and `fold` fights the NodeId doctrine                    | **Fixed and rebutted.** Percent-encoding rule specified, `label=` form dropped as ambiguous. But `fold` being NodeId-keyed is **correct**: `types.ts:163-166` says values are atomId-keyed and structural facts are positional. Restricted to pinned payloads; unknown ids ignored and counted in `l4-ready`.                                     |
| **m5**  | teardown / attribute-mutation semantics unwritten                                                   | **Fixed.** New §4.2a: `connectedCallback` + microtask re-check, `destroy()` on disconnect with `AbortController`, and a per-attribute mutation class table.                                                                                                                                                                                       |
| **m6**  | `LadderModel`-as-brain collides with EK4, the closure gate and acceptance                           | **Fixed.** **EK5** — the element's brain is `verdictFor` + a valuation map; `LadderModel` stays the IDE's. §6.3's import inventory corrected with three verified defects (required `l4Connection`, runtime `viz-expr`/`ts-pattern` in `eval/`, a `layout-ir` type import Step 8 deletes).                                                         |
| **m7**  | the no-JS fallback rests on `caption`, an attribute, which renders nothing                          | **Fixed.** The fallback is now light-DOM children (`<figcaption>` + optional pasted ASCII); the attribute is a JS-path convenience only. Accepted at §8.6.                                                                                                                                                                                        |
| **m8**  | unflagged S-numbering collision; EK3 "strikes" a dependency nobody recorded                         | **Fixed.** A namespace note heads the document; every use now reads "seam S*n*" or "surface S*n*". EK3 restated as pre-emptive rather than a strike.                                                                                                                                                                                              |
| **m9**  | R3's import inventory is wrong                                                                      | **Fixed** — see m6.                                                                                                                                                                                                                                                                                                                               |
| **m10** | three grep "universals" are unrunnable or wrong                                                     | **Fixed.** All three re-run and quoted as runnable commands; the `marks` grep is **1 hit, a comment** (`viz-adapter.ts:200`), not zero — the conclusion (`ViewSpec` has no `marks`) is unchanged and now cited to `types.ts:183`.                                                                                                                 |
| **m11** | DOM-lib tension the landing checklist misses                                                        | **Rebutted, then recorded.** There is no tension — DOM types are in scope by default (m3) — but §3.5 now asserts it, because the way it would break is a future explicit `lib`.                                                                                                                                                                   |
| **m12** | stray `</content></invoke>` at end of file                                                          | **Fixed.** Removed.                                                                                                                                                                                                                                                                                                                               |

Two further review observations are accepted without change, and recorded so they are not
re-litigated: the **≤ 60 KB gzipped budget remains an estimate** (§4.6 says so, and now says
what happens if the first measurement blows it), and the **CORS origin semantics remain
unverified by execution** (§5.2 says so).
