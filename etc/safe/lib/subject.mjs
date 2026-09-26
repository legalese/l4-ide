// The canon subject directory, as the generator sees it.
//
// SPEC.md §4 fixes the layout; nothing here assumes WHERE the canon checkout lives,
// because `--subject DIR` is always a path argument:
//
//   <subject>/source/md/<form>.md            verbatim `pandoc --to gfm --wrap=none`
//   <subject>/source/docx/<form>.docx        the YC originals (optional; --docx uses them)
//   <subject>/source/footers.json            the running header/footer pandoc drops
//   <subject>/templates/holes.json           the positional bracket -> hole map
//   <subject>/templates/<juris>/<variant>.md.mustache
//   <subject>/templates/side-letter/<juris>.md.mustache
//   <subject>/encodings/<row>/encoding.json  entrypoints + batch.record_fields

import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * The product matrix, from SPEC.md §3.4 and `safe-form.l4`'s `form is published`:
 * {US} x {cap, discount, MFN} together with {SG, CA, KY} x {cap}. The five cells off
 * that diagonal are not published, and synthesising one would be exactly the "modified
 * version" the CC BY-ND footer asks people not to disseminate — so the generator
 * refuses them rather than inventing them.
 */
export const PUBLISHED = [
  { jurisdiction: "us", variant: "cap" },
  { jurisdiction: "us", variant: "discount" },
  { jurisdiction: "us", variant: "mfn" },
  { jurisdiction: "sg", variant: "cap" },
  { jurisdiction: "ca", variant: "cap" },
  { jurisdiction: "ky", variant: "cap" },
];

/** A side letter exists for each jurisdiction, and carries no economic variant. */
export const SIDE_LETTER_JURISDICTIONS = ["us", "sg", "ca", "ky"];

export function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

export function sha256File(path) {
  return sha256(readFileSync(path));
}

function readJson(path, what) {
  if (!existsSync(path))
    throw new Error(`etc/safe: ${what} is missing — expected it at ${path}`);
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    throw new Error(
      `etc/safe: ${what} at ${path} is not valid JSON: ${e.message}`,
    );
  }
}

/** Where a filled document's template lives, relative to <subject>/templates. */
export function templateRelPath(document, jurisdiction, variant) {
  return document === "side-letter"
    ? join("side-letter", `${jurisdiction}.md.mustache`)
    : join(jurisdiction, `${variant}.md.mustache`);
}

/**
 * The template TOKEN for each hole entry.
 *
 * One hole name can appear in a form with more than one printed shape — the US
 * valuation-cap form writes the company as `[Company Name]` in the body and as
 * `[**COMPANY**]` in the signature block. The deal supplies ONE company name, but the
 * two places print it differently and, more to the point, the round-trip proof (§5.3)
 * has to put a DIFFERENT placeholder back in each. So the token is the hole name for the
 * first distinct literal and `<hole>2`, `<hole>3`, … for each further one, in document
 * order. Both make-templates.mjs and check-templates.mjs derive it here, from the same
 * holes.json, so they cannot disagree.
 */
/**
 * holes.json arrives in one of two shapes, and both are read here.
 *
 *   canon's:  {forms: {"<md>": {document, jurisdiction, variant,
 *                               brackets: [{literal, hole, placeholder_case, …}],
 *                               blanks:   [{literal, hole, label, …}]}}}
 *   internal: {forms: {"<md>": {…, holes: [{literal, hole, case?, wrap?}]}}}
 *
 * Merging `brackets` and `blanks` by concatenation is safe even though it is not
 * document order: the positional map only needs the entries for ONE literal to stay in
 * order relative to each other, and no bracket literal is ever also a blank literal.
 *
 * One repair happens here, and it is reported rather than done silently. pandoc renders
 * the signature block's bold "[COMPANY]" as `\[**COMPANY\]**` — the bracket opens
 * OUTSIDE the emphasis and closes INSIDE it — so canon's measured literal stops at
 * `\]` and leaves a `**` behind. Substituting into that template yields `ABC, INC.**`
 * with a dangling emphasis marker. When every occurrence of such a literal is followed
 * by `**`, the literal is extended to swallow it and the hole is marked `wrap: "**"`, so
 * the filled value comes out bold and the round-trip still puts the exact original text
 * back. `warnings` names each one for the report.
 */
