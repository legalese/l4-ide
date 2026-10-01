import * as vscode from 'vscode'
import type { EditorContext, EditorContextInfo } from '@repo/legalese-agent'

/**
 * {@link EditorContext} port over the VS Code window: what the user is
 * looking at, for the per-turn `<editor-context>` message (formatted by
 * the core's `buildEditorContextMessage`) and the active L4 document
 * for the first-turn `<workspace-exports>`.
 *
 * `chip`, when provided, is the active-file state the webview was
 * showing at send time. It overrides `vscode.window.activeTextEditor`
 * so the message reflects exactly what the user saw on the chip — even
 * across multi-window setups (each window has its own
 * activeTextEditor) or focus changes between chip update and request
 * assembly. cursorLine / selection / openFiles still come from the live
 * editor (those are inherently editor-scoped and the snapshot doesn't
 * carry them).
 */
export class VsCodeEditorContext implements EditorContext {
  describe(chip?: { name: string; path: string }): EditorContextInfo | null {
    const editor = vscode.window.activeTextEditor
    const visibleFiles = vscode.window.visibleTextEditors
      .filter(
        (e) => e.document.languageId === 'l4' || e.document.languageId === 'jl4'
      )
      .map((e) => workspaceRelative(e.document.uri))
    if (!chip && !editor && visibleFiles.length === 0) return null

    const info: EditorContextInfo = {}

    // Find the editor that's actually showing the chip's path. We look
    // through every visible editor (not just `activeTextEditor`) so a
    // focus race between chip update and request assembly — or the
    // sidebar webview itself momentarily owning focus — can't drop
    // the selection. activeTextEditor is preferred when it matches so
    // split-pane setups use the focused pane.
    let snapshotEditor: vscode.TextEditor | undefined
    if (chip) {
      if (editor && workspaceRelative(editor.document.uri) === chip.path) {
        snapshotEditor = editor
      } else {
        snapshotEditor = vscode.window.visibleTextEditors.find(
          (e) => workspaceRelative(e.document.uri) === chip.path
        )
      }
    }
    const snapshotMatchesLiveEditor = !!snapshotEditor

    if (chip) {
      // Snapshot wins — use the path the webview chip was showing at
      // send time. Live editor state (cursor / selection) only flows
      // through when SOME visible editor in this window shows the same
      // file.
      info.activeFile = { path: chip.path }
      if (snapshotEditor) {
        info.activeFile.cursorLine = snapshotEditor.selection.active.line + 1
        if (!snapshotEditor.selection.isEmpty) {
          info.activeFile.selectionLines = {
            start: snapshotEditor.selection.start.line + 1,
            end: snapshotEditor.selection.end.line + 1,
          }
        }
      }
    } else if (editor) {
      const uri = editor.document.uri
      info.activeFile = {
        path: workspaceRelative(uri),
        outsideWorkspace:
          uri.scheme === 'file' && !vscode.workspace.getWorkspaceFolder(uri),
        cursorLine: editor.selection.active.line + 1,
      }
      if (!editor.selection.isEmpty) {
        info.activeFile.selectionLines = {
          start: editor.selection.start.line + 1,
          end: editor.selection.end.line + 1,
        }
      }
    }
    // Only surface `openFiles` from the live window when there's no
    // snapshot OR the snapshot points at a file that's also visible
    // in this window. Otherwise the visible-files list belongs to a
    // different VSCode window than the activeFile line and would
    // mislead the model.
    const showOpenFiles = !chip || snapshotMatchesLiveEditor
    if (showOpenFiles && visibleFiles.length > 0) {
      info.openFiles = visibleFiles
    }
    return info
  }

  activeL4Document(): { uri: string; version: number } | null {
    const editor = vscode.window.activeTextEditor
    if (
      !editor ||
      (editor.document.languageId !== 'l4' &&
        editor.document.languageId !== 'jl4')
    ) {
      return null
    }
    return {
      uri: editor.document.uri.toString(),
      version: editor.document.version,
    }
  }
}

function workspaceRelative(uri: vscode.Uri): string {
  const folder = vscode.workspace.getWorkspaceFolder(uri)
  if (!folder) return uri.fsPath
  return vscode.workspace.asRelativePath(uri, false)
}
