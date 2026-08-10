#!/usr/bin/env node
// For every Haskell module a theme ships, find the imports that resolve to a
// module which (a) does not exist on main and (b) is shipped by a *different*
// theme. Those are hard compile-order dependencies between PRs.
import { execFileSync } from 'node:child_process'
import { readFileSync, readdirSync } from 'node:fs'

const git = (...a) => execFileSync('git', a, { encoding: 'utf8', maxBuffer: 1 << 28 })
const DIR = process.argv[2] || '.pr-split/themes'

const themes = readdirSync(DIR)
  .filter((f) => f.endsWith('.files'))
  .map((f) => f.replace(/\.files$/, ''))

// module name -> {theme, path} for every .hs file any theme ships
const owner = new Map()
const themeFiles = new Map()
for (const t of themes) {
  const fs_ = readFileSync(`${DIR}/${t}.files`, 'utf8').trim().split('\n').filter(Boolean)
  themeFiles.set(t, fs_)
  for (const f of fs_) {
    if (!f.endsWith('.hs')) continue
    const m = f.match(/\/(?:src|app|test|tests)\/(.+)\.hs$/)
    if (!m) continue
    owner.set(m[1].replace(/\//g, '.'), { theme: t, path: f })
  }
}

// modules that already exist on main are not a dependency at all
const onMain = new Set(
  git('ls-tree', '-r', '--name-only', 'origin/main')
    .trim()
    .split('\n')
    .filter((f) => f.endsWith('.hs'))
    .map((f) => f.match(/\/(?:src|app|test|tests)\/(.+)\.hs$/))
    .filter(Boolean)
    .map((m) => m[1].replace(/\//g, '.')),
)

const edges = new Map() // "from->to" -> [details]
for (const [t, fs_] of themeFiles) {
  for (const f of fs_) {
    if (!f.endsWith('.hs')) continue
    let src
    try {
      src = git('show', `origin/unstable:${f}`)
    } catch {
      continue
    }
    for (const line of src.split('\n')) {
      const m = line.match(/^import\s+(?:qualified\s+)?([A-Z][\w.']*)/)
      if (!m) continue
      const mod = m[1]
      const o = owner.get(mod)
      if (!o || o.theme === t) continue
      if (onMain.has(mod)) continue // main already has it; no new dependency
      const key = `${t} -> ${o.theme}`
      if (!edges.has(key)) edges.set(key, new Set())
      edges.get(key).add(`${f} imports ${mod}`)
    }
  }
}

const out = [...edges].sort()
console.log(`cross-theme Haskell import edges: ${out.length}\n`)
for (const [k, v] of out) {
  console.log(`## ${k}   (${v.size})`)
  for (const d of [...v].slice(0, 6)) console.log(`   ${d}`)
  if (v.size > 6) console.log(`   ... ${v.size - 6} more`)
}
