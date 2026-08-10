#!/usr/bin/env node
// Reconstruct one theme's version of each shared spine file.
//
//   apply-spine.mjs <theme> <worktree> <hunks.json>
//
// The attribution pass numbered hunks 1..N per file in default `git diff` order, and
// where a single hunk served several themes it marked the row {split:true, lines:[...]}
// naming the exact added lines that theme owns. So we work at line granularity:
// take main's file, then apply only the insertions/deletions this theme owns.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'

const [theme, wt, hunksPath] = process.argv.slice(2)
const spec = JSON.parse(readFileSync(hunksPath, 'utf8'))
const git = (args) => execFileSync('git', args, { encoding: 'utf8', maxBuffer: 1 << 28, cwd: wt })

const norm = (s) => s.replace(/\s+/g, ' ').trim()

// jl4/tests/Main.hs is the golden-suite driver and two of its hunks interleave
// several themes' blocks. Attribute it by block: a line that starts a block sets
// the owner, and the comment/continuation lines around it inherit that owner.
// Comments precede their block, so an unmatched line takes the *next* owner.
const MAIN_HS = 'jl4/tests/Main.hs'
const MAIN_HS_RULES = [
  [/^\s*import System\.Environment/, 'lang-imports-stdlib'],
  [/^\s*import Text\.Read/, 'lang-printer'],
  [/^\s*import qualified BpmnExport/, 'bpmn-export'],
  [/^\s*import qualified (VizAutoRefresh|VizImplies|VizGuardedRows)/, 'ladder-viz'],
  [/^\s*import qualified DmnExport/, 'dmn-export'],
  [/Make the golden suite self-sufficient/, 'lang-imports-stdlib'],
  [/^\s*mLibEnv <- lookupEnv/, 'lang-imports-stdlib'],
  [/^\s*case mLibEnv of/, 'lang-imports-stdlib'],
  [/^\s*Just _\s+-> pure \(\)/, 'lang-imports-stdlib'],
  [/setEnv "JL4_LIBRARY_PATH"/, 'lang-imports-stdlib'],
  [/Top-level not-ok\/ fixtures/, 'lang-syntax-typecheck'],
  [/^\s*exportPlacementFiles <- /, 'lang-syntax-typecheck'],
  [/describe "corpus sanity/, 'lang-syntax-typecheck'],
  [/^\s*corpusNonEmpty /, 'lang-syntax-typecheck'],
  [/let corpusNonEmpty /, 'lang-syntax-typecheck'],
  [/Invariant: exactprint is the identity/, 'lang-printer'],
  [/describe "exactprint identity/, 'lang-printer'],
  [/Invariant: the \*other\* printer/, 'lang-printer'],
  [/describe "prettyLayout round-trip/, 'lang-printer'],
  [/jl4(ExactPrintIdentity|PrettyLayoutRoundTrip)/, 'lang-printer'],
  [/describe "export placement/, 'lang-syntax-typecheck'],
  [/describe "viz/, 'ladder-viz'],
  [/DmnExport\.spec/, 'dmn-export'],
  [/describe "bpmn export"/, 'bpmn-export'],
]

// Assign every added line of Main.hs to a theme, in file order.
function mainHsOwners(addedInOrder, wholeHunkOwner) {
  const owners = new Array(addedInOrder.length).fill(null)
  addedInOrder.forEach(({ line, hunk }, i) => {
    for (const [rx, t] of MAIN_HS_RULES) if (rx.test(line)) { owners[i] = t; break }
    if (!owners[i] && wholeHunkOwner.has(hunk)) owners[i] = wholeHunkOwner.get(hunk)
  })
  // unmatched lines inherit forward (comments sit above the code they describe)
  for (let i = owners.length - 1; i >= 0; i--) if (!owners[i]) owners[i] = owners[i + 1] ?? null
  for (let i = 0; i < owners.length; i++) if (!owners[i]) owners[i] = owners[i - 1] ?? null
  return owners
}

let touched = 0
const warnings = []

for (const [file, rows] of Object.entries(spec)) {
  if (!rows.some((r) => r.theme === theme)) continue

  // default-context hunks, to reproduce the attribution pass's numbering
  const wide = git(['diff', 'origin/main...origin/unstable', '--', file]).split('\n')
  const hunkRanges = []
  for (const l of wide) {
    const m = l.match(/^@@ -(\d+)(?:,(\d+))? \+/)
    if (m) hunkRanges.push({ start: +m[1], count: m[2] === undefined ? 1 : +m[2] })
  }
  const hunkOf = (oldLine) => {
    for (let i = 0; i < hunkRanges.length; i++) {
      const h = hunkRanges[i]
      if (oldLine >= h.start && oldLine < h.start + Math.max(h.count, 1)) return i + 1
    }
    // a pure insertion can sit just past a hunk's last context line
    for (let i = 0; i < hunkRanges.length; i++) {
      const h = hunkRanges[i]
      if (oldLine >= h.start - 1 && oldLine <= h.start + Math.max(h.count, 1)) return i + 1
    }
    return null
  }

  // zero-context edits, so every insertion/deletion is separable
  const tight = git(['diff', '-U0', 'origin/main...origin/unstable', '--', file]).split('\n')
  const edits = []
  let cur = null
  for (const l of tight) {
    const m = l.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/)
    if (m) {
      if (cur) edits.push(cur)
      cur = { oldStart: +m[1], oldCount: m[2] === undefined ? 1 : +m[2], del: [], add: [] }
    } else if (cur) {
      if (l.startsWith('+')) cur.add.push(l.slice(1))
      else if (l.startsWith('-')) cur.del.push(l.slice(1))
    }
  }
  if (cur) edits.push(cur)

  // Main.hs: precompute a theme for every added line, in file order.
  let mainOwners = null
  if (file === MAIN_HS) {
    const wholeHunkOwner = new Map()
    for (const r of rows) if (!r.split) wholeHunkOwner.set(r.hunk, r.theme)
    const flat = []
    for (const e of edits) for (const a of e.add) flat.push({ line: a, hunk: hunkOf(e.oldStart) })
    const owners = mainHsOwners(flat, wholeHunkOwner)
    mainOwners = new Map()
    let k = 0
    for (const e of edits) {
      mainOwners.set(e, e.add.map(() => owners[k++]))
    }
  }

  const base = git(['show', `origin/main:${file}`]).split('\n')
  const out = base.slice()

  // apply back-to-front so earlier offsets stay valid
  for (const e of [...edits].reverse()) {
    const h = hunkOf(e.oldStart)
    const mine = rows.filter((r) => r.hunk === h && r.theme === theme)
    const anyHere = rows.filter((r) => r.hunk === h)
    if (!anyHere.length) {
      warnings.push(`${file}: no attribution for hunk ${h} (old line ${e.oldStart})`)
      continue
    }
    const ownedHere = mainOwners ? (mainOwners.get(e) || []).some((t) => t === theme) : false
    if (!mine.length && !ownedHere) continue // belongs to a sibling theme

    const splitRows = anyHere.filter((r) => r.split)
    let addLines
    if (mainOwners) {
      const own = mainOwners.get(e) || []
      addLines = e.add.filter((_, i) => own[i] === theme)
    } else if (splitRows.length) {
      const owned = new Set((mine.flatMap((r) => r.lines || [])).map((s) => norm(s.replace(/^\+/, ''))))
      addLines = e.add.filter((a) => owned.has(norm(a)))
    } else {
      addLines = e.add
    }
    // deletions only travel with a theme that owns the whole hunk
    const delCount = splitRows.length ? 0 : e.oldCount
    const at = e.oldStart === 0 ? 0 : e.oldStart - 1
    const start = e.oldCount === 0 ? at + 1 : at
    if (addLines.length || delCount) {
      out.splice(start, delCount, ...addLines)
      touched++
    }
  }

  writeFileSync(`${wt}/${file}`, out.join('\n'))
  git(['add', '--', file])
  console.log(`  ${file}: ${theme} slice written`)
}

for (const w of warnings) console.error(`  WARN ${w}`)
console.log(`spine[${theme}]: ${touched} edits applied`)
