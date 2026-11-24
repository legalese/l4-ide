import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type {
  DefaultChangeNotice,
  SidebarDeployResponse,
  SidebarUpdateStatusResponse,
} from 'jl4-client-rpc'
import {
  errorText,
  finishDeploy,
  pollDeployJob,
  runDeploy,
  type DeployPorts,
  type JobOutcome,
} from './deploy-job'

const notice: DefaultChangeNotice = {
  kind: 'default-changed',
  function: 'the smaller of',
  input: 'b',
  old: 0,
  new: 1,
}

/** A fetchStatus that answers from a script, one answer per call; a function
 *  in the script throws. Counts the calls. */
function scripted(answers: Array<SidebarUpdateStatusResponse | Error>) {
  let calls = 0
  const fetchStatus = async (): Promise<SidebarUpdateStatusResponse> => {
    const answer = answers[Math.min(calls, answers.length - 1)]!
    calls += 1
    if (answer instanceof Error) throw answer
    return answer
  }
  return { fetchStatus, calls: () => calls }
}
const noSleep = async () => {}

describe('pollDeployJob', () => {
  it('stops at an applied job and hands over the job`s notices as they came', async () => {
    const { fetchStatus, calls } = scripted([
      { status: 'compiling' },
      { status: 'applied', notices: [notice] },
    ])
    expect(await pollDeployJob(fetchStatus, { sleep: noSleep })).toEqual({
      kind: 'applied',
      notices: [notice],
    })
    expect(calls()).toBe(2)
  })

  it('stops at a rejected job and hands over its error and its notices', async () => {
    const { fetchStatus } = scripted([
      { status: 'rejected', error: 'type error', notices: [notice] },
    ])
    expect(await pollDeployJob(fetchStatus, { sleep: noSleep })).toEqual({
      kind: 'rejected',
      error: 'type error',
      notices: [notice],
    })
  })

  it('hands over no notices as undefined, which is a service that predates them', async () => {
    const { fetchStatus } = scripted([{ status: 'applied' }])
    const outcome = await pollDeployJob(fetchStatus, { sleep: noSleep })
    expect(outcome).toEqual({ kind: 'applied', notices: undefined })
  })

  it('keeps polling while the job compiles, and gives up as in progress', async () => {
    const { fetchStatus, calls } = scripted([{ status: 'compiling' }])
    expect(
      await pollDeployJob(fetchStatus, { sleep: noSleep, attempts: 5 })
    ).toEqual({ kind: 'in-progress' })
    expect(calls()).toBe(5)
  })

  it('treats one unreadable answer as transient and goes on', async () => {
    const { fetchStatus } = scripted([
      { status: 'unreadable', error: 'network' },
      { status: 'applied', notices: [] },
    ])
    expect(await pollDeployJob(fetchStatus, { sleep: noSleep })).toEqual({
      kind: 'applied',
      notices: [],
    })
  })

  it('reports a job it could not read three times running as unreadable, not as rejected', async () => {
    const { fetchStatus, calls } = scripted([
      { status: 'unreadable', error: 'HTTP 502' },
    ])
    expect(await pollDeployJob(fetchStatus, { sleep: noSleep })).toEqual({
      kind: 'unreadable',
      error: 'HTTP 502',
    })
    expect(calls()).toBe(3)
  })

  it('counts a thrown error like an unreadable answer', async () => {
    const { fetchStatus } = scripted([new Error('port closed')])
    expect(await pollDeployJob(fetchStatus, { sleep: noSleep })).toEqual({
      kind: 'unreadable',
      error: 'port closed',
    })
  })

  it('does not count unreadable answers that a good answer separates', async () => {
    const { fetchStatus } = scripted([
      { status: 'unreadable' },
      { status: 'unreadable' },
      { status: 'compiling' },
      { status: 'unreadable' },
      { status: 'unreadable' },
      { status: 'applied', notices: [] },
    ])
    expect((await pollDeployJob(fetchStatus, { sleep: noSleep })).kind).toBe(
      'applied'
    )
  })

  it('waits between polls', async () => {
    const waited: number[] = []
    const { fetchStatus } = scripted([
      { status: 'compiling' },
      { status: 'applied' },
    ])
    await pollDeployJob(fetchStatus, {
      sleep: async (ms) => {
        waited.push(ms)
      },
    })
    expect(waited).toEqual([1000, 1000])
  })
})

