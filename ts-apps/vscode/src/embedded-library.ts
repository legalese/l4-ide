/**
 * `jl4-embedded:` documents: the standard-library modules `jl4-lsp` carries
 * inside its own binary, which therefore have no file on disk.
 *
 * Go-to-definition on `sum` (from `IMPORT prelude`) answers with
 * `jl4-embedded:/prelude.l4`. Nothing in VS Code can open that unless the
 * extension serves it, and the language client only forwards a document to the
 * server (so hover and go-to-definition work *inside* it) if the client's
 * document selector names the scheme. This module is both halves.
 *
 * The text comes from the server rather than from the `libraries/` folder
 * shipped beside the binary: the server is the only party that knows what it
 * embedded, and a `jl4.serverExecutablePath` binary need not match the bundle.
 *
 * Lives in its own module with no `vscode` import so `node --test` can exercise
 * it (see `unit-tests/embedded-library.test.ts`).
 */

/** The URI scheme `jl4-lsp` gives its embedded stdlib
 *  (`embeddedLibraryUriScheme` in jl4-lsp's `LSP/Core/Shake.hs`). */
export const EMBEDDED_LIBRARY_SCHEME = 'jl4-embedded'

export function isEmbeddedLibraryUri(uri: string): boolean {
  return uri.startsWith(`${EMBEDDED_LIBRARY_SCHEME}:`)
}

export interface L4DocumentFilter {
  scheme: string
  language: string
  pattern?: string
}

/** The documents the language client forwards to `jl4-lsp`: files on disk, and
 *  the embedded stdlib modules the server itself hands back. */
export function l4DocumentSelector(langId: string): L4DocumentFilter[] {
  return [
    { scheme: 'file', language: langId, pattern: '**/*' },
    { scheme: EMBEDDED_LIBRARY_SCHEME, language: langId },
  ]
}

export interface EmbeddedLibraryProvider {
  provideTextDocumentContent(uri: { toString(): string }): Promise<string>
}

/**
 * A `TextDocumentContentProvider` for the `jl4-embedded` scheme.
 *
 * @param ready resolves once the language client is running. A tab restored
 *   from the previous session can ask for its content before the server is up.
 * @param readText the `l4/embeddedLibrary` request.
 */
export function embeddedLibraryProvider(
  ready: () => Promise<void>,
  readText: (uri: string) => Promise<{ text: string } | null>
): EmbeddedLibraryProvider {
  return {
    async provideTextDocumentContent(uri) {
      const name = uri.toString()
      try {
        await ready()
        const reply = await readText(name)
        if (reply === null) throw new Error('the server sent no reply')
        return reply.text
      } catch (err) {
        const why = err instanceof Error ? err.message : String(err)
        throw new Error(
          `Could not read ${name} from jl4-lsp: ${why}. ` +
            `A jl4-lsp older than this extension does not know the l4/embeddedLibrary request.`
        )
      }
    },
  }
}
