import * as vscode from 'vscode'
import * as path from 'path'
import { promises as fs, existsSync } from 'fs'
import {
  isHtmlPath,
  type ResolvedPath,
  type Workspace,
  type WorkspaceDirEntry,
  type WorkspaceStat,
  type WorkspaceTextEdit,
} from '@repo/legalese-agent'

/**
 * {@link Workspace} port over the VS Code workspace: tool paths resolve
 * against the loaded workspace folders (the active file's folder wins
 * in a multi-root workspace), reads go to disk, and writes go through
 * `workspace.applyEdit` + save so the L4 language server sees them via
 * didOpen/didChange and they join the undo stack.
 *
 * Editor side effects live here too: a created file opens as a tab,
 * and a created `.html` file opens in the built-in browser preview,
 * which live-refreshes as later edits land.
 */
export class VsCodeWorkspace implements Workspace {
  resolvePath(p: string): ResolvedPath {
    if (!p || typeof p !== 'string') {
      throw new Error('path is required')
    }
    const folders = vscode.workspace.workspaceFolders ?? []
    if (folders.length === 0) {
      throw new Error(
        'No workspace folder is open. fs tools only operate on files inside a loaded workspace folder.'
      )
    }
    // Candidate roots for relative paths. Active file's folder wins the
    // tiebreak so a tool call from inside a multi-root workspace lands
    // next to the file the user is looking at.
    const active = vscode.window.activeTextEditor?.document.uri
    const activeFolder = active
      ? vscode.workspace.getWorkspaceFolder(active)
      : undefined
    const roots: string[] = []
    if (activeFolder) roots.push(activeFolder.uri.fsPath)
    for (const f of folders) {
      if (!roots.includes(f.uri.fsPath)) roots.push(f.uri.fsPath)
    }
    const preferredBase = roots[0]!

    let absolute: string
    if (path.isAbsolute(p)) {
      absolute = p
    } else {
      // Try each root; first hit wins. If none exist, fall through to
      // the preferred base so create can land in a sensible location.
      let picked: string | null = null
      for (const root of roots) {
        const candidate = path.resolve(root, p)
        if (existsSync(candidate)) {
          picked = candidate
          break
        }
      }
      absolute = picked ?? path.resolve(preferredBase, p)
    }
    const insideWorkspace = folders.some(
      (f) =>
        absolute === f.uri.fsPath ||
        absolute.startsWith(f.uri.fsPath + path.sep)
    )
    if (!insideWorkspace) {
      throw new Error(
        `Path is outside every loaded workspace folder: ${p}. fs tools only operate on files inside a loaded workspace folder — ask the user to add the target folder to the workspace first.`
      )
    }
    return {
      relative:
        path.relative(preferredBase, absolute) || path.basename(absolute),
      uri: vscode.Uri.file(absolute).toString(),
      fsPath: absolute,
    }
  }

  relativePath(uri: string): string {
    const fsPath = vscode.Uri.parse(uri).fsPath
    const folders = vscode.workspace.workspaceFolders ?? []
    for (const f of folders) {
      if (fsPath === f.uri.fsPath) return path.basename(fsPath)
      if (fsPath.startsWith(f.uri.fsPath + path.sep)) {
        return path.relative(f.uri.fsPath, fsPath)
      }
    }
    return fsPath
  }

  pathForUri(uri: string): string {
    return vscode.Uri.parse(uri).fsPath
  }

  async stat(fsPath: string): Promise<WorkspaceStat | null> {
    try {
      const st = await fs.stat(fsPath)
      return { isDirectory: st.isDirectory(), isFile: st.isFile() }
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return null
      throw err
    }
  }

  async readDirectory(fsPath: string): Promise<WorkspaceDirEntry[]> {
    const entries = await fs.readdir(fsPath, { withFileTypes: true })
    return entries.map((e) => ({
      name: e.name,
      isDirectory: e.isDirectory(),
      isFile: e.isFile(),
    }))
  }

  readFile(fsPath: string): Promise<string> {
    return fs.readFile(fsPath, 'utf-8')
  }

  async readDocument(
    uri: string
  ): Promise<{ text: string; eol: '\n' | '\r\n' }> {
    const doc = await vscode.workspace.openTextDocument(vscode.Uri.parse(uri))
    return {
      text: doc.getText(),
      eol: doc.eol === vscode.EndOfLine.CRLF ? '\r\n' : '\n',
    }
  }

