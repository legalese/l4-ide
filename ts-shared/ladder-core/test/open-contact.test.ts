/**
 * The open-contact BREAK — where the circuit stopped (DESIGN §15.1, §25.4).
 *
 * §25.4 makes this glyph load-bearing rather than decorative: N/A and "undetermined"
 * are both dark lamps, and a reader tells them apart *"by looking at where the break
 * is. A scope that is definitively ✗ shows a clean open contact — tested, and it did
 * not bite. A scope that is ? is grey — not yet asked."* So a FALSE element must draw
 * a break and an UNKNOWN one must not, everywhere — not only on an OR fan, which was
 * the only place the engine used to draw it.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { layout, defaultViewSpec, estimateMetrics } from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  NodeId,
  ScenePrim,
  UBoolValue,
} from "../src/index.js";

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

const sceneOf = (body: IRExpr, vals: Array<[NodeId, UBoolValue]>) =>
  layout(
    { id: 1, name: "r", params: [], body } satisfies FunDecl,
    defaultViewSpec({ valuation: new Map(vals) }),
    estimateMetrics,
  );

const breaks = (prims: ScenePrim[]) =>
  prims.filter(
    (p): p is Extract<ScenePrim, { kind: "glyph" }> =>
      p.kind === "glyph" && p.role === "open-contact",
  );

test("a FALSE leaf draws a break; an UNKNOWN one draws none", () => {
  const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
  assert.equal(breaks(sceneOf(conj, [[3, "FalseV"]]).prims).length, 1);
  assert.equal(breaks(sceneOf(conj, [[3, "UnknownV"]]).prims).length, 0);
  assert.equal(breaks(sceneOf(conj, []).prims).length, 0);
  assert.equal(
    breaks(
      sceneOf(conj, [
        [3, "TrueV"],
        [4, "TrueV"],
      ]).prims,
    ).length,
    0,
  );
});

test("the break sits just past the failing leaf — clear of the box, on the wire", () => {
  const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
  const scene = sceneOf(conj, [
    [3, "TrueV"],
    [4, "FalseV"],
  ]);
  const [brk] = breaks(scene.prims);
  const box = scene.prims.find(
    (p): p is Extract<ScenePrim, { kind: "box" }> =>
      p.kind === "box" && p.id === 4,
  )!;
  assert.equal(brk.state, "dead");
  assert.equal(brk.at.y, box.rect.y + box.rect.h / 2);
  // The glyph is two vertical bars at ±7 about its centre, so it must sit CLEAR of the
  // box. Centred on the out-port, the left bar landed 7px INSIDE the box and read as a
  // stroke through the label rather than as a gap in the wire.
  assert.ok(
    brk.at.x - 7 > box.rect.x + box.rect.w,
    `both bars must clear the box: left bar ${brk.at.x - 7}, box ends ${box.rect.x + box.rect.w}`,
  );
});

test("a dead leaf in an OR gets ONE break, not two", () => {
  // the fan used to draw its own break unconditionally; a dead LEAF now marks itself,
  // so the two would double-report a single failure.
  const disj = or(2, [leaf(3, "a"), leaf(4, "b")]);
  assert.equal(
    breaks(
      sceneOf(disj, [
        [3, "FalseV"],
        [4, "TrueV"],
      ]).prims,
    ).length,
    1,
  );
});

test("a dead branch is marked at the leaf that failed, not at the group around it", () => {
  // §25.4's promise is that the reader "sees exactly WHERE it stopped", so one failure
  // gets one break, at the contact that opened. `measureAnd`/`measureOr` report their
  // Measured `state` as 'inert' regardless of value, so a group never draws a fan break
  // of its own — which turns out to be the behaviour §25.4 wants. (That also means the
  // pre-existing `m.state === 'dead'` fan branch only ever fired for LEAVES and folded
  // placeholders; this test pins that reading rather than the code's apparent intent.)
  const disj = or(2, [and(5, [leaf(6, "x"), leaf(7, "y")]), leaf(4, "b")]);
  const got = breaks(sceneOf(disj, [[6, "FalseV"]]).prims);
  assert.equal(got.length, 1);
  assert.equal(got[0].state, "dead");
});

test("a folded group pinned FALSE breaks at the placeholder — the fold hides the reason, not the fact", () => {
  const disj = or(2, [and(5, [leaf(6, "x"), leaf(7, "y")]), leaf(4, "b")]);
  const scene = layout(
    { id: 1, name: "r", params: [], body: disj } satisfies FunDecl,
    defaultViewSpec({
      valuation: new Map<NodeId, UBoolValue>([[5, "FalseV"]]),
      foldSet: new Set([5]),
    }),
    estimateMetrics,
  );
  const got = breaks(scene.prims);
  assert.equal(got.length, 1);
  assert.equal(got[0].state, "dead");
});

test("every break carries a state, so the renderer can tell a fact from a ghost", () => {
  const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
  const scene = layout(
    { id: 1, name: "r", params: [], body: conj } satisfies FunDecl,
    defaultViewSpec({
      valuation: new Map<NodeId, UBoolValue>([[3, "FalseV"]]),
      states: new Map([[4, "eliminable" as const]]),
    }),
    estimateMetrics,
  );
  const got = breaks(scene.prims);
  assert.deepEqual(
    got.map((b) => b.state).sort(),
    ["dead"],
    "an eliminable leaf in a SERIES draws no break; only the OR fan ghosts one",
  );
});
