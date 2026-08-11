/** flip.ts — the FLIP's pure half.
 *
 * The algorithm is a MOVE of code that worked in two demos, so the risk here is not "is it
 * right" but "did the move change it". Fixtures are hand-built `Scene` literals, same seam
 * discipline as `svg.test.ts`: nothing in this file touches `layout`, metrics or a DOM.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { flipIndex, flipKeyFor, flipMoves } from "../src/flip.js";
import type { Pos } from "../src/flip.js";
import type { Scene, ScenePrim } from "@repo/ladder-core";

const scene = (...prims: ScenePrim[]): Scene => ({
  size: { w: 400, h: 200 },
  prims,
});

const box = (id: number, x: number, y: number): ScenePrim => ({
  kind: "box",
  id,
  rect: { x, y, w: 80, h: 30 },
  role: "leaf",
  state: "live",
});

const label = (id: number | undefined, x: number, y: number): ScenePrim => ({
  kind: "text",
  at: { x, y },
  text: "t",
  anchor: "start",
  state: "live",
  ...(id === undefined ? {} : { id }),
});

test("flipIndex keys boxes off rect and labelled texts off at", () => {
  const idx = flipIndex(scene(box(7, 10, 20), label(9, 30, 40)));
  assert.deepEqual(idx.get("box:7"), { x: 10, y: 20 });
  assert.deepEqual(idx.get("label:9"), { x: 30, y: 40 });
  assert.equal(idx.size, 2);
});

test("flipIndex skips text with no id — inert prose has no data-fnid to match", () => {
  const idx = flipIndex(scene(label(undefined, 5, 5), box(1, 0, 0)));
  assert.deepEqual([...idx.keys()], ["box:1"]);
});

test("flipKeyFor: a rect is a box, anything else is a label, case-insensitively", () => {
  assert.equal(flipKeyFor("rect", "3"), "box:3");
  assert.equal(flipKeyFor("RECT", "3"), "box:3");
  assert.equal(flipKeyFor("text", "3"), "label:3");
  assert.equal(flipKeyFor("tspan", "3"), "label:3");
});

test("flipMoves inverts a displacement: the delta points BACK to where it was", () => {
  const old = new Map<string, Pos>([["box:1", { x: 100, y: 50 }]]);
  const next = new Map<string, Pos>([["box:1", { x: 130, y: 20 }]]);
  assert.deepEqual(flipMoves(old, next), [
    { key: "box:1", kind: "move", dx: -30, dy: 30 },
  ]);
});

test("flipMoves: new keys appear, unmoved keys are silent, vanished keys are ignored", () => {
  const old = new Map<string, Pos>([
    ["box:1", { x: 0, y: 0 }],
    ["box:2", { x: 5, y: 5 }],
  ]);
  const next = new Map<string, Pos>([
    ["box:1", { x: 0, y: 0 }], // unmoved
    ["box:3", { x: 9, y: 9 }], // new
    // box:2 is gone — iteration is over `next`, so there is no exit animation. That is
    // what the demos did before the move, and preserving it is the point.
  ]);
  assert.deepEqual(flipMoves(old, next), [{ key: "box:3", kind: "appear" }]);
});

test("scale multiplies the delta — the parameter a screen-space caller would need", () => {
  const old = new Map<string, Pos>([["label:4", { x: 10, y: 10 }]]);
  const next = new Map<string, Pos>([["label:4", { x: 20, y: 30 }]]);
  assert.deepEqual(flipMoves(old, next, 2), [
    { key: "label:4", kind: "move", dx: -20, dy: -40 },
  ]);
  // and the default is 1, which is what the controller passes: a CSS transform inside an
  // <svg> is resolved in USER units, so a content-space delta is already correct there.
  assert.deepEqual(flipMoves(old, next)[0], {
    key: "label:4",
    kind: "move",
    dx: -10,
    dy: -20,
  });
});
