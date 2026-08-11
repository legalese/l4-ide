#!/usr/bin/env node
// Report — and, only when asked in so many words, re-bless — the narrative
// provenance record for a subject's explainer.
//
// WHY THIS EXISTS. provenance.json records, per narrative file, its own sha256
// and the sha256 of every source it was drafted from. Those digests are the
// drift detector: p9-explain re-hashes them at render time and prints a banner
// over any section whose text or source has moved. Maintaining them by hand is
// not realistic, so this is the tool — and the whole design question is what a
// tool like this must REFUSE to do.
//
// It refuses to re-bless silently. `--check` is the default and only reports.
// `--bless` rewrites the digests AND resets every affected record's review to
// `unreviewed`, because a review signed over one text and one set of sources
// says nothing about a different text or different sources. A tool that
// refreshed the digests while leaving `"state": "reviewed"` in place would
// convert every drift into a laundered approval, which is precisely the thing
// the provenance record exists to make impossible.
//
// It also cannot invent a `drafted_from`: a new narrative file must be added to
// provenance.json by whoever drafted it, naming what they drafted it from,
// because that is a fact about how the prose was written and no tool can
// observe it after the fact.
//
// Usage:
//   node etc/go/lib/narrative-provenance.mjs <subject> [--check | --bless]
// Exit: 0 in step · 1 drift found (with --check) · 2 usage · 4 malformed deposit

import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { sha256File } from "./ledger.mjs";
import { loadSubject } from "./subject.mjs";
import { driftFor, loadProvenance } from "./narrative.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");

const argv = process.argv.slice(2);
const subject = argv.find((a) => !a.startsWith("--"));
const bless = argv.includes("--bless");
if (!subject) {
  process.stderr.write(
    "usage: narrative-provenance.mjs <subject> [--check | --bless]\n",
  );
  process.exit(2);
}

const { env } = loadSubject(subject);
const dir = env.GO_S_EXPLAINER_DIR;
if (!dir) {
  process.stderr.write(
    `narrative-provenance.mjs: subject '${subject}' declares no explainer directory in subject.json\n`,
  );
  process.exit(2);
}

const { records, problems } = loadProvenance(dir);
if (problems.length) {
  for (const p of problems) process.stderr.write(`  - ${p}\n`);
  process.exit(4);
}

// A narrative file with no record at all: reported, never invented. Only the
// person who wrote the prose knows what they wrote it from.
const recorded = new Set(records.map((r) => r.file));
const onDisk = readdirSync(dir).filter((f) => f.endsWith(".md"));
const unrecorded = onDisk.filter((f) => !recorded.has(f));

let drifted = 0;
const lines = [];
for (const rec of records) {
  const d = driftFor(rec, { repoRoot: REPO, dir });
  const moved = [];
  if (d.narrative) moved.push(`text ${d.narrative.kind}`);
  for (const s of d.sources) moved.push(`source ${s.path} ${s.kind}`);
  if (!moved.length) continue;
  drifted++;
  lines.push(`  ${rec.file}: ${moved.join("; ")}`);
  if (!bless) continue;

  const abs = resolve(dir, rec.file);
  if (existsSync(abs)) rec.sha256 = sha256File(abs);
  for (const s of rec.drafted_from ?? []) {
    const p = resolve(REPO, s.path);
    if (existsSync(p)) s.sha256 = sha256File(p);
  }
  // Re-blessing invalidates review, always and without an override. See header.
  if ((rec.review?.state ?? "unreviewed") !== "unreviewed") {
    rec.review = {
      state: "unreviewed",
      reviewer: null,
      reviewed_on: null,
      reviewed_sha256: null,
      reviewed_sources: [],
      signature: null,
    };
    lines.push(
      `    review cleared: it was signed over text or sources that have moved`,
    );
  }
}

for (const f of unrecorded)
  lines.push(
    `  ${f}: NO RECORD — add one naming what it was drafted from; this tool will not invent a source`,
  );

if (lines.length) process.stdout.write(lines.join("\n") + "\n");

if (bless) {
  writeFileSync(
    resolve(dir, "provenance.json"),
    JSON.stringify({ narrative_schema: 1, records }, null, 2) + "\n",
  );
  process.stdout.write(
    `narrative-provenance: re-blessed ${drifted} record(s) for '${subject}'. ` +
      `Run prettier over provenance.json, and re-read anything whose review was cleared.\n`,
  );
  process.exit(0);
}

process.stdout.write(
  `narrative-provenance: ${records.length} record(s) for '${subject}'; ` +
    `${drifted} drifted, ${unrecorded.length} narrative file(s) with no record.\n`,
);
process.exit(drifted + unrecorded.length === 0 ? 0 : 1);
