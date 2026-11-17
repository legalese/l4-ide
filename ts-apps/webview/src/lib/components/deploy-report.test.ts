import { describe, expect, it } from 'vitest'
import { render } from 'svelte/server'
import type { DefaultChangeNotice } from 'jl4-client-rpc'
import DeployReport from './deploy-report.svelte'

const notice: DefaultChangeNotice = {
  kind: 'default-changed',
  function: 'the smaller of',
  input: 'b',
  old: 0,
  new: 1,
}

const text = (report: {
  deploymentId: string
  outcome: 'applied' | 'rejected' | 'unknown'
  source: 'service' | 'review' | 'unread'
}) =>
  render(DeployReport, {
    props: {
      report: { ...report, notices: [notice], schemas: [] },
      onDismiss: () => {},
    },
  })
    .body.replace(/<!--.*?-->/g, '')
    .replace(/<\/(li|div|p)>/g, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim()

describe('DeployReport', () => {
  it('for an applied update reported by the service, says the new defaults are in use', () => {
    const t = text({
      deploymentId: 'smaller',
      outcome: 'applied',
      source: 'service',
    })
    expect(t).toContain('Defaults changed in smaller')
    expect(t).toContain(
      'A caller who leaves one of these inputs out now gets the new value.'
    )
    expect(t).toContain('the smaller of · b · typically 0 → 1')
    expect(t).not.toContain('did not report')
  })

  it('for a rejected update, says nothing changed and names what would have', () => {
    const t = text({
      deploymentId: 'smaller',
      outcome: 'rejected',
      source: 'service',
    })
    expect(t).toContain('Update of smaller rejected')
    expect(t).toContain(
      'Nothing changed. The update would have changed these defaults:'
    )
    expect(t).not.toContain('now gets the new value')
  })

  it('when the service did not report them, says the list is the one from before the deploy', () => {
    const t = text({
      deploymentId: 'smaller',
      outcome: 'applied',
      source: 'review',
    })
    expect(t).toContain(
      'Reported before the deploy; the service did not report them.'
    )
  })

  it('does the same for a rejected update', () => {
    const t = text({
      deploymentId: 'smaller',
      outcome: 'rejected',
      source: 'review',
    })
    expect(t).toContain(
      'Reported before the deploy; the service did not report them.'
    )
    expect(t).toContain('Nothing changed.')
  })

  it('for a result that could not be read, says it may have been applied and never that nothing changed', () => {
    const t = text({
      deploymentId: 'smaller',
      outcome: 'unknown',
      source: 'unread',
    })
    expect(t).toContain('Deploy of smaller: result not read')
    expect(t).toContain('The deploy may have been applied.')
    expect(t).toContain(
      'Reported before the deploy; the result of the deploy could not be read.'
    )
    expect(t).not.toContain('Nothing changed')
    expect(t).not.toContain('rejected')
    expect(t).not.toContain('the service did not report them')
  })

  it('for a result that could not be read, hedges each line instead of claiming the new default is in use', () => {
    const t = text({
      deploymentId: 'smaller',
      outcome: 'unknown',
      source: 'unread',
    })
    expect(t).toContain(
      'if the deploy was applied, callers who leave b out will get different answers.'
    )
    expect(t).not.toContain(
      'b · typically 0 → 1: callers who leave b out will get'
    )
  })

  it('for a rejected update, each line says what would have happened', () => {
    const t = text({
      deploymentId: 'smaller',
      outcome: 'rejected',
      source: 'service',
    })
    expect(t).toContain(
      'callers who leave b out would have got different answers.'
    )
    expect(t).not.toContain('will get')
  })

  it('for an applied update, each line says what will happen', () => {
    const t = text({
      deploymentId: 'smaller',
      outcome: 'applied',
      source: 'service',
    })
    expect(t).toContain('callers who leave b out will get different answers.')
    expect(t).not.toContain('would have')
  })
})
