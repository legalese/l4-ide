/** HEAD AS SINK (`ViewSpec.headAsSink`) — the decision's own name as the rightmost node.
 *
 * A Layman Allen normalised diagram names both ends of the run: in Woon, *Essential
 * Criminal Law* ch 8, the robbery figure runs `Offender` at the left margin through the
 * elements to `Commits Robbery` at the right. Our ladder has always drawn both ends as
 * bare power terminals, so the picture stated the antecedent and left the consequent to
 * the caption. This option draws it.
 *
 * What the tests below are actually defending, in order of how expensive each would be
 * to discover later:
 *
 *   1. DEFAULT OFF, and off means *byte-identical* — every existing figure, golden and
 *      corpus projection depends on that, and "I added an option" is exactly the change
 *      that quietly moves a scene by one lead-length.
 *   2. The head is a TERMINAL, i.e. it sits between the body's last box and the sink,
 *      not somewhere merely to the right of things.
 *   3. It is NOT clickable and draws NO second break — both are ways of reporting
 *      something the head does not know.
 *   4. An `Implies` body ignores it, because such a rule already has its two sinks.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  layout,
  estimateMetrics,
  defaultViewSpec,
  PIXEL_GEOMETRY,
} from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  And,
  Implies,
  Scene,
  ScenePrim,
  NodeId,
  UBoolValue,
} from "../src/index.js";

let c = 0;
const nid = () => ++c;
const leaf = (label: string): Leaf => ({
  $type: "UBoolVar",
  id: nid(),
  label,
  atomId: label,
});
const and = (args: IRExpr[]): And => ({ $type: "And", id: nid(), args });

const theft = leaf("commits theft");
const forThatEnd = leaf("for that end");
const body = and([theft, forThatEnd]);
/** Backticked, the way a wire name arrives from `viz-adapter` (`name: viz.name.label`). */
const fn: FunDecl = {
  id: nid(),
  name: "`theft is robbery`",
  params: [],
  body,
};

const tm = estimateMetrics;
const boxes = (s: Scene) => s.prims.filter((p) => p.kind === "box");
const heads = (s: Scene) => boxes(s).filter((b) => b.role === "head");
const terminal = (s: Scene) =>
  s.prims.find(
    (p) => p.kind === "glyph" && p.role === "power-terminal" && p.at.x > 100,
  );

const plain = layout(fn, defaultViewSpec({}), tm);
const withHead = layout(fn, defaultViewSpec({ headAsSink: true }), tm);

/* ---------------------------------------------------------------- 1. default off */

test("headAsSink is off by default, and off leaves the scene untouched", () => {
  assert.equal(defaultViewSpec({}).headAsSink, false);
  assert.equal(heads(plain).length, 0);
  // Not "roughly the same" — the same. Anything else and every committed figure moves.
  const explicitlyOff = layout(fn, defaultViewSpec({ headAsSink: false }), tm);
  assert.deepEqual(explicitlyOff, plain);
});

/* ------------------------------------------------- 2. one extra node, before the sink */

test("on, the scene gains exactly one terminal node carrying the head text", () => {
  assert.equal(heads(withHead).length, 1);
  assert.equal(boxes(withHead).length, boxes(plain).length + 1);
  const head = heads(withHead)[0];
  // the L4 backticks are quoting for a spaced identifier, not part of the name
  const label = withHead.prims.find(
    (p) => p.kind === "text" && p.id === head.id,
  );
  assert.ok(label && label.kind === "text");
  assert.equal(label.text, "theft is robbery");
  assert.equal(head.id, fn.id);
});

test("the head sits BETWEEN the body's last box and the sink terminal", () => {
  const head = heads(withHead)[0];
  const bodyBoxes = boxes(withHead).filter((b) => b.role !== "head");
  const rightmostBody = Math.max(...bodyBoxes.map((b) => b.rect.x + b.rect.w));
  const sink = terminal(withHead);
  assert.ok(sink && sink.kind === "glyph");
  assert.ok(
    head.rect.x > rightmostBody,
    `head at ${head.rect.x} should start right of the body's ${rightmostBody}`,
  );
  assert.ok(
    head.rect.x + head.rect.w < sink.at.x,
    `head ends at ${head.rect.x + head.rect.w}, sink is at ${sink.at.x}`,
  );
  // …and on the same axis the run was already on
  const cy = head.rect.y + head.rect.h / 2;
  assert.ok(Math.abs(cy - sink.at.y) < 0.01);
});

