/**
 * The deploy sidebar's client-side compatibility check, as pure functions.
 *
 * It mirrors jl4-service/src/Compatibility.hs ("so both surfaces agree"): the
 * sidebar shows the result BEFORE a redeploy is sent, the service enforces it
 * on a guarded update. It lives here, apart from the Svelte page, so that a
 * test can import it and run the cases the service check runs
 * (jl4-service/test/fixtures/default-change-cases.json).
 *
 * No Svelte, no DOM, no VS Code API.
 */
import {
  takesDeonticEnvelope,
  type ExportedFunctionInfo,
  type RemoteFunctionSchema,
} from 'jl4-client-rpc'

/** A segment of a breaking change message: either plain text or an identifier. */
export type ChangeSegment = {
  /** What the page shows: an identifier containing spaces is in backticks. */
  text: string
  ident?: boolean
  /** The identifier as it is written in the schema, without decoration; the
   *  service's message for the same change spells it this way. */
  plain?: string
}
export type BreakingChange = ChangeSegment[]

export function ident(name: string): ChangeSegment {
  const needsBackticks = /\s/.test(name)
  return {
    text: needsBackticks ? `\`${name}\`` : name,
    ident: true,
    plain: name,
  }
}
function txt(text: string): ChangeSegment {
  return { text }
}

/** A change as the service words it: names undecorated, one string. The
 *  page itself renders the segments, so that names are set in monospace. */
export function changeToPlainText(change: BreakingChange): string {
  return change.map((seg) => seg.plain ?? seg.text).join('')
}

/** A node in a parameter / return-value JSON schema (structurally a
 *  superset of both `FunctionParameters` and `FunctionParameter`). */
export type SchemaNode = {
  type?: string
  format?: string
  enum?: string[]
  properties?: Record<string, SchemaNode>
  required?: string[]
  items?: SchemaNode
}

/** Direction of compatibility: `in` = request parameter (caller sends),
 *  `out` = return value (caller consumes). The two are mirror images —
 *  e.g. a *new optional input* is safe, but a *removed output field* is
 *  not (and vice-versa). */
type Dir = 'in' | 'out'

function subject(
  fn: string,
  kind: 'parameter' | 'return value',
  loc: string
): ChangeSegment[] {
  return loc
    ? [ident(fn), txt(` ${kind} `), ident(loc)]
    : [ident(fn), txt(` ${kind}`)]
}

/**
 * Recursively diff one schema node (old `remote` vs new `local`),
 * appending a message for every backwards-incompatible change.
 * Recurses through object `properties` and array `items` so nested
 * record/list parameters are compared at every depth.
 */
function diffNode(
  fn: string,
  kind: 'parameter' | 'return value',
  loc: string,
  remote: SchemaNode,
  local: SchemaNode,
  dir: Dir,
  changes: BreakingChange[]
) {
  const here = () => subject(fn, kind, loc)

  // Type change — once the type differs, deeper structural diffing
  // would just be noise, so report and stop descending this branch.
  if (remote.type && local.type && remote.type !== local.type) {
    changes.push([
      ...here(),
      txt(' type changed from '),
      ident(remote.type),
      txt(' to '),
      ident(local.type),
    ])
    return
  }

  // Format change (e.g. plain string → date) is a contract change.
  const rFmt = remote.format ?? ''
  const lFmt = local.format ?? ''
  if (rFmt !== lFmt && (rFmt || lFmt)) {
    changes.push([
      ...here(),
      txt(' format changed from '),
      ident(rFmt || 'none'),
      txt(' to '),
      ident(lFmt || 'none'),
    ])
  }

  // Enum (allowed value set).
  const rEnum = remote.enum ?? []
  const lEnum = local.enum ?? []
  if (rEnum.length && lEnum.length) {
    if (dir === 'in') {
      const dropped = rEnum.filter((v) => !lEnum.includes(v))
      if (dropped.length)
        changes.push([
          ...here(),
          txt(' no longer accepts '),
          ident(dropped.join(', ')),
        ])
    } else {
      const added = lEnum.filter((v) => !rEnum.includes(v))
      if (added.length)
        changes.push([
          ...here(),
          txt(' may now return new values '),
          ident(added.join(', ')),
        ])
    }
  } else if (dir === 'in' && !rEnum.length && lEnum.length) {
    // Previously any value, now restricted — rejects formerly-valid input.
    changes.push([
      ...here(),
      txt(' is now restricted to a fixed set of values'),
    ])
  } else if (dir === 'out' && rEnum.length && !lEnum.length) {
    // Previously a fixed set, now unbounded — exhaustive consumers break.
    changes.push([
      ...here(),
      txt(' is no longer limited to a fixed set of values'),
    ])
  }

  // Object properties.
  if (remote.properties || local.properties) {
    const rProps = remote.properties ?? {}
    const lProps = local.properties ?? {}
    const rReq = new Set(remote.required ?? [])
    const lReq = new Set(local.required ?? [])

    for (const key of Object.keys(rProps)) {
      const childLoc = loc ? `${loc}.${key}` : key
      if (!(key in lProps)) {
        changes.push([
          ...subject(fn, kind, childLoc),
          dir === 'in' ? txt(' removed') : txt(' no longer returned'),
        ])
        continue
      }
      // Required-ness tightening.
      if (dir === 'in' && lReq.has(key) && !rReq.has(key)) {
        changes.push([...subject(fn, kind, childLoc), txt(' is now required')])
      }
      if (dir === 'out' && rReq.has(key) && !lReq.has(key)) {
        changes.push([
          ...subject(fn, kind, childLoc),
          txt(' may now be absent from the result'),
        ])
      }
      diffNode(fn, kind, childLoc, rProps[key], lProps[key], dir, changes)
    }

    for (const key of Object.keys(lProps)) {
      if (key in rProps) continue
      const childLoc = loc ? `${loc}.${key}` : key
      // New optional input / new output field → compatible. Only a new
      // *required* input breaks existing callers.
      if (dir === 'in' && lReq.has(key)) {
        changes.push([
          ident(fn),
          txt(' has a new required parameter '),
          ident(childLoc),
        ])
      }
    }
  }

  // Array element schema.
  if (remote.items || local.items) {
    diffNode(
      fn,
      kind,
      loc ? `${loc}[]` : '[]',
      remote.items ?? {},
      local.items ?? {},
      dir,
      changes
    )
  }
}

