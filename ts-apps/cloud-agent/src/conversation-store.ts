import type {
  AiChatMessage,
  AiConversation,
  AiConversationSummary,
} from 'jl4-client-rpc'
import type { ConversationStore } from '@repo/legalese-agent'

/**
 * {@link ConversationStore} for a cloud session (spec §11:
 * "`session.json` + server-held conversation").
 *
 * The model context lives in ai-proxy's server-held conversation and
 * the transcript is the session's event log, so this store keeps no
 * messages. It remembers the one conversation's metadata in memory (so
 * the chat service's follow-up lookups work) and reports the
 * conversation id and generated title to the runner, which records
 * them in `session.json`.
 */
export class SessionConversationStore implements ConversationStore {
  private conv: AiConversation | null = null

  constructor(
    private readonly hooks: {
      onConversation?: (id: string) => void
      onTitle?: (id: string, title: string) => void
    } = {}
  ) {}

  async list(): Promise<AiConversationSummary[]> {
    return []
  }

  async load(id: string): Promise<AiConversation | null> {
    return this.conv && this.conv.id === id
      ? { ...this.conv, messages: [] }
      : null
  }

  async save(conv: AiConversation): Promise<void> {
    this.remember({ ...conv, messages: [] })
  }

  async delete(): Promise<boolean> {
    return false
  }

  async appendMessages(
    id: string,
    orgId: string,
    userId: string,
    model: string,
    titleHint: string,
    _messages: AiChatMessage[],
    extensionVersion?: string,
    deploymentId?: string,
    apiBaseUrl?: string
  ): Promise<AiConversation> {
    const now = new Date().toISOString()
    const same = this.conv?.id === id ? this.conv : null
    const conv: AiConversation = {
      id,
      orgId: orgId || same?.orgId || '',
      userId: userId || same?.userId || '',
      model: model || same?.model || '',
      title: same?.title || titleHint,
      createdAt: same?.createdAt ?? now,
      lastActiveAt: now,
      messages: [],
      ...(extensionVersion ? { extensionVersion } : {}),
      ...(deploymentId ? { deploymentId } : {}),
      ...(apiBaseUrl ? { apiBaseUrl } : {}),
    }
    this.remember(conv)
    return { ...conv }
  }

  async setTitle(id: string, title: string): Promise<void> {
    if (this.conv?.id === id) this.conv = { ...this.conv, title }
    this.hooks.onTitle?.(id, title)
  }

  private remember(conv: AiConversation): void {
    const isNew = this.conv?.id !== conv.id
    this.conv = conv
    if (isNew) this.hooks.onConversation?.(conv.id)
  }
}
