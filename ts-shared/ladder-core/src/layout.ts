/**
 * The BBE layout kernel (DESIGN §5): IRExpr × TextMetrics × ViewSpec -> Scene IR.
 *
 * "Align, then stack." AND = series (horizontal, children centered vertically);
 * OR = parallel (vertical, children centered horizontally). Centering is intrinsic
 * to the re-margining — `pos = (boundingExtent - childExtent) / 2` — so no general
 * graph engine ever fights us (the headline fix; DESIGN §0, §5.3).
 *
 * Inert (grammatical scaffolding) renders UNBOXED (DESIGN §17): a leading inert in
 * an OR becomes a HEADING above the stack; an inert in a series RIDES THE WIRE (and
 * a leading one lands to the left of the stack for free). P0 is LR-only.
 */
import type {
  IRExpr,
  FunDecl,
  ViewSpec,
  TextMetrics,
  Scene,
  ScenePrim,
  Pt,
  State,
  NodeId,
  And,
  Or,
  ConnectiveStyle,
  UBoolValue,
  Flow,
  Implies,
} from "./types.js";
import type { Verdict } from "@repo/boolean-analysis";

/**
 * The kernel's geometry, injected (DESIGN §3.2). TextMetrics was always
 * injectable, but these constants were not — so "substrate-independent" only
 * half held: a substrate whose cells are not pixels (a MONOSPACE GRID; §24) needs
 * the paddings and gaps to land on whole cells too, or identical boxes come out
 * different sizes in different rungs. Units are notional pixels for the SVG and
 * notional cells×scale for ASCII; the kernel never cares which.
 */
export interface Geometry {
  PAD_X: number;
  PAD_Y: number;
  GAP_SERIES: number; // horizontal gap between AND siblings
  GAP_PARALLEL: number; // vertical gap between OR siblings
  BUS_PAD: number; // gap between an OR's bus and its child boxes
  INERT_PAD: number; // horizontal breathing room around inline inert text
  LEAD: number; // power-lead length at the far left/right
  MARGIN: number;
  FONT: number;
  CARET_PAD: number; // extra room beside a fold placeholder's ▸
  TAG_RISE: number; // how far above a box its otiose/typically tag sits
  HEAD_PAD: number; // an OR heading's band = lineHeight + HEAD_PAD
  HEAD_DROP: number; // …and the heading's baseline nudge inside that band
  NOT_PAD_X: number;
  NOT_PAD_Y: number;
  NOT_LABEL: number;
  NOT_BUBBLE: number; // output room for the inverter bubble
  NOT_R: number; // bubble radius
  CONNECTIVE_GAP: number; // clearance between wire and connective text
  STRADDLE_MIN_WIDTH: number; // only wrap connectives wider than this
  // §25 IMPLIES — the seam, the changeover fork, and the two sinks
  SEAM_W: number; //   room for the MUST / ⇒ connective between the two panels
  FORK_W: number; //   the changeover fan from the requirement to the lamps
  COIL_R: number; //   lamp radius
  COIL_SEP: number; // how far each lamp sits off the axis (green up, red down)
  COIL_LABEL: number; // room to the right of a lamp for "complies" / "in breach"
}

/** The pixel geometry the SVG target has always used. */
export const PIXEL_GEOMETRY: Geometry = {
  PAD_X: 14,
  PAD_Y: 10,
  GAP_SERIES: 44,
  GAP_PARALLEL: 26,
  BUS_PAD: 26,
  INERT_PAD: 12,
  LEAD: 40,
  MARGIN: 70,
  FONT: 14,
  CARET_PAD: 8,
  TAG_RISE: 9,
  HEAD_PAD: 12,
  HEAD_DROP: 2,
  NOT_PAD_X: 16,
  NOT_PAD_Y: 12,
  NOT_LABEL: 16,
  NOT_BUBBLE: 20,
  NOT_R: 5,
  CONNECTIVE_GAP: 3,
  STRADDLE_MIN_WIDTH: 160,
  SEAM_W: 66,
  FORK_W: 44,
  COIL_R: 9,
  COIL_SEP: 40,
  COIL_LABEL: 74,
};

interface Measured {
  w: number;
  h: number;
  state: State; // own state (leaf state, or 'inert' for a group/placeholder/inert)
  emit(ox: number, oy: number, out: ScenePrim[]): { inPort: Pt; outPort: Pt };
}

interface Ctx {
  vs: ViewSpec;
  tm: TextMetrics;
  k: Geometry;
  values: Map<NodeId, UBoolValue>; // evaluated T/F/U per node id
  em: Map<NodeId, Energ> | null; // energization per node id, when showCurrent
}

const isOperative = (e: IRExpr): boolean => e.$type !== "InertE";

const valueToState = (v: UBoolValue): State =>
  v === "TrueV" ? "live" : v === "FalseV" ? "dead" : "inert";

/** Render state for a node: manual override (vs.states) wins, else derived from the
 *  evaluated T/F/U value (DESIGN §19). */
function renderState(ctx: Ctx, id: NodeId): State {
  return (
    ctx.vs.states.get(id) ?? valueToState(ctx.values.get(id) ?? "UnknownV")
  );
}

