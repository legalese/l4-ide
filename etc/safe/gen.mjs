#!/usr/bin/env node
// gen.mjs — the SAFE generator (SPEC.md §8).
//
//   node etc/safe/gen.mjs fill   --subject DIR --deal deal.json --out DIR [--pdf] [--docx] [--no-embed]
//   node etc/safe/gen.mjs round  --subject DIR --deal deal.json --out DIR
//   node etc/safe/gen.mjs verify FILE.pdf [--subject DIR]
//
// Deal parameters in, one executable SAFE per investor out: a Markdown document that is
// the publisher's form with its blanks filled and nothing else changed, an instance .l4
// module that is the same transaction as a program, and — with --pdf — a PDF carrying
// both, the module hashed into its XMP packet and attached as a file stream.
//
// The order in SPEC.md §5.2 is load-bearing and is the order below: VALIDATE through the
// encoding first (a deal the form cannot take must not produce a document at all), then
// instantiate, fill, render, and only then embed. Embedding happens BEFORE any signature
// is applied, because the L4 has to be inside the signed envelope; this tool does not
// sign.

import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import {
  check,
  discoverL4,
  l4Version,
  runBatch,
  runBatchRow,
} from "./lib/l4.mjs";
import { buildView, holeValues, instanceModule, slug } from "./lib/fill.mjs";
import { conversionSchedule, liquiditySchedule } from "./lib/schedule.mjs";
import {
  formEdition,
  loadSubject,
  moduleHashes,
  sha256,
  sha256File,
} from "./lib/subject.mjs";
import { render } from "./lib/mustache.mjs";
import {
  attach,
  embedXmp,
  have,
  listAttachments,
  mdToDocx,
  mdToPdf,
  readAttachment,
  readXmp,
  toolVersions,
} from "./lib/tools.mjs";

const USAGE = `usage:
  gen.mjs fill   --subject DIR --deal deal.json --out DIR [--pdf] [--docx] [--no-embed] [--encoding ROW]
  gen.mjs round  --subject DIR --deal deal.json --out DIR [--encoding ROW]
  gen.mjs liquidity --subject DIR --deal deal.json --out DIR --proceeds N
                    [--indebtedness N] [--promised-options N] [--encoding ROW]
  gen.mjs verify FILE.pdf [--subject DIR] [--encoding ROW]
`;

function parseArgs(argv) {
  const a = { _: [], flags: {} };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === "--pdf" || t === "--docx" || t === "--no-embed")
      a.flags[t.slice(2)] = true;
    else if (t.startsWith("--")) a.flags[t.slice(2)] = argv[++i];
    else a._.push(t);
  }
  return a;
}

/** The l4-ide commit this generator ran from, for the XMP payload's provenance. */
function repoCommit() {
  const r = spawnSync(
    "git",
    ["-C", new URL(".", import.meta.url).pathname, "rev-parse", "HEAD"],
    {
      encoding: "utf8",
    },
  );
  return r.status === 0 ? r.stdout.trim() : "unknown";
}

/** The licence sentence and version stamp, which pandoc drops and CC BY-ND requires. */
/** The local calendar date. `at` is UTC, and a document must not be dated yesterday. */
function localDate(d = new Date()) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function footerBlock(subject, file, at) {
  const f = subject.footers[file];
  if (!f || !f.licence)
    throw new Error(
      `etc/safe: source/footers.json carries no licence line for ${file}. That line is a ` +
        `CONDITION of the CC BY-ND 4.0 grant (SPEC.md §2, ruling R9) and a filled form ` +
        `must reproduce it; refusing to generate a document without it.`,
    );
  const stamp = (f.version ?? []).filter(Boolean).join(" · ");
  return [
    "",
    "------------------------------------------------------------------------",
    "",
    ...(stamp ? [`*${stamp}*`, ""] : []),
    f.licence,
    "",
    `*Filled from the Y Combinator form \`${file.replace(/\.md$/, ".docx")}\` by ` +
      `\`etc/safe/gen.mjs\` on ${localDate()} over encoding row \`${subject.rowName}\`. ` +
      `Blanks and bracketed terms have been filled; nothing else in the form has been changed.*`,
    "",
  ].join("\n");
}

/**
 * The normaliser's repairs, condensed. They are worth saying once — each one is a place
 * where the measured hole map and the document disagree — and not worth six lines.
 */
