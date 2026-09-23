#!/usr/bin/env node
//
// bpmn-to-svg.mjs — render an emitted BPMN 2.0 file to a standalone SVG.
//
// WHY THIS EXISTS, AND WHY IT IS NOT bpmn-js.
//
// bpmn.io's `bpmn-js` is the reference renderer, and for a general BPMN file it
// is the right answer. It is the wrong answer *here*, for reasons measured on
// 2026-08-06 rather than assumed:
//
//   * It needs a browser. Every route to it — puppeteer, `bpmn-to-image`, the
//     Camunda Modeler binary — is the same route: launch Chromium, call
//     `saveSVG`. (Camunda Modeler 5.49.0 has no headless mode at all; its whole
//     CLI opens files in the GUI. `bpmn-to-image`'s SVG normalises to the same
//     digest as driving puppeteer directly.)
//   * Its output is geometry measured from real font metrics. A machine whose
//     `Arial, sans-serif` resolves to a metrically different face — DejaVu Sans
//     on a bare Debian or Alpine image — changes not just coordinates but the
//     NUMBER OF LINE BREAKS. Measured: 14 `<tspan>` under Arial, 15 under
//     Times, 19 under Courier. That defeats hash attestation.
//   * It bakes its palette in as inline `style` attributes, and emits a
//     `<!DOCTYPE>` referencing an external W3C DTD.
//
// And the objection that killed roll-your-own for the LTS pictures does not
// apply. EXPLAINER-REPORT-SPEC.md §8.2 rejected a DOT serializer because "DOT
// carries no coordinates, so writing a serializer would mean writing a layout
// engine". BPMN's diagram interchange carries every coordinate: `dc:Bounds` for
// each shape, `di:waypoint` for each edge. There is no layout to compute.
//
// WHAT THIS IS NOT. It is not a general BPMN renderer and must never become
// one. It renders the closed vocabulary that `L4.Bpmn.IR` emits, and it THROWS
// on anything else — see `unsupported()`. That throw is the whole anti-rot
// mechanism: when the exporter grows a node kind, this file fails loudly in the
// same CI run rather than silently omitting a shape from a legal diagram.
//
// OUTPUT CONVENTIONS, all three matching the committed ladder figures so these
// can be inlined into `explainer.html` on the same terms (§8.1, byte for byte,
// after a hash check):
//
//   1. ZERO `id` attributes. Arrowheads are drawn as explicit paths rather than
//      a `<defs><marker>`, so nothing needs `url(#…)`. An `<svg>` element is not
//      an identifier scope, so a shared id would collide across the nine
//      figures on that page — the hazard `render-explainer.mjs` documents for
//      the GraphViz pictures, which need `namespaceIds()` precisely because
//      they do define ids. These need no such rewriting, and so keep the
//      byte-for-byte claim the ladders make.
//   2. NO `<style>` ELEMENT AND NO CLASSES. A `<style>` block inside an inlined
//      SVG is not scoped to it; `.lbl { … }` would match anything in the host
//      document. Everything is a presentation attribute.
//   3. LIGHT ONLY, on an explicit white background, matching
//      `<rect fill="#ffffff"/>` in every committed ladder SVG. RULED 2026-08-06
//      (EXPLAINER-REPORT-SPEC.md §8.1): these figures may be printed, and a
//      diagram that inverts under a reader's theme is a different picture from
//      the one that was attested.
//
// Deterministic by construction: the only inputs are the file and argv. No
// `document`, no `getBBox`, no `Date`, no `Math.random`, no `process.env`, no
// locale. Glyph widths come from the table below, not from a font engine.
//
// Usage:  node etc/bpmn-to-svg.mjs <in.bpmn> <out.svg>

import { readFileSync, writeFileSync } from "node:fs";

const FS = 12; // px — the label size the emitted DI is laid out around
const LH = 14.4; // 1.2 line height
const PAD = 10; // viewport padding
const INK = "#22242a";
const PAPER = "#ffffff";

