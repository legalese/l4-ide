import type { ExportedFunctionInfo, RemoteFunctionSchema } from 'jl4-client-rpc'

/**
 * The Deploy panel's breaking-change check: the client-side copy of
 * jl4-service's compatibility gate (`jl4-service/src/Compatibility.hs`),
 * which decides whether a PUT over a deployment is applied. It is a module
 * of its own so that it can be tested (`breaking-changes.test.ts`), and it
 * applies the gate's rules in the gate's directions, so that the warning
 * before a redeploy says what the service will say. The messages are worded
 * as the gate's are, with identifiers marked for the panel.
 */

/** A segment of a breaking change message: either plain text or an identifier. */
export type ChangeSegment = { text: string; ident?: boolean }
export type BreakingChange = ChangeSegment[]

function ident(name: string): ChangeSegment {
  const needsBackticks = /\s/.test(name)
  return { text: needsBackticks ? `\`${name}\`` : name, ident: true }
}
function txt(text: string): ChangeSegment {
  return { text }
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
  /** The forms of a type with a constructor that carries data and one that
   *  carries none: its names (a string) and its tagged constructors (an
   *  object). A node with a `oneOf` has no `type` of its own. */
  oneOf?: SchemaNode[]
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

/** An object whose keys are alternatives, of which a value holds exactly
 *  one: the tagged constructors of a type with a constructor that carries
 *  data, or the two sides of an EITHER. Their schema has no `required`,
 *  which a record's always has (`isAlternatives` in the gate). */
function isAlternatives(p: SchemaNode): boolean {
  return p.properties !== undefined && p.required === undefined
}

/** A record's object: its schema always has a `required`. */
function isRecordObject(p: SchemaNode): boolean {
  return p.properties !== undefined && p.required !== undefined
}

/** The forms a node's value takes, by their type: its `oneOf`'s members, or
 *  itself. */
function formsOf(p: SchemaNode): [string, SchemaNode][] {
  return p.oneOf
    ? p.oneOf.map((m): [string, SchemaNode] => [m.type ?? '', m])
    : [[p.type ?? '', p]]
}

function formName(ty: string): string {
  return (/^[aeiou]/.test(ty) ? 'an ' : 'a ') + ty
}

function objectForm(p: SchemaNode): string {
  const keys = Object.keys(p.properties ?? {})
    .sort()
    .join(', ')
  return isAlternatives(p)
    ? `an object keyed by its constructor (${keys})`
    : `an object of its fields (${keys})`
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

  // A oneOf: the forms are matched by their type. One the new interface
  // removes is breaking in both directions; one it adds is breaking on a
  // result only (MULLET; STOWAWAY for results). Two that match are compared
  // as any node is.
  if (remote.oneOf || local.oneOf) {
    const localForms = formsOf(local)
    const remoteForms = formsOf(remote)
    for (const [ty, rf] of remoteForms) {
      const match = localForms.find(([lty]) => lty === ty)
      if (!match) {
        changes.push([
          ...here(),
          txt(
            ` no longer ${dir === 'in' ? 'accepts' : 'returns'} ${formName(ty)}`
          ),
        ])
      } else {
        diffNode(fn, kind, loc, rf, match[1], dir, changes)
      }
    }
    if (dir === 'out') {
      for (const [ty] of localForms) {
        if (!remoteForms.some(([rty]) => rty === ty))
          changes.push([...here(), txt(` may now return ${formName(ty)}`)])
      }
    }
    return
  }

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

  // A record's object on one side and an object keyed by constructor on the
  // other, as when a type whose only constructor is named like it gains a
  // second: the form changed. Report it, and stop here.
  if (
    (isRecordObject(remote) && isAlternatives(local)) ||
    (isAlternatives(remote) && isRecordObject(local))
  ) {
    changes.push([
      ...here(),
      txt(` form changed from ${objectForm(remote)} to ${objectForm(local)}`),
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

  // The keys of an object of alternatives are constructors, of which a value
  // holds one, so they are compared as an enum's names are: one added to a
  // result, or removed from an input, is breaking, and one on both sides is
  // compared as any node (STOWAWAY carried to the constructors).
  if (
    remote.properties &&
    local.properties &&
    isAlternatives(remote) &&
    isAlternatives(local)
  ) {
    const rAlts = remote.properties
    const lAlts = local.properties
    const dropped = Object.keys(rAlts)
      .filter((k) => !(k in lAlts))
      .sort()
    const added = Object.keys(lAlts)
      .filter((k) => !(k in rAlts))
      .sort()
    if (dir === 'in' && dropped.length)
      changes.push([
        ...here(),
        txt(' no longer accepts '),
        ident(dropped.join(', ')),
      ])
    if (dir === 'out' && added.length)
      changes.push([
        ...here(),
        txt(' may now return new values '),
        ident(added.join(', ')),
      ])
    for (const key of Object.keys(rAlts).sort()) {
      if (!(key in lAlts)) continue
      const childLoc = loc ? `${loc}.${key}` : key
      diffNode(fn, kind, childLoc, rAlts[key], lAlts[key], dir, changes)
    }
  } else if (remote.properties || local.properties) {
    // Object properties.
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
    const isDeontic =
      (remote.returnType ?? '').startsWith('DEONTIC') ||
      (local.returnType ?? '').startsWith('DEONTIC')
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
