/**
 * `--dev` helpers: create a session folder the way `POST /sessions`
 * does, and queue commands the way `POST /sessions/:sid/commands`
 * does (exclusive create of the next number, then rewrite
 * `commands.seq`), so a scripted session can run against a local
 * folder and a local ai-proxy.
 */
import { promises as fs } from 'node:fs'
import * as path from 'node:path'
import {
  clientCommand,
  formatCommandSeq,
  parseCommandSeq,
  sessionPaths,
  type ClientCommandPayload,
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
    `${p.state}/git/incoming`,
  ]) {
    await fs.mkdir(path.join(root, d), { recursive: true })
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
