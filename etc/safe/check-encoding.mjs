#!/usr/bin/env node
// check-encoding.mjs — keep encoding.json's decoding key honest.
//
//   node etc/safe/check-encoding.mjs --subject DIR [--encoding ROW]
//
// `l4 batch` emits a record as {"Conversion": [v1, v2, …]} — the constructor name and
// the field values POSITIONALLY, in DECLARE order, with no field names on the wire. So
// encoding.json's `batch.record_fields` IS the decoding key, and if a DECLARE gains,
// loses or reorders a field while that map stands still, every generated conversion
// schedule silently reports the wrong numbers under the right headings. Nothing else in
// the pipeline would notice: the JSON still parses, the arithmetic still runs.
//
// So this compares the two directly. It also computes which records the entrypoints can
// actually return, transitively, and requires the map to name exactly those — an extra
// key is dead weight, a missing one is a decode that throws at generation time.
//
// Exits 0 when they agree, 1 on drift (naming every difference), 2 on usage.

import { readFileSync } from "node:fs";
import { loadSubject } from "./lib/subject.mjs";

const BUILTIN = new Set([
  "STRING",
  "NUMBER",
  "BOOLEAN",
  "DATE",
  "TIME",
  "LIST",
  "MAYBE",
  "OF",
  "A",
  "AN",
  "IS",
]);

/**
 * Field names, in order, for every `DECLARE <Name> HAS` block in an .l4 file.
 * A block runs from the DECLARE line to the first line that is neither indented nor
 * blank; `--` comment lines inside it are skipped. `DECLARE … IS ONE OF` (sum types)
 * has no positional record encoding and is not collected.
 */
export function declaredRecords(text) {
  const out = new Map();
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^DECLARE\s+(`[^`]+`|\S+)\s+HAS\s*$/);
    if (!m) continue;
    const name = m[1].replace(/`/g, "");
    const fields = [];
    for (let j = i + 1; j < lines.length; j++) {
      const line = lines[j];
      if (/^\s*$/.test(line)) continue;
      if (!/^\s/.test(line)) break;
      if (/^\s*--/.test(line)) continue;
      const f = line.match(/^\s+(`[^`]+`|[^\s`]+)\s+IS\s+AN?\s+(.*)$/);
      if (!f) break;
      fields.push({
        name: f[1].replace(/`/g, ""),
        type: f[2].replace(/\s*--.*$/, "").trim(),
      });
    }
    out.set(name, fields);
  }
  return out;
}

/** The record type names a `GIVETH`/`returns` phrase mentions. */
function typeNames(phrase) {
  return (phrase.match(/`[^`]+`|[A-Za-z][A-Za-z0-9]*/g) ?? [])
    .map((t) => t.replace(/`/g, ""))
    .filter((t) => !BUILTIN.has(t));
}

/** Every record reachable from `seeds` through record-typed fields. */
export function reachable(seeds, records) {
  const out = new Set();
  const queue = [...seeds];
  while (queue.length) {
    const t = queue.pop();
    if (!records.has(t) || out.has(t)) continue;
    out.add(t);
    for (const f of records.get(t)) queue.push(...typeNames(f.type));
  }
  return out;
}

function main(argv) {
  let dir = null;
  let encoding = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--subject") dir = argv[++i];
    else if (argv[i] === "--encoding") encoding = argv[++i];
    else {
      process.stderr.write(
        "usage: check-encoding.mjs --subject DIR [--encoding ROW]\n",
      );
      return 2;
    }
  }
  const subject = loadSubject(dir, { encoding });

  const records = new Map();
  for (const m of subject.encoding.modules ?? [])
    for (const [name, fields] of declaredRecords(
      readFileSync(subject.modulePath(m), "utf8"),
    ))
      records.set(name, fields);

  const seeds = Object.values(subject.encoding.entrypoints ?? {}).flatMap((e) =>
    typeNames(e.returns ?? ""),
  );
  const expected = reachable(seeds, records);
  const declared = subject.recordFields;

  let failures = 0;
  for (const [name, fields] of Object.entries(declared)) {
    const actual = records.get(name);
    if (!actual) {
      process.stderr.write(
        `DRIFT  encoding.json names record \`${name}\`, which no module DECLAREs\n`,
      );
      failures++;
      continue;
    }
    const got = actual.map((f) => f.name);
    if (got.length !== fields.length || got.some((f, i) => f !== fields[i])) {
      process.stderr.write(
        `DRIFT  \`${name}\` field order disagrees\n` +
          `         DECLARE:      ${got.join(", ")}\n` +
          `         encoding.json: ${fields.join(", ")}\n`,
      );
      failures++;
    } else {
      process.stdout.write(
        `ok     ${name.padEnd(16)} ${got.length} fields: ${got.join(", ")}\n`,
      );
    }
  }
  for (const name of expected)
    if (!(name in declared)) {
      process.stderr.write(
        `DRIFT  \`${name}\` is reachable from an entrypoint's return type but is not in ` +
          `batch.record_fields — decoding it would throw\n`,
      );
      failures++;
    }
  for (const name of Object.keys(declared))
    if (!expected.has(name) && records.has(name))
      process.stdout.write(
        `note   \`${name}\` is in batch.record_fields but no entrypoint can return it\n`,
      );

  process.stdout.write(
    failures === 0
      ? `\nencoding.json's batch.record_fields matches the DECLAREs in ${subject.rowName}\n`
      : `\n${failures} drift(s)\n`,
  );
  return failures === 0 ? 0 : 1;
}

if (import.meta.url === `file://${process.argv[1]}`)
  process.exit(main(process.argv.slice(2)));
