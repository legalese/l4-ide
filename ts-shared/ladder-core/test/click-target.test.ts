/**
 * A box's label is part of the box for clicking purposes.
 *
 * The box rectangle carries `act: {t:"value"}` and its label `<text>` is a SIBLING, not a
 * child, so the controller's `closest("[data-value],[data-fold]")` (controller.ts) finds
 * nothing when the click lands on the words — the one place a reader aims. The label must
 * carry the box's own act. Folded placeholders are the same: the box cycles the group's
 * override, and so does its label (only the ▸ caret folds).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { layout, defaultViewSpec, estimateMetrics } from "../src/index.js";
import type { FunDecl, IRExpr, NodeId, ScenePrim } from "../src/index.js";

const leaf = (id: NodeId, label: string): IRExpr => ({
  $type: "UBoolVar",
  id,
  label,
});
const and = (id: NodeId, args: IRExpr[], label?: string): IRExpr => ({
  $type: "And",
  id,
  args,
  ...(label ? { label } : {}),
});
const scene = (body: IRExpr, foldSet: NodeId[] = []) =>
  layout(
    { id: 1, name: "r", params: [], body } satisfies FunDecl,
    defaultViewSpec({ foldSet: new Set(foldSet) }),
    estimateMetrics,
  );

type Text = Extract<ScenePrim, { kind: "text" }>;
const labelOf = (prims: ScenePrim[], id: NodeId) =>
  prims.find((p): p is Text => p.kind === "text" && p.id === id && !p.tag);
const boxOf = (prims: ScenePrim[], id: NodeId) =>
  prims.find((p) => p.kind === "box" && p.id === id);

test("a leaf's label carries the same value act as its box", () => {
  const s = scene(and(2, [leaf(3, "alpha"), leaf(4, "beta")]));
  for (const id of [3, 4]) {
    const box = boxOf(s.prims, id) as { act?: unknown };
    const text = labelOf(s.prims, id)!;
    assert.deepEqual(box.act, { t: "value", id });
    assert.deepEqual(text.act, { t: "value", id });
  }
});

test("a folded placeholder's label cycles the group override; only the caret folds", () => {
  const s = scene(and(2, [and(5, [leaf(6, "x"), leaf(7, "y")], "group")]), [5]);
  assert.deepEqual(labelOf(s.prims, 5)!.act, { t: "value", id: 5 });
  const caret = s.prims.find(
    (p): p is Text => p.kind === "text" && p.tag === "caret",
  )!;
  assert.deepEqual(caret.act, { t: "fold", id: 5 });
});
