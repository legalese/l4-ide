/** palette.ts + the S8 parameterisation of svg.ts.
 *
 * Two things are under test and only one of them is behaviour.
 *
 * The first is **byte-identity**: making the palette a parameter must not move a single
 * character of the default output, because `test/svg.test.ts` asserts on literal hexes and
 * the 25 committed doc-figure carriers under `jl4/examples/legal/regcf/figures/` are
 * exhibits. That is guaranteed by construction (`SCREEN_PALETTE` carries the old literals
 * verbatim) and checked here anyway.
 *
 * The second is the **source scan** at the bottom, and it is the test with teeth: it fails
 * if anyone ever re-bakes a colour into `svg.ts`. Behavioural tests cannot catch that — a
 * newly baked colour still renders — so without the scan the seam re-opens quietly.
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
import type { Palette } from "../src/index.js";
import type { Scene, ScenePrim } from "@repo/ladder-core";

/** A Scene that reaches every branch of `prim()`: both box roles plus eliminable, a rail
 *  wire and all three flow weights, all four glyph roles, a lit and an unlit coil of each
 *  colour, a frame, and one text per fill branch. */
const prims: ScenePrim[] = [
  {
    kind: "box",
    id: 1,
    rect: { x: 0, y: 0, w: 80, h: 30 },
    role: "leaf",
    state: "live",
  },
  {
    kind: "box",
    id: 2,
    rect: { x: 0, y: 40, w: 80, h: 30 },
    role: "leaf",
    state: "inert",
  },
  {
    kind: "box",
    id: 3,
    rect: { x: 0, y: 80, w: 80, h: 30 },
    role: "leaf",
    state: "eliminable",
  },
  {
    kind: "box",
    id: 4,
    rect: { x: 0, y: 120, w: 80, h: 30 },
    role: "placeholder",
    state: "live",
  },
  {
    kind: "box",
    id: 5,
    rect: { x: 0, y: 160, w: 80, h: 30 },
    role: "leaf",
    state: "dead",
  },
  {
    kind: "wire",
    path: [
      { x: 0, y: 0 },
      { x: 9, y: 0 },
    ],
    role: "rail",
    state: "inert",
  },
  {
    kind: "wire",
    path: [
      { x: 0, y: 1 },
      { x: 9, y: 1 },
    ],
    role: "rung",
    state: "live",
    flow: "closed",
  },
  {
    kind: "wire",
    path: [
      { x: 0, y: 2 },
      { x: 9, y: 2 },
    ],
    role: "rung",
    state: "live",
    flow: "open",
  },
  {
    kind: "curve",
    from: { x: 0, y: 0 },
    c1: { x: 1, y: 1 },
    c2: { x: 2, y: 2 },
    to: { x: 3, y: 3 },
    role: "conn",
    state: "live",
    flow: "streamer",
  },
  { kind: "glyph", at: { x: 1, y: 1 }, role: "changeover" },
  { kind: "glyph", at: { x: 2, y: 2 }, role: "inverter" },
  { kind: "glyph", at: { x: 3, y: 3 }, role: "open-contact" },
  { kind: "glyph", at: { x: 4, y: 4 }, role: "power-terminal" },
  {
    kind: "coil",
    at: { x: 5, y: 5 },
    role: "green",
    lit: true,
    label: "complies",
  },
  {
    kind: "coil",
    at: { x: 5, y: 6 },
    role: "red",
    lit: true,
    label: "in breach",
  },
  {
    kind: "coil",
    at: { x: 5, y: 7 },
    role: "green",
    lit: false,
    label: "complies",
  },
  { kind: "frame", rect: { x: 0, y: 0, w: 10, h: 10 }, label: "not" },
  {
    kind: "text",
    at: { x: 1, y: 1 },
    text: "body",
    anchor: "start",
    state: "live",
  },
  {
    kind: "text",
    at: { x: 1, y: 2 },
    text: "▸",
    anchor: "start",
    state: "live",
    tag: "caret",
  },
  {
    kind: "text",
    at: { x: 1, y: 3 },
    text: "MUST",
    anchor: "start",
    state: "live",
    tag: "seam",
  },
  {
    kind: "text",
    at: { x: 1, y: 4 },
    text: "typically",
    anchor: "start",
    state: "live",
    tag: "typically",
  },
  {
    kind: "text",
    at: { x: 1, y: 5 },
    text: "gone",
    anchor: "start",
    state: "live",
    tag: "otiose",
  },
  {
    kind: "text",
    at: { x: 1, y: 6 },
    text: "title",
    anchor: "start",
    state: "inert",
    tag: "title",
  },
  {
    kind: "text",
    at: { x: 1, y: 7 },
    text: "assumed false",
    anchor: "start",
    state: "live",
    tag: "assumed",
  },
];