test("the scene widens by the head plus one lead, and the body does not move", () => {
  assert.ok(withHead.size.w > plain.size.w);
  const head = heads(withHead)[0];
  assert.ok(
    Math.abs(
      withHead.size.w - (plain.size.w + head.rect.w + PIXEL_GEOMETRY.LEAD),
    ) < 0.01,
  );
  const first = (s: Scene) => boxes(s).filter((b) => b.role !== "head")[0].rect;
  assert.deepEqual(first(withHead), first(plain));
});

/* ------------------------------------------- 3. what the head deliberately does NOT do */

test("the head carries no click affordance — its value is derived, not settable", () => {
  assert.equal(heads(withHead)[0].act, undefined);
});

test("the head takes the body's verdict, and does not draw a second break", () => {
  const val = (v: UBoolValue) =>
    new Map<NodeId, UBoolValue>([
      [theft.id, v],
      [forThatEnd.id, v],
    ]);
  const breaks = (s: Scene) =>
    s.prims.filter((p) => p.kind === "glyph" && p.role === "open-contact");

  const yes = layout(
    fn,
    defaultViewSpec({ valuation: val("TrueV"), headAsSink: true }),
    tm,
  );
  assert.equal(heads(yes)[0].state, "live");

  const no = layout(
    fn,
    defaultViewSpec({ valuation: val("FalseV"), headAsSink: true }),
    tm,
  );
  assert.equal(heads(no)[0].state, "dead");
  // the break belongs where the current stopped — inside the body — and the head must
  // not report the same failure a second time
  const noPlain = layout(fn, defaultViewSpec({ valuation: val("FalseV") }), tm);
  assert.equal(breaks(no).length, breaks(noPlain).length);

  const dunno = layout(fn, defaultViewSpec({ headAsSink: true }), tm);
  assert.equal(heads(dunno)[0].state, "inert");
});

test("both rails round the head carry the body's own flow", () => {
  const lit = layout(
    fn,
    defaultViewSpec({
      valuation: new Map<NodeId, UBoolValue>([
        [theft.id, "TrueV"],
        [forThatEnd.id, "TrueV"],
      ]),
      showCurrent: true,
      headAsSink: true,
    }),
    tm,
  );
  const head = heads(lit)[0];
  const rails = lit.prims.filter(
    (p): p is Extract<ScenePrim, { kind: "wire" }> =>
      p.kind === "wire" && p.role === "rail",
  );
  const after = rails.filter((r) => r.path[0].x >= head.rect.x + head.rect.w);
  assert.equal(after.length, 1);
  assert.equal(after[0].flow, "closed");
  assert.equal(lit.complete, true);
});

/* ------------------------------------------------------------ 4. an Implies ignores it */

test("an Implies body ignores headAsSink — it already has its two sinks", () => {
  const rule: Implies = {
    $type: "Implies",
    id: nid(),
    scope: leaf("in scope"),
    requirement: leaf("does the thing"),
    seam: "IMPLIES",
  };
  const ruleFn: FunDecl = { id: nid(), name: "a duty", params: [], body: rule };
  const off = layout(ruleFn, defaultViewSpec({}), tm);
  const on = layout(ruleFn, defaultViewSpec({ headAsSink: true }), tm);
  assert.equal(heads(on).length, 0);
  assert.deepEqual(on, off);
  assert.equal(on.prims.filter((p) => p.kind === "coil").length, 2);
});

/* ----------------------------------------------- a head with no name draws no box */

test("a nameless decision gets no head box rather than an empty one", () => {
  const anon: FunDecl = { id: nid(), name: "``", params: [], body };
  assert.equal(
    heads(layout(anon, defaultViewSpec({ headAsSink: true }), tm)).length,
    0,
  );
});