/** Three-valued evaluation with per-node OVERRIDE (pins): a node listed in `val`
 *  takes that value opaquely (children not consulted); otherwise groups derive from
 *  operative children and leaves are unknown / constant. Fills `out` for every id. */
function nodeValue(
  e: IRExpr,
  val: ReadonlyMap<NodeId, UBoolValue>,
  out: Map<NodeId, UBoolValue>,
): UBoolValue {
  let v: UBoolValue;
  if (e.$type === "And" || e.$type === "Or") {
    const kids = e.args
      .map((a) => nodeValue(a, val, out))
      .filter((_, i) => isOperative(e.args[i]));
    if (val.has(e.id)) v = val.get(e.id)!;
    else if (e.$type === "And")
      v = kids.some((k) => k === "FalseV")
        ? "FalseV"
        : kids.every((k) => k === "TrueV")
          ? "TrueV"
          : "UnknownV";
    else
      v = kids.some((k) => k === "TrueV")
        ? "TrueV"
        : kids.every((k) => k === "FalseV")
          ? "FalseV"
          : "UnknownV";
  } else if (e.$type === "Not") {
    const c = nodeValue(e.negand, val, out);
    v = val.has(e.id)
      ? val.get(e.id)!
      : c === "TrueV"
        ? "FalseV"
        : c === "FalseV"
          ? "TrueV"
          : "UnknownV";
  } else if (e.$type === "Implies") {
    // P → Q, three-valued (DESIGN §25). Note it is TRUE when the scope is FALSE —
    // vacuously — and that is correct; L4's #EVAL says so too. The picture, not the
    // logic, is what must distinguish "true because satisfied" from "true because
    // never reached" (§25.3), and it does that with the lamps (§25.4).
    const p = nodeValue(e.scope, val, out);
    const q = nodeValue(e.requirement, val, out);
    v = val.has(e.id)
      ? val.get(e.id)!
      : p === "FalseV" || q === "TrueV"
        ? "TrueV"
        : p === "TrueV" && q === "FalseV"
          ? "FalseV"
          : "UnknownV";
  } else if (e.$type === "InertE") {
    v = "TrueV"; // inert conducts (identity); nominal, excluded from derivation
  } else {
    v = val.has(e.id)
      ? val.get(e.id)!
      : e.$type === "TrueE"
        ? "TrueV"
        : e.$type === "FalseE"
          ? "FalseV"
          : "UnknownV";
  }
  out.set(e.id, v);
  return v;
}

/** Which lamp is lit (DESIGN §25.4). The whole verdict, in two booleans.
 *  Neither lit ⇒ **N/A** (the scope did not conduct) or **undetermined** (something
 *  is still `?`). The reader tells those apart by looking at WHERE the break is —
 *  a definitively-open scope shows a clean break; an unknown one is grey. */
export interface Lamps {
  green: boolean;
  red: boolean;
}
function lampsFor(
  e: Implies,
  values: Map<NodeId, UBoolValue>,
  inE: boolean,
): Lamps {
  const p = values.get(e.scope.id);
  const q = values.get(e.requirement.id);
  const reached = inE && p === "TrueV"; // current actually left the scope panel
  return {
    green: reached && q === "TrueV",
    red: reached && q === "FalseV", // NOT on `?` — an unknown requirement is not a breach
  };
}

/**
 * The verdict for a decision, from its top-level shape and a valuation (§E1/S9, DESIGN §25f).
 *
 * This is the picture's half of the same answer `BooleanDecisionQuery.verdictOf` computes
 * for the wizard — the SAME six-row table, deliberately, because a diagram and a wizard that
 * disagreed about a case would be lying to the same user. What the IDE header must show is
 * this, NOT the raw truth value: telling someone they "comply" with a rule that never reached
 * them is the N/A-vs-complies category error the whole seam exists to fix.
 *
 *   no seam (body is not an Implies): the function's own value — TrueV `Holds`, FalseV
 *     `Fails`, else `Undetermined`.
 *   seam, scope FALSE:      `NotApplicable`   — the rule never bit; the function is vacuously
 *                                               TRUE, and that TRUE is not compliance.
 *   seam, scope UNKNOWN:    `Undetermined`    — even if the requirement is already met and the
 *                                               function is settled TRUE, we do not know WHICH
 *                                               true it is (N/A vs complies).
 *   seam, scope TRUE + req TRUE:    `Complies`
 *   seam, scope TRUE + req FALSE:   `InBreach`
 *   seam, scope TRUE + req UNKNOWN: `Undetermined`
 *
 * `valuation` is the same map `layout` takes (`ViewSpec.valuation`): positional per-node
 * pins/values, three-valued-evaluated through the tree exactly as the render is.
 */
export function verdictFor(
  fn: FunDecl,
  valuation: ReadonlyMap<NodeId, UBoolValue>,
): Verdict {
  const values = new Map<NodeId, UBoolValue>();
  nodeValue(fn.body, valuation, values);
  const body = fn.body;
  if (body.$type !== "Implies") {
    const v = values.get(body.id);
    return v === "TrueV" ? "Holds" : v === "FalseV" ? "Fails" : "Undetermined";
  }
  const scope = values.get(body.scope.id);
  if (scope === "FalseV") return "NotApplicable";
  if (scope !== "TrueV") return "Undetermined"; // unknown scope: verdict not settled
  const req = values.get(body.requirement.id);
  return req === "TrueV"
    ? "Complies"
    : req === "FalseV"
      ? "InBreach"
      : "Undetermined";
}

