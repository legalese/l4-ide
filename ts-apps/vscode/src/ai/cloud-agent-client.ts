import * as vscode from 'vscode'
import type { AiChatStartParams } from 'jl4-client-rpc'
import { LEGALESE_CLOUD_DOMAIN, type AuthManager } from '../auth.js'
import type { VSCodeL4LanguageClient } from '../vscode-l4-language-client.js'
import type { AiLogger } from './logger.js'
import type { ChatServiceEvent } from './chat-service.js'
import { parseSse } from './ai-proxy-client.js'
import { gatherL4Bundle } from './l4-bundle.js'

/**
 * Drives a turn on the cloud compose agent (legalese-compose-agent) instead of
 * streaming ai-proxy locally. The harness — tool loop, MCP, file tools — runs
 * server-side; this client only:
 *   1. mints a per-turn agent token from the user's session,
 *   2. uploads the workspace bundle (attachments + active file + L4 import tree),
 *   3. POSTs the turn and maps the agent's (ai-proxy-compatible) SSE back onto
 *      the same {@link ChatServiceEvent}s the local path emits, and
 *   4. revokes the token at end of turn.
 *
 * Because the agent's SSE is wire-identical to ai-proxy's, the webview renders
 * the conversation exactly as a normal one.
 */

interface MintResponse {
  token: string
  jti: string
  expiresAt: number
}

export class CloudAgentClient {
  constructor(
    private readonly auth: AuthManager,
    private readonly client: VSCodeL4LanguageClient,
    private readonly logger: AiLogger
  ) {}

  /** Agent base URL. Honours `legaleseAi.localMode` for local dev. */
  private endpoint(): string {
    const cfg = vscode.workspace.getConfiguration()
    const override = cfg.get<string>('legaleseAgent.url')
    if (override) return override.replace(/\/$/, '')
    if (cfg.get<boolean>('legaleseAi.localMode') === true) {
      return 'http://127.0.0.1:8080'
    }
    return 'https://agent.legalese.cloud'
  }

  /** Auth-proxy base for minting/revoking the per-turn token. */
  private authBase(): string {
    const override = vscode.workspace
      .getConfiguration()
      .get<string>('legaleseAgent.authBaseUrl')
    return (override ?? `https://${LEGALESE_CLOUD_DOMAIN}`).replace(/\/$/, '')
  }

  /**
   * Run one cloud-agent turn, emitting {@link ChatServiceEvent}s. Resolves when
   * the stream ends (or errors). Never throws — failures surface as an `error`
   * event so the webview shows a retry affordance.
   */
  async run(
    params: AiChatStartParams,
    emit: (event: ChatServiceEvent) => void,
    abortSignal: AbortSignal
  ): Promise<void> {
    const orgSlug = this.auth.getCloudOrgSlug()
    const conversationId =
      params.conversationId ??
      `conv_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`

    if (!orgSlug) {
      emit({
        kind: 'error',
        conversationId,
        message: 'Sign in with Legalese Cloud to use the cloud agent.',
        code: 'unauthenticated',
      })
      emit({ kind: 'done', conversationId, finishReason: 'error' })
      return
    }

    let mint: MintResponse | undefined
    try {
      mint = await this.mintToken()
    } catch (err) {
      this.logger.warn(
        `cloud-agent: token mint failed: ${err instanceof Error ? err.message : String(err)}`
      )
      emit({
        kind: 'error',
        conversationId,
        message: 'Could not authorize the cloud agent for this turn.',
        code: 'mint_failed',
      })
      emit({ kind: 'done', conversationId, finishReason: 'error' })
      return
    }

    try {
      const bundle = await gatherL4Bundle(this.client, this.logger)
      const body = {
        conversationId,
        turnId: params.turnId,
        orgSlug,
        text: params.text,
        ...(bundle.activeFile && params.includeActiveFile !== false
          ? { activeFile: bundle.activeFile }
          : {}),
        files: bundle.files,
        attachments: params.attachments,
      }

      const res = await fetch(`${this.endpoint()}/v1/agent/turn`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${mint.token}`,
          'Content-Type': 'application/json',
          Accept: 'text/event-stream',
        },
        body: JSON.stringify(body),
        signal: abortSignal,
      })
      if (!res.ok || !res.body) {
        const text = await res.text().catch(() => '')
        emit({
          kind: 'error',
          conversationId,
          message: text.slice(0, 200) || `Agent returned HTTP ${res.status}`,
          code: 'agent_error',
        })
        emit({ kind: 'done', conversationId, finishReason: 'error' })
        return
      }

      let started = false
      for await (const ev of parseSse(res.body, this.logger)) {
        switch (ev.kind) {
          case 'metadata':
            if (!started) {
              started = true
              emit({
                kind: 'started',
                conversationId,
                turnId: params.turnId,
                model: ev.model,
              })
            }
            break
          case 'text-delta':
            emit({ kind: 'text-delta', conversationId, text: ev.text })
            break
          case 'thinking-delta':
            emit({ kind: 'thinking-delta', conversationId, text: ev.text })
            break
          case 'tool-activity':
            emit({
              kind: 'tool-activity',
              conversationId,
              tool: ev.tool,
              status: ev.status,
              label: ev.label,
              message: ev.message,
              input: ev.input,
              output: ev.output,
              ruleId: ev.ruleId,
              deploymentId: ev.deploymentId,
              error: ev.error,
              sources: ev.sources,
            })
            break
          case 'tool-call':
            // The agent executes tools server-side and reports them as
            // tool-activity; a raw tool-call shouldn't reach the client.
            break
          case 'error':
            emit({
              kind: 'error',
              conversationId,
              message: ev.message,
              code: ev.code,
            })
            break
          case 'done':
            emit({
              kind: 'done',
              conversationId,
              finishReason: ev.finishReason,
              usage: ev.usage,
            })
            break
        }
      }
      if (!started) {
        // Stream ended before any frame — surface a terminal done so the
        // webview clears its spinner.
        emit({ kind: 'done', conversationId, finishReason: 'stop' })
      }
    } catch (err) {
      if (!abortSignal.aborted) {
        emit({
          kind: 'error',
          conversationId,
          message:
            err instanceof Error ? err.message : 'Cloud agent turn failed',
          code: 'agent_error',
        })
      }
      emit({
        kind: 'done',
        conversationId,
        finishReason: abortSignal.aborted ? 'aborted' : 'error',
      })
    } finally {
      // End-of-turn: invalidate the token so it can't be reused.
      void this.revokeToken(mint.jti, mint.expiresAt)
    }
  }

  private async mintToken(): Promise<MintResponse> {
    const headers = await this.auth.getAuthHeaders()
    if (!headers.Authorization) {
      throw new Error('no session')
    }
    const res = await fetch(`${this.authBase()}/auth/agent-token`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    })
    if (!res.ok) throw new Error(`mint HTTP ${res.status}`)
    return (await res.json()) as MintResponse
  }

  private async revokeToken(jti: string, expiresAt: number): Promise<void> {
    try {
      const headers = await this.auth.getAuthHeaders()
      await fetch(`${this.authBase()}/auth/agent-token/revoke`, {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ jti, exp: expiresAt }),
      })
    } catch (err) {
      this.logger.warn(
        `cloud-agent: token revoke failed (will expire): ${err instanceof Error ? err.message : String(err)}`
      )
    }
  }
}
