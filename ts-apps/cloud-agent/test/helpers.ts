import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { createServer, type IncomingMessage, type Server } from 'node:http'
import type { AddressInfo } from 'node:net'
import { tmpdir } from 'node:os'
import * as path from 'node:path'
import type {
  DirectiveResultRow,
  L4Diagnostic,
  L4Language,
  Logger,
  LspLocation,
  SemanticTokensSnapshot,
} from '@repo/legalese-agent'
import type { CloudEvent } from '@repo/legalese-agent/protocol'
import { DirectiveResultsCache } from '@repo/legalese-agent'

export const SID = '01J9Z3K4M5N6P7Q8R9S0T1V2W3'

export async function tempDir(prefix = 'cloud-agent-test-'): Promise<{
  dir: string
  cleanup: () => Promise<void>
}> {
  const dir = await mkdtemp(path.join(tmpdir(), prefix))
  return { dir, cleanup: () => rm(dir, { recursive: true, force: true }) }
}

export class MemoryLogger implements Logger {
  readonly lines: Array<{ level: string; message: string }> = []
  info(message: string): void {
    this.lines.push({ level: 'info', message })
  }
  warn(message: string): void {
    this.lines.push({ level: 'warn', message })
  }
  error(message: string, err?: unknown): void {
    this.lines.push({
      level: 'error',
      message: err ? `${message}: ${String(err)}` : message,
    })
  }
  debug(message: string): void {
    this.lines.push({ level: 'debug', message })
  }
  has(level: string, re: RegExp): boolean {
    return this.lines.some((l) => l.level === level && re.test(l.message))
  }
}

export const silent: Logger = {
  info: () => undefined,
  warn: () => undefined,
  error: () => undefined,
  debug: () => undefined,
}

/** Read every event from the session's log, following head.json. */
export async function readEvents(stateDir: string): Promise<CloudEvent[]> {
  let head: { segment: number; length: number }
  try {
    head = JSON.parse(await readFile(path.join(stateDir, 'head.json'), 'utf8'))
  } catch {
    return []
  }
  const out: CloudEvent[] = []
  for (let n = 1; n <= head.segment; n++) {
    let buf = await readFile(path.join(stateDir, 'events', `${n}.jsonl`))
    if (n === head.segment) buf = buf.subarray(0, head.length)
    for (const line of buf.toString('utf8').split('\n')) {
      if (line.trim()) out.push(JSON.parse(line) as CloudEvent)
    }
  }
  return out
}

export async function waitUntil(
  cond: () => boolean | Promise<boolean>,
  timeoutMs = 5_000,
  what = 'condition'
): Promise<void> {
  const end = Date.now() + timeoutMs
  while (Date.now() < end) {
    if (await cond()) return
    await new Promise((r) => setTimeout(r, 10))
  }
  throw new Error(`timed out waiting for ${what}`)
}

/** A language server that knows nothing (the runner tests don't compile L4). */
export class StubL4 implements L4Language {
  readonly directives = new DirectiveResultsCache()
  disposed = false
  async openDocument(): Promise<{ lineCount: number; version: number }> {
    return { lineCount: 1, version: 1 }
  }
  async getDiagnostics(): Promise<L4Diagnostic[]> {
    return []
  }
  getDirectiveResults(uri: string): DirectiveResultRow[] | undefined {
    return this.directives.get(uri)
  }
  awaitDirectiveResults(uri: string, timeoutMs: number): Promise<void> {
    return this.directives.waitForNext(uri, Math.min(timeoutMs, 5))
  }
  async findReferences(): Promise<LspLocation[]> {
    return []
  }
  async getSemanticTokens(): Promise<SemanticTokensSnapshot | null> {
    return null
  }
  async getExportedFunctions(): Promise<never[]> {
    return []
  }
  async dispose(): Promise<void> {
    this.disposed = true
  }
}

// ── A scripted ai-proxy ──────────────────────────────────────────────

export const chunk = (delta: unknown, finish?: string): string =>
  `data: ${JSON.stringify({
    choices: [{ delta, ...(finish ? { finish_reason: finish } : {}) }],
  })}`

export const metadata = (conversationId: string): string =>
  `event: metadata\ndata: ${JSON.stringify({ conversationId, model: 'm1' })}`

export const toolCall = (id: string, name: string, args: unknown): string =>
  chunk({
    tool_calls: [
      { index: 0, id, function: { name, arguments: JSON.stringify(args) } },
    ],
  })

export interface ProxyRequest {
  url: string
  headers: IncomingMessage['headers']
  body: Record<string, unknown>
}

/**
 * A local HTTP ai-proxy: each chat request gets the next scripted SSE
 * response (or `status` for an error); title requests get a title.
 */
export class FakeAiProxy {
  readonly requests: ProxyRequest[] = []
  readonly scripts: Array<string[] | { status: number; body: unknown }> = []
  /** Resolves a held response when set (to test waiting). */
  hold: Promise<void> | null = null
  private server: Server | null = null

  async start(): Promise<string> {
    this.server = createServer((req, res) => {
      let raw = ''
      req.setEncoding('utf8')
      req.on('data', (c: string) => (raw += c))
      req.on('end', () => {
        void (async () => {
          const body = (raw ? JSON.parse(raw) : {}) as Record<string, unknown>
          this.requests.push({ url: req.url ?? '', headers: req.headers, body })
          if (body.model === 'legalese-summize-4') {
            return this.sse(res, [chunk({ content: 'A title' }, 'stop')])
          }
          if (this.hold) await this.hold
          const next = this.scripts.shift()
          if (!next) {
            res.writeHead(500, { 'content-type': 'application/json' })
            res.end(JSON.stringify({ error: { message: 'no script' } }))
            return
          }
          if (!Array.isArray(next)) {
            res.writeHead(next.status, { 'content-type': 'application/json' })
            res.end(JSON.stringify(next.body))
            return
          }
          this.sse(res, next)
        })()
      })
    })
    await new Promise<void>((r) => this.server!.listen(0, '127.0.0.1', r))
    const { port } = this.server.address() as AddressInfo
    return `http://127.0.0.1:${port}`
  }

  chatRequests(): ProxyRequest[] {
    return this.requests.filter((r) => r.body.model !== 'legalese-summize-4')
  }

  private sse(res: import('node:http').ServerResponse, frames: string[]): void {
    res.writeHead(200, { 'content-type': 'text/event-stream' })
    res.end(frames.map((f, i) => `id: ${i + 1}\n${f}\n\n`).join(''))
  }

  async stop(): Promise<void> {
    await new Promise<void>((r) => this.server?.close(() => r()) ?? r())
  }
}
