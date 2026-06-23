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
} from './types.js'

const PAD_X = 14
const PAD_Y = 10
const GAP_SERIES = 44 // horizontal gap between AND siblings
const GAP_PARALLEL = 26 // vertical gap between OR siblings
const BUS_PAD = 26 // gap between an OR's bus and its child boxes
const INERT_PAD = 12 // horizontal breathing room around inline inert text
const LEAD = 40 // power-lead length at the far left/right
const MARGIN = 70
const FONT = 14

interface Measured {
  w: number
  h: number
  state: State // own state (leaf state, or 'inert' for a group/placeholder/inert)
  emit(ox: number, oy: number, out: ScenePrim[]): { inPort: Pt; outPort: Pt }
}

interface Ctx {
  vs: ViewSpec
  tm: TextMetrics
}

const stateOf = (vs: ViewSpec, id: NodeId): State => vs.states.get(id) ?? 'inert'
const isOperative = (e: IRExpr): boolean => e.$type !== 'InertE'

/** Leading run of inert text = the group's Pre / heading. */
function leadingInert(args: readonly IRExpr[]): string | undefined {
  const lead: string[] = []
  for (const a of args) {
    if (a.$type === 'InertE') lead.push(a.text)
    else break
  }
  return lead.length ? lead.join(' ') : undefined
}

/** Fold placeholder label: explicit IR label -> leading inert (the Pre) ->
 *  synthesized. The explicit/Pre branches answer "does the IR need a way to label
 *  a subtree?" (DESIGN §16.1). */
function foldLabel(e: And | Or): string {
  const explicit = e.label ?? leadingInert(e.args)
  if (explicit) return `▸ ${explicit}`
  const n = e.args.filter(isOperative).length
  return e.$type === 'And' ? `▸ ALL of ${n}` : `▸ ANY of ${n}`
}

function leafBox(
  id: NodeId,
  label: string,
  state: State,
  role: 'leaf' | 'placeholder',
  tm: TextMetrics
): Measured {
  const w = tm.width(label, FONT) + 2 * PAD_X
  const h = tm.lineHeight(FONT) + 2 * PAD_Y
  return {
    w,
    h,
    state,
    emit(ox, oy, out) {
      out.push({ kind: 'box', id, rect: { x: ox, y: oy, w, h }, role, state })
      out.push({ kind: 'text', at: { x: ox + w / 2, y: oy + h / 2 }, text: label, anchor: 'middle', state })
      if (state === 'eliminable')
        out.push({ kind: 'text', at: { x: ox + w / 2, y: oy - 9 }, text: 'otiose — always open', anchor: 'middle', state, tag: 'otiose', size: 11 })
      const cy = oy + h / 2
      return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } }
    },
  }
}

/** Inert text rendered UNBOXED, with left/right ports at its vertical center so a
 *  series wire connects through it (DESIGN §17). Two styles:
 *  - 'on-wire':    the series leaves the inert's span as a gap; text sits on the line.
 *  - 'below-wire': the inert draws a continuous wire across its span; text drops below. */
const C_GAP = 8 // clearance between the wire and the nearest edge of connective text
const C_ASCENT = FONT * 0.78
const C_DESCENT = FONT * 0.22
const STRADDLE_MIN_WIDTH = 160 // only wrap connectives wider than this (~a box width)
const STRADDLE_GAP = 3 // tighter than C_GAP: the two straddle lines hug the wire

/** Split inert prose into two width-balanced lines (for 'straddle-wire'). One word
 *  can't split -> single line.
 *
 *  FUTURE: generalize to N balanced lines straddling the wire (≈ N/2 above, N/2
 *  below) so we can set an entire paragraph's worth of verbatim inert prose in a
 *  compact block — e.g. balanceNLines(text, tm, targetWidth). Two lines is enough
 *  for now; the wire would thread the middle line (or the gap between the two
 *  central lines for even N). */
function balanceTwoLines(text: string, tm: TextMetrics): string[] {
  const words = text.split(/\s+/).filter(Boolean)
  if (words.length < 2) return [text]
  let best = 1
  let bestDiff = Infinity
  for (let i = 1; i < words.length; i++) {
    const l = tm.width(words.slice(0, i).join(' '), FONT)
    const r = tm.width(words.slice(i).join(' '), FONT)
    const diff = Math.abs(l - r)
    if (diff < bestDiff) {
      bestDiff = diff
      best = i
    }
  }
  return [words.slice(0, best).join(' '), words.slice(best).join(' ')]
}

