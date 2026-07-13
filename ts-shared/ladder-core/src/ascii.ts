/**
 * Scene IR -> monospace character grid (DESIGN §24, carrier I-b).
 *
 * The third renderer beside `svg.ts`, and the one that pays off the substrate-
 * independence the kernel was built for (§3.2, §4.4): swap in a MONOSPACE
 * TextMetrics and the very same BBE layout lands on a character grid. A fenced
 * code block renders verbatim wherever Markdown goes — github.com, PR comments,
 * commit messages, terminals, email, `git diff` — so a ladder becomes pasteable
 * and, more to the point, DIFFABLE.
 *
 * Two translations do the real work:
 *
 *  1. **Edges, not glyphs.** Cells accumulate a 4-bit mask of which directions
 *     carry a line (plus a weight), and the box-drawing character is resolved at
 *     the end. Junctions (├ ┤ ┬ ┴ ┼) therefore fall out for free — a wire meeting
 *     a box's left border yields `┤` without anyone asking for it.
 *
 *  2. **The Bézier fan becomes a bus.** Sampling §18's curves into characters
 *     would be mush. But every curve in an OR shares one endpoint (the group's
 *     port), so we recover the fan structure and draw the classic ladder-logic
 *     vertical bus instead — which is what the curve was always depicting.
 *
 * The lightning model (§20) survives the trip: heavy box-drawing (━┃╋) = closed,
 * light (─│┼) = streamer, dashed (┄┊) = open. Rebuttable presumptions (§22) and
 * eliminable rungs (§15) keep their dashes — fine for tentative, coarse for
 * otiose — mirroring the SVG. T/F/U, which is COLOUR in the SVG and so cannot
 * survive a code fence, moves into the box as a ✓/✗/? marker.
 */
import type { Scene, State, Flow, TextMetrics, Pt } from "./types.js";
import type { Geometry } from "./layout.js";

/* ------------------------------------------------------------------ metrics */

/**
 * A cell is CELL_W × CELL_H "pixels". The numbers themselves are arbitrary — what
 * matters is that EVERY length in the geometry below is a whole multiple of one
 * or the other, so no coordinate anywhere in the tree can land on a half-cell.
 *
 * That is the whole trick, and skipping it is what makes naive ASCII renderers
 * ugly: with off-grid constants, `round()` sends the same box to 3 rows in one
 * rung and 4 in the next, and headings drift onto the stack they label. Here
 * instead:
 *
 *   box height  = lineHeight + 2*PAD_Y  = 13 + 13 = 26 = 2 cells  → a 3-row box
 *   rung stride = box height + GAP_PARALLEL = 26 + 26 = 4 cells    → 3 rows + 1 blank
 *   box width   = len*CELL_W + 2*PAD_X  = (len + 4) cells          → │ label │
 *   OR band     = lineHeight + HEAD_PAD = 26 = 2 cells             → heading clears the stack
 *
 * Every subtree height therefore comes out a multiple of 2 cells, so BBE's
 * centering step — `(boundingExtent − childExtent) / 2` — also lands on a whole
 * cell. The grid is exact all the way down.
 */
export const CELL_W = 7;
export const CELL_H = 13;

export const monoMetrics = (cellW: number = CELL_W): TextMetrics => ({
  width: (t) => Math.max(1, t.length) * cellW,
  lineHeight: () => CELL_H,
});

/** Cell-exact geometry for the character grid. Pass to `layout()` alongside
 *  `monoMetrics()`; `sceneToAscii` assumes a scene laid out with these. */
