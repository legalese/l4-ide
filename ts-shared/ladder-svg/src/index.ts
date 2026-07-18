/** @repo/ladder-svg — the SVG rendering backend (DESIGN §12, split out of
 *  `ladder-core` per §13.1 / task G6).
 *
 *  The seam is the **Scene IR** (§4.2): this package consumes `Scene` and emits
 *  SVG, and knows nothing about `IRExpr`, BBE, or layout. That is why the import
 *  from `@repo/ladder-core` below is `import type` — at runtime this package has
 *  no dependency on the layout engine at all. Anything that can produce a `Scene`
 *  can render through here; anything that can consume a `Scene` (ASCII, Mermaid)
 *  is a peer, not a subclass. */
export { sceneToSvg } from "./svg.js";
export { canvasMetrics } from "./metrics.js";
export type { CanvasMetricsOpts } from "./metrics.js";
export type { Theme } from "@repo/ladder-core";
