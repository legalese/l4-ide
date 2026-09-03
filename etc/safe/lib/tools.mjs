// The external tools: pandoc for rendering, exiftool for the XMP packet, qpdf for the
// file attachment. All three are optional — a caller that only wants Markdown never
// touches them — so each is probed rather than assumed, and a missing one produces a
// named skip rather than a stack trace.

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
export const XMP_CONFIG = join(HERE, "l4meta-xmp.config");
export const UNDERLINE_FILTER = join(HERE, "underline.lua");

function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { encoding: "utf8", ...opts });
  return {
    status: r.status,
    out: (r.stdout || "") + (r.stderr || ""),
    stdout: r.stdout || "",
  };
}

function must(cmd, args, what) {
  const r = run(cmd, args);
  if (r.status !== 0)
    throw new Error(`etc/safe: ${what} failed (exit ${r.status})\n${r.out}`);
  return r;
}

/** Version strings for the manifest; null when the tool is not on PATH. */
export function toolVersions() {
  const probe = (cmd, args, re) => {
    const r = run(cmd, args);
    if (r.status !== 0) return null;
    const m = r.out.match(re);
    return m ? m[1] : r.out.split("\n")[0].trim();
  };
  return {
    node: process.version,
    pandoc: probe("pandoc", ["--version"], /^pandoc\s+([\d.]+)/m),
    exiftool: probe("exiftool", ["-ver"], /([\d.]+)/),
    qpdf: probe("qpdf", ["--version"], /qpdf version ([\d.]+)/),
  };
}

export function have(tool) {
  return run(tool === "pandoc" ? "pandoc" : tool, ["--version"]).status === 0;
}

/** Markdown -> PDF. `--wrap=none` gfm in, LaTeX out, with the blanks preserved. */
export function mdToPdf(mdPath, pdfPath) {
  must(
    "pandoc",
    [
      "--from=gfm",
      `--lua-filter=${UNDERLINE_FILTER}`,
      "-V",
      "geometry:margin=1in",
      "-V",
      "fontsize=11pt",
      "-o",
      pdfPath,
      mdPath,
    ],
    `pandoc ${basename(mdPath)} -> pdf`,
  );
  return pdfPath;
}

/**
 * Markdown -> docx, using the YC original as the reference document when it is there so
 * the styles are the publisher's. `--reference-doc` copies STYLES, not content.
 * @returns {{path: string, reference: string|null}}
 */
export function mdToDocx(mdPath, docxPath, referenceDocx) {
  const args = ["--from=gfm", "-o", docxPath, mdPath];
  const ref = referenceDocx && existsSync(referenceDocx) ? referenceDocx : null;
  if (ref) args.splice(1, 0, `--reference-doc=${ref}`);
  must("pandoc", args, `pandoc ${basename(mdPath)} -> docx`);
  return { path: docxPath, reference: ref };
}

/**
 * Write the payload into XMP-pdfx:L4, in place.
 * exiftool cannot write to the file it reads, so it writes a sibling and we move it.
 */
export function embedXmp(pdfPath, payload, tmpDir) {
  const jsonPath = join(tmpDir, "payload.json");
  const outPath = join(tmpDir, basename(pdfPath));
  writeFileSync(jsonPath, JSON.stringify(payload, null, 2));
  must(
    "exiftool",
    [
      "-config",
      XMP_CONFIG,
      "-q",
      "-o",
      outPath,
      `-XMP-pdfx:L4<=${jsonPath}`,
      pdfPath,
    ],
    "exiftool -XMP-pdfx:L4",
  );
  writeFileSync(pdfPath, readFileSync(outPath));
  return pdfPath;
}

/** Read XMP-pdfx:L4 back. @returns the parsed payload, or null when the tag is absent. */
export function readXmp(pdfPath) {
  const r = run("exiftool", [
    "-config",
    XMP_CONFIG,
    "-XMP-pdfx:L4",
    "-b",
    pdfPath,
  ]);
  if (r.status !== 0 || !r.stdout.trim()) return null;
  return JSON.parse(r.stdout);
}

/** Attach the instance .l4 as a PDF file stream (SPEC.md §5.4: the second carrier). */
export function attach(pdfPath, filePath, tmpDir) {
  const outPath = join(tmpDir, "attached-" + basename(pdfPath));
  must(
    "qpdf",
    [
      "--add-attachment",
      filePath,
      "--mimetype=text/plain",
      "--",
      pdfPath,
      outPath,
    ],
    `qpdf --add-attachment ${basename(filePath)}`,
  );
  writeFileSync(pdfPath, readFileSync(outPath));
  return pdfPath;
}

export function listAttachments(pdfPath) {
  const r = run("qpdf", ["--list-attachments", pdfPath]);
  if (r.status !== 0) return [];
  return [...r.out.matchAll(/^(\S+)\s+->/gm)].map((m) => m[1]);
}

export function readAttachment(pdfPath, key) {
  const r = spawnSync("qpdf", [`--show-attachment=${key}`, pdfPath], {
    encoding: "buffer",
  });
  if (r.status !== 0)
    throw new Error(
      `etc/safe: qpdf --show-attachment=${key} failed: ${String(r.stderr || "")}`,
    );
  return r.stdout;
}
