// Dev-only demo transport.
//
// Drop-in stand-in for `AiBridge` (same messenger surface) that needs no
// auth and no network: history, transcripts, and streamed replies are all
// canned. Activated by the `/demo/...` route in dev builds only — see the
// `isDemo` guard in `[org]/[deployment]/+page.svelte`. Lets anyone run
// `npm run dev` and click through the full chat UI (sidebar/drawer, empty
// state, streaming, rule tool-call rows) with example content.

import {
  AiAuthStatus,
  AiActiveFile,
  AiChatAbort,
  AiChatDone,
  AiChatPickAttachment,
  AiChatStart,
  AiChatStarted,
  AiChatTextDelta,
  AiChatThinkingDelta,
  AiChatToolActivity,
  AiConversationDelete,
  AiConversationList,
  AiConversationLoad,
  AiMentionSearch,
  AiToolRenderMeta,
  AiUsageSubscribe,
  AiUsageUpdate,
  type AiChatMessage,
  type AiChatStartParams,
  type AiConversation,
  type AiConversationSummary,
} from 'jl4-client-rpc'

type Handler = (params: unknown) => void
type TypeRef = { method: string }

export const DEMO_ORG = 'demo'
export const DEMO_DEPLOYMENT = 'sg-employment-act'
export const DEMO_INTENDED_USE =
  'Ask about Singapore Employment Act entitlements — severance, overtime, ' +
  'leave and notice periods. Answers are computed from deployed L4 rules. ' +
  '(Local demo: replies are canned examples, nothing leaves your machine.)'

const MODEL = 'legalese-comply-4 (demo)'

function minutesAgo(m: number): string {
  return new Date(Date.now() - m * 60_000).toISOString()
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms))
}

interface DemoConversation {
  summary: AiConversationSummary
  messages: AiChatMessage[]
}

/** The streamed reply every demo turn produces (word-chunked). */
const DEMO_REPLY = [
  'Based on the deployed **severance_pay** rule, an employee with ',
  '**6 years and 3 months** of service on a monthly salary of ',
  '**S$4,200** is owed:\n\n',
  '| Component | Amount |\n',
  '|---|---|\n',
  '| Base entitlement (6 yrs × 0.5 month) | S$12,600 |\n',
  '| Pro-rated part-year (3/12 × 0.5 month) | S$525 |\n',
  '| **Total severance** | **S$13,125** |\n\n',
  'Two things to note:\n\n',
  '1. The Employment Act only *mandates* retrenchment benefit eligibility ',
  'after 2 years of service — the quantum above follows the deployed ',
  "rule's half-month-per-year convention.\n",
  '2. If the contract or collective agreement specifies a higher rate, ',
  'that rate prevails.\n\n',
  'Want me to re-run this with a different salary or service period?',
]

const DEMO_THINKING =
  'The user asks about severance. The deployment exposes severance_pay ' +
  '(years_of_service, monthly_salary). 6y3m → 6.25 years; evaluate the ' +
  'rule, then present the breakdown with the statutory caveats.'

const SEED_CONVERSATIONS: DemoConversation[] = [
  {
    summary: {
      id: 'demo-severance',
      title: 'Severance for a 6-year employee',
      model: MODEL,
      createdAt: minutesAgo(95),
      lastActiveAt: minutesAgo(90),
      messageCount: 2,
      deploymentId: DEMO_DEPLOYMENT,
    },
    messages: [
      {
        role: 'user',
        content:
          'An employee worked 6 years and 3 months with us, last drawn ' +
          'monthly salary S$4,200. What severance are they owed?',
      },
      { role: 'assistant', content: DEMO_REPLY.join('') },
    ],
  },
  {
    summary: {
      id: 'demo-overtime',
      title: 'Overtime pay eligibility',
      model: MODEL,
      createdAt: minutesAgo(2 * 24 * 60),
      lastActiveAt: minutesAgo(2 * 24 * 60 - 5),
      messageCount: 2,
      deploymentId: DEMO_DEPLOYMENT,
    },
    messages: [
      {
        role: 'user',
        content:
          'Is a workman earning S$3,800/month covered by Part IV overtime provisions?',
      },
      {
        role: 'assistant',
        content:
          'Yes. Under the deployed **part_iv_coverage** rule, a *workman* is ' +
          'covered by Part IV of the Employment Act when their basic monthly ' +
          'salary does not exceed **S$4,500** — S$3,800 qualifies.\n\n' +
          'Overtime is then payable at **1.5× the hourly basic rate**, and ' +
          'total overtime is capped at 72 hours a month.',
      },
    ],
  },
]

export class DemoBridge {
  private handlers = new Map<string, Handler>()
  private conversations = new Map<string, DemoConversation>(
    SEED_CONVERSATIONS.map((c) => [c.summary.id, c])
  )
  private aborted = new Set<string>()
  private usedToday = 18_400
  private counter = 0

  // ── Messenger surface (subset the store/panel use) ───────────────────

  onNotification(type: TypeRef, handler: Handler): this {
    this.handlers.set(type.method, handler)
    return this
  }

  sendNotification(type: TypeRef, _recipient: unknown, params: unknown): void {
    switch (type) {
      case AiChatStart:
        void this.runTurn(params as AiChatStartParams)
        break
      case AiChatAbort:
        this.aborted.add((params as { turnId: string }).turnId)
        break
      case AiUsageSubscribe:
        this.emitUsage()
        break
      default:
        break
    }
  }