function inertInline(text: string, tm: TextMetrics, style: ConnectiveStyle): Measured {
  const lineH = tm.lineHeight(FONT)

  // 'straddle-wire': long prose wraps to two balanced lines threading the
  // (unbroken) wire; short prose stays a single line above (adaptive — "for long
  // strings", DESIGN §17). So this style is a strict superset of 'above-wire'.
  if (style === 'straddle-wire') {
    const singleW = tm.width(text, FONT) + 2 * INERT_PAD
    const lines = singleW > STRADDLE_MIN_WIDTH ? balanceTwoLines(text, tm) : [text]
    if (lines.length === 2) {
      const w = Math.max(tm.width(lines[0], FONT), tm.width(lines[1], FONT)) + 2 * INERT_PAD
      const h = 2 * lineH + 2 * STRADDLE_GAP // tight: the two lines hug the wire
      return {
        w,
        h,
        state: 'inert',
        emit(ox, oy, out) {
          const cy = oy + h / 2
          const mid = ox + w / 2
          out.push({ kind: 'wire', path: [{ x: ox, y: cy }, { x: ox + w, y: cy }], role: 'rung', state: 'inert' })
          out.push({ kind: 'text', at: { x: mid, y: cy - STRADDLE_GAP - C_DESCENT }, text: lines[0], anchor: 'middle', state: 'inert', tag: 'connective' })
          out.push({ kind: 'text', at: { x: mid, y: cy + STRADDLE_GAP + C_ASCENT }, text: lines[1], anchor: 'middle', state: 'inert', tag: 'connective' })
          return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } }
        },
      }
    }
    style = 'above-wire' // single word: nothing to straddle
  }

  const w = tm.width(text, FONT) + 2 * INERT_PAD
  const h = lineH + 2 * PAD_Y
  return {
    w,
    h,
    state: 'inert',
    emit(ox, oy, out) {
      const cy = oy + h / 2
      const mid = ox + w / 2
      if (style === 'on-wire') {
        out.push({ kind: 'text', at: { x: mid, y: cy }, text, anchor: 'middle', state: 'inert', tag: 'connective' })
      } else {
        // unbroken wire through the span (inert always conducts)
        out.push({ kind: 'wire', path: [{ x: ox, y: cy }, { x: ox + w, y: cy }], role: 'rung', state: 'inert' })
        const baseline = style === 'above-wire' ? cy - C_GAP - C_DESCENT : cy + C_GAP + C_ASCENT
        out.push({ kind: 'text', at: { x: mid, y: baseline }, text, anchor: 'middle', state: 'inert', tag: 'connective' })
      }
      return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } }
    },
  }
}

function measure(e: IRExpr, ctx: Ctx): Measured {
  const { vs, tm } = ctx

  if (e.$type === 'InertE') return inertInline(e.text, tm, vs.connectiveStyle)

  if (e.$type === 'Not') {
    const inner = measure(e.negand, ctx)
    return {
      ...inner,
      emit(ox, oy, out) {
        const p = inner.emit(ox, oy, out)
        out.push({ kind: 'text', at: { x: p.inPort.x - 6, y: p.inPort.y - 8 }, text: '¬', anchor: 'middle', state: inner.state })
        return p
      },
    }
  }

  if (e.$type !== 'And' && e.$type !== 'Or') {
    return leafBox(e.id, e.label, stateOf(vs, e.id), 'leaf', tm)
  }

  if (vs.foldSet.has(e.id)) {
    return leafBox(e.id, foldLabel(e), rollup(e, vs), 'placeholder', tm)
  }

  return e.$type === 'And' ? measureAnd(e, ctx) : measureOr(e, ctx)
}

/** AND: series, children centered vertically. Inert children render inline and
 *  ride the wire; a leading inert thus sits to the LEFT of the next element. */
