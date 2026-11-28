#!/usr/bin/env node
// check-templates.mjs — the "unmodified except blanks" proof (SPEC.md §5.3).
//
//   node etc/safe/check-templates.mjs --subject DIR
//
// Two assertions, both of which must hold before any document is generated:
//
//   1. ROUND TRIP. Render each template through the real renderer with every hole set to
//      the ORIGINAL placeholder text, and require the result to equal
//      source/md/<form>.md BYTE FOR BYTE. That is the evidence for the representation
//      the form itself makes — "neither one has modified the form, except to fill in
//      blanks and bracketed terms" — and it is what distinguishes a derived template
//      from a modified form under CC BY-ND 4.0 (SPEC.md §2, ruling R9).
//   2. THE MATRIX. The template set is exactly the six published SAFEs plus the four
//      side letters. A seventh cell would be a form YC does not publish (SPEC.md §3.4).
//
// Exits 0 on proof, 1 on any difference (printing a unified diff), 2 on usage.
//
// CLAUDE.md §1.2 pattern: this reads a canon checkout and never becomes a build
// dependency; a caller that has no subject directory simply does not run it.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { unifiedDiff } from "./lib/diff.mjs";
import {
  PUBLISHED,
  SIDE_LETTER_JURISDICTIONS,
  holeTokens,
  loadSubject,
  templateRelPath,
} from "./lib/subject.mjs";
import { render } from "./lib/mustache.mjs";

/** The view that puts the form back: every token mapped to its own placeholder text. */
export function placeholderView(form, file) {
  const view = {};
  for (const e of holeTokens(form, file).entries) view[e.token] = e.literal;
  return view;
}

function expectedCells() {
  const out = new Set();
  for (const c of PUBLISHED)
    out.add(templateRelPath("safe", c.jurisdiction, c.variant));
  for (const j of SIDE_LETTER_JURISDICTIONS)
    out.add(templateRelPath("side-letter", j, null));
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
        "usage: check-templates.mjs --subject DIR [--encoding ROW]\n",
      );
      return 2;
    }
  }
  const subject = loadSubject(dir, { encoding });
  for (const w of subject.warnings) process.stdout.write(`note     ${w}\n`);

  let failures = 0;
  const seen = new Set();
  for (const [file, form] of Object.entries(subject.forms)) {
    const rel = templateRelPath(form.document, form.jurisdiction, form.variant);
    seen.add(rel);
    const tpl = join(subject.templatesDir, rel);
    if (!existsSync(tpl)) {
      process.stderr.write(
        `MISSING  ${rel} — run etc/safe/make-templates.mjs\n`,
      );
      failures++;
      continue;
    }
    const source = readFileSync(subject.mdPath(file), "utf8");
    const back = render(readFileSync(tpl, "utf8"), placeholderView(form, file));
    if (back === source) {
      process.stdout.write(
        `ok       ${rel.padEnd(28)} ${String(form.holes.length).padStart(2)} holes, ` +
          `${source.length} bytes reproduced\n`,
      );
    } else {
      failures++;
      process.stderr.write(`FAIL     ${rel} does not reproduce ${file}\n`);
      process.stderr.write(
        unifiedDiff(
          source,
          back,
          `source/md/${file}`,
          `render(templates/${rel})`,
        ),
      );
    }
  }

  const expected = expectedCells();
  for (const rel of expected)
    if (!seen.has(rel)) {
      process.stderr.write(
        `MISSING CELL  ${rel} — holes.json maps no form to it\n`,
      );
      failures++;
    }
  for (const rel of seen)
    if (!expected.has(rel)) {
      process.stderr.write(
        `UNPUBLISHED CELL  ${rel} — YC publishes six SAFEs and four side letters; ` +
          `generating a seventh would disseminate a modified form (SPEC.md §3.4)\n`,
      );
      failures++;
    }

  process.stdout.write(
    failures === 0
      ? `\nround-trip proof: ${seen.size}/${expected.size} templates reproduce their source byte for byte\n`
      : `\n${failures} failure(s)\n`,
  );
  return failures === 0 ? 0 : 1;
}

if (import.meta.url === `file://${process.argv[1]}`)
  process.exit(main(process.argv.slice(2)));