const scene: Scene = { size: { w: 400, h: 200 }, prims };

/** `complete` and `provisional` are SCENE-level and mutually exclusive in what they select
 *  — `wireMade` needs a made circuit, `wireMadeProvisional` needs a made-but-presumed one —
 *  so no single render can reach both. The contract test unions all three readings. */
const scenes: Scene[] = [
  scene,
  { ...scene, complete: true },
  { ...scene, complete: true, provisional: true },
];

/* --------------------------------------------------------------- byte-identity (R3) */

test("the default emit is byte-identical whether the palette is implicit, named, or passed", () => {
  const implicit = sceneToSvg(scene);
  assert.equal(implicit, sceneToSvg(scene, "screen"));
  assert.equal(implicit, sceneToSvg(scene, SCREEN_PALETTE));
});

test("the ink theme name and INK_PALETTE are the same palette", () => {
  assert.equal(sceneToSvg(scene, "ink"), sceneToSvg(scene, INK_PALETTE));
  assert.notEqual(sceneToSvg(scene, "ink"), sceneToSvg(scene, "screen"));
});

/* ------------------------------------------------- the contract: every field is wired */

/** Every field. `dead` used to be excluded — see the test that now covers it. */
const REACHABLE: Array<keyof Palette> = [
  "live",
  "inert",
  "dead",
  "ghost",
  "rail",
  "ink",
  "bg",
  "eliminableFill",
  "boxFill",
  "placeholderFill",
  "wireClosed",
  "wireStreamer",
  "wireOpen",
  "coilGreen",
  "coilRed",
  "coilOff",
  "coilHollow",
  "glyphDot",
  "inverterFill",
  "inverterStroke",
  "frameStroke",
  "frameLabel",
  "caret",
  "seam",
  "typically",
  "tagInk",
  "wireMade",
  "wireMadeProvisional",
  "coilGreenSoft",
  "coilRedSoft",
  "assumed",
];

/** A palette whose every field is a distinct sentinel, so "did this field reach the emit"
 *  is a substring search rather than an argument. */
const sentinelPalette = (): Palette => {
  const out = {} as Record<string, string>;
  REACHABLE.forEach((f, i) => {
    out[f] = `#${(0xaa0000 + i).toString(16).padStart(6, "0")}`;
  });
  return out as unknown as Palette;
};

test("the palette has exactly the 31 fields the specs quote", () => {
  // Pinned because the count is quoted in prose that cannot check itself: E1-IDE-INTEGRATION
  // .md's S8 row and EMBEDDABLE.md §2 / §9 R8 all name it. An earlier draft of those rows said
  // "21 colours … 14 literals" — 14 was a count of SITES (svg.ts:41 carried three colours,
  // :59, :90 and :113 two each), and the wrong number was transcribed into three owning
  // documents before anyone counted. Adding a field now fails here, which is the reminder to
  // move the prose with the code.
  //
  // 26 -> 31: DESIGN §26's fix wired `dead` up and brought five new colours (the two
  // made-circuit inks, the two soft coils, and `assumed`). The three owning documents
  // moved in the same commit.
  assert.equal(Object.keys(SCREEN_PALETTE).length, 31);
  assert.equal(Object.keys(INK_PALETTE).length, 31);
  assert.equal(Object.keys(DARK_PALETTE).length, 31);
  assert.equal(REACHABLE.length, 31, "REACHABLE must cover the type");
});

