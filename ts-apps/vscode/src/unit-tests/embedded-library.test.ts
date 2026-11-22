/** `jl4-embedded:` documents, minus VS Code: the document selector that makes
 *  the language client forward them to jl4-lsp, and the provider that serves
 *  their text. Go-to-definition into `prelude` returned a URI nothing could
 *  open until both existed. */
import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  EMBEDDED_LIBRARY_SCHEME,
  embeddedLibraryProvider,
  isEmbeddedLibraryUri,
  l4DocumentSelector,
} from '../embedded-library.js'

describe('l4DocumentSelector', () => {
  test('still forwards files on disk, with the same filter as before', () => {
    assert.deepEqual(
      l4DocumentSelector('l4').find((f) => f.scheme === 'file'),
      { scheme: 'file', language: 'l4', pattern: '**/*' }
    )
  })

  test('also forwards the embedded stdlib, or hover and go-to-definition die inside it', () => {
    assert.equal(EMBEDDED_LIBRARY_SCHEME, 'jl4-embedded')
    assert.deepEqual(
      l4DocumentSelector('l4').find((f) => f.scheme === 'jl4-embedded'),
      { scheme: 'jl4-embedded', language: 'l4' }
    )
  })
})

describe('isEmbeddedLibraryUri', () => {
  test('recognises the scheme the server uses, and nothing else', () => {
    assert.ok(isEmbeddedLibraryUri('jl4-embedded:/prelude.l4'))
    assert.ok(!isEmbeddedLibraryUri('file:///work/prelude.l4'))
    assert.ok(!isEmbeddedLibraryUri('l4-ai-proposed:/1/prelude.l4'))
  })
})

describe('embeddedLibraryProvider', () => {
  const uri = { toString: () => 'jl4-embedded:/prelude.l4' }

  test('asks the server for exactly the URI it was given, once the client is up', async () => {
    const calls: string[] = []
    const provider = embeddedLibraryProvider(
      async () => {
        calls.push('ready')
      },
      async (u) => {
        calls.push(`read ${u}`)
        return { text: 'GIVEN list IS A LIST OF NUMBER\n' }
      }
    )
    assert.equal(
      await provider.provideTextDocumentContent(uri),
      'GIVEN list IS A LIST OF NUMBER\n'
    )
    assert.deepEqual(calls, ['ready', 'read jl4-embedded:/prelude.l4'])
  })

  test('passes the text through untouched (the server positions refer to it)', async () => {
    const text = '§§ `Numeric Aggregates`\r\n\tsum list\n\n'
    const provider = embeddedLibraryProvider(
      async () => {},
      async () => ({ text })
    )
    assert.equal(await provider.provideTextDocumentContent(uri), text)
  })

  test('says which document failed when the server errors, e.g. an older jl4-lsp', async () => {
    const provider = embeddedLibraryProvider(
      async () => {},
      async () => {
        throw new Error('Unhandled method l4/embeddedLibrary')
      }
    )
    await assert.rejects(
      provider.provideTextDocumentContent(uri),
      /Could not read jl4-embedded:\/prelude\.l4 from jl4-lsp: Unhandled method l4\/embeddedLibrary/
    )
  })

  test('does not ask the server while the client is not up', async () => {
    let asked = false
    const provider = embeddedLibraryProvider(
      async () => {
        throw new Error('Client is not running')
      },
      async () => {
        asked = true
        return { text: '' }
      }
    )
    await assert.rejects(
      provider.provideTextDocumentContent(uri),
      /Client is not running/
    )
    assert.equal(asked, false)
  })

  test('rejects an empty reply instead of showing an empty document', async () => {
    const provider = embeddedLibraryProvider(
      async () => {},
      async () => null
    )
    await assert.rejects(
      provider.provideTextDocumentContent(uri),
      /the server sent no reply/
    )
  })
})
