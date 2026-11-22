/**
 * Call panels in the SVG (C5): the panel prim drawn behind everything as a filled rounded
 * rect, shaded by layer with the darkest outside; the backdrop one step darker than the
 * outermost panel; rule boxes keeping their own fill; and the NOT bubble filled with the NOT's
 * output value (Meng, 2026-10-05).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  sceneToSvg,
  panelShade,
  panelBackdrop,
  SCREEN_PALETTE,
  INK_PALETTE,
  DARK_PALETTE,
} from "../src/index.js";
import type { Palette } from "../src/index.js";
import { layout, defaultViewSpec, estimateMetrics } from "@repo/ladder-core";
import type { FunDecl, IRExpr, Scene, ScenePrim } from "@repo/ladder-core";

const leaf = (id: number, label: string): IRExpr => ({
  $type: "UBoolVar",
  id,
  label,
});
/** `outer x` expands to `NOT p AND inner x`, and `inner x` expands to `q`: two levels. */
const nested: FunDecl = {
  id: 0,
  name: "top",
  params: [],
  body: {
    $type: "And",
    id: 1,
    label: "outer x",
    call: true,
    args: [
      {
        $type: "And",
        id: 2,
        args: [
          { $type: "Not", id: 3, negand: leaf(4, "p") },
          {
            $type: "And",
            id: 5,
            label: "inner x",
            call: true,
            args: [leaf(6, "q")],
          },
        ],
      },
    ],
  },
};
const draw = (opts: Parameters<typeof defaultViewSpec>[0] = {}) =>
  layout(nested, defaultViewSpec(opts), estimateMetrics);

const lum = (hex: string) => {
  const h = hex.replace("#", "");
  const f = h.length === 3 ? h.split("").map((d) => d + d) : h.match(/../g)!;
  const [r, g, b] = f.map((x) => parseInt(x, 16));
  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
};
const backdrop = (svg: string) =>
  /<rect width="\d+" height="\d+" fill="([^"]+)"\/>/.exec(svg)![1]!;
const panelFills = (svg: string) =>
  [
    ...svg.matchAll(/class="lad-panel" data-panel="(\d+)"[^>]*fill="([^"]+)"/g),
  ].map((m) => [Number(m[1]), m[2]!] as const);

test("panels are drawn behind everything, outer before inner", () => {
  const svg = sceneToSvg(draw());
  const body = svg.split("\n").slice(2, -1); // past <svg> and the backdrop
  const kinds = body.map((l) => (l.includes('class="lad-panel"') ? "P" : "x"));
  assert.deepEqual(kinds.slice(0, 2), ["P", "P"]);
  assert.ok(!kinds.slice(2).includes("P"));
  assert.deepEqual(
    panelFills(svg).map(([id]) => id),
    [1, 5],
  );
});

test("shading by layer: backdrop darkest, then outer, then inner; boxes keep boxFill", () => {
  for (const [name, pal] of [
    ["SCREEN", SCREEN_PALETTE],
    ["INK", INK_PALETTE],
    ["DARK", DARK_PALETTE],
  ] as const) {
    const svg = sceneToSvg(draw(), pal);
    const bg = backdrop(svg);
    const [[, outer], [, inner]] = panelFills(svg) as [
      readonly [number, string],
      readonly [number, string],
    ];
    assert.equal(bg, panelBackdrop(pal, 2), `${name}: backdrop two steps out`);
    assert.equal(outer, pal.panelDeep, `${name}: the outer panel one step out`);
    assert.equal(inner, pal.panelNear, `${name}: innermost is the near end`);
    assert.ok(lum(bg) < lum(outer!), `${name}: backdrop darker than outer`);
    assert.ok(lum(outer!) < lum(inner!), `${name}: outer darker than inner`);
    // terms stay the lightest surface (review 2026-10-05: DARK had panels above boxes)
    assert.ok(
      lum(inner!) < lum(pal.boxFill),
      `${name}: innermost panel darker than a term`,
    );
    assert.match(
      svg,
      new RegExp(`class="lad-box[^"]*"[^>]*fill="${pal.boxFill}"`),
      `${name}: an unanswered term keeps the plain box fill`,
    );
  }
});

