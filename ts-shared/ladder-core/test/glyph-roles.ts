/**
 * One definition of "a glyph the layout no longer emits", shared by every test that asserts
 * no open-contact break is drawn.
 *
 * The `open-contact` role is gone from `ScenePrim` (Meng, 2026-11-27: "yeah, get rid of the
 * open switch on the eliminable too."), so a test cannot compare a role against it and still
 * compile, and a test that compared a string would pass for a typo or a rename. Counting the
 * glyphs whose role is NOT one of the three the layout still emits catches a break
 * reinstated under any name.
 */
import type { ScenePrim } from "../src/index.js";

export type Glyph = Extract<ScenePrim, { kind: "glyph" }>;

/** The glyph roles `layout` still emits. */
export const KNOWN_GLYPH_ROLES: readonly string[] = [
  "power-terminal",
  "inverter",
  "changeover",
];

/** Every glyph whose role is not one of them: a break, however it is named. */
export const unknownGlyphs = (prims: readonly ScenePrim[]): Glyph[] =>
  prims.filter(
    (p): p is Glyph =>
      p.kind === "glyph" && !KNOWN_GLYPH_ROLES.includes(p.role),
  );