interface Energ {
  inE: boolean;
  outE: boolean;
}

/** Current-flow propagation from the source (DESIGN §20). A node CONDUCTS when its
 *  value is TRUE (inert conducts trivially); energization (current reaches a port)
 *  flows top-down — a series stops at the first non-conducting child; an OR's output
 *  closes iff some branch conducts. Fills `em` for every node id. */
function energize(
  e: IRExpr,
  inE: boolean,
  values: Map<NodeId, UBoolValue>,
  em: Map<NodeId, Energ>,
): void {
  const conducts = (n: IRExpr) =>
    n.$type === "InertE" ? true : values.get(n.id) === "TrueV";
  let outE: boolean;
  if (e.$type === "And") {
    let cur = inE;
    for (const a of e.args) {
      energize(a, cur, values, em);
      cur = em.get(a.id)!.outE; // current after this child (false past the first non-conductor)
    }
    outE = e.args.length ? cur : inE;
  } else if (e.$type === "Or") {
    let any = false;
    for (const a of e.args) {
      if (a.$type === "InertE") {
        em.set(a.id, { inE, outE: inE });
        continue;
      }
      energize(a, inE, values, em); // every operative branch sees the OR's input
      if (em.get(a.id)!.outE) any = true;
    }
    outE = inE && any;
  } else if (e.$type === "Not") {
    energize(e.negand, inE, values, em);
    outE = inE && values.get(e.id) === "TrueV";
  } else if (e.$type === "Implies") {
    // The scope sees the rule's own input. The requirement sees current ONLY IF the
    // scope conducts — which is exactly why vacuity needs no bypass: when the scope
    // is open, nothing downstream is energized and NEITHER lamp lights (§25.4).
    energize(e.scope, inE, values, em);
    energize(e.requirement, em.get(e.scope.id)!.outE, values, em);
    outE = inE && values.get(e.id) === "TrueV"; // the node's own truth (¬P ∨ Q)
  } else {
    outE = inE && conducts(e);
  }
  em.set(e.id, { inE, outE });
}

/** Does a node contribute LOCAL closure (a real closed contact)? Inert pass-throughs
 *  don't count — only a TRUE atom/group raises a streamer. */
const trueConducts = (vals: Map<NodeId, UBoolValue>, n: IRExpr): boolean =>
  n.$type !== "InertE" && vals.get(n.id) === "TrueV";

/** Is a node a *presumed* closed contact (DESIGN §22)? — conducting on a TYPICALLY
 *  default the user hasn't confirmed. Its adjacent connectors cap at streamer. */
const presumedConducts = (ctx: Ctx, n: IRExpr): boolean =>
  trueConducts(ctx.values, n) && ctx.vs.provenance.get(n.id) === "default";

/** Connector flow (DESIGN §20): reached by the leader -> 'closed'; else local closure
 *  nearby -> 'streamer'; else 'open'. `tentative` (DESIGN §22) caps a would-be
 *  'closed' at 'streamer' — a rebuttable presumption closes the circuit only
 *  provisionally. Returns undefined when current flow is off. */
function flowFor(
  em: Map<NodeId, Energ> | null,
  leader: boolean,
  local: boolean,
  tentative = false,
): Flow | undefined {
  if (!em) return undefined;
  if (leader) return tentative ? "streamer" : "closed";
  return local ? "streamer" : "open";
}

/** Leading run of inert text = the group's Pre / heading. */
function leadingInert(args: readonly IRExpr[]): string | undefined {
  const lead: string[] = [];
  for (const a of args) {
    if (a.$type === "InertE") lead.push(a.text);
    else break;
  }
  return lead.length ? lead.join(" ") : undefined;
}

/** Fold placeholder label: explicit IR label -> leading inert (the Pre) ->
 *  synthesized. The explicit/Pre branches answer "does the IR need a way to label
 *  a subtree?" (DESIGN §16.1). */
function foldLabel(e: And | Or): string {
  const explicit = e.label ?? leadingInert(e.args);
  if (explicit) return explicit;
  const n = e.args.filter(isOperative).length;
  return e.$type === "And" ? `ALL of ${n}` : `ANY of ${n}`;
}

/** A box for a leaf (click cycles its value) or a folded placeholder (click cycles
 *  the parent's OVERRIDE value; a ▸ caret expands it). DESIGN §19. */