test("every built-in palette orders backdrop < panelDeep < panelNear < boxFill", () => {
  for (const [name, pal] of [
    ["SCREEN", SCREEN_PALETTE],
    ["INK", INK_PALETTE],
    ["DARK", DARK_PALETTE],
  ] as const) {
    const order = [
      panelBackdrop(pal, 1),
      pal.panelDeep,
      pal.panelNear,
      pal.boxFill,
    ];
    assert.equal(
      order[0],
      pal.panelDeep,
      `${name}: one level's backdrop is panelDeep`,
    );
    assert.ok(
      lum(pal.panelDeep) < lum(pal.panelNear),
      `${name}: deep below near`,
    );
    assert.ok(
      lum(pal.panelNear) < lum(pal.boxFill),
      `${name}: near below boxFill`,
    );
  }
});

test("folding a panel changes no other panel's shade, nor the backdrop", () => {
  const full = sceneToSvg(draw());
  const folded = sceneToSvg(draw({ foldSet: new Set([5]) }));
  assert.equal(backdrop(folded), backdrop(full));
  assert.deepEqual(
    panelFills(folded),
    panelFills(full).filter(([id]) => id !== 5),
  );
});

test("panelShade steps a FIXED amount per layer, however deep the decision", () => {
  // The approved page (live3.ts) stepped 4.5 lightness points per layer from L 95 whatever
  // the depth; an earlier panelShade split fixed ends into `levels` steps, so a one-level
  // decision stepped 9 and a four-level one 2.25 (review 2026-10-05).
  const pal = { ...SCREEN_PALETTE, panelNear: "#cccccc", panelDeep: "#bbbbbb" };
  assert.equal(panelShade(pal, 0, 1), "#cccccc"); // one level: the panel is the near end
  assert.equal(panelShade(pal, -1, 1), "#bbbbbb"); // …and its backdrop one step out
  assert.equal(panelShade(pal, 2, 3), "#cccccc");
  assert.equal(panelShade(pal, 1, 3), "#bbbbbb");
  assert.equal(panelShade(pal, 0, 3), "#aaaaaa");
  assert.equal(panelBackdrop(pal, 3), "#999999");
  assert.equal(panelBackdrop(pal, 20), "#000000"); // clamped, never wraps
  // the approved page's two-level look, to within one unit of hex rounding
  assert.equal(panelBackdrop(SCREEN_PALETTE, 2), "#d1dae4"); // live3: #d2dbe5
  assert.equal(panelBackdrop(SCREEN_PALETTE, 1), "#e0e6ed"); // live3: hsl(212 26% 90.5%)
  // a palette that cannot be mixed gets an end, never an invented colour
  const named: Palette = { ...SCREEN_PALETTE, panelDeep: "navy" };
  assert.equal(panelShade(named, 0, 2), named.panelNear);
  assert.equal(panelBackdrop(named, 2), "navy");
});

test("a scene without panels keeps bg and the plain open-wire ink", () => {
  const plain: Scene = {
    size: { w: 20, h: 20 },
    prims: [
      {
        kind: "wire",
        path: [
          { x: 0, y: 0 },
          { x: 9, y: 0 },
        ],
        role: "rung",
        state: "inert",
        flow: "open",
      },
    ],
  };
  const svg = sceneToSvg(plain);
  assert.equal(backdrop(svg), SCREEN_PALETTE.bg);
  assert.ok(svg.includes(`stroke="${SCREEN_PALETTE.wireOpen}"`));
  const shaded = sceneToSvg({ ...plain, panelDepth: 1 });
  assert.equal(backdrop(shaded), SCREEN_PALETTE.panelDeep);
  assert.equal(
    backdrop(sceneToSvg({ ...plain, panelDepth: 2 })),
    panelBackdrop(SCREEN_PALETTE, 2),
  );
  assert.ok(shaded.includes(`stroke="${SCREEN_PALETTE.wireOpenPanel}"`));
});

test("the panel's name renders clickable, with the fold act and its own ink", () => {
  const svg = sceneToSvg(draw());
  const name = /<text[^>]*>▾ inner x<\/text>/.exec(svg)?.[0];
  assert.ok(name, "the name is drawn");
  assert.match(name, /data-fold="5"/);
  assert.match(name, /lad-clickable/);
  assert.match(name, new RegExp(`fill="${SCREEN_PALETTE.panelLabel}"`));
});

