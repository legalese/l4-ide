/**
 * The box OUTLINE as the state carrier. Ruled 2026-11-28 (DESIGN §6).
 *
 * `sceneToSvg(scene, theme, { boxState })` draws a box's outline one of two ways:
 *   `"weight"`   TRUE = a border as thick as a lit wire, UNKNOWN = the thin border it has
 *                always had, FALSE = no border; the pale washes stay.
 *   `"outline"`  every box has the thin border in its state's ink: the look before 2026-11-28.
 * The default is `"weight"` on the light and dark palettes and `"outline"` on `INK_PALETTE`,
 * which the documentation figures use. This file pins that, one assertion per state per
 * look, and holds the ink emit to the bytes unstable's code drew before the change.
 *
 * The thick width is never typed here: it is read off a rendered closed wire, so the claim
 * under test is "as thick as a lit wire", not "3.4".
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  sceneToSvg,
  SCREEN_PALETTE,
  INK_PALETTE,
  DARK_PALETTE,
} from "../src/index.js";
import type { Palette, BoxState } from "../src/index.js";
import { layout, defaultViewSpec, estimateMetrics } from "@repo/ladder-core";
import type { Scene, ScenePrim, State } from "@repo/ladder-core";

/** The palettes that draw `"weight"` by default. */
const WEIGHT_THEMES: readonly (readonly [string, Palette])[] = [
  ["screen", SCREEN_PALETTE],
  ["dark", DARK_PALETTE],
];
const ALL_THEMES: readonly (readonly [string, Palette])[] = [
  ...WEIGHT_THEMES,
  ["ink", INK_PALETTE],
];
const STATES: readonly State[] = ["live", "inert", "dead", "eliminable"];

const RECT = { x: 10, y: 20, w: 100, h: 30 };
const scene = (...prims: ScenePrim[]): Scene => ({
  size: { w: 400, h: 200 },
  prims,
});
const box = (
  state: State,
  extra: Partial<Extract<ScenePrim, { kind: "box" }>> = {},
): ScenePrim => ({
  kind: "box",
  id: 1,
  rect: RECT,
  role: "leaf",
  state,
  act: { t: "value", id: 1 },
  ...extra,
});

/** The one `<rect>` the box emits, parsed into its attributes. */
const rectOf = (svg: string): Record<string, string> => {
  const m = /<rect data-fnid="1"[^>]*\/>/.exec(svg);
  assert.ok(m, `no box rect in ${svg}`);
  return Object.fromEntries(
    [...m[0].matchAll(/ ([\w-]+)="([^"]*)"/g)].map((a) => [a[1]!, a[2]!]),
  );
};
const draw = (p: ScenePrim, pal: Palette, boxState?: BoxState) =>
  sceneToSvg(scene(p), pal, boxState ? { boxState } : {});

/** The width of a lit wire, read from the emit rather than typed. */
const litWireWidth = (): number => {
  const svg = sceneToSvg(
    scene({
      kind: "wire",
      path: [
        { x: 0, y: 5 },
        { x: 50, y: 5 },
      ],
      role: "rung",
      state: "live",
      flow: "closed",
    }),
  );
  return Number(/stroke-width="([\d.]+)"/.exec(svg)![1]);
};
/** The thin border: read from the emit of an unknown box, which both looks draw the same. */
const thinBorder = (): number =>
  Number(rectOf(sceneToSvg(scene(box("inert"))))["stroke-width"]);

test("the two widths come from the emit: a lit wire is thicker than the thin border", () => {
  assert.ok(litWireWidth() > thinBorder());
  assert.ok(thinBorder() > 0);
});

/* -------------------------------------------------------- which look is the default */

test("light and dark draw the weight look by default", () => {
  for (const [name, pal] of WEIGHT_THEMES)
    for (const s of STATES)
      assert.equal(
        draw(box(s), pal),
        draw(box(s), pal, "weight"),
        `${name} ${s}`,
      );
  // the theme names are the same palettes
  const sc = scene(box("live"));
  assert.equal(sceneToSvg(sc), sceneToSvg(sc, "screen"));
  assert.equal(sceneToSvg(sc), sceneToSvg(sc, SCREEN_PALETTE));
  assert.notEqual(
    sceneToSvg(sc),
    sceneToSvg(sc, "screen", { boxState: "outline" }),
  );
});

