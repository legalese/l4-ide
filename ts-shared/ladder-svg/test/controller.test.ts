/** controller.ts — the part of it that is not a DOM.
 *
 * The controller is ~90 lines of event plumbing wrapped around pure code that lives in
 * `viewport.ts` and `flip.ts` and is tested there. What is left worth testing without a
 * browser is the click ROUTING rule: which act, if any, an element's data-attrs denote.
 * `actFromAttrs` is exported for exactly that reason, and everything above it — listener
 * attach, `innerHTML`, pointer capture, the double-rAF — has the manual checklist in
 * `controller.ts`'s header instead. No DOM test environment is added on purpose: a
 * `jsdom`/`happy-dom` dependency on `unstable` is the merge-queue hazard EMBEDDABLE §3.5
 * flags, and it is not worth it for event-to-argument translation.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { actFromAttrs } from "../src/index.js";

test("data-value routes to a value act, data-fold to a fold act", () => {
  assert.deepEqual(actFromAttrs("7", null), { t: "value", id: 7 });
  assert.deepEqual(actFromAttrs(null, "9"), { t: "fold", id: 9 });
});

test("id 0 is a real id, not a falsy one", () => {
  // `svg.ts` emits whatever NodeId the layout produced; a truthiness check here would
  // silently drop the first node of any tree that happens to be 0-indexed.
  assert.deepEqual(actFromAttrs("0", null), { t: "value", id: 0 });
  assert.deepEqual(actFromAttrs(null, "0"), { t: "fold", id: 0 });
});

test("an element with neither attribute is not an act", () => {
  assert.equal(actFromAttrs(null, null), null);
});

test("a non-numeric or empty attribute is refused rather than becoming NaN", () => {
  assert.equal(actFromAttrs("nope", null), null);
  assert.equal(actFromAttrs("", null), null);
  assert.equal(actFromAttrs(null, "  "), null);
  // and value wins over fold if both are somehow present — `actAttr` emits at most one,
  // so this is defensive, but the precedence is written down rather than accidental.
  assert.deepEqual(actFromAttrs("1", "2"), { t: "value", id: 1 });
});
