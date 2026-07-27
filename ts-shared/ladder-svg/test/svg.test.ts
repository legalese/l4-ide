/** svg.ts — Scene IR → SVG. The emit had no tests at all while it lived inside
 * `ladder-core`; the package split (G6) is the moment to give it some.
 *
 * Every fixture below is a hand-built `Scene` literal — no `layout`, no `IRExpr`,
 * no metrics. That is not laziness, it is the architectural claim under test: the
 * Scene IR is the seam (DESIGN §4.2), so the renderer can be exercised without the
 * engine that normally feeds it. If a future change makes these tests need `layout`
 * to compile, the seam has leaked.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { sceneToSvg } from "../src/index.js";
import type { Scene, ScenePrim } from "@repo/ladder-core";

const scene = (...prims: ScenePrim[]): Scene => ({
  size: { w: 400, h: 200 },
  prims,
});

/* ------------------------------------------------------- §25.4 — the two lamps */

/** The verdict is read off the LIT coils, so "lit" has to survive the emit. This is
 *  the picture half of the §25f wizard fix: the query planner now reports Complies /
 *  InBreach / NotApplicable, and these are the coils that show it. */
test("a lit coil is filled and bold; an unlit one is hollow and italic", () => {
  const lit = sceneToSvg(
    scene({
      kind: "coil",
      at: { x: 300, y: 50 },
      role: "green",
      lit: true,
      label: "complies",
    }),
  );
  const unlit = sceneToSvg(
    scene({
      kind: "coil",
      at: { x: 300, y: 50 },
      role: "green",
      lit: false,
      label: "complies",
    }),
  );

  assert.match(lit, /<circle[^>]*fill="#1a7f37"/); // green, filled
  assert.match(lit, /font-weight="700"/);
  assert.doesNotMatch(lit, /font-style="italic"/);

  assert.match(unlit, /<circle[^>]*fill="#ffffff"/); // hollow
  assert.match(unlit, /font-style="italic"/);
  assert.doesNotMatch(unlit, /font-weight="700"/);
});

test("the red coil is red, and neither coil lit is a drawable state", () => {
  const breach = sceneToSvg(
    scene({
      kind: "coil",
      at: { x: 300, y: 50 },
      role: "red",
      lit: true,
      label: "in breach",
    }),
  );
  assert.match(breach, /<circle[^>]*stroke="#c0392b"/);

  // N/A and undetermined both render as two DARK lamps — vacuity is a state, not a
  // path, so there is no bypass ink to look for (DESIGN §25.3). The scene is legal
  // and the emit must not invent a lit lamp for it.
  const na = sceneToSvg(
    scene(
      {
        kind: "coil",
        at: { x: 300, y: 40 },
        role: "green",
        lit: false,
        label: "complies",
      },
      {
        kind: "coil",
        at: { x: 300, y: 70 },
        role: "red",
        lit: false,
        label: "in breach",
      },
    ),
  );
  assert.equal(na.match(/fill="#ffffff"\s+stroke=/g)?.length, 2); // both hollow
  assert.doesNotMatch(na, /fill="#1a7f37"/);
  assert.doesNotMatch(na, /fill="#c0392b"/);
});

/* ------------------------------------------------------------------ escaping */

/** Statute leaf labels are natural language and routinely contain `&` and comparison
 *  operators. An unescaped `&` or `<` produces SVG that no parser will accept — so
 *  this is a correctness bug that only shows up on real corpora, never on fixtures
 *  with tidy labels. */
test("labels with XML metacharacters are escaped, not emitted raw", () => {
  const svg = sceneToSvg(
    scene({
      kind: "text",
      at: { x: 10, y: 10 },
      text: "age < 18 & height > 1.7m",
      anchor: "start",
      state: "live",
    }),
  );
  assert.match(svg, /age &lt; 18 &amp; height &gt; 1\.7m/);
  assert.doesNotMatch(svg, /age < 18/);
  // and the ampersand is escaped exactly once — a double-escape would print "&amp;amp;"
  assert.doesNotMatch(svg, /&amp;amp;/);
});