// Width an external label (below an event or gateway) wraps at.
//
// CALIBRATED, not derived. bpmn-js breaks "deadline passes, not performed"
// after the comma; with the metrics below that requires a limit in
// [90.05, 110.06), and 100 sits in the middle of that window. I did not
// establish WHY bpmn-js lands there — its own default external-label width is
// 90, which would break after "deadline", so some padding or tolerance is in
// play that I have not read. This is a measured fit against the reference
// renderer, and it is recorded as such so nobody later mistakes it for a
// mechanism. Re-measure if the reference changes.
const EXTERNAL_LABEL_W = 100;

// --------------------------------------------------------------- numbers
//
// Every coordinate goes through here. Two decimals is finer than any renderer
// resolves and coarse enough that no float noise reaches the file — the
// prototype emitted `height="503.20000000000005"`, which would have made the
// output look nondeterministic to a reader diffing two runs.
function n(v) {
  const r = Math.round(v * 100) / 100;
  return Object.is(r, -0) ? 0 : r;
}

// ------------------------------------------------------------ font metrics
//
// Adobe's Helvetica AFM advance widths, per 1000 em. Arial is metrically
// compatible with Helvetica by design, as are Liberation Sans and Arimo — which
// is why the font stack below names all four. Wrapping therefore agrees with a
// browser rendering the same stack, and is identical on every machine because
// it never asks one.
// prettier-ignore
const AW = {
  " ":278,"!":278,'"':355,"#":556,"$":556,"%":889,"&":667,"'":191,"(":333,")":333,
  "*":389,"+":584,",":278,"-":333,".":278,"/":278,
  "0":556,"1":556,"2":556,"3":556,"4":556,"5":556,"6":556,"7":556,"8":556,"9":556,
  ":":278,";":278,"<":584,"=":584,">":584,"?":556,"@":1015,
  "A":667,"B":667,"C":722,"D":722,"E":667,"F":611,"G":778,"H":722,"I":278,"J":500,
  "K":667,"L":556,"M":833,"N":722,"O":778,"P":667,"Q":778,"R":722,"S":667,"T":611,
  "U":722,"V":667,"W":944,"X":667,"Y":667,"Z":611,
  "[":278,"\\":278,"]":278,"^":469,"_":556,"`":333,
  "a":556,"b":556,"c":500,"d":556,"e":556,"f":278,"g":556,"h":556,"i":222,"j":222,
  "k":500,"l":222,"m":833,"n":556,"o":556,"p":556,"q":556,"r":333,"s":500,"t":278,
  "u":556,"v":500,"w":722,"x":500,"y":500,"z":500,
  "{":334,"|":260,"}":334,"~":584,
  "‘":222,"’":222,"“":333,"”":333,"–":556,"—":1000,
};
const DEFAULT_AW = 556; // an unlisted glyph is assumed lowercase-ish

// Single quotes around the multi-word family, deliberately: this string is
// emitted inside a double-quoted XML attribute, and double quotes here produce
// a malformed document. Caught by `xmllint` on the first run.
const FONT = "Arial, Helvetica, 'Liberation Sans', Arimo, sans-serif";

const textWidth = (s) =>
  ([...s].reduce((t, c) => t + (AW[c] ?? DEFAULT_AW), 0) * FS) / 1000;

function wrap(text, maxW) {
  const out = [];
  let line = "";
  for (const word of String(text).split(/\s+/).filter(Boolean)) {
    const t = line ? line + " " + word : word;
    if (line && textWidth(t) > maxW) {
      out.push(line);
      line = word;
    } else line = t;
  }
  if (line) out.push(line);
  return out.length ? out : [""];
}

const esc = (s) =>
  String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

