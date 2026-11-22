import { after, before, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  mkdir,
  mkdtemp,
  readFile,
  realpath,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises'
import { tmpdir } from 'node:os'
import * as path from 'node:path'
import { isWriteSensitive, leavesRoots } from '../ai/workspace-paths.js'

describe('workspace paths', () => {
  let base: string
  let root: string
  let outside: string

  before(async () => {
    base = await realpath(await mkdtemp(path.join(tmpdir(), 'ws-paths-')))
    root = path.join(base, 'project')
    outside = path.join(base, 'elsewhere')
    await mkdir(path.join(root, 'rules'), { recursive: true })
    await mkdir(path.join(root, '.vscode'))
    await mkdir(outside)
    await writeFile(path.join(outside, 'secret.txt'), 'x')
    await symlink(outside, path.join(root, 'link-out'))
    await symlink(path.join(root, 'rules'), path.join(root, 'link-in'))
    await symlink(path.join(root, '.vscode'), path.join(root, 'innocent'))
    await symlink(
      path.join(outside, 'not-there.txt'),
      path.join(root, 'dangling.l4')
    )
  })
  after(() => rm(base, { recursive: true, force: true }))

  test('a normal file stays inside', () => {
    assert.equal(leavesRoots(path.join(root, 'rules/a.l4'), [root]), false)
  })

  test('a file that does not exist yet stays inside', () => {
    assert.equal(leavesRoots(path.join(root, 'new/dir/a.l4'), [root]), false)
  })

  test('a symlink leading out is caught', () => {
    assert.equal(
      leavesRoots(path.join(root, 'link-out/secret.txt'), [root]),
      true
    )
  })

  test('a new file through a symlink leading out is caught', () => {
    assert.equal(leavesRoots(path.join(root, 'link-out/new.l4'), [root]), true)
  })

  test('a symlink staying inside is fine', () => {
    assert.equal(leavesRoots(path.join(root, 'link-in/a.l4'), [root]), false)
  })

  test('a workspace folder that is itself a symlink works', async () => {
    const alias = path.join(base, 'alias')
    await symlink(root, alias)
    assert.equal(leavesRoots(path.join(alias, 'rules/a.l4'), [alias]), false)
  })

  test('the other root of a multi-root workspace counts', () => {
    assert.equal(
      leavesRoots(path.join(root, 'link-out/secret.txt'), [root, outside]),
      false
    )
  })

  test('configuration files need approval', () => {
    assert.equal(
      isWriteSensitive(path.join(root, '.vscode/settings.json'), [root]),
      true
    )
    assert.equal(isWriteSensitive(path.join(root, '.mcp.json'), [root]), true)
  })

  test('so does configuration reached through a symlink', () => {
    assert.equal(
      isWriteSensitive(path.join(root, 'innocent/settings.json'), [root]),
      true
    )
  })

  test('ordinary files do not', () => {
    assert.equal(isWriteSensitive(path.join(root, 'rules/a.l4'), [root]), false)
  })

  test('a workspace living under a dot folder is judged from its root', async () => {
    const hidden = path.join(base, '.vscode', 'project')
    await mkdir(hidden, { recursive: true })
    assert.equal(isWriteSensitive(path.join(hidden, 'a.l4'), [hidden]), false)
  })
})

describe('a setting that steers the model', () => {
  test('cannot come from a workspace', async () => {
    const manifest = JSON.parse(
      await readFile(path.join(process.cwd(), 'package.json'), 'utf8')
    ) as {
      contributes: {
        configuration:
          | { properties: Record<string, { scope?: string }> }
          | Array<{ properties: Record<string, { scope?: string }> }>
      }
    }
    const { configuration } = manifest.contributes
    const blocks = Array.isArray(configuration)
      ? configuration
      : [configuration]
    const settings = Object.assign(
      {},
      ...blocks.map((b) => b.properties)
    ) as Record<string, { scope?: string }>
    assert.equal(settings['legaleseAi.methodology']?.scope, 'application')
  })
})
