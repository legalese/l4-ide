/** @repo/ladder-core — pure IRExpr -> BBE -> Scene IR (DESIGN §4.2). No DOM, no
 *  rendering backend: the Scene IR is where this package stops.
 *
 *  SVG lives in `@repo/ladder-svg` (split out per §13.1 / G6). ASCII and Mermaid
 *  stay here because they are *text carriers* for the doc pipeline (§24) with no
 *  sink to speak of — but they are peers of the SVG emit, not part of the core:
 *  all three consume `Scene` and nothing else. */
export * from "./types.js";
export {
  layout,
  estimateMetrics,
  PIXEL_GEOMETRY,
  verdictFor,
} from "./layout.js";
export type { Geometry, Lamps } from "./layout.js";
/** The verdict vocabulary is defined ONCE, in `@repo/boolean-analysis` (the "what a
 *  wizard may tell a user" module), and re-exported here so ladder-core's `verdictFor`
 *  and the wizard's `queryDecision` name the same six values — §E1/S9. */
export type { Verdict } from "@repo/boolean-analysis";
export {
  sceneToAscii,
  monoMetrics,
  ASCII_GEOMETRY,
  CELL_W,
  CELL_H,
} from "./ascii.js";
export type { AsciiOpts } from "./ascii.js";
export { toMermaidRailroad } from "./mermaid.js";
export type { MermaidOpts } from "./mermaid.js";
export { fromVizFunDecl, fromVizExpr } from "./viz-adapter.js";
export type { DecodedViz } from "./viz-adapter.js";
export { expandSentences } from "./sentences.js";
