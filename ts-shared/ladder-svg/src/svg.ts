/**
 * Scene IR -> SVG string (DESIGN §4). Canonical text is <text>/<tspan> so the same
 * emit feeds screen AND print (§4.4). `theme` maps state -> ink; no second layout.
 *
 * The import below is deliberately `import type`: the Scene IR is a *contract*, not
 * a library, so this backend carries no runtime dependency on the layout engine.
 */
import type { Scene, ScenePrim, State, Theme, Flow } from "@repo/ladder-core";

interface Palette {
  live: string;
  inert: string;
  dead: string;
  ghost: string;
  rail: string;
  ink: string;
  bg: string;
}

// DESIGN §6/§15.1 gives four leaf states four appearances, and the difference between
// `dead` and `inert` is the one the picture cannot afford to lose: a FALSE atom was
// tested and did not bite; an UNKNOWN one was never asked. §25.4 reads N/A off exactly
// that contrast ("a scope that is definitively ✗ shows a clean open contact; a scope
// that is ? is grey"), so drawing them in one grey — as this palette did — silently
// deleted the disambiguation the two-lamp form depends on.
//
// Determinacy is what the ink tracks: a settled fact is drawn FIRMLY (dark slate),
// an open question FAINTLY (light grey), a don't-care fainter still (ghost). Red is
// deliberately not used — it belongs to the breach lamp, and a false atom is very often
// the good outcome (an exception that did not apply).
const SCREEN: Palette = {
  live: "#1a7f37",
  inert: "#9aa0a6",
  dead: "#4a5560",
  ghost: "#b9bdc2",
  rail: "#3a3a3a",
  ink: "#222",
  bg: "#ffffff",
};
const INK: Palette = {
  ...SCREEN,
  live: "#222",
  inert: "#777",
  dead: "#333",
  ghost: "#999",
  rail: "#222",
  ink: "#111",
};

// current-flow style (DESIGN §20): closed (leader) thick+dark, streamer (local
// closure) medium, open thin+light.
//
// When the circuit is MADE end to end (`Scene.complete`, TODO G1), the closed run is
// dark GREEN rather than near-black: the difference between "current has reached here"
// and "this circuit conducts, source to sink" is the single most legible thing the
// picture can say, and colour says it without changing the weight the eye already reads
// as live. Width is deliberately unchanged.
//
// A made circuit that rests on assumptions gets a MUTED green instead (`Scene.provisional`):
// the reader is still told the circuit conducts, but not in the same voice as one made of
// answered facts. Suppressing the green entirely would hide a real result; giving it the
// full green would let an all-assumed path pass for a finding.
const CLOSED_INK = "#1b1b1b";
const CLOSED_MADE = "#0f5c2a"; // dark green — a completed source→sink path
const CLOSED_MADE_PROV = "#5f9e77"; // muted green — completed, but on presumptions
const flowStroke = (f: Flow, complete = false, provisional = false) =>
  f === "closed"
    ? complete
      ? provisional
        ? CLOSED_MADE_PROV
        : CLOSED_MADE
      : CLOSED_INK
    : f === "streamer"
      ? "#7c828a"
      : "#d6dadd";
const flowWidth = (f: Flow) =>
  f === "closed" ? 3.4 : f === "streamer" ? 2.3 : 1.1;

// Four states, four inks. `dead` used to fall through to `p.inert` here, which meant
// `p.dead` was never read at all — the palette entry existed and the renderer ignored it.
const strokeFor = (s: State, p: Palette) =>
  s === "live"
    ? p.live
    : s === "eliminable"
      ? p.ghost
      : s === "dead"
        ? p.dead
        : p.inert;

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
        return `<rect${a} x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="7" fill="#f6f7f8" stroke="${pal.ghost}" stroke-width="1.5" stroke-dasharray="5 4" opacity="0.9"/>`;
      const fill = p.role === "placeholder" ? "#eef1f6" : "#ffffff";
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
        return `<polyline ${cls} points="${d}" fill="none" stroke="${flowStroke(p.flow, complete, provisional)}" stroke-width="${flowWidth(p.flow)}"/>`;
      const dash = p.state === "eliminable" ? ' stroke-dasharray="5 4"' : "";
      const col = p.role === "rail" ? pal.rail : strokeFor(p.state, pal);
      const op = p.state === "eliminable" ? ' opacity="0.9"' : "";
      return `<polyline ${cls} points="${d}" fill="none" stroke="${col}" stroke-width="1.5"${dash}${op}/>`;
    }
    case "curve": {
      const d = `M ${p.from.x.toFixed(1)},${p.from.y.toFixed(1)} C ${p.c1.x.toFixed(1)},${p.c1.y.toFixed(1)} ${p.c2.x.toFixed(1)},${p.c2.y.toFixed(1)} ${p.to.x.toFixed(1)},${p.to.y.toFixed(1)}`;
      const cls = `class="lad-wire${p.act ? " lad-clickable" : ""}"${actAttr(p.act)}`;
      if (p.flow)
        return `<path ${cls} d="${d}" fill="none" stroke="${flowStroke(p.flow, complete, provisional)}" stroke-width="${flowWidth(p.flow)}"/>`;
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
      const on = p.role === "green" ? "#1a7f37" : "#c0392b";
      const soft = p.role === "green" ? "#5f9e77" : "#cd8b84";
      const off = "#c9ced3";
      const col = p.lit ? (prov ? soft : on) : off;
      const r = 9;
      return (
        `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="${r}" ` +
        `fill="${p.lit && !prov ? col : "#ffffff"}" stroke="${col}" stroke-width="${p.lit ? 2.6 : 1.4}"` +
        `${prov ? ' stroke-dasharray="1.5 3"' : ""}/>` +
        `<text x="${(p.at.x + r + 7).toFixed(1)}" y="${(p.at.y + 4).toFixed(1)}" ` +
        `font-family="Georgia, serif" font-size="12" fill="${p.lit ? col : off}"` +
        `${p.lit && !prov ? ' font-weight="700"' : ' font-style="italic"'}>${esc(p.label)}</text>`
      );
    }
    case "glyph":
      if (p.role === "changeover")
        // one pole, two throws — the requirement's verdict throws the blade
        return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="3" fill="#3a3a3a"/>`;
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
        return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="5" fill="#ffffff" stroke="#1b1b1b" stroke-width="1.5"/>`;
      return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="3.5" fill="${pal.rail}"/>`;
    case "frame": {
      const { x, y, w, h } = p.rect;
      return (
        `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="10" fill="none" stroke="#b3b7bb" stroke-width="1.2" stroke-dasharray="2 4"/>` +
        `<text x="${(x + 11).toFixed(1)}" y="${(y + 15).toFixed(1)}" font-family="Georgia, serif" font-size="11" fill="#8a9096" font-style="italic">${esc(p.label)}</text>`
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
        ? "#7a7f85"
        : p.tag === "seam"
          ? "#1b1b1b"
          : p.tag === "typically"
            ? "#9a7b34"
            : p.tag === "assumed"
              ? "#3f6d8f"
              : p.tag === "otiose"
                ? pal.ghost
                : p.state === "live"
                  ? pal.ink
                  : p.tag
                    ? "#555"
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

export function sceneToSvg(scene: Scene, theme: Theme = "screen"): string {
  const pal = theme === "ink" ? INK : SCREEN;
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
