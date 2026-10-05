/**
 * Call panels, client half, stage 2: the layout of a call drawn expanded in place (C4).
 *
 * A group with `call: true` that is not folded is measured as a PANEL — the NOT scope frame's
 * box model (padding, a name band mirrored top and bottom, wire stubs) — and emits a `panel`
 * prim with its `depth`, plus its name as a `panel` text prim carrying the fold act. The
 * scene carries `panelDepth`, the panel levels of the WHOLE decision, folds ignored. Also
 * here: the NOT's inverter glyph carries the NOT's output value.
 *
 * The real-module cases read `fixtures/call-expansions.json`, a real capture from this branch's
 * jl4-lsp with expansions asked for (see `call-expansions.test.ts`); they look things up by label.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import type { FunDecl as VizFunDecl } from "@repo/viz-expr";
import { fromVizFunDecl } from "../src/viz-adapter.js";
import { layout, estimateMetrics, PIXEL_GEOMETRY } from "../src/layout.js";
import { ASCII_GEOMETRY, monoMetrics, sceneToAscii } from "../src/ascii.js";
import { defaultViewSpec } from "../src/types.js";
import type {
  FunDecl,
  IRExpr,
  NodeId,
  Scene,
  ScenePrim,
  UBoolValue,
  ViewSpec,
} from "../src/types.js";

const CAP = JSON.parse(
  readFileSync(
    new URL("./fixtures/call-expansions.json", import.meta.url),
    "utf8",
  ),
) as { modules: Record<string, { funDecls: VizFunDecl[] }> };

const decode = (mod: string, name: string, calls: "leaf" | "expand") => {
  const f = CAP.modules[mod]!.funDecls.find(
    (d) => d.name.label.replace(/`/g, "") === name,
  );
  assert.ok(f, `${mod}: no FunDecl ${name}`);
  return fromVizFunDecl(f, { calls });
};
const visa = () => decode("visa", "may be granted a work visa", "expand");
const joint = () => decode("joint", "may lend jointly", "expand");

const all = (e: IRExpr): IRExpr[] =>
  e.$type === "And" || e.$type === "Or"
    ? [e, ...e.args.flatMap(all)]
    : e.$type === "Not"
      ? [e, ...all(e.negand)]
      : e.$type === "Implies"
        ? [e, ...all(e.scope), ...all(e.requirement)]
        : [e];
const callId = (fn: FunDecl, label: string): NodeId => {
  const n = all(fn.body).find(
    (e) => e.$type === "And" && e.call && e.label === label,
  );
  assert.ok(n, `no panel ${label}`);
  return n.id;
};

type Panel = Extract<ScenePrim, { kind: "panel" }>;
type Text = Extract<ScenePrim, { kind: "text" }>;
type Box = Extract<ScenePrim, { kind: "box" }>;
type Wire = Extract<ScenePrim, { kind: "wire" }>;
type Glyph = Extract<ScenePrim, { kind: "glyph" }>;
const panels = (s: Scene) =>
  s.prims.filter((p): p is Panel => p.kind === "panel");
const draw = (fn: FunDecl, vs: Partial<ViewSpec> = {}) =>
  layout(fn, defaultViewSpec(vs), estimateMetrics);

/* A tiny hand-built tree: `f x AND y`, with `f x` expanded to the one leaf `x`. */
const leaf = (id: NodeId, label: string): IRExpr => ({
  $type: "UBoolVar",
  id,
  label,
});
const small = (label = "f x"): FunDecl => ({
  id: 0,
  name: "top",
  params: [],
  body: {
    $type: "And",
    id: 1,
    args: [
      { $type: "And", id: 2, label, call: true, args: [leaf(3, "x")] },
      leaf(4, "y"),
    ],
  },
});

