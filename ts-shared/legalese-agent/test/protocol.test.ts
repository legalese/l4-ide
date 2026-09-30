import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import type { ChatServiceEvent } from '../src/index.js'
import {
  ProtocolError,
  agentKeyName,
  chatEventToPayload,
  ABANDONED_TMP_DAYS,
  addFilesRequest,
  addFilesResponse,
  clientCommand,
  deletedCopyPath,
  isModelWritableRepoPath,
  decodeSealed,
  encodeSealed,
  cloudEventToChatEvent,
  createSessionRequest,
  eventsResponse,
  formatCommandSeq,
  formatCursor,
  formatEventLine,
  formatEventsQuery,
  generateSealingKeyPair,
  isSealingPublicKey,
  mcpCredentials,
  mcpCredentialsContext,
  openSealed,
  parseAgentKeyError,
  parseAgentKeyName,
  parseCloudCommand,
  parseCloudEvent,
  parseCommandSeq,
  parseCursor,
  parseEventChunk,
  parseEventsQuery,
  parseHeadFile,
  parseLeaseFile,
  parseSessionFile,
  seal,
  sessionPaths,
  tryParse,
  type CloudEvent,
  type SessionFile,
} from '../src/protocol/index.js'

const SID = '01J9Z8X7W6V5T4S3R2Q1P0N9M8'

describe('session files', () => {
  const session: SessionFile = {
    sessionId: SID,
    ownerUserId: 'user_01ABC',
    title: 'Tax rules',
    created: 1_790_000_000_000,
    lastActivity: 1_790_000_060_000,
    status: 'running',
    mcpServers: [
      { name: 'docs', url: 'https://mcp.example.com/mcp', transport: 'http' },
    ],
  }

  test('session.json reads the Sessions API form (nulls as absent)', () => {
    const parsed = parseSessionFile(
      JSON.stringify({ ...session, conversationId: null, orgId: null })
    )
    assert.deepEqual(parsed, session)
  })

  test('session.json round-trips and drops unknown fields', () => {
    const parsed = parseSessionFile(
      JSON.stringify(session).replace(
        /}$/,
        ',"extra":"x","__proto__":{"polluted":1}}'
      )
    )
    assert.deepEqual(parsed, session)
    assert.equal(({} as Record<string, unknown>).polluted, undefined)
  })

  test('session.json rejects secrets-shaped junk and bad ids', () => {
    assert.throws(
      () => parseSessionFile(JSON.stringify({ ...session, sessionId: '../x' })),
      ProtocolError
    )
    assert.throws(
      () =>
        parseSessionFile(
          JSON.stringify({
            ...session,
            mcpServers: [
              { name: 'a', url: 'http://plain.example', transport: 'http' },
            ],
          })
        ),
      /mcpServers\[0\]\.url/
    )
    assert.throws(
      () =>
        parseSessionFile(
          JSON.stringify({
            ...session,
            mcpServers: [session.mcpServers[0], session.mcpServers[0]],
          })
        ),
      /duplicate MCP server name/
    )
  })

  test('lease, head and commands.seq', () => {
    assert.deepEqual(
      parseLeaseFile(
        '{"taskId":"abc123","state":"busy","turnId":"t1","expiresAt":5}'
      ),
      { taskId: 'abc123', state: 'busy', turnId: 't1', expiresAt: 5 }
    )
    assert.deepEqual(parseHeadFile('{"segment":2,"length":10}'), {
      segment: 2,
      length: 10,
    })
    assert.throws(() => parseHeadFile('{"segment":0,"length":0}'))
    assert.equal(parseCommandSeq(formatCommandSeq(42)), 42)
    assert.equal(parseCommandSeq('4 2'), null)
  })

  test('paths stay inside the session folder', () => {
    const p = sessionPaths(SID)
    assert.equal(p.command(3), `sessions/${SID}/state/commands/3.json`)
    assert.equal(p.eventSegment(0), `sessions/${SID}/state/events/0.jsonl`)
    assert.equal(
      p.incomingBundle(`${SID}.bundle`),
      `sessions/${SID}/state/git/incoming/${SID}.bundle`
    )
    assert.throws(() => sessionPaths('../../etc'))
    assert.throws(() => p.attachment('../secret'))
    assert.throws(() => p.incomingBundle('x.bundle'))
    assert.throws(() => p.command(-1))
  })

  test('repo layout: data/, tmp/, deleted copies, writable paths', () => {
    const p = sessionPaths(SID)
    assert.equal(p.repoData, `sessions/${SID}/repo/data`)
    assert.equal(p.repoTmp, `sessions/${SID}/repo/tmp`)
    assert.equal(p.repoDeleted, `sessions/${SID}/repo/tmp/deleted`)
    assert.equal(
      deletedCopyPath('turn1', 'rules/tax.l4'),
      'tmp/deleted/t-turn1/rules/tax.l4'
    )
    assert.equal(
      p.deletedCopy('turn1', 'a.l4'),
      `sessions/${SID}/repo/tmp/deleted/t-turn1/a.l4`
    )
    assert.throws(() => deletedCopyPath('turn1', '../x'))
    assert.throws(() => deletedCopyPath('turn1', '/etc/passwd'))
    assert.throws(() => deletedCopyPath('a/b', 'x'))
    assert.equal(isModelWritableRepoPath('data/rules/tax.l4'), true)
    assert.equal(isModelWritableRepoPath('./tmp/notes.md'), true)
    assert.equal(isModelWritableRepoPath('data/.hidden'), true)
    assert.equal(isModelWritableRepoPath('data'), false)
    assert.equal(isModelWritableRepoPath('tmp/'), false)
    assert.equal(isModelWritableRepoPath('session-meta.json'), false)
    assert.equal(isModelWritableRepoPath('.git/config'), false)
    assert.equal(isModelWritableRepoPath('data/../x'), false)
    assert.equal(isModelWritableRepoPath('/data/x'), false)
    assert.equal(ABANDONED_TMP_DAYS, 30)
  })

  test('cursors', () => {
    assert.deepEqual(parseCursor('0'), { segment: 0, offset: 0 })
    assert.deepEqual(parseCursor('3:1024'), { segment: 3, offset: 1024 })
    assert.equal(parseCursor('3:-1'), null)
    assert.equal(formatCursor({ segment: 1, offset: 2 }), '1:2')
    assert.equal(formatCursor({ segment: 0, offset: 0 }), '0')
  })
})

