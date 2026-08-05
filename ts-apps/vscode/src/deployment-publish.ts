// Publish / unpublish a deployment on the Provable marketplace.
//
// Primary target is the Provable site API
// (`POST https://provable.legalese.com/api/skills/{org}/{dep}/publish`),
// which forwards the user's own bearer to the platform endpoint AND
// records the listing metadata + publisher row in one call
// (PROVABLE-SITE-SPEC.md §3). If the site is unreachable (network error
// or 5xx), we fall back to the platform endpoint on the bare cloud
// domain (`POST /marketplace/publish|unpublish?org={slug}`) so publish
// state itself never depends on the website being up — the site's cron
// registry-sync picks the listing up afterwards.

import * as vscode from 'vscode'
import type { AuthManager } from './auth.js'
import { LEGALESE_CLOUD_DOMAIN } from './auth.js'
import type { SidebarPublishParams } from 'jl4-client-rpc'

const PROVABLE_SITE = 'https://provable.legalese.com'

export interface PublishResult {
  success: boolean
  live?: boolean
  url?: string
  error?: string
}

interface MarketplaceResponse {
  ok: boolean
  status: number
  json: Record<string, unknown>
}

async function post(
  url: string,
  token: string,
  body: Record<string, unknown>
): Promise<MarketplaceResponse> {
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

async function callMarketplace(
  auth: AuthManager,
  outputChannel: vscode.OutputChannel,
  action: 'publish' | 'unpublish',
  deploymentId: string,
  body: Record<string, unknown>
): Promise<MarketplaceResponse> {
  const slug = auth.getCloudOrgSlug()
  const token = await auth.getSessionToken()
  if (!slug || !token) {
    return {
      ok: false,
      status: 401,
      json: { error: 'Sign in with Legalese Cloud first.' },
    }
  }
  const siteUrl = `${PROVABLE_SITE}/api/skills/${encodeURIComponent(slug)}/${encodeURIComponent(deploymentId)}/${action}`
  outputChannel.appendLine(`[publish] POST ${siteUrl}`)
  try {
    const result = await post(siteUrl, token, body)
    if (result.status < 500) return result
    outputChannel.appendLine(
      `[publish] site returned ${result.status}, falling back to platform`
    )
  } catch (err) {
    outputChannel.appendLine(
      `[publish] site unreachable (${err instanceof Error ? err.message : String(err)}), falling back to platform`
    )
  }
  const platformUrl = `https://${LEGALESE_CLOUD_DOMAIN}/marketplace/${action}?org=${encodeURIComponent(slug)}`
  outputChannel.appendLine(`[publish] POST ${platformUrl}`)
  return post(platformUrl, token, body)
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
    params.deploymentId,
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
    url: slug
      ? `${PROVABLE_SITE}/skills/${encodeURIComponent(slug)}/${encodeURIComponent(params.deploymentId)}`
      : undefined,
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
    deploymentId,
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