test("a panel pads its contents like the NOT frame: sides, a mirrored name band, stubs", () => {
  const k = PIXEL_GEOMETRY;
  const s = draw(small());
  const [p] = panels(s);
  assert.ok(p, "an unfolded call group is a panel");
  const box = s.prims.find((q): q is Box => q.kind === "box" && q.id === 3)!;
  const band = k.PANEL_LABEL + k.PANEL_PAD_Y;
  assert.equal(p.w, box.rect.w + 2 * k.PANEL_PAD_X);
  assert.equal(p.h, box.rect.h + 2 * band);
  assert.equal(box.rect.x, p.at.x + k.PANEL_PAD_X);
  assert.equal(box.rect.y, p.at.y + band);
  // the port is on the panel's own axis, so the series wire into it is level
  const cy = p.at.y + p.h / 2;
  assert.equal(box.rect.y + box.rect.h / 2, cy);
  const wires = s.prims.filter((q): q is Wire => q.kind === "wire");
  const stubIn = wires.find(
    (w) => w.path[0]!.x === p.at.x && w.path[1]!.x === box.rect.x,
  );
  const stubOut = wires.find(
    (w) =>
      w.path[0]!.x === box.rect.x + box.rect.w && w.path[1]!.x === p.at.x + p.w,
  );
  assert.ok(stubIn && stubOut, "a stub on each side, edge to contents");
  assert.ok([...stubIn.path, ...stubOut.path].every((pt) => pt.y === cy));
  // and the panel occupies room in the series: the next box starts past it
  const y = s.prims.find((q): q is Box => q.kind === "box" && q.id === 4)!;
  assert.equal(y.rect.x, p.at.x + p.w + k.GAP_SERIES);
});

test("a panel is at least as wide as its name, and centres narrower contents", () => {
  const k = PIXEL_GEOMETRY;
  const long = "a call whose name is much wider than the one leaf inside it";
  const s = draw(small(long));
  const [p] = panels(s);
  const box = s.prims.find((q): q is Box => q.kind === "box" && q.id === 3)!;
  const near = (a: number, b: number) => Math.abs(a - b) < 1e-9;
  assert.ok(
    near(
      p!.w,
      estimateMetrics.width(`▾ ${long}`, k.PANEL_FONT) + 2 * k.PANEL_PAD_X,
    ),
  );
  assert.ok(p!.w > box.rect.w + 2 * k.PANEL_PAD_X);
  assert.ok(
    near(box.rect.x - p!.at.x, p!.at.x + p!.w - (box.rect.x + box.rect.w)),
  );
});

test("the panel's name is a text prim that folds the panel", () => {
  const s = draw(small());
  const name = s.prims.find(
    (q): q is Text => q.kind === "text" && q.tag === "panel",
  );
  assert.ok(name);
  assert.equal(name.text, "▾ f x");
  assert.deepEqual(name.act, { t: "fold", id: 2 });
  assert.equal(name.id, 2);
  const [p] = panels(s);
  assert.equal(p!.label, "f x");
  assert.equal(p!.id, 2);
  // inside the panel, in its top band
  assert.ok(name.at.x > p!.at.x && name.at.y > p!.at.y);
  assert.ok(name.at.y <= p!.at.y + PIXEL_GEOMETRY.PANEL_LABEL);
});

test("depth counts the expanded panels around a panel; panelDepth is the decision's levels", () => {
  const d = visa();
  const s = draw(d.fn);
  assert.equal(s.panelDepth, 2);
  const depth = Object.fromEntries(panels(s).map((p) => [p.label, p.depth]));
  assert.deepEqual(depth, {
    "meets general requirements a": 0,
    "identity is established a": 1,
    "character requirement is met a": 1,
    "qualifies by employer sponsorship a": 0,
    "has qualifying skills a": 1,
    "qualifies by self-employment a": 0,
    "has financial backing a": 1,
  });
  // an outer panel is emitted before the panels inside it
  const order = panels(s).map((p) => p.label);
  assert.ok(
    order.indexOf("meets general requirements a") <
      order.indexOf("identity is established a"),
  );
  assert.equal(draw(joint().fn).panelDepth, 1);
});

