# E1 — the IDE integration: replacing Dagre/SvelteFlow with `ladder-core` + `ladder-svg`

_Scoped 2026-07-15, against `mengwong/ladder-diagrams-3` after the `ladder-svg` split
(G6/E4, `0ad98784`). Companion to [DESIGN.md](./DESIGN.md) §9, §11, §12, §25f._

This is **the ship**. Everything below the IDE seam is real — the kernel, the visual
language, the viz-expr adapter, the verdict. The seam itself is uncrossed: the production
Svelte package still renders through Dagre + SvelteFlow, and in the IDE that is still the
picture a user gets.

---

## 0. The two facts that shape the plan

**The eval brain is already seam-ready, and nobody noticed.** `expandImplies` has exactly
**one** call site in the whole repo's app code — `l4-ladder-visualizer/src/lib/data/viz-expr-to-lir.ts:73`,
the entry point of the Dagre path. Meanwhile `eval/eval.ts` and `eval/partial-eval.ts`
_already carry `Implies` arms_ (`partial-eval.ts:79,101,159,194,216,241,267`). So the
expansion was never a semantic requirement; it was a **Dagre requirement**. A displayer
that feeds the _raw_ viz `FunDecl` to the existing `Evaluator` + `PartialEvalAnalyzer`
gets the §25f seam end-to-end **for free**, without touching the elicitation logic.

That is why E1 is now the last mile of §25 rather than a separate project: the verdict is
computed (`BooleanDecisionQuery.verdictOf`), on the wire (`QueryPlanResponse.verdict`), and
drawable (`ScenePrim.coil`) — and the _only_ thing that cannot show it is the renderer.

**The five eval modules survive the swap intact.** `eval/{type,assignment,eval,partial-eval,query-plan-override}.ts`
are already LIR-free (`query-plan-override.ts` imports `LirContext` as a _type_ only) and
`elicitationOverrideFromQueryPlan` is already structurally typed against
`{getUniquesForAtomId, getUniquesForLabel}` — so a new model class need only implement two
methods to reuse it verbatim. This is the biggest and least obvious "Keep" in §11: the whole
eval + elicitation brain is renderer-agnostic already.

---

## 1. Seam inventory — what the new engine cannot do yet

Ordered by whether it blocks.

| #       | Gap                                                                                                                                                                                                                                                                                                            | Where                                               | Blocks                          |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------- |
| **S1**  | **No `Unique` on a ladder leaf.** `viz-adapter.ts:26` says outright "the `unique` is dropped". But `Assignment`, `PartialEvalAnalysis`, `ElicitationOverride` and every LSP round-trip are keyed by `Unique`, while `ViewSpec.valuation` is keyed by `NodeId`. **There is no NodeId↔Unique bridge anywhere.** | `ladder-core/src/types.ts:31`, `viz-adapter.ts:151` | eval, sidebar, query-plan       |
| **S2**  | `canInline` dropped — the "unfold to definition" `+` button has nothing to gate on.                                                                                                                                                                                                                            | same                                                | the `+` affordance              |
| **S3**  | `App` flattened to a bare leaf, losing its args — but `evalApp` needs them. **Not a core bug:** keep the raw viz `FunDecl` beside the decoded tree. ladder-core's `IRExpr` is the _drawing_ tree; viz-expr's is the _evaluation_ tree.                                                                         | `viz-adapter.ts:159`                                | — (architecture, write it down) |
| **S4**  | `ClickAct` has two verbs (`value`, `fold`) and there is **no channel at all** for selection, hover, elicitation marks, the ask badge, or tooltips. `ViewSpec` has no `marks`.                                                                                                                                  | `types.ts:158,214`                                  | Step 6                          |
| **S5**  | No DOM sink — only the string sink. `{@html}` + delegated listeners works, but cannot host Svelte children (bits-ui menus need real anchors).                                                                                                                                                                  | `ladder-svg/src/svg.ts:160`                         | Step 6 chrome                   |
| **S6**  | No pan/zoom or fit-view. SvelteFlow supplied all of it.                                                                                                                                                                                                                                                        | —                                                   | Step 4                          |
| **S7**  | **Text metrics are a crude estimator** (`length * size * 0.56`) while the emit centres labels in boxes — any under-estimate overflows. This is TODO **A4**. Good news: `layout(fn, vs, tm)` already takes the metrics interface, so **the seam exists; only the implementation is missing.**                   | `layout.ts:1037`                                    | E1 _looking right_              |
| **S8**  | Palettes are baked into inline `fill=`/`stroke=` attrs. The VS Code webview themes off `--vscode-*`; a white-filled SVG is unreadable in a dark theme.                                                                                                                                                         | `ladder-svg/src/svg.ts:18`                          | Step 5                          |
| **S9**  | `lampsFor` exists but is **not exported**, and there is no local `verdictFor`. The IDE header today prints `evaluates to …` — the exact bare TRUE §25f condemns.                                                                                                                                               | `layout.ts:193`                                     | the point of the exercise       |
| **S10** | The `ANY OF` / `AND` annotations have no equivalent: ladder-core draws an OR heading only when a leading `InertE` supplies one. Modules without inert prose lose the tag.                                                                                                                                      | `layout.ts:289`                                     | product call                    |
| **S11** | Selection / paths-list is a **substitution, not a port**: ladder-core's answer (`expandSentences`) is a _text list_, not a graph highlight. Needs a decision before the old code is deleted.                                                                                                                   | `node-paths-selection.ts`                           | Step 8                          |

