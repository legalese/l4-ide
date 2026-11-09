/**
 * Events the chat service emits while running a turn, through the
 * {@link UserInteraction} port. The VS Code sidebar forwards each to the
 * webview as the matching `AiChat*` notification.
 */
export type ChatServiceEvent =
  | { kind: 'started'; conversationId: string; turnId: string; model: string }
  | { kind: 'text-delta'; conversationId: string; text: string }
  | { kind: 'thinking-delta'; conversationId: string; text: string }
  | {
      kind: 'tool-activity'
      conversationId: string
      tool: string
      status: 'running' | 'done' | 'error'
      /** Proxy-supplied bold action prefix (e.g. "L4 Deployments",
       *  "Compacting...", "Legalesing..."). The webview renders it
       *  verbatim — no per-tool name mapping on this side. */
      label?: string
      message: string
      /** L4 Rule activities only. */
      input?: unknown
      output?: unknown
      ruleId?: string
      deploymentId?: string
      error?: string
      /** Synthetic `web_search` activities only — URL citations the
       *  upstream model's provider-native web search produced. */
      sources?: Array<{ url: string; title?: string }>
    }
  | {
      kind: 'tool-call'
      conversationId: string
      callId: string
      name: string
      argsJson: string
      status: 'pending-approval' | 'running' | 'done' | 'error'
      result?: string
      error?: string
      /** For `l4-rules__<sanitised>` calls: original L4 function name
       *  + deployment id parsed from the MCP description trailer.
       *  Threaded through to the webview so the tool-call row shows
       *  the unsanitised name (matching the server-side rule-activity
       *  card) instead of the wire-level slug with dashes. */
      ruleFnName?: string
      deploymentId?: string
    }
  | {
      kind: 'done'
      conversationId: string
      finishReason: string
      usage?: { promptTokens: number; completionTokens: number }
    }
  | {
      kind: 'error'
      conversationId: string
      message: string
      code?: string
    }
  /** Fired when a queued user message (sent during an in-flight turn
   *  via `AiChatInject`) triggers a brand-new sub-turn under the same
   *  conversation. The webview mounts a fresh streaming assistant
   *  bubble keyed off `subTurnId` so subsequent text-delta /
   *  tool-call events route to it. */
  | { kind: 'turn-spawn'; conversationId: string; subTurnId: string }
  /** Fired each time the chat service drains queued user messages
   *  into a fresh sub-turn. `injectionIds` lists the webview-minted
   *  ids of the messages just consumed — the webview removes the
   *  matching entries from its pending-queue array. An unack'd id
   *  stays in the array so a dropped event surfaces as a stuck
   *  pipeline rather than a silent miscount. */
  | {
      kind: 'queue-consumed'
      conversationId: string
      injectionIds: string[]
    }

export type ChatServiceEmitter = (event: ChatServiceEvent) => void

/** Chronological record of what happened inside an assistant turn, saved
 *  as `_meta.blocks` on the assistant message so the webview can
 *  reconstruct the original text + tool-call row layout on reload. */
export type PersistedBlock =
  | { kind: 'text'; text: string }
  | {
      kind: 'tool-call'
      callId: string
      name: string
      argsJson: string
      status: 'running' | 'done' | 'error'
      result?: string
      error?: string
      /** Original (unsanitised) L4 function name for `l4-rules__*`
       *  rule calls — preserved so a reloaded transcript shows the
       *  same row label the user saw live. */
      ruleFnName?: string
      /** Deployment id parsed from the MCP description trailer. */
      deploymentId?: string
    }
  // Server activities worth preserving across a history reload. Two
  // shapes share the variant:
  //
  //  - L4 Rule activities (the proxy ran a deployed rule): `ruleId` +
  //    `ruleKey` are both set; `ruleKey` mirrors the webview store's
  //    merge key so a `running → done` burst persists as ONE block.
  //  - Synthetic `web_search` activities: `tool === 'web_search'`,
  //    `sources` carries the URL citation list. No rule fields.
  //
  // Other plain status tickers (doc search, compaction, deployment
  // browsing) are intentionally not recorded — they're ephemeral
  // progress noise with nothing to reconstruct on reload.
  | {
      kind: 'tool-activity'
      tool: string
      ruleId?: string
      ruleKey?: string
      status: 'running' | 'done' | 'error'
      message: string
      input?: unknown
      output?: unknown
      deploymentId?: string
      error?: string
      sources?: Array<{ url: string; title?: string }>
    }
