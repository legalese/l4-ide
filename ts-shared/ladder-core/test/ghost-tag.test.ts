/**
 * The ELIMINABLE ghost's tag, "otiose — always open", and the room an OR stack gives it.
 *
 * Meng, 2026-11-27, looking at the s 415 diagram (the concealment rung ELIMINABLE): "we
 * need to vertically space out the OR so it doesn't collide with the 'otios -- always
 * open'." ("otios" is the tag's text.) The inert "or" between the two rungs of an OR (DESIGN §17) is set in the middle
 * of the gap above the lower rung, and the tag is set 9 px above that rung's box: the two
 * landed on one another, the "or" baseline 0.8 px from the tag's.
 *
 * The fix reserves a band for the tag (`Geometry.TAG_BAND`) in the gap under a medial
 * "or", under a heading, and — through `Measured.tagBand` — in whatever holds an OR or a
 * series whose first element draws a tag. These tests measure INK, not boxes: the ink of
 * a line of text rises `0.78 × size` above its baseline and drops `0.22 × size` below it,
 * the layout's own ascent and descent (`layout.ts`), and it is `estimateMetrics` that
 * says how wide the line is.
 *
 * What is NOT asserted, deliberately: the tag against the FAN CURVES. A tag is about
 * 123 px wide under `estimateMetrics` and a box is `7.84 × chars + 28`, so a ghost leaf
 * with a label under about 12 characters is narrower than its own tag, and a neighbouring
 * rung's curve can cross the overhang. That is older than this change and a different
 * defect (vertical spacing does not touch it); it is recorded in DESIGN §15.1.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  layout,
  defaultViewSpec,
  estimateMetrics,
  monoMetrics,
  sceneToAscii,
  ASCII_GEOMETRY,
  CELL_H,
  PIXEL_GEOMETRY,
} from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  NodeId,
  Scene,
  ScenePrim,
  State,
  UBoolValue,
} from "../src/index.js";

type Text = Extract<ScenePrim, { kind: "text" }>;
type Box = Extract<ScenePrim, { kind: "box" }>;

/** Least clearance, in px, the tag must keep from any other text or box. */
const MIN_CLEARANCE = 4;

let counter = 1000;
const nid = () => ++counter;
const leaf = (label: string): IRExpr => ({
  $type: "UBoolVar",
  id: nid(),
  label,
});
const inert = (text: string): IRExpr => ({
  $type: "InertE",
  id: nid(),
  text,
  context: "InertOr",
});
const and = (args: IRExpr[]): IRExpr => ({ $type: "And", id: nid(), args });
const or = (args: IRExpr[]): IRExpr => ({ $type: "Or", id: nid(), args });
const not = (negand: IRExpr): IRExpr => ({ $type: "Not", id: nid(), negand });
const implies = (scope: IRExpr, requirement: IRExpr): IRExpr => ({
  $type: "Implies",
  id: nid(),
  scope,
  requirement,
});

const sceneOf = (
  body: IRExpr,
  ghosts: IRExpr[],
  extra: Record<string, unknown> = {},
): Scene =>
  layout(
    { id: nid(), name: "r", params: [], body } satisfies FunDecl,
    defaultViewSpec({
      states: new Map<NodeId, State>(
        ghosts.map((g) => [g.id, "eliminable" as const]),
      ),
      ...extra,
    }),
    estimateMetrics,
  );

/* ------------------------------------------------------------------ the helper */

interface Ink {
  x0: number;
  x1: number;
  y0: number;
  y1: number;
}
/** The ink of a text prim, read from the prim's own `size` and `estimateMetrics`. */
const inkOf = (p: Text): Ink => {
  const size = p.size ?? 14;
  const w = estimateMetrics.width(p.text, size);
  const x0 = p.anchor === "middle" ? p.at.x - w / 2 : p.at.x;
  return { x0, x1: x0 + w, y0: p.at.y - 0.78 * size, y1: p.at.y + 0.22 * size };
};
const inkOfBox = (b: Box): Ink => ({
  x0: b.rect.x,
  x1: b.rect.x + b.rect.w,
  y0: b.rect.y,
  y1: b.rect.y + b.rect.h,
});
/** Separation along the better axis: negative when the two inks intersect. */
const clearance = (a: Ink, b: Ink): number =>
  Math.max(a.x0 - b.x1, b.x0 - a.x1, a.y0 - b.y1, b.y0 - a.y1);