// ------------------------------------------------------------------ parse
//
// A real open/close/self-close walk, not a regex sweep with a stack that only
// grows. The prototype never popped on a closing tag, so every event definition
// after the first would have attached to whichever node was still on top. It
// happened not to bite because a definition always immediately follows its
// parent — but "happens not to bite" is not a parser.
function parse(xml) {
  const els = new Map();
  const stack = [];
  const tagRe = /<(\/?)(?:bpmn2?|semantic):(\w+)\b([^>]*?)(\/?)>/g;
  let m;
  while ((m = tagRe.exec(xml))) {
    const [, closing, tag, attrsSrc, selfClose] = m;
    if (closing) {
      stack.pop();
      continue;
    }
    const a = Object.fromEntries(
      [...attrsSrc.matchAll(/([\w:.-]+)="([^"]*)"/g)].map((x) => [x[1], x[2]]),
    );
    if (/EventDefinition$/.test(tag) && stack.length) {
      const parent = els.get(stack[stack.length - 1]);
      if (parent) parent.defs.push(tag);
    }
    if (a.id && !els.has(a.id)) els.set(a.id, { tag, ...a, defs: [] });
    if (!selfClose) stack.push(a.id ?? null);
  }

  const shapes = [];
  for (const s of xml.matchAll(
    /<bpmndi:BPMNShape\b([^>]*)>\s*<(?:dc|omgdc):Bounds\b([^>]*)\/?>/g,
  )) {
    const at = (src, k) => src.match(new RegExp(`\\b${k}="([^"]*)"`))?.[1];
    const of = at(s[1], "bpmnElement");
    if (!of) continue;
    shapes.push({
      of,
      x: +at(s[2], "x"),
      y: +at(s[2], "y"),
      w: +at(s[2], "width"),
      h: +at(s[2], "height"),
    });
  }

  const edges = [];
  for (const e of xml.matchAll(
    /<bpmndi:BPMNEdge\b([^>]*)>([\s\S]*?)<\/bpmndi:BPMNEdge>/g,
  )) {
    const of = e[1].match(/\bbpmnElement="([^"]*)"/)?.[1];
    if (!of) continue;
    const pts = [
      ...e[2].matchAll(
        /<(?:di|omgdi):waypoint\b[^>]*x="([-\d.]+)"[^>]*y="([-\d.]+)"/g,
      ),
    ].map((p) => ({ x: +p[1], y: +p[2] }));
    if (pts.length >= 2) edges.push({ of, pts });
  }

  return { els, shapes, edges };
}

// ------------------------------------------------------------------ anti-rot
//
// THE most important function in this file. `L4.Bpmn.IR` emits a closed set of
// node kinds; this renderer covers exactly that set. When the set grows — and
// it has grown once already, when `BusinessRule` was added for the DMN wiring —
// the correct behaviour is to fail the build, not to omit a shape. A legal
// diagram that is silently missing an element is worse than no diagram: the
// reader cannot tell that anything is absent.
function unsupported(what, id) {
  throw new Error(
    `bpmn-to-svg: unsupported BPMN element <bpmn:${what}> (id=${id}).\n` +
      `This renderer deliberately covers only the closed vocabulary that\n` +
      `L4.Bpmn.IR emits. If the exporter has grown a new node kind, add it\n` +
      `here in the same change — do not widen the default case. See the\n` +
      `header of etc/bpmn-to-svg.mjs.`,
  );
}

// ------------------------------------------------------------------ glyphs
//
// BPMN's marker glyphs. Drawn to the notation rather than approximated: a
// reviewer who knows BPMN reads these as type information, so a rough zigzag
// where the spec draws an error bolt is a legibility defect, not a cosmetic one.

// Clock: rim, ticks at the quarters, and two hands reading ten past ten.
function clockIcon(cx, cy, r = 9) {
  const ticks = [0, 90, 180, 270]
    .map((deg) => {
      const a = (deg * Math.PI) / 180;
      const c = Math.cos(a),
        s = Math.sin(a);
      return (
        `M${n(cx + c * (r - 2))} ${n(cy + s * (r - 2))}` +
        `L${n(cx + c * r)} ${n(cy + s * r)}`
      );
    })
    .join("");
  return (
    `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r)}" fill="none" stroke="${INK}" stroke-width="1.2"/>` +
    `<path d="${ticks}" fill="none" stroke="${INK}" stroke-width="1"/>` +
    `<path d="M${n(cx)} ${n(cy)}L${n(cx)} ${n(cy - r + 3)}M${n(cx)} ${n(cy)}L${n(cx + r - 4)} ${n(cy - 2)}"` +
    ` fill="none" stroke="${INK}" stroke-width="1.2" stroke-linecap="round"/>`
  );
}