test("folding changes no panel's depth and not panelDepth", () => {
  const d = visa();
  const full = draw(d.fn);
  const depthOf = (s: Scene) =>
    new Map(panels(s).map((p) => [p.label, p.depth]));
  const inner = callId(d.fn, "identity is established a");
  const outer = callId(d.fn, "meets general requirements a");
  for (const fold of [[inner], [outer], [inner, outer]]) {
    const s = draw(d.fn, { foldSet: new Set(fold) });
    assert.equal(s.panelDepth, 2, `fold ${fold}`);
    for (const [label, depth] of depthOf(s))
      assert.equal(depth, depthOf(full).get(label), label);
  }
  // fold every panel: none drawn, and the scale is still the decision's
  const every = panels(full).map((p) => p.id);
  const s = draw(d.fn, { foldSet: new Set(every) });
  assert.equal(panels(s).length, 0);
  assert.equal(s.panelDepth, 2);
});

test("a folded panel is today's placeholder: the call's name, a ▸ that unfolds, a value click", () => {
  const d = visa();
  const id = callId(d.fn, "identity is established a");
  const s = draw(d.fn, { foldSet: new Set([id]) });
  assert.ok(!panels(s).some((p) => p.id === id));
  const box = s.prims.find((q): q is Box => q.kind === "box" && q.id === id);
  assert.ok(box);
  assert.equal(box.role, "placeholder");
  assert.deepEqual(box.act, { t: "value", id });
  const caret = s.prims.find(
    (q): q is Text => q.kind === "text" && q.tag === "caret",
  );
  assert.deepEqual(caret?.act, { t: "fold", id });
  assert.ok(
    s.prims.some(
      (q) =>
        q.kind === "text" &&
        q.id === id &&
        q.text === "identity is established a",
    ),
  );
  // a value on the folded panel is an override of the whole call
  const pinned = draw(d.fn, {
    foldSet: new Set([id]),
    valuation: new Map([[id, "TrueV"]]),
  });
  const pbox = pinned.prims.find(
    (q): q is Box => q.kind === "box" && q.id === id,
  );
  assert.equal(pbox?.state, "live");
});

test("no call groups, no panels: leaf mode and every older tree keep their scene", () => {
  const d = decode("visa", "may be granted a work visa", "leaf");
  const s = draw(d.fn);
  assert.equal(panels(s).length, 0);
  assert.ok(!("panelDepth" in s), "panelDepth absent, not 0");
  assert.ok(!s.prims.some((p) => p.kind === "text" && p.tag === "panel"));
});

test("TB: a stub leaves the way the contents' port faces, so none crosses the name band", () => {
  // A leaf's ports are on its left and right whatever the orientation (`leafBox`), and an
  // OR is still drawn LR in TB. The stubs used to drop vertically from the panel's top edge
  // to such a port, straight through the panel's name (review 2026-10-05,
  // visual-attack/visa-values-TB.png). Now a side-facing port gets a sideways stub.
  const s = draw(small(), { orient: "TB" });
  const [p] = panels(s);
  const box = s.prims.find((q): q is Box => q.kind === "box" && q.id === 3)!;
  const midY = box.rect.y + box.rect.h / 2;
  const wires = s.prims.filter((q): q is Wire => q.kind === "wire");
  const within = (q: { x: number; y: number }) =>
    q.x >= p!.at.x &&
    q.x <= p!.at.x + p!.w &&
    q.y >= p!.at.y &&
    q.y <= p!.at.y + p!.h;
  const stubs = wires.filter((w) => w.path.every(within));
  assert.equal(stubs.length, 2, "one stub in, one out");
  for (const w of stubs) {
    assert.ok(
      w.path.every((q) => q.y === midY),
      "each stub is horizontal, on the contents' axis",
    );
    assert.ok(
      midY > p!.at.y + PIXEL_GEOMETRY.PANEL_LABEL,
      "below the name band",
    );
  }
});

test("ASCII draws a panel's outline and its name", () => {
  const s = layout(
    small(),
    defaultViewSpec({ connectiveStyle: "on-wire" }),
    monoMetrics(),
    ASCII_GEOMETRY,
  );
  const txt = sceneToAscii(s);
  assert.match(txt, /▾ f x/);
  assert.match(txt, /┈/, "the panel outline is drawn");
});

