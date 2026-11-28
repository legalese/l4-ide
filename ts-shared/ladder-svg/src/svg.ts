/**
 * Scene IR -> SVG string (DESIGN §4). Canonical text is <text>/<tspan> so the same
 * emit feeds screen AND print (§4.4). The palette maps state -> ink; no second layout.
 *
 * The `@repo/ladder-core` import below is deliberately `import type`: the Scene IR is a
 * *contract*, not a library, so this backend carries no runtime dependency on the layout
 * engine. (`controller.ts` is the one module in the package that does — see index.ts.)
 *
 * Seam S8: this file contains NO colour literals. Every colour it can emit is a named field
 * of `Palette` (`palette.ts`), and `test/palette.test.ts` scans this source to keep that
 * true.
 *
 * S8 itself was byte-identical to its pre-S8 output. This file is NO LONGER byte-identical
 * to S8's, and deliberately: DESIGN §26.1's fix gives the `dead` state its own ink and wash,
 * where before it fell through to `inert` and a tested-and-false element drew exactly like a
 * never-asked one. Default screen and print output both move. What did NOT change is the
 * shape of the contract — `sceneToSvg(scene)`, `(scene, "screen")` and `(scene,
 * SCREEN_PALETTE)` are still the same string, character for character.
 *
 * A second deliberate move, ruled 2026-11-28 (DESIGN §6): on every palette but `INK_PALETTE`
 * a box's outline carries its value by weight (see `BoxState`), so the default screen and
 * dark output moved again. The ink look did not: it is byte-identical to what it was.
 */
import type { Scene, ScenePrim, State, Theme, Flow } from "@repo/ladder-core";
import {
  paletteFor,
  panelShade,
  panelBackdrop,
  INK_PALETTE,
} from "./palette.js";
import type { Palette } from "./palette.js";

// current-flow style (DESIGN §20): closed (leader) thick+dark, streamer (local
// closure) medium, open thin+light.
//
// When the circuit is MADE end to end (`Scene.complete`), a closed run takes `wireMade`
// instead of `wireClosed`, and `wireMadeProvisional` when the making rests on assumptions.
// Width is deliberately unchanged — see those two palette fields for why colour carries it.
const flowStroke = (
  f: Flow,
  p: Palette,
  complete = false,
  provisional = false,
  panels = false,
) =>
  f === "closed"
    ? complete
      ? provisional
        ? p.wireMadeProvisional
        : p.wireMade
      : p.wireClosed
    : f === "streamer"
      ? p.wireStreamer
      : panels
        ? p.wireOpenPanel
        : p.wireOpen;
const flowWidth = (f: Flow) =>
  f === "closed" ? 3.4 : f === "streamer" ? 2.3 : 1.1;

/** A box's thin border: every box in the `"outline"` look, and an unknown box in `"weight"`. */
const BOX_STROKE = 1.5;
/** The fine dot a tentative box (§22) is drawn with: dash and gap, at BOX_STROKE wide. */
const TENT_DASH: readonly [number, number] = [1.5, 3];
/** Corner radius of a box. */
const BOX_RX = 7;
/** The border of a TRUE box in the `"weight"` look: as thick as a live current wire, read off the wire. */
const THICK_STROKE = flowWidth("closed");

