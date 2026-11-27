/**
 * The open-contact BREAK — the pair of short vertical bars once drawn on the wire where
 * the circuit stopped (DESIGN §15.1, §25.4) — and why no element draws one any more.
 *
 * Meng, 2026-11-27, first: "i wonder if we can do without the open-contact break; the
 * colour should be sufficient to indicate that the current stops." — and, in the same
 * breath, over a parent node as well as a leaf. So a FALSE (`dead`) element draws no
 * break, wherever it sits: a leaf, a folded group pinned false, a NOT rung whose negand
 * is true, a group inside a NOT. What tells a reader "this stopped here" is the INK: the
 * dead box stroke and wash, the NOT bubble's fill, and — in `ladder-svg`, with current
 * shown — the wire that is no longer lit (`ladder-svg/test/open-contact.test.ts`
 * measures that).
 *
 * Meng, 2026-11-27, then, on the one break that had been kept for an ELIMINABLE rung in
 * an OR: "yeah, get rid of the open switch on the eliminable too." So nothing draws one,
 * and the `open-contact` glyph role is gone from `ScenePrim`.
 *
 * `breaks` below therefore does not look for one role: it returns every glyph whose role
 * is not one of the three the layout still emits (the power terminal, the NOT bubble and
 * the changeover pivot). The type no longer has an `open-contact` member to compare
 * against, so a test that named it would not compile, and a test that compared a string
 * would pass for a typo; "not one of the three" is the check that a reinstated emitter,
 * under any name, cannot slip past.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { layout, defaultViewSpec, estimateMetrics } from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  NodeId,
  Scene,
  ScenePrim,
  State,
  UBoolValue,
} from "../src/index.js";

const leaf = (id: NodeId, label: string): IRExpr => ({
  $type: "UBoolVar",
  id,
  label,
});
const and = (id: NodeId, args: IRExpr[]): IRExpr => ({
  $type: "And",
  id,
  args,
});
const or = (id: NodeId, args: IRExpr[]): IRExpr => ({ $type: "Or", id, args });
const not = (id: NodeId, negand: IRExpr): IRExpr => ({
  $type: "Not",
  id,
  negand,
});
const implies = (id: NodeId, scope: IRExpr, requirement: IRExpr): IRExpr => ({
  $type: "Implies",
  id,
  scope,
  requirement,
});

const sceneOf = (
  body: IRExpr,
  vals: Array<[NodeId, UBoolValue]>,
  extra: Record<string, unknown> = {},
): Scene =>
  layout(
    { id: 1, name: "r", params: [], body } satisfies FunDecl,
    defaultViewSpec({ valuation: new Map(vals), showCurrent: true, ...extra }),
    estimateMetrics,
  );

/** The glyph roles `layout` still emits. Anything else is a break, however it is named. */
const KNOWN_ROLES: readonly string[] = [
  "power-terminal",
  "inverter",
  "changeover",
];
const breaks = (prims: ScenePrim[]) =>
  prims.filter(
    (p): p is Extract<ScenePrim, { kind: "glyph" }> =>
      p.kind === "glyph" && !KNOWN_ROLES.includes(p.role),
  );
const glyphs = (prims: ScenePrim[]) => prims.filter((p) => p.kind === "glyph");
const box = (s: Scene, id: NodeId) =>
  s.prims.find(
    (p): p is Extract<ScenePrim, { kind: "box" }> =>
      p.kind === "box" && p.id === id,
  )!;

/* -------------------------------------------------- a dead LEAF draws no break */

test("a FALSE leaf draws no break — and is still drawn dead, so the colour has something to say", () => {
  const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
  const s = sceneOf(conj, [[3, "FalseV"]]);
  assert.equal(breaks(s.prims).length, 0);
  assert.equal(box(s, 3).state, "dead", "the ink is the whole cue now");
  assert.equal(box(s, 4).state, "inert", "an unknown leaf is still grey");
});

