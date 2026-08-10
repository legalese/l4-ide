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
 */
import type { Scene, ScenePrim, State, Theme, Flow } from "@repo/ladder-core";
import { paletteFor } from "./palette.js";
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
) =>
  f === "closed"
    ? complete
      ? provisional
        ? p.wireMadeProvisional
        : p.wireMade
      : p.wireClosed
    : f === "streamer"
      ? p.wireStreamer
      : p.wireOpen;
const flowWidth = (f: Flow) =>
  f === "closed" ? 3.4 : f === "streamer" ? 2.3 : 1.1;

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

const esc = (t: string) =>
  t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function prim(
  p: ScenePrim,
  pal: Palette,
  complete = false,
  provisional = false,
): string {
  switch (p.kind) {
    case "box": {
      const { x, y, w, h } = p.rect;
      const a = ` data-fnid="${p.id}"${actAttr(p.act)} class="lad-box${p.act ? " lad-clickable" : ""}"`;
      if (p.state === "eliminable")
        return `<rect${a} x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="7" fill="${pal.eliminableFill}" stroke="${pal.ghost}" stroke-width="1.5" stroke-dasharray="5 4" opacity="0.9"/>`;
      // A folded placeholder keeps its own bluish neutral ONLY while its value is unknown;
      // once it has one, the state wash wins — a fold must not hide the verdict it stands in
      // for, which is the whole point of being able to pin a folded group (§19).
      const fill =
        p.role === "placeholder" && p.state === "inert"
          ? pal.placeholderFill
          : fillFor(p.state, pal);
      // tentative (DESIGN §22): fine dots + normal ink — a presumption, not a ghost.
      // Finer dash (1.5 3) distinguishes it from eliminable's coarser dashes (5 4).
      const tent = p.tentative ? ' stroke-dasharray="1.5 3"' : "";
      return `<rect${a} x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="7" fill="${fill}" stroke="${strokeFor(p.state, pal)}" stroke-width="1.5"${tent}/>`;
    }
    case "wire": {
      const d = p.path
        .map((pt) => `${pt.x.toFixed(1)},${pt.y.toFixed(1)}`)
        .join(" ");
      const cls = `class="lad-wire${p.act ? " lad-clickable" : ""}"${actAttr(p.act)}`;
      if (p.flow)
        return `<polyline ${cls} points="${d}" fill="none" stroke="${flowStroke(p.flow, pal, complete, provisional)}" stroke-width="${flowWidth(p.flow)}"/>`;
      const dash = p.state === "eliminable" ? ' stroke-dasharray="5 4"' : "";
      const col = p.role === "rail" ? pal.rail : strokeFor(p.state, pal);
      const op = p.state === "eliminable" ? ' opacity="0.9"' : "";
      return `<polyline ${cls} points="${d}" fill="none" stroke="${col}" stroke-width="1.5"${dash}${op}/>`;
    }
    case "curve": {
      const d = `M ${p.from.x.toFixed(1)},${p.from.y.toFixed(1)} C ${p.c1.x.toFixed(1)},${p.c1.y.toFixed(1)} ${p.c2.x.toFixed(1)},${p.c2.y.toFixed(1)} ${p.to.x.toFixed(1)},${p.to.y.toFixed(1)}`;
      const cls = `class="lad-wire${p.act ? " lad-clickable" : ""}"${actAttr(p.act)}`;
      if (p.flow)
        return `<path ${cls} d="${d}" fill="none" stroke="${flowStroke(p.flow, pal, complete, provisional)}" stroke-width="${flowWidth(p.flow)}"/>`;
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
      if (p.role === "open-contact") {
        // A break on a FALSE element is a settled fact and is drawn firmly; a break on an
        // ELIMINABLE one is a ghost (DESIGN §15.1). Same glyph, different conviction.
        const col = p.state === "dead" ? pal.dead : pal.ghost;
        const wdt = p.state === "dead" ? 2 : 1.6;
        // …and a break whose falsity is only PRESUMED takes §22's fine dash, exactly as
        // its box does. Same ink (a presumption is not a ghost), softer line.
        const d = p.tentative ? ' stroke-dasharray="1.5 3"' : "";
        return (
          `<line x1="${(p.at.x - 7).toFixed(1)}" y1="${(p.at.y - 7).toFixed(1)}" x2="${(p.at.x - 7).toFixed(1)}" y2="${(p.at.y + 7).toFixed(1)}" stroke="${col}" stroke-width="${wdt}"${d}/>` +
          `<line x1="${(p.at.x + 7).toFixed(1)}" y1="${(p.at.y - 7).toFixed(1)}" x2="${(p.at.x + 7).toFixed(1)}" y2="${(p.at.y + 7).toFixed(1)}" stroke="${col}" stroke-width="${wdt}"${d}/>`
        );
      }
      if (p.role === "inverter")
        // the NOT bubble — sits on the output wire (DESIGN §21)
        return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="5" fill="${pal.inverterFill}" stroke="${pal.inverterStroke}" stroke-width="1.5"/>`;
      return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="3.5" fill="${pal.rail}"/>`;
    case "frame": {
      const { x, y, w, h } = p.rect;
      return (
        `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="10" fill="none" stroke="${pal.frameStroke}" stroke-width="1.2" stroke-dasharray="2 4"/>` +
        `<text x="${(x + 11).toFixed(1)}" y="${(y + 15).toFixed(1)}" font-family="Georgia, serif" font-size="11" fill="${pal.frameLabel}" font-style="italic">${esc(p.label)}</text>`
      );
    }
    case "text": {
      const size = p.size ?? 14;
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
 */
export function sceneToSvg(
  scene: Scene,
  theme: Theme | Palette = "screen",
): string {
  const pal = paletteFor(theme);
  const { w, h } = scene.size;
  const body = scene.prims
    .map((p) => prim(p, pal, !!scene.complete, !!scene.provisional))
    .join("\n");
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w.toFixed(0)}" height="${h.toFixed(0)}" viewBox="0 0 ${w.toFixed(0)} ${h.toFixed(0)}">`,
    `<rect width="${w.toFixed(0)}" height="${h.toFixed(0)}" fill="${pal.bg}"/>`,
    body,
    `</svg>`,
  ].join("\n");
}