function leafBox(
  id: NodeId,
  label: string,
  state: State,
  role: "leaf" | "placeholder",
  tm: TextMetrics,
  k: Geometry,
  tentative = false,
): Measured {
  const { FONT, PAD_X, PAD_Y, CARET_PAD, TAG_RISE } = k;
  const caretW = role === "placeholder" ? tm.width("▸", FONT) + CARET_PAD : 0;
  const w = caretW + tm.width(label, FONT) + 2 * PAD_X;
  const h = tm.lineHeight(FONT) + 2 * PAD_Y;
  return {
    w,
    h,
    state,
    emit(ox, oy, out) {
      const cy = oy + h / 2;
      out.push({
        kind: "box",
        id,
        rect: { x: ox, y: oy, w, h },
        role,
        state,
        tentative: tentative || undefined,
        act: { t: "value", id },
      });
      if (role === "placeholder")
        out.push({
          kind: "text",
          at: { x: ox + PAD_X, y: cy },
          text: "▸",
          anchor: "middle",
          state,
          tag: "caret",
          act: { t: "fold", id },
        });
      out.push({
        kind: "text",
        at: { x: ox + caretW + (w - caretW) / 2, y: cy },
        text: label,
        anchor: "middle",
        state,
        id,
      });
      if (state === "eliminable")
        out.push({
          kind: "text",
          at: { x: ox + w / 2, y: oy - TAG_RISE },
          text: "otiose — always open",
          anchor: "middle",
          state,
          tag: "otiose",
          size: 11,
        });
      else if (tentative)
        // riding a TYPICALLY presumption (DESIGN §22)
        out.push({
          kind: "text",
          at: { x: ox + w / 2, y: oy - TAG_RISE },
          text: "typically",
          anchor: "middle",
          state,
          tag: "typically",
          size: 10,
        });
      return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } };
    },
  };
}

/** Inert text rendered UNBOXED, with left/right ports at its vertical center so a
 *  series wire connects through it (DESIGN §17). Two styles:
 *  - 'on-wire':    the series leaves the inert's span as a gap; text sits on the line.
 *  - 'below-wire': the inert draws a continuous wire across its span; text drops below. */
// clearance between the wire and the nearest edge of connective text lives in
// Geometry.CONNECTIVE_GAP — shared by above-wire / below-wire / straddle-wire so
// they all hug the line identically. Ascent/descent are derived from the font.
const ascent = (k: Geometry) => k.FONT * 0.78;
const descent = (k: Geometry) => k.FONT * 0.22;

/** Split inert prose into two width-balanced lines (for 'straddle-wire'). One word
 *  can't split -> single line.
 *
 *  FUTURE: generalize to N balanced lines straddling the wire (≈ N/2 above, N/2
 *  below) so we can set an entire paragraph's worth of verbatim inert prose in a
 *  compact block — e.g. balanceNLines(text, tm, targetWidth). Two lines is enough
 *  for now; the wire would thread the middle line (or the gap between the two
 *  central lines for even N). */
function balanceTwoLines(text: string, tm: TextMetrics, k: Geometry): string[] {
  const words = text.split(/\s+/).filter(Boolean);
  if (words.length < 2) return [text];
  let best = 1;
  let bestDiff = Infinity;
  for (let i = 1; i < words.length; i++) {
    const l = tm.width(words.slice(0, i).join(" "), k.FONT);
    const r = tm.width(words.slice(i).join(" "), k.FONT);
    const diff = Math.abs(l - r);
    if (diff < bestDiff) {
      bestDiff = diff;
      best = i;
    }
  }
  return [words.slice(0, best).join(" "), words.slice(best).join(" ")];
}

function inertInline(
  text: string,
  tm: TextMetrics,
  style: ConnectiveStyle,
  k: Geometry,
): Measured {
  const { FONT, PAD_Y, INERT_PAD, CONNECTIVE_GAP, STRADDLE_MIN_WIDTH } = k;
  const lineH = tm.lineHeight(FONT);

  // 'straddle-wire': long prose wraps to two balanced lines threading the
  // (unbroken) wire; short prose stays a single line above (adaptive — "for long
  // strings", DESIGN §17). So this style is a strict superset of 'above-wire'.
  if (style === "straddle-wire") {
    const singleW = tm.width(text, FONT) + 2 * INERT_PAD;
    const lines =
      singleW > STRADDLE_MIN_WIDTH ? balanceTwoLines(text, tm, k) : [text];
    if (lines.length === 2) {
      const w =
        Math.max(tm.width(lines[0], FONT), tm.width(lines[1], FONT)) +
        2 * INERT_PAD;
      const h = 2 * lineH + 2 * CONNECTIVE_GAP; // tight: the two lines hug the wire
      return {
        w,
        h,
        state: "inert",
        emit(ox, oy, out) {
          // the spine wire under the span is drawn by measureAnd (flow-styled, §20)
          const cy = oy + h / 2;
          const mid = ox + w / 2;
          out.push({
            kind: "text",
            at: { x: mid, y: cy - CONNECTIVE_GAP - descent(k) },
            text: lines[0],
            anchor: "middle",
            state: "inert",
            tag: "connective",
          });
          out.push({
            kind: "text",
            at: { x: mid, y: cy + CONNECTIVE_GAP + ascent(k) },
            text: lines[1],
            anchor: "middle",
            state: "inert",
            tag: "connective",
          });
          return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } };
        },
      };
    }
    style = "above-wire"; // single word: nothing to straddle
  }

  const w = tm.width(text, FONT) + 2 * INERT_PAD;
  const h = lineH + 2 * PAD_Y;
  return {
    w,
    h,
    state: "inert",
    emit(ox, oy, out) {
      const cy = oy + h / 2;
      const mid = ox + w / 2;
      if (style === "on-wire") {
        out.push({
          kind: "text",
          at: { x: mid, y: cy },
          text,
          anchor: "middle",
          state: "inert",
          tag: "connective",
        });
      } else {
        // spine wire under the span is drawn by measureAnd (flow-styled, §20)
        const baseline =
          style === "above-wire"
            ? cy - CONNECTIVE_GAP - descent(k)
            : cy + CONNECTIVE_GAP + ascent(k);
        out.push({
          kind: "text",
          at: { x: mid, y: baseline },
          text,
          anchor: "middle",
          state: "inert",
          tag: "connective",
        });
      }
      return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } };
    },
  };
}