test("a FALSE leaf draws no break in a series, in an OR, or on its own", () => {
  const fixtures: Array<[string, IRExpr, Array<[NodeId, UBoolValue]>]> = [
    ["series", and(2, [leaf(3, "a"), leaf(4, "b")]), [[4, "FalseV"]]],
    [
      "OR with a true sibling",
      or(2, [leaf(3, "a"), leaf(4, "b")]),
      [
        [3, "FalseV"],
        [4, "TrueV"],
      ],
    ],
    ["alone", leaf(2, "a"), [[2, "FalseV"]]],
  ];
  for (const [name, body, vals] of fixtures)
    assert.equal(breaks(sceneOf(body, vals).prims).length, 0, name);
});

test("a PRESUMED-false leaf draws no break either — its box keeps §22's fine dash", () => {
  // `tentative` used to ride on the break glyph too (a dashed break). The box carries it
  // alone now.
  const disj = or(2, [leaf(3, "a"), leaf(4, "b")]);
  const s = sceneOf(disj, [[4, "FalseV"]], {
    provenance: new Map<NodeId, "default">([[4, "default"]]),
  });
  assert.equal(breaks(s.prims).length, 0);
  assert.equal(box(s, 4).state, "dead");
  assert.equal(box(s, 4).tentative, true);
});

/* ------------------------------------------------ a dead PARENT draws no break */

test("an OR whose operands are both false draws no break at all", () => {
  const disj = or(2, [leaf(3, "a"), leaf(4, "b")]);
  const s = sceneOf(disj, [
    [3, "FalseV"],
    [4, "FalseV"],
  ]);
  assert.equal(breaks(s.prims).length, 0);
  assert.equal(box(s, 3).state, "dead");
  assert.equal(box(s, 4).state, "dead");
});

test("an AND with one false operand draws no break at all", () => {
  const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
  assert.equal(breaks(sceneOf(conj, [[3, "FalseV"]]).prims).length, 0);
});

test("a group that went dead inside an OR draws no break, at the leaf or on the fan", () => {
  const disj = or(2, [and(5, [leaf(6, "x"), leaf(7, "y")]), leaf(4, "b")]);
  assert.equal(breaks(sceneOf(disj, [[6, "FalseV"]]).prims).length, 0);
  const both = or(2, [
    and(3, [leaf(4, "a"), leaf(5, "b")]),
    and(6, [leaf(7, "c"), leaf(8, "d")]),
  ]);
  assert.equal(
    breaks(
      sceneOf(both, [
        [4, "FalseV"],
        [7, "FalseV"],
      ]).prims,
    ).length,
    0,
  );
});

test("a folded group pinned FALSE draws no break at its placeholder", () => {
  const disj = or(2, [and(5, [leaf(6, "x"), leaf(7, "y")]), leaf(4, "b")]);
  const s = sceneOf(disj, [[5, "FalseV"]], { foldSet: new Set([5]) });
  assert.equal(breaks(s.prims).length, 0);
  assert.equal(
    box(s, 5).state,
    "dead",
    "the placeholder still wears the dead ink",
  );
});

/* ---------------------------------- …inside a NOT, and a NOT that is itself dead */

test("a false group inside a NOT draws no break", () => {
  assert.equal(
    breaks(
      sceneOf(not(2, or(3, [leaf(4, "a"), leaf(5, "b")])), [
        [4, "FalseV"],
        [5, "FalseV"],
      ]).prims,
    ).length,
    0,
    "NOT(OR(F, F))",
  );
  assert.equal(
    breaks(
      sceneOf(not(2, and(3, [leaf(4, "a"), leaf(5, "b")])), [[4, "FalseV"]])
        .prims,
    ).length,
    0,
    "NOT(AND(F, ?))",
  );
});

test("a NOT rung that is DEAD (negand true) draws no break on the OR fan — the parent-node site", () => {
  // The fan used to draw a firm break for any rung that reported `dead` and had not drawn
  // its own. Leaves and folded placeholders set `ownBreak` and groups report `inert`, so
  // they never reached it; a NOT rung does. This is the fixture that exercises the fan
  // site, not the leaf site.
  const disj = or(2, [not(5, leaf(6, "x")), leaf(4, "b")]);
  const s = sceneOf(disj, [[6, "TrueV"]]);
  assert.equal(breaks(s.prims).length, 0);
  const fan = s.prims.find((p) => p.kind === "curve" && p.state === "dead");
  assert.ok(fan, "the rung's fan curve is still drawn in the dead state");
});