/**
 * What a box's OUTLINE says about its value. Ruled on 2026-11-28 (DESIGN §6): the light and
 * dark looks draw `"weight"`, and the ink look keeps the outline it had.
 *
 *  - `"weight"`   a TRUE box has a border as thick as a lit wire, an UNKNOWN box has the thin
 *                 border it has always had, a FALSE box has none. The pale washes stay, so a
 *                 FALSE box is still painted (never `fill="none"`) and still a click target.
 *  - `"outline"`  every box has a 1.5 border in its state's ink, over the state's wash: the
 *                 look before 2026-11-28.
 *
 * The default is `"outline"` when the palette is `INK_PALETTE` (so the theme name `"ink"`
 * too) and `"weight"` for every other palette. The test is the palette's identity, so a
 * caller's own `Palette`, even one spread from `INK_PALETTE`, gets `"weight"`; a caller who
 * wants the old look on any palette passes `{ boxState: "outline" }`.
 *
 * The dashed ELIMINABLE ghost box and call panels are drawn as before in both looks, and a
 * presumed value (§22) keeps its dotted outline, except that a presumed-TRUE box is now thick
 * as well as dotted (item 2). Choices made by Claude on 2026-11-27 and
 * 2026-11-28, pending the owner's review, none part of the ruling:
 *  1. The thick border is drawn INSIDE the rect (outer edge = the rect's edge), so ports,
 *     layout and `scene.size` are those of the outline look. A centred 3.4 would spill 1.7
 *     into the wires that meet the box.
 *  2. A TENTATIVE (§22) box keeps its fine dots: a presumed-FALSE box would otherwise lose
 *     a cue that it is a presumption (the tag is the other), so it keeps the dotted 1.5 border it had; a
 *     presumed-TRUE box is thick AND dotted, the dots scaled with the stroke.
 *  3. The border keeps its state ink (live green, unknown grey) so weight and hue agree.
 *  4. A folded placeholder follows the same rule by its value; while unknown it keeps its
 *     bluish `placeholderFill`, which says "this is a fold", not a state.
 */
export type BoxState = "weight" | "outline";

/** Options on the emit. Every field defaults as its own comment says. */
export interface RenderOpts {
  /** What the box outline says; see `BoxState`. */
  readonly boxState?: BoxState;
}

// Four states, four inks. `dead` used to fall through to `p.inert` here, which meant
// `p.dead` was never read at all — the palette entry existed and the renderer ignored it,
// so a tested-and-false element emitted byte-identical SVG to a never-asked one.
const strokeFor = (s: State, p: Palette) =>
  s === "live"
    ? p.live
    : s === "eliminable"
      ? p.ghost
      : s === "dead"
        ? p.dead
        : p.inert;

// …and four interiors. `inert` is the plain box fill (an empty box for an open question)
// and `eliminable` keeps its own; only `live` and `dead` need a wash of their own.
const fillFor = (s: State, p: Palette) =>
  s === "live"
    ? p.liveFill
    : s === "dead"
      ? p.deadFill
      : s === "eliminable"
        ? p.eliminableFill
        : p.boxFill;

/** Compile-time exhaustiveness: a `never` argument means every case was handled; what it
 *  draws, if a hand-built scene gets past the types, is nothing. */
const exhaustive = (_unhandled: never): string => "";

