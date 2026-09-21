import {
  forceCollide,
  forceLink,
  forceSimulation,
  forceX,
  forceY,
  type SimulationLinkDatum,
  type SimulationNodeDatum,
} from 'd3-force'
import type { DagLayout, LaidOutNode } from './graph'

/**
 * A dot-like layout for the evidence graph: four ranks (charge, elements,
 * facts, sources) held in columns by a strong horizontal force, and nodes
 * spread within their rank by the links that join them and a collision
 * radius sized to their label — so a fact sits beside the elements it
 * supports and a source beside its facts, instead of every column stacking
 * from the top. The simulation is run to rest synchronously, so the picture
 * is deterministic for a given graph and never animates.
 */
export interface PlacedNode extends LaidOutNode {
  x: number
  y: number
  w: number
  h: number
}
export interface PlacedEdge {
  readonly from: PlacedNode
  readonly to: PlacedNode
}
export interface ForceLayout {
  readonly nodes: readonly PlacedNode[]
  readonly edges: readonly PlacedEdge[]
  readonly width: number
  readonly height: number
}

type SimNode = SimulationNodeDatum & {
  id: string
  col: number
  w: number
  h: number
}
type SimLink = SimulationLinkDatum<SimNode>

const COL_W = 190
const PAD = 16
const BOX_H = 36
const CHAR_W = 6.4
/** Minimum centre-to-centre spacing within a rank: the box plus breathing room. */
const MIN_GAP = BOX_H + 10

/** Label box width, bounded so a long fact does not push the column apart. */
function boxWidth(n: LaidOutNode): number {
  const longest = Math.max(n.label.length, (n.sub ?? '').length)
  return Math.max(72, Math.min(COL_W - 24, 16 + longest * CHAR_W))
}

export function forceLayoutDag(dag: DagLayout): ForceLayout {
  const perCol = [0, 0, 0, 0]
  for (const n of dag.nodes) perCol[n.col]++
  const rows = Math.max(1, ...perCol)
  // Room for the tallest rank to stand apart; the drawing is cropped to the
  // nodes afterwards, so a generous canvas costs nothing.
  const canvas = Math.max(200, PAD * 2 + rows * MIN_GAP)
  const width = COL_W * 4 + PAD * 2
  const colX = (c: number) => PAD + c * COL_W + COL_W / 2

  const sim: SimNode[] = dag.nodes.map((n) => {
    const k = perCol[n.col]
    return {
      id: n.id,
      col: n.col,
      w: boxWidth(n),
      h: BOX_H,
      x: colX(n.col),
      y:
        k === 1
          ? canvas / 2
          : PAD + BOX_H / 2 + (n.row * (canvas - PAD * 2 - BOX_H)) / (k - 1),
    }
  })
  const byId = new Map(sim.map((n) => [n.id, n]))
  const links: SimLink[] = dag.edges
    .filter((e) => byId.has(e.from) && byId.has(e.to))
    .map((e) => ({ source: byId.get(e.from)!, target: byId.get(e.to)! }))

  const simulation = forceSimulation<SimNode>(sim)
    .force('x', forceX<SimNode>((d) => colX(d.col)).strength(1))
    .force('y', forceY<SimNode>(canvas / 2).strength(0.02))
    .force(
      'link',
      forceLink<SimNode, SimLink>(links).distance(COL_W).strength(0.4)
    )
    .force('collide', forceCollide<SimNode>(MIN_GAP / 2).strength(1))
    .stop()
  for (let i = 0; i < 300; i++) simulation.tick()

  // The simulation gets each node NEAR its neighbours; this pass guarantees
  // the rest. Within a column, in the order the force settled them, push
  // every node at least MIN_GAP from the one above, then recentre the whole
  // column on its own mean so it does not drift downwards.
  for (let c = 0; c < 4; c++) {
    const col = sim
      .filter((n) => n.col === c)
      .sort((a, b) => (a.y ?? 0) - (b.y ?? 0))
    if (col.length < 2) continue
    const before = col.reduce((t, n) => t + (n.y ?? 0), 0) / col.length
    for (let i = 1; i < col.length; i++) {
      const min = (col[i - 1].y ?? 0) + MIN_GAP
      if ((col[i].y ?? 0) < min) col[i].y = min
    }
    const after = col.reduce((t, n) => t + (n.y ?? 0), 0) / col.length
    const shift = before - after
    for (const n of col) n.y = (n.y ?? 0) + shift
  }

  // Crop to the nodes: the canvas was sized for the worst case, and an
  // uncropped drawing opens with a band of empty space above the graph.
  const top = Math.min(...sim.map((n) => (n.y ?? 0) - n.h / 2))
  const offset = PAD - top
  const meta = new Map(dag.nodes.map((n) => [n.id, n]))
  const placed = new Map<string, PlacedNode>()
  let bottom = 0
  for (const n of sim) {
    const y = (n.y ?? 0) + offset
    bottom = Math.max(bottom, y + n.h / 2)
    placed.set(n.id, { ...meta.get(n.id)!, x: colX(n.col), y, w: n.w, h: n.h })
  }
  const nodes = [...placed.values()]
  const edges = dag.edges
    .filter((e) => placed.has(e.from) && placed.has(e.to))
    .map((e) => ({ from: placed.get(e.from)!, to: placed.get(e.to)! }))
  return { nodes, edges, width, height: Math.max(120, bottom + PAD) }
}
