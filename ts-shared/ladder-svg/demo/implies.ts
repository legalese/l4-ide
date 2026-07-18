/**
 * IMPLIES demo (DESIGN §25) — the seam, the changeover, and the two sinks.
 *
 * A.3 as `covers IMPLIES requirement-met`, drawn as ONE path with TWO lamps. The
 * point of the exercise is the verdict table: count the lit lamps.
 *
 *   scope ✗   → both dark  → N/A: the rule never bit (the break is IN THE SCOPE)
 *   scope ?   → both dark  → undetermined
 *   ✓ then ✓  → GREEN      → complies
 *   ✓ then ✗  → RED        → in breach
 *
 * Run: cd ts-shared/ladder-svg && npx tsx demo/implies.ts
 */
import { mkdirSync, writeFileSync } from "node:fs";
import {
  layout,
  estimateMetrics,
  sceneToAscii,
  monoMetrics,
  toMermaidRailroad,
  ASCII_GEOMETRY,
  defaultViewSpec,
} from "@repo/ladder-core";
import { sceneToSvg } from "../src/index.js";
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
  ViewSpec,
} from "@repo/ladder-core";

let c = 0;
const nid = () => ++c;
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
const or = (args: IRExpr[], label?: string): Or => ({
  $type: "Or",
  id: nid(),
  args,
  label,
});
const implies = (
  scope: IRExpr,
  requirement: IRExpr,
  seam: string,
): Implies => ({
  $type: "Implies",
  id: nid(),
  scope,
  requirement,
  seam,
});

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

const glazed = leaf("obscure-glazed");
const shut = leaf("non-opening");
const high = leaf("openable parts ≥ 1.7m");
const met = and(
  [
    glazed,
    inert("and", "InertAnd"),
    or([inert("either", "InertOr"), shut, inert("or", "InertOr"), high]),
  ],
  "A.3 requirement met",
);

// §25e: the seam keeps the connective as the DRAFTER wrote it. The L4 source for this
// rule reads `\`A.3 covers\` w  IMPLIES  \`A.3 requirement met by\` w`, so the picture
// says IMPLIES. It would read more sweetly as MUST — but the source did not say MUST,
// and a diagram that says more than its source is the very fault this whole exercise
// convicts flowcharts of. (This is exactly what `seamLabel` emits from real L4.)
const fn: FunDecl = {
  id: nid(),
  name: "window complies with A.3",
  params: ["w"],
  body: implies(covers, met, "IMPLIES"),
};

const V = (m: Record<number, UBoolValue>) =>
  new Map<NodeId, UBoolValue>(
    Object.entries(m).map(([k, v]) => [Number(k), v]),
  );

const CASES: { name: string; vals: Map<NodeId, UBoolValue> }[] = [
  {
    name: "1. a GROUND-FLOOR window — the rule never reaches it (expect: N/A, both lamps dark)",
    vals: V({
      [upper.id]: "FalseV",
      [inWall.id]: "TrueV",
      [inRoof.id]: "FalseV",
    }),
  },
  {
    name: "2. a covered, COMPLIANT window (expect: GREEN)",
    vals: V({
      [upper.id]: "TrueV",
      [inWall.id]: "TrueV",
      [inRoof.id]: "FalseV",
      [glazed.id]: "TrueV",
      [shut.id]: "TrueV",
      [high.id]: "FalseV",
    }),
  },
  {
    name: "3. a covered window IN BREACH — glazed, but it opens below 1.7m (expect: RED)",
    vals: V({
      [upper.id]: "TrueV",
      [inWall.id]: "TrueV",
      [inRoof.id]: "FalseV",
      [glazed.id]: "TrueV",
      [shut.id]: "FalseV",
      [high.id]: "FalseV",
    }),
  },
  {
    // NOTE the near-miss: setting non-opening=✗ AND ≥1.7m=✗ would make the inner OR
    // definitively FALSE, and `Unknown ∧ False = False` — so the requirement fails
    // whatever the glazing turns out to be, and the lamp SHOULD go red. Three-valued
    // logic short-circuits, and the picture must not pretend otherwise. To be genuinely
    // undetermined, the requirement has to be genuinely unasked.
    name: "4. covered, but the requirement is not yet asked (expect: BOTH DARK — undetermined, NOT breach)",
    vals: V({
      [upper.id]: "TrueV",
      [inWall.id]: "TrueV",
      [inRoof.id]: "FalseV",
    }),
  },
  {
    name: "5. covered; glazing unknown, but it already opens below 1.7m (expect: RED — the breach is settled without asking)",
    vals: V({
      [upper.id]: "TrueV",
      [inWall.id]: "TrueV",
      [inRoof.id]: "FalseV",
      [shut.id]: "FalseV",
      [high.id]: "FalseV",
    }),
  },
];

const spec = (vals: Map<NodeId, UBoolValue>): ViewSpec =>
  defaultViewSpec({
    valuation: vals,
    showCurrent: true,
    connectiveStyle: "on-wire",
  });

const tm = monoMetrics();
mkdirSync(new URL("out/", import.meta.url), { recursive: true });

for (const { name, vals } of CASES) {
  console.log(`\n─── ${name}\n`);
  console.log(sceneToAscii(layout(fn, spec(vals), tm, ASCII_GEOMETRY)));
}

// SVG, for the eye
CASES.forEach(({ vals }, i) => {
  const svg = sceneToSvg(layout(fn, spec(vals), estimateMetrics));
  writeFileSync(new URL(`out/implies-${i + 1}.svg`, import.meta.url), svg);
});

console.log(
  "\n─── and the same rule as Mermaid railroad (§25.6, the bottleneck)\n",
);
console.log(
  toMermaidRailroad(fn, {
    factor: new Set([covers.id, met.id]),
    frontmatter: false,
  }),
);
