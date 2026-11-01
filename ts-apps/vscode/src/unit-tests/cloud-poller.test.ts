import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import type {
  EventStreamRequest,
  EventStreamResponse,
  SessionState,
} from '@repo/legalese-agent/protocol'
import {
  EventPoller,
  POLL_BUSY_MS,
  POLL_GRACE_MS,
  POLL_IDLE_MS,
} from '../cloud/event-poller.js'
import { FakeClock, flush, sid } from './cloud-fakes.js'

function setup(states: Map<string, SessionState>, moreTimes = 0) {
  let more = moreTimes
  const clock = new FakeClock()
  const requests: EventStreamRequest[][] = []
  const seen: string[] = []
  let respond: ((r: EventStreamRequest[]) => Promise<void>) | undefined
  const poller = new EventPoller({
    getEvents: async (streams) => {
      requests.push(streams)
      if (respond) await respond(streams)
      return {
        streams: streams.map(
          (s): EventStreamResponse => ({
            sessionId: s.sessionId,
            events: [],
            cursor: `1:${requests.length * 10}`,
            state: states.get(s.sessionId) ?? 'running',
            ...(more-- > 0 ? { more: true } : {}),
          })
        ),
      }
    },
    onStream: (s) => {
      seen.push(s.sessionId)
    },
    now: clock.now,
    setTimer: clock.setTimer,
    clearTimer: clock.clearTimer,
  })
  return {
    clock,
    poller,
    requests,
    seen,
    setRespond: (f: typeof respond) => (respond = f),
  }
}

describe('EventPoller', () => {
  test('polls every second while busy, every 5 s while running', async () => {
    const states = new Map<string, SessionState>([[sid(1), 'busy']])
    const { clock, poller, requests } = setup(states)
    poller.watch(sid(1))
    await clock.advance(0)
    assert.equal(requests.length, 1)
    assert.deepEqual(requests[0], [
      { sessionId: sid(1), cursor: { segment: 0, offset: 0 } },
    ])
    assert.equal(clock.pending(), POLL_BUSY_MS)
    await clock.advance(POLL_BUSY_MS)
    assert.equal(requests.length, 2)
    // The cursor advances from the response.
    assert.deepEqual(requests[1]![0]!.cursor, { segment: 1, offset: 10 })
    states.set(sid(1), 'running')
    await clock.advance(POLL_BUSY_MS)
    assert.equal(clock.pending(), POLL_IDLE_MS)
  })

  test('stops for sleeping sessions after the grace period; poke resumes', async () => {
    const states = new Map<string, SessionState>([[sid(1), 'sleeping']])
    const { clock, poller, requests } = setup(states)
    poller.watch(sid(1))
    await clock.advance(POLL_GRACE_MS + 5_000)
    const n = requests.length
    assert.ok(n > 1)
    assert.equal(clock.pending(), undefined)
    await clock.advance(60_000)
    assert.equal(requests.length, n)
    poller.poke(sid(1))
    await clock.advance(0)
    assert.equal(requests.length, n + 1)
  })

  test('batches at most 10 sessions per request', async () => {
    const states = new Map<string, SessionState>()
    const { clock, poller, requests } = setup(states)
    for (let i = 1; i <= 12; i++) poller.watch(sid(i))
    await clock.advance(0)
    assert.deepEqual(
      requests.map((r) => r.length),
      [10, 2]
    )
  })

  test('polls again at once when the response says more', async () => {
    const states = new Map<string, SessionState>([[sid(1), 'running']])
    const { clock, poller, requests } = setup(states, 2)
    poller.watch(sid(1))
    await clock.advance(0)
    assert.equal(requests.length, 3)
    assert.equal(clock.pending(), POLL_IDLE_MS)
  })

  test('ignores a response for a cursor that was reset meanwhile', async () => {
    const states = new Map<string, SessionState>([[sid(1), 'busy']])
    const { clock, poller, requests, seen, setRespond } = setup(states)
    poller.watch(sid(1), { cursor: { segment: 3, offset: 40 } })
    setRespond(async () => {
      setRespond(undefined)
      // The view reopens the session (replay from the start) while
      // this request is in flight.
      poller.watch(sid(1), { cursor: { segment: 0, offset: 0 } })
    })
    await clock.advance(0)
    await flush()
    assert.equal(seen.length, 1, 'only the replay response is delivered')
    assert.deepEqual(requests[1]![0]!.cursor, { segment: 0, offset: 0 })
    assert.deepEqual(poller.cursorOf(sid(1)), { segment: 1, offset: 20 })
  })
})