// Error: the BPMN lightning bolt, filled. A closed seven-point polygon.
function errorIcon(cx, cy) {
  const p = [
    [-6, 7],
    [-2.2, -3.2],
    [1.2, 1.4],
    [6, -7],
    [2.2, 3.2],
    [-1.2, -1.4],
  ]
    .map(([dx, dy], i) => `${i ? "L" : "M"}${n(cx + dx)} ${n(cy + dy)}`)
    .join("");
  return `<path d="${p}Z" fill="${INK}" stroke="${INK}" stroke-width="0.8" stroke-linejoin="round"/>`;
}

// Conditional: a small ruled page.
function condIcon(cx, cy) {
  const rules = [-4, -1, 2, 5]
    .map((d) => `M${n(cx - 4)} ${n(cy + d)}h8`)
    .join("");
  return (
    `<rect x="${n(cx - 6)}" y="${n(cy - 8)}" width="12" height="16" fill="none" stroke="${INK}" stroke-width="1.2"/>` +
    `<path d="${rules}" fill="none" stroke="${INK}" stroke-width="1"/>`
  );
}

// Business rule task: the table marker, top-left of the activity.
function tableMarker(x, y) {
  return (
    `<rect x="${n(x)}" y="${n(y)}" width="16" height="12" fill="${PAPER}" stroke="${INK}" stroke-width="1.2"/>` +
    `<path d="M${n(x)} ${n(y + 4)}h16M${n(x + 5)} ${n(y)}v12" fill="none" stroke="${INK}" stroke-width="1"/>`
  );
}

// ------------------------------------------------------------------ labels
function label(text, cx, cy, maxW) {
  const lines = wrap(text, maxW);
  const y0 = cy - ((lines.length - 1) * LH) / 2;
  const spans = lines
    .map(
      (l, i) => `<tspan x="${n(cx)}" dy="${i ? n(LH) : 0}">${esc(l)}</tspan>`,
    )
    .join("");
  return (
    `<text x="${n(cx)}" y="${n(y0)}" font-family="${FONT}" font-size="${FS}"` +
    ` fill="${INK}" text-anchor="middle" dominant-baseline="central">${spans}</text>`
  );
}

// How many lines an external label will occupy, so the viewport can make room
// for the deepest one rather than guessing a constant.
const labelDepth = (text, maxW) => (text ? wrap(text, maxW).length : 0);

