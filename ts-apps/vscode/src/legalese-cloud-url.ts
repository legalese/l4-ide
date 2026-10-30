/**
 * Legalese Cloud's domain, and which URLs belong to it. No `vscode`
 * import, so unit tests can load it.
 */
export const LEGALESE_CLOUD_DOMAIN = 'legalese.cloud'

/**
 * Whether `url` is Legalese Cloud: https to legalese.cloud or one of its
 * subdomains, on the default port and without userinfo. Legalese Cloud
 * credentials (the sign-in session, tokens made from it, Legalese AI
 * keys) are only ever sent to such URLs, whatever a setting says.
 */
export function isLegaleseCloudUrl(url: string): boolean {
  let u: URL
  try {
    u = new URL(url)
  } catch {
    return false
  }
  return (
    u.protocol === 'https:' &&
    u.port === '' &&
    !u.username &&
    !u.password &&
    (u.hostname === LEGALESE_CLOUD_DOMAIN ||
      u.hostname.endsWith(`.${LEGALESE_CLOUD_DOMAIN}`))
  )
}
