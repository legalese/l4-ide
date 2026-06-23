/**
 * P0 demo: render Penal Code s 415 second limb (DESIGN §15.4) through ladder-core.
 *
 *   And[ Or[by-deceiving, dishonest-concealment]   "there is a deception"
 *      , intentionally, causes-harm
 *      , Or[body, mind, reputation, property]       "harm to…" ]
 *
 * Emits three SVGs into demo/out/:
 *   s415-court.svg      — court's reading: concealment rung LIVE
 *   s415-applicants.svg — applicants' reading: concealment rung ELIMINABLE (dead)
 *   s415-diff.svg       — the two stacked: the surplusage argument, drawn
 *   s415-folded.svg     — the harm group folded -> placeholder, to prove re-centering
 *
 * Run: cd ts-shared/ladder-core && npx tsx demo/s415.ts
 */
import { mkdirSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { layout, estimateMetrics, sceneToSvg, defaultViewSpec } from '../src/index.js'
import type {
  FunDecl,
  IRExpr,
  Leaf,
  Inert,
  And,
  Or,
  State,
  ScenePrim,
  Scene,
  NodeId,
} from '../src/index.js'

let counter = 0
const nid = () => ++counter
const leaf = (label: string): Leaf => ({ $type: 'UBoolVar', id: nid(), label, atomId: label })
const inert = (text: string, context: 'InertAnd' | 'InertOr'): Inert => ({ $type: 'InertE', id: nid(), text, context })
const and = (args: IRExpr[]): And => ({ $type: 'And', id: nid(), args })
const or = (args: IRExpr[]): Or => ({ $type: 'Or', id: nid(), args })

// ---- build the tree in inert style: operative atoms boxed, prose inert/unboxed ----
const byDeceiving = leaf('by deceiving')
const concealment = leaf('dishonest concealment')
// leading inert => HEADING above the OR stack
const deception = or([inert('there is a deception (Expl. 1)', 'InertOr'), byDeceiving, concealment])
const intentionally = leaf('intentionally')
const causesHarm = leaf('causes harm')
const harm = or([leaf('body'), leaf('mind'), leaf('reputation'), leaf('property')])
// inert nodes in the series ride the wire; "to any person in" lands to the LEFT of
// the harm stack (the `text … (stack)` pattern) — no heading needed on `harm`.
const second = and([
  deception,
  intentionally,
  inert('induces an act or omission that', 'InertAnd'),
  causesHarm,
  inert('to any person in', 'InertAnd'),
  harm,
])
const fn: FunDecl = { id: nid(), name: 'is said to cheat (second limb)', params: [], body: second }

// ---- collect every leaf id so we can mark them all live ----
function leafIds(e: IRExpr, acc: NodeId[] = []): NodeId[] {
  if (e.$type === 'And' || e.$type === 'Or') e.args.forEach((a) => leafIds(a, acc))
  else if (e.$type === 'Not') leafIds(e.negand, acc)
  else if (e.$type !== 'InertE') acc.push(e.id) // inert carries no value/state
  return acc
}
const allLive = new Map<NodeId, State>(leafIds(second).map((id) => [id, 'live']))

const courtStates = new Map(allLive) // every rung live
const applicantStates = new Map(allLive)
applicantStates.set(concealment.id, 'eliminable') // the otiose rung

const tm = estimateMetrics
const sceneCourt = layout(fn, defaultViewSpec({ states: courtStates }), tm)
const sceneCourtAbove = layout(fn, defaultViewSpec({ states: courtStates, connectiveStyle: 'above-wire' }), tm)
const sceneCourtBelow = layout(fn, defaultViewSpec({ states: courtStates, connectiveStyle: 'below-wire' }), tm)
const sceneAppl = layout(fn, defaultViewSpec({ states: applicantStates }), tm)
// fold the deception group -> its leading inert becomes the placeholder label
const sceneFolded = layout(
  fn,
  defaultViewSpec({ states: courtStates, foldSet: new Set([deception.id]) }),
  tm
)

// ---- compose the two readings into one diff figure ----
function shift(prims: ScenePrim[], dx: number, dy: number): ScenePrim[] {
  return prims.map((p) => {
    if (p.kind === 'box') return { ...p, rect: { ...p.rect, x: p.rect.x + dx, y: p.rect.y + dy } }
    if (p.kind === 'wire') return { ...p, path: p.path.map((pt) => ({ x: pt.x + dx, y: pt.y + dy })) }
    return { ...p, at: { x: p.at.x + dx, y: p.at.y + dy } }
  })
}

function diff(a: Scene, b: Scene): Scene {
  const W = Math.max(a.size.w, b.size.w)
  const titleH = 44
  const gap = 28
  const prims: ScenePrim[] = []
  prims.push({ kind: 'text', at: { x: W / 2, y: 30 }, text: 'Penal Code s 415, second limb (no property) — surplusage as a dead rung', anchor: 'middle', state: 'inert', tag: 'title', size: 16 })
  let y = 44
  prims.push({ kind: 'text', at: { x: 44, y: y + 24 }, text: "The court's reading (Fourth Interpretation)", anchor: 'start', state: 'inert', tag: 'title', size: 15 })
  prims.push(...shift(a.prims, 0, y + titleH))
  const yB = y + titleH + a.size.h + gap
  prims.push({ kind: 'wire', path: [{ x: 44, y: yB - gap / 2 }, { x: W - 44, y: yB - gap / 2 }], role: 'stub', state: 'eliminable' })
  prims.push({ kind: 'text', at: { x: 44, y: yB + 24 }, text: "The applicants' reading (Second Interpretation)", anchor: 'start', state: 'inert', tag: 'title', size: 15 })
  prims.push(...shift(b.prims, 0, yB + titleH))
  const yCap = yB + titleH + b.size.h + 8
  prims.push({ kind: 'text', at: { x: W / 2, y: yCap + 18 }, text: 'The "dishonest concealment" rung can never carry current ⇒ a don\'t-care ⇒ the minimiser deletes it ⇒ Explanation 1 is otiose.  (GD [30], [32])', anchor: 'middle', state: 'inert', tag: 'note', size: 12.5 })
  return { size: { w: W, h: yCap + 36 }, prims }
}

const outDir = fileURLToPath(new URL('./out/', import.meta.url))
mkdirSync(outDir, { recursive: true })
const write = (name: string, scene: Scene) => {
  writeFileSync(outDir + name, sceneToSvg(scene))
  console.log(`wrote ${name}  (${scene.size.w.toFixed(0)}x${scene.size.h.toFixed(0)})`)
}

write('s415-court.svg', sceneCourt)
write('s415-court-onwire.svg', sceneCourt)
write('s415-court-abovewire.svg', sceneCourtAbove)
write('s415-court-belowwire.svg', sceneCourtBelow)
write('s415-applicants.svg', sceneAppl)
write('s415-diff.svg', diff(sceneCourt, sceneAppl))
write('s415-folded.svg', sceneFolded)
