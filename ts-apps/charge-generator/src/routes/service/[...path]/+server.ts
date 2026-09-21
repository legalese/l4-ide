import type { RequestHandler } from './$types'
import { env } from '$env/dynamic/private'

/**
 * A same-origin proxy to jl4-service, so the page can be served through one
 * hostname (a tunnel, a reverse proxy) and still reach the rules service at
 * `/service/…` under CSP `connect-src 'self'`. The upstream is the loopback
 * service by default; JL4_UPSTREAM overrides it for the node server.
 *
 * Forwards method, path, query, body and content-type; passes the response
 * through unchanged. No caching, no auth: this is a demo front door, and the
 * service behind it is the same one the page would otherwise call directly.
 */
const UPSTREAM = (env.JL4_UPSTREAM ?? 'http://127.0.0.1:18099').replace(
  /\/$/,
  ''
)

const forward: RequestHandler = async ({ request, params, url }) => {
  const target = `${UPSTREAM}/${params.path}${url.search}`
  const headers = new Headers()
  const ct = request.headers.get('content-type')
  if (ct) headers.set('content-type', ct)
  const accept = request.headers.get('accept')
  if (accept) headers.set('accept', accept)
  const init: RequestInit & { duplex?: 'half' } = {
    method: request.method,
    headers,
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    init.body = request.body
    init.duplex = 'half'
  }
  let res: Response
  try {
    res = await fetch(target, init)
  } catch (e) {
    return new Response(
      JSON.stringify({
        error: `rules service unreachable at ${UPSTREAM}: ${e instanceof Error ? e.message : String(e)}`,
      }),
      { status: 502, headers: { 'content-type': 'application/json' } }
    )
  }
  const out = new Headers()
  const rct = res.headers.get('content-type')
  if (rct) out.set('content-type', rct)
  out.set('cache-control', 'no-store')
  return new Response(res.body, { status: res.status, headers: out })
}

export const GET = forward
export const POST = forward
export const PUT = forward
export const DELETE = forward
