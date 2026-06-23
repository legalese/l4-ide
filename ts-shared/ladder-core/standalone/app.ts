/**
 * Standalone interactive ladder (DESIGN target C). Self-contained page: builds the
 * s415 second-limb tree, renders it through the PURE core (layout -> Scene IR ->
 * SVG), and drives fold/expand + reading + connectiveStyle live. Every interaction
 * just mutates a ViewSpec and re-runs the core — proving live re-centring and the
 * ViewSpec round-trip — with a FLIP animation so boxes glide to their new homes.
 *
 * Bundled to dist/app.js by build.sh (esbuild). No framework, no workspace deps.
 */
import { layout, sceneToSvg, estimateMetrics, defaultViewSpec } from '../src/index.js'
import type {
  FunDecl,
  IRExpr,
  Leaf,
  Inert,
  And,
  Or,
  State,
  NodeId,
  ConnectiveStyle,
  Scene,
} from '../src/index.js'

/* ----------------------------------------------------- s415 fixture (inert style) */
let counter = 0
const nid = () => ++counter
const leaf = (label: string): Leaf => ({ $type: 'UBoolVar', id: nid(), label, atomId: label })
const inert = (text: string, context: 'InertAnd' | 'InertOr'): Inert => ({ $type: 'InertE', id: nid(), text, context })
const and = (args: IRExpr[]): And => ({ $type: 'And', id: nid(), args })
const or = (args: IRExpr[]): Or => ({ $type: 'Or', id: nid(), args })

const byDeceiving = leaf('by deceiving')
const concealment = leaf('dishonest concealment')
const deception = or([inert('there is a deception (Expl. 1)', 'InertOr'), byDeceiving, inert('or', 'InertOr'), concealment])
const harm = or([leaf('body'), leaf('mind'), leaf('reputation'), inert('or', 'InertOr'), leaf('property')])
const second = and([
  deception,
  leaf('intentionally'),
  inert('induces an act or omission that', 'InertAnd'),
  leaf('causes harm'),
  inert('to any person in', 'InertAnd'),
  harm,
])
const fn: FunDecl = { id: nid(), name: 'is said to cheat (second limb)', params: [], body: second }

function leafIds(e: IRExpr, acc: NodeId[] = []): NodeId[] {
  if (e.$type === 'And' || e.$type === 'Or') e.args.forEach((a) => leafIds(a, acc))
  else if (e.$type === 'Not') leafIds(e.negand, acc)
  else if (e.$type !== 'InertE') acc.push(e.id)
  return acc
}
const allLive = new Map<NodeId, State>(leafIds(second).map((id) => [id, 'live']))
const courtStates = new Map(allLive)
const applicantStates = new Map(allLive)
applicantStates.set(concealment.id, 'eliminable')

/* ------------------------------------------------------------------------ state */
const foldSet = new Set<NodeId>()
let reading: 'court' | 'applicants' = 'court'
let connective: ConnectiveStyle = 'straddle-wire'
const tm = estimateMetrics
let lastScene: Scene | null = null
const container = document.getElementById('ladder') as HTMLElement

type Pos = { x: number; y: number }
function flipIndex(scene: Scene): Map<string, Pos> {
  const m = new Map<string, Pos>()
  for (const p of scene.prims) {
    if (p.kind === 'box') m.set(`box:${p.id}`, { x: p.rect.x, y: p.rect.y })
    else if (p.kind === 'text' && p.id != null) m.set(`label:${p.id}`, { x: p.at.x, y: p.at.y })
  }
  return m
}

function render(animate: boolean) {
  const vs = defaultViewSpec({
    states: reading === 'court' ? courtStates : applicantStates,
    foldSet,
    connectiveStyle: connective,
  })
  const scene = layout(fn, vs, tm)
  const old = lastScene && animate ? flipIndex(lastScene) : null
  container.innerHTML = sceneToSvg(scene)
  const svg = container.querySelector('svg') as SVGSVGElement
  svg.style.maxWidth = '100%'
  svg.style.height = 'auto'

  // FLIP: invert each surviving node by its user-space delta, then play to 0.
  if (old) {
    const next = flipIndex(scene)
    const play: SVGElement[] = []
    svg.querySelectorAll<SVGElement>('[data-fnid]').forEach((el) => {
      const id = el.getAttribute('data-fnid')!
      const key = `${el.tagName.toLowerCase() === 'rect' ? 'box' : 'label'}:${id}`
      const o = old.get(key)
      const n = next.get(key)
      if (o && n && (o.x !== n.x || o.y !== n.y)) {
        el.style.transition = 'none'
        el.style.transform = `translate(${o.x - n.x}px, ${o.y - n.y}px)`
        play.push(el)
      } else if (!o && n) {
        el.style.transition = 'none'
        el.style.opacity = '0'
        play.push(el)
      }
    })
    const wires = Array.from(svg.querySelectorAll<SVGElement>('.lad-wire'))
    wires.forEach((el) => {
      el.style.transition = 'none'
      el.style.opacity = '0'
    })
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        play.forEach((el) => {
          el.style.transition = 'transform 300ms cubic-bezier(.2,.7,.2,1), opacity 300ms ease'
          el.style.transform = ''
          el.style.opacity = ''
        })
        wires.forEach((el) => {
          el.style.transition = 'opacity 320ms ease'
          el.style.opacity = ''
        })
      })
    )
  }
  lastScene = scene

  // click a heading (to fold) or a folded placeholder (to expand)
  svg.querySelectorAll<SVGElement>('[data-fold]').forEach((el) => {
    el.style.cursor = 'pointer'
    el.addEventListener('click', () => toggleFold(Number(el.getAttribute('data-fold'))))
  })
  syncControls()
}

function setFold(id: NodeId, on: boolean) {
  if (on) foldSet.add(id)
  else foldSet.delete(id)
  render(true)
}
const toggleFold = (id: NodeId) => setFold(id, !foldSet.has(id))

function syncControls() {
  ;(document.getElementById('fold-deception') as HTMLInputElement).checked = foldSet.has(deception.id)
  ;(document.getElementById('fold-harm') as HTMLInputElement).checked = foldSet.has(harm.id)
}

/* --------------------------------------------------------------------- controls */
document.querySelectorAll<HTMLInputElement>('input[name=reading]').forEach((r) =>
  r.addEventListener('change', () => {
    if (r.checked) {
      reading = r.value as 'court' | 'applicants'
      render(true)
    }
  })
)
;(document.getElementById('connective') as HTMLSelectElement).addEventListener('change', (e) => {
  connective = (e.target as HTMLSelectElement).value as ConnectiveStyle
  render(true)
})
;(document.getElementById('fold-deception') as HTMLInputElement).addEventListener('change', (e) =>
  setFold(deception.id, (e.target as HTMLInputElement).checked)
)
;(document.getElementById('fold-harm') as HTMLInputElement).addEventListener('change', (e) =>
  setFold(harm.id, (e.target as HTMLInputElement).checked)
)

render(false)