function reportWarnings(subject) {
  if (subject.warnings.length === 0) return;
  if (process.env.SAFE_EXPLAIN || process.argv.includes("--explain")) {
    for (const w of subject.warnings) process.stdout.write(`note      ${w}\n`);
    return;
  }
  process.stdout.write(
    `note      ${subject.warnings.length} literal(s) in holes.json extended to swallow a ` +
      `trailing \`**\` (a bold run that opens inside the bracket and closes outside it); ` +
      `run with --explain for the list\n`,
  );
}

function writeOut(outputs, path, text) {
  writeFileSync(path, text);
  outputs.push({
    path: basename(path),
    bytes: statSync(path).size,
    sha256: sha256File(path),
  });
  return path;
}

// ---------------------------------------------------------------------------
// fill
// ---------------------------------------------------------------------------

function cmdFill(args) {
  const subject = loadSubject(args.flags.subject, {
    encoding: args.flags.encoding,
  });
  const dealPath = resolve(args.flags.deal);
  const deal = JSON.parse(readFileSync(dealPath, "utf8"));
  const out = resolve(args.flags.out);
  mkdirSync(out, { recursive: true });
  const at = new Date().toISOString();
  const today = localDate();
  const l4 = discoverL4();

  reportWarnings(subject);

  // 1. VALIDATE. A deal that cannot be filled onto the form it names produces no
  //    document at all — not a document with a note attached.
  const validate = subject.encoding.entrypoints?.validate;
  const reasons = runBatch(
    subject.modulePath(validate?.module ?? "safe-form.l4"),
    validate?.function ?? "validate deal",
    deal,
    {
      l4: l4.path,
      libraryPath: subject.row,
      recordFields: subject.recordFields,
    },
  );
  if (reasons.length > 0) {
    process.stderr.write(
      `\nthis deal cannot be filled onto the form it names:\n`,
    );
    for (const r of reasons) process.stderr.write(`  - ${r}\n`);
    return 2;
  }
  process.stdout.write(
    `validate  ${basename(dealPath)}: fillable (no reasons)\n`,
  );

  // 1b. EDITION. The edition is the form's own header stamp, never deal.json's opinion of
  //     it: the US MFN form is "Version 1.3" while the cap and discount forms are 1.2, so
  //     a deal that says "1.2" for every US form is wrong about one of them (SPEC.md §2).
  //     A deal that names a different edition is refused rather than quietly overridden —
  //     it is a statement about which paper the parties think they are signing.
  const safeFile = subject.fileFor(
    "safe",
    deal.form.jurisdiction,
    deal.form.variant,
  );
  const stamped = formEdition(subject, safeFile);
  if (!stamped.edition)
    throw new Error(
      `etc/safe: ${safeFile} carries no version stamp in source/footers.json, so the ` +
        `edition cannot be read off the form. Re-extract the .docx headers.`,
    );
  if (deal.form.edition && deal.form.edition !== stamped.edition) {
    process.stderr.write(
      `\nthis deal cannot be filled onto the form it names:\n` +
        `  - deal.form.edition is "${deal.form.edition}", but ${safeFile} is stamped ` +
        `"${stamped.stamp}" — edition ${stamped.edition}. The stamp is the form; ` +
        `fix deal.json or select a different form.\n`,
    );
    return 2;
  }
  process.stdout.write(
    `edition   ${stamped.edition} from the form's own stamp (${stamped.stamp})\n`,
  );

  const outputs = [];
  const editionsUsed = {};
  const modules = moduleHashes(subject);
  const commit = repoCommit();
  const l4v = l4Version(l4.path);
  const wantPdf = !!args.flags.pdf;
  const wantDocx = !!args.flags.docx;
  const embed = !args.flags["no-embed"];
  if (wantPdf && !have("pandoc"))
    throw new Error("etc/safe: --pdf needs pandoc on PATH");
  if (wantDocx && !have("pandoc"))
    throw new Error("etc/safe: --docx needs pandoc on PATH");

  // The instance module is the same for every Safe in the round (it binds them all), but
  // each document gets its own copy so a PDF is self-contained; the header names which
  // Safe it accompanies.
  for (const safe of deal.safes) {
    const id = slug(safe.investor.name);
    const docs = [{ document: "safe", suffix: "" }];
    if (safe.proRataSideLetter)
      docs.push({ document: "side-letter", suffix: "-pro-rata" });

    const instText = instanceModule(deal, {
      generatedAt: at,
      row: subject.rowName,
      forSafe: safe.investor.name,
    });
    const instPath = writeOut(outputs, join(out, `${id}.l4`), instText);
    const checked = check(instPath, { l4: l4.path, libraryPath: subject.row });
    if (!checked.ok)
      throw new Error(
        `etc/safe: the instance module ${basename(instPath)} does not typecheck.\n` +
          `That is a generator bug, not a deal problem — the document is not written.\n${checked.output}`,
      );
    process.stdout.write(`l4 check  ${id}.l4: ok\n`);

    for (const { document, suffix } of docs) {
      const file = subject.fileFor(
        document,
        deal.form.jurisdiction,
        deal.form.variant,
      );
      const form = subject.forms[file];
      const tplPath = subject.templatePath(
        document,
        deal.form.jurisdiction,
        deal.form.variant,
      );
      if (!existsSync(tplPath))
        throw new Error(
          `etc/safe: ${tplPath} is missing — run etc/safe/make-templates.mjs --subject ${subject.dir}`,
        );
      editionsUsed[file] = formEdition(subject, file);
      const template = readFileSync(tplPath, "utf8");
      const values = holeValues(deal, safe, { document });
      const { view, unresolved, blank } = buildView(
        template,
        form,
        file,
        values,
      );
      if (unresolved.length > 0)
        throw new Error(
          `etc/safe: ${file} has holes this generator has no value for: ${unresolved.join(", ")}.\n` +
            `Either deal.json is missing a field or holes.json has grown a hole name ` +
            `lib/fill.mjs does not know. Refusing to write a document with an unfilled bracket.`,
        );
      const md = render(template, view) + footerBlock(subject, file, at);
      const mdPath = writeOut(outputs, join(out, `${id}${suffix}.md`), md);
      process.stdout.write(
        `fill      ${basename(mdPath)}: ${Object.keys(view).length} holes` +
          `${blank.length ? `, ${blank.length} left blank for signature (${[...new Set(blank)].join(", ")})` : ""}\n`,
      );

      if (wantDocx) {
        const src = join(
          subject.dir,
          "source",
          "docx",
          file.replace(/\.md$/, ".docx"),
        );
        const r = mdToDocx(mdPath, join(out, `${id}${suffix}.docx`), src);
        outputs.push({
          path: basename(r.path),
          bytes: statSync(r.path).size,
          sha256: sha256File(r.path),
        });
        process.stdout.write(
          `docx      ${basename(r.path)}: ${r.reference ? `styles from ${basename(r.reference)}` : "plain (no source .docx found; pandoc defaults used)"}\n`,
        );
      }

      if (wantPdf) {
        const pdfPath = join(out, `${id}${suffix}.pdf`);
        mdToPdf(mdPath, pdfPath);
        if (embed) {
          const docx = join(
            subject.dir,
            "source",
            "docx",
            file.replace(/\.md$/, ".docx"),
          );
          if (!existsSync(docx))
            throw new Error(
              `etc/safe: the XMP payload records source_form_sha256, the hash of the YC ` +
                `.docx this document reproduces, and ${docx} is not there. Deposit ` +
                `source/docx/ or pass --no-embed.`,
            );
          const payload = {
            l4meta: "1.0",
            instrument: "yc-safe-postmoney",
            form: {
              edition: formEdition(subject, file).edition,
              jurisdiction: deal.form.jurisdiction,
              variant: deal.form.variant,
            },
            source_form_sha256: sha256File(docx),
            template_sha256: sha256File(tplPath),
            parameters: view,
            encoding: { row: subject.rowName, modules },
            instance: {
              path: basename(instPath),
              sha256: sha256(instText),
              text: instText,
            },
            generator: { tool: "etc/safe/gen.mjs", l4: l4v, commit, at },
          };
          const tmp = mkdtempSync(join(tmpdir(), "safe-embed-"));
          try {
            embedXmp(pdfPath, payload, tmp);
            attach(pdfPath, instPath, tmp);
          } finally {
            rmSync(tmp, { recursive: true, force: true });
          }
        }
        outputs.push({
          path: basename(pdfPath),
          bytes: statSync(pdfPath).size,
          sha256: sha256File(pdfPath),
        });
        process.stdout.write(
          `pdf       ${basename(pdfPath)}: ${statSync(pdfPath).size} bytes` +
            `${embed ? ", XMP-pdfx:L4 written and instance attached" : ", not embedded (--no-embed)"}\n`,
        );
      }
    }
  }

  const manifest = {
    generated: at,
    subject: subject.dir,
    // The edition is evidence, so the manifest carries the stamp it was read from as
    // well as the number, per form the run touched.
    editions: editionsUsed,
    encoding: { row: subject.rowName, modules },
    deal: { path: dealPath, sha256: sha256File(dealPath) },
    tools: {
      ...toolVersions(),
      l4: l4v,
      l4Path: l4.path,
      l4Provenance: l4.provenance,
    },
    generator: { tool: "etc/safe/gen.mjs", commit },
    outputs,
  };
  writeFileSync(
    join(out, "manifest.json"),
    JSON.stringify(manifest, null, 2) + "\n",
  );
  process.stdout.write(
    `\n${outputs.length} file(s) + manifest.json in ${out}\n`,
  );
  return 0;
}

