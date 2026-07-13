/** @repo/ladder-core — pure IRExpr -> BBE -> Scene IR, plus the shared SVG emit
 *  (the latter to be split into @repo/ladder-svg per DESIGN §12). */
export * from "./types.js";
export { layout, estimateMetrics, PIXEL_GEOMETRY } from "./layout.js";
export type { Geometry } from "./layout.js";
export { sceneToSvg } from "./svg.js";
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
