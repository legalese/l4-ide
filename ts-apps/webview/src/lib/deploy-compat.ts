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
  type DefaultChangeNotice,
  type ExportedFunctionInfo,
  type RemoteFunctionSchema,
} from 'jl4-client-rpc'
import { describeDefault, hasDefault } from './param-defaults'

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
  /** The input's default, when it has one (`null` is a value). */
  default?: unknown
  properties?: Record<string, SchemaNode>
  required?: string[]
  items?: SchemaNode
}

/** Whether `obj` itself has `key`. Not `key in obj`: an input may be named
 *  `toString`, `constructor` or `valueOf`, which every object "has" through
 *  its prototype, and the service's check (a map lookup) sees only the inputs
 *  that are really there. */
function hasOwn(obj: object, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(obj, key)
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
      if (!hasOwn(lProps, key)) {
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
      if (hasOwn(rProps, key)) continue
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

function sameJson(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b)
}

function diffDefaults(
  fn: string,
  loc: string,
  remote: SchemaNode,
  local: SchemaNode,
  notices: DefaultChangeNotice[]
) {
  // A node missing on either side has nothing to compare (a null node is not
  // a schema, and the service's own check never meets one).
  if (!remote || !local) return

  // A node whose type changed is skipped with everything under it, as the
  // service's check does (Compatibility.hs `diffDefault`): the type change is
  // reported as breaking, and the defaults of a retyped input are not
  // comparable.
  if (remote.type && local.type && remote.type !== local.type) return

  // A default on one side only is not a change: adding one makes the input
  // optional, which is compatible; removing one makes it required, which the
  // breaking check already reports; a deployment stored by a service that did
  // not publish defaults carries none, so there is nothing to compare.
  if (
    loc !== '' &&
    hasDefault(remote) &&
    hasDefault(local) &&
    !sameJson(remote.default, local.default)
  ) {
    notices.push({
      kind: 'default-changed',
      function: fn,
      input: loc,
      old: remote.default,
      new: local.default,
    })
  }

  const rProps = remote.properties ?? {}
  const lProps = local.properties ?? {}
  for (const key of Object.keys(lProps).sort()) {
    if (!hasOwn(rProps, key)) continue
    diffDefaults(
      fn,
      loc ? `${loc}.${key}` : key,
      rProps[key]!,
      lProps[key]!,
      notices
    )
  }

  if (remote.items && local.items) {
    diffDefaults(
      fn,
      loc ? `${loc}[]` : '[]',
      remote.items,
      local.items,
      notices
    )
  }
}

/**
 * The inputs whose default (the `default` the service publishes) differs
 * between the currently-deployed interface and the one about to be deployed,
 * for rules and inputs present on both sides. Recurses through record fields
 * and list elements. Not a compatibility check: nothing here can block a
 * deploy; it only says what a caller who leaves an input out will now get.
 */
export function detectDefaultChanges(
  localFns: ExportedFunctionInfo[],
  remoteFns: RemoteFunctionSchema[]
): DefaultChangeNotice[] {
  const notices: DefaultChangeNotice[] = []
  const remoteByName = new Map(remoteFns.map((f) => [f.name, f]))
  for (const local of localFns) {
    const remote = remoteByName.get(local.name)
    if (!remote?.parameters || !local.parameters) continue
    // One rule's schema that cannot be read costs that rule's notices, not the
    // others'. The failure is logged, because the person then sees no default
    // review for that rule and nothing else says why.
    const found: DefaultChangeNotice[] = []
    try {
      diffDefaults(
        local.name,
        '',
        remote.parameters as unknown as SchemaNode,
        local.parameters as unknown as SchemaNode,
        found
      )
      notices.push(...found)
    } catch (err) {
      console.error(
        `The default check failed for rule "${local.name}"; no changed defaults are shown for it.`,
        err
      )
    }
  }
  return notices
}

/** What the deploy review does next, for a redeploy of an existing deployment. */
export type ReviewStep =
  /** Nothing to show: send the deploy. */
  | 'deploy'
  /** Only changed defaults: show them, non-blocking, then deploy. */
  | 'default-review'
  /** At least one incompatible change: the existing warning, which the
   *  person must confirm. Changed defaults are listed there too. */
  | 'breaking-warning'

export interface DeployReview {
  step: ReviewStep
  /** Incompatible changes; the only thing that blocks. */
  breaking: BreakingChange[]
  /** Changed defaults; never block and never count as breaking. */
  notices: DefaultChangeNotice[]
}

/**
 * The review of a redeploy, before it is sent. `remoteFns` is the deployed
 * interface, `null` when there is no such deployment yet (a first deploy has
 * nothing to break and nothing to change).
 */
export function reviewDeploy(
  localFns: ExportedFunctionInfo[],
  remoteFns: RemoteFunctionSchema[] | null,
  checkDefaults: typeof detectDefaultChanges = detectDefaultChanges
): DeployReview {
  if (!remoteFns) return { step: 'deploy', breaking: [], notices: [] }
  const breaking = detectBreakingChanges(localFns, remoteFns)
  // The default check only informs. If it fails, the review goes on without
  // its notices: the breaking list, which blocks, must never be lost to it.
  // The person then sees no default review at all, so the failure is logged.
  let notices: DefaultChangeNotice[] = []
  try {
    notices = checkDefaults(localFns, remoteFns)
  } catch (err) {
    console.error(
      'The default check failed; no changed defaults are shown for this deploy.',
      err
    )
    notices = []
  }
  const step: ReviewStep =
    breaking.length > 0
      ? 'breaking-warning'
      : notices.length > 0
        ? 'default-review'
        : 'deploy'
  return { step, breaking, notices }
}

/**
 * A default as the review lists it, spelled as the rule card spells it: text is
 * quoted, a constructor of an enumerated input is bare (pass the input's
 * allowed values, from {@link noticeEnum}), and NOTHING reads "nothing". A
 * notice carries only the value, not the input's type, so without the allowed
 * values a constructor is quoted like any other text.
 */
export function formatNoticeValue(
  value: unknown,
  enumValues?: string[]
): string {
  return describeDefault({ default: value, enum: enumValues }) ?? ''
}

/**
 * The allowed values of the input a notice is about, when it is an
 * enumeration, read from the schemas of the rules (`input` is the dotted path,
 * `xs[].n` for a field of a list's elements). `undefined` when the rule or the
 * input is not found or is not an enumeration.
 */
export function noticeEnum(
  schemas: ReadonlyArray<{ name: string; parameters?: unknown }>,
  notice: DefaultChangeNotice
): string[] | undefined {
  const rule = schemas.find((f) => f.name === notice.function)
  let node = rule?.parameters as SchemaNode | undefined
  for (const segment of notice.input.split('.')) {
    const key = segment.replace(/(\[\])+$/, '')
    const lists = (segment.length - key.length) / 2
    if (!node?.properties || !hasOwn(node.properties, key)) return undefined
    node = node.properties[key]
    for (let i = 0; i < lists; i++) node = node?.items
  }
  const values = node?.enum
  return values && values.length > 0 ? values : undefined
}

/** "2 defaults changed", for a notification; "" when none. */
export function noticeSummary(notices: DefaultChangeNotice[]): string {
  if (notices.length === 0) return ''
  return `${notices.length} default${notices.length === 1 ? '' : 's'} changed`
}

/**
 * The `notices` of a deploy job result, read defensively: the field is
 * absent from a service that predates the report, and a notice that is not
 * the agreed shape is dropped rather than shown half-formed.
 */
export function normalizeNotices(raw: unknown): DefaultChangeNotice[] {
  if (!Array.isArray(raw)) return []
  const notices: DefaultChangeNotice[] = []
  for (const item of raw) {
    if (
      item !== null &&
      typeof item === 'object' &&
      (item as { kind?: unknown }).kind === 'default-changed' &&
      typeof (item as { function?: unknown }).function === 'string' &&
      typeof (item as { input?: unknown }).input === 'string' &&
      'old' in item &&
      'new' in item
    ) {
      const n = item as DefaultChangeNotice
      notices.push({
        kind: 'default-changed',
        function: n.function,
        input: n.input,
        old: n.old,
        new: n.new,
      })
    }
  }
  return notices
}

/**
 * What the sidebar says about changed defaults once a deploy job has finished,
 * applied or rejected: either the list the service reported (`notices` in the
 * job result, which the service puts on a rejection too), or, when the job
 * result has no `notices` (a service that predates the report), the list the
 * review held before the deploy, marked as such. `null` when there is nothing
 * to say.
 */
export interface DeployReport {
  deploymentId: string
  /** `unknown`: the result of the deploy could not be read, so it may have
   *  been applied. Only `rejected` says that nothing changed. */
  outcome: 'applied' | 'rejected' | 'unknown'
  /** `service`: the job result carried the list. `review`: it did not, and
   *  this is what the review showed before the deploy. */
  source: 'service' | 'review'
  notices: DefaultChangeNotice[]
  /** The rules' schemas as they were when the deploy was sent, so that an
   *  enumerated default is spelled as on the card. */
  schemas: ReadonlyArray<{ name: string; parameters?: unknown }>
}

export function reportAfterDeploy(args: {
  /** The job result's `notices`, as it came: `undefined` when the key is absent. */
  jobNotices: unknown
  /** What the review held before the deploy. */
  reviewNotices: DefaultChangeNotice[]
}): Pick<DeployReport, 'source' | 'notices'> | null {
  if (Array.isArray(args.jobNotices)) {
    const notices = normalizeNotices(args.jobNotices)
    return notices.length > 0 ? { source: 'service', notices } : null
  }
  return args.reviewNotices.length > 0
    ? { source: 'review', notices: args.reviewNotices }
    : null
}

/** The report after a deployment is undeployed: gone if it was about that one. */
export function clearReportFor(
  report: DeployReport | null,
  deploymentId: string
): DeployReport | null {
  return report?.deploymentId === deploymentId ? null : report
}