// ---------------------------------------------------------------------------
// round
// ---------------------------------------------------------------------------

function cmdRound(args) {
  const subject = loadSubject(args.flags.subject, {
    encoding: args.flags.encoding,
  });
  const deal = JSON.parse(readFileSync(resolve(args.flags.deal), "utf8"));
  const out = resolve(args.flags.out);
  mkdirSync(out, { recursive: true });
  const l4 = discoverL4();
  const at = new Date().toISOString();

  const convert = subject.encoding.entrypoints?.convert;
  const conversion = runBatch(
    subject.modulePath(convert?.module ?? "safe-portfolio.l4"),
    convert?.function ?? "convert",
    deal,
    {
      l4: l4.path,
      libraryPath: subject.row,
      recordFields: subject.recordFields,
    },
  );
  writeFileSync(
    join(out, "conversion.json"),
    JSON.stringify(conversion, null, 2) + "\n",
  );
  const md = conversionSchedule(deal, conversion, {
    at: localDate(),
    row: subject.rowName,
  });
  writeFileSync(join(out, "conversion-schedule.md"), md);
  process.stdout.write(
    `convert   Company Capitalization ${Math.floor(conversion.companyCapitalization)}` +
      `, ${conversion.rows.length} Safe(s)` +
      `${conversion.standardPrice > 0 ? `, Standard Preferred ${conversion.standardPrice.toFixed(4)}` : ""}\n` +
      `wrote     ${join(out, "conversion-schedule.md")}\n` +
      `wrote     ${join(out, "conversion.json")}\n`,
  );
  return 0;
}