describe('events', () => {
  test('chat-service events map to cloud events and back', () => {
    const chat: ChatServiceEvent[] = [
      { kind: 'started', conversationId: 'c1', turnId: 't1', model: 'm' },
      { kind: 'text-delta', conversationId: 'c1', text: 'hi' },
      {
        kind: 'tool-call',
        conversationId: 'c1',
        callId: 'call_1',
        name: 'fs__read_file',
        argsJson: '{}',
        status: 'running',
      },
      {
        kind: 'done',
        conversationId: 'c1',
        finishReason: 'stop',
        usage: { promptTokens: 1, completionTokens: 2 },
      },
      { kind: 'queue-consumed', conversationId: 'c1', injectionIds: ['i1'] },
    ]
    chat.forEach((e, i) => {
      const event = parseCloudEvent({
        seq: i + 1,
        ts: 1000,
        ...chatEventToPayload(e),
      })
      assert.deepEqual(cloudEventToChatEvent(event), e)
    })
  })

  test('cloud-only events validate and are not chat events', () => {
    const event = parseCloudEvent({
      seq: 1,
      ts: 1,
      type: 'git-committed',
      turnId: 't1',
      sha: 'a'.repeat(40),
      parent: 'b'.repeat(40),
    })
    assert.equal(cloudEventToChatEvent(event), null)
    assert.throws(
      () =>
        parseCloudEvent({
          seq: 1,
          ts: 1,
          type: 'rolled-back',
          turnId: 't',
          sha: 'zz',
        }),
      /sha/
    )
    assert.throws(
      () => parseCloudEvent({ seq: 1, ts: 1, type: 'nope' }),
      /unknown type/
    )
    assert.throws(() => parseCloudEvent({ seq: 0, ts: 1, type: 'stop' }))
  })

  test('JSONL chunks: complete lines only, invalid lines skipped', () => {
    const a: CloudEvent = {
      seq: 1,
      ts: 1,
      type: 'session-state',
      state: 'running',
      publicKey: generateSealingKeyPair().publicKey,
    }
    const b: CloudEvent = {
      seq: 2,
      ts: 2,
      type: 'user-message',
      turnId: 't1',
      text: 'héllo',
      attachments: [],
    }
    const text =
      formatEventLine(a) + 'garbage\n' + formatEventLine(b) + '{"seq":3'
    const chunk = Buffer.from(text, 'utf8')
    const out = parseEventChunk(chunk)
    assert.deepEqual(out.events, [a, b])
    assert.equal(out.invalid, 1)
    assert.equal(
      out.bytes,
      Buffer.byteLength(text) - Buffer.byteLength('{"seq":3')
    )
  })
})