test("the ink theme draws the outline look by default, by name or by palette", () => {
  for (const s of STATES) {
    const sc = scene(box(s));
    assert.equal(sceneToSvg(sc, "ink"), sceneToSvg(sc, INK_PALETTE), s);
    assert.equal(
      sceneToSvg(sc, "ink"),
      sceneToSvg(sc, "ink", { boxState: "outline" }),
      s,
    );
  }
});

test('"outline" is the look before 2026-11-28 on every palette: the state\'s ink, thin, every state', () => {
  for (const [name, pal] of ALL_THEMES)
    for (const s of STATES) {
      const r = rectOf(draw(box(s), pal, "outline"));
      assert.equal(Number(r["stroke-width"]), thinBorder(), `${name} ${s}`);
      const ink: Record<State, string> = {
        live: pal.live,
        inert: pal.inert,
        dead: pal.dead,
        eliminable: pal.ghost,
      };
      assert.equal(r["stroke"], ink[s], `${name} ${s}: the state's ink`);
    }
});

/* ----------------------------------------------- one assertion per state per palette */

for (const [name, pal] of WEIGHT_THEMES) {
  test(`${name}: TRUE has a border as thick as a lit wire, in the live ink`, () => {
    const r = rectOf(draw(box("live"), pal));
    assert.equal(Number(r["stroke-width"]), litWireWidth());
    assert.equal(r["stroke"], pal.live);
  });

  test(`${name}: UNKNOWN is exactly the thin border it has always had, byte for byte`, () => {
    assert.equal(draw(box("inert"), pal), draw(box("inert"), pal, "outline"));
    const r = rectOf(draw(box("inert"), pal));
    assert.equal(Number(r["stroke-width"]), thinBorder());
    assert.equal(r["stroke"], pal.inert);
  });

  test(`${name}: FALSE has no border at all, and is still a click target`, () => {
    const r = rectOf(draw(box("dead"), pal));
    assert.equal(r["stroke"], undefined, "no stroke attribute");
    assert.equal(r["stroke-width"], undefined, "no stroke-width attribute");
    assert.equal(r["stroke-dasharray"], undefined);
    // A rect painted `none` takes no pointer events on its interior, so the box would
    // stop being clickable (the label is a sibling, not a child). It must keep a fill.
    assert.ok(r["fill"] && r["fill"] !== "none", `fill is ${r["fill"]}`);
    assert.match(r["class"]!, /lad-clickable/);
    assert.equal(r["data-value"], "1");
    // and it is at the rect's own place and size: only the border went
    assert.deepEqual(
      [r["x"], r["y"], r["width"], r["height"]],
      ["10.0", "20.0", "100.0", "30.0"],
    );
  });

  test(`${name}: ELIMINABLE is untouched: the dashed ghost outline`, () => {
    assert.equal(
      draw(box("eliminable"), pal),
      draw(box("eliminable"), pal, "outline"),
    );
  });

  test(`${name}: the washes stay: TRUE green, FALSE rose, UNKNOWN plain`, () => {
    const fill = (s: State) => rectOf(draw(box(s), pal))["fill"];
    assert.equal(fill("live"), pal.liveFill);
    assert.equal(fill("dead"), pal.deadFill);
    assert.equal(fill("inert"), pal.boxFill);
  });
}

/* ------------------------------------------------------------------ the ink theme */

test("the ink theme has no thick border and no missing one: the thin border on every state", () => {
  for (const s of STATES) {
    const r = rectOf(draw(box(s), INK_PALETTE));
    assert.equal(Number(r["stroke-width"]), thinBorder(), s);
    assert.ok(r["stroke"], `${s}: every ink box has a border`);
  }
});

interface InkFixture {
  readonly note: string;
  readonly cases: readonly {
    readonly name: string;
    readonly scene: Scene;
    readonly svg: string;
  }[];
}
const inkFixture = JSON.parse(
  readFileSync(
    new URL("./fixtures/ink-before-box-weight.json", import.meta.url),
    "utf8",
  ),
) as InkFixture;