const texts = (s: Scene): Text[] =>
  s.prims.filter((p): p is Text => p.kind === "text");
const tagsOf = (s: Scene): Text[] => texts(s).filter((t) => t.tag === "otiose");
const boxes = (s: Scene): Box[] =>
  s.prims.filter((p): p is Box => p.kind === "box");

/** Every other text and every box, with its name for the failure message. */
const neighbours = (s: Scene, tag: Text): Array<[string, Ink]> => [
  ...texts(s)
    .filter((t) => t !== tag)
    .map((t): [string, Ink] => [`${t.tag ?? "label"} "${t.text}"`, inkOf(t)]),
  ...boxes(s).map((b): [string, Ink] => [`box ${b.id}`, inkOfBox(b)]),
];

/** The assertion every case below makes: each otiose tag keeps MIN_CLEARANCE from every
 *  other text and every box. `want` is how many tags the fixture should draw, so that a
 *  scene which drew none cannot pass by having nothing to measure. */
const assertTagsClear = (s: Scene, want: number, name: string) => {
  const tags = tagsOf(s);
  assert.equal(tags.length, want, `${name}: draws ${want} tag(s)`);
  for (const t of tags)
    for (const [what, other] of neighbours(s, t))
      assert.ok(
        clearance(inkOf(t), other) >= MIN_CLEARANCE,
        `${name}: the tag at (${t.at.x.toFixed(1)}, ${t.at.y.toFixed(1)}) is ${clearance(inkOf(t), other).toFixed(2)} px from ${what}`,
      );
};

/* --------------------------------------- the s 415 second limb, applicants' reading */

/** DESIGN §15.4, as `ladder-svg/demo/s415.ts` builds it: the concealment rung is
 *  ELIMINABLE, and it is the second rung of an OR whose first rung is followed by "or". */
const s415 = () => {
  const byDeceiving = leaf("by deceiving");
  const concealment = leaf("dishonest concealment");
  const deception = or([
    inert("there is a deception (Expl. 1)"),
    byDeceiving,
    inert("or"),
    concealment,
  ]);
  const harm = or([
    leaf("body"),
    leaf("mind"),
    leaf("reputation"),
    inert("or"),
    leaf("property"),
  ]);
  const body = and([
    deception,
    leaf("intentionally"),
    inert("induces an act or omission that"),
    leaf("causes harm"),
    inert("to any person in"),
    harm,
  ]);
  return { body, concealment };
};

test("s 415: the tag and the medial 'or' of the deception OR do not meet, LR and TB", () => {
  for (const orient of ["LR", "TB"] as const) {
    const { body, concealment } = s415();
    const s = sceneOf(body, [concealment], { orient });
    const [tag] = tagsOf(s);
    assert.ok(tag, `${orient}: the ghost rung is tagged`);
    // Both ORs' medial 'or's can share the tag's column (in TB the whole series is centred on
    // one axis), so take the nearest one above the tag: that is the deception OR's own.
    const ors = texts(s).filter(
      (t) => t.tag === "connective" && t.text === "or",
    );
    assert.equal(
      ors.length,
      2,
      `${orient}: the two medial 'or's are both drawn`,
    );
    const mine = ors
      .filter((t) => Math.abs(t.at.x - tag.at.x) < 1 && t.at.y < tag.at.y)
      .sort((p, q) => q.at.y - p.at.y);
    assert.ok(mine.length >= 1, `${orient}: an 'or' sits above the ghost rung`);
    const gap = clearance(inkOf(tag), inkOf(mine[0]));
    assert.ok(
      gap >= MIN_CLEARANCE,
      `${orient}: tag and 'or' are ${gap.toFixed(2)} px apart (want ≥ ${MIN_CLEARANCE})`,
    );
    assert.ok(
      mine[0].at.y < tag.at.y,
      `${orient}: the 'or' stays above the tag`,
    );
    assertTagsClear(s, 1, `${orient} s415`);
  }
});

