/**
 * viewBox arithmetic — seam **S6**'s brain (E1-IDE-INTEGRATION.md:56).
 *
 * SvelteFlow supplied pan/zoom, fit-view and the wheel handling for the old renderer. The
 * BBE picture has to grow its own, and the R1 spike says it is not optional: p99 width is
 * 2882px and the corpus max is 4372px (E1-IDE-INTEGRATION.md:214-220) against a pane that
 * is rarely 900.
 *
 * Everything here is PURE — two `Size`s and a `Box` in, a `Box` out, no DOM, no listeners.
 * That split is why S6 is unit-testable with no browser at all: `controller.ts` keeps only
 * the event plumbing, and every off-by-an-offset lives in this file where a test can see it.
 *
 * ## The invariant
 *
 * **`vb.w / vb.h === vp.w / vp.h` at all times.** Hold that and three things fall out:
 * `preserveAspectRatio="xMidYMid meet"` never letterboxes (so there is no offset term in
 * the content↔screen mapping), the scale is the same in both axes, and zoom-at-cursor is
 * exact rather than approximately right. Every function below re-derives `h` as
 * `vp.h / scale` rather than carrying it, which preserves the invariant by construction.
 */

export interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface Size {
  w: number;
  h: number;
}

/** Zoom bounds, as multiples of the FIT scale (not absolute scales — a bound in absolute
 *  units would mean something different for a 400px diagram and a 4372px one). */
export interface ZoomLimits {
  min: number;
  max: number;
}

/** `min` lets the user pull back past fit for context; `max` lets the 4372px worst case from
 *  the R1 spike be read above 1:1 inside an 800px pane. */
export const DEFAULT_LIMITS: ZoomLimits = { min: 0.5, max: 8 };

/** Margin `fitBox` leaves on each side, as a fraction of the content box. */
export const FIT_PAD = 0.03;

/** How far past the content an axis may be pushed, as a fraction of the viewBox's own size.
 *  Small enough that the picture is always most of the pane, large enough that a box at the
 *  very edge is not clipped by the frame. */
export const CLAMP_MARGIN = 0.15;

const ok = (n: number) => Number.isFinite(n) && n > 0;
const sane = (s: Size) => ok(s.w) && ok(s.h);
const clampTo = (v: number, lo: number, hi: number) =>
  v < lo ? lo : v > hi ? hi : v;

/** Viewport px per content unit. Equal in both axes, by the invariant. */
export const scaleOf = (vb: Box, vp: Size): number => vp.w / vb.w;

/** The box of content visible at `scale`, centred on the content point `(cx, cy)`.
 *  Aspect-correct by construction — this is the only constructor of a `Box` in this file
 *  that sets `w` and `h` independently, and it derives both from `vp`. */
export function boxAt(cx: number, cy: number, scale: number, vp: Size): Box {
  const w = vp.w / scale;
  const h = vp.h / scale;
  return { x: cx - w / 2, y: cy - h / 2, w, h };
}

/**
 * The viewBox that shows all of `content`, centred, with `pad` of margin on each side.
 *
 * Degenerate inputs (a host that is `display:none` reports 0×0; a Scene can in principle be
 * empty) must not produce `NaN`/`Infinity` — the attribute would be invalid and the picture
 * would vanish. They fall back to the content's own box, which is exactly what `sceneToSvg`
 * already emits, so the static case degrades to today's behaviour.
 */
export function fitBox(content: Size, vp: Size, pad = FIT_PAD): Box {
  if (!sane(content) || !sane(vp)) {
    const dim = (n: number) => (Number.isFinite(n) && n > 0 ? n : 1);
    return { x: 0, y: 0, w: dim(content.w), h: dim(content.h) };
  }
  const scale = Math.min(
    vp.w / (content.w * (1 + 2 * pad)),
    vp.h / (content.h * (1 + 2 * pad)),
  );
  return boxAt(content.w / 2, content.h / 2, scale, vp);
}

