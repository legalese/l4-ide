import * as vscode from 'vscode'
import {
  DirectiveResultsCache,
  FileCheckTracker,
  type CheckedDiagnostics,
  type DiagnosticSeverity,
  type DirectiveResultRow,
  type L4Diagnostic,
  type L4Language,
  type LspLocation,
  type LspPosition,
  type SemanticTokensSnapshot,
} from '@repo/legalese-agent'
import {
  GetExportedFunctionsRequestType,
  type ExportedFunctionInfo,
} from 'jl4-client-rpc'
import type { VSCodeL4LanguageClient } from '../vscode-l4-language-client.js'

/** How long a fresh open gets before diagnostics are read — they
 *  arrive asynchronously via publishDiagnostics. */
const DIAGNOSTIC_SETTLE_MS = 400

/** Longest wait for the check of a file's latest text. After this the
 *  result is reported as pending: never as clean. */
const CHECK_TIMEOUT_MS = 15_000

/** A diagnostic as `l4/fileChecked` carries it. */
export interface WireDiagnostic {
  severity?: number
  range?: { start?: { line?: number } }
  message: string
  source?: string
  code?: string | number
}

/**
 * {@link L4Language} port over VS Code's view of jl4-lsp: documents are
 * opened with `openTextDocument` (the language client sends didOpen),
 * diagnostics come from `vscode.languages.getDiagnostics`, references
 * and semantic tokens from the registered providers, and exported
 * functions from the language client directly.
 *
 * Directive results are pushed by the server; extension.mts feeds the
 * `l4/directiveResultsUpdated` notification into {@link recordDirectiveResults}.
 * One instance per language client, shared by every chat session.
 */
export class VsCodeL4Language implements L4Language {
  private readonly directives = new DirectiveResultsCache()
  /** What `l4/fileChecked` has said, per file path. */
  private readonly checks = new FileCheckTracker<L4Diagnostic>()

  constructor(private readonly client: VSCodeL4LanguageClient) {}

  /** Mirror an `l4/fileChecked` payload. */
  recordFileChecked(
    uri: string,
    version: number | null,
    diagnostics: WireDiagnostic[]
  ): void {
    this.checks.record(
      vscode.Uri.parse(uri).fsPath,
      version,
      diagnostics.map((d) => ({
        severity: severityFromWire(d.severity),
        line: d.range?.start?.line ?? 0,
        message: d.message,
        source: d.source,
        code: d.code === undefined ? undefined : String(d.code),
      }))
    )
  }

  /** A document closed: its version numbers start over if it reopens,
   *  so what was said about it no longer applies. */
  forgetDocument(uri: string): void {
    this.checks.forget(vscode.Uri.parse(uri).fsPath)
  }

  /** Mirror an `l4/directiveResultsUpdated` payload. */
  recordDirectiveResults(uri: string, results: DirectiveResultRow[]): void {
    this.directives.record(uri, results)
  }

  async openDocument(
    uri: string
  ): Promise<{ lineCount: number; version: number }> {
    const doc = await vscode.workspace.openTextDocument(vscode.Uri.parse(uri))
    return { lineCount: doc.lineCount, version: doc.version }
  }

  async getDiagnostics(uri: string): Promise<L4Diagnostic[]> {
    const target = vscode.Uri.parse(uri)
    // Opening a document triggers the LSP to parse + type-check it. If
    // it's already open in an editor this is effectively a no-op.
    await vscode.workspace.openTextDocument(target)
    // Give the server a moment to finish if this is a fresh open. The
    // diagnostics collection updates async via publishDiagnostics.
    await new Promise((r) => setTimeout(r, DIAGNOSTIC_SETTLE_MS))

    // Scan all collections and match by fsPath instead of relying on
    // exact URI equality — `vscode.Uri.file(path).toString()` can subtly
    // differ from what the LSP published with (casing, encoding, etc.).
    const everything = vscode.languages.getDiagnostics()
    const match = everything.find(
      ([u]) =>
        u.fsPath === target.fsPath ||
        u.toString() === target.toString() ||
        u.fsPath.toLowerCase() === target.fsPath.toLowerCase()
    )
    return (match?.[1] ?? []).map((d) => ({
      severity: severityName(d.severity),
      line: d.range.start.line,
      message: d.message,
      source: d.source,
      code:
        d.code === undefined
          ? undefined
          : typeof d.code === 'object' && d.code !== null && 'value' in d.code
            ? String((d.code as { value: string | number }).value)
            : String(d.code),
    }))
  }

