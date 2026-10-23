#!/usr/bin/env node
// make-templates.mjs — derive the fill templates from the publisher's verbatim Markdown.
//
//   node etc/safe/make-templates.mjs --subject DIR [--check]
//
// SPEC.md §5.3: a template is the form with its blanks marked as holes, derived
// MECHANICALLY from source/md/<form>.md by a positional map, and proven to reproduce the
// source byte for byte (etc/safe/check-templates.mjs). That derivation plus that proof is
// what makes a template not a "modified version of the form" under CC BY-ND 4.0 — so this
// script's one rule is: touch nothing that holes.json does not name.
//
// The positional map: within one form, `holes` is in document order, and the nth entry
// whose `literal` is L stands for the nth occurrence of L. That is what lets the two
// `$[___]` blanks on the cap form be Purchase Amount and then Post-Money Valuation Cap,
// and the two `[___]` on the Canadian governing-law line both be the Province.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { holeTokens, loadSubject, templateRelPath } from "./lib/subject.mjs";

/** Every offset at which `needle` occurs in `hay`, left to right, non-overlapping. */
function occurrences(hay, needle) {
  const out = [];
  for (
    let i = hay.indexOf(needle);
    i >= 0;
    i = hay.indexOf(needle, i + needle.length)
  )
    out.push(i);
  return out;
}

/**
 * Resolve a form's hole list to (offset, length, hole) edits, in document order.
 * Throws — loudly, naming the literal — when the map and the text disagree, because a
 * silently-unapplied hole is a template that renders the placeholder into a real
 * instrument.
 */
export function planEdits(text, holes, file) {
  const offsets = new Map(); // literal -> occurrence offsets
  const used = new Map(); // literal -> how many entries consumed so far
  const edits = [];
  for (const h of holes) {
    const lit = h.literal;
    if (!offsets.has(lit)) offsets.set(lit, occurrences(text, lit));
    const n = used.get(lit) ?? 0;
    const at = offsets.get(lit)[n];
    if (at === undefined)
      throw new Error(
        `etc/safe: ${file} — holes.json wants occurrence ${n + 1} of ${JSON.stringify(lit)} ` +
          `(hole \`${h.hole}\`) but the document has only ${offsets.get(lit).length}.`,
      );
    used.set(lit, n + 1);
    edits.push({
      at,
      len: lit.length,
      hole: h.hole,
      token: h.token ?? h.hole,
      literal: lit,
    });
  }
  edits.sort((a, b) => a.at - b.at);
  for (let i = 1; i < edits.length; i++)
    if (edits[i].at < edits[i - 1].at + edits[i - 1].len)
      throw new Error(
        `etc/safe: ${file} — holes ${edits[i - 1].hole} and ${edits[i].hole} overlap at ` +
          `offset ${edits[i].at}. The map is wrong; a template cannot be derived from it.`,
      );
  return edits;
}

/** The template text: the source with each planned edit replaced by `{{token}}`. */
export function makeTemplate(text, form, file) {
  const { entries } = holeTokens(form, file);
  const edits = planEdits(text, entries, file);
  let out = "";
  let cursor = 0;
  for (const e of edits) {
    out += text.slice(cursor, e.at) + `{{${e.token}}}`;
    cursor = e.at + e.len;
  }
  return out + text.slice(cursor);
}

function main(argv) {
  let dir = null;
  let encoding = null;
  let checkOnly = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--subject") dir = argv[++i];
    else if (argv[i] === "--encoding") encoding = argv[++i];
    else if (argv[i] === "--check") checkOnly = true;
    else {
      process.stderr.write(
        `usage: make-templates.mjs --subject DIR [--encoding ROW] [--check]\n`,
      );
      return 2;
    }
  }
  const subject = loadSubject(dir, { encoding });
  for (const w of subject.warnings) process.stdout.write(`note     ${w}\n`);
  let written = 0;
  let unchanged = 0;
  for (const [file, form] of Object.entries(subject.forms)) {
    const src = subject.mdPath(file);
    if (!existsSync(src)) {
      process.stderr.write(
        `etc/safe: holes.json names ${file}, which is not in ${subject.sourceMd}\n`,
      );
      return 1;
    }
    const text = readFileSync(src, "utf8");
    const template = makeTemplate(text, form, file);
    const rel = templateRelPath(form.document, form.jurisdiction, form.variant);
    const out = join(subject.templatesDir, rel);
    const before = existsSync(out) ? readFileSync(out, "utf8") : null;
    if (before === template) {
      unchanged++;
    } else if (checkOnly) {
      process.stderr.write(
        `etc/safe: ${rel} is ${before === null ? "missing" : "stale"} — re-run make-templates.mjs\n`,
      );
      return 1;
    } else {
      mkdirSync(dirname(out), { recursive: true });
      writeFileSync(out, template);
      written++;
    }
    process.stdout.write(
      `${rel.padEnd(30)} ${String(form.holes.length).padStart(2)} holes  <- ${file}\n`,
    );
  }
  process.stdout.write(
    `\n${written} written, ${unchanged} already current, into ${subject.templatesDir}\n`,
  );
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}`)
  process.exit(main(process.argv.slice(2)));
