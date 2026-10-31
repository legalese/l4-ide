import { createHash } from 'node:crypto'
import type { AiTool, Logger, ToolProvider } from './ports.js'

/**
 * Thin MCP (streamable HTTP, JSON responses) client for the L4 Rules
 * server. In VS Code it talks to the local MCP proxy at
 * `http://127.0.0.1:{port}/mcp`, which forwards to the user's connected
 * jl4-service on `/.mcp`; a headless host points it at
 * `mcp.legalese.cloud` with its own credentials. Either way `tools/list`
 * returns whichever rules the user currently has deployed. We translate
 * those into OpenAI function-tool shape with a `l4-rules__` prefix so
 * they land in the same dispatcher path as the built-in tools
 * (`fs__read_file`, etc.).
 */

/** Where the MCP endpoint is. `getLocalUrl` returns undefined while it
 *  isn't available (no tools are listed then). */
export interface McpEndpoint {
  getLocalUrl(): string | undefined
  /** Extra request headers (e.g. Authorization for a remote server). */
  getHeaders?(): Promise<Record<string, string>>
}

/** JSON-RPC id counter, unique per process. */
let rpcIdCounter = 1

/** Shape of a single MCP tool as returned by `tools/list`. */
interface McpTool {
  name: string
  description?: string
  inputSchema?: {
    type?: string
    properties?: Record<string, unknown>
    required?: string[]
    additionalProperties?: boolean
  }
}

interface McpListResult {
  tools?: McpTool[]
}

interface McpCallResult {
  content?: Array<{ type: string; text?: string }>
  isError?: boolean
}

export const MCP_L4_RULES_PREFIX = 'l4-rules__'

/** At or below this many rules, each is its own tool: one direct call is
 *  the better deal. Above it they're found on demand, because every tool
 *  definition is resent on every round whether it's used or not. Same rule
 *  as `data-tools="auto"` in the WebMCP embed. */
export const DIRECT_RULE_LIMIT = 10

/** Names listed in the first-turn index; beyond this, only search. */
const INDEX_RULE_LIMIT = 400

const SEARCH_DEFAULT_LIMIT = 8
const SCHEMA_MAX_CHARS = 16_000

/** A deployed rule found in `tools/list`. */
interface RuleEntry {
  deployId: string
  fnName: string
  /** The name to call it by over MCP. */
  mcpName: string
  description: string
  inputSchema: Record<string, unknown>
}

/** The discovery tools, named and shaped like a remote rules server's, so
 *  the system prompt needs one description of them for both. */
const DISCOVERY_TOOLS: AiTool[] = [
  {
    type: 'function',
    function: {
      name: `${MCP_L4_RULES_PREFIX}search_rules`,
      description:
        "Find deployed rules by keyword. Keywords match a rule's name and description literally, so try several words. Returns each rule's deployment, name and description.",
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          query: { type: 'string', description: 'Space-separated keywords.' },
          limit: { type: 'number', description: 'Max rules (default 8).' },
        },
        required: ['query'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: `${MCP_L4_RULES_PREFIX}get_schema`,
      description:
        'Get the input schema of a deployed rule, so you can call it with valid arguments.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          deployment: { type: 'string' },
          function: { type: 'string', description: 'Rule name.' },
        },
        required: ['function'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: `${MCP_L4_RULES_PREFIX}evaluate`,
      description:
        'Run a deployed rule and return the authoritative result. Call get_schema first. Prefer this over reasoning the determination yourself, and cite the rule you ran.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          deployment: { type: 'string' },
          function: { type: 'string', description: 'Rule name.' },
          arguments: {
            type: 'object',
            description: "Arguments matching the rule's input schema.",
          },
        },
        required: ['function', 'arguments'],
      },
    },
  },
]

const DISCOVERY_NAMES: ReadonlySet<string> = new Set(
  DISCOVERY_TOOLS.map((t) => t.function.name.slice(MCP_L4_RULES_PREFIX.length))
)

export class McpToolClient implements ToolProvider {
  readonly prefix = MCP_L4_RULES_PREFIX