describe('commands', () => {
  test('client commands validate; apply-bundle is internal', () => {
    assert.deepEqual(
      clientCommand(
        {
          type: 'message',
          turnId: 't1',
          text: 'go',
          attachments: ['brief.pdf'],
        },
        ''
      ),
      { type: 'message', turnId: 't1', text: 'go', attachments: ['brief.pdf'] }
    )
    assert.throws(
      () => clientCommand({ type: 'apply-bundle', file: `${SID}.bundle` }, ''),
      /not a client command/
    )
    assert.throws(
      () =>
        clientCommand(
          { type: 'message', turnId: 't1', text: 'x', attachments: ['../a'] },
          ''
        ),
      ProtocolError
    )
    assert.deepEqual(
      parseCloudCommand({
        id: 7,
        ts: 9,
        type: 'apply-bundle',
        file: `${SID}.bundle`,
      }),
      { id: 7, ts: 9, type: 'apply-bundle', file: `${SID}.bundle` }
    )
  })
})

describe('no tool approvals in cloud sessions', () => {
  test('approval-request events and approve commands are rejected', () => {
    assert.throws(
      () =>
        parseCloudEvent({
          seq: 1,
          ts: 1,
          type: 'approval-request',
          conversationId: 'c',
          turnId: 't',
          callId: 'k',
          name: 'fs__delete_file',
          argsJson: '{}',
        }),
      /unknown type/
    )
    assert.throws(
      () =>
        clientCommand({ type: 'approve', callId: 'k', decision: 'allow' }, ''),
      /unknown type/
    )
    // Questions stay.
    assert.equal(
      clientCommand({ type: 'answer', callId: 'k', answer: 'yes' }, '').type,
      'answer'
    )
  })
})

describe('files added mid-session', () => {
  const BATCH = '01J9Z8X7W6V5T4S3R2Q1P0N9MA'

  test('paths, request, response, command and event', () => {
    const p = sessionPaths(SID)
    assert.equal(p.incomingFiles, `sessions/${SID}/incoming/files`)
    assert.equal(
      p.incomingFile(BATCH, 'data/rules/tax.l4'),
      `sessions/${SID}/incoming/files/${BATCH}/data/rules/tax.l4`
    )
    assert.throws(() => p.incomingFile(BATCH, 'tmp/x'))
    assert.throws(() => p.incomingFile('nope', 'data/x'))

    const req = tryParse(addFilesRequest, {
      files: [{ path: 'data/a.l4', size: 10, contentType: 'text/plain' }],
    })
    assert.equal(req.ok, true)
    for (const bad of [
      { files: [] },
      { files: [{ path: 'a.l4', size: 1, contentType: 'text/plain' }] },
      { files: [{ path: 'data/../x', size: 1, contentType: 'text/plain' }] },
      {
        files: [
          { path: 'data/a', size: 1, contentType: 'text/plain' },
          { path: 'data/a', size: 1, contentType: 'text/plain' },
        ],
      },
      {
        files: Array.from({ length: 6 }, (_, i) => ({
          path: `data/f${i}`,
          size: 10 * 1024 * 1024,
          contentType: 'application/pdf',
        })),
      },
    ]) {
      assert.equal(tryParse(addFilesRequest, bad).ok, false)
    }
    assert.equal(
      tryParse(addFilesResponse, {
        batchId: BATCH,
        uploads: [
          {
            path: 'data/a.l4',
            url: 'https://s3.example/x',
            method: 'PUT',
            headers: {},
            maxBytes: 10,
          },
        ],
      }).ok,
      true
    )

    // add-files is internal, like apply-bundle.
    const cmd = {
      type: 'add-files',
      batchId: BATCH,
      files: [{ path: 'data/a.l4' }],
    }
    assert.throws(() => clientCommand(cmd, ''), /not a client command/)
    assert.equal(parseCloudCommand({ id: 1, ts: 1, ...cmd }).type, 'add-files')

    const ev = parseCloudEvent({
      seq: 1,
      ts: 1,
      type: 'files-added',
      batchId: BATCH,
      files: [{ path: 'data/a.l4', sha: 'c'.repeat(40) }],
    })
    assert.equal(ev.type, 'files-added')
  })

  test('message context names the files the user meant', () => {
    const m = clientCommand(
      {
        type: 'message',
        turnId: 't1',
        text: 'check @tax.l4',
        context: {
          activeFile: 'data/main.l4',
          mentions: ['data/rules/tax.l4'],
        },
      },
      ''
    )
    assert.deepEqual((m as { context?: unknown }).context, {
      activeFile: 'data/main.l4',
      mentions: ['data/rules/tax.l4'],
    })
    assert.throws(() =>
      clientCommand(
        {
          type: 'message',
          turnId: 't1',
          text: 'x',
          context: { mentions: ['/etc/x'] },
        },
        ''
      )
    )
  })
})