test("a dead IMPLIES rung (scope true, requirement false) inside an OR draws no break — neither the leaf's nor the fan's", () => {
  // `measureImplies` reports `renderState` like a NOT does, so an IMPLIES rung that is
  // false reached the fan site with state `dead` and no `ownBreak`: before the change this
  // drew TWO breaks, one at the requirement leaf and one on the fan.
  const disj = or(2, [implies(5, leaf(6, "a"), leaf(7, "b")), leaf(4, "c")]);
  const s = sceneOf(disj, [
    [6, "TrueV"],
    [7, "FalseV"],
  ]);
  assert.equal(breaks(s.prims).length, 0);
  assert.equal(
    box(s, 7).state,
    "dead",
    "the requirement leaf is still drawn dead",
  );
  assert.ok(
    s.prims.some((p) => p.kind === "curve" && p.state === "dead"),
    "the IMPLIES rung's fan curve is dead, so this fixture does reach the fan site",
  );
});

test("a NOT over a group, itself a rung of an OR, draws no break whether the group is false or true", () => {
  const rung = (id: NodeId) =>
    or(2, [not(5, and(6, [leaf(id, "x"), leaf(8, "y")])), leaf(4, "b")]);
  assert.equal(
    breaks(sceneOf(rung(7), [[7, "FalseV"]]).prims).length,
    0,
    "group false, so the NOT conducts",
  );
  assert.equal(
    breaks(
      sceneOf(rung(7), [
        [7, "TrueV"],
        [8, "TrueV"],
      ]).prims,
    ).length,
    0,
    "group true, so the NOT is dead",
  );
});

/* ------------------------------------ …and in both orientations, not only LR */

test("dead elements draw no break in the TB orientation, including the one case that is turned (a series)", () => {
  // Both emission sites sit in code that is written in (main, cross) and projected by
  // `Axis`, so a change that reinstated a break for one orientation alone would pass every
  // LR assertion above. (In TB only a series is turned; an OR is still drawn LR, but its
  // `ctx.axis` says TB, which is what a TB-only mutation would key on.)
  const fixtures: Array<[string, IRExpr, Array<[NodeId, UBoolValue]>]> = [
    [
      "dead leaf in a series",
      and(2, [leaf(3, "a"), leaf(4, "b")]),
      [[4, "FalseV"]],
    ],
    [
      "OR of two false leaves",
      or(2, [leaf(3, "a"), leaf(4, "b")]),
      [
        [3, "FalseV"],
        [4, "FalseV"],
      ],
    ],
    [
      "dead NOT rung on the fan",
      or(2, [not(5, leaf(6, "x")), leaf(4, "b")]),
      [[6, "TrueV"]],
    ],
    [
      "dead IMPLIES rung on the fan",
      or(2, [implies(5, leaf(6, "a"), leaf(7, "b")), leaf(4, "c")]),
      [
        [6, "TrueV"],
        [7, "FalseV"],
      ],
    ],
  ];
  for (const orient of ["LR", "TB"] as const)
    for (const [name, body, vals] of fixtures) {
      const s = sceneOf(body, vals, { orient });
      assert.ok(
        s.prims.some((p) => p.kind === "box" && p.state === "dead") ||
          s.prims.some((p) => p.kind === "curve" && p.state === "dead"),
        `${orient} ${name}: the fixture really has a dead element`,
      );
      assert.equal(breaks(s.prims).length, 0, `${orient}: ${name}`);
    }
});

/* ----------------------- …and an ELIMINABLE rung draws none either (the second ruling) */

const ghostStates = (...ids: NodeId[]) =>
  new Map<NodeId, State>(ids.map((id) => [id, "eliminable"]));
/** The ghost fan: a curve drawn in the eliminable state. Positive control that a fixture
 *  does reach the OR's fan site, where the glyph used to be emitted. */
