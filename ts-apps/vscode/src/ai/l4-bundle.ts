import * as vscode from 'vscode'
import { GetExportedFunctionsRequestType } from 'jl4-client-rpc'
import type { VSCodeL4LanguageClient } from '../vscode-l4-language-client.js'
import type { AiLogger } from './logger.js'

/** A file uploaded to the cloud agent's workspace for a turn. */
export interface BundleFile {
  /** Path inside the agent workspace (basename — L4 imports resolve by
   *  module name within the same directory). */
  path: string
  /** Base64-encoded file bytes. */
  contentBase64: string
}

export interface L4Bundle {
  files: BundleFile[]
  activeFile?: { path: string; name: string }
}

/**
 * Gather the upload bundle for a cloud-agent turn: the active L4 file plus its
 * transitive `IMPORT` tree, resolved by the language server (the same
 * `GetExportedFunctions` request the deploy path uses). Files are flattened to
 * their basenames so `l4 run main.l4` resolves sibling imports in the agent's
 * scratch workspace.
 *
 * Best-effort: a failed LSP call or unreadable import is logged and skipped —
 * the turn still runs with whatever was gathered.
 */
export async function gatherL4Bundle(
  client: VSCodeL4LanguageClient,
  logger: AiLogger
): Promise<L4Bundle> {
  const editor = vscode.window.activeTextEditor
  if (!editor) return { files: [] }
  const doc = editor.document
  const mainUri = doc.uri

  let importUris: string[] = []
  if (doc.languageId === 'l4' || mainUri.path.endsWith('.l4')) {
    try {
      const resp = await client.sendRequest(GetExportedFunctionsRequestType, {
        verDocId: { uri: mainUri.toString(), version: doc.version },
      })
      importUris = resp.importedFiles ?? []
    } catch (err) {
      logger.warn(
        `l4-bundle: GetExportedFunctions failed: ${err instanceof Error ? err.message : String(err)}`
      )
    }
  }

  const seen = new Set<string>()
  const files: BundleFile[] = []
  const collect = async (uriStr: string): Promise<void> => {
    if (seen.has(uriStr)) return
    seen.add(uriStr)
    try {
      const uri = vscode.Uri.parse(uriStr)
      const existing = vscode.workspace.textDocuments.find(
        (d) => d.uri.toString() === uriStr
      )
      const bytes = existing
        ? Buffer.from(existing.getText(), 'utf-8')
        : Buffer.from(await vscode.workspace.fs.readFile(uri))
      const name = decodeURIComponent(uri.path.split('/').pop() ?? 'main.l4')
      files.push({ path: name, contentBase64: bytes.toString('base64') })
    } catch (err) {
      logger.warn(
        `l4-bundle: could not read ${uriStr}: ${err instanceof Error ? err.message : String(err)}`
      )
    }
  }

  await collect(mainUri.toString())
  for (const u of importUris) await collect(u)

  const name = decodeURIComponent(mainUri.path.split('/').pop() ?? 'main.l4')
  return { files, activeFile: { path: name, name } }
}