/* ------------------------------------------------- the NOT bubble's output value */

const notOf = (negand: IRExpr): FunDecl => ({
  id: 0,
  name: "top",
  params: [],
  body: { $type: "Not", id: 1, negand },
});
const bubble = (s: Scene) =>
  s.prims.find((q): q is Glyph => q.kind === "glyph" && q.role === "inverter");

test("the inverter carries the NOT's output: TRUE for a false negand, FALSE for a true one", () => {
  const fn = notOf(leaf(2, "p"));
  const at = (v?: UBoolValue) =>
    bubble(draw(fn, { valuation: new Map(v ? [[2, v]] : []) }));
  assert.equal(at("FalseV")?.value, "TrueV");
  assert.equal(at("TrueV")?.value, "FalseV");
  const unknown = at();
  assert.ok(unknown);
  assert.ok(!("value" in unknown), "unknown: no value key, so the old scene");
});

test("the inverter reads the honest value, not a grounding assumption, and honours a pin", () => {
  const fn = notOf(leaf(2, "p"));
  assert.ok(!("value" in bubble(draw(fn, { grounding: "closed" }))!));
  assert.equal(
    bubble(draw(fn, { valuation: new Map([[1, "FalseV"]]) }))?.value,
    "FalseV",
  );
});

test("the inverter in a real panel follows the term it negates (joint)", () => {
  const d = joint();
  const def = all(d.fn.body).filter(
    (e) => "label" in e && /a's `?has recent default/.test(e.label ?? ""),
  );
  assert.equal(def.length, 2, "a's term appears in both a-panels");
  const v = new Map<NodeId, UBoolValue>(def.map((e) => [e.id, "FalseV"]));
  const s = draw(d.fn, { valuation: v });
  const values = s.prims
    .filter((q): q is Glyph => q.kind === "glyph" && q.role === "inverter")
    .map((g) => g.value ?? "?");
  // a, b, a: the b panel's NOT is still unknown
  assert.deepEqual(values, ["TrueV", "?", "TrueV"]);
});

test("a FALSE term's break clears the NOT bubble it feeds (no tick through the bubble)", () => {
  // The break is drawn BREAK_CLEAR (9) past the box as two bars at ±7; the bubble sat 16
  // past the box, so the right bar went through its centre and poked out above and below
  // (review 2026-10-05, visual-attack/bubble-zoom.png).
  const s = draw(notOf(leaf(2, "p")), { valuation: new Map([[2, "FalseV"]]) });
  const tick = s.prims.find(
    (q): q is Glyph => q.kind === "glyph" && q.role === "open-contact",
  );
  const b = bubble(s)!;
  assert.ok(tick, "a false leaf draws its break");
  const tickRight = tick.at.x + 7 + 1; // bar and half its stroke
  const bubbleLeft = b.at.x - PIXEL_GEOMETRY.NOT_R - 0.75;
  assert.ok(
    tickRight < bubbleLeft,
    `tick ends at ${tickRight}, bubble starts at ${bubbleLeft}`,
  );
});

/* ------------------------------------- a value on a call panel holds only while folded */

test("an override on an OPEN panel is set aside, so it conducts by what it draws", () => {
  // Clicking a folded `is creditworthy a` spreads the value to every copy of that call
  // (`spreadValue`), the open twin included. Before, the open twin then conducted TRUE with
  // every box inside it unanswered (review 2026-10-05, joint-override-folded165.png).
  const d = joint();
  const ids = all(d.fn.body)
    .filter(
      (e) => e.$type === "And" && e.call && e.label === "is creditworthy a",
    )
    .map((e) => e.id);
  assert.equal(ids.length, 2);
  const [folded, open] = ids as [NodeId, NodeId];
  const both = new Map<NodeId, UBoolValue>([
    [folded, "TrueV"],
    [open, "TrueV"],
  ]);
  const onlyFolded = new Map<NodeId, UBoolValue>([[folded, "TrueV"]]);
  const fold = new Set([folded]);
  const vs = (valuation: Map<NodeId, UBoolValue>) =>
    ({ foldSet: fold, valuation, showCurrent: true }) as Partial<ViewSpec>;
  assert.deepEqual(
    draw(d.fn, vs(both)),
    draw(d.fn, vs(onlyFolded)),
    "the open twin's entry changes nothing",
  );
  // …the folded copy does carry it
  const ph = draw(d.fn, vs(both)).prims.find(
    (q): q is Box => q.kind === "box" && q.id === folded,
  );
  assert.equal(ph?.state, "live");
  // …and folding the twin brings its value back
  const s2 = draw(d.fn, { ...vs(both), foldSet: new Set(ids) });
  const ph2 = s2.prims.find((q): q is Box => q.kind === "box" && q.id === open);
  assert.equal(ph2?.state, "live");
});

