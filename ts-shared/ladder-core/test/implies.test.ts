/** IMPLIES — the seam and the two sinks (DESIGN §25).
 *
 * The load-bearing property is the VERDICT TABLE. Count the lit lamps:
 *
 *   scope ✗   → both dark  → N/A: the rule never bit
 *   scope ?   → both dark  → undetermined
 *   ✓ then ✓  → GREEN      → complies
 *   ✓ then ✗  → RED        → in breach
 *
 * Note especially the two rows that are easy to get wrong, and that a `NOT P OR Q`
 * expansion cannot express at all: N/A must not read as "complies", and an UNKNOWN
 * requirement must not read as "in breach".
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  layout,
  estimateMetrics,
  toMermaidRailroad,
  defaultViewSpec,
} from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  And,
  Implies,
  NodeId,
  UBoolValue,
  Scene,
} from "../src/index.js";

let c = 0;
const nid = () => ++c;
const leaf = (label: string): Leaf => ({
  $type: "UBoolVar",
  id: nid(),
  label,
  atomId: label,
});
const and = (args: IRExpr[], label?: string): And => ({
  $type: "And",
  id: nid(),
  args,
  label,
});

const upper = leaf("upper floor");
const side = leaf("side elevation");
const glazed = leaf("obscure-glazed");
const shut = leaf("non-opening");

const scope = and([upper, side], "A.3 covers");
const requirement = and([glazed, shut], "A.3 requirement met");
const rule: Implies = {
  $type: "Implies",
  id: nid(),
  scope,
  requirement,
  must: "MUST",
};
const fn: FunDecl = { id: nid(), name: "complies", params: [], body: rule };

const draw = (v: Record<number, UBoolValue>): Scene =>
  layout(
    fn,
    defaultViewSpec({
      valuation: new Map<NodeId, UBoolValue>(
        Object.entries(v).map(([k, x]) => [Number(k), x]),
      ),
      showCurrent: true,
    }),
    estimateMetrics,
  );

const lamps = (s: Scene) => {
  const coils = s.prims.filter((p) => p.kind === "coil");
  assert.equal(coils.length, 2, "an implication has exactly two sinks");
  const g = coils.find((p) => p.role === "green")!;
  const r = coils.find((p) => p.role === "red")!;
  return { green: g.lit, red: r.lit };
};

const T = "TrueV" as const,
  F = "FalseV" as const;

test("scope FALSE ⇒ N/A: neither lamp lights (the rule never bit)", () => {
  const s = draw({ [upper.id]: F, [side.id]: T, [glazed.id]: F, [shut.id]: F });
  assert.deepEqual(lamps(s), { green: false, red: false });
  // …and emphatically NOT "complies", even though ¬P ∨ Q is TRUE here. That is the
  // whole reason Implies is a node and not sugar: the value is true, the ink is not.
  const na = s.prims.find((p) => p.kind === "text" && p.text.startsWith("N/A"));
  assert.ok(na, "a definitively out-of-scope case should say so");
});

test("scope TRUE, requirement TRUE ⇒ GREEN", () => {
  const s = draw({ [upper.id]: T, [side.id]: T, [glazed.id]: T, [shut.id]: T });
  assert.deepEqual(lamps(s), { green: true, red: false });
});

test("scope TRUE, requirement FALSE ⇒ RED", () => {
  const s = draw({ [upper.id]: T, [side.id]: T, [glazed.id]: T, [shut.id]: F });
  assert.deepEqual(lamps(s), { green: false, red: true });
});

test("scope TRUE, requirement UNKNOWN ⇒ both dark — an unasked question is NOT a breach", () => {
  const s = draw({ [upper.id]: T, [side.id]: T }); // requirement never asked
  assert.deepEqual(lamps(s), { green: false, red: false });
  // and it must NOT claim N/A either — the rule DID reach this case
  assert.ok(
    !s.prims.some((p) => p.kind === "text" && p.text.startsWith("N/A")),
  );
});

test("scope UNKNOWN ⇒ both dark, and no N/A claim", () => {
  const s = draw({ [glazed.id]: T, [shut.id]: T });
  assert.deepEqual(lamps(s), { green: false, red: false });
  assert.ok(
    !s.prims.some((p) => p.kind === "text" && p.text.startsWith("N/A")),
  );
});

test("three-valued short-circuit: a settled breach needs no further questions", () => {
  // glazing is UNKNOWN, but non-opening is already FALSE, so `? ∧ F = F` — the
  // requirement fails whatever the glazing turns out to be. RED is correct, and the
  // wizard should not ask about the glazing at all.
  const s = draw({ [upper.id]: T, [side.id]: T, [shut.id]: F });
  assert.deepEqual(lamps(s), { green: false, red: true });
});

test("the two lamps ARE the sinks: no second power terminal is drawn", () => {
  const s = draw({ [upper.id]: T, [side.id]: T, [glazed.id]: T, [shut.id]: T });
  const terminals = s.prims.filter(
    (p) => p.kind === "glyph" && p.role === "power-terminal",
  );
  assert.equal(
    terminals.length,
    1,
    "source only — the lamps are the sinks (§25.4)",
  );
  assert.ok(
    s.prims.some((p) => p.kind === "glyph" && p.role === "changeover"),
    "one pole, two throws",
  );
});

test("the seam keeps the drafter's register, and is not struck through by its wire", () => {
  const s = draw({ [upper.id]: T, [side.id]: T });
  const seam = s.prims.find((p) => p.kind === "text" && p.tag === "seam");
  assert.ok(seam && seam.kind === "text" && seam.text === "MUST");
  // the wire is drawn in two segments with a gap, so the connective sits IN the line
  const through = s.prims.filter(
    (p) =>
      p.kind === "wire" &&
      p.path.length === 2 &&
      p.path[0].y === p.path[1].y &&
      p.path[0].x < seam.at.x &&
      p.path[1].x > seam.at.x,
  );
  assert.equal(through.length, 0, "no wire may run through the seam text");
});

test("Mermaid emits the BOTTLENECK, never optional()", () => {
  const m = toMermaidRailroad(fn, { frontmatter: false });
  assert.match(m, /sequence\(.*terminal\("MUST"\).*\)/);
  assert.ok(
    !m.includes("optional("),
    "optional() is an UNGATED bypass: it says the requirement is moot (§25.6)",
  );
});
