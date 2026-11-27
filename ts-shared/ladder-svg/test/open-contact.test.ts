/**
 * What the SVG says for a FALSE element now that no open-contact break is drawn.
 *
 * Meng, 2026-11-27: "i wonder if we can do without the open-contact break; the colour
 * should be sufficient to indicate that the current stops." — and over a parent node as
 * well as a leaf. The scene-level half of this (no `open-contact` glyph for any dead
 * state) is `ladder-core/test/open-contact.test.ts`; this file is the rendered half, and
 * it also pins the two cues that are meant to carry the meaning instead:
 *
 *   - the INK: a dead box is not the grey of an unanswered one, in every built-in palette;
 *   - the WIDTH: with current shown, a lit wire is drawn at `flowWidth("closed")` = 3.4 and
 *     a wire past a dead contact at `flowWidth("open")` = 1.1, so the cue survives a
 *     reader who cannot tell the two colours apart. With current OFF there is no `flow`,
 *     every wire is 1.5, and the colour is the only cue — the last test says so.
 *
 * The break glyph is the only thing `svg.ts` draws with `<line>`, which is why the absence
 * of that tag is a faithful "no glyph in the output".
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  sceneToSvg,
  SCREEN_PALETTE,
  INK_PALETTE,
  DARK_PALETTE,
} from "../src/index.js";
import { layout, defaultViewSpec, estimateMetrics } from "@repo/ladder-core";
import type { FunDecl, IRExpr, NodeId, UBoolValue } from "@repo/ladder-core";

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

const render = (
  body: IRExpr,
  vals: Array<[NodeId, UBoolValue]>,
  opts: { showCurrent?: boolean; theme?: "screen" | "ink" } = {},
): string =>
  sceneToSvg(
    layout(
      { id: 1, name: "r", params: [], body } satisfies FunDecl,
      defaultViewSpec({
        valuation: new Map(vals),
        showCurrent: opts.showCurrent ?? true,
      }),
      estimateMetrics,
    ),
    opts.theme ?? "screen",
  );

/** The `stroke-width` of every wire and curve in the output, in drawing order. */
const wireWidths = (svg: string): number[] =>
  [
    ...svg.matchAll(
      /<(?:polyline|path) class="lad-wire[^>]*stroke-width="([\d.]+)"/g,
    ),
  ].map((m) => Number(m[1]));

const FALSE_FIXTURES: Array<[string, IRExpr, Array<[NodeId, UBoolValue]>]> = [
  [
    "a false leaf in a series",
    and(2, [leaf(3, "a"), leaf(4, "b")]),
    [[3, "FalseV"]],
  ],
  [
    "an OR of two false leaves",
    or(2, [leaf(3, "a"), leaf(4, "b")]),
    [
      [3, "FalseV"],
      [4, "FalseV"],
    ],
  ],
  [
    "an AND with one false operand under a NOT",
    not(2, and(3, [leaf(4, "a"), leaf(5, "b")])),
    [[4, "FalseV"]],
  ],
  [
    "an OR of two false leaves under a NOT",
    not(2, or(3, [leaf(4, "a"), leaf(5, "b")])),
    [
      [4, "FalseV"],
      [5, "FalseV"],
    ],
  ],
  [
    "a NOT rung gone dead (its negand is true) inside an OR",
    or(2, [not(5, leaf(6, "x")), leaf(4, "b")]),
    [[6, "TrueV"]],
  ],
];

test("a FALSE element renders no open-contact break, leaf or parent, in either theme", () => {
  for (const [name, body, vals] of FALSE_FIXTURES)
    for (const theme of ["screen", "ink"] as const) {
      const svg = render(body, vals, { theme });
      assert.ok(svg.includes("<svg"), `${name}: the render happened`);
      assert.ok(
        svg.includes("lad-box"),
        `${name}: and it drew boxes, so the absence below means something`,
      );
      assert.doesNotMatch(svg, /<line\b/, `${name} (${theme}) drew a break`);
    }
});

test("the ELIMINABLE ghost break is still drawn: the renderer is not what changed", () => {
  const body = or(2, [leaf(3, "a"), leaf(4, "b")]);
  const svg = sceneToSvg(
    layout(
      { id: 1, name: "r", params: [], body } satisfies FunDecl,
      defaultViewSpec({ states: new Map([[4, "eliminable" as const]]) }),
      estimateMetrics,
    ),
  );
  assert.equal(svg.match(/<line\b/g)?.length, 2, "two bars");
  assert.match(svg, /stroke="#b9bdc2" stroke-width="1.6"/);
});

test("a lit wire and a dark wire still differ in stroke width, not in colour alone", () => {
  // a is TRUE and b is FALSE: power reaches `a`, crosses it, and stops at `b`.
  const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
  const widths = wireWidths(
    render(conj, [
      [3, "TrueV"],
      [4, "FalseV"],
    ]),
  );
  assert.ok(widths.includes(3.4), `a lit wire is 3.4 wide; got ${widths}`);
  assert.ok(
    widths.includes(1.1),
    `a wire past the dead contact is 1.1; got ${widths}`,
  );
  // …and an all-TRUE circuit has no dark wire left to draw
  const lit = wireWidths(
    render(conj, [
      [3, "TrueV"],
      [4, "TrueV"],
    ]),
  );
  assert.ok(
    !lit.includes(1.1),
    `a closed circuit has no thin wire; got ${lit}`,
  );
  assert.ok(lit.includes(3.4));
});

test("the dead ink is not the unknown ink, in every built-in palette — the colour has to carry it alone", () => {
  for (const [name, pal] of [
    ["screen", SCREEN_PALETTE],
    ["ink", INK_PALETTE],
    ["dark", DARK_PALETTE],
  ] as const) {
    assert.notEqual(
      pal.dead,
      pal.inert,
      `${name}: dead must differ from inert`,
    );
    assert.notEqual(
      pal.deadFill,
      pal.boxFill,
      `${name}: a dead box's wash must differ from an empty box's`,
    );
  }
});

test("with current OFF there is no width cue: every wire is 1.5, so only ink distinguishes", () => {
  const conj = and(2, [leaf(3, "a"), leaf(4, "b")]);
  const widths = wireWidths(
    render(
      conj,
      [
        [3, "TrueV"],
        [4, "FalseV"],
      ],
      { showCurrent: false },
    ),
  );
  assert.ok(widths.length > 0);
  assert.deepEqual([...new Set(widths)], [1.5]);
});
