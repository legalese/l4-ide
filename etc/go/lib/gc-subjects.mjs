#!/usr/bin/env node
// Group the run store by subject, for `go.sh gc`.
//
// Two modes, both reading `run_begin.subject` through ledger.runSubject:
//
//   gc-subjects.mjs <runRoot>            -> one subject key per line
//   gc-subjects.mjs <runRoot> <subject>  -> the run dirs under that key
//
// A run whose journal names no subject — the runs of 2026-08-09, whose
// run_begin predates the field — is keyed "(unattributed)". It is a real key,
// not a discard: those runs cannot be shown redundant with any subject's
// latest, so they get their own --keep window rather than competing for one
// subject's. The key is parenthesised because `subject.mjs` refuses that shape
// as a sidecar id, so it can never collide with a real subject.
//
// Shell contract: one value per line, nothing else on stdout. gc splits on
// whitespace, so a key or path containing a space would break it — subject ids
// cannot contain one (subject.mjs validates the id), and run dir names are
// generated, never user-supplied.
import fs from "node:fs";
import path from "node:path";
import { runSubject } from "./ledger.mjs";

const UNATTRIBUTED = "(unattributed)";

const [runRoot, wanted] = process.argv.slice(2);
if (!runRoot) {
  console.error("gc-subjects.mjs: usage: gc-subjects.mjs <runRoot> [subject]");
  process.exit(2);
}

let entries = [];
try {
  entries = fs
    .readdirSync(runRoot, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => path.join(runRoot, e.name));
} catch {
  // No store yet is not an error: gc over an empty store removes nothing.
  process.exit(0);
}

const bySubject = new Map();
for (const dir of entries) {
  const key = runSubject(path.join(dir, "journal.ndjson")) ?? UNATTRIBUTED;
  if (!bySubject.has(key)) bySubject.set(key, []);
  bySubject.get(key).push(dir);
}

if (wanted === undefined) {
  for (const key of [...bySubject.keys()].sort()) console.log(key);
} else {
  for (const dir of (bySubject.get(wanted) ?? []).sort()) console.log(dir);
}
