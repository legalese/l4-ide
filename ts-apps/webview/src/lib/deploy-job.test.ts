import { describe, expect, it } from 'vitest'
import type {
  DefaultChangeNotice,
  SidebarUpdateStatusResponse,
} from 'jl4-client-rpc'
import { finishDeploy, pollDeployJob, type JobOutcome } from './deploy-job'

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
