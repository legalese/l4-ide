/**
 * Text from a cloud session in VS Code notifications. VS Code renders
 * `[label](link)` in a notification as a link, `command:` links
 * included, and a session's text (its questions, file names) can come
 * from a prompt injection: so notifications use fixed text, or this.
 * No `vscode` import (unit-tested).
 */

/**
 * Session-supplied text for a notification: no link syntax (`[` `]`),
 * no backticks or control characters, at most `max` characters.
 */
export function notificationText(text: string, max = 80): string {
  // eslint-disable-next-line no-control-regex
  const plain = text.replace(/[[\]`\u0000-\u001f\u007f]/g, '').trim()
  return plain.length > max ? `${plain.slice(0, max - 1)}…` : plain
}

/** The notification for a `local-merge-conflict` (§9.1). */
export function mergeConflictMessage(files: string[]): string {
  const shown = files
    .slice(0, 3)
    .map((f) => notificationText(f, 60))
    .join(', ')
  const more = files.length > 3 ? ` and ${files.length - 3} more` : ''
  return `Your synced changes conflict with the cloud session's and were not merged (${shown}${more}). Resolve the conflict in your clone, then sync again.`
}
