# Ladder Diagrams — remaining workplan

_Scratch planning file for the ladder-diagrams-2026 effort. **Not committed** (working-tree only).
Canonical design lives in `specs/todo/ladder-diagrams-2026/DESIGN.md`; its §14 is the status board.
Last reoriented: 2026-07-15._

---

## 0. Where we are (post-#96, post-#116-MERGED, post-§25, post-E1-Steps-1–3)

- **PR #96 is MERGED into `unstable`.** The foundation: the pure BBE `ladder-core` (P0
  kernel), the standalone interactive page (target C), and the visual language §15–§22
  (ELIMINABLE, folding, unboxed inert, Bézier fan, valuation/override, leader+streamer
  current flow, NOT, TYPICALLY defaulted-vs-given).
- **PR #116 is MERGED into `unstable`** (2026-07-18, merge commit `5bde53da`, via the merge
  queue). It carried everything on this branch: the **viz-expr adapter** (A1), the
  **TYPICALLY→provenance consumption** (B1) + real-module test (B2), the **IDE-free L4→ladder
  playground** (A2 transport), the **sentence expander**, the **ASCII + Mermaid carriers**
  (§24), the whole **IMPLIES seam** (§25, task **J**), the **`ladder-svg` split** (E4/G6),
  the **R1 corpus spike**, and **E1 Steps 1 / 2-metrics / 3** — the identity + `verdictFor`,
  `canvasMetrics`, and the LIR-free `LadderModel`. Plus the §18 Bézier-thrust tuning.
- **⚠ This worktree branch is now STALE.** After the #116 merge, `mengwong/ladder-diagrams-3`
  is **0 ahead / 55 behind `origin/unstable`** — fully merged, nothing unpushed. Those 55
  commits are unrelated parallel work (set-operators #133, fixity #128/#131, library-resolution
  #134, l4-papers #132). **H2 is now forced:** cut a fresh branch off `origin/unstable` for
  E1 Step 4+ rather than continuing on this dead branch (see §H2).
- **PR #110 is MERGED** — the shared TYPICALLY wire field + both extractors (Haskell
  `VizExpr.hs` `UBoolVar` 6th field, TS `viz-expr.ts` `typically`, the shared
  `typicallyBridge`). The "build once, do not duplicate" bridge exists; we consume it.
- Repo-level FYI: **PR #112 reverted mengwong's direct-to-main changes (Jun 23 – Jul 10)**
  pending review; #113/#114/#115 are the reapply-for-review PRs into `main`. Nothing on this
  branch ever went direct-to-main, so this is unrelated — but some previously-merged work is
  currently backed out of `main`.

**The live gap now:** the production Svelte component (`l4-ladder-visualizer`) is still on
the old Dagre/SvelteFlow path. Everything below the IDE seam is real; the IDE seam is not
crossed. See task **E** — and note §25 has now given **E1 a second, sharper reason to exist**:
the old visualizer runs `expandImplies` at its entry point, so it _cannot draw the two lamps_
and an IDE user still sees a bare TRUE where the rule never reached them.

---

## 1. Priority ladder (what to do, in order)

1. **E — P3 IDE integration.** _Now the biggest unlock_ — A is essentially done, so this is
   the actual ship (replace the Dagre path; jl4-web + VS Code). §25 raised its stakes: the
   verdict is now computed and on the wire, and the old renderer is the only thing that can't
   show it.
2. **I — GFM/Markdown embedding.** Make ladders embeddable in GitHub-flavoured Markdown so the
   docs (e.g. `doc/concepts/language-design/logic-not-flowcharts.md`) can _show_ the ladder they
   argue for. **Mostly shipped** (§24: ASCII + Mermaid carriers) — what remains is **I-a**, the
   CI-checked regeneration so the doc's exhibits cannot drift from the generator.
3. **C — scales + minimap** and **D — predicate leaves** and **F — print** — parallel
   enhancements.
4. **G — visual-language follow-ups.** Small, independent; pick up opportunistically.

---

## A. P2 — Live LSP data _(biggest unlock; no hard blocker)_

Render **real statutes**, not just the s415 fixture. Decode the viz-expr wire IR from the
LSP into ladder-core's `IRExpr`.

