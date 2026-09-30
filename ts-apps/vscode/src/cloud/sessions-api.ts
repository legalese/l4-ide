/**
 * Client for the Sessions API (spec §7.1, §8, §15.5). Every call carries
 * the WorkOS access token; a 401 refreshes it once and retries. Errors
 * come back as {@link SessionsApiError} with the `{ error }` code.
 *
 * No `vscode` import (unit-tested with a stubbed fetch).
 */
import {
  ProtocolError,
  addFilesRequest,
  addFilesResponse,
  apiError,
  clientCommand,
  createSessionRequest,
  createSessionResponse,
  formatEventsQuery,
  getSessionResponse,
  listSessionsResponse,
  parseEventStream,
  postCommandResponse,
  sessionStateResponse,
  type AddFilesRequest,
  type AddFilesResponse,
  type Check,
  type ClientCommandPayload,
  type CreateSessionRequest,
  type CreateSessionResponse,
  type EventStreamError,
  type EventStreamRequest,
  type EventStreamResponse,
  type GetSessionResponse,
  type ListSessionsResponse,
  type PostCommandResponse,
  type PresignedUpload,
  type SessionState,
} from '@repo/legalese-agent/protocol'
import type { FetchFn } from './auth-proxy.js'

export class SessionsApiError extends Error {
  constructor(
    readonly status: number,
    /** The `{ error }` code, e.g. `too_many_sessions`, `not_found`. */
    readonly code: string,
    message?: string
  ) {
    super(message ?? describeSessionsApiError(status, code))
    this.name = 'SessionsApiError'
  }
}

/** A user-facing sentence for a Sessions API error. */
export function describeSessionsApiError(status: number, code: string): string {
  switch (code) {
    case 'too_many_sessions':
      return 'Too many cloud sessions are running. Stop one and try again.'
    case 'start_failed':
      return 'The cloud session could not start. Try again in a minute.'
    case 'unavailable':
      return 'Cloud sessions are temporarily unavailable. Try again later.'
    case 'not_initialized':
      return 'The cloud session was not set up completely. Start a new one.'
    case 'stopping':
      return 'The cloud session is still stopping. Try again in a minute.'
    case 'invalid_seed':
      return 'The files for the cloud session were rejected.'
    case 'too_large':
      return 'The upload is too large for a cloud session.'
    case 'not_found':
      return 'This cloud session no longer exists.'
    case 'unauthenticated':
      return 'Sign in to Legalese Cloud to use cloud sessions.'
    case 'forbidden':
      return 'Your account is not allowed to use cloud sessions.'
    default:
      return `Cloud sessions request failed (HTTP ${status}${code ? `, ${code}` : ''}).`
  }
}

export interface SessionsApiDeps {
  /** The `legaleseAi.cloudSessions.apiUrl` setting; '' = off. */
  baseUrl: () => string
  /** WorkOS access token; `force` bypasses the cache. */
  getAccessToken: (opts?: { force?: boolean }) => Promise<string>
  fetch?: FetchFn
}

const REQUEST_TIMEOUT_MS = 30_000
const UPLOAD_TIMEOUT_MS = 10 * 60_000

/** The subset of the client the session manager uses (tests fake it). */
export interface SessionsApi {
  createSession(req: CreateSessionRequest): Promise<CreateSessionResponse>
  upload(target: PresignedUpload, body: Uint8Array): Promise<void>
  initSession(sid: string): Promise<SessionState>
  listSessions(): Promise<ListSessionsResponse>
  getSession(sid: string): Promise<GetSessionResponse>
  startSession(sid: string, agentKey: string): Promise<SessionState>
  postCommand(
    sid: string,
    command: ClientCommandPayload
  ): Promise<PostCommandResponse>
  stopSession(sid: string): Promise<SessionState>
  /** Add files mid-session: pre-signed PUTs for a batch… */
  addFiles(sid: string, req: AddFilesRequest): Promise<AddFilesResponse>
  /** …then queue it for the harness (`add-files`). */
  commitFiles(sid: string, batchId: string): Promise<PostCommandResponse>
  deleteSession(sid: string): Promise<void>
  getEvents(
    streams: EventStreamRequest[]
  ): Promise<{ streams: Array<EventStreamResponse | EventStreamError> }>
}

export class SessionsApiClient implements SessionsApi {
  private readonly fetchFn: FetchFn

  constructor(private readonly deps: SessionsApiDeps) {
    this.fetchFn = deps.fetch ?? fetch
  }

  /** Base URL without a trailing slash; throws when the feature is off. */
  base(): string {
    const url = this.deps.baseUrl().trim().replace(/\/+$/, '')
    if (!url)
      throw new SessionsApiError(
        0,
        'disabled',
        'Cloud sessions are not configured.'
      )
    return url
  }

