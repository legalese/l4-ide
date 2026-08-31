#!/usr/bin/env node
/**
 * Guards FOUNDATION.md R4: the two guided fact vocabularies must be MECHANICAL
 * transliterations of one source schema. If they drift, the guided cells measure
 * whichever schema disambiguated better rather than the languages, and the
 * comparison is void. Run this whenever any of the three files changes.
 *
 * Transliteration rules, enforced here:
 *   neutral `foo_bar`  ->  Prolog `claim_foo_bar(C, Value)`
 *   neutral `foo_bar`  ->  L4 record field `foo bar`
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), "utf8");

// Source: numbered rows of the field table only.
const source = [...read("schema.md").matchAll(/^\|\s*(\d+)\s*\|\s*`([a-z0-9_]+)`\s*\|/gm)].map((m) => m[2]);

const prolog = [...read("schema-prolog.md").matchAll(/^claim_([a-z0-9_]+)\(C,\s*Value\)\./gm)].map((m) => m[1]);

// L4 fields live between HAS and the closing fence; spaces stand in for underscores.
const l4Block = /DECLARE Claim\n([\s\S]*?)\n```/.exec(read("schema-l4.md"))?.[1] ?? "";
const l4 = [...l4Block.matchAll(/^\s*(?:HAS\s+)?([a-z][a-z ]*?)\s+IS A /gm)].map((m) => m[1].trim().replace(/ /g, "_"));

const problems = [];
const cmp = (name, got) => {
  const missing = source.filter((f) => !got.includes(f));
  const extra = got.filter((f) => !source.includes(f));
  if (missing.length) problems.push(`${name}: MISSING ${missing.join(", ")}`);
  if (extra.length) problems.push(`${name}: EXTRA ${extra.join(", ")}`);
  if (!missing.length && !extra.length && got.join("|") !== source.join("|"))
    problems.push(`${name}: same fields, DIFFERENT ORDER (source: ${source.join(", ")})`);
};
cmp("prolog", prolog);
cmp("l4", l4);

console.log(`source ${source.length} · prolog ${prolog.length} · l4 ${l4.length}`);
if (problems.length) { problems.forEach((p) => console.error("  " + p)); process.exit(1); }
console.log("R4 parity OK — all three agree on field set and order.");
