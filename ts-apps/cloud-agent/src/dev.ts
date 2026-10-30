/**
 * `--dev` helpers: create a session folder the way `POST /sessions`
 * does, claim a run the way `POST /sessions/:sid/start` does (§7.3), and
 * queue commands the way `POST /sessions/:sid/commands` does (exclusive
 * create of the next number, then rewrite `commands.seq`), so a scripted
 * session can run against a local folder and a local ai-proxy.
 */
import { promises as fs } from 'node:fs'
import * as path from 'node:path'
import {
  API_LEASE_TASK_ID,
  START_GRACE_MS,
  clientCommand,
  formatCommandSeq,
  isRunNumber,
  parseCommandSeq,
  sessionPaths,
  type ClientCommandPayload,
  type RunLeaseFile,
  type RunRecordFile,
  type SessionFile,
} from '@repo/legalese-agent/protocol'
import {
  createExclusive,
  isErrno,
  readKnownText,
  writeAtomic,
} from './safe-fs.js'

export async function initSessionFolder(
  root: string,
  sessionId: string,
  now = Date.now()
): Promise<string> {
  const p = sessionPaths(sessionId)
  const dir = path.join(root, p.dir)
  for (const d of [
    p.repo,
    p.repoData,
    p.repoTmp,
    p.attachments,
    `${p.state}/events`,
    `${p.state}/commands`,
    p.runs,
    `${p.state}/git/incoming`,
  ]) {
    await fs.mkdir(path.join(root, d), { recursive: true })
  }
  // No run yet (§7.3), as `POST /sessions` writes it.
  try {
    await createExclusive(path.join(root, p.runsSeq), '0\n')
  } catch (err) {
    if (!isErrno(err, 'EEXIST')) throw err
  }
  const session: SessionFile = {
    sessionId,
    ownerUserId: 'dev',
    title: '',
    created: now,
    lastActivity: now,
    status: 'new',
    mcpServers: [],
  }
  try {
    await createExclusive(
      path.join(root, p.sessionJson),
      JSON.stringify(session, null, 2) + '\n'
    )
  } catch (err) {
    if (!isErrno(err, 'EEXIST')) throw err
  }
  return dir
}

/**
 * Claim the session's next run the way the Sessions API's `start` does
 * (§7.3): exclusive-create `runs/<n>.json` after the latest, write its
 * `starting` lease, then `runs.seq`. Returns the run number. A harness
 * still running an earlier run sees the new record at its next renewal
 * and stops.
 */
export async function claimDevRun(
  root: string,
  sessionId: string,
  now = Date.now()
): Promise<number> {
  const p = sessionPaths(sessionId)
  await fs.mkdir(path.join(root, p.runs), { recursive: true })
  const seqFile = path.join(root, p.runsSeq)
  const readSeq = async (): Promise<number> => {
    const n = Number(((await readKnownText(seqFile, 64)) ?? '0').trim())
    return isRunNumber(n) ? n : 0
  }
  let n = (await readSeq()) + 1
  for (;;) {
    const record: RunRecordFile = { run: n, createdAt: now }
    try {
      await createExclusive(
        path.join(root, p.runRecord(n)),
        JSON.stringify(record) + '\n'
      )
      break
    } catch (err) {
      if (!isErrno(err, 'EEXIST')) throw err
      n++
    }
  }
  const lease: RunLeaseFile = {
    run: n,
    taskId: API_LEASE_TASK_ID,
    state: 'starting',
    expiresAt: now + START_GRACE_MS,
  }
  await writeAtomic(
    path.join(root, p.runLease(n)),
    JSON.stringify(lease) + '\n'
  )
  if ((await readSeq()) < n) await writeAtomic(seqFile, `${n}\n`)
  return n
}

/** Queue a client command; returns its number. */
export async function sendCommand(
  root: string,
  sessionId: string,
  command: unknown,
  now = Date.now()
): Promise<number> {
  const payload: ClientCommandPayload = clientCommand(command, 'command')
  const p = sessionPaths(sessionId)
  const seqFile = path.join(root, p.commandSeq)
  const readSeq = async (): Promise<number> =>
    parseCommandSeq((await readKnownText(seqFile, 64)) ?? '0') ?? 0
  let n = (await readSeq()) + 1
  for (;;) {
    try {
      await createExclusive(
        path.join(root, p.command(n)),
        JSON.stringify({ ...payload, id: n, ts: now })
      )
      break
    } catch (err) {
      if (!isErrno(err, 'EEXIST')) throw err
      n++
    }
  }
  if ((await readSeq()) < n) await writeAtomic(seqFile, formatCommandSeq(n))
  return n
}