  /**
   * Diagnostics for the file's current text. `getDiagnostics` reads
   * whatever VS Code holds after a fixed delay, which on a slow compile is
   * the previous version's result: an edit could report clean when the
   * file had errors. This waits for the check of this exact version.
   */
  async getCheckedDiagnostics(uri: string): Promise<CheckedDiagnostics> {
    const target = vscode.Uri.parse(uri)
    const doc = await vscode.workspace.openTextDocument(target)
    const key = target.fsPath
    const outcome = await this.checks.settle(key, doc.version, CHECK_TIMEOUT_MS)
    if (outcome === 'unsupported') {
      return { diagnostics: await this.getDiagnostics(uri), pending: false }
    }
    const done = outcome === 'checked'
    return {
      diagnostics: this.checks.latest(key) ?? (await this.getDiagnostics(uri)),
      pending: !done,
      ...(done ? { confirmed: true } : {}),
    }
  }

  fileErrorCounts(): Map<string, number> {
    const counts = new Map<string, number>()
    const byPath = this.checks.errorCounts(
      (d) => d.severity === 'error' && d.source !== 'eval'
    )
    for (const [fsPath, n] of byPath) {
      counts.set(vscode.Uri.file(fsPath).toString(), n)
    }
    return counts
  }

  getDirectiveResults(uri: string): DirectiveResultRow[] | undefined {
    return this.directives.get(uri)
  }

  awaitDirectiveResults(uri: string, timeoutMs: number): Promise<void> {
    return this.directives.waitForNext(uri, timeoutMs)
  }

  async findReferences(
    uri: string,
    position: LspPosition
  ): Promise<LspLocation[]> {
    // VSCode's reference provider proxies to the jl4-lsp
    // textDocument/references handler.
    const locations = await vscode.commands.executeCommand<
      vscode.Location[] | undefined
    >(
      'vscode.executeReferenceProvider',
      vscode.Uri.parse(uri),
      new vscode.Position(position.line, position.character)
    )
    return (locations ?? []).map((loc) => ({
      uri: loc.uri.toString(),
      range: {
        start: {
          line: loc.range.start.line,
          character: loc.range.start.character,
        },
        end: { line: loc.range.end.line, character: loc.range.end.character },
      },
    }))
  }

  async getSemanticTokens(uri: string): Promise<SemanticTokensSnapshot | null> {
    const target = vscode.Uri.parse(uri)
    const legend = await vscode.commands.executeCommand<
      vscode.SemanticTokensLegend | undefined
    >('vscode.provideDocumentSemanticTokensLegend', target)
    const tokens = await vscode.commands.executeCommand<
      vscode.SemanticTokens | undefined
    >('vscode.provideDocumentSemanticTokens', target)
    if (!legend || !tokens || !tokens.data) return null
    return { tokenTypes: legend.tokenTypes, data: tokens.data }
  }

  async getExportedFunctions(doc: {
    uri: string
    version: number
  }): Promise<ExportedFunctionInfo[]> {
    const response = await this.client.sendRequest(
      GetExportedFunctionsRequestType,
      { verDocId: { uri: doc.uri, version: doc.version } }
    )
    return response?.functions ?? []
  }
}

function severityName(
  s: vscode.DiagnosticSeverity | undefined
): DiagnosticSeverity {
  switch (s) {
    case vscode.DiagnosticSeverity.Error:
      return 'error'
    case vscode.DiagnosticSeverity.Warning:
      return 'warning'
    case vscode.DiagnosticSeverity.Information:
      return 'info'
    case vscode.DiagnosticSeverity.Hint:
      return 'hint'
    default:
      return 'info'
  }
}

function severityFromWire(s: number | undefined): DiagnosticSeverity {
  switch (s) {
    case 2:
      return 'warning'
    case 3:
      return 'info'
    case 4:
      return 'hint'
    default:
      return 'error'
  }
}
