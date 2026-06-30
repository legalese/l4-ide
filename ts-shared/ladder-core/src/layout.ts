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
  values: Map<NodeId, UBoolValue> // evaluated T/F/U per node id
  em: Map<NodeId, Energ> | null // energization per node id, when showCurrent
}

const isOperative = (e: IRExpr): boolean => e.$type !== 'InertE'

const valueToState = (v: UBoolValue): State =>
  v === 'TrueV' ? 'live' : v === 'FalseV' ? 'dead' : 'inert'

/** Render state for a node: manual override (vs.states) wins, else derived from the
 *  evaluated T/F/U value (DESIGN §19). */
function renderState(ctx: Ctx, id: NodeId): State {
  return ctx.vs.states.get(id) ?? valueToState(ctx.values.get(id) ?? 'UnknownV')
}

/** Three-valued evaluation with per-node OVERRIDE (pins): a node listed in `val`
 *  takes that value opaquely (children not consulted); otherwise groups derive from
 *  operative children and leaves are unknown / constant. Fills `out` for every id. */
function nodeValue(e: IRExpr, val: ReadonlyMap<NodeId, UBoolValue>, out: Map<NodeId, UBoolValue>): UBoolValue {
  let v: UBoolValue
  if (e.$type === 'And' || e.$type === 'Or') {
    const kids = e.args.map((a) => nodeValue(a, val, out)).filter((_, i) => isOperative(e.args[i]))
    if (val.has(e.id)) v = val.get(e.id)!
    else if (e.$type === 'And') v = kids.some((k) => k === 'FalseV') ? 'FalseV' : kids.every((k) => k === 'TrueV') ? 'TrueV' : 'UnknownV'
    else v = kids.some((k) => k === 'TrueV') ? 'TrueV' : kids.every((k) => k === 'FalseV') ? 'FalseV' : 'UnknownV'
  } else if (e.$type === 'Not') {
    const c = nodeValue(e.negand, val, out)
    v = val.has(e.id) ? val.get(e.id)! : c === 'TrueV' ? 'FalseV' : c === 'FalseV' ? 'TrueV' : 'UnknownV'
  } else if (e.$type === 'InertE') {
    v = 'TrueV' // inert conducts (identity); nominal, excluded from derivation
  } else {
    v = val.has(e.id) ? val.get(e.id)! : e.$type === 'TrueE' ? 'TrueV' : e.$type === 'FalseE' ? 'FalseV' : 'UnknownV'
  }
  out.set(e.id, v)
  return v
}

interface Energ {
  inE: boolean
  outE: boolean
}

/** Current-flow propagation from the source (DESIGN §20). A node CONDUCTS when its
 *  value is TRUE (inert conducts trivially); energization (current reaches a port)
 *  flows top-down — a series stops at the first non-conducting child; an OR's output
 *  closes iff some branch conducts. Fills `em` for every node id. */
function energize(e: IRExpr, inE: boolean, values: Map<NodeId, UBoolValue>, em: Map<NodeId, Energ>): void {
  const conducts = (n: IRExpr) => (n.$type === 'InertE' ? true : values.get(n.id) === 'TrueV')
  let outE: boolean
  if (e.$type === 'And') {
    let cur = inE
    for (const a of e.args) {
      energize(a, cur, values, em)
      cur = em.get(a.id)!.outE // current after this child (false past the first non-conductor)
    }
    outE = e.args.length ? cur : inE
  } else if (e.$type === 'Or') {
    let any = false
    for (const a of e.args) {
      if (a.$type === 'InertE') {
        em.set(a.id, { inE, outE: inE })
        continue
      }
      energize(a, inE, values, em) // every operative branch sees the OR's input
      if (em.get(a.id)!.outE) any = true
    }
    outE = inE && any
  } else if (e.$type === 'Not') {
    energize(e.negand, inE, values, em)
    outE = inE && values.get(e.id) === 'TrueV'
  } else {
    outE = inE && conducts(e)
  }
  em.set(e.id, { inE, outE })
}

/** Does a node contribute LOCAL closure (a real closed contact)? Inert pass-throughs
 *  don't count — only a TRUE atom/group raises a streamer. */
const trueConducts = (vals: Map<NodeId, UBoolValue>, n: IRExpr): boolean =>
  n.$type !== 'InertE' && vals.get(n.id) === 'TrueV'

/** Connector flow (DESIGN §20): reached by the leader -> 'closed'; else local closure
 *  nearby -> 'streamer'; else 'open'. Returns undefined when current flow is off. */