/* -------------------------------------------------- §20 — the current-flow model */

test("flow reads off the stroke: closed thicker and darker than streamer than open", () => {
  const wire = (flow: "open" | "streamer" | "closed"): ScenePrim => ({
    kind: "wire",
    path: [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
    ],
    role: "rung",
    state: "live",
    flow,
  });
  const widthOf = (flow: "open" | "streamer" | "closed") =>
    Number(
      /stroke-width="([\d.]+)"/.exec(sceneToSvg(scene(wire(flow))))?.[1] ?? -1,
    );

  assert.ok(
    widthOf("closed") > widthOf("streamer"),
    "the leader must outweigh the streamer",
  );
  assert.ok(
    widthOf("streamer") > widthOf("open"),
    "a locally-closed element must outweigh dead air",
  );
});

/* -------------------------------------------- the host-wiring contract (E1/E2) */

/** The IDE binds interactivity to these data-attrs — they are the whole hit-testing
 *  contract between a string of SVG and a Svelte host. Nothing else in the emit is
 *  API; these are. */
test("click affordances survive as data-attrs the host can bind", () => {
  const svg = sceneToSvg(
    scene(
      {
        kind: "box",
        id: 7,
        rect: { x: 0, y: 0, w: 80, h: 30 },
        role: "leaf",
        state: "live",
        act: { t: "value", id: 7 },
      },
      {
        kind: "text",
        at: { x: 5, y: 5 },
        text: "fold me",
        anchor: "start",
        state: "live",
        id: 9,
        act: { t: "fold", id: 9 },
      },
    ),
  );
  assert.match(svg, /data-fnid="7"[^>]*data-value="7"/);
  assert.match(svg, /class="lad-box lad-clickable"/);
  assert.match(svg, /data-fold="9"/);
  assert.match(svg, /class="lad-clickable"/);
});

test("a box with no act is not advertised as clickable", () => {
  const svg = sceneToSvg(
    scene({
      kind: "box",
      id: 1,
      rect: { x: 0, y: 0, w: 80, h: 30 },
      role: "leaf",
      state: "live",
    }),
  );
  assert.match(svg, /class="lad-box"/);
  assert.doesNotMatch(svg, /lad-clickable/);
  assert.doesNotMatch(svg, /data-value/);
});

/* ------------------------------- §22 tentative vs §15 eliminable — distinguishable */

/** Both are dashed. They mean opposite things — a presumption you may rebut vs a rung
 *  that cannot matter — so if the dash patterns ever collide the diagram lies. */
test("tentative and eliminable do not share a dash pattern", () => {
  const box = (extra: Partial<Extract<ScenePrim, { kind: "box" }>>) =>
    sceneToSvg(
      scene({
        kind: "box",
        id: 1,
        rect: { x: 0, y: 0, w: 80, h: 30 },
        role: "leaf",
        state: "live",
        ...extra,
      } as ScenePrim),
    );
  const dashOf = (svg: string) => /stroke-dasharray="([^"]+)"/.exec(svg)?.[1];

  const tentative = dashOf(box({ tentative: true }));
  const eliminable = dashOf(box({ state: "eliminable" }));
  assert.ok(tentative, "a tentative box must be dashed");
  assert.ok(eliminable, "an eliminable box must be dashed");
  assert.notEqual(tentative, eliminable);
});

/* ---------------------------------------------------------------------- themes */