test("the reserved band is exactly the tag's reach above its box, and is read from the tag", () => {
  const { body, concealment } = s415();
  const s = sceneOf(body, [concealment]);
  const [tag] = tagsOf(s);
  const box = boxes(s).find((b) => b.id === concealment.id)!;
  // the band is TAG_RISE + the ascent of the tag's own size, read from the prim
  const reach = box.rect.y - inkOf(tag).y0;
  assert.ok(Math.abs(reach - PIXEL_GEOMETRY.TAG_BAND) < 1e-9, `${reach}`);
});

test("only the ghost scene grows, and by exactly one band", () => {
  // A standalone OR, so the stack's own height is the scene's. (In the s 415 diagram the
  // deception OR is shorter than the harm OR beside it, so its band is absorbed by the row
  // and the scene is no taller; the ghost's neighbours are not pushed.)
  const ghost = leaf("dishonest concealment");
  const body = or([leaf("by deceiving"), inert("or"), ghost]);
  const withGhost = sceneOf(body, [ghost]);
  const without = sceneOf(body, []);
  assert.equal(withGhost.size.w, without.size.w, "the width is unchanged");
  assert.ok(
    Math.abs(withGhost.size.h - without.size.h - PIXEL_GEOMETRY.TAG_BAND) <
      1e-9,
    `${withGhost.size.h - without.size.h} vs ${PIXEL_GEOMETRY.TAG_BAND}`,
  );
});

/* ------------------------------------------------------- the other places a tag sits */

test("the first rung is the ghost: it clears the OR's heading, mirrored so the rail stays straight", () => {
  const ghost = leaf("dishonest concealment");
  const body = or([
    inert("there is a deception"),
    ghost,
    inert("or"),
    leaf("b"),
  ]);
  for (const orient of ["LR", "TB"] as const) {
    const s = sceneOf(body, [ghost], { orient });
    assertTagsClear(s, 1, `${orient} first-rung ghost under a heading`);
    const plain = sceneOf(body, [], { orient });
    assert.ok(
      Math.abs(s.size.h - plain.size.h - 2 * PIXEL_GEOMETRY.TAG_BAND) < 1e-9,
      `${orient}: the heading band grows at the top and mirrors at the bottom`,
    );
  }
});

test("the first rung is the ghost and there is no heading: the stack itself is not taller", () => {
  const ghost = leaf("dishonest concealment");
  const body = or([ghost, inert("or"), leaf("b")]);
  const s = sceneOf(body, [ghost]);
  assertTagsClear(s, 1, "first-rung ghost, no heading");
  assert.equal(
    s.size.h,
    sceneOf(body, []).size.h,
    "nothing above it to make room for",
  );
});

test("a folded group that is eliminable is tagged and cleared like a leaf", () => {
  const group = and([leaf("x"), leaf("y")]);
  const body = or([leaf("a"), inert("or"), group]);
  const s = sceneOf(body, [group], { foldSet: new Set([group.id]) });
  assertTagsClear(s, 1, "folded ghost group");
});

test("three rungs: each ghost under its own 'or' gets its own band", () => {
  const b = leaf("a long second rung");
  const c = leaf("a long third rung");
  const body = or([leaf("a long first rung"), inert("or"), b, inert("or"), c]);
  const s = sceneOf(body, [b, c]);
  assertTagsClear(s, 2, "three rungs, two ghosts");
  const plain = sceneOf(body, []);
  assert.ok(
    Math.abs(s.size.h - plain.size.h - 2 * PIXEL_GEOMETRY.TAG_BAND) < 1e-9,
    "two bands",
  );
  // …and a ghost under NO connective takes no band: the ordinary gap already holds the tag
  const d = leaf("a long second rung");
  const bare = or([leaf("a long first rung"), d]);
  assert.equal(
    sceneOf(bare, [d]).size.h,
    sceneOf(bare, []).size.h,
    "an unlabelled gap is as it was",
  );
});