describe('finishDeploy: what each outcome shows', () => {
  const schemas = [{ name: 'the smaller of', parameters: {} }]
  const finish = (outcome: JobOutcome, reviewNotices = [notice]) =>
    finishDeploy({ deploymentId: 'smaller', outcome, reviewNotices, schemas })

  it('applied, with the service`s list: the report is the service`s, on the Deployments tab', () => {
    const f = finish({ kind: 'applied', notices: [notice] }, [])
    expect(f.report).toMatchObject({
      deploymentId: 'smaller',
      outcome: 'applied',
      source: 'service',
      notices: [notice],
    })
    expect(f.showDeployments).toBe(true)
    expect(f.refreshDeployments).toBe(true)
    expect(f.toast).toEqual({
      type: 'info',
      message: 'Deployed "smaller" successfully. 1 default changed.',
    })
  })

  it('applied, by a service that sent no list: the review`s list, marked as such', () => {
    const f = finish({ kind: 'applied', notices: undefined })
    expect(f.report).toMatchObject({
      outcome: 'applied',
      source: 'review',
      notices: [notice],
    })
  })

  it('applied with nothing to say says nothing but the toast', () => {
    const f = finish({ kind: 'applied', notices: [] }, [notice])
    expect(f.report).toBeNull()
    expect(f.toast).toEqual({
      type: 'info',
      message: 'Deployed "smaller" successfully.',
    })
  })

  it('rejected: the list the service sent, nothing changed, stay on the Deploy tab', () => {
    const f = finish(
      { kind: 'rejected', error: 'type error', notices: [notice] },
      []
    )
    expect(f.report).toMatchObject({
      outcome: 'rejected',
      source: 'service',
      notices: [notice],
    })
    expect(f.showDeployments).toBe(false)
    expect(f.refreshDeployments).toBe(false)
    expect(f.toast).toEqual({
      type: 'error',
      message: 'Deploy "smaller" rejected: type error',
    })
  })

  it('rejected without an error says compilation error', () => {
    expect(finish({ kind: 'rejected', notices: undefined }).toast.message).toBe(
      'Deploy "smaller" rejected: compilation error'
    )
  })

  it('rejected, by a service that sent no list: the review`s list, marked as such', () => {
    expect(
      finish({ kind: 'rejected', notices: undefined }).report
    ).toMatchObject({
      outcome: 'rejected',
      source: 'review',
    })
  })

  it('could not read the result: not rejected, it may have been applied, and the review`s list is marked as unconfirmed', () => {
    const f = finish({ kind: 'unreadable', error: 'HTTP 502' })
    expect(f.report).toMatchObject({
      outcome: 'unknown',
      source: 'unread',
      notices: [notice],
    })
    expect(f.showDeployments).toBe(true)
    expect(f.toast.type).toBe('warning')
    expect(f.toast.message).toBe(
      'The result of deploying "smaller" could not be read; it may have been applied.'
    )
    expect(f.toast.message).not.toContain('rejected')
  })

  it('does not ask for the deployments list again when the result could not be read', () => {
    // The list request answers an empty list on any error, which would show
    // "No deployments yet" and hide the deployment: keep the list we have.
    expect(
      finish({ kind: 'unreadable', error: 'HTTP 502' }).refreshDeployments
    ).toBe(false)
    expect(finish({ kind: 'unreadable' }, []).refreshDeployments).toBe(false)
  })

  it('does not mark the review`s list as one the service did not report when the service was never read', () => {
    expect(finish({ kind: 'unreadable' }).report!.source).toBe('unread')
  })

  it('says how many changes the review reported, not that they changed, when the service did not report', () => {
    expect(finish({ kind: 'applied', notices: undefined }).toast.message).toBe(
      'Deployed "smaller" successfully. 1 default change was reported before the deploy.'
    )
    expect(
      finish({ kind: 'applied', notices: undefined }, [notice, notice]).toast
        .message
    ).toBe(
      'Deployed "smaller" successfully. 2 default changes were reported before the deploy.'
    )
  })

  it('could not read the result, with nothing reviewed: only the toast', () => {
    expect(finish({ kind: 'unreadable' }, []).report).toBeNull()
  })

  it('still in progress: no report, no refresh, the same message as before', () => {
    const f = finish({ kind: 'in-progress' })
    expect(f.report).toBeNull()
    expect(f.showDeployments).toBe(true)
    expect(f.refreshDeployments).toBe(false)
    expect(f.toast).toEqual({
      type: 'warning',
      message: 'Deploying "smaller" — still in progress. Refresh later.',
    })
  })

  it('resolved at once (same content, no job): deployed, nothing reported', () => {
    const f = finish({ kind: 'immediate' })
    expect(f.report).toBeNull()
    expect(f.showDeployments).toBe(true)
    expect(f.refreshDeployments).toBe(true)
    expect(f.toast.message).toBe('Deployed "smaller" successfully.')
  })

  it('carries the schemas it was given into the report', () => {
    expect(finish({ kind: 'applied', notices: [notice] }).report!.schemas).toBe(
      schemas
    )
  })

  it('claims nothing changed only for a rejected job', () => {
    for (const outcome of [
      { kind: 'applied', notices: [notice] },
      { kind: 'unreadable' },
      { kind: 'in-progress' },
      { kind: 'immediate' },
    ] as JobOutcome[]) {
      expect(finish(outcome).report?.outcome).not.toBe('rejected')
    }
  })
})