export const ASCII_GEOMETRY: Geometry = {
  PAD_X: 2 * CELL_W, //   box w = (len + 4) cells
  PAD_Y: CELL_H / 2, //   box h = 2 cells
  // characters are far coarser than pixels, so the pixel geometry's generous
  // gaps become a very wide diagram. Tightened to keep a rule inside ~90 columns.
  GAP_SERIES: 4 * CELL_W,
  GAP_PARALLEL: 2 * CELL_H, // rung stride = 4 cells
  BUS_PAD: 3 * CELL_W,
  INERT_PAD: 2 * CELL_W,
  LEAD: 3 * CELL_W,
  MARGIN: CELL_W * CELL_H, // a multiple of BOTH, so x and y both start on-grid
  FONT: 14, // monoMetrics ignores size; kept for the interface
  CARET_PAD: CELL_W,
  TAG_RISE: CELL_H, //   the `typically` tag sits exactly one row above
  HEAD_PAD: CELL_H, //   OR band = 2 cells
  HEAD_DROP: 0,
  NOT_PAD_X: 2 * CELL_W,
  NOT_PAD_Y: CELL_H,
  NOT_LABEL: CELL_H,
  NOT_BUBBLE: 2 * CELL_W,
  NOT_R: CELL_W,
  CONNECTIVE_GAP: 0,
  STRADDLE_MIN_WIDTH: Infinity, // a code cell has no sub-line room: use 'on-wire'
  SEAM_W: 10 * CELL_W, //  ══MUST══▶
  FORK_W: 4 * CELL_W,
  COIL_R: CELL_W, //       a lamp is one cell: (✓) / (✗)
  COIL_SEP: 2 * CELL_H, // exactly two rows off the axis, so the fork is drawable
  COIL_LABEL: 12 * CELL_W,
};

/* -------------------------------------------------------------------- edges */

/** Line weight on one edge of a cell. Ordered — a heavier edge wins the junction. */
const NONE = 0;
const FINE = 1; // ┈ ┊ fine dash — a TENTATIVE presumption (§22) or an OPEN circuit (§20)
const COARSE = 2; // ╌ ╎ coarse dash — an ELIMINABLE/otiose rung (§15)
const LIGHT = 3; // ─ │ — the default, and a STREAMER (§20)
const HEAVY = 4; // ━ ┃ — CLOSED: the leader reached here (§20)
type Weight = 0 | 1 | 2 | 3 | 4;

const N = 0,
  S = 1,
  E = 2,
  W = 3;

interface Cell {
  edge: [Weight, Weight, Weight, Weight]; // N S E W
  text?: string; // text layer wins over lines
}

/** mask bit order NSEW -> character, for the LIGHT and HEAVY families. */
const LIGHT_CHARS: Record<number, string> = {
  0b0000: " ",
  0b0010: "─",
  0b0001: "─",
  0b0011: "─", // E, W, E+W
  0b1000: "│",
  0b0100: "│",
  0b1100: "│", // N, S, N+S
  0b0110: "┌",
  0b0101: "┐",
  0b1010: "└",
  0b1001: "┘",
  0b1110: "├",
  0b1101: "┤",
  0b0111: "┬",
  0b1011: "┴",
  0b1111: "┼",
};
const HEAVY_CHARS: Record<number, string> = {
  0b0000: " ",
  0b0010: "━",
  0b0001: "━",
  0b0011: "━",
  0b1000: "┃",
  0b0100: "┃",
  0b1100: "┃",
  0b0110: "┏",
  0b0101: "┓",
  0b1010: "┗",
  0b1001: "┛",
  0b1110: "┣",
  0b1101: "┫",
  0b0111: "┳",
  0b1011: "┻",
  0b1111: "╋",
};
/** Straight runs only — a dashed junction is not a thing, so junctions fall back
 *  to the solid family (correct: a junction is where the dash meets real wire). */
const DASH_H: Record<number, string> = { [FINE]: "┈", [COARSE]: "╌" };
const DASH_V: Record<number, string> = { [FINE]: "┊", [COARSE]: "╎" };

/** Pure-ASCII fallback for surfaces that mangle Unicode. */
const ASCII_FALLBACK: Record<string, string> = {
  "─": "-",
  "━": "=",
  "│": "|",
  "┃": "|",
  "┌": "+",
  "┐": "+",
  "└": "+",
  "┘": "+",
  "┏": "+",
  "┓": "+",
  "┗": "+",
  "┛": "+",
  "├": "+",
  "┤": "+",
  "┬": "+",
  "┴": "+",
  "┼": "+",
  "┣": "+",
  "┫": "+",
  "┳": "+",
  "┻": "+",
  "╋": "+",
  "┈": ".",
  "╌": ".",
  "┊": ":",
  "╎": ":",
  "●": "*",
  "✓": "T",
  "✗": "F",
  "▸": ">",
  "○": "o",
  "┿": "+",
};