test("a ghost that is the first rung of a nested OR clears the PARENT's 'or'", () => {
  const ghost = leaf("a long ghost rung label");
  const body = or([leaf("a"), inert("or"), or([ghost, leaf("c")])]);
  const s = sceneOf(body, [ghost]);
  assertTagsClear(s, 1, "nested OR, first rung ghost");
});

test("a ghost inside a series rung clears the parent's 'or' — first in a TB column, or any child in LR", () => {
  for (const orient of ["LR", "TB"] as const) {
    for (const order of ["ghost first", "ghost second"] as const) {
      const ghost = leaf("a ghost atom here");
      const series =
        order === "ghost first"
          ? and([ghost, leaf("a")])
          : and([leaf("a"), ghost]);
      const s = sceneOf(or([leaf("b"), inert("or"), series]), [ghost], {
        orient,
      });
      assertTagsClear(s, 1, `${orient} series rung, ${order}`);
    }
  }
});

test("a ghost that is the first rung of an OR inside an IMPLIES rung clears the parent's 'or', LR and TB", () => {
  // `measureImplies` passes the band of its scope and requirement up, as a series does.
  // The requirement is a three-rung OR, taller than the lamp pair, so the ghost's tag
  // reaches above the rule's own top edge.
  for (const orient of ["LR", "TB"] as const) {
    for (const where of ["requirement", "scope"] as const) {
      const ghost = leaf("a long ghost rung label");
      const stack = or([ghost, leaf("c"), leaf("d")]);
      const rule =
        where === "requirement"
          ? implies(leaf("p"), stack)
          : implies(stack, leaf("q"));
      const body = or([leaf("a"), inert("or"), rule]);
      const s = sceneOf(body, [ghost], { orient });
      assertTagsClear(
        s,
        1,
        `${orient} ghost in the ${where} of an IMPLIES rung`,
      );
      assert.ok(
        s.size.h > sceneOf(body, [], { orient }).size.h,
        `${orient} ${where}: the parent made room for it`,
      );
    }
  }
});

test("a ghost leaf deep inside an IMPLIES rung reserves no band: the rule is taller than it", () => {
  // The lamp pair makes the rule at least 137 px tall, so a one-line requirement sits
  // (h - its height) / 2 below the rule's top and its tag is inside the rule.
  for (const orient of ["LR", "TB"] as const) {
    const ghost = leaf("a long ghost rung label");
    const body = or([leaf("a"), inert("or"), implies(leaf("p"), ghost)]);
    const s = sceneOf(body, [ghost], { orient });
    assertTagsClear(s, 1, `${orient} ghost requirement`);
    assert.equal(
      s.size.h,
      sceneOf(body, [], { orient }).size.h,
      `${orient}: not a pixel taller`,
    );
  }
});

/* ------------------------- the band is for ELIMINABLE rungs, and for the first child only */

test("only an ELIMINABLE rung gets a band: dead, live and unknown rungs under an 'or' do not", () => {
  const b = leaf("a long second rung");
  const body = or([leaf("a long first rung"), inert("or"), b]);
  const at = (vals: Array<[NodeId, UBoolValue]>, states: IRExpr[] = []) =>
    sceneOf(body, states, { valuation: new Map(vals) }).size.h;
  const unknown = at([]);
  assert.equal(at([[b.id, "FalseV"]]), unknown, "a dead rung (known false)");
  assert.equal(at([[b.id, "TrueV"]]), unknown, "a live rung (known true)");
  assert.equal(
    at([], [b]),
    unknown + PIXEL_GEOMETRY.TAG_BAND,
    "an eliminable rung: exactly one band",
  );
});

test("LR: a series passes up only what its tallest sibling leaves uncovered", () => {
  const stacked = (extra: IRExpr[]) => or([...extra, leaf("c"), leaf("d")]);
  // equal heights: the ghost's top is the series' top, so the whole band passes up
  const g1 = leaf("a long ghost rung label");
  const level = or([leaf("b"), inert("or"), and([g1, leaf("a")])]);
  assert.equal(
    sceneOf(level, [g1]).size.h,
    sceneOf(level, []).size.h + PIXEL_GEOMETRY.TAG_BAND,
    "level siblings: exactly one band",
  );
  // a sibling far taller than the ghost: the ghost sits well below the series' top and its
  // tag is inside the row, so nothing is reserved
  const g2 = leaf("a long ghost rung label");
  const tall = or([leaf("b"), inert("or"), and([g2, stacked([leaf("x")])])]);
  const s = sceneOf(tall, [g2]);
  assertTagsClear(s, 1, "LR ghost beside a tall sibling");
  assert.equal(s.size.h, sceneOf(tall, []).size.h, "not a pixel taller");
});

