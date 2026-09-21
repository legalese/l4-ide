import type { EvidenceGraph, ElementSupport, Fact, Source } from './types'

/** Facts supporting one element of one charge. */
export function factsFor(
  g: EvidenceGraph,
  section: string,
  field: string
): Fact[] {
  const ids = new Set(
    g.support
      .filter((s) => s.section === section && s.field === field)
      .flatMap((s) => s.factIds)
  )
  return g.facts.filter((f) => ids.has(f.id))
}

/** Elements of a charge that rest on NO fact — the interview's next questions. */
export function gaps(
  g: EvidenceGraph,
  section: string,
  fields: readonly string[]
): string[] {
  return fields.filter((f) => factsFor(g, section, f).length === 0)
}

/** Sources a fact rests on. */
export function sourcesFor(g: EvidenceGraph, fact: Fact): Source[] {
  const ids = new Set(fact.sourceIds)
  return g.sources.filter((s) => ids.has(s.id))
}

/** Add or replace a support edge (charge element → facts). */
export function support(g: EvidenceGraph, edge: ElementSupport): EvidenceGraph {
  const rest = g.support.filter(
    (s) => !(s.section === edge.section && s.field === edge.field)
  )
  return { ...g, support: [...rest, edge] }
}

export function addFact(g: EvidenceGraph, fact: Fact): EvidenceGraph {
  return { ...g, facts: [...g.facts.filter((f) => f.id !== fact.id), fact] }
}

export function addSource(g: EvidenceGraph, src: Source): EvidenceGraph {
  return { ...g, sources: [...g.sources.filter((s) => s.id !== src.id), src] }
}

/**
 * Layout for the columned DAG drawing: four columns (charge, elements, facts,
 * sources), rows in first-mention order, edges between adjacent columns only.
 * Pure — the SVG component only draws what this returns.
 */
export interface LaidOutNode {
  readonly id: string
  readonly col: 0 | 1 | 2 | 3
  readonly row: number
  readonly label: string
  readonly sub?: string
  readonly gap?: boolean
}
export interface LaidOutEdge {
  readonly from: string
  readonly to: string
}
export interface DagLayout {
  readonly nodes: readonly LaidOutNode[]
  readonly edges: readonly LaidOutEdge[]
  readonly rows: number
}

export function layoutDag(
  g: EvidenceGraph,
  section: string,
  title: string,
  fields: readonly string[]
): DagLayout {
  const nodes: LaidOutNode[] = [
    {
      id: `charge:${section}`,
      col: 0,
      row: 0,
      label: `s ${section}`,
      sub: title,
    },
  ]
  const edges: LaidOutEdge[] = []
  const factRow = new Map<string, number>()
  const srcRow = new Map<string, number>()
  fields.forEach((field, i) => {
    const fs = factsFor(g, section, field)
    nodes.push({
      id: `el:${field}`,
      col: 1,
      row: i,
      label: field.split('/').at(-1) ?? field,
      gap: fs.length === 0,
    })
    edges.push({ from: `charge:${section}`, to: `el:${field}` })
    for (const f of fs) {
      if (!factRow.has(f.id)) {
        factRow.set(f.id, factRow.size)
        nodes.push({
          id: `fact:${f.id}`,
          col: 2,
          row: factRow.get(f.id)!,
          label: f.text,
          gap: f.sourceIds.length === 0,
        })
        for (const s of sourcesFor(g, f)) {
          if (!srcRow.has(s.id)) {
            srcRow.set(s.id, srcRow.size)
            nodes.push({
              id: `src:${s.id}`,
              col: 3,
              row: srcRow.get(s.id)!,
              label: s.title,
              sub: s.maker,
            })
          }
          edges.push({ from: `fact:${f.id}`, to: `src:${s.id}` })
        }
      }
      edges.push({ from: `el:${field}`, to: `fact:${f.id}` })
    }
  })
  const rows = Math.max(fields.length, factRow.size, srcRow.size, 1)
  return { nodes, edges, rows }
}
