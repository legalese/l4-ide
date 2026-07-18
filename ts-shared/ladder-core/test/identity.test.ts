/**
 * §E1/S1 — the decoded tree must carry the semantic identity the IDE evaluator keys on.
 *
 * Before this, `viz-adapter` said outright "the `unique` is dropped" — which was fine while
 * ladder-core only ever produced pictures, and fatal the moment it has to feed an evaluator
 * whose `Assignment` is keyed by `Unique`. These tests pin the two halves of the fix: the
 * identity travels ON the leaf, and the PLURAL inverse indexes fan a proposition out to every
 * position it occupies (R2 — get that wrong and one diagram shows one atom at two values).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import type { FunDecl as VizFunDecl } from "@repo/viz-expr";
import { fromVizFunDecl } from "../src/viz-adapter.js";
import type { And, Leaf } from "../src/index.js";

const nm = (label: string, unique: number) => ({ unique, label });
const iid = (id: number) => ({ id });

/* A tree where the SAME proposition (`unique: 10`, `atomId: "atom-x"`) appears at TWO
 * positions (node 3 and node 4) — the shape the fan-out must handle. Plus an App (atomId
 * but no unique), a TrueE (neither), and one distinct atom. */
const wire: VizFunDecl = {
  $type: "FunDecl",
  id: iid(100),
  name: nm("f", 1),
  params: [],
  body: {
    $type: "And",
    id: iid(1),
    args: [
      {
        $type: "Or",
        id: iid(2),
        args: [
          {
            $type: "UBoolVar",
            id: iid(3),
            name: nm("x", 10),
            value: "UnknownV",
            canInline: true,
            atomId: "atom-x",
          },
          {
            $type: "UBoolVar",
            id: iid(4), // same proposition as node 3: same unique + atomId, different position
            name: nm("x", 10),
            value: "UnknownV",
            canInline: true,
            atomId: "atom-x",
          },
        ],
      },
      {
        $type: "UBoolVar",
        id: iid(5),
        name: nm("y", 11),
        value: "UnknownV",
        canInline: false, // a non-inlinable atom — the `+` button must stay off here
        atomId: "atom-y",
      },
      {
        $type: "App",
        id: iid(6),
        fnName: nm("p", 12),
        args: [],
        atomId: "atom-p",
      },
      { $type: "TrueE", id: iid(7), name: nm("always", 13) },
    ],
  },
};

test("unique + canInline travel on the UBoolVar leaf; absent on App/TrueE", () => {
  const { fn } = fromVizFunDecl(wire);
  const and = fn.body as And;
  const [or, y, app, trueE] = and.args;
  const x0 = (or as And).args[0] as Leaf;

  assert.equal(x0.unique, 10);
  assert.equal(x0.canInline, true);
  assert.equal((y as Leaf).unique, 11);
  assert.equal((y as Leaf).canInline, false);

  // App is addressed by atomId (via evalApp), not by unique — so no unique on the leaf.
  assert.equal((app as Leaf).$type, "App");
  assert.equal((app as Leaf).unique, undefined);
  assert.equal((app as Leaf).atomId, "atom-p");
  assert.equal((app as Leaf).canInline, undefined);

  // Constants carry neither.
  assert.equal((trueE as Leaf).unique, undefined);
  assert.equal((trueE as Leaf).canInline, undefined);
});

test("uniqueByNode covers UBoolVar only; App and constants stay out", () => {
  const { uniqueByNode } = fromVizFunDecl(wire);
  assert.equal(uniqueByNode.get(3), 10);
  assert.equal(uniqueByNode.get(4), 10);
  assert.equal(uniqueByNode.get(5), 11);
  assert.equal(uniqueByNode.has(6), false, "App is not addressed by unique");
  assert.equal(
    uniqueByNode.has(7),
    false,
    "a constant has no evaluable unique",
  );
  assert.equal(uniqueByNode.size, 3);
});

test("nodesByUnique fans a repeated proposition to EVERY position (R2)", () => {
  const { nodesByUnique } = fromVizFunDecl(wire);
  // the whole point: unique 10 occupies nodes 3 AND 4, and a binding on it must reach both.
  assert.deepEqual(
    nodesByUnique
      .get(10)
      ?.slice()
      .sort((a, b) => a - b),
    [3, 4],
  );
  assert.deepEqual(nodesByUnique.get(11), [5]);
  assert.equal(
    nodesByUnique.has(12),
    false,
    "App's fnName.unique is not indexed here",
  );
});

test("atomId index spans UBoolVar AND App, and fans repeats too", () => {
  const { atomIdByNode, nodesByAtomId } = fromVizFunDecl(wire);
  assert.equal(atomIdByNode.get(3), "atom-x");
  assert.equal(
    atomIdByNode.get(6),
    "atom-p",
    "App is eval-addressable by atomId",
  );
  assert.equal(atomIdByNode.has(7), false, "a constant has no atomId");
  assert.deepEqual(
    nodesByAtomId
      .get("atom-x")
      ?.slice()
      .sort((a, b) => a - b),
    [3, 4],
  );
  assert.deepEqual(nodesByAtomId.get("atom-p"), [6]);
});

test("the leaf's own `unique` agrees with the index — the S1 invariant", () => {
  // leaf.unique !== undefined  ⟺  leaf ∈ nodesByUnique. A caller may read identity off the
  // drawn tree OR off the index and must get the same answer; drift here is the bug class
  // this whole step exists to foreclose.
  const { fn, uniqueByNode, nodesByUnique } = fromVizFunDecl(wire);
  const seen = new Set<number>();
  const walk = (e: unknown): void => {
    const n = e as {
      $type: string;
      id: number;
      unique?: number;
      args?: unknown[];
      negand?: unknown;
      scope?: unknown;
      requirement?: unknown;
    };
    if (
      n.$type === "UBoolVar" ||
      n.$type === "App" ||
      n.$type === "TrueE" ||
      n.$type === "FalseE"
    ) {
      if (n.unique !== undefined) {
        seen.add(n.id);
        assert.equal(
          uniqueByNode.get(n.id),
          n.unique,
          `node ${n.id} unique disagrees`,
        );
        assert.ok(
          nodesByUnique.get(n.unique)?.includes(n.id),
          `node ${n.id} missing from its unique's fan`,
        );
      } else {
        assert.equal(
          uniqueByNode.has(n.id),
          false,
          `node ${n.id} has no leaf.unique but is indexed`,
        );
      }
      return;
    }
    n.args?.forEach(walk);
    if (n.negand) walk(n.negand);
    if (n.scope) walk(n.scope);
    if (n.requirement) walk(n.requirement);
  };
  walk(fn.body);
  assert.equal(
    seen.size,
    uniqueByNode.size,
    "every indexed node was reached via a leaf.unique",
  );
});