// ------------------------------------------------------------------- nodes
function drawNode(el, b) {
  const { x, y, w, h } = b;
  const cx = x + w / 2,
    cy = y + h / 2,
    r = w / 2;
  const name = el.name ?? "";
  const below = () =>
    name ? label(name, cx, y + h + LH, EXTERNAL_LABEL_W) : "";
  const circle = (rr, sw) =>
    `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(rr)}" fill="${PAPER}" stroke="${INK}" stroke-width="${sw}"/>`;

  switch (el.tag) {
    case "startEvent":
      return circle(r, 1.5) + below();

    case "endEvent": {
      const icon = el.defs.includes("errorEventDefinition")
        ? errorIcon(cx, cy)
        : "";
      return circle(r, 3.5) + icon + below();
    }

    case "boundaryEvent": {
      const icon = el.defs.includes("timerEventDefinition")
        ? clockIcon(cx, cy)
        : condIcon(cx, cy);
      return circle(r, 1.5) + circle(r - 3, 1.5) + icon + below();
    }

    case "exclusiveGateway":
    case "parallelGateway": {
      const d =
        `M${n(cx)} ${n(y)}L${n(x + w)} ${n(cy)}` +
        `L${n(cx)} ${n(y + h)}L${n(x)} ${n(cy)}Z`;
      // The `+` is bold in the notation; the exclusive `X` is drawn only when
      // the DI asks for it via `isMarkerVisible`, and the emitted DI never does
      // (MEASURED 2026-08-06: zero occurrences corpus-wide). bpmn-js draws the
      // bare diamond in that case too, so this matches the reference.
      const mark =
        el.tag === "parallelGateway"
          ? `<path d="M${n(cx - 11)} ${n(cy)}h22M${n(cx)} ${n(cy - 11)}v22"` +
            ` fill="none" stroke="${INK}" stroke-width="2.5" stroke-linecap="butt"/>`
          : el.isMarkerVisible === "true"
            ? `<path d="M${n(cx - 8)} ${n(cy - 8)}l16 16M${n(cx + 8)} ${n(cy - 8)}l-16 16"` +
              ` fill="none" stroke="${INK}" stroke-width="2.5"/>`
            : "";
      return (
        `<path d="${d}" fill="${PAPER}" stroke="${INK}" stroke-width="1.5"/>` +
        mark +
        below()
      );
    }

    case "task":
    case "businessRuleTask": {
      const hasMarker = el.tag === "businessRuleTask";
      const marker = hasMarker ? tableMarker(x + 5, y + 5) : "";
      // A tall label centred in the box rides up under the type marker: with
      // four lines in an 80px activity the first line's glyphs reach y+13 and
      // the marker occupies y+5..y+17. bpmn-js has this collision too — its
      // table icon sits on the "t" of "transfer falls…" — but we own this
      // renderer, so clear it. Shift by exactly the overlap, so short labels
      // (already below the marker) do not move at all and stay centred.
      const MARKER_BOTTOM = y + 17 + 3;
      let ty = cy;
      if (hasMarker) {
        const depth = wrap(name, w - 14).length;
        const top = cy - ((depth - 1) * LH) / 2 - FS / 2;
        ty += Math.max(0, MARKER_BOTTOM - top);
      }
      return (
        `<rect x="${n(x)}" y="${n(y)}" width="${n(w)}" height="${n(h)}" rx="10"` +
        ` fill="${PAPER}" stroke="${INK}" stroke-width="1.5"/>` +
        marker +
        label(name, cx, ty, w - 14)
      );
    }

    default:
      return unsupported(el.tag, el.id);
  }
}

// ------------------------------------------------------------------- edges
//
// Rounded corners at each interior waypoint, with the radius CLAMPED to half
// the shorter adjacent segment. Unclamped, a corner whose neighbours are closer
// than 2R overshoots and doubles back — which is what produced the visible comb
// of hooks where six flows converge on `Fulfilled` in the handover diagram.
function drawEdge(e) {
  const R = 5;
  const p = e.pts;
  let d = `M${n(p[0].x)} ${n(p[0].y)}`;
  for (let i = 1; i < p.length - 1; i++) {
    const a = p[i - 1],
      c = p[i],
      b = p[i + 1];
    const lIn = Math.hypot(c.x - a.x, c.y - a.y);
    const lOut = Math.hypot(b.x - c.x, b.y - c.y);
    const r = Math.min(R, lIn / 2, lOut / 2);
    if (r < 0.5) {
      d += `L${n(c.x)} ${n(c.y)}`;
      continue;
    }
    const din = unit(c, a),
      dout = unit(b, c);
    d +=
      `L${n(c.x - din.x * r)} ${n(c.y - din.y * r)}` +
      `Q${n(c.x)} ${n(c.y)} ${n(c.x + dout.x * r)} ${n(c.y + dout.y * r)}`;
  }
  const last = p[p.length - 1],
    prev = p[p.length - 2];
  const dir = unit(last, prev);
  // Stop the stroke at the base of the arrowhead so the two do not overlap and
  // darken; then draw the head explicitly. No <defs>, no marker, no id.
  const HEAD = 9,
    HALF = 3.6;
  const bx = last.x - dir.x * HEAD,
    by = last.y - dir.y * HEAD;
  const nx = -dir.y,
    ny = dir.x;
  const head =
    `M${n(last.x)} ${n(last.y)}` +
    `L${n(bx + nx * HALF)} ${n(by + ny * HALF)}` +
    `L${n(bx - nx * HALF)} ${n(by - ny * HALF)}Z`;
  return (
    `<path d="${d}L${n(bx)} ${n(by)}" fill="none" stroke="${INK}" stroke-width="2"` +
    ` stroke-linecap="round" stroke-linejoin="round"/>` +
    `<path d="${head}" fill="${INK}"/>`
  );
}