describe('Sessions API and agent keys', () => {
  test('create-session request', () => {
    const r = tryParse(createSessionRequest, {
      title: 'x',
      seedSize: 1024,
      attachments: [
        { name: 'a.pdf', contentType: 'application/pdf', size: 10 },
      ],
    })
    assert.equal(r.ok, true)
    const tooBig = tryParse(createSessionRequest, {
      seedSize: 60 * 1024 * 1024,
    })
    assert.equal(tooBig.ok, false)
  })

  test('events query round-trips', () => {
    const q = formatEventsQuery([
      { sessionId: SID, cursor: { segment: 1, offset: 20 } },
    ])
    assert.equal(q, `s=${SID}%3A1%3A20`)
    const values = new URLSearchParams(q).getAll('s')
    assert.deepEqual(parseEventsQuery(values), [
      { sessionId: SID, cursor: { segment: 1, offset: 20 } },
    ])
    assert.deepEqual(parseEventsQuery([`${SID}:0`]), [
      { sessionId: SID, cursor: { segment: 0, offset: 0 } },
    ])
    assert.throws(() => parseEventsQuery([`${SID}:0`, `${SID}:1`]), /duplicate/)
    assert.throws(() => parseEventsQuery(['nope:0']), ProtocolError)
  })

  test('events response validates nested events', () => {
    const ok = tryParse(eventsResponse, {
      sessions: [
        { sessionId: SID, events: [], cursor: '0:0', state: 'sleeping' },
      ],
    })
    assert.equal(ok.ok, true)
    const bad = tryParse(eventsResponse, {
      sessions: [
        {
          sessionId: SID,
          events: [{ seq: 1 }],
          cursor: '0:0',
          state: 'sleeping',
        },
      ],
    })
    assert.equal(bad.ok, false)
  })

  test('agent key names and errors', () => {
    const name = agentKeyName(SID, 1_790_000_000)
    assert.equal(name, `cloud-session:${SID}:1790000000`)
    assert.deepEqual(parseAgentKeyName(name), {
      sessionId: SID,
      chainStartEpochSeconds: 1_790_000_000,
    })
    assert.equal(parseAgentKeyName('cloud-session:x:1'), null)
    assert.equal(parseAgentKeyError({ error: 'chain_forked' }), 'chain_forked')
    assert.equal(parseAgentKeyError({ error: 'toString' }), null)
  })
})

describe('sealed secrets', () => {
  const credentials = JSON.stringify({
    servers: [{ name: 'docs', headers: { Authorization: 'Bearer secret' } }],
  })

  test('seal → open round-trips and yields valid credentials', () => {
    const harness = generateSealingKeyPair()
    assert.ok(isSealingPublicKey(harness.publicKey))
    const ctx = mcpCredentialsContext(SID)
    const envelope = seal(harness.publicKey, credentials, ctx)
    // The command carrying it (compact string form) validates…
    const sealed = encodeSealed(envelope)
    const command = clientCommand({ type: 'mcp-credentials', sealed }, '')
    assert.deepEqual(decodeSealed(sealed), envelope)
    // …and only the harness can open it.
    const plain = openSealed(
      harness,
      (command as { sealed: string }).sealed,
      ctx
    ).toString('utf8')
    assert.deepEqual(
      mcpCredentials(JSON.parse(plain), ''),
      JSON.parse(credentials)
    )
    assert.ok(!JSON.stringify(envelope).includes('secret'))
  })

  test('wrong key, wrong context or tampering fail', () => {
    const harness = generateSealingKeyPair()
    const other = generateSealingKeyPair()
    const ctx = mcpCredentialsContext(SID)
    const envelope = seal(harness.publicKey, credentials, ctx)
    assert.throws(() => openSealed(other, envelope, ctx))
    assert.throws(() =>
      openSealed(
        harness,
        envelope,
        mcpCredentialsContext('01J9Z8X7W6V5T4S3R2Q1P0N9M9')
      )
    )
    const ct = Buffer.from(envelope.ct, 'base64url')
    ct[0] = ct[0]! ^ 1
    assert.throws(() =>
      openSealed(harness, { ...envelope, ct: ct.toString('base64url') }, ctx)
    )
    assert.throws(
      () => seal('not-a-key', 'x', ctx),
      /invalid sealing public key/
    )
  })

  test('each seal uses a fresh ephemeral key and IV', () => {
    const harness = generateSealingKeyPair()
    const a = seal(harness.publicKey, 'same', 'c')
    const b = seal(harness.publicKey, 'same', 'c')
    assert.notEqual(a.epk, b.epk)
    assert.notEqual(a.ct, b.ct)
  })
})
