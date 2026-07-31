/**
 * FLIP indexing and delta computation — the pure half of the transition between two Scenes.
 *
 * The algorithm is not new: it is `standalone/app.ts:92-100` + `:116-153`, which had a
 * near-verbatim twin in `standalone/playground.ts:136-146` + `:166-210`, whose own section
 * header admitted the copy in as many words: "FLIP (app.ts)".
 * E1-IDE-INTEGRATION.md:104 says the FLIP is **moved**, not copied, and EMBEDDABLE.md §3.2
 * constraint 3 says the job is to move it, not redesign it —
 * so this file is the one definition of `flipIndex` in the repo, and `controller.ts` is its
 * only consumer — both demos now get the FLIP through `LadderController` rather than owning
 * one, which is what "moved, not copied" buys.
 *
 * Splitting the arithmetic out of the DOM play loop is what makes it testable at all: the
 * indexing and the delta are exercised from hand-built `Scene` literals under `tsx --test`,
 * and only the `style.transition` / double-`requestAnimationFrame` half needs a browser.
 */
import type { Scene } from "@repo/ladder-core";

export interface Pos {
  x: number;
  y: number;
}

/** `box:<id>` for a rect, `label:<id>` for a text. Both come off `data-fnid`, which
 *  `svg.ts` emits on boxes (`:56`) and on identified texts (`:151`). */
export type FlipKey = string;

/** Where every keyed prim sits in this Scene. Text prims without an `id` are skipped —
 *  they are inert prose, they have no `data-fnid` in the emit, and there is therefore no
 *  element to animate. */
export function flipIndex(scene: Scene): Map<FlipKey, Pos> {
  const m = new Map<FlipKey, Pos>();
  for (const p of scene.prims) {
    if (p.kind === "box") m.set(`box:${p.id}`, { x: p.rect.x, y: p.rect.y });
    else if (p.kind === "text" && p.id != null)
      m.set(`label:${p.id}`, { x: p.at.x, y: p.at.y });
  }
  return m;
}

/** The FLIP key for a DOM element, from its tag name and its `data-fnid`. A `rect` is a
 *  box, anything else is a label — exactly `app.ts:121`'s rule, extracted so it can be
 *  tested without a DOM. */
export const flipKeyFor = (tagName: string, fnid: string): FlipKey =>
  `${tagName.toLowerCase() === "rect" ? "box" : "label"}:${fnid}`;

export type FlipMove =
  | { key: FlipKey; kind: "move"; dx: number; dy: number }
  | { key: FlipKey; kind: "appear" };

/**
 * The invert step: for each prim in the NEW scene, how far to displace it so that it starts
 * where it used to be. A key absent from `old` is new and fades in instead.
 *
 * Iteration is over `next`, so a prim that disappeared is simply gone — there is no exit
 * animation. That is the behaviour the demos have always had; the extraction preserves it
 * rather than quietly adding one.
 *
 * `scale` converts CONTENT units into whatever unit the caller will write into its
 * `transform`. **The controller passes 1, deliberately**: a CSS `transform: translate(Npx)`
 * on an element *inside* an `<svg>` is resolved in the SVG's own user coordinate system, not
 * in screen px, so a content-space delta is already in the right units and multiplying by
 * the zoom would over-shoot by exactly the zoom factor. (This is also why the old demos
 * animated correctly while `max-width:100%` was scaling the whole picture down.) The
 * parameter exists for a caller that animates something with a real CSS box — a Step-6b HTML
 * overlay positioned off the `box` prims' rects would need `scaleOf(vb, vp)` here.
 */
export function flipMoves(
  old: ReadonlyMap<FlipKey, Pos>,
  next: ReadonlyMap<FlipKey, Pos>,
  scale = 1,
): FlipMove[] {
  const out: FlipMove[] = [];
  for (const [key, n] of next) {
    const o = old.get(key);
    if (!o) {
      out.push({ key, kind: "appear" });
      continue;
    }
    if (o.x !== n.x || o.y !== n.y)
      out.push({
        key,
        kind: "move",
        dx: (o.x - n.x) * scale,
        dy: (o.y - n.y) * scale,
      });
  }
  return out;
}
