/**
 * ASCII ladder demo (DESIGN §24, carrier I-b) — prove that the SAME BBE layout,
 * driven by a monospace TextMetrics, lands on a character grid.
 *
 * The specimen is the GPDO Class A para A.3 window rule from
 * `doc/concepts/language-design/logic-not-flowcharts.md` — the very document that
 * argues the ladder is the right picture for a material conditional and then
 * shows no ladder. A code fence renders verbatim on github.com, so this closes
 * that gap with no build step and no image.
 *
 *   P = onUpperFloor AND (inWall OR inRoofSlope)
 *   Q = obscureGlazed AND (nonOpening OR openablePartsAbove1_7m)
 *   A.3: P -> Q
 *
 * Run: cd ts-shared/ladder-core && npx tsx demo/ascii.ts
 */
import {
  layout,
  sceneToAscii,
  monoMetrics,
  ASCII_GEOMETRY,
  defaultViewSpec,
} from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  Inert,
  And,
  Or,
  Not,
  NodeId,
  UBoolValue,
  Provenance,
} from "../src/index.js";

let counter = 0;
const nid = () => ++counter;
const leaf = (label: string): Leaf => ({
  $type: "UBoolVar",
  id: nid(),
  label,
  atomId: label,
});
const inert = (text: string, context: "InertAnd" | "InertOr"): Inert => ({
  $type: "InertE",
  id: nid(),
  text,
  context,
});
const and = (args: IRExpr[]): And => ({ $type: "And", id: nid(), args });
const or = (args: IRExpr[]): Or => ({ $type: "Or", id: nid(), args });
const not = (negand: IRExpr): Not => ({ $type: "Not", id: nid(), negand });

/* ---- A.3 covers w:  upper floor AND (in a wall OR in a roof slope) ---- */
const upper = leaf("on an upper floor");
const inWall = leaf("in a wall");
const inRoof = leaf("in a roof slope");
const covers = and([
  upper,
  inert("and", "InertAnd"),
  or([
    inert("in a side elevation:", "InertOr"),
    inWall,
    inert("or", "InertOr"),
    inRoof,
  ]),
]);

/* ---- A.3 requirement met:  obscure-glazed AND (non-opening OR >= 1.7m) ---- */
const obscure = leaf("obscure-glazed");
const nonOpening = leaf("non-opening");
const high = leaf("openable parts ≥ 1.7m up");
const requirement = and([
  obscure,
  inert("and", "InertAnd"),
  or([inert("either", "InertOr"), nonOpening, inert("or", "InertOr"), high]),
]);

/* ---- the material conditional, as a ladder: covered => requirement met ----
   `IF P THEN Q ELSE TRUE` IS `NOT P OR Q`, so the conditional is not a special
   node — it is an OR whose first rung is a NOT. Drawn that way the reader can SEE
   the two ways a window satisfies A.3: escape the antecedent, or meet the
   consequent. The NOT gets a scope frame + an inverter bubble (DESIGN §21). */
const rule = or([
  inert("the window complies with A.3 if either", "InertOr"),
  not(covers),
  inert("or", "InertOr"),
  requirement,
]);

const fn: FunDecl = {
  id: nid(),
  name: "window complies with A.3",
  params: ["w"],
  body: rule,
};

// ASCII wants connectives ON the wire (a code cell has no sub-line room for the
// SVG's above/below-wire hairline offsets).
const spec = (extra = {}) =>
  defaultViewSpec({ connectiveStyle: "on-wire", ...extra });

const tm = monoMetrics();
const render = (vs: ReturnType<typeof spec>) =>
  sceneToAscii(layout(fn, vs, tm, ASCII_GEOMETRY));

const banner = (t: string) =>
  console.log(`\n─── ${t} ${"─".repeat(Math.max(0, 66 - t.length))}\n`);

banner("1. structure only (no valuation)");
console.log(render(spec()));

/* a real window: upper-floor, in a wall, obscure-glazed, but it OPENS below 1.7m
   -> not compliant. Watch the current die. */
const vals = new Map<NodeId, UBoolValue>([
  [upper.id, "TrueV"],
  [inWall.id, "TrueV"],
  [inRoof.id, "FalseV"],
  [obscure.id, "TrueV"],
  [nonOpening.id, "FalseV"],
  [high.id, "FalseV"],
]);
banner("2. a covered, non-compliant window (current flow on)");
console.log(render(spec({ valuation: vals, showCurrent: true })));

/* the same window, but we PRESUME the glazing rather than checking it */
const presumed = new Map<NodeId, Provenance>([[obscure.id, "default"]]);
banner("3. same, but `obscure-glazed` rides a TYPICALLY presumption");
console.log(
  render(spec({ valuation: vals, provenance: presumed, showCurrent: true })),
);

banner("4. folded: the antecedent collapses to a placeholder");
console.log(render(spec({ foldSet: new Set([covers.id]) })));

banner("5. pure-ASCII fallback (no Unicode box-drawing)");
console.log(
  sceneToAscii(layout(fn, spec(), tm, ASCII_GEOMETRY), { pure: true }),
);