export function normaliseHoles(raw, readSource) {
  const forms = {};
  const warnings = [];
  for (const [file, f] of Object.entries(raw.forms ?? {})) {
    // The bracket list has been called both `brackets` and `holes`. Take whichever is
    // there, and merge `blanks` in either case. The only shape that skips normalisation
    // is a `holes` array carrying neither `placeholder_case` nor a sibling `blanks` list
    // — i.e. one already in this module's internal form.
    const bracketList = f.brackets ?? (Array.isArray(f.holes) ? f.holes : []);
    const measured =
      f.brackets !== undefined ||
      f.blanks !== undefined ||
      bracketList.some((e) => e && e.placeholder_case !== undefined);
    if (!measured) {
      forms[file] = { ...f, holes: f.holes ?? [] };
      continue;
    }
    const text = readSource(file);
    const entries = [...bracketList, ...(f.blanks ?? [])]
      .filter((e) => e.hole)
      .map((e) => ({
        literal: e.literal,
        hole: e.hole,
        // Only `upper` is applied. A placeholder that happens to be lower case (the
        // Canadian cover reads `[company name]`) is the drafter's typography, not an
        // instruction to lower-case a legal name, so `lower`, `title`, `italic` and
        // `blank` all pass the value through unchanged.
        case: e.placeholder_case === "upper" ? "upper" : undefined,
        // A `<u>   </u>` blank IS the form's fill-in rule: the value belongs inside the
        // underline, not after it, or the filled line reads "Address:548 Market Street"
        // with the rule gone. The whole tag is replaced, so the value carries the tags.
        wrap: /^<u>\s*<\/u>$/.test(e.literal) ? ["<u>", "</u>"] : undefined,
      }));
    const extended = new Map();
    for (const e of entries) {
      if (!e.literal.startsWith("\\[**") || extended.has(e.literal)) continue;
      let all = true;
      let n = 0;
      for (
        let i = text.indexOf(e.literal);
        i >= 0;
        i = text.indexOf(e.literal, i + e.literal.length)
      ) {
        n++;
        if (text.slice(i + e.literal.length, i + e.literal.length + 2) !== "**")
          all = false;
      }
      if (n > 0 && all) {
        extended.set(e.literal, e.literal + "**");
        warnings.push(
          `${file}: extended ${JSON.stringify(e.literal)} to ${JSON.stringify(e.literal + "**")} ` +
            `for hole \`${e.hole}\` — the bold run opened inside the bracket and closed outside it, ` +
            `so the measured literal would have left a dangling \`**\` in the filled document`,
        );
      }
    }
    for (const e of entries) {
      if (extended.has(e.literal)) {
        e.literal = extended.get(e.literal);
        e.wrap = "**";
      } else if (e.literal.startsWith("\\[**") && e.literal.endsWith("]**")) {
        // The map already carries the extended literal (canon's holes.json does, flagged
        // `bold: true`), so there is nothing to repair — but the value is still bold.
        e.wrap = "**";
      }
    }
    forms[file] = {
      document: f.document,
      jurisdiction: f.jurisdiction,
      variant: f.variant,
      holes: entries,
    };
  }
  return { forms, warnings };
}

/**
 * footers.json likewise arrives in one of two shapes:
 *   canon's:  {files: {"<docx>": {version_stamp, banner, copyright_and_license_line}}}
 *   internal: {forms: {"<md>":   {version: [...], licence}}}
 * Both normalise to md-basename -> {version: [...], licence}. The licence sentence and
 * the version stamp live ONLY in the .docx header/footer — pandoc drops both — and
 * reproducing the licence line is a condition of the CC BY-ND grant (SPEC.md §2), so a
 * form whose licence line is missing here is an error at fill time, not a warning.
 */
export function normaliseFooters(raw) {
  const out = {};
  if (raw.files) {
    for (const [docx, v] of Object.entries(raw.files)) {
      const md = docx.replace(/\.docx$/, ".md");
      const version = [v.version_stamp, v.banner]
        .filter(Boolean)
        .map((s) => s.trim());
      out[md] = { version, licence: v.copyright_and_license_line ?? null };
    }
    return out;
  }
  for (const [md, v] of Object.entries(raw.forms ?? {}))
    out[md] = { version: v.version ?? [], licence: v.licence ?? null };
  return out;
}

export function holeTokens(form, file = "<form>") {
  const seen = new Map(); // hole -> [literal, ...] in document order
  const shape = new Map(); // hole + "\u0000" + literal -> {case, wrap}
  const entries = [];
  for (const h of form.holes) {
    const list = seen.get(h.hole) ?? [];
    if (!list.includes(h.literal)) list.push(h.literal);
    seen.set(h.hole, list);
    const key = h.hole + "\u0000" + h.literal;
    const prev = shape.get(key);
    if (prev && (prev.case !== h.case || prev.wrap !== h.wrap))
      throw new Error(
        `etc/safe: ${file} — holes.json gives ${JSON.stringify(h.literal)} two different ` +
          `presentations for hole \`${h.hole}\`. One literal, one presentation.`,
      );
    shape.set(key, { case: h.case, wrap: h.wrap });
  }
  for (const h of form.holes) {
    const n = seen.get(h.hole).indexOf(h.literal) + 1;
    const token = n === 1 ? h.hole : `${h.hole}${n}`;
    entries.push({ ...h, token });
  }
  const byToken = new Map();
  for (const e of entries) byToken.set(e.token, e);
  return { entries, byToken };
}