class Grid {
  private cells = new Map<string, Cell>();
  private maxC = 0;
  private maxR = 0;

  private at(c: number, r: number): Cell {
    const k = `${c},${r}`;
    let cell = this.cells.get(k);
    if (!cell) {
      cell = { edge: [NONE, NONE, NONE, NONE] };
      this.cells.set(k, cell);
    }
    if (c > this.maxC) this.maxC = c;
    if (r > this.maxR) this.maxR = r;
    return cell;
  }

  /** Add a line edge; the heavier weight wins so a closed wire outranks an open one. */
  edge(c: number, r: number, dir: number, w: Weight): void {
    if (c < 0 || r < 0) return;
    const cell = this.at(c, r);
    if (w > cell.edge[dir]) cell.edge[dir] = w;
  }

  /** Horizontal run [c0..c1] on row r. Interior cells get both E and W. */
  hline(c0: number, c1: number, r: number, w: Weight): void {
    const [a, b] = c0 <= c1 ? [c0, c1] : [c1, c0];
    for (let c = a; c <= b; c++) {
      if (c > a) this.edge(c, r, W, w);
      if (c < b) this.edge(c, r, E, w);
    }
  }

  /** Vertical run [r0..r1] in column c. */
  vline(c: number, r0: number, r1: number, w: Weight): void {
    const [a, b] = r0 <= r1 ? [r0, r1] : [r1, r0];
    for (let r = a; r <= b; r++) {
      if (r > a) this.edge(c, r, N, w);
      if (r < b) this.edge(c, r, S, w);
    }
  }

  text(c: number, r: number, s: string): void {
    for (let i = 0; i < s.length; i++) {
      const cell = this.at(c + i, r);
      if (cell.text === undefined) cell.text = s[i];
    }
  }

  private glyph(cell: Cell): string {
    if (cell.text !== undefined) return cell.text;
    const [n, s, e, w] = cell.edge;
    const mask =
      (n ? 0b1000 : 0) | (s ? 0b0100 : 0) | (e ? 0b0010 : 0) | (w ? 0b0001 : 0);
    if (mask === 0) return " ";
    // a straight dashed run keeps its dash; anything else resolves solid
    if (mask === 0b0011 && e <= COARSE && e === w) return DASH_H[e];
    if (mask === 0b0010 || mask === 0b0001) {
      const d = e || w;
      if (d <= COARSE) return DASH_H[d];
    }
    if (mask === 0b1100 && n <= COARSE && n === s) return DASH_V[n];
    if (mask === 0b1000 || mask === 0b0100) {
      const d = n || s;
      if (d <= COARSE) return DASH_V[d];
    }
    const heavy = Math.max(n, s, e, w) === HEAVY;
    return (heavy ? HEAVY_CHARS : LIGHT_CHARS)[mask] ?? "+";
  }

  /** Render, cropped to the ink. */
  render(pure: boolean): string {
    const rows: string[] = [];
    for (let r = 0; r <= this.maxR; r++) {
      let line = "";
      for (let c = 0; c <= this.maxC; c++) {
        const cell = this.cells.get(`${c},${r}`);
        let g = cell ? this.glyph(cell) : " ";
        if (pure) g = ASCII_FALLBACK[g] ?? g;
        line += g;
      }
      rows.push(line.replace(/\s+$/, ""));
    }
    // crop blank rows top/bottom, and the common left indent
    while (rows.length && rows[0] === "") rows.shift();
    while (rows.length && rows[rows.length - 1] === "") rows.pop();
    const indent = Math.min(
      ...rows
        .filter((l) => l !== "")
        .map((l) => l.length - l.trimStart().length),
    );
    return rows.map((l) => l.slice(indent)).join("\n");
  }
}

/* ---------------------------------------------------------------- rendering */

export interface AsciiOpts {
  cellW?: number;
  cellH?: number;
  /** Pure ASCII (+ - | . :) instead of Unicode box-drawing. */
  pure?: boolean;
  /** Append ✓ / ✗ / ? to a box label. Default: only when some box has a value. */
  showValues?: boolean;
}