describe('errorText: any thrown value as a readable string', () => {
  it('reads an Error by its message', () => {
    expect(errorText(new Error('port closed'))).toBe('port closed')
  })

  it('reads a string as it is', () => {
    expect(errorText('HTTP 502')).toBe('HTTP 502')
  })

  it('reads a plain object with a message, as a JSON-RPC rejection has', () => {
    expect(errorText({ code: -32603, message: 'internal error' })).toBe(
      'internal error'
    )
  })

  it('reads a plain object with an error string', () => {
    expect(errorText({ error: 'not allowed' })).toBe('not allowed')
  })

  it('never says [object Object]', () => {
    expect(errorText({ code: 7 })).toBe('{"code":7}')
    const circular: Record<string, unknown> = {}
    circular['self'] = circular
    expect(errorText(circular)).not.toContain('[object Object]')
  })

  it('reads the rest as text', () => {
    expect(errorText(undefined)).toBe('undefined')
    expect(errorText(null)).toBe('null')
    expect(errorText(42)).toBe('42')
  })
})

describe('pollDeployJob: a plain-object rejection', () => {
  it('is reported by its message, not as [object Object]', async () => {
    let calls = 0
    const fetchStatus = async (): Promise<SidebarUpdateStatusResponse> => {
      calls += 1
      throw { code: -32603, message: 'port closed' }
    }
    expect(await pollDeployJob(fetchStatus, { sleep: async () => {} })).toEqual(
      {
        kind: 'unreadable',
        error: 'port closed',
      }
    )
    expect(calls).toBe(3)
  })
})

/** The two ports of a run, as fakes that count what they are asked. */
function ports(
  opts: {
    send?: () => Promise<SidebarDeployResponse>
    statuses?: Array<SidebarUpdateStatusResponse | Error>
    deploying?: boolean
  } = {}
) {
  const sent: number[] = []
  const asked: Array<{ deploymentId: string; updateId: string }> = []
  const flag: boolean[] = []
  let current = opts.deploying ?? false
  const statuses = opts.statuses ?? [{ status: 'applied' }]
  const p: DeployPorts = {
    sendDeploy:
      opts.send ??
      (async () => {
        return { success: true, deploymentId: 'returned-id', updateId: 'job-1' }
      }),
    fetchStatus: async (deploymentId, updateId) => {
      asked.push({ deploymentId, updateId })
      const answer = statuses[Math.min(asked.length - 1, statuses.length - 1)]!
      if (answer instanceof Error) throw answer
      return answer
    },
    sleep: async () => {},
    isDeploying: () => current,
    setDeploying: (v) => {
      current = v
      flag.push(v)
    },
  }
  const original = p.sendDeploy
  p.sendDeploy = async () => {
    sent.push(1)
    return original()
  }
  return { p, sent, asked, flag }
}

const U: SidebarUpdateStatusResponse = { status: 'unreadable' }
const C: SidebarUpdateStatusResponse = { status: 'compiling' }
const A: SidebarUpdateStatusResponse = { status: 'applied', notices: [] }
const R: SidebarUpdateStatusResponse = {
  status: 'rejected',
  error: 'type error',
}

const run = (p: DeployPorts) =>
  runDeploy(p, {
    deploymentId: 'asked-for-id',
    reviewNotices: [],
    schemas: [],
  })

