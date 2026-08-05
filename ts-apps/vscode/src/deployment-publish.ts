// Publish / unpublish a deployment on the Legalese Cloud marketplace.
//
// Talks to the platform endpoints on the bare cloud domain
// (`POST /marketplace/publish|unpublish?org={slug}`, l4:deploy) with the
// user's own session token — mirroring deployment-install.ts. The listing
// fields collected by the popover ride along in the body; the platform
// endpoint acts on deploymentId/mode/termsVersion today and the Provable
// site's API will consume the rest via the same call once it exists
// (VSCODE-PUBLISH-SPEC.md §4 — one URL swap, no shape change).

import * as vscode from 'vscode'
import type { AuthManager } from './auth.js'
import { LEGALESE_CLOUD_DOMAIN } from './auth.js'
import type { SidebarPublishParams } from 'jl4-client-rpc'

export interface PublishResult {
  success: boolean
  live?: boolean
  url?: string
  error?: string
}

async function callMarketplace(
  auth: AuthManager,
  outputChannel: vscode.OutputChannel,
  action: 'publish' | 'unpublish',
  body: Record<string, unknown>
): Promise<{ ok: boolean; status: number; json: Record<string, unknown> }> {
  const slug = auth.getCloudOrgSlug()
  const token = await auth.getSessionToken()
  if (!slug || !token) {
    return {
      ok: false,
      status: 401,
      json: { error: 'Sign in with Legalese Cloud first.' },
    }
  }
  const url = `https://${LEGALESE_CLOUD_DOMAIN}/marketplace/${action}?org=${encodeURIComponent(slug)}`
  outputChannel.appendLine(`[publish] POST ${url}`)
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  let json: Record<string, unknown> = {}
  try {
    json = (await resp.json()) as Record<string, unknown>
  } catch {
    // Non-JSON error body — fall through with the status alone.
  }
  return { ok: resp.ok, status: resp.status, json }
}

/** Map platform failures to actionable copy (VSCODE-PUBLISH-SPEC.md §4). */
function friendlyError(status: number, json: Record<string, unknown>): string {
  if (status === 422) {
    return "This deployment has no 'Intended use' description. Add one and redeploy before publishing."
  }
  if (status === 403) {
    return "Your role can't publish (deploy rights required)."
  }
  if (status === 404) {
    return 'Deployment not found on Legalese Cloud.'
  }
  return typeof json.error === 'string'
    ? json.error
    : `Marketplace request failed (HTTP ${status})`
}

export async function publishDeployment(
  params: SidebarPublishParams,
  auth: AuthManager,
  outputChannel: vscode.OutputChannel
): Promise<PublishResult> {
  const { ok, status, json } = await callMarketplace(
    auth,
    outputChannel,
    'publish',
    {
      deploymentId: params.deploymentId,
      mode: params.mode,
      termsVersion: params.termsVersion,
      listing: params.listing,
    }
  )
  if (!ok) {
    const error = friendlyError(status, json)
    outputChannel.appendLine(`[publish] failed (${status}): ${error}`)
    return { success: false, error }
  }
  const live = json.live === true
  const slug = auth.getCloudOrgSlug()
  outputChannel.appendLine(
    `[publish] ${params.deploymentId} published (${params.mode}, live: ${live})`
  )
  return {
    success: true,
    live,
    // Listing URL: the skills registry until the Provable site ships.
    url: slug ? `https://skills.${LEGALESE_CLOUD_DOMAIN}/${slug}` : undefined,
  }
}

export async function unpublishDeployment(
  deploymentId: string,
  auth: AuthManager,
  outputChannel: vscode.OutputChannel
): Promise<{ success: boolean; error?: string }> {
  const { ok, status, json } = await callMarketplace(
    auth,
    outputChannel,
    'unpublish',
    { deploymentId }
  )
  if (!ok) {
    const error = friendlyError(status, json)
    outputChannel.appendLine(`[publish] unpublish failed (${status}): ${error}`)
    return { success: false, error }
  }
  outputChannel.appendLine(`[publish] ${deploymentId} unpublished`)
  return { success: true }
}
