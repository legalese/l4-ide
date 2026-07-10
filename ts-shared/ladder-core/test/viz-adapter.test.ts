/**
 * A1 adapter tests — decode a wire-IR `FunDecl` (the `@repo/viz-expr` shape the LSP
 * emits) into ladder-core's IR + valuation side-channel, then prove the result
 * flows through `layout()` unchanged. Run: `npm test` (tsx --test) in ladder-core.
 *
 * The fixture mirrors the s415 second-limb shape (demo/s415.ts) but in the WIRE
 * form: ids are `{id:number}`, names are `{unique,label}`, leaves carry inline
 * `value`. The fixture weaves in one of every wire node kind — And, Or, InertE,
 * UBoolVar (TrueV/FalseV/UnknownV), App, Not, TrueE, FalseE — plus non-empty
 * `params`, so all eight branches of `convert` are exercised.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import type { FunDecl as VizFunDecl } from "@repo/viz-expr";
import { fromVizFunDecl, fromVizExpr } from "../src/viz-adapter.js";
import { layout, estimateMetrics, defaultViewSpec } from "../src/index.js";
import type { And, Or, Not, Leaf, Inert } from "../src/index.js";

const nm = (label: string, unique: number) => ({ unique, label });
const iid = (id: number) => ({ id });

// ---- wire-IR fixture (deception AND intentionally AND App AND NOT(defence)) ----
const wire: VizFunDecl = {
  $type: "FunDecl",
  id: iid(100),
  name: nm("is said to cheat", 1),
  params: [nm("actor", 2), nm("victim", 3)],
  body: {
    $type: "And",
    id: iid(1),
    args: [
      {
        $type: "Or",
        id: iid(2),
        args: [
          {
            $type: "InertE",
            id: iid(3),
            text: "there is a deception",
            context: "InertOr",
          },
          {
            $type: "UBoolVar",
            id: iid(4),
            name: nm("by deceiving", 10),
            value: "TrueV",
            canInline: true,
            atomId: "atom-deceiving",
          },
          {
            $type: "UBoolVar",
            id: iid(5),
            name: nm("dishonest concealment", 11),
            value: "FalseV",
            canInline: true,
            atomId: "atom-concealment",
          },
        ],
      },
      {
        $type: "UBoolVar",
        id: iid(6),
        name: nm("intentionally", 12),
        value: "UnknownV", // must NOT land in the valuation map
        canInline: true,
        atomId: "atom-intentionally",
      },
      {
        $type: "App",
        id: iid(7),
        fnName: nm("age at least", 13),
        args: [],
        atomId: "atom-age",
      },
      {
        $type: "Not",
        id: iid(8),
        negand: {
          $type: "UBoolVar",
          id: iid(9),
          name: nm("has a defence", 14),
          value: "FalseV",
          canInline: true,
          atomId: "atom-defence",
        },
      },
      { $type: "TrueE", id: iid(20), name: nm("always", 15) },
      { $type: "FalseE", id: iid(21), name: nm("never", 16) },
    ],
  },
};

test("FunDecl head is flattened (ids preserved, names -> labels)", () => {
  const { fn } = fromVizFunDecl(wire);
  assert.equal(fn.id, 100);
  assert.equal(fn.name, "is said to cheat");
  assert.deepEqual(fn.params, ["actor", "victim"]); // Name[] -> label[]
  assert.equal(fn.body.$type, "And");
  assert.equal(fn.body.id, 1);
});

test("valuation lifts inline leaf values, skips UnknownV", () => {
  const { valuation } = fromVizFunDecl(wire);
  // by-deceiving TRUE, concealment FALSE, defence FALSE — intentionally (Unknown) absent, App absent
  assert.equal(valuation.get(4), "TrueV");
  assert.equal(valuation.get(5), "FalseV");
  assert.equal(valuation.get(9), "FalseV");
  assert.equal(valuation.has(6), false, "UnknownV must be omitted");
  assert.equal(valuation.has(7), false, "App carries no inline value");
  assert.equal(
    valuation.has(20),
    false,
    "TrueE keeps its inherent value, not a valuation entry",
  );
  assert.equal(
    valuation.has(21),
    false,
    "FalseE keeps its inherent value, not a valuation entry",
  );
  assert.equal(valuation.size, 3);
});

test("every node kind maps to its ladder counterpart", () => {
  const { fn } = fromVizFunDecl(wire);
  const and = fn.body as And;
  const [or, intentionally, app, not, trueE, falseE] = and.args;

  assert.equal(or.$type, "Or");
  const orArgs = (or as Or).args;
  assert.equal(orArgs[0].$type, "InertE");
  assert.equal((orArgs[0] as Inert).text, "there is a deception"); // text preserved
  assert.equal((orArgs[0] as Inert).context, "InertOr"); // context preserved
  assert.equal(orArgs[1].$type, "UBoolVar");
  assert.equal((orArgs[1] as Leaf).label, "by deceiving");
  assert.equal((orArgs[1] as Leaf).atomId, "atom-deceiving");

  assert.equal(intentionally.$type, "UBoolVar");

  assert.equal(app.$type, "App");
  assert.equal((app as Leaf).label, "age at least");
  assert.equal((app as Leaf).atomId, "atom-age");

  assert.equal(not.$type, "Not");
  assert.equal((not as Not).negand.$type, "UBoolVar");
  assert.equal(((not as Not).negand as Leaf).label, "has a defence");

  assert.equal(trueE.$type, "TrueE");
  assert.equal((trueE as Leaf).label, "always");
  assert.equal(trueE.id, 20);
  assert.equal(falseE.$type, "FalseE");
  assert.equal((falseE as Leaf).label, "never");
  assert.equal(falseE.id, 21);
});

test("And/Or carry no synthesized label (wire has no NamedExpr yet)", () => {
  const { fn } = fromVizFunDecl(wire);
  assert.equal((fn.body as And).label, undefined);
});

test("decoded tree + valuation flow through layout() without error", () => {
  const { fn, valuation } = fromVizFunDecl(wire);
  const scene = layout(fn, defaultViewSpec({ valuation }), estimateMetrics);
  assert.ok(scene.prims.length > 0, "produces primitives");
  assert.ok(scene.size.w > 0 && scene.size.h > 0, "has positive extent");
  // the two TRUE leaves + FALSE leaves should be drawn as boxes
  const boxes = scene.prims.filter((p) => p.kind === "box");
  assert.ok(boxes.length >= 4, "operative leaves render as boxes");
});

test("fromVizExpr decodes a bare sub-expression", () => {
  const { expr, valuation } = fromVizExpr(wire.body);
  assert.equal(expr.$type, "And");
  assert.equal(valuation.get(4), "TrueV");
});