  async sendRequest(
    type: TypeRef,
    _recipient: unknown,
    params: unknown
  ): Promise<unknown> {
    switch (type) {
      case AiConversationList:
        return { items: this.listSummaries() }
      case AiConversationLoad: {
        const c = this.conversations.get((params as { id: string }).id)
        return { conversation: c ? this.toConversation(c) : null }
      }
      case AiConversationDelete:
        this.conversations.delete((params as { id: string }).id)
        return {}
      case AiChatPickAttachment:
        return { note: 'Attachments are disabled in the local demo.' }
      case AiMentionSearch:
        return { items: [] }
      case AiToolRenderMeta:
        return { kind: 'unavailable' }
      default:
        return null
    }
  }

  start(): this {
    return this
  }

  signalReady(): void {
    this.emit(AiAuthStatus, { signedIn: true })
    this.emit(AiActiveFile, {
      uri: null,
      name: null,
      path: null,
      inWorkspace: false,
    })
  }

  dispose(): void {
    this.handlers.clear()
  }

  // ── Internals ────────────────────────────────────────────────────────

  private emit(type: TypeRef, payload: unknown): void {
    this.handlers.get(type.method)?.(payload)
  }

  private listSummaries(): AiConversationSummary[] {
    return [...this.conversations.values()]
      .map((c) => c.summary)
      .sort((a, b) => b.lastActiveAt.localeCompare(a.lastActiveAt))
  }

  private toConversation(c: DemoConversation): AiConversation {
    return {
      id: c.summary.id,
      orgId: DEMO_ORG,
      userId: 'demo-user',
      model: MODEL,
      title: c.summary.title,
      createdAt: c.summary.createdAt,
      lastActiveAt: c.summary.lastActiveAt,
      messages: c.messages,
      deploymentId: DEMO_DEPLOYMENT,
      apiBaseUrl: `demo://${DEMO_ORG}/${DEMO_DEPLOYMENT}`,
    }
  }

  private emitUsage(): void {
    this.emit(AiUsageUpdate, {
      used: this.usedToday,
      limit: 250_000,
      blockOnOverage: true,
    })
  }

  /** Stream the canned reply: thinking → rule tool-call → text → done. */
  private async runTurn(p: AiChatStartParams): Promise<void> {
    const stopped = (): boolean => this.aborted.has(p.turnId)

    let conv = p.conversationId
      ? this.conversations.get(p.conversationId)
      : undefined
    if (!conv) {
      const id = `demo-new-${++this.counter}`
      conv = {
        summary: {
          id,
          title:
            p.text.length > 42 ? `${p.text.slice(0, 42).trimEnd()}…` : p.text,
          model: MODEL,
          createdAt: minutesAgo(0),
          lastActiveAt: minutesAgo(0),
          messageCount: 0,
          deploymentId: DEMO_DEPLOYMENT,
        },
        messages: [],
      }
      this.conversations.set(id, conv)
    }
    const convId = conv.summary.id
    if (!p.continueTurn) conv.messages.push({ role: 'user', content: p.text })

    await sleep(350)
    this.emit(AiChatStarted, {
      conversationId: convId,
      turnId: p.turnId,
      model: MODEL,
    })

    // Thinking stream.
    for (const word of DEMO_THINKING.split(/(?<= )/)) {
      if (stopped()) return this.finish(p.turnId, conv, 'abort')
      this.emit(AiChatThinkingDelta, { conversationId: convId, text: word })
      await sleep(18)
    }

    // Server-side rule evaluation: running → done merges into one card.
    const ruleInput = {
      function_name: 'severance_pay',
      arguments: { years_of_service: 6.25, monthly_salary: 4200 },
    }
    this.emit(AiChatToolActivity, {
      conversationId: convId,
      tool: 'evaluate_rule',
      status: 'running',
      ruleId: 'severance_pay',
      deploymentId: DEMO_DEPLOYMENT,
      label: 'severance_pay',
      message: 'Evaluating severance_pay',
      input: ruleInput,
    })
    await sleep(900)
    if (stopped()) return this.finish(p.turnId, conv, 'abort')
    this.emit(AiChatToolActivity, {
      conversationId: convId,
      tool: 'evaluate_rule',
      status: 'done',
      ruleId: 'severance_pay',
      deploymentId: DEMO_DEPLOYMENT,
      label: 'severance_pay',
      message: 'Evaluated severance_pay',
      input: ruleInput,
      output: { result: 13125, currency: 'SGD', basis: '0.5 month per year' },
    })

    // Answer stream.
    let full = ''
    for (const chunk of DEMO_REPLY) {
      for (const word of chunk.split(/(?<= )/)) {
        if (stopped()) return this.finish(p.turnId, conv, 'abort')
        this.emit(AiChatTextDelta, { conversationId: convId, text: word })
        full += word
        await sleep(14)
      }
    }

    conv.messages.push({ role: 'assistant', content: full })
    this.finish(p.turnId, conv, 'stop')
  }

  private finish(
    turnId: string,
    conv: DemoConversation,
    finishReason: string
  ): void {
    this.aborted.delete(turnId)
    conv.summary.lastActiveAt = minutesAgo(0)
    conv.summary.messageCount = conv.messages.length
    this.usedToday += 940
    this.emit(AiChatDone, {
      conversationId: conv.summary.id,
      finishReason,
      usage: { promptTokens: 812, completionTokens: 128 },
    })
    this.emitUsage()
  }
}