  /** Short in-process cache so a chat turn's tools/list call doesn't
   *  hammer the proxy if several turns are fired in quick succession. */
  private cache: { at: number; tools: AiTool[] } | null = null
  /** sanitized-prefixed-name → original MCP rule name. Populated on
   *  every listTools(); consulted by callTool() to reverse the
   *  `[^a-zA-Z0-9_-]` sanitization we applied for OpenAI compliance. */
  private nameMap = new Map<string, string>()
  /** sanitized-prefixed-name → (deployId, fnName) parsed from the
   *  tool description's trailing `[deployId/fnName]` token. Used by
   *  the chat tool-call card to fetch the function-schema endpoint
   *  on demand for L4-syntax rendering. */
  private targetMap = new Map<string, { deployId: string; fnName: string }>()
  /** Every rule from the last listing. Non-empty only while they're
   *  found on demand instead of each being a tool. */
  private rules: RuleEntry[] = []
  private initialized = false

  constructor(
    private readonly proxy: McpEndpoint,
    private readonly logger: Logger
  ) {}

  /**
   * Fetch the current tool list from the local MCP proxy, cached for a
   * few seconds. Returns an empty list if the proxy isn't running or
   * the user isn't connected (the proxy happily answers `tools/list`
   * with `[]` in that state — see its `handleLocally`).
   */
  async listTools(): Promise<AiTool[]> {
    if (this.cache && Date.now() - this.cache.at < 3_000) {
      return this.cache.tools
    }
    const url = this.proxy.getLocalUrl()
    if (!url) return []
    try {
      if (!this.initialized) await this.initialize(url)
      const listed = await this.rpc<McpListResult>(url, 'tools/list', {})
      this.nameMap.clear()
      this.targetMap.clear()
      const listedTools = listed?.tools ?? []
      const ruleCount = listedTools.filter((t) =>
        parseToolDescriptionTarget(t.description)
      ).length
      const discover = ruleCount > DIRECT_RULE_LIMIT
      const rules: RuleEntry[] = []
      const tools: AiTool[] = []
      for (const t of listedTools) {
        const tool = this.toAiTool(t)
        const target = parseToolDescriptionTarget(t.description)
        if (target && discover) {
          rules.push({
            ...target,
            mcpName: t.name,
            description: describeRule(t.description, target.fnName),
            inputSchema: tool.function.parameters,
          })
          continue
        }
        this.nameMap.set(tool.function.name, t.name)
        if (target) this.targetMap.set(tool.function.name, target)
        tools.push(tool)
      }
      if (discover) tools.push(...DISCOVERY_TOOLS)
      this.rules = rules
      this.cache = { at: Date.now(), tools }
      return tools
    } catch (err) {
      this.logger.warn(
        `mcp-client: tools/list failed: ${err instanceof Error ? err.message : String(err)}`
      )
      return []
    }
  }

  /**
   * Forward a `l4-rules__<name>` tool invocation to the MCP proxy as
   * `tools/call`. Returns a plain string the chat-service can ship
   * back to the LLM as the tool-result content.
   */
  async callTool(prefixedName: string, argsJson: string): Promise<string> {
    if (!prefixedName.startsWith(MCP_L4_RULES_PREFIX)) {
      throw new Error(
        `mcp-client: tool name must start with ${MCP_L4_RULES_PREFIX}: ${prefixedName}`
      )
    }
    let name = prefixedName
    let argsToSend = argsJson
    const local = prefixedName.slice(MCP_L4_RULES_PREFIX.length)
    // After invalidate() the rules are gone until the next listing, and a
    // call made in that gap mustn't fall through to the server.
    if (this.rules.length === 0 && DISCOVERY_NAMES.has(local)) {
      await this.listTools()
    }
    if (this.rules.length > 0) {
      if (local === 'search_rules') return this.searchRules(argsJson)
      if (local === 'get_schema') return this.ruleSchema(argsJson)
      if (local === 'evaluate') {
        const args = parseObject(argsJson)
        const rule = this.findRule(args)
        name = `${MCP_L4_RULES_PREFIX}${rule.mcpName}`
        this.nameMap.set(name, rule.mcpName)
        argsToSend = JSON.stringify(args.arguments ?? {})
      }
    }
    // Prefer the reverse-mapped original name (undoes the sanitization
    // applied when we built the OpenAI tools list). Fall back to the
    // trimmed suffix if we've never listed or the map lost the entry —
    // covers the case where a rule name was already OpenAI-valid.
    const toolName =
      this.nameMap.get(name) ?? name.slice(MCP_L4_RULES_PREFIX.length)
    const url = this.proxy.getLocalUrl()
    if (!url) {
      throw new Error(
        'L4 MCP proxy is not running — cannot invoke deployed-rule tools.'
      )
    }
    let parsed: Record<string, unknown>
    try {
      parsed = argsToSend?.trim() ? JSON.parse(argsToSend) : {}
    } catch (err) {
      throw new Error(
        `mcp-client: invalid JSON arguments for ${prefixedName}: ${err instanceof Error ? err.message : String(err)}`
      )
    }
    if (!this.initialized) await this.initialize(url)
    const res = await this.rpc<McpCallResult>(url, 'tools/call', {
      name: toolName,
      arguments: parsed,
    })
    if (res?.isError) {
      const text = (res.content ?? [])
        .map((c) => (c.type === 'text' && c.text ? c.text : ''))
        .filter(Boolean)
        .join('\n')
      throw new Error(text || `${prefixedName} failed`)
    }
    const text = (res?.content ?? [])
      .map((c) => (c.type === 'text' && c.text ? c.text : JSON.stringify(c)))
      .join('\n')
    return text || JSON.stringify(res ?? {})
  }

