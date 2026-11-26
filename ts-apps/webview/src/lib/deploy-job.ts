/**
 * What happens after a deploy has been sent: polling the job to an outcome, and
 * deciding what the sidebar shows for each outcome. Pure (the clock and the
 * network are passed in), so that every outcome can be tested; the sidebar
 * page only calls these.
 */
import type {
  DefaultChangeNotice,
  SidebarDeployResponse,
  SidebarUpdateStatusResponse,
} from 'jl4-client-rpc'
import {
  noticeSummary,
  reportAfterDeploy,
  type DeployReport,
} from './deploy-compat'

/**
 * Any thrown value as a readable string. A request through the webview
 * messenger can reject with a plain object (a JSON-RPC error), which `String`
 * turns into "[object Object]".
 */
export function errorText(err: unknown): string {
  if (err instanceof Error) return err.message || err.name
  if (typeof err === 'string') return err
  if (err !== null && typeof err === 'object') {
    const { message, error } = err as { message?: unknown; error?: unknown }
    if (typeof message === 'string' && message) return message
    if (typeof error === 'string' && error) return error
    try {
      return JSON.stringify(err)
    } catch {
      return 'an object that could not be written as text'
    }
  }
  return String(err)
}

/** How a deploy ended. */
export type JobOutcome =
  /** The job was applied. `notices` is the job result's field as it came:
   *  `undefined` when the service predates the report. */
  | { kind: 'applied'; notices: unknown }
  /** The service rejected the job (it puts `notices` on a rejection too). */
  | { kind: 'rejected'; error?: string; notices: unknown }
  /** The result could not be read, repeatedly: the deploy may have been applied. */
  | { kind: 'unreadable'; error?: string }
  /** Still compiling when we stopped asking. */
  | { kind: 'in-progress' }
  /** No job: the service resolved it at once (same content). */
  | { kind: 'immediate' }

/**
 * Ask for the job until it is applied or rejected. A job that cannot be read
 * (the extension's `unreadable`, or a request that threw) is transient once or
 * twice and is then reported as unreadable: it is not a rejection, because the
 * service did not say that.
 */
export async function pollDeployJob(
  fetchStatus: () => Promise<SidebarUpdateStatusResponse>,
  options: {
    sleep: (ms: number) => Promise<void>
    attempts?: number
    maxUnreadable?: number
  }
): Promise<JobOutcome> {
  const attempts = options.attempts ?? 60
  const maxUnreadable = options.maxUnreadable ?? 3
  let unreadable = 0
  let lastError: string | undefined
  for (let i = 0; i < attempts; i++) {
    await options.sleep(1000)
    let resp: SidebarUpdateStatusResponse | undefined
    try {
      resp = await fetchStatus()
    } catch (err) {
      lastError = errorText(err)
    }
    if (!resp || resp.status === 'unreadable') {
      if (resp) lastError = resp.error
      unreadable += 1
      if (unreadable >= maxUnreadable) {
        return { kind: 'unreadable', error: lastError }
      }
      continue
    }
    unreadable = 0
    if (resp.status === 'applied') {
      return { kind: 'applied', notices: resp.notices }
    }
    if (resp.status === 'rejected') {
      return { kind: 'rejected', error: resp.error, notices: resp.notices }
    }
  }
  return { kind: 'in-progress' }
}

/** What the sidebar does once a deploy has ended. */
export interface DeployFinish {
  /** Changed defaults, to show until dismissed (`null`: nothing to say). */
  report: DeployReport | null
  /** Switch to the Deployments tab. */
  showDeployments: boolean
  /** Fetch the deployments list again. */
  refreshDeployments: boolean
  toast: { type: 'info' | 'warning' | 'error'; message: string }
}

