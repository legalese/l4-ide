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
 * defaults arrive as provenance and render tentative (§22). No framework.
 */
import {
  layout,
  sceneToSvg,
  estimateMetrics,
  defaultViewSpec,
  fromVizFunDecl,
  expandSentences,
} from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  NodeId,
  UBoolValue,
  Provenance,
  ConnectiveStyle,
  Scene,
} from "../src/index.js";

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
const foldSet = new Set<NodeId>();
const valuation = new Map<NodeId, UBoolValue>();
let connective: ConnectiveStyle = "straddle-wire";
let lastScene: Scene | null = null;
const tm = estimateMetrics;

/* structural id walks (mirror app.ts) */
function walk(e: IRExpr, leaves: NodeId[], groups: NodeId[]): void {
  if (e.$type === "And" || e.$type === "Or") {
    groups.push(e.id);
    e.args.forEach((a) => walk(a, leaves, groups));
  } else if (e.$type === "Not") walk(e.negand, leaves, groups);
  else if (e.$type !== "InertE") leaves.push(e.id);
}
const leafIds = (fn: FunDecl) => {
  const l: NodeId[] = [];
  walk(fn.body, l, []);
  return l;
};
const groupIds = (fn: FunDecl) => {
  const g: NodeId[] = [];
  walk(fn.body, [], g);
  return g;
};

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
  const vs = defaultViewSpec({
    valuation,
    foldSet,
    provenance: cur.provenance,
    connectiveStyle: connective,
    showCurrent: true,
  });
  const scene = layout(cur.fn, vs, tm);
  const old = lastScene && animate ? flipIndex(lastScene) : null;
  container.innerHTML = sceneToSvg(scene);
  const svg = container.querySelector("svg") as SVGSVGElement;
  svg.style.maxWidth = "100%";
  svg.style.height = "auto";

  if (old) {
    const next = flipIndex(scene);
    const play: SVGElement[] = [];
    svg.querySelectorAll<SVGElement>("[data-fnid]").forEach((el) => {
      const id = el.getAttribute("data-fnid")!;
      const key = `${el.tagName.toLowerCase() === "rect" ? "box" : "label"}:${id}`;
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

  svg
    .querySelectorAll<SVGElement>("[data-value]")
    .forEach((el) =>
      el.addEventListener("click", () =>
        cycleValue(Number(el.getAttribute("data-value"))),
      ),
    );
  svg
    .querySelectorAll<SVGElement>("[data-fold]")
    .forEach((el) =>
      el.addEventListener("click", () =>
        toggleFold(Number(el.getAttribute("data-fold"))),
      ),
    );
  renderSentences();
}

/** The layman-style combination view: enumerate every way to satisfy the rule.
 *  Tracks foldSet — folding a disjunction collapses it inline and shrinks the set. */
function renderSentences() {
  if (!cur) return;
  const ss = expandSentences(cur.fn, foldSet);
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

/* ------------------------------------------------------------- load a decision */
function selectDecision(i: number) {
  cur = decisions[i] ?? null;
  foldSet.clear();
  valuation.clear();
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
  if (cur) groupIds(cur.fn).forEach((id) => foldSet.add(id));
  render(true);
});
$("all-true").addEventListener("click", () => {
  if (cur) leafIds(cur.fn).forEach((id) => valuation.set(id, "TrueV"));
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