  async createFile(target: ResolvedPath, content: string): Promise<void> {
    const uri = vscode.Uri.file(target.fsPath)
    await fs.mkdir(path.dirname(target.fsPath), { recursive: true })
    // Route through VSCode's WorkspaceEdit so the LSP picks up the new
    // file via its normal didOpen path (otherwise a silent Node write
    // doesn't get didChange/didOpen events, and l4__evaluate can
    // return stale results for a freshly-created file).
    const edit = new vscode.WorkspaceEdit()
    edit.createFile(uri, { overwrite: false })
    edit.insert(uri, new vscode.Position(0, 0), content)
    const ok = await vscode.workspace.applyEdit(edit)
    if (!ok) {
      throw new Error(
        `fs__create_file: VSCode refused to create ${target.relative} (readonly workspace or similar).`
      )
    }
    // Persist to disk so subsequent non-VSCode readers (including our
    // own fs__read_file / fs.readFile) see the new content immediately.
    const doc = await vscode.workspace.openTextDocument(uri)
    if (doc.isDirty) await doc.save()
    if (isHtmlPath(target.fsPath)) {
      // Open the rendered page in the built-in browser preview rather
      // than a source tab — and live-refresh it as follow-up edits land.
      await htmlPreview.open(uri)
    } else {
      // Surface the new file as a visible tab so the user sees what the
      // model just created without having to expand the tool-call row
      // and click. `preserveFocus: true` keeps the cursor wherever the
      // user was — usually the chat input — instead of stealing focus
      // into the editor mid-conversation.
      await vscode.window.showTextDocument(doc, {
        preview: false,
        preserveFocus: true,
      })
    }
  }

  async applyEdits(edits: WorkspaceTextEdit[]): Promise<void> {
    const edit = new vscode.WorkspaceEdit()
    const docs = new Map<string, vscode.TextDocument>()
    for (const e of edits) {
      let doc = docs.get(e.uri)
      if (!doc) {
        doc = await vscode.workspace.openTextDocument(vscode.Uri.parse(e.uri))
        docs.set(e.uri, doc)
      }
      edit.replace(
        doc.uri,
        new vscode.Range(
          doc.positionAt(e.startOffset),
          doc.positionAt(e.endOffset)
        ),
        e.newText
      )
    }
    const ok = await vscode.workspace.applyEdit(edit)
    if (!ok) {
      throw new Error('VSCode refused to apply the edit')
    }
    // Persist every touched document so type-checks and disk-based
    // readers (fs__read_file, other extensions) see the change.
    for (const doc of docs.values()) {
      if (doc.isDirty) await doc.save()
      // If this is an HTML doc currently shown in the built-in browser
      // preview, reload the rendered page so it tracks the edit.
      if (isHtmlPath(doc.uri.fsPath))
        await htmlPreview.refreshIfShowing(doc.uri)
    }
  }

  async deleteFile(target: ResolvedPath): Promise<'trashed' | 'deleted'> {
    // Use VSCode's FS so the Trash is honored (user can recover).
    await vscode.workspace.fs.delete(vscode.Uri.file(target.fsPath), {
      recursive: false,
      useTrash: true,
    })
    return 'trashed'
  }
}

/**
 * A single reused webview panel acts as the "built-in browser" for
 * AI-created HTML files. Reused across creates so a new document
 * replaces the previous preview instead of stacking tabs. The
 * save-watcher keeps the rendered page in sync as follow-up
 * `fs__edit_file` calls build the document up (each one saves the
 * buffer, firing onDidSaveTextDocument).
 */
class HtmlPreview {
  private panel: vscode.WebviewPanel | undefined
  private uri: vscode.Uri | undefined
  private watcher: vscode.Disposable | undefined

  /**
   * Open (or refocus) the preview on an HTML file and point it at
   * `uri`. Renders the file's current contents in a webview panel
   * beside the chat, and live-refreshes whenever that file is saved so
   * the user watches the document take shape.
   */
  async open(uri: vscode.Uri): Promise<void> {
    const title = `Preview: ${path.basename(uri.fsPath)}`
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel(
        'l4.htmlPreview',
        title,
        // Beside the chat, without stealing focus from the conversation.
        { viewColumn: vscode.ViewColumn.Active, preserveFocus: true },
        {
          enableScripts: true,
          retainContextWhenHidden: true,
          localResourceRoots:
            vscode.workspace.workspaceFolders?.map((f) => f.uri) ?? [],
        }
      )
      this.panel.onDidDispose(() => {
        this.panel = undefined
        this.uri = undefined
        this.watcher?.dispose()
        this.watcher = undefined
      })
      // Manual saves (Cmd+S) also refresh — the edit tool path
      // refreshes explicitly via refreshIfShowing, but this keeps the
      // preview honest for any other writer too.
      this.watcher = vscode.workspace.onDidSaveTextDocument((doc) =>
        this.refreshIfShowing(doc.uri)
      )
    }
    this.uri = uri
    this.panel.title = title
    this.panel.webview.html = await readFileText(uri)
    this.panel.reveal(vscode.ViewColumn.Active, true)
  }

  /**
   * Reload the preview from disk when it is currently showing `uri`.
   * No-op when the panel is closed or pointed at a different file.
   */
  async refreshIfShowing(uri: vscode.Uri): Promise<void> {
    if (this.panel && this.uri && uri.toString() === this.uri.toString()) {
      this.panel.webview.html = await readFileText(uri)
    }
  }
}

const htmlPreview = new HtmlPreview()

/** Read a workspace file as UTF-8 text. */
async function readFileText(uri: vscode.Uri): Promise<string> {
  const bytes = await vscode.workspace.fs.readFile(uri)
  return Buffer.from(bytes).toString('utf8')
}