> **S0 (was: the blocker) — RESOLVED before this plan was written.** `ladder-core`'s
> `exports` promised `./dist/index.js` while `rootDir: "./"` emitted `dist/src/index.js`;
> the package entry point had never resolved, and E1 would have been its first runtime
> importer. Fixed in the G6/E4 split (`tsconfig.build.json`, both packages). This is the
> concrete payoff of splitting _before_ integrating rather than during.

---

## 2. Strangler-fig, not big-bang

Land `LadderSvg` as a **second displayer in the same package**, selectable by a toolbar
toggle in both apps, and delete `LadderFlow` only at the end.

1. **There is no green big-bang commit.** Both consuming apps import `LadderFlow`,
   `LirContext`, `LirRegistry`, `FunDeclLirNode`, `VizDeclLirSource`, `LadderEnv` _by name_,
   and reach into the LIR for query-plan refresh. A one-shot swap touches four packages and
   cannot keep `turbo run check test` green in the middle.
2. **§25f's own argument demands the comparison.** The claim is that the IDE shows a bare
   TRUE where the rule never reached the user. The cheapest possible proof is _the same
   statute, two renderers, one toggle._
3. **BBE has never met a real statute at scale.** ladder-core has been driven by the s415
   hand fixture and the playground; Dagre has been driven by every module anyone has ever
   opened. The old path is the insurance policy (see R1).
4. Dropping `@dagrejs/dagre`, `@xyflow/svelte`, `graphology*`, `array-keyed-map` and
   `@repo/layout-ir` is a real prize — but it is a **reward, not a prerequisite.** Take it last.

**The one thing not to do:** build `LadderSvg` on top of `LirContext`. §11 retires the LIR.
Extract a **LIR-free `LadderModel`** and let the old displayer keep its LIR until it dies.

---

## 3. Ordered steps

Each is one commit; each leaves `npx turbo run check test` green.