// ---------------------------------------------------------------------------
// liquidity
// ---------------------------------------------------------------------------

function cmdLiquidity(args) {
  const subject = loadSubject(args.flags.subject, {
    encoding: args.flags.encoding,
  });
  const deal = JSON.parse(readFileSync(resolve(args.flags.deal), "utf8"));
  const out = resolve(args.flags.out);
  mkdirSync(out, { recursive: true });
  const l4 = discoverL4();

  if (args.flags.proceeds === undefined)
    throw new Error(
      "etc/safe: liquidity needs --proceeds N, the Proceeds legally available for " +
        "distribution at the Liquidity Event.",
    );
  // The two figures beyond the cap table that the form leaves to the deal. The User Guide
  // zeroes the Promised Options "because treatment of promised options is deal-specific"
  // (p. 21 n. 3), so zero is the default here and is stated in the schedule, not assumed.
  const event = {
    proceeds: Number(args.flags.proceeds),
    indebtedness: Number(args.flags.indebtedness ?? 0),
    promisedOptionsReceivingProceeds: Number(
      args.flags["promised-options"] ?? 0,
    ),
  };
  for (const [k, v] of Object.entries(event))
    if (!Number.isFinite(v))
      throw new Error(`etc/safe: liquidity: ${k} is not a number`);

  const ep = subject.encoding.entrypoints?.liquidity;
  if (!ep)
    throw new Error(
      `etc/safe: encoding row ${subject.rowName} has no \`liquidity\` entrypoint. ` +
        `This subcommand needs the §1(b) leg of the encoding.`,
    );
  const [dealParam = "deal", eventParam = "event"] = ep.params ?? [];
  const result = runBatchRow(
    subject.modulePath(ep.module),
    ep.function ?? "liquidity",
    { [dealParam]: deal, [eventParam]: event },
    {
      l4: l4.path,
      libraryPath: subject.row,
      recordFields: subject.recordFields,
    },
  );

  writeFileSync(
    join(out, "liquidity.json"),
    JSON.stringify({ event, result }, null, 2) + "\n",
  );
  writeFileSync(
    join(out, "liquidity-schedule.md"),
    liquiditySchedule(deal, event, result, {
      at: localDate(),
      row: subject.rowName,
    }),
  );
  process.stdout.write(
    `liquidity Liquidity Capitalization ${Math.floor(result.liquidityCapitalization)}` +
      `, ${result.rows.length} Safe(s), ` +
      `${result.rows.filter((r) => r.method === "convert").length} converting\n` +
      `wrote     ${join(out, "liquidity-schedule.md")}\n` +
      `wrote     ${join(out, "liquidity.json")}\n`,
  );
  return 0;
}