export function loadSubject(dir, { encoding } = {}) {
  if (!dir) throw new Error("etc/safe: --subject DIR is required");
  if (!existsSync(dir))
    throw new Error(`etc/safe: no such subject directory: ${dir}`);
  const sourceMd = join(dir, "source", "md");
  const templates = join(dir, "templates");
  const holesPath = join(templates, "holes.json");
  const footersPath = join(dir, "source", "footers.json");

  // Pick the encoding row: the named one, else the only one there is. Refusing a
  // subject with two rows and no --encoding is better than silently picking a winner.
  const encodingsDir = join(dir, "encodings");
  let rowName = encoding;
  if (!rowName) {
    const rows = existsSync(encodingsDir)
      ? readdirSync(encodingsDir, { withFileTypes: true })
          .filter((e) => e.isDirectory() || e.isSymbolicLink())
          .map((e) => e.name)
      : [];
    if (rows.length === 0)
      throw new Error(`etc/safe: no encoding row under ${encodingsDir}`);
    if (rows.length > 1)
      throw new Error(
        `etc/safe: ${rows.length} encoding rows under ${encodingsDir} (${rows.join(", ")}) — name one with --encoding`,
      );
    rowName = rows[0];
  }
  const row = join(encodingsDir, rowName);
  const encodingJson = readJson(join(row, "encoding.json"), "encoding.json");

  const rawHoles = readJson(holesPath, "templates/holes.json");
  if (!rawHoles.forms)
    throw new Error(
      `etc/safe: ${holesPath} has no \`forms\` object. Expected ` +
        `{forms: {"<md file>": {document, jurisdiction, variant, ` +
        `holes | brackets+blanks}}}.`,
    );
  const { forms, warnings } = normaliseHoles(rawHoles, (file) =>
    readFileSync(join(sourceMd, file), "utf8"),
  );
  const footers = existsSync(footersPath)
    ? normaliseFooters(readJson(footersPath, "source/footers.json"))
    : {};

  const byCell = new Map();
  for (const [file, f] of Object.entries(forms)) {
    // A side letter has no economic variant: one letter serves all three US Safes.
    const key = `${f.document}/${f.jurisdiction}/${f.document === "side-letter" ? "-" : (f.variant ?? "-")}`;
    if (byCell.has(key))
      throw new Error(
        `etc/safe: holes.json maps two files to the same cell ${key}: ` +
          `${byCell.get(key)} and ${file}`,
      );
    byCell.set(key, file);
  }

  return {
    dir,
    row,
    rowName,
    encoding: encodingJson,
    recordFields: encodingJson.batch?.record_fields ?? {},
    sourceMd,
    templatesDir: templates,
    holesPath,
    forms,
    footers,
    warnings,

    /** @returns the md basename for a cell, or throws naming the published matrix. */
    fileFor(document, jurisdiction, variant) {
      const key = `${document}/${jurisdiction}/${document === "side-letter" ? "-" : variant}`;
      const file = byCell.get(key);
      if (!file)
        throw new Error(
          `etc/safe: no published YC form for ${key}. The matrix is ` +
            PUBLISHED.map((c) => `${c.jurisdiction}/${c.variant}`).join(", ") +
            ` plus a side letter for ${SIDE_LETTER_JURISDICTIONS.join(", ")}.`,
        );
      return file;
    },
    mdPath(file) {
      return join(sourceMd, file);
    },
    templatePath(document, jurisdiction, variant) {
      return join(templates, templateRelPath(document, jurisdiction, variant));
    },
    modulePath(name) {
      return join(row, name);
    },
  };
}

/**
 * The edition of one form, read off the form's OWN header stamp.
 *
 * Not from deal.json: the deposit measured the stamps and the US MFN form is "Version
 * 1.3" while the cap and discount forms are 1.2, so a deal that says "1.2" for every US
 * form is wrong about one of them (SPEC.md §2). The stamp is the only thing that knows,
 * and it is the only thing this generator believes. `edition` is null when the form
 * carries no stamp at all — the Singapore, Canada and Cayman side letters do not.
 *
 * @returns {{edition: string|null, stamp: string|null}}
 */
export function formEdition(subject, file) {
  const f = subject.footers[file];
  const stamp = (f?.version ?? []).filter(Boolean).join(" \u00b7 ") || null;
  const m = stamp?.match(/Version\s+(\d+(?:\.\d+)*)/);
  return { edition: m ? m[1] : null, stamp };
}

/** Every .l4 the encoding row declares, with its sha256 — for the XMP payload (§5.4). */
export function moduleHashes(subject) {
  const out = {};
  for (const m of subject.encoding.modules ?? [])
    out[m] = "sha256:" + sha256File(subject.modulePath(m));
  return out;
}
