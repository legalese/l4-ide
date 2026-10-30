import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { mkdir, readFile, rm, stat, symlink, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import type { CloudEventPayload } from '@repo/legalese-agent/protocol'
import {
  CommandReader,
  COMMAND_GRACE_MS,
  COMMAND_TRANSIENT_GRACE_MS,
} from '../src/command-reader.js'
import { EventLog, DELTA_COALESCE_MS } from '../src/event-log.js'
import { CloudInteraction, MAX_TOOL_EVENT_TEXT } from '../src/interaction.js'
import { Lease, LeaseHeldError } from '../src/lease.js'
import { appendToFile, readKnownFile, readKnownText } from '../src/safe-fs.js'
import { SessionJson } from '../src/session-file.js'
import { initSessionFolder, sendCommand } from '../src/dev.js'
import {
  MemoryLogger,
  SID,
  readEvents,
  silent,
  tempDir,
  waitUntil,
} from './helpers.js'

describe('EventLog', () => {
  let dir: string
  let cleanup: () => Promise<void>
  beforeEach(async () => {
    ;({ dir, cleanup } = await tempDir())
    await mkdir(path.join(dir, 'events'), { recursive: true })
  })
  afterEach(() => cleanup())

  test('appends numbered events and publishes them through head.json', async () => {
    const log = new EventLog(dir, silent, { now: () => 1000 })
    await log.open()
    log.emit({ type: 'session-state', state: 'running' })
    log.emit({ type: 'local-merged', sha: 'a'.repeat(40) })
    await log.flush()
    const events = await readEvents(dir)
    assert.deepEqual(
      events.map((e) => [e.seq, e.ts, e.type]),
      [
        [1, 1000, 'session-state'],
        [2, 1000, 'local-merged'],
      ]
    )
    const head = JSON.parse(await readFile(path.join(dir, 'head.json'), 'utf8'))
    const seg = await readFile(path.join(dir, 'events', '1.jsonl'))
    assert.deepEqual(head, { segment: 1, length: seg.length })
  })

  test('coalesces deltas per conversation and keeps order', async () => {
    const log = new EventLog(dir, silent)
    await log.open()
    log.emit({ type: 'text-delta', conversationId: 'c1', text: 'Hel' })
    log.emit({ type: 'text-delta', conversationId: 'c1', text: 'lo' })
    log.emit({ type: 'thinking-delta', conversationId: 'c1', text: 'hm' })
    log.emit({ type: 'text-delta', conversationId: 'c1', text: '!' })
    // The finished deltas are written before the last one's window ends
    // (checked by polling, so a loaded machine can't make it flaky).
    await waitUntil(async () => (await readEvents(dir)).length >= 2, 5_000)
    const early = await readEvents(dir)
    assert.deepEqual(
      early.slice(0, 2).map((e) => e.type),
      ['text-delta', 'thinking-delta']
    )
    await waitUntil(async () => (await readEvents(dir)).length >= 3, 5_000)
    await new Promise((r) => setTimeout(r, DELTA_COALESCE_MS + 50))
    const events = await readEvents(dir)
    assert.deepEqual(
      events.map((e) => [e.type, (e as { text?: string }).text]),
      [
        ['text-delta', 'Hello'],
        ['thinking-delta', 'hm'],
        ['text-delta', '!'],
      ]
    )
  })

  test('drops invalid events instead of writing them', async () => {
    const logger = new MemoryLogger()
    const log = new EventLog(dir, logger)
    await log.open()
    log.emit({ type: 'local-merged', sha: 'not-a-sha' })
    log.emit({ type: 'local-merged', sha: 'b'.repeat(40) })
    await log.flush()
    const events = await readEvents(dir)
    assert.deepEqual(
      events.map((e) => e.seq),
      [1]
    )
    assert.ok(logger.has('error', /dropping invalid local-merged/))
  })

  test('continues seq after a restart and truncates unpublished bytes', async () => {
    const a = new EventLog(dir, silent)
    await a.open()
    a.emit({ type: 'session-state', state: 'running' })
    a.emit({ type: 'session-state', state: 'busy' })
    await a.flush()
    // A crash after appending but before head.json was rewritten.
    await writeFile(
      path.join(dir, 'events', '1.jsonl'),
      '{"seq":3,"ts":1,"type":"session-state","state":"waiting"}\n',
      { flag: 'a' }
    )
    const b = new EventLog(dir, silent)
    await b.open()
    assert.equal(b.lastSeq, 2)
    b.emit({ type: 'session-state', state: 'running' })
    await b.flush()
    const events = await readEvents(dir)
    assert.deepEqual(
      events.map((e) => [e.seq, (e as { state?: string }).state]),
      [
        [1, 'running'],
        [2, 'busy'],
        [3, 'running'],
      ]
    )
  })

  test('a failed write keeps its events and later writes go on, seq contiguous', async () => {
    let fail = false
    const log = new EventLog(dir, silent, {
      retryDelaysMs: [60_000],
      append: async (file, data) => {
        if (fail) {
          // Half of it reaches the file, then the mount errors.
          await appendToFile(file, String(data).slice(0, 10))
          throw Object.assign(new Error('stale handle'), { code: 'ESTALE' })
        }
        await appendToFile(file, data)
      },
    })
    await log.open()
    log.emit({ type: 'session-state', state: 'running' })
    await log.flush()
    fail = true
    log.emit({ type: 'session-state', state: 'busy' })
    await assert.rejects(log.flush(), /stale handle/)
    assert.equal(log.lastSeq, 1)
    fail = false
    log.emit({ type: 'session-state', state: 'waiting' })
    await log.flush()
    const events = await readEvents(dir)
    assert.deepEqual(
      events.map((e) => [e.seq, (e as { state?: string }).state]),
      [
        [1, 'running'],
        [2, 'busy'],
        [3, 'waiting'],
      ]
    )
    // The torn bytes of the failed attempt are gone.
    const head = JSON.parse(await readFile(path.join(dir, 'head.json'), 'utf8'))
    const seg = await readFile(path.join(dir, 'events', '1.jsonl'))
    assert.equal(seg.length, head.length)
  })

  test('recovers when the segment was briefly unwritable, retrying on its own', async () => {
    const log = new EventLog(dir, silent, { retryDelaysMs: [20] })
    await log.open()
    log.emit({ type: 'session-state', state: 'running' })
    await log.flush()
    const seg = path.join(dir, 'events', '1.jsonl')
    const published = await readFile(seg)
    // The segment turns into something that can't be appended to.
    await rm(seg)
    await mkdir(seg)
    log.emit({ type: 'session-state', state: 'busy' })
    await assert.rejects(log.flush())
    await rm(seg, { recursive: true })
    await writeFile(seg, published)
    // No new emit or flush: the retry timer writes the kept event.
    await waitUntil(async () => (await readEvents(dir)).length === 2, 5_000)
    log.emit({ type: 'session-state', state: 'waiting' })
    await log.flush()
    assert.deepEqual(
      (await readEvents(dir)).map((e) => e.seq),
      [1, 2, 3]
    )
  })

  test('writes nothing once closed, not even a pending retry', async () => {
    let fail = true
    let appends = 0
    const log = new EventLog(dir, silent, {
      retryDelaysMs: [10],
      append: async (file, data) => {
        appends++
        if (fail) throw Object.assign(new Error('EIO'), { code: 'EIO' })
        await appendToFile(file, data)
      },
    })
    await log.open()
    log.emit({ type: 'session-state', state: 'running' })
    await assert.rejects(log.flush())
    log.close()
    fail = false
    log.emit({ type: 'session-state', state: 'busy' })
    await new Promise((r) => setTimeout(r, 50))
    await log.flush()
    assert.equal(appends, 1)
    assert.deepEqual(await readEvents(dir), [])
  })

  test('cuts an oversized field down instead of dropping the event', async () => {
    const log = new EventLog(dir, silent)
    await log.open()
    log.emit({
      type: 'tool-call',
      conversationId: 'c',
      callId: 'call-1',
      name: 'fs__read_file',
      argsJson: '{}',
      status: 'done',
      result: 'x'.repeat(1_200_000),
    })
    await log.flush()
    const [event] = await readEvents(dir)
    const result = (event as { result: string }).result
    assert.equal(event?.type, 'tool-call')
    assert.ok(result.length <= 1_000_000)
    assert.match(result, /…\[truncated \d+ chars\]$/)
    const dropped = Number(/truncated (\d+) chars/.exec(result)![1])
    assert.equal(dropped + result.indexOf('…'), 1_200_000)
  })

  test('opens when head.json is ahead of its segment, continuing in a new one', async () => {
    const a = new EventLog(dir, silent)
    await a.open()
    a.emit({ type: 'session-state', state: 'running' })
    a.emit({ type: 'session-state', state: 'busy' })
    await a.flush()
    // The segment lost its last bytes; head.json kept the longer length.
    const seg = path.join(dir, 'events', '1.jsonl')
    const text = await readFile(seg, 'utf8')
    await writeFile(seg, text.slice(0, text.indexOf('\n') + 1))
    const b = new EventLog(dir, silent)
    await b.open()
    assert.equal(b.lastSeq, 1)
    b.emit({ type: 'session-state', state: 'waiting' })
    await b.flush()
    const head = JSON.parse(await readFile(path.join(dir, 'head.json'), 'utf8'))
    assert.equal(head.segment, 2)
    // A restart before anything else was written still continues.
    const c = new EventLog(dir, silent)
    await c.open()
    assert.equal(c.lastSeq, 2)
  })

  test('a fresh head segment with nothing in it keeps seq', async () => {
    const a = new EventLog(dir, silent)
    await a.open()
    a.emit({ type: 'session-state', state: 'running' })
    await a.flush()
    await writeFile(
      path.join(dir, 'head.json'),
      JSON.stringify({ segment: 2, length: 0 }) + '\n'
    )
    const b = new EventLog(dir, silent)
    await b.open()
    assert.equal(b.lastSeq, 1)
  })

  test('starts a new segment past 1 MB', async () => {
    const log = new EventLog(dir, silent)
    await log.open()
    const big = 'x'.repeat(400_000)
    for (let i = 0; i < 3; i++) {
      log.emit({ type: 'error', conversationId: 'c', message: big })
    }
    await log.flush()
    const head = JSON.parse(await readFile(path.join(dir, 'head.json'), 'utf8'))
    assert.equal(head.segment, 2)
    const events = await readEvents(dir)
    assert.deepEqual(
      events.map((e) => e.seq),
      [1, 2, 3]
    )
    // A restart finds the last seq in the new head segment.
    const again = new EventLog(dir, silent)
    await again.open()
    assert.equal(again.lastSeq, 3)
  })
})

describe('CommandReader', () => {
  let root: string
  let stateDir: string
  let cleanup: () => Promise<void>
  beforeEach(async () => {
    ;({ dir: root, cleanup } = await tempDir())
    stateDir = path.join(await initSessionFolder(root, SID), 'state')
  })
  afterEach(() => cleanup())

  const writeCommand = (n: number, body: unknown): Promise<void> =>
    writeFile(
      path.join(stateDir, 'commands', `${n}.json`),
      JSON.stringify(body)
    )
  const setSeq = (n: number): Promise<void> =>
    writeFile(path.join(stateDir, 'commands.seq'), `${n}\n`)

  test('creates commands.seq and delivers commands in order', async () => {
    const reader = new CommandReader(stateDir, silent)
    await reader.open()
    assert.equal(
      await readFile(path.join(stateDir, 'commands.seq'), 'utf8'),
      '0\n'
    )
    assert.deepEqual(await reader.poll(), [])
    await sendCommand(root, SID, { type: 'message', turnId: 't1', text: 'a' })
    await sendCommand(root, SID, { type: 'abort', turnId: 't1' })
    const cmds = await reader.poll()
    assert.deepEqual(
      cmds.map((c) => [c.id, c.type]),
      [
        [1, 'message'],
        [2, 'abort'],
      ]
    )
    // Delivered once.
    assert.deepEqual(await reader.poll(), [])
  })

  test('never opens a number commands.seq has not reached', async () => {
    const reader = new CommandReader(stateDir, silent)
    await reader.open()
    await writeCommand(1, { id: 1, ts: 1, type: 'stop' })
    // The file exists but seq still says 0: not read.
    assert.deepEqual(await reader.poll(), [])
    await setSeq(1)
    assert.equal((await reader.poll()).length, 1)
  })

  test('keeps the highest commands.seq seen when it goes backwards', async () => {
    const reader = new CommandReader(stateDir, silent)
    await reader.open()
    await writeCommand(1, { id: 1, ts: 1, type: 'abort', turnId: 'a' })
    await writeCommand(2, { id: 2, ts: 1, type: 'abort', turnId: 'b' })
    await writeCommand(3, { id: 3, ts: 1, type: 'abort', turnId: 'c' })
    await setSeq(1)
    assert.equal((await reader.poll()).length, 1)
    await setSeq(3)
    // A concurrent writer rewrites a smaller number after we read 3 —
    // but we haven't read 2 and 3 yet (say the read of 2 was half done).
    await setSeq(2)
    const cmds = await reader.poll()
    assert.deepEqual(
      cmds.map((c) => c.id),
      [2]
    )
    assert.equal(reader.seen, 2)
    await setSeq(3)
    assert.deepEqual(
      (await reader.poll()).map((c) => c.id),
      [3]
    )
    await setSeq(2)
    await writeCommand(4, { id: 4, ts: 1, type: 'abort', turnId: 'd' })
    // seq regressed below what we handled: nothing new, and 4 isn't probed.
    assert.deepEqual(await reader.poll(), [])
    assert.equal(reader.seen, 3)
  })

  test('waits for a half-written command, then skips it after the grace period', async () => {
    let now = 1_000
    const logger = new MemoryLogger()
    const reader = new CommandReader(stateDir, logger, { now: () => now })
    await reader.open()
    await writeFile(path.join(stateDir, 'commands', '1.json'), '{"id":1,')
    await writeCommand(2, { id: 2, ts: 1, type: 'abort', turnId: 'b' })
    await setSeq(2)
    assert.deepEqual(await reader.poll(), [])
    now += COMMAND_GRACE_MS - 1
    assert.deepEqual(await reader.poll(), [])
    now += 2
    const cmds = await reader.poll()
    assert.deepEqual(
      cmds.map((c) => c.id),
      [2]
    )
    assert.ok(logger.has('warn', /command 1 never became readable/))
  })

  test('retries a command the mount fails to read for a while, then skips it', async () => {
    let now = 1_000
    let failing = new Set([1, 2])
    const logger = new MemoryLogger()
    const reader = new CommandReader(stateDir, logger, {
      now: () => now,
      readText: async (file, max) => {
        const n = Number(path.basename(file, '.json'))
        if (failing.has(n)) {
          throw Object.assign(new Error('stale file handle'), {
            code: 'ESTALE',
          })
        }
        return readKnownText(file, max)
      },
    })
    await reader.open()
    await writeCommand(1, { id: 1, ts: 1, type: 'abort', turnId: 'a' })
    await writeCommand(2, { id: 2, ts: 1, type: 'abort', turnId: 'b' })
    await setSeq(2)
    // Past the half-written grace, still within the transient one.
    assert.deepEqual(await reader.poll(), [])
    now += COMMAND_GRACE_MS + 1
    assert.deepEqual(await reader.poll(), [])
    // The mount recovers for command 1: it's delivered, not lost.
    failing = new Set([2])
    assert.deepEqual(
      (await reader.poll()).map((c) => c.id),
      [1]
    )
    await reader.markHandled(1)
    // Command 2 keeps failing: skipped once the transient grace is over.
    assert.deepEqual(await reader.poll(), [])
    now += COMMAND_TRANSIENT_GRACE_MS + 1
    assert.deepEqual(await reader.poll(), [])
    assert.ok(logger.has('warn', /command 2 unreadable \(ESTALE\); skipping/))
    assert.equal(reader.handled, 2)
  })

  test('skips at once a command that fails to read for another reason', async () => {
    const logger = new MemoryLogger()
    const reader = new CommandReader(stateDir, logger, {
      readText: async () => {
        throw new Error('file too large: 1.json')
      },
    })
    await reader.open()
    await writeCommand(1, { id: 1, ts: 1, type: 'abort', turnId: 'a' })
    await setSeq(1)
    assert.deepEqual(await reader.poll(), [])
    assert.equal(reader.handled, 1)
    assert.ok(logger.has('warn', /command 1 unreadable \(file too large/))
  })

  test('recovers a half-written command that completes in time', async () => {
    const reader = new CommandReader(stateDir, silent)
    await reader.open()
    await writeFile(path.join(stateDir, 'commands', '1.json'), '')
    await setSeq(1)
    assert.deepEqual(await reader.poll(), [])
    await writeCommand(1, { id: 1, ts: 1, type: 'stop' })
    assert.equal((await reader.poll())[0]?.type, 'stop')
  })

  test('skips invalid commands and ones whose id does not match', async () => {
    const reader = new CommandReader(stateDir, silent)
    await reader.open()
    await writeCommand(1, { id: 1, ts: 1, type: 'launch-missiles' })
    await writeCommand(2, { id: 7, ts: 1, type: 'stop' })
    await writeCommand(3, { id: 3, ts: 1, type: 'stop' })
    await setSeq(3)
    const cmds = await reader.poll()
    assert.deepEqual(
      cmds.map((c) => c.id),
      [3]
    )
    assert.equal(reader.handled, 2)
  })

  test('refuses a command file that is a symlink', async () => {
    const reader = new CommandReader(stateDir, silent)
    await reader.open()
    await writeFile(
      path.join(root, 'elsewhere.json'),
      JSON.stringify({ id: 1, ts: 1, type: 'stop' })
    )
    await symlink(
      path.join(root, 'elsewhere.json'),
      path.join(stateDir, 'commands', '1.json')
    )
    await setSeq(1)
    assert.deepEqual(await reader.poll(), [])
    assert.equal(reader.handled, 1)
  })

  test('persists the handled prefix, so a restart redelivers what was pending', async () => {
    const a = new CommandReader(stateDir, silent)
    await a.open()
    for (let i = 0; i < 3; i++) {
      await sendCommand(root, SID, { type: 'abort', turnId: `t${i}` })
    }
    assert.equal((await a.poll()).length, 3)
    await a.markHandled(1)
    await a.markHandled(3) // out of order: 2 is still pending
    assert.equal(a.handled, 1)
    assert.equal(
      await readFile(path.join(stateDir, 'commands.done'), 'utf8'),
      '1\n'
    )

    const b = new CommandReader(stateDir, silent)
    await b.open()
    assert.deepEqual(
      (await b.poll()).map((c) => c.id),
      [2, 3]
    )
    await b.markHandled(2)
    await b.markHandled(3)
    assert.equal(b.handled, 3)
    await b.markHandledThrough(3)
    assert.equal(
      await readFile(path.join(stateDir, 'commands.done'), 'utf8'),
      '3\n'
    )
  })
})

describe('Lease', () => {
  let dir: string
  let cleanup: () => Promise<void>
  beforeEach(async () => {
    ;({ dir, cleanup } = await tempDir())
  })
  afterEach(() => cleanup())

  const read = async (): Promise<Record<string, unknown>> =>
    JSON.parse(await readFile(path.join(dir, 'lease.json'), 'utf8'))

  test('takes the lease, tracks state and releases with an expired lease', async () => {
    let now = 10_000
    const lease = new Lease(dir, 'task-a', silent, { now: () => now })
    await lease.acquire()
    assert.deepEqual(await read(), {
      taskId: 'task-a',
      state: 'running',
      expiresAt: 100_000,
    })
    await lease.set('busy', 'turn1')
    assert.deepEqual(await read(), {
      taskId: 'task-a',
      state: 'busy',
      turnId: 'turn1',
      expiresAt: 100_000,
    })
    now = 20_000
    await lease.release()
    assert.equal((await read()).expiresAt, 20_000)
  })

  test('refuses while another task holds a live lease, takes over a dead one', async () => {
    let now = 10_000
    await writeFile(
      path.join(dir, 'lease.json'),
      JSON.stringify({ taskId: 'task-b', state: 'running', expiresAt: 50_000 })
    )
    const lease = new Lease(dir, 'task-a', silent, { now: () => now })
    await assert.rejects(lease.acquire(), LeaseHeldError)
    now = 60_000
    await lease.acquire()
    assert.equal((await read()).taskId, 'task-a')
    await lease.release()
  })
})

describe('SessionJson and safe reads', () => {
  test('updates status and keeps unknown fields', async () => {
    const { dir: root, cleanup } = await tempDir()
    try {
      const dir = await initSessionFolder(root, SID, 5)
      const raw = JSON.parse(
        await readFile(path.join(dir, 'session.json'), 'utf8')
      )
      await writeFile(
        path.join(dir, 'session.json'),
        JSON.stringify({ ...raw, conversationId: null, future: 1 })
      )
      const s = new SessionJson(dir)
      assert.equal((await s.read()).conversationId, undefined)
      await s.update({
        status: 'parked',
        parkedReason: 'chain_forked',
        lastActivity: 3,
      })
      let after = JSON.parse(
        await readFile(path.join(dir, 'session.json'), 'utf8')
      )
      assert.equal(after.status, 'parked')
      assert.equal(after.parkedReason, 'chain_forked')
      assert.equal(after.lastActivity, 5) // never goes backwards
      assert.equal(after.future, 1)
      await s.update({
        status: 'running',
        parkedReason: null,
        conversationId: 'conv1',
      })
      after = JSON.parse(await readFile(path.join(dir, 'session.json'), 'utf8'))
      assert.equal(after.parkedReason, undefined)
      assert.equal(after.conversationId, 'conv1')
      assert.ok((await stat(path.join(dir, 'session.json'))).isFile())
    } finally {
      await cleanup()
    }
  })

  test('readKnownFile refuses symlinks and oversized files', async () => {
    const { dir, cleanup } = await tempDir()
    try {
      await writeFile(path.join(dir, 'a'), 'hello')
      await symlink(path.join(dir, 'a'), path.join(dir, 'link'))
      await assert.rejects(readKnownFile(path.join(dir, 'link'), 100))
      await assert.rejects(readKnownFile(path.join(dir, 'a'), 2), /too large/)
      assert.equal(await readKnownFile(path.join(dir, 'missing'), 2), null)
    } finally {
      await cleanup()
    }
  })
})

describe('CloudInteraction', () => {
  test('caps the tool text it puts in events', () => {
    const sent: CloudEventPayload[] = []
    const interaction = new CloudInteraction((p) => sent.push(p))
    const ctx = { conversationId: 'c', turnId: 't' }
    interaction.notifyToolStatus(
      'call-1',
      'done',
      { result: 'r'.repeat(MAX_TOOL_EVENT_TEXT + 500) },
      ctx
    )
    const result = (sent[0] as { result: string }).result
    assert.equal(
      result,
      'r'.repeat(MAX_TOOL_EVENT_TEXT) + '…[truncated 500 chars]'
    )
    interaction.notifyToolStatus('call-2', 'done', { result: 'short' }, ctx)
    assert.equal((sent[1] as { result: string }).result, 'short')
  })
})
