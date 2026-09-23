/**
 * canvasMetrics (E1 Step 2 / A4). The Canvas backend needs a browser, so these tests drive
 * the parts that must be right REGARDLESS of the backend — the font string handed to
 * `measureText`, the memoisation, the line-height ratio — through an injected `measure`. The
 * one thing they cannot check here is the actual glyph widths; that is the browser's job, and
 * the whole reason this exists is to stop trusting the `* 0.56` estimate for them.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { canvasMetrics } from "../src/index.js";

test("measures with the emit's font, at the requested px size", () => {
  const seen: string[] = [];
  const tm = canvasMetrics({
    measure: (text, cssFont) => {
      seen.push(cssFont);
      return text.length * 10;
    },
  });
  tm.width("hello", 14);
  tm.width("hi", 12.5); // the seam's fractional size must round-trip into the font string
  assert.deepEqual(seen, ["14px Georgia, serif", "12.5px Georgia, serif"]);
});

test("a custom fontFamily flows into the measured font string", () => {
  let font = "";
  const tm = canvasMetrics({
    fontFamily: "Inter, sans-serif",
    measure: (_t, cssFont) => ((font = cssFont), 1),
  });
  tm.width("x", 16);
  assert.equal(font, "16px Inter, sans-serif");
});

test("width is memoised per (size, text) — measure is called once per distinct key", () => {
  let calls = 0;
  const tm = canvasMetrics({
    measure: (text) => (calls++, text.length),
  });
  tm.width("abc", 14);
  tm.width("abc", 14); // cache hit
  assert.equal(calls, 1);
  tm.width("abc", 12); // same text, different size — distinct key
  assert.equal(calls, 2);
  tm.width("abcd", 14); // same size, different text — distinct key
  assert.equal(calls, 3);
});

test("the memo key does not collide across (size, text) boundaries", () => {
  // "1" + " " + "2 x"  vs  "12" + " " + "x"  would collide under a naive concat; they must not.
  const widths: Record<string, number> = {};
  const tm = canvasMetrics({
    measure: (text, cssFont) => cssFont.length + text.length,
  });
  const a = tm.width("2 x", 1);
  const b = tm.width("x", 12);
  // distinct measurements, distinct results — the point is they were not conflated
  assert.notEqual(a, b);
  widths.a = a;
  widths.b = b;
  // re-reading returns the SAME cached value for each, not the other's
  assert.equal(tm.width("2 x", 1), widths.a);
  assert.equal(tm.width("x", 12), widths.b);
});

test("lineHeight follows the ratio; default 1.4 matches the P0 estimator", () => {
  assert.equal(canvasMetrics({ measure: () => 0 }).lineHeight(14), 14 * 1.4);
  assert.equal(
    canvasMetrics({ measure: () => 0, lineHeightRatio: 1.2 }).lineHeight(10),
    12,
  );
});

test("off-DOM with no injected measure fails loudly, and only on use", () => {
  // Import + construction must not touch the DOM (lazy backend); the throw is deferred to the
  // first measurement, and it names the fix.
  const tm = canvasMetrics();
  assert.throws(() => tm.width("x", 14), /Inject `measure`/);
});