test("every reachable Palette field actually reaches the emit", () => {
  const pal = sentinelPalette();
  const svg = scenes.map((s) => sceneToSvg(s, pal)).join("\n");
  const missing = REACHABLE.filter((f) => !svg.includes(pal[f]));
  assert.deepEqual(
    missing,
    [],
    `these palette fields never appear in the output — either the fixture does not reach ` +
      `their branch, or svg.ts still has a literal there: ${missing.join(", ")}`,
  );
  assert.notEqual(
    svg,
    scenes.map((s) => sceneToSvg(s)).join("\n"),
    "a custom palette must change the bytes",
  );
});

test("a FALSE box does not render as an UNKNOWN one — DESIGN §26.1", () => {
  // The regression test for the headline defect. `strokeFor` used to map live -> live,
  // eliminable -> ghost and EVERYTHING ELSE -> inert, so the `dead` State never read
  // `pal.dead`; with `dead === inert` in every built-in palette, a tested-and-false box
  // emitted BYTE-IDENTICAL SVG to one nobody had answered. §25.4 tells N/A from
  // undetermined purely by that contrast, so the two-lamp form had lost its only way to
  // say which a reader was looking at.
  const pal = sentinelPalette();
  const emit = (state: "dead" | "inert") =>
    sceneToSvg(
      {
        size: { w: 10, h: 10 },
        prims: [
          {
            kind: "box",
            id: 1,
            rect: { x: 0, y: 0, w: 8, h: 8 },
            role: "leaf",
            state,
          } as ScenePrim,
        ],
      },
      pal,
    );

  assert.notEqual(
    emit("dead"),
    emit("inert"),
    "a false atom and an unanswered one must not be the same picture",
  );
  assert.ok(emit("dead").includes(pal.dead), "pal.dead must reach the emit");
  assert.ok(!emit("dead").includes(pal.inert), "and pal.inert must not");
});

test("every built-in palette separates dead from inert", () => {
  // The ink is only half of it: the fix is worthless if a palette hands the same value to
  // both fields, which is exactly how the defect survived S8 — `dead` was declared, and
  // set to `inert`'s grey, in all three.
  for (const [name, pal] of [
    ["SCREEN", SCREEN_PALETTE],
    ["INK", INK_PALETTE],
    ["DARK", DARK_PALETTE],
  ] as const)
    assert.notEqual(
      pal.dead,
      pal.inert,
      `${name}: dead must differ from inert`,
    );
});

test("a dark palette leaves no white fill behind — S8's actual complaint", () => {
  const svg = sceneToSvg(scene, DARK_PALETTE);
  assert.ok(
    svg.includes(`fill="${DARK_PALETTE.bg}"`),
    "the backdrop must be dark",
  );
  assert.doesNotMatch(svg, /fill="#ffffff"/i);
  assert.doesNotMatch(
    svg,
    /#1a7f37/i,
    "the screen green must not leak through",
  );
});

/* ----------------------------------------------------------------- the source scan */

const HEX = /#[0-9a-fA-F]{3,8}\b/;
const read = (rel: string) =>
  readFileSync(new URL(rel, import.meta.url), "utf8");

test("svg.ts contains no colour literal at all", () => {
  const src = read("../src/svg.ts");
  const hit = HEX.exec(src);
  assert.equal(
    hit,
    null,
    `svg.ts has a baked colour (${hit?.[0]}) — seam S8 says every colour is a Palette field`,
  );
});

test("palette.ts has no colour literal below the end-of-palettes marker", () => {
  const src = read("../src/palette.ts");
  const i = src.indexOf("END OF PALETTES");
  assert.ok(i > 0, "the end-of-palettes marker went missing");
  const hit = HEX.exec(src.slice(i));
  assert.equal(hit, null, `a colour literal escaped the palettes: ${hit?.[0]}`);
});