  /** Force a cache refresh on the next listTools() call. */
  invalidate(): void {
    this.cache = null
    this.targetMap.clear()
    this.rules = []
  }

  /**
   * Rule names for the first turn when rules aren't tools. The model reads
   * these rather than relying on keyword search alone, which misses a
   * question phrased in other words ("sacked" for wrongful dismissal) and
   * would otherwise end in an answer from memory.
   */
  async promptIndex(): Promise<string | null> {
    await this.listTools()
    if (this.rules.length === 0) return null
    const shown = this.rules.slice(0, INDEX_RULE_LIMIT)
    const byDeployment = new Map<string, string[]>()
    for (const rule of shown) {
      const names = byDeployment.get(rule.deployId) ?? []
      names.push(indexText(rule.fnName))
      byDeployment.set(rule.deployId, names)
    }
    const lines = [...byDeployment].map(
      ([deployment, names]) => `${indexText(deployment)}: ${names.join('; ')}`
    )
    if (this.rules.length > shown.length) {
      lines.push(
        `(${this.rules.length - shown.length} more; use search_rules to find them.)`
      )
    }
    return lines.join('\n')
  }

  private searchRules(argsJson: string): string {
    const args = parseObject(argsJson)
    const query = typeof args.query === 'string' ? args.query : ''
    const keywords = query
      .toLowerCase()
      .split(/\s+/)
      .filter((k) => k.length >= 2)
    const limit =
      typeof args.limit === 'number' && args.limit > 0
        ? Math.min(Math.floor(args.limit), 25)
        : SEARCH_DEFAULT_LIMIT
    const scored = this.rules
      .map((rule) => {
        const name = rule.fnName.toLowerCase()
        const description = rule.description.toLowerCase()
        let score = 0
        for (const k of keywords) {
          if (name.includes(k)) score += 2
          else if (description.includes(k)) score += 1
        }
        return { rule, score }
      })
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, limit)
    if (scored.length === 0) {
      return `No deployed rule matched "${query}". Keywords match literally, so check the rule names you were given and try other words. If no rule applies, tell the user that no deployed rule covers this before answering from general knowledge.`
    }
    return JSON.stringify(
      scored.map(({ rule }) => ({
        deployment: rule.deployId,
        function: rule.fnName,
        description: rule.description,
      }))
    )
  }

  private ruleSchema(argsJson: string): string {
    const rule = this.findRule(parseObject(argsJson))
    const text = JSON.stringify({
      deployment: rule.deployId,
      function: rule.fnName,
      description: rule.description,
      inputSchema: rule.inputSchema,
    })
    return text.length > SCHEMA_MAX_CHARS
      ? `${text.slice(0, SCHEMA_MAX_CHARS)}... [schema truncated]`
      : text
  }

  /** The rule a discovery call names. Refuses to guess between rules with
   *  one name: running the wrong one would give a confident wrong answer. */
  private findRule(args: Record<string, unknown>): RuleEntry {
    const fn = typeof args.function === 'string' ? args.function : ''
    const deployment =
      typeof args.deployment === 'string' ? args.deployment : undefined
    const inDeployment = (r: RuleEntry): boolean =>
      deployment === undefined ||
      r.deployId === deployment ||
      indexText(r.deployId) === deployment
    let matches = this.rules.filter(
      (r) => (r.fnName === fn || r.mcpName === fn) && inDeployment(r)
    )
    // The index shows names cleaned for the prompt, so a model copying one
    // from there may not have the exact name.
    if (matches.length === 0) {
      matches = this.rules.filter(
        (r) => indexText(r.fnName) === fn && inDeployment(r)
      )
    }
    if (matches.length === 1) return matches[0]!
    if (matches.length === 0) {
      throw new Error(
        `No deployed rule named "${fn}"${deployment ? ` in ${deployment}` : ''}. Use search_rules to find it.`
      )
    }
    const options = matches.map((m) => `${m.deployId}/${m.fnName}`).join(', ')
    throw new Error(
      `"${fn}" could be several rules: ${options}. Pass the exact \`deployment\` and \`function\`.`
    )
  }

  /**
   * Map a sanitized prefixed tool name (e.g. `l4-rules__make_person`)
   * back to its `(deployId, fnName)` pair. The MCP server stamps
   * `[deployId/fnName]` into each tool's description; we parse that
   * out during listTools() and cache the mapping. Returns null for
   * file-infra tools (`list_files`, `read_file`, etc.) and when no
   * listTools() has happened yet. The caller may want to call
   * `listTools()` first to populate the map.
   */
  getToolTarget(
    prefixedName: string,
    argsJson?: string
  ): { deployId: string; fnName: string } | null {
    const direct = this.targetMap.get(prefixedName)
    if (direct) return direct
    if (prefixedName !== `${MCP_L4_RULES_PREFIX}evaluate` || !argsJson) {
      return null
    }
    // The rule is in the arguments, on both this client's discovery tools
    // and a remote server's.
    try {
      const args = JSON.parse(argsJson) as {
        deployment?: unknown
        function?: unknown
      }
      if (typeof args.function !== 'string') return null
      if (typeof args.deployment === 'string') {
        return { deployId: args.deployment, fnName: args.function }
      }
      const rule = this.findRule({ function: args.function })
      return { deployId: rule.deployId, fnName: rule.fnName }
    } catch {
      return null
    }
  }

  private async initialize(url: string): Promise<void> {
    try {
      await this.rpc(url, 'initialize', {
        protocolVersion: '2025-03-26',
        capabilities: { tools: {} },
        clientInfo: { name: 'legalese-ai-chat', version: '1.4.0' },
      })
      // Fire-and-forget the initialized notification.
      void this.rpc(url, 'notifications/initialized', {}).catch(() => undefined)
      this.initialized = true
    } catch (err) {
      this.logger.warn(
        `mcp-client: initialize failed: ${err instanceof Error ? err.message : String(err)}`
      )
      throw err
    }
  }

  private async rpc<T>(
    url: string,
    method: string,
    params: Record<string, unknown>
  ): Promise<T | null> {
    const id = rpcIdCounter++
    const extra = (await this.proxy.getHeaders?.()) ?? {}
    const res = await fetch(url, {
      method: 'POST',
      headers: { ...extra, 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
    })
    if (!res.ok) {
      throw new Error(`${method} returned HTTP ${res.status}`)
    }
    const text = await res.text()
    if (!text) return null
    const payload = JSON.parse(text) as {
      result?: T
      error?: { code?: number; message?: string }
    }
    if (payload.error) {
      throw new Error(payload.error.message ?? `${method} failed`)
    }
    return payload.result ?? null
  }

  private toAiTool(t: McpTool): AiTool {
    // OpenAI function-tool schema wants `parameters` (not `inputSchema`).
    // MCP gives us a nearly-matching JSON schema; we shape it so the
    // provider accepts it even when a rule ships no schema at all.
    const parameters = t.inputSchema ?? { type: 'object', properties: {} }
    // OpenAI's function-tool schema requires `parameters.type === 'object'`;
    // some MCP tools omit that, which the provider rejects.
    const shaped = {
      type: 'object' as const,
      properties:
        (parameters as { properties?: Record<string, unknown> }).properties ??
        {},
      ...(Array.isArray((parameters as { required?: string[] }).required)
        ? { required: (parameters as { required: string[] }).required }
        : {}),
      additionalProperties:
        (parameters as { additionalProperties?: boolean })
          .additionalProperties ?? false,
    }
    return {
      type: 'function',
      function: {
        name: `${MCP_L4_RULES_PREFIX}${sanitizeToolName(t.name)}`,
        description:
          t.description ??
          `Deployed L4 rule: ${t.name}. Inputs come from the rule's function signature.`,
        parameters: shaped,
      },
    }
  }
}