test("the ink emit is byte-identical to what unstable drew before the change", () => {
  assert.ok(inkFixture.cases.length >= 10, "the fixture was emptied");
  for (const c of inkFixture.cases) {
    assert.equal(sceneToSvg(c.scene, "ink"), c.svg, `${c.name} by name`);
    assert.equal(
      sceneToSvg(c.scene, INK_PALETTE),
      c.svg,
      `${c.name} by palette`,
    );
  }
});

test("the ink fixture can tell the looks apart: it holds every state, and weight would move it", () => {
  const boxes = inkFixture.cases.flatMap((c) =>
    c.scene.prims.filter((p) => p.kind === "box"),
  );
  for (const s of STATES)
    assert.ok(
      boxes.some((b) => b.kind === "box" && b.state === s),
      `no ${s} box in the fixture`,
    );
  assert.ok(
    boxes.some((b) => b.kind === "box" && b.tentative),
    "no tentative box in the fixture",
  );
  assert.ok(
    boxes.some((b) => b.kind === "box" && b.role === "placeholder"),
    "no folded placeholder in the fixture",
  );
  // the bytes held above are not ones the weight look would also have produced
  for (const c of inkFixture.cases) {
    const moves = c.scene.prims.some(
      (p) =>
        p.kind === "box" &&
        (p.state === "live" || (p.state === "dead" && !p.tentative)),
    );
    if (moves)
      assert.notEqual(
        sceneToSvg(c.scene, INK_PALETTE, { boxState: "weight" }),
        c.svg,
        c.name,
      );
  }
});

test("a caller's own palette, even one spread from ink, is not the ink theme", () => {
  const mine: Palette = { ...INK_PALETTE };
  assert.equal(
    rectOf(draw(box("live"), mine))["stroke-width"],
    String(litWireWidth()),
  );
  assert.equal(
    draw(box("live"), mine, "outline"),
    draw(box("live"), INK_PALETTE),
  );
  // and a caller can ask the ink palette for the weight look
  assert.equal(
    rectOf(draw(box("live"), INK_PALETTE, "weight"))["stroke-width"],
    String(litWireWidth()),
  );
});

/* ---------------------------------------------------------------- folded groups */

test("a folded placeholder follows the rule by its value; unknown keeps its fold neutral", () => {
  for (const [name, pal] of WEIGHT_THEMES) {
    const ph = (s: State) => rectOf(draw(box(s, { role: "placeholder" }), pal));
    assert.equal(ph("inert")["fill"], pal.placeholderFill, name);
    assert.equal(ph("inert")["stroke"], pal.inert, name);
    assert.equal(Number(ph("inert")["stroke-width"]), thinBorder(), name);
    assert.equal(Number(ph("live")["stroke-width"]), litWireWidth(), name);
    assert.equal(ph("live")["stroke"], pal.live, name);
    // pinned FALSE takes the same path as a leaf: no border
    assert.equal(ph("dead")["stroke"], undefined, `${name}: folded FALSE`);
    assert.ok(ph("dead")["fill"] !== "none", name);
  }
});

/* ------------------------------------------------------------------- tentative */

test("a tentative FALSE box keeps its fine dotted border; only that case", () => {
  for (const [name, pal] of WEIGHT_THEMES) {
    const r = rectOf(draw(box("dead", { tentative: true }), pal));
    assert.equal(r["stroke"], pal.dead, name);
    assert.equal(Number(r["stroke-width"]), thinBorder());
    assert.equal(r["stroke-dasharray"], "1.5 3");
    // …and an UNKNOWN tentative box is byte-identical to the outline look
    assert.equal(
      draw(box("inert", { tentative: true }), pal),
      draw(box("inert", { tentative: true }), pal, "outline"),
    );
  }
});

test("a tentative TRUE box is thick and dotted, the dots scaled with the stroke", () => {
  const r = rectOf(
    draw(box("live", { tentative: true }), SCREEN_PALETTE, "weight"),
  );
  assert.equal(Number(r["stroke-width"]), litWireWidth());
  const [dash, gap] = r["stroke-dasharray"]!.split(" ").map(Number);
  const k = litWireWidth() / thinBorder();
  assert.ok(Math.abs(dash! - 1.5 * k) < 0.06, `dash ${dash}`);
  assert.ok(Math.abs(gap! - 3 * k) < 0.06, `gap ${gap}`);
});