test("the ink theme drops the colour but keeps the geometry", () => {
  const prims: ScenePrim[] = [
    {
      kind: "box",
      id: 1,
      rect: { x: 0, y: 0, w: 80, h: 30 },
      role: "leaf",
      state: "live",
    },
  ];
  const screen = sceneToSvg(scene(...prims), "screen");
  const ink = sceneToSvg(scene(...prims), "ink");

  assert.match(screen, /stroke="#1a7f37"/); // live green on screen
  assert.match(ink, /stroke="#222"/); // near-black in print
  assert.doesNotMatch(ink, /#1a7f37/);
  // same layout, different ink: the rect geometry is byte-identical
  const rect = (s: string) => /<rect[^>]*x="0.0"[^>]*\/>/.exec(s)?.[0] ?? "";
  assert.equal(
    /width="80.0" height="30.0"/.test(rect(screen)),
    /width="80.0" height="30.0"/.test(rect(ink)),
  );
});

test("the root svg carries a viewBox matching the scene size", () => {
  const svg = sceneToSvg(scene());
  assert.match(svg, /viewBox="0 0 400 200"/);
  assert.match(svg, /width="400" height="200"/);
});

/* --------------------------------------- §20 / G1 — a MADE circuit reads dark green */

/** `Scene.complete` says the circuit conducts source→sink. The emit spends that on the
 *  closed run's COLOUR only: weight already means "live", so re-using weight would say
 *  nothing new, while green vs near-black distinguishes "current got here" from "this
 *  rule fires". Streamer and open runs are unaffected — they are not carrying anything
 *  to the sink, complete or not. */
test("a closed run is dark green when the circuit is complete, near-black when not", () => {
  const wire: ScenePrim = {
    kind: "wire",
    path: [
      { x: 0, y: 10 },
      { x: 100, y: 10 },
    ],
    role: "rail",
    state: "inert",
    flow: "closed",
  };
  const made = sceneToSvg({
    size: { w: 400, h: 200 },
    prims: [wire],
    complete: true,
  });
  const partial = sceneToSvg({ size: { w: 400, h: 200 }, prims: [wire] });

  assert.match(made, /stroke="#0f5c2a"/);
  assert.doesNotMatch(made, /stroke="#1b1b1b"/);
  assert.match(partial, /stroke="#1b1b1b"/);
  // the user's constraint: existing thickness for live wires is right, so it must not move
  assert.match(made, /stroke-width="3.4"/);
  assert.match(partial, /stroke-width="3.4"/);
});

test("completeness does not recolour streamer or open runs", () => {
  const mk = (flow: "streamer" | "open"): ScenePrim => ({
    kind: "wire",
    path: [
      { x: 0, y: 10 },
      { x: 100, y: 10 },
    ],
    role: "rail",
    state: "inert",
    flow,
  });
  for (const [flow, colour] of [
    ["streamer", "#7c828a"],
    ["open", "#d6dadd"],
  ] as const) {
    const s = sceneToSvg({
      size: { w: 400, h: 200 },
      prims: [mk(flow)],
      complete: true,
    });
    assert.match(s, new RegExp(`stroke="${colour}"`));
    assert.doesNotMatch(s, /#0f5c2a/);
  }
});

/* --------------------------------------- §6/§15.1/§25.4 — FALSE is not UNKNOWN */

/** The bug this pins: `strokeFor` sent `dead` to `p.inert` and both palettes set
 *  `dead === inert`, so a tested-and-false element and a never-asked one emitted
 *  BYTE-IDENTICAL SVG. §25.4 distinguishes N/A from undetermined purely by "where the
 *  break is" — a definitively ✗ scope shows a clean open contact, a ? scope is grey —
 *  so collapsing the two deleted the two-lamp form's only means of saying which it is.
 *  The ASCII carrier always honoured this (`✓ / ✗ / ?`); the SVG did not. */
test("a FALSE box and an UNKNOWN box do not render the same ink", () => {
  const box = (state: "dead" | "inert"): ScenePrim => ({
    kind: "box",
    id: 1,
    rect: { x: 10, y: 10, w: 100, h: 30 },
    role: "leaf",
    state,
  });
  const no = sceneToSvg(scene(box("dead")));
  const dunno = sceneToSvg(scene(box("inert")));
  assert.notEqual(
    no,
    dunno,
    "known-false must not render identically to unknown",
  );
  assert.match(no, /stroke="#4a5560"/);
  assert.match(dunno, /stroke="#9aa0a6"/);
});

test("all four leaf states are mutually distinguishable in both themes", () => {
  const states = ["live", "dead", "inert", "eliminable"] as const;
  for (const theme of ["screen", "ink"] as const) {
    const inks = states.map(
      (state) =>
        sceneToSvg(
          scene({
            kind: "box",
            id: 1,
            rect: { x: 0, y: 0, w: 10, h: 10 },
            role: "leaf",
            state,
          }),
          theme,
        ).match(/stroke="(#[0-9a-f]{3,6})"/)![1],
    );
    assert.equal(
      new Set(inks).size,
      states.length,
      `${theme}: states collapsed to ${inks.join(",")}`,
    );
  }
});

/** The break glyph is shared by `dead` and `eliminable`, and they mean different
 *  things: a false contact was TESTED and did not bite; a don't-care CANNOT matter.
 *  Firm ink vs ghost. Absent `state` keeps the old ghost rendering. */
test("a dead break is drawn firmly; an eliminable break stays a ghost", () => {
  const brk = (state?: "dead" | "eliminable"): string =>
    sceneToSvg(
      scene({
        kind: "glyph",
        at: { x: 50, y: 50 },
        role: "open-contact",
        state,
      }),
    );
  assert.match(brk("dead"), /stroke="#4a5560" stroke-width="2"/);
  assert.match(brk("eliminable"), /stroke="#b9bdc2" stroke-width="1.6"/);
  assert.equal(
    brk(),
    brk("eliminable"),
    "no state ⇒ the pre-existing ghost break",
  );
});

/* ------------------------------- provisionality reaches BOTH kinds of sink */

/** An `Implies` body is never `complete` — it has two sinks, not one (§25.4) — so the
 *  muted-green wire treatment can never fire on a rule. A rule is exactly where a soft
 *  verdict matters most: a grounding knob can carry a reader from "undetermined" to a lit
 *  IN BREACH lamp with no new facts, and the lamp must not say that in a finding's voice. */
test("a lamp lit on assumptions is hollow and muted; one lit on facts is filled and bold", () => {
  const coil: ScenePrim = {
    kind: "coil",
    at: { x: 300, y: 50 },
    role: "red",
    lit: true,
    label: "in breach",
  };
  const found = sceneToSvg(scene(coil));
  const assumed = sceneToSvg({ ...scene(coil), provisional: true });
  assert.notEqual(found, assumed);
  assert.match(found, /fill="#c0392b"/);
  assert.match(found, /font-weight="700"/);
  assert.match(assumed, /fill="#ffffff" stroke="#cd8b84"/);
  assert.match(assumed, /stroke-dasharray="1.5 3"/);
  assert.match(assumed, /font-style="italic"/);
});

test("an unlit lamp is unaffected by provisionality — there is no verdict to soften", () => {
  const coil: ScenePrim = {
    kind: "coil",
    at: { x: 300, y: 50 },
    role: "green",
    lit: false,
    label: "complies",
  };
  assert.equal(
    sceneToSvg(scene(coil)),
    sceneToSvg({ ...scene(coil), provisional: true }),
  );
});

test("a made circuit resting on assumptions is muted green, not the made green", () => {
  const wire: ScenePrim = {
    kind: "wire",
    path: [
      { x: 0, y: 10 },
      { x: 40, y: 10 },
    ],
    role: "rung",
    state: "inert",
    flow: "closed",
  };
  const s = scene(wire);
  assert.match(sceneToSvg({ ...s, complete: true }), /stroke="#0f5c2a"/);
  assert.match(
    sceneToSvg({ ...s, complete: true, provisional: true }),
    /stroke="#5f9e77"/,
  );
  // provisional without completion changes nothing: there is no made-circuit claim yet
  assert.equal(sceneToSvg(s), sceneToSvg({ ...s, provisional: true }));
});
