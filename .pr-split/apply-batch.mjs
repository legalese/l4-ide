#!/usr/bin/env node
// Splice .pr-split/BATCH.md into the body of every PR in the merge batch, replacing any
// earlier batch section. Idempotent: run it again after editing BATCH.md and the bodies
// pick up the new text.
//
//   apply-batch.mjs [bodies-dir] [batch-file]
import { readFileSync, writeFileSync } from 'node:fs'

const bdir = process.argv[2] ?? '.pr-split/bodies'
const bfile = process.argv[3] ?? '.pr-split/BATCH.md'

// The twelve themes measured to be inseparable — see BATCH.md for the evidence.
const MEMBERS = [
  'lang-syntax-typecheck',
  'lang-eval-ledger',
  'lang-imports-stdlib',
  'lang-printer',
  'ladder-viz',
  'service-cli',
  'dmn-export',
  'bpmn-export',
  'openfisca-export',
  'lsp',
  'mlir',
  'actus-archive',
]

const batch = readFileSync(bfile, 'utf8').trim()

// Any heading that opens a batch section, current or superseded.
const BATCH_HEADING = /^## (Must merge as a batch|Part of a \d+-PR merge batch)/

for (const theme of MEMBERS) {
  const path = `${bdir}/${theme}.md`
  const lines = readFileSync(path, 'utf8').split('\n')

  // Drop an existing batch section: from its heading to the next `## ` heading.
  const out = []
  let skipping = false
  for (const line of lines) {
    if (BATCH_HEADING.test(line)) {
      skipping = true
      continue
    }
    if (skipping) {
      if (/^## /.test(line)) skipping = false
      else continue
    }
    out.push(line)
  }

  // Insert before `## Provenance` — the last section in every body — or append.
  const at = out.findIndex((l) => /^## Provenance/.test(l))
  const block = batch.split('\n')
  if (at === -1) {
    while (out.length && out[out.length - 1].trim() === '') out.pop()
    out.push('', ...block, '')
  } else {
    out.splice(at, 0, ...block, '', '')
  }

  // Collapse any run of 3+ blank lines the splice may have produced.
  const text = out.join('\n').replace(/\n{4,}/g, '\n\n\n')
  writeFileSync(path, text)
  console.log(`batch section applied: ${theme}`)
}