/**
 * Zoom by `factor` (>1 zooms in) holding the content point currently under `at` fixed.
 * `at` is in VIEWPORT px with the origin at the viewport's top-left — the caller converts
 * from `clientX/Y` with a `getBoundingClientRect()`.
 *
 * There are TWO clamps here and they do different jobs — read them as a pair, because a
 * reader who conflates them will "fix" the second one out and re-open the unreachable-picture
 * case it exists for:
 *
 *   1. the ZOOM-LIMIT clamp acts on the **scale** (`limits` × the FIT scale, so the bounds
 *      mean the same thing for a 400px diagram and a 4372px one). Clamping the box for this
 *      would break the anchor outright;
 *   2. the REACHABILITY clamp (`clampBox`) then acts on the **box**. It normally does
 *      nothing, but where it bites — zooming out with the cursor near a content edge — the
 *      anchored point does move. That drift is the deliberate trade: the alternative is a
 *      viewBox that wanders off the picture and cannot be got back.
 *
 * So "zoom-at-cursor is exact" holds everywhere except at the edges, and `test/viewport.test.ts`
 * pins both halves.
 */
export function zoomAt(
  vb: Box,
  vp: Size,
  factor: number,
  at: { x: number; y: number },
  content: Size,
  limits: ZoomLimits = DEFAULT_LIMITS,
): Box {
  if (!sane(vp) || !ok(vb.w) || !ok(vb.h) || !Number.isFinite(factor))
    return vb;
  const s = scaleOf(vb, vp);
  // the content point under the cursor, which must not move
  const cx = vb.x + at.x / s;
  const cy = vb.y + at.y / s;
  const fit = scaleOf(fitBox(content, vp), vp);
  const sNew = clampTo(s * factor, limits.min * fit, limits.max * fit);
  if (!ok(sNew)) return vb;
  return clampBox(
    {
      x: cx - at.x / sNew,
      y: cy - at.y / sNew,
      w: vp.w / sNew,
      h: vp.h / sNew,
    },
    content,
  );
}

/** Pan by a POINTER delta in viewport px. Drag right ⇒ the content moves right under the
 *  hand ⇒ the window onto it moves left, so `vb.x` falls. Getting this sign backwards is
 *  the single most common pan bug, so it has its own test. */
export function panBy(
  vb: Box,
  vp: Size,
  dxPx: number,
  dyPx: number,
  content: Size,
): Box {
  if (!sane(vp) || !ok(vb.w)) return vb;
  const s = scaleOf(vb, vp);
  return clampBox({ ...vb, x: vb.x - dxPx / s, y: vb.y - dyPx / s }, content);
}

/**
 * Keep the picture reachable. Per axis: a viewBox WIDER than the content is centred (and
 * therefore unpannable — there is nothing to pan to); otherwise the box may overscroll the
 * content by `CLAMP_MARGIN` of its own size at either end.
 *
 * Only `x`/`y` move, so the aspect invariant survives untouched.
 */
export function clampBox(vb: Box, content: Size): Box {
  if (!sane(content) || !ok(vb.w) || !ok(vb.h)) return vb;
  const axis = (pos: number, extent: number, span: number) =>
    extent >= span
      ? (span - extent) / 2
      : clampTo(
          pos,
          -CLAMP_MARGIN * extent,
          span - extent + CLAMP_MARGIN * extent,
        );
  return {
    ...vb,
    x: axis(vb.x, vb.w, content.w),
    y: axis(vb.y, vb.h, content.h),
  };
}

/**
 * Restore the aspect invariant after the viewport changed shape, keeping the centre.
 *
 * With `prevVp` (which the controller caches) the SCALE is preserved: the picture keeps its
 * pixel size and a wider pane simply reveals more. Without it there is no way to recover the
 * old scale from `(vb, vp)` alone, so the horizontal extent `vb.w` is kept instead and `h`
 * is re-derived — the picture stays framed and rescales with the pane.
 */
export function refit(vb: Box, vp: Size, prevVp?: Size): Box {
  if (!sane(vp) || !ok(vb.w) || !ok(vb.h)) return vb;
  const cx = vb.x + vb.w / 2;
  const cy = vb.y + vb.h / 2;
  if (prevVp && sane(prevVp)) return boxAt(cx, cy, scaleOf(vb, prevVp), vp);
  return boxAt(cx, cy, vp.w / vb.w, vp);
}

/** The `viewBox` attribute value. Two decimals: enough that a pan is smooth at any zoom,
 *  few enough that the attribute does not churn on sub-pixel noise. */
export const viewBoxAttr = (vb: Box): string =>
  `${vb.x.toFixed(2)} ${vb.y.toFixed(2)} ${vb.w.toFixed(2)} ${vb.h.toFixed(2)}`;
