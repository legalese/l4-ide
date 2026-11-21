#!/usr/bin/env node
// Measures the harness on small statute-to-L4 tasks: does what it writes do
// what the law says, and at what cost? See eval/README.md.
//
//   node eval/run.mjs --check-tasks --l4 l4
//   node eval/run.mjs --ai-url http://localhost:3000 --lsp jl4-lsp --l4 l4
//   node eval/run.mjs --compare before.json after.json

import { execFile, spawn } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { existsSync } from 'node:fs'
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from 'node:fs/promises'
import { platform, tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

const exec = promisify(execFile)
const here = dirname(fileURLToPath(import.meta.url))
const DEFAULT_TASKS = join(here, 'tasks')
const BUNDLE = join(here, '..', 'dist', 'cloud-agent.cjs')

function parseArgs(argv) {
  const opts = { positional: [] }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (
      a === '--check-tasks' ||
      a === '--compare' ||
      a === '--allow-network' ||
      a === '--show-reply'
    ) {
      opts[a.slice(2)] = true
    } else if (a.startsWith('--')) {
      opts[a.slice(2)] = argv[++i]
    } else {
      opts.positional.push(a)
    }
  }
  return opts
}

/** Model-written L4 can call FETCH or POST, so scoring it runs with no
 *  network. Refuses to run at all if it can't arrange that. */
function offline(allowNetwork, command, args) {
  if (allowNetwork) return [command, args]
  if (platform() === 'darwin') {
    return [
      'sandbox-exec',
      ['-p', '(version 1)(allow default)(deny network*)', command, ...args],
    ]
  }
  if (platform() === 'linux') return ['unshare', ['-rn', command, ...args]]
  throw new Error('no way to block the network here; see --allow-network')
}

async function runL4(l4, dir, file, allowNetwork) {
  const [command, args] = offline(allowNetwork, l4, ['run', '--json', file])
  let stdout
  try {
    ;({ stdout } = await exec(command, args, {
      cwd: dir,
      timeout: 60_000,
      maxBuffer: 20 * 1024 * 1024,
    }))
  } catch (err) {
    stdout = err.stdout ?? ''
  }
  try {
    return JSON.parse(stdout)
  } catch {
    return { ok: false, results: [], diagnostics: [stdout.slice(0, 2000)] }
  }
}

function assertions(report) {
  return (report.results ?? []).filter((r) => r.kind === 'assertion')
}

/** Score a solution against the task's oracle. The oracle's expected values
 *  are hand-written, so a model can't pass by writing its own tests. */