- [x] **A1.** Map `@repo/viz-expr` schema → ladder-core `IRExpr`. They're structurally
      near-identical (P0 kept a local mirror deliberately). Reconcile the `label?` /
      `NamedExpr` difference (see G5) and the `App` shape (see D).
      → **DONE** (2026-07-10): `ts-shared/ladder-core/src/viz-adapter.ts` — `fromVizFunDecl` /
      `fromVizExpr`, type-only import of `@repo/viz-expr` (no runtime dep; standalone bundle
      unchanged at 28.7kb). Exhaustive switch over all 8 wire node kinds; ids preserved;
      `Name.label`→`label`, `App`→flat leaf carrying `atomId`+`fnName` (interior deferred to
      D1); And/Or `label` left undefined pending NamedExpr (G5). Tests: `test/viz-adapter.test.ts`
      (6 cases, `npm test`), tsc clean, prettier clean, adversarially reviewed (no bugs; test
      gaps closed). Added `@repo/viz-expr` dep + `test` script to ladder-core `package.json`.
- [x] **A2.** LSP transport — **DONE (2026-07-11), via the playground bridge** rather than
      the originally-planned in-IDE path. `standalone/serve.mjs` connects to (or spawns) a real
      `jl4-lsp` over websocket and runs the visualize capture — initialize → didOpen → codeLens →
      `executeCommand "Show decision graph"` — exposing `POST /render {l4}` that returns every
      decision's `RenderAsLadderInfo.funDecl`. So we render **real L4** headlessly, no SvelteKit /
      Monaco / webview. _Still unconsumed: `l4/evalApp`, `l4/inlineExprs`, `l4/queryPlan` (DESIGN
      §11 "Keep") — the interactive eval round-trip; see E2._
- [~] **A3.** Feed `ViewSpec.valuation` / `states` from real eval results (positional by
  node id; leaf values by atomId — DESIGN §15.2).
  → _decode-side DONE in A1: `fromVizFunDecl` returns a `valuation` map lifted from each
  `UBoolVar.value` (UnknownV omitted; TrueE/FalseE keep inherent values). Merging LIVE
  eval results still needs the `l4/evalApp` round-trip (E2)._
- [ ] **A4.** Swap the P0 estimator `TextMetrics` for the real browser Canvas
      `measureText` in the live path (keep the estimator for headless/tests).
- Fixture already vendored: `jl4/ok/inert/cheating-415-poh-yuan-nie.l4`.

## B. viz-expr TYPICALLY wiring — §22 real data _(SHARED with `../typically`; rides on A)_