  /** `<apiUrl>/git/<sid>.git` (§9.2). */
  gitUrl(sid: string): string {
    return `${this.base()}/git/${sid}.git`
  }

  private async request<T>(
    method: string,
    path: string,
    check: Check<T> | null,
    body?: unknown
  ): Promise<T> {
    const url = `${this.base()}${path}`
    const send = async (force: boolean): Promise<Response> => {
      const token = await this.deps.getAccessToken({ force })
      return this.fetchFn(url, {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        },
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      })
    }
    let res = await send(false)
    if (res.status === 401) res = await send(true)
    if (!res.ok) {
      let code = ''
      try {
        code = apiError(await res.json(), 'error').error
      } catch {
        // not a JSON error body
      }
      throw new SessionsApiError(res.status, code)
    }
    if (check === null) return undefined as T
    try {
      return check(await res.json(), 'response')
    } catch (err) {
      if (err instanceof ProtocolError || err instanceof SyntaxError) {
        throw new SessionsApiError(
          res.status,
          'bad_response',
          `Unexpected response from the Sessions API (${err.message}).`
        )
      }
      throw err
    }
  }

  async createSession(
    req: CreateSessionRequest
  ): Promise<CreateSessionResponse> {
    return this.request(
      'POST',
      '/sessions',
      createSessionResponse,
      createSessionRequest(req, 'request')
    )
  }

  /** PUT to a pre-signed inbox URL with the headers it came with. */
  async upload(target: PresignedUpload, body: Uint8Array): Promise<void> {
    if (target.maxBytes !== undefined && body.byteLength > target.maxBytes) {
      throw new SessionsApiError(413, 'too_large')
    }
    const res = await this.fetchFn(target.url, {
      method: target.method,
      headers: target.headers,
      body,
      signal: AbortSignal.timeout(UPLOAD_TIMEOUT_MS),
    })
    if (!res.ok) {
      throw new SessionsApiError(
        res.status,
        'upload_failed',
        `Uploading to the cloud session failed (HTTP ${res.status}).`
      )
    }
  }

  async initSession(sid: string): Promise<SessionState> {
    return (
      await this.request(
        'POST',
        `/sessions/${sid}/init`,
        sessionStateResponse,
        {}
      )
    ).state
  }

  async listSessions(): Promise<ListSessionsResponse> {
    return this.request('GET', '/sessions', listSessionsResponse)
  }

  async getSession(sid: string): Promise<GetSessionResponse> {
    return this.request('GET', `/sessions/${sid}`, getSessionResponse)
  }

  async startSession(sid: string, agentKey: string): Promise<SessionState> {
    return (
      await this.request(
        'POST',
        `/sessions/${sid}/start`,
        sessionStateResponse,
        {
          agentKey,
        }
      )
    ).state
  }

  async postCommand(
    sid: string,
    command: ClientCommandPayload
  ): Promise<PostCommandResponse> {
    return this.request(
      'POST',
      `/sessions/${sid}/commands`,
      postCommandResponse,
      clientCommand(command, 'command')
    )
  }

  async addFiles(sid: string, req: AddFilesRequest): Promise<AddFilesResponse> {
    return this.request(
      'POST',
      `/sessions/${sid}/files`,
      addFilesResponse,
      addFilesRequest(req, 'request')
    )
  }

  async commitFiles(
    sid: string,
    batchId: string
  ): Promise<PostCommandResponse> {
    return this.request(
      'POST',
      `/sessions/${sid}/files/${batchId}/commit`,
      postCommandResponse
    )
  }

  async stopSession(sid: string): Promise<SessionState> {
    return (
      await this.request(
        'POST',
        `/sessions/${sid}/stop`,
        sessionStateResponse,
        {}
      )
    ).state
  }

  async deleteSession(sid: string): Promise<void> {
    await this.request('DELETE', `/sessions/${sid}`, null)
  }

  /**
   * `GET /events` for up to 10 sessions. Invalid events are dropped
   * per session (one bad line mustn't stall the view); a malformed
   * envelope fails the call.
   */
  async getEvents(
    streams: EventStreamRequest[]
  ): Promise<{ streams: Array<EventStreamResponse | EventStreamError> }> {
    const raw = await this.request(
      'GET',
      `/events?${formatEventsQuery(streams)}`,
      (v, path) => {
        // Validate the outer shape only; events are checked leniently.
        const sessions = (v as { sessions?: unknown })?.sessions
        if (!Array.isArray(sessions)) {
          throw new ProtocolError('expected sessions', path)
        }
        return sessions as unknown[]
      }
    )
    return { streams: raw.map((s) => parseEventStream(s).stream) }
  }
}