/** Longest rule-derived part of a tool name. */
const TOOL_NAME_MAX = 48

/** A stable short digest of a name, to keep shortened names distinct. */
export function nameDigest(name: string): string {
  return createHash('sha256').update(name).digest('hex').slice(0, 8)
}

/** OpenAI function names allow `[a-zA-Z0-9_-]{1,64}`; MCP rule names can
 *  contain spaces / dots / slashes. Map those to underscore so the
 *  combined name still round-trips safely. We key the dispatcher on
 *  the final prefixed name so the sanitization has to be deterministic.
 *
 *  A name this changes gets a digest of the original: two rules that
 *  differ only past the cut (section-33D-1, section-33D-2A) would otherwise
 *  collapse into one tool, and calls to one would run the other. */
function sanitizeToolName(s: string): string {
  const clean = s.replace(/[^a-zA-Z0-9_-]/g, '_')
  if (clean === s && s.length <= TOOL_NAME_MAX) return s
  return `${clean.slice(0, TOOL_NAME_MAX - 9)}-${nameDigest(s)}`
}

/** `<prefix><server>_<tool>` for a user's MCP tool, within the 64 characters
 *  a tool name may have. A name that has to be shortened gets a digest, so
 *  two tools that differ only past the cut stay two tools. */
export function userMcpToolName(
  prefix: string,
  server: string,
  tool: string
): string {
  const clean = (s: string): string => s.replace(/[^a-zA-Z0-9_-]/g, '_')
  const s = clean(server)
  const t = clean(tool)
  if (s.length <= 16 && t.length <= 40) return `${prefix}${s}_${t}`
  return `${prefix}${s.slice(0, 16)}_${t.slice(0, 31)}-${nameDigest(`${server}/${tool}`)}`
}