/** A cubic Bézier connector with horizontal tangents (leaves the source rightward,
 *  enters the target from the left) — the Layman / box-model fan (DESIGN §17a). */
type Curve = Extract<ScenePrim, { kind: "curve" }>;
function hCurve(from: Pt, to: Pt, state: State): Curve {
  const t = Math.min(
    60,
    Math.max(Math.abs(to.x - from.x) * 0.6, Math.abs(to.y - from.y) * 0.35, 22),
  );
  return {
    kind: "curve",
    from,
    c1: { x: from.x + t, y: from.y },
    c2: { x: to.x - t, y: to.y },
    to,
    role: "conn",
    state,
  };
}
function cubicMid(c: Curve): Pt {
  return {
    x: (c.from.x + 3 * c.c1.x + 3 * c.c2.x + c.to.x) / 8,
    y: (c.from.y + 3 * c.c1.y + 3 * c.c2.y + c.to.y) / 8,
  };
}

function measure(e: IRExpr, ctx: Ctx): Measured {
  const { vs, tm, k } = ctx;

  if (e.$type === "InertE")
    return inertInline(e.text, tm, vs.connectiveStyle, k);

  if (e.$type === "Not") {
    // NOT grammar (DESIGN §21): a scope FRAME round a complex negand (so you can see
    // exactly what's negated) + an inverter BUBBLE on the output. The negand renders
    // its own internal flow; current flips at the bubble (downstream closes iff the
    // inside is open). Nests naturally: not(x(not(ys))) -> frames within frames.
    const inner = measure(e.negand, ctx);
    const complex =
      e.negand.$type === "And" ||
      e.negand.$type === "Or" ||
      e.negand.$type === "Not";
    const NPX = k.NOT_PAD_X;
    const NPY = k.NOT_PAD_Y;
    const LBL = complex ? k.NOT_LABEL : 0;
    const BR = k.NOT_R; // bubble radius
    const BUB = k.NOT_BUBBLE; // output room for the bubble
    const band = LBL + NPY; // symmetric top/bottom so the port stays centred
    const framW = inner.w + 2 * NPX;
    const w = framW + BUB;
    const h = inner.h + 2 * band;
    return {
      w,
      h,
      state: renderState(ctx, e.id),
      emit(ox, oy, out) {
        if (complex)
          out.push({
            kind: "frame",
            rect: { x: ox, y: oy, w: framW, h },
            label: "NOT",
          });
        const p = inner.emit(ox + NPX, oy + band, out);
        const cy = p.inPort.y;
        if (!complex)
          out.push({
            kind: "text",
            at: { x: ox + NPX + inner.w / 2, y: oy + band - 5 },
            text: "NOT",
            anchor: "middle",
            state: "inert",
            tag: "heading",
            size: 11,
            id: e.id,
          });
        const bubbleX = ox + framW;
        // lead in: source-side current reaches the negand
        out.push({
          kind: "wire",
          path: [{ x: ox, y: cy }, p.inPort],
          role: "rung",
          state: "inert",
          flow: flowFor(ctx.em, !!ctx.em?.get(e.id)?.inE, false),
        });
        // negand output up to the bubble (shows the INSIDE's flow)
        out.push({
          kind: "wire",
          path: [p.outPort, { x: bubbleX - BR, y: cy }],
          role: "rung",
          state: "inert",
          flow: flowFor(
            ctx.em,
            !!ctx.em?.get(e.negand.id)?.outE,
            trueConducts(ctx.values, e.negand),
          ),
        });
        out.push({
          kind: "glyph",
          at: { x: bubbleX, y: cy },
          role: "inverter",
        });
        // past the bubble = INVERTED (closes iff the inside is open)
        out.push({
          kind: "wire",
          path: [
            { x: bubbleX + BR, y: cy },
            { x: ox + w, y: cy },
          ],
          role: "rung",
          state: "inert",
          flow: flowFor(
            ctx.em,
            !!ctx.em?.get(e.id)?.outE,
            trueConducts(ctx.values, e),
          ),
        });
        return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } };
      },
    };
  }

  if (e.$type === "Implies") return measureImplies(e, ctx);

  if (e.$type !== "And" && e.$type !== "Or") {
    return leafBox(
      e.id,
      e.label,
      renderState(ctx, e.id),
      "leaf",
      tm,
      k,
      vs.provenance.get(e.id) === "default",
    );
  }

  if (vs.foldSet.has(e.id)) {
    return leafBox(
      e.id,
      foldLabel(e),
      renderState(ctx, e.id),
      "placeholder",
      tm,
      k,
    );
  }

  return e.$type === "And" ? measureAnd(e, ctx) : measureOr(e, ctx);
}

/** AND: series, children centered vertically. Inert children render inline and
 *  ride the wire; a leading inert thus sits to the LEFT of the next element. */
