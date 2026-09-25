/** viewport.ts — seam S6's arithmetic.
 *
 * This is the riskiest new code in Step 4: it has no incumbent, and zoom-at-cursor is the
 * classic place to acquire an off-by-an-offset that nobody notices until a user complains
 * that the diagram "runs away" under the pointer. It is also the cheapest thing in the step
 * to get provably right, because it is pure — hence this file, and hence the split that put
 * the arithmetic in `viewport.ts` rather than inside the controller.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CLAMP_MARGIN,
  DEFAULT_LIMITS,
  boxAt,
  clampBox,
  fitBox,
  panBy,
  refit,
  scaleOf,
  viewBoxAttr,
  zoomAt,
} from "../src/viewport.js";
import type { Box, Size } from "../src/viewport.js";

/** A deliberately NON-SQUARE viewport: a square one hides an axis swap. */
const VP: Size = { w: 800, h: 500 };
/** A wide diagram, like the corpus's tail (R1 spike: p99 2882px). Tall enough that the
 *  vertical axis is genuinely pannable at the zoom levels below — a short content centres
 *  vertically under `clampBox` and would make half these assertions vacuous. */
const CONTENT: Size = { w: 2400, h: 1400 };

const near = (a: number, b: number, eps = 1e-9, msg?: string) =>
  assert.ok(
    Math.abs(a - b) <= eps,
    msg ?? `expected ${a} ≈ ${b} (Δ=${Math.abs(a - b)})`,
  );

/** THE invariant: hold it and `preserveAspectRatio` never letterboxes, so there is no
 *  offset term anywhere in the content↔screen mapping. */
const assertAspect = (vb: Box, vp: Size, what: string) =>
  near(vb.w / vb.h, vp.w / vp.h, 1e-9, `${what} broke the aspect invariant`);

/* --------------------------------------------------------------------------- fitBox */

test("fitBox shows all of the content, centred", () => {
  const vb = fitBox(CONTENT, VP);
  assert.ok(vb.x <= 0, "the content's left edge must be visible");
  assert.ok(vb.y <= 0, "the content's top edge must be visible");
  assert.ok(vb.x + vb.w >= CONTENT.w, "the right edge must be visible");
  assert.ok(vb.y + vb.h >= CONTENT.h, "the bottom edge must be visible");
  near(vb.x + vb.w / 2, CONTENT.w / 2, 1e-9, "not horizontally centred");
  near(vb.y + vb.h / 2, CONTENT.h / 2, 1e-9, "not vertically centred");
});

test("fitBox honours pad: more padding shows more slack around the same content", () => {
  const tight = fitBox(CONTENT, VP, 0);
  const loose = fitBox(CONTENT, VP, 0.25);
  assert.ok(loose.w > tight.w, "a bigger pad must pull the camera back");
  // with no padding the constrained axis touches the content exactly
  near(tight.w, CONTENT.w, 1e-9);
});

test("fitBox keeps the aspect invariant, on both a wide and a tall content", () => {
  assertAspect(fitBox(CONTENT, VP), VP, "fitBox(wide)");
  assertAspect(fitBox({ w: 200, h: 4000 }, VP), VP, "fitBox(tall)");
});

test("fitBox survives a degenerate viewport or content without NaN", () => {
  for (const [c, v] of [
    [CONTENT, { w: 0, h: 0 }],
    [{ w: 0, h: 0 }, VP],
    [{ w: Number.NaN, h: 10 }, VP],
  ] as Array<[Size, Size]>) {
    const vb = fitBox(c, v);
    for (const n of [vb.x, vb.y, vb.w, vb.h])
      assert.ok(Number.isFinite(n), `degenerate input produced ${n}`);
    assert.ok(
      vb.w > 0 && vb.h > 0,
      "a degenerate fallback must still be drawable",
    );
  }
});

/* ---------------------------------------------------------------------------- zoomAt */

