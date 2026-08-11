/** ascii.ts (DESIGN §24) — the character-grid renderer.
 *
 * The load-bearing property is GRID EXACTNESS: with ASCII_GEOMETRY every length
 * in the layout is a whole multiple of a cell, so no coordinate can land on a
 * half-cell and `round()` cannot drift. If that breaks, identical boxes come out
 * different heights in different rungs — so it is asserted directly.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  layout,
  sceneToAscii,
  monoMetrics,
  ASCII_GEOMETRY,
  defaultViewSpec,
  CELL_H,
  CELL_W,
} from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  Inert,
  NodeId,
  UBoolValue,
  Provenance,
  ViewSpec,
} from "../src/index.js";

let c = 0;
const nid = () => ++c;
const leaf = (label: string): Leaf => ({
  $type: "UBoolVar",
  id: nid(),
  label,
  atomId: label,
});
const inert = (text: string): Inert => ({
  $type: "InertE",
  id: nid(),
  text,
  context: "InertOr",
});

const a = leaf("alpha");
const b = leaf("beta");
const g = leaf("gamma");
// an OR of three, in series with a leaf: exercises stacking, the bus, and centering
const fn: FunDecl = {
  id: nid(),
  name: "r",
  params: [],
  body: {
    $type: "And",
    id: nid(),
    args: [
      leaf("head"),
      { $type: "Or", id: nid(), args: [inert("any of:"), a, b, g] },
    ],
  } as IRExpr,
};

const tm = monoMetrics();
const spec = (extra: Partial<ViewSpec> = {}) =>
  defaultViewSpec({ connectiveStyle: "on-wire", ...extra });
const draw = (extra: Partial<ViewSpec> = {}) =>
  sceneToAscii(layout(fn, spec(extra), tm, ASCII_GEOMETRY));

test("ASCII_GEOMETRY is grid-exact: every length is a whole cell", () => {
  const k = ASCII_GEOMETRY;
  // horizontal lengths must be whole columns…
  for (const key of [
    "PAD_X",
    "GAP_SERIES",
    "BUS_PAD",
    "INERT_PAD",
    "LEAD",
    "MARGIN",
    "CARET_PAD",
    "NOT_PAD_X",
    "NOT_BUBBLE",
    "NOT_R",
  ] as const)
    assert.equal(k[key] % CELL_W, 0, `${key} is not a whole column`);
  // …and vertical lengths whole rows
  for (const key of [
    "GAP_PARALLEL",
    "MARGIN",
    "TAG_RISE",
    "HEAD_PAD",
    "NOT_PAD_Y",
    "NOT_LABEL",
  ] as const)
    assert.equal(k[key] % CELL_H, 0, `${key} is not a whole row`);
  // the two identities the whole renderer rests on
  const boxH = tm.lineHeight(k.FONT) + 2 * k.PAD_Y;
  assert.equal(boxH, 2 * CELL_H, "a box must be exactly 2 cells (3 rows) tall");
  assert.equal(
    (boxH + k.GAP_PARALLEL) % (2 * CELL_H),
    0,
    "the rung stride must keep subtree heights even, so BBE centering stays on-grid",
  );
});

test("every box renders the same size wherever it lands", () => {
  const lines = draw().split("\n");
  // alpha/beta/gamma are equal-length labels on three different rungs; each must
  // produce an identical 3-row box. Count the border rows around each label.
  const boxRow = (label: string) => lines.findIndex((l) => l.includes(label));
  for (const label of ["alpha", "beta", "gamma"]) {
    const r = boxRow(label);
    assert.ok(r > 0, `${label} not drawn`);
    const col = lines[r].indexOf(label);
    // a border directly above and below the label, at the same column span
    assert.match(
      lines[r - 1].slice(col - 2),
      /^─*┌|^┌/,
      `${label} lacks a top border`,
    );
    assert.match(
      lines[r + 1].slice(col - 2),
      /^─*└|^└/,
      `${label} lacks a bottom border`,
    );
  }
});

test("the OR fan becomes a bus with tee junctions, not sampled curves", () => {
  const out = draw();
  // a vertical bus with a top corner, a middle tee and a bottom corner
  assert.ok(out.includes("┌"), "no bus top corner");
  assert.ok(out.includes("└"), "no bus bottom corner");
  assert.ok(/[├┤]/.test(out), "no tee junction where a rung meets the bus");
  assert.ok(!/[\\\/]/.test(out), "curves must not be sampled as slashes");
});

test("current flow survives: closed is heavy, open is dashed", () => {
  const vals = new Map<NodeId, UBoolValue>([
    [a.id, "TrueV"],
    [b.id, "FalseV"],
    [g.id, "FalseV"],
  ]);
  const out = draw({ valuation: vals, showCurrent: true });
  assert.ok(/[━┃┏┓┗┛┣┫╋]/.test(out), "no heavy stroke for the closed path");
  assert.ok(/[┈┊]/.test(out), "no dashed stroke for the open branches");
  assert.ok(out.includes("alpha ✓"), "a live atom should carry its ✓");
  assert.ok(out.includes("beta ✗"), "a dead atom should carry its ✗");
});

test("a TYPICALLY presumption renders tentative and caps the current", () => {
  const vals = new Map<NodeId, UBoolValue>([[a.id, "TrueV"]]);
  const prov = new Map<NodeId, Provenance>([[a.id, "default"]]);
  const out = draw({ valuation: vals, provenance: prov, showCurrent: true });
  const lines = out.split("\n");
  assert.ok(out.includes("typically"), "the presumption is not tagged");
  // The box is FINE-dashed (┈), not the COARSE dash (╌) of an eliminable rung.
  // It shows on the top/bottom edges: a 3-row box's sides are junctions (┤ ├)
  // wherever the wire lands, and a junction always resolves solid.
  const r = lines.findIndex((l) => l.includes("alpha"));
  assert.ok(/┈/.test(lines[r - 1]), "a presumed box should be finely dashed");
  assert.ok(
    !/╌/.test(lines[r - 1]),
    "fine dash, not the eliminable coarse dash",
  );
  // …and a presumed contact only closes the circuit provisionally: the current it
  // carries is capped at streamer (light), never the heavy leader (DESIGN §22).
  assert.ok(
    !/[━┃┏┓┗┛┣┫╋]/.test(lines[r]),
    "a presumption must not draw heavy current",
  );
});

test("pure mode emits no Unicode box-drawing", () => {
  const out = sceneToAscii(layout(fn, spec(), tm, ASCII_GEOMETRY), {
    pure: true,
  });
  assert.ok(!/[─│┌┐└┘├┤┬┴┼━┃┈┊╌╎●]/.test(out), "Unicode leaked into pure mode");
  assert.ok(out.includes("+") && out.includes("-") && out.includes("|"));
});
