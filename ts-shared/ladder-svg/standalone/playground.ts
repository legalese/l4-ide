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
 * CALL PANELS. A call to another boolean rule of the module (`is creditworthy a`,
 * `limb a b`) can carry an `expansion` on the wire: the callee's body with the call's
 * actual arguments substituted, which the SERVER must compute in the caller's context.
 * No jl4-lsp sends it yet (2026-10-05: the server half is specified, not landed); until
 * one does, this page draws every call as one box, and the panels below are exercised
 * only through the tests' synthetic fixture.
 * `fromVizFunDecl(…, { calls: "expand" })` decodes each one as a call panel, a
 * `call: true` group under the call leaf's own id, and the layout draws it as a shaded
 * panel named after the call. Its name folds it to one box (an ordinary `foldSet` fold),
 * and the ▸ caret on that box opens it again; "expand calls" / "collapse calls" do every
 * panel at once. A reply with no expansions (a jl4-lsp older than call panels) draws
 * every call as a single box, as it always did.
 *
 * ONE CLICK, EVERY COPY. A click on a box sets that value on every box that is the same
 * proposition — the same `atomId`, which the server is to compute after substitution — via
 * `spreadValue`. So the `a` inside `limb a b` answers with the caller's own `a`, the two
 * `is creditworthy a` panels in `may lend jointly` answer together, and
 * `is creditworthy b` stays apart. A folded panel's box is the call as a whole; clicking
 * it sets that value on every copy of the call, open or folded, but an OPEN panel sets its
 * copy aside and conducts by what is drawn inside it (`layout`, `dropOpenPanels`): the
 * value shows on every folded copy, and comes back on an open one when it is folded.
 *
 * Nothing here splices or renumbers a tree: the identity is the server's, and this page
 * only reads it. This file used to splice a callee's body in on the client, from the
 * bodies `/render` returned, because the LSP then marked applied calls `canInline: false`.
 * That splice copied the callee's tree under fresh ids and substituted no arguments, so an
 * inlined box was the callee's parameter (`p`, not `a`) and shared no identity with anything.
 *
 * E1 Step 4: the DOM half lives in `src/controller.ts`, shared with app.ts. What is
 * genuinely this demo's — spreading a value over every copy, and the panel buttons —
 * rides on `onAct`. Pan/zoom (seam S6) comes along for free.
 */
import {
  defaultViewSpec,
  fromVizFunDecl,
  expandSentences,
  spreadValue,
} from "@repo/ladder-core";
import {
  LadderController,
  SCREEN_PALETTE,
  panelBackdrop,
} from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  NodeId,
  UBoolValue,
  ConnectiveStyle,
  Grounding,
  Scene,
  DecodedViz,
} from "@repo/ladder-core";

const $ = (id: string) => document.getElementById(id)!;
const src = $("src") as HTMLTextAreaElement;
const picker = $("decision") as HTMLSelectElement;
const examples = $("examples") as HTMLSelectElement;
const status = $("status");
const container = $("ladder");
const sentList = $("sentences") as HTMLOListElement;
const sentCount = $("sent-count");
const msg = $("msg");

/* ------------------------------------------------------------------- state */
/** One LSP diagnostic, flattened by `/render` (1-based line/column). */
type Diagnostic = {
  severity: number; // 1 Error, 2 Warning, 3 Information, 4 Hint
  line: number;
  column: number;
  message: string;
};
/** A decoded decision: the tree with its calls expanded into panels, plus the identity
 *  index (`atomIdByNode` / `nodesByAtomId`) that `spreadValue` reads. */
let decisions: DecodedViz[] = [];
let cur: DecodedViz | null = null;
/** The call panels of `cur`, id → the call as written. Rebuilt when a decision loads. */
let panels = new Map<NodeId, string>();
const foldSet = new Set<NodeId>();
let valuation = new Map<NodeId, UBoolValue>();
let connective: ConnectiveStyle = "straddle-wire";
/** How to read an atom nobody answered, and whether the source's own TYPICALLY
 *  presumptions are in play. Two independent axes; see `Grounding` in ladder-core. */
let grounding: Grounding = "none";
let respectDefaults = true;

