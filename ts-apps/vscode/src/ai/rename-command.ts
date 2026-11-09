import * as vscode from 'vscode'
import {
  IDENTIFIER_TOKEN_TYPES,
  classifyAnchorToken,
  type BuiltinTools,
} from '@repo/legalese-agent'

/**
 * VSCode command entry-point: prompts the user for a new name based on
 * the identifier under the cursor, then drives the core's `l4__refactor`
 * rename. Registered as `l4.renameIdentifier` so it's reachable from the
 * command palette (and bindable to a keystroke by the user).
 */
export async function commandRenameIdentifier(
  tools: BuiltinTools
): Promise<void> {
  const notOnIdentifier = (): void =>
    void vscode.window.showInformationMessage(
      'Cursor position is not targeting a valid L4 identifier.'
    )

  const editor = vscode.window.activeTextEditor
  if (!editor || editor.document.languageId !== 'l4') {
    notOnIdentifier()
    return
  }
  const doc = editor.document
  const pos = editor.selection.active
  const oldName = identifierAtPosition(doc, pos)
  if (!oldName) {
    notOnIdentifier()
    return
  }
  // Confirm via the LSP that the cursor isn't on a keyword/directive/
  // annotation that just happens to look identifier-shaped to the text
  // heuristic. `null` means the LSP can't tell yet (file not
  // type-checked) — fall through and let the rename pipeline make the
  // final call.
  const tokenType = await classifyAnchorToken(tools.l4, doc.uri.toString(), {
    line: pos.line,
    character: pos.character,
  })
  if (tokenType !== null && !IDENTIFIER_TOKEN_TYPES.has(tokenType)) {
    notOnIdentifier()
    return
  }
  const newName = await vscode.window.showInputBox({
    prompt: `Rename "${oldName}" to (backticks added automatically when the new name contains spaces or punctuation):`,
    value: oldName,
    validateInput: (v) => {
      const trimmed = (v ?? '').trim().replace(/^`+|`+$/g, '')
      if (!trimmed) return 'New name cannot be empty.'
      if (trimmed.includes('`'))
        return 'Backticks are not allowed inside the name — type it bare; quoting is added on write.'
      return null
    },
  })
  if (newName === undefined) return
  const normalisedNew = newName.trim().replace(/^`+|`+$/g, '')
  if (!normalisedNew || normalisedNew === oldName) return
  try {
    const result = await tools.refactor({
      action: 'rename',
      path: doc.uri.fsPath,
      oldName,
      newName: normalisedNew,
    })
    void vscode.window.showInformationMessage(result)
  } catch (err) {
    void vscode.window.showErrorMessage(
      err instanceof Error ? err.message : String(err)
    )
  }
}

/** Extract the L4 identifier at `pos`. Handles both backticked names
 *  (`\`foo bar\``) and bare identifiers. Returns the bare name (no
 *  surrounding backticks) — the rest of the rename pipeline always
 *  wraps as needed. */
function identifierAtPosition(
  doc: vscode.TextDocument,
  pos: vscode.Position
): string | null {
  const lineText = doc.lineAt(pos.line).text
  const col = pos.character
  // Backticked form: scan for a pair of backticks that bracket `col`.
  // We look for the nearest ` to the left and the nearest ` to the
  // right, on the same line — quoted names can't span newlines.
  const left = lineText.lastIndexOf('`', col - 1)
  const right = left >= 0 ? lineText.indexOf('`', left + 1) : -1
  if (left >= 0 && right > left && col >= left && col <= right + 1) {
    const inner = lineText.slice(left + 1, right)
    if (inner.length > 0) return inner
  }
  // Bare identifier — expand left/right while we stay inside [A-Za-z0-9_].
  const isIdent = (c: string): boolean => /[A-Za-z0-9_]/.test(c)
  let start = col
  while (start > 0 && isIdent(lineText[start - 1]!)) start--
  let end = col
  while (end < lineText.length && isIdent(lineText[end]!)) end++
  if (end === start) return null
  return lineText.slice(start, end)
}
