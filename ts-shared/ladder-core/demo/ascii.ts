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
  toMermaidRailroad,
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
  Implies,
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
const and = (args: IRExpr[], label?: string): And => ({
  $type: "And",
  id: nid(),
  args,
  label,
});
const or = (args: IRExpr[]): Or => ({ $type: "Or", id: nid(), args });
const implies = (
  scope: IRExpr,
  requirement: IRExpr,
  seam: string,
): Implies => ({ $type: "Implies", id: nid(), scope, requirement, seam });

/* ---- A.3 covers w:  upper floor AND (in a wall OR in a roof slope) ---- */
const upper = leaf("on an upper floor");
const inWall = leaf("in a wall");
const inRoof = leaf("in a roof slope");
const covers = and(
  [
    upper,
    inert("and", "InertAnd"),
    or([
      inert("in a side elevation:", "InertOr"),
      inWall,
      inert("or", "InertOr"),
      inRoof,
    ]),
  ],
  "A.3 covers this window",
);

/* ---- A.3 requirement met:  obscure-glazed AND (non-opening OR >= 1.7m) ---- */
const obscure = leaf("obscure-glazed");
const nonOpening = leaf("non-opening");
const high = leaf("openable parts ≥ 1.7m up");
const requirement = and(
  [
    obscure,
    inert("and", "InertAnd"),
    or([inert("either", "InertOr"), nonOpening, inert("or", "InertOr"), high]),
  ],
  "A.3 requirement met",
);

/* ---- the material conditional, as a SEAM (DESIGN §25) ----------------------
   This demo used to build the rule as `NOT covers OR requirement` — classically
   perfect, and a lie about the shape. It drew the vacuous escape ("the rule never
   reached your window") as a RUNG: a co-equal way of complying, sitting right
   alongside actually meeting the requirement. No one reading a statute thinks
   that way; on a form they would write "N/A".

   So implication is a real node now, drawn as ONE path with TWO sinks. Current
   leaves the scope panel only if the rule bites you, crosses the seam, and the
   requirement's verdict throws a changeover to the green lamp or the red one.
   Vacuity needs no ink at all: if the scope does not conduct, nothing leaves it
   and NEITHER lamp lights. That is N/A, and you can see exactly where it stopped. */
const rule = implies(covers, requirement, "IMPLIES");

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

/* Both of the doc's exhibits come from THIS tree, so they cannot drift apart: the
   ASCII fence above and the Mermaid fence below are two renderings of one IR. */
banner("6. the same rule as a Mermaid railroad (§24 carrier I-d)");
console.log(
  toMermaidRailroad(fn, {
    factor: new Set([covers.id, requirement.id]),
    frontmatter: false,
  }),
);
