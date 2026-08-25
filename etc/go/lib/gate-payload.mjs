#!/usr/bin/env node
// Build the canonical payload for a gate, from the journal.
//
// Nothing here is typed by hand. The payload is a deterministic rendering of
// (a) what run this is, (b) what tree it ran against, (c) the sha256 of every
// corpus file, and (d) the receipt hash of every stage that EXECUTED before the
// gate. Signing it approves that exact content and nothing else.
//
// (d) says "executed" rather than "ran" on purpose: replayed receipts are
// excluded, so resuming a run leaves the payload — and therefore a signature
// over it — untouched. See the filter below.
//
// Usage: node etc/go/lib/gate-payload.mjs HG1|HG2 RUNDIR

import { resolve } from "node:path";
import { read } from "./ledger.mjs";

const [, , gate, rundir] = process.argv;
if (!gate || !rundir) {
  process.stderr.write("usage: gate-payload.mjs HG1|HG2 RUNDIR\n");
  process.exit(2);
}

const records = read(resolve(rundir, "journal.ndjson"));
const begin = records.find((r) => r.kind === "run_begin");
if (!begin) {
  process.stderr.write("gate-payload.mjs: journal has no run_begin record\n");
  process.exit(2);
}

// Replayed receipts are EXCLUDED. A replay carries no new evidence — it copies
// the verdict and the artifact records of the receipt it names, whose own row is
// already in this list — but it is a fresh record with a fresh hash. Including
// replays made the payload a function of how many times the run had been
// resumed, so a signature stopped verifying on the very first resume the tools
// themselves print, over a corpus nobody had touched. The payload must be a
// function of CONTENT, and a replay changes none.
const stageEnds = records.filter(
  (r) => r.kind === "stage_end" && !r.replayed_from,
);
const corpus = [];
for (const r of stageEnds) {
  if (r.stage !== "p0-preflight") continue;
  for (const [k, v] of Object.entries(r.metrics || {})) {
    if (k.startsWith("corpus_sha_"))
      corpus.push([k.replace(/^corpus_sha_/, ""), v]);
  }
}

const lines = [];
lines.push(`l4-go gate payload`);
lines.push(`gate: ${gate}`);
lines.push(`run_id: ${begin.run_id}`);
lines.push(`milestone: ${begin.milestone}`);
lines.push(`subject: ${begin.subject}`);
lines.push(`repo_head: ${begin.repo_head}`);
lines.push(`tree_state: ${begin.tree_state}`);
lines.push(`fixed_now: ${begin.fixed_now}`);
lines.push("");
lines.push("corpus (sha256 of every file this gate blesses):");
for (const [name, sha] of corpus.sort()) lines.push(`  ${name} ${sha}`);
if (corpus.length === 0)
  lines.push("  (none recorded — p0-preflight has not run)");
lines.push("");
lines.push("receipts that EXECUTED before this gate (replays excluded):");
for (const r of stageEnds) lines.push(`  ${r.stage} ${r.status} ${r.hash}`);
lines.push("");
lines.push(
  "Signing this payload approves exactly this content. Any later change",
);
lines.push(
  "to a corpus file or an earlier receipt changes this payload's digest,",
);
lines.push("the signature stops verifying, and the gate closes again.");
lines.push("Resuming a run does NOT change it: a replayed receipt re-states a");
lines.push("verdict this payload already covers, so it is not listed above.");
process.stdout.write(lines.join("\n") + "\n");