export async function score(task, solution, opts) {
  const dir = await mkdtemp(join(tmpdir(), 'l4-eval-score-'))
  try {
    await writeFile(join(dir, 'solution.l4'), solution)
    await copyFile(join(task.dir, 'oracle.l4'), join(dir, 'oracle.l4'))
    const own = await runL4(opts.l4, dir, 'solution.l4', opts['allow-network'])
    const oracle = await runL4(opts.l4, dir, 'oracle.l4', opts['allow-network'])
    const results = assertions(oracle)
    const passed = results.filter((r) => r.value === true).length
    const ownResults = assertions(own)
    const kept = (task.keepLines ?? []).every((line) => solution.includes(line))
    return {
      compiles: own.ok === true,
      oraclePassed: passed,
      oracleTotal: results.length,
      ownChecks: ownResults.length,
      ownChecksFailing: ownResults.filter((r) => r.value === false).length,
      keptRequiredLines: kept,
      correct:
        own.ok === true &&
        results.length > 0 &&
        passed === results.length &&
        kept,
    }
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
}

async function loadTasks(only, root = DEFAULT_TASKS) {
  const names = (await readdir(root)).sort()
  const tasks = []
  for (const name of names) {
    if (only && only !== name) continue
    const dir = join(root, name)
    const meta = JSON.parse(await readFile(join(dir, 'task.json'), 'utf-8'))
    tasks.push({
      name,
      dir,
      ...meta,
      prompt: await readFile(join(dir, 'prompt.md'), 'utf-8'),
    })
  }
  return tasks
}

/** A task that can't be passed, or a seed that isn't broken, would look like
 *  a model failure, so every task is proved before any model runs. */
async function checkTasks(opts) {
  let bad = 0
  for (const task of await loadTasks(opts.task, opts['tasks-dir'])) {
    const ref = await readFile(join(task.dir, 'reference.l4'), 'utf-8')
    const result = await score(task, ref, opts)
    const problems = result.correct ? [] : ['the reference fails its oracle']
    if (task.seed) {
      const seed = await readFile(join(task.dir, task.seed), 'utf-8')
      const seeded = await score(task, seed, opts)
      if (seeded.correct) problems.push('the seed already passes')
    }
    console.log(
      `${problems.length ? 'FAIL' : 'ok  '} ${task.name} ${problems.join('; ')}`
    )
    bad += problems.length
  }
  if (bad > 0) process.exitCode = 1
}

function ulid() {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
  const bytes = randomBytes(26)
  let id = ''
  for (let i = 0; i < 26; i++) {
    id += alphabet[i === 0 ? bytes[i] % 8 : bytes[i] % 32]
  }
  return id
}

async function readEvents(stateDir) {
  const dir = join(stateDir, 'events')
  if (!existsSync(dir)) return []
  const events = []
  for (const f of (await readdir(dir)).sort()) {
    const text = await readFile(join(dir, f), 'utf-8')
    for (const line of text.split('\n')) {
      if (line.trim()) events.push(JSON.parse(line))
    }
  }
  return events
}

/** One task through the real harness, against a local backend. */
async function runTask(task, opts) {
  const root = await mkdtemp(join(tmpdir(), 'l4-eval-run-'))
  const sid = ulid()
  const base = ['--dev', '--root', root, '--session', sid]
  try {
    const dev = [
      ...base,
      '--ai-url',
      opts['ai-url'],
      '--lsp',
      opts.lsp,
      '--log-level',
      'info',
    ]
    const session = join(root, 'sessions', sid)
    const repo = join(session, 'repo')
    await mkdir(join(repo, 'data'), { recursive: true })
    if (task.seed) {
      await copyFile(join(task.dir, task.seed), join(repo, task.file))
    }
    for (const [to, from] of Object.entries(task.seedFiles ?? {})) {
      await copyFile(join(task.dir, from), join(repo, to))
    }
    const started = Date.now()
    const harness = spawn('node', [BUNDLE, ...dev, '--init'], {
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let log = ''
    harness.stdout.on('data', (d) => (log += d))
    harness.stderr.on('data', (d) => (log += d))
    const send = (command) =>
      exec('node', [BUNDLE, 'send', ...base, JSON.stringify(command)])
    // `--init` creates the rest of the session folder when the harness
    // starts, and commands can only be queued after that.
    while (!existsSync(join(session, 'state', 'commands'))) {
      if (harness.exitCode !== null) {
        throw new Error(`harness exited early:\n${log.slice(-2000)}`)
      }
      await new Promise((r) => setTimeout(r, 100))
    }
    await send({ type: 'message', turnId: 't1', text: task.prompt })
    const deadline = started + Number(opts['task-timeout-s'] ?? 900) * 1000
    let done
    while (!done && Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 1000))
      const events = await readEvents(join(session, 'state'))
      done = events.find((e) => e.type === 'done' || e.type === 'error')
    }
    await send({ type: 'stop' }).catch(() => null)
    await new Promise((resolve) => {
      harness.once('exit', resolve)
      setTimeout(() => harness.kill(), 15_000).unref()
    })
    const events = await readEvents(join(session, 'state'))
    const calls = events.filter(
      (e) => e.type === 'tool-call' && e.argsJson && e.status !== undefined
    )
    const reply = events
      .filter((e) => e.type === 'text-delta')
      .map((e) => e.text)
      .join('')
    const target = join(repo, task.file)
    const solution = existsSync(target) ? await readFile(target, 'utf-8') : ''
    return {
      task: task.name,
      finished: done?.type === 'done',
      seconds: Math.round((Date.now() - started) / 1000),
      rounds: log.split('/v1/chat/completions (').length - 1,
      promptTokens: done?.usage?.promptTokens ?? null,
      completionTokens: done?.usage?.completionTokens ?? null,
      toolCalls: calls.length,
      ...(opts['show-reply'] ? { reply } : {}),
      ...(solution
        ? await score(task, solution, opts)
        : { correct: false, compiles: false }),
    }
  } finally {
    await rm(root, { recursive: true, force: true })
  }
}

function summarise(rows) {
  const n = rows.length || 1
  const mean = (key) =>
    Math.round(rows.reduce((a, r) => a + (r[key] ?? 0), 0) / n)
  return {
    tasks: rows.length,
    correct: rows.filter((r) => r.correct).length,
    compiled: rows.filter((r) => r.compiles).length,
    meanRounds: mean('rounds'),
    meanSeconds: mean('seconds'),
    meanPromptTokens: mean('promptTokens'),
  }
}

async function compare(before, after) {
  const load = async (f) => JSON.parse(await readFile(f, 'utf-8'))
  const [a, b] = [await load(before), await load(after)]
  const rows = Object.keys(a.summary).map((k) => [
    k,
    a.summary[k],
    b.summary[k],
  ])
  console.log('measure'.padEnd(20), 'before'.padStart(12), 'after'.padStart(12))
  for (const [k, x, y] of rows) {
    console.log(k.padEnd(20), String(x).padStart(12), String(y).padStart(12))
  }
  const worse = a.rows.filter(
    (r) => r.correct && !b.rows.find((s) => s.task === r.task)?.correct
  )
  if (worse.length > 0) {
    console.log(`Regressed: ${worse.map((r) => r.task).join(', ')}`)
    process.exitCode = 1
  }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2))
  if (opts.compare) return compare(opts.positional[0], opts.positional[1])
  opts.l4 ??= 'l4'
  if (opts['check-tasks']) return checkTasks(opts)
  if (!opts['ai-url'] || !opts.lsp) {
    throw new Error('--ai-url and --lsp are required to run tasks')
  }
  const rows = []
  for (const task of await loadTasks(opts.task, opts['tasks-dir'])) {
    const row = await runTask(task, opts)
    console.log(JSON.stringify(row))
    rows.push(row)
  }
  const summary = summarise(rows)
  console.log(JSON.stringify(summary))
  if (opts.out) {
    await writeFile(opts.out, JSON.stringify({ summary, rows }, null, 2))
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err instanceof Error ? err.message : err)
    process.exitCode = 2
  })
}
