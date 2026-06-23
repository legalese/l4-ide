/**
 * Scene IR -> SVG string (the shared `ladder-svg` emit, DESIGN §4; for P0 it lives
 * here, to be split out per §12). Canonical text is <text>/<tspan> so the same
 * emit feeds screen AND print (§4.4). `theme` maps state -> ink; no second layout.
 */
import type { Scene, ScenePrim, State, Theme } from './types.js'

interface Palette {
  live: string
  inert: string
  dead: string
  ghost: string
  rail: string
  ink: string
  bg: string
}

const SCREEN: Palette = {
  live: '#1a7f37',
  inert: '#9aa0a6',
  dead: '#9aa0a6',
  ghost: '#b9bdc2',
  rail: '#3a3a3a',
  ink: '#222',
  bg: '#ffffff',
}
const INK: Palette = { ...SCREEN, live: '#222', inert: '#555', dead: '#555', ghost: '#999', rail: '#222', ink: '#111' }

const strokeFor = (s: State, p: Palette) =>
  s === 'live' ? p.live : s === 'eliminable' ? p.ghost : p.inert

const esc = (t: string) =>
  t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

function prim(p: ScenePrim, pal: Palette): string {
  switch (p.kind) {
    case 'box': {
      const { x, y, w, h } = p.rect
      const foldable = p.role === 'placeholder'
      const a = ` data-fnid="${p.id}"${foldable ? ` data-fold="${p.id}"` : ''} class="lad-box${foldable ? ' lad-foldable' : ''}"`
      if (p.state === 'eliminable')
        return `<rect${a} x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="7" fill="#f6f7f8" stroke="${pal.ghost}" stroke-width="1.5" stroke-dasharray="5 4" opacity="0.9"/>`
      const fill = p.role === 'placeholder' ? '#eef1f6' : '#ffffff'
      return `<rect${a} x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="7" fill="${fill}" stroke="${strokeFor(p.state, pal)}" stroke-width="1.5"/>`
    }
    case 'wire': {
      const d = p.path.map((pt) => `${pt.x.toFixed(1)},${pt.y.toFixed(1)}`).join(' ')
      const dash = p.state === 'eliminable' ? ' stroke-dasharray="5 4"' : ''
      const col = p.role === 'rail' ? pal.rail : strokeFor(p.state, pal)
      const op = p.state === 'eliminable' ? ' opacity="0.9"' : ''
      return `<polyline class="lad-wire" points="${d}" fill="none" stroke="${col}" stroke-width="1.5"${dash}${op}/>`
    }
    case 'glyph':
      if (p.role === 'open-contact')
        return (
          `<line x1="${(p.at.x - 7).toFixed(1)}" y1="${(p.at.y - 7).toFixed(1)}" x2="${(p.at.x - 7).toFixed(1)}" y2="${(p.at.y + 7).toFixed(1)}" stroke="${pal.ghost}" stroke-width="1.6"/>` +
          `<line x1="${(p.at.x + 7).toFixed(1)}" y1="${(p.at.y - 7).toFixed(1)}" x2="${(p.at.x + 7).toFixed(1)}" y2="${(p.at.y + 7).toFixed(1)}" stroke="${pal.ghost}" stroke-width="1.6"/>`
        )
      return `<circle cx="${p.at.x.toFixed(1)}" cy="${p.at.y.toFixed(1)}" r="3.5" fill="${pal.rail}"/>`
    case 'text': {
      const size = p.size ?? 14
      const inert = p.tag === 'otiose' || p.tag === 'heading' || p.tag === 'note' || p.tag === 'connective'
      const dy = inert ? 0 : 5 // vertical-center body text
      const italic = inert ? ' font-style="italic"' : ''
      const weight = p.tag === 'title' ? ' font-weight="700"' : ''
      const fill = p.tag === 'otiose' ? pal.ghost : p.state === 'live' ? pal.ink : p.tag ? '#555' : pal.ink
      const foldable = p.tag === 'heading' && p.id != null
      const a = `${p.id != null ? ` data-fnid="${p.id}"` : ''}${foldable ? ` data-fold="${p.id}" class="lad-foldable"` : ''}`
      return `<text${a} x="${p.at.x.toFixed(1)}" y="${(p.at.y + dy).toFixed(1)}" font-family="Georgia, serif" font-size="${size}" text-anchor="${p.anchor}" fill="${fill}"${italic}${weight}>${esc(p.text)}</text>`
    }
  }
}

export function sceneToSvg(scene: Scene, theme: Theme = 'screen'): string {
  const pal = theme === 'ink' ? INK : SCREEN
  const { w, h } = scene.size
  const body = scene.prims.map((p) => prim(p, pal)).join('\n')
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w.toFixed(0)}" height="${h.toFixed(0)}" viewBox="0 0 ${w.toFixed(0)} ${h.toFixed(0)}">`,
    `<rect width="${w.toFixed(0)}" height="${h.toFixed(0)}" fill="${pal.bg}"/>`,
    body,
    `</svg>`,
  ].join('\n')
}
