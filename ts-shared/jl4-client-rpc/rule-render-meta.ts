/**
 * When a rule call's row asks its host for the rule's schema, which it
 * needs to show the call's input and output as L4 rather than JSON.
 */

/** What a row asks: the shape of `AiToolRenderMeta`'s params. */
export interface RenderMetaQuery {
  toolName: string
  deploymentId?: string
  fnName?: string
}

/** The generic rule tool: it names its rule in its arguments, not its name. */
const GENERIC_EVALUATE = 'l4-rules__evaluate'

/**
 * What a rule call's row asks for its schema, or null while it can't ask.
 * A rule's own tool is found by its name. The generic `evaluate` only names
 * its rule once its arguments have streamed in, and the host can't find the
 * schema before then, so asking earlier only gets "unavailable".
 */
export function renderMetaQuery(call: {
  name: string
  deploymentId?: string
  ruleFnName?: string
}): RenderMetaQuery | null {
  const named = !!call.deploymentId && !!call.ruleFnName
  if (call.name === GENERIC_EVALUATE && !named) return null
  return {
    toolName: call.name,
    ...(call.deploymentId ? { deploymentId: call.deploymentId } : {}),
    ...(call.ruleFnName ? { fnName: call.ruleFnName } : {}),
  }
}

function queryKey(q: RenderMetaQuery): string {
  return [q.toolName, q.deploymentId ?? '', q.fnName ?? ''].join('\n')
}

/**
 * Loads a row's schema: one request at a time, until one returns it.
 *
 * A row's query can change while a request is out: an `evaluate` call
 * names its rule, or finishes, as the host answers an earlier question.
 * When the answer has no schema and the query changed meanwhile, the
 * loader asks again at once; otherwise the next `load()` does. Without
 * this a row whose call finished while a request was out stayed on JSON:
 * nothing called `load()` again.
 */
export class RenderMetaLoader<M> {
  private inFlight = false
  private loaded = false

  constructor(
    private readonly opts: {
      /** The row's current query, or null while it can't ask. */
      query: () => RenderMetaQuery | null
      /** The schema, or null when the host has none for this query. */
      fetch: (query: RenderMetaQuery) => Promise<M | null>
      onLoaded: (meta: M) => void
    }
  ) {}

  async load(): Promise<void> {
    if (this.loaded || this.inFlight) return
    const asked = this.opts.query()
    if (!asked) return
    this.inFlight = true
    let meta: M | null = null
    try {
      meta = await this.opts.fetch(asked)
    } catch {
      // Unreachable host: the next `load()` tries again.
    } finally {
      this.inFlight = false
    }
    if (meta) {
      this.loaded = true
      this.opts.onLoaded(meta)
      return
    }
    const now = this.opts.query()
    if (now && queryKey(now) !== queryKey(asked)) await this.load()
  }
}