function unit(to, from) {
  const dx = to.x - from.x,
    dy = to.y - from.y;
  const l = Math.hypot(dx, dy) || 1;
  return { x: dx / l, y: dy / l };
}

// -------------------------------------------------------------------- drive
export function render(xml) {
  const { els, shapes, edges } = parse(xml);
  if (!shapes.length)
    throw new Error("bpmn-to-svg: no BPMNShape found — is this file DI-less?");

  const CONTAINERS = new Set(["participant", "lane"]);

  // Viewport. Shapes and waypoints give the ink extent; external labels hang
  // below their shape, so measure them rather than padding by a constant.
  let x0 = Infinity,
    y0 = Infinity,
    x1 = -Infinity,
    y1 = -Infinity;
  for (const s of shapes) {
    x0 = Math.min(x0, s.x);
    y0 = Math.min(y0, s.y);
    x1 = Math.max(x1, s.x + s.w);
    y1 = Math.max(y1, s.y + s.h);
    const el = els.get(s.of);
    if (el && !CONTAINERS.has(el.tag) && el.name) {
      const isInternal = el.tag === "task" || el.tag === "businessRuleTask";
      if (!isInternal)
        y1 = Math.max(
          y1,
          s.y + s.h + LH * (labelDepth(el.name, EXTERNAL_LABEL_W) + 0.5),
        );
    }
  }
  for (const e of edges)
    for (const p of e.pts) {
      x0 = Math.min(x0, p.x);
      y0 = Math.min(y0, p.y);
      x1 = Math.max(x1, p.x);
      y1 = Math.max(y1, p.y);
    }
  const vx = n(x0 - PAD),
    vy = n(y0 - PAD);
  const vw = n(x1 - x0 + 2 * PAD),
    vh = n(y1 - y0 + 2 * PAD);

  const body = [];
  // Containers first, so nodes and flows draw over their bands.
  for (const s of shapes) {
    const el = els.get(s.of);
    if (!el || !CONTAINERS.has(el.tag)) continue;
    const ly = s.y + s.h / 2;
    body.push(
      `<rect x="${n(s.x)}" y="${n(s.y)}" width="${n(s.w)}" height="${n(s.h)}" fill="none" stroke="${INK}" stroke-width="1.5"/>`,
      `<path d="M${n(s.x + 30)} ${n(s.y)}v${n(s.h)}" fill="none" stroke="${INK}" stroke-width="1.5"/>`,
      `<text x="${n(s.x + 15)}" y="${n(ly)}" font-family="${FONT}" font-size="${FS}"` +
        ` fill="${INK}" text-anchor="middle" dominant-baseline="central"` +
        ` transform="rotate(-90 ${n(s.x + 15)} ${n(ly)})">${esc(el.name ?? "")}</text>`,
    );
  }
  for (const e of edges) body.push(drawEdge(e));
  for (const s of shapes) {
    const el = els.get(s.of);
    if (!el || CONTAINERS.has(el.tag)) continue;
    body.push(drawNode(el, s));
  }

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${vw}" height="${vh}" viewBox="${vx} ${vy} ${vw} ${vh}">\n` +
    `<rect x="${vx}" y="${vy}" width="${vw}" height="${vh}" fill="${PAPER}"/>\n` +
    body.join("\n") +
    `\n</svg>\n`
  );
}

const isMain =
  process.argv[1] && import.meta.url.endsWith(process.argv[1].split("/").pop());
if (isMain) {
  const [, , inPath, outPath] = process.argv;
  if (!inPath || !outPath) {
    console.error("usage: node etc/bpmn-to-svg.mjs <in.bpmn> <out.svg>");
    process.exit(2);
  }
  const svg = render(readFileSync(inPath, "utf8"));
  writeFileSync(outPath, svg);
  console.error(`bpmn-to-svg: wrote ${outPath} (${svg.length} bytes)`);
}