const esc = (t: string) =>
  t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function prim(
  p: ScenePrim,
  pal: Palette,
  complete = false,
  provisional = false,
  panelDepth = 0,
  boxState: BoxState = "outline",
): string {
  switch (p.kind) {
    case "panel":
      // A call drawn expanded in place: a filled rounded panel, shaded by layer, darkest
      // outside. Its name is a separate `panel` text prim, which carries the fold act.
      return `<rect class="lad-panel" data-panel="${p.id}" x="${p.at.x.toFixed(1)}" y="${p.at.y.toFixed(1)}" width="${p.w.toFixed(1)}" height="${p.h.toFixed(1)}" rx="12" fill="${panelShade(pal, p.depth, panelDepth)}" stroke="${pal.panelEdge}" stroke-width="1"><title>${esc(p.label)}</title></rect>`;
    case "box": {
      const { x, y, w, h } = p.rect;
      const a = ` data-fnid="${p.id}"${actAttr(p.act)} class="lad-box${p.act ? " lad-clickable" : ""}"`;
      if (p.state === "eliminable")
        return `<rect${a} x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="${BOX_RX}" fill="${pal.eliminableFill}" stroke="${pal.ghost}" stroke-width="${BOX_STROKE}" stroke-dasharray="5 4" opacity="0.9"/>`;
      // A folded placeholder keeps its own bluish neutral ONLY while its value is unknown;
      // once it has one, the state wash wins — a fold must not hide the verdict it stands in
      // for, which is the whole point of being able to pin a folded group (§19).
      const fill =
        p.role === "placeholder" && p.state === "inert"
          ? pal.placeholderFill
          : fillFor(p.state, pal);
      if (boxState === "weight" && p.state !== "inert") {
        // A tentative box keeps its fine dots in the weight look, scaled with its stroke.
        const dash = (sw: number) =>
          p.tentative
            ? ` stroke-dasharray="${TENT_DASH.map((v) => +((v * sw) / BOX_STROKE).toFixed(1)).join(" ")}"`
            : "";
        const rect = (
          r: { x: number; y: number; w: number; h: number },
          rx: number,
          rest: string,
        ) =>
          `<rect${a} x="${r.x.toFixed(1)}" y="${r.y.toFixed(1)}" width="${r.w.toFixed(1)}" height="${r.h.toFixed(1)}" rx="${rx}" fill="${fill}"${rest}/>`;
        if (p.state === "live") {
          // TRUE: a border as thick as a lit wire, INSET so the outer edge is the rect's own
          const i = THICK_STROKE / 2;
          return rect(
            { x: x + i, y: y + i, w: w - THICK_STROKE, h: h - THICK_STROKE },
            Math.max(0, BOX_RX - i),
            ` stroke="${pal.live}" stroke-width="${THICK_STROKE}"${dash(THICK_STROKE)}`,
          );
        }
        // FALSE: no border — unless it is a presumption, which keeps its fine dots
        return rect(
          p.rect,
          BOX_RX,
          p.tentative
            ? ` stroke="${pal.dead}" stroke-width="${BOX_STROKE}"${dash(BOX_STROKE)}`
            : "",
        );
      }
      // UNKNOWN in the weight look, and every state in the outline look: a thin border in the
      // state's ink. tentative (DESIGN §22): fine dots + normal ink — a presumption, not a
      // ghost. Finer dash (1.5 3) distinguishes it from eliminable's coarser dashes (5 4).
      const tent = p.tentative
        ? ` stroke-dasharray="${TENT_DASH.join(" ")}"`
        : "";
      return `<rect${a} x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="${BOX_RX}" fill="${fill}" stroke="${strokeFor(p.state, pal)}" stroke-width="${BOX_STROKE}"${tent}/>`;
    }
    case "wire": {
      const d = p.path
        .map((pt) => `${pt.x.toFixed(1)},${pt.y.toFixed(1)}`)
        .join(" ");
      const cls = `class="lad-wire${p.act ? " lad-clickable" : ""}"${actAttr(p.act)}`;
      if (p.flow)
        return `<polyline ${cls} points="${d}" fill="none" stroke="${flowStroke(p.flow, pal, complete, provisional, panelDepth > 0)}" stroke-width="${flowWidth(p.flow)}"/>`;
      const dash = p.state === "eliminable" ? ' stroke-dasharray="5 4"' : "";
      const col = p.role === "rail" ? pal.rail : strokeFor(p.state, pal);
      const op = p.state === "eliminable" ? ' opacity="0.9"' : "";
      return `<polyline ${cls} points="${d}" fill="none" stroke="${col}" stroke-width="1.5"${dash}${op}/>`;
    }
    case "curve": {
      const d = `M ${p.from.x.toFixed(1)},${p.from.y.toFixed(1)} C ${p.c1.x.toFixed(1)},${p.c1.y.toFixed(1)} ${p.c2.x.toFixed(1)},${p.c2.y.toFixed(1)} ${p.to.x.toFixed(1)},${p.to.y.toFixed(1)}`;
      const cls = `class="lad-wire${p.act ? " lad-clickable" : ""}"${actAttr(p.act)}`;
      if (p.flow)
        return `<path ${cls} d="${d}" fill="none" stroke="${flowStroke(p.flow, pal, complete, provisional, panelDepth > 0)}" stroke-width="${flowWidth(p.flow)}"/>`;
      const dash = p.state === "eliminable" ? ' stroke-dasharray="5 4"' : "";
      const op = p.state === "eliminable" ? ' opacity="0.9"' : "";
      return `<path ${cls} d="${d}" fill="none" stroke="${strokeFor(p.state, pal)}" stroke-width="1.5"${dash}${op}/>`;
    }
    case "coil": {
      // §25.4 — the right-hand half of a rung, which we have never drawn until now.
      // LIT is the whole point: count the lit lamps and you have the verdict. Neither
      // lit ⇒ N/A (the scope did not conduct) or undetermined.
      //
      // A lamp lit under `Scene.provisional` is drawn HOLLOW, in a muted ink, with the
      // label still italic. An `Implies` body is never `complete` — it has two sinks, not
      // one (§25.4) — so the muted-green wire treatment above can never fire on a rule,
      // and a rule is precisely the diagram where a soft verdict matters most: a grounding
      // knob can walk a reader from "undetermined" to a lit IN BREACH lamp with no new
      // facts, and the lamp must not report that in the same voice as a finding.
      const prov = provisional && p.lit;
      const on = p.role === "green" ? pal.coilGreen : pal.coilRed;
      const soft = p.role === "green" ? pal.coilGreenSoft : pal.coilRedSoft;
      const off = pal.coilOff;
      const col = p.lit ? (prov ? soft : on) : off;
      const r = 9;
      return (
        `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="${r}" ` +
        `fill="${p.lit && !prov ? col : pal.coilHollow}" stroke="${col}" stroke-width="${p.lit ? 2.6 : 1.4}"` +
        `${prov ? ' stroke-dasharray="1.5 3"' : ""}/>` +
        `<text x="${(p.at.x + r + 7).toFixed(1)}" y="${(p.at.y + 4).toFixed(1)}" ` +
        `font-family="Georgia, serif" font-size="12" fill="${p.lit ? col : off}"` +
        `${p.lit && !prov ? ' font-weight="700"' : ' font-style="italic"'}>${esc(p.label)}</text>`
      );
    }
    case "glyph":
      if (p.role === "changeover")
        // one pole, two throws — the requirement's verdict throws the blade
        return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="3" fill="${pal.glyphDot}"/>`;
      if (p.role === "inverter")
        // the NOT bubble — sits on the output wire (DESIGN §21), filled with the NOT's
        // OUTPUT value (Meng, 2026-10-05): green when the negand is false, red when it is
        // true, plain while unknown. Its own two fields, not `live`/`dead`, which are TEXT
        // inks and are neither green-and-red in dark nor distinguishable in ink.
        return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="5" fill="${p.value === "TrueV" ? pal.inverterTrue : p.value === "FalseV" ? pal.inverterFalse : pal.inverterFill}" stroke="${pal.inverterStroke}" stroke-width="1.5"/>`;
      if (p.role === "power-terminal")
        return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="3.5" fill="${pal.rail}"/>`;
      // A role added to `ScenePrim` without a branch here fails `tsc` at this line, and a
      // hand-built scene carrying an unknown role draws nothing, as the ASCII carrier does.
      // It used to fall through to the power terminal's dot.
      return exhaustive(p.role);
    case "frame": {
      const { x, y, w, h } = p.rect;
      return (
        `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="10" fill="none" stroke="${pal.frameStroke}" stroke-width="1.2" stroke-dasharray="2 4"/>` +
        `<text x="${(x + 11).toFixed(1)}" y="${(y + 15).toFixed(1)}" font-family="Georgia, serif" font-size="11" fill="${pal.frameLabel}" font-style="italic">${esc(p.label)}</text>`
      );
    }
    case "text": {
      const size = p.size ?? 14;
      if (p.tag === "panel")
        // a panel's name: small, sans, set on the panel's top band
        return `<text data-fnid="${p.id ?? ""}"${actAttr(p.act)}${p.act ? ' class="lad-clickable lad-panel-name"' : ' class="lad-panel-name"'} x="${p.at.x.toFixed(1)}" y="${p.at.y.toFixed(1)}" font-family="IBM Plex Sans, system-ui, sans-serif" font-size="${size}" font-weight="600" fill="${pal.panelLabel}">${esc(p.text)}</text>`;
      const isCaret = p.tag === "caret";
      const inert =
        !isCaret &&
        (p.tag === "otiose" ||
          p.tag === "heading" ||
          p.tag === "note" ||
          p.tag === "connective" ||
          p.tag === "typically" ||
          p.tag === "assumed");
      // 'seam' is deliberately NOT inert: the MUST is the load-bearing connective
      const dy = inert ? 0 : 5; // vertical-center body/caret text
      const italic = inert ? ' font-style="italic"' : "";
      const weight =
        p.tag === "title" || p.tag === "seam" ? ' font-weight="700"' : "";
      // 'typically' (DESIGN §22) reads muted-amber to mark a rebuttable presumption.
      // 'assumed' reads slate-blue, and the two colours are the point: amber is what the
      // SOURCE presumed, blue is what the READER chose to assume. Confusing a drafter's
      // presumption with a viewer's setting is exactly the audit failure to avoid.
      const fill = isCaret
        ? pal.caret
        : p.tag === "seam"
          ? pal.seam
          : p.tag === "typically"
            ? pal.typically
            : p.tag === "assumed"
              ? pal.assumed
              : p.tag === "otiose"
                ? pal.ghost
                : p.state === "live"
                  ? pal.ink
                  : p.tag
                    ? pal.tagInk
                    : pal.ink;
      const a = `${p.id != null ? ` data-fnid="${p.id}"` : ""}${actAttr(p.act)}${p.act ? ' class="lad-clickable"' : ""}`;
      return `<text${a} x="${p.at.x.toFixed(1)}" y="${(p.at.y + dy).toFixed(1)}" font-family="Georgia, serif" font-size="${size}" text-anchor="${p.anchor}" fill="${fill}"${italic}${weight}>${esc(p.text)}</text>`;
    }
  }
}

/** Renders a ClickAct as a data-attr the host wires (data-value / data-fold). */
function actAttr(a?: { t: "value" | "fold"; id: number }): string {
  return a ? ` data-${a.t}="${a.id}"` : "";
}

/**
 * The emit. `theme` takes a built-in name (`"screen"` / `"ink"`) or a caller's own
 * `Palette` — seam S8. `sceneToSvg(scene)` and `sceneToSvg(scene, "screen")` and
 * `sceneToSvg(scene, SCREEN_PALETTE)` are the same string, character for character.
 * `opts.boxState` overrides the box outline the palette would draw (`BoxState`).
 */
export function sceneToSvg(
  scene: Scene,
  theme: Theme | Palette = "screen",
  opts: RenderOpts = {},
): string {
  const pal = paletteFor(theme);
  const boxState =
    opts.boxState ?? (pal === INK_PALETTE ? "outline" : "weight");
  const { w, h } = scene.size;
  const levels = scene.panelDepth ?? 0;
  // Panels go behind everything, in emit order — and the layout emits an outer panel before
  // anything inside it, so the inner panels land on top of the outer ones.
  const ordered = levels
    ? [
        ...scene.prims.filter((p) => p.kind === "panel"),
        ...scene.prims.filter((p) => p.kind !== "panel"),
      ]
    : scene.prims;
  const body = ordered
    .map((p) =>
      prim(p, pal, !!scene.complete, !!scene.provisional, levels, boxState),
    )
    .join("\n");
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w.toFixed(0)}" height="${h.toFixed(0)}" viewBox="0 0 ${w.toFixed(0)} ${h.toFixed(0)}">`,
    // a diagram with panels sits one step below the outermost panel
    `<rect width="${w.toFixed(0)}" height="${h.toFixed(0)}" fill="${levels ? panelBackdrop(pal, levels) : pal.bg}"/>`,
    body,
    `</svg>`,
  ].join("\n");
}