function measureAnd(e: And, ctx: Ctx): Measured {
  const { GAP_SERIES } = ctx.k;
  const kids = e.args.map((a) => measure(a, ctx));
  const h = Math.max(...kids.map((m) => m.h));
  const w = kids.reduce((s, m) => s + m.w, 0) + GAP_SERIES * (kids.length - 1);
  return {
    w,
    h,
    state: "inert",
    emit(ox, oy, out) {
      let x = ox;
      const ports = kids.map((m) => {
        const cy = oy + (h - m.h) / 2; // <-- centered on the cross axis
        const p = m.emit(x, cy, out);
        x += m.w + GAP_SERIES;
        return p;
      });
      const fold = { t: "fold", id: e.id } as const;
      const tc = (n: IRExpr | undefined) =>
        n ? trueConducts(ctx.values, n) : false;
      const pc = (n: IRExpr | undefined) =>
        n ? presumedConducts(ctx, n) : false;
      // connectors between consecutive children
      for (let i = 0; i < ports.length - 1; i++) {
        const leader = !!ctx.em?.get(e.args[i].id)?.outE;
        const local = tc(e.args[i]) || tc(e.args[i + 1]);
        const tentative = pc(e.args[i]) || pc(e.args[i + 1]); // adjacent presumption (§22)
        out.push({
          kind: "wire",
          path: [ports[i].outPort, ports[i + 1].inPort],
          role: "rung",
          state: "inert",
          act: fold,
          flow: flowFor(ctx.em, leader, local, tentative),
        });
      }
      // spine UNDER each inert connective (a pass-through) — same current as its
      // surroundings, so it matches (DESIGN §20). Skipped for 'on-wire' (a real gap).
      if (ctx.vs.connectiveStyle !== "on-wire")
        e.args.forEach((a, i) => {
          if (a.$type !== "InertE") return;
          const leader = !!ctx.em?.get(a.id)?.inE;
          const local = tc(e.args[i - 1]) || tc(e.args[i + 1]);
          const tentative = pc(e.args[i - 1]) || pc(e.args[i + 1]);
          out.push({
            kind: "wire",
            path: [ports[i].inPort, ports[i].outPort],
            role: "rung",
            state: "inert",
            act: fold,
            flow: flowFor(ctx.em, leader, local, tentative),
          });
        });
      return {
        inPort: ports[0].inPort,
        outPort: ports[ports.length - 1].outPort,
      };
    },
  };
}

/** OR: parallel rungs stacked vertically, each centered horizontally, joined by a
 *  left and right bus. A leading inert run becomes a HEADING above the stack; the
 *  band is mirrored top+bottom so the stack stays centered and the rail stays
 *  straight (a poor-man's protrude band, DESIGN §5.6).
 *
 *  A DISJUNCTIVE MEDIAL inert (an inert BETWEEN two rungs, e.g. "or") just sits
 *  unboxed, centered in the gap between the boxes — the gap only widens if the text
 *  needs the room (DESIGN §17). Not connected to the buses; it carries no current. */
