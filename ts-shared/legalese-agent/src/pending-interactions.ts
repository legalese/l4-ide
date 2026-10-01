import type { ToolCallContext } from './ports.js'

type Decision = 'allow' | 'deny'

interface PendingApproval {
  resolve: (decision: Decision) => void
  ctx: ToolCallContext
}

interface PendingQuestion {
  resolve: (answer: string) => void
  ctx: ToolCallContext
}

/**
 * Book-keeping for tool approvals and `meta__ask_user` questions that
 * are waiting on the user, for {@link UserInteraction} adapters.
 *
 * Everything is scoped to the conversation and turn that raised it:
 * starting a new message in conversation A denies A's outstanding
 * approvals and skips A's questions, and leaves conversation B alone.
 * (The VS Code extension used to deny every pending approval in every
 * conversation.)
 *
 * Clients may show Allow/Deny before the dispatcher asks (the buttons
 * appear while the model is still streaming): {@link decide} stashes
 * such early decisions and {@link requestApproval} consumes them.
 */
export class PendingInteractions {
  private readonly approvals = new Map<string, PendingApproval>()
  private readonly questions = new Map<string, PendingQuestion>()
  /** callId → decision made before the dispatcher asked, with the
   *  conversation the client attributed the call to (if known). */
  private readonly early = new Map<
    string,
    { decision: Decision; conversationId?: string }
  >()

  /** Wait for the user's decision on a tool call. */
  requestApproval(callId: string, ctx: ToolCallContext): Promise<Decision> {
    const early = this.early.get(callId)
    if (early) {
      this.early.delete(callId)
      return Promise.resolve(early.decision)
    }
    return new Promise<Decision>((resolve) => {
      this.approvals.set(callId, { resolve, ctx })
    })
  }

  /**
   * Record the user's decision. Resolves the waiting approval and
   * returns true, or — when the dispatcher hasn't asked yet — stashes
   * it for {@link requestApproval} and returns false.
   */
  decide(callId: string, decision: Decision, conversationId?: string): boolean {
    const pending = this.approvals.get(callId)
    if (!pending) {
      this.early.set(callId, { decision, conversationId })
      return false
    }
    this.approvals.delete(callId)
    pending.resolve(decision)
    return true
  }

  /** Wait for the user's answer to a question (`''` = skipped). */
  askUser(callId: string, ctx: ToolCallContext): Promise<string> {
    return new Promise<string>((resolve) => {
      this.questions.set(callId, { resolve, ctx })
    })
  }

  /** Deliver an answer; false when no question is waiting. */
  answer(callId: string, answer: string): boolean {
    const pending = this.questions.get(callId)
    if (!pending) return false
    this.questions.delete(callId)
    pending.resolve(answer)
    return true
  }

  /** The context a waiting approval or question was raised in. */
  contextFor(callId: string): ToolCallContext | undefined {
    return this.approvals.get(callId)?.ctx ?? this.questions.get(callId)?.ctx
  }

  pendingApprovalCount(): number {
    return this.approvals.size
  }

  pendingQuestionCount(): number {
    return this.questions.size
  }

  /**
   * Deny every approval and skip every question raised in
   * `conversationId`, and drop early decisions attributed to it. Called
   * when the user sends a new message in that conversation. Returns
   * how many waiting interactions were cancelled.
   */
  cancelConversation(conversationId: string): number {
    for (const [callId, e] of this.early) {
      if (e.conversationId === conversationId) this.early.delete(callId)
    }
    return this.cancelWhere((ctx) => ctx.conversationId === conversationId)
  }

  /**
   * Deny every approval and skip every question raised by `turnId` (the
   * user stopped that turn), dropping early decisions attributed to its
   * conversation. Returns how many waiting interactions were cancelled.
   */
  cancelTurn(turnId: string): number {
    const conversations = new Set<string>()
    for (const p of [...this.approvals.values(), ...this.questions.values()]) {
      if (p.ctx.turnId === turnId) conversations.add(p.ctx.conversationId)
    }
    for (const [callId, e] of this.early) {
      if (e.conversationId !== undefined && conversations.has(e.conversationId))
        this.early.delete(callId)
    }
    return this.cancelWhere((ctx) => ctx.turnId === turnId)
  }

  /** Deny / skip everything (shutdown). */
  cancelAll(): number {
    this.early.clear()
    return this.cancelWhere(() => true)
  }

  private cancelWhere(match: (ctx: ToolCallContext) => boolean): number {
    let n = 0
    for (const [callId, p] of this.approvals) {
      if (!match(p.ctx)) continue
      this.approvals.delete(callId)
      p.resolve('deny')
      n++
    }
    for (const [callId, p] of this.questions) {
      if (!match(p.ctx)) continue
      this.questions.delete(callId)
      p.resolve('')
      n++
    }
    return n
  }
}
