import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

/**
 * The sidebar page cannot be rendered under vitest (it needs the VS Code
 * webview API and a messenger, and this setup has no DOM), so what it does
 * after a deploy is decided in pure modules (`deploy-job.ts`,
 * `deploy-compat.ts`) and tested there. What this file pins is that the page
 * CALLS them, in the places that matter: delete one of these lines from the
 * page and a test here fails. It reads the page's source, so it is a check of
 * wiring, not of behaviour; the behaviour is in the modules' tests.
 */
const page = readFileSync(
  new URL('../routes/sidebar/+page.svelte', import.meta.url),
  'utf8'
)
const provider = readFileSync(
  new URL('../../../vscode/src/sidebar-provider.ts', import.meta.url),
  'utf8'
)

/** The text of a top-level function of the page's script, by name. */
function fn(source: string, name: string): string {
  const start = source.search(
    new RegExp(`^  (async )?function ${name}\\(`, 'm')
  )
  expect(start, `function ${name} not found`).toBeGreaterThanOrEqual(0)
  const end = source.indexOf('\n  }\n', start)
  return source.slice(start, end + 4)
}

describe('the sidebar page: deploying', () => {
  const executeDeploy = fn(page, 'executeDeploy')

  it('polls the job through pollDeployJob and decides what to show in finishDeploy', () => {
    expect(executeDeploy).toContain('pollDeployJob(')
    expect(executeDeploy).toContain('finishDeploy(')
  })

  it('hands finishDeploy the changed defaults the review held', () => {
    expect(executeDeploy).toContain('reviewNotices: defaultNotices')
  })

  it('shows what finishDeploy says: the report, the toast, the tab and the refresh', () => {
    expect(executeDeploy).toContain('deployReport = finish.report')
    expect(executeDeploy).toContain(
      'notify(finish.toast.type, finish.toast.message)'
    )
    expect(executeDeploy).toContain(
      "if (finish.showDeployments) activeTab = 'deployments'"
    )
    expect(executeDeploy).toContain(
      'if (finish.refreshDeployments) await fetchDeployments()'
    )
  })

  it('keeps no per-outcome logic of its own', () => {
    expect(executeDeploy).not.toContain('reportAfterDeploy')
    expect(executeDeploy).not.toContain('resp.notices')
    expect(executeDeploy).not.toContain("outcome === 'rejected'")
  })

  it('snapshots the rules BEFORE the deploy is sent', () => {
    const snapshot = executeDeploy.indexOf('$state.snapshot(functions)')
    const send = executeDeploy.indexOf('RequestSidebarDeploy')
    expect(snapshot).toBeGreaterThanOrEqual(0)
    expect(snapshot).toBeLessThan(send)
    expect(executeDeploy).toContain('schemas,')
  })
})

describe('the sidebar page: reviewing', () => {
  const continueDeploy = fn(page, 'continueDeploy')

  it('clears the previous review before it asks the service anything', () => {
    const firstAwait = continueDeploy.indexOf('await ')
    for (const line of ['defaultNotices = []', 'breakingChanges = []']) {
      const at = continueDeploy.indexOf(line)
      expect(at, line).toBeGreaterThanOrEqual(0)
      expect(at, line).toBeLessThan(firstAwait)
    }
  })

  it('takes the review from reviewDeploy, notices as well as the breaking list', () => {
    expect(continueDeploy).toContain('reviewDeploy(functions, remoteFns)')
    expect(continueDeploy).toContain('defaultNotices = review.notices')
    expect(continueDeploy).toContain('breakingChanges = review.breaking')
  })

  it('clears the report and the notices when the Deploy form opens', () => {
    const show = fn(page, 'showDeployForm')
    expect(show).toContain('defaultNotices = []')
    expect(show).toContain('deployReport = null')
  })
})

describe('the sidebar page: after an undeploy', () => {
  it('clears a report about the deployment that was removed', () => {
    expect(fn(page, 'handleUndeploy')).toContain(
      'deployReport = clearReportFor(deployReport, deploymentId)'
    )
  })
})

describe('the sidebar page: where the report is shown', () => {
  it('shows a rejected one on the Deploy tab and the others on the Deployments tab', () => {
    expect(page).toContain("{#if deployReport?.outcome === 'rejected'}")
    expect(page).toContain(
      "{#if deployReport && deployReport.outcome !== 'rejected'"
    )
    expect(page.match(/<DeployReportBanner/g)).toHaveLength(2)
  })
})

describe('the extension: reading a job', () => {
  const handler = provider.slice(
    provider.indexOf('GetSidebarUpdateStatus, async')
  )
  const body = handler.slice(0, handler.indexOf('\n  })\n'))

  it('forwards the job`s notices', () => {
    expect(body).toContain('notices: resp.notices')
  })

  it('does not call a job it could not read rejected', () => {
    const catchBlock = body.slice(body.indexOf('catch'))
    expect(catchBlock).toContain("status: 'unreadable'")
    expect(catchBlock).not.toMatch(/status:\s*'rejected'/)
  })
})