const ghostFans = (s: Scene) =>
  s.prims.filter((p) => p.kind === "curve" && p.state === "eliminable");
const tagsOf = (s: Scene) =>
  s.prims.filter((p) => p.kind === "text" && p.tag === "otiose");

test("an ELIMINABLE leaf in an OR draws no break — only the dashed box and fan and its tag", () => {
  const disj = or(2, [leaf(3, "a"), leaf(4, "b")]);
  const s = sceneOf(disj, [], { states: ghostStates(4) });
  assert.equal(breaks(s.prims).length, 0);
  assert.equal(box(s, 4).state, "eliminable", "the ghost box is still drawn");
  assert.equal(ghostFans(s).length, 2, "…and its fan: in-curve and out-curve");
  assert.equal(tagsOf(s).length, 1, "…and the tag that says what it is");
  assert.ok(
    glyphs(s.prims).length >= 2,
    "the scene's own glyphs (the power terminals) are still there",
  );
});

test("an ELIMINABLE folded group, NOT rung and IMPLIES rung draw no break on the fan", () => {
  const fixtures: Array<[string, IRExpr, NodeId, Record<string, unknown>]> = [
    [
      "folded group",
      or(2, [and(5, [leaf(6, "x"), leaf(7, "y")]), leaf(4, "b")]),
      5,
      { foldSet: new Set([5]) },
    ],
    ["NOT rung", or(2, [not(5, leaf(6, "x")), leaf(4, "b")]), 5, {}],
    [
      "IMPLIES rung",
      or(2, [implies(5, leaf(6, "a"), leaf(7, "b")), leaf(4, "c")]),
      5,
      {},
    ],
  ];
  for (const orient of ["LR", "TB"] as const)
    for (const [name, body, id, extra] of fixtures) {
      const s = sceneOf(body, [], {
        states: ghostStates(id),
        orient,
        ...extra,
      });
      assert.equal(
        ghostFans(s).length,
        2,
        `${orient} ${name}: the fan is a ghost`,
      );
      assert.equal(breaks(s.prims).length, 0, `${orient} ${name}`);
    }
});

test("an ELIMINABLE leaf draws no break in either orientation, in an OR or in a series", () => {
  // The fan site is written in (main, cross) and projected by `Axis`, and a TB-only
  // reinstatement would pass every LR assertion above.
  const disj = or(2, [leaf(3, "a"), leaf(4, "b")]);
  const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
  for (const orient of ["LR", "TB"] as const) {
    const s = sceneOf(disj, [], { states: ghostStates(4), orient });
    assert.equal(ghostFans(s).length, 2, `${orient} OR: the fan is a ghost`);
    assert.equal(breaks(s.prims).length, 0, `${orient} OR`);
    const t = sceneOf(conj, [], { states: ghostStates(4), orient });
    assert.equal(
      box(t, 4).state,
      "eliminable",
      `${orient} series: a ghost box`,
    );
    assert.equal(breaks(t.prims).length, 0, `${orient} series`);
  }
});

test("a dead rung beside an eliminable one: neither draws a break, each keeps its own ink", () => {
  const disj = or(2, [leaf(3, "a"), leaf(4, "b"), leaf(5, "c")]);
  const s = sceneOf(disj, [[3, "FalseV"]], { states: ghostStates(4) });
  assert.equal(breaks(s.prims).length, 0);
  assert.equal(box(s, 3).state, "dead");
  assert.equal(box(s, 4).state, "eliminable");
  assert.equal(box(s, 5).state, "inert");
});

test("the mutation guard bites: a hand-built scene with a stray glyph role is counted", () => {
  // `breaks` must see a glyph of ANY role outside the three, not only the old name — else
  // every test above would pass vacuously after a reinstatement under a new one.
  const stray = {
    kind: "glyph",
    at: { x: 1, y: 1 },
    role: "open-switch",
  } as unknown as ScenePrim;
  assert.equal(breaks([stray]).length, 1);
  assert.equal(
    breaks([{ kind: "glyph", at: { x: 1, y: 1 }, role: "inverter" }]).length,
    0,
  );
});
