import type { AiChatMessage } from 'jl4-client-rpc'
import type { EditorContextInfo, L4Language } from './ports.js'

/**
 * Build the per-turn `<editor-context>` system message that tells the
 * model what the user is currently looking at. Only references the
 * active file by path — the model is expected to call `fs__read_file`
 * if it decides the body is worth reading. Sent as a second system
 * message (after ai-proxy's cached L4 reference) so it doesn't break
 * the provider's prompt cache. Only built when the user has the
 * "attach active file" chip enabled for this turn.
 *
 * The host's {@link EditorContext} resolves the chip snapshot against
 * its live editors; this function only formats the result.
 */
export function buildEditorContextMessage(
  info: EditorContextInfo | null
): AiChatMessage | null {
  if (!info) return null
  const lines: string[] = []
  lines.push('<editor-context>')
  const active = info.activeFile
  if (active) {
    lines.push(
      active.outsideWorkspace
        ? `activeFile: ${active.path} (outside every loaded workspace folder — fs tools cannot read/edit/delete it)`
        : `activeFile: ${active.path} (call fs__read_file on this path if you need the body)`
    )
    if (active.cursorLine !== undefined) {
      lines.push(`cursorLine: ${active.cursorLine}`)
    }
    // The selection range is emitted as a pointer, not as content — the
    // model can call `fs__read_file` with a line range if it actually
    // wants the bytes, which keeps the system message tight on context.
    if (active.selectionLines) {
      lines.push(
        `selectionLines: ${active.selectionLines.start}-${active.selectionLines.end}`
      )
    }
  }
  if (info.openFiles && info.openFiles.length > 0) {
    lines.push('openFiles:')
    for (const f of info.openFiles) lines.push(`  - ${f}`)
  }
  lines.push('</editor-context>')
  return { role: 'system', content: lines.join('\n') }
}

/**
 * Build a `<session-context>` system message carrying the runtime
 * facts the model otherwise has no way to know: the org-specific
 * deployment URL the user is signed in to, and the client build the
 * request is coming from. Sent as an additional system message so it
 * doesn't invalidate the ai-proxy's cached L4 prompt prefix, and only
 * on the first turn of a conversation (matches workspace-exports).
 * Date/time/timezone are NOT here — those are inlined into the user
 * message every turn via {@link buildCurrentTimeBlock} so they stay
 * fresh on follow-ups (the proxy filters role:"system" out of the
 * per-turn delta).
 */
export function buildSessionContextMessage(
  deploymentUrl: string | undefined,
  extensionVersion: string
): AiChatMessage | null {
  const lines: string[] = []
  lines.push('<session-context>')
  if (deploymentUrl) {
    lines.push(`deploymentUrl: ${deploymentUrl}`)
  } else {
    lines.push('deploymentUrl: (none — user not signed in)')
  }
  lines.push(`l4VscodeExtensionVersion: ${extensionVersion}`)
  lines.push('</session-context>')
  return { role: 'system', content: lines.join('\n') }
}

/**
 * Build a `<methodology>` system message from the user's free-text
 * methodology preference. It's the user's own standing instruction on
 * how the model should approach the work — e.g. how to think about
 * encoding natural-language rules in L4 — so it rides as the last
 * system message before the first user prompt, where it sits closest to
 * the request it should shape.
 *
 * Only meaningful on the first turn of a non-deployment conversation;
 * the caller gates on `isNew && !deploymentMode`. Returns null when the
 * preference is unset or blank.
 */
export function buildMethodologyContextMessage(
  raw: string | undefined
): AiChatMessage | null {
  const text = (raw ?? '').trim()
  if (!text) return null
  return {
    role: 'system',
    content: ['<methodology>', text, '</methodology>'].join('\n'),
  }
}

