import type {
  FunDecl,
  IRExpr,
  Leaf,
  NodeId,
  UBoolValue,
} from '@repo/ladder-core'
import {
  parseLeafLabel,
  readAt,
  triOf,
  type FieldPath,
  type LeafBinding,
} from './leaf-field'

/** Every leaf of a decoded ladder, with its binding parsed once. */
export interface BoundLeaf {
  readonly id: NodeId
  readonly label: string
  readonly unique?: number
  readonly binding: LeafBinding
}

function walk(e: IRExpr, out: Leaf[]): void {
  switch (e.$type) {
    case 'UBoolVar':
    case 'App':
    case 'TrueE':
    case 'FalseE':
      out.push(e)
      return
    case 'InertE':
      return
    case 'And':
    case 'Or':
      for (const a of e.args) walk(a, out)
      return
    case 'Not':
      walk(e.negand, out)
      return
    case 'Implies':
      walk(e.scope, out)
      walk(e.requirement, out)
      return
  }
}

export function boundLeaves(fn: FunDecl, param: string): BoundLeaf[] {
  const leaves: Leaf[] = []
  walk(fn.body, leaves)
  return leaves
    .filter((l) => l.$type === 'UBoolVar' || l.$type === 'App')
    .map((l) => ({
      id: l.id,
      label: l.label,
      unique: l.unique,
      binding: parseLeafLabel(l.label, param),
    }))
}

/** The distinct facts-record paths a ladder reads — the charge's ELEMENTS. */
export function elementPaths(fn: FunDecl, param: string): FieldPath[] {
  const seen = new Set<string>()
  const out: FieldPath[] = []
  for (const l of boundLeaves(fn, param)) {
    if (l.binding.kind !== 'projection') continue
    const key = l.binding.path.join('/')
    if (seen.has(key)) continue
    seen.add(key)
    out.push(l.binding.path)
  }
  return out
}

/**
 * The positional valuation a ladder wants, read off the facts record. A call
 * leaf (`cheats f`) takes its value from `calls` — the verdict of that rule's
 * own ladder, computed by the caller with `verdictFor` — or stays Unknown.
 */
export function valuationFor(
  fn: FunDecl,
  param: string,
  facts: Record<string, unknown>,
  calls: ReadonlyMap<string, UBoolValue> = new Map(),
  prefix: FieldPath = []
): Map<NodeId, UBoolValue> {
  const out = new Map<NodeId, UBoolValue>()
  for (const l of boundLeaves(fn, param)) {
    if (l.binding.kind === 'projection') {
      out.set(l.id, triOf(readAt(facts, [...prefix, ...l.binding.path])))
    } else if (l.binding.kind === 'call') {
      const v = calls.get(l.binding.fn)
      if (v) out.set(l.id, v)
    }
  }
  return out
}

/** Node id → field path (under `prefix`), for routing a click. */
export function pathByNode(
  fn: FunDecl,
  param: string,
  prefix: FieldPath = []
): Map<NodeId, FieldPath> {
  const out = new Map<NodeId, FieldPath>()
  for (const l of boundLeaves(fn, param))
    if (l.binding.kind === 'projection')
      out.set(l.id, [...prefix, ...l.binding.path])
  return out
}

/** Rule name → the record path it is called on, from every call leaf of a ladder. */
export function callPrefixes(
  fn: FunDecl,
  param: string
): Map<string, FieldPath> {
  const out = new Map<string, FieldPath>()
  for (const l of boundLeaves(fn, param))
    if (l.binding.kind === 'call') out.set(l.binding.fn, l.binding.argPath)
  return out
}