| Step  | What                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Size  |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| ~~0~~ | ~~`exports`/`rootDir` fix~~ — **done in G6/E4**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | ~~S~~ |
| **1** | **ladder-core: carry the identity the IDE needs.** `Leaf` gains optional `unique` + `canInline` (optional ⇒ every existing fixture still compiles). `DecodedViz` gains `nodesByUnique: Map<Unique, NodeId[]>` and `nodesByAtomId` — **plural**, because one atom can occupy several positions (R2). Export `lampsFor` and a pure `verdictFor(fn, valuation)`, with `Verdict` **re-exported from `@repo/boolean-analysis`** — one definition, not two. Test it against the same six-row table the Haskell and TS engines already assert.                                                                                                | S/M   |
| **2** | **ladder-svg: real metrics + a themeable palette.** `canvasMetrics()` (`measureText`-backed, memoised) — **this is TODO A4**, and it is what makes E1 look right rather than approximately right. Replace baked palettes with CSS custom properties, keeping default output byte-identical so the doc exhibits don't churn. _Parallelizable._                                                                                                                                                                                                                                                                                          | M     |
| **3** | **`LadderModel` — LIR-free.** A Svelte-5 `$state` class holding the raw viz `FunDecl` (evaluation tree) _and_ the decoded ladder tree (drawing tree), the `Assignment`, the id maps, the fold set. Derives `viewSpec` (valuation projected `Unique → NodeId[]`; `eliminable` from `PartialEvalAnalysis.irrelevantRootIds`; **`provenance` from `DecodedViz` — the first time TYPICALLY reaches the production component at all**) and `verdict`. Calls the **existing** `Evaluator` + `PartialEvalAnalyzer` on the **raw** FunDecl — **no `expandImplies`.** This is where §25f is repaired. Nothing renders it yet ⇒ trivially green. | M     |
| **4** | **The `LadderSvg` displayer.** `{@html sceneToSvg(layout(…))}` + **one** delegated click reading `data-value`/`data-fold`. Hand-rolled `viewBox` pan/zoom (~60 lines, no new dep — simpler under the webview CSP than `svg-pan-zoom`). Port the FLIP from `ladder-svg/standalone/app.ts:96`. Header shows the **verdict**, not `evaluates to …`. **Reuse `partial-eval-sidebar.svelte` as-is** — widen its prop to a structural interface (~5 lines) and the whole "Still Needed" panel comes along.                                                                                                                                   | L     |
| **5** | **The toggle in both IDEs** — the side-by-side commit. Make `getCurrentAtomBindings` / `refreshQueryPlan` / `setElicitationOverride` renderer-agnostic. Manual gate: open the s415 fixture **and a real IMPLIES module** in both renderers.                                                                                                                                                                                                                                                                                                                                                                                            | S/M   |
| **6** | **Close the gaps the side-by-side exposes.** Two mechanisms, both needed: **ink** (elicitation marks) → extend `ViewSpec` with `marks` + new `ScenePrim` tags; **chrome** (the `+`, tooltips, context menus) → an HTML overlay positioned from the `box` prims' `rect`s, read straight off the returned `Scene`. Real DOM, real bits-ui anchors.                                                                                                                                                                                                                                                                                       | M/L   |
| **7** | Flip the default; keep `LadderFlow` behind an escape hatch for one release.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | S     |
| **8** | **The deletion commit.** `displayers/flow/**`, `layout-ir/**`, `algebraic-graphs/**`, `data/viz-expr-to-lir.ts` (**the last `expandImplies` call site**), and five dependencies. Settle S11 first.                                                                                                                                                                                                                                                                                                                                                                                                                                     | M     |

≈ 3 L-equivalents. Critical path **1 → 3 → 4 → 5**; Step 2 runs in parallel.

---

## 4. What dies

The **bundling-node sandwich** (`viz-expr-to-lir.ts:372`) and the **anchor hack**
(`displayers/flow/layout.ts:70` — the `isSFBundlingNode ? don't-shift : shift-by-half-dimensions`
conditional that right-aligns everything). Both are pure Dagre artefacts. BBE has real ports.
Also: Zen mode's edge labels (there are no edges to label), and `expandImplies`'s last caller.

---

## 5. Risks

- **R1 (highest) — BBE layout quality on real statutes is unmeasured.** BBE is align-then-stack
  with no edge routing; a wide OR of long-prose leaves may blow the pane. **Cheap spike, and the
  tooling already exists:** drive `ladder-svg/standalone/serve.mjs` (the headless LSP bridge) over
  every `.l4` in `jl4/ok/**` and record `Scene.size`. **Run this before committing to Step 4** — a
  bad answer promotes scale-modes/auto-fold onto E1's critical path.
- **R2 — repeated atoms.** One `Unique` can sit at several `NodeId`s. A binding must fan out to
  _all_ positions or one diagram will show the same atom with two different values.
- **R3 — theming/CSP in the VS Code webview.** Unknown whether `{@html <svg>}` picks up the
  `--vscode-*` cascade and whether the CSP objects. Spike: one static Scene, dark theme, screenshot.
- **R4 — the paths-list is a substitution, not a port** (S11). Product call, or the feature
  silently vanishes at Step 8.
- **R6 — `App` leaves render flat** (S3): `first limb OF s, i` loses its arguments today. §23/D1 is
  the real fix. **Recommend shipping E1 without it** and taking D1 next.
- **R7 — an armed trap (see TODO G10).** `types.ts:98` promises nested `Implies` falls back to
  `¬P ∨ Q`; `layout.ts:627` sends _every_ `Implies` to `measureImplies` with no pre-pass. Unreachable
  only because the Haskell expands nested implications first. Fix the guard or fix the comment.