/** A rule's description without the `L4 Rule:` label and target token. */
function describeRule(description: string | undefined, fnName: string): string {
  const text = (description ?? '')
    .replace(/^L4 Rule:\s*/, '')
    .replace(/\s*\[[^/\]]+\/[^\]]+\]\s*$/, '')
    .trim()
  return text || fnName
}

/** Text from a deployment for the first-turn index: it's data from someone
 *  else, so it keeps only what a name needs and can't carry markup. */
function indexText(s: string): string {
  return s
    .replace(/[^\p{L}\p{N} _.()'-]/gu, ' ')
    .trim()
    .slice(0, 100)
}

function parseObject(json: string): Record<string, unknown> {
  try {
    const parsed: unknown = JSON.parse(json || '{}')
    if (parsed && typeof parsed === 'object') {
      return parsed as Record<string, unknown>
    }
  } catch {
    // Fall through to the error below.
  }
  throw new Error('Invalid tool arguments: expected a JSON object.')
}

/** Parse the `[deployId/fnName]` token MCP server stamps onto every
 *  rule-evaluation tool's description (see jl4-service McpServer.hs:
 *  `"L4 Rule: " <> fsDescription <> " [" <> deployId <> "/" <> fsName <> "]"`).
 *  Returns null when no token is present (file-infra tools, custom
 *  descriptions). The fnName is allowed to contain spaces — only the
 *  closing bracket terminates it. */
function parseToolDescriptionTarget(
  description: string | undefined
): { deployId: string; fnName: string } | null {
  if (!description) return null
  // Anchor on the LAST `[…/…]` so a description that itself contains
  // brackets earlier (rare, but possible in user-provided text) doesn't
  // mis-match. Greedy `.*` to consume everything before the final tag.
  const m = description.match(/\[([^/\]]+)\/([^\]]+)\]\s*$/)
  if (!m) return null
  return { deployId: m[1]!, fnName: m[2]! }
}