// ---------------------------------------------------------------------------
// verify
// ---------------------------------------------------------------------------

function cmdVerify(args) {
  const pdf = resolve(args._[0]);
  if (!existsSync(pdf)) throw new Error(`etc/safe: no such file: ${pdf}`);
  let bad = 0;
  const say = (ok, line) => {
    process.stdout.write(`${ok ? "ok    " : "FAIL  "} ${line}\n`);
    if (!ok) bad++;
  };

  const payload = readXmp(pdf);
  if (!payload) {
    process.stderr.write(
      `FAIL   ${basename(pdf)} carries no XMP-pdfx:L4 tag\n`,
    );
    return 1;
  }
  say(
    payload.l4meta === "1.0",
    `XMP-pdfx:L4 present, payload schema ${payload.l4meta}`,
  );
  say(
    payload.instrument === "yc-safe-postmoney",
    `instrument ${payload.instrument}, form ${payload.form?.jurisdiction}/${payload.form?.variant} edition ${payload.form?.edition}`,
  );

  const want = payload.instance?.path;
  const attachments = listAttachments(pdf);
  if (!attachments.includes(want)) {
    say(
      false,
      `attachment ${want} is not in the PDF (found: ${attachments.join(", ") || "none"})`,
    );
    return 1;
  }
  const bytes = readAttachment(pdf, want);
  const got = sha256(bytes);
  say(
    got === payload.instance.sha256,
    `attachment ${want}: sha256 ${got}${got === payload.instance.sha256 ? " matches the payload" : ` != payload ${payload.instance.sha256}`}`,
  );
  if (payload.instance.text !== undefined)
    say(
      bytes.toString("utf8") === payload.instance.text,
      "the attached module is byte-identical to the copy inlined in the XMP packet",
    );

  const tmp = mkdtempSync(join(tmpdir(), "safe-verify-"));
  try {
    const path = join(tmp, want);
    writeFileSync(path, bytes);
    let libraryPath = null;
    if (args.flags.subject) {
      const subject = loadSubject(args.flags.subject, {
        encoding: args.flags.encoding,
      });
      libraryPath = subject.row;
      const modules = moduleHashes(subject);
      for (const [m, h] of Object.entries(payload.encoding?.modules ?? {}))
        say(
          modules[m] === h,
          `encoding module ${m} ${modules[m] === h ? "matches" : `DIFFERS: subject has ${modules[m]}`}`,
        );
    }
    const r = check(path, { l4: discoverL4().path, libraryPath });
    if (!libraryPath && !r.ok)
      process.stdout.write(
        `skip   l4 check: the instance IMPORTs the encoding row, which needs ` +
          `--subject DIR to resolve. Hashes above still stand.\n`,
      );
    else say(r.ok, `l4 check ${want}${r.ok ? "" : `\n${r.output}`}`);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }

  process.stdout.write(
    bad === 0
      ? `\nVERDICT: ${basename(pdf)} carries its own L4 and every hash agrees.\n`
      : `\nVERDICT: ${bad} check(s) failed on ${basename(pdf)}.\n`,
  );
  return bad === 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------

function main(argv) {
  const args = parseArgs(argv);
  const cmd = args._.shift();
  try {
    if (cmd === "fill") return cmdFill(args);
    if (cmd === "round") return cmdRound(args);
    if (cmd === "liquidity") return cmdLiquidity(args);
    if (cmd === "verify") return cmdVerify(args);
    process.stderr.write(USAGE);
    return 2;
  } catch (e) {
    process.stderr.write(`${e.message}\n`);
    return 1;
  }
}

if (import.meta.url === `file://${process.argv[1]}`)
  process.exit(main(process.argv.slice(2)));