/* ------------------------------------------------------- the NOT bubble's fill */

const bubbleFill = (svg: string) =>
  /<circle[^>]*r="5" fill="([^"]+)"/.exec(svg)![1];

test("the NOT bubble: green when the negand is FALSE, mild red when TRUE, plain when unknown", () => {
  const at = (v?: "TrueV" | "FalseV") =>
    bubbleFill(sceneToSvg(draw({ valuation: new Map(v ? [[4, v]] : []) })));
  assert.equal(at("FalseV"), SCREEN_PALETTE.inverterTrue);
  assert.equal(at("TrueV"), SCREEN_PALETTE.inverterFalse);
  assert.equal(at(), SCREEN_PALETTE.inverterFill);
  // on screen these are the box inks: green, and the mild red of a settled-false box
  assert.equal(SCREEN_PALETTE.inverterTrue, SCREEN_PALETTE.live);
  assert.equal(SCREEN_PALETTE.inverterFalse, SCREEN_PALETTE.dead);
});

test("the bubble fill comes from the palette, in every theme", () => {
  const glyph = (value?: "TrueV" | "FalseV"): ScenePrim => ({
    kind: "glyph",
    at: { x: 5, y: 5 },
    role: "inverter",
    ...(value ? { value } : {}),
  });
  for (const pal of [SCREEN_PALETTE, INK_PALETTE, DARK_PALETTE]) {
    const svg = (v?: "TrueV" | "FalseV") =>
      sceneToSvg({ size: { w: 10, h: 10 }, prims: [glyph(v)] }, pal);
    assert.equal(bubbleFill(svg("TrueV")), pal.inverterTrue);
    assert.equal(bubbleFill(svg("FalseV")), pal.inverterFalse);
    assert.equal(bubbleFill(svg()), pal.inverterFill);
  }
});

const rgb = (hex: string) => {
  const h = hex.replace("#", "");
  const f = h.length === 3 ? h.split("").map((d) => d + d) : h.match(/../g)!;
  return f.map((x) => parseInt(x, 16)) as [number, number, number];
};

test("DARK: the bubble is green for a NOT that holds and RED for one that fails", () => {
  // DARK's `dead` is the bright grey of settled-false text, and it used to fill the bubble
  // (review 2026-10-05, visual-attack/dark-notT-crop.png). Red means red channel on top.
  const [r, g, b] = rgb(DARK_PALETTE.inverterFalse);
  assert.ok(
    r > g + 40 && r > b + 40,
    `inverterFalse ${DARK_PALETTE.inverterFalse} is red`,
  );
  const [r2, g2, b2] = rgb(DARK_PALETTE.inverterTrue);
  assert.ok(
    g2 > r2 + 40 && g2 > b2,
    `inverterTrue ${DARK_PALETTE.inverterTrue} is green`,
  );
  assert.notEqual(DARK_PALETTE.inverterFalse, DARK_PALETTE.dead);
  // and through the real layout: the watched term TRUE makes the bubble red
  const svg = sceneToSvg(
    draw({ valuation: new Map([[4, "TrueV"]]) }),
    DARK_PALETTE,
  );
  assert.equal(bubbleFill(svg), DARK_PALETTE.inverterFalse);
});

test("every palette tells the bubble's three readings apart at a glance", () => {
  // INK used live/dead (#222/#333): two black dots (review 2026-10-05).
  for (const [name, pal] of [
    ["SCREEN", SCREEN_PALETTE],
    ["INK", INK_PALETTE],
    ["DARK", DARK_PALETTE],
  ] as const) {
    const fills = [pal.inverterTrue, pal.inverterFalse, pal.inverterFill].map(
      rgb,
    );
    for (let i = 0; i < 3; i++)
      for (let j = i + 1; j < 3; j++) {
        const d = Math.max(
          ...fills[i]!.map((v, c) => Math.abs(v - fills[j]![c]!)),
        );
        assert.ok(
          d >= 80,
          `${name}: bubble fills ${i} and ${j} differ by only ${d}`,
        );
      }
  }
});
