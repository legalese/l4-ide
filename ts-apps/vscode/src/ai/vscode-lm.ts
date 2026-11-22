import * as vscode from 'vscode'
import type { LmTools } from './web-fetch-tool.js'

/** True for the cancellation VS Code raises when the user turns down a
 *  tool's confirmation dialog. Across the extension-host boundary it can
 *  arrive as a plain Error named `Canceled`. */
function isCancellation(err: unknown): boolean {
  return (
    err instanceof vscode.CancellationError ||
    (err instanceof Error && err.name === 'Canceled')
  )
}

/** {@link LmTools} over `vscode.lm`: tools are invoked outside a chat
 *  session (no invocation token), so VS Code confirms in a dialog. */
export const vscodeLmTools: LmTools = {
  has: (name) => vscode.lm.tools.some((t) => t.name === name),
  async invoke(name, input) {
    try {
      const result = await vscode.lm.invokeTool(name, {
        input,
        toolInvocationToken: undefined,
      })
      const text = result.content
        .filter(
          (p): p is vscode.LanguageModelTextPart =>
            p instanceof vscode.LanguageModelTextPart
        )
        .map((p) => p.value)
        .join('\n')
      return { kind: 'ok', text }
    } catch (err) {
      if (isCancellation(err)) return { kind: 'declined' }
      throw err
    }
  },
}
