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
 */
import {
  layout,
  estimateMetrics,
  defaultViewSpec,
  fromVizFunDecl,
  expandSentences,
} from "@repo/ladder-core";
import { sceneToSvg } from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  And,
  NodeId,
  UBoolValue,
  Provenance,
  ConnectiveStyle,
  Scene,
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
let lastScene: Scene | null = null;
const tm = estimateMetrics;

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

/* --------------------------------------------------------------- FLIP (app.ts) */
type Pos = { x: number; y: number };
function flipIndex(scene: Scene): Map<string, Pos> {
  const m = new Map<string, Pos>();
  for (const p of scene.prims) {
    if (p.kind === "box") m.set(`box:${p.id}`, { x: p.rect.x, y: p.rect.y });
    else if (p.kind === "text" && p.id != null)
      m.set(`label:${p.id}`, { x: p.at.x, y: p.at.y });
  }
  return m;
}

function render(animate: boolean) {
  if (!cur) return;
  // rebuild the display tree (with hydrations spliced in) and its provenance
  activeProv = new Map(cur.provenance);
  collapsedRefs = new Set();
  wrappers = new Map();
  const body = buildDisplay(cur.fn.body, (x) => x);
  const fn: FunDecl = { ...cur.fn, body };
  lastDisplayFn = fn;

  const vs = defaultViewSpec({
    valuation,
    foldSet,
    provenance: activeProv,
    connectiveStyle: connective,
    showCurrent: true,
  });
  const scene = layout(fn, vs, tm);
  const old = lastScene && animate ? flipIndex(lastScene) : null;
  container.innerHTML = sceneToSvg(scene);
  const svg = container.querySelector("svg") as SVGSVGElement;
  svg.style.maxWidth = "100%";
  svg.style.height = "auto";

  if (old) {
    const next = flipIndex(scene);
    const play: SVGElement[] = [];
    svg.querySelectorAll<SVGElement>("[data-fnid]").forEach((el) => {
      const nid = el.getAttribute("data-fnid")!;
      const key = `${el.tagName.toLowerCase() === "rect" ? "box" : "label"}:${nid}`;
      const o = old.get(key);
      const n = next.get(key);
      if (o && n && (o.x !== n.x || o.y !== n.y)) {
        el.style.transition = "none";
        el.style.transform = `translate(${o.x - n.x}px, ${o.y - n.y}px)`;
        play.push(el);
      } else if (!o && n) {
        el.style.transition = "none";
        el.style.opacity = "0";
        play.push(el);
      }
    });
    const wires = Array.from(svg.querySelectorAll<SVGElement>(".lad-wire"));
    wires.forEach(
      (el) => ((el.style.transition = "none"), (el.style.opacity = "0")),
    );
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        play.forEach((el) => {
          el.style.transition =
            "transform 300ms cubic-bezier(.2,.7,.2,1), opacity 300ms ease";
          el.style.transform = "";
          el.style.opacity = "";
        });
        wires.forEach(
          (el) => (
            (el.style.transition = "opacity 320ms ease"),
            (el.style.opacity = "")
          ),
        );
      }),
    );
  }
  lastScene = scene;

  // wire clicks: refs hydrate, hydrated headings collapse, else cycle / fold
  svg.querySelectorAll<SVGElement>("[data-value]").forEach((el) => {
    const nid = Number(el.getAttribute("data-value"));
    if (collapsedRefs.has(nid)) {
      el.classList.add("lad-ref");
      el.setAttribute("data-ref", "1");
      el.addEventListener("click", () => hydrate(nid));
    } else {
      el.addEventListener("click", () => cycleValue(nid));
    }
  });
  svg.querySelectorAll<SVGElement>("[data-fold]").forEach((el) => {
    const nid = Number(el.getAttribute("data-fold"));
    if (wrappers.has(nid)) {
      el.classList.add("lad-hydrated");
      el.addEventListener("click", () => dehydrate(wrappers.get(nid)!));
    } else {
      el.addEventListener("click", () => toggleFold(nid));
    }
  });
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
  lastScene = null;
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
