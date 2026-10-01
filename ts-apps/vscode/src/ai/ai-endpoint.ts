import * as vscode from 'vscode'
import {
  LOCAL_AI_ENDPOINT,
  PROD_AI_ENDPOINT,
  type AiEndpoint,
} from '@repo/legalese-agent'

/**
 * True when the user has flipped `legaleseAi.localMode` on. Read fresh
 * each request so toggling the setting takes effect without a reload.
 */
export function isLocalMode(): boolean {
  return (
    vscode.workspace.getConfiguration().get<boolean>('legaleseAi.localMode') ===
    true
  )
}

/**
 * Resolve the active ai-proxy base URL. Re-evaluated per call so the
 * setting toggle applies immediately to subsequent requests.
 */
export function getAiEndpoint(): string {
  return isLocalMode() ? LOCAL_AI_ENDPOINT : PROD_AI_ENDPOINT
}

/** The endpoint resolver handed to the core's `AiProxyClient`. */
export function vscodeAiEndpoint(): AiEndpoint {
  const local = isLocalMode()
  return { url: local ? LOCAL_AI_ENDPOINT : PROD_AI_ENDPOINT, local }
}
