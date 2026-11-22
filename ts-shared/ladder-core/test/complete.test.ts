/**
 * `Scene.complete` — does the circuit conduct END TO END (DESIGN §20, TODO G1)?
 *
 * The distinction this pins is the one a per-connector `flow` cannot make. `flow: "closed"`
 * means only *the leader reached me*; a diagram can be full of closed connectors and still
 * die at an open contact before the sink. So "current is flowing here" and "this circuit is
 * MADE" are different claims, and only the second one licenses telling a reader the rule
 * fires. G1 recorded that leader+streamer could not tell them apart; `complete` is that
 * missing bit, taken off the forward pass rather than a second traversal.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { layout, defaultViewSpec, estimateMetrics } from "../src/index.js";
import type { FunDecl, IRExpr, NodeId, UBoolValue } from "../src/index.js";

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
const fn = (body: IRExpr): FunDecl => ({
  id: 1,
  name: "r",
  params: [],
  body,
});

const sceneOf = (body: IRExpr, vals: Array<[NodeId, UBoolValue]>) =>
  layout(
    fn(body),
    defaultViewSpec({ valuation: new Map(vals), showCurrent: true }),
    estimateMetrics,
  );

// a AND b
const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
// a OR b
const disj = or(2, [leaf(3, "a"), leaf(4, "b")]);

test("a series circuit is complete only when EVERY contact is closed", () => {
  assert.equal(
    sceneOf(conj, [
      [3, "TrueV"],
      [4, "TrueV"],
    ]).complete,
    true,
  );
  // the half-energized case G1 is about: the leader reaches b, then stops.
  assert.equal(
    sceneOf(conj, [
      [3, "TrueV"],
      [4, "FalseV"],
    ]).complete,
    false,
  );
  assert.equal(
    sceneOf(conj, [
      [3, "FalseV"],
      [4, "TrueV"],
    ]).complete,
    false,
  );
});

test("unknown is not complete — an unproven path is not a made circuit", () => {
  assert.equal(sceneOf(conj, [[3, "TrueV"]]).complete, false);
  assert.equal(sceneOf(conj, []).complete, false);
});

test("one closed branch makes a parallel circuit", () => {
  assert.equal(sceneOf(disj, [[3, "TrueV"]]).complete, true);
  assert.equal(
    sceneOf(disj, [
      [3, "FalseV"],
      [4, "FalseV"],
    ]).complete,
    false,
  );
});

test("`complete` is undefined when current flow is off", () => {
  const scene = layout(
    fn(conj),
    defaultViewSpec({
      valuation: new Map<NodeId, UBoolValue>([
        [3, "TrueV"],
        [4, "TrueV"],
      ]),
      showCurrent: false,
    }),
    estimateMetrics,
  );
  assert.equal(scene.complete, undefined);
});

test("an IMPLIES body is never `complete` — it has two lamps, not a sink (§25.4)", () => {
  const rule: IRExpr = {
    $type: "Implies",
    id: 2,
    scope: leaf(3, "in scope"),
    requirement: leaf(4, "met"),
    seam: "IMPLIES",
  };
  // even fully satisfied, there is no right rail to reach
  assert.equal(
    sceneOf(rule, [
      [3, "TrueV"],
      [4, "TrueV"],
    ]).complete,
    false,
  );
});

// An override on a group — a value set on the group itself — makes the group conduct as a
// leaf would (DESIGN §19: its children are not consulted). The reader's case is a FOLDED call
// answered "as a whole" in the playground: it must drive current, not the hidden contents.
// G(x, y) AND z, with G a call whose contents are x AND y.
const callG = (call: boolean): IRExpr => ({
  $type: "And",
  id: 2,
  args: [
    {
      $type: "And",
      id: 5,
      args: [leaf(6, "x"), leaf(7, "y")],
      ...(call ? { call: true, label: "g x y" } : {}),
    },
    leaf(4, "z"),
  ],
});
const overridden = (
  body: IRExpr,
  vals: Array<[NodeId, UBoolValue]>,
  folded: boolean,
) =>
  layout(
    fn(body),
    defaultViewSpec({
      valuation: new Map(vals),
      showCurrent: true,
      foldSet: new Set<NodeId>(folded ? [5] : []),
    }),
    estimateMetrics,
  ).complete;

for (const call of [true, false]) {
  const what = call ? "a folded call" : "a folded plain group";
  test(`${what} pinned TRUE conducts, whatever its hidden contents`, () => {
    assert.equal(
      overridden(
        callG(call),
        [
          [5, "TrueV"],
          [4, "TrueV"],
        ],
        true,
      ),
      true,
    );
  });
  test(`${what} pinned FALSE stops the circuit, even when its contents are TRUE`, () => {
    assert.equal(
      overridden(
        callG(call),
        [
          [5, "FalseV"],
          [6, "TrueV"],
          [7, "TrueV"],
          [4, "TrueV"],
        ],
        true,
      ),
      false,
    );
  });
}

test("an OPEN call panel sets its override aside: the contents decide", () => {
  assert.equal(
    overridden(
      callG(true),
      [
        [5, "TrueV"],
        [4, "TrueV"],
      ],
      false,
    ),
    false,
  );
  assert.equal(
    overridden(
      callG(true),
      [
        [5, "FalseV"],
        [6, "TrueV"],
        [7, "TrueV"],
        [4, "TrueV"],
      ],
      false,
    ),
    true,
  );
});

test("an overridden OR conducts by its own value, not its branches", () => {
  const body = and(2, [or(5, [leaf(6, "x"), leaf(7, "y")]), leaf(4, "z")]);
  assert.equal(
    overridden(
      body,
      [
        [5, "TrueV"],
        [4, "TrueV"],
      ],
      true,
    ),
    true,
  );
  assert.equal(
    overridden(
      body,
      [
        [5, "FalseV"],
        [6, "TrueV"],
        [4, "TrueV"],
      ],
      true,
    ),
    false,
  );
});