test("zoomAt holds the content point under the cursor EXACTLY", () => {
  const vb = fitBox(CONTENT, VP);
  // a deliberately off-centre anchor on a non-square viewport: a centre-only test passes
  // even when the anchor term has been dropped entirely.
  const at = { x: 137, y: 411 };
  const before = {
    x: vb.x + at.x / scaleOf(vb, VP),
    y: vb.y + at.y / scaleOf(vb, VP),
  };
  const zoomed = zoomAt(vb, VP, 2.5, at, CONTENT);
  const after = {
    x: zoomed.x + at.x / scaleOf(zoomed, VP),
    y: zoomed.y + at.y / scaleOf(zoomed, VP),
  };
  near(
    after.x,
    before.x,
    1e-9,
    "the anchored content point moved horizontally",
  );
  near(after.y, before.y, 1e-9, "the anchored content point moved vertically");
  assertAspect(zoomed, VP, "zoomAt");
});

test("zoomAt's anchor DOES drift where the reachability clamp bites, and stays in range", () => {
  // The exactness above is the normal case. This is the documented exception, pinned rather
  // than left as folklore: `zoomAt` applies two clamps — the zoom limit on the SCALE, then
  // `clampBox` on the BOX — and the second one moves the anchor whenever the new box would
  // leave the content by more than CLAMP_MARGIN. Zooming OUT with the pointer hard against
  // the left edge is that case. A reader who "fixes" the drift by dropping `clampBox` here
  // re-opens the unreachable-picture bug it exists for, so the trade is asserted both ways.
  const start = zoomAt(fitBox(CONTENT, VP), VP, 4, { x: 400, y: 250 }, CONTENT);
  const at = { x: 2, y: 2 };
  const before = {
    x: start.x + at.x / scaleOf(start, VP),
    y: start.y + at.y / scaleOf(start, VP),
  };
  const out = zoomAt(start, VP, 1 / 3, at, CONTENT);
  const after = {
    x: out.x + at.x / scaleOf(out, VP),
    y: out.y + at.y / scaleOf(out, VP),
  };
  assert.ok(
    Math.abs(after.x - before.x) > 1e-6,
    "the clamp was expected to bite here; if it no longer does, the fixture drifted",
  );
  // and having bitten, it must have left a legal box — that is the point of it.
  assert.deepEqual(out, clampBox(out, CONTENT));
  assertAspect(out, VP, "zoomAt (clamped)");
});

test("zoomAt clamps to limits × the fit scale, in both directions", () => {
  const fit = fitBox(CONTENT, VP);
  const fitScale = scaleOf(fit, VP);
  const at = { x: VP.w / 2, y: VP.h / 2 };

  let vb = fit;
  for (let i = 0; i < 20; i++) vb = zoomAt(vb, VP, 2, at, CONTENT);
  near(scaleOf(vb, VP), DEFAULT_LIMITS.max * fitScale, 1e-6, "max clamp");

  vb = fit;
  for (let i = 0; i < 20; i++) vb = zoomAt(vb, VP, 0.5, at, CONTENT);
  near(scaleOf(vb, VP), DEFAULT_LIMITS.min * fitScale, 1e-6, "min clamp");
});

test("zoomAt respects a caller's own limits", () => {
  const fit = fitBox(CONTENT, VP);
  const fitScale = scaleOf(fit, VP);
  const at = { x: 10, y: 10 };
  let vb = fit;
  for (let i = 0; i < 10; i++)
    vb = zoomAt(vb, VP, 2, at, CONTENT, { min: 1, max: 2 });
  near(scaleOf(vb, VP), 2 * fitScale, 1e-6);
});

/* ----------------------------------------------------------------------------- panBy */

test("panBy moves the content WITH the pointer (the sign nobody gets right first try)", () => {
  const vb = zoomAt(fitBox(CONTENT, VP), VP, 4, { x: 400, y: 250 }, CONTENT);
  const dragRight = panBy(vb, VP, 50, 0, CONTENT);
  assert.ok(
    dragRight.x < vb.x,
    "dragging right must move the WINDOW left, i.e. vb.x falls",
  );
  const dragDown = panBy(vb, VP, 0, 40, CONTENT);
  assert.ok(dragDown.y < vb.y, "dragging down must lower vb.y");
  assertAspect(dragRight, VP, "panBy");
});

