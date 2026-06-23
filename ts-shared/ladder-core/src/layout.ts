/**
 * The BBE layout kernel (DESIGN §5): IRExpr × TextMetrics × ViewSpec -> Scene IR.
 *
 * "Align, then stack." AND = series (horizontal, children centered vertically);
 * OR = parallel (vertical, children centered horizontally). Centering is intrinsic
 * to the re-margining — `pos = (boundingExtent - childExtent) / 2` — so no general
 * graph engine ever fights us (the headline fix; DESIGN §0, §5.3).
 *
 * P0 is LR-only; TB is a later transpose. Text is single-line (no pre-breaking yet).
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
} from './types.js'

const PAD_X = 14
const PAD_Y = 10
const GAP_SERIES = 44 // horizontal gap between AND siblings
const GAP_PARALLEL = 26 // vertical gap between OR siblings
const BUS_PAD = 26 // gap between an OR's bus and its child boxes
const LEAD = 40 // power-lead length at the far left/right
const MARGIN = 60
const FONT = 14

/** A measured BBE: intrinsic size + an emit that places it at an absolute origin
 *  and returns its in/out ports (DESIGN §5.7). This is the BBE algebra in code. */
interface Measured {
  w: number
  h: number
  state: State // own state (leaf state, or 'inert' for a group/placeholder)
  emit(ox: number, oy: number, out: ScenePrim[]): { inPort: Pt; outPort: Pt }
}

interface Ctx {
  vs: ViewSpec
  tm: TextMetrics
}

const stateOf = (vs: ViewSpec, id: NodeId): State => vs.states.get(id) ?? 'inert'

/** Label shown when a subtree is folded. Precedence: explicit IR label (if the
 *  IR carries one) -> synthesized "ALL/ANY of n". The explicit branch is the
 *  answer to "does the IR need a way to label a subtree?" — see DESIGN §16. */
function foldLabel(e: Extract<IRExpr, { $type: 'And' | 'Or' }>): string {
  if (e.label) return `▸ ${e.label}`
  const n = e.args.length
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
      out.push({
        kind: 'text',
        at: { x: ox + w / 2, y: oy + h / 2 },
        text: label,
        anchor: 'middle',
        state,
      })
      if (state === 'eliminable')
        out.push({
          kind: 'text',
          at: { x: ox + w / 2, y: oy - 9 },
          text: 'otiose — always open',
          anchor: 'middle',
          state,
          tag: 'otiose',
          size: 11,
        })
      const cy = oy + h / 2
      return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } }
    },
  }
}

function measure(e: IRExpr, ctx: Ctx): Measured {
  const { vs, tm } = ctx

  if (e.$type === 'Not') {
    // P0: render the negand and prefix a ¬ marker on its in-port. (No Not in the
    // s415 second-limb fixture; kept minimal.)
    const inner = measure(e.negand, ctx)
    return {
      ...inner,
      emit(ox, oy, out) {
        const p = inner.emit(ox, oy, out)
        out.push({
          kind: 'text',
          at: { x: p.inPort.x - 6, y: p.inPort.y - 8 },
          text: '¬',
          anchor: 'middle',
          state: inner.state,
        })
        return p
      },
    }
  }

  if (e.$type !== 'And' && e.$type !== 'Or') {
    return leafBox(e.id, e.label, stateOf(vs, e.id), 'leaf', tm)
  }

  // Folded AND/OR collapses to a placeholder leaf that KEEPS its rolled-up state.
  if (vs.foldSet.has(e.id)) {
    return leafBox(e.id, foldLabel(e), rollup(e, vs), 'placeholder', tm)
  }

  const kids = e.args.map((a) => measure(a, ctx))

  if (e.$type === 'And') {
    // series: lay left->right, center each child vertically (the centering).
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
          out.push({
            kind: 'wire',
            path: [ports[i].outPort, ports[i + 1].inPort],
            role: 'rung',
            state: 'inert',
          })
        return { inPort: ports[0].inPort, outPort: ports[ports.length - 1].outPort }
      },
    }
  }

  // OR: parallel rungs stacked vertically, each centered horizontally, joined by
  // a left and right bus (DESIGN §5.5, §5.7).
  const colW = Math.max(...kids.map((k) => k.w))
  const totalW = colW + 2 * BUS_PAD
  const h = kids.reduce((s, k) => s + k.h, 0) + GAP_PARALLEL * (kids.length - 1)
  return {
    w: totalW,
    h,
    state: 'inert',
    emit(ox, oy, out) {
      const leftBusX = ox
      const rightBusX = ox + totalW
      let y = oy
      const centers: number[] = []
      for (const k of kids) {
        const cx = ox + BUS_PAD + (colW - k.w) / 2 // <-- centered horizontally
        const p = k.emit(cx, y, out)
        const cy = p.inPort.y
        centers.push(cy)
        const broken = k.state === 'eliminable' || k.state === 'dead'
        if (broken) {
          // split the left stub with an open-contact break: no current passes.
          const mid = (leftBusX + p.inPort.x) / 2
          out.push({ kind: 'wire', path: [{ x: leftBusX, y: cy }, { x: mid - 7, y: cy }], role: 'stub', state: k.state })
          out.push({ kind: 'glyph', at: { x: mid, y: cy }, role: 'open-contact' })
          out.push({ kind: 'wire', path: [{ x: mid + 7, y: cy }, { x: p.inPort.x, y: cy }], role: 'stub', state: k.state })
        } else {
          out.push({ kind: 'wire', path: [{ x: leftBusX, y: cy }, p.inPort], role: 'stub', state: k.state })
        }
        out.push({ kind: 'wire', path: [p.outPort, { x: rightBusX, y: p.outPort.y }], role: 'stub', state: k.state })
        y += k.h + GAP_PARALLEL
      }
      out.push({ kind: 'wire', path: [{ x: leftBusX, y: centers[0] }, { x: leftBusX, y: centers[centers.length - 1] }], role: 'rail', state: 'inert' })
      out.push({ kind: 'wire', path: [{ x: rightBusX, y: centers[0] }, { x: rightBusX, y: centers[centers.length - 1] }], role: 'rail', state: 'inert' })
      return { inPort: { x: leftBusX, y: oy + h / 2 }, outPort: { x: rightBusX, y: oy + h / 2 } }
    },
  }
}

/** Rolled-up state of a folded subtree (P0 heuristic; real eval is P1). */
function rollup(e: Extract<IRExpr, { $type: 'And' | 'Or' }>, vs: ViewSpec): State {
  const kid = e.args.map((a) => ('id' in a ? stateOf(vs, a.id) : 'inert'))
  if (kid.some((s) => s === 'eliminable')) return 'eliminable'
  return 'inert'
}

/** Top-level: lay out the body, add power leads + terminals, return a Scene. */
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