function measureAnd(e: And, ctx: Ctx): Measured {
  const kids = e.args.map((a) => measure(a, ctx))
  const h = Math.max(...kids.map((k) => k.h))
  const w = kids.reduce((s, k) => s + k.w, 0) + GAP_SERIES * (kids.length - 1)
  return {
    w,
    h,
    state: 'inert',
    emit(ox, oy, out) {
      let x = ox
      const ports = kids.map((k) => {
        const cy = oy + (h - k.h) / 2 // <-- centered on the cross axis
        const p = k.emit(x, cy, out)
        x += k.w + GAP_SERIES
        return p
      })
      for (let i = 0; i < ports.length - 1; i++)
        out.push({ kind: 'wire', path: [ports[i].outPort, ports[i + 1].inPort], role: 'rung', state: 'inert' })
      return { inPort: ports[0].inPort, outPort: ports[ports.length - 1].outPort }
    },
  }
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
  const { tm } = ctx
  const lineH = tm.lineHeight(FONT)
  const head = leadingInert(e.args)
  // drop the leading inert run (the heading); fold the remaining inerts into the
  // gaps between the operative rungs they sit between.
  let start = 0
  while (start < e.args.length && e.args[start].$type === 'InertE') start++

  const rungs: Measured[] = []
  const gapLabel: (string | null)[] = [] // gapLabel[k] = inert between rung k and k+1
  let pending: string[] = []
  for (const it of e.args.slice(start)) {
    if (it.$type === 'InertE') {
      pending.push(it.text)
    } else {
      if (rungs.length >= 1) gapLabel.push(pending.length ? pending.join(' ') : null)
      pending = []
      rungs.push(measure(it, ctx))
    }
  }
  // (a trailing `pending` after the last rung would be a Post; dropped for now)

  const labelW = (k: number) => (gapLabel[k] ? tm.width(gapLabel[k] as string, FONT) + 2 * INERT_PAD : 0)
  const gapH = (k: number) => (gapLabel[k] ? Math.max(GAP_PARALLEL, lineH + 8) : GAP_PARALLEL)
  const colW = Math.max(0, ...rungs.map((m) => m.w), ...gapLabel.map((_, k) => labelW(k)))
  const totalW = colW + 2 * BUS_PAD
  const stackH = rungs.reduce((s, m) => s + m.h, 0) + gapLabel.reduce((s, _, k) => s + gapH(k), 0)
  const band = head ? lineH + 12 : 0
  const h = stackH + 2 * band

  return {
    w: totalW,
    h,
    state: 'inert',
    emit(ox, oy, out) {
      const leftBusX = ox
      const rightBusX = ox + totalW
      const top = oy + band
      let y = top
      const rungCenters: number[] = []
      rungs.forEach((m, i) => {
        if (i > 0) {
          const k = i - 1
          const gh = gapH(k)
          if (gapLabel[k])
            out.push({ kind: 'text', at: { x: ox + totalW / 2, y: y + gh / 2 + 4 }, text: gapLabel[k] as string, anchor: 'middle', state: 'inert', tag: 'connective' })
          y += gh
        }
        const cx = ox + BUS_PAD + (colW - m.w) / 2 // <-- centered horizontally
        const p = m.emit(cx, y, out)
        const cy = p.inPort.y
        const broken = m.state === 'eliminable' || m.state === 'dead'
        if (broken) {
          const mid = (leftBusX + p.inPort.x) / 2
          out.push({ kind: 'wire', path: [{ x: leftBusX, y: cy }, { x: mid - 7, y: cy }], role: 'stub', state: m.state })
          out.push({ kind: 'glyph', at: { x: mid, y: cy }, role: 'open-contact' })
          out.push({ kind: 'wire', path: [{ x: mid + 7, y: cy }, { x: p.inPort.x, y: cy }], role: 'stub', state: m.state })
        } else {
          out.push({ kind: 'wire', path: [{ x: leftBusX, y: cy }, p.inPort], role: 'stub', state: m.state })
        }
        out.push({ kind: 'wire', path: [p.outPort, { x: rightBusX, y: p.outPort.y }], role: 'stub', state: m.state })
        rungCenters.push(cy)
        y += m.h
      })
      if (rungCenters.length) {
        out.push({ kind: 'wire', path: [{ x: leftBusX, y: rungCenters[0] }, { x: leftBusX, y: rungCenters[rungCenters.length - 1] }], role: 'rail', state: 'inert' })
        out.push({ kind: 'wire', path: [{ x: rightBusX, y: rungCenters[0] }, { x: rightBusX, y: rungCenters[rungCenters.length - 1] }], role: 'rail', state: 'inert' })
      }
      if (head) out.push({ kind: 'text', at: { x: ox + totalW / 2, y: oy + band / 2 + 2 }, text: head, anchor: 'middle', state: 'inert', tag: 'heading', size: 12.5 })
      return { inPort: { x: leftBusX, y: top + stackH / 2 }, outPort: { x: rightBusX, y: top + stackH / 2 } }
    },
  }
}

function rollup(e: And | Or, vs: ViewSpec): State {
  const kid = e.args.filter(isOperative).map((a) => ('id' in a ? stateOf(vs, a.id) : 'inert'))
  if (kid.some((s) => s === 'eliminable')) return 'eliminable'
  return 'inert'
}

export function layout(fn: FunDecl, vs: ViewSpec, tm: TextMetrics): Scene {
  const prims: ScenePrim[] = []
  const m = measure(fn.body, { vs, tm })
  const ox = MARGIN + LEAD
  const oy = MARGIN
  const { inPort, outPort } = m.emit(ox, oy, prims)

  prims.push({ kind: 'wire', path: [{ x: MARGIN, y: inPort.y }, inPort], role: 'rail', state: 'inert' })
  prims.push({ kind: 'wire', path: [outPort, { x: ox + m.w + LEAD, y: outPort.y }], role: 'rail', state: 'inert' })
  prims.push({ kind: 'glyph', at: { x: MARGIN, y: inPort.y }, role: 'power-terminal' })
  prims.push({ kind: 'glyph', at: { x: ox + m.w + LEAD, y: outPort.y }, role: 'power-terminal' })

  return { size: { w: ox + m.w + LEAD + MARGIN, h: oy + m.h + MARGIN }, prims }
}

/** Cheap P0 metrics — proportional-ish estimate; good enough to prove centering.
 *  Swapped for Canvas/fontkit later (font parity, DESIGN §4.4). */
export const estimateMetrics: TextMetrics = {
  width: (t, s) => Math.max(1, t.length) * s * 0.56,
  lineHeight: (s) => s * 1.4,
}
