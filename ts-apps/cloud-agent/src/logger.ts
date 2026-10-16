import type { Logger } from '@repo/legalese-agent'

export type LogLevel = 'error' | 'warn' | 'info' | 'debug'

export const LOG_LEVELS: readonly LogLevel[] = [
  'error',
  'warn',
  'info',
  'debug',
]

const RANK: Record<LogLevel, number> = { error: 0, warn: 1, info: 2, debug: 3 }

/** Longest message written, after redaction. */
const MAX_MESSAGE = 500

/**
 * Structured stdout logger for the harness (spec §13): one JSON object
 * per line, `{ ts, level, msg, sid, err? }`, picked up by `awslogs`.
 *
 * Logs carry ids, tool names, durations and errors — never prompt
 * text, model output or file content. The agent core logs a few lines
 * with tool arguments (`tool/dispatch … args=…`); {@link redact} drops
 * those tails, and every message is capped at {@link MAX_MESSAGE}
 * characters so an error that quotes content can't leak much of it.
 * `LOG_LEVEL=debug` keeps the same redaction.
 */
export class JsonLogger implements Logger {
  constructor(
    private readonly level: LogLevel,
    private readonly fields: Record<string, string> = {},
    private readonly write: (line: string) => void = (line) =>
      process.stdout.write(line)
  ) {}

  info(message: string): void {
    this.log('info', message)
  }

  warn(message: string): void {
    this.log('warn', message)
  }

  error(message: string, err?: unknown): void {
    this.log('error', message, err)
  }

  debug(message: string): void {
    this.log('debug', message)
  }

  private log(level: LogLevel, message: string, err?: unknown): void {
    if (RANK[level] > RANK[this.level]) return
    const entry: Record<string, unknown> = {
      ts: new Date().toISOString(),
      level,
      msg: redact(message),
      ...this.fields,
    }
    if (err !== undefined) {
      entry.err = redact(
        err instanceof Error ? `${err.name}: ${err.message}` : String(err)
      )
    }
    this.write(JSON.stringify(entry) + '\n')
  }
}

/** Strip content-bearing tails and cap the length. */
export function redact(message: string): string {
  let m = message.replace(
    /\s(?:args|argsJson|text|body)=[\s\S]*$/,
    ' [redacted]'
  )
  if (m.length > MAX_MESSAGE) m = m.slice(0, MAX_MESSAGE) + '…'
  return m
}

export function parseLogLevel(raw: string | undefined): LogLevel | null {
  if (raw === undefined || raw === '') return 'info'
  const v = raw.toLowerCase()
  return (LOG_LEVELS as readonly string[]).includes(v) ? (v as LogLevel) : null
}
