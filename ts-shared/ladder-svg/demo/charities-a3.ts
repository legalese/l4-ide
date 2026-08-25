/**
 * A3 poster: `is a charitable purpose` from the Charities (Jersey) Law 2014
 * encoding (part-3-charity-test.l4, lines 122-237) — the Article 6(1) head
 * disjunction with its Article 6(2) gates and extensions, minus the Article
 * 6(5) political-purpose override.
 *
 * Faithful to the L4: extensions ((d),(f),(n),(p)) are nested ORs; gates
 * ((h),(i)) are nested ANDs; 6(5) is AND NOT at the top level. Labels are the
 * statutory phrases, trimmed for the page.
 *
 * Run: cd ts-shared/ladder-svg && npx tsx demo/charities-a3.ts
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { layout, estimateMetrics, defaultViewSpec } from "@repo/ladder-core";
import { sceneToSvg } from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  Inert,
  And,
  Or,
  Not,
  State,
  NodeId,
} from "@repo/ladder-core";

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

// ---- Article 6(1), heads (a)-(p), with the 6(2) qualifications in place ----
const headsOr = or([
  inert("Article 6(1): the charitable purposes are —", "InertOr"),
  leaf("(a) the prevention or relief of poverty"),
  leaf("(b) the advancement of education"),
  leaf("(c) the advancement of religion"),
  // (d) EXTENDED by 6(2)(a)
  or([
    leaf("(d) the advancement of health"),
    inert("which includes, by 6(2)(a) —", "InertOr"),
    leaf("the prevention or relief of sickness, disease or human suffering"),
  ]),
  leaf("(e) the saving of lives"),
  // (f) EXTENDED by 6(2)(b)
  or([
    leaf("(f) the advancement of citizenship or community development"),
    inert("which includes, by 6(2)(b) —", "InertOr"),
    leaf("rural or urban regeneration"),
    leaf(
      "the promotion of civic responsibility, volunteering, the voluntary sector",
    ),
  ]),
  leaf("(g) the advancement of the arts, heritage, culture or science"),
  // (h) GATED by 6(2)(c)
  and([
    leaf("(h) the advancement of public participation in sport"),
    inert("where, by 6(2)(c),", "InertAnd"),
    leaf("the sport involves physical skill and exertion"),
  ]),
  // (i) GATED by 6(2)(d) — the head AND one of the two limbs
  and([
    leaf("(i) the provision of recreational facilities or activities…"),
    inert("but only, by 6(2)(d), where they are", "InertAnd"),
    or([
      leaf("primarily intended for persons who have need of them…"),
      leaf("available to members of the public at large"),
    ]),
  ]),
  leaf(
    "(j) the advancement of human rights, conflict resolution or reconciliation",
  ),
  leaf("(k) the promotion of religious or racial harmony"),
  leaf("(l) the promotion of equality and diversity"),
  leaf("(m) the advancement of environmental protection or improvement"),
  // (n) EXTENDED by 6(2)(e)
  or([
    leaf(
      "(n) the relief of those in need by reason of age, ill-health, disability…",
    ),
    inert("which includes, by 6(2)(e) —", "InertOr"),
    leaf("relief given by the provision of accommodation or care"),
  ]),
  leaf("(o) the advancement of animal welfare"),
  // (p) EXTENDED by 6(2)(f), which DEEMS philosophical belief analogous
  or([
    leaf(
      "(p) any other purpose reasonably regarded as analogous to (a) to (o)",
    ),
    inert("or, deemed analogous by 6(2)(f) —", "InertOr"),
    leaf(
      "the advancement of a philosophical belief (whether or not involving belief in a god)",
    ),
  ]),
]);

// ---- Article 6(5): the political-purpose override, AND NOT at the top ----
const political = leaf(
  "6(5): advancing a political party, or promoting a candidate for election",
);
const top = and([
  headsOr,
  inert("and, irrespective of the above,", "InertAnd"),
  not(political),
]);

const fn: FunDecl = {
  id: nid(),
  name: "is a charitable purpose — Charities (Jersey) Law 2014, Articles 6(1), 6(2) and 6(5)",
  params: [],
  body: top,
};

// ---- all operative atoms live; ink theme for print ----
function leafIds(e: IRExpr, acc: NodeId[] = []): NodeId[] {
  if (e.$type === "And" || e.$type === "Or")
    e.args.forEach((a) => leafIds(a, acc));
  else if (e.$type === "Not") leafIds(e.negand, acc);
  else if (e.$type !== "InertE") acc.push(e.id);
  return acc;
}
const allLive = new Map<NodeId, State>(leafIds(top).map((id) => [id, "live"]));

const scene = layout(fn, defaultViewSpec({ states: allLive }), estimateMetrics);
const svg = sceneToSvg(scene, "ink");

const outDir = fileURLToPath(new URL("./out/", import.meta.url));
mkdirSync(outDir, { recursive: true });
writeFileSync(outDir + "charities-art6-a3.svg", svg);
console.log(
  `wrote charities-art6-a3.svg  (${scene.size.w.toFixed(0)}x${scene.size.h.toFixed(0)})`,
);