/**
 * Build the per-turn `<current-time>` block, inlined as a text content
 * part on the user message every turn. It rides inside the user
 * message (not as a `role:"system"` message) because the ai-proxy's
 * extractDelta filters system messages out of follow-up-turn deltas —
 * a system message here would only land on turn 1. Inlining keeps the
 * timestamp fresh on every turn for "today" / "now" / relative-time
 * reasoning, in the user's IANA zone with a UTC fallback.
 */
export function buildCurrentTimeBlock(now: Date = new Date()): string {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
  return [
    '<current-time>',
    `localTime: ${now.toLocaleString(undefined, { timeZone: tz, timeZoneName: 'short' })}`,
    `timezone: ${tz}`,
    '</current-time>',
  ].join('\n')
}

/**
 * Build a `<mention-context>` system message for any `@`-mentions on
 * this turn. The user's text already carries the literal `@<label>`
 * token (so the visual chip survives), but the model treats it as an
 * arbitrary string until something tells it the token resolves to a
 * file path it can open. We surface those resolved paths separately
 * so the model knows which fs__read_file calls would actually work.
 *
 * Returns null when there are no mentions, or when every mention is a
 * non-path kind (selection / symbol — those are handled elsewhere).
 */
export function buildMentionContextMessage(
  mentions: Array<{ kind: 'file' | 'symbol' | 'selection'; label: string }>
): AiChatMessage | null {
  if (!mentions || mentions.length === 0) return null
  const files = mentions
    .filter((m) => m.kind === 'file')
    .map((m) => m.label)
    .filter((label) => label.length > 0)
  if (files.length === 0) return null
  // Dedupe while preserving the order the user picked them in.
  const seen = new Set<string>()
  const unique = files.filter((f) =>
    seen.has(f) ? false : (seen.add(f), true)
  )
  const lines: string[] = []
  lines.push('<mention-context>')
  lines.push(
    'The `@<path>` tokens in the user message resolve to these workspace files. Call fs__read_file on the path if you need the body:'
  )
  for (const f of unique) lines.push(`  - ${f}`)
  lines.push('</mention-context>')
  return { role: 'system', content: lines.join('\n') }
}

/**
 * Build the first-turn `<workspace-exports>` system message listing the
 * L4 functions the model should know about. Sent as a separate system
 * message so it doesn't invalidate the proxy's cached L4 reference.
 *
 * Narrow on purpose: the active L4 document's exports only (via the
 * language server). Expanding to a multi-file index can come later.
 */
export async function buildWorkspaceBootstrapMessage(
  activeL4Document: { uri: string; version: number } | null,
  l4: L4Language
): Promise<AiChatMessage | null> {
  const lines: string[] = []
  lines.push('<workspace-exports>')

  if (activeL4Document) {
    try {
      const fns = await l4.getExportedFunctions(activeL4Document)
      if (fns.length === 0) {
        lines.push('(no L4 exports defined in the active file yet)')
      } else {
        for (const fn of fns) {
          const props = fn.parameters?.properties ?? {}
          const params = Object.entries(props)
            .map(([name, spec]) => `${name}: ${formatParamType(spec)}`)
            .join(', ')
          const ret = fn.returnType ?? 'Any'
          lines.push(`- ${fn.name}(${params}) -> ${ret}`)
        }
      }
    } catch {
      lines.push('(exports unavailable — language server not ready)')
    }
  } else {
    lines.push('(no L4 file open)')
  }

  lines.push('</workspace-exports>')
  return { role: 'system', content: lines.join('\n') }
}

/**
 * Best-effort type stringifier for a `FunctionParameter`. The LSP sends
 * JSON-Schema-ish shapes; most useful for the AI is just the `type`
 * field, falling back to `Any` when untyped or a compound we'd rather
 * not serialize inline.
 */
function formatParamType(spec: unknown): string {
  if (!spec || typeof spec !== 'object') return 'Any'
  const rec = spec as Record<string, unknown>
  if (typeof rec.type === 'string') return rec.type
  return 'Any'
}
