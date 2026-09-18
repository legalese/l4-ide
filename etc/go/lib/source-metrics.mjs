#!/usr/bin/env node
// THE DENOMINATOR: how much law went in.
//
// Usage:
//   node etc/go/lib/source-metrics.mjs FILE...            # key=value metric lines
//   node etc/go/lib/source-metrics.mjs --json FILE...     # the full per-file record
//   node etc/go/lib/source-metrics.mjs --json --dir DIR   # every text file under DIR
//
// Exit: 0 measured · 2 usage, or a path that is not on disk
//
// --- what this is for --------------------------------------------------------
//
// Every cost figure the pipeline records is a NUMERATOR — tokens, dollars,
// minutes — and a numerator alone forecasts nothing. "This run cost $40" does
// not say what the next statute will cost; "this run cost $40 over 18,000 words
// of source" does, to the extent the ratio holds. So the size of the input is
// measured with the same discipline as the cost of the run, and the two are
// recorded together.
//
// --- what a "word" is here, precisely ----------------------------------------
//
// A maximal run of non-whitespace characters. That is a REPRODUCIBLE definition
// and deliberately not a linguistic one: it counts `227.100(a)(2)` as one word
// and `—` as one word, and two people running this on the same file will always
// get the same number. A linguistically-motivated count would be a better proxy
// for reading effort and a worse basis for comparison, because every
// implementation of it differs. If the ratio to tokens is what matters — and it
// is — then any stable definition works, because the ratio is MEASURED rather
// than assumed (see estimate-cost.mjs).
//
// `chars` is Unicode code points, not UTF-16 units, so an em-dash counts once
// and `bytes` is the only figure that reflects encoding.
//
// --- and why tokens are not counted here -------------------------------------
//
// Exact token counts come from the Anthropic API's own `count_tokens`, which
// needs the network and a credential. This module is called from phase scripts
// that must run offline and deterministically, so it measures only what can be
// measured from the bytes. estimate-cost.mjs takes an optional measured
// tokens-per-word ratio and says, on every output, whether the ratio it used was
// measured or assumed.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join, relative, resolve } from "node:path";

/** Extensions we will read as text. A PDF's bytes are not its words. */
export const TEXT_EXTENSIONS = new Set([
  ".txt",
  ".md",
  ".markdown",
  ".xml",
  ".html",
  ".htm",
  ".json",
  ".csv",
  ".l4",
  ".akn",
  "",
]);

/**
 * Measure one file. Returns null for anything that is not readable as text —
 * a caller that wants to know about skips reads `skipped` from measureAll.
 */
export function measureFile(path) {
  const abs = resolve(path);
  const st = statSync(abs);
  if (!st.isFile()) return null;
  const buf = readFileSync(abs);
  // A NUL byte in the first 8 KiB is the usual binary sniff, and it is the one
  // that matters here: a PDF or a .docx read as text yields a word count that
  // is not wrong so much as meaningless, and a meaningless denominator produces
  // a confident wrong dollar figure downstream.
  const probe = buf.subarray(0, 8192);
  if (probe.includes(0)) return { path: abs, binary: true, bytes: st.size };
  const text = buf.toString("utf8");
  const words = text.split(/\s+/).filter(Boolean).length;
  return {
    path: abs,
    binary: false,
    bytes: st.size,
    chars: [...text].length,
    lines: text.length ? text.split("\n").length : 0,
    words,
  };
}

/** Every text file under a directory, depth-first, sorted for reproducibility. */
export function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true }).sort((a, b) =>
    a.name < b.name ? -1 : 1,
  )) {
    if (e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (TEXT_EXTENSIONS.has(extname(e.name).toLowerCase())) out.push(p);
  }
  return out;
}

/**
 * Measure a set of paths. Directories are walked; files are taken as given.
 *
 * `skipped` is part of the result and not a silent omission: a source bundle
 * that is nine PDFs and one README would otherwise report the README's word
 * count as the size of the law, which is the failure this whole module exists
 * to make impossible.
 */
export function measureAll(paths, { root = process.cwd() } = {}) {
  const files = [];
  for (const p of paths) {
    const abs = resolve(p);
    const st = statSync(abs);
    if (st.isDirectory()) files.push(...walk(abs));
    else files.push(abs);
  }
  const measured = [];
  const skipped = [];
  for (const f of files.sort()) {
    const m = measureFile(f);
    if (!m) continue;
    const rel = relative(root, m.path);
    if (m.binary) {
      skipped.push({ path: rel, bytes: m.bytes, reason: "binary" });
      continue;
    }
    measured.push({ ...m, path: rel });
  }
  const sum = (k) => measured.reduce((a, m) => a + m[k], 0);
  return {
    files: measured,
    skipped,
    totals: {
      files: measured.length,
      files_skipped: skipped.length,
      bytes: sum("bytes"),
      chars: sum("chars"),
      lines: sum("lines"),
      words: sum("words"),
    },
  };
}

// ---------------------------------------------------------------- CLI --------
if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2);
  const json = argv.includes("--json");
  const paths = argv.filter((a) => !a.startsWith("--"));
  if (!paths.length) {
    process.stderr.write(
      "usage: source-metrics.mjs [--json] FILE|DIR...\n" +
        "  Measures the SIZE OF THE INPUT: bytes, chars, lines, words.\n" +
        "  Binary files are reported as skipped, never counted as text.\n",
    );
    process.exit(2);
  }
  let r;
  try {
    r = measureAll(paths);
  } catch (e) {
    process.stderr.write(`source-metrics.mjs: ${e.message}\n`);
    process.exit(2);
  }
  if (json) {
    process.stdout.write(JSON.stringify(r, null, 2) + "\n");
  } else {
    // The metric transport receipt.mjs accepts: one key=value per line.
    for (const [k, v] of Object.entries(r.totals))
      process.stdout.write(`source_${k}=${v}\n`);
  }
}