Populate `ViewSpec.provenance` from the real L4 TYPICALLY instead of injected demo data.
**The bridge itself is owned by the `typically` v2 session** ("build once — do not
duplicate", their spec §8), and it has now **landed** as PR #110 — the single shared wire
field + both mirrored extractors:

- [x] Haskell + TS wire threading = **v2's PR #110** (`mengwong/question-ordering-v2`):
      `VizExpr.hs` `UBoolVar` 6th field `Maybe Bool` (+ shared `boolPriorsFromBody`); both
      `Ladder.hs` producers via one exported `collectTypicallyDefaults`; `viz-expr.ts`
      `typically: Schema.optional(Schema.NullOr(Schema.Boolean))` + the shared `typicallyBridge`
      (emits weights **and** provenance in one walk). → **not our work — we RETRACTED our own
      duplicate threading (2026-07-10) and rebased onto #110** so there is one wire, not two.
      JSON key `"typically"`, always-emit (`null` when absent), `.:?` decode.

Ladder-side work that remains ours (the ladder-core adapter #110 explicitly deferred):

- [x] **B1.** **Consume** the shared wire field in the A-decode path — done in
      `ts-shared/ladder-core/src/viz-adapter.ts`: `convert` threads a second side-channel
      `provenance: Map<NodeId, Provenance>`, populated in the `UBoolVar` case by
      `if (e.typically === true || e.typically === false) provenance.set(e.id.id, "default")`
      (a concrete boolean, NOT mere presence — #110's nullable schema means non-presumed atoms
      arrive as `null`, which must not be read as a default; a `false` default is still a
      default). `DecodedViz` returns it; host call site is `defaultViewSpec({ valuation,
provenance })`. Rendering already done (#96 §22: tentative box + `typically` tag +
      streamer-cap). → **DONE (2026-07-10); rebased clean onto #110.**
- [x] **B2.** Ladder integration test on a **real** TYPICALLY L4 module — **DONE
      (2026-07-10)**: `test/viz-adapter.real-module.test.ts` against
      `test/fixtures/may-purchase-alcohol.viz.json`, a viz payload captured from the live LSP
      producer, proving the tentative marks land on genuinely-defaulted atoms (not just the
      hand-fed s415 demo). Complements the adapter-level round-trip in `viz-adapter.test.ts`.
- [ ] **B3.** (stretch) Model the full `Either (Maybe Bool)(Maybe Bool)` four cells, incl.
      `Left Nothing` (never asked) vs `Right Nothing` (confirmed don't-know) — see G3. _Confirm
      with the `typically` session first: the four-cell distinction may belong in the shared bridge._

## C. §7 scales + minimap _(P1 remaining; independent)_

- [ ] **C1.** Full / Small / Tiny scale modes (`ViewSpec.scale`; already in the type).
- [ ] **C2.** The **Tiny minimap** that stays fully expanded while the main view folds
      (DESIGN §16 "heuristics & persistence").
- [ ] **C3.** Fold heuristics: auto-fold beyond depth N; "focus mode" folds siblings.

## D. §23 predicate leaves — the membrane _(designed, not built)_

> **The R1 spike (see E0) just made D1 the highest-value item in this task.** It is not
> cosmetic. A `CONSIDER` or `BRANCH` currently collapses into ONE leaf whose label is the
> whole expression's source text — so a decision table renders as a 4372px unreadable
> ribbon. The membrane is what draws it as a table instead of a paragraph in a box.

- [ ] **D1.** Render an `App` leaf **"drawn open"**: `fnName` → outer predicate band
      (carries T/F/U), literal arg → inner value chip. Not a new node — it's the existing
      `App`, just rendered with its interior (DESIGN §23; cf. the `enhance/ladder-expressions`
      ExactPrint technique in §11 salvage).
- [ ] **D2.** Value/type metadata on the leaf: injected first, then from viz-expr `App` args.
- [ ] **D3.** Static fixture: `age = 21` chip inside a `≥ 18?` band.
- [ ] **D4.** Wire `Default a` (§22 provenance) onto the value chip — a defaulted chip
      (`age TYPICALLY 18`) renders tentative _inside_ the membrane. This is also the visual
      explanation of the wizard's Boolean-only wrinkle.
- v1 chip is **display-only**; live typed-value editing is a P3 web affordance.

## E. P3 — IDE integration _(the ship; rides on A)_

> **SCOPED** — the full plan is now a tracked doc:
> `specs/todo/ladder-diagrams-2026/E1-IDE-INTEGRATION.md` (8 steps, strangler-fig, ≈3 L).
> Two things it established: (1) **the eval brain is already seam-ready** — `expandImplies`
> has exactly ONE call site in the repo's app code (the Dagre entry point) while `eval.ts` /
> `partial-eval.ts` already carry `Implies` arms, so feeding the RAW viz FunDecl to the
> existing evaluator gets the §25f seam end-to-end for free; (2) **the R1 spike is done and
> BBE survives the corpus** — see below.

- [x] **E0 / R1 spike — DONE.** `ts-shared/ladder-svg/spike/corpus-sizes.ts`: every decision in
      the corpus (313 files, **442 decisions**) through `jl4-lsp → fromVizFunDecl → layout`.
      **Verdict: BBE survives; Step 4 is go.** OR fan-out maxes at **8**; worst compound diagram
      (s415 `second limb`) is 2866×444 — ~3× a pane, pannable. Heights are trivial (max 636).
      **The predicted pathology — a wide OR of long prose blowing the pane — does not occur**, and
      scale-modes/auto-fold stay OFF the critical path.
      **But it found a different problem:** 17 of the 22 widest diagrams have exactly **one leaf**.
      Every non-boolean construct (`CONSIDER`, `BRANCH`) collapses to a single leaf labelled with
      the **raw L4 source** — 38 labels in the corpus contain a literal newline — and BBE/SVG does
      not wrap. `is adult` (legal-persons.l4) is a **4372×180 single-line ribbon** containing a whole
      decision table. See **E5** and **D1**.
- [ ] **E5. Leaf-label wrapping/elision** — _promoted into E1 (Step 2, next to the metrics work)_.
      Wrap to N lines and grow the box height, or elide with the full text on hover. **Possible
      regression vs Dagre**, whose nodes are HTML `<div>`s that wrap for free — so the old renderer
      may handle these gracefully today. Unverified; the Step 5 side-by-side is what will show it.
- [~] **E1 — IN PROGRESS.** Steps 1, 2-metrics, 3 shipped (`d3651fdb` `0ae4c39b` `a2dfb72c`
  `be6cd2fa`): ladder-core carries the evaluator's identity + `verdictFor` (adversarially
  reviewed → sound-not-complete contract); `canvasMetrics` (A4); and **`LadderModel`** — the
  LIR-free, framework-free brain that feeds the RAW wire FunDecl to the existing Evaluator +
  PartialEvalAnalyzer, so the §25f seam survives to the verdict with no `expandImplies`. Next:
  **Step 4** (the `LadderSvg` Svelte displayer — first browser-dependent step). Full plan +
  status: `specs/todo/ladder-diagrams-2026/E1-IDE-INTEGRATION.md`.
- [ ] **E1 (original).** Replace the Dagre/SvelteFlow path in `ts-shared/l4-ladder-visualizer`
      (`displayers/flow/**` — the bundling-node sandwich + anchor hack that right-aligns)
      with `ladder-core` + `ladder-svg`. Note (per `../typically/TODO.md`): this production
      Svelte package currently has **no provenance concept at all** (`ladder.svelte.ts` builds
      `PartialEvalAnalyzer` from bare `IRExpr`) — so the shared bridge (task B) feeds provenance
      in here for the first time.
- [ ] **E2.** Restore eval / inline-expr interactivity through the new core.
- [ ] **E3.** Ship to jl4-web and the VS Code webview.
- [x] **E4 / G6. `ladder-svg` package split — DONE** (`0ad98784`). Done _before_ E1 rather
      than during it, which turned out to matter: being the first cross-package consumer of
      `ladder-core` is what revealed that **`ladder-core`'s package entry point had never
      resolved** (`exports` promised `dist/index.js`; `rootDir: "./"` emitted `dist/src/index.js`).
      E1 would have met that from Svelte, where it would have looked like a Vite bug. Both
      packages now build via `tsconfig.build.json` (emit `src/` only) while `tsconfig.json`
      still typechecks `demo/`/`test/`/`standalone/`. The emit also got its first **9 tests**
      (§25.4 lamps, XML escaping, §20 flow weights, §22-vs-§15 dashes, the `data-*` host
      contract). Seam = the Scene IR: `ladder-svg`'s only import from core is `import type`,
      so at runtime the renderer does not depend on the layout engine. ASCII + Mermaid stay
      in core as the §24 text carriers. `turbo check test` 28/28.

## F. P4 — Print pipeline _(no hard blocker; font parity is the real task)_

- [ ] **F1.** `ladder-print` Node CLI: `ViewSpec` → SVG string → PDF (the seam already exists).
- [ ] **F2.** **Font parity** — real headless metrics via fontkit/opentype.js on the
      SAME font as the browser's Canvas `measureText` (DESIGN §4.4 / §8). Without this, print
      geometry drifts from screen.
- [ ] **F3.** A3+ page fitting: scale `viewBox` to printable area, fixed margin; optional
      tiling across sheets for large trees.
- [ ] **F4.** **The poster (target D):** the two-panel surplusage diff (s415 court vs
      applicants) as a stakeholder-grade A3 print. `demo/s415.ts` `diff()` already composes it.

## G. Visual-language follow-ups _(small, mostly independent)_

- [ ] **G1.** §20 **backward sink pass** — distinguish a genuinely COMPLETE source→sink
      path from a merely partial one (leader + streamer can't today).
- [ ] **G2.** §22 **propagate tentativeness along the leader** — a segment _downstream_ of
      a presumed contact should read provisional too (today only the presumed leaf's own
      adjacent connectors cap).
- [ ] **G3.** §22 distinguish `Left Nothing` (never asked) vs `Right Nothing` (confirmed
      don't-know) — both grey today; the latter is a settled fact the wizard shouldn't re-ask.
- [ ] **G4.** §17 **N-line straddle** for long statutory clauses + trailing inert as a
      `Post` below a group.
- [ ] **G5.** §13.4 / §16.1 **`NamedExpr` wrapper** for legible subtree fold labels
      (Tier 2) — already stubbed in `viz-expr.ts` (~L198); populate Haskell-side from the
      inlined DECIDE / `Where` name (ties to the NLG round-trip work).
- [x] **G6.** §13.1 split **`ladder-svg`** out of `ladder-core` — **DONE**, see **E4**.
- [ ] **G10. Latent: the nested-`Implies` guard is documented but not implemented.**
      `ladder-core/src/types.ts:98` promises that a nested `Implies` "falls back to the
      `¬P ∨ Q` expansion", but `layout.ts:627` sends **every** `Implies` to `measureImplies`
      with no pre-pass — it would draw lamps mid-tree. Unreachable today _only_ because the
      Haskell expands nested implications before they reach the wire
      (`jl4-core/src/L4/Viz/Ladder.hs:392-398`), so ladder-core's own contract is currently
      a lie that any hand-built fixture could cash. Either add the guard in `fromVizExpr`
      (defence in depth, and makes the comment true) or correct the comment. Do not leave
      the trap armed. Found while scoping E1.
- [ ] **G7.** Wire **NOT** (§21) into the interactive standalone — s415 has no NOT, so it
      needs a dedicated fixture.
- [ ] **G8.** **TB orientation** — the kernel is LR-only today (`ViewSpec.orient` exists).
- [ ] **G9.** **Live browser verification** of the standalone (fold/cycle/FLIP, current
      flow, tentative marks) — never verified interactively (only via rsvg PNG). Screenshot
      the fold + T/F/U cycle + defaults render.

## I. GFM / Markdown embedding _(§24; mostly SHIPPED)_

Make a ladder embeddable in GitHub-flavoured Markdown, so `logic-not-flowcharts.md` (and the
rest of `doc/`) can **show** the picture it argues for — and so a ladder can travel in a PR
comment, an issue, a README. See DESIGN §24.

- [x] **I1.** Strategy decided (§24): **two carriers**, because GFM will not run our code.
      **ASCII** in a code fence (survives anywhere, carries _state_ — current, T/F/U, lit lamps),
      and **Mermaid** (renders natively on GitHub, carries _structure_ only).
- [x] **I2.** Both built in `ladder-core`: the ASCII renderer and `toMermaidRailroad`.
- [x] **I3.** Ladders backfilled into `logic-not-flowcharts.md` — the GPDO window rule, exactly
      the specimen this task wanted: a material conditional over two AND/OR trees, now drawn with
      the seam and the two sinks it took §25 to earn.
- [ ] **I-a.** _(open)_ The doc's ASCII/Mermaid exhibits are **hand-spliced** into the Markdown.
      They come from one generator (`demo/ascii.ts` emits both), but nothing stops them drifting
      from it. Owed: a CI-checked regeneration.

## J. §25 — the IMPLIES seam _(SHIPPED; the newest and largest slab on this branch)_

`P IMPLIES Q` is **not** sugar for `NOT P OR Q`. The expansion is truth-functionally perfect
and **shape-destroying**: it discards the scope/requirement split, and it cannot tell **N/A**
(the rule never reached this case — vacuously TRUE) from **complies**. _Same value; different
ink._ Design: DESIGN §25 (§25f is the wizard half).

- [x] **J1 (§25a).** `Implies` in the wire IR (`VizExpr.hs` + `viz-expr.ts`) and in both
      ladder translators. `translateExpr` now **peels the top-level implication before
      `Transform.simplify` runs** and simplifies each side on its own — simplification is a
      readability win _inside_ a panel and a shape-destroyer _across_ the seam. Previously the seam
      was destroyed **two** ways: `simplify` rewrote it, and with simplify off it fell through to
      `leafFromExpr` and became **one opaque box**. `expandImplies` is the deliberately-lossy escape
      hatch for the seam-free consumers. Pinned in `jl4/tests/VizImplies.hs`.
- [x] **J2 (§25b–d).** `ladder-core`: the `Implies` node, `measureImplies`, three-valued flow,
      the **changeover** (one pole, two throws) into a **green** coil (complies) and a **red** one
      (in breach). **No bypass ink** — vacuity is a STATE, not a PATH — so N/A is "neither lamp lit".
      Emitters: ASCII, SVG, Mermaid `sequence(P, IMPLIES, Q)`, never `optional()`.
- [x] **J3 (§25e).** Keep the drafter's spelling (`IMPLIES` vs `=>`) on the seam. **Attempted and
      defeated, and the reason is kept**: the typechecker desugars every binop into a function
      application and `annoNoFunName` rebuilds the annotation as two bare holes, destroying the
      operator token. Always emits `IMPLIES`; a test pins it so it fails loudly if anyone ever
      teaches the desugarer to preserve concrete syntax.
- [x] **J4 (§25f).** **The seam in the WIZARD.** The recorded finding ("don't _report_ a vacuous
      TRUE as complies") was an under-diagnosis. The real one:

  > **The classical short-circuit is valid only if you are computing a truth VALUE.** For a
  > **verdict**, a met requirement does not settle it — you must still establish the scope,
  > because _"the rule never reached you"_ and _"you comply"_ are different answers.

  So the planner didn't merely mislabel the vacuous case: with `requirement = TRUE` and the scope
  open, support went **empty** and the interview **stopped**, with the one distinguishing question
  unasked. Built: `BImplies` in both BDD engines (classical in the diagram, **two sides kept as
  roots of their own**); a `Verdict` (`Undetermined | Holds | Fails | Complies | InBreach |
NotApplicable`) on the query plan and on every impact preview; support computed against the
  **verdict**; info-gain measured about the verdict (`H(scope) + P(scope)·H(req)`) — without which
  the ranking goes blind exactly when the fix needs it. `determined` stays, correct and unchanged.
  The verdict table is `lampsFor`'s table, asserted in both runtimes.

- [ ] **J5.** _(open, small)_ The old `l4-ladder-visualizer` sidebar can now show `Still Needed`
      atoms while its own `overallResult` reads TRUE (the extra scope questions §25f introduced). Not
      false — the value _is_ TRUE and those questions _are_ worth asking — but that panel has no
      vocabulary for the verdict and so cannot explain why. Subsumed by **E1**; not worth a
      retrofit into a renderer we are replacing.
- [ ] **J6.** _(open, deferred by design — §25.5)_ **Regulative / "must do" rules.** The ladder
      renders their **guard** for free and then **stops**, handing the obligation to a statechart
      view. Their consequent is a whole transition system, not a coil; drawing it as one would be the
      very category error this project exists to name.

## H. Housekeeping

- [ ] **H1.** Decide storage for the `tmp/` PDFs (the box-model + and/or-tree spec PDFs;
      still deliberately untracked pending a binary-storage decision).
- [x] **H2. DONE (2026-07-25).** `mengwong/ladder-diagrams-3` went 0-ahead / 55-behind after
      #116 merged, so the tracker updates (this file's §0, DESIGN §14, the E1 doc header) were
      carried onto a fresh branch off `origin/unstable` —
      **`mengwong/lexipedia-superset`** — which also carries the new programme spec at
      `specs/todo/lexipedia-superset/`. E1 Step 4+ resumes from there or from a sibling branch
      off `origin/unstable`. The stale `ladder-diagrams-3` worktree can now be retired.
- [x] **H3.** ~~Pre-existing prettier failures~~ — **DONE** (`07ff7742`, its own commit so the
      ~650 lines of formatting churn stayed out of the substantive diff). Every _tracked_ file now
      passes `prettier --check .`; the only remaining warnings are on untracked scratch (`tmp/`,
      this file).

---

## Dependencies at a glance

```
A (live data)  ──DONE──►  B (shared provenance consumed)  ──DONE──►  [typically v2 bridge = PR #110, MERGED]
      │
      ├──► J (§25 IMPLIES seam)  ──DONE──►  the verdict is computed, on the wire, and drawable
      │         │
      │         └──► E1 now has TWO reasons: the old renderer can't draw the two lamps (J5)
      │
      └──► E4/G6 (ladder-svg split)  ──DONE──►  E1 (IDE integration)   ← THE critical path
                                                 └──► E2 (interactivity) ──► E3 (ship)
I (GFM embedding) — SHIPPED (§24, two carriers). I-a (CI-checked regeneration) remains;
    I-c (interactive VS Code Markdown preview) was blocked on the split, now unblocked.
C, D, F, G  — independent (D/F prefer A's App-decode + real metrics; can prototype on injected data)
J6 (regulative rules) — deliberately NOT on this path: it wants a statechart view, not a coil.
```
