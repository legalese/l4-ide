/**
 * Deployment versions, each asked for at most once per `ttlMs`.
 *
 * The chat's rule rows ask for a rule's schema, and the extension checks
 * the deployment's version first so a redeploy brings a fresh schema. A
 * conversation with many rule rows used to ask for the deployment's status
 * once per row, though the cached schema answered them all. Now rows for
 * the same deployment share one check per minute, and concurrent ones
 * share one request. A redeploy within that minute keeps the old schema
 * until the check runs again. A failed check isn't remembered: the next
 * row asks again.
 *
 * No `vscode` import, so the unit tests can run it.
 */
export class DeploymentVersionCache {
  private readonly checked = new Map<
    string,
    { version: string; checkedAt: number }
  >()
  private readonly inFlight = new Map<string, Promise<string>>()

  constructor(
    private readonly fetchVersion: (deployId: string) => Promise<string>,
    private readonly ttlMs = 60_000,
    private readonly now: () => number = Date.now
  ) {}

  version(deployId: string): Promise<string> {
    const known = this.checked.get(deployId)
    if (known && this.now() - known.checkedAt < this.ttlMs) {
      return Promise.resolve(known.version)
    }
    const pending = this.inFlight.get(deployId)
    if (pending) return pending
    const work = this.fetchVersion(deployId)
      .then((version) => {
        this.checked.set(deployId, { version, checkedAt: this.now() })
        return version
      })
      .finally(() => this.inFlight.delete(deployId))
    this.inFlight.set(deployId, work)
    return work
  }
}
