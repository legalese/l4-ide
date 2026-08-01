/**
 * Ladder playground (DESIGN target C, decoupled from the IDE webview). Goes from
 * an INERT-STYLE L4 program straight to an interactive ladder diagram:
 *
 *   L4 textarea → POST /render (serve.mjs → real jl4-lsp) → RenderAsLadderInfo
 *   → fromVizFunDecl (viz-adapter) → layout → sceneToSvg → interactive SVG.
 *
 * Interactions (pure core, same as app.ts): click a BOX to cycle U→T→F→U; click
 * a HEADING / CONNECTOR / ▸ caret to fold; expand-all / collapse-all / reset.
 * A decision picker switches between the DECIDEs the module exposes. TYPICALLY
 * defaults arrive as provenance and render tentative (§22).
 *
 * HYDRATION. A leaf that references another DECIDE in the module (e.g.
 * `first limb OF s, i`) is drawn as a dotted reference; click it to splice that
 * DECIDE's whole tree in place — recursively, so a limb's own sub-conditions
 * become hydratable in turn. Click the hydrated heading to collapse it back.
 * We do this CLIENT-SIDE from the bodies /render already returned (the LSP marks
 * applied refs canInline:false — an open TODO there), so it needs no backend.
 * No framework.
 *
 * E1 Step 4: the DOM half is gone from this file. Its `flipIndex` was a near-verbatim
 * copy of app.ts's (its own section header said so), and both are now the one definition
 * in `src/flip.ts`. The two behaviours that are genuinely this demo's — routing a click
 * to hydrate/collapse instead of cycle/fold, and dotting the hydratable refs after the
 * draw — survive as `onAct` and `onRender`, which is exactly the split the controller
 * exists to draw. Pan/zoom (seam S6) comes along for free.
 */
import {
  defaultViewSpec,
  fromVizFunDecl,
  expandSentences,
} from "@repo/ladder-core";
import { LadderController } from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  And,
  NodeId,
  UBoolValue,
  Provenance,
  ConnectiveStyle,
} from "@repo/ladder-core";

const $ = (id: string) => document.getElementById(id)!;
const src = $("src") as HTMLTextAreaElement;
const picker = $("decision") as HTMLSelectElement;
const examples = $("examples") as HTMLSelectElement;
const status = $("status");
const container = $("ladder");
const sentList = $("sentences") as HTMLOListElement;
const sentCount = $("sent-count");

/* ------------------------------------------------------------------- state */
type Decoded = { fn: FunDecl; provenance: Map<NodeId, Provenance> };
let decisions: Decoded[] = [];
let cur: Decoded | null = null;
const nameMap = new Map<string, Decoded>(); // cleaned DECIDE name -> its tree
const foldSet = new Set<NodeId>();
const valuation = new Map<NodeId, UBoolValue>();
let connective: ConnectiveStyle = "straddle-wire";

/* hydration: display ids currently expanded, and a stable id-remap for the
 * subtrees we splice in (so ids survive re-render for FLIP + click + fold). */
const hydrated = new Set<NodeId>();
const remapCache = new Map<string, NodeId>();
let remapCounter = 1_000_000;
const rid = (key: string): NodeId => {
  let v = remapCache.get(key);
  if (v == null) remapCache.set(key, (v = ++remapCounter));
  return v;
};