function measureOr(e: Or, ctx: Ctx): Measured {
  const { tm } = ctx;
  const { FONT, INERT_PAD, GAP_PARALLEL, BUS_PAD, HEAD_PAD, HEAD_DROP } = ctx.k;
  const lineH = tm.lineHeight(FONT);
  const head = leadingInert(e.args);
  // drop the leading inert run (the heading); fold the remaining inerts into the
  // gaps between the operative rungs they sit between.
  let start = 0;
  while (start < e.args.length && e.args[start].$type === "InertE") start++;

  const rungs: { node: IRExpr; m: Measured }[] = [];
  const gapLabel: (string | null)[] = []; // gapLabel[k] = inert between rung k and k+1
  let pending: string[] = [];
  for (const it of e.args.slice(start)) {
    if (it.$type === "InertE") {
      pending.push(it.text);
    } else {
      if (rungs.length >= 1)
        gapLabel.push(pending.length ? pending.join(" ") : null);
      pending = [];
      rungs.push({ node: it, m: measure(it, ctx) });
    }
  }
  // (a trailing `pending` after the last rung would be a Post; dropped for now)

  const labelW = (k: number) =>
    gapLabel[k] ? tm.width(gapLabel[k] as string, FONT) + 2 * INERT_PAD : 0;
  const gapH = (k: number) =>
    gapLabel[k] ? Math.max(GAP_PARALLEL, lineH + 8) : GAP_PARALLEL;
  const colW = Math.max(
    0,
    ...rungs.map((r) => r.m.w),
    ...gapLabel.map((_, k) => labelW(k)),
  );
  const totalW = colW + 2 * BUS_PAD;
  const stackH =
    rungs.reduce((s, r) => s + r.m.h, 0) +
    gapLabel.reduce((s, _, k) => s + gapH(k), 0);
  const band = head ? lineH + HEAD_PAD : 0;
  const h = stackH + 2 * band;

  return {
    w: totalW,
    h,
    state: "inert",
    emit(ox, oy, out) {
      const leftX = ox; // the OR's in-port: a single point all rungs fan from
      const rightX = ox + totalW; // the out-port, where they converge again
      const top = oy + band;
      const centerY = top + stackH / 2;
      const groupIn: Pt = { x: leftX, y: centerY };
      const groupOut: Pt = { x: rightX, y: centerY };
      let y = top;
      // the leader reaches the fan iff the OR's input is energized (DESIGN §20)
      const leaderIn = !!ctx.em?.get(e.id)?.inE;
      rungs.forEach(({ node, m }, i) => {
        if (i > 0) {
          const k = i - 1;
          const gh = gapH(k);
          if (gapLabel[k])
            out.push({
              kind: "text",
              at: { x: ox + totalW / 2, y: y + gh / 2 + 4 },
              text: gapLabel[k] as string,
              anchor: "middle",
              state: "inert",
              tag: "connective",
            });
          y += gh;
        }
        const cx = ox + BUS_PAD + (colW - m.w) / 2; // <-- centered horizontally
        const p = m.emit(cx, y, out);
        // organic Bézier fan: group port -> rung port, and back (DESIGN §17a).
        // Clicking a fan curve folds this OR (DESIGN §19).
        const fold = { t: "fold", id: e.id } as const;
        const local = trueConducts(ctx.values, node); // this branch is a closed contact
        const tentative = presumedConducts(ctx, node); // …on a rebuttable presumption (§22)
        const leaderOut = !!ctx.em?.get(node.id)?.outE;
        const inCurve = hCurve(groupIn, p.inPort, m.state);
        inCurve.act = fold;
        inCurve.flow = flowFor(ctx.em, leaderIn, local, tentative);
        out.push(inCurve);
        const outCurve = hCurve(p.outPort, groupOut, m.state);
        outCurve.act = fold;
        outCurve.flow = flowFor(ctx.em, leaderOut, local, tentative);
        out.push(outCurve);
        if (m.state === "eliminable" || m.state === "dead") {
          const mid = cubicMid(inCurve);
          out.push({ kind: "glyph", at: mid, role: "open-contact" }); // current can't pass
        }
        y += m.h;
      });
      if (head)
        out.push({
          kind: "text",
          at: { x: ox + totalW / 2, y: oy + band / 2 + HEAD_DROP },
          text: head,
          anchor: "middle",
          state: "inert",
          tag: "heading",
          size: 12.5,
          id: e.id,
          act: { t: "fold", id: e.id },
        });
      return { inPort: groupIn, outPort: groupOut };
    },
  };
}

/** IMPLIES — the seam, the changeover, and the two sinks (DESIGN §25).
 *
 * ONE path: `[scope] ══MUST══▶ [requirement]`, then the requirement's verdict throws a
 * CHANGEOVER — one pole, two throws — to a green lamp (complies) or a red one (in
 * breach). There is deliberately NO bypass: when the scope does not conduct, no
 * current leaves it and neither lamp lights. That is N/A, and the reader sees exactly
 * where it stopped. Drawing the vacuous case as a rung would make "the rule never
 * reached you" a co-equal way of COMPLYING, which it is not — it is a way of not
 * being asked (§25.3).
 */