/**
 * Remove the DEONTIC simulation-envelope keys ('startTime', 'events')
 * from a parameter schema's top-level properties/required. These keys
 * are present in jl4-service's deployed schema but not in the LSP's
 * local schema, so they would otherwise drive false-positive diffs.
 * Returns the schema unchanged when not deontic or when no properties
 * are present.
 */
function stripDeonticEnvelope(
  schema: SchemaNode | undefined,
  isDeontic: boolean
): SchemaNode | undefined {
  if (!isDeontic || !schema || !schema.properties) return schema
  const props = { ...schema.properties }
  delete props.startTime
  delete props.events
  const required = (schema.required ?? []).filter(
    (k) => k !== 'startTime' && k !== 'events'
  )
  return { ...schema, properties: props, required }
}

/**
 * Detect backwards-incompatible changes between the local functions
 * and the currently-deployed interface (fetched per-function from
 * jl4-service). New functions and new optional parameters are safe;
 * removals, renames, type/format changes, required-ness tightening and
 * enum narrowing are breaking — checked recursively at every depth.
 */
export function detectBreakingChanges(
  localFns: ExportedFunctionInfo[],
  remoteFns: RemoteFunctionSchema[]
): BreakingChange[] {
  const changes: BreakingChange[] = []
  const remoteByName = new Map(remoteFns.map((f) => [f.name, f]))

  for (const local of localFns) {
    const remote = remoteByName.get(local.name)
    if (!remote) continue // new function — not breaking

    // Return type (display name, e.g. BOOLEAN / DEONTIC OF P, A). A
    // change here also covers deontic ⇄ non-deontic (different request
    // envelope).
    const returnTypeChanged =
      !!remote.returnType &&
      !!local.returnType &&
      remote.returnType !== local.returnType
    if (returnTypeChanged) {
      changes.push([
        ident(local.name),
        txt(' return type changed from '),
        ident(remote.returnType as string),
        txt(' to '),
        ident(local.returnType),
      ])
    }

    // For DEONTIC functions, jl4-service injects 'startTime' and 'events'
    // into the deployed parameter schema (the simulation envelope), but
    // the LSP-derived local schema does not. Strip them on both sides
    // before diffing so the envelope's presence/absence doesn't show up
    // as a spurious "parameter removed" breaking change.
    const isDeontic = takesDeonticEnvelope(remote, local)
    const remoteParams = stripDeonticEnvelope(
      remote.parameters as unknown as SchemaNode,
      isDeontic
    )
    const localParams = stripDeonticEnvelope(
      local.parameters as unknown as SchemaNode,
      isDeontic
    )

    // Recursive parameter (input) diff.
    diffNode(
      local.name,
      'parameter',
      '',
      remoteParams ?? {},
      localParams ?? {},
      'in',
      changes
    )

    // Recursive return-value (output) diff — mirror image of inputs:
    // a removed/renamed output field or a narrowed output type breaks
    // existing consumers. Only meaningful when the return type itself
    // is unchanged and both sides expose a structured schema.
    if (!returnTypeChanged && remote.returnSchema && local.returnSchema) {
      diffNode(
        local.name,
        'return value',
        '',
        remote.returnSchema as unknown as SchemaNode,
        local.returnSchema as unknown as SchemaNode,
        'out',
        changes
      )
    }
  }

  // Removed functions.
  for (const remote of remoteFns) {
    if (!localFns.find((f) => f.name === remote.name)) {
      changes.push([txt('rule '), ident(remote.name), txt(' removed')])
    }
  }

  return changes
}
