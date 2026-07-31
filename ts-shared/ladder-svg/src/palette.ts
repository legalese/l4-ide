/**
 * Seam **S8** — the palette contract (E1-IDE-INTEGRATION.md:58).
 *
 * S8's complaint is that the colours are BAKED: `svg.ts` carried a seven-field `Palette` and
 * then hard-coded nineteen more colours as inline literals — at fourteen SITES, since
 * `svg.ts:41` carried three and `:59`, `:90` and `:113` two apiece — so "a widget pasted into a host
 * page whose colours we do not control reads as a foreign white rectangle"
 * (EMBEDDABLE.md §2). This file closes the contract half of that seam: every colour the emit
 * can produce is a named field, the palette is a PARAMETER of `sceneToSvg`, and
 * `DARK_PALETTE` is the second implementation that proves the parameter is real.
 *
 * What is deliberately NOT here, and why:
 *
 *   • **CSS custom properties.** Emitting `fill="var(--l4-box)"` would let a host restyle
 *     without a re-render, but E1-IDE-INTEGRATION.md:102 gives theming to **Step 2** with an
 *     explicit "keep default output byte-identical" constraint, and the doc-figure carriers
 *     under `jl4/examples/legal/regcf/figures/` are committed. Step 2's, not Step 4's.
 *   • **`theme: "auto"`.** EMBEDDABLE.md R8. A host that knows its own theme passes a
 *     `Palette`; sniffing `prefers-color-scheme` is the CSS-variable work above.
 *   • **The `--vscode-*` binding.** That is Step 5's file (the webview), not this package's.
 *
 * `Theme` in `ladder-core/src/types.ts` is deliberately NOT widened — it stays exactly
 * `"screen" | "ink"`, and `ViewSpec.theme` is untouched. A third look is reached by passing a
 * `Palette`, not by adding a string, which keeps every ladder-core golden and the layout
 * kernel out of the blast radius.
 */
import type { Theme } from "@repo/ladder-core";

/**
 * Every colour the SVG emit can produce — 26 fields, and `test/palette.test.ts` pins that
 * count because three specs quote it. The first seven were already a `Palette` in `svg.ts`;
 * the other nineteen were inline literals, and the comment on each says where it was baked.
 *
 * All of them are required. An optional field would let a caller hand over a half-palette
 * and silently inherit a light-theme literal into a dark diagram, which is precisely the
 * failure S8 describes.
 */
export interface Palette {
  /* --- the original seven (svg.ts:10-18) --- */
  /** A box/text that carries current. */
  live: string;
  /** A box/text that does not. */
  inert: string;
  /** Reserved for the dead state; equal to `inert` in both built-ins. */
  dead: string;
  /** Eliminable (DESIGN §15) — a rung that cannot matter. */
  ghost: string;
  /** The power rails. */
  rail: string;
  /** Body text. */
  ink: string;
  /** The backdrop rect. */
  bg: string;

  /* --- lifted out of inline literals, cited at their former sites --- */
  /** Fill of an eliminable box (was svg.ts:58). */
  eliminableFill: string;
  /** Fill of an ordinary box (was svg.ts:59). */
  boxFill: string;
  /** Fill of a folded group's placeholder box (was svg.ts:59). */
  placeholderFill: string;
  /** Connector reached by the leader (was svg.ts:41-42). */
  wireClosed: string;
  /** Connector closed locally but not yet reached (was svg.ts:41-42). */
  wireStreamer: string;
  /** Connector carrying nothing (was svg.ts:41-42). */
  wireOpen: string;
  /** A lit "complies" coil (was svg.ts:90). */
  coilGreen: string;
  /** A lit "in breach" coil (was svg.ts:90). */
  coilRed: string;
  /** An unlit coil's ring and label (was svg.ts:91). */
  coilOff: string;
  /** The inside of an unlit coil (was svg.ts:96). */
  coilHollow: string;
  /** The changeover pivot dot (was svg.ts:105). */
  glyphDot: string;
  /** Inside of the NOT bubble (was svg.ts:113). */
  inverterFill: string;
  /** Ring of the NOT bubble (was svg.ts:113). */
  inverterStroke: string;
  /** A fold frame's dashed outline (was svg.ts:118). */
  frameStroke: string;
  /** A fold frame's caption (was svg.ts:119). */
  frameLabel: string;
  /** The ▸ fold caret (was svg.ts:138). */
  caret: string;
  /** The MUST / ⇒ seam connective (was svg.ts:141). */
  seam: string;
  /** A TYPICALLY presumption's muted amber (was svg.ts:143). */
  typically: string;
  /** Tagged (non-body) text that is not otherwise special-cased (was svg.ts:149). */
  tagInk: string;
}

