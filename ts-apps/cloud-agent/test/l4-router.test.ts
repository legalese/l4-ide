import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { mkdir, readlink, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import type { DirectiveResultRow } from '@repo/legalese-agent'
import { Jl4Lsp } from '../src/jl4-lsp.js'
import { L4Router, prepareTmpLibraryAlias } from '../src/l4-router.js'
import { uriForPath } from '../src/node-workspace.js'
import { StubL4, silent, tempDir } from './helpers.js'

/** A language server that records what it's asked. */
class Recorder extends StubL4 {
  readonly calls: string[] = []
  constructor(readonly name: string) {
    super()
  }
  override async getDiagnostics(uri?: string): Promise<never[]> {
    this.calls.push(`diag ${uri}`)
    return []
  }
  override getDirectiveResults(uri: string): DirectiveResultRow[] | undefined {
    this.calls.push(`results ${uri}`)
    return []
  }
  onDidWrite(uri: string): void {
    this.calls.push(`write ${uri}`)
  }
  onDidDelete(uri: string): void {
    this.calls.push(`delete ${uri}`)
  }
  async resync(uris: string[]): Promise<void> {
    this.calls.push(`resync ${uris.length}`)
  }
}

describe('L4Router', () => {
  const repo = '/r/repo'
  const u = (rel: string): string => uriForPath(path.join(repo, rel))
  const alias = '/x/jl4/libraries'

  function build(): {
    router: L4Router
    data: Recorder
    tmp: Recorder
    starts: () => number
  } {
    const data = new Recorder('data')
    const tmp = new Recorder('tmp')
    let n = 0
    const router = new L4Router({
      repoDir: repo,
      data,
      tmpLibraryAlias: alias,
      logger: silent,
      startTmp: async () => {
        n++
        return tmp
      },
    })
    return { router, data, tmp, starts: () => n }
  }

  test('routes tmp/ files to the tmp instance, started lazily once', async () => {
    const { router, data, tmp, starts } = build()
    await router.getDiagnostics(u('data/a.l4'))
    await router.getDiagnostics(u('notes.l4'))
    assert.equal(starts(), 0)
    // Nothing is sent to a tmp instance that doesn't run yet.
    router.onDidWrite(u('tmp/x.l4'), 'x', true)
    assert.equal(router.getDirectiveResults(u('tmp/x.l4')), undefined)
    assert.equal(starts(), 0)
    await Promise.all([
      router.getDiagnostics(u('tmp/x.l4')),
      router.getDiagnostics(u('tmp/sub/y.l4')),
    ])
    assert.equal(starts(), 1)
    assert.deepEqual(data.calls, [
      `diag ${u('data/a.l4')}`,
      `diag ${u('notes.l4')}`,
    ])
    assert.deepEqual(tmp.calls, [
      `diag ${u('tmp/x.l4')}`,
      `diag ${u('tmp/sub/y.l4')}`,
    ])
  })

  test('mirrors data/ changes to the running tmp instance under the alias path', async () => {
    const { router, data, tmp } = build()
    await router.getDiagnostics(u('tmp/x.l4'))
    router.onDidWrite(u('data/sub/m.l4'), 'm', false)
    router.onDidDelete(u('data/old.l4'))
    router.onDidWrite(u('tmp/x.l4'), 'x', false)
    assert.deepEqual(data.calls, [
      `write ${u('data/sub/m.l4')}`,
      `delete ${u('data/old.l4')}`,
    ])
    assert.deepEqual(tmp.calls.slice(1), [
      `write ${uriForPath(path.join(alias, 'sub', 'm.l4'))}`,
      `delete ${uriForPath(path.join(alias, 'old.l4'))}`,
      `write ${u('tmp/x.l4')}`,
    ])
    await router.resync([u('data/a.l4'), u('tmp/b.l4')])
    assert.equal(data.calls.at(-1), 'resync 2')
    // The tmp instance also gets the data/ file's alias.
    assert.equal(tmp.calls.at(-1), 'resync 3')
  })

  test('the alias is a symlink to data/', async () => {
    const { dir, cleanup } = await tempDir()
    try {
      const lib = await prepareTmpLibraryAlias(
        path.join(dir, 'xdg'),
        path.join(dir, 'data')
      )
      assert.equal(lib, path.join(dir, 'xdg', 'jl4', 'libraries'))
      assert.equal(await readlink(lib), path.join(dir, 'data'))
      // Idempotent.
      await prepareTmpLibraryAlias(
        path.join(dir, 'xdg'),
        path.join(dir, 'data')
      )
    } finally {
      await cleanup()
    }
  })
})

// Optional: a real jl4-lsp (set JL4_LSP=/path/to/jl4-lsp; a build with the
// embedded core libraries, i.e. from this repo).
const testEnv: NodeJS.ProcessEnv = process.env
const realLsp = testEnv['JL4_LSP']
describe('L4Router against a real jl4-lsp', { skip: !realLsp }, () => {
  test('tmp/ files: tmp modules first, then data/ modules and the core libraries', async () => {
    const { dir, cleanup } = await tempDir()
    try {
      const repo = path.join(dir, 'repo')
      for (const d of ['data/sub', 'tmp/sub']) {
        await mkdir(path.join(repo, d), { recursive: true })
      }
      const files: Record<string, string> = {
        'data/money.l4': 'DECIDE `the fee` IS 40\n',
        'data/shadow.l4': 'DECIDE `the shade` IS 1\n',
        'data/sub/uses.l4':
          'IMPORT money\nIMPORT shadow\n\n#EVAL `the fee` PLUS `the shade`\n',
        'tmp/shadow.l4': 'DECIDE `the shade` IS 2\n',
        'tmp/draft.l4':
          'IMPORT money\nIMPORT shadow\nIMPORT prelude\n\n#EVAL `the fee` PLUS `the shade`\n',
        'tmp/sub/deep.l4': 'IMPORT money\n\n#EVAL `the fee` PLUS 5\n',
      }
      for (const [f, t] of Object.entries(files)) {
        await writeFile(path.join(repo, f), t)
      }
      const env = { PATH: testEnv['PATH'] ?? '', HOME: path.join(dir, 'home') }
      const xdg = path.join(dir, 'xdg')
      const alias = await prepareTmpLibraryAlias(xdg, path.join(repo, 'data'))
      const router = new L4Router({
        repoDir: repo,
        tmpLibraryAlias: alias,
        logger: silent,
        data: await Jl4Lsp.spawn({
          command: realLsp!,
          root: path.join(repo, 'data'),
          logger: silent,
          env,
        }),
        startTmp: () =>
          Jl4Lsp.spawn({
            command: realLsp!,
            root: path.join(repo, 'tmp'),
            logger: silent,
            env: { ...env, XDG_DATA_HOME: xdg },
          }),
      })
      const diag = async (rel: string): Promise<string[]> =>
        (await router.getDiagnostics(uriForPath(path.join(repo, rel)))).map(
          (x) => `${x.severity}: ${x.message}`
        )
      // data/: data modules (shade 1).
      assert.deepEqual(await diag('data/sub/uses.l4'), ['info: 41'])
      // tmp/: tmp/shadow.l4 wins over data/shadow.l4; money from data/;
      // prelude from the core libraries.
      assert.deepEqual(await diag('tmp/draft.l4'), ['info: 42'])
      assert.deepEqual(await diag('tmp/sub/deep.l4'), ['info: 45'])
      // A change to a data/ module reaches the tmp instance.
      const money = uriForPath(path.join(repo, 'data', 'money.l4'))
      await writeFile(
        path.join(repo, 'data', 'money.l4'),
        'DECIDE `the fee` IS 100\n'
      )
      router.onDidWrite(money, 'DECIDE `the fee` IS 100\n', false)
      // Open importers are re-checked without being touched.
      assert.deepEqual(await diag('tmp/draft.l4'), ['info: 102'])
      assert.deepEqual(await diag('data/sub/uses.l4'), ['info: 101'])
      await router.dispose()
    } finally {
      await cleanup()
    }
  })
})
