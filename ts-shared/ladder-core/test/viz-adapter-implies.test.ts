/** The WIRE path for the seam (DESIGN §25a).
 *
 * §25b–d built the seam inside ladder-core, from hand-made nodes. This pins the part
 * that makes it reachable from real L4: an `Implies` arriving over the wire from the
 * Haskell ladder builder must land as a REAL `Implies` in the kernel — with its two
 * lamps — and not as the `NOT scope OR requirement` that every other consumer of the
 * wire IR is entitled to flatten it into.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { expandImplies } from "@repo/viz-expr";
import type {
  FunDecl as VizFunDecl,
  IRExpr as VizIRExpr,
  Implies as VizImplies,
} from "@repo/viz-expr";
import {
  fromVizFunDecl,
  layout,
  estimateMetrics,
  defaultViewSpec,
} from "../src/index.js";
import type { NodeId, UBoolValue, Scene } from "../src/index.js";

/* A wire tree shaped like the real thing: `covers IMPLIES requirement-met`. */
const v = (id: number, label: string, value: UBoolValue): VizIRExpr => ({
  $type: "UBoolVar",
  id: { id },
  name: { unique: id, label },
  value,
  canInline: false,
  atomId: `atom-${id}`,
});

const wire = (upper: UBoolValue, glazed: UBoolValue): VizImplies => ({
  $type: "Implies",
  id: { id: 1 },
  scope: v(2, "on an upper floor", upper),
  requirement: v(3, "obscure-glazed", glazed),
  seam: "IMPLIES",
});

const fnOf = (body: VizIRExpr): VizFunDecl => ({
  $type: "FunDecl",
  id: { id: 100 },
  name: { unique: 100, label: "window complies with A.3" },
  params: [],
  body,
});

const lamps = (s: Scene) => {
  const coils = s.prims.filter((p) => p.kind === "coil");
  const g = coils.find((p) => p.role === "green");
  const r = coils.find((p) => p.role === "red");
  return { green: !!g?.lit, red: !!r?.lit, count: coils.length };
};

const drawWire = (body: VizIRExpr): Scene => {
  const { fn, valuation } = fromVizFunDecl(fnOf(body));
  return layout(
    fn,
    defaultViewSpec({ valuation, showCurrent: true }),
    estimateMetrics,
  );
};

test("an Implies from the wire survives into the kernel as a seam with two sinks", () => {
  const s = drawWire(wire("TrueV", "TrueV"));
  assert.equal(
    lamps(s).count,
    2,
    "the wire node must reach the two-sink layout",
  );
  assert.deepEqual(
    { green: lamps(s).green, red: lamps(s).red },
    { green: true, red: false },
  );
  const seam = s.prims.find((p) => p.kind === "text" && p.tag === "seam");
  assert.ok(
    seam && seam.kind === "text" && seam.text === "IMPLIES",
    "the drafter's spelling rides the wire",
  );
});

test("the wire preserves the N/A case the classical expansion destroys", () => {
  // scope FALSE. `NOT P OR Q` is TRUE here — so any consumer that expanded the seam
  // would have to call this "complies". The ladder lights NEITHER lamp: N/A.
  const s = drawWire(wire("FalseV", "FalseV"));
  assert.deepEqual(
    { green: lamps(s).green, red: lamps(s).red },
    { green: false, red: false },
  );
  assert.ok(
    s.prims.some((p) => p.kind === "text" && p.text.startsWith("N/A")),
    "and it says so",
  );
});

test("valuation is lifted from BOTH sides of the seam", () => {
  // The seam is not a barrier to the side-channels. If `convert` failed to recurse
  // into scope/requirement, the leaves would arrive value-free and both lamps would
  // stay dark — which is why the green-lamp test above is load-bearing here too.
  const { valuation } = fromVizFunDecl(fnOf(wire("TrueV", "FalseV")));
  assert.equal(valuation.get(2 as NodeId), "TrueV");
  assert.equal(valuation.get(3 as NodeId), "FalseV");
});

test("expandImplies is the LOSSY escape hatch, and mints non-colliding ids", () => {
  // For consumers with no seam (the original visualizer's LIR). It must produce
  // `NOT scope OR requirement`, reusing the Implies' id for the Or and minting a
  // fresh id for the Not — ids are POSITIONAL keys, so a collision is a real bug.
  const out = expandImplies(wire("TrueV", "TrueV"));
  assert.equal(out.$type, "Or");
  if (out.$type !== "Or") return;
  assert.equal(out.id.id, 1, "the Or inherits the (now-free) Implies id");
  const [not, req] = out.args;
  assert.equal(not.$type, "Not");
  assert.equal(req.$type, "UBoolVar");

  const ids = new Set<number>();
  const walk = (e: VizIRExpr): void => {
    assert.ok(
      !ids.has(e.id.id),
      `duplicate node id ${e.id.id} after expansion`,
    );
    ids.add(e.id.id);
    if (e.$type === "Not") walk(e.negand);
    else if (e.$type === "Or" || e.$type === "And") e.args.forEach(walk);
  };
  walk(out);

  // …and the loss is exactly the thing §25 exists to prevent: after this rewrite the
  // vacuous case is indistinguishable from compliance. Nothing downstream can recover it.
});
