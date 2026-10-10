/**
 * The OR fan must not run a connector through another branch's box.
 *
 * The sprung Bézier fan (DESIGN §17a) banks from the OR's in-port to each branch's
 * centred port. When a narrower branch sits beyond a wider one, that bank used to cut
 * straight through the wider branch: the dairy's reading of the Oakhurst exemption,
 * `… storing, (packing for shipment) or distribution`, drew `distribution`'s connector
 * through `packing` and `shipment` (2026-10-07). An OR that would collide now keeps its
 * fan in the bus lanes and runs straight stubs to the branches, as an OR with a call
 * panel already did; an OR that would not collide keeps its sprung fan.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { layout, defaultViewSpec, estimateMetrics } from "../src/index.js";
import { PIXEL_GEOMETRY } from "../src/layout.js";
import type { FunDecl, IRExpr, NodeId, Scene } from "../src/index.js";

const leaf = (id: NodeId, label: string): IRExpr => ({
  $type: "UBoolVar",
  id,
  label,
});
const and = (id: NodeId, args: IRExpr[]): IRExpr => ({
  $type: "And",
  id,
  args,
});
const or = (id: NodeId, args: IRExpr[]): IRExpr => ({ $type: "Or", id, args });
const inert = (id: NodeId, text: string): IRExpr => ({
  $type: "InertE",
  id,
  text,
  context: "InertAnd",
});

const draw = (body: IRExpr): Scene =>
  layout(
    { id: 1, name: "exempt", params: [], body } satisfies FunDecl,
    defaultViewSpec(),
    estimateMetrics,
  );

type Curve = Extract<Scene["prims"][number], { kind: "curve" }>;
const bez = (c: Curve, t: number) => {
  const u = 1 - t;
  return {
    x:
      u * u * u * c.from.x +
      3 * u * u * t * c.c1.x +
      3 * u * t * t * c.c2.x +
      t * t * t * c.to.x,
    y:
      u * u * u * c.from.y +
      3 * u * u * t * c.c1.y +
      3 * u * t * t * c.c2.y +
      t * t * t * c.to.y,
  };
};

/** Every connector that passes strictly inside a box it neither starts nor ends at. */
function crossings(s: Scene): string[] {
  const boxes = s.prims.flatMap((p) => (p.kind === "box" ? [p] : []));
  const out: string[] = [];
  for (const p of s.prims) {
    let pts: { x: number; y: number }[];
    let ends: { x: number; y: number }[];
    if (p.kind === "curve") {
      pts = Array.from({ length: 101 }, (_, i) => bez(p, i / 100));
      ends = [p.from, p.to];
    } else if (p.kind === "wire") {
      pts = p.path.slice(1).flatMap((b, i) => {
        const a = p.path[i]!;
        return Array.from({ length: 51 }, (_, j) => ({
          x: a.x + ((b.x - a.x) * j) / 50,
          y: a.y + ((b.y - a.y) * j) / 50,
        }));
      });
      ends = [p.path[0]!, p.path[p.path.length - 1]!];
    } else continue;
    for (const b of boxes) {
      const { x, y, w, h } = b.rect;
      const on = (q: { x: number; y: number }) =>
        q.x >= x - 1 && q.x <= x + w + 1 && q.y >= y - 1 && q.y <= y + h + 1;
      const inside = (q: { x: number; y: number }) =>
        q.x > x + 1 && q.x < x + w - 1 && q.y > y + 1 && q.y < y + h - 1;
      if (!ends.some(on) && pts.some(inside))
        out.push(`${p.kind} ${JSON.stringify(ends)} crosses box ${b.id}`);
    }
  }
  return out;
}

/** The seven activities the two readings agree on, ids from `base`. */
const agreed = (base: number) =>
  [
    "canning",
    "processing",
    "preserving",
    "freezing",
    "drying",
    "marketing",
    "storing",
  ].map((w, i) => leaf(base + i, w));
/** The two parses of "storing, packing for shipment or distribution", short and in full. */
const dairyShort = or(20, [
  leaf(21, "storing"),
  and(22, [leaf(23, "packing"), inert(24, "for"), leaf(25, "shipment")]),
  leaf(26, "distribution"),
]);
const dairy = or(40, [
  ...agreed(41),
  and(50, [leaf(51, "packing"), inert(52, "for"), leaf(53, "shipment")]),
  leaf(54, "distribution"),
]);
const drivers = or(60, [
  ...agreed(61),
  and(70, [
    leaf(71, "packing"),
    inert(72, "for"),
    or(73, [leaf(74, "shipment"), leaf(75, "distribution")]),
  ]),
]);

test("a narrower branch below a wider one is reached without crossing it", () => {
  assert.deepEqual(crossings(draw(dairyShort)), []);
  assert.deepEqual(crossings(draw(dairy)), []);
});

test("an OR whose sprung fan crosses nothing keeps it", () => {
  const s = draw(drivers);
  assert.deepEqual(crossings(s), []);
  // Every curve leaving the top-level in-port still thrusts further than half a bus lane.
  const curves = s.prims.filter((q): q is Curve => q.kind === "curve");
  const inX = Math.min(...curves.map((q) => q.from.x));
  const top = curves.filter((q) => q.from.x === inX);
  assert.equal(top.length, 8, "one curve per branch of the top-level OR");
  for (const q of top)
    assert.ok(
      Math.abs(q.c1.x - q.from.x) > PIXEL_GEOMETRY.BUS_PAD / 2,
      "the sprung fan was replaced although nothing collided",
    );
});
