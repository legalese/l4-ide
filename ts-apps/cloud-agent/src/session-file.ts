import * as path from 'node:path'
import {
  SESSION_TITLE_MAX,
  parseJsonText,
  sessionFile,
  type AgentKeyFailure,
  type SessionFile,
  type SessionFileStatus,
} from '@repo/legalese-agent/protocol'
import { readKnownText, writeAtomic } from './safe-fs.js'

const MAX_SESSION_JSON = 256 * 1024

export interface SessionFileUpdate {
  status?: SessionFileStatus
  /** `null` clears it. */
  parkedReason?: AgentKeyFailure | null
  conversationId?: string
  lastActivity?: number
  title?: string
}

/**
 * `session.json` (spec §4.2): created by the Sessions API, updated by
 * the harness (status, conversation id, last activity, parked reason).
 * Updates are read-modify-write through a temp file + rename; fields
 * the harness doesn't know are kept as they are.
 */
export class SessionJson {
  /** Updates run one at a time, so concurrent ones don't lose writes. */
  private queue: Promise<unknown> = Promise.resolve()

  constructor(private readonly sessionDir: string) {}

  private get file(): string {
    return path.join(this.sessionDir, 'session.json')
  }

  async read(): Promise<SessionFile> {
    const raw = await this.readRaw()
    return sessionFile(raw, 'session.json')
  }

  update(change: SessionFileUpdate): Promise<SessionFile> {
    const run = this.queue.then(
      () => this.apply(change),
      () => this.apply(change)
    )
    this.queue = run.catch(() => undefined)
    return run
  }

  private async apply(change: SessionFileUpdate): Promise<SessionFile> {
    const raw = (await this.readRaw()) as Record<string, unknown>
    const next: Record<string, unknown> = { ...raw }
    if (change.status !== undefined) next.status = change.status
    if (change.parkedReason === null) delete next.parkedReason
    else if (change.parkedReason !== undefined) {
      next.parkedReason = change.parkedReason
    }
    if (change.conversationId !== undefined) {
      next.conversationId = change.conversationId
    }
    if (change.lastActivity !== undefined) {
      next.lastActivity = Math.max(
        change.lastActivity,
        typeof raw.lastActivity === 'number' ? raw.lastActivity : 0
      )
    }
    if (change.title !== undefined) {
      next.title = change.title.slice(0, SESSION_TITLE_MAX)
    }
    // Validate what we're about to write.
    const checked = sessionFile(next, 'session.json')
    await writeAtomic(this.file, JSON.stringify(next, null, 2) + '\n')
    return checked
  }

  private async readRaw(): Promise<unknown> {
    const text = await readKnownText(this.file, MAX_SESSION_JSON)
    if (text === null) throw new Error('session.json is missing')
    const raw = parseJsonText(text)
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      throw new Error('session.json is not an object')
    }
    return raw
  }
}