test("TB: a series passes up the band of its FIRST child only", () => {
  const first = leaf("a long ghost rung label");
  const second = leaf("a long ghost rung label");
  const ghostFirst = or([leaf("b"), inert("or"), and([first, leaf("a")])]);
  const ghostSecond = or([leaf("b"), inert("or"), and([leaf("a"), second])]);
  const orient = "TB";
  assert.equal(
    sceneOf(ghostFirst, [first], { orient }).size.h,
    sceneOf(ghostFirst, [], { orient }).size.h + PIXEL_GEOMETRY.TAG_BAND,
    "first in the column: its tag is above the series, one band",
  );
  const s = sceneOf(ghostSecond, [second], { orient });
  assertTagsClear(s, 1, "TB ghost second in a column");
  assert.equal(
    s.size.h,
    sceneOf(ghostSecond, [], { orient }).size.h,
    "second in the column: its tag is between the children, nothing passes up",
  );
});

/* ------------------------------------- no tag drawn, no band reserved */

test("an eliminable NOT or IMPLIES rung draws no tag, so it reserves no band", () => {
  const x = leaf("x");
  const notRung = not(x);
  const im = implies(leaf("p"), leaf("q"));
  for (const [name, rung] of [
    ["NOT", notRung],
    ["IMPLIES", im],
  ] as const) {
    const body = or([leaf("a"), inert("or"), rung]);
    const ghost = sceneOf(body, [rung]);
    assert.equal(tagsOf(ghost).length, 0, `${name}: no tag`);
    assert.equal(
      ghost.size.h,
      sceneOf(body, []).size.h,
      `${name}: not a pixel taller than without the ghost state`,
    );
  }
});

/* ------------------------------------------------------ the ASCII carrier, same defect */

test("ASCII: the tag and the 'or' sit on different rows, and the band is whole rows", () => {
  const byDeceiving = leaf("by deceiving");
  const ghost = leaf("dishonest concealment");
  const body = or([
    inert("there is a deception"),
    byDeceiving,
    inert("or"),
    ghost,
  ]);
  const s = layout(
    { id: nid(), name: "r", params: [], body } satisfies FunDecl,
    defaultViewSpec({
      states: new Map<NodeId, State>([[ghost.id, "eliminable"]]),
    }),
    monoMetrics(),
    ASCII_GEOMETRY,
  );
  const [tag] = tagsOf(s);
  const [medial] = texts(s).filter((t) => t.tag === "connective");
  assert.ok(tag && medial);
  // `sceneToAscii` puts a baseline on row `round(y / CELL_H)`
  const rowOf = (y: number) => Math.round(y / CELL_H);
  assert.equal(
    rowOf(tag.at.y) - rowOf(medial.at.y),
    2,
    `the tag is on row ${rowOf(tag.at.y)} and the 'or' on row ${rowOf(medial.at.y)}`,
  );
  // …and the band is exactly two rows: the same OR with no ghost is two rows shorter
  const plain = layout(
    { id: nid(), name: "r", params: [], body } satisfies FunDecl,
    defaultViewSpec({}),
    monoMetrics(),
    ASCII_GEOMETRY,
  );
  assert.equal(s.size.h - plain.size.h, 2 * CELL_H);
  const art = sceneToAscii(s);
  assert.ok(art.includes("otiose — always open"), "the tag survives whole");
  assert.ok(!/orways/.test(art), "…and is not overprinted by the 'or'");
  // the band is whole rows, and an EVEN number of them: the stack's centre must stay on a row
  assert.equal(ASCII_GEOMETRY.TAG_BAND, 2 * CELL_H);
});