function measureImplies(e: Implies, ctx: Ctx): Measured {
  const { tm, k } = ctx;
  const { FONT, SEAM_W, FORK_W, COIL_R, COIL_SEP, COIL_LABEL } = k;
  const s = measure(e.scope, ctx);
  const r = measure(e.requirement, ctx);
  const seam = e.seam ?? "⇒";

  const lampsW = FORK_W + 2 * COIL_R + COIL_LABEL;
  const w = s.w + SEAM_W + r.w + lampsW;
  // tall enough for the widest panel AND for the lamp pair to clear the axis
  const h = Math.max(s.h, r.h, 2 * (COIL_SEP + COIL_R + tm.lineHeight(FONT)));

  return {
    w,
    h,
    state: renderState(ctx, e.id),
    emit(ox, oy, out) {
      const cy = oy + h / 2; // the rule's axis
      const sp = s.emit(ox, cy - s.h / 2, out);
      const seamX = ox + s.w;
      const reqX = seamX + SEAM_W;
      const rp = r.emit(reqX, cy - r.h / 2, out);

      const em = ctx.em;
      const inE = !!em?.get(e.id)?.inE;
      const scopeOut = !!em?.get(e.scope.id)?.outE; // did current LEAVE the scope?
      const lamps = lampsFor(e, ctx.values, inE);

      // ── the seam: the drafter's own connective, ON the wire ────────────────────
      // The wire is drawn in TWO segments with a gap, so the connective sits in the
      // line rather than being struck through by it (the 'on-wire' idiom of §17).
      const seamMid = seamX + SEAM_W / 2;
      const gap = tm.width(seam, 12.5) / 2 + 8;
      const seamFlow = flowFor(em, scopeOut, trueConducts(ctx.values, e.scope));
      out.push({
        kind: "wire",
        path: [sp.outPort, { x: seamMid - gap, y: cy }],
        role: "rung",
        state: "inert",
        flow: seamFlow,
      });
      out.push({
        kind: "wire",
        path: [
          { x: seamMid + gap, y: cy },
          { x: reqX, y: cy },
        ],
        role: "rung",
        state: "inert",
        flow: seamFlow,
      });
      out.push({
        kind: "text",
        at: { x: seamMid, y: cy },
        text: seam,
        anchor: "middle",
        state: scopeOut ? "live" : "inert",
        tag: "seam",
        size: 12.5,
        id: e.id,
      });

      // ── the changeover: one pole, two throws (§25.4) ───────────────────────────
      // This segment carries the REQUIREMENT's own conduction, not the scope's. The
      // distinction is not pedantry: feeding it from `scopeOut` would draw a heavy,
      // live wire coming OUT of a requirement that did not conduct — a picture saying
      // current flowed through a failed contact, which is precisely the sort of lie
      // this whole notation exists to refuse. When the requirement fails, current goes
      // in and does not come out, and the changeover — sensing that — throws to red.
      // The red current therefore originates AT the pivot, which is honest: the pole is
      // fed by the rule's own supply and the requirement merely ACTUATES the switch.
      // That compression (one device instead of a `[Q]`/`[/Q]` pair of rungs) is the
      // whole reason the requirement gets drawn once instead of twice.
      const pivotX = rp.outPort.x + FORK_W / 2;
      const coilX = rp.outPort.x + FORK_W + COIL_R;
      out.push({
        kind: "wire",
        path: [rp.outPort, { x: pivotX, y: cy }],
        role: "rung",
        state: "inert",
        flow: flowFor(em, lamps.green, false),
      });
      out.push({ kind: "glyph", at: { x: pivotX, y: cy }, role: "changeover" });

      const throwTo = (dy: number, lit: boolean) => {
        const to = { x: coilX - COIL_R, y: cy + dy };
        const from = { x: pivotX, y: cy };
        const c = hCurve(from, to, "inert");
        c.flow = flowFor(em, lit, false);
        out.push(c);
      };
      throwTo(-COIL_SEP, lamps.green);
      throwTo(COIL_SEP, lamps.red);

      out.push({
        kind: "coil",
        at: { x: coilX, y: cy - COIL_SEP },
        role: "green",
        lit: lamps.green,
        label: "complies",
        id: e.id,
      });
      out.push({
        kind: "coil",
        at: { x: coilX, y: cy + COIL_SEP },
        role: "red",
        lit: lamps.red,
        label: "in breach",
        id: e.id,
      });

      // N/A is not a stamp and not a path — it is BOTH LAMPS DARK, with the break
      // visible in the scope. We only say so in words when the scope is DEFINITIVELY
      // open (a `?` scope is merely undetermined, and must not be reported as N/A).
      if (inE && ctx.values.get(e.scope.id) === "FalseV")
        out.push({
          kind: "text",
          at: { x: coilX + COIL_R + 7, y: cy },
          text: "N/A — the rule does not reach this case",
          anchor: "start",
          state: "inert",
          tag: "note",
          size: 11,
        });

      return { inPort: sp.inPort, outPort: { x: ox + w, y: cy } };
    },
  };
}

export function layout(
  fn: FunDecl,
  vs: ViewSpec,
  tm: TextMetrics,
  k: Geometry = PIXEL_GEOMETRY,
): Scene {
  const { LEAD, MARGIN } = k;
  const prims: ScenePrim[] = [];
  const values = new Map<NodeId, UBoolValue>();
  nodeValue(fn.body, vs.valuation, values);
  const em = vs.showCurrent ? new Map<NodeId, Energ>() : null;
  if (em) energize(fn.body, true, values, em);
  const ctx: Ctx = { vs, tm, k, values, em };
  const m = measure(fn.body, ctx);
  const ox = MARGIN + LEAD;
  const oy = MARGIN;
  const { inPort, outPort } = m.emit(ox, oy, prims);
  prims.push({
    kind: "wire",
    path: [{ x: MARGIN, y: inPort.y }, inPort],
    role: "rail",
    state: "inert",
    flow: em ? "closed" : undefined,
  });
  prims.push({
    kind: "glyph",
    at: { x: MARGIN, y: inPort.y },
    role: "power-terminal",
  });

  // An IMPLIES already HAS its sinks — the two lamps (DESIGN §25.4). A right rail and
  // a second power terminal on top of them would draw the same thing twice, and would
  // claim the rule "conducts" past a breach, which it does not. This is where §25.2's
  // observation is paid off: what was a second power terminal BECOMES the two lamps
  // that report the verdict.
  const twoSinks = fn.body.$type === "Implies";
  if (!twoSinks) {
    prims.push({
      kind: "wire",
      path: [outPort, { x: ox + m.w + LEAD, y: outPort.y }],
      role: "rail",
      state: "inert",
      flow: flowFor(
        em,
        !!em?.get(fn.body.id)?.outE,
        trueConducts(values, fn.body),
        presumedConducts(ctx, fn.body),
      ),
    });
    prims.push({
      kind: "glyph",
      at: { x: ox + m.w + LEAD, y: outPort.y },
      role: "power-terminal",
    });
  }

  const w = ox + m.w + (twoSinks ? 0 : LEAD) + MARGIN;
  return { size: { w, h: oy + m.h + MARGIN }, prims };
}

/** Cheap P0 metrics — proportional-ish estimate; good enough to prove centering.
 *  Swapped for Canvas/fontkit later (font parity, DESIGN §4.4). */
export const estimateMetrics: TextMetrics = {
  width: (t, s) => Math.max(1, t.length) * s * 0.56,
  lineHeight: (s) => s * 1.4,
};