/** Line weight for a wire/bus segment, from its flow (§20) and state (§15/§22). */
function weightOf(flow: Flow | undefined, state: State): Weight {
  if (state === "eliminable") return COARSE;
  if (!flow) return LIGHT; // current flow off: everything is plain wire
  return flow === "closed" ? HEAVY : flow === "streamer" ? LIGHT : FINE;
}

/** Box border weight: a live (closed) contact reads BOLD; a presumption or an
 *  otiose rung reads DASHED (fine vs coarse, mirroring the SVG's 1.5/3 vs 5/4). */
function boxWeight(state: State, tentative: boolean | undefined): Weight {
  if (state === "eliminable") return COARSE;
  if (tentative) return FINE;
  return state === "live" ? HEAVY : LIGHT;
}

const MARK: Partial<Record<State, string>> = {
  live: "✓",
  dead: "✗",
  inert: "?",
};

const key = (p: Pt) => `${Math.round(p.x)},${Math.round(p.y)}`;

export function sceneToAscii(scene: Scene, opts: AsciiOpts = {}): string {
  const cw = opts.cellW ?? CELL_W;
  const ch = opts.cellH ?? CELL_H;
  const g = new Grid();
  const col = (x: number) => Math.round(x / cw);
  const row = (y: number) => Math.round(y / ch);

  const boxes = scene.prims.filter((p) => p.kind === "box");
  // T/F/U is colour in the SVG and cannot survive a code fence, so it moves into
  // the label. Only worth the noise once something actually has a value.
  const showValues =
    opts.showValues ??
    boxes.some((b) => b.state === "live" || b.state === "dead");

  /** Cell-space box, anchored at its rounded top-left and sized from its extent,
   *  so every box of a given label is the SAME size wherever it lands. */
  const rects = new Map<
    number,
    { c0: number; c1: number; r0: number; r1: number; state: State }
  >();

  /* boxes — drawn as EDGES, so a wire arriving at a border merges into ┤ / ├ */
  for (const p of boxes) {
    const w = boxWeight(p.state, p.tentative);
    const c0 = col(p.rect.x);
    const r0 = row(p.rect.y);
    const c1 = c0 + Math.round(p.rect.w / cw);
    const r1 = r0 + Math.round(p.rect.h / ch);
    rects.set(p.id, { c0, c1, r0, r1, state: p.state });
    g.hline(c0, c1, r0, w);
    g.hline(c0, c1, r1, w);
    g.vline(c0, r0, r1, w);
    g.vline(c1, r0, r1, w);
  }

  /* wires — every `wire` prim in this layout is horizontal (a series centres all
     its children on one axis, so consecutive ports share a y) */
  for (const p of scene.prims) {
    if (p.kind !== "wire") continue;
    const w = weightOf(p.flow, p.state);
    for (let i = 0; i < p.path.length - 1; i++) {
      const a = p.path[i],
        b = p.path[i + 1];
      if (row(a.y) === row(b.y)) g.hline(col(a.x), col(b.x), row(a.y), w);
      else if (col(a.x) === col(b.x)) g.vline(col(a.x), row(a.y), row(b.y), w);
      else {
        // shouldn't happen today; degrade to an L rather than lose the wire
        g.hline(col(a.x), col(b.x), row(a.y), w);
        g.vline(col(b.x), row(a.y), row(b.y), w);
      }
    }
  }

  /* the Bézier fan (§18) becomes a BUS. Every curve of one OR shares an endpoint
     — the group's port — so we can recover the fan and draw what it depicted. */
  const curves = scene.prims.filter((p) => p.kind === "curve");
  const byFrom = new Map<string, typeof curves>();
  const byTo = new Map<string, typeof curves>();
  for (const c of curves) {
    (
      byFrom.get(key(c.from)) ?? byFrom.set(key(c.from), []).get(key(c.from))!
    ).push(c);
    (byTo.get(key(c.to)) ?? byTo.set(key(c.to), []).get(key(c.to))!).push(c);
  }
  const drawn = new Set<(typeof curves)[number]>();

  const bus = (
    hub: Pt,
    fan: typeof curves,
    rungOf: (c: (typeof curves)[number]) => Pt,
  ) => {
    const hc = col(hub.x);
    const rungs = fan.map((c) => ({ c, p: rungOf(c) }));
    const rowsUsed = rungs.map((r) => row(r.p.y));
    // the vertical bus spans the rungs; each segment takes the heavier of its neighbours
    const lo = Math.min(...rowsUsed, row(hub.y));
    const hi = Math.max(...rowsUsed, row(hub.y));
    for (let r = lo; r < hi; r++) {
      // weight of a bus segment: the heaviest rung whose span covers it
      let w: Weight = FINE;
      for (const { c, p } of rungs) {
        const a = Math.min(row(hub.y), row(p.y)),
          b = Math.max(row(hub.y), row(p.y));
        if (r >= a && r < b) {
          const cand = weightOf(c.flow, c.state);
          if (cand > w) w = cand;
        }
      }
      g.edge(hc, r, S, w);
      g.edge(hc, r + 1, N, w);
    }
    for (const { c, p } of rungs) {
      g.hline(hc, col(p.x), row(p.y), weightOf(c.flow, c.state));
      drawn.add(c);
    }
  };

  for (const fan of byFrom.values())
    if (fan.length >= 2) bus(fan[0].from, fan, (c) => c.to);
  for (const fan of byTo.values())
    if (fan.length >= 2) bus(fan[0].to, fan, (c) => c.from);
  // a single-rung OR: the curve degenerates to a straight wire (one rung centres
  // on the group's own axis), so no bus is needed
  for (const c of curves) {
    if (drawn.has(c)) continue;
    g.hline(
      col(c.from.x),
      col(c.to.x),
      row(c.from.y),
      weightOf(c.flow, c.state),
    );
  }

  /* lamps (§25.4) — the verdict, in two characters */
  for (const p of scene.prims) {
    if (p.kind !== "coil") continue;
    const c = col(p.at.x),
      r = row(p.at.y);
    const mark = p.role === "green" ? "✓" : "✗";
    // lit lamps get a bold ring and their label; dark ones stay hollow and italic-ish
    g.text(c - 1, r, p.lit ? `(${mark})` : `( )`);
    g.text(c + 3, r, ` ${p.lit ? p.label.toUpperCase() : p.label}`);
  }

  /* glyphs */
  for (const p of scene.prims) {
    if (p.kind !== "glyph") continue;
    if (p.role === "power-terminal") g.text(col(p.at.x), row(p.at.y), "●");
    else if (p.role === "changeover") g.text(col(p.at.x), row(p.at.y), "┿");
    else if (p.role === "inverter") g.text(col(p.at.x), row(p.at.y), "○");
    // 'open-contact' is left to the dotted flow + the ✗ marker: a single cell
    // cannot draw -| |- , and the rung already reads as broken.
  }

  /* NOT scope frames (§21) */
  for (const p of scene.prims) {
    if (p.kind !== "frame") continue;
    const c0 = col(p.rect.x),
      c1 = col(p.rect.x + p.rect.w);
    const r0 = row(p.rect.y),
      r1 = row(p.rect.y + p.rect.h);
    g.hline(c0, c1, r0, COARSE);
    g.hline(c0, c1, r1, COARSE);
    g.vline(c0, r0, r1, COARSE);
    g.vline(c1, r0, r1, COARSE);
    g.text(c0 + 2, r0, ` ${p.label} `);
  }

  /* text last — it wins the cell */
  for (const p of scene.prims) {
    if (p.kind !== "text") continue;
    const box = p.id !== undefined ? rects.get(p.id) : undefined;

    // A BOX LABEL is placed against its box, not by rounding its own centre —
    // that keeps it inside the border and lets the value marker share the row.
    if (box && p.tag === undefined) {
      const inner = box.c1 - box.c0 - 1; // usable columns between the borders
      const mark = showValues ? MARK[box.state] : undefined;
      const need = p.text.length + (mark ? 2 : 0);
      const start = box.c0 + 1 + Math.max(0, Math.floor((inner - need) / 2));
      g.text(start, box.r0 + 1, p.text);
      if (mark) g.text(start + p.text.length + 1, box.r0 + 1, mark);
      continue;
    }

    const r = row(p.at.y);
    const c =
      p.anchor === "middle"
        ? Math.round(p.at.x / cw - p.text.length / 2)
        : col(p.at.x);
    g.text(Math.max(0, c), Math.max(0, r), p.text);
  }

  return g.render(opts.pure ?? false);
}
