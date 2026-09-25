/**
 * Real text metrics for the browser target (DESIGN §4.4 / §8, TODO A4 / E1 Step 2).
 *
 * The layout kernel takes a `TextMetrics` and sizes every box to `width(label)`; the SVG
 * emit then typesets that label in `Georgia, serif` and centres it. If the metrics
 * UNDER-estimate, the text overflows its box — which is exactly what the P0 estimator
 * (`length * size * 0.56`) does on wide glyphs and proportional fonts. The fix is to measure
 * with the SAME font the emit will use, via Canvas `measureText`.
 *
 * Parity is the whole point, so `fontFamily` defaults to the emit's `"Georgia, serif"`
 * (svg.ts) — pass a different one only if you have also changed the emit. Measurement is
 * memoised per (size, text): layout calls `width` on the same labels repeatedly across a
 * render, and `measureText` is not free.
 *
 * The Canvas backend is created lazily, so importing this module is safe in a headless
 * context; only calling `width()` there fails. For tests (and any non-DOM caller) inject
 * `measure` — the CSS-font string and memo key are then exercised without a browser.
 */
import type { TextMetrics } from "@repo/ladder-core";

export interface CanvasMetricsOpts {
  /** Font family to MEASURE with — must match the SVG emit (`Georgia, serif`). */
  fontFamily?: string;
  /** `size -> line box height` ratio. 1.4 matches the P0 estimator and the emit's spacing. */
  lineHeightRatio?: number;
  /**
   * The raw measuring backend: CSS-font string (e.g. `"14px Georgia, serif"`) -> advance width
   * in px. Defaults to a lazily-created offscreen Canvas 2D context. Inject to unit-test, or to
   * measure headlessly with fontkit/opentype.js later.
   */
  measure?: (text: string, cssFont: string) => number;
}

/** Lazily create a single reusable Canvas 2D context, or throw a legible error off-DOM. */
function canvasBackend(): (text: string, cssFont: string) => number {
  let ctx: {
    font: string;
    measureText: (t: string) => { width: number };
  } | null = null;
  return (text, cssFont) => {
    if (!ctx) {
      const doc = (globalThis as { document?: Document }).document;
      const canvas = doc?.createElement?.("canvas");
      const c = canvas?.getContext?.("2d");
      if (!c)
        throw new Error(
          "canvasMetrics: no Canvas 2D context (not a browser). Inject `measure` for headless use.",
        );
      ctx = c;
    }
    ctx.font = cssFont;
    return ctx.measureText(text).width;
  };
}

export function canvasMetrics(opts: CanvasMetricsOpts = {}): TextMetrics {
  const family = opts.fontFamily ?? "Georgia, serif";
  const ratio = opts.lineHeightRatio ?? 1.4;
  // Resolve the backend once, but do NOT build the canvas until the first measurement, so a
  // headless import never touches the DOM.
  let backend = opts.measure;
  const measure = (text: string, cssFont: string) => {
    if (!backend) backend = canvasBackend();
    return backend(text, cssFont);
  };
  const memo = new Map<string, number>();
  return {
    width(text, sizePx) {
      // A space separates size from text. `sizePx` stringifies with no space (even the
      // fractional 12.5px the seam measures at), so splitting on the first space is lossless
      // and the key cannot collide across distinct (size, text) pairs.
      const key = `${sizePx} ${text}`;
      let w = memo.get(key);
      if (w === undefined) {
        w = measure(text, `${sizePx}px ${family}`);
        memo.set(key, w);
      }
      return w;
    },
    lineHeight: (sizePx) => sizePx * ratio,
  };
}