function flowFor(em: Map<NodeId, Energ> | null, leader: boolean, local: boolean): Flow | undefined {
  if (!em) return undefined
  return leader ? 'closed' : local ? 'streamer' : 'open'
}

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
  if (explicit) return explicit
  const n = e.args.filter(isOperative).length
  return e.$type === 'And' ? `ALL of ${n}` : `ANY of ${n}`
}

/** A box for a leaf (click cycles its value) or a folded placeholder (click cycles
 *  the parent's OVERRIDE value; a ▸ caret expands it). DESIGN §19. */
function leafBox(
  id: NodeId,
  label: string,
  state: State,
  role: 'leaf' | 'placeholder',
  tm: TextMetrics
): Measured {
  const caretW = role === 'placeholder' ? tm.width('▸', FONT) + 8 : 0
  const w = caretW + tm.width(label, FONT) + 2 * PAD_X
  const h = tm.lineHeight(FONT) + 2 * PAD_Y
  return {
    w,
    h,
    state,
    emit(ox, oy, out) {
      const cy = oy + h / 2
      out.push({ kind: 'box', id, rect: { x: ox, y: oy, w, h }, role, state, act: { t: 'value', id } })
      if (role === 'placeholder')
        out.push({ kind: 'text', at: { x: ox + PAD_X, y: cy }, text: '▸', anchor: 'middle', state, tag: 'caret', act: { t: 'fold', id } })
      out.push({ kind: 'text', at: { x: ox + caretW + (w - caretW) / 2, y: cy }, text: label, anchor: 'middle', state, id })
      if (state === 'eliminable')
        out.push({ kind: 'text', at: { x: ox + w / 2, y: oy - 9 }, text: 'otiose — always open', anchor: 'middle', state, tag: 'otiose', size: 11 })
      return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } }
    },
  }
}

/** Inert text rendered UNBOXED, with left/right ports at its vertical center so a
 *  series wire connects through it (DESIGN §17). Two styles:
 *  - 'on-wire':    the series leaves the inert's span as a gap; text sits on the line.
 *  - 'below-wire': the inert draws a continuous wire across its span; text drops below. */
// clearance between the wire and the nearest edge of connective text — shared by
// above-wire / below-wire / straddle-wire so they all hug the line identically.
const CONNECTIVE_GAP = 3
const C_ASCENT = FONT * 0.78
const C_DESCENT = FONT * 0.22
const STRADDLE_MIN_WIDTH = 160 // only wrap connectives wider than this (~a box width)

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
      const h = 2 * lineH + 2 * CONNECTIVE_GAP // tight: the two lines hug the wire
      return {
        w,
        h,
        state: 'inert',
        emit(ox, oy, out) {
          // the spine wire under the span is drawn by measureAnd (flow-styled, §20)
          const cy = oy + h / 2
          const mid = ox + w / 2
          out.push({ kind: 'text', at: { x: mid, y: cy - CONNECTIVE_GAP - C_DESCENT }, text: lines[0], anchor: 'middle', state: 'inert', tag: 'connective' })
          out.push({ kind: 'text', at: { x: mid, y: cy + CONNECTIVE_GAP + C_ASCENT }, text: lines[1], anchor: 'middle', state: 'inert', tag: 'connective' })
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
        // spine wire under the span is drawn by measureAnd (flow-styled, §20)
        const baseline = style === 'above-wire' ? cy - CONNECTIVE_GAP - C_DESCENT : cy + CONNECTIVE_GAP + C_ASCENT
        out.push({ kind: 'text', at: { x: mid, y: baseline }, text, anchor: 'middle', state: 'inert', tag: 'connective' })
      }
      return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } }
    },
  }
}

/** A cubic Bézier connector with horizontal tangents (leaves the source rightward,
 *  enters the target from the left) — the Layman / box-model fan (DESIGN §17a). */
type Curve = Extract<ScenePrim, { kind: 'curve' }>
function hCurve(from: Pt, to: Pt, state: State): Curve {
  const t = Math.min(60, Math.max(Math.abs(to.x - from.x) * 0.6, Math.abs(to.y - from.y) * 0.35, 22))
  return { kind: 'curve', from, c1: { x: from.x + t, y: from.y }, c2: { x: to.x - t, y: to.y }, to, role: 'conn', state }
}
function cubicMid(c: Curve): Pt {
  return {
    x: (c.from.x + 3 * c.c1.x + 3 * c.c2.x + c.to.x) / 8,
    y: (c.from.y + 3 * c.c1.y + 3 * c.c2.y + c.to.y) / 8,
  }
}