const clean = (s: string) => s.replace(/`/g, "").trim();
/** The DECIDE a leaf references, if any: the name before " OF " (applied) or the
 *  whole label (nullary), matched against the module's decisions. */
function refNameOf(e: IRExpr): string | null {
  if (e.$type !== "UBoolVar" && e.$type !== "App") return null;
  const label = e.$type === "App" ? e.label : e.label;
  const head = clean(label.split(" OF ")[0]);
  return nameMap.has(head) ? head : null;
}

/* per-render scratch, rebuilt by buildDisplay each frame */
let activeProv = new Map<NodeId, Provenance>();
let collapsedRefs = new Set<NodeId>(); // display id -> clicking hydrates
let wrappers = new Map<NodeId, NodeId>(); // wrapper group id -> the ref id it stands for

/** Build the tree actually shown: copy `node` (remapping ids via `remap`), and
 *  where a hydratable ref is expanded, splice the referenced DECIDE's body
 *  (recursively) under a labelled group whose heading collapses it again. */
function buildDisplay(node: IRExpr, remap: (id: NodeId) => NodeId): IRExpr {
  const id = remap(node.id);
  switch (node.$type) {
    case "And":
    case "Or":
      return {
        ...node,
        id,
        args: node.args.map((a) => buildDisplay(a, remap)),
      };
    case "Not":
      return { ...node, id, negand: buildDisplay(node.negand, remap) };
    case "InertE":
      return { ...node, id };
    default: {
      const ref = refNameOf(node);
      if (ref && hydrated.has(id)) {
        const target = nameMap.get(ref)!;
        const sub = (o: NodeId) => rid(`${id}:${o}`);
        for (const [o, p] of target.provenance) activeProv.set(sub(o), p);
        const inner = buildDisplay(target.fn.body, sub);
        const wrapperId = rid(`${id}:__wrap`);
        wrappers.set(wrapperId, id);
        const group: And = {
          $type: "And",
          id: wrapperId,
          args: [inner],
          label: clean(target.fn.name),
        };
        return group;
      }
      if (ref) collapsedRefs.add(id);
      return { ...node, id };
    }
  }
}

/* structural id walks over the DISPLAY tree (buttons operate on what's shown) */
let lastDisplayFn: FunDecl | null = null;
function walk(e: IRExpr, leaves: NodeId[], groups: NodeId[]): void {
  if (e.$type === "And" || e.$type === "Or") {
    groups.push(e.id);
    e.args.forEach((a) => walk(a, leaves, groups));
  } else if (e.$type === "Not") walk(e.negand, leaves, groups);
  else if (e.$type !== "InertE") leaves.push(e.id);
}

/* ------------------------------------------------------------------ the controller */
/** Nothing is rendered until a module comes back from the LSP, so the controller starts on
 *  an empty tree and `render()` swaps in the real one via `setFunDecl`. */
const EMPTY_FN: FunDecl = {
  id: 0,
  name: "",
  params: [],
  body: { $type: "InertE", id: 0, text: "", context: "InertAnd" },
};

/** Routing is conditional on this demo's own hydration state, and the controller never
 *  sees it: it reports an act, the host decides what the act MEANS. */
const controller = new LadderController(container, EMPTY_FN, {
  onAct: (act) => {
    if (act.t === "value")
      collapsedRefs.has(act.id) ? hydrate(act.id) : cycleValue(act.id);
    else
      wrappers.has(act.id)
        ? dehydrate(wrappers.get(act.id)!)
        : toggleFold(act.id);
  },
  /** Post-draw decoration the ViewSpec cannot express: which leaves are hydratable refs
   *  and which headings stand for a hydrated limb. `playground.html:144-160` styles both
   *  classes and is unchanged. This hook is why `onRender` exists. */
  onRender: (svg) => {
    svg.querySelectorAll<SVGElement>("[data-value]").forEach((el) => {
      if (collapsedRefs.has(Number(el.getAttribute("data-value")))) {
        el.classList.add("lad-ref");
        el.setAttribute("data-ref", "1");
      }
    });
    svg.querySelectorAll<SVGElement>("[data-fold]").forEach((el) => {
      if (wrappers.has(Number(el.getAttribute("data-fold"))))
        el.classList.add("lad-hydrated");
    });
  },
});

function render(animate: boolean) {
  if (!cur) return;
  // rebuild the display tree (with hydrations spliced in) and its provenance
  activeProv = new Map(cur.provenance);
  collapsedRefs = new Set();
  wrappers = new Map();
  const body = buildDisplay(cur.fn.body, (x) => x);
  const fn: FunDecl = { ...cur.fn, body };
  lastDisplayFn = fn;

  // The display tree is rebuilt every frame, so the controller's `fn` is swapped every
  // frame too — but `keepBaseline` when animating, because a hydration IS the thing the
  // FLIP is there to show. `animate: false` (a fresh decision) drops the baseline.
  controller.setFunDecl(fn, animate);
  controller.render(
    defaultViewSpec({
      valuation,
      foldSet,
      provenance: activeProv,
      connectiveStyle: connective,
      showCurrent: true,
    }),
  );
  renderSentences();
}

/** Combination view: enumerate every way to satisfy the rule (the hydrated
 *  display tree, so expanding a limb expands its combinations too). */
function renderSentences() {
  if (!lastDisplayFn) return;
  const ss = expandSentences(lastDisplayFn, foldSet);
  sentCount.textContent = `(${ss.length})`;
  sentList.innerHTML = "";
  for (const s of ss) {
    const li = document.createElement("li");
    li.textContent = s;
    sentList.appendChild(li);
  }
}

const NEXT: Record<UBoolValue, UBoolValue> = {
  UnknownV: "TrueV",
  TrueV: "FalseV",
  FalseV: "UnknownV",
};
function cycleValue(id: NodeId) {
  const nx = NEXT[valuation.get(id) ?? "UnknownV"];
  if (nx === "UnknownV") valuation.delete(id);
  else valuation.set(id, nx);
  render(true);
}
function toggleFold(id: NodeId) {
  foldSet.has(id) ? foldSet.delete(id) : foldSet.add(id);
  render(true);
}
function hydrate(id: NodeId) {
  hydrated.add(id);
  render(true);
}
function dehydrate(id: NodeId) {
  hydrated.delete(id);
  render(true);
}

/* ------------------------------------------------------------- load a decision */
function selectDecision(i: number) {
  cur = decisions[i] ?? null;
  foldSet.clear();
  valuation.clear();
  hydrated.clear();
  remapCache.clear();
  // render(false) drops the FLIP baseline and refits — a different decision has no
  // correspondence with the one before it.
  render(false);
}

async function doRender() {
  status.textContent = "rendering…";
  try {
    const r = await fetch("/render", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ l4: src.value }),
    });
    const data = await r.json();
    if (data.error) throw new Error(data.error);
    decisions = (data.funcs ?? [])
      .filter((f: { funDecl?: unknown }) => f.funDecl)
      .map((f: { funDecl: Parameters<typeof fromVizFunDecl>[0] }) => {
        const { fn, provenance } = fromVizFunDecl(f.funDecl);
        return { fn, provenance };
      });
    nameMap.clear();
    decisions.forEach((d) => nameMap.set(clean(d.fn.name), d));
    picker.innerHTML = "";
    decisions.forEach((d, i) => {
      const o = document.createElement("option");
      o.value = String(i);
      o.textContent = d.fn.name;
      picker.appendChild(o);
    });
    if (!decisions.length) {
      status.textContent = "no visualizable DECIDE found";
      container.innerHTML = "";
      return;
    }
    status.textContent = `${decisions.length} decision(s)`;
    selectDecision(0);
  } catch (e) {
    status.textContent = "error: " + String(e);
  }
}

/* ------------------------------------------------------------------- controls */
$("render").addEventListener("click", doRender);
picker.addEventListener("change", () => selectDecision(Number(picker.value)));
($("connective") as HTMLSelectElement).addEventListener("change", (e) => {
  connective = (e.target as HTMLSelectElement).value as ConnectiveStyle;
  render(true);
});
$("expand-all").addEventListener("click", () => {
  foldSet.clear();
  render(true);
});
$("collapse-all").addEventListener("click", () => {
  if (!lastDisplayFn) return;
  const g: NodeId[] = [];
  walk(lastDisplayFn.body, [], g);
  g.forEach((id) => foldSet.add(id));
  render(true);
});
$("all-true").addEventListener("click", () => {
  if (!lastDisplayFn) return;
  const l: NodeId[] = [];
  walk(lastDisplayFn.body, l, []);
  l.forEach((id) => valuation.set(id, "TrueV"));
  render(true);
});
$("reset").addEventListener("click", () => {
  valuation.clear();
  render(true);
});
/* view controls — the controller draws no chrome of its own */
$("zoom-in").addEventListener("click", () => controller.zoom(1.25));
$("zoom-out").addEventListener("click", () => controller.zoom(1 / 1.25));
$("fit").addEventListener("click", () => controller.fit());

async function loadExample(id: string) {
  const t = await (await fetch("/example?id=" + encodeURIComponent(id))).text();
  src.value = t;
  await doRender();
}
examples.addEventListener("change", () => loadExample(examples.value));

/* ------------------------------------------------------------------- boot */
(async () => {
  const list: { id: string; label: string }[] = await (
    await fetch("/examples")
  ).json();
  examples.innerHTML = "";
  list.forEach((e) => {
    const o = document.createElement("option");
    o.value = e.id;
    o.textContent = e.label;
    examples.appendChild(o);
  });
  if (list.length) await loadExample(list[0].id);
})();