/** The default. Every value is the literal that stood at the cited site before S8, verbatim,
 *  which is what makes `sceneToSvg(scene)` byte-identical to its pre-S8 output. */
export const SCREEN_PALETTE: Palette = {
  live: "#1a7f37",
  inert: "#9aa0a6",
  dead: "#9aa0a6",
  ghost: "#b9bdc2",
  rail: "#3a3a3a",
  ink: "#222",
  bg: "#ffffff",
  eliminableFill: "#f6f7f8",
  boxFill: "#ffffff",
  placeholderFill: "#eef1f6",
  wireClosed: "#1b1b1b",
  wireStreamer: "#7c828a",
  wireOpen: "#d6dadd",
  coilGreen: "#1a7f37",
  coilRed: "#c0392b",
  coilOff: "#c9ced3",
  coilHollow: "#ffffff",
  glyphDot: "#3a3a3a",
  inverterFill: "#ffffff",
  inverterStroke: "#1b1b1b",
  frameStroke: "#b3b7bb",
  frameLabel: "#8a9096",
  caret: "#7a7f85",
  seam: "#1b1b1b",
  typically: "#9a7b34",
  tagInk: "#555",
};

/**
 * The print look. Exactly the same six overrides `svg.ts` applied before S8 — no more, no
 * fewer — so the committed doc figures do not move.
 *
 * **Known wart, preserved deliberately.** It inherits the chromatic `coilGreen`/`coilRed`,
 * so a lit coil prints in colour even in the "ink" theme. It did that before S8 too, because
 * those literals never went through the palette at all. Fixing it re-bytes the print
 * figures, which is Step 2's business, not Step 4's — recorded in S8's row.
 */
export const INK_PALETTE: Palette = {
  ...SCREEN_PALETTE,
  live: "#222",
  inert: "#555",
  dead: "#555",
  ghost: "#999",
  rail: "#222",
  ink: "#111",
};

/**
 * A dark look — S8's row names exactly this case ("a white-filled SVG is unreadable in a
 * dark theme"). It exists because a contract with one implementation is not a contract: it
 * is what proves the parameter is load-bearing, and it is what Track E imports today rather
 * than waiting for Step 2's CSS variables.
 */
export const DARK_PALETTE: Palette = {
  live: "#4ec97a",
  inert: "#8b9096",
  dead: "#8b9096",
  ghost: "#5a6068",
  rail: "#b9bdc2",
  ink: "#e6e6e6",
  bg: "#1e1f22",
  eliminableFill: "#24262a",
  boxFill: "#26282c",
  placeholderFill: "#2f333a",
  wireClosed: "#e6e6e6",
  wireStreamer: "#9aa3ad",
  wireOpen: "#4a4f57",
  coilGreen: "#4ec97a",
  coilRed: "#f0715e",
  coilOff: "#4a4f57",
  coilHollow: "#1e1f22",
  glyphDot: "#c9ced3",
  inverterFill: "#1e1f22",
  inverterStroke: "#e6e6e6",
  frameStroke: "#4a4f57",
  frameLabel: "#8b9096",
  caret: "#9aa3ad",
  seam: "#e6e6e6",
  typically: "#d6b56a",
  tagInk: "#a8adb3",
};

/* ------------------------------------------------------------------------------------
 * END OF PALETTES — no colour literal may appear below this line, and none may appear in
 * `svg.ts` at all. `test/palette.test.ts` scans both files for that and fails if a colour
 * gets re-baked, which is the only durable way to keep this seam closed.
 * ---------------------------------------------------------------------------------- */

/** Resolve the `theme` option: a built-in name, or a caller's own `Palette` passed through. */
export const paletteFor = (t: Theme | Palette): Palette =>
  typeof t === "string" ? (t === "ink" ? INK_PALETTE : SCREEN_PALETTE) : t;
