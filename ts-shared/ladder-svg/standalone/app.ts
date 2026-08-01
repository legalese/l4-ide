/**
 * Standalone interactive ladder (DESIGN target C, §19). Builds the s415 second-limb
 * tree and drives it live through the PURE core:
 *   • click a BOX  -> cycle its value  U → T → F → U  (a folded placeholder cycles
 *     the parent's OVERRIDE / pin — assign the parent without naming a witness child)
 *   • click a HEADING, a CONNECTOR, or a ▸ CARET -> fold / expand that group
 *   • drag to pan, ⌘/ctrl-wheel to zoom, double-click or `fit` to re-frame (seam S6)
 *   • connective-style + fold checkboxes + reset in the control bar
 * Every interaction just mutates a ViewSpec and re-renders (the controller FLIPs).
 *
 * E1 Step 4: this file used to own the DOM — its own `flipIndex`, its own invert/play
 * loop, its own per-node click listeners re-attached on every render, its own sizing.
 * All of that is now `LadderController`, and this demo is the proof that the factoring
 * is real (EMBEDDABLE.md §3.4). It also moved from `estimateMetrics` to the controller's
 * default `canvasMetrics()` — so the diagram is a little wider than it used to be, and
 * that is the S7/A4 fix landing, not a regression.
 *
 * Bundled to dist/app.js by build.sh (esbuild). No framework, no workspace deps.
 */
import { defaultViewSpec } from "@repo/ladder-core";
import { LadderController } from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  Inert,
  And,
  Or,
  NodeId,
  UBoolValue,
  ConnectiveStyle,
} from "@repo/ladder-core";

/* ----------------------------------------------------- s415 fixture (inert style) */
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

const byDeceiving = leaf("by deceiving");
const concealment = leaf("dishonest concealment");
const deception = or([
  inert("there is a deception (Expl. 1)", "InertOr"),
  byDeceiving,
  inert("or", "InertOr"),
  concealment,
]);
const harm = or([
  leaf("body"),
  leaf("mind"),
  leaf("reputation"),
  inert("or", "InertOr"),
  leaf("property"),
]);
const second = and([
  deception,
  leaf("intentionally"),
  inert("induces an act or omission that", "InertAnd"),
  leaf("causes harm"),
  inert("to any person in", "InertAnd"),
  harm,
]);
const fn: FunDecl = {
  id: nid(),
  name: "is said to cheat (second limb)",
  params: [],
  body: second,
};

function leafIds(e: IRExpr, acc: NodeId[] = []): NodeId[] {
  if (e.$type === "And" || e.$type === "Or")
    e.args.forEach((a) => leafIds(a, acc));
  else if (e.$type === "Not") leafIds(e.negand, acc);
  else if (e.$type !== "InertE") acc.push(e.id);
  return acc;
}
const allLeaves = leafIds(second);

/* ------------------------------------------------------------------------ state */
const foldSet = new Set<NodeId>();
const valuation = new Map<NodeId, UBoolValue>();
let connective: ConnectiveStyle = "straddle-wire";

const controller = new LadderController(
  document.getElementById("ladder") as HTMLElement,
  fn,
  {
    onAct: (act) =>
      act.t === "value" ? cycleValue(act.id) : toggleFold(act.id),
  },
);

function render() {
  controller.render(
    defaultViewSpec({
      valuation,
      foldSet,
      connectiveStyle: connective,
      showCurrent: true,
    }),
  );
  syncControls();
}

const NEXT: Record<UBoolValue, UBoolValue> = {
  UnknownV: "TrueV",
  TrueV: "FalseV",
  FalseV: "UnknownV",
};
function cycleValue(id: NodeId) {
  const cur = valuation.get(id) ?? "UnknownV";
  const next = NEXT[cur];
  if (next === "UnknownV") valuation.delete(id);
  else valuation.set(id, next);
  render();
}
function toggleFold(id: NodeId) {
  if (foldSet.has(id)) foldSet.delete(id);
  else foldSet.add(id);
  render();
}
function setFold(id: NodeId, on: boolean) {
  if (on) foldSet.add(id);
  else foldSet.delete(id);
  render();
}

function syncControls() {
  (document.getElementById("fold-deception") as HTMLInputElement).checked =
    foldSet.has(deception.id);
  (document.getElementById("fold-harm") as HTMLInputElement).checked =
    foldSet.has(harm.id);
}

/* --------------------------------------------------------------------- controls */
(document.getElementById("connective") as HTMLSelectElement).addEventListener(
  "change",
  (e) => {
    connective = (e.target as HTMLSelectElement).value as ConnectiveStyle;
    render();
  },
);
(
  document.getElementById("fold-deception") as HTMLInputElement
).addEventListener("change", (e) =>
  setFold(deception.id, (e.target as HTMLInputElement).checked),
);
(document.getElementById("fold-harm") as HTMLInputElement).addEventListener(
  "change",
  (e) => setFold(harm.id, (e.target as HTMLInputElement).checked),
);
document.getElementById("all-true")!.addEventListener("click", () => {
  allLeaves.forEach((id) => valuation.set(id, "TrueV"));
  render();
});
document.getElementById("reset")!.addEventListener("click", () => {
  valuation.clear();
  render();
});

/* view controls — the controller draws no chrome of its own (S5/6b stay untouched) */
document
  .getElementById("zoom-in")!
  .addEventListener("click", () => controller.zoom(1.25));
document
  .getElementById("zoom-out")!
  .addEventListener("click", () => controller.zoom(1 / 1.25));
document
  .getElementById("fit")!
  .addEventListener("click", () => controller.fit());

render();
