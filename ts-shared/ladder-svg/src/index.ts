/** @repo/ladder-svg — the SVG rendering backend + the interaction controller
 *  (DESIGN §12, split out of `ladder-core` per §13.1 / task G6; controller added in
 *  E1 Step 4 per EMBEDDABLE.md §3).
 *
 *  The seam is the **Scene IR** (§4.2), and it is the EMIT that honours it: `svg.ts`
 *  imports `@repo/ladder-core` with `import type` only, so the rendering backend carries no
 *  runtime dependency on the layout engine. Anything that can produce a `Scene` can render
 *  through it; anything that can consume a `Scene` (ASCII, Mermaid) is a peer, not a
 *  subclass.
 *
 *  `controller.ts` is the deliberate exception, and the reason is written down in
 *  EMBEDDABLE.md §3.2: layout is parameterised by `TextMetrics`, so putting it host-side
 *  makes every consumer re-write the same three lines and pick its own metrics backend.
 *  The controller therefore imports `layout` as a VALUE. An importer of `sceneToSvg` alone
 *  still pulls no layout code — bundlers tree-shake the controller away — but it is no
 *  longer true that the package as a whole has none, and that sentence used to live here. */

/** The emit, and seam S8's palette contract. */
export { sceneToSvg } from "./svg.js";
export {
  paletteFor,
  SCREEN_PALETTE,
  INK_PALETTE,
  DARK_PALETTE,
} from "./palette.js";
export type { Palette } from "./palette.js";

/** Browser text metrics (E1 Step 2 / TODO A4). */
export { canvasMetrics } from "./metrics.js";
export type { CanvasMetricsOpts } from "./metrics.js";

/** The interaction controller (E1 Step 4 / Track E's E0). */
export { LadderController, actFromAttrs } from "./controller.js";
export type { LadderControllerOpts } from "./controller.js";

/** Seam S6's pure arithmetic — exported because it is part of the tested surface, and
 *  because a host that draws its own minimap or scrollbars needs the same maths. */
export {
  boxAt,
  clampBox,
  fitBox,
  panBy,
  refit,
  scaleOf,
  viewBoxAttr,
  zoomAt,
  CLAMP_MARGIN,
  DEFAULT_LIMITS,
  FIT_PAD,
} from "./viewport.js";
export type { Box, Size, ZoomLimits } from "./viewport.js";

/** The FLIP's pure half. */
export { flipIndex, flipKeyFor, flipMoves } from "./flip.js";
export type { FlipKey, FlipMove, Pos } from "./flip.js";

export type { Theme } from "@repo/ladder-core";
