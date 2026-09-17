#!/usr/bin/env node
/**
 * Seed jl4-service with the Penal Code corpus.
 *
 * The corpus lives in the canon repo, not in l4-ide (decision 2 in the plan):
 * `$CANON_DIR/subjects/sg/penal-code-1871/encodings/legalese/*.l4`. Until the
 * vendoring PR lands there is no copy in this tree, so this script zips the
 * modules straight from the canon clone and POSTs them as one deployment.
 *
 *   CANON_DIR=~/src/legalese/canon JL4_BASE_URL=http://127.0.0.1:18099 node scripts/seed.mjs
 *
 * Deploy = multipart POST /deployments with `id` and a zip under `sources`; the
 * job is polled at …/updates/{job} until `applied` (recipe measured on the
 * housing wizard). `culpable-homicide-301.l4` is included: it carries no
 * exports, so it costs nothing and keeps the deployment equal to the row.
 */
import { readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { homedir } from 'node:os'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'

// Not a turbo task: this script is run by hand, so its env vars are not turbo inputs.
/* eslint-disable turbo/no-undeclared-env-vars */

const CANON_DIR = process.env.CANON_DIR ?? join(homedir(), 'src/legalese/canon')
const BASE = process.env.JL4_BASE_URL ?? 'http://127.0.0.1:18099'
const ID = process.env.JL4_DEPLOYMENT ?? 'sg-penal-code'
const ROW = join(CANON_DIR, 'subjects/sg/penal-code-1871/encodings/legalese')

const files = (await readdir(ROW)).filter((f) => f.endsWith('.l4')).sort()
if (files.length === 0) {
  console.error(`no .l4 files under ${ROW}`)
  process.exit(1)
}

// zip via the system `zip` (macOS and Linux both ship it); flat archive.
const tmp = mkdtempSync(join(tmpdir(), 'sg-penal-code-'))
for (const f of files) writeFileSync(join(tmp, f), await readFile(join(ROW, f)))
const zipPath = join(tmp, 'bundle.zip')
execFileSync('zip', ['-q', '-j', zipPath, ...files.map((f) => join(tmp, f))])

const form = new FormData()
form.append('id', ID)
form.append(
  'sources',
  new Blob([await readFile(zipPath)], { type: 'application/zip' }),
  'bundle.zip'
)

// POST creates; PUT /deployments/{id} replaces an existing deployment in place
// (ControlPlane.hs: `Verb 'PUT 202`). Probe first so re-seeding after an edit
// to the corpus is one command.
const exists = await fetch(`${BASE}/deployments/${ID}`).then((r) => r.ok).catch(() => false)
const res = exists
  ? await fetch(`${BASE}/deployments/${ID}`, { method: 'PUT', body: form })
  : await fetch(`${BASE}/deployments`, { method: 'POST', body: form })
const body = await res.text()
if (!res.ok) {
  console.error(`deploy failed: HTTP ${res.status}\n${body}`)
  process.exit(1)
}
console.log(`${exists ? 'updated' : 'deployed'} ${files.length} files as ${ID}: ${body}`)

// Poll the update job if the response names one.
let job
try {
  job = JSON.parse(body)?.jobId ?? JSON.parse(body)?.updateId
} catch {
  job = undefined
}
if (job) {
  for (let i = 0; i < 60; i++) {
    const r = await fetch(`${BASE}/deployments/${ID}/updates/${job}`)
    const j = await r.json().catch(() => ({}))
    const status = j.status ?? j.state
    if (status === 'applied' || status === 'ready') {
      console.log(`update ${job}: ${status}`)
      break
    }
    if (status === 'failed' || status === 'error') {
      console.error(`update ${job} failed: ${JSON.stringify(j)}`)
      process.exit(1)
    }
    await new Promise((r) => setTimeout(r, 500))
  }
}
rmSync(tmp, { recursive: true, force: true })

const fns = await fetch(`${BASE}/deployments/${ID}`)
  .then((r) => r.json())
  .catch(() => null)
if (fns) console.log(JSON.stringify(fns, null, 1).slice(0, 2000))