describe('runDeploy: send once, poll, finish', () => {
  // A result that cannot be read is logged (and tested to be, below): keep the
  // run quiet.
  let logged: ReturnType<typeof vi.spyOn>
  beforeEach(() => {
    logged = vi.spyOn(console, 'error').mockImplementation(() => {})
  })
  afterEach(() => {
    vi.restoreAllMocks()
  })

  const sequences: Array<[string, Array<SidebarUpdateStatusResponse | Error>]> =
    [
      ['applied at once', [A]],
      ['compiling, then applied', [C, A]],
      [
        'unreadable twice, compiling, unreadable twice, applied',
        [U, U, C, U, U, A],
      ],
      ['unreadable three times', [U, U, U]],
      ['rejected', [R]],
      ['compiling for ever (the poll times out)', [C]],
      ['a thrown error each time', [new Error('boom')]],
    ]

  for (const [name, statuses] of sequences) {
    it(`sends the deploy exactly once: ${name}`, async () => {
      const { p, sent } = ports({ statuses })
      await run(p)
      expect(sent).toHaveLength(1)
    })

    it(`asks for the job by the id the send returned, every time: ${name}`, async () => {
      const { p, asked } = ports({ statuses })
      await run(p)
      expect(asked.length).toBeGreaterThan(0)
      for (const a of asked) {
        expect(a).toEqual({ deploymentId: 'returned-id', updateId: 'job-1' })
      }
    })

    it(`clears the deploying flag once the run is over: ${name}`, async () => {
      const { p, flag } = ports({ statuses })
      await run(p)
      expect(flag).toEqual([true, false])
    })
  }

  it('uses the id it was asked for when the send returns none', async () => {
    const { p, asked } = ports({
      send: async () => ({ success: true, updateId: 'job-2' }),
    })
    await run(p)
    expect(asked[0]!.deploymentId).toBe('asked-for-id')
  })

  it('asks for no job when the send returns none (resolved at once)', async () => {
    const { p, asked } = ports({
      send: async () => ({ success: true, deploymentId: 'd' }),
    })
    const result = await run(p)
    expect(asked).toEqual([])
    expect(result).toMatchObject({
      kind: 'done',
      finish: { toast: { message: 'Deployed "d" successfully.' } },
    })
  })

  it('finishes with what the job said: applied and rejected', async () => {
    const applied = await run(ports({ statuses: [A] }).p)
    expect(applied).toMatchObject({
      kind: 'done',
      finish: { toast: { type: 'info' } },
    })
    const rejected = await run(ports({ statuses: [R] }).p)
    expect(rejected).toMatchObject({
      kind: 'done',
      finish: {
        toast: {
          type: 'error',
          message: 'Deploy "returned-id" rejected: type error',
        },
      },
    })
  })

  it('does nothing when a deploy is already in progress', async () => {
    const { p, sent, asked, flag } = ports({ deploying: true })
    expect(await run(p)).toEqual({ kind: 'busy' })
    expect(sent).toEqual([])
    expect(asked).toEqual([])
    expect(flag).toEqual([])
  })

  it('does not start a second deploy while the first polls', async () => {
    // The first run is still polling (its poll never answers) when a second
    // starts: the second finds the flag set and sends nothing.
    let release!: () => void
    const held = new Promise<void>((r) => (release = r))
    const first = ports({ statuses: [C, A] })
    const slow = first.p.fetchStatus
    first.p.fetchStatus = async (id, job) => {
      await held
      return slow(id, job)
    }
    const running = run(first.p)
    await Promise.resolve()
    await Promise.resolve()
    expect(await run(first.p)).toEqual({ kind: 'busy' })
    expect(first.sent).toHaveLength(1)
    release()
    await running
    expect(first.sent).toHaveLength(1)
  })

  it('reports a send that failed, clears the flag, and polls nothing', async () => {
    const { p, asked, flag } = ports({
      send: async () => ({ success: false, error: 'no such file' }),
    })
    expect(await run(p)).toEqual({
      kind: 'failed',
      toast: { type: 'error', message: 'no such file' },
    })
    expect(asked).toEqual([])
    expect(flag).toEqual([true, false])
  })

  it('says "Deploy failed" for a failed send that gave no reason', async () => {
    const { p } = ports({ send: async () => ({ success: false }) })
    expect(await run(p)).toMatchObject({
      toast: { message: 'Deploy failed' },
    })
  })

  it('reports a send that throws, clears the flag, and never reads the thrown value as [object Object]', async () => {
    for (const thrown of [
      new Error('port closed'),
      { message: 'port closed' },
    ]) {
      const { p, flag, asked } = ports({
        send: async () => {
          throw thrown
        },
      })
      expect(await run(p)).toEqual({
        kind: 'failed',
        toast: { type: 'error', message: 'port closed' },
      })
      expect(flag).toEqual([true, false])
      expect(asked).toEqual([])
    }
  })

  it('logs why a result could not be read', async () => {
    const { p } = ports({
      statuses: [{ status: 'unreadable', error: 'HTTP 502' }],
    })
    await run(p)
    expect(logged).toHaveBeenCalledTimes(1)
    expect(String(logged.mock.calls[0]![0])).toContain('returned-id')
    expect(logged.mock.calls[0]![1]).toBe('HTTP 502')
  })
})