const clean = (s: string) => s.replace(/`/g, "").trim();

/* structural walks over the decoded tree (the buttons operate on all of it, folded or not) */
function walk(
  e: IRExpr,
  leaves: NodeId[],
  groups: NodeId[],
  calls: Map<NodeId, string>,
): void {
  if (e.$type === "And" || e.$type === "Or") {
    groups.push(e.id);
    if (e.$type === "And" && e.call) calls.set(e.id, e.label ?? "");
    e.args.forEach((a) => walk(a, leaves, groups, calls));
  } else if (e.$type === "Not") walk(e.negand, leaves, groups, calls);
  else if (e.$type === "Implies") {
    walk(e.scope, leaves, groups, calls);
    walk(e.requirement, leaves, groups, calls);
  } else if (e.$type !== "InertE") leaves.push(e.id);
}
const leavesOf = (e: IRExpr): NodeId[] => {
  const l: NodeId[] = [];
  walk(e, l, [], new Map());
  return l;
};

/** The words a box shows, for the status line. */
function labelOf(e: IRExpr, id: NodeId): string | null {
  if (e.id === id && "label" in e && typeof e.label === "string")
    return clean(e.label);
  const kids =
    e.$type === "And" || e.$type === "Or"
      ? e.args
      : e.$type === "Not"
        ? [e.negand]
        : e.$type === "Implies"
          ? [e.scope, e.requirement]
          : [];
  for (const k of kids) {
    const hit = labelOf(k, id);
    if (hit !== null) return hit;
  }
  return null;
}
const say = (t: string) => (msg.textContent = t);

/* ------------------------------------------------------------------ the controller */
/** Nothing is rendered until a module comes back from the LSP, so the controller starts on
 *  an empty tree and `render()` swaps in the real one via `setFunDecl`. */
const EMPTY_FN: FunDecl = {
  id: 0,
  name: "",
  params: [],
  body: { $type: "InertE", id: 0, text: "", context: "InertAnd" },
};

/** A value act is a click on a box: spread it over every copy of that proposition.
 *  A fold act is a panel's name, a group heading, or a ▸ caret: an ordinary fold. */
const controller = new LadderController(container, EMPTY_FN, {
  onAct: (act) => {
    if (act.t === "value") cycleValue(act.id);
    else toggleFold(act.id);
  },
  /** The diagram's backdrop is one step below its outermost panel when it has panels; the
   *  pane's own padding around the SVG takes the same shade, so there is no white frame. */
  onRender: (_svg, scene) => {
    container.style.background = scene.panelDepth
      ? panelBackdrop(SCREEN_PALETTE, scene.panelDepth)
      : "";
  },
});

function render(animate: boolean) {
  if (!cur) return;
  // The decoded tree already holds every panel; folding one is a `foldSet` entry, so the
  // tree itself never changes between frames and ids are stable for FLIP, click and fold.
  // `animate: false` (a fresh decision) drops the FLIP baseline.
  //
  // The two epistemic knobs ride the ViewSpec, so the controller needs no knowledge of
  // them; `render` hands back the Scene, which is what the banner reads its wording off.
  controller.setFunDecl(cur.fn, animate);
  const scene = controller.render(
    defaultViewSpec({
      valuation,
      foldSet,
      provenance: cur.provenance,
      defaults: cur.defaults,
      connectiveStyle: connective,
      showCurrent: true,
      grounding,
      respectDefaults,
    }),
  );
  renderEpiNote(scene);
  renderSentences();
}

/**
 * Say IN WORDS what reading the picture is under, because the colour grammar alone
 * cannot: a muted-green completed circuit and a dark-green one differ by one shade, and
 * the difference between them is "this is what the facts say" versus "this is what the
 * facts say once I fill in the gaps myself". A viewer who mis-reads that is exactly the
 * audit failure the two knobs exist to prevent, so the banner is not decoration.
 */
function renderEpiNote(scene: Scene) {
  const note = $("epi-note");
  const parts: string[] = [];
  if (grounding !== "none")
    parts.push(
      grounding === "closed"
        ? "Unanswered atoms are being read as <b>false</b> (closed world / negation as failure)."
        : "Unanswered atoms are being read as <b>true</b> (open world).",
    );
  if (!respectDefaults)
    parts.push(
      "<code>TYPICALLY</code> defaults from the source are <b>ignored</b>.",
    );
  if (scene.complete && scene.provisional)
    parts.push(
      "The circuit is made, but <b>provisionally</b> — some closed contact is presumed or assumed, not answered.",
    );
  const on = grounding !== "none" || !respectDefaults;
  note.className = on ? "assumed" : "grounded";
  note.innerHTML = parts.length
    ? parts.join(" ")
    : "Showing only what is known — unanswered atoms stay unanswered.";
}

/** Combination view: enumerate every way to satisfy the rule. A panel is a group like
 *  any other, so opening a call opens its combinations too, and folding it keeps the
 *  call inline as one term. */
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
const WORD: Record<UBoolValue, string> = {
  TrueV: "true",
  FalseV: "false",
  UnknownV: "unknown",
};
/** Cycle the clicked box and carry the new value to every box that is the same
 *  proposition (`spreadValue`, keyed by the server's atomId). */
function cycleValue(id: NodeId) {
  if (!cur) return;
  const nx = NEXT[valuation.get(id) ?? "UnknownV"];
  valuation = spreadValue(cur, id, nx, valuation);
  // Count the boxes the reader will see change: an OPEN panel holds the value but sets it
  // aside while open, so it is not one of them.
  const atom = cur.atomIdByNode.get(id);
  const copies =
    atom === undefined ? [id] : (cur.nodesByAtomId.get(atom) ?? [id]);
  const n = copies.filter((c) => !panels.has(c) || foldSet.has(c)).length;
  const held = copies.length - n;
  const what = panels.has(id)
    ? `${panels.get(id)} as a whole`
    : (labelOf(cur.fn.body, id) ?? `box ${id}`);
  say(
    `Set ${what} to ${WORD[nx]}: ${n} box${n === 1 ? "" : "es"} changed` +
      (held
        ? `; ${held} open cop${held === 1 ? "y holds" : "ies hold"} it until folded.`
        : "."),
  );
  render(true);
}
function toggleFold(id: NodeId) {
  const folding = !foldSet.has(id);
  folding ? foldSet.add(id) : foldSet.delete(id);
  if (panels.has(id))
    say(`${folding ? "Collapsed" : "Expanded"} ${panels.get(id)}.`);
  render(true);
}

/* ------------------------------------------------------------- load a decision */
function selectDecision(i: number) {
  cur = decisions[i] ?? null;
  foldSet.clear();
  valuation = new Map();
  panels = new Map();
  if (cur) walk(cur.fn.body, [], [], panels);
  $("panel-buttons").hidden = panels.size === 0;
  say(
    panels.size
      ? `${panels.size} call${panels.size === 1 ? "" : "s"} drawn in place. Click a call's name to fold it.`
      : "",
  );
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
      .map((f: { funDecl: Parameters<typeof fromVizFunDecl>[0] }) =>
        fromVizFunDecl(f.funDecl, { calls: "expand" }),
      );
    picker.innerHTML = "";
    decisions.forEach((d, i) => {
      const o = document.createElement("option");
      o.value = String(i);
      o.textContent = d.fn.name;
      picker.appendChild(o);
    });
    if (!decisions.length) {
      // Drop the PREVIOUS module's tree too. `render()` early-returns on a null `cur`, so
      // leaving it set means any later control — a grounding radio, a fold — silently
      // redraws the last file that compiled, on top of the diagnostics explaining why this
      // one did not. A ladder for a program you are no longer looking at is worse than none.
      cur = null;
      panels = new Map();
      say("");
      // …and the controller's FLIP baseline with it, or the next module that DOES compile
      // animates out of a scene belonging to a program nobody is looking at.
      controller.setFunDecl(EMPTY_FN);
      picker.innerHTML = "";
      sentList.innerHTML = "";
      sentCount.textContent = "";
      // Prefer the compiler's own words. "No DECIDE found" is true but useless
      // when the real reason is a parse error on a line we can name.
      const diags: Diagnostic[] = data.diagnostics ?? [];
      const errs = diags.filter((d) => d.severity === 1);
      if (errs.length) {
        status.textContent = `${errs.length} error(s)`;
        container.innerHTML = "";
        const pre = document.createElement("pre");
        pre.className = "diagnostics";
        pre.textContent = errs
          .map((d) => `line ${d.line}:${d.column}  ${d.message}`)
          .join("\n\n");
        container.appendChild(pre);
        return;
      }
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
document
  .querySelectorAll<HTMLInputElement>('input[name="grounding"]')
  .forEach((el) =>
    el.addEventListener("change", () => {
      if (!el.checked) return;
      grounding = el.value as Grounding;
      render(true);
    }),
  );
($("respect-defaults") as HTMLInputElement).addEventListener("change", (e) => {
  respectDefaults = (e.target as HTMLInputElement).checked;
  render(true);
});
$("expand-all").addEventListener("click", () => {
  foldSet.clear();
  say("Expanded all.");
  render(true);
});
$("collapse-all").addEventListener("click", () => {
  if (!cur) return;
  const g: NodeId[] = [];
  walk(cur.fn.body, [], g, new Map());
  g.forEach((id) => foldSet.add(id));
  say("Collapsed all.");
  render(true);
});
/* The approved page's two buttons: every call panel at once, other groups untouched. */
$("expand-calls").addEventListener("click", () => {
  panels.forEach((_, id) => foldSet.delete(id));
  say("Expanded every call.");
  render(true);
});
$("collapse-calls").addEventListener("click", () => {
  panels.forEach((_, id) => foldSet.add(id));
  say("Collapsed every call.");
  render(true);
});
$("all-true").addEventListener("click", () => {
  if (!cur) return;
  valuation = new Map(valuation);
  leavesOf(cur.fn.body).forEach((id) => valuation.set(id, "TrueV"));
  render(true);
});
$("reset").addEventListener("click", () => {
  valuation = new Map();
  say("Values reset.");
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
