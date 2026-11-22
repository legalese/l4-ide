/**
 * Keeps assistant markdown inert. The model's text can carry whatever a
 * prompt injection put there (a seeded file, an MCP tool result), and
 * it is rendered with `{@html}`, so:
 *
 * - raw HTML is shown as text, except a few bare formatting tags;
 * - links keep only web, mail, in-page and relative targets;
 * - images become links, since loading one would be a beacon.
 */

/** Escape text for element content or a double-quoted attribute. */
export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

// Bare formatting tags (no attributes) the model uses in tables and
// prose, which can't run or load anything.
const ALLOWED_TAG =
  /^<\/?(?:br|b|i|em|strong|u|s|del|ins|sub|sup|kbd|mark|small)\s*\/?>$/i

/** A raw HTML token from marked: an allowed bare tag, or its text. */
export function safeHtml(raw: string): string {
  const tag = raw.trim()
  return ALLOWED_TAG.test(tag) ? tag : escapeHtml(raw)
}

const SAFE_SCHEMES = new Set(['http', 'https', 'mailto'])

/**
 * The `href` to render for a markdown link target, or null to render
 * the link's text alone. Browsers drop tabs and newlines anywhere in a
 * URL, and control characters and spaces at its ends, so this does too
 * before reading the scheme; the result is percent-encoded and still
 * needs attribute escaping.
 */
export function safeHref(href: string): string | null {
  const h = href
    .replace(/[\t\n\r]/g, '')
    // eslint-disable-next-line no-control-regex
    .replace(/^[\u0000- ]+|[\u0000- ]+$/g, '')
  if (!h) return null
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(h)
  if (scheme && !SAFE_SCHEMES.has(scheme[1].toLowerCase())) return null
  try {
    return encodeURI(h).replace(/%25/g, '%')
  } catch {
    // A lone surrogate.
    return null
  }
}

/** `<a>` for a link (or an image) whose inner HTML is `inner`. */
export function safeLink(
  href: string,
  title: string | null | undefined,
  inner: string
): string {
  const target = safeHref(href)
  if (target === null) return inner
  const titleAttr = title ? ` title="${escapeHtml(title)}"` : ''
  return `<a href="${escapeHtml(target)}"${titleAttr}>${inner}</a>`
}