/* ----------------------------------------------- wires keep out of panels they don't serve */

const bez = (c: Extract<ScenePrim, { kind: "curve" }>, t: number) => {
  const u = 1 - t;
  const f = (k: "x" | "y") =>
    u * u * u * c.from[k] +
    3 * u * u * t * c.c1[k] +
    3 * u * t * t * c.c2[k] +
    t * t * t * c.to[k];
  return { x: f("x"), y: f("y") };
};
/** Every wire or curve sample strictly inside a panel that neither of its ends touches. */
function crossings(s: Scene): string[] {
  const out: string[] = [];
  for (const p of s.prims) {
    let pts: { x: number; y: number }[];
    let ends: { x: number; y: number }[];
    if (p.kind === "curve") {
      pts = Array.from({ length: 101 }, (_, i) => bez(p, i / 100));
      ends = [p.from, p.to];
    } else if (p.kind === "wire") {
      pts = p.path.slice(1).flatMap((b, i) => {
        const a = p.path[i]!;
        return Array.from({ length: 51 }, (_, j) => ({
          x: a.x + ((b.x - a.x) * j) / 50,
          y: a.y + ((b.y - a.y) * j) / 50,
        }));
      });
      ends = [p.path[0]!, p.path[p.path.length - 1]!];
    } else continue;
    for (const P of panels(s)) {
      const [x0, y0, x1, y1] = [P.at.x, P.at.y, P.at.x + P.w, P.at.y + P.h];
      const on = (q: { x: number; y: number }) =>
        q.x >= x0 - 1 && q.x <= x1 + 1 && q.y >= y0 - 1 && q.y <= y1 + 1;
      const inside = (q: { x: number; y: number }) =>
        q.x > x0 + 1 && q.x < x1 - 1 && q.y > y0 + 1 && q.y < y1 - 1;
      if (!ends.some(on) && pts.some(inside))
        out.push(`${p.kind} ${JSON.stringify(ends)} crosses ${P.label}`);
    }
  }
  return out;
}

test("no wire runs through a panel it neither starts nor ends at, in any single fold", () => {
  // The OR fan used to bank across a sibling panel's corner when a narrower branch sat
  // further out (review 2026-10-05: visa with `has qualifying skills a` folded, 9.6px deep).
  for (const d of [visa(), joint()]) {
    const ps = all(d.fn.body).filter((e) => e.$type === "And" && e.call);
    for (const fold of [undefined, ...ps.map((p) => p.id)]) {
      const s = draw(d.fn, {
        foldSet: new Set(fold === undefined ? [] : [fold]),
        showCurrent: true,
      });
      assert.deepEqual(crossings(s), [], `${d.fn.name} folded at ${fold}`);
    }
  }
});

test("an OR with no panel below it keeps its sprung fan", () => {
  // The lane routing is for ORs with a drawn panel only; a plain OR's curves are unchanged.
  const d = decode("visa", "may be granted a work visa", "leaf");
  const s = draw(d.fn);
  assert.ok(
    s.prims.some(
      (q) =>
        q.kind === "curve" &&
        Math.abs(q.c1.x - q.from.x) > PIXEL_GEOMETRY.BUS_PAD / 2,
    ),
    "some curve still thrusts further than half a bus lane",
  );
});