function measure(e: IRExpr, ctx: Ctx): Measured {
  const { vs, tm } = ctx

  if (e.$type === 'InertE') return inertInline(e.text, tm, vs.connectiveStyle)

  if (e.$type === 'Not') {
    // NOT grammar (DESIGN §21): a scope FRAME round a complex negand (so you can see
    // exactly what's negated) + an inverter BUBBLE on the output. The negand renders
    // its own internal flow; current flips at the bubble (downstream closes iff the
    // inside is open). Nests naturally: not(x(not(ys))) -> frames within frames.
    const inner = measure(e.negand, ctx)
    const complex = e.negand.$type === 'And' || e.negand.$type === 'Or' || e.negand.$type === 'Not'
    const NPX = 16
    const NPY = 12
    const LBL = complex ? 16 : 0
    const BR = 5 // bubble radius
    const BUB = 20 // output room for the bubble
    const band = LBL + NPY // symmetric top/bottom so the port stays centred
    const framW = inner.w + 2 * NPX
    const w = framW + BUB
    const h = inner.h + 2 * band
    return {
      w,
      h,
      state: renderState(ctx, e.id),
      emit(ox, oy, out) {
        if (complex) out.push({ kind: 'frame', rect: { x: ox, y: oy, w: framW, h }, label: 'NOT' })
        const p = inner.emit(ox + NPX, oy + band, out)
        const cy = p.inPort.y
        if (!complex) out.push({ kind: 'text', at: { x: ox + NPX + inner.w / 2, y: oy + band - 5 }, text: 'NOT', anchor: 'middle', state: 'inert', tag: 'heading', size: 11, id: e.id })
        const bubbleX = ox + framW
        // lead in: source-side current reaches the negand
        out.push({ kind: 'wire', path: [{ x: ox, y: cy }, p.inPort], role: 'rung', state: 'inert', flow: flowFor(ctx.em, !!ctx.em?.get(e.id)?.inE, false) })
        // negand output up to the bubble (shows the INSIDE's flow)
        out.push({ kind: 'wire', path: [p.outPort, { x: bubbleX - BR, y: cy }], role: 'rung', state: 'inert', flow: flowFor(ctx.em, !!ctx.em?.get(e.negand.id)?.outE, trueConducts(ctx.values, e.negand)) })
        out.push({ kind: 'glyph', at: { x: bubbleX, y: cy }, role: 'inverter' })
        // past the bubble = INVERTED (closes iff the inside is open)
        out.push({ kind: 'wire', path: [{ x: bubbleX + BR, y: cy }, { x: ox + w, y: cy }], role: 'rung', state: 'inert', flow: flowFor(ctx.em, !!ctx.em?.get(e.id)?.outE, trueConducts(ctx.values, e)) })
        return { inPort: { x: ox, y: cy }, outPort: { x: ox + w, y: cy } }
      },
    }
  }

  if (e.$type !== 'And' && e.$type !== 'Or') {
    return leafBox(e.id, e.label, renderState(ctx, e.id), 'leaf', tm)
  }

  if (vs.foldSet.has(e.id)) {
    return leafBox(e.id, foldLabel(e), renderState(ctx, e.id), 'placeholder', tm)
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
      const fold = { t: 'fold', id: e.id } as const
      const tc = (n: IRExpr | undefined) => (n ? trueConducts(ctx.values, n) : false)
      // connectors between consecutive children
      for (let i = 0; i < ports.length - 1; i++) {
        const leader = !!ctx.em?.get(e.args[i].id)?.outE
        const local = tc(e.args[i]) || tc(e.args[i + 1])
        out.push({ kind: 'wire', path: [ports[i].outPort, ports[i + 1].inPort], role: 'rung', state: 'inert', act: fold, flow: flowFor(ctx.em, leader, local) })
      }
      // spine UNDER each inert connective (a pass-through) — same current as its
      // surroundings, so it matches (DESIGN §20). Skipped for 'on-wire' (a real gap).
      if (ctx.vs.connectiveStyle !== 'on-wire')
        e.args.forEach((a, i) => {
          if (a.$type !== 'InertE') return
          const leader = !!ctx.em?.get(a.id)?.inE
          const local = tc(e.args[i - 1]) || tc(e.args[i + 1])
          out.push({ kind: 'wire', path: [ports[i].inPort, ports[i].outPort], role: 'rung', state: 'inert', act: fold, flow: flowFor(ctx.em, leader, local) })
        })
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

  const rungs: { node: IRExpr; m: Measured }[] = []
  const gapLabel: (string | null)[] = [] // gapLabel[k] = inert between rung k and k+1
  let pending: string[] = []
  for (const it of e.args.slice(start)) {
    if (it.$type === 'InertE') {
      pending.push(it.text)
    } else {
      if (rungs.length >= 1) gapLabel.push(pending.length ? pending.join(' ') : null)
      pending = []
      rungs.push({ node: it, m: measure(it, ctx) })
    }
  }
  // (a trailing `pending` after the last rung would be a Post; dropped for now)

  const labelW = (k: number) => (gapLabel[k] ? tm.width(gapLabel[k] as string, FONT) + 2 * INERT_PAD : 0)
  const gapH = (k: number) => (gapLabel[k] ? Math.max(GAP_PARALLEL, lineH + 8) : GAP_PARALLEL)
  const colW = Math.max(0, ...rungs.map((r) => r.m.w), ...gapLabel.map((_, k) => labelW(k)))
  const totalW = colW + 2 * BUS_PAD
  const stackH = rungs.reduce((s, r) => s + r.m.h, 0) + gapLabel.reduce((s, _, k) => s + gapH(k), 0)
  const band = head ? lineH + 12 : 0
  const h = stackH + 2 * band

  return {
    w: totalW,
    h,
    state: 'inert',
    emit(ox, oy, out) {
      const leftX = ox // the OR's in-port: a single point all rungs fan from
      const rightX = ox + totalW // the out-port, where they converge again
      const top = oy + band
      const centerY = top + stackH / 2
      const groupIn: Pt = { x: leftX, y: centerY }
      const groupOut: Pt = { x: rightX, y: centerY }
      let y = top
      // the leader reaches the fan iff the OR's input is energized (DESIGN §20)
      const leaderIn = !!ctx.em?.get(e.id)?.inE
      rungs.forEach(({ node, m }, i) => {
        if (i > 0) {
          const k = i - 1
          const gh = gapH(k)
          if (gapLabel[k])
            out.push({ kind: 'text', at: { x: ox + totalW / 2, y: y + gh / 2 + 4 }, text: gapLabel[k] as string, anchor: 'middle', state: 'inert', tag: 'connective' })
          y += gh
        }
        const cx = ox + BUS_PAD + (colW - m.w) / 2 // <-- centered horizontally
        const p = m.emit(cx, y, out)
        // organic Bézier fan: group port -> rung port, and back (DESIGN §17a).
        // Clicking a fan curve folds this OR (DESIGN §19).
        const fold = { t: 'fold', id: e.id } as const
        const local = trueConducts(ctx.values, node) // this branch is a closed contact
        const leaderOut = !!ctx.em?.get(node.id)?.outE
        const inCurve = hCurve(groupIn, p.inPort, m.state)
        inCurve.act = fold
        inCurve.flow = flowFor(ctx.em, leaderIn, local)
        out.push(inCurve)
        const outCurve = hCurve(p.outPort, groupOut, m.state)
        outCurve.act = fold
        outCurve.flow = flowFor(ctx.em, leaderOut, local)
        out.push(outCurve)
        if (m.state === 'eliminable' || m.state === 'dead') {
          const mid = cubicMid(inCurve)
          out.push({ kind: 'glyph', at: mid, role: 'open-contact' }) // current can't pass
        }
        y += m.h
      })
      if (head) out.push({ kind: 'text', at: { x: ox + totalW / 2, y: oy + band / 2 + 2 }, text: head, anchor: 'middle', state: 'inert', tag: 'heading', size: 12.5, id: e.id, act: { t: 'fold', id: e.id } })
      return { inPort: groupIn, outPort: groupOut }
    },
  }
}

export function layout(fn: FunDecl, vs: ViewSpec, tm: TextMetrics): Scene {
  const prims: ScenePrim[] = []
  const values = new Map<NodeId, UBoolValue>()
  nodeValue(fn.body, vs.valuation, values)
  const em = vs.showCurrent ? new Map<NodeId, Energ>() : null
  if (em) energize(fn.body, true, values, em)
  const m = measure(fn.body, { vs, tm, values, em })
  const ox = MARGIN + LEAD
  const oy = MARGIN
  const { inPort, outPort } = m.emit(ox, oy, prims)

  prims.push({ kind: 'wire', path: [{ x: MARGIN, y: inPort.y }, inPort], role: 'rail', state: 'inert', flow: em ? 'closed' : undefined })
  prims.push({ kind: 'wire', path: [outPort, { x: ox + m.w + LEAD, y: outPort.y }], role: 'rail', state: 'inert', flow: flowFor(em, !!em?.get(fn.body.id)?.outE, trueConducts(values, fn.body)) })
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
