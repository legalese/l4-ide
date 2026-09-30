import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import { fileURLToPath } from 'node:url'
import { HOST_PATH, SID, tempDir } from './helpers.js'

const here = path.dirname(fileURLToPath(import.meta.url))
// out/test → the package root
const script = path.resolve(here, '..', '..', 'docker', 'entrypoint.sh')

const good: Record<string, string> = {
  SESSION_ID: SID,
  AGENT_KEY: 'sk_live_abcdefgh12345',
  AI_PROXY_URL: 'https://ai.legalese.cloud',
  MCP_URL: 'https://mcp.legalese.cloud/mcp',
  AUTH_URL: 'https://legalese.cloud',
  LOG_LEVEL: 'info',
}

/**
 * Run a copy of the entry point whose fixed paths point into a temp dir:
 * the "harness" it execs prints its environment as JSON.
 */
async function run(
  env: Record<string, string>,
  args: string[] = []
): Promise<{
  code: number | null
  stderr: string
  env?: Record<string, string>
  gitconfig?: string
}> {
  const { dir, cleanup } = await tempDir()
  try {
    const app = path.join(dir, 'app')
    const home = path.join(dir, 'home')
    await mkdir(app, { recursive: true })
    await writeFile(
      path.join(app, 'cloud-agent.cjs'),
      `require('fs').writeFileSync(${JSON.stringify(path.join(dir, 'env.json'))}, JSON.stringify(process.env))\n`
    )
    const text = (await readFile(script, 'utf8'))
      .replaceAll('/usr/local/bin/node', process.execPath)
      .replaceAll('/app/cloud-agent.cjs', path.join(app, 'cloud-agent.cjs'))
      .replaceAll('export HOME=/home/agent', `export HOME=${home}`)
      .replaceAll(
        'export PATH=/usr/local/bin:/usr/bin:/bin',
        `export PATH=${HOST_PATH}`
      )
    const copy = path.join(dir, 'entrypoint.sh')
    await writeFile(copy, text, { mode: 0o755 })
    const r = spawnSync('bash', [copy, ...args], {
      env: { PATH: HOST_PATH, ...env },
      encoding: 'utf8',
    })
    const out: {
      code: number | null
      stderr: string
      env?: Record<string, string>
      gitconfig?: string
    } = {
      code: r.status,
      stderr: r.stderr,
    }
    try {
      out.env = JSON.parse(await readFile(path.join(dir, 'env.json'), 'utf8'))
      out.gitconfig = await readFile(path.join(home, '.gitconfig'), 'utf8')
    } catch {
      // not started
    }
    return out
  } finally {
    await cleanup()
  }
}

describe('docker/entrypoint.sh', () => {
  test('keeps only the allowed variables and writes the git config', async () => {
    const r = await run(
      {
        ...good,
        ECS_CONTAINER_METADATA_URI_V4: 'http://169.254.170.2/v4/abc-123',
        NODE_OPTIONS: '--require /tmp/evil.js',
        AWS_SECRET_ACCESS_KEY: 'nope',
      },
      ['--ignored', 'args']
    )
    assert.equal(r.code, 0, r.stderr)
    const env = r.env!
    for (const [k, v] of Object.entries(good)) assert.equal(env[k], v)
    assert.equal(
      env.ECS_CONTAINER_METADATA_URI_V4,
      'http://169.254.170.2/v4/abc-123'
    )
    assert.equal(env.NODE_OPTIONS, undefined)
    assert.equal(env.AWS_SECRET_ACCESS_KEY, undefined)
    assert.equal(env.NODE_ENV, 'production')
    assert.match(r.gitconfig ?? '', /createObject = rename/)
    assert.match(r.gitconfig ?? '', /hooksPath = \/dev\/null/)
    assert.match(r.gitconfig ?? '', /email = agent@legalese.cloud/)
  })

  test('drops a task-metadata URI that is not the Fargate endpoint', async () => {
    const r = await run({
      ...good,
      ECS_CONTAINER_METADATA_URI_V4: 'http://evil.example/v4/x',
    })
    assert.equal(r.code, 0, r.stderr)
    assert.equal(r.env!.ECS_CONTAINER_METADATA_URI_V4, undefined)
  })

  for (const [name, value] of [
    ['SESSION_ID', 'not-a-ulid'],
    ['SESSION_ID', `${SID}\nX=1`],
    ['AGENT_KEY', 'pk_live_abcdefgh'],
    ['AGENT_KEY', 'sk_short'],
    ['AI_PROXY_URL', 'http://ai.legalese.cloud'],
    ['MCP_URL', 'https://user:pw@mcp.legalese.cloud'],
    ['AUTH_URL', 'https://legalese.cloud/?x=1'],
    ['LOG_LEVEL', 'loud'],
  ] as const) {
    test(`rejects ${name}=${JSON.stringify(value)} without echoing values`, async () => {
      const r = await run({ ...good, [name]: value })
      assert.equal(r.code, 64)
      assert.equal(r.env, undefined)
      assert.ok(!r.stderr.includes(good.AGENT_KEY!))
      assert.ok(!r.stderr.includes(value))
    })
  }

  test('requires every variable', async () => {
    const env = { ...good }
    delete env.AUTH_URL
    assert.equal((await run(env)).code, 64)
  })
})