test("panBy converts pointer px to content units through the current scale", () => {
  const vb = zoomAt(fitBox(CONTENT, VP), VP, 3, { x: 400, y: 250 }, CONTENT);
  const s = scaleOf(vb, VP);
  const moved = panBy(vb, VP, 30, 0, CONTENT);
  // well inside the clamp, so the delta is exactly 30/s
  near(vb.x - moved.x, 30 / s, 1e-9);
});

/* -------------------------------------------------------------------------- clampBox */

test("clampBox centres an axis whose viewBox is wider than the content", () => {
  const vb: Box = { x: 999, y: -999, w: 4000, h: 2500 };
  const c = clampBox(vb, CONTENT);
  near(c.x, (CONTENT.w - vb.w) / 2, 1e-9);
  near(c.y, (CONTENT.h - vb.h) / 2, 1e-9);
  assert.equal(c.w, vb.w, "clampBox must not resize");
  assert.equal(c.h, vb.h, "clampBox must not resize");
});

test("clampBox permits exactly CLAMP_MARGIN of overscroll and no more", () => {
  const vb: Box = { x: 0, y: 0, w: 400, h: 250 };
  const far = clampBox({ ...vb, x: -100_000, y: -100_000 }, CONTENT);
  near(far.x, -CLAMP_MARGIN * vb.w, 1e-9);
  near(far.y, -CLAMP_MARGIN * vb.h, 1e-9);
  const other = clampBox({ ...vb, x: 100_000, y: 100_000 }, CONTENT);
  near(other.x, CONTENT.w - vb.w + CLAMP_MARGIN * vb.w, 1e-9);
  near(other.y, CONTENT.h - vb.h + CLAMP_MARGIN * vb.h, 1e-9);
  // and a box already inside is left alone
  const inside: Box = { x: 300, y: 40, w: 400, h: 250 };
  assert.deepEqual(clampBox(inside, CONTENT), inside);
});

/* ----------------------------------------------------------------------------- refit */

test("refit with the previous viewport keeps the SCALE and the centre", () => {
  const vb = zoomAt(fitBox(CONTENT, VP), VP, 2, { x: 200, y: 100 }, CONTENT);
  const bigger: Size = { w: 1200, h: 400 };
  const r = refit(vb, bigger, VP);
  near(scaleOf(r, bigger), scaleOf(vb, VP), 1e-9, "scale drifted");
  near(r.x + r.w / 2, vb.x + vb.w / 2, 1e-9, "centre drifted");
  near(r.y + r.h / 2, vb.y + vb.h / 2, 1e-9, "centre drifted");
  assertAspect(r, bigger, "refit(prevVp)");
});

test("refit without the previous viewport keeps the framing and re-derives h", () => {
  const vb = fitBox(CONTENT, VP);
  const taller: Size = { w: 800, h: 1000 };
  const r = refit(vb, taller);
  near(r.w, vb.w, 1e-9, "the horizontal framing should be preserved");
  assertAspect(r, taller, "refit(no prevVp)");
});

/* ------------------------------------------------------------------ misc / formatting */

test("boxAt derives both extents from the viewport, so it cannot skew", () => {
  const b = boxAt(100, 50, 4, VP);
  near(b.w, VP.w / 4, 1e-9);
  near(b.h, VP.h / 4, 1e-9);
  near(b.x + b.w / 2, 100, 1e-9);
  near(b.y + b.h / 2, 50, 1e-9);
});

test("viewBoxAttr formats exactly four numbers at two decimals", () => {
  assert.equal(
    viewBoxAttr({ x: -1.5, y: 2, w: 333.333, h: 208.3333 }),
    "-1.50 2.00 333.33 208.33",
  );
});