/* -------------------------------------------------------------------- geometry */

test("the thick border is drawn INSIDE the rect: its outer edge is the rect's edge", () => {
  for (const [name, pal] of WEIGHT_THEMES) {
    const r = rectOf(draw(box("live"), pal));
    const sw = Number(r["stroke-width"]);
    const [x, y, w, h, rx] = ["x", "y", "width", "height", "rx"].map((k) =>
      Number(r[k]),
    ) as [number, number, number, number, number];
    // the painted band is [edge - sw/2, edge + sw/2] about the drawn path
    assert.ok(Math.abs(x - sw / 2 - RECT.x) < 0.06, `${name}: left edge`);
    assert.ok(Math.abs(y - sw / 2 - RECT.y) < 0.06, `${name}: top edge`);
    assert.ok(Math.abs(x + w + sw / 2 - (RECT.x + RECT.w)) < 0.06, name);
    assert.ok(Math.abs(y + h + sw / 2 - (RECT.y + RECT.h)) < 0.06, name);
    // and the corner keeps the OUTER radius of the outline look (7), not an inner one
    assert.ok(Math.abs(rx + sw / 2 - 7) < 0.06, `${name}: outer radius`);
  }
});

test("only box lines differ between the looks: wires, text, header and size are the same bytes", () => {
  const fn = {
    id: 0,
    name: "r",
    params: [],
    body: {
      $type: "And" as const,
      id: 1,
      args: [
        { $type: "UBoolVar" as const, id: 2, label: "alpha" },
        { $type: "UBoolVar" as const, id: 3, label: "beta" },
        {
          $type: "Or" as const,
          id: 4,
          args: [
            { $type: "UBoolVar" as const, id: 5, label: "gamma" },
            { $type: "UBoolVar" as const, id: 6, label: "delta" },
          ],
        },
      ],
    },
  };
  const vs = defaultViewSpec({
    valuation: new Map([
      [2, "TrueV"],
      [3, "FalseV"],
      [5, "TrueV"],
    ]),
    showCurrent: true,
  });
  const sc = layout(fn, vs, estimateMetrics);
  const before = JSON.stringify(sc);
  const lines = (m: BoxState) =>
    sceneToSvg(sc, "screen", { boxState: m }).split("\n");
  const base = lines("outline");
  const l = lines("weight");
  assert.equal(l.length, base.length);
  assert.equal(l[0], base[0], "the <svg> header carries scene.size");
  assert.equal(l[1], base[1], "the backdrop");
  let changed = 0;
  l.forEach((line, i) => {
    if (line !== base[i]) {
      changed++;
      assert.match(line, /^<rect data-fnid=/, `non-box line ${i} changed`);
    }
  });
  assert.ok(changed >= 2, "the TRUE and FALSE boxes changed");
  // the option is a render-time choice; it reaches no layout and mutates no scene
  assert.equal(JSON.stringify(sc), before);
});

test("with a call panel, the panel and its backdrop are unchanged by the looks", () => {
  const fn = {
    id: 0,
    name: "top",
    params: [],
    body: {
      $type: "And" as const,
      id: 1,
      label: "outer x",
      call: true,
      args: [
        { $type: "UBoolVar" as const, id: 2, label: "p" },
        { $type: "UBoolVar" as const, id: 3, label: "q" },
      ],
    },
  };
  const sc = layout(
    fn,
    defaultViewSpec({
      valuation: new Map([
        [2, "TrueV"],
        [3, "FalseV"],
      ]),
    }),
    estimateMetrics,
  );
  assert.ok(sc.prims.some((p) => p.kind === "panel"));
  const panelLines = (m: BoxState) =>
    sceneToSvg(sc, "screen", { boxState: m })
      .split("\n")
      .filter((l) => l.includes("lad-panel") || /^<rect width=/.test(l));
  assert.deepEqual(panelLines("weight"), panelLines("outline"));
});