export function finishDeploy(args: {
  deploymentId: string
  outcome: JobOutcome
  /** The changed defaults the review held before the deploy was sent. */
  reviewNotices: DefaultChangeNotice[]
  /** The rules' schemas as they were when the deploy was sent. */
  schemas: DeployReport['schemas']
}): DeployFinish {
  const { deploymentId: id, outcome, reviewNotices, schemas } = args
  const said = (jobNotices: unknown) =>
    reportAfterDeploy({ jobNotices, reviewNotices })

  switch (outcome.kind) {
    case 'applied': {
      const s = said(outcome.notices)
      const report = s
        ? { deploymentId: id, outcome: 'applied' as const, ...s, schemas }
        : null
      return {
        report,
        showDeployments: true,
        refreshDeployments: true,
        toast: {
          type: 'info',
          message:
            `Deployed "${id}" successfully.` +
            (report ? ` ${noticeSummary(report.notices, report.source)}.` : ''),
        },
      }
    }
    case 'rejected': {
      const s = said(outcome.notices)
      const report = s
        ? { deploymentId: id, outcome: 'rejected' as const, ...s, schemas }
        : null
      return {
        report,
        showDeployments: false,
        refreshDeployments: false,
        toast: {
          type: 'error',
          message: `Deploy "${id}" rejected: ${outcome.error ?? 'compilation error'}`,
        },
      }
    }
    case 'unreadable':
      // Not rejected, and not known to be applied: the service did not say.
      return {
        report:
          reviewNotices.length > 0
            ? {
                deploymentId: id,
                outcome: 'unknown',
                source: 'unread',
                notices: reviewNotices,
                schemas,
              }
            : null,
        showDeployments: true,
        // Not refreshed: the list request answers an empty list on any error,
        // which would show "No deployments yet" under the banner and hide the
        // deployment. The list we have stays.
        refreshDeployments: false,
        toast: {
          type: 'warning',
          message: `The result of deploying "${id}" could not be read; it may have been applied.`,
        },
      }
    case 'in-progress':
      return {
        report: null,
        showDeployments: true,
        refreshDeployments: false,
        toast: {
          type: 'warning',
          message: `Deploying "${id}" — still in progress. Refresh later.`,
        },
      }
    case 'immediate':
      return {
        report: null,
        showDeployments: true,
        refreshDeployments: true,
        toast: { type: 'info', message: `Deployed "${id}" successfully.` },
      }
  }
}

/** What `runDeploy` needs from the page: the two requests, the clock and the
 *  page's `deploying` flag. Fakes of these test the whole sequence. */
export interface DeployPorts {
  /** Send the deploy. Called once per run. */
  sendDeploy: () => Promise<SidebarDeployResponse>
  /** Ask for a job: the id the send returned, and the job's id. */
  fetchStatus: (
    deploymentId: string,
    updateId: string
  ) => Promise<SidebarUpdateStatusResponse>
  sleep: (ms: number) => Promise<void>
  isDeploying: () => boolean
  setDeploying: (deploying: boolean) => void
}

export type RunDeployResult =
  /** Another deploy is in progress: nothing was sent. */
  | { kind: 'busy' }
  /** The deploy was not sent, or the send failed: stay on the form. */
  | { kind: 'failed'; toast: DeployFinish['toast'] }
  /** The deploy was sent and has ended: leave the form and show `finish`. */
  | { kind: 'done'; finish: DeployFinish }

/**
 * The whole sequence after the person confirms: refuse to start while another
 * deploy is in progress, send the deploy ONCE, poll the job it started by the
 * id the send returned, decide what to show, and clear the `deploying` flag on
 * every way out, including a send that throws. The page only calls this.
 */
export async function runDeploy(
  ports: DeployPorts,
  args: {
    deploymentId: string
    reviewNotices: DefaultChangeNotice[]
    schemas: DeployReport['schemas']
  }
): Promise<RunDeployResult> {
  if (ports.isDeploying()) return { kind: 'busy' }
  ports.setDeploying(true)
  try {
    const result = await ports.sendDeploy()
    if (!result.success) {
      return {
        kind: 'failed',
        toast: { type: 'error', message: result.error || 'Deploy failed' },
      }
    }
    const id = result.deploymentId ?? args.deploymentId
    const updateId = result.updateId
    // No updateId: resolved at once (same content). Otherwise poll the job.
    const outcome: JobOutcome = updateId
      ? await pollDeployJob(() => ports.fetchStatus(id, updateId), {
          sleep: ports.sleep,
        })
      : { kind: 'immediate' }
    if (outcome.kind === 'unreadable') {
      console.error(
        `Could not read the result of deploying "${id}"; it may have been applied.`,
        outcome.error
      )
    }
    return {
      kind: 'done',
      finish: finishDeploy({
        deploymentId: id,
        outcome,
        reviewNotices: args.reviewNotices,
        schemas: args.schemas,
      }),
    }
  } catch (err) {
    return {
      kind: 'failed',
      toast: { type: 'error', message: errorText(err) || 'Deploy failed' },
    }
  } finally {
    ports.setDeploying(false)
  }
}
